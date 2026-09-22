/* Test del post-chequeo del bot de apoyo a agentes. `node postcheck.test.js`.
   ============================================================================
   Tres cosas, y las tres son "el mismo dato en dos sitios que no pueden
   separarse", que es la familia de fallo cara de este estudio:

   1. La función postCheck de postcheck.js es BYTE A BYTE la misma que la que
      lleva la Edge Function (contracts/edge/bot-agentes/index.ts, entre los
      marcadores `// >>> postCheck` y `// <<< postCheck`). Si alguien afina el
      freno en un sitio y no en el otro, esto falla.
   2. La copia de despliegue supabase/functions/bot-agentes/index.ts es idéntica
      a contracts/edge/bot-agentes/index.ts. En este checkout Windows no es un
      symlink (LAW-238, 17-sep-2026): es un fichero real que nadie sincroniza
      solo, y `empaqueta_edge.py --check` solo cubre las dos edges de facturas.
   3. Los casos del freno: cifra ajena → descartado · cifra del contexto → pasa
      · patron_salida → descartado · patron_salida roto → descartado (fail
      closed) · separadores de miles y agrupación no engañan al freno. */
const fs = require('fs');
const path = require('path');
const { postCheck } = require('./postcheck.js');

let fallos = 0;
function ok(cond, msg) {
  if (!cond) { fallos++; console.error('  FALLA  ' + msg); }
}

// ── 1. paridad de la función con la edge ──────────────────────────────────
function bloque(fichero) {
  const txt = fs.readFileSync(fichero, 'utf8');
  const a = txt.indexOf('// >>> postCheck');
  const b = txt.indexOf('// <<< postCheck');
  if (a < 0 || b < 0 || b < a) return null;
  return txt.slice(a, b + '// <<< postCheck'.length);
}
const aqui = path.dirname(__filename);
const EDGE = path.join(aqui, '..', 'edge', 'bot-agentes', 'index.ts');
const DEPLOY = path.join(aqui, '..', '..', 'supabase', 'functions', 'bot-agentes', 'index.ts');
const bJs = bloque(path.join(aqui, 'postcheck.js'));
const bEdge = bloque(EDGE);
ok(bJs, 'postcheck.js no tiene los marcadores >>> postCheck / <<< postCheck');
ok(bEdge, 'contracts/edge/bot-agentes/index.ts no tiene los marcadores >>> postCheck / <<< postCheck');
ok(bJs && bEdge && bJs === bEdge, 'postCheck difiere entre postcheck.js y la edge: el freno que se prueba aquí no es el que corre');

// ── 2. copia de despliegue idéntica ───────────────────────────────────────
ok(fs.existsSync(DEPLOY), 'falta la copia de despliegue supabase/functions/bot-agentes/index.ts');
if (fs.existsSync(DEPLOY)) {
  ok(fs.readFileSync(DEPLOY, 'utf8') === fs.readFileSync(EDGE, 'utf8'),
    'supabase/functions/bot-agentes/index.ts no es idéntico a contracts/edge/bot-agentes/index.ts (LAW-238)');
}

// ── 3. el freno ───────────────────────────────────────────────────────────
const contexto = JSON.stringify({
  contrato: { numero: 'CC00107', precio_total: 1500000000, moneda: 'IDR', fecha_firma: '2026-05-14',
    hitos: [{ es: 'Firma', pct: 30, monto: 450000000 }, { es: 'Cubierta', pct: 40, monto: 600000000 }] },
  cuenta_asignada: { titular: 'PT Sandal Woods', banco: 'BCA' },
});
const bloqueos = [
  { patron: 'cuenta', patron_salida: 'n[uú]mero de cuenta|\\biban\\b|account number', motivo: 'Destino del pago: pendiente.' },
  { patron: 'retenci', patron_salida: '(aceptamos|we accept).{0,60}(retenci|retention)', motivo: 'Retención: contraoferta.' },
  { patron: 'entrega', patron_salida: null, motivo: 'Sin patrón de salida.' },
];

