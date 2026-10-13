-- Servicios de AxisWorks: correcciones de la revisión de código del 13-oct-2026 (code-review sobre 20261013210000, antes de aterrizar).
-- Solo CONSTRUYE: una columna nueva, dos funciones nuevas y create or replace con las MISMAS firmas (la edge v2 en producción sigue llamando igual).
--   1. Una llamada que el PROVEEDOR RECHAZA (contesta con un error HTTP: 429, 500, 529…) no cobra: se cierra con coste 0 y no pesa contra el
--      tope (editor_ia_rechazada, solo la edge). Antes pesaba al peor caso: 57 caídas seguidas del proveedor gastaban el tope del mes sin
--      haber pagado nada. Lo que se corta SIN respuesta (tiempo agotado, red) sigue pesando al peor caso: pudo cobrar y no se sabe cuánto.
--   2. editor_ia_reserva vuelve a mirar lo que falta (margen, suspensión, tarifa) con el candado tomado, y para con un margen vacío.
--   3. editor_ia_estado dice lo mismo que la reserva: «lleno» = no cabe el peor caso de la llamada más barata (empresa o instancia), «puede»
--      por acción, y el precio para la empresa (coste × (1 + margen), redondeado HACIA ARRIBA) en vez del coste sin margen redondeado hacia abajo.
--      El motivo de «apagado» va además como clave (motivo_clave) para traducirlo en pantalla.
--   4. Extracto: las líneas de la factura suman (se redondea cada total una vez y lo derivado se resta).
--   5. Ajustes: el margen y las tarifas de Claude no se pueden vaciar; una tarifa tiene que ser mayor que cero.
-- Vuelta atrás: supabase/reversion_editor_ia/vuelta_atras_servicios.sql (las funciones vuelven a su versión de 20261013210000 re-aplicando
-- ese fichero desde «ayudantes»; la columna rechazada_http se queda: vacía no estorba).

alter table public.editor_ia_uso add column rechazada_http smallint check (rechazada_http between 400 and 599);   -- el proveedor rechazó: coste 0

-- La razón de _editor_ia_falta como CLAVE (apagado | suspendido | sin_configurar): la pantalla la traduce; el texto en llano sigue para Ajustes.
create function public._editor_ia_falta_clave(p_empresa text) returns text language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.editor_ia_empresa x where x.empresa = p_empresa and x.encendido) then return 'apagado'; end if;
  if exists (select 1 from public.servicios_axisworks_empresa x where x.empresa = p_empresa and x.suspendido) then return 'suspendido'; end if;
  if public._editor_ia_falta(p_empresa) is not null then return 'sin_configurar'; end if;
  return null;
end $$;
revoke all on function public._editor_ia_falta_clave(text) from public, anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── el proveedor rechazó la llamada (solo la edge)
-- Anthropic y DeepL no cobran una petición que contestan con un error HTTP (no hubo trabajo del modelo ni caracteres traducidos). La edge
-- la llama SOLO cuando recibió esa respuesta de error; un corte sin respuesta sigue por editor_ia_cierra (peor caso).
create function public.editor_ia_rechazada(p_uso uuid, p_http integer) returns boolean language plpgsql security definer set search_path = '' as $$
declare u public.editor_ia_uso%rowtype;
begin
  perform public._editor_ia_candado();
  if p_http is null or p_http not between 400 and 599 then raise exception 'Codigo HTTP no valido' using errcode = '22023'; end if;
  select * into u from public.editor_ia_uso x where x.id = p_uso for update;
  if not found then raise exception 'Uso no encontrado' using errcode = '22023'; end if;
  if u.estado <> 'reservado' then return false; end if;                       -- ya cerrado o caducado: no se toca
  if u.enviada_en is null then raise exception 'Ese uso no se llego a enviar' using errcode = '22023'; end if;
  update public.editor_ia_uso set estado = 'fallo', cerrada_en = now(), coste_usd = 0, importe_usd = null, rechazada_http = p_http,
         tokens_entrada = 0, tokens_salida = 0, caracteres = 0
   where id = u.id;
  return true;
