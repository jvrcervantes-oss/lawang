-- destructivo-ok: construye la PURGA DE RETENCION del bot (borra solo lo caducado segun Legal, y solo cuando la ejecuta el job pg_cron o un administrador) y el borrado a peticion del titular. La migracion en si no borra ni vacia ninguna fila: crea tablas de traza, funciones y un job. Los delete estan DENTRO de las funciones nuevas bot_purga, _bot_olvidar_tel y lead_nota_retirar; el trigger de bot_acciones_log se sustituye por uno que solo deja borrar a la purga. Reversion: supabase/reversion_bot_sin_redis_s7/REVERSION.sql.
-- ============================================================================
-- LAWANG — BOT SIN REDIS: PURGA, OLVIDO Y RETIRADA DE RESUMENES — S7 (9-oct-2026)
-- ----------------------------------------------------------------------------
-- Encargo: encargos/20261009_lawang_bot_sin_redis.md, subtarea S7. Legal: contexto/legal/bot_lawang_aviso_retencion_precio.md (v2) apartados b y e;
-- filas LAW-508 (texto de legal.html, del owner) y LAW-509 (requisitos de Legal para S7).
--
-- QUE HACE
--   1. bot_purga() (job pg_cron diario 'bot_purga', 03:23 UTC): funcion especifica, SECURITY DEFINER, devuelve y registra SOLO CONTEOS por tabla
--      en bot_purga_log (nunca contenido). Plazos:
--        · bot_mensaje: hilo entero de todo telefono con actividad_en > 365 dias (criterio por inactividad del hilo) y, ADEMAS, tope duro:
--          ningun mensaje vive mas de 24 meses aunque el hilo siga activo.
--        · bot_chat: se borra con el hilo, SALVO bajas («no contactar») y pausas sin caducidad: esas filas se quedan reducidas a la marca
--          (la purga de la memoria no puede olvidar un STOP: el bot volveria a escribir).
--        · bot_wamid: 10 dias (S0: Meta reintenta hasta 7; minimo 8; 10 deja margen).
--        · bot_lecturas_log: 12 meses (Legal) · bot_acciones_log: 90 dias (Legal) · bot_olvidos_log y bot_purga_log: 24 meses.
--        · NO toca lead_notas (los resumenes del bot son decision 6 del owner; su plazo propio lo fija Legal) ni leads ni lead_accion.
--   2. bot_acciones_log deja de ser «solo anade» para ESTE job, con una funcion NUEVA (_bot_log_solo_anade_purga): deja pasar el DELETE solo
--      si la transaccion fijo bot.purga=on (lo hace bot_purga, que es DEFINER y no la ejecuta nadie mas). La compartida
--      bot_acciones_log_solo_anade() NO se toca (la siguen usando bot_config_log, bot_config y los TRUNCATE).
--   3. crm_bot_olvidar(tel, motivo, no_contactar): borrado a peticion del titular. Permiso ALTO (administrador de alcance global). Borra
--      bot_mensaje, bot_escalacion y bot_wamid del telefono; reduce bot_chat a la marca de baja (por defecto marca «no contactar»); reduce la
--      ficha del lead al minimo (Legal e.2.5: sin email, IP, atribucion de campana, respuestas del formulario ni notas libres) salvo que el
--      lead este en reserva/contrato (obligacion legal, Legal b.5.a); NO toca los resumenes (decision 6 del owner). Deja traza con el telefono
--      HASHEADO en bot_olvidos_log y solo conteos.
--   4. bot_olvidos_reaplicar(): tras restaurar un backup, vuelve a aplicar los olvidos (Legal e.5; LAW-509.5). Sin EXECUTE para nadie: se
--      lanza como postgres.
--   5. lead_nota_retirar(nota, motivo): solo administrador de alcance global. Unica via de retirar un resumen del bot (las notas son
--      append-only: sin ella no hay rectificacion, Legal e.2.6). Traza en lead_notas_retiradas (quien, cuando, motivo de lista cerrada, sin contenido).
--
-- LLAMADORES CON NOMBRE (seguridad_2026 §1.ter): bot_purga -> solo el job pg_cron (postgres). crm_bot_olvidar y lead_nota_retirar -> la
-- intranet de Lawang (administradores) por RPC con su JWT; AUTHENTICATED con el permiso comprobado DENTRO. La pantalla que los llama es de S10
-- (hoy no existe): hasta entonces solo se pueden usar por SQL/RPC. Las tablas nuevas nacen cerradas: RLS sin policies, 0 privilegios.
-- ============================================================================

