/* node avisos.test.js — la campana (23-sep-2026, S17).
   1) Lo que decide `lwAvisosArmar` (avisos.js), que comparten la campana de las
      herramientas clásicas (topbar.js) y la de la intranet v4 (datos.js).
   2) Que toda página que carga topbar.js cargue también avisos.js: sin él la
      campana se queda muda sin ningún error visible. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
// el formateador REAL de la suite, como en el navegador (avisos.js lo usa si está)
global.lwFormatoImporte = require('./dinero.js').lwFormatoImporte;
const { lwAvisosArmar, lwAvisoEnlace } = require('./avisos.js');

const AHORA = '2026-09-23T12:00:00Z';
const dia = n => new Date(Date.parse(AHORA) + n * 86400000).toISOString().slice(0, 10);
const ok = data => ({ data, error: null });
const yo = 'agente@lawang.test';

// --- enlaces: solo rutas del propio dominio ---
assert.strictEqual(lwAvisoEnlace('/intranet/operaciones/?contrato=1'), '/intranet/operaciones/?contrato=1');
assert.strictEqual(lwAvisoEnlace('javascript:alert(1)'), '#');
assert.strictEqual(lwAvisoEnlace('//evil.example/x'), '#');
assert.strictEqual(lwAvisoEnlace('/\\evil.example'), '#');
assert.strictEqual(lwAvisoEnlace('https://evil.example'), '#');
assert.strictEqual(lwAvisoEnlace(null), '#');

const r = [
  ok([
    { titulo: 'Nuevo', enlace: 'javascript:x', creado_en: '2026-09-23T10:00:00Z' },
    { titulo: 'Visto', enlace: '/intranet/', creado_en: '2026-09-01T10:00:00Z' },
  ]),
  ok([
    { id: 'f1', numero: 'F1', total: 100, moneda: 'EUR', contrato_id: 'c1', creado_por: yo, tipo: 'factura', venc: dia(-3) },
    { id: 'f2', numero: 'F2', total: 100, moneda: 'EUR', contrato_id: 'c2', creado_por: 'otro@lawang.test', tipo: 'factura', venc: dia(-3) },
    { id: 'f3', numero: 'F3', total: 100, moneda: 'EUR', contrato_id: 'c3', creado_por: null, tipo: 'factura', venc: dia(-3) },
    { id: 'f4', numero: 'F4', total: 100, moneda: 'EUR', contrato_id: 'c4', creado_por: yo, tipo: 'factura', venc: dia(2) },   // cobrada
    { id: 'f5', numero: 'F5', total: 100, moneda: 'EUR', contrato_id: 'c5', creado_por: yo, tipo: 'proforma', venc: dia(1) },
    { id: 'f6', numero: 'F6', total: 100, moneda: 'EUR', contrato_id: 'c6', creado_por: yo, tipo: 'factura', venc: dia(30) }, // lejos
    { id: 'f7', numero: 'F7', total: 100, moneda: 'EUR', contrato_id: 'c7', creado_por: yo, tipo: 'factura', venc: dia(10), anulada: true },
    { id: 'f8', numero: 'F8', total: 100, moneda: 'EUR', contrato_id: 'c8', creado_por: yo, tipo: 'factura', venc: dia(10) },
  ]),
  ok([
    { firmante_nombre: 'Ana', expira_en: dia(1), contrato_id: 'c9', contratos: { numero: 'RP9', creado_por: yo } },
    { firmante_nombre: 'Bea', expira_en: dia(1), contrato_id: 'c10', contratos: { numero: 'RP10', creado_por: 'otro@lawang.test' } },
  ]),
  ok([{ factura_id: 'f4', pendiente: 0 }]),
];

// --- quién ve qué lo decide la RLS, no el armado (LAW-276, 23-sep-2026) ---
// Con un manager, la RLS le devuelve también facturas/firmas de su equipo: el
// armado ya NO las filtra por autor (antes le escondía las de su equipo).
const ag = lwAvisosArmar(r, { esAdmin: false, email: yo, vistoHasta: '2026-09-20T00:00:00Z', ahora: AHORA });
const t = ag.avisos.map(a => a.titulo);
assert.ok(t.includes('Factura F1 vencida hace 3 d'), t);
assert.ok(t.some(x => /F2/.test(x)) && t.some(x => /RP10/.test(x)), 'lo que la RLS deja leer (su equipo) se avisa: ' + t);
assert.ok(!t.some(x => /F4/.test(x)), 'factura ya cobrada fuera');
assert.ok(!t.some(x => /F5|F6|F7/.test(x)), 'proforma, lejana y anulada fuera');
assert.ok(t.includes('Factura F8 vence en 10 d'));
assert.ok(t.includes('Enlace de firma de RP9 caduca en 1 d'));
// hechos: nuevo por vistoHasta; alertas: nuevo por d<=5 (F8 a 10 días no lo es)
const nuevos = ag.avisos.filter(a => a.nuevo).map(a => a.titulo).sort();
assert.deepStrictEqual(nuevos, ['Enlace de firma de RP10 caduca en 1 d', 'Enlace de firma de RP9 caduca en 1 d', 'Factura F1 vencida hace 3 d', 'Factura F2 vencida hace 3 d', 'Factura F3 vencida hace 3 d', 'Nuevo']);
assert.strictEqual(ag.sinLeer, 6);
assert.strictEqual(ag.avisos.find(a => a.titulo === 'Nuevo').enlace, '#', 'enlace javascript: neutralizado');

// --- tono de cada aviso (colores de la campana, 23-sep-2026) ---
const tono = x => ag.avisos.find(a => a.titulo === x);
assert.deepStrictEqual([tono('Factura F1 vencida hace 3 d').nivel, tono('Factura F1 vencida hace 3 d').etiqueta, tono('Factura F1 vencida hace 3 d').clase], ['mal', 'Vencida', 'alerta']);
assert.deepStrictEqual([tono('Factura F8 vence en 10 d').nivel, tono('Factura F8 vence en 10 d').etiqueta], ['atencion', 'Por vencer']);
assert.deepStrictEqual([tono('Enlace de firma de RP9 caduca en 1 d').nivel, tono('Enlace de firma de RP9 caduca en 1 d').etiqueta], ['atencion', 'Firma por caducar']);
assert.strictEqual(tono('Nuevo').clase, 'hecho');
const { lwAvisoTonoHecho } = require('./avisos.js');
assert.deepStrictEqual(lwAvisoTonoHecho('contrato_firmado'), ['ok', 'Firmado']);
assert.deepStrictEqual(lwAvisoTonoHecho('factura_emitida'), ['neutro', 'Emitida'], 'emitida: gris, como en listados y fichas');
assert.deepStrictEqual(lwAvisoTonoHecho('firma_enviada'), ['neutro', 'Firma enviada'], 'un hecho es una foto: no afirma «en firma» después de firmado');
assert.deepStrictEqual(lwAvisoTonoHecho('unidad_reservada'), ['neutro', 'Inventario']);
assert.deepStrictEqual(lwAvisoTonoHecho('solicitud_pago', 'Tu solicitud SP-2 — rechazada'), ['mal', 'Rechazada']);
assert.deepStrictEqual(lwAvisoTonoHecho('solicitud_pago', 'Tu solicitud SP-2 — pagada'), ['ok', 'Pagada']);
assert.deepStrictEqual(lwAvisoTonoHecho('solicitud_pago', 'Solicitud de pago SP-8'), ['neutro', 'Solicitud'], 'no dice «pendiente» de algo que quizá ya se pagó');
assert.deepStrictEqual(lwAvisoTonoHecho('solicitud_pago', 'Tu solicitud SP-2 — aprobada'), ['atencion', 'Aprobada'], 'aprobada no es pagada');
assert.deepStrictEqual(lwAvisoTonoHecho('tipo_nuevo_que_no_existe'), ['neutro', 'tipo nuevo que no existe'], 'un tipo sin clasificar no desaparece');

// --- una vez por suceso: copias por manager y aviso general de parcela (23-sep-2026) ---
const T0 = '2026-09-21T07:43:54.845606+00:00';
const copias = lwAvisosArmar([ok([
  { tipo: 'unidad_disponible', titulo: 'Parcela C4 vuelve a estar disponible', destinatario: null, creado_en: T0 },
  { tipo: 'unidad_estado', titulo: 'Unidad C4 — disponible', destinatario: 'm1@x', creado_en: T0 },
  { tipo: 'unidad_estado', titulo: 'Unidad C4 — disponible', destinatario: 'm2@x', creado_en: T0 },
  { tipo: 'unidad_estado', titulo: 'Unidad C4 — disponible', destinatario: 'm3@x', creado_en: T0 },
  { tipo: 'reserva_por_vencer', titulo: 'Reserva CR00025 vence mañana', destinatario: 'm1@x', creado_en: '2026-09-23T04:00:04.124956+00:00' },
  { tipo: 'reserva_por_vencer', titulo: 'Reserva CR00025 vence mañana', destinatario: 'm1@x', creado_en: '2026-09-23T04:00:04.167858+00:00' },
  { tipo: 'reserva_por_vencer', titulo: 'Reserva CR00025 vence mañana', destinatario: 'm2@x', creado_en: '2026-09-23T04:00:04.207311+00:00' },
  { tipo: 'unidad_estado', titulo: 'Unidad A3 — reservada', destinatario: 'm1@x', creado_en: '2026-09-15T11:13:52+00:00' },
  { tipo: 'unidad_estado', titulo: 'Unidad A3 — reservada', destinatario: 'm1@x', creado_en: '2026-09-16T09:00:00+00:00' },
]), ok([]), ok([]), ok([])], { esAdmin: true, email: 'jefe@x', ahora: AHORA });
const tc = copias.avisos.map(a => a.titulo).sort();
assert.deepStrictEqual(tc, ['Parcela C4 vuelve a estar disponible', 'Reserva CR00025 vence mañana', 'Unidad A3 — reservada', 'Unidad A3 — reservada'],
  'un cambio de parcela = 1 aviso; 3 copias de la reserva = 1; dos cambios reales en días distintos siguen siendo 2: ' + tc.join(' | '));
// misma transacción, OTRA parcela: C4 pasa a disponible (con aviso general) y C2 a no_disponible
// (sin aviso general) en el mismo segundo — la copia de C2 NO se esconde
const mismaTx = lwAvisosArmar([ok([
  { tipo: 'unidad_disponible', titulo: 'Parcela C4 vuelve a estar disponible', destinatario: null, creado_en: T0 },
  { tipo: 'unidad_estado', titulo: 'Unidad C4 — disponible', destinatario: 'm1@x', creado_en: T0 },
  { tipo: 'unidad_estado', titulo: 'Unidad C2 — no_disponible', destinatario: 'm1@x', creado_en: T0 },
]), ok([]), ok([]), ok([])], { esAdmin: true, email: 'jefe@x', ahora: AHORA });
assert.deepStrictEqual(mismaTx.avisos.map(a => a.titulo).sort(), ['Parcela C4 vuelve a estar disponible', 'Unidad C2 — no_disponible'],
  'la copia de otra parcela del mismo segundo no desaparece');
// «Tu solicitud …» de OTRO: el admin no lo lee como suyo, y se funde con la copia de managers
const T1 = '2026-09-23T04:22:57.185563+00:00';
const rech = lwAvisosArmar([ok([
  { tipo: 'solicitud_pago', titulo: 'Tu solicitud SP-8 — rechazada', destinatario: 'agente@x', creado_en: T1 },
  { tipo: 'solicitud_pago', titulo: 'Solicitud SP-8 — rechazada', destinatario: 'm1@x', creado_en: T1 },
  { tipo: 'solicitud_pago', titulo: 'Solicitud SP-8 — rechazada', destinatario: 'm2@x', creado_en: T1 },
  { tipo: 'solicitud_pago', titulo: 'Tu solicitud SP-9 — pagada', destinatario: 'agente@x', creado_en: T1 },
]), ok([]), ok([]), ok([])], { esAdmin: true, email: 'jefe@x', ahora: AHORA });
assert.deepStrictEqual(rech.avisos.map(a => a.titulo).sort(), ['Solicitud SP-8 — rechazada', 'Solicitud SP-9 — pagada'],
  'sin «Tu» para quien no es el destinatario, y una vez por suceso');
const suya = lwAvisosArmar([ok([{ tipo: 'solicitud_pago', titulo: 'Tu solicitud SP-8 — rechazada', destinatario: 'agente@x', creado_en: T1 }]), ok([]), ok([]), ok([])],
  { esAdmin: false, email: 'Agente@x', ahora: AHORA });
assert.strictEqual(suya.avisos[0].titulo, 'Tu solicitud SP-8 — rechazada', 'al propio agente sí le dice «Tu»');
// un manager ve SU copia aunque exista el aviso general (la base solo le da la suya)
const mgr = lwAvisosArmar([ok([
  { tipo: 'unidad_disponible', titulo: 'Parcela C4 vuelve a estar disponible', destinatario: null, creado_en: T0 },
  { tipo: 'unidad_estado', titulo: 'Unidad C4 — disponible', destinatario: 'm1@x', creado_en: T0 },
]), ok([]), ok([]), ok([])], { esAdmin: false, email: 'M1@x', ahora: AHORA });
assert.ok(mgr.avisos.some(a => a.titulo === 'Unidad C4 — disponible'), 'la copia dirigida a quien mira no se oculta');

// --- admin: ve las de todos ---
const ad = lwAvisosArmar(r, { esAdmin: true, email: 'jefe@lawang.test', ahora: AHORA });
const ta = ad.avisos.map(a => a.titulo);
assert.ok(ta.some(x => /F2/.test(x)) && ta.some(x => /F3/.test(x)) && ta.some(x => /RP10/.test(x)), ta);
// sin vistoHasta todo hecho es nuevo
assert.ok(ad.avisos.find(a => a.titulo === 'Visto').nuevo);

// --- una consulta con error no rompe las demás ---
const conFallo = lwAvisosArmar([{ data: null, error: { message: 'x' } }, r[1], r[2], r[3]], { esAdmin: false, email: yo, ahora: AHORA });
assert.ok(conFallo.avisos.length > 0);

// --- sin lo cobrado NO se avisa de facturas (con el total como pendiente, lo ya pagado salía «sin cobrar») ---
const sinCobro = lwAvisosArmar([r[0], r[1], r[2], { data: null, error: { message: 'rpc caída' } }], { esAdmin: true, email: yo, ahora: AHORA });
assert.ok(!sinCobro.avisos.some(a => /^Factura/.test(a.titulo)), 'sin rpc de cobrado, ninguna factura');
assert.ok(sinCobro.avisos.some(a => /^Enlace de firma/.test(a.titulo)), 'las firmas no dependen de lo cobrado');
assert.strictEqual(sinCobro.cobroSinComprobar, true);
assert.strictEqual(ag.cobroSinComprobar, false);

// --- el detalle dice lo que QUEDA, no el total (pago a cuenta) ---
const parcial = lwAvisosArmar([ok([]), ok([{ id: 'p1', numero: 'P1', total: 1000, moneda: 'EUR', creado_por: yo, tipo: 'factura', venc: dia(1) }]), ok([]), ok([{ factura_id: 'p1', pendiente: 250.5 }])], { esAdmin: false, email: yo, ahora: AHORA });
assert.strictEqual(parcial.avisos[0].detalle, '250,50 EUR sin cobrar');
const miles = lwAvisosArmar([ok([]), ok([{ id: 'm1', numero: 'M1', total: 1500, moneda: 'EUR', tipo: 'factura', venc: dia(1) }]), ok([]), ok([])], { ahora: AHORA });
assert.strictEqual(miles.avisos[0].detalle, '1.500,00 EUR sin cobrar', 'miles también con 4 cifras');
const grande = lwAvisosArmar([ok([]), ok([{ id: 'g1', numero: 'G1', total: 200000000, moneda: 'IDR', tipo: 'factura', venc: dia(1) }]), ok([]), ok([])], { ahora: AHORA });
assert.strictEqual(grande.avisos[0].detalle, '200.000.000 IDR sin cobrar', 'importe con separador de miles');

// --- enlaces con blancos o controles dentro: el navegador los quita y «/\t/x» sería «//x» ---
assert.strictEqual(lwAvisoEnlace('/\t/evil.example'), '#');
assert.strictEqual(lwAvisoEnlace('/\n/evil.example'), '#');
assert.strictEqual(lwAvisoEnlace('/intranet/ x'), '#');

// --- toda página con topbar.js carga avisos.js ---
const RAIZ = path.resolve(__dirname, '..', '..');
const SALTA = /(^|[\\/])(Backups|node_modules|\.git|_archive)([\\/]|$)/;
const faltan = [];
(function recorre(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (SALTA.test(p) || e.name.startsWith('_')) continue;   // _qa_*, _verify_*, _diag_*: pruebas locales
    if (e.isDirectory()) recorre(p);
    else if (/\.(html|php)$/.test(e.name)) {
      const s = fs.readFileSync(p, 'utf8');
      if (/<script[^>]+src="[^"]*assets\/topbar\.js/.test(s) && !/<script[^>]+src="[^"]*assets\/avisos\.js/.test(s)) faltan.push(path.relative(RAIZ, p));
    }
  }
})(RAIZ);
assert.deepStrictEqual(faltan, [], 'páginas con topbar.js sin avisos.js (campana muda): ' + faltan.join(', '));

console.log('avisos.test.js OK');