end $$;
revoke all on function public.editor_ia_rechazada(uuid, integer) from public, anon, authenticated;
grant execute on function public.editor_ia_rechazada(uuid, integer) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── estado (pantalla del editor)
-- «puede» por acción con la MISMA cuenta que editor_ia_reserva (gasto + peor caso ≤ tope, de la empresa y de la instancia); «lleno» si no
-- cabe ni la más barata, y «lleno_por» dice cuál de los dos topes. «precio_max» = lo que como mucho se le factura a la empresa por llamada
-- (DeepL: por párrafo), redondeado hacia arriba. «facturado_usd» = lo que lleva facturado este mes (solo lo «hecho», con su margen).
create or replace function public.editor_ia_estado(p_empresa text) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_falta text; v_per date := public._editor_ia_periodo(); v_gasto numeric; v_tope numeric; v_inst numeric; v_fact numeric;
  s public.servicios_axisworks_ajustes%rowtype; k text; v_max numeric; v_min numeric;
  v_cm jsonb := '{}'::jsonb; v_pm jsonb := '{}'::jsonb; v_puede jsonb := '{}'::jsonb; v_lleno text;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El asistente de textos lo usa la administracion de la empresa' using errcode = '42501';
  end if;
  v_falta := public._editor_ia_falta(p_empresa);
  if v_falta is not null then
    return jsonb_build_object('encendido', false, 'motivo', v_falta, 'motivo_clave', public._editor_ia_falta_clave(p_empresa));
  end if;
  select * into s from public.servicios_axisworks_ajustes x where x.id;
  v_gasto := public._servicios_gasto_mes(p_empresa, v_per);
  v_tope := public._servicios_tope_empresa(p_empresa);
  v_inst := public._servicios_gasto_mes(null, v_per);
  foreach k in array array['propone', 'traduce_ia', 'traduce_deepl'] loop
    v_max := public._editor_ia_coste_max(k);
    v_cm := v_cm || jsonb_build_object(k, round(v_max, 4));
    v_pm := v_pm || jsonb_build_object(k, ceil(v_max * (1 + s.margen_pct / 100.0) * 100) / 100.0);
    v_puede := v_puede || jsonb_build_object(k, v_max is not null and v_gasto + v_max <= v_tope and v_inst + v_max <= s.tope_instancia_usd);
    if k <> 'traduce_deepl' and v_max is not null then v_min := least(coalesce(v_min, v_max), v_max); end if;
  end loop;
  v_lleno := case when v_min is null then null
                  when v_gasto + v_min > v_tope then 'empresa'
                  when v_inst + v_min > s.tope_instancia_usd then 'instancia' end;
  select sum(u.importe_usd) into v_fact from public.editor_ia_uso u where u.empresa = p_empresa and u.periodo = v_per and u.estado = 'hecho';
  return jsonb_build_object('encendido', true, 'motivo', null, 'motivo_clave', null, 'periodo', v_per,
    'gasto_usd', round(v_gasto, 2), 'tope_usd', v_tope, 'pct', least(100, floor(100 * v_gasto / v_tope))::int,
    'facturado_usd', round(coalesce(v_fact, 0), 2),
    'aviso', v_gasto >= v_tope * s.aviso_pct / 100.0, 'lleno', v_lleno is not null, 'lleno_por', v_lleno, 'puede', v_puede,
    'deepl', public._editor_ia_coste_max('traduce_deepl') is not null, 'coste_max', v_cm, 'precio_max', v_pm);
end $$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── reserva
-- MISMA firma y retorno que 20261013210000. Cambia: (1) se vuelve a mirar lo que falta y el peor caso con el candado tomado; (2) un margen
-- vacío bajo el candado para; (3) el «apagado» lleva su clave en DETAIL (apagado | suspendido | sin_configurar) para traducirlo en pantalla.
create or replace function public.editor_ia_reserva(p_empresa text, p_accion text, p_slug text, p_variante text, p_version uuid, p_parrafos integer)
 returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
  v_var text := coalesce(p_variante, 'estandar');
  v_falta text; s public.servicios_axisworks_ajustes%rowtype;
  v_per date := public._editor_ia_periodo(); v_min int; v_id uuid; v_max numeric; v_gasto numeric; v_tope numeric; v_inst numeric;
