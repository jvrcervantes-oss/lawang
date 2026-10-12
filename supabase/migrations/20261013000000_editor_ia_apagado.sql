-- Asistente de redacción y traducción por IA del editor de textos de contrato — E4, E4b, E5 y E5b del encargo
-- encargos/20261008_lawang_editor_textos_contrato.md (agencia). Construido APAGADO por decisión del owner (12-oct-2026,
-- «Constrúyelo apagado»): nadie lo usa ni se cobra nada hasta que el owner rellene los precios en la pantalla
-- (Textos de contrato → pestaña «Asistente IA», solo el super administrador global) y encienda una empresa.
-- Revisión previa del 8-oct (Seguridad, Administración, Diseño) y #225 (Datos, Seguridad, Bots), plegadas aquí.
--
-- DUEÑO DE CADA DATO (ninguna tabla tiene GRANT a anon ni a authenticated: todo pasa por las funciones de abajo)
--   editor_ia_ajustes         UNA fila (la instancia): precio del crédito, moneda, créditos por acción, tope global mensual,
--                             a quién se factura, si caducan, créditos de prueba y tarifas del proveedor (coste real).
--                             Nace VACÍA. La escribe solo editor_ia_ajustes_guarda (super admin global).
--   editor_ia_empresa         encendido (por defecto NO), créditos incluidos al mes y tope mensual de cada empresa. Mismo escritor.
--   editor_ia_ajustes_log     cada cambio de las dos anteriores: antes, después, motivo, quién, cuándo. Solo se añade.
--   editor_ia_saldo           créditos usados por (empresa, mes) y por ('*' = la instancia entera, mes). Solo lo mueven
--                             la reserva (sube) y el cierre de una llamada fallida (devuelve).
--   editor_ia_uso             un apunte por llamada: quién, cuándo, qué plantilla, cuántos párrafos y créditos, modelo,
--                             tokens o caracteres, huella de la propuesta. NUNCA el texto del contrato ni la instrucción.
--   editor_ia_traduccion_marca  huella (sha256) de cada trozo traducido automáticamente y si alguien lo dio por revisado.
--
-- QUIÉN LLAMA A CADA FUNCIÓN (reducir la exposición, seguridad_2026.md §1.ter)
--   editor_ia_estado          authenticated · textos-contrato-ia.js (saldo y si está encendido, en llano)
--   editor_ia_reserva         authenticated · edge editor-ia, con el JWT de la persona (la identidad la pone la base, no la edge).
--                             Llamarla a mano desde el navegador ocupa créditos sin recibir nada; a los 10 min caducan y vuelven
--                             (las de TODAS las empresas: si no, una empresa podría tener llena la jaula global de las demás).
--   editor_ia_cierra          SOLO service_role · edge editor-ia: escribe tokens, modelo y caracteres REALES. Ningún navegador.
--   editor_ia_enviada         SOLO service_role · edge editor-ia, justo antes de llamar al proveedor (la jaula ya no devuelve).
--   editor_ia_aceptada        authenticated · textos-contrato-ia.js tras guardar el borrador (la propuesta quedó en una versión)
--   editor_ia_marcas          authenticated · textos-contrato-ia.js (qué trozos están «traducidos, sin revisar»)
--   editor_ia_marca_revisada  authenticated · textos-contrato-ia.js («Ya lo he revisado»)
--   editor_ia_ajustes_datos   authenticated (dentro: super admin global) · textos-contrato-ia.js, pestaña Asistente IA
--   editor_ia_ajustes_guarda  authenticated (dentro: super admin global) · textos-contrato-ia.js, pestaña Asistente IA
--
-- EL CONTADOR NO SE SALTA NI QUEDA EN NEGATIVO: cada reserva es UN update condicional por fila
-- (`usados + n <= tope … returning`), y bajo READ COMMITTED una segunda petición simultánea espera el candado de la fila y
-- vuelve a evaluar la condición con el valor ya sumado. CHECK (usados >= 0) impide el negativo. Seguro por construcción y
-- probado en secuencia (supabase/pruebas/editor_ia.sql); dos peticiones a la vez no se pueden ensayar dentro de un bloque.
--
-- NO TOCA la emisión ni la firma de contratos, ni plantilla_contrato_versiones (su `origen` no cambia: el rastro de una
-- propuesta aceptada vive en editor_ia_uso.version_aceptada). Vuelta atrás: supabase/reversion_editor_ia/vuelta_atras.sql.

-- ─────────────────────────────────────────────────────────────────────────────────────────────── tablas
create table public.editor_ia_ajustes (
  id                         boolean primary key default true check (id),
  precio_credito             numeric(14,4) check (precio_credito >= 0 and precio_credito <= 1000000),
  moneda                     text check (moneda in ('EUR', 'USD', 'IDR')),
  creditos_propuesta         integer check (creditos_propuesta between 1 and 1000),
  creditos_traduccion_ia     integer check (creditos_traduccion_ia between 1 and 1000),
  creditos_traduccion_deepl  integer check (creditos_traduccion_deepl between 1 and 1000),
  tope_global_mensual        integer check (tope_global_mensual between 1 and 10000000),
  factura_a                  text check (factura_a in ('instancia', 'empresa')),
  caducan                    boolean,
  prueba_creditos            integer check (prueba_creditos between 0 and 1000000),
  tarifa_entrada_usd_mtok    numeric(12,4) check (tarifa_entrada_usd_mtok between 0 and 10000),
  tarifa_salida_usd_mtok     numeric(12,4) check (tarifa_salida_usd_mtok between 0 and 10000),
  tarifa_deepl_usd_mcar      numeric(12,4) check (tarifa_deepl_usd_mcar between 0 and 10000),
  actualizado_por            text,
  actualizado_en             timestamptz
);
comment on table public.editor_ia_ajustes is
  'Precios del asistente IA del editor de textos (una fila). Nace vacía: con cualquier dato obligatorio vacío el servidor rechaza toda llamada. Escribe: editor_ia_ajustes_guarda (super admin global).';
