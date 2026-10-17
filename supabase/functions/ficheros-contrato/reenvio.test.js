/* node reenvio.test.js — la regla de «Reenviar todas» (ficheros-contrato/reenvio.ts, mejora 5b, 17-oct-2026), con el .ts REAL
   (node ≥ 22.18 le quita los tipos), sin red. Qué fija (revisión previa Backend + Seguridad del 17-oct): solo se reenvía la
   ÚNICA firma pendiente si ya caducó; nunca con una firma a medias, un contrato bloqueado o liberado, un firmante que ya firmó
   o sin huella del documento; el documento tiene que casar con la huella; y el tope de todo el equipo. */
const assert = require('assert');
const path = require('path');
const { pathToFileURL } = require('url');

(async () => {
  const R = await import(pathToFileURL(path.join(__dirname, 'reenvio.ts')).href);
  let n = 0;
  const igual = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++; };
  const AHORA = Date.parse('2026-10-17T06:00:00Z');
  const H = 'a'.repeat(64);
  const C = { bloqueado: false, liberado_en: null };
  const fila = (o = {}) => Object.assign({ id: 'f1', estado: 'pendiente', expira_en: '2026-10-10T00:00:00Z', firmante_nombre: 'Ana',
    firmante_email: 'ana@ejemplo.com', firmante_rol: 'adquiriente_1', orden: 1, snapshot_hash: H }, o);
  const motivo = (c, filas) => { const d = R.decideReenvio(c, filas, AHORA); return d.ok ? 'ok:' + d.fila.id : d.motivo; };

  igual(motivo(C, [fila()]), 'ok:f1', 'caducada, única, con huella → se reenvía');
  igual(motivo(C, [fila({ estado: 'anulado', id: 'v' }), fila({ estado: 'firmado', id: 'x' }), fila({ id: 'f2', firmante_rol: 'adquiriente_2', orden: 2 })]),
    'ok:f2', 'cadena a medias (firmó el 1.º, caducó el del 2.º) sirve igual; las anuladas no estorban');
  igual(motivo(null, [fila()]), 'contrato_no_encontrado', 'sin contrato');
  igual(motivo({ bloqueado: true, liberado_en: null }, [fila()]), 'bloqueado', 'bloqueado');
  igual(motivo({ bloqueado: false, liberado_en: '2026-10-01T00:00:00Z' }, [fila()]), 'liberado', 'liberado (contrato_firma_estado no lo mira)');
  igual(motivo(C, [fila(), fila({ id: 'p', estado: 'procesando' })]), 'firma_a_medias', 'una firma a medias de estampar');
  igual(motivo(C, [fila({ estado: 'anulado' })]), 'sin_enlace_pendiente', 'nada pendiente (ya reenviado: la 2.ª llamada se para)');
  igual(motivo(C, [fila(), fila({ id: 'f2', firmante_rol: 'adquiriente_2' })]), 'varios_pendientes', 'dos pendientes');
  igual(motivo(C, [fila({ expira_en: '2026-10-20T00:00:00Z' })]), 'enlace_vivo', 'enlace aún vivo: nunca se anula');
  igual(motivo(C, [fila({ expira_en: null })]), 'enlace_vivo', 'sin caducidad: se trata como vivo');
  igual(motivo(C, [fila({ expira_en: 'mañana' })]), 'enlace_vivo', 'caducidad ilegible: se trata como vivo');
  igual(motivo(C, [fila({ estado: 'firmado', id: 'x' }), fila()]), 'ya_firmo', 'ese mismo rol ya firmó');
  igual(motivo(C, [fila({ snapshot_hash: null })]), 'sin_huella', 'enlace de antes del 26-sep, sin huella');
  igual(motivo(C, [fila({ snapshot_hash: 'ABC' })]), 'sin_huella', 'huella mal formada');
  igual(motivo(C, [fila({ firmante_email: 'no-es-email' })]), 'sin_email', 'email de la fila roto');
  igual(motivo(C, [fila({ firmante_rol: 'vendedor' })]), 'firmante_raro', 'rol que la RPC no acepta');
  igual(motivo(C, [fila({ orden: 0 })]), 'firmante_raro', 'orden que la RPC no acepta');

  igual(R.documentoCasa(H, fila()), true, 'el fijo casa con la huella');
  igual(R.documentoCasa('b'.repeat(64), fila()), false, 'el fijo cambió');
  igual(R.documentoCasa('', fila()), false, 'sin hash del fijo');
  igual(R.documentoCasa(H, fila({ snapshot_hash: null })), false, 'fila sin huella');

  igual(R.superaTope(R.TOPE_REENVIOS - 1), false, 'por debajo del tope');
  igual(R.superaTope(R.TOPE_REENVIOS), true, 'en el tope, se para');

  console.log('reenvio.test.js: ' + n + ' comprobaciones en verde');
})().catch((e) => { console.error(e); process.exit(1); });
