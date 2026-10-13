-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- «Servicios de AxisWorks» (AXW-104), primera pieza: el asistente de IA del editor de textos de contrato pasa a COSTE + MARGEN, con tope
-- en dólares por empresa, interruptor de impago y extracto mensual. Encargo agencia encargos/20261008_lawang_editor_textos_contrato.md.
--
-- DECISIONES DEL OWNER (13-oct-2026, por opciones; sustituyen el modelo de créditos de 20261013020822, construido ayer y nunca usado):
--   «No es gratis, lo pago yo y luego se lo cobro. Con tope, dijimos de en Ajustes ponerle ciertas herramientas de pago mediante IA».
--   1. Precio = coste real del proveedor + margen fijo en %, que el owner pone en Ajustes (aquí nace VACÍO: sin margen no arranca).
--   2. Cobro = en la factura mensual de mantenimiento; el ERP lleva contador y extracto mensual por empresa (coste, margen, total). Sin Stripe.
--   3. Tope por defecto 20 $/mes por empresa; al llegar SE PARA hasta el mes siguiente o hasta que el owner lo suba; aviso al 80 %.
--   4. Impago = interruptor manual del owner (solo super admin global) que apaga los servicios de pago de una empresa. Nada se apaga solo.
--   Dónde: Ajustes → «Servicios de AxisWorks» (solo super admin global). Encendido hoy: solo la empresa `lawang`.
--
-- DUEÑO DE CADA DATO
--   servicios_axisworks_ajustes  UNA fila: margen %, tope por defecto por empresa, tope de toda la instancia (= el límite de gasto puesto en la
--                                consola del proveedor: si las empresas suman más, el proveedor corta a mitad de llamada), aviso %.
--                                Escribe: servicios_axisworks_guarda (super admin global). Revisión previa de Administración (13-oct).
--   servicios_axisworks_empresa  por empresa: tope propio en USD (vacío = el de defecto) y «suspendido» (impago). Mismo escritor.
--   servicios_axisworks_log      cada cambio de las anteriores y de las tarifas: antes, después, motivo, quién, cuándo. Solo se añade.
--   editor_ia_ajustes            sigue siendo de este servicio, pero solo valen sus TARIFAS (coste del proveedor). Mismo escritor.
--   editor_ia_empresa.encendido  si el asistente está encendido para la empresa. Mismo escritor.
--   editor_ia_uso                un apunte por llamada (sin texto): coste REAL y, congelados al reservar, el peor caso y el margen; el importe se
--                                calcula al cerrar. Escriben editor_ia_reserva y editor_ia_cierra. Un mes pasado NO se recalcula con tarifas
--                                o margen nuevos. Coste e importe sin redondear: se redondea una sola vez, al total del extracto (Administración).
--   DEJAN DE USARSE (nunca tuvieron una fila real): las columnas de créditos de editor_ia_ajustes/_empresa/_uso y la tabla editor_ia_saldo.
--   Retirarlas es DDL que borra estructura: queda con fila en contexto/pendientes.md (LAW-555), no en este comentario.
--
-- EL TOPE NO SE PASA NI CON LLAMADAS A LA VEZ: cada reserva aparta el PEOR CASO en dólares de esa llamada (tope de tokens × tarifa, por
-- acción, en _editor_ia_coste_max) y se niega si gasto del mes + reservas en vuelo + este peor caso > tope. El gasto cuenta el coste REAL
-- (lo que el owner paga al proveedor), también de las llamadas fallidas que llegaron a enviarse (no se facturan a la empresa: «coste no
-- repercutido»), y una enviada cuyo coste no se conoce (se cortó) cuenta al peor caso. Todo bajo el mismo candado de transacción.
--
-- QUIÉN LLAMA A CADA FUNCIÓN (seguridad_2026.md §1.ter)
--   editor_ia_estado            authenticated · textos-contrato-ia.js (encendido, gasto y tope del mes en dólares, peor caso por acción)
--   editor_ia_reserva           authenticated · edge editor-ia, con el JWT de la persona (MISMA firma de 6 parámetros: create or replace)
--   editor_ia_cierra            SOLO service_role · edge editor-ia
--   servicios_axisworks_datos   authenticated (dentro: super admin global) · ajustes-servicios.js (Ajustes → Servicios de AxisWorks)
--   servicios_axisworks_guarda  authenticated (dentro: super admin global) · ajustes-servicios.js
--   SIN LLAMADOR desde hoy: editor_ia_ajustes_datos, editor_ia_ajustes_guarda (la pestaña «Asistente IA» de Textos de contrato desaparece:
--   el owner lo quiere en Ajustes). Se les QUITA el permiso aquí; retirarlas del todo es DDL que borra y va con LAW-555 (válvula del owner).
-- Esta migración no lleva ningún borrado de estructura (tools/no_destruir.py): lo que E10 necesita ensanchar en editor_ia_uso (acciones
-- nuevas, slug vacío para una redacción) va en su propia migración, con la válvula del owner y copia previa.
-- Prueba: supabase/pruebas/servicios_axisworks.sql · Vuelta atrás: supabase/reversion_editor_ia/vuelta_atras_servicios.sql