insert into public.editor_ia_ajustes (id) values (true) on conflict (id) do nothing;

create table public.editor_ia_empresa (
  empresa             text primary key references public.empresas (clave),
  encendido           boolean not null default false,
  creditos_incluidos  integer check (creditos_incluidos between 0 and 10000000),
  tope_mensual        integer check (tope_mensual between 1 and 10000000),
  actualizado_por     text,
  actualizado_en      timestamptz,
  constraint editor_ia_empresa_tope_cubre_incluidos check (tope_mensual is null or creditos_incluidos is null or tope_mensual >= creditos_incluidos)
);
comment on table public.editor_ia_empresa is
  'Encendido y bolsa mensual del asistente IA por empresa. Sin fila = apagado. Escribe: editor_ia_ajustes_guarda (super admin global).';

create table public.editor_ia_ajustes_log (
  id          bigint generated always as identity primary key,
  ambito      text not null,                                   -- 'instancia' o la clave de la empresa
  antes       jsonb,
  despues     jsonb,
  motivo      text not null,
  autor       text not null,
  autor_uid   uuid,
  fecha       timestamptz not null default now()
);

create table public.editor_ia_saldo (
  empresa   text not null,                                     -- clave de la empresa, o '*' = toda la instancia
  periodo   date not null,                                     -- primer día del mes (hora de Bali)
  usados    integer not null default 0 check (usados >= 0),
  incluidos integer check (incluidos >= 0),                    -- créditos incluidos de la empresa ESE mes (congelados al primer uso)
  primary key (empresa, periodo)
);

create table public.editor_ia_uso (
  id                uuid primary key default gen_random_uuid(),
  empresa           text not null references public.empresas (clave),
  usuario           uuid not null,
  autor             text not null,
  fecha             timestamptz not null default now(),
  periodo           date not null,
  accion            text not null check (accion in ('propone', 'traduce_ia', 'traduce_deepl')),
  slug              text not null,
  variante          text not null,
  version_id        uuid references public.plantilla_contrato_versiones (id),
  parrafos          integer not null check (parrafos between 1 and 40),
  creditos          integer not null check (creditos > 0),
  de_prueba         boolean not null default false,
  estado            text not null default 'reservado' check (estado in ('reservado', 'hecho', 'fallo', 'caducada')),   -- se factura SOLO «hecho»
  modelo            text,
  tokens_entrada    integer check (tokens_entrada >= 0),
  tokens_salida     integer check (tokens_salida >= 0),
  caracteres        integer check (caracteres >= 0),
  huella_propuesta  text check (huella_propuesta ~ '^[0-9a-f]{64}$'),
  cerrada_en        timestamptz,
  aceptada_en       timestamptz,
  version_aceptada  uuid references public.plantilla_contrato_versiones (id),
  -- La edge lo marca JUSTO ANTES de llamar al proveedor (editor_ia_enviada). Con la petición ya enviada el proveedor puede
  -- haber cobrado aunque la función muera sin cerrar: entonces la jaula global NO se devuelve (ni al fallar ni al caducar).
  enviada_en        timestamptz,
  -- Congelados en el apunte (Administración 13-oct): el extracto de un mes pasado no se recalcula con el precio ni las tarifas de hoy.
  precio_credito    numeric(14,4),                              -- precio del crédito al reservar
  moneda            text,                                       -- moneda de ese precio
  coste_usd         numeric(14,6)                               -- coste real del proveedor al cerrar, con las tarifas de ese momento (null = sin tarifa)
);
create index editor_ia_uso_usuario_fecha on public.editor_ia_uso (usuario, fecha desc);
create index editor_ia_uso_empresa_periodo on public.editor_ia_uso (empresa, periodo);
create index editor_ia_uso_periodo on public.editor_ia_uso (periodo);                                  -- extracto de 3 meses
create index editor_ia_uso_reservadas on public.editor_ia_uso (fecha) where estado = 'reservado';    -- caducidad (dentro del candado)
comment on table public.editor_ia_uso is
  'Un apunte por llamada al asistente IA del editor de textos. Sin texto del contrato ni instrucción: quién, cuándo, plantilla, créditos, modelo y tokens. Lo escriben editor_ia_reserva y editor_ia_cierra.';

create table public.editor_ia_traduccion_marca (
  empresa       text not null references public.empresas (clave),
  slug          text not null,
  variante      text not null,
  lang          text not null check (lang in ('en', 'id')),
  huella        text not null check (huella ~ '^[0-9a-f]{64}$'),
  uso           uuid references public.editor_ia_uso (id),
  fecha         timestamptz not null default now(),
  revisada_en   timestamptz,
  revisada_por  text,
  primary key (empresa, slug, variante, lang, huella)
);

