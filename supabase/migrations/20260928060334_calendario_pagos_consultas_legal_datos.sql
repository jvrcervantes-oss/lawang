-- destructivo-ok: reemplaza contrato_calendario_preset, sincroniza_vencimientos y contrato_guarda con la misma firma; no toca datos.
-- Consultas de deploy del calendario de pagos (28-sep-2026), antes de publicar la pantalla:
-- 1) Legal: el concepto del pago único a la firma decía «Pago único a la firma» junto a una fecha que puede ser hasta
--    90 días después — dos momentos de pago en la misma fila de un documento firmable (art. 1349 KUHPerdata: la
--    ambigüedad se interpreta contra quien redacta). Pasa a «Pago único / Single payment / Pembayaran tunggal»; la
--    fecha de la tabla es la que manda, como dice la cláusula. 0 contratos lo usaban.
-- 2) Datos [ALTA]: sincroniza_vencimientos borraba y recreaba todo vencimiento no ajustado ni facturado al cambiar los
--    hitos, y así perdía `no_facturar` y `nota` (29 vencimientos pactados aparte en contratos firmados): el robot los
--    habría facturado. Ahora actualiza en sitio (upsert por contrato+orden) solo lo que no está ajustado ni facturado,
--    no toca `no_facturar` ni `nota`, y borra únicamente los `orden` que ya no existen en el calendario.
-- 3) Datos [MEDIA]: un contrato FIRMADO no pasa por el calendario al guardarse (solo puede hacerlo un super admin): su
--    tabla es la que se firmó, no se remonta desde el preset ni pierde sus fechas.
-- 4) Cambiar de calendario con algún pago «no facturar» se rechaza, como con uno ajustado o facturado: la marca se
--    queda en su `orden` y el pago nuevo que cae ahí la heredaría (cazado por la prueba de esta misma migración).

create or replace function public.contrato_calendario_preset(p_cal text) returns jsonb
language sql immutable set search_path = '' as $$
  select (
-- >>> presets
'{
  "estandar": [
    {"pct": "25", "monto": "", "timing": "", "es": "Preparación del terreno y movimiento de tierras", "en": "Site preparation and earthworks", "id": "Persiapan lahan dan pekerjaan tanah", "fijo": true, "calculado": true},
    {"pct": "25", "monto": "", "timing": "", "es": "Estructura", "en": "Structure", "id": "Struktur", "fijo": true, "calculado": true},
    {"pct": "25", "monto": "", "timing": "", "es": "Instalaciones generales", "en": "General installations", "id": "Instalasi umum", "fijo": true, "calculado": true},
    {"pct": "20", "monto": "", "timing": "", "es": "Acabados y terminaciones", "en": "Finishes", "id": "Finishing", "fijo": true, "calculado": true},
    {"pct": "5", "monto": "", "timing": "", "es": "Revisión y entrega", "en": "Inspection and handover", "id": "Pemeriksaan dan serah terima", "fijo": true, "calculado": true, "resto": true}
  ],
  "unico_firma": [
    {"pct": "100", "monto": "", "timing": "", "es": "Pago único", "en": "Single payment", "id": "Pembayaran tunggal", "fijo": true, "calculado": true, "resto": true}
  ],
  "unico_obra": [
    {"pct": "100", "monto": "", "timing": "", "es": "Pago único al inicio de obra", "en": "Single payment upon commencement of works", "id": "Pembayaran tunggal pada saat dimulainya pekerjaan", "fijo": true, "calculado": true, "resto": true}
  ]
}'
-- <<< presets
  ::jsonb) -> p_cal
$$;

create or replace function public.sincroniza_vencimientos()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  hitos jsonb := coalesce(new.datos->'hitos', '[]'::jsonb);
begin
  if tg_op = 'UPDATE' and new.datos->'hitos' is not distinct from old.datos->'hitos' then
    return new;
  end if;
  if jsonb_typeof(hitos) <> 'array' then hitos := '[]'::jsonb; end if;

  -- hitos que ya no existen: fuera, salvo lo ajustado a mano o ya facturado
  delete from public.contrato_vencimientos v
   where v.contrato_id = new.id and v.orden > jsonb_array_length(hitos)
     and not v.ajustado and v.factura_id is null;

  -- los que existen: en sitio. `no_facturar` y `nota` son de quien los puso, no del calendario
  insert into public.contrato_vencimientos as v
         (contrato_id, orden, descripcion, pct, monto, fecha)
  select new.id,
         h.ordinality,
         nullif(btrim(coalesce(h.value->>'es', h.value->>'en', h.value->>'id', '')), ''),
         public.lw_importe(h.value->>'pct'),
         public.lw_importe(h.value->>'monto'),
         case when h.value->>'fecha' ~ '^\d{4}-\d{2}-\d{2}$'
              then (h.value->>'fecha')::date end
    from jsonb_array_elements(hitos) with ordinality h
  on conflict (contrato_id, orden) do update
     set descripcion = excluded.descripcion, pct = excluded.pct, monto = excluded.monto, fecha = excluded.fecha
   where not v.ajustado and v.factura_id is null;

  return new;
