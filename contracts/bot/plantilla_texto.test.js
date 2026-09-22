/* Test de plantillaTexto. `node plantilla_texto.test.js`.
   1. Paridad byte a byte con las DOS copias de la edge (contracts/edge y
      supabase/functions) — mismo motivo que postcheck.test.js.
   2. Sobre las plantillas REALES del repo: sale un solo idioma, los artículos
      se pueden citar, un campo vacío es «(en blanco)», uno reservado nunca
      enseña su valor, y no queda HTML ni marcadores. */
const fs = require('fs');
const path = require('path');
const { plantillaTexto } = require('./plantilla_texto.js');

let fallos = 0;
function ok(cond, msg) { if (!cond) { fallos++; console.error('  FALLA  ' + msg); } }

const aqui = path.dirname(__filename);
function bloque(fichero) {
  const txt = fs.readFileSync(fichero, 'utf8');
  const a = txt.indexOf('// >>> plantillaTexto');
  const b = txt.indexOf('// <<< plantillaTexto');
  if (a < 0 || b < 0 || b < a) return null;
  return txt.slice(a, b + '// <<< plantillaTexto'.length);
}
const bJs = bloque(path.join(aqui, 'plantilla_texto.js'));
for (const f of [
  path.join(aqui, '..', 'edge', 'bot-agentes', 'index.ts'),
  path.join(aqui, '..', '..', 'supabase', 'functions', 'bot-agentes', 'index.ts'),
]) {
  const b = bloque(f);
  ok(b, f + ' no tiene los marcadores >>> plantillaTexto / <<< plantillaTexto');
  ok(b === bJs, f + ': plantillaTexto difiere de plantilla_texto.js');
}

const RESERVADO = /pasaporte|nik|email|telefono|domicilio|direccion|edad|ocupacion|npwp|nib|registro|nacionalidad|firma_adquiriente|^firmante$|titular|client_id|cuenta|apoderado|propietario|rep_/i;
const esReservado = (k) => RESERVADO.test(k);
const T = (n) => fs.readFileSync(path.join(aqui, '..', 'templates', n), 'utf8');

// ── construcción, ES, plazo vacío ──────────────────────────────────────────
const cons = plantillaTexto(T('ppjb_construccion.html'), 'es', {
  adq1_nombre: 'COMPRADOR DE PRUEBA', adq1_pasaporte: 'X1234567', plazo_meses: '', precio_total: '66.000', moneda: 'EUR',
  tipologia_construccion: 'Dune', adq1_tipo: 'persona', prom_razon: 'PT PRUEBA', fecha_firma: '2026-09-21',
}, esReservado);
ok(cons.includes('Artículo 6 — Plazo de ejecución'), 'construcción: falta el título del Art. 6');
ok(cons.includes('es de (en blanco) meses naturales'), 'construcción: plazo vacío no sale como (en blanco)');
ok(cons.includes('Artículo 7 — Prórroga del plazo') && cons.includes('máximo de 6 meses'), 'construcción: falta el Art. 7');
ok(cons.includes('COMPRADOR DE PRUEBA'), 'construcción: no sustituye adq1_nombre');
ok(!cons.includes('X1234567') && cons.includes('(dato reservado)'), 'construcción: un campo reservado enseña su valor');
ok(!/Execution term|Article 6|Pasal 6/.test(cons), 'construcción: se cuela otro idioma');
ok(!cons.includes('{{') && !cons.includes('<'), 'construcción: quedan marcadores o HTML');
ok(!cons.includes('<!--'), 'construcción: quedan comentarios');

// ── parcela, ES: régimen y renovación citables ─────────────────────────────
// modalidad_pago decide qué bloque <!--if:--> de pagos y de escrow entra (RP00194 es «reserva»)
const parc = plantillaTexto(T('ppjb_parcela.html'), 'es', { regimen_tenencia: 'leasehold', modalidad_pago: 'reserva', plazo_pago_final_dias: '30', plazo_pago_final_meses: '' }, esReservado);
ok(parc.includes('30+30+30'), 'parcela: falta el 30+30+30 del Art. 2');
ok(parc.includes('podrá renovarse conforme a la legislación vigente'), 'parcela: falta la cláusula de renovación');
ok(parc.includes('30 días') && !parc.includes('(en blanco) meses'), 'parcela: <!--opt:--> no respeta el campo vacío/lleno');
ok(parc.includes('cuenta ESCROW del notario'), 'parcela: falta la cláusula de escrow');

// ── inglés ─────────────────────────────────────────────────────────────────
const en = plantillaTexto(T('ppjb_construccion.html'), 'en', { plazo_meses: '8' }, esReservado);
ok(en.includes('Article 6 — Execution term') && en.includes('is 8 calendar months'), 'inglés: no sale el Art. 6 en inglés');
ok(!en.includes('Artículo 6'), 'inglés: se cuela el español');

// ── <!--if:k=v--> ──────────────────────────────────────────────────────────
const conDto = plantillaTexto(T('ppjb_construccion.html'), 'es', { descuento_comercial_aplica: 'si', precio_lista_construccion: '68.000', descuento_comercial: '2.000', descuento_comercial_motivo: 'prueba', precio_total: '66.000', moneda: 'EUR' }, esReservado);
ok(conDto.includes('aplicado un descuento comercial de 2.000 EUR (prueba)'), 'if: no entra el bloque cuando el campo vale eso');
const sinDto = plantillaTexto(T('ppjb_construccion.html'), 'es', { precio_total: '66.000', moneda: 'EUR' }, esReservado);
ok(!sinDto.includes('descuento comercial de'), 'if: entra el bloque cuando el campo no vale eso');

if (fallos) { console.error('plantilla_texto.test.js: ' + fallos + ' fallo(s)'); process.exit(1); }
console.log('OK plantilla_texto.test.js — paridad con las dos copias de la edge + plantillas reales ES/EN');