alter table public.editor_ia_ajustes enable row level security;
alter table public.editor_ia_empresa enable row level security;
alter table public.editor_ia_ajustes_log enable row level security;
alter table public.editor_ia_saldo enable row level security;
alter table public.editor_ia_uso enable row level security;
alter table public.editor_ia_traduccion_marca enable row level security;
revoke all on table public.editor_ia_ajustes, public.editor_ia_empresa, public.editor_ia_ajustes_log, public.editor_ia_saldo,
                    public.editor_ia_uso, public.editor_ia_traduccion_marca from public, anon, authenticated, service_role;

-- el registro de ajustes solo se añade
create function public._trg_editor_ia_log_solo_anade() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'El registro de ajustes del asistente no se cambia: solo se añade' using errcode = '55000';
end $$;
create trigger editor_ia_ajustes_log_solo_anade before update or delete on public.editor_ia_ajustes_log
  for each row execute function public._trg_editor_ia_log_solo_anade();
revoke all on function public._trg_editor_ia_log_solo_anade() from public, anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── ayudantes privados
create function public._editor_ia_periodo() returns date language sql stable security definer set search_path = '' as $$
  select (date_trunc('month', now() at time zone 'Asia/Makassar'))::date
$$;

-- null = se puede usar; si no, la razón en llano (la enseña la pantalla tal cual)
create function public._editor_ia_falta(p_empresa text) returns text language plpgsql stable security definer set search_path = '' as $$
declare a public.editor_ia_ajustes%rowtype; e public.editor_ia_empresa%rowtype; f text[] := '{}';
begin
  select * into e from public.editor_ia_empresa x where x.empresa = p_empresa;
  if not found or not e.encendido then return 'El asistente no está encendido para esta empresa.'; end if;
  select * into a from public.editor_ia_ajustes x where x.id;
  if a.precio_credito is null then f := f || 'precio del crédito'::text; end if;
  if a.moneda is null then f := f || 'moneda'::text; end if;
  if a.creditos_propuesta is null then f := f || 'créditos por propuesta'::text; end if;
  if a.creditos_traduccion_ia is null then f := f || 'créditos por párrafo traducido con IA'::text; end if;
  if a.creditos_traduccion_deepl is null then f := f || 'créditos por párrafo traducido con DeepL'::text; end if;
  if a.tope_global_mensual is null then f := f || 'tope mensual de toda la intranet'::text; end if;
  if a.factura_a is null then f := f || 'a quién se factura'::text; end if;
  if a.caducan is null then f := f || 'si caducan los créditos'::text; end if;
  if a.prueba_creditos is null then f := f || 'créditos de prueba'::text; end if;
  if e.creditos_incluidos is null then f := f || 'créditos incluidos de la empresa'::text; end if;
  if e.tope_mensual is null then f := f || 'tope mensual de la empresa'::text; end if;
  if cardinality(f) > 0 then return 'Faltan datos de precio: ' || array_to_string(f, ', ') || '.'; end if;
  return null;
end $$;
revoke all on function public._editor_ia_periodo(), public._editor_ia_falta(text) from public, anon, authenticated, service_role;

-- Reservas que nadie cerró (la función murió a medias, o alguien reservó desde el navegador sin llamar a la función): a los 10
-- minutos caducan y devuelven sus créditos a la empresa y a la jaula global. Una función viva cierra en segundos (su tope de
-- ejecución es muy inferior), así que no se pisa con un cierre de verdad; y si chocan, el cierre ve que ya no está «reservado».
-- Caducan las de TODAS las empresas (Seguridad 13-oct): si solo caducaran las de quien reserva, las abandonadas por una empresa
-- seguirían ocupando la jaula global de las demás. Todo lo que mueve `editor_ia_saldo` (reserva, cierre, caducidad) toma antes
-- el MISMO candado de transacción (`_editor_ia_candado`): así no hay orden de bloqueo entre filas que respetar ni abrazo mortal
-- posible. El volumen es mínimo (6 por persona y minuto) y el candado dura una transacción corta, nunca la llamada al modelo.
create function public._editor_ia_candado() returns void language sql security definer set search_path = '' as $$
  select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('editor_ia/saldo', 0))
$$;
create function public._editor_ia_caduca() returns integer language plpgsql security definer set search_path = '' as $$
declare u record; n int := 0;
begin
  perform public._editor_ia_candado();
  for u in select x.id, x.empresa, x.periodo, x.creditos, x.enviada_en from public.editor_ia_uso x
            where x.estado = 'reservado' and x.fecha < now() - interval '10 minutes'
            order by x.fecha for update skip locked loop
    update public.editor_ia_uso set estado = 'caducada', cerrada_en = now() where id = u.id;
    update public.editor_ia_saldo s set usados = greatest(s.usados - u.creditos, 0) where s.empresa = u.empresa and s.periodo = u.periodo;
    if u.enviada_en is null then                                               -- enviada = el proveedor pudo cobrar: la jaula no devuelve
      update public.editor_ia_saldo s set usados = greatest(s.usados - u.creditos, 0) where s.empresa = '*' and s.periodo = u.periodo;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public._editor_ia_candado(), public._editor_ia_caduca() from public, anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── estado (pantalla)
