-- `autor = auth.email()` da NULL si no hay sesión (o si el email es null), y
-- `false or NULL` = NULL. En una policy NULL deniega igual que false, pero un
-- predicado que devuelve NULL es una trampa para quien lo reutilice fuera de
-- RLS. Se fuerza booleano.
create or replace function public.es_suyo(autor text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(autor is null or autor = (select auth.email()) or public.es_admin(), false)
$$;;
