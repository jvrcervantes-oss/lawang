-- El linter marcó public._protege_liberado_contrato() como ejecutable por
-- anon/PUBLIC (SECURITY DEFINER + grant PUBLIC por defecto de toda función
-- nueva en Postgres). Es una función de trigger interna — no necesita EXECUTE
-- para dispararse como trigger (eso no lo comprueba el motor), y el resto de
-- funciones-trigger de esta tabla (contrato_no_editable_en_firma,
-- carta_cobrado_congelado_en_update) ya están así de restringidas. Se alinea.
revoke all on function public._protege_liberado_contrato() from public, anon, authenticated;
grant execute on function public._protege_liberado_contrato() to service_role;
