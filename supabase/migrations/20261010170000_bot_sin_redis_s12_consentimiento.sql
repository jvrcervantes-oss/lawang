-- destructivo-ok: construye las columnas y funciones del consentimiento de seguimiento (S12). El UPDATE solo ANADE la marca `revocado` a las filas que ya tenian baja (no borra ni vacia nada) y las funciones sustituidas (bot_baja, bot_turno_estado, _bot_olvidar_tel, bot_purga) conservan su cuerpo de produccion salvo lo declarado abajo. Reversion: supabase/reversion_bot_sin_redis_s12/REVERSION.sql.
-- ============================================================================
-- LAWANG — BOT SIN REDIS — S12: CONSENTIMIENTO DE SEGUIMIENTO Y REENGANCHE (10-oct-2026)
-- Encargo: encargos/20261009_lawang_bot_sin_redis.md (S12, LAW-507). Texto y reglas de Legal: contexto/legal/bot_lawang_consentimiento_seguimiento.md
-- (version CONSENT-SEGUIMIENTO-2026-10-09-v1). Decision del owner 9-oct: UNA sola pregunta por lead.
--
-- PRINCIPIO: el estado del consentimiento lo fija ESTE codigo (SQL determinista contra las listas cerradas de Legal §2), nunca una etiqueta del
-- modelo ni un valor que mande el bot: ninguna funcion recibe un `estado`. El bot manda el telefono, el wamid, el texto literal del lead y el
-- `context.id`; la base normaliza, compara con las listas y decide.
--
-- PIEZAS
--   · bot_chat.consent_*  registro de Legal §3.1 (estado, version, textos EXACTOS preguntados, wamids, respuesta literal, regla, revocacion)
--                        y los dos envios de reenganche (envio1/envio2: fecha, wamid, resultado) y el ancla (ultimo mensaje nuestro antes del 1.º envio).
--   · bot_consentimiento_preguntar / _enviada   reservar -> enviar -> anclar el wamid. Si el envio falla el estado se queda `preguntado` sin wamid:
--                        no se vuelve a preguntar (preguntar de menos es el fallo seguro).
--   · bot_consentimiento_responder              interpreta la respuesta (listas cerradas; regla cita / turno_siguiente; una repregunta; despues `no`).
--   · bot_seguimiento_candidatos / _reservar / _registrar   el reloj del reenganche. SOLO sale con consentimiento `si` vigente (<=30 d), sin baja,
--                        sin pausa, sin respuesta del lead, sin intervencion de la operadora ni cita abierta, y como maximo 2 por lead.
--   · bot_baja (sustituida): la baja marca ademas el consentimiento `revocado` en la MISMA llamada (no hay segundo detector de STOP).
--   · _bot_olvidar_tel y bot_purga (sustituidas): vacian los textos de consentimiento y CONSERVAN la marca `revocado` sin plazo.
--   · bot_turno_estado (sustituida): anade `consentimiento` {estado, repreguntado, puede_preguntar} a la respuesta (sin llamada extra).
--
-- EXCEPCION 3 a «el bot no lee otro telefono» (regla 4 del plan), declarada con nombre y tope: bot_seguimiento_candidatos() — <=20 filas, solo
-- telefonos con consentimiento `si` vigente y envio debido; sin parametros. Va por la ruta /recordatorio (el reloj). Las otras dos: bot_citas_recordar
-- y bot_escalacion_tomar.
--
-- LO QUE NO HACE: no activa nada. El bot solo pregunta con BOT_CONSENTIMIENTO=on y solo envia con BOT_SEGUIMIENTO=postgres (ambas apagadas por defecto)
-- y con BOT_MODE=testing el freno de salida sigue vigente. Antes de encender: contrastar la politica de opt-in de Meta y validar UU PDP con abogado indonesio.
-- RETENCION: el registro vive en bot_chat, asi que se purga con el hilo (365 d de inactividad), MENOS que el tope de 24 meses que admite Legal §3.2;
-- la marca `revocado` no caduca.
-- ============================================================================