create function public.editor_ia_estado(p_empresa text) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_falta text; a public.editor_ia_ajustes%rowtype; e public.editor_ia_empresa%rowtype; v_per date := public._editor_ia_periodo(); v_usados int;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El asistente de textos lo usa la administracion de la empresa' using errcode = '42501';
  end if;
  v_falta := public._editor_ia_falta(p_empresa);
  if v_falta is not null then return jsonb_build_object('encendido', false, 'motivo', v_falta); end if;
  select * into a from public.editor_ia_ajustes x where x.id;
  select * into e from public.editor_ia_empresa x where x.empresa = p_empresa;
  select s.usados into v_usados from public.editor_ia_saldo s where s.empresa = p_empresa and s.periodo = v_per;
  return jsonb_build_object('encendido', true, 'motivo', null, 'periodo', v_per,
    'usados', coalesce(v_usados, 0), 'incluidos', e.creditos_incluidos, 'tope', e.tope_mensual,
    'creditos', jsonb_build_object('propone', a.creditos_propuesta, 'traduce_ia', a.creditos_traduccion_ia, 'traduce_deepl', a.creditos_traduccion_deepl));
end $$;
revoke all on function public.editor_ia_estado(text) from public, anon, service_role;
grant execute on function public.editor_ia_estado(text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── reserva (antes de llamar al modelo)
create function public.editor_ia_reserva(p_empresa text, p_accion text, p_slug text, p_variante text, p_version uuid, p_parrafos integer)
 returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
  v_var text := coalesce(p_variante, 'estandar');
  v_falta text; a public.editor_ia_ajustes%rowtype; e public.editor_ia_empresa%rowtype;
  v_per date := public._editor_ia_periodo(); v_unit int; v_n int; v_usados int; v_min int; v_hist bigint; v_id uuid; v_prueba boolean;
begin
  if v_uid is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El asistente de textos lo usa la administracion de la empresa' using errcode = '42501';
  end if;
  if p_accion is null or p_accion not in ('propone', 'traduce_ia', 'traduce_deepl') then raise exception 'Accion no valida' using errcode = '22023'; end if;
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
  if v_falta is not null then raise exception 'Asistente apagado: %', v_falta using errcode = '55000', hint = 'apagado'; end if;
  perform public._editor_ia_caduca();                                        -- toma el candado del saldo; lo abandonado deja de ocupar
  -- tope por persona: 6 llamadas por minuto (serializado por persona: dos peticiones suyas a la vez no se cuelan las dos)
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('editor_ia/usuario/' || v_uid::text, 0));
  select count(*) into v_min from public.editor_ia_uso u where u.usuario = v_uid and u.fecha > now() - interval '1 minute';
  if v_min >= 6 then raise exception 'Demasiadas consultas seguidas: espera un minuto' using errcode = 'P0001', hint = 'tope_minuto'; end if;
  select * into a from public.editor_ia_ajustes x where x.id;
  select * into e from public.editor_ia_empresa x where x.empresa = p_empresa;
  v_unit := case p_accion when 'propone' then a.creditos_propuesta when 'traduce_ia' then a.creditos_traduccion_ia else a.creditos_traduccion_deepl end;
  v_n := v_unit * p_parrafos;
  insert into public.editor_ia_saldo (empresa, periodo, incluidos) values (p_empresa, v_per, e.creditos_incluidos), ('*', v_per, null)
    on conflict (empresa, periodo) do nothing;
  -- la empresa, con su tope: un update condicional (atómico frente a peticiones a la vez)
  update public.editor_ia_saldo s set usados = s.usados + v_n
   where s.empresa = p_empresa and s.periodo = v_per and s.usados + v_n <= e.tope_mensual
  returning s.usados into v_usados;
  if not found then raise exception 'Esta empresa ha llegado a su tope de creditos de este mes' using errcode = 'P0001', hint = 'tope_empresa'; end if;
  -- la instancia entera (la jaula del dinero). Si falla, la excepción deshace también la suma de arriba.
  update public.editor_ia_saldo s set usados = s.usados + v_n
   where s.empresa = '*' and s.periodo = v_per and s.usados + v_n <= a.tope_global_mensual;
  if not found then raise exception 'El asistente ha llegado al tope de creditos de este mes' using errcode = 'P0001', hint = 'tope_global'; end if;
  select coalesce(sum(u.creditos), 0) into v_hist from public.editor_ia_uso u where u.empresa = p_empresa and u.estado in ('reservado', 'hecho');
  -- La prueba es por llamada entera, a propósito: si una llamada no cabe en lo que queda de prueba, se cobra entera y ese resto
  -- de prueba no se usa (partirla complicaría el extracto por unos pocos créditos).
  v_prueba := v_hist + v_n <= a.prueba_creditos;
  insert into public.editor_ia_uso (empresa, usuario, autor, periodo, accion, slug, variante, version_id, parrafos, creditos, de_prueba, precio_credito, moneda)
  values (p_empresa, v_uid, v_autor, v_per, p_accion, p_slug, v_var, p_version, p_parrafos, v_n, v_prueba, a.precio_credito, a.moneda)
  returning id into v_id;
  return jsonb_build_object('uso', v_id, 'creditos', v_n, 'usados', v_usados, 'incluidos', e.creditos_incluidos, 'tope', e.tope_mensual, 'de_prueba', v_prueba);
