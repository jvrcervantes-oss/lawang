-- destructivo-ok: UPDATE de UNA fila conocida por id (RP00116), con rastro
-- ANTES en correcciones_datos -- no es un update masivo ni sin WHERE.
--
-- El contrato guardaba parcela_codigo = "A5" (texto suelto de antes de
-- LAW-73, 21-ago-2026, cuando la parcela paso a salir siempre del
-- inventario) pero la relacion real (unidades.contrato_id) ya apuntaba
-- correctamente a W3.1 - D5 -- vinculada por otra via, probablemente desde
-- Proyectos, nunca desde este contrato. El propio contracts/assets/
-- parcela_inventario.js protege a proposito cualquier codigo "historico" que
-- no este en el inventario actual sin boton de quitar (no se puede reescribir
-- texto libre), asi que la UI nunca iba a dejar corregir esto sola.
--
-- Seguro: la firma de este contrato quedo ANULADA y nunca firmado_en (tabla
-- contrato_firmas, verificado antes de tocar nada) -- no hay ningun
-- documento ya entregado a la compradora que este corrigiendo en sitio.
--
-- Al hacer este UPDATE, el trigger sincroniza_unidad_contrato corre igual
-- que si se guardara desde la UI: suelta lo que ya no esta en la lista nueva
-- (nada, W3.1 - D5 es la unica unidad que tenia) y confirma que W3.1 - D5
-- sigue libre para este contrato (lo estaba, era ya suyo). Peticion del
-- owner (28-ago-2026).

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
where id = '4d235426-fbc6-470b-83a2-293a5f31aced' and numero = 'RP00116';;
