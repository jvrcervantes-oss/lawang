-- Vínculo entre contratos de la misma venta (obra → su reserva/PPJB).
-- Lo escribe app.html al guardar (número elegido → id); lo lee /operaciones/
-- para juntar ambos documentos en una sola operación.
alter table public.contratos
  add column contrato_padre_id uuid references public.contratos(id),
  add constraint contratos_padre_no_self check (contrato_padre_id is distinct from id);
create index contratos_padre_idx on public.contratos (contrato_padre_id);
comment on column public.contratos.contrato_padre_id is
  'Contrato de reserva/PPJB del que deriva este (misma venta). NULL = contrato raíz o sin vincular.';;
