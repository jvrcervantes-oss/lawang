-- destructivo-ok: REVERSION de S12 (consentimiento de seguimiento). Quita las columnas consent_* (la prueba del consentimiento se pierde) y las funciones nuevas, y restaura las 4 funciones sustituidas con el cuerpo que tenian en produccion antes (comprobado por hash el 10-oct-2026).
-- Ejecutar solo si hay que deshacer S12. Antes, apagar BOT_CONSENTIMIENTO y BOT_SEGUIMIENTO en Railway.

create or replace function public.bot_baja(p_tel text, p_wamid text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_w    text := nullif(left(btrim(coalesce(p_wamid, '')), 120), '');
  v_c    public.bot_chat%rowtype;
  v_res  text;
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  insert into public.bot_chat (tel) values (v_tel) on conflict (tel) do nothing;        -- una baja se honra aunque la fila no existiera
  select * into v_c from public.bot_chat where tel = v_tel for update;
  if v_c.baja_en is null then
    update public.bot_chat
       set baja_en = now(), baja_acuse_en = now(), baja_wamid = v_w,
           pausado = true, pausa_hasta = null, pausa_por = 'baja', actualizado_en = now(), actividad_en = now()
     where tel = v_tel;
    v_res := 'nueva';
  elsif v_w is not null and v_c.baja_wamid = v_w then
    v_res := 'nueva';                                                                    -- reintento de la misma peticion: sigue debiendo su acuse
  else
    v_res := 'ya_dada';
  end if;
  return jsonb_build_object('baja', v_res, 'pausado', true);
end $f$;

create or replace function public.bot_turno_estado(p_tel text, p_testing boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_c    public.bot_chat%rowtype;
  v_avisar_testing boolean := false;
  v_hist jsonb;
  v_cfg  jsonb;
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  select * into v_c from public.bot_chat where tel = v_tel;
  if not found then return jsonb_build_object('error', 'sin_chat'); end if;

  if coalesce(p_testing, false) and v_c.aviso_testing_en is null then
    update public.bot_chat set aviso_testing_en = now() where tel = v_tel and aviso_testing_en is null;
    v_avisar_testing := true;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('rol', m.rol, 'texto', m.contenido, 'por', m.por, 'media', m.media,
                                               'ts', (extract(epoch from m.creado_en) * 1000)::bigint) order by m.id), '[]'::jsonb)
    into v_hist
    from (select x.* from public.bot_mensaje x where x.tel = v_tel order by x.id desc limit 20) m;

  select jsonb_build_object('extra', c.extra, 'bienvenida', c.bienvenida, 'pausa_horas', c.pausa_horas,
                            'resumen_cada_n', c.resumen_cada_n, 'fallos_alarma', c.fallos_alarma,
                            'version', c.version, 'actualizado_en', c.actualizado_en)
    into v_cfg from public.bot_config c;

  return jsonb_build_object(
    'baja', v_c.baja_en is not null,
    'pausado', v_c.pausado and (v_c.pausa_hasta is null or v_c.pausa_hasta > now()),
    'esperando', v_c.esperando,
    'avisar_testing', v_avisar_testing,
    'primer_turno', not exists (select 1 from public.bot_mensaje m where m.tel = v_tel and m.rol = 'assistant'),
    'historial', v_hist,
    'config', v_cfg);
end $f$;

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


drop function if exists public.bot_seguimiento_registrar(text, text, text, text, text);
drop function if exists public.bot_seguimiento_reservar(text, text);
drop function if exists public.bot_seguimiento_candidatos();
drop function if exists public.bot_consentimiento_responder(text, text, text, text);
drop function if exists public.bot_consentimiento_enviada(text, text, boolean);
drop function if exists public.bot_consentimiento_preguntar(text, text, text, text, boolean);
drop function if exists public._bot_cs_debido(public.bot_chat);
drop function if exists public._bot_cs_clase(text);
drop function if exists public._bot_cs_sin_cola(text);
drop function if exists public._bot_cs_norm(text);
alter table public.bot_chat drop constraint if exists bot_chat_consent_check;
alter table public.bot_chat
  drop column if exists consent_estado, drop column if exists consent_version, drop column if exists consent_idioma, drop column if exists consent_texto,
  drop column if exists consent_pregunta_wamid, drop column if exists consent_preguntado_en, drop column if exists consent_repregunta_texto,
  drop column if exists consent_repregunta_wamid, drop column if exists consent_repreguntado_en, drop column if exists consent_respuesta_texto,
  drop column if exists consent_respuesta_wamid, drop column if exists consent_respuesta_cita, drop column if exists consent_respondido_en,
  drop column if exists consent_regla, drop column if exists consent_revocado_en, drop column if exists consent_revocado_wamid,
  drop column if exists consent_ancla_en, drop column if exists consent_envio1_en, drop column if exists consent_envio1_wamid,
  drop column if exists consent_envio1_res, drop column if exists consent_envio2_en, drop column if exists consent_envio2_wamid,
  drop column if exists consent_envio2_res;
-- Las sustituidas conservan sus concesiones (create or replace); se reafirman:
revoke all on function public.bot_baja(text, text), public.bot_turno_estado(text, boolean), public._bot_olvidar_tel(text, boolean), public.bot_purga() from public, anon, authenticated, service_role;
grant execute on function public.bot_baja(text, text), public.bot_turno_estado(text, boolean) to bot_lawang;
