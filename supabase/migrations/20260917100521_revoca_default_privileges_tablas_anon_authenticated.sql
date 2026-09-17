-- Mismo patron ya aplicado a funciones el 16-sep (20260916042641/20260916042744), extendido a
-- tablas: hallazgo de Seguridad en la consulta de deploy del 17-sep sobre
-- obra_vencimientos_esquema -- toda tabla nueva nacia con INSERT/UPDATE/DELETE abiertos de
-- fabrica para anon Y authenticated (pg_default_acl), no solo para authenticated. El REVOKE
-- por tabla sigue siendo obligatorio (el mismo gotcha de funciones -- una funcion creada
-- DESPUES del default fix seguia con PUBLIC=EXECUTE, causa no explicada -- puede repetirse
-- aqui), esto es defensa en profundidad, no sustituye verificar cada tabla nueva.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
