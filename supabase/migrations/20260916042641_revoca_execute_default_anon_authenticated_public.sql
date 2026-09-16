-- Hallazgo de Seguridad (consulta de deploy, 16-sep-2026), 2a vez en la misma
-- sesion que una funcion nueva nace ejecutable por anon/authenticated sin
-- pedirlo (investor_deck_parcelas primero, unidad_parte_cobrada_interno
-- despues) -- causa raiz: pg_default_acl del rol `postgres` en el esquema
-- `public` concede EXECUTE por defecto a anon/authenticated/service_role en
-- TODA funcion nueva creada por ese rol (las migraciones corren como
-- postgres). Se cierra de raiz para que el proximo REVOKE manual deje de
-- hacer falta -- las funciones que SI deben ser publicas siguen necesitando
-- su GRANT explicito (mismo patron que ya usan las RPC del investor-deck).
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;
