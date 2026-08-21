-- Revocar de `anon` no servía de nada: Postgres concede EXECUTE a PUBLIC por
-- defecto al crear una función, y anon lo hereda. Hay que quitarlo de PUBLIC y
-- devolverlo explícitamente a quien lo necesita.
-- `authenticated` LO NECESITA: las policies evalúan estas funciones con los
-- privilegios de la sesión, así que sin EXECUTE cada comprobación de RLS
-- fallaría con "permission denied" y la suite entera quedaría fuera.
revoke execute on function public.es_agente()   from public;
revoke execute on function public.es_admin()    from public;
revoke execute on function public.puede(text)   from public;
revoke execute on function public.es_suyo(text) from public;

grant execute on function public.es_agente()   to authenticated, service_role;
grant execute on function public.es_admin()    to authenticated, service_role;
grant execute on function public.puede(text)   to authenticated, service_role;
grant execute on function public.es_suyo(text) to authenticated, service_role;;