-- ── 1. trazas ────────────────────────────────────────────────────────────────
create table if not exists public.bot_purga_log (
  id     bigint generated always as identity primary key,
  cuando timestamptz not null default now(),
  tabla  text not null check (length(tabla) <= 40),
  filas  integer not null check (filas >= 0),
  motivo text not null check (length(motivo) <= 80)
);
create index if not exists bot_purga_log_cuando on public.bot_purga_log (cuando);

create table if not exists public.bot_olvidos_log (
  id        bigint generated always as identity primary key,
  cuando    timestamptz not null default now(),
  usuario   text not null check (length(usuario) <= 120),
  tel_hash  text not null check (tel_hash ~ '^[0-9a-f]{64}$'),                 -- sha256 del telefono: permite reaplicar el olvido tras restaurar un backup sin guardar el numero
  motivo    text not null check (motivo in ('peticion_titular', 'oposicion', 'autoridad', 'otro')),
  resultado jsonb not null                                                      -- solo conteos
);
create index if not exists bot_olvidos_log_hash on public.bot_olvidos_log (tel_hash);
create index if not exists bot_olvidos_log_cuando on public.bot_olvidos_log (cuando);

create table if not exists public.lead_notas_retiradas (
  id      bigint generated always as identity primary key,
  cuando  timestamptz not null default now(),
  usuario text not null check (length(usuario) <= 120),
  nota_id bigint not null,
  lead_id uuid not null,                                                        -- sin FK: el lead puede borrarse despues y la traza se queda
  motivo  text not null check (motivo in ('dato_sensible', 'rectificacion', 'oposicion', 'autoridad', 'otro'))
);

alter table public.bot_purga_log        enable row level security;
alter table public.bot_olvidos_log      enable row level security;
alter table public.lead_notas_retiradas enable row level security;
revoke all on public.bot_purga_log, public.bot_olvidos_log, public.lead_notas_retiradas from public, anon, authenticated, service_role;
revoke all on sequence public.bot_purga_log_id_seq, public.bot_olvidos_log_id_seq, public.lead_notas_retiradas_id_seq from public, anon, authenticated, service_role;

-- Funcion NUEVA de «solo anade con excepcion de la purga». No se reutiliza la compartida (la siguen usando bot_config_log y los TRUNCATE).
create or replace function public._bot_log_solo_anade_purga()
returns trigger language plpgsql set search_path = '' as $f$
begin
  if tg_op = 'DELETE' and coalesce(current_setting('bot.purga', true), '') = 'on' then
    return old;
  end if;
  raise exception '% es de solo anadir (solo la purga de retencion borra)', tg_table_name using errcode = '42501';
end $f$;
revoke all on function public._bot_log_solo_anade_purga() from public, anon, authenticated, service_role;

do $c$ begin
  -- bot_acciones_log: se sustituye el trigger de fila (update/delete) por el que deja pasar a la purga. El de TRUNCATE no se toca.
  drop trigger if exists trg_bot_acciones_log_solo_anade on public.bot_acciones_log;
  create trigger trg_bot_acciones_log_solo_anade before update or delete on public.bot_acciones_log
    for each row execute function public._bot_log_solo_anade_purga();
  if not exists (select 1 from pg_trigger where tgname = 'trg_bot_purga_log_solo_anade' and tgrelid = 'public.bot_purga_log'::regclass) then
    create trigger trg_bot_purga_log_solo_anade before update or delete on public.bot_purga_log
      for each row execute function public._bot_log_solo_anade_purga();
    create trigger trg_bot_purga_log_no_truncate before truncate on public.bot_purga_log
      for each statement execute function public.bot_acciones_log_solo_anade();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_bot_olvidos_log_solo_anade' and tgrelid = 'public.bot_olvidos_log'::regclass) then
    create trigger trg_bot_olvidos_log_solo_anade before update or delete on public.bot_olvidos_log
      for each row execute function public._bot_log_solo_anade_purga();
    create trigger trg_bot_olvidos_log_no_truncate before truncate on public.bot_olvidos_log
      for each statement execute function public.bot_acciones_log_solo_anade();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_lead_notas_retiradas_solo_anade' and tgrelid = 'public.lead_notas_retiradas'::regclass) then
    create trigger trg_lead_notas_retiradas_solo_anade before update or delete on public.lead_notas_retiradas
      for each row execute function public.bot_acciones_log_solo_anade();
    create trigger trg_lead_notas_retiradas_no_truncate before truncate on public.lead_notas_retiradas
      for each statement execute function public.bot_acciones_log_solo_anade();
  end if;
