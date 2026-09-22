/* Test de borradorComprador. `node borrador_comprador.test.js`.
   1. Paridad byte a byte con las DOS copias de la edge (contracts/edge y
      supabase/functions) — mismo motivo que postcheck.test.js: si alguien
      afina el recorte en un sitio y no en el otro, esto falla.
   2. Casos: punto retirado fuera · «Fuente:» dentro · marca de IA fuera ·
      «Fuentes usadas:» fuera · frase fija fuera aunque vaya en un punto no
      retirado · preámbulo (aviso al agente) fuera · punto sin respuesta del
      modelo fuera · modelo sin numerar → texto limpio · entradas raras. */
const fs = require('fs');
const path = require('path');
const { borradorComprador, FRASE_PENDIENTE, FRASE_CONTRAOFERTA, MARCA_IA } = require('./borrador_comprador.js');

let fallos = 0;
function ok(cond, msg) { if (!cond) { fallos++; console.error('  FALLA  ' + msg); } }

// ── 1. paridad con las dos copias de la edge ──────────────────────────────
const aqui = path.dirname(__filename);
function bloque(fichero) {
  const txt = fs.readFileSync(fichero, 'utf8');
  const a = txt.indexOf('// >>> borradorComprador');
  const b = txt.indexOf('// <<< borradorComprador');
  if (a < 0 || b < 0 || b < a) return null;
  return txt.slice(a, b + '// <<< borradorComprador'.length);
}
const bJs = bloque(path.join(aqui, 'borrador_comprador.js'));
ok(bJs, 'borrador_comprador.js no tiene los marcadores >>> borradorComprador / <<< borradorComprador');
for (const f of [
  path.join(aqui, '..', 'edge', 'bot-agentes', 'index.ts'),
  path.join(aqui, '..', '..', 'supabase', 'functions', 'bot-agentes', 'index.ts'),
]) {
  const b = bloque(f);
  ok(b, f + ' no tiene los marcadores >>> borradorComprador / <<< borradorComprador');
  ok(b === bJs, f + ': borradorComprador difiere de borrador_comprador.js');
}

// ── 2. casos ──────────────────────────────────────────────────────────────
// Puntos como los deja partePuntos + los frenos: el 2 lo retiró el servidor.
const puntos = [
  { n: 0, texto: 'Hola, tengo dudas:', motivos: [] },
  { n: 1, texto: '¿Cuál es el plazo de ejecución?', motivos: [] },
  { n: 2, texto: '¿A qué cuenta pago?', motivos: [{ motivo: 'Destino del pago: pendiente.', ref: 'LAW-124' }] },
  { n: 3, texto: '¿Tenéis los anexos A y B?', motivos: [] },
  { n: 4, texto: '¿Hay penalización por retraso?', motivos: [] },
];
const modelo = [
  'Aviso: la plantilla cambió después de la firma; manda el PDF firmado.',
  '',
  '1. Plazo de ejecución — cita',
  '   Artículo 6 — Plazo de ejecución: «El Plazo de Ejecución es de 8 meses naturales».',
  '   Fuente: Artículo 6 — Plazo de ejecución · campo plazo_meses',
  '',
  '2. Artículo 3 — Forma de pago: «el pago se hará a la cuenta indicada».',
  '',
  '3. Anexos A y B — existe el documento',
  '   El contrato los menciona en el Artículo 1, pero no constan en la lista de documentos.',
  '   Fuente: Artículo 1 — Objeto',
  '   ' + FRASE_PENDIENTE,
  '',
  'Fuentes usadas: Artículo 6, Artículo 3, Artículo 1',
  MARCA_IA,
].join('\n');

const salida = borradorComprador(puntos, modelo);
ok(salida.startsWith('1. Plazo de ejecución\n'), 'el punto 1 abre el borrador con su número (no se renumera) y SIN la etiqueta de clase «— cita»');
ok(!/ — (cita|existe el documento|pendiente|contraoferta)/.test(salida), 'ninguna cabecera conserva su etiqueta de clase (es para el agente)');
ok(salida.includes('Fuente: Artículo 6 — Plazo de ejecución · campo plazo_meses'), 'la línea «Fuente: …» del punto 1 va dentro');
ok(salida.includes('«El Plazo de Ejecución es de 8 meses naturales»'), 'la cita del punto 1 va dentro');
ok(!salida.includes('Forma de pago') && !salida.includes('cuenta indicada') && !/\n2\. /.test(salida), 'el punto 2 (retirado por el servidor) queda FUERA entero');
ok(!salida.includes('Anexos A y B') && !salida.includes('Fuente: Artículo 1 — Objeto'), 'el punto 3 (el modelo lo dejó pendiente con la frase fija) sale ENTERO, no solo la frase');
ok(!salida.includes(FRASE_PENDIENTE), 'la frase fija de pendiente queda fuera');
ok(!salida.includes(MARCA_IA), 'la marca «Borrador generado por IA» queda fuera');
ok(!/Fuentes usadas/.test(salida), 'la línea «Fuentes usadas: …» queda fuera');
ok(!salida.includes('plantilla cambió'), 'el preámbulo (aviso al agente) queda fuera');
ok(!salida.includes('no ha respondido') && !/\n4\. /.test(salida), 'un punto no retirado sin respuesta del modelo no aparece (ni con relleno)');
ok(!/\n{3,}/.test(salida) && salida === salida.trim(), 'sin líneas en blanco de más ni espacios en los bordes');

