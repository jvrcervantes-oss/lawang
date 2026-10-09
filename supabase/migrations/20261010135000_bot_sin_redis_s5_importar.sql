-- destructivo-ok: solo construye (3 funciones nuevas bot_importar_* + 1 ayudante) y un create or replace de _bot_config_log (misma firma; solo gana una salida temprana durante la importacion). No borra ni vacia nada; los unicos insert/update son los de las funciones nuevas, que solo AÑADEN restricciones. Reversion: supabase/reversion_bot_sin_redis_s5/REVERSION.sql.
-- ============================================================================
-- LAWANG — BOT SIN REDIS — S5: IMPORTAR EL ESTADO DE REDIS A POSTGRES (9-oct-2026)
-- ----------------------------------------------------------------------------
-- Encargo: encargos/20261009_lawang_bot_sin_redis.md, subtarea S5 (LAW-507). TEMPORAL: estas funciones existen para UNA importacion y se
-- RETIRAN en S9 (drop function) junto con Redis y el endpoint /admin/api/redis-inventario del bot.
--
-- LLAMADOR CON NOMBRE (seguridad_2026 §1.ter): el servicio lawang-bot, via la ruta /importar de la edge bot-api (la añade S2; secreto propio).
-- EXECUTE solo bot_lawang. Nada llama a esto hasta que S2 publique la ruta y el owner lance la fase B.
--   bot_importar_chat(jsonb)      <- UN telefono por llamada (chat + mensajes + escalaciones abiertas)
--   bot_importar_config(jsonb)    <- UNA vez (botcfg:v1 + botcfg:log); solo actua con version=1 y el log vacio
--   bot_importar_cuadre(text)     <- lectura de UN telefono (conteos y md5), para el informe de cuadre
--   _bot_importar_ms(bigint)      <- ayudante interno
--
-- REGLAS (el importador SOLO AÑADE RESTRICCIONES y es REPETIBLE):
--   1. Una baja nunca se quita; la fecha mas antigua gana. Una baja implica pausado=true, pausa_hasta=null, pausa_por='baja' (como bot_baja).
--   2. Una pausa nunca se acorta ni se levanta: sin caducidad gana a con caducidad; entre dos caducidades, la mas lejana.
--      El PTTL restante lo convierte el bot en un instante absoluto al LEER; una pausa ya caducada al llegar aqui no se aplica.
--   3. Campos descriptivos: gana lo que ya hubiera (un telefono con mensajes vivos de la sombra no se pisa); creado_en el mas viejo;
--      actividad_en/ultimo_entrante_en/seguimientos/aviso_nivel el mayor. actividad_en sale de los DATOS (nunca now()): si no, se
--      reiniciaria el reloj de la purga de S7.
--   4. Mensajes: se desduplican por (tel, ts_origen, rol, md5(contenido)) — la mayoria no tiene wamid. Se insertan en orden de ts. Si el
--      telefono YA tiene mensajes mas nuevos que el lote que no vienen en el, NO se insertan (los ids vivos quedarian antes que los viejos y
--      el historial de 20 saldria desordenado): se devuelve omitidos_posteriores y el resto del estado SI se importa.
--   5. lead_id: se busca como bot_lead_upsert (uno -> se fija; cero -> nada; varios -> nulo) pero SIN llamarla (esa crea leads y escribe log).
--   6. Escalaciones: solo abiertas; unico por aviso_wamid; sin wamid se desduplican por (tel, pregunta) abierta.
--   7. Config: no la escribe nadie mas que S3 salvo esta unica vez. bot_lawang NO tiene privilegios sobre bot_config; esta funcion DEFINER solo
--      actua si version=1 y bot_config_log esta vacio (nadie ha editado nada). El log de Redis va en camelCase: se traduce a snake_case
--      (crm_bot_config_volver lee prev->>'pausa_horas'). Mientras importa, _bot_config_log se calla (bot.importando=on, solo dentro de la
--      transaccion) para no sumar una fila de log que no existio.
-- ============================================================================