end $c$;

-- ── 2. la purga ──────────────────────────────────────────────────────────────
create or replace function public.bot_purga()
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_res jsonb := '{}'::jsonb;
  n int;
  v_inact constant timestamptz := now() - interval '365 days';
  v_tope  constant timestamptz := now() - interval '24 months';
begin
  perform set_config('bot.purga', 'on', true);          -- solo dentro de esta transaccion: abre el DELETE de los logs

  -- A. hilos inactivos (>365 dias): mensajes, escalaciones y, si no hay baja ni pausa sin caducidad, la conversacion entera
  with d as (delete from public.bot_mensaje m using public.bot_chat c
              where m.tel = c.tel and c.actividad_en < v_inact returning 1)
  select count(*) into n from d;
  v_res := v_res || jsonb_build_object('bot_mensaje_hilo_inactivo', n);
  insert into public.bot_purga_log (tabla, filas, motivo) values ('bot_mensaje', n, 'hilo inactivo 365 d');

  with d as (delete from public.bot_escalacion e using public.bot_chat c
              where e.tel = c.tel and c.actividad_en < v_inact returning 1)
  select count(*) into n from d;
  v_res := v_res || jsonb_build_object('bot_escalacion_hilo_inactivo', n);
  insert into public.bot_purga_log (tabla, filas, motivo) values ('bot_escalacion', n, 'hilo inactivo 365 d');

  with d as (delete from public.bot_chat c
              where c.actividad_en < v_inact and c.baja_en is null and not (c.pausado and c.pausa_hasta is null) returning 1)
  select count(*) into n from d;
  v_res := v_res || jsonb_build_object('bot_chat_borrados', n);
  insert into public.bot_purga_log (tabla, filas, motivo) values ('bot_chat', n, 'hilo inactivo 365 d, sin baja ni pausa fija');

  -- las bajas y pausas sin caducidad se quedan, pero reducidas a la marca (sin nombre, intent ni ultimo mensaje)
  with d as (update public.bot_chat c
                set nombre_perfil = null, intent = null, ultimo_mensaje = null, ultimo_por = null, lead_id = null,
                    esperando = false, resumen_hasta_id = null, ultimo_entrante_en = null, entrega_error = null, entrega_error_en = null,
                    actualizado_en = now()
              where c.actividad_en < v_inact and (c.baja_en is not null or (c.pausado and c.pausa_hasta is null))
                and (c.nombre_perfil is not null or c.intent is not null or c.ultimo_mensaje is not null or c.lead_id is not null
                     or c.ultimo_por is not null or c.ultimo_entrante_en is not null or c.entrega_error is not null)
              returning 1)
  select count(*) into n from d;
  v_res := v_res || jsonb_build_object('bot_chat_reducidos_a_la_marca', n);
  insert into public.bot_purga_log (tabla, filas, motivo) values ('bot_chat', n, 'baja/pausa fija reducida a la marca');

  -- B. tope duro: ningun mensaje pasa de 24 meses, aunque el hilo siga activo
  with d as (delete from public.bot_mensaje where creado_en < v_tope returning 1) select count(*) into n from d;
  v_res := v_res || jsonb_build_object('bot_mensaje_tope_24m', n);
  insert into public.bot_purga_log (tabla, filas, motivo) values ('bot_mensaje', n, 'tope 24 meses por mensaje');

  -- C. identificadores tecnicos de mensaje
  with d as (delete from public.bot_wamid where visto_en < now() - interval '10 days' returning 1) select count(*) into n from d;
  v_res := v_res || jsonb_build_object('bot_wamid', n);
  insert into public.bot_purga_log (tabla, filas, motivo) values ('bot_wamid', n, 'plazo tecnico 10 d');

  -- D. registros
  with d as (delete from public.bot_lecturas_log where cuando < now() - interval '12 months' returning 1) select count(*) into n from d;
  v_res := v_res || jsonb_build_object('bot_lecturas_log', n);
  insert into public.bot_purga_log (tabla, filas, motivo) values ('bot_lecturas_log', n, 'registro de lecturas 12 meses');

  with d as (delete from public.bot_acciones_log where cuando < now() - interval '90 days' returning 1) select count(*) into n from d;
  v_res := v_res || jsonb_build_object('bot_acciones_log', n);
  insert into public.bot_purga_log (tabla, filas, motivo) values ('bot_acciones_log', n, 'registro de acciones 90 d');

  with d as (delete from public.bot_olvidos_log where cuando < now() - interval '24 months' returning 1) select count(*) into n from d;
  v_res := v_res || jsonb_build_object('bot_olvidos_log', n);
  insert into public.bot_purga_log (tabla, filas, motivo) values ('bot_olvidos_log', n, 'traza de olvidos 24 meses');

  with d as (delete from public.bot_purga_log where cuando < now() - interval '24 months' returning 1) select count(*) into n from d;
  v_res := v_res || jsonb_build_object('bot_purga_log', n);
  return v_res;
