-- destructivo-ok: DROP CONSTRAINT de un CHECK, no toca filas ni borra datos —
-- se sustituye por una versión más estricta del mismo check (ahora incluye
-- 'proforma'). 12-ago-2026, petición del cliente: factura, proforma y recibí
-- exigen contrato — sin eso no hay a qué balance atribuir el documento.
-- NOT VALID para no romper proformas ya emitidas sin contrato_id; sí se
-- exige en cualquier INSERT/UPDATE nuevo.
alter table public.facturas
  drop constraint if exists facturas_contrato_obligatorio;

alter table public.facturas
  add constraint facturas_contrato_obligatorio
  check (contrato_id is not null)
  not valid;;
