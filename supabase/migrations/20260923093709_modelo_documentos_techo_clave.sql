-- Anexo Maestro por modelo Y techo (23-sep-2026): el owner entrega un pack por
-- acabado de techo (Bambu / Sirap). El contrato de Construcción adjunta el
-- plano del techo elegido; NULL = vale para cualquier techo del modelo.
alter table public.modelo_documentos add column if not exists techo_clave text;
comment on column public.modelo_documentos.techo_clave is
  'Clave de modelo_techos (sirap, bambu…) a la que corresponde el documento. NULL = sirve para cualquier techo. El contrato de Construcción busca primero el plano de su techo y, si no hay, el de NULL.';
