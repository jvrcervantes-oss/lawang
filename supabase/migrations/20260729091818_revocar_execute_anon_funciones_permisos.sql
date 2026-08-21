-- El linter avisa de que estas SECURITY DEFINER son invocables por RPC.
-- No filtran nada (todas responden sobre QUIEN LLAMA: devuelven booleanos
-- sobre el propio solicitante, no datos de terceros), pero a `anon` no le
-- sirven para nada y siempre devuelven false: fuera.
--
-- ⚠️ A `authenticated` NO se le revoca a propósito. Las policies evalúan estas
-- funciones con los privilegios del usuario de la sesión: sin EXECUTE, cada
-- comprobación de RLS fallaría con "permission denied" y la suite entera se
-- quedaría fuera. Es exactamente el modo de fallo que ya nos costó una vez con
-- es_agente(). El aviso 0029 del linter se acepta como deuda consciente.
revoke execute on function public.es_agente()          from anon;
revoke execute on function public.es_admin()           from anon;
revoke execute on function public.puede(text)          from anon;
revoke execute on function public.es_suyo(text)        from anon;;
