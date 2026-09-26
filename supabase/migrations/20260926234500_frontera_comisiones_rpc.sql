-- destructivo-ok: los DELETE van DENTRO de funciones (reemplazar los tramos de una condicion sin devengos y borrar una condicion desactivada sin devengos: lo mismo que hacia la pantalla); esta migracion no borra ninguna fila al aplicarse.
-- Frontera frontend/backend — pieza 6: COMISIONES por el servidor (26-sep-2026, LAW-336). SOLO AÑADE
-- (funciones y dos tablas de registro); cerrar la escritura directa va aparte, con OK del owner.
-- Plan y revisión previa #121 (Seguridad + Administración): encargos/20260926_lawang_frontera_f6_comisiones.md
--
-- Dos triggers deciden por `current_user` y se apartan cuando escribe una función DEFINER
-- (_trg_condicion_comision_manager, _trg_comision_devengo_guarda); las RPC que ya existen cuentan con eso,
-- así que NO se tocan: cada función de aquí repite dentro sus reglas y las de las policies.
-- · Condición y tramos en UNA transacción (antes: insert, insert y un delete de compensación).
-- · Se decide con la fila GUARDADA (for update), nunca con equipo/nivel que mande la pantalla; lista
--   blanca de campos; created_by de la sesión.
-- · Decisión del owner (26-sep): con comisiones ya devengadas, el ADMIN puede seguir cambiando las cifras
--   de una condición, pero con motivo obligatorio, que queda en condiciones_comision_log; un manager no.
--   Los tramos con devengos no se tocan nunca (cada devengo cita su tramo con el importe congelado).
-- · Marcar pagada: atómica (solo pendiente→pagada, una vez), nadie a su propio nombre (tampoco un admin).
-- · Comisión de administración: el estado de una línea solo AVANZA (pendiente→facturada→cobrada,
--   pendiente→cobrada, pendiente→exenta); volver atrás exige motivo. Cada cambio de estado queda con
--   quién y cuándo en comision_admin_lineas_log — es la fecha de facturación/cobro que cuenta.

-- ── registros ──────────────────────────────────────────────────────────────────
create table if not exists public.condiciones_comision_log (
  id uuid primary key default gen_random_uuid(),
  condicion_id uuid not null,
  antes jsonb, despues jsonb,
  con_devengos boolean not null default false,
  motivo text,
  por text default auth.email(),
  en timestamptz not null default now()
);
alter table public.condiciones_comision_log enable row level security;
revoke all on public.condiciones_comision_log from anon, authenticated;
grant select on public.condiciones_comision_log to authenticated;
create policy "log de condiciones: lo ve un admin" on public.condiciones_comision_log
  for select to authenticated using (public.es_admin());

create table if not exists public.comision_admin_lineas_log (
  id uuid primary key default gen_random_uuid(),
  linea_id uuid not null,
  estado_antes text, estado_despues text,
  motivo text,
  por text default auth.email(),
  en timestamptz not null default now()
);
alter table public.comision_admin_lineas_log enable row level security;
revoke all on public.comision_admin_lineas_log from anon, authenticated;
grant select on public.comision_admin_lineas_log to authenticated;
create policy "log de estados: lo ve un super admin" on public.comision_admin_lineas_log
  for select to authenticated using (public.es_super_admin());

