-- destructivo-ok: solo reemplaza funciones con la misma firma (contrato_guarda, obra_contratos_afectados,
-- obra_confirmar_avance) y añade funciones y un parámetro; no toca datos.
-- Calendario de pagos elegible en el Contrato de Construcción (28-sep-2026, owner; revisión previa #148:
-- Legal + Seguridad + Administración).
--
-- El agente elige UNO de tres calendarios cerrados, y el servidor es quien monta la tabla:
--   · estandar     5 hitos 25/25/25/20/5. Sin fecha a la firma: cada uno lo fija el parte de obra de su
--                  fase (obra_confirmar_avance) — «el día que se firma no tenemos vencimientos» (owner).
--   · unico_firma  1 × 100 %. Vence en la fecha que ponga el agente: ≥ fecha de firma y ≤ fecha de firma +
--                  `construccion.pago_unico_max_dias` (90, owner). Admin pasa del tope.
--   · unico_obra   1 × 100 %. Lo fija el parte de «preparacion» (pago 1). La fecha que escriba el agente es
--                  ESTIMADA: se guarda en `fecha_estimada`, nunca en `fecha` — `sincroniza_vencimientos` solo lee
--                  `fecha` y `factura-vencimiento` factura cualquier fecha en [hoy, hoy+3]: con la estimada en
--                  `fecha` el robot habría facturado el 100 % antes de empezar la obra (Administración, ALTA).
-- Además, deducidos de lo YA guardado (nunca de lo que manda el navegador — Seguridad):
--   · manual  algún hito de fábrica (`fijo`) pero no es ningún preset: lo montó un admin. Solo admin lo cambia;
--             el resto conserva los hitos guardados y solo mueve fechas, como hasta hoy.
--   · libre   ningún hito `fijo`: contratos de antes del 16-sep. Siguen 100 % manuales para cualquiera (61
--             borradores así el 28-sep); no se les pone ninguna marca de fábrica.
-- Los importes los calcula SIEMPRE el servidor desde el precio total (No te creas nada del front-end): la
-- misma regla que recalcularMontosHitos() (contracts/assets/hitos_fechas.js) — round(total × pct) / 100 por
-- hito y el hito `resto` absorbe la diferencia — con lw_importe_texto, el port con paridad de
-- lwImporteCanonico. La Carta de Reserva NO entra: su abono solo se aplica al Bloqueo de Parcela.
-- Cambiar de calendario con algún vencimiento movido o facturado se rechaza: sincroniza_vencimientos no borra
-- los ajustados y dejaría pagos que ya no existen en el contrato, facturables (Seguridad + Administración).
-- La cláusula del Art. 5 sigue al calendario por `fields.clausula_pago` (vacío = texto de hitos de siempre),
-- que también escribe el servidor.

insert into public.parametros (clave, valor, etiqueta, ayuda, minimo, maximo, grupo, orden)
values ('construccion.pago_unico_max_dias', '90'::jsonb,
        'Pago único a la firma: días máximos desde la firma',
        'Hasta cuántos días después de la fecha de firma puede el agente poner el vencimiento del pago único. Un admin puede pasarse.',
        0, 365, 'construccion', 10)
on conflict (clave) do nothing;

-- Los tres calendarios de fábrica. La MISMA lista vive en contracts/tokens.json → hitosCalendarios;
-- contracts/calendario_pagos.test.js comprueba que son idénticas (entre los marcadores >>> y <<<).
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
    {"pct": "100", "monto": "", "timing": "", "es": "Pago único a la firma", "en": "Single payment upon signing", "id": "Pembayaran tunggal pada saat penandatanganan", "fijo": true, "calculado": true, "resto": true}
  ],
  "unico_obra": [
    {"pct": "100", "monto": "", "timing": "", "es": "Pago único al inicio de obra", "en": "Single payment upon commencement of works", "id": "Pembayaran tunggal pada saat dimulainya pekerjaan", "fijo": true, "calculado": true, "resto": true}
  ]
}'
-- <<< presets
  ::jsonb) -> p_cal
