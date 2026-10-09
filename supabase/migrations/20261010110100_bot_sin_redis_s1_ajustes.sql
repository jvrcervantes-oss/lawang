-- Ajustes de la revision de codigo de S1 (9-oct-2026). Solo create or replace de 4 funciones (misma firma):
--  1. bot_escalacion_tomar: si el dueño CITA un aviso y ese aviso no esta abierto, devuelve {} (antes caia a «la mas antigua»
--     y su respuesta salia hacia OTRO cliente). La cola por antiguedad solo vale cuando no cita nada.
--  2. «quitar pausa» (bot_pausar, bot_pausar_humano) y _bot_pausa_humana no tocan una conversacion con baja: el STOP manda.
-- Reversion: volver a las definiciones de 20261010110000_bot_sin_redis_s1_esquema.sql.
create or replace function public.bot_escalacion_tomar(p_ctx_wamid text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_ctx text := nullif(left(btrim(coalesce(p_ctx_wamid, '')), 120), '');
  v_r   record;
begin
  update public.bot_escalacion e
     set resuelta_en = now()
   where e.id = (select x.id from public.bot_escalacion x
                  where x.resuelta_en is null
                    and (case when v_ctx is not null then x.aviso_wamid = v_ctx
                              else x.creada_en > now() - interval '7 days' end)
                  order by x.creada_en, x.id
                  limit 1 for update skip locked)
  returning e.tel, e.nombre, e.pregunta into v_r;
  if not found then return '{}'::jsonb; end if;
  return jsonb_build_object('tel', v_r.tel, 'nombre', v_r.nombre, 'pregunta', v_r.pregunta);
end $f$;

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

create or replace function public.bot_pausar(p_tel text, p_modo text, p_horas int default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_hasta timestamptz;
  v_c    public.bot_chat%rowtype;
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  if p_modo is null or p_modo not in ('humano', 'quitar') then return jsonb_build_object('error', 'modo_invalido'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  if not exists (select 1 from public.bot_chat where tel = v_tel) then return jsonb_build_object('error', 'sin_chat'); end if;
  if p_modo = 'humano' then
    v_hasta := public._bot_pausa_humana(v_tel, p_horas, 'bot');
  else
    update public.bot_chat set pausado = false, pausa_hasta = null, pausa_por = 'bot', actualizado_en = now()
     where tel = v_tel and baja_en is null;
  end if;
  select * into v_c from public.bot_chat where tel = v_tel;
  return jsonb_build_object('pausado', v_c.pausado and (v_c.pausa_hasta is null or v_c.pausa_hasta > now()), 'hasta', v_c.pausa_hasta);
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

revoke all on function public._bot_pausa_humana(text, int, text) from public, anon, authenticated, service_role;
revoke all on function public.bot_escalacion_tomar(text)          from public, anon, authenticated, service_role;
revoke all on function public.bot_pausar(text, text, int)         from public, anon, authenticated, service_role;
revoke all on function public.bot_pausar_humano(text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.bot_escalacion_tomar(text)       to bot_lawang;
grant execute on function public.bot_pausar(text, text, int)      to bot_lawang;
grant execute on function public.bot_pausar_humano(text, text, text) to bot_lawang;
