-- APLICADA en producción el 29-jul-2026 (MCP supabase-lawang, migración
-- `hash_pdf_firmado`). Registro, no hace falta volver a correrla.
--
-- Integridad probatoria del PDF firmado (UU ITE 11/2008): con el bucket en
-- upsert no hay forma de demostrar que el fichero no cambió — el hash SHA-256
-- guardado en el registro sí lo prueba. Lo escriben firma-submit (firma
-- remota) y la subida manual de app.html.
alter table public.contrato_firmas add column pdf_hash text;
comment on column public.contrato_firmas.pdf_hash is
  'SHA-256 (hex) del PDF generado por esta firma. Lo escribe firma-submit al renderizar.';
alter table public.contratos add column pdf_firmado_hash text;
comment on column public.contratos.pdf_firmado_hash is
  'SHA-256 (hex) del PDF al que apunta pdf_firmado_path. Lo escribe firma-submit o la subida manual.';
