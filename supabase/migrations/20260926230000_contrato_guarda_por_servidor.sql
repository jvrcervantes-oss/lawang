-- destructivo-ok: el unico cambio sobre algo existente es reemplazar dos funciones (el trigger del contrato padre y contrato_firmas_anula) con la misma firma; no toca datos.
-- Frontera frontend/backend — contratos, pieza 5, paso A (26-sep-2026, LAW-336; plan corregido por la
-- revisión previa #120, decisión del owner sobre el precio y hallazgos de las consultas de deploy de C+D).
-- SOLO AÑADE; el revoke de la escritura directa va en la migración siguiente (paso F).
--
-- A) contrato_guarda: la pantalla mandaba `insert/update contratos` con el payload entero, incluidos
--    los campos que salen de `datos` y que calculaba ella: precio_total, comprador_nombre,
--    proyecto_nombre, moneda, fecha_firma y el contrato padre. Ahora los deriva el servidor de
--    `datos.fields` con la misma regla que la pantalla (compradoresDeContrato + nombresFactura de
--    contracts/assets/compradores.js; lw_parse_importe, que es el port de lwParseImporte con paridad
--    probada en facturas). Lo que la pantalla ya no puede escribir por aquí: bloqueado, pdf_firmado_*,
--    liberado_*, numero, creado_por, poder_id.
--    PRECIO (decisión del owner, 26-sep): se recalcula SOLO en contratos no firmados (sin bloquear y sin
--    ninguna firma dada). Un firmado conserva el suyo — hoy el único que diverge es CC00020 (45.975
--    guardado, 76.500 en el texto), firmado, y se queda como está.
--    Permiso = las policies de hoy, comprobadas dentro: antes de escribir con la fila vieja (USING) y
--    después con la nueva (WITH CHECK), porque proyecto_id lo fijan los triggers.
-- · _trg_contrato_padre_con_comisiones miraba current_user: dentro de una función DEFINER es `postgres`
--   y el freno se apagaba (Desarrollo #120, ALTA). Ahora mira si hay sesión de usuario.
-- · contrato_desbloquea: el «Desbloquear» del super admin (LAW-71) también por el servidor.
-- · firma-submit: `estampado_en` lo pone SOLO firma-submit antes de guardar el documento con la firma;
--   el atajo de reintento se apoya en esa columna y no en buscar el id dentro del HTML, que un agente
--   podía meter a mano (Seguridad, consulta C+D).
-- · Anular una firma ya dada exige que el firmante tenga email, para que el aviso sea posible (Legal).

alter table public.contrato_firmas add column if not exists estampado_en timestamptz;

create or replace function public._trg_contrato_padre_con_comisiones() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.contrato_padre_id is not distinct from old.contrato_padre_id then return new; end if;
  -- sin sesión de usuario (service_role, cron) o super admin: pasa. Con sesión, aplica aunque venga
  -- por una función DEFINER (antes `current_user` la dejaba pasar).
  if (select auth.uid()) is null or public.es_super_admin() then return new; end if;
  if exists (select 1 from public.comisiones_devengadas d
              where d.estado <> 'anulada'
                and d.contrato_raiz_id in (old.id, old.contrato_padre_id, new.contrato_padre_id))
     or exists (select 1 from public.reclamaciones_venta_propia r
              where r.estado in ('pendiente', 'aprobada')
                and r.contrato_raiz_id in (old.id, old.contrato_padre_id, new.contrato_padre_id)) then
    raise exception 'esta venta ya tiene comisiones: el contrato padre solo lo cambia un super admin' using errcode = '42501';
  end if;
  return new;
end $$;

-- Nombre de los compradores como lo imprime la suite: port de compradoresDeContrato + nombresFactura
-- (contracts/assets/compradores.js). adq1..adq3 del formulario + `compradores[]`, sin vacíos, espacios
-- colapsados y sin repetir a la misma persona (comparación sin mayúsculas), unidos con « · ».
create or replace function public.contrato_nombres_compradores(p_datos jsonb) returns text
language sql immutable set search_path = '' as $$
  with crudos as (
    select 1 as o, 0 as i, p_datos->'fields'->>'adq1_nombre' as n
    union all select 1, 1, p_datos->'fields'->>'adq2_nombre'
    union all select 1, 2, p_datos->'fields'->>'adq3_nombre'
    union all select 2, e.ord::int, e.v->>'nombre'
      from jsonb_array_elements(case when jsonb_typeof(p_datos->'compradores') = 'array'
                                     then p_datos->'compradores' else '[]'::jsonb end) with ordinality e(v, ord)
  ), limpios as (
    select o, i, regexp_replace(btrim(coalesce(n, '')), '\s+', ' ', 'g') as n from crudos
  ), unicos as (
    select distinct on (lower(n)) o, i, n from limpios where n <> '' order by lower(n), o, i
  )
  select nullif(string_agg(n, ' · ' order by o, i), '') from unicos
$$;

create or replace function public.contrato_guarda(p_id uuid, p_contrato jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_datos  jsonb := p_contrato->'datos';
  v_f      jsonb;
  v_tipo   text  := nullif(btrim(coalesce(p_contrato->>'tipo', '')), '');
  v_nrv    text;
  v_poa    text;
  v_padre  uuid;
  v_proy   text;
  v_comp   text;
  v_fecha  date;
  v_precio numeric;
  v_old    public.contratos%rowtype;
  v_row    public.contratos%rowtype;
  v_firmado boolean;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_agente() and public.puede('contratos')) then
    raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
  end if;
  if v_datos is null or jsonb_typeof(v_datos) <> 'object' or jsonb_typeof(v_datos->'fields') <> 'object' then
    raise exception 'Contrato sin datos' using errcode = '22023';
  end if;
  if v_tipo is null then raise exception 'Contrato sin tipo' using errcode = '22023'; end if;
  v_f := v_datos->'fields';

  -- contrato padre, con la regla de la pantalla (VINCULABLES / VINCULABLES_POA): la reserva vinculada si
  -- es una Reserva de Parcela, o en un Poder el contrato (no Poder) al que acompaña; solo entre los que
  -- quien guarda puede ver. Un número que no casa no vincula.
  v_nrv := nullif(btrim(v_f->>'num_reserva_vinculada'), '');
  v_poa := nullif(btrim(v_f->>'poa_hs_vinculado'), '');
  if v_nrv is not null then
    select c.id into v_padre from public.contratos c
     where c.numero = v_nrv and c.tipo = 'reserva_parcela' and public.contrato_visible(c.creado_por, c.proyecto_id) limit 1;
  end if;
  if v_padre is null and v_poa is not null then
    select c.id into v_padre from public.contratos c
     where c.numero = v_poa and c.tipo <> 'poa' and public.contrato_visible(c.creado_por, c.proyecto_id) limit 1;
  end if;
  v_proy := nullif(btrim(v_f->>'proyecto_nombre'), '');
  if v_proy is null and v_poa is not null then
    select c.proyecto_nombre into v_proy from public.contratos c
     where c.numero = v_poa and c.tipo <> 'poa' and public.contrato_visible(c.creado_por, c.proyecto_id) limit 1;
  end if;
  v_comp := coalesce(public.contrato_nombres_compradores(v_datos),
                     nullif(btrim(v_f->>'adq1_nombre'), ''), nullif(btrim(v_f->>'partner_nombre'), ''),
                     nullif(btrim(v_f->>'colaborador_nombre'), ''));
  begin
    v_fecha := nullif(btrim(coalesce(v_f->>'fecha_firma', '')), '')::date;
  exception when others then
    raise exception 'Rellena: la fecha de firma no es una fecha válida' using errcode = '22007';
  end;
  v_precio := public.lw_parse_importe(v_f->>'precio_total');

  if p_id is null then
    -- alta: la policy «agentes o su manager insertan contratos» se comprueba con la fila final, porque
    -- proyecto_id lo fijan los triggers (si no pasa, se deshace el alta entera)
    insert into public.contratos (tipo, comprador_nombre, proyecto_nombre, precio_total, moneda, fecha_firma,
                                  contrato_padre_id, unidad_id, datos)
    values (v_tipo, v_comp, v_proy, v_precio, nullif(btrim(v_f->>'moneda'), ''), v_fecha, v_padre,
            case when p_contrato ? 'unidad_id' then nullif(p_contrato->>'unidad_id', '')::uuid end, v_datos)
    returning * into v_row;
    if not (public.puede_proyecto_de(v_row.datos, v_row.proyecto_nombre, v_row.proyecto_id)
            or public.es_manager_de(v_row.proyecto_id)) then
      raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
    end if;
  else
    select * into v_old from public.contratos c where c.id = p_id for update;
    if not found then raise exception 'Ese contrato ya no existe' using errcode = 'P0002'; end if;
    -- USING de la policy de UPDATE, con la fila de antes
    if not (public.es_super_admin()
            or (coalesce(v_old.bloqueado, false) = false and not public.contrato_firma_viva(v_old.id)
                and (public.es_suyo(v_old.creado_por) or public.es_manager_de(v_old.proyecto_id))
                and public.puede_proyecto_de(jsonb_build_object('fields', v_old.datos_fields),
                                             v_old.proyecto_nombre, v_old.proyecto_id))) then
      raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
    end if;
    -- El padre solo cambia si el agente cambió el vínculo en el formulario. Los traspasos de carta y
    -- «carta colgada de su RP» lo fijan desde el servidor sin tocar `datos` (24 contratos el 26-sep):
    -- la pantalla vieja lo pisaba con null en cada guardado; el servidor no.
    if coalesce(v_nrv, '') || '|' || coalesce(v_poa, '')
       = coalesce(nullif(btrim(v_old.datos_fields->>'num_reserva_vinculada'), ''), '') || '|'
         || coalesce(nullif(btrim(v_old.datos_fields->>'poa_hs_vinculado'), ''), '') then
      v_padre := v_old.contrato_padre_id;
    end if;
    v_firmado := coalesce(v_old.bloqueado, false)
              or exists (select 1 from public.contrato_firmas f where f.contrato_id = p_id and f.estado = 'firmado');
    update public.contratos c
       set tipo = v_tipo, comprador_nombre = v_comp, proyecto_nombre = v_proy,
           precio_total = case when v_firmado then c.precio_total else v_precio end,
           moneda = nullif(btrim(v_f->>'moneda'), ''), fecha_firma = v_fecha,
           contrato_padre_id = v_padre,
           unidad_id = case when p_contrato ? 'unidad_id' then nullif(p_contrato->>'unidad_id', '')::uuid else c.unidad_id end,
           datos = v_datos
     where c.id = p_id
    returning * into v_row;
    -- WITH CHECK de la policy, con la fila de después
    if not (public.es_super_admin()
            or ((public.es_suyo(v_row.creado_por) or public.es_manager_de(v_row.proyecto_id))
                and public.puede_proyecto_de(v_row.datos, v_row.proyecto_nombre, v_row.proyecto_id))) then
      raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
    end if;
  end if;

  return jsonb_build_object('id', v_row.id, 'numero', v_row.numero, 'precio_total', v_row.precio_total,
                            'fields', v_row.datos->'fields', 'hitos', v_row.datos->'hitos');
end $$;
revoke all on function public.contrato_guarda(uuid, jsonb) from public, anon;
grant execute on function public.contrato_guarda(uuid, jsonb) to authenticated;

-- «Desbloquear» un contrato firmado (LAW-71): solo super admin; el rastro lo deja trg_registra_edicion_privilegiada
create or replace function public.contrato_desbloquea(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_super_admin() then
    raise exception 'Solo un super admin desbloquea un contrato firmado' using errcode = '42501';
  end if;
  update public.contratos c set bloqueado = false where c.id = p_id and coalesce(c.bloqueado, false);
  if not found then raise exception 'Ese contrato no está bloqueado' using errcode = 'P0002'; end if;
end $$;
revoke all on function public.contrato_desbloquea(uuid) from public, anon;
grant execute on function public.contrato_desbloquea(uuid) to authenticated;

-- anular una firma dada: el firmante tiene que tener email, o el aviso obligatorio no es posible (Legal)
create or replace function public.contrato_firmas_anula(p_contrato uuid, p_motivo text,
                                                        p_incluir_firmadas boolean default false,
                                                        p_justificacion text default null)
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_n int;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_just text := nullif(btrim(coalesce(p_justificacion, '')), '');
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_agente() or not exists (
       select 1 from public.contratos c
        where c.id = p_contrato and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))) then
    raise exception 'No puedes anular las firmas de este contrato' using errcode = '42501';
  end if;
  if v_motivo is null or v_motivo not in ('editar', 'nuevo_enlace', 'cierre_manual') then
    raise exception 'Motivo de anulación no válido' using errcode = '22023';
  end if;
  if coalesce(p_incluir_firmadas, false) then
    if not public.es_super_admin() then
      raise exception 'Una firma ya dada no se anula: el cambio va por adenda (o lo reabre un super admin)'
        using errcode = '42501';
    end if;
    if v_just is null or length(v_just) < 10 then
      raise exception 'Para anular una firma ya dada escribe por qué (queda en el registro)' using errcode = '22023';
    end if;
    if exists (select 1 from public.contrato_firmas f
                where f.contrato_id = p_contrato and f.estado = 'firmado'
                  and coalesce(f.firmante_email, '') !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$') then
      raise exception 'Alguien que ya firmó no tiene email: no se le puede avisar, así que su firma no se anula desde aquí'
        using errcode = '22023';
    end if;
  end if;

  update public.contrato_firmas f
     set estado = 'anulado', anulado_en = now(), anulado_por = (select auth.email()),
         anulado_motivo = v_motivo, anulado_justificacion = v_just
   where f.contrato_id = p_contrato
     and (f.estado = 'pendiente' or (coalesce(p_incluir_firmadas, false) and f.estado = 'firmado'));
  get diagnostics v_n = row_count;
  return v_n;
end $$;
