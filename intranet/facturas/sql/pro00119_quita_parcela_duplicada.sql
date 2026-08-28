-- Ya aplicado en producción (28-ago-2026, aviso del owner: "la 119 está
-- juntando lo que ya está duplicando la 118"). Copia de repo-de-registro,
-- no se vuelve a ejecutar.
--
-- Qué pasó: CC00067 (construcción, 44.000 EUR) va encadenado a RP00106
-- (parcela, 25.000 EUR) — el mismo par «bloqueo de parcela → construcción»
-- documentado en `pintarVinculados`. Al abrir la proforma de CC00067 en
-- blanco, `precargarConceptos()` auto-clicaba el botón «Toda la unidad · los
-- dos contratos» (data-unidad) por delante de «Total del proyecto»
-- (#hitoTodo) — sumando el total de RP00106, que YA tenía su propia proforma
-- (PRO00118, emitida dos minutos antes). PRO00119 salió por 69.000 en vez de
-- 44.000: la parcela facturada dos veces.
--
-- Corregido en dos sitios:
--   1. intranet/facturas/index.html, precargarConceptos(): la precarga
--      automática de una proforma en blanco solo pone el total de SU PROPIO
--      contrato. Combinar con un contrato vinculado sigue existiendo, pero
--      como clic consciente, nunca automático.
--   2. Los datos ya emitidos de PRO00119 (abajo), con rastro en
--      correcciones_datos antes de corregir.

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
where id = '0fbe72f6-c5e3-4e81-b91c-91dbf5a9dd15' and numero = 'PRO00119';

update public.facturas
set datos = jsonb_set(datos, '{fields,lineas}', '[{"descripcion":"Precio total del contrato CC00067","importe":"44000"}]'::jsonb)
where id = '0fbe72f6-c5e3-4e81-b91c-91dbf5a9dd15' and numero = 'PRO00119';