end $$;
revoke all on function public.editor_ia_reserva(text, text, text, text, uuid, integer) from public, anon, service_role;
grant execute on function public.editor_ia_reserva(text, text, text, text, uuid, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── cierre (solo la edge, con la clave de servicio)
-- p_marcas = [{ "lang": "en"|"id", "huella": "<sha256>" }, …] de los trozos traducidos. Una llamada fallida devuelve los créditos.
create function public.editor_ia_cierra(p_uso uuid, p_ok boolean, p_modelo text, p_entrada integer, p_salida integer, p_caracteres integer,
                                        p_huella text, p_marcas jsonb default '[]'::jsonb)
 returns boolean language plpgsql security definer set search_path = '' as $$
declare u public.editor_ia_uso%rowtype; m jsonb; a public.editor_ia_ajustes%rowtype; v_coste numeric;
begin
  select * into u from public.editor_ia_uso x where x.id = p_uso for update;
  if not found then raise exception 'Uso no encontrado' using errcode = '22023'; end if;
  if u.estado <> 'reservado' then return false; end if;                       -- ya cerrado: no se cuenta dos veces
  perform public._editor_ia_candado();                                       -- el mismo candado que la reserva y la caducidad
  if p_huella is not null and p_huella !~ '^[0-9a-f]{64}$' then raise exception 'Huella no valida' using errcode = '22023'; end if;
  select * into a from public.editor_ia_ajustes x where x.id;
  v_coste := case when u.accion = 'traduce_deepl' then greatest(p_caracteres, 0) * a.tarifa_deepl_usd_mcar / 1000000.0
                  else (greatest(p_entrada, 0) * a.tarifa_entrada_usd_mtok + greatest(p_salida, 0) * a.tarifa_salida_usd_mtok) / 1000000.0 end;
  update public.editor_ia_uso set estado = case when p_ok then 'hecho' else 'fallo' end, cerrada_en = now(),
         modelo = left(p_modelo, 80), tokens_entrada = greatest(p_entrada, 0), tokens_salida = greatest(p_salida, 0),
         caracteres = greatest(p_caracteres, 0), huella_propuesta = case when p_ok then p_huella end, coste_usd = round(v_coste, 6)
   where id = u.id;
  if not p_ok then
    -- La empresa no paga una llamada fallida. La jaula global solo la devuelve si la petición NO llegó a enviarse al proveedor:
    -- enviada, pudo cobrar (aunque la función no sepa cuánto, p. ej. si se cortó por tiempo), y ese gasto real sigue contando
    -- contra el tope de la instancia. Así los fallos tampoco salen gratis y la jaula nunca devuelve gasto real.
    update public.editor_ia_saldo s set usados = greatest(s.usados - u.creditos, 0) where s.empresa = u.empresa and s.periodo = u.periodo;
    if u.enviada_en is null then
      update public.editor_ia_saldo s set usados = greatest(s.usados - u.creditos, 0) where s.empresa = '*' and s.periodo = u.periodo;
    end if;
    return true;
  end if;
  if jsonb_typeof(coalesce(p_marcas, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_marcas, '[]'::jsonb)) > 400 then
    raise exception 'Marcas no validas' using errcode = '22023';
  end if;
  for m in select * from jsonb_array_elements(coalesce(p_marcas, '[]'::jsonb)) loop
    if (m ->> 'lang') not in ('en', 'id') or coalesce(m ->> 'huella', '') !~ '^[0-9a-f]{64}$' then raise exception 'Marca no valida' using errcode = '22023'; end if;
    insert into public.editor_ia_traduccion_marca (empresa, slug, variante, lang, huella, uso)
    values (u.empresa, u.slug, u.variante, m ->> 'lang', m ->> 'huella', u.id)
    on conflict (empresa, slug, variante, lang, huella) do update set uso = excluded.uso, fecha = now(), revisada_en = null, revisada_por = null;
  end loop;
  return true;
end $$;
revoke all on function public.editor_ia_cierra(uuid, boolean, text, integer, integer, integer, text, jsonb) from public, anon, authenticated;
grant execute on function public.editor_ia_cierra(uuid, boolean, text, integer, integer, integer, text, jsonb) to service_role;

-- La edge marca la reserva como enviada justo antes de llamar al proveedor (ver `enviada_en`). Solo service_role.
create function public.editor_ia_enviada(p_uso uuid) returns boolean language plpgsql security definer set search_path = '' as $$
begin
  update public.editor_ia_uso set enviada_en = now() where id = p_uso and estado = 'reservado' and enviada_en is null;
  return found;
end $$;
revoke all on function public.editor_ia_enviada(uuid) from public, anon, authenticated;
grant execute on function public.editor_ia_enviada(uuid) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── la propuesta quedó en un borrador
create function public.editor_ia_aceptada(p_uso uuid, p_version uuid) returns boolean language plpgsql security definer set search_path = '' as $$
declare u public.editor_ia_uso%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  select * into u from public.editor_ia_uso x where x.id = p_uso for update;
  if not found or u.usuario <> (select auth.uid()) then raise exception 'Uso no encontrado' using errcode = '22023'; end if;
  if not (public.es_admin_de(u.empresa) and public.empresa_en_alcance(u.empresa)) then     -- quien perdió el rol ya no anota nada
    raise exception 'El asistente de textos lo usa la administracion de la empresa' using errcode = '42501';
  end if;
  if u.estado <> 'hecho' then raise exception 'Esa consulta no termino bien' using errcode = '22023'; end if;
  if not exists (select 1 from public.plantilla_contrato_versiones v where v.id = p_version and v.empresa = u.empresa and v.slug = u.slug
                   and v.variante = u.variante and v.borrada_en is null) then
    raise exception 'Version no valida' using errcode = '22023';
  end if;
  if u.aceptada_en is not null then return false; end if;
  update public.editor_ia_uso set aceptada_en = now(), version_aceptada = p_version where id = u.id;
  return true;
end $$;
revoke all on function public.editor_ia_aceptada(uuid, uuid) from public, anon, service_role;
grant execute on function public.editor_ia_aceptada(uuid, uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── «traducido, sin revisar»
create function public.editor_ia_marcas(p_empresa text, p_slug text, p_variante text default 'estandar') returns jsonb
 language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El asistente de textos lo usa la administracion de la empresa' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('lang', m.lang, 'huella', m.huella))
                     from (select x.lang, x.huella from public.editor_ia_traduccion_marca x
                            where x.empresa = p_empresa and x.slug = p_slug and x.variante = coalesce(p_variante, 'estandar') and x.revisada_en is null
                            order by x.fecha desc limit 2000) m), '[]'::jsonb);
