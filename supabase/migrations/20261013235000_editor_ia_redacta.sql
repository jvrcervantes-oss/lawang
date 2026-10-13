-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- E10 «contrato entero desde una frase» (13-oct-2026). Encargo agencia encargos/20261008_lawang_editor_textos_contrato.md.
-- Owner, 13-oct: «dar de alta un contrato es un COÑAZO terrible» → la persona describe el contrato en una frase, el asistente (edge editor-ia,
-- acciones redacta y redacta_traduce) propone nombre, campos propios y cláusulas en español y luego en inglés e indonesio; la persona lo ve
-- ENTERO y lo crea con UNA función del servidor. Nace en BORRADOR: nada se activa solo (activar sigue siendo del super admin de la empresa).
-- Revisión previa 13-oct (Seguridad + Legal) recogida aquí punto por punto.
--
-- SIN NINGÚN BORRADO DE ESTRUCTURA (decisión por defecto del 13-oct, «E10 sin válvula»): las dos acciones nuevas NO caben en editor_ia_uso
-- (su CHECK de acción y su slug obligatorio), y ensanchar eso es DDL que borra (no_destruir.py). Van a una TABLA HERMANA, editor_ia_redaccion,
-- y lo que suma dinero (gasto contra el tope, extracto, facturado del mes) suma las DOS tablas.
--
-- DUEÑO DE CADA DATO
--   editor_ia_redaccion    un apunte por llamada de redacción o traducción de una redacción. Sin texto: huellas (sha256), tokens, coste.
--                          Escriben editor_ia_redaccion_reserva (persona), editor_ia_redaccion_paso (solo la edge, service_role) y
--                          plantilla_contrato_crea_desde_asistente (marca aceptada + el aviso de Legal aceptado + el contrato creado).
--   La propuesta (texto) NO se guarda en ningún sitio: viaja edge → navegador → función de crear, y la función la COMPRUEBA contra las
--   huellas que la edge apuntó al cerrar cada paso. El navegador no puede fabricar el texto que se guarda (Seguridad 13-oct, punto 1).
--
-- QUIÉN LLAMA A CADA FUNCIÓN (seguridad_2026.md §1.ter)
--   editor_ia_redaccion_reserva            authenticated · edge editor-ia (redacta, redacta_traduce), con el JWT de la persona
--   editor_ia_redaccion_paso               SOLO service_role · edge editor-ia (enviada / hecho / fallo / rechazada)
--   plantilla_contrato_crea_desde_asistente authenticated · textos-contrato-redacta.js (Textos de contrato → Contrato nuevo → «Descríbelo en una frase»)
--   editor_ia_estado, servicios_axisworks_datos   mismas firmas (create or replace): suman la tabla hermana
--   _plantilla_esqueleto_en_blanco         misma firma: el contrato en blanco trae ya partes, ley, arbitraje, idioma y firmas (Legal 13-oct)
-- Prueba: supabase/pruebas/editor_ia_redacta.sql · Vuelta atrás: supabase/reversion_editor_ia/vuelta_atras_redacta.sql

-- ─────────────────────────────────────────────────────────────────────────────────────────────── tabla hermana
create table public.editor_ia_redaccion (
  id               uuid primary key default gen_random_uuid(),
  empresa          text not null references public.empresas (clave),
  usuario          uuid not null,
  autor            text not null,
  fecha            timestamptz not null default now(),
  periodo          date not null,
  accion           text not null check (accion in ('redacta', 'redacta_traduce')),
  origen           uuid references public.editor_ia_redaccion (id),          -- la redacción que se traduce (solo redacta_traduce)
  idioma           text check (idioma in ('en', 'id')),                     -- idioma de destino (solo redacta_traduce)
  huella_entrada   text check (huella_entrada ~ '^[0-9a-f]{64}$'),           -- huella del español recibido = la que apuntó el paso (a)
  estado           text not null default 'reservado' check (estado in ('reservado', 'hecho', 'fallo', 'caducada')),   -- se factura SOLO «hecho»
  modelo           text,
  tokens_entrada   integer check (tokens_entrada >= 0),
  tokens_salida    integer check (tokens_salida >= 0),
  huella_propuesta text check (huella_propuesta ~ '^[0-9a-f]{64}$'),         -- huella de lo que devolvió el modelo YA validado
  enviada_en       timestamptz,
  cerrada_en       timestamptz,
  rechazada_http   smallint check (rechazada_http between 400 and 599),
  coste_max_usd    numeric(14,6) check (coste_max_usd >= 0),                 -- peor caso apartado al reservar
  margen_pct       numeric(7,2) check (margen_pct >= 0),                     -- congelado al reservar
  coste_usd        numeric(16,8) check (coste_usd >= 0),                     -- coste real al cerrar, sin redondear
  importe_usd      numeric(16,8) check (importe_usd >= 0),                   -- coste × (1 + margen), solo «hecho»
  aceptada_en      timestamptz,                                              -- se creó un contrato con esta redacción
  aceptada_por     text,
  aviso_aceptado   text,                                                     -- versión del aviso de Legal que la persona aceptó
  slug_creado      text,
  version_creada   uuid references public.plantilla_contrato_versiones (id),
  check ((accion = 'redacta' and origen is null and idioma is null and huella_entrada is null)
      or (accion = 'redacta_traduce' and origen is not null and idioma is not null and huella_entrada is not null))
);
-- Una traducción viva por idioma y redacción (Seguridad 13-oct): bajo el candado de la reserva y, por si acaso, en la base. Las fallidas y
-- caducadas NO cuentan (un 529 del proveedor no puede dejar ese idioma bloqueado para siempre); los intentos los acota la reserva (3).
create unique index editor_ia_redaccion_un_idioma on public.editor_ia_redaccion (origen, idioma)
  where accion = 'redacta_traduce' and estado in ('reservado', 'hecho');
create index editor_ia_redaccion_usuario_fecha on public.editor_ia_redaccion (usuario, fecha desc);
create index editor_ia_redaccion_periodo on public.editor_ia_redaccion (periodo, empresa);
create index editor_ia_redaccion_reservadas on public.editor_ia_redaccion (fecha) where estado = 'reservado';
create index editor_ia_redaccion_origen on public.editor_ia_redaccion (origen) where origen is not null;
comment on table public.editor_ia_redaccion is
  'Un apunte por llamada de «contrato desde una frase» (redacta) y de su traducción (redacta_traduce). Sin texto: huellas, tokens y coste. Hermana de editor_ia_uso; el dinero suma las dos.';
alter table public.editor_ia_redaccion enable row level security;
revoke all on table public.editor_ia_redaccion from public, anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── el peso contra el tope: UNA fórmula
-- La misma regla para las dos tablas (antes vivía solo en _editor_ia_peso): hecha o fallida enviada = su coste (si no se sabe, el peor caso);
-- en vuelo = el peor caso, salvo una reserva sin enviar de más de 10 minutos (= 0, lo que no salió no cuesta); caducada enviada = el peor caso.
create function public._editor_ia_peso_de(p_estado text, p_enviada timestamptz, p_fecha timestamptz, p_coste numeric, p_max numeric)
 returns numeric language sql stable set search_path = '' as $$
  select case
    when p_estado = 'reservado' and p_enviada is null and p_fecha < now() - interval '10 minutes' then 0
    when p_estado = 'reservado' then coalesce(p_max, 0)
    when p_enviada is null then 0
    when p_estado in ('hecho', 'fallo') then coalesce(p_coste, p_max, 0)
    else coalesce(p_max, 0) end
$$;
create or replace function public._editor_ia_peso(u public.editor_ia_uso) returns numeric language sql stable set search_path = '' as $$
  select public._editor_ia_peso_de(u.estado, u.enviada_en, u.fecha, u.coste_usd, u.coste_max_usd)