end;
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
    -- calendario de pagos de Construcción: lo monta el servidor (20260928052131)
    if v_tipo = 'construccion' then
      v_datos := public.contrato_calendario_aplica(v_datos, null, v_precio, v_fecha, null);
    end if;
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
    -- mismo mensaje que el trigger contrato_no_editable_en_firma: el agente sabe qué hacer
    if not public.es_super_admin() and (coalesce(v_old.bloqueado, false) or public.contrato_firma_viva(v_old.id)) then
      raise exception 'Contrato enviado a firma: usa «Editar (anula la firma)» para guardar cambios.' using errcode = '23514';
    end if;
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
    -- calendario de pagos de Construcción: lo monta el servidor, sobre el precio que se va a guardar. Un contrato
    -- firmado (solo lo guarda un super admin) conserva la tabla que se firmó (Datos, 28-sep)
    if v_tipo = 'construccion' and not v_firmado then
      v_datos := public.contrato_calendario_aplica(v_datos, v_old.datos,
                                                   case when v_firmado then v_old.precio_total else v_precio end,
                                                   v_fecha, p_id);
    end if;
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

  return jsonb_build_object('id', v_row.id, 'numero', v_row.numero, 'precio_total', v_row.precio_total, 'moneda', v_row.moneda,
                            'fields', v_row.datos->'fields', 'hitos', v_row.datos->'hitos',
                            'calendario', v_row.datos->'calendario');
end $$;
revoke all on function public.contrato_guarda(uuid, jsonb) from public, anon;
grant execute on function public.contrato_guarda(uuid, jsonb) to authenticated;

create or replace function public.contrato_calendario_aplica(p_datos jsonb, p_old_datos jsonb, p_precio numeric,
                                                             p_fecha_firma date, p_contrato_id uuid) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_admin   boolean := public.es_admin();
  v_old_cal text;
  v_cal     text := nullif(btrim(coalesce(p_datos->>'calendario', '')), '');
  v_hitos   jsonb := case when jsonb_typeof(p_datos->'hitos') = 'array' then p_datos->'hitos' else '[]'::jsonb end;
  v_old_h   jsonb;
  v_suma    numeric;
  i int;