-- ── 1. columnas ──────────────────────────────────────────────────────────────
alter table public.bot_chat
  add column if not exists consent_estado           text not null default 'sin_preguntar',
  add column if not exists consent_version          text,
  add column if not exists consent_idioma           text,
  add column if not exists consent_texto            text,
  add column if not exists consent_pregunta_wamid   text,
  add column if not exists consent_preguntado_en    timestamptz,
  add column if not exists consent_repregunta_texto text,
  add column if not exists consent_repregunta_wamid text,
  add column if not exists consent_repreguntado_en  timestamptz,
  add column if not exists consent_respuesta_texto  text,
  add column if not exists consent_respuesta_wamid  text,
  add column if not exists consent_respuesta_cita   text,
  add column if not exists consent_respondido_en    timestamptz,
  add column if not exists consent_regla            text,
  add column if not exists consent_revocado_en      timestamptz,
  add column if not exists consent_revocado_wamid   text,
  add column if not exists consent_ancla_en         timestamptz,
  add column if not exists consent_envio1_en        timestamptz,
  add column if not exists consent_envio1_wamid     text,
  add column if not exists consent_envio1_res       text,
  add column if not exists consent_envio2_en        timestamptz,
  add column if not exists consent_envio2_wamid     text,
  add column if not exists consent_envio2_res       text;

do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'bot_chat_consent_check') then
    alter table public.bot_chat add constraint bot_chat_consent_check check (
      consent_estado in ('sin_preguntar', 'preguntado', 'si', 'no', 'revocado', 'usado', 'caducado')
      and (consent_idioma is null or consent_idioma in ('en', 'es'))
      and (consent_texto is null or length(consent_texto) <= 1500)
      and (consent_repregunta_texto is null or length(consent_repregunta_texto) <= 600)
      and (consent_respuesta_texto is null or length(consent_respuesta_texto) <= 500)
      and (consent_regla is null or length(consent_regla) <= 120)
      and (consent_envio1_res is null or consent_envio1_res in ('reservado', 'enviado', 'fallo'))
      and (consent_envio2_res is null or consent_envio2_res in ('reservado', 'enviado', 'fallo'))
      -- un `si` lleva SIEMPRE su prueba: respuesta, wamid y regla
      and (consent_estado <> 'si' or (consent_respondido_en is not null and consent_respuesta_wamid is not null and consent_regla is not null))
    );
  end if;
end $c$;

-- Las bajas que ya existian pasan a `revocado` (la baja manda siempre).
update public.bot_chat set consent_estado = 'revocado', consent_revocado_en = baja_en, consent_revocado_wamid = baja_wamid
 where baja_en is not null and consent_estado <> 'revocado';

