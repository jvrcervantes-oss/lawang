-- destructivo-ok: UPDATE de UNA fila conocida por id (PRO00119), con rastro
-- ANTES en correcciones_datos -- no es un update masivo ni sin WHERE. Corrige
-- el bug real (precargarConceptos ofrecia "toda la unidad" primero y se
-- auto-clicaba, sumando el total de RP00106 que YA estaba facturado aparte
-- en PRO00118, dos minutos antes). El codigo que lo causaba se corrigio en
-- intranet/facturas/index.html (28-ago-2026): a partir de ahora la precarga
-- automatica de una proforma solo pone el total de SU PROPIO contrato.

insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
values (
  'facturas', '0fbe72f6-c5e3-4e81-b91c-91dbf5a9dd15', 'total,datos',
  '{"total":"69000","linea_parcela":"Parcela — precio total del contrato RP00106 · 25000"}',
  '{"total":"44000","linea_parcela":"retirada"}',
  'PRO00119 duplicaba la parcela de RP00106 (25.000), ya facturada aparte en PRO00118 dos minutos antes -- aviso del owner 28-ago-2026. La proforma queda solo con el total de su propio contrato, CC00067.',
  'owner-28ago-via-CEO'
);

update public.facturas
set total = 44000,
    datos = jsonb_set(
      jsonb_set(datos, '{lineas}', '[{"descripcion":"Precio total del contrato CC00067","importe":"44000"}]'::jsonb),
      '{totales}', '{"pct":0,"total":44000,"impuesto":0,"subtotal":44000}'::jsonb
    )
where id = '0fbe72f6-c5e3-4e81-b91c-91dbf5a9dd15' and numero = 'PRO00119';;
