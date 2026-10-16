-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68); el maestro no tiene el abono de la Carta (grep de erp/migraciones, 16-oct) y su traspaso por texto (b2_contratos) va comunicado aparte
-- EL DINERO Y LA PARCELA DE UNA CARTA DE RESERVA SOLO PASAN A UN BLOQUEO CON UNA FICHA EN COMÚN Y DE LA MISMA EMPRESA, NUNCA POR LO QUE
-- ESCRIBE EL NAVEGADOR — 16-oct-2026 (Backend, sesión carta-liberada-comprador; riesgo visto por Seguridad en la consulta de LAW-428,
-- Bitácora de encargos/20260929_lawang_proyecto_por_id.md; revisión previa #397 con Seguridad, que FRENÓ la v1 por dejar fuera la
-- hermana y dio CUMPLE a esta).
--
-- EL AGUJERO. Al dar de alta un Bloqueo de Parcela (solo por contrato_guarda: agente con la herramienta contratos), el disparador
-- BEFORE trg_carta_cobrado_al_bloquear le abona el cobrado de tres clases de Carta de Reserva, y el AFTER trg_sincroniza_unidad hace el
-- traspaso de la parcela (la Carta pasa a colgar del Bloqueo). Quién es «el mismo comprador» lo decidían con contrato_identificadores:
-- pasaporte y correo de datos.fields.adq1_* y datos.compradores[], texto que escribe el navegador.
--   · rama LIBERADA (22-sep): cualquier Carta liberada de CUALQUIER empresa cuyo pasaporte/correo coincidiera → abono.
--   · rama «misma» (la Carta que ocupa la parcela): abono sin mirar al comprador; solo la frenaba el traspaso del AFTER, que también
--     comparaba texto. Un co-comprador SIN ficha con el pasaporte del dueño de la Carta bastaba (el espejo de la ficha solo pisa adq1_*).
--   · rama colgada (la Carta ya colgada de este Bloqueo): la cuelga ese mismo traspaso.
-- Además el BEFORE corre antes que trg_espejo_comprador (orden alfabético): veía los adq1_* crudos del navegador.
-- MEDIDO el 16-oct en solo lectura: 5 Cartas liberadas, las 5 con ficha y 0 cobrado (0 € por esa rama); 6 Cartas no liberadas ocupan
-- parcela, 2 con saldo disponible > 0 (CR00021 sandal_woods, CR00025 lawang): ese era el dinero expuesto. Las 6 filas de
-- carta_cobrado_aplicado cumplen la regla nueva con estas mismas fuentes (ningún abono histórico deja de cumplirla).
--
-- LA REGLA NUEVA, una sola y escrita una vez: privado.carta_imputable(carta, fichas del Bloqueo, empresa del Bloqueo) =
--   la Carta tiene proyecto_id y la empresa de su proyecto es la del Bloqueo, Y comparten una FICHA. Las del Bloqueo son los client_id
--   de datos.adq1_client_id y datos.compradores[].client_id (privado.carta_cobrado_clientes_de: forma 8-4-4-4-12 y que exista en clients;
--   contrato_guarda ya comprobó con _contrato_clientes_comprueba que quien guarda ve cada ficha nueva, y authenticated no escribe
--   contratos por otro camino: solo SELECT, medido el 16-oct). Las de la Carta, contrato_compradores ∪ su columna adq1_client_id
--   (privado.contrato_fichas). NO las de contrato_compradores del Bloqueo: en el BEFORE aún está vacía, y sincronizar_compradores
--   enlaza un pasaporte TECLEADO a cualquier ficha visible; el BEFORE (dinero) y el AFTER (parcela) deciden con lo mismo.
--   Sin ficha, sin proyecto o sin empresa: no se imputa ni se traspasa (falla cerrado).
-- DÓNDE:
--   · privado.carta_cobrado_calcula_por_id (la viva desde LAW-428 2B, 20261016002630) y public.carta_cobrado_calcula (sin llamadores, pero
--     el REVERSION de 2B devuelve el disparador a ella): el predicado filtra las TRES ramas por fuera; la liberada deja de mirar texto.
--     La vieja toma la empresa de la COLUMNA proyecto_nombre (vía _contrato_proyecto_de), no de datos.fields.
--   · public.sincroniza_unidad_contrato: el traspaso Carta -> Bloqueo pasa a traspaso_carta_estado con las fichas, y un 'ok' que no cumple
--     el predicado es 'otro'. Mensajes nuevos (mismo prefijo «El traspaso de la parcela », que app.html reconoce como freno conocido).
--     La rama «Carta nueva sobre su Bloqueo» (continue) sigue por texto: no mueve dinero ni parcela, y la colgada ya pasa el predicado.
--   · RASTRO (Seguridad #397): imputar dinero de una Carta LIBERADA apunta un evento 'editado' {accion: carta_liberada_imputada,
--     bloqueo_id, importe} en la Carta (el Bloqueo aún no existe en el BEFORE INSERT); se repite en cada recálculo.
-- CAMBIO DE COMPORTAMIENTO DECLARADO: 25 de los 27 traspasos históricos comparten ficha por datos; los otros 2 (Bloqueo sin ficha elegida,
--   enlazado solo por pasaporte) hoy pedirían elegir la ficha del comprador. Un Bloqueo sin ficha (1 de 141) no recoge ninguna Carta.
-- DECISIÓN POR DEFECTO (Backend, aceptada por Seguridad en #397; reversible): «ficha en común», no «titular = titular». Medido: titular =
--   titular habría rechazado 4 de 27 traspasos legítimos; y meter como co-comprador a una persona cuya ficha el agente ve es una
--   decisión dentro de su permiso, escrita en el contrato que esa persona firma, no texto falsificado. El riesgo que queda lo asume el
--   owner, que puede pedir la versión estricta.
-- PERMISOS: los 3 ayudantes nacen sin EXECUTE para nadie del API; public.carta_cobrado_calcula pierde el de service_role (0 llamadores,
--   §1.ter). CREATE OR REPLACE conserva dueño y el resto de permisos.
-- Cuerpos GENERADOS desde pg_get_functiondef de la viva del 16-oct (md5 41be932a47f00beb4b4264df69b36d31 calcula_por_id,
--   ddf75635712cbec45b1d55d6cb630cc8 calcula, 524feef3b661037e3b444615c8eeb6af sincroniza) con reemplazos literales de recuento exacto.
-- NO TOCA: carta_cobrado_recalcula, los disparadores, contrato_guarda, la vista previa parcela_traspaso_estado(_por_unidad) (sigue
--   comparando los pasaportes que manda la pantalla: seguimiento de Frontend en el encargo), ni la búsqueda de la parcela por nombre
--   en sincroniza (LAW-428).
-- SIN SERIES: nada de esto da de alta en una tabla con numeración.
-- PRUEBA: supabase/pruebas/carta_liberada_mismo_comprador.sql (en rama). VUELTA ATRÁS: supabase/reversion_carta_liberada/REVERSION.sql.

set local lock_timeout = '5s';

-- ── precondición (falla cerrado): los tres cuerpos que se re-emiten tienen que ser EXACTAMENTE los del 16-oct de los que se generaron
-- (o ya llevar la regla, si se reaplica). Si otro cambio los tocó entre medias, re-emitirlos lo pisaría en silencio: se para y se
-- regenera desde la viva (scratchpad gen_carta.py de la sesión carta-liberada-comprador, reemplazos de recuento exacto).
do $pre$
declare f text; m text; esperado text;
begin
  for f, esperado in values ('privado.carta_cobrado_calcula_por_id(uuid,jsonb,uuid)', '41be932a47f00beb4b4264df69b36d31'),
                            ('public.carta_cobrado_calcula(uuid,jsonb,text)', 'ddf75635712cbec45b1d55d6cb630cc8'),
                            ('public.sincroniza_unidad_contrato()', '524feef3b661037e3b444615c8eeb6af') loop
    if to_regprocedure(f) is null then
      raise exception 'carta imputable: falta % (¿LAW-428 2B sin aplicar?)', f;
    end if;
    m := md5(pg_get_functiondef(f::regprocedure));
    if m <> esperado and position('carta_imputable' in pg_get_functiondef(f::regprocedure)) = 0 then
      raise exception 'carta imputable: % cambió desde el 16-oct (md5 % y no %): regenerar desde la viva antes de aplicar', f, m, esperado;
    end if;
  end loop;
end $pre$;

-- ── ayudantes (privado, sin EXECUTE para el API; los llaman los DEFINER de postgres) ──
create or replace function privado.carta_cobrado_clientes_de(p_datos jsonb)
 returns uuid[]
 language sql
 stable
 set search_path to ''
as $function$
  -- las fichas que el Bloqueo NOMBRA por id: datos.adq1_client_id y datos.compradores[].client_id, solo en la forma 8-4-4-4-12 (la que
  -- exige _contrato_clientes_comprueba) y solo si la ficha existe. Un texto que no es un uuid canónico se descarta, no lanza.
  select coalesce(array_agg(distinct k.id), '{}'::uuid[])
    from (select btrim(coalesce(p_datos->>'adq1_client_id', '')) as x
          union all
          select btrim(coalesce(e.v->>'client_id', ''))
            from jsonb_array_elements(case when jsonb_typeof(p_datos->'compradores') = 'array'
                                           then p_datos->'compradores' else '[]'::jsonb end) e(v)) t
    join public.clients k
      on k.id = case when t.x ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then t.x::uuid end
$function$;

create or replace function privado.contrato_fichas(p_contrato uuid)
 returns uuid[]
 language sql
 stable
 set search_path to ''
as $function$
  -- las fichas de un contrato YA GUARDADO, las que puso el servidor: contrato_compradores y la columna generada adq1_client_id
  select coalesce(array_agg(distinct f.id), '{}'::uuid[])
    from (select cc.client_id as id from public.contrato_compradores cc where cc.contrato_id = p_contrato
          union all
          select c.adq1_client_id from public.contratos c where c.id = p_contrato) f
   where f.id is not null
$function$;

create or replace function privado.carta_imputable(p_carta uuid, p_clientes uuid[], p_empresa text)
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  -- LA regla: una Carta solo aporta dinero o parcela a un Bloqueo si es de la MISMA empresa y comparten una FICHA
  select coalesce(array_length(p_clientes, 1), 0) > 0
     and p_empresa is not null
     and exists (select 1
                   from public.contratos c
                   join public.proyectos pc on pc.id = c.proyecto_id
                  where c.id = p_carta
                    and pc.empresa = p_empresa)
     and privado.contrato_fichas(p_carta) && p_clientes
$function$;

revoke all on function privado.carta_cobrado_clientes_de(jsonb), privado.contrato_fichas(uuid),
                       privado.carta_imputable(uuid, uuid[], text) from public, anon, authenticated, service_role;

-- ── re-emitidas ──
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
  -- 16-oct-2026: las FICHAS del Bloqueo y su EMPRESA deciden qué Carta aporta (privado.carta_imputable), nunca el texto del navegador
  clientes_yo uuid[] := privado.carta_cobrado_clientes_de(p_datos);
  empresa_yo text := (select pr.empresa from public.proyectos pr where pr.id = p_proyecto_id);
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
      -- la Carta LIBERADA del mismo comprador (22-sep): retenida e imputable. «Del mismo comprador» lo decide el filtro de abajo
      -- (16-oct: ficha en común y misma empresa); antes, el pasaporte o el correo de datos.fields.
      select c.id, c.numero, false
        from public.contratos c
       where c.tipo like 'carta_reserva%'
         and c.liberado_en is not null
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
    ) y
    -- 16-oct-2026 (máxima 3): ninguna de las tres ramas aporta dinero sin una FICHA en común y la MISMA empresa
    where privado.carta_imputable(y.id, clientes_yo, empresa_yo)
    group by y.id, y.numero) x;

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

    -- 16-oct-2026 (Seguridad, revisión previa #397): el dinero retenido de una Carta LIBERADA que se imputa deja rastro en la Carta
    -- (el Bloqueo aún no existe en el BEFORE INSERT). Se repite en cada recálculo, como el apunte de carta_cobrado_recalcula.
    insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
    select k.id, 'editado',
           jsonb_build_object('accion', 'carta_liberada_imputada', 'bloqueo_id', p_id, 'importe', elem->>'importe'),
           coalesce(public._quien_actua(), (select auth.uid())::text)
      from jsonb_array_elements(v_detalle) elem
      join public.contratos k on k.id = (elem->>'carta_id')::uuid
     where k.liberado_en is not null;
  end if;

  if v_sobrante > 0 then
    datos := jsonb_set(datos, '{fields,carta_cobrado_sobrante}', to_jsonb(public.lw_importe_texto(v_sobrante)), true);
  end if;

  datos := public.carta_cobrado_aplica_hitos(datos, 'insert');
  return datos;
end;
$function$;

CREATE OR REPLACE FUNCTION public.carta_cobrado_calcula(p_id uuid, p_datos jsonb, p_proyecto_nombre text)
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
  proy text := coalesce(nullif(btrim(p_datos->'fields'->>'proyecto_nombre'), ''), p_proyecto_nombre);
  moneda_bloqueo text := coalesce(nullif(btrim(p_datos->'fields'->>'moneda'), ''), 'EUR');
  -- 16-oct-2026: las FICHAS del Bloqueo y su EMPRESA deciden qué Carta aporta (privado.carta_imputable), nunca el texto del navegador;
  -- la empresa sale de la COLUMNA del contrato (p_proyecto_nombre), no de datos.fields
  clientes_yo uuid[] := privado.carta_cobrado_clientes_de(p_datos);
  empresa_yo text := (select pr.empresa from public.proyectos pr
                       where pr.id = public._contrato_proyecto_de(null, p_proyecto_nombre));
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

  if proy is null then
    return datos;
  end if;

  select array_agg(x.id order by x.misma desc, x.numero), array_agg(x.numero order by x.misma desc, x.numero)
    into cartas_ids, cartas_nums
    from (select y.id, y.numero, bool_or(y.misma) as misma from (
      -- la Carta que ocupa hoy la parcela (traspaso Carta -> Bloqueo, 17-sep)
      select distinct c.id, c.numero, true as misma
        from public.unidades u
        join public.contratos c on c.id = u.contrato_id
       where u.proyecto = proy and u.codigo = any(cods)
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
      -- la Carta LIBERADA del mismo comprador (22-sep): retenida e imputable. «Del mismo comprador» lo decide el filtro de abajo
      -- (16-oct: ficha en común y misma empresa); antes, el pasaporte o el correo de datos.fields.
      select c.id, c.numero, false
        from public.contratos c
       where c.tipo like 'carta_reserva%'
         and c.liberado_en is not null
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
    ) y
    -- 16-oct-2026 (máxima 3): ninguna de las tres ramas aporta dinero sin una FICHA en común y la MISMA empresa
    where privado.carta_imputable(y.id, clientes_yo, empresa_yo)
    group by y.id, y.numero) x;

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

    -- 16-oct-2026 (Seguridad, revisión previa #397): el dinero retenido de una Carta LIBERADA que se imputa deja rastro en la Carta
    -- (el Bloqueo aún no existe en el BEFORE INSERT). Se repite en cada recálculo, como el apunte de carta_cobrado_recalcula.
    insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
    select k.id, 'editado',
           jsonb_build_object('accion', 'carta_liberada_imputada', 'bloqueo_id', p_id, 'importe', elem->>'importe'),
           coalesce(public._quien_actua(), (select auth.uid())::text)
      from jsonb_array_elements(v_detalle) elem
      join public.contratos k on k.id = (elem->>'carta_id')::uuid
     where k.liberado_en is not null;
  end if;

  if v_sobrante > 0 then
    datos := jsonb_set(datos, '{fields,carta_cobrado_sobrante}', to_jsonb(public.lw_importe_texto(v_sobrante)), true);
  end if;

  datos := public.carta_cobrado_aplica_hitos(datos, 'insert');
  return datos;
end;
$function$;

CREATE OR REPLACE FUNCTION public.sincroniza_unidad_contrato()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cods text[] := (
    select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
      from unnest(string_to_array(coalesce(new.datos->'fields'->>'parcela_codigo',''), ',')) x);
  cods_ant text[];
  proy text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  proy_ant     text;
  cod          text;
  ocupada      text;
  ocupada_id   uuid;
  ocupada_tipo text;
  ids_nuevo    text[];
  ids_ocupa    text[];
  clientes_nuevo uuid[];
  empresa_nuevo  text;
  fichas_ocupa   text[];
  traspaso_ok  boolean;
  estado_tr    text;
  exige        boolean;
  master       text;
  falta        text;
  existe          boolean;
  hay_inventario  boolean;
  cod_nuevo       boolean;
begin
  if tg_op = 'UPDATE' and coalesce(current_setting('app.via_traspaso_autor', true), '') = 'on' and (to_jsonb(new) - 'creado_por') = (to_jsonb(old) - 'creado_por') then return new; end if;
  if new.liberado_en is not null then
    return new;
  end if;

  if tg_op = 'UPDATE' and pg_trigger_depth() > 1
     and new.datos     is not distinct from old.datos
     and new.tipo      is not distinct from old.tipo
     and new.bloqueado is not distinct from old.bloqueado then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    cods_ant := (
      select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
        from unnest(string_to_array(coalesce(old.datos->'fields'->>'parcela_codigo',''), ',')) x);
    proy_ant := coalesce(nullif(btrim(old.datos->'fields'->>'proyecto_nombre'), ''), old.proyecto_nombre);
    if cods_ant is distinct from cods
       or (old.datos->'fields'->>'proyecto_nombre') is distinct from (new.datos->'fields'->>'proyecto_nombre') then
      if coalesce(current_setting('app.via_traspaso_estudio', true), '') <> 'on' then
        select u.codigo, cr.numero, u.estado into cod, ocupada, estado_tr
          from public.unidades u
          left join public.contratos cr
            on cr.contrato_padre_id = new.id and cr.id <> new.id
           and cr.liberado_en is null and coalesce(cr.bloqueado, false)
           and u.codigo = any (select btrim(x) from unnest(string_to_array(coalesce(cr.datos->'fields'->>'parcela_codigo', ''), ',')) x)
         where u.contrato_id = new.id
           and (u.proyecto is distinct from proy or not (u.codigo = any (cods)))
           and (u.estado in ('vendida', 'cobrada') or cr.id is not null)
         limit 1;
        if cod is not null then
          if ocupada is not null then
            raise exception 'La parcela % de % no se puede quitar de %: la nombra la Carta de Reserva firmada %. Moverla es un traspaso: pídeselo a administración.',
              cod, proy_ant, new.numero, ocupada using errcode = '23514';
          end if;
          raise exception 'La parcela % de % no se puede quitar de %: está %. Pídeselo a administración.',
            cod, proy_ant, new.numero, estado_tr using errcode = '23514';
        end if;
        cod := null; ocupada := null; estado_tr := null;
      end if;
      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id
         and (u.proyecto is distinct from proy or not (u.codigo = any (cods)));
    end if;
  end if;

  if coalesce(array_length(cods, 1), 0) = 0 or proy is null then

    select true into exige
      from public.contrato_tipo_etapa e
     where e.tipo = new.tipo and e.etapa = 'reserva';

    if coalesce(exige, false) then
      proy_ant := case when tg_op = 'UPDATE'
                  then coalesce(nullif(btrim(old.datos->'fields'->>'proyecto_nombre'), ''), old.proyecto_nombre)
                  end;
      if tg_op = 'UPDATE'
         and cods_ant is not distinct from cods
         and proy_ant is not distinct from proy then
        return new;
      end if;

      falta := case
                 when proy is null and coalesce(array_length(cods, 1), 0) = 0
                   then 'el proyecto y la parcela'
                 when proy is null then 'el proyecto'
                 else 'la parcela'
               end;

      master := nullif(btrim(coalesce(new.datos->'fields'->>'parcela_master','')), '');

      if master is not null and coalesce(array_length(cods, 1), 0) = 0 then
        raise exception
          'Rellena: %. El código «%» está en «Parcela máster» por error — va en el campo «Parcela».',
          falta, master using errcode = '23514';
      end if;

      raise exception
        'Rellena: %.',
        falta using errcode = '23514';
    end if;

    return new;
  end if;

  ids_nuevo := public.contrato_identificadores(new.datos);
  -- 16-oct-2026 (máxima 3): el TRASPASO Carta -> Bloqueo se decide por FICHA y EMPRESA (privado.carta_imputable, la misma regla que
  -- el abono), no por el pasaporte o el correo que escribe el navegador. ids_nuevo/ids_ocupa (texto) solo quedan para la Carta
  -- nueva sobre un Bloqueo (abajo), que no mueve dinero ni parcela.
  clientes_nuevo := privado.carta_cobrado_clientes_de(new.datos);
  empresa_nuevo := (select pr.empresa from public.proyectos pr where pr.id = new.proyecto_id);

  foreach cod in array cods loop
    select c.id, c.numero, c.tipo, public.contrato_identificadores(c.datos)
      into ocupada_id, ocupada, ocupada_tipo, ids_ocupa
      from public.unidades u join public.contratos c on c.id = u.contrato_id
     where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id
       and c.liberado_en is null;

    cod_nuevo := (tg_op = 'INSERT')
              or (proy_ant is distinct from proy)
              or not (cod = any (coalesce(cods_ant, '{}')));

    if ocupada_id is null and cod_nuevo then
      select exists(select 1 from public.unidades u where u.proyecto = proy and u.codigo = cod)
        into existe;
      if not existe then
        select exists(select 1 from public.unidades u where u.proyecto = proy)
          into hay_inventario;
        if hay_inventario then
          raise exception
            'La parcela «%» no está en el inventario de «%». Revisa el código (puede faltar o sobrar un espacio, un punto o una tilde) — este proyecto ya tiene parcelas cargadas.',
            cod, proy using errcode = '23514';
        end if;
      end if;
    end if;

    if ocupada_id is not null then
      if new.tipo like 'carta_reserva%'
         and ocupada_tipo = 'reserva_parcela'
         and (ids_nuevo && ids_ocupa or new.contrato_padre_id = ocupada_id) then
        continue;
      end if;

      fichas_ocupa := privado.contrato_fichas(ocupada_id)::text[];
      estado_tr := public.traspaso_carta_estado(new.tipo, clientes_nuevo::text[], ocupada_tipo, fichas_ocupa);
      if estado_tr = 'ok' and not privado.carta_imputable(ocupada_id, clientes_nuevo, empresa_nuevo) then
        estado_tr := 'otro';
      end if;
      traspaso_ok := estado_tr <> 'no';

      if not traspaso_ok then
        raise exception 'La parcela % de % ya esta asignada al contrato %', cod, proy, ocupada
          using errcode = '23505';
      end if;

      if estado_tr = 'sin_datos' then
        raise exception 'El traspaso de la parcela % de % no se puede comprobar: falta la ficha del comprador en % o en el contrato que estás guardando. Elige al comprador en el buscador de clientes y vuelve a guardar.',
          cod, proy, ocupada using errcode = '23514';
      end if;
      if estado_tr = 'otro' then
        raise exception 'El traspaso de la parcela % de % no cuadra: % está a nombre de otro comprador. La parcela solo pasa de una Carta de Reserva a su Bloqueo si los dos contratos tienen la misma ficha de comprador y son de la misma empresa.',
          cod, proy, ocupada using errcode = '23514';
      end if;
    end if;

    update public.unidades u
       set contrato_id = new.id,
           estado = case
             when u.estado in ('vendida','cobrada') then u.estado
             when u.estado = 'no_disponible' then u.estado
             when u.estado = 'bloqueada' and not exists (
                    select 1 from public.contratos c2
                     where c2.id = u.contrato_id
                       and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                  ) then u.estado
             when new.tipo = 'reserva_parcela' and coalesce(new.bloqueado, false) then 'bloqueada'
             when new.tipo = 'construccion' then u.estado
             else 'reservada'
           end
     where u.proyecto = proy and u.codigo = cod;

    if ocupada_id is not null and traspaso_ok then
      update public.contratos c
         set contrato_padre_id = new.id
       where c.id = ocupada_id and c.contrato_padre_id is null;
    end if;

    ocupada_id := null; ocupada := null; ocupada_tipo := null; ids_ocupa := null; fichas_ocupa := null;
  end loop;

  update public.unidades u
     set estado = case
           when u.estado in ('vendida','cobrada') then u.estado
           when u.estado = 'no_disponible' then u.estado
           when u.estado = 'bloqueada' and not exists (
                  select 1 from public.contratos c2
                   where c2.id = u.contrato_id
                     and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                ) then u.estado
           when new.tipo = 'reserva_parcela' and coalesce(new.bloqueado, false) then 'bloqueada'
           when new.tipo = 'construccion' then u.estado
           else 'reservada'
         end
   where u.contrato_id = new.id;

  return new;
end;
$function$;

-- la vieja no tiene llamador: fuera del API también para service_role (§1.ter; el REVERSION lo devuelve)
revoke execute on function public.carta_cobrado_calcula(uuid, jsonb, text) from service_role;

-- comprobación al aplicar: lo que debe quedar, o se deshace todo
do $c$
declare f text; rl text;
begin
  foreach f in array array['privado.carta_cobrado_calcula_por_id(uuid,jsonb,uuid)', 'public.carta_cobrado_calcula(uuid,jsonb,text)'] loop
    if position('contrato_identificadores' in pg_get_functiondef(f::regprocedure)) > 0
       or position('where privado.carta_imputable(y.id, clientes_yo, empresa_yo)' in pg_get_functiondef(f::regprocedure)) = 0 then
      raise exception 'carta imputable: % no quedó con la regla nueva', f;
    end if;
  end loop;
  if position('privado.carta_imputable(ocupada_id, clientes_nuevo, empresa_nuevo)' in pg_get_functiondef('public.sincroniza_unidad_contrato()'::regprocedure)) = 0 then
    raise exception 'carta imputable: el traspaso de sincroniza_unidad_contrato no quedó con la regla nueva';
  end if;
  foreach rl in array array['anon', 'authenticated', 'service_role'] loop
    foreach f in array array['privado.carta_cobrado_clientes_de(jsonb)', 'privado.contrato_fichas(uuid)', 'privado.carta_imputable(uuid,uuid[],text)',
                             'privado.carta_cobrado_calcula_por_id(uuid,jsonb,uuid)', 'public.carta_cobrado_calcula(uuid,jsonb,text)'] loop
      if has_function_privilege(rl, f, 'execute') then
        raise exception 'carta imputable: % quedó ejecutable por %', f, rl;
      end if;
    end loop;
  end loop;
end $c$;