$$;

-- Qué calendario es una tabla de hitos YA GUARDADA. Casa por %, y concepto en los tres idiomas, en orden.
create or replace function public.contrato_calendario_deduce(p_hitos jsonb) returns text
language plpgsql immutable set search_path = '' as $$
declare v_cal text; v_pre jsonb; i int; ok boolean;
begin
  if p_hitos is null or jsonb_typeof(p_hitos) <> 'array' or jsonb_array_length(p_hitos) = 0
     or not exists (select 1 from jsonb_array_elements(p_hitos) h where coalesce((h->>'fijo')::boolean, false)) then
    return 'libre';
  end if;
  foreach v_cal in array array['estandar', 'unico_firma', 'unico_obra'] loop
    v_pre := public.contrato_calendario_preset(v_cal);
    if jsonb_array_length(v_pre) = jsonb_array_length(p_hitos) then
      ok := true;
      for i in 0 .. jsonb_array_length(v_pre) - 1 loop
        if public.lw_importe(p_hitos->i->>'pct') is distinct from public.lw_importe(v_pre->i->>'pct')
           or coalesce(p_hitos->i->>'es', '') <> (v_pre->i->>'es')
           or coalesce(p_hitos->i->>'en', '') <> (v_pre->i->>'en')
           or coalesce(p_hitos->i->>'id', '') <> (v_pre->i->>'id')
           or not coalesce((p_hitos->i->>'fijo')::boolean, false) then
          ok := false; exit;
        end if;
      end loop;
      if ok then return v_cal; end if;
    end if;
  end loop;
  return 'manual';
end $$;

-- Una fecha 'YYYY-MM-DD' del formulario, o null si viene vacía. Un 2026-13-45 es un error legible aquí, no un
-- fallo del cast dentro del trigger de vencimientos.
create or replace function public.contrato_calendario_fecha(p_txt text, p_que text) returns date
language plpgsql immutable set search_path = '' as $$
begin
  if nullif(btrim(coalesce(p_txt, '')), '') is null then return null; end if;
  if p_txt !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception '% no es una fecha válida', p_que using errcode = '22007';
  end if;
  return p_txt::date;
exception when datetime_field_overflow or invalid_datetime_format then
  raise exception '% no es una fecha válida', p_que using errcode = '22007';
end $$;

-- La tabla de un calendario de fábrica, montada entera en el servidor. Del navegador solo se lee la fecha del
-- pago único (unico_firma) o su estimación (unico_obra); ningún importe, %, concepto ni marca.
create or replace function public.contrato_calendario_monta(p_cal text, p_precio numeric, p_hitos jsonb,
                                                            p_base date, p_admin boolean) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_pre  jsonb := public.contrato_calendario_preset(p_cal);
  v_out  jsonb := '[]'::jsonb;
  v_h    jsonb;
  v_rep  numeric := 0;
  v_imp  numeric;
  v_resto int := -1;
  v_fecha date;
  v_max  int;
  i int;
