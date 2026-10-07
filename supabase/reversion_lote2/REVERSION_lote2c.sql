-- REVERSION lote 2c (6-oct-2026) · devuelve a tepi_sungai las familias RP00082+CC00043 y RP00125+CC00080.
-- Estado previo capturado ANTES de aplicar: los 4 contratos con datos.fields.sociedad_firmante='tepi_sungai', SIN cuenta_es_escrow y las 2 reservas
--   (RP00082, RP00125) SIN precio_lista_suelo; los 10 documentos con sociedad='tepi_sungai' y datos.fields.sociedad='tepi_sungai'
--   (datos.emisor previo: ausente salvo INV00178 y REC00134, con los mismos datos de Tepi; el trigger lo vuelve a congelar).
--   comision_admin_lineas de REC00055/REC00084/REC00134: sociedad 'tepi_sungai' (importes 125/50/100, pendiente).
-- ORDEN (obligatorio por los triggers de coherencia): recibis -> documentos -> reservas (padres) -> construcciones (hijos).
-- Pega todo en una sola transaccion. Si algun documento se hubiese ENVIADO despues, factura_enviada_no_cambia_emisor parara la reversion.
begin;
update public.facturas set sociedad='tepi_sungai', datos=jsonb_set(datos,'{fields,sociedad}','"tepi_sungai"')
 where numero in ('REC00055','REC00134','REC00084');
update public.facturas set sociedad='tepi_sungai', datos=jsonb_set(datos,'{fields,sociedad}','"tepi_sungai"')
 where numero in ('INV00073','PRO00072','PRO00147','INV00178','PRO00071','INV00118','PRO00146');
update public.contratos set datos = jsonb_set((datos #- '{fields,cuenta_es_escrow}') #- '{fields,precio_lista_suelo}', '{fields,sociedad_firmante}', '"tepi_sungai"')
 where numero in ('RP00082','RP00125');
update public.contratos set datos = jsonb_set(datos #- '{fields,cuenta_es_escrow}', '{fields,sociedad_firmante}', '"tepi_sungai"')
 where numero in ('CC00043','CC00080');
-- comprobar antes de commit: las 3 lineas de comision admin deben haber vuelto a tepi_sungai (las mueve el trigger del recibi)
select recibi_numero, sociedad, importe from public.comision_admin_lineas where recibi_numero in ('REC00055','REC00134','REC00084');
commit;