-- ─────────────────────────────────────────────────────────────────────────────────────────────── tablas nuevas
create table public.servicios_axisworks_ajustes (
  id                 boolean primary key default true check (id),
  margen_pct         numeric(7,2) check (margen_pct between 0 and 1000),                 -- vacío hasta que lo ponga el owner
  tope_usd_defecto   numeric(10,2) not null default 20 check (tope_usd_defecto between 1 and 100000),
  tope_instancia_usd numeric(10,2) not null default 20 check (tope_instancia_usd between 1 and 1000000),
  aviso_pct          integer not null default 80 check (aviso_pct between 1 and 100),
  actualizado_por    text,
  actualizado_en     timestamptz
);
comment on table public.servicios_axisworks_ajustes is
  'Servicios de pago de AxisWorks (AXW-104): margen sobre el coste real, topes en USD y aviso. Una fila. Escribe: servicios_axisworks_guarda (super admin global).';

create table public.servicios_axisworks_empresa (
  empresa          text primary key references public.empresas (clave),
  suspendido       boolean not null default false,                                     -- impago: lo pone y lo quita SOLO el owner
  tope_usd         numeric(10,2) check (tope_usd between 1 and 100000),                -- vacío = tope por defecto
  actualizado_por  text,
  actualizado_en   timestamptz
);
comment on table public.servicios_axisworks_empresa is
  'Por empresa: tope propio en USD (vacío = el de defecto) e interruptor de impago. Sin fila = tope por defecto, no suspendida. Escribe: servicios_axisworks_guarda.';

create table public.servicios_axisworks_log (
  id          bigint generated always as identity primary key,
  ambito      text not null,                                   -- 'instancia', 'tarifas' o la clave de la empresa
  antes       jsonb,
  despues     jsonb,
  motivo      text not null,
  autor       text not null,
  autor_uid   uuid,
  fecha       timestamptz not null default now()
);
create function public._trg_servicios_log_solo_anade() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'El registro de servicios de AxisWorks no se cambia: solo se añade' using errcode = '55000';
end $$;
create trigger servicios_axisworks_log_solo_anade before update or delete on public.servicios_axisworks_log
  for each row execute function public._trg_servicios_log_solo_anade();

alter table public.servicios_axisworks_ajustes enable row level security;
alter table public.servicios_axisworks_empresa enable row level security;
alter table public.servicios_axisworks_log enable row level security;
revoke all on table public.servicios_axisworks_ajustes, public.servicios_axisworks_empresa, public.servicios_axisworks_log
  from public, anon, authenticated, service_role;
revoke all on function public._trg_servicios_log_solo_anade() from public, anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── el apunte de cada llamada, en dólares
alter table public.editor_ia_uso add column coste_max_usd numeric(14,6) check (coste_max_usd >= 0);     -- peor caso apartado al reservar
alter table public.editor_ia_uso add column margen_pct numeric(7,2) check (margen_pct >= 0);           -- congelado al reservar
alter table public.editor_ia_uso add column importe_usd numeric(16,8) check (importe_usd >= 0);        -- coste × (1 + margen), solo «hecho»
alter table public.editor_ia_uso alter column coste_usd type numeric(16,8);                            -- sin redondear (Administración)