-- ── 2. ayudantes internos ────────────────────────────────────────────────────
-- Normaliza el mensaje del lead (Legal §2.2): minusculas, sin tildes, sin apostrofes, sin puntuacion ni emojis, espacios recortados.
create or replace function public._bot_cs_norm(p text)
returns text language sql immutable set search_path = '' as $f$
  select btrim(regexp_replace(regexp_replace(
           translate(lower(replace(replace(replace(coalesce(p, ''), '’', ''), '‘', ''), '''', '')), 'áéíóúüñàèìòù', 'aeiouunaeiou'),
           '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'))
$f$;

-- Cola de cortesia que se admite SOLO en el si y el no (Legal §2.2). Un mensaje que era solo cola queda vacio y no esta en ninguna lista.
create or replace function public._bot_cs_sin_cola(p text)
returns text language sql immutable set search_path = '' as $f$
  select btrim(regexp_replace(p, '( (please|por favor|thanks|thank you|gracias|terima kasih))+$', '', 'g'))
$f$;

-- Listas cerradas de Legal §2.3 y §2.4 ya normalizadas. Indonesio SIN activar: no entra.
create or replace function public._bot_cs_clase(p text)
returns text language sql immutable set search_path = '' as $f$
  with t as (select public._bot_cs_norm(p) as n)
  select case
    when t.n = '' then 'ambiguo'
    when t.n = any (array['yes','y','yes please','yeah','yep','sure','yes sure','of course','go ahead','thats fine',
                          'si','s','si por favor','claro','por supuesto','de acuerdo','adelante','vale si','si vale'])
      or public._bot_cs_sin_cola(t.n) = any (array['yes','y','yeah','yep','sure','yes sure','of course','go ahead','thats fine',
                          'si','s','claro','por supuesto','de acuerdo','adelante','vale si','si vale']) then 'si'
    when t.n = any (array['no','n','nope','no thanks','no thank you','not now','no need','dont',
                          'no gracias','ahora no','mejor no','no hace falta','no quiero'])
      or public._bot_cs_sin_cola(t.n) = any (array['no','n','nope','not now','no need','dont','ahora no','mejor no','no hace falta','no quiero']) then 'no'
    else 'ambiguo' end
  from t
$f$;

-- ¿Que envio de reenganche toca ahora a este chat? '48h' | '7d' | null. UNICA definicion de «elegible»: la usan la lista y la reserva.
create or replace function public._bot_cs_debido(c public.bot_chat)
returns text language plpgsql stable set search_path = '' as $f$
declare
  v_ult record;
  v_t0 timestamptz;
begin
  if c.consent_estado <> 'si' or c.consent_respondido_en is null then return null; end if;
  if c.consent_respondido_en < now() - interval '30 days' then return null; end if;                       -- caduca a los 30 dias
  if c.baja_en is not null or c.consent_revocado_en is not null then return null; end if;
  if c.pausado and (c.pausa_hasta is null or c.pausa_hasta > now()) then return null; end if;              -- pausa (operadora o traspaso)
  if c.consent_envio2_en is not null then return null; end if;                                             -- maximo 2

  select m.creado_en, m.rol, m.por into v_ult
    from public.bot_mensaje m
   where m.tel = c.tel and m.contenido not like '[plantilla lawang_reenganche\_%' escape '\'
   order by m.id desc limit 1;
  if v_ult.creado_en is null or v_ult.rol <> 'assistant' or v_ult.por is distinct from 'bot' then return null; end if;   -- el ultimo fue el lead o una persona
  if exists (select 1 from public.bot_mensaje m where m.tel = c.tel and m.por = 'humano' and m.creado_en > c.consent_respondido_en) then
    return null;                                                                                           -- la operadora intervino despues del si
  end if;
  if c.lead_id is not null and exists (
       select 1 from public.lead_accion a
        where a.lead_id = c.lead_id and a.tipo in ('llamada', 'visita') and a.completada_en is null and a.estado in ('propuesta', 'confirmada')) then
    return null;                                                                                           -- cita agendada
  end if;
  v_t0 := coalesce(c.consent_ancla_en, v_ult.creado_en);
  if exists (select 1 from public.bot_mensaje m where m.tel = c.tel and m.rol = 'user' and m.creado_en > v_t0) then return null; end if;   -- respondio

  if c.consent_envio1_en is null then
    if now() >= v_t0 + interval '48 hours' and now() < v_t0 + interval '96 hours' then return '48h'; end if;
  else
    if now() >= v_t0 + interval '7 days' and now() < v_t0 + interval '10 days' then return '7d'; end if;
  end if;
  return null;
end $f$;

-- ── 3. preguntar (reservar) y anclar el wamid ────────────────────────────────
create or replace function public.bot_consentimiento_preguntar(p_tel text, p_version text, p_idioma text, p_texto text, p_repregunta boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_c    public.bot_chat%rowtype;
  v_txt  text := public._bot_limpia(p_texto, 1500);
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  if p_version is distinct from 'CONSENT-SEGUIMIENTO-2026-10-09-v1' then return jsonb_build_object('error', 'version_desconocida'); end if;
  if p_idioma is null or p_idioma not in ('en', 'es') or v_txt = '' then return jsonb_build_object('error', 'no_procede'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  select * into v_c from public.bot_chat where tel = v_tel for update;
  if not found then return jsonb_build_object('error', 'sin_chat'); end if;
  if v_c.baja_en is not null or (v_c.pausado and (v_c.pausa_hasta is null or v_c.pausa_hasta > now())) then return jsonb_build_object('error', 'no_procede'); end if;

  if coalesce(p_repregunta, false) then
    -- la repregunta (Legal §2.5) es parte de la misma pregunta: solo una, y solo si hay una pregunta enviada sin contestar
    if v_c.consent_estado <> 'preguntado' or v_c.consent_pregunta_wamid is null or v_c.consent_repregunta_texto is not null then
      return jsonb_build_object('error', 'no_procede');
    end if;
    update public.bot_chat set consent_repregunta_texto = left(v_txt, 600), consent_repreguntado_en = now(), actualizado_en = now() where tel = v_tel;
    return jsonb_build_object('ok', true);
  end if;

  if v_c.consent_estado <> 'sin_preguntar' then return jsonb_build_object('error', 'no_procede'); end if;                   -- una sola vez por lead
  -- no en el primer mensaje del bot: el lead ha escrito >=2 veces y el bot ha contestado >=1 (Legal §4.1.1)
  if (select count(*) from (select 1 from public.bot_mensaje m where m.tel = v_tel and m.rol = 'user' limit 2) x) < 2
     or not exists (select 1 from public.bot_mensaje m where m.tel = v_tel and m.rol = 'assistant') then
    return jsonb_build_object('error', 'no_procede');
  end if;
  if v_c.lead_id is not null and exists (
       select 1 from public.lead_accion a
        where a.lead_id = v_c.lead_id and a.tipo in ('llamada', 'visita') and a.completada_en is null and a.estado in ('propuesta', 'confirmada')) then
    return jsonb_build_object('error', 'no_procede');                                                                       -- cita en curso (Legal §4.2)
  end if;
  update public.bot_chat
     set consent_estado = 'preguntado', consent_version = p_version, consent_idioma = p_idioma, consent_texto = v_txt,
         consent_preguntado_en = now(), consent_pregunta_wamid = null, actualizado_en = now()
   where tel = v_tel;
  return jsonb_build_object('ok', true);
end $f$;

create or replace function public.bot_consentimiento_enviada(p_tel text, p_wamid text, p_repregunta boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_w    text := nullif(left(btrim(coalesce(p_wamid, '')), 120), '');
  v_c    public.bot_chat%rowtype;
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  if v_w is null then return jsonb_build_object('error', 'wamid_invalido'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  select * into v_c from public.bot_chat where tel = v_tel for update;
  if not found then return jsonb_build_object('error', 'sin_chat'); end if;
  if v_c.consent_estado <> 'preguntado' then return jsonb_build_object('error', 'no_procede'); end if;
  if coalesce(p_repregunta, false) then
    if v_c.consent_repregunta_texto is null or v_c.consent_repregunta_wamid is not null then return jsonb_build_object('error', 'no_procede'); end if;
    update public.bot_chat set consent_repregunta_wamid = v_w, actualizado_en = now() where tel = v_tel;
  else
    if v_c.consent_pregunta_wamid is not null then return jsonb_build_object('error', 'no_procede'); end if;
    update public.bot_chat set consent_pregunta_wamid = v_w, actualizado_en = now() where tel = v_tel;
  end if;
  return jsonb_build_object('ok', true);
end $f$;

-- ── 4. responder: la unica via a `si`/`no` ───────────────────────────────────
-- resultado: 'si' | 'no' | 'repreguntar' | 'no_cuenta' (no es respuesta a la pregunta) | 'sin_efecto' (no hay pregunta pendiente)
create or replace function public.bot_consentimiento_responder(p_tel text, p_wamid text, p_texto text, p_cita text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_w    text := nullif(left(btrim(coalesce(p_wamid, '')), 120), '');
  v_cita text := nullif(left(btrim(coalesce(p_cita, '')), 120), '');
  v_c    public.bot_chat%rowtype;
  v_q    text; v_qid bigint; v_mid bigint;
  v_regla text; v_clase text; v_aplica boolean;
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  if v_w is null then return jsonb_build_object('error', 'wamid_invalido'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  select * into v_c from public.bot_chat where tel = v_tel for update;
  if not found then return jsonb_build_object('error', 'sin_chat'); end if;

  -- reintento del mismo mensaje: devuelve lo ya decidido
  if v_c.consent_respuesta_wamid = v_w and v_c.consent_estado in ('si', 'no') then
    return jsonb_build_object('resultado', v_c.consent_estado, 'estado', v_c.consent_estado);
  end if;
  if v_c.consent_estado <> 'preguntado' or v_c.baja_en is not null then
    return jsonb_build_object('resultado', 'sin_efecto', 'estado', v_c.consent_estado);
  end if;

  -- ¿contesta a ESTA pregunta? (Legal §2.1): cita el mensaje de la pregunta, o es el primer mensaje del lead tras ella sin nada del bot ni de la operadora en medio.
  v_q := coalesce(v_c.consent_repregunta_wamid, v_c.consent_pregunta_wamid);
  v_aplica := false;
  if v_cita is not null and v_cita in (coalesce(v_c.consent_pregunta_wamid, ''), coalesce(v_c.consent_repregunta_wamid, '')) then
    v_aplica := true; v_regla := 'cita';
  elsif v_q is not null then
    select m.id into v_qid from public.bot_mensaje m where m.tel = v_tel and m.wamid = v_q and m.rol = 'assistant' order by m.id desc limit 1;
    select m.id into v_mid from public.bot_mensaje m where m.tel = v_tel and m.wamid = v_w and m.rol = 'user' order by m.id desc limit 1;
    if v_qid is not null and v_mid is not null and v_mid > v_qid
       and not exists (select 1 from public.bot_mensaje m where m.tel = v_tel and m.id > v_qid and m.id < v_mid) then
      v_aplica := true; v_regla := 'turno_siguiente';
    end if;
  end if;

  if not v_aplica then
    -- Con la repregunta ya hecha, no contestarla a tiempo cierra el asunto en `no` (§2.5.3). Sin repregunta, la pregunta caduca pero el estado se queda
    -- `preguntado` (§4.3: no se vuelve a preguntar); un «si» posterior que CITE la pregunta sigue valiendo.
    if v_c.consent_repregunta_texto is not null then
      update public.bot_chat set consent_estado = 'no', consent_regla = 'repregunta_sin_respuesta', consent_respondido_en = now(), actualizado_en = now() where tel = v_tel;
      return jsonb_build_object('resultado', 'no_cuenta', 'estado', 'no');
    end if;
    return jsonb_build_object('resultado', 'no_cuenta', 'estado', 'preguntado');
  end if;

  v_clase := public._bot_cs_clase(p_texto);
  if v_clase in ('si', 'no') then
    update public.bot_chat
       set consent_estado = v_clase, consent_respuesta_texto = public._bot_limpia(p_texto, 500), consent_respuesta_wamid = v_w, consent_respuesta_cita = v_cita,
           consent_respondido_en = now(), consent_regla = left(v_regla || ':' || public._bot_cs_norm(p_texto), 120), actualizado_en = now()
     where tel = v_tel;
    return jsonb_build_object('resultado', v_clase, 'estado', v_clase);
  end if;

  -- ambiguo (§2.5): una repregunta; si ya se hizo (o se reservo), `no`
  if v_c.consent_repregunta_texto is null then
    return jsonb_build_object('resultado', 'repreguntar', 'estado', 'preguntado');
  end if;
  update public.bot_chat
     set consent_estado = 'no', consent_respuesta_texto = public._bot_limpia(p_texto, 500), consent_respuesta_wamid = v_w, consent_respuesta_cita = v_cita,
         consent_respondido_en = now(), consent_regla = 'ambiguo_tras_repregunta', actualizado_en = now()
   where tel = v_tel;
  return jsonb_build_object('resultado', 'no', 'estado', 'no');
end $f$;

-- ── 5. el reloj del reenganche ───────────────────────────────────────────────
-- EXCEPCION 3: devuelve telefonos de OTROS leads, <=20, solo los que tienen un envio debido. Sin parametros.
create or replace function public.bot_seguimiento_candidatos()
returns table (tel text, plantilla text, idioma text, nombre text)
language plpgsql volatile security definer set search_path = '' as $f$
begin
  -- limpieza de estado (perezosa: el envio ya se niega por SQL aunque esto no corra)
  update public.bot_chat set consent_estado = 'caducado', actualizado_en = now()
   where consent_estado = 'si' and consent_respondido_en < now() - interval '30 days';
  update public.bot_chat c set consent_estado = 'usado', actualizado_en = now()
   where c.consent_estado = 'si'
     and (c.consent_envio2_en is not null
          or (c.consent_envio1_en is not null and exists (select 1 from public.bot_mensaje m where m.tel = c.tel and m.rol = 'user' and m.creado_en > c.consent_envio1_en)));

  return query
    select c.tel, public._bot_cs_debido(c), c.consent_idioma,
           left(coalesce(nullif(btrim(l.name), ''), nullif(btrim(c.nombre_perfil), '')), 80)
      from public.bot_chat c
      left join public.leads l on l.id = c.lead_id
     where c.consent_estado = 'si' and c.baja_en is null and public._bot_cs_debido(c) is not null
     order by c.consent_respondido_en
     limit 20;
end $f$;

create or replace function public.bot_seguimiento_reservar(p_tel text, p_plantilla text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_c    public.bot_chat%rowtype;
  v_due  text;
  v_ult  timestamptz;
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  if p_plantilla is null or p_plantilla not in ('48h', '7d') then return jsonb_build_object('error', 'plantilla_invalida'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  select * into v_c from public.bot_chat where tel = v_tel for update;
  if not found then return jsonb_build_object('error', 'sin_chat'); end if;
  v_due := public._bot_cs_debido(v_c);
  if v_due is distinct from p_plantilla then return jsonb_build_object('error', 'no_procede'); end if;     -- un STOP entre la lista y el envio gana aqui
  if p_plantilla = '48h' then
    select m.creado_en into v_ult from public.bot_mensaje m
     where m.tel = v_tel and m.contenido not like '[plantilla lawang_reenganche\_%' escape '\' order by m.id desc limit 1;
    update public.bot_chat set consent_ancla_en = v_ult, consent_envio1_en = now(), consent_envio1_res = 'reservado', actualizado_en = now() where tel = v_tel;
  else
    update public.bot_chat set consent_envio2_en = now(), consent_envio2_res = 'reservado', actualizado_en = now() where tel = v_tel;
  end if;
  return jsonb_build_object('ok', true, 'idioma', coalesce(v_c.consent_idioma, 'en'),
    'nombre', left(coalesce(nullif((select btrim(l.name) from public.leads l where l.id = v_c.lead_id), ''), nullif(btrim(v_c.nombre_perfil), '')), 80));
end $f$;

create or replace function public.bot_seguimiento_registrar(p_tel text, p_plantilla text, p_wamid text, p_resultado text, p_texto text default null)
returns text language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_w    text := nullif(left(btrim(coalesce(p_wamid, '')), 120), '');
  v_c    public.bot_chat%rowtype;
begin
  if v_e164 is null then return 'telefono_invalido'; end if;
  if p_plantilla is null or p_plantilla not in ('48h', '7d') then return 'plantilla_invalida'; end if;
  if p_resultado is null or p_resultado not in ('enviado', 'fallo') then return 'resultado_invalido'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  select * into v_c from public.bot_chat where tel = v_tel for update;
  if not found then return 'no_aplica'; end if;
  if p_plantilla = '48h' then
    if v_c.consent_envio1_res is distinct from 'reservado' then return 'no_aplica'; end if;
    update public.bot_chat set consent_envio1_res = p_resultado, consent_envio1_wamid = case when p_resultado = 'enviado' then v_w end, actualizado_en = now() where tel = v_tel;
  else
    if v_c.consent_envio2_res is distinct from 'reservado' then return 'no_aplica'; end if;
    update public.bot_chat set consent_envio2_res = p_resultado, consent_envio2_wamid = case when p_resultado = 'enviado' then v_w end,
           consent_estado = 'usado', actualizado_en = now() where tel = v_tel;                    -- el 7d agota el consentimiento
  end if;
  if p_resultado = 'enviado' then
    -- queda en el hilo para que el equipo lo vea; NO toca ultimo_mensaje/actividad (no alarga la retencion) y la marca de texto lo excluye del ancla
    insert into public.bot_mensaje (tel, rol, por, contenido, wamid)
    values (v_tel, 'assistant', 'bot', public._bot_limpia('[plantilla lawang_reenganche_' || p_plantilla || '] ' || coalesce(p_texto, ''), 4096), v_w)
    on conflict (tel, wamid) where wamid is not null do nothing;
  end if;
  return 'ok';
end $f$;

-- ── 6. bot_baja: la baja revoca el consentimiento en la misma llamada ────────
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
           consent_estado = 'revocado', consent_revocado_en = coalesce(consent_revocado_en, now()), consent_revocado_wamid = coalesce(consent_revocado_wamid, v_w),
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

-- ── 7. bot_turno_estado: anade `consentimiento` ──────────────────────────────
create or replace function public.bot_turno_estado(p_tel text, p_testing boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_c    public.bot_chat%rowtype;
  v_avisar_testing boolean := false;
  v_hist jsonb;
  v_cfg  jsonb;
  v_puede boolean := false;
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

  -- ¿puede el bot hacer ahora la pregunta de seguimiento? (condiciones de datos; el resto —cierre de conversacion, cifra, traspaso— las decide el bot)
  if v_c.consent_estado = 'sin_preguntar' and v_c.baja_en is null
     and (select count(*) from (select 1 from public.bot_mensaje m where m.tel = v_tel and m.rol = 'user' limit 2) x) >= 2
     and exists (select 1 from public.bot_mensaje m where m.tel = v_tel and m.rol = 'assistant')
     and not (v_c.lead_id is not null and exists (
           select 1 from public.lead_accion a
            where a.lead_id = v_c.lead_id and a.tipo in ('llamada', 'visita') and a.completada_en is null and a.estado in ('propuesta', 'confirmada'))) then
    v_puede := true;
  end if;

  return jsonb_build_object(
    'baja', v_c.baja_en is not null,
    'pausado', v_c.pausado and (v_c.pausa_hasta is null or v_c.pausa_hasta > now()),
    'esperando', v_c.esperando,
    'avisar_testing', v_avisar_testing,
    'primer_turno', not exists (select 1 from public.bot_mensaje m where m.tel = v_tel and m.rol = 'assistant'),
    'historial', v_hist,
    'config', v_cfg,
    'consentimiento', jsonb_build_object('estado', v_c.consent_estado, 'repreguntado', v_c.consent_repregunta_texto is not null, 'puede_preguntar', v_puede));
end $f$;

-- ── 8. olvido: vacia los textos y conserva la marca ──────────────────────────
create or replace function public._bot_olvidar_tel(p_tel text, p_no_contactar boolean)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_c public.bot_chat%rowtype;
  v_leads uuid[];
  v_msg int := 0; v_esc int := 0; v_wam int := 0; v_notas int := 0; v_fichas int := 0; v_contr int := 0;
  v_chat text := 'sin_fila';
begin
  select * into v_c from public.bot_chat where tel = p_tel for update;
  select coalesce(array_agg(distinct x), '{}') into v_leads from (
    select v_c.lead_id as x where v_c.lead_id is not null
    union
    select l.id from public.leads l where public._bot_tel(l.whatsapp) = p_tel
  ) s;

  with d as (delete from public.bot_mensaje where tel = p_tel returning 1) select count(*) into v_msg from d;
  with d as (delete from public.bot_escalacion where tel = p_tel returning 1) select count(*) into v_esc from d;
  with d as (delete from public.bot_wamid where tel = p_tel returning 1) select count(*) into v_wam from d;

  if v_c.tel is not null then
    if p_no_contactar or v_c.baja_en is not null or v_c.consent_estado = 'revocado' then
      -- se queda SOLO la marca: baja + pausa fija (el bot no vuelve a escribir) y el acuse ya dado (no manda otro).
      -- S12: el consentimiento pasa a `revocado` (el borrado lo anula, Legal §2.6) y se vacian los TEXTOS; se conservan estado, fechas, version y wamids.
      update public.bot_chat
         set nombre_perfil = null, intent = null, ultimo_mensaje = null, ultimo_por = null, lead_id = null, esperando = false,
             resumen_hasta_id = null, ultimo_entrante_en = null, entrega_error = null, entrega_error_en = null,
             seguimientos = 0, aviso_nivel = 0, aviso_testing_en = null,
             consent_estado = 'revocado', consent_revocado_en = coalesce(consent_revocado_en, now()),
             consent_texto = null, consent_repregunta_texto = null, consent_respuesta_texto = null,
             baja_en = coalesce(baja_en, now()), baja_acuse_en = coalesce(baja_acuse_en, now()),
             pausado = true, pausa_hasta = null, pausa_por = coalesce(pausa_por, 'olvido'), actualizado_en = now()
       where tel = p_tel;
      v_chat := 'reducida_a_la_marca';
    else
      delete from public.bot_chat where tel = p_tel;
      v_chat := 'borrada';
    end if;
  elsif p_no_contactar then
    insert into public.bot_chat (tel, baja_en, baja_acuse_en, pausado, pausa_por, consent_estado, consent_revocado_en)
    values (p_tel, now(), now(), true, 'olvido', 'revocado', now());
    v_chat := 'marca_creada';
  end if;

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

-- ── 9. purga: la marca `revocado` no se purga; los textos de consentimiento se vacian al reducir ─
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

-- ── 10. concesiones: solo bot_lawang, solo su lista ──────────────────────────
revoke all on function public._bot_cs_norm(text)      from public, anon, authenticated, service_role;
revoke all on function public._bot_cs_sin_cola(text)  from public, anon, authenticated, service_role;
revoke all on function public._bot_cs_clase(text)     from public, anon, authenticated, service_role;
revoke all on function public._bot_cs_debido(public.bot_chat) from public, anon, authenticated, service_role;
revoke all on function public.bot_consentimiento_preguntar(text, text, text, text, boolean) from public, anon, authenticated, service_role;
revoke all on function public.bot_consentimiento_enviada(text, text, boolean)               from public, anon, authenticated, service_role;
revoke all on function public.bot_consentimiento_responder(text, text, text, text)          from public, anon, authenticated, service_role;
revoke all on function public.bot_seguimiento_candidatos()                                  from public, anon, authenticated, service_role;
revoke all on function public.bot_seguimiento_reservar(text, text)                          from public, anon, authenticated, service_role;
revoke all on function public.bot_seguimiento_registrar(text, text, text, text, text)       from public, anon, authenticated, service_role;
revoke all on function public.bot_baja(text, text)                from public, anon, authenticated, service_role;
revoke all on function public.bot_turno_estado(text, boolean)     from public, anon, authenticated, service_role;
revoke all on function public._bot_olvidar_tel(text, boolean)     from public, anon, authenticated, service_role;
revoke all on function public.bot_purga()                         from public, anon, authenticated, service_role;
grant execute on function public.bot_consentimiento_preguntar(text, text, text, text, boolean) to bot_lawang;
grant execute on function public.bot_consentimiento_enviada(text, text, boolean)               to bot_lawang;
grant execute on function public.bot_consentimiento_responder(text, text, text, text)          to bot_lawang;
grant execute on function public.bot_seguimiento_candidatos()                                  to bot_lawang;
grant execute on function public.bot_seguimiento_reservar(text, text)                          to bot_lawang;
grant execute on function public.bot_seguimiento_registrar(text, text, text, text, text)       to bot_lawang;
grant execute on function public.bot_baja(text, text)             to bot_lawang;
grant execute on function public.bot_turno_estado(text, boolean)  to bot_lawang;
