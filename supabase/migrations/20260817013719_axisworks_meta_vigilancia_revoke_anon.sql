-- La tabla nacio con SELECT para `anon` por los default privileges del esquema public —
-- sus hermanas (axisworks_cuentas, axisworks_meta_campanas) NO lo tienen. RLS con cero
-- politicas ya lo bloquea, asi que esto no tapa una fuga: quita la dependencia de una sola
-- capa y deja las tres tablas iguales, que es lo que hace que la proxima auditoria pueda
-- comparar sin excepciones que explicar.
revoke all on public.axisworks_meta_vigilancia from anon;;