$$;
create function public._editor_ia_peso_r(u public.editor_ia_redaccion) returns numeric language sql stable set search_path = '' as $$
  select public._editor_ia_peso_de(u.estado, u.enviada_en, u.fecha, u.coste_usd, u.coste_max_usd)
$$;

-- Gasto del mes contra el tope (empresa, o toda la instancia con p_empresa null): las DOS tablas.
create or replace function public._servicios_gasto_mes(p_empresa text, p_periodo date) returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce((select sum(public._editor_ia_peso(u)) from public.editor_ia_uso u
                    where u.periodo = p_periodo and (p_empresa is null or u.empresa = p_empresa)), 0)
       + coalesce((select sum(public._editor_ia_peso_r(r)) from public.editor_ia_redaccion r
                    where r.periodo = p_periodo and (p_empresa is null or r.empresa = p_empresa)), 0)
$$;

-- Reservas que nadie cerró, de las dos tablas, bajo el mismo candado.
create or replace function public._editor_ia_caduca() returns integer language plpgsql security definer set search_path = '' as $$
declare n int; m int;
begin
  perform public._editor_ia_candado();
  update public.editor_ia_uso set estado = 'caducada', cerrada_en = now()
   where estado = 'reservado' and fecha < now() - interval '10 minutes';
  get diagnostics n = row_count;
  update public.editor_ia_redaccion set estado = 'caducada', cerrada_en = now()
   where estado = 'reservado' and fecha < now() - interval '10 minutes';
  get diagnostics m = row_count;
  return n + m;
end $$;

revoke all on function public._editor_ia_peso_de(text, timestamptz, timestamptz, numeric, numeric), public._editor_ia_peso(public.editor_ia_uso),
                       public._editor_ia_peso_r(public.editor_ia_redaccion), public._servicios_gasto_mes(text, date), public._editor_ia_caduca()
  from public, anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── huella de una propuesta
-- Texto canónico ÚNICO (la edge lo construye igual en motor.js → huellaRedaccion; la prueba lo compara con una huella calculada en node):
--   español   = campos (clave US tipo US etiqueta_es US etiqueta_en US etiqueta_id US opciones unidas por GS) unidos por RS, FS, y las
--               cláusulas (título US párrafo US párrafo…) unidas por RS
--   en / id   = solo las cláusulas en ese idioma, igual
-- US/RS/GS/FS = chr(31)/chr(30)/chr(29)/chr(28): ningún texto aceptado lleva caracteres de control, así que no hay ambigüedad.
-- p = la propuesta en el formato de plantilla_contrato_crea_desde_asistente: { campos: [...], clausulas: [{ titulo: {es,en,id}, parrafos: [{es,en,id}] }] }.
create function public._editor_ia_huella_redaccion(p jsonb, p_lang text) returns text language sql immutable set search_path = '' as $$
  select encode(pg_catalog.sha256(convert_to(
    case when p_lang = 'es' then
      coalesce((select string_agg(concat_ws(chr(31), c ->> 'clave', c ->> 'tipo', c ->> 'etiqueta_es', c ->> 'etiqueta_en', c ->> 'etiqueta_id',
                        coalesce((select string_agg(o #>> '{}', chr(29) order by q.n)
                                    from jsonb_array_elements(case when jsonb_typeof(c -> 'opciones') = 'array' then c -> 'opciones' else '[]'::jsonb end)
                                         with ordinality q(o, n)), '')),
                        chr(30) order by w.k)
                  from jsonb_array_elements(case when jsonb_typeof(p -> 'campos') = 'array' then p -> 'campos' else '[]'::jsonb end) with ordinality w(c, k)), '')
      || chr(28)
    else '' end
    || coalesce((select string_agg(concat_ws(chr(31), variadic array[cl -> 'titulo' ->> p_lang]
                                     || array(select pp ->> p_lang from jsonb_array_elements(cl -> 'parrafos') with ordinality z(pp, m) order by z.m)),
                                   chr(30) order by w.k)
                   from jsonb_array_elements(p -> 'clausulas') with ordinality w(cl, k)), ''),
    'UTF8')), 'hex')
$$;
revoke all on function public._editor_ia_huella_redaccion(jsonb, text) from public, anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── reserva (antes de llamar al proveedor)
-- Misma lógica que editor_ia_reserva (20261013220000), para la tabla hermana. Diferencias:
--   · redacta reserva SU peor caso, pero solo se deja empezar si cabe la creación ENTERA (redacta + 2 × redacta_traduce): un tope que se
--     llena entre el paso (a) y el (b) cobraría una redacción que ya no se puede terminar (revisión de diseño 13-oct).
--   · redacta_traduce solo sobre una redacción propia, terminada bien, de menos de 2 h y sin usar, y con la MISMA huella que el paso (a)
--     apuntó (hint «huella»: el navegador mandó otro español). Una traducción viva por idioma, y como mucho 3 intentos por idioma.
create function public.editor_ia_redaccion_reserva(p_empresa text, p_accion text, p_origen uuid, p_idioma text, p_huella_entrada text)
 returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
  v_falta text; s public.servicios_axisworks_ajustes%rowtype; o public.editor_ia_redaccion%rowtype;
  v_per date := public._editor_ia_periodo(); v_min int; v_n int; v_id uuid; v_max numeric; v_hueco numeric; v_gasto numeric; v_tope numeric; v_inst numeric;
begin
  if v_uid is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El asistente de textos lo usa la administracion de la empresa' using errcode = '42501';
  end if;
  if p_accion is null or p_accion not in ('redacta', 'redacta_traduce') then raise exception 'Accion no valida' using errcode = '22023'; end if;
  if p_accion = 'redacta' and (p_origen is not null or p_idioma is not null or p_huella_entrada is not null) then
    raise exception 'Parametros no validos' using errcode = '22023';
  end if;
  if p_accion = 'redacta_traduce' then
    if p_idioma is null or p_idioma not in ('en', 'id') or coalesce(p_huella_entrada, '') !~ '^[0-9a-f]{64}$' then
      raise exception 'Parametros no validos' using errcode = '22023';
    end if;
    select * into o from public.editor_ia_redaccion x where x.id = p_origen;
    if not found or o.usuario <> v_uid or o.empresa <> p_empresa or o.accion <> 'redacta' or o.estado <> 'hecho'
       or o.aceptada_en is not null or o.fecha < now() - interval '2 hours' then
      raise exception 'Esa redaccion ya no se puede traducir: vuelve a pedirla' using errcode = '22023', hint = 'origen';
    end if;
    if o.huella_propuesta is distinct from p_huella_entrada then
      raise exception 'El texto a traducir no es el que redacto el asistente' using errcode = '22023', hint = 'huella';
    end if;
  end if;
  v_falta := public._editor_ia_falta(p_empresa);
  if v_falta is not null then
    raise exception 'Asistente apagado: %', v_falta using errcode = '55000', hint = 'apagado', detail = coalesce(public._editor_ia_falta_clave(p_empresa), 'apagado');
  end if;
  if public._editor_ia_coste_max(p_accion) is null or public._editor_ia_coste_max('redacta_traduce') is null then
    raise exception 'Ese motor no esta configurado' using errcode = '55000', hint = 'no_configurado';
  end if;
  perform public._editor_ia_caduca();                                        -- toma el candado: reservas, cierres y caducidad, en cola
  -- otra vez, con el candado tomado (un cambio en Ajustes que llegó entre medias manda)
  v_falta := public._editor_ia_falta(p_empresa);
  if v_falta is not null then
    raise exception 'Asistente apagado: %', v_falta using errcode = '55000', hint = 'apagado', detail = coalesce(public._editor_ia_falta_clave(p_empresa), 'apagado');
  end if;
  v_max := public._editor_ia_coste_max(p_accion);
  if v_max is null or public._editor_ia_coste_max('redacta_traduce') is null then
    raise exception 'Ese motor no esta configurado' using errcode = '55000', hint = 'no_configurado';
  end if;
  v_hueco := case when p_accion = 'redacta' then v_max + 2 * public._editor_ia_coste_max('redacta_traduce') else v_max end;
  if p_accion = 'redacta_traduce' then
    if exists (select 1 from public.editor_ia_redaccion x where x.origen = p_origen and x.idioma = p_idioma and x.estado in ('reservado', 'hecho')) then
      raise exception 'Ese idioma ya esta traducido o en curso' using errcode = 'P0001', hint = 'ya_traducido';
    end if;
    select count(*) into v_n from public.editor_ia_redaccion x where x.origen = p_origen and x.idioma = p_idioma;
    if v_n >= 3 then raise exception 'Demasiados intentos para ese idioma: vuelve a pedir la redaccion' using errcode = 'P0001', hint = 'intentos'; end if;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('editor_ia/usuario/' || v_uid::text, 0));
  -- el tope por persona y minuto cuenta las DOS tablas (si no, se esquivaría alternando acciones)
  select (select count(*) from public.editor_ia_uso u where u.usuario = v_uid and u.fecha > now() - interval '1 minute')
       + (select count(*) from public.editor_ia_redaccion r where r.usuario = v_uid and r.fecha > now() - interval '1 minute') into v_min;
  if v_min >= 6 then raise exception 'Demasiadas consultas seguidas: espera un minuto' using errcode = 'P0001', hint = 'tope_minuto'; end if;
  select * into s from public.servicios_axisworks_ajustes x where x.id;
  if s.margen_pct is null then
    raise exception 'Asistente apagado: falta el margen' using errcode = '55000', hint = 'apagado', detail = 'sin_configurar';
  end if;
  v_gasto := public._servicios_gasto_mes(p_empresa, v_per);
  v_tope := public._servicios_tope_empresa(p_empresa);
  if v_gasto + v_hueco > v_tope then
    raise exception 'Esta empresa ha llegado a su tope de % USD de este mes', v_tope using errcode = 'P0001', hint = 'tope_empresa';
  end if;
  v_inst := public._servicios_gasto_mes(null, v_per);
  if v_inst + v_hueco > s.tope_instancia_usd then
    raise exception 'El asistente ha llegado al tope de gasto de este mes' using errcode = 'P0001', hint = 'tope_global';
  end if;
  insert into public.editor_ia_redaccion (empresa, usuario, autor, periodo, accion, origen, idioma, huella_entrada, coste_max_usd, margen_pct)
  values (p_empresa, v_uid, v_autor, v_per, p_accion, p_origen, p_idioma, p_huella_entrada, v_max, s.margen_pct)
  returning id into v_id;
  return jsonb_build_object('uso', v_id, 'coste_max_usd', round(v_max, 4), 'gasto_usd', round(v_gasto + v_max, 2), 'tope_usd', v_tope,
                            'aviso', v_gasto + v_max >= v_tope * s.aviso_pct / 100.0);
