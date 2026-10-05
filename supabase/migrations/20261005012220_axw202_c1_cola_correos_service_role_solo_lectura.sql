-- destructivo-ok: solo QUITA privilegios de escritura directa a service_role sobre correos_cola, una tabla creada hoy y vacía; no borra ni cambia ningún dato.
-- AXW-202 C1 (5-oct-2026) — hallazgo de la prueba por perfil (contracts/sql/prueba_correos_cola.sql):
-- los default privileges de Supabase daban a service_role ALL sobre la tabla nueva, así que podía insertar, actualizar y borrar
-- SALTÁNDOSE las comprobaciones de correo_encolar (ancla, variables, clave soportada) y de las RPC de cierre. Lo único que tiene
-- llamador con nombre sobre la tabla es el SELECT (diagnóstico); la escritura va solo por RPC (definer, dueño postgres).
revoke insert, update, delete, truncate, references, trigger on public.correos_cola from service_role;
