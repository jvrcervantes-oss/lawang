-- La vista puente heredó el `grant all` que Supabase da por defecto a
-- `authenticated` — DELETE, INSERT, UPDATE y TRUNCATE incluidos. El
-- `grant select` que llevaba su migración no revoca ese default, solo lo
-- reafirma; medido con `information_schema.role_table_grants`, no supuesto.
--
-- No hay fuga: la vista es `security_invoker`, así que cualquier escritura a
-- través de ella aplicaría la RLS de `plantillas_contrato` (solo super admin).
-- Pero es una puerta que nadie necesita a una tabla de configuración, y esta
-- misma lección ya se ha pagado dos veces hoy en `plantilla_cuentas` y
-- `proyecto_cuentas`: el default de Supabase es `all`, y hay que recortarlo
-- explícitamente cada vez.
--
-- Es un PUENTE de lectura para el `entities.js` viejo. Solo select.
revoke all on public.plantillas_pago from authenticated;
grant select on public.plantillas_pago to authenticated;;