end $$;
revoke all on function public.editor_ia_marcas(text, text, text) from public, anon, service_role;
grant execute on function public.editor_ia_marcas(text, text, text) to authenticated;

create function public.editor_ia_marca_revisada(p_empresa text, p_slug text, p_variante text, p_lang text, p_huellas text[]) returns integer
 language plpgsql security definer set search_path = '' as $$
declare v_n int;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El asistente de textos lo usa la administracion de la empresa' using errcode = '42501';
  end if;
  if cardinality(coalesce(p_huellas, '{}')) > 500 then raise exception 'Demasiadas marcas de una vez' using errcode = '22023'; end if;
  update public.editor_ia_traduccion_marca x set revisada_en = now(), revisada_por = coalesce((select auth.email()), (select auth.uid())::text)
   where x.empresa = p_empresa and x.slug = p_slug and x.variante = coalesce(p_variante, 'estandar') and x.lang = p_lang
     and x.huella = any (p_huellas) and x.revisada_en is null;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function public.editor_ia_marca_revisada(text, text, text, text, text[]) from public, anon, service_role;
grant execute on function public.editor_ia_marca_revisada(text, text, text, text, text[]) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── precios: lectura y escritura (super admin global)
create function public.editor_ia_ajustes_datos() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare a public.editor_ia_ajustes%rowtype; v_per date := public._editor_ia_periodo();
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_super_admin() then raise exception 'Los precios del asistente los pone el super administrador' using errcode = '42501'; end if;
  select * into a from public.editor_ia_ajustes x where x.id;
  return jsonb_build_object(
    'instancia', to_jsonb(a) - 'id',
    'periodo', v_per,
    'usados_instancia', coalesce((select s.usados from public.editor_ia_saldo s where s.empresa = '*' and s.periodo = v_per), 0),
    'empresas', coalesce((select jsonb_agg(jsonb_build_object('clave', em.clave, 'nombre', em.nombre,
                                   'encendido', coalesce(e.encendido, false), 'creditos_incluidos', e.creditos_incluidos, 'tope_mensual', e.tope_mensual,
                                   'usados', coalesce(s.usados, 0), 'falta', public._editor_ia_falta(em.clave),
                                   'actualizado_por', e.actualizado_por, 'actualizado_en', e.actualizado_en) order by em.orden, em.clave)
                            from public.empresas em
                            left join public.editor_ia_empresa e on e.empresa = em.clave
                            left join public.editor_ia_saldo s on s.empresa = em.clave and s.periodo = v_per
                           where em.activa), '[]'::jsonb),
    -- extracto de los tres últimos meses, por empresa: lo que se factura sale de aquí (sin texto de nadie)
    'extracto', coalesce((select jsonb_agg(x order by x ->> 'periodo' desc, x ->> 'empresa') from (
        select jsonb_build_object('periodo', u.periodo, 'empresa', u.empresa,
                 'llamadas', count(*), 'fallidas', count(*) filter (where u.estado in ('fallo', 'caducada')),
                 'pendientes', count(*) filter (where u.estado = 'reservado'),
                 'creditos', coalesce(sum(u.creditos) filter (where u.estado = 'hecho'), 0),           -- hechos (con los de prueba)
                 'creditos_prueba', coalesce(sum(u.creditos) filter (where u.estado = 'hecho' and u.de_prueba), 0),
                 -- lo que se factura: hecho y no de prueba, con el precio CONGELADO en cada apunte
                 'facturables', coalesce(sum(u.creditos) filter (where u.estado = 'hecho' and not u.de_prueba), 0),
                 'importe', coalesce(sum(u.creditos * u.precio_credito) filter (where u.estado = 'hecho' and not u.de_prueba), 0),
                 'moneda', string_agg(distinct u.moneda, '/') filter (where u.estado = 'hecho' and not u.de_prueba),
                 'incluidos', (select s.incluidos from public.editor_ia_saldo s where s.empresa = u.empresa and s.periodo = u.periodo),
                 'exceso', greatest(coalesce(sum(u.creditos) filter (where u.estado = 'hecho' and not u.de_prueba), 0)
                                    - coalesce((select s.incluidos from public.editor_ia_saldo s where s.empresa = u.empresa and s.periodo = u.periodo), 0), 0),
                 'aceptadas', count(*) filter (where u.aceptada_en is not null),
                 'tokens_entrada', coalesce(sum(u.tokens_entrada), 0), 'tokens_salida', coalesce(sum(u.tokens_salida), 0),
                 'caracteres', coalesce(sum(u.caracteres), 0),
                 'coste_usd', round(coalesce(sum(u.coste_usd) filter (where u.estado in ('hecho', 'fallo')), 0), 4),
                 -- incompleto: falta una tarifa, o una consulta enviada al proveedor caducó sin cerrar (pudo cobrar y no se sabe cuánto)
                 'coste_incompleto', coalesce(bool_or((u.coste_usd is null and u.estado in ('hecho', 'fallo'))
                                                      or (u.estado = 'caducada' and u.enviada_en is not null)), false)) x
          from public.editor_ia_uso u
         where u.periodo >= (v_per - interval '2 months')::date
         group by u.periodo, u.empresa) t), '[]'::jsonb),
    'registro', coalesce((select jsonb_agg(jsonb_build_object('ambito', l.ambito, 'antes', l.antes, 'despues', l.despues, 'motivo', l.motivo, 'autor', l.autor, 'fecha', l.fecha) order by l.id desc)
                            from (select * from public.editor_ia_ajustes_log order by id desc limit 30) l), '[]'::jsonb));
