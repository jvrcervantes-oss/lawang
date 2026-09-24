-- destructivo-ok: se sustituye el CHECK de contrato_eventos.evento por uno que AMPLIA la lista (+factura_reactivada); no toca filas.
-- Evento nuevo del trigger factura_anulada_solo_cambia_autor (reactivar una
-- factura anulada no enviada, solo super_admin). Se ve en «Frenos saltados».
alter table public.contrato_eventos drop constraint contrato_eventos_evento_check;
alter table public.contrato_eventos add constraint contrato_eventos_evento_check check (evento = any (array[
  'creado','editado','tipo_cambiado','enviado_a_firma','firma_abierta','firma_recogida','firma_anulada',
  'firmado_del_todo','desbloqueado','traspaso','editado_estando_firmado','desbloqueado_estando_firmado',
  'factura_sin_bloquear','cobro_a_factura_huerfana','cobro_a_otro_comprador','comprador_sin_ficha',
  'factura_borrada','contrato_borrado','reserva_liberada','reserva_prorrogada','reserva_liberacion_deshecha',
  'pdf_descargado','factura_reactivada']::text[]));

create or replace view public.privilegios_ejercidos with (security_invoker = true) as
 select e.creado_en as cuando, e.quien, e.evento, c.numero as contrato, e.detalle
   from public.contrato_eventos e
   left join public.contratos c on c.id = e.contrato_id
  where e.evento = any (array['editado_estando_firmado','desbloqueado_estando_firmado','factura_sin_bloquear',
        'cobro_a_factura_huerfana','cobro_a_otro_comprador','comprador_sin_ficha','factura_reactivada']::text[])
union all
 select b.borrado_en as cuando, b.quien, 'borrado_'::text || b.tabla as evento, b.numero as contrato,
        jsonb_build_object('fila_id', b.fila_id) as detalle
   from public.borrados b;
