-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- F1 empresas: la funcion del trigger de clave fija no se ejecuta desde fuera. Esto se aplico como migracion aparte (nombre f1_empresas_revoke_trigger_fn) y la misma
--   linea ya esta dentro de 20261007000500_f1_empresas.sql; este fichero la repite para que el nombre aplicado tenga su texto (LAW-496, 7-oct-2026). Idempotente.
-- destructivo-ok: solo quita EXECUTE a una funcion de trigger
-- REVERTIR: no procede (reducir la exposicion; nadie la llama como RPC)
revoke all on function public.trg_empresa_clave_fija() from public, anon, authenticated;