// punto NO retirado que el modelo clasificó contraoferta → sale ENTERO: la cita
// del artículo iría al comprador como argumento (prompt: «nunca la cita como
// argumento a favor o en contra»); un segundo punto limpio se queda.
const modelo2 = '1. Retención del 5 % — cita + contraoferta\n   Artículo 5 — Pagos: «cada hito se abona íntegro».\n   Fuente: Artículo 5\n   ' + FRASE_CONTRAOFERTA + '\n\n2. Superficie — cita\n   Artículo 2: «120 m²».\n   Fuente: Artículo 2\n' + MARCA_IA;
const s2 = borradorComprador([{ n: 1, texto: 'retención', motivos: [] }, { n: 2, texto: 'superficie', motivos: [] }], modelo2);
ok(!s2.includes('cada hito se abona íntegro') && !s2.includes('Fuente: Artículo 5') && !s2.includes(FRASE_CONTRAOFERTA), 'contraoferta: el punto entero queda fuera, cita incluida');
ok(s2 === '2. Superficie\n   Artículo 2: «120 m²».\n   Fuente: Artículo 2', 'el punto limpio se queda, sin etiqueta de clase');
// clase en la cabecera SIN frase fija → también fuera («(en blanco) meses» + pendiente)
const s2b = borradorComprador([{ n: 1, texto: 'plazo', motivos: [] }], '1. Plazo — cita + pendiente\n   Artículo 6: «(en blanco) meses naturales».\n' + MARCA_IA);
ok(s2b === '', 'cabecera con clase pendiente y sin frase fija: el punto sale entero');

// todos los puntos retirados → nada que mandar
const s3 = borradorComprador([{ n: 1, texto: 'cuenta', motivos: [{ motivo: 'x', ref: null }] }], '1. Sin artículo aplicable\n' + MARCA_IA);
ok(s3 === '', 'si todos los puntos están retirados, el borrador para el comprador es vacío');

// modelo sin numerar y sin frases fijas ni retirados → texto sin la cola
const modelo4 = 'El plazo es de 8 meses (Artículo 6).\nFuentes usadas: Artículo 6\n' + MARCA_IA;
const s4 = borradorComprador([{ n: 1, texto: 'plazo', motivos: [] }, { n: 2, texto: 'anexos', motivos: [] }], modelo4);
ok(s4 === 'El plazo es de 8 meses (Artículo 6).', 'modelo sin numerar: devuelve el texto sin marca ni «Fuentes usadas»');
// modelo sin numerar con una frase fija → no se sabe de qué punto es → vacío
const s4b = borradorComprador([{ n: 1, texto: 'plazo', motivos: [] }], 'El plazo es de 8 meses.\n' + FRASE_PENDIENTE + '\n' + MARCA_IA);
ok(s4b === '', 'modelo sin numerar con frase fija: vacío');
// modelo sin numerar con un punto retirado → su cita podría ir dentro → vacío
const s4c = borradorComprador([{ n: 1, texto: 'plazo', motivos: [] }, { n: 2, texto: 'cuenta', motivos: [{ motivo: 'x', ref: null }] }], '1) El plazo es de 8 meses.\n2) Artículo 3: «el pago se hará a la cuenta indicada».\n' + MARCA_IA);
ok(s4c === '', 'modelo sin numerar con un punto retirado: vacío (la cita del retirado no puede colarse)');

// entradas raras
ok(borradorComprador(null, null) === '', 'puntos null y texto null no revientan');
ok(borradorComprador([], '') === '', 'sin puntos y sin texto → vacío');
ok(borradorComprador([{ n: 1, texto: 'a', motivos: [] }], '1. A — cita\r\n   B\r\n' + MARCA_IA) === '1. A\n   B', 'CRLF del modelo no rompe el corte (la sangría del modelo se respeta, como en `ensambla`)');

if (fallos) { console.error('borrador_comprador.test.js: ' + fallos + ' fallo(s)'); process.exit(1); }
console.log('OK borrador_comprador.test.js — paridad con las dos copias de la edge + recorte para el comprador');
