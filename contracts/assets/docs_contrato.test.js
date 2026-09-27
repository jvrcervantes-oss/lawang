/* node docs_contrato.test.js — la regla de qué documentos del modelo entran en el contrato
   de obra (docs_contrato.js) y la LISTA DE TIPOS contra todos los sitios donde vive.

   POR QUÉ EXISTE (27-sep-2026): los tipos de documento están escritos en seis sitios —el
   CHECK de la tabla, las dos RPC que la escriben, la edge `ficheros`, esta lista y el modal
   de subida— y el 'dosier' nuevo tenía que entrar en todos a la vez. Con uno olvidado, la
   pantalla ofrece un tipo que el servidor rechaza (o al revés) y nadie lo ve hasta que un
   agente sube un fichero. Este test afirma el hecho contra todos. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const RAIZ = path.join(__dirname, '..', '..');
const lee = r => fs.readFileSync(path.join(RAIZ, r), 'utf8');
const ctx = {}; ctx.window = ctx; vm.createContext(ctx);
vm.runInContext(lee('contracts/assets/docs_contrato.js'), ctx);
const R = ctx.lwDocsContrato;
const J = x => JSON.parse(JSON.stringify(x));
const TIPOS = J(R.TIPOS.map(t => t[0])).sort();
const lista = s => s.match(/'([a-z_]+)'/g).map(x => x.slice(1, -1)).sort();

// 1. La migración que define hoy el CHECK (la más reciente que lo toca) y las dos RPC.
const dir = path.join(RAIZ, 'supabase', 'migrations');
const ultima = fs.readdirSync(dir).filter(f => f.endsWith('.sql')).sort().reverse()
  .find(f => /modelo_documentos_tipo_ck[\s\S]*check \(tipo in/.test(fs.readFileSync(path.join(dir, f), 'utf8')));
assert.ok(ultima, 'hay una migración que define modelo_documentos_tipo_ck');
const sql = fs.readFileSync(path.join(dir, ultima), 'utf8');
assert.deepStrictEqual(lista(/add constraint modelo_documentos_tipo_ck\s+check \(tipo in \(([^)]*)\)\)/.exec(sql)[1]), TIPOS, 'CHECK de la tabla (' + ultima + ')');
const enRpc = [...sql.matchAll(/not in \(('plano'[^)]*)\)/g)].map(m => lista(m[1]));
assert.strictEqual(enRpc.length, 2, 'la lista de tipos aparece en cambia y en registra: ' + enRpc.length);
enRpc.forEach((l, i) => assert.deepStrictEqual(l, TIPOS, 'lista de tipos de la RPC #' + (i + 1)));

// 2. La edge `ficheros` (se comprueba ANTES de subir).
const edge = lee('supabase/functions/ficheros/index.ts');
const bloque = /modelo_documento: \{[\s\S]*?\n  \},/.exec(edge)[0];
assert.deepStrictEqual(lista(/\[('plano'[^\]]*)\]\.includes\(tipo\)/.exec(bloque)[1]), TIPOS, 'edge ficheros, clase modelo_documento');

// 3. Las pantallas no escriben su propia lista: toman la de aquí.
const ficha = lee('intranet/v4/assets/ficha_modelo.js');
assert.ok(/lwDocsContrato\.TIPOS/.test(ficha) && !/\['calidades', 'Memoria de calidades'\]/.test(ficha), 'ficha_modelo.js usa lwDocsContrato.TIPOS');
const editores = lee('intranet/v4/assets/editores.js');
const modal = /ata\(\/\^Añadir documento\$\/i[\s\S]*?\n      \}\);\n/.exec(editores);
assert.ok(modal && /lwDocsContrato/.test(modal[0]) && !/\['calidades', 'Memoria de calidades'\]/.test(modal[0]), 'el modal «Añadir documento» usa lwDocsContrato');
// y las dos pantallas cargan el fichero de la regla antes de usarlo
assert.ok(/docs_contrato\.js\?v=/.test(lee('contracts/app.html')), 'app.html carga docs_contrato.js');
assert.ok(/docs_contrato\.js\?v=/.test(lee('intranet/v4/modelos/index.html')), 'v4/modelos carga docs_contrato.js');
const app = lee('contracts/app.html');
assert.ok(app.indexOf('docs_contrato.js') < app.indexOf('documento_anexos.js'), 'en app.html, la regla antes que el generador');

// 4. La regla.
const D = (id, o) => Object.assign({ id, tipo: 'calidades', en_contrato: true, orden: 0, techo_clave: null, subido_en: '2026-09-01' }, o);
const docs = [
  D('b', { techo_clave: 'bambu', orden: 2 }), D('s', { techo_clave: 'sirap', orden: 1 }),
  D('g', { orden: 3 }), D('x', { en_contrato: false }), D('c', { orden: 1, subido_en: '2026-08-01' }),
];
const ids = (l) => J(l.map(d => d.id));
assert.deepStrictEqual(ids(R.entran(docs, 'sirap')), ['c', 's', 'g'], 'sirap: el suyo + los generales, en orden; empate por subido_en');
assert.deepStrictEqual(ids(R.entran(docs, 'bambu')), ['c', 'b', 'g']);
assert.deepStrictEqual(ids(R.entran(docs, '')), ['c', 'g'], 'sin techo: solo los de todos los techos');
assert.deepStrictEqual(ids(R.entran(docs, 'otro')), ['c', 'g'], 'techo sin documentos propios: solo los generales');
assert.deepStrictEqual(ids(R.entran([D('z', { en_contrato: 'true' })], '')), [], 'la casilla es booleana: un texto no cuenta');
assert.deepStrictEqual(ids(R.ordena([D('2', { orden: 1 }), D('1', { orden: 1 })])), ['1', '2'], 'empate total: por id, estable');
assert.strictEqual(R.etiqueta('dosier'), 'Dosier');
assert.strictEqual(R.etiqueta('plano'), 'Plano', 'ya no es «Plano · anexo del contrato»: lo que va al contrato lo dice la casilla');

// 5. El dosier NUNCA entra (owner, 28-sep-2026), aunque llegue marcado.
assert.deepStrictEqual(ids(R.entran([D('d', { tipo: 'dosier' }), D('p', { tipo: 'plano' })], '')), ['p']);

// 6. Letra por TIPO (Art. 3 de la plantilla: A planos, B especificaciones; informativos de la D en adelante).
assert.deepStrictEqual(J(R.LETRA), { plano: 'A', calidades: 'B', ficha: 'D', render: 'E', otro: 'F' });
const plantilla = lee('contracts/templates/ppjb_construccion.html');
assert.ok(/Apéndice A – Planos Arquitectónicos/.test(plantilla) && /Apéndice B – Especificaciones Técnicas/.test(plantilla),
  'la plantilla sigue llamando A a los planos y B a las especificaciones: si cambia, cambian las letras aquí');
assert.ok(/Apéndice B – Especificaciones Técnicas\. El CONSTRUCTOR/.test(plantilla) || /en el Apéndice B – Especificaciones Técnicas/.test(plantilla),
  'Art. 6 remite al Apéndice B (Legal, 28-sep)');
const ap = R.apendices([
  D('f', { tipo: 'ficha', orden: -5 }), D('c1', { tipo: 'calidades', orden: 2 }), D('p', { tipo: 'plano', orden: 9, techo_clave: 'sirap' }),
  D('c2', { tipo: 'calidades', orden: 1 }), D('o', { tipo: 'otro', nombre: 'Condiciones generales.pdf' }), D('x', { tipo: 'dosier' }),
], 'sirap');
assert.deepStrictEqual(J(ap.map((a) => [a.doc.id, a.letra])), [['p', 'A'], ['c2', 'B1'], ['c1', 'B2'], ['f', 'D'], ['o', 'F']],
  'por letra; dentro de la letra, por el orden de Modelos (B1/B2); el orden nunca cambia la letra');
assert.deepStrictEqual(J(ap[0].rotulo), { es: 'Apéndice A', en: 'Appendix A', id: 'Lampiran A' });
assert.deepStrictEqual(J(ap[0].titulo), { es: 'Planos Arquitectónicos', en: 'Architectural Drawings', id: 'Gambar Arsitektur' });
assert.deepStrictEqual(J(ap[1].titulo), { es: 'Especificaciones Técnicas', en: 'Technical Specifications', id: 'Spesifikasi Teknis' });
assert.strictEqual(ap[3].informativo, true);
assert.deepStrictEqual(J(ap[4].titulo), { es: 'Condiciones generales (informativo)', en: 'Condiciones generales (for information)', id: 'Condiciones generales (informatif)' },
  'otro: el nombre del fichero + informativo en los tres idiomas');
assert.ok(!ap.some((a) => a.doc.tipo === 'dosier'));

console.log('docs_contrato.test.js OK');