begin
  if v_uid is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El asistente de textos lo usa la administracion de la empresa' using errcode = '42501';
  end if;
  if p_accion is null or p_accion not in ('propone', 'traduce_ia', 'traduce_deepl') then
    raise exception 'Accion no valida' using errcode = '22023';
  end if;
  if p_parrafos is null or p_parrafos not between 1 and 40 or (p_accion = 'propone' and p_parrafos <> 1) then
    raise exception 'Numero de parrafos no valido' using errcode = '22023';
  end if;
  if v_var !~ '^[a-z][a-z0-9_]{0,39}$' then raise exception 'Revision no valida' using errcode = '22023'; end if;
  if p_slug is null or not exists (select 1 from public.plantillas_contrato t where t.slug = p_slug) then raise exception 'Plantilla no valida' using errcode = '22023'; end if;
  if p_version is not null and not exists (select 1 from public.plantilla_contrato_versiones v where v.id = p_version and v.empresa = p_empresa and v.slug = p_slug
                                             and v.variante = v_var and v.borrada_en is null) then
    raise exception 'Version no valida' using errcode = '22023';
  end if;
  v_falta := public._editor_ia_falta(p_empresa);
  if v_falta is not null then
    raise exception 'Asistente apagado: %', v_falta using errcode = '55000', hint = 'apagado', detail = coalesce(public._editor_ia_falta_clave(p_empresa), 'apagado');
  end if;
  v_max := public._editor_ia_coste_max(p_accion);
  if v_max is null then raise exception 'Ese motor no esta configurado' using errcode = '55000', hint = 'no_configurado'; end if;
  v_max := v_max * case when p_accion = 'traduce_deepl' then p_parrafos else 1 end;
  perform public._editor_ia_caduca();                                        -- toma el candado: reservas, cierres y caducidad, en cola
  -- OTRA VEZ, ya con el candado (code-review 13-oct): un cambio en Ajustes (margen vaciado, empresa suspendida, tarifa nueva) que llegó
  -- entre la primera comprobación y el candado manda. servicios_axisworks_guarda toma el mismo candado.
  v_falta := public._editor_ia_falta(p_empresa);
  if v_falta is not null then
    raise exception 'Asistente apagado: %', v_falta using errcode = '55000', hint = 'apagado', detail = coalesce(public._editor_ia_falta_clave(p_empresa), 'apagado');
  end if;
  v_max := public._editor_ia_coste_max(p_accion);
  if v_max is null then raise exception 'Ese motor no esta configurado' using errcode = '55000', hint = 'no_configurado'; end if;
  v_max := v_max * case when p_accion = 'traduce_deepl' then p_parrafos else 1 end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('editor_ia/usuario/' || v_uid::text, 0));
  select count(*) into v_min from public.editor_ia_uso u where u.usuario = v_uid and u.fecha > now() - interval '1 minute';
  if v_min >= 6 then raise exception 'Demasiadas consultas seguidas: espera un minuto' using errcode = 'P0001', hint = 'tope_minuto'; end if;
  select * into s from public.servicios_axisworks_ajustes x where x.id;
  if s.margen_pct is null then                                                -- nunca se congela un margen vacío (se facturaría a coste)
    raise exception 'Asistente apagado: falta el margen' using errcode = '55000', hint = 'apagado', detail = 'sin_configurar';
  end if;
  v_gasto := public._servicios_gasto_mes(p_empresa, v_per);
  v_tope := public._servicios_tope_empresa(p_empresa);
  if v_gasto + v_max > v_tope then
    raise exception 'Esta empresa ha llegado a su tope de % USD de este mes', v_tope using errcode = 'P0001', hint = 'tope_empresa';
  end if;
  v_inst := public._servicios_gasto_mes(null, v_per);
  if v_inst + v_max > s.tope_instancia_usd then
    raise exception 'El asistente ha llegado al tope de gasto de este mes' using errcode = 'P0001', hint = 'tope_global';
  end if;
  -- creditos = 1 y de_prueba = false solo porque esas columnas del modelo anterior siguen con su NOT NULL/CHECK hasta LAW-555
  insert into public.editor_ia_uso (empresa, usuario, autor, periodo, accion, slug, variante, version_id, parrafos, creditos, de_prueba,
                                    precio_credito, moneda, coste_max_usd, margen_pct)
  values (p_empresa, v_uid, v_autor, v_per, p_accion, p_slug, v_var, p_version, p_parrafos, 1, false, null, 'USD', v_max, s.margen_pct)
  returning id into v_id;
  return jsonb_build_object('uso', v_id, 'coste_max_usd', round(v_max, 4), 'gasto_usd', round(v_gasto + v_max, 2), 'tope_usd', v_tope,
                            'aviso', v_gasto + v_max >= v_tope * s.aviso_pct / 100.0);
