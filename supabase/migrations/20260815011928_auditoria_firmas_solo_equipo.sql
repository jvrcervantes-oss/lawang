-- En Postgres, una funcion nueva nace con EXECUTE para PUBLIC. El
-- `grant execute ... to authenticated` que llevaba NO revoca eso: solo anade.
-- Resultado: `auditoria_firmas()` era llamable por un anonimo con la clave
-- publicable, que esta en el HTML del sitio. Comprobado en vivo el 15-ago:
-- devolvia numeros de contrato, nombres de compradores y estado de sus firmas.
revoke all on function public.auditoria_firmas() from public;
revoke all on function public.auditoria_firmas() from anon;
grant execute on function public.auditoria_firmas() to authenticated;;
