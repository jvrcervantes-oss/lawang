-- destructivo-ok: DROP de un CHECK constraint para reemplazarlo por uno mas
-- amplio (superset exacto + los 4 tipos que faltaban) -- no toca ni borra
-- ninguna fila, solo amplia la lista de valores permitidos en `tipo`. El
-- usuario pidio arreglar el 400 al guardar ("Fixealo") y el diagnostico ya
-- esta confirmado: 0 filas de ppjb_bonian/ppjb_bonian_c2/hak_sewa_notario/
-- carta_reserva_hak_sewa en la tabla pese a llevar la app "lista" desde el
-- 4-ago -- esta restriccion bloqueaba CUALQUIER guardado de esos tipos desde
-- que se crearon, no solo el C2 de hoy.
alter table public.contratos drop constraint contratos_tipo_check;
alter table public.contratos add constraint contratos_tipo_check
  check (tipo = any (array[
    'reserva_parcela', 'construccion', 'contrato_general', 'commercial_offer',
    'carta_reserva', 'carta_reserva_ampliada', 'acuerdo_comercial', 'protocolo_operativo',
    'ppjb_bonian', 'ppjb_bonian_c2', 'hak_sewa_notario', 'carta_reserva_hak_sewa'
  ]));;
