-- Multi-firmante: cada firma guarda SU propio PDF.
-- Lawang · proyecto Supabase vtulllundrfennhjddhc · 28-jul-2026
--
-- QUÉ ARREGLA
-- `firma-submit` subía el PDF firmado a `<numero>.pdf` con upsert:true, o sea que
-- la ruta la decidía el CONTRATO y no el FIRMANTE. Dos consecuencias, las dos
-- silenciosas y las dos con pérdida de un documento legal:
--   1. Si Adquiriente I y II firman el mismo contrato, el segundo PDF machaca al
--      primero y solo sobrevive la última firma.
--   2. "Subir firmado" de contracts/app.html usaba ESA MISMA ruta, así que una
--      subida manual pisaba el PDF de una firma remota, y al revés.
--
-- El código ya escribe ahora rutas únicas (`<numero>_<id de firma>.pdf` la firma
-- remota, `<numero>_manual.pdf` la subida a mano). Esta columna es la otra mitad:
-- que cada fila de `contrato_firmas` sepa cuál es su fichero. `contratos.
-- pdf_firmado_path` se queda como está —apunta al último— porque es lo que lee
-- el botón "Descargar PDF" del panel y no hay motivo para romperlo hoy.
--
-- NO TOCA DATOS EXISTENTES: es un `add column` nullable. Las filas ya firmadas
-- se quedan con pdf_path NULL y su PDF sigue donde estaba (`CR00004.pdf`), al
-- que `contratos.pdf_firmado_path` sigue apuntando. Nada que migrar.

alter table public.contrato_firmas
  add column if not exists pdf_path text;

comment on column public.contrato_firmas.pdf_path is
  'Ruta del PDF de ESTA firma en el bucket contratos-firmados. Única por firma '
  '(<numero>_<id>.pdf) para que un segundo firmante no machaque al primero. '
  'NULL en las firmas anteriores al 28-jul-2026, que usaban <numero>.pdf.';

-- Comprobación (debe devolver la columna, y por la API REST además, que la caché
-- de esquema de PostgREST va por detrás del SQL Editor):
--   select column_name from information_schema.columns
--    where table_name='contrato_firmas' and column_name='pdf_path';
--   curl "$URL/rest/v1/contrato_firmas?select=pdf_path&limit=1" -H "apikey: $KEY"