-- ─────────────────────────────────────────────────────────────────────────────────────────────── ayudantes
-- Peor caso en dólares de UNA llamada (tope de tokens de entrada y de salida de la función × tarifa). La salida la acota max_tokens = 16000
-- en motor.js; la entrada, los topes de texto de motor.js (TOPES) más las reglas del sistema. Si cambian allí, cambian aquí.
create function public._editor_ia_coste_max(p_accion text) returns numeric language plpgsql stable security definer set search_path = '' as $$
declare a public.editor_ia_ajustes%rowtype; v_in int;
begin
  select * into a from public.editor_ia_ajustes x where x.id;
  if p_accion = 'traduce_deepl' then
    return case when a.tarifa_deepl_usd_mcar is null then null else 20000 * a.tarifa_deepl_usd_mcar / 1000000.0 end;
  end if;
  if a.tarifa_entrada_usd_mtok is null or a.tarifa_salida_usd_mtok is null then return null; end if;
  v_in := case p_accion when 'propone' then 8000 when 'traduce_ia' then 16000 when 'redacta' then 6000 when 'redacta_traduce' then 16000 else null end;
  if v_in is null then return null; end if;
  return (v_in * a.tarifa_entrada_usd_mtok + 16000 * a.tarifa_salida_usd_mtok) / 1000000.0;
end $$;

-- Lo que una llamada pesa contra el tope (coste real para el owner): hecha o fallida enviada = su coste (si no se sabe, el peor caso);
-- en vuelo = el peor caso; caducada enviada = el peor caso (pudo cobrar y no se sabe cuánto); lo que no salió = 0.
create function public._editor_ia_peso(u public.editor_ia_uso) returns numeric language sql immutable set search_path = '' as $$
  select case
    when u.estado = 'reservado' then coalesce(u.coste_max_usd, 0)
    when u.enviada_en is null then 0
    when u.estado in ('hecho', 'fallo') then coalesce(u.coste_usd, u.coste_max_usd, 0)
    else coalesce(u.coste_max_usd, 0) end
$$;

-- Gasto del mes contra el tope: de una empresa, o de toda la instancia (p_empresa null). Hoy solo hay un servicio de pago (este); el bot y
-- los siguientes suman aquí su propio gasto cuando lleguen (AXW-104).
create function public._servicios_gasto_mes(p_empresa text, p_periodo date) returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce(sum(public._editor_ia_peso(u)), 0)
    from public.editor_ia_uso u
   where u.periodo = p_periodo and (p_empresa is null or u.empresa = p_empresa)
$$;

create function public._servicios_tope_empresa(p_empresa text) returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce((select e.tope_usd from public.servicios_axisworks_empresa e where e.empresa = p_empresa),
                  (select a.tope_usd_defecto from public.servicios_axisworks_ajustes a where a.id), 20)
$$;

-- null = se puede usar; si no, la razón en llano (la enseña la pantalla tal cual)
create or replace function public._editor_ia_falta(p_empresa text) returns text language plpgsql stable security definer set search_path = '' as $$
declare a public.editor_ia_ajustes%rowtype; s public.servicios_axisworks_ajustes%rowtype; f text[] := '{}';
begin
  if not exists (select 1 from public.editor_ia_empresa x where x.empresa = p_empresa and x.encendido) then
    return 'El asistente no está encendido para esta empresa.';
  end if;
  if exists (select 1 from public.servicios_axisworks_empresa x where x.empresa = p_empresa and x.suspendido) then
    return 'Los servicios de pago de AxisWorks están suspendidos para esta empresa. Habla con el estudio.';
  end if;
  select * into a from public.editor_ia_ajustes x where x.id;
  select * into s from public.servicios_axisworks_ajustes x where x.id;
  if s.margen_pct is null then f := f || 'el margen sobre el coste'::text; end if;
  if a.tarifa_entrada_usd_mtok is null or a.tarifa_salida_usd_mtok is null then f := f || 'la tarifa del proveedor'::text; end if;
  if cardinality(f) > 0 then return 'Falta configurar en Ajustes → Servicios de AxisWorks: ' || array_to_string(f, ' y ') || '.'; end if;
  return null;
