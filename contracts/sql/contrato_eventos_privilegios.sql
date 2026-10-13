-- SIN APLICAR (13-oct-2026). Lo aplica el owner: lleva DROP CONSTRAINT y no_destruir.py exige su marca
-- ~/.axisworks/destructivo-ok, abierta desde SU terminal. Fila en contexto/pendientes.md de la agencia.
-- Cuando se aplique, pasa a supabase/migrations/ con la versión que le dé apply_migration (y supabase_fetch_seguro.py).
--
-- Qué arregla. registra_privilegio() deja el rastro de una salida del super_admin en contrato_eventos, pero la CHECK
-- contrato_eventos_evento_check no admite estos tres eventos:
--   · 'factura_sobre_tope'         — _factura_tope_cadena, desde 20261005210000 (5-oct).
--   · 'documento_sobre_hak_sewa'   — _factura_moneda_valida, 20261013074408 (LAW-553).
--   · 'cambia_venta_con_facturas'  — trg_contrato_moneda_con_documentos, 20261013074408 (LAW-553).
--   Y desde 20261013081849 también usa 'factura_sobre_tope' factura_reactiva (reactivar una factura por encima del tope).
-- Resultado hoy (medido el 13-oct, supabase/pruebas/factura_moneda_del_contrato.sql casos g3-g5 en PENDIENTE): la
-- salida del super_admin revienta con «violates check constraint contrato_eventos_evento_check». Falla CERRADA: nadie
-- se salta el tope ni la moneda, tampoco el super_admin. 0 filas con esos eventos en contrato_eventos.
--
-- Qué NO cambia: ningún dato. Es la misma lista de 25 eventos vivos (pg_get_constraintdef, 13-oct) más los tres.
--
-- Vuelta atrás: la misma operación con la lista sin los tres (solo si no hay filas con ellos; si las hay, no se vuelve).

-- Un solo ALTER TABLE (revisión de código, 13-oct): DROP y ADD van en la misma sentencia, así no hay ningún instante
-- (ni un fallo a medias fuera de transacción) en que contrato_eventos quede sin CHECK.
alter table public.contrato_eventos
  drop constraint contrato_eventos_evento_check,
  add constraint contrato_eventos_evento_check check (evento = any (array[
  'creado', 'editado', 'tipo_cambiado', 'enviado_a_firma', 'firma_abierta', 'firma_recogida', 'firma_anulada',
  'firmado_del_todo', 'desbloqueado', 'traspaso', 'editado_estando_firmado', 'desbloqueado_estando_firmado',
  'factura_sin_bloquear', 'cobro_a_factura_huerfana', 'cobro_a_otro_comprador', 'comprador_sin_ficha',
  'factura_borrada', 'contrato_borrado', 'reserva_liberada', 'reserva_prorrogada', 'reserva_liberacion_deshecha',
  'pdf_descargado', 'factura_reactivada', 'anexos_al_archivo', 'envio_sin_anexo_confirmado',
  'factura_sobre_tope', 'documento_sobre_hak_sewa', 'cambia_venta_con_facturas'
]::text[]));
