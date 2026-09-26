-- destructivo-ok: QUITA permisos de escritura directa (insert/update/delete) a anon/authenticated sobre solicitudes_pago y contrato_vencimientos; no borra ni cambia ninguna fila.
-- LAW-336 pieza 2 (cobros), 26-sep-2026. Las pantallas (v4, solicitudes/, vencimientos/) ya van
-- por solicitud_pago_guarda/_resuelve y vencimiento_ajusta_fecha (SECURITY DEFINER), y producción
-- sirve el JS nuevo (verificado por ?v=). Ninguna edge escribe en estas tablas; las funciones que
-- lo hacen son DEFINER o corren como service_role (factura_vencimiento_emite).
-- Verificado: facturas, solicitudes_pago y contrato_vencimientos quedan solo con SELECT para
-- authenticated y 0 columnas escribibles.
revoke insert, update, delete on public.solicitudes_pago, public.contrato_vencimientos from anon, authenticated;