end $$;

-- Reservas que nadie cerró: a los 10 minutos caducan. Ya no hay saldo que devolver: dejan de pesar en vuelo y, si se habían enviado,
-- pesan al peor caso (_editor_ia_peso).
create or replace function public._editor_ia_caduca() returns integer language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform public._editor_ia_candado();
  update public.editor_ia_uso set estado = 'caducada', cerrada_en = now()
   where estado = 'reservado' and fecha < now() - interval '10 minutes';
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public._editor_ia_coste_max(text), public._editor_ia_peso(public.editor_ia_uso), public._servicios_gasto_mes(text, date),
                       public._servicios_tope_empresa(text), public._editor_ia_falta(text), public._editor_ia_caduca()
  from public, anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── estado (pantalla del editor)
create or replace function public.editor_ia_estado(p_empresa text) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_falta text; v_per date := public._editor_ia_periodo(); v_gasto numeric; v_tope numeric; v_aviso int;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El asistente de textos lo usa la administracion de la empresa' using errcode = '42501';
  end if;
  v_falta := public._editor_ia_falta(p_empresa);
  if v_falta is not null then return jsonb_build_object('encendido', false, 'motivo', v_falta); end if;
  v_gasto := public._servicios_gasto_mes(p_empresa, v_per);
  v_tope := public._servicios_tope_empresa(p_empresa);
  select a.aviso_pct into v_aviso from public.servicios_axisworks_ajustes a where a.id;
  return jsonb_build_object('encendido', true, 'motivo', null, 'periodo', v_per,
    'gasto_usd', round(v_gasto, 2), 'tope_usd', v_tope, 'pct', least(100, floor(100 * v_gasto / v_tope))::int,
    'aviso', v_gasto >= v_tope * coalesce(v_aviso, 80) / 100.0, 'lleno', v_gasto >= v_tope,
    'deepl', public._editor_ia_coste_max('traduce_deepl') is not null,
    'coste_max', jsonb_build_object('propone', round(public._editor_ia_coste_max('propone'), 2), 'traduce_ia', round(public._editor_ia_coste_max('traduce_ia'), 2),
                                    'traduce_deepl', round(public._editor_ia_coste_max('traduce_deepl'), 2)));
end $$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── reserva (antes de llamar al proveedor)
-- MISMA firma de 6 parámetros y mismo retorno que la función ya desplegada (create or replace: la edge sigue llamando igual).
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
  if v_falta is not null then raise exception 'Asistente apagado: %', v_falta using errcode = '55000', hint = 'apagado'; end if;
  v_max := public._editor_ia_coste_max(p_accion);
  if v_max is null then raise exception 'Ese motor no esta configurado' using errcode = '55000', hint = 'no_configurado'; end if;
  v_max := v_max * case when p_accion = 'traduce_deepl' then p_parrafos else 1 end;
  perform public._editor_ia_caduca();                                        -- toma el candado: reservas, cierres y caducidad, en cola
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('editor_ia/usuario/' || v_uid::text, 0));
  select count(*) into v_min from public.editor_ia_uso u where u.usuario = v_uid and u.fecha > now() - interval '1 minute';
  if v_min >= 6 then raise exception 'Demasiadas consultas seguidas: espera un minuto' using errcode = 'P0001', hint = 'tope_minuto'; end if;
  select * into s from public.servicios_axisworks_ajustes x where x.id;
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

-- ─────────────────────────────────────────────────────────────────────────────────────────────── cierre (solo la edge, con la clave de servicio)
-- Coste REAL con la tarifa de este momento, sin redondear. Una fallida no se factura (importe null); una fallida enviada sin tokens conocidos
-- (se cortó: entrada y salida 0) deja el coste vacío y pesa contra el tope al peor caso.
create or replace function public.editor_ia_cierra(p_uso uuid, p_ok boolean, p_modelo text, p_entrada integer, p_salida integer, p_caracteres integer,
                                                   p_huella text, p_marcas jsonb default '[]'::jsonb)
 returns boolean language plpgsql security definer set search_path = '' as $$