create or replace function public._bot_importar_ms(p bigint)
returns timestamptz language sql stable security definer set search_path = '' as $f$
  select case when p is null or p < 100000000000 or p > 4102444800000 then null
              else least(timestamptz 'epoch' + p * interval '1 millisecond', now() + interval '1 day') end
$f$;

-- _bot_config_log: igual que en S1 salvo la salida temprana durante la importacion
create or replace function public._bot_config_log()
returns trigger language plpgsql security definer set search_path = '' as $f$
begin
  if coalesce(current_setting('bot.importando', true), '') = 'on' then return null; end if;
  insert into public.bot_config_log (usuario, version, prev, next)
  values (left(coalesce(nullif(new.actualizado_por, ''), 'desconocido'), 120), new.version, to_jsonb(old), to_jsonb(new));
  return null;
end $f$;

-- ── un telefono ──────────────────────────────────────────────────────────────
create or replace function public.bot_importar_chat(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164   text := public._bot_e164(p->>'tel');
  v_tel    text := ltrim(public._bot_e164(p->>'tel'), '+');
  c        jsonb := p->'chat';
  v_existia boolean;
  v_lote   jsonb;
  v_n_lote int;
  v_min_ts timestamptz;
  v_max_ts timestamptz;
  v_creado timestamptz;
  v_actual timestamptz;
  v_entr   timestamptz;
  v_baja   timestamptz;
  v_pausado boolean;
  v_hasta  timestamptz;
  v_indef  boolean;
  v_leads  uuid[];
  v_lead   text;
  v_ins    int := 0;
  v_posteriores boolean := false;
  v_esc_in int := 0;
  v_esc_ins int := 0;
begin
  if v_e164 is null then return jsonb_build_object('ok', false, 'error', 'telefono_invalido'); end if;
  if c is null or jsonb_typeof(c) <> 'object'
     or jsonb_typeof(coalesce(p->'mensajes', '[]'::jsonb)) <> 'array' or jsonb_typeof(coalesce(p->'escalaciones', '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p->'mensajes', '[]'::jsonb)) > 100 or jsonb_array_length(coalesce(p->'escalaciones', '[]'::jsonb)) > 20 then
    return jsonb_build_object('ok', false, 'error', 'forma');
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));

  -- mensajes normalizados (mismo saneo que bot_mensaje_recibir), en orden de ts
  v_creado := coalesce(public._bot_importar_ms(case when (c->>'creado_ms') ~ '^[0-9]{1,15}$' then (c->>'creado_ms')::bigint end), now());
  select coalesce(jsonb_agg(jsonb_build_object('rol', q.rol, 'por', q.por, 'pu', q.pu, 'contenido', q.contenido, 'media', q.media,
                                               'wamid', q.wamid, 'ts', q.ts) order by q.ts, q.ord), '[]'::jsonb)
    into v_lote
    from (
      select e.ord,
             case when e.v->>'rol' = 'user' then 'user' else 'assistant' end as rol,
             case when e.v->>'rol' = 'user' then 'cliente' when e.v->>'por' = 'humano' then 'humano' else 'bot' end as por,
             nullif(public._bot_limpia(e.v->>'por_usuario', 120), '') as pu,
             public._bot_limpia(e.v->>'contenido', 4096) as contenido,
             public._bot_media(e.v->'media') as media,
             nullif(left(btrim(coalesce(e.v->>'wamid', '')), 120), '') as wamid,
             coalesce(public._bot_importar_ms(case when (e.v->>'ts_ms') ~ '^[0-9]{1,15}$' then (e.v->>'ts_ms')::bigint end), v_creado) as ts
        from jsonb_array_elements(coalesce(p->'mensajes', '[]'::jsonb)) with ordinality as e(v, ord)
       where jsonb_typeof(e.v) = 'object'
    ) q;
  v_n_lote := jsonb_array_length(v_lote);
  select min(l.ts), max(l.ts) into v_min_ts, v_max_ts
    from jsonb_to_recordset(v_lote) as l(rol text, por text, pu text, contenido text, media jsonb, wamid text, ts timestamptz);

  v_entr := public._bot_importar_ms(case when (c->>'ultimo_entrante_ms') ~ '^[0-9]{1,15}$' then (c->>'ultimo_entrante_ms')::bigint end);
  v_actual := coalesce(public._bot_importar_ms(case when (c->>'actualizado_ms') ~ '^[0-9]{1,15}$' then (c->>'actualizado_ms')::bigint end), v_creado);
  v_actual := least(now(), greatest(v_actual, coalesce(v_max_ts, v_actual), coalesce(v_entr, v_actual)));   -- actividad real, nunca now()

  -- baja: una baja sin fecha valida SIGUE siendo una baja
  if c->>'baja_ms' is not null and c->>'baja_ms' <> 'null' then
    v_baja := coalesce(public._bot_importar_ms(case when (c->>'baja_ms') ~ '^[0-9]{1,15}$' then (c->>'baja_ms')::bigint end), now());
  end if;
  -- pausa: sin pausa_hasta = no caduca; una ya caducada no se aplica
  v_hasta := public._bot_importar_ms(case when (c->>'pausa_hasta_ms') ~ '^[0-9]{1,15}$' then (c->>'pausa_hasta_ms')::bigint end);
  v_indef := coalesce((c->>'pausado')::boolean, false) and (c->>'pausa_hasta_ms') is null;
  v_pausado := v_baja is not null or v_indef or (coalesce((c->>'pausado')::boolean, false) and v_hasta is not null and v_hasta > now());
  if v_baja is not null then v_hasta := null; end if;
  if not v_pausado then v_hasta := null; end if;
  if v_pausado and not v_indef and v_baja is null and v_hasta is null then v_pausado := false; end if;

  select exists (select 1 from public.bot_chat where tel = v_tel) into v_existia;

  insert into public.bot_chat as b (tel, nombre_perfil, intent, ultimo_mensaje, ultimo_por, creado_en, actualizado_en, actividad_en, archivado,
                                    pausado, pausa_hasta, pausa_por, esperando, ultimo_entrante_en, baja_en, baja_acuse_en,
                                    seguimientos, aviso_nivel, aviso_testing_en)
  values (v_tel,
          nullif(public._bot_limpia(c->>'nombre_perfil', 80), ''),
          nullif(public._bot_limpia(c->>'intent', 40), ''),
          nullif(public._bot_limpia(c->>'ultimo_mensaje', 200), ''),
          case when c->>'ultimo_por' in ('cliente', 'bot', 'humano') then c->>'ultimo_por' end,
          least(v_creado, v_actual), v_actual, v_actual,
          coalesce((c->>'archivado')::boolean, false),
          v_pausado, v_hasta,
          case when v_baja is not null then 'baja' when v_pausado then 'importado de Redis' end,
          coalesce((c->>'esperando')::boolean, false),
          v_entr, v_baja,
          case when v_baja is not null and coalesce((c->>'baja_acuse')::boolean, false) then v_baja end,
          least(greatest(coalesce((c->>'seguimientos')::int, 0), 0), 1000),
          least(greatest(coalesce((c->>'aviso_nivel')::int, 0), 0), 2),
          case when coalesce((c->>'aviso_testing')::boolean, false) then now() end)
  on conflict (tel) do update set
    nombre_perfil      = coalesce(b.nombre_perfil, excluded.nombre_perfil),
    intent             = coalesce(b.intent, excluded.intent),
    ultimo_mensaje     = case when excluded.actividad_en > b.actividad_en then coalesce(excluded.ultimo_mensaje, b.ultimo_mensaje) else b.ultimo_mensaje end,
    ultimo_por         = case when excluded.actividad_en > b.actividad_en then coalesce(excluded.ultimo_por, b.ultimo_por) else b.ultimo_por end,
    creado_en          = least(b.creado_en, excluded.creado_en),
    actualizado_en     = greatest(b.actualizado_en, excluded.actualizado_en),
    actividad_en       = greatest(b.actividad_en, excluded.actividad_en),
    ultimo_entrante_en = greatest(b.ultimo_entrante_en, excluded.ultimo_entrante_en),
    baja_en            = least(b.baja_en, excluded.baja_en),
    baja_acuse_en      = coalesce(b.baja_acuse_en, excluded.baja_acuse_en),
    pausado            = b.pausado or excluded.pausado or b.baja_en is not null or excluded.baja_en is not null,
    pausa_hasta        = case when b.baja_en is not null or excluded.baja_en is not null then null
                              when (b.pausado and b.pausa_hasta is null) or (excluded.pausado and excluded.pausa_hasta is null) then null
                              else greatest(b.pausa_hasta, excluded.pausa_hasta) end,
    pausa_por          = case when b.baja_en is not null or excluded.baja_en is not null then 'baja' else coalesce(b.pausa_por, excluded.pausa_por) end,
    seguimientos       = greatest(b.seguimientos, excluded.seguimientos),
    aviso_nivel        = greatest(b.aviso_nivel, excluded.aviso_nivel),
    aviso_testing_en   = coalesce(b.aviso_testing_en, excluded.aviso_testing_en);
  -- archivado y esperando: si el telefono ya existia, manda lo que habia (son banderas del momento; no se resucitan)

  -- mensajes
  if v_n_lote > 0 then
    if exists (
      select 1 from public.bot_mensaje b
       where b.tel = v_tel and coalesce(b.ts_origen, b.creado_en) > v_min_ts
         and not exists (select 1 from jsonb_to_recordset(v_lote) as l(rol text, por text, pu text, contenido text, media jsonb, wamid text, ts timestamptz)
                          where l.ts = b.ts_origen and l.rol = b.rol and md5(l.contenido) = md5(b.contenido))
    ) then
      v_posteriores := true;
    else
      insert into public.bot_mensaje (tel, rol, por, por_usuario, contenido, media, wamid, creado_en, ts_origen)
      select v_tel, e.v->>'rol', e.v->>'por', e.v->>'pu', e.v->>'contenido', nullif(e.v->'media', 'null'::jsonb), e.v->>'wamid',
             (e.v->>'ts')::timestamptz, (e.v->>'ts')::timestamptz
        from jsonb_array_elements(v_lote) with ordinality as e(v, ord)
       where not exists (select 1 from public.bot_mensaje b where b.tel = v_tel and b.ts_origen = (e.v->>'ts')::timestamptz
                            and b.rol = e.v->>'rol' and md5(b.contenido) = md5(e.v->>'contenido'))
       order by e.ord
      on conflict (tel, wamid) where wamid is not null do nothing;
      get diagnostics v_ins = row_count;
    end if;
  end if;

  -- escalaciones abiertas
  select count(*) into v_esc_in from jsonb_array_elements(coalesce(p->'escalaciones', '[]'::jsonb)) e where jsonb_typeof(e) = 'object';
  insert into public.bot_escalacion (tel, nombre, pregunta, aviso_wamid, creada_en)
  select v_tel, nullif(public._bot_limpia(e.v->>'nombre', 80), ''), public._bot_limpia(e.v->>'pregunta', 500),
         nullif(left(btrim(coalesce(e.v->>'aviso_wamid', '')), 120), ''),
         coalesce(public._bot_importar_ms(case when (e.v->>'creada_ms') ~ '^[0-9]{1,15}$' then (e.v->>'creada_ms')::bigint end), now())
    from jsonb_array_elements(coalesce(p->'escalaciones', '[]'::jsonb)) with ordinality as e(v, ord)
   where jsonb_typeof(e.v) = 'object' and public._bot_limpia(e.v->>'pregunta', 500) <> ''
     and not exists (select 1 from public.bot_escalacion x where x.tel = v_tel and x.resuelta_en is null
                        and x.pregunta = public._bot_limpia(e.v->>'pregunta', 500))
   order by e.ord
  on conflict (aviso_wamid) where aviso_wamid is not null do nothing;
  get diagnostics v_esc_ins = row_count;

  -- lead_id (referencia): uno -> se fija; varios -> nulo; cero -> nada
  select coalesce(array_agg(l.id order by l.created_at), '{}') into v_leads from public.leads l where public._lw_tel_e164(l.whatsapp) = v_e164;
  if cardinality(v_leads) = 1 then
    update public.bot_chat set lead_id = v_leads[1] where tel = v_tel and lead_id is distinct from v_leads[1];
    v_lead := 'enlazado';
  elsif cardinality(v_leads) > 1 then
    update public.bot_chat set lead_id = null where tel = v_tel and lead_id is not null;
    v_lead := 'ambiguo';
  else
    v_lead := 'sin_lead';
  end if;

  return jsonb_build_object('ok', true, 'chat', case when v_existia then 'actualizado' else 'creado' end, 'lead', v_lead,
    'mensajes', jsonb_build_object('recibidos', v_n_lote, 'insertados', v_ins, 'omitidos_posteriores', v_posteriores),
    'escalaciones', jsonb_build_object('recibidas', v_esc_in, 'insertadas', v_esc_ins));
end $f$;

-- ── cuadre de UN telefono: conteos y md5, nunca contenido ────────────────────
-- hash_mensajes = md5 de «rol|por|ms|contenido» unidos con chr(1)/chr(2), en orden (ts_origen, id): la MISMA cadena que import_redis.js
-- (digestMensajes) construye de su lado.
create or replace function public.bot_importar_cuadre(p_tel text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_tel text := ltrim(public._bot_e164(p_tel), '+');
  v_c   public.bot_chat%rowtype;
  v_n   int;
  v_h   text;
  v_e   int;
begin
  if v_tel is null then return jsonb_build_object('existe', false); end if;
  select * into v_c from public.bot_chat where tel = v_tel;
  if not found then return jsonb_build_object('existe', false); end if;
  select count(*), md5(coalesce(string_agg(m.rol || chr(1) || m.por || chr(1) || floor(extract(epoch from m.ts_origen) * 1000)::bigint::text || chr(1) || m.contenido,
                                           chr(2) order by m.ts_origen, m.id), ''))
    into v_n, v_h from public.bot_mensaje m where m.tel = v_tel;
  select count(*) into v_e from public.bot_escalacion e where e.tel = v_tel and e.resuelta_en is null;
  return jsonb_build_object('existe', true, 'n_mensajes', v_n, 'hash_mensajes', v_h,
    'ultimo_entrante_ms', case when v_c.ultimo_entrante_en is null then null else floor(extract(epoch from v_c.ultimo_entrante_en) * 1000)::bigint end,
    'pausado', v_c.pausado,
    'pausa_hasta_ms', case when v_c.pausa_hasta is null then null else floor(extract(epoch from v_c.pausa_hasta) * 1000)::bigint end,
    'baja', v_c.baja_en is not null, 'aviso_nivel', v_c.aviso_nivel, 'escalaciones_abiertas', v_e);
end $f$;

-- ── config (UNA vez) ─────────────────────────────────────────────────────────
-- p = {config:{extra,bienvenida,pausa_horas,updated_by}, log:[{ts_ms,by,prev:{extra,bienvenida,pausa_horas},next:{...}}]} (log: mas viejo primero, <=50)
create or replace function public.bot_importar_config(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  c   jsonb := p->'config';
  v_ver int;
  v_n bigint;
  v_extra text; v_bien text; v_ph int;
  e record;
  v_total int := 0;
begin
  if c is null or jsonb_typeof(c) <> 'object' or jsonb_typeof(coalesce(p->'log', '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p->'log', '[]'::jsonb)) > 50 then
    return jsonb_build_object('ok', false, 'error', 'forma');
  end if;
  select b.version into v_ver from public.bot_config b where b.id for update;
  select count(*) into v_n from public.bot_config_log;
  if v_ver is distinct from 1 or v_n > 0 then
    return jsonb_build_object('ok', true, 'resultado', 'ya_configurada');          -- alguien ya la edito desde la intranet: manda lo de Postgres
  end if;
  v_extra := left(public._crm_bot_config_limpia(c->>'extra'), 2000);
  v_bien  := left(public._crm_bot_config_limpia(c->>'bienvenida'), 500);
  if (c->>'pausa_horas') !~ '^[0-9]{1,3}$' or (c->>'pausa_horas')::int > 720 then return jsonb_build_object('ok', false, 'error', 'pausa_horas'); end if;
  v_ph := (c->>'pausa_horas')::int;

  perform set_config('bot.importando', 'on', true);
  -- el registro primero (mas viejo primero => ids crecientes), en snake_case y con la forma completa de la fila
  for e in select x.v, x.ord from jsonb_array_elements(coalesce(p->'log', '[]'::jsonb)) with ordinality as x(v, ord) order by x.ord loop
    continue when jsonb_typeof(e.v) <> 'object' or jsonb_typeof(e.v->'prev') <> 'object' or jsonb_typeof(e.v->'next') <> 'object';
    continue when (e.v->'prev'->>'pausa_horas') !~ '^[0-9]{1,3}$' or (e.v->'next'->>'pausa_horas') !~ '^[0-9]{1,3}$';
    continue when (e.v->'prev'->>'pausa_horas')::int > 720 or (e.v->'next'->>'pausa_horas')::int > 720;
    insert into public.bot_config_log (cuando, usuario, version, prev, next)
    values (coalesce(public._bot_importar_ms(case when (e.v->>'ts_ms') ~ '^[0-9]{1,15}$' then (e.v->>'ts_ms')::bigint end), now()),
            coalesce(nullif(left(public._bot_limpia(e.v->>'by', 120), 120), ''), 'desconocido'),
            e.ord::int,
            jsonb_build_object('id', true, 'extra', left(public._crm_bot_config_limpia(e.v->'prev'->>'extra'), 2000),
                               'bienvenida', left(public._crm_bot_config_limpia(e.v->'prev'->>'bienvenida'), 500),
                               'pausa_horas', (e.v->'prev'->>'pausa_horas')::int, 'resumen_cada_n', 30, 'fallos_alarma', 3, 'version', e.ord::int),
            jsonb_build_object('id', true, 'extra', left(public._crm_bot_config_limpia(e.v->'next'->>'extra'), 2000),
                               'bienvenida', left(public._crm_bot_config_limpia(e.v->'next'->>'bienvenida'), 500),
                               'pausa_horas', (e.v->'next'->>'pausa_horas')::int, 'resumen_cada_n', 30, 'fallos_alarma', 3, 'version', e.ord::int + 1));
    v_total := v_total + 1;
  end loop;
  update public.bot_config
     set extra = v_extra, bienvenida = v_bien, pausa_horas = v_ph,
         actualizado_por = coalesce(nullif(left(public._bot_limpia(c->>'updated_by', 120), 120), ''), 'importado de Redis')
   where id;
  perform set_config('bot.importando', 'off', true);
  return jsonb_build_object('ok', true, 'resultado', 'importada', 'log_importado', v_total);
end $f$;

-- ── cerrar: nace sin EXECUTE para nadie salvo bot_lawang ─────────────────────
revoke all on function public._bot_importar_ms(bigint)      from public, anon, authenticated, service_role;
revoke all on function public.bot_importar_chat(jsonb)      from public, anon, authenticated, service_role;
revoke all on function public.bot_importar_cuadre(text)     from public, anon, authenticated, service_role;
revoke all on function public.bot_importar_config(jsonb)    from public, anon, authenticated, service_role;
grant execute on function public.bot_importar_chat(jsonb)   to bot_lawang;
grant execute on function public.bot_importar_cuadre(text)  to bot_lawang;
grant execute on function public.bot_importar_config(jsonb) to bot_lawang;
