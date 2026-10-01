-- ============================================================================
-- AXW-127 — portal_elegible: lo que el portal deja hacer de verdad — 1-oct-2026
-- ----------------------------------------------------------------------------
-- La primera versión (20261001160000) exigía una fila ya existente en
-- portal_accesos. Medido: casi nadie la tiene (37 filas, 1 persona ha entrado
-- alguna vez), pero el portal NO la pide para entrar: la edge portal-acceso
-- llama a portal_autoservicio(email), que siembra la fila si el email es el de
-- una ficha enlazada a un contrato, y solo entonces concede el claim `portal`.
-- Con la regla estricta casi todos los compradores habrían recibido un PDF
-- adjunto que el portal ya les ofrece.
--
-- Regla ahora (lo que pasa en la práctica, solo en lectura):
--   · email válido, no es del equipo (usuarios), sin acceso revocado — los tres
--     rechazos de portal_autoservicio — y
--   · en ESTE contrato (contrato_compradores) hay una ficha con ese email, o ya
--     existe una fila activa de portal_accesos para esa ficha y ese email.
-- Es la condición de portal_ve_pdf (pa.client_id = cc.client_id de ESE
-- contrato, pa.email = email) una vez que el autoservicio ha sembrado la fila.
-- No usa la regla de portal_autoservicio entera: esa acepta al cliente de
-- CUALQUIER contrato y aquí hace falta el de ESTE.
-- Ante la duda: false (adjunto por la cola), nunca enlace.
-- ============================================================================
create or replace function public.portal_elegible(p_email text, p_contrato uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  with e as (select lower(btrim(coalesce(p_email, ''))) as v)
  select (select v from e) ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
     and exists (
           select 1
             from public.contratos c
             join public.contrato_compradores cc on cc.contrato_id = c.id
            where c.id = p_contrato
              and c.pdf_firmado_path is not null
              and (exists (select 1 from public.portal_accesos pa
                            where pa.client_id = cc.client_id and pa.activo
                              and pa.email = (select v from e))
                or exists (select 1 from public.clients cl
                            where cl.id = cc.client_id
                              and lower(btrim(coalesce(cl.email, ''))) = (select v from e))))
     and not exists (
           select 1 from public.usuarios u
            where lower(btrim(u.email)) = (select v from e))
     and not exists (
           select 1 from public.portal_accesos pa
            where pa.email = (select v from e) and not pa.activo)
$$;
revoke execute on function public.portal_elegible(text, uuid) from public, anon, authenticated;
grant  execute on function public.portal_elegible(text, uuid) to service_role;
