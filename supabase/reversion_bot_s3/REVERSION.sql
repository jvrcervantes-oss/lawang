-- destructivo-ok: reversion MANUAL de la migracion 20261010080000/20261010080100 (S3 del encargo bot catalogo+CRM). No se aplica sola. Solo es segura si bot_acciones_log no se necesita (se pierde el log) y no hay citas del bot: comprobar antes `select count(*) from lead_accion where origen='bot'`.
-- Las 3 funciones del CRM (crm_leads, crm_lead_accion_poner, crm_lead_accion_completar) se devuelven a su version anterior a mano desde
-- 20261008303000_f2_b3_4_crm_leads.sql y 20260911*; aqui solo se quita lo que S3 añadio.
drop function if exists public.bot_catalogo_leer();
drop function if exists public.bot_lead_upsert(text, text, text, text);
drop function if exists public.bot_lead_nota(text, text, text);
drop function if exists public.bot_lead_cita(text, text, text, text);
drop function if exists public._bot_nota_ambiguo(uuid[], text);
drop function if exists public._bot_log(text, uuid, text, text, text);
drop function if exists public._bot_e164(text);
drop table if exists public.bot_acciones_log;
drop function if exists public.bot_acciones_log_solo_anade();
delete from public.crm_origen_empresa where clave in ('bot-whatsapp-lawang', 'bot-whatsapp-sumbahills');
drop index if exists public.lead_accion_cita_viva;
drop index if exists public.lead_accion_una_viva;
create unique index lead_accion_una_viva on public.lead_accion (lead_id) where completada_en is null;   -- solo si ya no hay cita viva
alter table public.lead_accion drop column if exists tipo, drop column if exists cuando_ts, drop column if exists estado, drop column if exists origen;
drop trigger if exists trg_proyectos_bot_publico_sello on public.proyectos;
drop function if exists public.proyectos_bot_publico_sello();
alter table public.proyectos drop column if exists bot_publico, drop column if exists bot_publico_por, drop column if exists bot_publico_en;
revoke bot_lawang from postgres;
drop role if exists bot_lawang;