// cifra ajena de 10 dígitos → descartado
let r = postCheck('Puedes transferir a la cuenta 1234567890 del promotor.', contexto, bloqueos);
ok(!r.ok && r.motivo === 'cifra_ajena_al_contexto', 'una cifra de 10 dígitos ajena al contexto tiene que descartar el borrador');

// la misma cifra pero PARTIDA con espacios o puntos → sigue siendo ajena
r = postCheck('Cuenta: 1234 5678 90.', contexto, bloqueos);
ok(!r.ok && r.motivo === 'cifra_ajena_al_contexto', 'una cifra ajena agrupada con espacios (1234 5678 90) tiene que descartar');
r = postCheck('Importe: 9.876.543.210 IDR.', contexto, bloqueos);
ok(!r.ok && r.motivo === 'cifra_ajena_al_contexto', 'una cifra ajena con puntos de miles (9.876.543.210) tiene que descartar');

// cifras que SÍ están en el contexto → pasa, escritas tal cual o con separadores
r = postCheck('1. Cita — campo `precio_total`: 1500000000 IDR. Hito 2: 600000000 IDR (40 %).', contexto, bloqueos);
ok(r.ok, 'las cifras del contexto tienen que pasar');
r = postCheck('Precio total: 1.500.000.000 IDR; hito Cubierta 600.000.000 IDR.', contexto, bloqueos);
ok(r.ok, 'las cifras del contexto con puntos de miles tienen que pasar');
r = postCheck('Total price: 1,500,000,000 IDR.', contexto, bloqueos);
ok(r.ok, 'las cifras del contexto con comas de miles tienen que pasar');

// una fecha del contexto reescrita con otro separador NO es una cuenta ajena
r = postCheck('Fecha de firma: 2026-05-14 (14/05/2026).', contexto, bloqueos);
ok(r.ok, 'una fecha con / o - no se colapsa a una secuencia de 8 dígitos');

// sin cifras largas → pasa
r = postCheck('Art. 6 — Plazo de ejecución: 18 meses. Hito 1: 30 %.', contexto, bloqueos);
ok(r.ok, 'un borrador sin secuencias de 8 dígitos pasa');

// patron_salida → descartado (insensible a mayúsculas)
r = postCheck('El NÚMERO DE CUENTA te lo confirma el promotor.', contexto, bloqueos);
ok(!r.ok && r.motivo === 'patron_salida' && /Destino del pago/.test(r.detalle), 'un patron_salida que casa tiene que descartar, con su motivo');
r = postCheck('We accept the 5 % retention proposed.', contexto, bloqueos);
ok(!r.ok && r.motivo === 'patron_salida', 'aceptar una retención casa el patron_salida de contraoferta');

// un bloqueo sin patron_salida no descarta nada por sí solo
r = postCheck('La entrega se fija en el hito 5.', contexto, [bloqueos[2]]);
ok(r.ok, 'un bloqueo sin patron_salida no descarta por su patron de entrada');

// patron_salida que no compila → descartado (fail closed)
r = postCheck('Todo correcto.', contexto, [{ patron_salida: '(', motivo: 'roto' }]);
ok(!r.ok && r.motivo === 'patron_salida_invalido', 'un patron_salida que no compila tiene que descartar, no leerse como sin freno');

// entradas raras: null/undefined no revientan
r = postCheck('', contexto, null);
ok(r.ok, 'borrador vacío y bloqueos null no revientan');
r = postCheck(null, '', undefined);
ok(r.ok, 'borrador null no revienta');

if (fallos) { console.error('\n' + fallos + ' fallo(s) en postcheck.test.js'); process.exit(1); }
console.log('OK postcheck.test.js — postCheck es el mismo en la edge, la copia de despliegue es idéntica y el freno descarta lo que debe.');
