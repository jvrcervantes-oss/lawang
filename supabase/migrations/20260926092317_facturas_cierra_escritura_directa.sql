-- destructivo-ok: QUITA permisos de escritura directa (insert/update/delete) a anon/authenticated sobre facturas; no borra ni cambia ninguna fila.
-- LAW-339, 26-sep-2026, OK del owner («hazlo ya»). Frontera frontend/backend: desde hoy toda
-- escritura en facturas va por factura_guarda/anula/reactiva/borra/marca_enviada (SECURITY
-- DEFINER, permiso dentro) o por guardar_recibi y las edges con service role. Revocar a nivel
-- de tabla quita también los grants por columna. Verificado: authenticated solo conserva SELECT;
-- insert/update/delete directos dan 42501 y factura_guarda sigue emitiendo.
revoke insert, update, delete on public.facturas from anon, authenticated;
