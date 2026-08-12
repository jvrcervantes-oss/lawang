-- 12-ago-2026, petición del cliente: factura, proforma y recibí exigen contrato
-- (antes solo factura+recibí, ver tipo_y_contrato.sql). Sin contrato no hay a
-- qué balance atribuir el documento — ni siquiera una proforma.
-- Aplicado directamente vía MCP (DDL que construye, se aplica solo).
--
-- NOT VALID para no romper proformas ya emitidas sin contrato_id; sí se exige
-- en cualquier INSERT/UPDATE nuevo.
alter table public.facturas
  drop constraint if exists facturas_contrato_obligatorio;

alter table public.facturas
  add constraint facturas_contrato_obligatorio
  check (contrato_id is not null)
  not valid;