begin
  if v_pre is null then raise exception 'Calendario de pagos desconocido: %', p_cal using errcode = '22023'; end if;
  for i in 0 .. jsonb_array_length(v_pre) - 1 loop
    v_h := v_pre->i;
    if coalesce((v_h->>'resto')::boolean, false) then
      v_resto := i;
    elsif coalesce(p_precio, 0) > 0 then
      v_imp := round(p_precio * public.lw_importe(v_h->>'pct')) / 100;
      v_rep := v_rep + v_imp;
      if v_imp > 0 then v_h := v_h || jsonb_build_object('monto', public.lw_importe_texto(v_imp)); end if;
    end if;
    v_out := v_out || jsonb_build_array(v_h);
  end loop;
  if v_resto >= 0 and coalesce(p_precio, 0) > 0 then
    v_out := jsonb_set(v_out, array[v_resto::text, 'monto'],
                       to_jsonb(public.lw_importe_texto(greatest(0, p_precio - v_rep))));
  end if;

  if p_cal = 'unico_firma' then
    v_fecha := public.contrato_calendario_fecha(p_hitos->0->>'fecha', 'El vencimiento del pago único');
    if v_fecha is null then
      raise exception 'Pon la fecha de vencimiento del pago único.' using errcode = '23514';
    end if;
    if v_fecha < p_base then
      raise exception 'El pago único no puede vencer antes de la fecha de firma (%).', to_char(p_base, 'DD/MM/YYYY') using errcode = '23514';
    end if;
    v_max := public.parametro_num('construccion.pago_unico_max_dias', 90)::int;
    if not p_admin and v_fecha > p_base + v_max then
      raise exception 'El pago único vence como muy tarde % días después de la firma (%). Más allá lo decide un admin.',
        v_max, to_char(p_base + v_max, 'DD/MM/YYYY') using errcode = '23514';
    end if;
    v_out := jsonb_set(v_out, '{0,fecha}', to_jsonb(to_char(v_fecha, 'YYYY-MM-DD')));
  elsif p_cal = 'unico_obra' then
    v_fecha := public.contrato_calendario_fecha(p_hitos->0->>'fecha_estimada', 'La fecha estimada del pago único');
    if v_fecha is not null then
      if v_fecha < p_base then
        raise exception 'La fecha estimada del pago no puede ser anterior a la firma (%).', to_char(p_base, 'DD/MM/YYYY') using errcode = '23514';
      end if;
      v_out := jsonb_set(v_out, '{0,fecha_estimada}', to_jsonb(to_char(v_fecha, 'YYYY-MM-DD')));
    end if;
  end if;
  return v_out;
end $$;

-- Aplica el calendario a `datos` de un Contrato de Construcción antes de guardarlo. Solo la llama contrato_guarda.
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

  if p_old_datos is not null and v_cal is distinct from v_old_cal
     and exists (select 1 from public.contrato_vencimientos cv
                  where cv.contrato_id = p_contrato_id and (cv.ajustado or cv.factura_id is not null)) then
    raise exception 'Este contrato ya tiene pagos con fecha movida o facturados: no se puede cambiar de calendario. Habla con administración.'
      using errcode = '23514';
  end if;

  if v_cal in ('estandar', 'unico_firma', 'unico_obra') then
    v_hitos := public.contrato_calendario_monta(v_cal, p_precio, v_hitos, coalesce(p_fecha_firma, current_date), v_admin);
  elsif v_cal = 'manual' and not v_admin then
    -- conserva la tabla guardada; solo deja mover la fecha de cada hito, como hasta hoy
    if jsonb_array_length(v_hitos) <> jsonb_array_length(v_old_h) then
      raise exception 'Este calendario de pagos lo montó un admin: añadir o quitar hitos es cosa suya.' using errcode = '42501';
    end if;
    for i in 0 .. jsonb_array_length(v_old_h) - 1 loop
      v_old_h := jsonb_set(v_old_h, array[i::text, 'fecha'],
                           to_jsonb(coalesce(to_char(public.contrato_calendario_fecha(v_hitos->i->>'fecha', 'El vencimiento del hito ' || (i + 1)), 'YYYY-MM-DD'), '')));
    end loop;
    v_hitos := v_old_h;
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
    if exists (select 1 from jsonb_array_elements(v_hitos) h where public.lw_importe(h->>'monto') < 0) then
      raise exception 'Hay un hito con importe negativo.' using errcode = '23514';
    end if;
    for i in 0 .. jsonb_array_length(v_hitos) - 1 loop
      perform public.contrato_calendario_fecha(v_hitos->i->>'fecha', 'El vencimiento del hito ' || (i + 1));
    end loop;
  end if;

  return jsonb_set(
           p_datos || jsonb_build_object('calendario', v_cal, 'hitos', v_hitos),
           '{fields}',
           (coalesce(p_datos->'fields', '{}'::jsonb) - 'clausula_pago')
             || case when v_cal in ('unico_firma', 'unico_obra') then jsonb_build_object('clausula_pago', v_cal) else '{}'::jsonb end);