end $f$;
revoke all on function public.bot_purga() from public, anon, authenticated, service_role;

-- ── 3. olvido: el nucleo (lo usan crm_bot_olvidar y bot_olvidos_reaplicar) ───
create or replace function public._bot_tel_hash(p_tel text)
returns text language sql immutable set search_path = '' as $f$
  select encode(sha256(convert_to('lawang-bot-olvido:' || p_tel, 'UTF8')), 'hex')
$f$;
revoke all on function public._bot_tel_hash(text) from public, anon, authenticated, service_role;


create or replace function public._bot_olvidar_tel(p_tel text, p_no_contactar boolean)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_c public.bot_chat%rowtype;
  v_leads uuid[];
  v_msg int := 0; v_esc int := 0; v_wam int := 0; v_notas int := 0; v_fichas int := 0; v_contr int := 0;
  v_chat text := 'sin_fila';
begin
  select * into v_c from public.bot_chat where tel = p_tel for update;
  -- leads de ese telefono: el que enlazo el bot y los que casan por numero (si hay varios, todos: es la misma persona)
  select coalesce(array_agg(distinct x), '{}') into v_leads from (
    select v_c.lead_id as x where v_c.lead_id is not null
    union
    select l.id from public.leads l where public._bot_tel(l.whatsapp) = p_tel
  ) s;

  with d as (delete from public.bot_mensaje where tel = p_tel returning 1) select count(*) into v_msg from d;
  with d as (delete from public.bot_escalacion where tel = p_tel returning 1) select count(*) into v_esc from d;
  with d as (delete from public.bot_wamid where tel = p_tel returning 1) select count(*) into v_wam from d;

  if v_c.tel is not null then
    if p_no_contactar or v_c.baja_en is not null then
      -- se queda SOLO la marca: baja + pausa fija (el bot no vuelve a escribir) y el acuse ya dado (no manda otro)
      update public.bot_chat
         set nombre_perfil = null, intent = null, ultimo_mensaje = null, ultimo_por = null, lead_id = null, esperando = false,
             resumen_hasta_id = null, ultimo_entrante_en = null, entrega_error = null, entrega_error_en = null,
             seguimientos = 0, aviso_nivel = 0, aviso_testing_en = null,
             baja_en = coalesce(baja_en, now()), baja_acuse_en = coalesce(baja_acuse_en, now()),
             pausado = true, pausa_hasta = null, pausa_por = coalesce(pausa_por, 'olvido'), actualizado_en = now()
       where tel = p_tel;
      v_chat := 'reducida_a_la_marca';
    else
      delete from public.bot_chat where tel = p_tel;
      v_chat := 'borrada';
    end if;
  elsif p_no_contactar then
    insert into public.bot_chat (tel, baja_en, baja_acuse_en, pausado, pausa_por) values (p_tel, now(), now(), true, 'olvido');
    v_chat := 'marca_creada';
  end if;

  -- ficha minima (Legal e.2.5): sin email, IP, atribucion de campana, respuestas del formulario ni notas libres.
  -- NO se tocan: nombre, telefono, citas, estado, y los RESUMENES del bot (decision 6 del owner). Un lead en reserva/contrato no se toca (obligacion legal).
  if cardinality(v_leads) > 0 then
    select count(*) into v_contr from unnest(v_leads) x
     where exists (select 1 from public.lead_estado e where e.lead_id = x and e.estado in ('reserva', 'contrato'));
    with ok as (
      select x as id from unnest(v_leads) x
       where not exists (select 1 from public.lead_estado e where e.lead_id = x and e.estado in ('reserva', 'contrato'))
    ),
    n as (delete from public.lead_notas where lead_id in (select id from ok) and tipo = 'nota' returning 1),
    f as (update public.leads set email = null, ip = null, campaign_id = null, adset_id = null, ad_id = null, form_id = null, respuestas = null
           where id in (select id from ok) returning 1)
    select (select count(*) from n), (select count(*) from f) into v_notas, v_fichas;
  end if;

  return jsonb_build_object('bot_mensaje', v_msg, 'bot_escalacion', v_esc, 'bot_wamid', v_wam, 'bot_chat', v_chat,
                            'leads', cardinality(v_leads), 'fichas_reducidas', v_fichas, 'notas_libres_borradas', v_notas,
                            'fichas_conservadas_por_contrato', v_contr);
