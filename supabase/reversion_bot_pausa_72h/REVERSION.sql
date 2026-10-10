-- REVERSION de LAW-515 (pausa manual 72 h): restaura _bot_pausa_humana y bot_pausar_humano (cuerpo de 20261010110100) y bot_purga (cuerpo de S12).
-- destructivo-ok: solo create or replace de funciones; no toca datos. Las pausas con caducidad ya escritas se quedan como estan.

create or replace function public._bot_pausa_humana(p_tel text, p_horas int default null, p_por text default null)
returns timestamptz language plpgsql set search_path = '' as $f$
declare
  v_h int := least(greatest(coalesce(p_horas, (select c.pausa_horas from public.bot_config c)), 0), 720);
  v_c public.bot_chat%rowtype;
  v_hasta timestamptz;
begin
  select * into v_c from public.bot_chat where tel = p_tel for update;
  if not found or v_c.baja_en is not null then return null; end if;
  if v_h = 0 then
    update public.bot_chat set pausado = true, pausa_hasta = null, pausa_por = coalesce(left(p_por, 120), pausa_por), actualizado_en = now()
     where tel = p_tel;
    return null;
  end if;
  if v_c.pausado and v_c.pausa_hasta is null then return null; end if;
  v_hasta := now() + make_interval(hours => v_h);
  update public.bot_chat set pausado = true, pausa_hasta = v_hasta, pausa_por = coalesce(left(p_por, 120), pausa_por), actualizado_en = now()
   where tel = p_tel;
  return v_hasta;
end $f$;

create or replace function public.bot_pausar_humano(p_tel text, p_modo text, p_usuario text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_u    text := nullif(public._bot_limpia(p_usuario, 120), '');
  v_c    public.bot_chat%rowtype;
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  if v_u is null then return jsonb_build_object('error', 'sin_usuario'); end if;
  if p_modo is null or p_modo not in ('pausar', 'quitar') then return jsonb_build_object('error', 'modo_invalido'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  if not exists (select 1 from public.bot_chat where tel = v_tel) then return jsonb_build_object('error', 'sin_chat'); end if;
  update public.bot_chat
     set pausado = (p_modo = 'pausar'), pausa_hasta = null, pausa_por = v_u, actualizado_en = now()
   where tel = v_tel and baja_en is null;
  select * into v_c from public.bot_chat where tel = v_tel;
  return jsonb_build_object('pausado', v_c.pausado, 'hasta', v_c.pausa_hasta);
end $f$;

create or replace function public.bot_purga()
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_res jsonb := '{}'::jsonb;
  n int;
  v_inact constant timestamptz := now() - interval '365 days';
  v_tope  constant timestamptz := now() - interval '24 months';
begin
  perform set_config('bot.purga', 'on', true);

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
              where c.actividad_en < v_inact and c.baja_en is null and c.consent_estado <> 'revocado' and not (c.pausado and c.pausa_hasta is null) returning 1)
  select count(*) into n from d;
  v_res := v_res || jsonb_build_object('bot_chat_borrados', n);
  insert into public.bot_purga_log (tabla, filas, motivo) values ('bot_chat', n, 'hilo inactivo 365 d, sin baja ni pausa fija ni consentimiento revocado');

  with d as (update public.bot_chat c
                set nombre_perfil = null, intent = null, ultimo_mensaje = null, ultimo_por = null, lead_id = null,
                    esperando = false, resumen_hasta_id = null, ultimo_entrante_en = null, entrega_error = null, entrega_error_en = null,
                    consent_texto = null, consent_repregunta_texto = null, consent_respuesta_texto = null,
                    actualizado_en = now()
              where c.actividad_en < v_inact and (c.baja_en is not null or (c.pausado and c.pausa_hasta is null) or c.consent_estado = 'revocado')
                and (c.nombre_perfil is not null or c.intent is not null or c.ultimo_mensaje is not null or c.lead_id is not null
                     or c.ultimo_por is not null or c.ultimo_entrante_en is not null or c.entrega_error is not null
                     or c.consent_texto is not null or c.consent_repregunta_texto is not null or c.consent_respuesta_texto is not null)
              returning 1)
  select count(*) into n from d;
  v_res := v_res || jsonb_build_object('bot_chat_reducidos_a_la_marca', n);
  insert into public.bot_purga_log (tabla, filas, motivo) values ('bot_chat', n, 'baja/pausa fija/revocado reducida a la marca');

  with d as (delete from public.bot_mensaje where creado_en < v_tope returning 1) select count(*) into n from d;
  v_res := v_res || jsonb_build_object('bot_mensaje_tope_24m', n);
  insert into public.bot_purga_log (tabla, filas, motivo) values ('bot_mensaje', n, 'tope 24 meses por mensaje');

  with d as (delete from public.bot_wamid where visto_en < now() - interval '10 days' returning 1) select count(*) into n from d;
  v_res := v_res || jsonb_build_object('bot_wamid', n);
  insert into public.bot_purga_log (tabla, filas, motivo) values ('bot_wamid', n, 'plazo tecnico 10 d');

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
