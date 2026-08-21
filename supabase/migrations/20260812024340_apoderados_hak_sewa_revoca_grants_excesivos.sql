-- destructivo-ok: solo REVOKE de privilegios, no toca filas ni borra datos.
-- Autocorrección inmediata: el CREATE TABLE anterior heredó privilegios por
-- defecto de Supabase para `authenticated` (INSERT/UPDATE/DELETE, no solo
-- SELECT) — a diferencia de `cuentas_bancarias`, que solo tiene SELECT
-- concedido a authenticated. Verificado y comparado justo después de crear
-- la tabla, antes de que nadie la usara. Cualquier agente autenticado podía
-- escribir/borrar apoderados por REST directo.
revoke all on public.apoderados_hak_sewa from authenticated;
grant select on public.apoderados_hak_sewa to authenticated;;