-- ── ayudantes ──────────────────────────────────────────────────────────────────
-- ¿Puede quien llama tocar ESTA condición? (policies «condiciones_comision: escribir» y «el manager
-- configura a sus closers», con la fila guardada)
create or replace function public._condicion_es_mia(p_nivel text, p_equipo uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_admin()
      or (p_nivel in ('closer', 'setter', 'team_lead') and p_equipo is not null and public.es_manager_de_equipo(p_equipo))
$$;
revoke all on function public._condicion_es_mia(text, uuid) from public, anon, authenticated;

create or replace function public._closer_del_equipo(p_equipo uuid, p_email text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.equipo_miembros em
                  where em.equipo_id = p_equipo and lower(em.closer_email) = lower(p_email)
                    and em.desde <= current_date and (em.hasta is null or em.hasta >= current_date))
$$;
revoke all on function public._closer_del_equipo(uuid, text) from public, anon, authenticated;

create or replace function public._condicion_tramos_pone(p_condicion uuid, p_tramos jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_tramos is null or jsonb_typeof(p_tramos) <> 'array' or jsonb_array_length(p_tramos) = 0 then
    raise exception 'Hacen falta tramos de pago' using errcode = '23514';
  end if;
  delete from public.condicion_tramos where condicion_id = p_condicion;
  insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo)
  select p_condicion, ord, t->>'disparador_tipo',
         case when (t->>'disparador_tipo') like 'pct_cobrado_%' then (t->>'umbral')::numeric end,
         (t->>'pct_tramo')::numeric
    from jsonb_array_elements(p_tramos) with ordinality as x(t, ord);
end $$;
revoke all on function public._condicion_tramos_pone(uuid, jsonb) from public, anon, authenticated;

-- ── condiciones de comisión ────────────────────────────────────────────────────
create or replace function public.condicion_comision_guarda(p_id uuid, p_cond jsonb, p_tramos jsonb,
                                                            p_motivo text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_old    public.condiciones_comision%rowtype;
  v_id     uuid;
  v_nivel  text;
  v_equipo uuid;
  v_proy   uuid;
  v_closer text := nullif(lower(btrim(coalesce(p_cond->>'closer_email', ''))), '');
  v_pct    numeric;
  v_base   text := p_cond->>'base_calculo';
  v_fijo   numeric;
  v_desde  date;
  v_admin  boolean := public.es_admin();
  v_n      int := 0;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  begin
    v_pct   := (p_cond->>'pct_comision')::numeric;
    v_fijo  := case when v_base = 'importe_fijo' then (p_cond->>'importe_fijo')::numeric end;
    v_desde := coalesce(nullif(p_cond->>'vigente_desde', '')::date, current_date);
  exception when others then
    raise exception 'Revisa las cifras: el %%, el importe fijo o la fecha no son válidos' using errcode = '22023';
  end;
  if v_pct is null or v_pct < 0 or v_pct > 100 then raise exception 'El %% de comisión va entre 0 y 100' using errcode = '22023'; end if;

  if p_id is null then
    v_equipo := nullif(p_cond->>'equipo_id', '')::uuid;
    v_proy   := nullif(p_cond->>'proyecto_id', '')::uuid;
    v_nivel  := case when v_equipo is null then 'closer' else coalesce(p_cond->>'nivel', 'closer') end;
    if not public._condicion_es_mia(v_nivel, v_equipo) then
      raise exception 'Solo puedes crear condiciones para los closers, setters o team leads de tu equipo' using errcode = '42501';
    end if;
    if not v_admin then
      if v_desde < current_date then raise exception 'La fecha no puede ser anterior a hoy.' using errcode = '22023'; end if;
      if v_closer is not null and not public._closer_del_equipo(v_equipo, v_closer) then
        raise exception 'Esa persona no está hoy en tu equipo' using errcode = '42501';
      end if;
    end if;
    insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo,
                                             importe_fijo, vigente_desde, created_by)
    values (v_equipo, v_proy, v_nivel,
            case when v_nivel in ('closer', 'setter', 'team_lead') then v_closer end,
            v_pct, v_base, v_fijo, v_desde, (select auth.email()))
    returning id into v_id;
    perform public._condicion_tramos_pone(v_id, p_tramos);
    insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
    select v_id, null, to_jsonb(c), v_motivo from public.condiciones_comision c where c.id = v_id;
    return v_id;
  end if;

  select * into v_old from public.condiciones_comision c where c.id = p_id for update;
  -- mismo mensaje para «no existe» y «no es tuya»: no se adivinan ids de otros equipos
  if not found or not public._condicion_es_mia(v_old.nivel, v_old.equipo_id) then
    raise exception 'No encuentro esa condición entre las tuyas' using errcode = '42501';
  end if;
  select count(*) into v_n from public.comisiones_devengadas d where d.condicion_id = p_id;
  if v_n > 0 then
    if not v_admin then
      raise exception 'Esta condición ya ha generado comisiones: no se cambian sus cifras. Desactívala y crea una nueva.' using errcode = '22023';
    end if;
    if v_motivo is null or length(v_motivo) < 10 then
      raise exception 'Esta condición ya ha generado comisiones: escribe por qué cambias sus cifras (queda registrado)' using errcode = '22023';
    end if;
  end if;
  if not v_admin then
    if v_desde is distinct from v_old.vigente_desde and v_desde < current_date then
      raise exception 'la fecha de vigencia no puede quedar en el pasado' using errcode = '22023';
    end if;
    if v_closer is not null and not public._closer_del_equipo(v_old.equipo_id, v_closer) then
      raise exception 'Esa persona no está hoy en tu equipo' using errcode = '42501';
    end if;
  end if;

  update public.condiciones_comision c
     set pct_comision = v_pct, base_calculo = v_base, importe_fijo = v_fijo, vigente_desde = v_desde,
         closer_email = case when c.nivel in ('closer', 'setter', 'team_lead') then v_closer else c.closer_email end
   where c.id = p_id;
  if v_n = 0 then
    perform public._condicion_tramos_pone(p_id, p_tramos);   -- con devengos, los tramos no se tocan
  end if;
  insert into public.condiciones_comision_log (condicion_id, antes, despues, con_devengos, motivo)
  select p_id, to_jsonb(v_old), to_jsonb(c), v_n > 0, v_motivo from public.condiciones_comision c where c.id = p_id;
  return p_id;
end $$;
revoke all on function public.condicion_comision_guarda(uuid, jsonb, jsonb, text) from public, anon;
grant execute on function public.condicion_comision_guarda(uuid, jsonb, jsonb, text) to authenticated;

create or replace function public.condicion_comision_activa(p_id uuid, p_activo boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare v_old public.condiciones_comision%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  select * into v_old from public.condiciones_comision c where c.id = p_id for update;
  if not found or not public._condicion_es_mia(v_old.nivel, v_old.equipo_id) then
    raise exception 'No encuentro esa condición entre las tuyas' using errcode = '42501';
  end if;
  update public.condiciones_comision set activo = coalesce(p_activo, false) where id = p_id;
  insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
  values (p_id, jsonb_build_object('activo', v_old.activo), jsonb_build_object('activo', coalesce(p_activo, false)), null);
end $$;
revoke all on function public.condicion_comision_activa(uuid, boolean) from public, anon;
grant execute on function public.condicion_comision_activa(uuid, boolean) to authenticated;

create or replace function public.condicion_comision_borra(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_old public.condiciones_comision%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  select * into v_old from public.condiciones_comision c where c.id = p_id for update;
  if not found or not public._condicion_es_mia(v_old.nivel, v_old.equipo_id) then
    raise exception 'No encuentro esa condición entre las tuyas' using errcode = '42501';
  end if;
  if exists (select 1 from public.comisiones_devengadas d where d.condicion_id = p_id) then
    raise exception 'esta condición ya ha generado comisiones: desactívala en vez de borrarla' using errcode = '22023';
  end if;
  if v_old.activo then
    raise exception 'Desactiva la condición antes de borrarla' using errcode = '22023';
  end if;
  insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
  values (p_id, to_jsonb(v_old), null, 'borrada');
  delete from public.condiciones_comision where id = p_id;   -- los tramos caen en cascada
end $$;
revoke all on function public.condicion_comision_borra(uuid) from public, anon;
grant execute on function public.condicion_comision_borra(uuid) to authenticated;

-- ── marcar pagada una comisión de closer/setter/team lead ──────────────────────
create or replace function public.comision_marca_pagada(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v public.comisiones_devengadas%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  select * into v from public.comisiones_devengadas d where d.id = p_id for update;
  if not found or v.nivel not in ('closer', 'setter', 'team_lead')
     or not ((public.es_admin() and public.puede('comisiones_reparto'))
             or public.es_manager_de_equipo(public._equipo_de_condicion_comision(v.condicion_id))) then
    raise exception 'No encuentro esa comisión entre las que puedes marcar' using errcode = '42501';
  end if;
  if lower(v.beneficiario_email) = lower(coalesce((select auth.email()), '')) then
    raise exception 'nadie marca como pagada una comisión a su propio nombre' using errcode = '42501';
  end if;
  if v.estado <> 'pendiente' then
    raise exception 'Solo se marca pagada una comisión pendiente (esta está «%»)', v.estado using errcode = '22023';
  end if;
  update public.comisiones_devengadas
     set estado = 'pagada', pagado_por = (select auth.email()), pagado_en = now()
   where id = p_id and estado = 'pendiente';
end $$;
revoke all on function public.comision_marca_pagada(uuid) from public, anon;
grant execute on function public.comision_marca_pagada(uuid) to authenticated;

-- ── comisión de administración (solo super admin) ─────────────────────────────
create or replace function public.comision_admin_tarifa_crea(p_pct numeric, p_efectivo_desde date, p_nota text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_afectadas int := 0;
begin
  if not public.es_super_admin() then raise exception 'Solo un super admin' using errcode = '42501'; end if;
  if p_pct is null or p_pct < 0 or p_pct > 100 then
    raise exception 'El porcentaje va entre 0 y 100. Medio por ciento es 0,5 — no 50.' using errcode = '22023';
  end if;
  if p_efectivo_desde is null then raise exception 'La tarifa necesita la fecha desde la que rige' using errcode = '22023'; end if;
  if exists (select 1 from public.comision_admin_tarifas t where t.efectivo_desde = p_efectivo_desde) then
    raise exception 'Ya hay una tarifa que rige desde el %: edítala en vez de crear otra', p_efectivo_desde using errcode = '23505';
  end if;
  insert into public.comision_admin_tarifas (pct, efectivo_desde, nota, creado_por)
  values (p_pct, p_efectivo_desde, nullif(btrim(coalesce(p_nota, '')), ''), (select auth.email()))
  returning id into v_id;
  -- una tarifa con fecha pasada no reescribe lo ya devengado: se dice cuántas líneas quedan con la anterior
  if p_efectivo_desde < current_date then
    select count(*) into v_afectadas from public.comision_admin_lineas l
     where l.tipo_linea = 'devengo' and not l.anulada and l.fecha_recibi >= p_efectivo_desde;
  end if;
  return jsonb_build_object('id', v_id, 'lineas_con_tarifa_anterior', v_afectadas);
end $$;
revoke all on function public.comision_admin_tarifa_crea(numeric, date, text) from public, anon;
grant execute on function public.comision_admin_tarifa_crea(numeric, date, text) to authenticated;

-- alta de un fee (p_serie null) o cambio de uno existente (fila nueva de la MISMA serie: lo anterior queda)
create or replace function public.comision_admin_fee_guarda(p_serie uuid, p_datos jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid; v_imp numeric; v_mon text := upper(coalesce(p_datos->>'moneda', 'EUR')); v_desde date;
  v_serie record;
begin
  if not public.es_super_admin() then raise exception 'Solo un super admin' using errcode = '42501'; end if;
  begin
    v_imp := (p_datos->>'importe')::numeric;
    v_desde := (p_datos->>'efectivo_desde')::date;
  exception when others then
    raise exception 'Revisa el importe y la fecha' using errcode = '22023';
  end;
  if v_imp is null or v_imp < 0 then raise exception 'El importe tiene que ser un número igual o mayor que 0.' using errcode = '22023'; end if;
  if v_desde is null then raise exception 'Falta la fecha desde la que rige' using errcode = '22023'; end if;
  if v_mon not in ('EUR', 'USD', 'IDR') then raise exception 'Moneda no válida' using errcode = '22023'; end if;
  if p_serie is not null then
    select f.sociedad, f.concepto, f.beneficiario into v_serie
      from public.comision_admin_fees f where f.serie_id = p_serie order by f.created_at limit 1;
    if not found then raise exception 'Ese fee no existe' using errcode = 'P0002'; end if;
    insert into public.comision_admin_fees (serie_id, concepto, beneficiario, sociedad, importe, moneda, efectivo_desde, nota, creado_por)
    values (p_serie, v_serie.concepto, v_serie.beneficiario, v_serie.sociedad, v_imp, v_mon, v_desde,
            nullif(btrim(coalesce(p_datos->>'nota', '')), ''), (select auth.email()))
    returning id into v_id;
  else
    if nullif(btrim(coalesce(p_datos->>'concepto', '')), '') is null then
      raise exception 'Ponle un concepto: es lo que distingue este fee de los demás.' using errcode = '22023';
    end if;
    if nullif(btrim(coalesce(p_datos->>'sociedad', '')), '') is null then
      raise exception 'Elige la sociedad: cada una es un deudor distinto y se le factura por separado.' using errcode = '22023';
    end if;
    insert into public.comision_admin_fees (concepto, beneficiario, sociedad, importe, moneda, efectivo_desde, nota, creado_por)
    values (btrim(p_datos->>'concepto'), nullif(btrim(coalesce(p_datos->>'beneficiario', '')), ''),
            btrim(p_datos->>'sociedad'), v_imp, v_mon, v_desde,
            nullif(btrim(coalesce(p_datos->>'nota', '')), ''), (select auth.email()))
    returning id into v_id;
  end if;
  return v_id;
end $$;
revoke all on function public.comision_admin_fee_guarda(uuid, jsonb) from public, anon;
grant execute on function public.comision_admin_fee_guarda(uuid, jsonb) to authenticated;

-- estado de cobro de una línea: solo avanza; atrás con motivo; queda quién y cuándo
create or replace function public.comision_admin_linea_estado(p_id uuid, p_estado text, p_nota text,
                                                              p_toca_nota boolean, p_quitar_revisar boolean,
                                                              p_motivo text default null)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  v public.comision_admin_lineas%rowtype;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_avanza boolean;
begin
  if not public.es_super_admin() then raise exception 'Solo un super admin' using errcode = '42501'; end if;
  select * into v from public.comision_admin_lineas l where l.id = p_id for update;
  if not found then raise exception 'Esa comisión no existe' using errcode = 'P0002'; end if;
  if v.anulada then raise exception 'Esa comisión está anulada: su estado no se cambia' using errcode = '22023'; end if;
  if p_estado not in ('pendiente', 'facturada', 'cobrada', 'exenta') then
    raise exception 'Estado no válido' using errcode = '22023';
  end if;
  if p_estado is distinct from v.estado then
    v_avanza := (v.estado = 'pendiente' and p_estado in ('facturada', 'cobrada', 'exenta'))
             or (v.estado = 'facturada' and p_estado = 'cobrada');
    if not v_avanza and (v_motivo is null or length(v_motivo) < 5) then
      raise exception 'Volver de «%» a «%» necesita un motivo (queda registrado)', v.estado, p_estado using errcode = '22023';
    end if;
    insert into public.comision_admin_lineas_log (linea_id, estado_antes, estado_despues, motivo)
    values (p_id, v.estado, p_estado, v_motivo);
  end if;
  update public.comision_admin_lineas l
     set estado = p_estado,
         nota = case when coalesce(p_toca_nota, false) then nullif(btrim(coalesce(p_nota, '')), '') else l.nota end,
         revisar = case when coalesce(p_quitar_revisar, false) then false else l.revisar end,   -- solo baja, nunca sube
         actualizado_en = now()
   where l.id = p_id;
  return p_estado;
end $$;
revoke all on function public.comision_admin_linea_estado(uuid, text, text, boolean, boolean, text) from public, anon;
grant execute on function public.comision_admin_linea_estado(uuid, text, text, boolean, boolean, text) to authenticated;
