-- S12 (revisor-codigo, hallazgo BAJA): registrar el 7d no debe pisar un `revocado`. Aplicada en produccion junto a la anterior. Reversion: la definicion de 20261010170000.
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
           consent_estado = case when consent_estado = 'si' then 'usado' else consent_estado end, actualizado_en = now() where tel = v_tel;   -- el 7d agota el consentimiento, sin pisar un `revocado` (STOP entre reservar y registrar)
  end if;
  if p_resultado = 'enviado' then
    -- queda en el hilo para que el equipo lo vea; NO toca ultimo_mensaje/actividad (no alarga la retencion) y la marca de texto lo excluye del ancla
    insert into public.bot_mensaje (tel, rol, por, contenido, wamid)
    values (v_tel, 'assistant', 'bot', public._bot_limpia('[plantilla lawang_reenganche_' || p_plantilla || '] ' || coalesce(p_texto, ''), 4096), v_w)
    on conflict (tel, wamid) where wamid is not null do nothing;
  end if;
  return 'ok';
end $f$;
revoke all on function public.bot_seguimiento_registrar(text, text, text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.bot_seguimiento_registrar(text, text, text, text, text) to bot_lawang;
