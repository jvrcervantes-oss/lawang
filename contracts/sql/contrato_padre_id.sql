-- APLICADA en producción el 29-jul-2026 (MCP supabase-lawang, migración
-- `contratos_contrato_padre_id`). Se guarda aquí como registro, igual que el
-- resto de sql/ — no hace falta volver a correrla.
--
-- Vínculo entre contratos de la misma venta (obra → su reserva/PPJB).
-- Lo escribe contracts/app.html al guardar (el número elegido en el desplegable
-- «Nº del Contrato de Reserva/PPJB vinculado» se resuelve a id); lo lee
-- /intranet/operaciones/ para juntar ambos documentos en una sola operación.
alter table public.contratos
  add column contrato_padre_id uuid references public.contratos(id),
  add constraint contratos_padre_no_self check (contrato_padre_id is distinct from id);
create index contratos_padre_idx on public.contratos (contrato_padre_id);
comment on column public.contratos.contrato_padre_id is
  'Contrato de reserva/PPJB del que deriva este (misma venta). NULL = contrato raíz o sin vincular.';
