-- destructivo-ok: QUITA permisos de escritura directa (insert/update/delete) a anon/authenticated sobre gastos y proveedores; no borra ni cambia ninguna fila.
-- LAW-336 pieza 3, 26-sep-2026. panel-gastos.js ya va por gasto_* / proveedor_guarda (servido en
-- producción, VERDE). Ninguna otra función escribe en estas tablas (medido).
-- Verificado: authenticated solo SELECT y 0 columnas escribibles en las dos.
revoke insert, update, delete on public.gastos, public.proveedores from anon, authenticated;
