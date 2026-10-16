-- destructivo-ok: VUELTA ATRÁS de 20261016073530_mcp_f1_p4_ajustes.sql (funciones de las pantallas del MCP de Lawang).
-- No borra datos: P4 no crea tablas. Las pantallas dejan de funcionar; apagar la IA sin esto: Ajustes › IA o
-- `update public.ia_ajustes set encendido = false`. Va ANTES de vuelta_atras_p1.sql si se quita todo.
begin;
drop function if exists public.ia_permiso_guarda(uuid, boolean);
drop function if exists public.ia_cliente_guarda(uuid, text, text, text[], boolean);
drop function if exists public.ia_ajustes_guarda(jsonb);
drop function if exists public.ia_ajustes_datos();
drop function if exists public.ia_ajustes_ver();       -- su nombre desde 20261016080000
drop function if exists public.ia_mis_conexiones();
drop function if exists public.ia_peticion_datos(text);
drop function if exists public.ia_peticion_ver(text);   -- su nombre desde 20261016080000
drop function if exists privado.ia_redirect_valida(text, text);
drop function if exists privado.ia_gestor_uid();
drop function if exists privado.ia_pantalla_uid();
drop function if exists privado.ia_equipo();
commit;