end $$;
revoke all on function public.editor_ia_ajustes_datos() from public, anon, service_role;
grant execute on function public.editor_ia_ajustes_datos() to authenticated;

-- p_empresa null = los datos de la instancia; con clave = los de esa empresa. p_campos: solo las claves que cambian (null = vaciar).
create function public.editor_ia_ajustes_guarda(p_empresa text, p_campos jsonb, p_motivo text) returns jsonb
 language plpgsql security definer set search_path = '' as $$
declare
  v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
  k text; v jsonb; v_antes jsonb; v_despues jsonb; v_falta text;
  CL_INST constant text[] := array['precio_credito', 'moneda', 'creditos_propuesta', 'creditos_traduccion_ia', 'creditos_traduccion_deepl', 'tope_global_mensual',
                                   'factura_a', 'caducan', 'prueba_creditos', 'tarifa_entrada_usd_mtok', 'tarifa_salida_usd_mtok', 'tarifa_deepl_usd_mcar'];
  CL_EMP  constant text[] := array['encendido', 'creditos_incluidos', 'tope_mensual'];
  NUM     constant text[] := array['precio_credito', 'tarifa_entrada_usd_mtok', 'tarifa_salida_usd_mtok', 'tarifa_deepl_usd_mcar'];
  ENT     constant text[] := array['creditos_propuesta', 'creditos_traduccion_ia', 'creditos_traduccion_deepl', 'tope_global_mensual', 'prueba_creditos', 'creditos_incluidos', 'tope_mensual'];
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_super_admin() then raise exception 'Los precios del asistente los pone el super administrador' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 3 or length(p_motivo) > 300 then raise exception 'Falta el motivo del cambio (de 3 a 300 letras)' using errcode = '22023'; end if;
  if p_campos is null or jsonb_typeof(p_campos) <> 'object' or p_campos = '{}'::jsonb then raise exception 'No hay nada que guardar' using errcode = '22023'; end if;
  -- forma de cada valor (los rangos los pone el CHECK de la tabla: fuera de rango no se guarda)
  for k, v in select * from jsonb_each(p_campos) loop
    if p_empresa is null and k <> all (CL_INST) or p_empresa is not null and k <> all (CL_EMP) then
      raise exception 'El dato «%» no se cambia aqui', left(k, 40) using errcode = '22023';
    end if;
    continue when jsonb_typeof(v) = 'null';
    if k = any (NUM) and (jsonb_typeof(v) <> 'number') then raise exception '«%» es un numero', k using errcode = '22023'; end if;
    if k = any (ENT) and (jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric <> trunc((v #>> '{}')::numeric)) then raise exception '«%» es un numero entero', k using errcode = '22023'; end if;
    if k in ('caducan', 'encendido') and jsonb_typeof(v) <> 'boolean' then raise exception '«%» es si o no', k using errcode = '22023'; end if;
    if k in ('moneda', 'factura_a') and jsonb_typeof(v) <> 'string' then raise exception '«%» es un texto', k using errcode = '22023'; end if;
    -- Administración 13-oct: el saldo es por mes y no hay arrastre construido; aceptar «no caducan» sería un dato que no hace nada
    if k = 'caducan' and v = 'false'::jsonb then
      raise exception 'Que los creditos no usados pasen al mes siguiente todavia no esta construido: hoy caducan a fin de mes' using errcode = '22023';
    end if;
  end loop;
  if p_empresa is null then
    select to_jsonb(a) - 'id' into v_antes from public.editor_ia_ajustes a where a.id for update;
    -- Una sola moneda por mes (revisor 13-oct): cada consulta congela la suya y el importe del extracto las sumaría mezcladas.
    -- Con consultas hechas o en curso este mes, la moneda no cambia hasta el mes que viene (antes de su primera consulta).
    if p_campos ? 'moneda' and (p_campos ->> 'moneda') is distinct from (v_antes ->> 'moneda')
       and exists (select 1 from public.editor_ia_uso u where u.periodo = public._editor_ia_periodo() and u.estado in ('hecho', 'reservado')) then
      raise exception 'La moneda no se cambia a mitad de mes: este mes ya hay consultas en %. Se puede cambiar el primer dia del mes que viene, antes de la primera consulta', v_antes ->> 'moneda' using errcode = '22023';
    end if;
    update public.editor_ia_ajustes a set
      precio_credito            = case when p_campos ? 'precio_credito' then (p_campos ->> 'precio_credito')::numeric else a.precio_credito end,
      moneda                    = case when p_campos ? 'moneda' then p_campos ->> 'moneda' else a.moneda end,
      creditos_propuesta        = case when p_campos ? 'creditos_propuesta' then (p_campos ->> 'creditos_propuesta')::int else a.creditos_propuesta end,
      creditos_traduccion_ia    = case when p_campos ? 'creditos_traduccion_ia' then (p_campos ->> 'creditos_traduccion_ia')::int else a.creditos_traduccion_ia end,
      creditos_traduccion_deepl = case when p_campos ? 'creditos_traduccion_deepl' then (p_campos ->> 'creditos_traduccion_deepl')::int else a.creditos_traduccion_deepl end,
      tope_global_mensual       = case when p_campos ? 'tope_global_mensual' then (p_campos ->> 'tope_global_mensual')::int else a.tope_global_mensual end,
      factura_a                 = case when p_campos ? 'factura_a' then p_campos ->> 'factura_a' else a.factura_a end,
      caducan                   = case when p_campos ? 'caducan' then (p_campos ->> 'caducan')::boolean else a.caducan end,
      prueba_creditos           = case when p_campos ? 'prueba_creditos' then (p_campos ->> 'prueba_creditos')::int else a.prueba_creditos end,
      tarifa_entrada_usd_mtok   = case when p_campos ? 'tarifa_entrada_usd_mtok' then (p_campos ->> 'tarifa_entrada_usd_mtok')::numeric else a.tarifa_entrada_usd_mtok end,
      tarifa_salida_usd_mtok    = case when p_campos ? 'tarifa_salida_usd_mtok' then (p_campos ->> 'tarifa_salida_usd_mtok')::numeric else a.tarifa_salida_usd_mtok end,
      tarifa_deepl_usd_mcar     = case when p_campos ? 'tarifa_deepl_usd_mcar' then (p_campos ->> 'tarifa_deepl_usd_mcar')::numeric else a.tarifa_deepl_usd_mcar end,
      actualizado_por = v_autor, actualizado_en = now()
     where a.id;
    select to_jsonb(a) - 'id' into v_despues from public.editor_ia_ajustes a where a.id;
    insert into public.editor_ia_ajustes_log (ambito, antes, despues, motivo, autor, autor_uid) values ('instancia', v_antes, v_despues, btrim(p_motivo), v_autor, (select auth.uid()));
    return v_despues;
  end if;
  if not exists (select 1 from public.empresas e where e.clave = p_empresa and e.activa) then raise exception 'Empresa no valida' using errcode = '22023'; end if;
  insert into public.editor_ia_empresa (empresa) values (p_empresa) on conflict (empresa) do nothing;
  select to_jsonb(e) into v_antes from public.editor_ia_empresa e where e.empresa = p_empresa for update;
  update public.editor_ia_empresa e set
    encendido          = case when p_campos ? 'encendido' then coalesce((p_campos ->> 'encendido')::boolean, false) else e.encendido end,
    creditos_incluidos = case when p_campos ? 'creditos_incluidos' then (p_campos ->> 'creditos_incluidos')::int else e.creditos_incluidos end,
    tope_mensual       = case when p_campos ? 'tope_mensual' then (p_campos ->> 'tope_mensual')::int else e.tope_mensual end,
    actualizado_por = v_autor, actualizado_en = now()
   where e.empresa = p_empresa;
  -- un solo dueño de «incluidos» (Backend 13-oct): el MES EN CURSO sigue al valor vivo; los meses cerrados quedan congelados
  update public.editor_ia_saldo s set incluidos = (select x.creditos_incluidos from public.editor_ia_empresa x where x.empresa = p_empresa)
   where s.empresa = p_empresa and s.periodo = public._editor_ia_periodo();
  -- encender exige que no falte ningún dato de precio: si falta, no se guarda nada
  if (select x.encendido from public.editor_ia_empresa x where x.empresa = p_empresa) then
    v_falta := public._editor_ia_falta(p_empresa);
    if v_falta is not null then raise exception 'No se puede encender: %', v_falta using errcode = '22023', hint = 'faltan_datos'; end if;
  end if;
  select to_jsonb(e) into v_despues from public.editor_ia_empresa e where e.empresa = p_empresa;
  insert into public.editor_ia_ajustes_log (ambito, antes, despues, motivo, autor, autor_uid) values (p_empresa, v_antes, v_despues, btrim(p_motivo), v_autor, (select auth.uid()));
  return v_despues;
end $$;
revoke all on function public.editor_ia_ajustes_guarda(text, jsonb, text) from public, anon, service_role;
grant execute on function public.editor_ia_ajustes_guarda(text, jsonb, text) to authenticated;