declare u public.editor_ia_uso%rowtype; m jsonb; a public.editor_ia_ajustes%rowtype; v_coste numeric; v_sabe boolean;
begin
  perform public._editor_ia_candado();
  select * into u from public.editor_ia_uso x where x.id = p_uso for update;
  if not found then raise exception 'Uso no encontrado' using errcode = '22023'; end if;
  if u.estado <> 'reservado' then return false; end if;                       -- ya cerrado o caducado: no se cuenta dos veces
  if p_huella is not null and p_huella !~ '^[0-9a-f]{64}$' then raise exception 'Huella no valida' using errcode = '22023'; end if;
  select * into a from public.editor_ia_ajustes x where x.id;
  v_sabe := p_ok or coalesce(p_entrada, 0) > 0 or coalesce(p_salida, 0) > 0 or coalesce(p_caracteres, 0) > 0 or u.enviada_en is null;
  v_coste := case when not v_sabe then null
                  when u.accion = 'traduce_deepl' then greatest(coalesce(p_caracteres, 0), 0) * a.tarifa_deepl_usd_mcar / 1000000.0
                  else (greatest(coalesce(p_entrada, 0), 0) * a.tarifa_entrada_usd_mtok + greatest(coalesce(p_salida, 0), 0) * a.tarifa_salida_usd_mtok) / 1000000.0 end;
  update public.editor_ia_uso set estado = case when p_ok then 'hecho' else 'fallo' end, cerrada_en = now(),
         modelo = left(p_modelo, 80), tokens_entrada = greatest(coalesce(p_entrada, 0), 0), tokens_salida = greatest(coalesce(p_salida, 0), 0),
         caracteres = greatest(coalesce(p_caracteres, 0), 0), huella_propuesta = case when p_ok then p_huella end, coste_usd = v_coste,
         importe_usd = case when p_ok and v_coste is not null then v_coste * (1 + coalesce(u.margen_pct, 0) / 100.0) end
   where id = u.id;
  if not p_ok then return true; end if;
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

