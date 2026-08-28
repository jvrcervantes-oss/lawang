-- Ya aplicado en producción (28-ago-2026, aviso del owner: "el contrato
-- RP00116 está vinculado a A5, que está fuera de inventario. Necesito
-- quitarla y no puedo. La nueva vinculación debe ser: W3 D5"). Copia de
-- repo-de-registro, no se vuelve a ejecutar.
--
-- El contrato guardaba parcela_codigo = "A5" (texto suelto de antes de
-- LAW-73, 21-ago-2026, cuando la parcela pasó a salir siempre del
-- inventario) pero la relación real (unidades.contrato_id) ya apuntaba
-- correctamente a W3.1 - D5 -- vinculada por otra vía, probablemente desde
-- Proyectos, nunca desde este contrato. El propio contracts/assets/
-- parcela_inventario.js protege a propósito cualquier código "histórico" que
-- no esté en el inventario actual sin botón de quitar (no se puede
-- reescribir texto libre), así que la UI nunca iba a dejar corregir esto
-- sola -- por diseño, no por error.
--
-- Seguro de corregir en sitio: la firma de este contrato quedó ANULADA y
-- nunca `firmado_en` (tabla contrato_firmas, verificado antes de tocar
-- nada) -- no hay ningún documento ya entregado a la compradora que se esté
-- alterando.

insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
values (
  'contratos', '4d235426-fbc6-470b-83a2-293a5f31aced', 'datos.fields.parcela_codigo',
  'A5',
  'W3.1 - D5',
  'RP00116 imprimia "A5" (texto suelto de antes de LAW-73) aunque la relacion real (unidades.contrato_id) ya apuntaba a W3.1 - D5. Aviso del owner 28-ago-2026: "esta vinculado a A5, que esta fuera de inventario. Necesito quitarla y no puedo. La nueva vinculacion debe ser: W3 D5." Firma de este contrato anulada y nunca completada -- sin documento ya entregado que se este alterando.',
  'owner-28ago-via-CEO'
);

update public.contratos
set datos = jsonb_set(datos, '{fields,parcela_codigo}', '"W3.1 - D5"'::jsonb)
where id = '4d235426-fbc6-470b-83a2-293a5f31aced' and numero = 'RP00116';