end $$;

revoke all on function public.contrato_calendario_preset(text) from public, anon, authenticated;
revoke all on function public.contrato_calendario_deduce(jsonb) from public, anon, authenticated;
revoke all on function public.contrato_calendario_fecha(text, text) from public, anon, authenticated;
revoke all on function public.contrato_calendario_monta(text, numeric, jsonb, date, boolean) from public, anon, authenticated;
revoke all on function public.contrato_calendario_aplica(jsonb, jsonb, numeric, date, uuid) from public, anon, authenticated;

-- contrato_guarda: igual que en 20260926230000, más la llamada a contrato_calendario_aplica en los dos caminos.
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
    -- calendario de pagos de Construcción: lo monta el servidor, sobre el precio que se va a guardar
    if v_tipo = 'construccion' then
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

-- obra_contratos_afectados: la elegibilidad sale del calendario guardado (`elegible` sin NULL: 20260928052357). Sin `calendario` (todo lo firmado
-- antes de hoy) se deduce con la regla de siempre: 5 hitos, todos de fábrica = estándar.
create or replace function public.obra_contratos_afectados(p_proyecto_id uuid, p_fase_masterplan text,
                                                           p_zona_masterplan text, p_fase_nueva text)
returns table (contrato_id uuid, numero text, elegible boolean, motivo text, orden_pago integer,
               vencimiento_id uuid, fecha_actual date)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_proyecto_nombre text;
  v_orden int;
begin
  select nombre into v_proyecto_nombre from public.proyectos where id = p_proyecto_id;
  if v_proyecto_nombre is null then
    raise exception 'Proyecto no encontrado';
  end if;
  if not (public.puede('obra') and public.puede_proyecto(v_proyecto_nombre)) then
    raise exception 'Sin permiso sobre este proyecto' using errcode = '42501';
  end if;
  if coalesce(p_fase_masterplan,'') = '' or coalesce(p_zona_masterplan,'') = '' then
    raise exception 'Fase y zona de masterplan son obligatorias';
  end if;

  select op.orden_pago into v_orden
    from public.obra_fase_orden_pago op where op.obra_fase_clave = p_fase_nueva;
  if v_orden is null then
    raise exception 'Fase de obra desconocida: %', p_fase_nueva;
  end if;

  return query
  with base as (
    select
      c.id, c.numero, cv.id as venc_id, cv.ajustado, cv.factura_id, cv.fecha,
      jsonb_array_length(coalesce(c.datos->'hitos','[]'::jsonb)) as n_hitos,
      (select bool_and(coalesce((h->>'fijo')::boolean,false))
         from jsonb_array_elements(coalesce(c.datos->'hitos','[]'::jsonb)) h) as todos_fijos,
      (select bool_or(coalesce((h->>'fijo')::boolean,false))
         from jsonb_array_elements(coalesce(c.datos->'hitos','[]'::jsonb)) h) as algun_fijo,
      nullif(c.datos->>'calendario', '') as cal
    from public.contratos c
    join public.unidades u on u.id = c.unidad_id
     and u.proyecto_id = p_proyecto_id
     and u.fase_masterplan = p_fase_masterplan
     and u.zona_masterplan = p_zona_masterplan
    left join public.contrato_vencimientos cv on cv.contrato_id = c.id and cv.orden = v_orden
    where c.tipo = 'construccion' and c.bloqueado = true
  ), clase as (
    select b.*,
      coalesce(b.cal, case when b.n_hitos = 5 and coalesce(b.todos_fijos,false) then 'estandar' end) as calendario,
      (b.venc_id is not null and not b.ajustado and b.factura_id is null) as libre_para_fijar
    from base b
  )
  select
    k.id,
    k.numero,
    (k.libre_para_fijar
      and ((k.calendario = 'estandar' and k.n_hitos = 5 and coalesce(k.todos_fijos,false))
           or (k.calendario = 'unico_obra' and v_orden = 1))) as elegible,
    (case
      when k.calendario = 'unico_firma' then 'pago_unico_firma'
      when k.calendario = 'unico_obra' and v_orden <> 1 then 'pago_unico_ya_al_inicio'
      when k.calendario = 'unico_obra' or (k.calendario = 'estandar' and k.n_hitos = 5 and coalesce(k.todos_fijos,false)) then
        case
          when k.venc_id is null then 'sin_vencimiento_en_ese_orden'
          when k.ajustado then 'ajustado_a_mano'
          when k.factura_id is not null then 'ya_facturado'
          else null
        end
      -- Sin ningún hito `fijo`: contrato anterior al calendario de fábrica del 16-sep. No es un calendario
      -- «a medida», es que se firmó antes.
      when k.n_hitos > 0 and not coalesce(k.algun_fijo,false) then 'anterior_al_mecanismo'
      else 'calendario_manual'
    end) as motivo,
    v_orden,
    k.venc_id,
    k.fecha
  from clase k;
