-- Reservas por vencer (23-sep-2026, owner: «necesito una sección exclusiva
-- para reservas por vencer, alta prio»). La pantalla /intranet/v4/reservas/
-- lee la MISMA función que usa el cron libera-reservas-vencidas, para que lo
-- que se ve sea lo que el sistema va a hacer.
--
-- 1) EXECUTE para authenticated. La función es SECURITY INVOKER: cada sesión
--    ve solo los contratos que su RLS ya le deja (contrato_visible =
--    es_suyo / es_manager_de; admin todo). Nada de SECURITY DEFINER.
-- 2) contrato_tipo_etapa pasaba de puede('leads') a es_agente(). La función
--    filtra por ese catálogo, y quien tenía Operaciones sin CRM recibía 0
--    filas: Victor (autor de 7 de las 13 reservas vivas) veía la pantalla
--    vacía — revisión previa de Seguridad (#50), probado con SET ROLE. Es un
--    catálogo tipo→etapa sin datos personales. ALTER, no drop+create: la
--    policy conserva su nombre histórico.
-- Ensayo en ROLLBACK antes de aplicar: victor 7 contratos, dortegag 1,
-- gusabellan 6, los 7 admin/super_admin 13; anon sigue sin EXECUTE.

grant execute on function public.reservas_vencimiento() to authenticated;

alter policy "crm ve el catalogo de etapas" on public.contrato_tipo_etapa
  using (public.es_agente());
