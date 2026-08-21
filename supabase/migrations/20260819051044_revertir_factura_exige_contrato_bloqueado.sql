-- Revertido el mismo dia por el owner: hay que poder facturar contratos no
-- bloqueados. Se quitan el trigger y su funcion; las facturas vuelven a poder
-- emitirse sobre cualquier contrato, como antes del 19-ago-2026.
drop trigger if exists trg_factura_exige_contrato_bloqueado on public.facturas;
drop function if exists public.trg_factura_exige_contrato_bloqueado();;
