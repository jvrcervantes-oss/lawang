-- destructivo-ok: no destruye datos -- REVOKE de permisos excesivos (INSERT/UPDATE/
-- DELETE/TRUNCATE a anon/authenticated) que un CREATE OR REPLACE VIEW dejó abiertos
-- por accidente en una vista de solo lectura; no toca ninguna fila. Ver contexto abajo.
--
-- 10-ago-2026 (Seguridad): la migración de esta misma tarde (unidades_estado_vista_fase_zona,
-- 20260810100129) recreó la vista con CREATE OR REPLACE VIEW sin repetir el
-- `alter view ... set (security_invoker = true)` ni el `grant select ... to authenticated`
-- que sí llevaban las dos migraciones anteriores de esta vista (vinculo_contrato_unidad,
-- 31-jul; unidades_estado_con_obra, 5-ago). Un CREATE OR REPLACE VIEW no conserva
-- reloptions ni grants explícitos: la vista quedó SECURITY DEFINER (confirmado por
-- get_advisors: security_definer_view, ERROR) con INSERT/UPDATE/DELETE/TRUNCATE
-- abiertos a anon y authenticated (grants por defecto del owner) -- cualquiera sin
-- sesión podía leer comprador_nombre/contrato_numero/facturado/pct_cobrado de las
-- 228 unidades saltándose la RLS de unidades/contratos/facturas. Restaura el estado
-- previo exacto: solo SELECT, solo para authenticated, con RLS de las tablas base.
revoke all on public.unidades_estado from anon, authenticated;
alter view public.unidades_estado set (security_invoker = true);
grant select on public.unidades_estado to authenticated;;