begin
  if p_old_datos is not null then
    v_old_h := case when jsonb_typeof(p_old_datos->'hitos') = 'array' then p_old_datos->'hitos' else '[]'::jsonb end;
    v_old_cal := coalesce(nullif(p_old_datos->>'calendario', ''), public.contrato_calendario_deduce(v_old_h));
  end if;
  -- Una pestaña abierta antes de este cambio no manda `calendario`: se sigue con el que ya tenía, o, en un alta,
  -- con el que dicen sus hitos. Deducido del payload SOLO aquí, y lo que salga se valida igual abajo.
  if v_cal is null then v_cal := coalesce(v_old_cal, public.contrato_calendario_deduce(v_hitos)); end if;
  if v_cal not in ('estandar', 'unico_firma', 'unico_obra', 'manual', 'libre') then
    raise exception 'Calendario de pagos desconocido: %', v_cal using errcode = '22023';
  end if;

  if v_cal = 'libre' and v_old_cal is distinct from 'libre' and not v_admin then
    raise exception 'Elige el calendario de pagos: por hitos, pago único a la firma o pago único al inicio de obra.'
      using errcode = '23514';
  end if;
  if v_cal = 'manual' and v_old_cal is distinct from 'manual' and not v_admin then
    raise exception 'Un calendario de pagos a medida solo lo monta un admin.' using errcode = '42501';
  end if;
  if v_old_cal = 'manual' and v_cal <> 'manual' and not v_admin then
    raise exception 'Este calendario de pagos lo montó un admin: cambiar la forma de pago es cosa suya.' using errcode = '42501';
  end if;

  if p_old_datos is not null and v_cal is distinct from v_old_cal
     and exists (select 1 from public.contrato_vencimientos cv
                  where cv.contrato_id = p_contrato_id and (cv.ajustado or cv.factura_id is not null or coalesce(cv.no_facturar, false))) then
    -- `no_facturar` también (Datos, 28-sep): sincroniza_vencimientos conserva la marca por `orden`, así que el pago
    -- nuevo que cae en ese número la heredaría y el robot no lo facturaría nunca
    raise exception 'Este contrato ya tiene pagos con fecha movida, facturados o marcados «no facturar»: no se puede cambiar de calendario. Habla con administración.'
      using errcode = '23514';
  end if;

  if v_cal in ('estandar', 'unico_firma', 'unico_obra') then
    -- La fecha de un pago único que ya estaba guardada (quizá la puso un admin más allá del tope) no bloquea al agente
    -- que guarda el contrato por otra cosa: el tope solo se mira cuando la fecha cambia.
    v_hitos := public.contrato_calendario_monta(v_cal, p_precio, v_hitos, coalesce(p_fecha_firma, current_date),
                 -- coalesce: en un alta no hay calendario ni hitos viejos y la comparación da NULL, que
                 -- dentro de monta se leería como «no mires el tope»
                 v_admin or coalesce(v_cal = v_old_cal and coalesce(v_hitos->0->>'fecha', '') <> ''
                                     and v_hitos->0->>'fecha' = v_old_h->0->>'fecha', false));
  elsif v_cal = 'manual' and not v_admin then
    -- conserva la tabla guardada; solo deja mover la fecha de cada hito, como hasta hoy. Los importes se rehacen
    -- abajo con el precio de ahora.
    if jsonb_array_length(v_hitos) <> jsonb_array_length(v_old_h) then
      raise exception 'Este calendario de pagos lo montó un admin: añadir o quitar hitos es cosa suya.' using errcode = '42501';
    end if;
    for i in 0 .. jsonb_array_length(v_old_h) - 1 loop
      v_old_h := jsonb_set(v_old_h, array[i::text, 'fecha'],
                           to_jsonb(coalesce(to_char(public.contrato_calendario_fecha(v_hitos->i->>'fecha', 'El vencimiento del hito ' || (i + 1)), 'YYYY-MM-DD'), '')));
    end loop;
    v_hitos := public.contrato_calendario_reparte(v_old_h, p_precio);
  else
    -- libre (cualquiera, solo en un contrato que ya lo era) o manual de admin: la tabla es de quien la escribe,
    -- pero un agente no se fabrica marcas de fábrica, y ninguna tabla sale con importes negativos ni % que no cuadren
    if not v_admin and exists (select 1 from jsonb_array_elements(v_hitos) h where coalesce((h->>'fijo')::boolean, false)) then
      raise exception 'Este contrato no tiene calendario de fábrica: elige uno en vez de marcar hitos a mano.' using errcode = '42501';
    end if;
    select sum(public.lw_importe(h->>'pct')) into v_suma
      from jsonb_array_elements(v_hitos) h where coalesce(public.lw_importe(h->>'pct'), 0) > 0;
    if v_suma is not null and abs(v_suma - 100) > 0.01 then
      raise exception 'Los hitos suman % %%, no 100 %%.', v_suma using errcode = '23514';
    end if;
    for i in 0 .. jsonb_array_length(v_hitos) - 1 loop
      perform public.contrato_calendario_fecha(v_hitos->i->>'fecha', 'El vencimiento del hito ' || (i + 1));
    end loop;
    -- los hitos `calculado` salen del precio (los escritos a mano, no: son importes cerrados a propósito)
    v_hitos := public.contrato_calendario_reparte(v_hitos, p_precio);
    if exists (select 1 from jsonb_array_elements(v_hitos) h where public.lw_importe(h->>'monto') < 0) then
      raise exception 'Hay un hito con importe negativo.' using errcode = '23514';
    end if;
  end if;

  return jsonb_set(
           p_datos || jsonb_build_object('calendario', v_cal, 'hitos', v_hitos),
           '{fields}',
           (coalesce(p_datos->'fields', '{}'::jsonb) - 'clausula_pago')
             || case when v_cal in ('unico_firma', 'unico_obra') then jsonb_build_object('clausula_pago', v_cal) else '{}'::jsonb end);
end $$;

revoke all on function public.contrato_calendario_aplica(jsonb, jsonb, numeric, date, uuid) from public, anon, authenticated;
