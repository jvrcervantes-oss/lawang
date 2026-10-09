-- destructivo-ok: solo construye (5 funciones nuevas, ninguna tabla ni columna). El unico «update» es el de la fila unica de bot_config, dentro de las funciones nuevas. Reversion: supabase/reversion_bot_sin_redis_s3/REVERSION.sql.
-- ============================================================================
-- LAWANG — BOT SIN REDIS — S3: la configuracion del bot se ESCRIBE en Postgres (9-oct-2026)
-- ----------------------------------------------------------------------------
-- Encargo: encargos/20261009_lawang_bot_sin_redis.md, subtarea S3. Sigue a S1 (20261010110000/0100), que ya creo bot_config (fila unica) y
-- bot_config_log (lo llena un trigger EN LA MISMA TRANSACCION, con el valor anterior).
--
-- EL DATO TIENE UN DUEÑO:
--   · extra / bienvenida / pausa_horas  -> dueño: el ERP (bot_config). El bot SOLO LEE (dentro de bot_turno_estado). Un bot comprometido ya no
--     puede reescribir sus propias instrucciones: bot_lawang no ejecuta nada de lo de aqui ni toca la tabla.
--   · quien y cuando lo cambio           -> bot_config.actualizado_por / actualizado_en (los pone la base) y bot_config_log.
--
-- LLAMADOR CON NOMBRE (seguridad_2026 §1.ter): la edge lawang-bot-proxy, acciones config_get / config_set / config_revert, la pestaña «Configurar bot»
-- de intranet/leads (data-accion="cfg-guardar" / "cfg-volver"). UNICO llamador: EXECUTE solo para service_role (la clave que tiene esa edge). Ni anon,
-- ni authenticated, ni bot_lawang. El prefijo es crm_ y no bot_ A PROPOSITO: el gate BOT-S1 reserva bot_* para lo que ejecuta el bot.
--   crm_bot_config_leer(uuid)                                      <- config_get
--   crm_bot_config_guardar(uuid, text, text, integer, bigint, text) <- config_set
--   crm_bot_config_volver(uuid, bigint, text)                      <- config_revert
--   _crm_bot_config_autoriza(uuid), _crm_bot_config_json(), _crm_bot_config_limpia(text) <- solo las tres de arriba. Sin EXECUTE para nadie.
--
-- DECISIONES:
--   1. EL PERMISO SE COMPRUEBA EN LA EDGE Y OTRA VEZ AQUI. La edge pasa el user_id que sale del JWT ya verificado (nunca del cuerpo); la base vuelve a
--      mirar usuarios: activo, alcance GLOBAL y sin empresas (el bot es uno y mezcla las dos empresas) y super_admin o la casilla bot_configurar.
--      Misma regla que lawang-bot-proxy y _bot_conversaciones_autoriza.
--   2. CONCURRENCIA OPTIMISTA, DENTRO DE LA TRANSACCION: el token es updatedAt en milisegundos de epoca (lo que el front ya manda como
--      expectedUpdatedAt). Se compara bajo FOR UPDATE; si no coincide, NO se escribe y se devuelve el estado actual (la edge responde 409 con el).
--   3. VOLVER A LA VERSION ANTERIOR = restaurar el «prev» de la ultima fila de bot_config_log, como una edicion mas (version nueva, nueva fila de log).
--      Sin fila en el log -> sin_anterior (404). Igual que hacia el bot con Redis.
--   4. LIMPIEZA: los delimitadores <<< y >>> se neutralizan tambien aqui (defensa contra inyeccion en el system prompt: el texto se coloca entre
--      ellos). La validacion de correos y telefonos vive en la edge (TS), portada de botcfg.validaConfig; un telefono no se detecta con una regex
--      de Postgres sin cambiar su semantica. Los limites 2000/500/0-720 los garantiza ademas la propia tabla (check).
--   5. updatedBy lo pone la edge desde la sesion (ficha.email), nunca el navegador.
-- ============================================================================

