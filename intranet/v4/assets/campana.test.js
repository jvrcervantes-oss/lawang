/* Campana de la cabecera v4 (cabecera.js → pintaAvisos), sin navegador. H7, 17-oct-2026: un aviso se da por leído al pulsarlo.
   Lo que se comprueba es lo que pinta: con la base que marca de uno en uno (avisos.js → porAviso) cada fila nueva lleva los ids de
   todas sus copias y sale «Marcar todo como leído»; sin ella (una instancia sin la migración 20261017200000: la respuesta no trae
   `id`), ninguna fila lleva ids y el enlace es un enlace normal: el clic navega como siempre y abrir lo da por visto (avisos.test.js).
   Además: la acción de la fila sale de la herramienta de destino, «3 d» no se parte y el título va escapado.
   node intranet/v4/assets/campana.test.js */
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const nodo = () => { let t = ''; return { set textContent(v) { t = v; }, get innerHTML() { return t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); } }; };
global.window = global;
global.document = { querySelectorAll: () => [], addEventListener: () => {}, querySelector: () => null, createElement: nodo };
new Function(fs.readFileSync(path.join(__dirname, 'cabecera.js'), 'utf8'))();
const pintaAvisos = window.LW_CABECERA.pintaAvisos;
const aV4 = h => h;
const ID1 = '11111111-1111-1111-1111-111111111111', ID2 = '22222222-2222-2222-2222-222222222222', ID3 = '33333333-3333-3333-3333-333333333333';
const av = [
  { titulo: 'Enlace de firma de CC1 caduca en 3 d', detalle: 'x', enlace: '/intranet/v4/operaciones/?contrato=1', cuando: '2026-10-17', nuevo: true, clase: 'alerta', nivel: 'atencion', etiqueta: 'Por vencer' },
  { titulo: 'Contrato <b>CC2</b> firmado', detalle: '', enlace: '/intranet/leads/', cuando: '2026-10-16T10:00:00Z', nuevo: true, clase: 'hecho', nivel: 'ok', etiqueta: 'Firmado', ids: [ID1, ID2] },
  { titulo: 'Ya leído', detalle: '', enlace: '/intranet/v4/comisiones/', cuando: '2026-10-15T10:00:00Z', nuevo: false, clase: 'hecho', nivel: 'neutro', etiqueta: 'Aviso', ids: [ID3] },
  { titulo: 'Sin enlace', detalle: '', enlace: '#', cuando: '2026-10-14T10:00:00Z', nuevo: true, clase: 'hecho', nivel: 'neutro', etiqueta: 'Aviso', ids: [] },
];

const con = pintaAvisos(av, aV4, { marcarTodo: true });
assert.ok(con.includes('data-accion="avisos-marcar-todo"'), 'con la base que marca de uno en uno sale «Marcar todo como leído»');
assert.ok(con.includes('data-lw-aviso-ids="' + ID1 + ',' + ID2 + '"'), 'la fila nueva lleva los ids de todas sus copias');
assert.ok(!con.includes(ID3), 'un aviso ya leído no lleva ids (pulsarlo no vuelve a marcar)');
assert.strictEqual((con.match(/data-lw-aviso-ids=/g) || []).length, 1, 'ni las alertas ni un aviso sin ids llevan el atributo');
assert.ok(con.includes('caduca en 3' + String.fromCharCode(160) + 'd'), '«3 d» con espacio duro');
assert.ok(con.includes('Abrir operación →') && con.includes('Abrir CRM →') && con.includes('Ver comisiones →'), 'la acción sale de la herramienta de destino');
const filaSin = con.split('<a class="lw-av"').find(x => x.includes('Sin enlace'));
assert.ok(filaSin && filaSin.includes('<span class="lw-av-a"></span>'), 'sin destino no se promete acción');
assert.ok(!con.includes('<b>CC2</b>') && con.includes('&lt;b&gt;CC2&lt;/b&gt;'), 'el título va escapado');

// la base sin `id` (porAviso false): ni botón ni ids → el enlace navega como siempre
const sinIds = av.map(a => Object.assign({}, a, { ids: [] }));
const sin = pintaAvisos(sinIds, aV4);
assert.ok(!sin.includes('avisos-marcar-todo'), 'sin porAviso no hay botón');
assert.ok(!sin.includes('data-lw-aviso-ids'), 'sin ids ninguna fila se intercepta: el clic es un enlace normal');
assert.ok(sin.includes('href="/intranet/leads/"'), 'el enlace sigue ahí');

console.log('campana.test.js OK');
