/* node plantillas_aviso_anulacion.test.js — AXW-202 C3 (5-oct-2026). Solo de Lawang (el maestro no tiene anulado_en en contrato_firmas y su
   `resuelve` contesta «no disponible»). Fija cómo `resuelve('aviso_anulacion')` elige variante y motivo cuando un mismo correo tiene firmas de
   VARIAS rondas de anulación: solo cuenta la más reciente, igual que el aviso que componía el navegador (que mira solo lo que acaba de anular). */
const assert = require('assert');
(async () => {
  const V = await import('./valida.ts');
  const F = await import('./plantillas_fabrica.ts');
  const CT = 'c0000000-0000-4000-8000-000000000001';
  const comun = { marca: 'Acme', portal: 'https://erp.ejemplo.com/portal/', dominio: 'ejemplo.com' };
  const rest = (firmas) => async (ruta) => {
    if (ruta.startsWith('contratos?')) return [{ numero: 'CR00001' }];
    if (ruta.startsWith('contrato_firmas?')) return firmas;
    throw new Error('consulta inesperada ' + ruta);
  };
  const fila = (o) => ({ firmante_nombre: 'Ana Pérez', firmante_email: 'ana@cliente.test', firmado_en: null, anulado_en: null, anulado_motivo: 'editar', anulado_justificacion: null, ...o });
  const pide = async (firmas, to = 'ana@cliente.test') => F.resuelve('aviso_anulacion', { contrato_id: CT, factura_id: '', firma_id: '' }, to, {}, rest(firmas), comun);
  let n = 0;
  const ok = (c, m) => { assert.ok(c, m); n++; };

  // 1. una sola ronda: firmó → variante «alt» con su motivo; no firmó → principal sin motivo (el caso de siempre)
  let r = await pide([fila({ firmado_en: '2026-10-01T10:00:00+00:00', anulado_en: '2026-10-05T09:00:00+00:00', anulado_justificacion: 'cambia el precio' })]);
  ok(!V.esFallo(r) && r.variante === 'alt' && r.vars.bloque_motivo === 'Motivo: cambia el precio\n\n', 'firmó y se anuló: alt con motivo');
  r = await pide([fila({ anulado_en: '2026-10-05T09:00:00+00:00' })]);
  ok(!V.esFallo(r) && r.variante === 'principal' && r.vars.bloque_motivo === '', 'no había firmado: principal sin motivo');

  // 2. DOS rondas: firmó en la primera (anulada), en la segunda NO firmó → la segunda manda: principal, sin el motivo viejo
  r = await pide([
    fila({ firmado_en: '2026-10-01T10:00:00+00:00', anulado_en: '2026-10-02T09:00:00+00:00', anulado_justificacion: 'motivo de la primera ronda' }),
    fila({ anulado_en: '2026-10-05T09:00:00+00:00' }),
  ]);
  ok(!V.esFallo(r) && r.variante === 'principal' && r.vars.bloque_motivo === '', 'ronda anterior firmada, ronda actual sin firmar: NO arrastra el motivo viejo');
  // y al revés: la ronda actual sí firmó y la anterior no → alt con el motivo de la actual
  r = await pide([
    fila({ anulado_en: '2026-10-02T09:00:00+00:00' }),
    fila({ firmado_en: '2026-10-04T10:00:00+00:00', anulado_en: '2026-10-05T09:00:00+00:00', anulado_justificacion: 'motivo actual' }),
  ]);
  ok(!V.esFallo(r) && r.variante === 'alt' && r.vars.bloque_motivo === 'Motivo: motivo actual\n\n', 'ronda actual firmada: su motivo');
  // 3. dos firmas del MISMO correo en la misma anulación (dos roles del comprador): si una firmó, cuenta como firmado (como el navegador)
  r = await pide([
    fila({ anulado_en: '2026-10-05T09:00:00+00:00' }),
    fila({ firmado_en: '2026-10-04T10:00:00+00:00', anulado_en: '2026-10-05T09:00:00+00:00', anulado_justificacion: 'x'.repeat(12) }),
  ]);
  ok(!V.esFallo(r) && r.variante === 'alt', 'dos roles del mismo correo en la misma anulación: si uno firmó, alt');
  // 3b. una anulación POSTERIOR por otro motivo (nuevo_enlace) no cambia el aviso de la edición
  r = await pide([
    fila({ firmado_en: '2026-10-04T10:00:00+00:00', anulado_en: '2026-10-05T09:00:00+00:00', anulado_motivo: 'editar', anulado_justificacion: 'motivo real' }),
    fila({ anulado_en: '2026-10-05T11:00:00+00:00', anulado_motivo: 'nuevo_enlace' }),
  ]);
  ok(!V.esFallo(r) && r.variante === 'alt' && r.vars.bloque_motivo === 'Motivo: motivo real

', 'una anulación posterior por nuevo_enlace no pisa el aviso de «editar»');
  // 4. una firma viva (no anulada) del mismo correo no cuenta; sin ninguna anulada → 400
  r = await pide([fila({ firmado_en: '2026-10-01T10:00:00+00:00' })]);
  ok(V.esFallo(r) && r.status === 400, 'sin firma anulada: 400');
  // 5. el destinatario tiene que ser un firmante del contrato
  r = await pide([fila({ anulado_en: '2026-10-05T09:00:00+00:00' })], 'otro@cliente.test');
  ok(V.esFallo(r) && r.status === 400, 'destinatario ajeno: 400');
  console.log('OK plantillas_aviso_anulacion.test.js — ' + n + ' comprobaciones (una ronda, dos rondas en los dos sentidos, mismo correo en la misma anulación, sin anulada, destinatario ajeno)');
})().catch((e) => { console.error(e); process.exit(1); });