-- ─────────────────────────────────────────────────────────────────────────────────────────────── Ajustes → Servicios de AxisWorks (super admin global)
create function public.servicios_axisworks_datos() returns jsonb language plpgsql stable security definer set search_path = '' as $$
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
    -- redondea una sola vez, al total. Se factura solo lo «hecho»; los fallos enviados son coste del owner («no repercutido»).
    'extracto', coalesce((select jsonb_agg(x order by x ->> 'periodo' desc, x ->> 'empresa') from (
        select jsonb_build_object('periodo', u.periodo, 'empresa', u.empresa,
                 'llamadas', count(*), 'hechas', count(*) filter (where u.estado = 'hecho'),
                 'fallidas', count(*) filter (where u.estado in ('fallo', 'caducada')), 'en_vuelo', count(*) filter (where u.estado = 'reservado'),
                 'coste_proveedor_usd', round(coalesce(sum(u.coste_usd) filter (where u.estado in ('hecho', 'fallo')), 0), 2),
                 'coste_no_repercutido_usd', round(coalesce(sum(u.coste_usd) filter (where u.estado = 'fallo'), 0), 2),
                 'coste_facturable_usd', round(coalesce(sum(u.coste_usd) filter (where u.estado = 'hecho'), 0), 2),
                 'margen_usd', round(coalesce(sum(u.importe_usd - u.coste_usd) filter (where u.estado = 'hecho'), 0), 2),
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

-- p_empresa null = instancia y tarifas; con clave = esa empresa. p_campos: solo las claves que cambian (null = vaciar).
create function public.servicios_axisworks_guarda(p_empresa text, p_campos jsonb, p_motivo text) returns jsonb
 language plpgsql security definer set search_path = '' as $$
declare
  v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
  k text; v jsonb; v_antes jsonb; v_despues jsonb;
  CL_INST constant text[] := array['margen_pct', 'tope_usd_defecto', 'tope_instancia_usd', 'aviso_pct', 'tarifa_entrada_usd_mtok', 'tarifa_salida_usd_mtok', 'tarifa_deepl_usd_mcar'];
  CL_EMP  constant text[] := array['editor_ia', 'tope_usd', 'suspendido'];
  NUM     constant text[] := array['margen_pct', 'tope_usd_defecto', 'tope_instancia_usd', 'tarifa_entrada_usd_mtok', 'tarifa_salida_usd_mtok', 'tarifa_deepl_usd_mcar', 'tope_usd'];
  NO_NULL constant text[] := array['tope_usd_defecto', 'tope_instancia_usd', 'aviso_pct', 'editor_ia', 'suspendido'];
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
revoke all on function public.servicios_axisworks_datos(), public.servicios_axisworks_guarda(text, jsonb, text) from public, anon, service_role;
grant execute on function public.servicios_axisworks_datos(), public.servicios_axisworks_guarda(text, jsonb, text) to authenticated;

-- sin llamador desde hoy (la pantalla de precios en créditos desaparece): nadie las puede ejecutar; se retiran con LAW-555
revoke all on function public.editor_ia_ajustes_datos(), public.editor_ia_ajustes_guarda(text, jsonb, text)
  from public, anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────── encendido de hoy (decisión del owner, 13-oct)
-- Tarifas = coste del proveedor (precio público de Claude Opus 5.5 a 6-oct-2026: 4 USD por millón de tokens de entrada, 20 de salida; se
-- corrigen en Ajustes si cambian). DeepL sin tarifa: no hay cuenta, la traducción va por Claude. Margen VACÍO: lo pone el owner; hasta
-- entonces el asistente responde «falta el margen» y no se llama a nadie. Solo la empresa lawang; Sandal Woods sin fila (apagada).
insert into public.servicios_axisworks_ajustes (id, margen_pct, tope_usd_defecto, tope_instancia_usd, aviso_pct, actualizado_por, actualizado_en)
values (true, null, 20, 20, 80, 'estudio (decisión del owner 13-oct)', now());
update public.editor_ia_ajustes set tarifa_entrada_usd_mtok = 4, tarifa_salida_usd_mtok = 20, tarifa_deepl_usd_mcar = null,
       actualizado_por = 'estudio (decisión del owner 13-oct)', actualizado_en = now()
 where id;
insert into public.servicios_axisworks_empresa (empresa, suspendido, tope_usd, actualizado_por, actualizado_en)
values ('lawang', false, null, 'estudio (decisión del owner 13-oct)', now());
insert into public.editor_ia_empresa (empresa, encendido, actualizado_por, actualizado_en)
values ('lawang', true, 'estudio (decisión del owner 13-oct)', now())
on conflict (empresa) do update set encendido = true, actualizado_por = excluded.actualizado_por, actualizado_en = now();
insert into public.servicios_axisworks_log (ambito, antes, despues, motivo, autor)
values ('instancia', null, jsonb_build_object('margen_pct', null, 'tope_usd_defecto', 20, 'tope_instancia_usd', 20, 'aviso_pct', 80,
                                               'tarifa_entrada_usd_mtok', 4, 'tarifa_salida_usd_mtok', 20, 'tarifa_deepl_usd_mcar', null),
        'Decisión del owner 13-oct: coste + margen, tope 20 USD/mes por empresa, aviso al 80 %; margen pendiente de que lo ponga él', 'estudio (migración 20261013210000)'),
       ('lawang', null, jsonb_build_object('editor_ia', true, 'suspendido', false, 'tope_usd', null),
        'Decisión del owner 13-oct: encendido solo para Lawang', 'estudio (migración 20261013210000)');

do $comprueba$
begin
  if public._editor_ia_falta('lawang') is distinct from 'Falta configurar en Ajustes → Servicios de AxisWorks: el margen sobre el coste.' then
    raise exception 'Encendido de Lawang inesperado: %', coalesce(public._editor_ia_falta('lawang'), 'nada falta');
  end if;
  if exists (select 1 from public.editor_ia_empresa where encendido and empresa <> 'lawang') then
    raise exception 'Otra empresa quedo encendida';
  end if;
end $comprueba$;