end $$;
revoke all on function public.obra_contratos_afectados(uuid,text,text,text) from public, anon;
grant execute on function public.obra_contratos_afectados(uuid,text,text,text) to authenticated;

-- obra_confirmar_avance: sin plazo pasado ni configurado, 14 días. No es un plazo inventado: es el del propio
-- contrato (Art. 5: «dentro de los catorce (14) días naturales siguientes a la recepción de dicha notificación»),
-- y ningún proyecto tenía plazo configurado el 28-sep, así que cada parte lo tecleaba a mano.
create or replace function public.obra_confirmar_avance(p_proyecto_id uuid, p_fase_masterplan text, p_zona_masterplan text,
                                                        p_fase_nueva text, p_dias integer, p_nota text,
                                                        p_contratos_esperados uuid[])
returns table (contrato_id uuid, numero text, fecha_vencimiento date)
language plpgsql security definer set search_path = '' as $$
declare
  v_proyecto_nombre text;
  v_estado text;
  v_orden_pago int;
  v_dias int;
  v_fase_actual text;
  v_orden_actual int;
  v_orden_nuevo int;
  v_contratos uuid[];
  v_esperados uuid[];
  v_autor text;
  v_dia date;
  v_usadas int;
  r record;
begin
  select nombre, estado into v_proyecto_nombre, v_estado
    from public.proyectos where id = p_proyecto_id;
  if v_proyecto_nombre is null then
    raise exception 'Proyecto no encontrado';
  end if;
  if not (public.puede('obra') and public.puede_proyecto(v_proyecto_nombre)) then
    raise exception 'Sin permiso sobre este proyecto' using errcode = '42501';
  end if;
  if v_estado <> 'en_construccion' then
    raise exception 'El proyecto no esta en construccion todavia (estado actual: %)', v_estado;
  end if;
  if coalesce(p_fase_masterplan,'') = '' or coalesce(p_zona_masterplan,'') = '' then
    raise exception 'Fase y zona de masterplan son obligatorias';
  end if;

  select op.orden_pago into v_orden_pago
    from public.obra_fase_orden_pago op where op.obra_fase_clave = p_fase_nueva;
  if v_orden_pago is null then
    raise exception 'Fase de obra desconocida: %', p_fase_nueva;
  end if;

  -- El plazo: el que se pase explicitamente manda; si no, el configurado en la ficha del proyecto para ese
  -- pago; si tampoco, los 14 días del Art. 5 del contrato.
  v_dias := p_dias;
  if v_dias is null then
    select dias into v_dias
      from public.proyecto_plazo_pago
     where proyecto_id = p_proyecto_id and orden_pago = v_orden_pago;
  end if;
  v_dias := coalesce(v_dias, 14);
  if v_dias < 0 then
    raise exception 'El desfase en dias no puede ser negativo';
  end if;
  if v_dias > 365 then
    raise exception 'El desfase en dias (%) supera el tope de 365 -- si de verdad hace falta ir mas lejos, confirmalo aparte', v_dias;
  end if;

  select obra_fase_actual into v_fase_actual
    from public.obra_progreso_fase_zona
   where proyecto_id = p_proyecto_id and fase_masterplan = p_fase_masterplan
     and zona_masterplan = p_zona_masterplan;

  if v_fase_actual is not distinct from p_fase_nueva then
    return; -- idempotente: ya esta en esa fase
  end if;

  if v_fase_actual is null then
    if p_fase_nueva <> 'preparacion' then
      raise exception 'Una fase-zona nueva solo puede arrancar en preparacion, no en %', p_fase_nueva;
    end if;
  else
    select orden into v_orden_actual from public.obra_fases where clave = v_fase_actual;
    select orden into v_orden_nuevo from public.obra_fases where clave = p_fase_nueva;
    if v_orden_nuevo is distinct from v_orden_actual + 1 then
      raise exception 'Solo se puede avanzar un paso de obra cada vez (actual: % [orden %]; pedido: % [orden %])',
        v_fase_actual, v_orden_actual, p_fase_nueva, v_orden_nuevo;
    end if;
  end if;

  select coalesce(array_agg(contrato_id order by contrato_id), '{}'::uuid[]) into v_contratos
    from public.obra_contratos_afectados(p_proyecto_id, p_fase_masterplan, p_zona_masterplan, p_fase_nueva)
   where elegible;

  select coalesce(array_agg(x order by x), '{}'::uuid[]) into v_esperados
    from unnest(coalesce(p_contratos_esperados, '{}'::uuid[])) x;

  if v_contratos <> v_esperados then
    raise exception 'La lista de contratos afectados cambio desde la vista previa -- vuelve a comprobarla antes de confirmar' using errcode = '40001';
  end if;

  v_autor := (select auth.email());

  insert into public.obra_partes_trabajo
    (proyecto_id, fase_masterplan, zona_masterplan, fase_anterior, fase_nueva, autor, nota, dias_offset)
  values (p_proyecto_id, p_fase_masterplan, p_zona_masterplan, v_fase_actual, p_fase_nueva, v_autor, p_nota, v_dias);

  insert into public.obra_progreso_fase_zona
    (proyecto_id, fase_masterplan, zona_masterplan, obra_fase_actual, actualizado_por)
  values (p_proyecto_id, p_fase_masterplan, p_zona_masterplan, p_fase_nueva, v_autor)
  on conflict (proyecto_id, fase_masterplan, zona_masterplan)
  do update set obra_fase_actual = excluded.obra_fase_actual,
                actualizado_en = now(),
                actualizado_por = excluded.actualizado_por;

  for r in
    select c.id as contrato_id, c.numero, a.vencimiento_id
    from public.obra_contratos_afectados(p_proyecto_id, p_fase_masterplan, p_zona_masterplan, p_fase_nueva) a
    join public.contratos c on c.id = a.contrato_id
    where a.elegible
    order by c.numero
  loop
    v_dia := current_date + v_dias;
    loop
      select count(*) into v_usadas
        from public.contrato_vencimientos cv2
       where cv2.fecha = v_dia and cv2.factura_id is null;
      exit when v_usadas < 8;
      v_dia := v_dia + 1;
    end loop;

    update public.contrato_vencimientos
       set fecha = v_dia,
           ajustado = true,
           origen = 'obra'
     where id = r.vencimiento_id;

    contrato_id := r.contrato_id;
    numero := r.numero;
    fecha_vencimiento := v_dia;
    return next;
  end loop;
end $$;
revoke all on function public.obra_confirmar_avance(uuid,text,text,text,int,text,uuid[]) from public, anon;
grant execute on function public.obra_confirmar_avance(uuid,text,text,text,int,text,uuid[]) to authenticated;