-- ── 1. permiso (interna) ─────────────────────────────────────────────────────
create or replace function public._crm_bot_config_autoriza(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $f$
begin
  if p_user is null or not exists (
    select 1 from public.usuarios u
     where u.user_id = p_user and u.activo
       and u.ambito = 'global' and coalesce(cardinality(u.empresas), 0) = 0
       and (u.rol = 'super_admin' or 'bot_configurar' = any (coalesce(u.herramientas, '{}')))
  ) then
    raise exception 'Sin permiso para configurar el bot' using errcode = '42501';
  end if;
end $f$;

-- ── 2. forma de la respuesta (interna): la MISMA que daba el bot con Redis ({config:{...,updatedAt,updatedBy}, log:[{ts,by}]}) ──
create or replace function public._crm_bot_config_json()
returns jsonb language sql stable set search_path = '' as $f$
  select jsonb_build_object(
    'config', (select jsonb_build_object('extra', c.extra, 'bienvenida', c.bienvenida, 'pausaHoras', c.pausa_horas,
                  'updatedAt', floor(extract(epoch from c.actualizado_en) * 1000)::bigint, 'updatedBy', c.actualizado_por)
                 from public.bot_config c),
    'log', coalesce((select jsonb_agg(jsonb_build_object('ts', floor(extract(epoch from l.cuando) * 1000)::bigint, 'by', l.usuario) order by l.id desc)
                       from (select x.id, x.cuando, x.usuario from public.bot_config_log x order by x.id desc limit 50) l), '[]'::jsonb));
$f$;

create or replace function public._crm_bot_config_limpia(p_t text)
returns text language sql immutable set search_path = '' as $f$
  select btrim(replace(replace(replace(coalesce(p_t, ''), E'\r\n', E'\n'), '<<<', '‹‹‹'), '>>>', '›››'));
$f$;

-- ── 3. leer ──────────────────────────────────────────────────────────────────
create or replace function public.crm_bot_config_leer(p_user uuid)
returns jsonb language plpgsql security definer set search_path = '' as $f$
begin
  perform public._crm_bot_config_autoriza(p_user);
  return public._crm_bot_config_json();
end $f$;

-- ── 4. guardar (token = updatedAt en ms) ─────────────────────────────────────
-- Devuelve {ok:true, config, log} o {conflicto:true, config, log} (no escribe nada). Entradas no validas -> PT400; sin permiso -> 42501.
create or replace function public.crm_bot_config_guardar(
  p_user uuid, p_extra text, p_bienvenida text, p_pausa_horas integer, p_esperada bigint, p_por text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_extra text := public._crm_bot_config_limpia(p_extra);
  v_bien  text := public._crm_bot_config_limpia(p_bienvenida);
  v_actual bigint;
begin
  perform public._crm_bot_config_autoriza(p_user);
  if p_esperada is null then raise exception 'Falta la version que se estaba viendo' using errcode = 'PT400'; end if;
  if p_pausa_horas is null or p_pausa_horas < 0 or p_pausa_horas > 720 then
    raise exception 'pausaHoras debe estar entre 0 y 720' using errcode = 'PT400'; end if;
  if length(v_extra) > 2000 or length(v_bien) > 500 then raise exception 'Texto demasiado largo' using errcode = 'PT400'; end if;
  select floor(extract(epoch from c.actualizado_en) * 1000)::bigint into v_actual from public.bot_config c where c.id for update;
  if v_actual is distinct from p_esperada then
    return jsonb_build_object('conflicto', true) || public._crm_bot_config_json();
  end if;
  update public.bot_config
     set extra = v_extra, bienvenida = v_bien, pausa_horas = p_pausa_horas, actualizado_por = left(coalesce(nullif(btrim(p_por), ''), 'desconocido'), 120)
   where id;
  return jsonb_build_object('ok', true) || public._crm_bot_config_json();
end $f$;

-- ── 5. volver a la version anterior ──────────────────────────────────────────
-- {ok:true,...} | {conflicto:true,...} | {sin_anterior:true,...}
create or replace function public.crm_bot_config_volver(p_user uuid, p_esperada bigint, p_por text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_actual bigint;
  v_prev jsonb;
begin
  perform public._crm_bot_config_autoriza(p_user);
  if p_esperada is null then raise exception 'Falta la version que se estaba viendo' using errcode = 'PT400'; end if;
  select floor(extract(epoch from c.actualizado_en) * 1000)::bigint into v_actual from public.bot_config c where c.id for update;
  if v_actual is distinct from p_esperada then
    return jsonb_build_object('conflicto', true) || public._crm_bot_config_json();
  end if;
  select l.prev into v_prev from public.bot_config_log l order by l.id desc limit 1;
  if v_prev is null then return jsonb_build_object('sin_anterior', true) || public._crm_bot_config_json(); end if;
  update public.bot_config
     set extra = public._crm_bot_config_limpia(v_prev->>'extra'), bienvenida = public._crm_bot_config_limpia(v_prev->>'bienvenida'),
         pausa_horas = (v_prev->>'pausa_horas')::integer, actualizado_por = left(coalesce(nullif(btrim(p_por), ''), 'desconocido'), 120)
   where id;
  return jsonb_build_object('ok', true) || public._crm_bot_config_json();
end $f$;

-- ── 6. cerrar: nace sin EXECUTE para nadie; solo la edge (service_role) ejecuta las tres publicas ──
revoke all on function public._crm_bot_config_autoriza(uuid)                                       from public, anon, authenticated, service_role;
revoke all on function public._crm_bot_config_json()                                               from public, anon, authenticated, service_role;
revoke all on function public._crm_bot_config_limpia(text)                                         from public, anon, authenticated, service_role;
revoke all on function public.crm_bot_config_leer(uuid)                                            from public, anon, authenticated, service_role;
revoke all on function public.crm_bot_config_guardar(uuid, text, text, integer, bigint, text)      from public, anon, authenticated, service_role;
revoke all on function public.crm_bot_config_volver(uuid, bigint, text)                            from public, anon, authenticated, service_role;
grant execute on function public.crm_bot_config_leer(uuid)                                         to service_role;
grant execute on function public.crm_bot_config_guardar(uuid, text, text, integer, bigint, text)  to service_role;
grant execute on function public.crm_bot_config_volver(uuid, bigint, text)                         to service_role;
