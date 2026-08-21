alter table public.contrato_eventos drop constraint contrato_eventos_evento_check;
alter table public.contrato_eventos add constraint contrato_eventos_evento_check
  check (evento = any (array[
    'creado','editado','tipo_cambiado','enviado_a_firma','firma_abierta','firma_recogida',
    'firma_anulada','firmado_del_todo','desbloqueado','traspaso',
    'editado_estando_firmado','factura_sin_bloquear','cobro_a_factura_huerfana',
    'cobro_a_otro_comprador','comprador_sin_ficha','factura_borrada','contrato_borrado'
  ]));

comment on constraint contrato_eventos_evento_check on public.contrato_eventos is
  'Lista cerrada de eventos. Al anadir uno nuevo en codigo hay que anadirlo AQUI: si no, la escritura falla y el sintoma aparece lejos de la causa (una edicion que no guarda, un cobro que no se aplica). Lo vigila tools/test.py via contracts/eventos.test.js.';;