end $f$;
revoke all on function public._bot_olvidar_tel(text, boolean) from public, anon, authenticated, service_role;

create or replace function public.crm_bot_olvidar(p_tel text, p_motivo text default 'peticion_titular', p_no_contactar boolean default true)
returns jsonb language plpgsql volatile security definer set search_path = '' as $f$
declare
  v_quien text := coalesce(nullif((select auth.email()), ''), '');
  v_tel text := public._bot_tel(p_tel);
  v_res jsonb;
begin
  if v_quien = '' or not exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo and u.ambito = 'global' and coalesce(cardinality(u.empresas), 0) = 0
       and u.rol in ('super_admin', 'admin')
  ) then
    raise exception 'Sin permiso para borrar datos del bot' using errcode = '42501';
  end if;
  if v_tel is null or v_tel !~ '^[0-9]{6,20}$' then raise exception 'Telefono no valido' using errcode = 'PT400'; end if;
  if p_motivo is null or p_motivo not in ('peticion_titular', 'oposicion', 'autoridad', 'otro') then
    raise exception 'Motivo no valido' using errcode = 'PT400';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot_olvidar:' || v_tel, 0));
  v_res := public._bot_olvidar_tel(v_tel, coalesce(p_no_contactar, true));
  insert into public.bot_olvidos_log (usuario, tel_hash, motivo, resultado)
  values (left(v_quien, 120), public._bot_tel_hash(v_tel), p_motivo, v_res);
  return v_res || jsonb_build_object('ok', true);
end $f$;
revoke all on function public.crm_bot_olvidar(text, text, boolean) from public, anon, service_role;
grant execute on function public.crm_bot_olvidar(text, text, boolean) to authenticated;

-- Tras restaurar un backup en produccion: reaplica los olvidos (Legal e.5, LAW-509.5). Sin EXECUTE para nadie: se lanza como postgres.
create or replace function public.bot_olvidos_reaplicar()
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare r record; n int := 0;
begin
  for r in
    select distinct t.tel from (select tel from public.bot_chat union select tel from public.bot_wamid) t
     where public._bot_tel_hash(t.tel) in (select tel_hash from public.bot_olvidos_log)
  loop
    perform public._bot_olvidar_tel(r.tel, true);
    n := n + 1;
  end loop;
  return jsonb_build_object('telefonos_reaplicados', n);
end $f$;
revoke all on function public.bot_olvidos_reaplicar() from public, anon, authenticated, service_role;

-- ── 4. retirar un resumen del bot (unica via: las notas son append-only) ─────
create or replace function public.lead_nota_retirar(p_nota bigint, p_motivo text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $f$
declare
  v_quien text := coalesce(nullif((select auth.email()), ''), '');
  v_lead uuid;
begin
  if v_quien = '' or not exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo and u.ambito = 'global' and coalesce(cardinality(u.empresas), 0) = 0
       and u.rol in ('super_admin', 'admin')
  ) then
    raise exception 'Sin permiso para retirar resumenes' using errcode = '42501';
  end if;
  if p_motivo is null or p_motivo not in ('dato_sensible', 'rectificacion', 'oposicion', 'autoridad', 'otro') then
    raise exception 'Motivo no valido' using errcode = 'PT400';
  end if;
  delete from public.lead_notas where id = p_nota and tipo = 'resumen_bot' returning lead_id into v_lead;
  if v_lead is null then raise exception 'Solo se pueden retirar resumenes del bot que existan' using errcode = 'PT404'; end if;
  insert into public.lead_notas_retiradas (usuario, nota_id, lead_id, motivo) values (left(v_quien, 120), p_nota, v_lead, p_motivo);
  return jsonb_build_object('ok', true);
end $f$;
revoke all on function public.lead_nota_retirar(bigint, text) from public, anon, service_role;
grant execute on function public.lead_nota_retirar(bigint, text) to authenticated;

-- ── 5. el job ────────────────────────────────────────────────────────────────
do $c$ begin
  if exists (select 1 from cron.job where jobname = 'bot_purga') then perform cron.unschedule('bot_purga'); end if;
  perform cron.schedule('bot_purga', '23 3 * * *', 'select public.bot_purga()');
end $c$;
