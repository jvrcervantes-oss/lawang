-- destructivo-ok: retira el INSERT/UPDATE directo de authenticated en bot_faq y sus dos policies de escritura; no toca filas.
-- APLICAR tras desplegar la edge `bot-agentes` que escribe por bot_faq_aprobar / bot_faq_retirar (20260927171000).
-- Con esto, la única escritura de authenticated/anon que queda en toda la base es el INSERT anónimo de `leads`
-- (SumbaHills/api/lead.php), que tiene su propia pieza.
revoke insert, update on public.bot_faq from authenticated, anon;
drop policy if exists "bot_faq: solo super_admin aprueba" on public.bot_faq;
drop policy if exists "bot_faq: solo super_admin retira" on public.bot_faq;

do $$
begin
  if has_table_privilege('authenticated', 'public.bot_faq', 'INSERT') or has_table_privilege('authenticated', 'public.bot_faq', 'UPDATE') then
    raise exception 'bot_faq: authenticated sigue pudiendo escribir';
  end if;
  if exists (select 1 from information_schema.column_privileges where table_schema = 'public' and table_name = 'bot_faq'
              and grantee in ('authenticated', 'anon') and privilege_type in ('INSERT', 'UPDATE')) then
    raise exception 'bot_faq: quedan permisos de escritura por columna';
  end if;
end $$;
