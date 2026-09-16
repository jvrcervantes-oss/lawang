-- La correccion anterior (REVOKE ... FROM anon, authenticated) no basto: un
-- function de prueba creada despues seguia saliendo ejecutable por PUBLIC
-- (que anon/authenticated heredan por ser miembros implicitos de PUBLIC).
-- Se cierra explicitamente tambien PUBLIC en el default -- el default de
-- Postgres para funciones nuevas es "EXECUTE a PUBLIC" salvo que se revoque.
--
-- NOTA (16-sep-2026, sin resolver del todo): tras ESTA migracion,
-- pg_default_acl para (rol postgres, esquema public, funciones) queda en
-- {postgres=X/postgres,service_role=X/postgres} -- correcto, sin PUBLIC ni
-- anon/authenticated. Pero una funcion de prueba creada DESPUES de aplicar
-- esto (misma sesion, mismo current_user=postgres) seguia devolviendo
-- PUBLIC=EXECUTE en information_schema.routine_privileges. No se identifico
-- la causa (no hay event trigger de este proyecto que lo explique -- se
-- revisaron pg_event_trigger y son los estandar de Supabase). Registrado
-- como deuda en contexto/seguridad_2026.md: mientras no se explique, TODA
-- funcion SECURITY DEFINER sensible nueva sigue necesitando su propio
-- REVOKE EXECUTE explicito verificado con information_schema tras crearla,
-- no fiarse de este default.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
