/* Comisión de administración (7-oct-2026): un abono cuyo devengo se anuló sin
   haberse cobrado (pendiente/exenta/facturada) no es un crédito, y la pantalla ya saca
   ese devengo de las sumas: contarlo lo restaba dos veces. Cuenta el abono sin
   origen conocido (falla hacia contar) o con origen facturado/cobrado: crédito real.
   `porId` = mapa id -> línea del libro. Pura: la prueba es comision-neto.test.js. */
function lwAbonoSinEfecto(l, porId) {
  if (!l || l.tipo_linea !== 'abono') return false;
  var o = porId && porId[l.linea_origen_id];
  return !!(o && o.anulada && (o.estado === 'pendiente' || o.estado === 'exenta' || o.estado === 'facturada'));
}
if (typeof module !== 'undefined' && module.exports) module.exports = { lwAbonoSinEfecto };