end $$;
revoke all on function public.editor_ia_redaccion_reserva(text, text, uuid, text, text) from public, anon, service_role;
grant execute on function public.editor_ia_redaccion_reserva(text, text, uuid, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── los pasos de la edge (solo service_role)
-- UNA función para los cuatro momentos (menos exposición que cuatro): 'enviada' justo antes de llamar al proveedor; 'hecho' con tokens reales
-- y la huella de lo validado; 'fallo' (corte, respuesta que no vale, sin clave); 'rechazada' (el proveedor contestó con error HTTP: no cobró,
-- coste 0). Misma regla de coste que editor_ia_cierra / editor_ia_rechazada. Devuelve false si el apunte ya no estaba «reservado».
create function public.editor_ia_redaccion_paso(p_uso uuid, p_paso text, p_modelo text default null, p_entrada integer default 0,
                                                p_salida integer default 0, p_http integer default null, p_huella text default null)
 returns boolean language plpgsql security definer set search_path = '' as $$
declare u public.editor_ia_redaccion%rowtype; a public.editor_ia_ajustes%rowtype; v_coste numeric; v_sabe boolean; v_ok boolean;
begin
  if p_paso is null or p_paso not in ('enviada', 'hecho', 'fallo', 'rechazada') then raise exception 'Paso no valido' using errcode = '22023'; end if;
  if p_paso = 'enviada' then
    update public.editor_ia_redaccion set enviada_en = now() where id = p_uso and estado = 'reservado' and enviada_en is null;
    return found;
  end if;
  perform public._editor_ia_candado();
  select * into u from public.editor_ia_redaccion x where x.id = p_uso for update;
  if not found then raise exception 'Uso no encontrado' using errcode = '22023'; end if;
  if u.estado <> 'reservado' then return false; end if;                        -- ya cerrado o caducado: no se cuenta dos veces
  if p_paso = 'rechazada' then
    if p_http is null or p_http not between 400 and 599 then raise exception 'Codigo HTTP no valido' using errcode = '22023'; end if;
    if u.enviada_en is null then raise exception 'Ese uso no se llego a enviar' using errcode = '22023'; end if;
    update public.editor_ia_redaccion set estado = 'fallo', cerrada_en = now(), coste_usd = 0, importe_usd = null, rechazada_http = p_http,
           tokens_entrada = 0, tokens_salida = 0 where id = u.id;
    return true;
  end if;
  v_ok := p_paso = 'hecho';
  if v_ok and coalesce(p_huella, '') !~ '^[0-9a-f]{64}$' then raise exception 'Huella no valida' using errcode = '22023'; end if;
  select * into a from public.editor_ia_ajustes x where x.id;
  v_sabe := v_ok or coalesce(p_entrada, 0) > 0 or coalesce(p_salida, 0) > 0 or u.enviada_en is null;
  v_coste := case when not v_sabe then null
                  else (greatest(coalesce(p_entrada, 0), 0) * a.tarifa_entrada_usd_mtok + greatest(coalesce(p_salida, 0), 0) * a.tarifa_salida_usd_mtok) / 1000000.0 end;
  update public.editor_ia_redaccion set estado = case when v_ok then 'hecho' else 'fallo' end, cerrada_en = now(), modelo = left(p_modelo, 80),
         tokens_entrada = greatest(coalesce(p_entrada, 0), 0), tokens_salida = greatest(coalesce(p_salida, 0), 0),
         huella_propuesta = case when v_ok then p_huella end, coste_usd = v_coste,
         importe_usd = case when v_ok and v_coste is not null then v_coste * (1 + coalesce(u.margen_pct, 0) / 100.0) end
   where id = u.id;
  return true;
end $$;
revoke all on function public.editor_ia_redaccion_paso(uuid, text, text, integer, integer, integer, text) from public, anon, authenticated;
grant execute on function public.editor_ia_redaccion_paso(uuid, text, text, integer, integer, integer, text) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── estado (pantalla del editor)
-- Misma firma y forma que 20261013220000; añade redacta, redacta_traduce y «redacta_completo» (a + 2 × b, lo que cuesta como mucho crear un
-- contrato desde una frase) a coste_max / precio_max / puede, y «facturado_usd» suma la tabla hermana.
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
  foreach k in array array['propone', 'traduce_ia', 'traduce_deepl', 'redacta', 'redacta_traduce', 'redacta_completo'] loop
    v_max := case when k = 'redacta_completo' then public._editor_ia_coste_max('redacta') + 2 * public._editor_ia_coste_max('redacta_traduce')
                  else public._editor_ia_coste_max(k) end;
    v_cm := v_cm || jsonb_build_object(k, round(v_max, 4));
    v_pm := v_pm || jsonb_build_object(k, ceil(v_max * (1 + s.margen_pct / 100.0) * 100) / 100.0);
    v_puede := v_puede || jsonb_build_object(k, v_max is not null and v_gasto + v_max <= v_tope and v_inst + v_max <= s.tope_instancia_usd);
    if k in ('propone', 'traduce_ia') and v_max is not null then v_min := least(coalesce(v_min, v_max), v_max); end if;
  end loop;
  v_lleno := case when v_min is null then null
                  when v_gasto + v_min > v_tope then 'empresa'
                  when v_inst + v_min > s.tope_instancia_usd then 'instancia' end;
  select coalesce((select sum(u.importe_usd) from public.editor_ia_uso u where u.empresa = p_empresa and u.periodo = v_per and u.estado = 'hecho'), 0)
       + coalesce((select sum(r.importe_usd) from public.editor_ia_redaccion r where r.empresa = p_empresa and r.periodo = v_per and r.estado = 'hecho'), 0)
    into v_fact;
  return jsonb_build_object('encendido', true, 'motivo', null, 'motivo_clave', null, 'periodo', v_per,
    'gasto_usd', round(v_gasto, 2), 'tope_usd', v_tope, 'pct', least(100, floor(100 * v_gasto / v_tope))::int,
    'facturado_usd', round(coalesce(v_fact, 0), 2),
    'aviso', v_gasto >= v_tope * s.aviso_pct / 100.0, 'lleno', v_lleno is not null, 'lleno_por', v_lleno, 'puede', v_puede,
    'deepl', public._editor_ia_coste_max('traduce_deepl') is not null, 'coste_max', v_cm, 'precio_max', v_pm);
end $$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── Ajustes → Servicios (extracto con las dos tablas)
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
    -- Extracto de los 3 últimos meses: las llamadas del editor (editor_ia_uso) y las de «contrato desde una frase» (editor_ia_redaccion),
    -- juntas por empresa y mes. Misma regla de redondeo: una vez por total; «no repercutido» y «margen» salen de restar (las líneas suman).
    'extracto', coalesce((select jsonb_agg(x order by x ->> 'periodo' desc, x ->> 'empresa') from (
        select jsonb_build_object('periodo', u.periodo, 'empresa', u.empresa,
                 'llamadas', count(*), 'hechas', count(*) filter (where u.estado = 'hecho'),
                 'fallidas', count(*) filter (where u.estado in ('fallo', 'caducada')), 'en_vuelo', count(*) filter (where u.estado = 'reservado'),
                 'rechazadas', count(*) filter (where u.rechazada_http is not null),
                 'redacciones', count(*) filter (where u.tabla = 'r'),
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
          from (select 'u'::text as tabla, e.periodo, e.empresa, e.estado, e.rechazada_http, e.coste_usd, e.importe_usd, e.margen_pct, e.aceptada_en,
                       e.tokens_entrada, e.tokens_salida, e.enviada_en
                  from public.editor_ia_uso e where e.periodo >= (v_per - interval '2 months')::date
                union all
                select 'r', r.periodo, r.empresa, r.estado, r.rechazada_http, r.coste_usd, r.importe_usd, r.margen_pct, r.aceptada_en,
                       r.tokens_entrada, r.tokens_salida, r.enviada_en
                  from public.editor_ia_redaccion r where r.periodo >= (v_per - interval '2 months')::date) u
         group by u.periodo, u.empresa) t), '[]'::jsonb),
    'registro', coalesce((select jsonb_agg(jsonb_build_object('ambito', l.ambito, 'antes', l.antes, 'despues', l.despues, 'motivo', l.motivo, 'autor', l.autor, 'fecha', l.fecha) order by l.id desc)
                            from (select * from public.servicios_axisworks_log order by id desc limit 30) l), '[]'::jsonb));
end $$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── el contrato en blanco, con partes y firmas
-- Antes (E9, 20261010030000) el contrato en blanco no traía partes, firmas, ley ni idioma: cada contrato propio salía sin identificar a nadie
-- ni decir qué ley rige. Ahora (Legal 13-oct, revisión previa de E10):
--   · «Las Partes»: Primera Parte con los marcadores de la sociedad de la empresa y Segunda Parte con sus DOS redacciones (persona / empresa,
--     contracts/comprador_empresa.test.js), texto literal de la Adenda (contracts/templates/adenda.html), en <!--bloque-fijo:partes-->.
--   · Las cláusulas: una sección <h2> por cláusula (los títulos se fijan al crear; el texto se escribe en el editor o lo trae el asistente).
--   · «Ley aplicable, arbitraje e idioma» en <!--bloque-fijo:foro_ley-->: ley = commercial_collaboration.html:142-144 con «Contrato»;
--     arbitraje = Adenda tal cual (no remite a ningún contrato madre); idioma = Adenda (Ley 24/2009, prevalece el indonesio). La cláusula de
--     idioma va DENTRO de foro_ley porque _plantilla_analiza solo admite una lista cerrada de nombres de bloque fijo (no hay «idioma»).
--     Aviso de Legal que va al owner, no aquí: el SIAC es desproporcionado para un contrato pequeño con un particular (UU 8/1999, BPSK).
--   · «Suscrito como acuerdo» en <!--bloque-fijo:firmas-->: firmas de la Adenda con «Nama» y «Jabatan» también en indonesio, y SOLO la imagen
--     de firma de la sociedad de la empresa (la Adenda trae las dos y la de Lawang hace saltar _plantilla_otra_sociedad en Sandal Woods).
--   · «Nº de contrato / Contract No. / No. Kontrak» con {{contrato_num}}; se conservan <!--extra-clauses--> y <!--firmas-adquirientes-->.
-- p_clausulas: [{ titulo: {es,en,id}, parrafos: [{es,en,id}] | null }]; sin párrafos = el texto de ejemplo «[Escribe aquí…]» (no activable).
-- Los textos llegan YA validados (sin «<», sin control); aquí solo se escapa «&».
create function public._plantilla_cuerpo_asistente(p_nombre text, p_campos text[], p_empresa text, p_clausulas jsonb)
 returns text language plpgsql stable security definer set search_path = '' as $$
declare
  v text; c text; f record; cl jsonb; pp jsonb; i int := 0; soc text; firma text := '';
  nom text := replace(btrim(p_nombre), '&', '&amp;');
  L constant text[] := array['es', 'en', 'id'];
  lg text;
begin
  select e.sociedad_clave into soc from public.empresas e where e.clave = p_empresa;
  if soc = 'tepi_sungai' then
    firma := '<!--if:sociedad_firmante=tepi_sungai--><img src="assets/brand/firma-lawang.png" alt="" style="max-height:20mm;max-width:100%"><!--/if:sociedad_firmante-->';
  elsif soc = 'san_dal_woods' then
    firma := '<!--if:sociedad_firmante=san_dal_woods--><img src="assets/brand/firma-sandalwoods.png" alt="" style="max-height:20mm;max-width:100%"><!--/if:sociedad_firmante-->';
  end if;
  v := E'<!DOCTYPE html>\n<html lang="es">\n<head>\n<meta charset="UTF-8">\n<title>' || nom || E'</title>\n</head>\n<body>\n  <div class="doc">\n'
    || '    <div class="doc-title"><span class="bold"><span data-lang="es">' || nom || '</span><span data-lang="en">' || nom || '</span><span data-lang="id">' || nom || E'</span></span></div>\n'
    || '    <div class="doc-date"><span data-lang="es">En Indonesia, a fecha <span class="f f-sm">{{fecha_firma}}</span> · Nº de contrato: <span class="f f-md">{{contrato_num}}</span></span>'
    || '<span data-lang="en">In Indonesia, dated <span class="f f-sm">{{fecha_firma}}</span> · Contract No.: <span class="f f-md">{{contrato_num}}</span></span>'
    || '<span data-lang="id">Di Indonesia, tertanggal <span class="f f-sm">{{fecha_firma}}</span> · No. Kontrak: <span class="f f-md">{{contrato_num}}</span></span></div>' || E'\n\n'
    -- Las Partes (texto literal de la Adenda)
    || E'    <!--bloque-fijo:partes-->\n'
    || E'    <h2><span data-lang="es">Las Partes</span><span data-lang="en">The Parties</span><span data-lang="id">Para Pihak</span></h2>\n'
    || E'    <div class="party">\n'
    || E'      <div class="role"><span data-lang="es">Primera Parte</span><span data-lang="en">First Party</span><span data-lang="id">Pihak Pertama</span></div>\n'
    || E'      <p data-lang="es">1. {{prom_razon}}, sociedad constituida conforme a las leyes de la República de Indonesia,<!--opt:prom_marca--> propietaria de la marca registrada en Indonesia {{prom_marca}},<!--/opt:prom_marca--> con domicilio registrado en {{prom_domicilio}}, NPWP {{prom_npwp}}. En este acto representada por D. {{prom_rep}}, actuando en su calidad de Director, {{prom_cred_es}} (en adelante, la «Primera Parte»).</p>\n'
    || E'      <p data-lang="en">1. {{prom_razon}}, a company incorporated under the laws of the Republic of Indonesia,<!--opt:prom_marca--> owner of the trademark registered in Indonesia {{prom_marca}},<!--/opt:prom_marca--> with registered address at {{prom_domicilio}}, NPWP {{prom_npwp}}. Represented herein by Mr. {{prom_rep}}, acting as Director, {{prom_cred_en}} (hereinafter, the "First Party").</p>\n'
    || E'      <p data-lang="id">1. {{prom_razon}}, perusahaan yang didirikan berdasarkan hukum Republik Indonesia,<!--opt:prom_marca--> pemilik merek dagang terdaftar di Indonesia {{prom_marca}},<!--/opt:prom_marca--> beralamat terdaftar di {{prom_domicilio}}, NPWP {{prom_npwp}}. Dalam hal ini diwakili oleh Tn. {{prom_rep}}, bertindak sebagai Direktur, {{prom_cred_id}} (selanjutnya disebut "Pihak Pertama").</p>\n'
    || E'    </div>\n'
    || E'    <div class="party">\n'
    || E'      <div class="role"><span data-lang="es">Segunda Parte</span><span data-lang="en">Second Party</span><span data-lang="id">Pihak Kedua</span></div>\n'
    || E'      <!--if:adq1_tipo=persona-->\n'
    || E'      <p data-lang="es">2. <span class="f">{{adq1_nombre}}</span>, de nacionalidad <span class="f">{{adq1_nacionalidad}}</span>, titular del pasaporte n.º <span class="f">{{adq1_pasaporte}}</span>, teléfono <span class="f">{{adq1_telefono}}</span> y email <span class="f">{{adq1_email}}</span>. En este acto actuando en nombre propio (en adelante, la «Segunda Parte»).</p>\n'
    || E'      <p data-lang="en">2. <span class="f">{{adq1_nombre}}</span>, of <span class="f">{{adq1_nacionalidad}}</span> nationality, holder of passport no. <span class="f">{{adq1_pasaporte}}</span>, telephone <span class="f">{{adq1_telefono}}</span> and email <span class="f">{{adq1_email}}</span>. Acting herein in their own name (hereinafter, the "Second Party").</p>\n'
    || E'      <p data-lang="id">2. <span class="f">{{adq1_nombre}}</span>, berkewarganegaraan <span class="f">{{adq1_nacionalidad}}</span>, pemegang paspor no. <span class="f">{{adq1_pasaporte}}</span>, telepon <span class="f">{{adq1_telefono}}</span> dan email <span class="f">{{adq1_email}}</span>. Dalam hal ini bertindak atas nama sendiri (selanjutnya disebut "Pihak Kedua").</p>\n'
    || E'      <!--/if:adq1_tipo-->\n'
    || E'      <!--if:adq1_tipo=empresa-->\n'
    || E'      <p data-lang="es">2. <span class="f">{{adq1_nombre}}</span>, sociedad de nacionalidad <span class="f">{{adq1_nacionalidad}}</span>, con número de registro <span class="f">{{adq1_registro_num}}</span>, teléfono <span class="f">{{adq1_telefono}}</span> y email <span class="f">{{adq1_email}}</span>. En este acto representada por <span class="f">{{adq1_rep_nombre}}</span>, en calidad de <span class="f">{{adq1_rep_cargo}}</span> (en adelante, la «Segunda Parte»).</p>\n'
    || E'      <p data-lang="en">2. <span class="f">{{adq1_nombre}}</span>, a company of <span class="f">{{adq1_nacionalidad}}</span> nationality, registration number <span class="f">{{adq1_registro_num}}</span>, telephone <span class="f">{{adq1_telefono}}</span> and email <span class="f">{{adq1_email}}</span>. Represented herein by <span class="f">{{adq1_rep_nombre}}</span>, as <span class="f">{{adq1_rep_cargo}}</span> (hereinafter, the "Second Party").</p>\n'
    || E'      <p data-lang="id">2. <span class="f">{{adq1_nombre}}</span>, perusahaan berkewarganegaraan <span class="f">{{adq1_nacionalidad}}</span>, dengan nomor registrasi <span class="f">{{adq1_registro_num}}</span>, telepon <span class="f">{{adq1_telefono}}</span> dan email <span class="f">{{adq1_email}}</span>. Dalam hal ini diwakili oleh <span class="f">{{adq1_rep_nombre}}</span>, selaku <span class="f">{{adq1_rep_cargo}}</span> (selanjutnya disebut "Pihak Kedua").</p>\n'
    || E'      <!--/if:adq1_tipo-->\n'
    || E'    </div>\n'
    || E'    <!--/bloque-fijo:partes-->\n\n';
  -- Las cláusulas: una sección por cláusula, numerada
  for cl in select x from jsonb_array_elements(coalesce(p_clausulas, '[]'::jsonb)) x loop
    i := i + 1;
    v := v || '    <h2>';
    foreach lg in array L loop
      v := v || '<span data-lang="' || lg || '">' || i || '. ' || replace(coalesce(cl -> 'titulo' ->> lg, ''), '&', '&amp;') || '</span>';
    end loop;
    v := v || E'</h2>\n';
    if jsonb_typeof(cl -> 'parrafos') = 'array' and jsonb_array_length(cl -> 'parrafos') > 0 then
      for pp in select x from jsonb_array_elements(cl -> 'parrafos') x loop
        foreach lg in array L loop
          v := v || '    <p data-lang="' || lg || '">' || replace(coalesce(pp ->> lg, ''), '&', '&amp;') || E'</p>\n';
        end loop;
      end loop;
    else
      v := v || E'    <p data-lang="es">[Escribe aquí el texto de esta cláusula]</p>\n'
             || E'    <p data-lang="en">[Write here the text of this clause]</p>\n'
             || E'    <p data-lang="id">[Tulis di sini isi klausul ini]</p>\n';
    end if;
  end loop;
  -- Los campos propios elegidos, con su etiqueta del catálogo
  if coalesce(cardinality(p_campos), 0) > 0 then
    v := v || E'\n    <h2><span data-lang="es">Datos del contrato</span><span data-lang="en">Contract details</span><span data-lang="id">Data perjanjian</span></h2>\n';
    foreach c in array p_campos loop
      select replace(pf.etiqueta_es, '&', '&amp;') as es, replace(coalesce(pf.etiqueta_en, pf.etiqueta_es), '&', '&amp;') as en, replace(coalesce(pf.etiqueta_id, pf.etiqueta_es), '&', '&amp;') as id
        into f from public.plantilla_campos_propios pf where pf.empresa = p_empresa and pf.clave = c and not pf.archivado;
      v := v || '    <p data-lang="es">' || f.es || ': <span class="f f-md">{{' || c || E'}}</span></p>\n'
             || '    <p data-lang="en">' || f.en || ': <span class="f f-md">{{' || c || E'}}</span></p>\n'
             || '    <p data-lang="id">' || f.id || ': <span class="f f-md">{{' || c || E'}}</span></p>\n';
    end loop;
  end if;
  -- Ley aplicable, arbitraje e idioma (Legal 13-oct)
  v := v || E'\n    <!--bloque-fijo:foro_ley-->\n'
    || E'    <h2><span data-lang="es">Ley aplicable, arbitraje e idioma</span><span data-lang="en">Governing law, arbitration and language</span><span data-lang="id">Hukum yang berlaku, arbitrase dan bahasa</span></h2>\n'
    || E'    <p data-lang="es">Este Contrato se regirá e interpretará de conformidad con las leyes de la República de Indonesia.</p>\n'
    || E'    <p data-lang="en">This Contract shall be governed by and construed in accordance with the laws of the Republic of Indonesia.</p>\n'
    || E'    <p data-lang="id">Kontrak ini diatur dan ditafsirkan sesuai dengan hukum Republik Indonesia.</p>\n'
    || E'    <p data-lang="es">Cualquier controversia se resolverá, en primer lugar, mediante negociación amistosa entre las Partes durante 30 (treinta) días naturales desde su notificación escrita. De no alcanzarse acuerdo, la controversia se someterá a arbitraje administrado bajo las reglas del Singapore International Arbitration Centre (SIAC), con sede en Singapur, ante un árbitro único, en idioma español e inglés, siendo el laudo definitivo y vinculante, con renuncia expresa a cualquier otro fuero.</p>\n'
    || E'    <p data-lang="en">Any dispute shall first be resolved through amicable negotiation between the Parties for 30 (thirty) calendar days from written notice thereof. If no agreement is reached, the dispute shall be submitted to arbitration administered under the rules of the Singapore International Arbitration Centre (SIAC), seated in Singapore, before a sole arbitrator, in the Spanish and English languages, with the award being final and binding, with express waiver of any other jurisdiction.</p>\n'
    || E'    <p data-lang="id">Setiap perselisihan pertama-tama diselesaikan melalui negosiasi damai antara Para Pihak selama 30 (tiga puluh) hari kalender sejak pemberitahuan tertulis. Apabila tidak tercapai kesepakatan, perselisihan diajukan ke arbitrase yang diselenggarakan berdasarkan aturan Singapore International Arbitration Centre (SIAC), berkedudukan di Singapura, di hadapan seorang arbiter tunggal, dalam bahasa Spanyol dan Inggris, dengan putusan yang bersifat final dan mengikat, dengan pelepasan tegas atas yurisdiksi lain.</p>\n'
    || E'    <p data-lang="es">Este documento se otorga en español, inglés y bahasa indonesia. Conforme a la Ley nº 24/2009 sobre uso obligatorio del idioma indonesio, <b>prevalecerá la versión en bahasa indonesia</b> en caso de discrepancia entre versiones, y será la presentada ante autoridades y registros indonesios. Las versiones en español e inglés son traducciones fieles de aquélla y se otorgan para la comprensión de las Partes.</p>\n'
    || E'    <p data-lang="en">This document is executed in Spanish, English and Indonesian (bahasa). Pursuant to Law no. 24/2009 on the mandatory use of the Indonesian language, <b>the Indonesian version shall prevail</b> in the event of any discrepancy between versions, and shall be the one filed with Indonesian authorities and registries. The Spanish and English versions are faithful translations thereof and are executed for the Parties'' understanding.</p>\n'
    || E'    <p data-lang="id">Dokumen ini dibuat dalam bahasa Spanyol, Inggris, dan Indonesia. Sesuai Undang-Undang No. 24/2009 tentang kewajiban penggunaan bahasa Indonesia, <b>versi bahasa Indonesia yang berlaku</b> apabila terdapat perbedaan antar versi, dan versi tersebut yang diajukan kepada otoritas dan pendaftaran di Indonesia. Versi bahasa Spanyol dan Inggris merupakan terjemahan yang setia dan dibuat untuk pemahaman Para Pihak.</p>\n'
    || E'    <!--/bloque-fijo:foro_ley-->\n\n'
    || E'    <!--extra-clauses-->\n\n'
    -- Firmas (Adenda, con Nama / Jabatan también en indonesio y solo la firma de la sociedad de la empresa)
    || E'    <!--bloque-fijo:firmas-->\n'
    || E'    <h2><span data-lang="es">Suscrito como acuerdo</span><span data-lang="en">Agreed and signed</span><span data-lang="id">Disepakati dan ditandatangani</span></h2>\n'
    || E'    <table class="pays sigs" style="margin-top:14px">\n      <tbody>\n        <tr>\n          <td>\n'
    || E'            <div class="role"><span data-lang="es">Primera Parte — {{prom_razon}}</span><span data-lang="en">First Party — {{prom_razon}}</span><span data-lang="id">Pihak Pertama — {{prom_razon}}</span></div>\n'
    || '            <div style="height:22mm;border-bottom:1px solid var(--ss,#BEB3A5);display:flex;align-items:flex-end">' || firma || E'</div>\n'
    || E'            <p style="margin-top:4px;font-size:9pt"><span data-lang="es">Nombre / Nama</span><span data-lang="en">Name / Nama</span><span data-lang="id">Nama</span>: {{prom_rep}} — <span data-lang="es">Cargo / Jabatan: Director / Direktur</span><span data-lang="en">Position / Jabatan: Director / Direktur</span><span data-lang="id">Jabatan: Direktur</span></p>\n'
    || E'          </td>\n          <td>\n'
    || E'            <div class="role"><span data-lang="es">Segunda Parte</span><span data-lang="en">Second Party</span><span data-lang="id">Pihak Kedua</span></div>\n'
    || E'            <div style="height:22mm;border-bottom:1px solid var(--ss,#BEB3A5);display:flex;align-items:flex-end"><img src="{{firma_adquiriente}}" alt="" style="max-height:22mm;max-width:100%"></div>\n'
    || E'            <p style="margin-top:4px;font-size:9pt"><span data-lang="es">Nombre / Nama</span><span data-lang="en">Name / Nama</span><span data-lang="id">Nama</span>: <span class="f">{{adq1_nombre}}</span></p>\n'
    || E'            <!--firmas-adquirientes-->\n'
    || E'          </td>\n        </tr>\n      </tbody>\n    </table>\n'
    || E'    <!--/bloque-fijo:firmas-->\n';
  return v || E'  </div>\n</body>\n</html>';
end $$;

-- MISMA firma que E9. Sin más, tres cláusulas de ejemplo como antes (Objeto, Condiciones, Disposiciones finales). Si la función que crea desde
-- el asistente fijó en ESTA transacción los títulos de sus cláusulas (lw.esqueleto_asistente), el esqueleto lleva esas secciones: así el
-- borrador con el texto del asistente tiene EXACTAMENTE la estructura del esqueleto. Lo que llegue mal formado ahí se ignora (vuelven las tres
-- de ejemplo): un cliente no puede fijar ese ajuste por PostgREST y, si pudiera, solo cambiaría los títulos de SU contrato nuevo.
create or replace function public._plantilla_esqueleto_en_blanco(p_nombre text, p_campos text[], p_empresa text)
 returns text language plpgsql stable security definer set search_path = '' as $$
declare j jsonb; s text := pg_catalog.current_setting('lw.esqueleto_asistente', true); ok boolean := false;
begin
  if coalesce(s, '') <> '' then
    begin
      j := s::jsonb;
      ok := jsonb_typeof(j) = 'array' and jsonb_array_length(j) between 1 and 8
            and not exists (select 1 from jsonb_array_elements(j) t, unnest(array['es', 'en', 'id']) lg
                             where jsonb_typeof(t -> lg) <> 'string' or length(t ->> lg) not between 1 and 120
                                or (t ->> lg) ~ '[<>{}\x01-\x1f\x7f]');
    exception when others then ok := false;
    end;
  end if;
  if ok then
    return public._plantilla_cuerpo_asistente(p_nombre, p_campos, p_empresa,
             (select jsonb_agg(jsonb_build_object('titulo', t) order by n) from jsonb_array_elements(j) with ordinality q(t, n)));
  end if;
  return public._plantilla_cuerpo_asistente(p_nombre, p_campos, p_empresa, jsonb_build_array(
    jsonb_build_object('titulo', jsonb_build_object('es', 'Objeto del contrato', 'en', 'Purpose of the agreement', 'id', 'Objek perjanjian')),
    jsonb_build_object('titulo', jsonb_build_object('es', 'Condiciones', 'en', 'Terms', 'id', 'Ketentuan')),
    jsonb_build_object('titulo', jsonb_build_object('es', 'Disposiciones finales', 'en', 'Final provisions', 'id', 'Ketentuan penutup'))));
end $$;
revoke all on function public._plantilla_cuerpo_asistente(text, text[], text, jsonb), public._plantilla_esqueleto_en_blanco(text, text[], text)
  from public, anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── crear el contrato desde la propuesta
-- UNA transacción (decisión por defecto 13-oct; Seguridad 13-oct punto 4): o queda el contrato entero o no queda nada.
--   1. la redacción es de quien llama, de su empresa, terminó bien, tiene menos de 2 h, no se usó, y tiene sus dos traducciones hechas;
--   2. la propuesta que manda el navegador tiene EXACTAMENTE las huellas que la edge apuntó (español = paso a; inglés e indonesio = paso b):
--      el navegador no fabrica el texto que se guarda. El NOMBRE sí lo puede cambiar la persona: se valida aparte y lleva « (IA)»;
--   3. forma y topes otra vez (8 campos, 8 cláusulas × 3 párrafos), y los {{…}} de cada párrafo son campos de la propia propuesta e iguales en
--      los tres idiomas;
--   4. campos: uno que ya existe con el mismo tipo se REUTILIZA sin tocarlo (otras plantillas usan sus etiquetas); con otro tipo o archivado,
--      el nuevo se renombra (_2, _3…) en la propuesta entera; los que faltan se crean (sensibles por defecto: el bot y la IA no los ven);
--   5. contrato nuevo en blanco con las secciones de sus cláusulas (plantilla_contrato_nuevo_crea, el mismo de E9: tope de 30, nombre único)
--      y su borrador con el texto por plantilla_contrato_guarda_borrador (el MISMO validador de siempre). Si el texto toca una parte sensible
--      (p. ej. «defectos» en una garantía) y la persona no ha confirmado el aviso, la base para con el mensaje de siempre y NO queda nada; la
--      pantalla enseña el aviso y, si la persona lo confirma, vuelve a llamar con p_confirma_sensibles = true (nunca lo manda sola);
--   6. el aviso de Legal (la IA lo redactó, el estudio no lo revisó, responde la empresa, prevalece el indonesio traducido a máquina) lo
--      tiene que haber aceptado la persona: se apunta quién, cuándo, qué versión del aviso y qué contrato salió.
-- Nada se activa: el borrador espera a que el super admin de la empresa lo active con su aviso de siempre.
create function public.plantilla_contrato_crea_desde_asistente(p_empresa text, p_uso uuid, p_propuesta jsonb, p_acepta_aviso boolean,
                                                               p_confirma_sensibles boolean default false)
 returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
  AVISO constant text := 'legal-2026-10-13';
  CTRL constant text := '[<>\x01-\x1f\x7f­​-‏‪-‮⁠⁦-⁩﻿]';
  r public.editor_ia_redaccion%rowtype; t_en public.editor_ia_redaccion%rowtype; t_id public.editor_ia_redaccion%rowtype;
  v_nom text; c jsonb; cl jsonb; pp jsonb; lg text; tx text; k text; k2 text; n int; pc public.plantilla_campos_propios%rowtype;
  v_claves text[] := '{}'; v_finales text[] := '{}'; v_renombres jsonb := '{}'::jsonb; v_txt text; v_marc text[]; v_ref text[];
  v_cr jsonb; v_body text; v_ver uuid; v_titulos jsonb;
begin
  if v_uid is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El texto de los contratos de una empresa lo escribe su administracion' using errcode = '42501';
  end if;
  if p_acepta_aviso is not true then
    raise exception 'Lee y acepta el aviso antes de crear el contrato' using errcode = '22023', hint = 'aviso';
  end if;
  -- 1. la redacción y sus traducciones
  select * into r from public.editor_ia_redaccion x where x.id = p_uso for update;
  if not found or r.usuario <> v_uid or r.empresa <> p_empresa or r.accion <> 'redacta' then
    raise exception 'Esa redaccion no existe' using errcode = '22023', hint = 'origen';
  end if;
  if r.estado <> 'hecho' then raise exception 'Esa redaccion no termino bien' using errcode = '22023', hint = 'origen'; end if;
  if r.aceptada_en is not null then raise exception 'Con esa redaccion ya se creo un contrato' using errcode = '22023', hint = 'usada'; end if;
  if r.fecha < now() - interval '2 hours' then raise exception 'La redaccion tiene mas de 2 horas: vuelve a pedirla' using errcode = '22023', hint = 'caducada'; end if;
  select * into t_en from public.editor_ia_redaccion x where x.origen = r.id and x.idioma = 'en' and x.estado = 'hecho';
  if not found then raise exception 'Falta la traduccion al ingles' using errcode = '22023', hint = 'traduccion'; end if;
  select * into t_id from public.editor_ia_redaccion x where x.origen = r.id and x.idioma = 'id' and x.estado = 'hecho';
  if not found then raise exception 'Falta la traduccion al indonesio' using errcode = '22023', hint = 'traduccion'; end if;

  -- 3 (forma, antes de calcular huellas sobre algo que no es lo esperado)
  if p_propuesta is null or jsonb_typeof(p_propuesta) <> 'object' or jsonb_typeof(p_propuesta -> 'campos') <> 'array'
     or jsonb_typeof(p_propuesta -> 'clausulas') <> 'array' or jsonb_typeof(p_propuesta -> 'nombre') <> 'string' then
    raise exception 'La propuesta no es valida' using errcode = '22023', hint = 'forma';
  end if;
  if jsonb_array_length(p_propuesta -> 'campos') > 8 or jsonb_array_length(p_propuesta -> 'clausulas') not between 1 and 8 then
    raise exception 'La propuesta no es valida (como mucho 8 campos y de 1 a 8 clausulas)' using errcode = '22023', hint = 'forma';
  end if;

  -- 2. huellas: el texto es el que la edge validó
  if public._editor_ia_huella_redaccion(p_propuesta, 'es') is distinct from r.huella_propuesta
     or public._editor_ia_huella_redaccion(p_propuesta, 'en') is distinct from t_en.huella_propuesta
     or public._editor_ia_huella_redaccion(p_propuesta, 'id') is distinct from t_id.huella_propuesta then
    raise exception 'La propuesta no es la que redacto el asistente' using errcode = '22023', hint = 'huella';
  end if;

  -- 3. campos
  for c in select x from jsonb_array_elements(p_propuesta -> 'campos') x loop
    k := c ->> 'clave';
    if jsonb_typeof(c) <> 'object' or coalesce(k, '') !~ '^cx_[a-z0-9_]{1,40}$' or k = any (v_claves)
       or coalesce(c ->> 'tipo', '') not in ('texto', 'numero', 'fecha', 'importe', 'lista', 'si_no') then
      raise exception 'La propuesta no es valida (campo)' using errcode = '22023', hint = 'forma';
    end if;
    foreach lg in array array['es', 'en', 'id'] loop
      tx := c ->> ('etiqueta_' || lg);
      if tx is null or length(tx) not between 1 and 60 or tx <> btrim(tx) or tx ~ CTRL or tx ~ '[{}]' then
        raise exception 'La propuesta no es valida (etiqueta de campo)' using errcode = '22023', hint = 'forma';
      end if;
    end loop;
    if c ->> 'tipo' = 'lista' then
      if not public._cx_opciones_ok(c -> 'opciones') or jsonb_array_length(c -> 'opciones') > 10 then
        raise exception 'La propuesta no es valida (opciones de lista)' using errcode = '22023', hint = 'forma';
      end if;
    elsif jsonb_typeof(c -> 'opciones') = 'array' and jsonb_array_length(c -> 'opciones') > 0 then
      raise exception 'La propuesta no es valida (solo una lista lleva opciones)' using errcode = '22023', hint = 'forma';
    end if;
    v_claves := v_claves || k;
  end loop;
  -- cláusulas: textos limpios, topes, y los {{…}} de cada párrafo = campos de la propuesta, iguales en los tres idiomas
  for cl in select x from jsonb_array_elements(p_propuesta -> 'clausulas') x loop
    if jsonb_typeof(cl -> 'titulo') <> 'object' or jsonb_typeof(cl -> 'parrafos') <> 'array' or jsonb_array_length(cl -> 'parrafos') not between 1 and 3 then
      raise exception 'La propuesta no es valida (clausula)' using errcode = '22023', hint = 'forma';
    end if;
    foreach lg in array array['es', 'en', 'id'] loop
      tx := cl -> 'titulo' ->> lg;
      if tx is null or length(tx) not between 1 and 120 or tx <> btrim(tx) or tx ~ CTRL or tx ~ '[{}]' then
        raise exception 'La propuesta no es valida (titulo)' using errcode = '22023', hint = 'forma';
      end if;
    end loop;
    for pp in select x from jsonb_array_elements(cl -> 'parrafos') x loop
      v_ref := null;
      foreach lg in array array['es', 'en', 'id'] loop
        tx := pp ->> lg;
        if tx is null or length(tx) not between 1 and 1200 or tx <> btrim(tx) or tx ~ CTRL
           or regexp_replace(tx, '\{\{cx_[a-z0-9_]{1,40}\}\}', '', 'g') ~ '[{}]' then
          raise exception 'La propuesta no es valida (parrafo)' using errcode = '22023', hint = 'forma';
        end if;
        v_marc := array(select m[1] from regexp_matches(tx, '\{\{(cx_[a-z0-9_]{1,40})\}\}', 'g') m order by 1);
        if exists (select 1 from unnest(v_marc) q where not q = any (v_claves)) then
          raise exception 'La propuesta usa un campo que no declara' using errcode = '22023', hint = 'forma';
        end if;
        if v_ref is null then v_ref := v_marc;
        elsif v_ref is distinct from v_marc then
          raise exception 'Un parrafo no lleva los mismos campos en los tres idiomas' using errcode = '22023', hint = 'forma';
        end if;
      end loop;
    end loop;
  end loop;

  -- nombre: lo puede cambiar la persona; siempre acaba en « (IA)» (la validación de 3-80 letras la hace nuevo_crea)
  v_nom := btrim(p_propuesta ->> 'nombre');
  if right(v_nom, 5) <> ' (IA)' then v_nom := v_nom || ' (IA)'; end if;

  -- 4. campos: reutilizar, renombrar o crear (renombrar antes de crear nada)
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cx/' || p_empresa, 0));
  for c in select x from jsonb_array_elements(p_propuesta -> 'campos') x loop
    k := c ->> 'clave';
    select * into pc from public.plantilla_campos_propios pf where pf.empresa = p_empresa and pf.clave = k;
    if found and pc.tipo = c ->> 'tipo' and not pc.archivado then
      v_finales := v_finales || k;                                            -- se reutiliza tal cual
      continue;
    end if;
    k2 := k;
    if found then
      n := 1;
      loop
        n := n + 1;
        k2 := left(k, 37) || '_' || n;
        exit when not exists (select 1 from public.plantilla_campos_propios pf where pf.empresa = p_empresa and pf.clave = k2)
              and not k2 = any (v_claves) and not k2 = any (v_finales);
        if n > 50 then raise exception 'No se ha podido dar nombre al campo %', k using errcode = '22023'; end if;
      end loop;
      v_renombres := v_renombres || jsonb_build_object(k, k2);
    end if;
    perform public.plantilla_campo_propio_guarda(p_empresa, k2, c ->> 'etiqueta_es', c ->> 'etiqueta_en', c ->> 'etiqueta_id', c ->> 'tipo',
                                                 case when c ->> 'tipo' = 'lista' then c -> 'opciones' end, false, true);
    v_finales := v_finales || k2;
  end loop;

  -- la propuesta con los campos renombrados, en el formato del cuerpo (dos pasadas con fichas de control: un renombre no pisa a otro)
  v_txt := (p_propuesta -> 'clausulas')::text;
  n := 0;
  for k, k2 in select * from jsonb_each_text(v_renombres) loop
    n := n + 1;
    v_txt := replace(v_txt, '{{' || k || '}}', chr(1) || n || chr(2));
  end loop;
  n := 0;
  for k, k2 in select * from jsonb_each_text(v_renombres) loop
    n := n + 1;
    v_txt := replace(v_txt, chr(1) || n || chr(2), '{{' || k2 || '}}');
  end loop;
  -- (chr(1)/chr(2) no pueden venir en la propuesta: lo comprueba CTRL arriba; y en el texto jsonb un control iría escapado como \u0001)
  v_titulos := (select jsonb_agg(q.x -> 'titulo' order by q.n) from jsonb_array_elements(v_txt::jsonb) with ordinality q(x, n));

  -- 5. el contrato nuevo (esqueleto con las secciones de sus cláusulas) y su borrador con el texto
  perform pg_catalog.set_config('lw.esqueleto_asistente', v_titulos::text, true);
  v_cr := public.plantilla_contrato_nuevo_crea(p_empresa, v_nom, 'blanco', null, null, to_jsonb(v_finales));
  perform pg_catalog.set_config('lw.esqueleto_asistente', '', true);
  v_body := public._plantilla_cuerpo_asistente(v_cr ->> 'nombre', v_finales, p_empresa, v_txt::jsonb);
  v_ver := public.plantilla_contrato_guarda_borrador(p_empresa, v_cr ->> 'slug', v_body,
             'Redactado por el asistente de IA desde una frase (sin revisar por el estudio)', 'estandar', p_confirma_sensibles is true);

  -- 6. el aviso aceptado y el contrato que salió
  update public.editor_ia_redaccion set aceptada_en = now(), aceptada_por = v_autor, aviso_aceptado = AVISO,
         slug_creado = v_cr ->> 'slug', version_creada = v_ver
   where id in (r.id, t_en.id, t_id.id);
  return jsonb_build_object('slug', v_cr ->> 'slug', 'nombre', v_cr ->> 'nombre', 'version_id', v_ver, 'campos', to_jsonb(v_finales),
                            'renombrados', v_renombres);
end $$;
revoke all on function public.plantilla_contrato_crea_desde_asistente(text, uuid, jsonb, boolean, boolean) from public, anon, service_role;
grant execute on function public.plantilla_contrato_crea_desde_asistente(text, uuid, jsonb, boolean, boolean) to authenticated;

do $comprueba$
begin
  if has_function_privilege('authenticated', 'public._plantilla_esqueleto_en_blanco(text, text[], text)', 'execute')
     or has_function_privilege('authenticated', 'public._plantilla_cuerpo_asistente(text, text[], text, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.editor_ia_redaccion_paso(uuid, text, text, integer, integer, integer, text)', 'execute')
     or has_function_privilege('authenticated', 'public._editor_ia_huella_redaccion(jsonb, text)', 'execute')
     or has_table_privilege('authenticated', 'public.editor_ia_redaccion', 'select') then
    raise exception 'Permiso de mas en E10';
  end if;
  if not has_function_privilege('authenticated', 'public.plantilla_contrato_crea_desde_asistente(text, uuid, jsonb, boolean, boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.editor_ia_redaccion_reserva(text, text, uuid, text, text)', 'execute') then
    raise exception 'Falta un permiso de E10';
  end if;
end $comprueba$;
