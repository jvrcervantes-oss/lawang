-- Lawang · contrato_firmas — cerrar el mismo agujero que se cerró en `contratos`
-- 27-jul-2026
--
-- Estado al detectarlo: una sola policy, `contrato_firmas_auth_all`, ALL para
-- `authenticated` con `using (true) with check (true)`. Como el registro de
-- Supabase Auth sigue ABIERTO (/auth/v1/settings → disable_signup:false) y la
-- publishable key va en el HTML, cualquiera puede registrarse y:
--   · leer nombre y email de cada firmante y la ruta de su snapshot,
--   · alterar `estado` (dejar un enlace inservible o reabrir uno ya firmado),
--   · insertar o borrar filas de firma.
-- El token no se puede derivar (en la tabla vive su SHA-256) y el bucket
-- `contratos-firmados` ya exige es_agente(), así que no se llega al documento;
-- pero los datos personales del firmante y el control del flujo sí quedan al aire.
--
-- Fix: el mismo claim que el resto de la suite. Las Edge Functions firma-get y
-- firma-submit usan service_role, que se salta RLS — no les afecta.

drop policy if exists "contrato_firmas_auth_all" on public.contrato_firmas;

create policy "agentes autenticados gestionan firmas"
  on public.contrato_firmas for all to authenticated
  using (public.es_agente())
  with check (public.es_agente());

-- Comprobación: debe devolver es_agente() en qual y with_check.
-- select policyname, qual, with_check from pg_policies where tablename='contrato_firmas';