end $$;
revoke all on function public.editor_ia_reserva(text, text, text, text, uuid, integer) from public, anon, service_role;
grant execute on function public.editor_ia_reserva(text, text, text, text, uuid, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── Ajustes → Servicios (extracto)
create or replace function public.servicios_axisworks_datos() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s public.servicios_axisworks_ajustes%rowtype; a public.editor_ia_ajustes%rowtype; v_per date := public._editor_ia_periodo();
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_super_admin() then raise exception 'Los servicios de AxisWorks los configura el super administrador' using errcode = '42501'; end if;
  select * into s from public.servicios_axisworks_ajustes x where x.id;
  select * into a from public.editor_ia_ajustes x where x.id;
  return jsonb_build_object(
    'periodo', v_per, 'zona', 'Asia/Makassar',
    'instancia', jsonb_build_object('margen_pct', s.margen_pct, 'tope_usd_defecto', s.tope_usd_defecto, 'tope_instancia_usd', s.tope_instancia_usd,
                                    'aviso_pct', s.aviso_pct, 'gasto_usd', round(public._servicios_gasto_mes(null, v_per), 2),
                                    'actualizado_por', s.actualizado_por, 'actualizado_en', s.actualizado_en),
    'tarifas', jsonb_build_object('modelo', 'claude-opus-5-5', 'tarifa_entrada_usd_mtok', a.tarifa_entrada_usd_mtok,
                                  'tarifa_salida_usd_mtok', a.tarifa_salida_usd_mtok, 'tarifa_deepl_usd_mcar', a.tarifa_deepl_usd_mcar),
    'empresas', coalesce((select jsonb_agg(jsonb_build_object('clave', em.clave, 'nombre', em.nombre,
                                   'editor_ia', coalesce(ie.encendido, false), 'suspendido', coalesce(se.suspendido, false),
                                   'tope_usd', se.tope_usd, 'tope_efectivo_usd', public._servicios_tope_empresa(em.clave),
                                   'gasto_usd', round(public._servicios_gasto_mes(em.clave, v_per), 2), 'falta', public._editor_ia_falta(em.clave))
                                 order by em.orden, em.clave)
                            from public.empresas em
                            left join public.editor_ia_empresa ie on ie.empresa = em.clave
                            left join public.servicios_axisworks_empresa se on se.empresa = em.clave
                           where em.activa), '[]'::jsonb),
    -- Extracto de los 3 últimos meses (hora de Bali), por empresa e importes SIN impuestos. Coste e importe por llamada sin redondear; se
    -- redondean una sola vez el coste del proveedor, el facturable y el total; «no repercutido» y «margen» salen de restar (las líneas suman). Se factura solo lo «hecho»; los fallos enviados son coste del owner («no repercutido»).
    'extracto', coalesce((select jsonb_agg(x order by x ->> 'periodo' desc, x ->> 'empresa') from (
        select jsonb_build_object('periodo', u.periodo, 'empresa', u.empresa,
                 'llamadas', count(*), 'hechas', count(*) filter (where u.estado = 'hecho'),
                 'fallidas', count(*) filter (where u.estado in ('fallo', 'caducada')), 'en_vuelo', count(*) filter (where u.estado = 'reservado'),
                 'rechazadas', count(*) filter (where u.rechazada_http is not null),
                 'coste_proveedor_usd', round(coalesce(sum(u.coste_usd) filter (where u.estado in ('hecho', 'fallo')), 0), 2),
                 'coste_no_repercutido_usd', round(coalesce(sum(u.coste_usd) filter (where u.estado in ('hecho', 'fallo')), 0), 2)
                                             - round(coalesce(sum(u.coste_usd) filter (where u.estado = 'hecho'), 0), 2),
                 'coste_facturable_usd', round(coalesce(sum(u.coste_usd) filter (where u.estado = 'hecho'), 0), 2),
                 'margen_usd', round(coalesce(sum(u.importe_usd) filter (where u.estado = 'hecho'), 0), 2)
                               - round(coalesce(sum(u.coste_usd) filter (where u.estado = 'hecho'), 0), 2),
                 'total_sin_impuestos_usd', round(coalesce(sum(u.importe_usd) filter (where u.estado = 'hecho'), 0), 2),
                 'margenes_pct', coalesce(jsonb_agg(distinct u.margen_pct) filter (where u.estado = 'hecho' and u.margen_pct is not null), '[]'::jsonb),
                 'aceptadas', count(*) filter (where u.aceptada_en is not null),
                 'tokens_entrada', coalesce(sum(u.tokens_entrada), 0), 'tokens_salida', coalesce(sum(u.tokens_salida), 0),
                 'coste_incompleto', coalesce(bool_or((u.coste_usd is null and u.estado in ('hecho', 'fallo') and u.enviada_en is not null)
                                                      or (u.estado = 'caducada' and u.enviada_en is not null)), false)) x
          from public.editor_ia_uso u
         where u.periodo >= (v_per - interval '2 months')::date
         group by u.periodo, u.empresa) t), '[]'::jsonb),
    'registro', coalesce((select jsonb_agg(jsonb_build_object('ambito', l.ambito, 'antes', l.antes, 'despues', l.despues, 'motivo', l.motivo, 'autor', l.autor, 'fecha', l.fecha) order by l.id desc)
                            from (select * from public.servicios_axisworks_log order by id desc limit 30) l), '[]'::jsonb));
end $$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── Ajustes → Servicios (guardar)
create or replace function public.servicios_axisworks_guarda(p_empresa text, p_campos jsonb, p_motivo text) returns jsonb
 language plpgsql security definer set search_path = '' as $$
declare
  v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
  k text; v jsonb; v_antes jsonb; v_despues jsonb;
  CL_INST constant text[] := array['margen_pct', 'tope_usd_defecto', 'tope_instancia_usd', 'aviso_pct', 'tarifa_entrada_usd_mtok', 'tarifa_salida_usd_mtok', 'tarifa_deepl_usd_mcar'];
  CL_EMP  constant text[] := array['editor_ia', 'tope_usd', 'suspendido'];
  NUM     constant text[] := array['margen_pct', 'tope_usd_defecto', 'tope_instancia_usd', 'tarifa_entrada_usd_mtok', 'tarifa_salida_usd_mtok', 'tarifa_deepl_usd_mcar', 'tope_usd'];
  -- margen y tarifas de Claude: vaciarlos apagaría el servicio sin decirlo (un campo que el navegador no entiende llega vacío). DeepL sí
  -- se puede vaciar: vacío = no configurado.
  NO_NULL constant text[] := array['tope_usd_defecto', 'tope_instancia_usd', 'aviso_pct', 'editor_ia', 'suspendido', 'margen_pct',
                                   'tarifa_entrada_usd_mtok', 'tarifa_salida_usd_mtok'];
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_super_admin() then raise exception 'Los servicios de AxisWorks los configura el super administrador' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 3 or length(p_motivo) > 300 then raise exception 'Falta el motivo del cambio (de 3 a 300 letras)' using errcode = '22023'; end if;
  if p_campos is null or jsonb_typeof(p_campos) <> 'object' or p_campos = '{}'::jsonb then raise exception 'No hay nada que guardar' using errcode = '22023'; end if;
  for k, v in select * from jsonb_each(p_campos) loop
    if p_empresa is null and k <> all (CL_INST) or p_empresa is not null and k <> all (CL_EMP) then
      raise exception 'El dato «%» no se cambia aqui', left(k, 40) using errcode = '22023';
    end if;
    if jsonb_typeof(v) = 'null' then
      if k = any (NO_NULL) then raise exception '«%» no se puede dejar vacio', k using errcode = '22023'; end if;
      continue;
    end if;
    if k = any (NUM) and jsonb_typeof(v) <> 'number' then raise exception '«%» es un numero', k using errcode = '22023'; end if;
    if k like 'tarifa\_%' and (v #>> '{}')::numeric <= 0 then raise exception '«%» tiene que ser mayor que cero', k using errcode = '22023'; end if;
    if k = 'aviso_pct' and (jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric <> trunc((v #>> '{}')::numeric)) then raise exception '«%» es un numero entero', k using errcode = '22023'; end if;
    if k in ('editor_ia', 'suspendido') and jsonb_typeof(v) <> 'boolean' then raise exception '«%» es si o no', k using errcode = '22023'; end if;
  end loop;
  perform public._editor_ia_candado();                                       -- la misma cola que las reservas
  if p_empresa is null then
    select to_jsonb(s) - 'id' || jsonb_build_object('tarifa_entrada_usd_mtok', a.tarifa_entrada_usd_mtok, 'tarifa_salida_usd_mtok', a.tarifa_salida_usd_mtok,
                                                    'tarifa_deepl_usd_mcar', a.tarifa_deepl_usd_mcar)
      into v_antes
      from public.servicios_axisworks_ajustes s, public.editor_ia_ajustes a where s.id and a.id;
    update public.servicios_axisworks_ajustes s set
      margen_pct         = case when p_campos ? 'margen_pct' then (p_campos ->> 'margen_pct')::numeric else s.margen_pct end,
      tope_usd_defecto   = case when p_campos ? 'tope_usd_defecto' then (p_campos ->> 'tope_usd_defecto')::numeric else s.tope_usd_defecto end,
      tope_instancia_usd = case when p_campos ? 'tope_instancia_usd' then (p_campos ->> 'tope_instancia_usd')::numeric else s.tope_instancia_usd end,
      aviso_pct          = case when p_campos ? 'aviso_pct' then (p_campos ->> 'aviso_pct')::int else s.aviso_pct end,
      actualizado_por = v_autor, actualizado_en = now()
     where s.id;
    update public.editor_ia_ajustes a set
      tarifa_entrada_usd_mtok = case when p_campos ? 'tarifa_entrada_usd_mtok' then (p_campos ->> 'tarifa_entrada_usd_mtok')::numeric else a.tarifa_entrada_usd_mtok end,
      tarifa_salida_usd_mtok  = case when p_campos ? 'tarifa_salida_usd_mtok' then (p_campos ->> 'tarifa_salida_usd_mtok')::numeric else a.tarifa_salida_usd_mtok end,
      tarifa_deepl_usd_mcar   = case when p_campos ? 'tarifa_deepl_usd_mcar' then (p_campos ->> 'tarifa_deepl_usd_mcar')::numeric else a.tarifa_deepl_usd_mcar end,
      actualizado_por = v_autor, actualizado_en = now()
     where a.id;
    select to_jsonb(s) - 'id' || jsonb_build_object('tarifa_entrada_usd_mtok', a.tarifa_entrada_usd_mtok, 'tarifa_salida_usd_mtok', a.tarifa_salida_usd_mtok,
                                                    'tarifa_deepl_usd_mcar', a.tarifa_deepl_usd_mcar)
      into v_despues
      from public.servicios_axisworks_ajustes s, public.editor_ia_ajustes a where s.id and a.id;
    insert into public.servicios_axisworks_log (ambito, antes, despues, motivo, autor, autor_uid) values ('instancia', v_antes, v_despues, btrim(p_motivo), v_autor, (select auth.uid()));
    return v_despues;
  end if;
  if not exists (select 1 from public.empresas e where e.clave = p_empresa and e.activa) then raise exception 'Empresa no valida' using errcode = '22023'; end if;
  insert into public.servicios_axisworks_empresa (empresa) values (p_empresa) on conflict (empresa) do nothing;
  insert into public.editor_ia_empresa (empresa) values (p_empresa) on conflict (empresa) do nothing;
  select to_jsonb(se) - 'empresa' || jsonb_build_object('editor_ia', ie.encendido) into v_antes
    from public.servicios_axisworks_empresa se join public.editor_ia_empresa ie on ie.empresa = se.empresa where se.empresa = p_empresa for update of se, ie;
  update public.servicios_axisworks_empresa se set
    suspendido = case when p_campos ? 'suspendido' then (p_campos ->> 'suspendido')::boolean else se.suspendido end,
    tope_usd   = case when p_campos ? 'tope_usd' then (p_campos ->> 'tope_usd')::numeric else se.tope_usd end,
    actualizado_por = v_autor, actualizado_en = now()
   where se.empresa = p_empresa;
  if p_campos ? 'editor_ia' then
    update public.editor_ia_empresa ie set encendido = (p_campos ->> 'editor_ia')::boolean, actualizado_por = v_autor, actualizado_en = now()
     where ie.empresa = p_empresa;
  end if;
  select to_jsonb(se) - 'empresa' || jsonb_build_object('editor_ia', ie.encendido) into v_despues
    from public.servicios_axisworks_empresa se join public.editor_ia_empresa ie on ie.empresa = se.empresa where se.empresa = p_empresa;
  insert into public.servicios_axisworks_log (ambito, antes, despues, motivo, autor, autor_uid) values (p_empresa, v_antes, v_despues, btrim(p_motivo), v_autor, (select auth.uid()));
  return v_despues;
end $$;

do $comprueba$
begin
  if public._editor_ia_falta_clave('lawang') is distinct from 'sin_configurar' then
    raise exception 'Clave de Lawang inesperada: %', coalesce(public._editor_ia_falta_clave('lawang'), 'nada falta');
  end if;
end $comprueba$;
