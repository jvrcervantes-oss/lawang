-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68); el maestro recibe estas gemelas en su propia subtarea (LAW-428 2M)
-- LA INTRANET PREGUNTA POR EL ID DEL PROYECTO, NUNCA POR SU NOMBRE — 15-oct-2026, LAW-428 fase 2, tanda B (sesión proyecto-por-id).
-- Encargo: encargos/20260929_lawang_proyecto_por_id.md. Revisión previa #152 (29-sep) y #381 (15-oct, Backend + Seguridad).
-- Cuerpos GENERADOS desde pg_get_functiondef de la viva del 15-oct con reemplazos literales y recuento exacto (gen_2b.py de la sesión):
-- todo lo que no se nombra abajo es byte a byte lo de hoy.
--
-- NUEVAS (las viejas no se tocan: las sigue llamando la intranet publicada hasta la fase 3 y mueren en la fase 4):
--   · borrar_proyecto_por_id(uuid): la de borrar_proyecto(text) con el proyecto por id. Mismo listón (super admin de la empresa DEL
--     PROYECTO), mismas comprobaciones de lo que cuelga (por espejo de nombre O por id, el nombre leído de la fila: falla cerrado si
--     el espejo se desalinea) y el mismo apunte en proyectos_borrados. Id inexistente: solo un super global pasa el listón y recibe
--     «no existe»; el resto, 42501 (no revela si existe).
--   · proyecto_vinculos_datos_por_id(uuid): el recuento previo a renombrar y a borrar. La vieja solo miraba la sesión (Seguridad #381:
--     cualquier usuario del equipo, también el portal, contaba lo de cualquier proyecto); la gemela exige admin de la empresa del
--     proyecto, el listón de renombrar (borrar ya exige más). Dueño lw_lector, como la vieja.
--   · renombrar_proyecto_por_id(uuid, text): la de renombrar_proyecto(p_antiguo, p_nuevo), que se escapaba del chequeo 7.x porque su
--     argumento no se llama p_nombre. El proyecto por id; el resto (contratos y facturas sin firmar ni enviar), igual.
--   · parcela_traspaso_estado_por_unidad(uuid, text[]): la parcela por SU id (el formulario de contratos no tiene a mano el id del
--     proyecto, contracts/app.html:2343; la unidad sí lo tiene). Mismo permiso (agente con contratos que ve el proyecto o su manager)
--     y la misma respuesta (número + estado, ningún dato personal).
--   · privado.carta_cobrado_calcula_por_id(uuid, jsonb, uuid): el abono de la Carta en un Bloqueo, cruzando las parcelas por proyecto_id.
--     En `privado` (la API no lo expone) y sin grant: solo lo llaman el disparador y el recálculo, DEFINER de postgres.
--     Medido el 15-oct en solo lectura: en los 140 Bloqueos, las unidades casadas por nombre (hoy) y por id (gemela) son las mismas
--     (0 distintos, 0 sin proyecto). Cambio declarado: hoy manda datos.fields.proyecto_nombre (lo escribe el navegador) sobre la
--     columna; ahora manda la columna (máxima 3). 1 de 140 difiere en el nombre (RP00024) y no tiene Cartas: ningún importe cambia.
-- RECABLEADAS: carta_cobrado_al_bloquear (trigger del alta de Bloqueo) y carta_cobrado_recalcula → carta_cobrado_calcula_por_id;
--   obra_contratos_afectados y obra_datos_cobro → puede_proyecto_id(p_proyecto_id) (ya recibían el id y buscaban su nombre para
--   preguntar por nombre; puede_proyecto_id = la misma regla, proyecto_visible); proyecto_guarda pierde la rama del slug (revisor
--   29-sep: el candado trg_proyecto_slug lo rechazaba siempre): ahora lo dice antes de tocar nada.
-- NO TOCA: las policies «documentacion: leer» y «modelos: leer» (llaman a puede_proyecto(text,uuid), que ya va primero por id;
--   cambiarlas es un drop policy, que para con el owner); agente_ve_documento_proyecto y documento_proyecto_borra (idem);
--   unidad_guarda / unidades_importa (_unidad_proyecto recibe el nombre tecleado en el CSV: alta por nombre, a propósito).
-- SIN SERIES: nada de esto da de alta en una tabla con numeración.
-- VUELTA ATRÁS: supabase/reversion_proyecto_por_id/REVERSION.sql (cuerpos vivos del 15-oct con su md5 y drop de las 5 nuevas).

