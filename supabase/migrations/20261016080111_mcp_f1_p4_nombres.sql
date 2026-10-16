-- MCP de Lawang · F1-P4 · las dos lecturas de pantalla del puente dejan el sufijo `_datos` (16-oct-2026, sesión mcp-lawang).
-- Solo renombra (ALTER ... RENAME conserva dueño, cuerpo y EXECUTE): no borra ni abre nada.
--
-- Por qué. En Lawang `<pantalla>_datos` es un contrato, no un nombre: es una lectura de LAW-338 cuyo dueño es lw_lector, que ve
-- lo mismo que authenticated (las policies de lectura van `TO authenticated, lw_lector`); la pide la pantalla por lwDatos
-- (contracts/assets/guard.js) y la vigila «lw_lector es un lector» (a) de tools/salud_lawang.py. public.ia_ajustes_datos y
-- public.ia_peticion_datos no cumplen ese contrato ni pueden: leen tablas ia_* que authenticated no lee y que solo su dueño,
-- ia_puente_rol, toca (RLS sin policies, 20261016073011). Al aplicar la 073530 salieron en (a) con «dueno ia_puente_rol»
-- (agencia-cd, 16-oct). No es «saltarse el freno con otro nombre»: pasan a la convención de su familia, la de
-- public.ia_mis_conexiones (lectura de pantalla del puente, dueño ia_puente_rol, sin `_datos` y pedida con sb.rpc), y la
-- familia tiene su propio guardián: «el puente MCP sigue cerrado» lista su EXECUTE exacto y desde este cambio comprueba
-- también que su dueño es ia_puente_rol (apartado e). Así una que renazca con dueño postgres salta igual que en (a).
-- Pasarlas a dueño lw_lector, descartado: lw_lector tendría que leer tablas ia_* que authenticated no lee, que es justo lo que
-- (b) prohíbe.
--
-- Llamadores al día en el mismo commit: intranet/v4/assets/ajustes-ia.js (ia_ajustes_ver) y la página de conexión que espera en
-- supabase/propuestas/web/ (ia_peticion_ver), con su grant en supabase/propuestas/20261016140000_mcp_f1_abre_conexion.sql.
-- La web que llama al nombre nuevo aterriza DESPUÉS de aplicar esta migración.
--
-- VUELTA ATRÁS (no destruye nada):
--   alter function public.ia_ajustes_ver() rename to ia_ajustes_datos;
--   alter function public.ia_peticion_ver(text) rename to ia_peticion_datos;
set lock_timeout = '5s';
alter function public.ia_ajustes_datos() rename to ia_ajustes_ver;
alter function public.ia_peticion_datos(text) rename to ia_peticion_ver;
