-- REVERSION de 20261010110000_bot_sin_redis_s1_esquema.sql (S1 del encargo «bot de Lawang sin Redis»).
-- NO es una migracion: no se aplica sola. Solo si el owner pide deshacer S1 ANTES de que el bot escriba en estas tablas
-- (despues, hay datos de conversaciones: parar y preguntar). Es destructivo a proposito (todo lo que borra lo creo S1).
-- Orden: funciones nuevas → triggers → tablas → columnas → bot_lead_upsert a su version anterior.

-- 1. funciones nuevas
-- (20261010110100_bot_sin_redis_s1_ajustes solo reemplaza 4 funciones de estas mismas firmas: este drop tambien la revierte)
drop function if exists public.bot_mensaje_recibir(text, text, text, jsonb);
drop function if exists public.bot_turno_estado(text, boolean);
drop function if exists public.bot_turno_cerrar(text, text, jsonb, text, text, boolean, boolean);
drop function if exists public.bot_eco_operadora(text, text, text, int);
drop function if exists public.bot_pausar(text, text, int);
drop function if exists public.bot_baja(text, text);
drop function if exists public.bot_entrega_fallida(text, text, text);
drop function if exists public.bot_escalar(text, text, text, text);
drop function if exists public.bot_escalacion_tomar(text);
drop function if exists public.bot_lead_resumen(text, text, bigint);
drop function if exists public.bot_citas_recordar();
drop function if exists public.bot_cita_recordatorio_res(uuid, text);
drop function if exists public.bot_pausar_humano(text, text, text);
drop function if exists public.bot_envio_humano(text, text, text, jsonb, text);
drop function if exists public._bot_conversaciones_autoriza(text, text);

-- 2. trigger de lead_accion y tablas (los triggers de las tablas caen con ellas)
drop trigger if exists trg_lead_accion_recordatorio_reinicia on public.lead_accion;
drop table if exists public.bot_lecturas_log, public.bot_config_log, public.bot_config,
                     public.bot_escalacion, public.bot_mensaje, public.bot_wamid, public.bot_chat;
drop function if exists public._bot_recordatorio_reinicia();
drop function if exists public._bot_lecturas_solo_anade();
drop function if exists public._bot_config_antes();
drop function if exists public._bot_config_log();
drop function if exists public._bot_pausa_humana(text, int, text);
drop function if exists public._bot_media(jsonb);
drop function if exists public._bot_limpia(text, int);
drop function if exists public._bot_tel(text);

-- 3. columnas nuevas (al soltar lead_notas.tipo, los resumenes del bot SOBREVIVEN como notas normales, indistinguibles de las humanas: marcarlos antes con un update de texto si importa)
drop index if exists public.lead_notas_resumen_unico;
drop index if exists public.lead_accion_recordar;
alter table public.lead_notas  drop constraint if exists lead_notas_tipo_check, drop column if exists tipo, drop column if exists ref_hasta_id;
alter table public.lead_accion drop constraint if exists lead_accion_recordatorio_res_check,
                               drop column if exists recordatorio_en, drop column if exists recordatorio_res, drop column if exists recordatorio_intentos;

-- 4. bot_lead_upsert: version anterior (20261010080200, vigente el 9-oct-2026 antes de S1)
create or replace function public.bot_lead_upsert(
  p_tel text, p_nombre text default null::text, p_origen text default 'bot-whatsapp-lawang'::text, p_msg_id text default null::text)
returns text language plpgsql security definer set search_path to '' as $function$
declare
  v_e164   text := public._bot_e164(p_tel);
  v_msg    text := nullif(left(btrim(coalesce(p_msg_id, '')), 120), '');
  v_nombre text := nullif(left(btrim(regexp_replace(regexp_replace(coalesce(p_nombre, ''), '[[:cntrl:]]', ' ', 'g'), ' {2,}', ' ', 'g')), 80), '');
  v_origen text := case when p_origen in ('bot-whatsapp-lawang', 'bot-whatsapp-sumbahills') then p_origen else 'bot-whatsapp-lawang' end;
  v_prev   text;
  v_ids    uuid[];
  v_lead   uuid;
begin
  if v_e164 is null then return 'telefono_invalido'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  if v_msg is not null then
    select l.resultado into v_prev from public.bot_acciones_log l where l.accion = 'upsert' and l.msg_id = v_msg;
    if found then return v_prev; end if;
  end if;

  select coalesce(array_agg(l.id order by l.created_at), '{}') into v_ids
    from public.leads l where public._lw_tel_e164(l.whatsapp) = v_e164;

  if cardinality(v_ids) > 1 then
    perform public._bot_nota_ambiguo(v_ids, 'alta');
    perform public._bot_log('upsert', null, v_msg, 'ambiguo', 'n=' || cardinality(v_ids));
    return 'ambiguo';
  end if;

  if cardinality(v_ids) = 1 then
    v_lead := v_ids[1];
    if (select count(*) from public.bot_acciones_log l
         where l.lead_id = v_lead and l.accion = 'upsert' and l.cuando > now() - interval '24 hours') >= 500 then
      return 'tope';
    end if;
    if v_nombre is not null then
      update public.leads set name = v_nombre where id = v_lead and name is null;
    end if;
    perform public._bot_log('upsert', v_lead, v_msg, 'existente');
    return 'existente';
  end if;

  if (select count(*) from public.bot_acciones_log l
       where l.accion = 'upsert' and l.resultado = 'creado' and l.cuando > now() - interval '1 hour') >= 60 then
    return 'tope';
  end if;
  insert into public.leads (whatsapp, name, source) values (v_e164, v_nombre, v_origen) returning id into v_lead;
  perform public._bot_log('upsert', v_lead, v_msg, 'creado');
  return 'creado';
end $function$;