set local lock_timeout = '5s';

-- ── nuevas (gemelas por id) ──
CREATE OR REPLACE FUNCTION public.borrar_proyecto_por_id(p_proyecto_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid := p_proyecto_id; v_nombre text; v_empresa text;
  v_unidades int; v_modelos int; v_documentos int; v_resort text;
  v_contratos text; v_facturas text; v_condiciones int; v_obra int;
begin
  select pr.nombre, pr.empresa into v_nombre, v_empresa from public.proyectos pr where pr.id = p_proyecto_id;
  if not public.es_super_admin_de(v_empresa) then
    raise exception 'solo un super_admin puede borrar un proyecto' using errcode = '42501';
  end if;

  select resort into v_resort from public.proyectos where id = p_proyecto_id;
  if v_nombre is null then
    raise exception 'no existe ese proyecto' using errcode = '23503';
  end if;

  select count(*) into v_unidades from public.unidades where proyecto = v_nombre or proyecto_id = v_id;
  if v_unidades > 0 then
    raise exception 'el proyecto tiene % unidad(es) dadas de alta — bórralas o muévelas primero', v_unidades using errcode = '23503';
  end if;

  select count(*) into v_modelos from public.modelos_villa where proyecto = v_nombre or proyecto_id = v_id;
  if v_modelos > 0 then
    raise exception 'el proyecto tiene % modelo(s) de villa — bórralos primero', v_modelos using errcode = '23503';
  end if;

  select count(*) into v_documentos from public.documentos_proyecto where proyecto = v_nombre or proyecto_id = v_id;
  if v_documentos > 0 then
    raise exception 'el proyecto tiene % documento(s) subido(s) — bórralos primero', v_documentos using errcode = '23503';
  end if;

  select string_agg(c.numero, ', ' order by c.numero) into v_contratos
    from public.contratos c where c.proyecto_id = v_id;
  if v_contratos is not null then
    raise exception 'el proyecto tiene contratos (%) — un proyecto con contratos no se borra, se marca como cerrado', v_contratos using errcode = '23503';
  end if;

  select string_agg(coalesce(f.numero, 'sin nº'), ', ' order by f.numero) into v_facturas
    from public.facturas f where f.proyecto_id = v_id;
  if v_facturas is not null then
    raise exception 'el proyecto tiene documentos de facturación (%) — no se borra un proyecto con facturas', v_facturas using errcode = '23503';
  end if;

  select count(*) into v_condiciones from public.condiciones_comision cc where cc.proyecto_id = v_id;
  if v_condiciones > 0 then
    raise exception 'el proyecto tiene % condición(es) de comisión — bórralas desde Comisiones primero', v_condiciones using errcode = '23503';
  end if;

  select (select count(*) from public.obra_partes_trabajo o where o.proyecto_id = v_id)
       + (select count(*) from public.obra_progreso_fase_zona o where o.proyecto_id = v_id)
    into v_obra;
  if v_obra > 0 then
    raise exception 'el proyecto tiene % registro(s) de obra (partes o avance) — no se borra un proyecto con obra', v_obra using errcode = '23503';
  end if;

  insert into public.proyectos_borrados (nombre, resort, borrado_por)
  values (v_nombre, v_resort, coalesce((select auth.email()), (select auth.uid())::text));

  delete from public.proyectos where id = v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.proyecto_vinculos_datos_por_id(p_proyecto_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid := p_proyecto_id; v_nombre text;
begin
  if public.uid_sesion() is null then
    raise exception 'proyecto_vinculos_datos_por_id: sin sesión' using errcode = '42501';
  end if;
  if p_proyecto_id is null then
    raise exception 'proyecto_vinculos_datos_por_id: falta el proyecto' using errcode = '22023';
  end if;
  -- Seguridad #381: la vieja solo miraba la sesión. Lo pide la ficha del proyecto para renombrar (admin) y para borrar (super):
  -- el mismo listón que renombrar_proyecto_por_id, el más bajo de los dos.
  if not public.es_admin_de(public.empresa_de_proyecto(p_proyecto_id)) then
    raise exception 'proyecto_vinculos_datos_por_id: sin permiso sobre este proyecto' using errcode = '42501';
  end if;
  select p.nombre into v_nombre from public.proyectos p where p.id = p_proyecto_id;
  -- mismo criterio que borrar_proyecto (nombre O id): el aviso previo tiene que coincidir con quien decide
  return jsonb_build_object(
    'unidades',      (select count(*) from public.unidades u
                       where u.proyecto = v_nombre or (v_id is not null and u.proyecto_id = v_id)),
    'modelos_villa', (select count(*) from public.modelos_villa m
                       where m.proyecto = v_nombre or (v_id is not null and m.proyecto_id = v_id)),
    'documentos',    (select count(*) from public.documentos_proyecto d
                       where d.proyecto = v_nombre or (v_id is not null and d.proyecto_id = v_id)));
end $function$;

CREATE OR REPLACE FUNCTION public.renombrar_proyecto_por_id(p_proyecto_id uuid, p_nuevo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_antiguo text;
  v_unidades int; v_contratos int; v_facturas int; v_documentos int; v_modelos int;
begin
  select pr.nombre into v_antiguo from public.proyectos pr where pr.id = p_proyecto_id;
  if not public.es_admin_de(public.empresa_de_proyecto(p_proyecto_id)) then
    raise exception 'Solo un administrador puede renombrar un proyecto' using errcode = '42501';
  end if;
  if v_antiguo is null then raise exception 'Ese proyecto no existe' using errcode = 'P0002'; end if;
  if v_antiguo is null or trim(v_antiguo) = '' or p_nuevo is null or trim(p_nuevo) = '' then
    raise exception 'Nombre de proyecto vacío';
  end if;
  if v_antiguo = p_nuevo then
    return jsonb_build_object('sin_cambios', true);
  end if;
  if length(btrim(p_nuevo)) > 120 then raise exception 'El nombre no puede pasar de 120 caracteres' using errcode = '22023'; end if;
  if btrim(p_nuevo) ~ '^[=+\-@]' then raise exception 'El nombre no puede empezar por = + - @' using errcode = '22023'; end if;
  if exists (select 1 from public.proyectos where nombre = p_nuevo) then
    raise exception 'Ya existe un proyecto llamado "%"', p_nuevo;
  end if;

  update public.proyectos set nombre = p_nuevo where id = p_proyecto_id;

  update public.unidades set proyecto = p_nuevo where proyecto = v_antiguo;
  get diagnostics v_unidades = row_count;

  update public.contratos set proyecto_nombre = p_nuevo where proyecto_nombre = v_antiguo;
  get diagnostics v_contratos = row_count;
  update public.contratos c
     set datos = jsonb_set(datos, '{fields,proyecto_nombre}', to_jsonb(p_nuevo))
   where proyecto_nombre = p_nuevo and bloqueado = false
     and datos #>> '{fields,proyecto_nombre}' = v_antiguo
     and not exists (select 1 from public.contrato_firmas cf where cf.contrato_id = c.id);

  update public.facturas set proyecto_nombre = p_nuevo where proyecto_nombre = v_antiguo;
  get diagnostics v_facturas = row_count;
  update public.facturas
     set datos = jsonb_set(datos, '{fields,proyecto_nombre}', to_jsonb(p_nuevo))
   where proyecto_nombre = p_nuevo and not anulada and not enviada
     and datos #>> '{fields,proyecto_nombre}' = v_antiguo;

  update public.documentos_proyecto set proyecto = p_nuevo where proyecto = v_antiguo;
  get diagnostics v_documentos = row_count;

  update public.modelos_villa set proyecto = p_nuevo where proyecto = v_antiguo;
  get diagnostics v_modelos = row_count;

  return jsonb_build_object(
    'unidades', v_unidades, 'contratos', v_contratos, 'facturas', v_facturas,
    'documentos_proyecto', v_documentos, 'modelos_villa', v_modelos
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.parcela_traspaso_estado_por_unidad(p_unidad_id uuid, p_ids text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_proy_id uuid;
  v_ids     text[];
  v_numero  text;
  v_tipo    text;
  v_ocupa   text[];
begin
  if (select auth.uid()) is null then
    raise exception 'parcela_traspaso_estado_por_unidad: sin sesión';
  end if;
  select u.proyecto_id into v_proy_id from public.unidades u where u.id = p_unidad_id;
  if not (public.es_agente() and public.puede('contratos')
          and (public.puede_proyecto_id(v_proy_id) or public.es_manager_de(v_proy_id))) then
    raise exception 'parcela_traspaso_estado_por_unidad: sin permiso sobre este proyecto';
  end if;

  select coalesce(array_agg(distinct lower(btrim(x))), '{}') into v_ids
    from unnest((coalesce(p_ids, '{}'::text[]))[1:20]) x
   where nullif(btrim(x), '') is not null;

  select c.numero, c.tipo, public.contrato_identificadores(c.datos)
    into v_numero, v_tipo, v_ocupa
    from public.unidades u join public.contratos c on c.id = u.contrato_id
   where u.id = p_unidad_id
     and c.liberado_en is null;

  if v_tipo is null or v_tipo not like 'carta_reserva%' then
    return null;
  end if;
  return jsonb_build_object(
    'numero', v_numero,
    'estado', public.traspaso_carta_estado('reserva_parcela', v_ids, v_tipo, v_ocupa));
end;
$function$;

CREATE OR REPLACE FUNCTION privado.carta_cobrado_calcula_por_id(p_id uuid, p_datos jsonb, p_proyecto_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  datos jsonb := p_datos;
  cods text[] := (
    select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
      from unnest(string_to_array(coalesce(p_datos->'fields'->>'parcela_codigo',''), ',')) x);
  moneda_bloqueo text := coalesce(nullif(btrim(p_datos->'fields'->>'moneda'), ''), 'EUR');
  ids_yo text[] := public.contrato_identificadores(p_datos);
  cartas_ids        uuid[];
  cartas_nums        text[];
  v_disponibles      numeric[] := '{}';
  v_nums_aportantes  text[] := '{}';
  v_cobrado          numeric := 0;
  v_precio_total     numeric;
  v_descuento        numeric;
  v_sobrante         numeric;
  v_restante         numeric;
  v_detalle          jsonb := '[]'::jsonb;
  v_disp             numeric;
  v_ya               numeric;
  v_claim            numeric;
  i                  int;
begin
  datos := datos #- '{fields,carta_cobrado_importe}'
                 #- '{fields,carta_cobrado_numeros}'
                 #- '{fields,carta_cobrado_sobrante}'
                 #- '{fields,carta_cobrado_detalle}';
  datos := public.carta_cobrado_aplica_hitos(datos, 'insert');

  if p_proyecto_id is null then
    return datos;
  end if;

  select array_agg(x.id order by x.misma desc, x.numero), array_agg(x.numero order by x.misma desc, x.numero)
    into cartas_ids, cartas_nums
    from (select y.id, y.numero, bool_or(y.misma) as misma from (
      -- la Carta que ocupa hoy la parcela (traspaso Carta -> Bloqueo, 17-sep)
      select distinct c.id, c.numero, true as misma
        from public.unidades u
        join public.contratos c on c.id = u.contrato_id
       where u.proyecto_id = p_proyecto_id and u.codigo = any(cods)
         and c.tipo like 'carta_reserva%'
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
      union
      -- la Carta ya colgada de este Bloqueo (traspaso posterior al alta, 23-sep)
      select c.id, c.numero, true
        from public.contratos c
       where c.contrato_padre_id = p_id
         and c.tipo like 'carta_reserva%'
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
      union
      -- la Carta LIBERADA del mismo comprador (22-sep): retenida e imputable
      select c.id, c.numero, false
        from public.contratos c
       where c.tipo like 'carta_reserva%'
         and c.liberado_en is not null
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
         and coalesce(array_length(ids_yo, 1), 0) > 0
         and public.contrato_identificadores(c.datos) && ids_yo
    ) y group by y.id, y.numero) x;

  if coalesce(array_length(cartas_ids, 1), 0) = 0 then
    return datos;
  end if;

  for i in 1 .. array_length(cartas_ids, 1) loop
    perform pg_advisory_xact_lock(hashtext(cartas_ids[i]::text));
    v_ya := coalesce((
      select sum(importe) from public.carta_cobrado_aplicado
       where carta_id = cartas_ids[i] and contrato_id <> p_id
    ), 0);
    v_disp := greatest(coalesce(public.contrato_cobrado(cartas_ids[i]), 0) - v_ya, 0);
    v_disponibles := v_disponibles || v_disp;
    v_cobrado := v_cobrado + v_disp;
  end loop;

  if v_cobrado <= 0 then
    return datos;
  end if;

  v_precio_total := greatest(coalesce(public.lw_importe(datos->'fields'->>'precio_total'), 0), 0);
  v_descuento := least(v_cobrado, v_precio_total);
  v_sobrante  := greatest(v_cobrado - v_precio_total, 0);

  if v_descuento > 0 then
    v_restante := v_descuento;
    for i in 1 .. array_length(cartas_ids, 1) loop
      exit when v_restante <= 0;
      v_disp := v_disponibles[i];
      if v_disp > 0 then
        v_claim := least(v_disp, v_restante);
        v_detalle := v_detalle || jsonb_build_object(
          'carta_id', cartas_ids[i],
          'numero', cartas_nums[i],
          'importe', public.lw_importe_texto(v_claim));
        v_nums_aportantes := v_nums_aportantes || cartas_nums[i];
        v_restante := v_restante - v_claim;
      end if;
    end loop;

    datos := jsonb_set(datos, '{fields,carta_cobrado_importe}', to_jsonb(public.lw_importe_texto(v_descuento)), true);
    datos := jsonb_set(datos, '{fields,carta_cobrado_numeros}', to_jsonb(array_to_string(v_nums_aportantes, ', ')), true);
    datos := jsonb_set(datos, '{fields,carta_cobrado_detalle}', v_detalle, true);

    insert into public.carta_cobrado_aplicado (contrato_id, carta_id, importe)
    select p_id, (elem->>'carta_id')::uuid, public.lw_importe(elem->>'importe')
      from jsonb_array_elements(v_detalle) elem
    on conflict (contrato_id, carta_id) do nothing;
  end if;

  if v_sobrante > 0 then
    datos := jsonb_set(datos, '{fields,carta_cobrado_sobrante}', to_jsonb(public.lw_importe_texto(v_sobrante)), true);
  end if;

  datos := public.carta_cobrado_aplica_hitos(datos, 'insert');
  return datos;
end;
$function$;

do $g$
declare f text;
begin
  foreach f in array array['public.borrar_proyecto_por_id(uuid)', 'public.proyecto_vinculos_datos_por_id(uuid)',
                           'public.renombrar_proyecto_por_id(uuid, text)', 'public.parcela_traspaso_estado_por_unidad(uuid, text[])',
                           'privado.carta_cobrado_calcula_por_id(uuid, jsonb, uuid)'] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
  -- la llama la intranet con la sesión de quien está dentro (editores.js, parcela_inventario.js); calcula: solo DEFINER internos
  foreach f in array array['public.borrar_proyecto_por_id(uuid)', 'public.proyecto_vinculos_datos_por_id(uuid)',
                           'public.renombrar_proyecto_por_id(uuid, text)', 'public.parcela_traspaso_estado_por_unidad(uuid, text[])'] loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $g$;
-- proyecto_vinculos_datos_por_id: dueño lw_lector, como su vieja (patrón LAW-338; mismo baile que 20261015075011)
grant create on schema public to lw_lector;
alter function public.proyecto_vinculos_datos_por_id(uuid) owner to lw_lector;
revoke create on schema public from lw_lector;
revoke all on function public.proyecto_vinculos_datos_por_id(uuid) from public, anon, service_role;
grant execute on function public.proyecto_vinculos_datos_por_id(uuid) to authenticated;

-- ── recableadas (create or replace conserva dueño y permisos) ──
CREATE OR REPLACE FUNCTION public.carta_cobrado_al_bloquear()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_proyecto_id uuid;
begin
  if tg_op <> 'INSERT' or new.tipo <> 'reserva_parcela' then
    return new;
  end if;
  -- LAW-428: por id. Este disparador va ANTES que trg_espejo_proyecto (orden alfabético de los BEFORE), que es quien pone
  -- new.proyecto_id cuando contrato_guarda no lo trae: se resuelve aquí con la misma regla (_contrato_proyecto_de). El proyecto
  -- sale de las columnas del contrato, nunca de datos.fields (lo escribe el navegador). Sin proyecto no se calcula a ciegas:
  -- se para (antes devolvía el Bloqueo sin abono, en silencio; medido el 15-oct: 0 de 140 Bloqueos sin proyecto).
  v_proyecto_id := public._contrato_proyecto_de(new.proyecto_id, new.proyecto_nombre);
  if v_proyecto_id is null then
    raise exception 'Un Bloqueo de Parcela necesita su proyecto' using errcode = '23502';
  end if;
  new.datos := privado.carta_cobrado_calcula_por_id(new.id, new.datos, v_proyecto_id);
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.carta_cobrado_recalcula(p_contrato_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  c public.contratos%rowtype;
  v_datos jsonb;
begin
  if not public.es_admin_de(public.empresa_de_contrato(p_contrato_id)) then
    raise exception 'Recalcular el abono de la Carta exige admin.' using errcode = '42501';
  end if;
  select * into c from public.contratos where id = p_contrato_id;
  if c.id is null then raise exception 'Contrato no encontrado.' using errcode = 'P0002'; end if;
  if c.tipo <> 'reserva_parcela' then
    raise exception 'Solo se recalcula en un Bloqueo de Parcela.' using errcode = '22023';
  end if;
  if coalesce(c.bloqueado, false) or public.contrato_firma_viva(c.id) then
    raise exception 'El contrato está firmado o en firma: el abono impreso no se toca.' using errcode = '23514';
  end if;
  -- lo reclamado por este Bloqueo se suelta y se vuelve a calcular desde cero
  delete from public.carta_cobrado_aplicado where contrato_id = p_contrato_id;
  v_datos := privado.carta_cobrado_calcula_por_id(c.id, c.datos, public._contrato_proyecto_de(c.proyecto_id, c.proyecto_nombre));
  perform set_config('app.via_carta_cobrado_recalcula', 'on', true);
  update public.contratos set datos = v_datos where id = p_contrato_id;
  insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
  values (p_contrato_id, 'editado',
          jsonb_build_object('accion', 'carta_cobrado_recalculado',
                             'importe', v_datos->'fields'->>'carta_cobrado_importe',
                             'numeros', v_datos->'fields'->>'carta_cobrado_numeros'),
          coalesce(public._quien_actua(), (select auth.uid())::text));
  return jsonb_build_object('carta_cobrado_importe', v_datos->'fields'->>'carta_cobrado_importe',
                            'carta_cobrado_numeros', v_datos->'fields'->>'carta_cobrado_numeros',
                            'carta_cobrado_sobrante', v_datos->'fields'->>'carta_cobrado_sobrante');
end $function$;

CREATE OR REPLACE FUNCTION public.obra_contratos_afectados(p_proyecto_id uuid, p_fase_masterplan text, p_zona_masterplan text, p_fase_nueva text)
 RETURNS TABLE(contrato_id uuid, numero text, elegible boolean, motivo text, orden_pago integer, vencimiento_id uuid, fecha_actual date)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_proyecto_nombre text;
  v_orden int;
begin
  select nombre into v_proyecto_nombre from public.proyectos where id = p_proyecto_id;
  if v_proyecto_nombre is null then
    raise exception 'Proyecto no encontrado';
  end if;
  if not (public._puede_herr_o_super_empresa('obra') and public.puede_proyecto_id(p_proyecto_id)) then
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
    coalesce(k.libre_para_fijar
      and ((k.calendario = 'estandar' and k.n_hitos = 5 and coalesce(k.todos_fijos,false))
           or (k.calendario = 'unico_obra' and v_orden = 1)), false) as elegible,
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
      when k.n_hitos > 0 and not coalesce(k.algun_fijo,false) then 'anterior_al_mecanismo'
      else 'calendario_manual'
    end) as motivo,
    v_orden,
    k.venc_id,
    k.fecha
  from clase k;
end $function$;

CREATE OR REPLACE FUNCTION public.obra_datos_cobro(p_proyecto_id uuid, p_fase_masterplan text, p_zona_masterplan text, p_fase_nueva text)
 RETURNS TABLE(contrato_id uuid, numero text, moneda text, precio_total numeric, cobrado numeric, vencimientos jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_proyecto_nombre text;
begin
  select nombre into v_proyecto_nombre from public.proyectos where id = p_proyecto_id;
  if v_proyecto_nombre is null then
    raise exception 'Proyecto no encontrado';
  end if;
  -- Mismo gate, palabra por palabra, que obra_contratos_afectados().
  if not (public._puede_herr_o_super_empresa('obra') and public.puede_proyecto_id(p_proyecto_id)) then
    raise exception 'Sin permiso sobre este proyecto' using errcode = '42501';
  end if;

  return query
  select
    c.id,
    c.numero,
    c.moneda,
    c.precio_total,
    -- Lo cobrado de esta Construcción contando su venta: primero la parcela, luego la obra (owner, 14-oct-2026).
    -- La puerta de arriba es por proyecto y ninguna venta tiene contratos en dos proyectos (Seguridad, 14-oct).
    public._contrato_cobrado_venta(c.id),
    coalesce((
      select jsonb_agg(jsonb_build_object('orden', cv.orden, 'pct', cv.pct,
                                          'monto', cv.monto, 'fecha', cv.fecha)
                       order by cv.orden)
        from public.contrato_vencimientos cv where cv.contrato_id = c.id
    ), '[]'::jsonb)
  from public.contratos c
  join public.unidades u on u.id = c.unidad_id
   and u.proyecto_id = p_proyecto_id
   and u.fase_masterplan = p_fase_masterplan
   and u.zona_masterplan = p_zona_masterplan
  where c.tipo = 'construccion' and c.bloqueado = true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.proyecto_guarda(p_id uuid, p_cambios jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old public.proyectos%rowtype; v_fecha date; v_pct numeric;
begin
  if not public.es_admin_de(public.empresa_de_proyecto(p_id)) then raise exception 'La ficha del proyecto la edita un administrador' using errcode = '42501'; end if;
  select * into v_old from public.proyectos p where p.id = p_id for update;
  if not found then raise exception 'Ese proyecto no existe' using errcode = 'P0002'; end if;
  begin
    v_fecha := case when p_cambios ? 'fecha_entrega_estimada_proyecto' then nullif(p_cambios->>'fecha_entrega_estimada_proyecto', '')::date end;
    v_pct := case when p_cambios ? 'pct_minimo_inicio' then (p_cambios->>'pct_minimo_inicio')::numeric end;
  exception when others then raise exception 'Revisa la fecha y el porcentaje' using errcode = '22023';
  end;
  if p_cambios ? 'pct_minimo_inicio' and (v_pct is null or v_pct < 0 or v_pct > 100) then
    raise exception 'El porcentaje mínimo va de 0 a 100' using errcode = '22023';
  end if;
  -- LAW-428: el slug es el id público del proyecto y no se cambia (candado trg_proyecto_slug desde la fase 1); se dice aquí,
  -- antes de tocar nada, en vez de validar un cambio que el candado iba a rechazar igual.
  if p_cambios ? 'slug' and (p_cambios->>'slug') is distinct from v_old.slug then
    raise exception 'El slug es el identificador público del proyecto y no se cambia' using errcode = '22023';
  end if;
  update public.proyectos p
     set resort = case when p_cambios ? 'resort' then nullif(btrim(coalesce(p_cambios->>'resort', '')), '') else p.resort end,
         parcela_master = case when p_cambios ? 'parcela_master' then nullif(btrim(coalesce(p_cambios->>'parcela_master', '')), '') else p.parcela_master end,
         ubicacion_maps = case when p_cambios ? 'ubicacion_maps' then nullif(btrim(coalesce(p_cambios->>'ubicacion_maps', '')), '') else p.ubicacion_maps end,
         fecha_entrega_estimada_proyecto = case when p_cambios ? 'fecha_entrega_estimada_proyecto' then v_fecha else p.fecha_entrega_estimada_proyecto end,
         fecha_entrega_estimada_fijada_en = case
             when p_cambios ? 'fecha_entrega_estimada_proyecto' and v_fecha is distinct from p.fecha_entrega_estimada_proyecto
             then case when v_fecha is null then null else current_date end
             else p.fecha_entrega_estimada_fijada_en end,
         pct_minimo_inicio = case when p_cambios ? 'pct_minimo_inicio' then v_pct else p.pct_minimo_inicio end
   where p.id = p_id;
end $function$;
