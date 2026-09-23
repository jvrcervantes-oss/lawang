-- ============================================================================
-- Documentación KYC de un comprador con contrato FIRMADO: solo la retira un
-- super admin — 23-sep-2026, decisión de Legal del 19-sep (revisión previa #27
-- del encargo de paridad v4) que no se había aplicado.
-- ----------------------------------------------------------------------------
-- Hasta hoy la policy «admins borran documentos» (es_admin()) dejaba a
-- cualquier admin retirar el pasaporte o el justificante de fondos de un
-- comprador con contrato firmado — 10 compradores en ese caso el 23-sep. Esa
-- documentación es la base del KYC/AML de una venta cerrada: conservarla es
-- una obligación, no una preferencia (RGPD 5.2, UU PDP, conservación AML).
-- El super admin puede (casos reales: un documento subido a la ficha
-- equivocada) y el borrado queda en `borrados` con quién y cuándo
-- (trg_guarda_antes_de_borrar, 20260923140000). El «motivo» que pedía Legal
-- no se captura aquí — un trigger no puede pedirlo; queda el rastro de quién.
-- Probado con el rol REAL en transacción con ROLLBACK: un admin rebota con el
-- mensaje de abajo; el super admin borra.
-- ============================================================================

create or replace function public._documents_kyc_firmado()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if not public.es_super_admin() and exists (
       select 1 from public.contrato_compradores cc
         join public.contratos c on c.id = cc.contrato_id
        where cc.client_id = old.client_id and c.bloqueado) then
    raise exception 'Este comprador tiene un contrato firmado: su documentación KYC solo la retira un super admin (queda registrado).'
      using errcode = '42501';
  end if;
  return old;
end; $function$;

create or replace trigger trg_documents_kyc_firmado
  before delete on public.documents
  for each row execute function public._documents_kyc_firmado();
