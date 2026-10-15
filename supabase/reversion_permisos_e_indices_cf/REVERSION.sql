-- REVERSION de 20261015055028_permisos_e_indices_cf (14-oct-2026): vuelve a dar EXECUTE a authenticated en las dos funciones de
--   trigger (como estaban medidas el 14-oct: anon no, authenticated si, service_role si) y quita los ocho indices nuevos.
-- destructivo-ok: solo quita los ocho indices que crea 20261015055028 (no hay datos en un indice); se aplica a mano para revertir
set local lock_timeout = '5s';
grant execute on function public._documents_kyc_firmado() to authenticated;
grant execute on function public._trg_contrato_bloqueado_aviso_manager() to authenticated;
drop index if exists public.facturas_sociedad_idx;
drop index if exists public.notificaciones_contrato_id_idx;
drop index if exists public.solicitudes_pago_contrato_id_idx;
drop index if exists public.correos_cola_contrato_id_idx;
drop index if exists public.correos_cola_factura_id_idx;
drop index if exists public.correos_cola_firma_id_idx;
drop index if exists public.reclamos_pago_contrato_id_idx;
drop index if exists public.reclamos_pago_cola_id_idx;
