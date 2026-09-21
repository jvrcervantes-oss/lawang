-- Corrige la cabecera de 20260921111709_contrato_closer_semilla_revoke_execute.sql:
-- citaba "la migración 20260921193000", que no existe en el repo (fue el nombre de
-- archivo que yo mismo elegí a mano ANTES de correr `supabase migration fetch`, que
-- reescribió el historial real con el timestamp verdadero de aplicación,
-- 20260921111614_contrato_closer_semilla_al_alta.sql). Lo cazó code-review sobre el
-- diff, 21-sep-2026: "A maintainer... will search for 20260921193000 and find
-- nothing". El REVOKE ya estaba correctamente aplicado por la migración anterior;
-- esto es solo idempotente (revocar dos veces no hace nada) para dejar la cita bien
-- en el historial real que luego baja `supabase_fetch_seguro.py`.
revoke execute on function public.crm_contrato_closer_semilla() from public, anon, authenticated;
;
