-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 1 (OK del owner 6-oct-2026) · G5-A: documentar el corte 2026-08-18 de hitos_sin_factura. Solo COMMENT, sin cambiar comportamiento.
comment on function public.hitos_sin_factura(date) is
  'Hitos vencidos sin factura de contratos firmados. Corte fijo 2026-08-18: día en que se activó la facturación automática a D-3 (cliente, 18-ago-2026); lo anterior es alta de histórico y se revisa aparte. Misma regla en el Home v4 (intranet/v4/assets/datos.js bandejaHoy). Si cambia, cambiar las dos.';
