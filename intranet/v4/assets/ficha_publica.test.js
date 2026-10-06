/* node intranet/v4/assets/ficha_publica.test.js — The Collection v2, F3b (5-oct-2026).
   Prueba las funciones PURAS de ficha_publica.js (la pantalla «Ficha pública»): qué se manda al servidor, qué falta
   para publicar, cómo se cuenta un error y cómo se normaliza una dirección. Sin navegador: el módulo se carga con
   `new Function('window', 'module', …)`. El camino de pantalla (cajón, formulario, clics) lo mide el arnés de
   navegador `coleccion/tests/arnes_ficha_publica.js`.

   Lo que más importa y por qué:
   · cada edición lleva p_version, TAL CUAL (la cadena con microsegundos): pasarla por Date da 40001 en cada guardado
     y mandarla vacía se salta el control de «otra persona cambió esta ficha»;
   · editar UN campo no manda claves que no se tocaron: el servidor mezcla por clave de primer nivel, así que un
     `ficha.imagenes` o un `equipamiento` a medias en el parche BORRARÍA lo que la pantalla no edita (las fotos que
     F9a acababa de arreglar);
   · publicar no es una clave del parche de guardar. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const V4 = path.resolve(__dirname, '..');
const RAIZ = path.resolve(V4, '..', '..');
const fuente = fs.readFileSync(path.join(__dirname, 'ficha_publica.js'), 'utf8');
function carga(extra) {
  const win = Object.assign({}, extra || {});
  const mod = { exports: {} };
  new Function('window', 'module', fuente)(win, mod);
  return mod.exports;
}
// el lector de importes REAL de la suite (una sola forma de leer dinero)
const lwParseImporte = new Function(fs.readFileSync(path.join(RAIZ, 'contracts', 'assets', 'dinero.js'), 'utf8') + '\n;return lwParseImporte;')();
const F = carga({ lwParseImporte });

let n = 0;
const caso = (nombre, fn) => { try { fn(); n++; } catch (e) { console.error('FALLA · ' + nombre + '\n  ' + (e && e.message)); process.exitCode = 1; } };

// una ficha como la devuelve ficha_publica_lee, con TODO lo que la pantalla no edita
const IMAGENES = ['/assets/a.webp', '/assets/b.webp'];
const DOWNLOADS = [{ name: 'Brochure', url: '/dl/b.pdf', ext: 'pdf', size: '2 MB' }];
const DISENO = { logo: '/l.svg', landColor: '#aabbcc', tabs: [{ title: { en: 'A', es: 'B' } }] };
function ficha(extra) {
  return Object.assign({
    id: 'f1', slug: 'villa-uno', linea: 'signature', region_key: 'bali', region: 'Ubud, Bali', publicada_web: true,
    en_coleccion: true, destacada: false, destacada_home: false, orden: 3, proyecto_id: 'p1', modelo_id: null, unidad_id: 'u1',
    precio_modo: 'fijo', precio_eur: 250000, tenure: 'freehold', lease_years: null, estado_obra: 'ready',
    textos: { title: { es: 'Villa Uno', en: 'Villa One' }, sub: { es: 'Sub', en: 'Sub en' }, desc: { es: 'Descripción', en: 'Description' } },
    ficha: {
      highlights: ['Piscina', 'Vistas'], tech_specs: [{ l: 'Dormitorios', v: '3' }],
      equipamiento: { pool: true, poolType: 'infinity', garage: false, garageDesc: 'dos coches', furnished: 'sí', style: 'moderno' },
      view: 'arrozales', imagenes: IMAGENES.slice(), downloads: DOWNLOADS.slice(), diseno: JSON.parse(JSON.stringify(DISENO)),
      payment_plan: [{ pct: 30, label: 'Reserva' }], masterplan_pins: [{ code: 'A1', x: 1, y: 2 }]
    },
    version: '2026-10-05T11:22:33.123456Z', publico: null
  }, extra || {});
}
// el formulario tal cual lo pinta, con un cambio
const edita = (f, cambio) => Object.assign(F.valoresDeFicha(f), cambio);
const claves = (o) => Object.keys(o).sort();

caso('sin tocar nada no hay parche', () => {
  const f = ficha();
  assert.deepStrictEqual(F.construyeCambios(f, F.valoresDeFicha(f)), {});
});
caso('una ficha sin ningún dato opcional tampoco da parche (vacío = ausente)', () => {
  const f = ficha({ region: null, tenure: null, estado_obra: null, unidad_id: null, textos: {}, ficha: {}, precio_modo: 'consultar', precio_eur: null });
  assert.deepStrictEqual(F.construyeCambios(f, F.valoresDeFicha(f)), {});
});
caso('editar un texto: solo esa clave e idioma, sin tocar el otro idioma ni `ficha`', () => {
  const f = ficha();
  const c = F.construyeCambios(f, edita(f, { t_title_en: 'Villa One Deluxe' }));
  assert.deepStrictEqual(c, { textos: { title: { en: 'Villa One Deluxe' } } });
  assert.ok(!('ficha' in c));
});
caso('vaciar un texto que tenía valor manda null en ESE idioma; vaciar uno ya vacío no manda nada', () => {
  const f = ficha();
  assert.deepStrictEqual(F.construyeCambios(f, edita(f, { t_sub_en: '  ' })), { textos: { sub: { en: null } } });
  assert.deepStrictEqual(F.construyeCambios(f, edita(f, { t_meta_en: '' })), {});
});
caso('editar la vista: solo ficha.view; nada de imagenes, downloads, diseno ni equipamiento', () => {
  const f = ficha();
  const c = F.construyeCambios(f, edita(f, { view: 'mar' }));
  assert.deepStrictEqual(c, { ficha: { view: 'mar' } });
});
caso('quitar la vista manda null (borra la clave)', () => {
  const f = ficha();
  assert.deepStrictEqual(F.construyeCambios(f, edita(f, { view: '' })), { ficha: { view: null } });
});
caso('editar UNA subclave de equipamiento manda equipamiento ENTERO (el servidor mezcla solo el primer nivel)', () => {
  const f = ficha();
  const c = F.construyeCambios(f, edita(f, { pool: false }));
  assert.deepStrictEqual(claves(c), ['ficha']);
  assert.deepStrictEqual(claves(c.ficha), ['equipamiento']);
  assert.deepStrictEqual(c.ficha.equipamiento, { pool: false, poolType: 'infinity', garage: false, garageDesc: 'dos coches', furnished: 'sí', style: 'moderno' });
});
caso('vaciar una subclave de equipamiento la OMITE (null en una subclave lo rechaza el validador)', () => {
  const f = ficha();
  const c = F.construyeCambios(f, edita(f, { poolType: '' }));
  assert.ok(!('poolType' in c.ficha.equipamiento));
  assert.strictEqual(c.ficha.equipamiento.garageDesc, 'dos coches');
  assert.ok(!JSON.stringify(c).includes('null'));
});
caso('quitar todo el equipamiento borra la clave entera (null de primer nivel)', () => {
  const f = ficha({ ficha: { equipamiento: { poolType: 'infinity' } } });
  assert.deepStrictEqual(F.construyeCambios(f, edita(f, { poolType: '' })), { ficha: { equipamiento: null } });
});
caso('un booleano ausente cuenta como false: marcar/desmarcar sin cambio real no genera parche', () => {
  const f = ficha({ ficha: { equipamiento: {} } });
  assert.deepStrictEqual(F.construyeCambios(f, edita(f, { pool: false, garage: false })), {});
});
caso('highlights y tech_specs: la lista entera, y solo si cambió', () => {
  const f = ficha();
  assert.deepStrictEqual(F.construyeCambios(f, edita(f, { highlights: ['Piscina', 'Vistas', 'Jardín'] })), { ficha: { highlights: ['Piscina', 'Vistas', 'Jardín'] } });
  assert.deepStrictEqual(F.construyeCambios(f, edita(f, { highlights: ['Piscina', ' ', 'Vistas', ''] })), {});   // las filas vacías no cuentan
  assert.deepStrictEqual(F.construyeCambios(f, edita(f, { tech_specs: [{ l: 'Dormitorios', v: '4' }] })), { ficha: { tech_specs: [{ l: 'Dormitorios', v: '4' }] } });
  assert.deepStrictEqual(F.construyeCambios(f, edita(f, { highlights: [] })), { ficha: { highlights: null } });
});
caso('NINGÚN parche de edición lleva claves que la pantalla no edita ni publicada_web', () => {
  const f = ficha();
  const cambios = [
    { t_desc_es: 'otra' }, { view: 'x' }, { pool: false }, { highlights: ['a'] }, { tech_specs: [] }, { precio_eur: '300000' },
    { linea: 'villa', precio_modo: 'desde' }, { region: 'Seminyak' }, { orden: '9' }, { destacada: true }, { tenure: 'leasehold', lease_years: '25' }
  ];
  const vetadas = ['imagenes', 'downloads', 'diseno', 'payment_plan', 'masterplan_pins', 'masterplan_imagen', 'videos', 'aerial', 'handover', 'mapa_url'];
  cambios.forEach((x) => {
    const c = F.construyeCambios(f, edita(f, x));
    assert.ok(Object.keys(c).length, 'debería haber parche para ' + JSON.stringify(x));
    assert.ok(!('publicada_web' in c), 'publicar no va en guardar');
    vetadas.forEach((k) => assert.ok(!c.ficha || !(k in c.ficha), k + ' no debe viajar editando ' + JSON.stringify(x)));
    Object.keys(c).forEach((k) => assert.ok(['linea', 'region_key', 'region', 'en_coleccion', 'destacada', 'destacada_home', 'orden', 'precio_modo', 'precio_eur',
      'tenure', 'lease_years', 'estado_obra', 'unidad_id', 'modelo_id', 'textos', 'ficha'].includes(k), 'clave inesperada ' + k));
  });
});
caso('precio: con «desde» o «consultar» NO viaja importe; con «fijo» sí, y se lee con el lector de la suite', () => {
  const f = ficha();
  const aDesde = F.construyeCambios(f, edita(f, { precio_modo: 'desde', precio_eur: '999' }));
  assert.deepStrictEqual(aDesde, { precio_modo: 'desde' });
  const aConsultar = F.construyeCambios(f, edita(f, { precio_modo: 'consultar', precio_eur: '999' }));
  assert.deepStrictEqual(aConsultar, { precio_modo: 'consultar' });
  assert.deepStrictEqual(F.construyeCambios(f, edita(f, { precio_eur: '1.250.000' })), { precio_eur: 1250000 });
  assert.deepStrictEqual(F.construyeCambios(f, edita(f, { precio_eur: '1250000,50' })), { precio_eur: 1250000.5 });
  const g = ficha({ precio_modo: 'desde', precio_eur: null, linea: 'signature' });
  assert.deepStrictEqual(F.construyeCambios(g, edita(g, { precio_modo: 'fijo', precio_eur: '300000' })), { precio_modo: 'fijo', precio_eur: 300000 });
});
caso('claves que nunca pueden ir a null no van a null (linea, region_key, flags, orden, precio_modo)', () => {
  const f = ficha();
  const c = F.construyeCambios(f, edita(f, { linea: 'villa', region_key: 'sumba', en_coleccion: false, destacada: true, destacada_home: true, orden: '', precio_modo: 'desde' }));
  ['linea', 'region_key', 'en_coleccion', 'destacada', 'destacada_home', 'orden', 'precio_modo'].forEach((k) => assert.notStrictEqual(c[k], null, k));
  assert.ok(!('orden' in c), 'orden vacío = no se toca');
});
caso('columnas que admiten vacío: «» → null solo si antes tenían algo', () => {
  const f = ficha({ modelo_id: 'm1' });
  const c = F.construyeCambios(f, edita(f, { region: '', tenure: '', estado_obra: '', unidad_id: '', modelo_id: '', lease_years: '' }));
  assert.deepStrictEqual(c, { region: null, tenure: null, estado_obra: null, unidad_id: null, modelo_id: null });
});
caso('orden se convierte a número', () => {
  const f = ficha();
  assert.strictEqual(F.construyeCambios(f, edita(f, { orden: '12' })).orden, 12);
});

// ── p_version ──
caso('payload de edición: SIEMPRE p_version y es la cadena de `lee` sin tocar (microsegundos incluidos)', () => {
  const f = ficha({ version: '2026-10-05T11:22:33.123456Z' });
  const p = F.payloadGuarda(f, f.slug, { view: 'x' });
  assert.strictEqual(p.p_version, '2026-10-05T11:22:33.123456Z');
  assert.strictEqual(p.p_slug, 'villa-uno');
  assert.ok('p_version' in p);
  // y no pasa por Date, que corta los microsegundos
  assert.ok(p.p_version.includes('.123456Z'));
  assert.ok(!(p.p_version instanceof Date));
});
caso('una edición sin version se niega en el cliente (no se manda sin control de concurrencia)', () => {
  assert.throws(() => F.payloadGuarda(ficha({ version: null }), 'villa-uno', {}), /versión/);
  assert.throws(() => F.payloadGuarda(ficha({ version: undefined }), 'villa-uno', {}), /versión/);
});
caso('el alta va sin p_version, con el slug tecleado', () => {
  const p = F.payloadGuarda(null, 'villa-nueva', { linea: 'villa', region_key: 'bali', proyecto_id: 'p1' });
  assert.ok(!('p_version' in p));
  assert.strictEqual(p.p_slug, 'villa-nueva');
});
caso('publicar / despublicar es su propia llamada: {publicada_web} + p_version', () => {
  const f = ficha({ publicada_web: false });
  assert.deepStrictEqual(F.payloadGuarda(f, f.slug, { publicada_web: true }), { p_slug: 'villa-uno', p_cambios: { publicada_web: true }, p_version: f.version });
});

// ── qué falta para publicar ──
caso('faltantes para publicar: proyecto, títulos ES y EN, importe del fijo', () => {
  assert.deepStrictEqual(F.faltaParaPublicar(ficha()), []);
  assert.deepStrictEqual(F.faltaParaPublicar(ficha({ proyecto_id: null })), ['vincularla a un proyecto']);
  assert.deepStrictEqual(F.faltaParaPublicar(ficha({ textos: { title: { en: 'X' } } })), ['el título en español']);
  assert.deepStrictEqual(F.faltaParaPublicar(ficha({ textos: { title: { es: ' ', en: '' } } })), ['el título en español', 'el título en inglés']);
  assert.deepStrictEqual(F.faltaParaPublicar(ficha({ precio_eur: null })), ['el importe del precio fijo (mayor que 0)']);
  assert.deepStrictEqual(F.faltaParaPublicar(ficha({ precio_eur: 0 })), ['el importe del precio fijo (mayor que 0)']);
  assert.deepStrictEqual(F.faltaParaPublicar(ficha({ precio_modo: 'desde', precio_eur: null })), []);
  assert.deepStrictEqual(F.faltaParaPublicar(ficha({ proyecto_id: null, textos: {}, precio_eur: null })).length, 4);
});
caso('avisos que no impiden publicar: descripciones vacías', () => {
  assert.deepStrictEqual(F.avisosPublicacion(ficha()), []);
  assert.deepStrictEqual(F.avisosPublicacion(ficha({ textos: { title: { es: 'a', en: 'b' }, desc: { es: 'x' } } })), ['La descripción en inglés está vacía.']);
});

// ── forma, espejo del servidor ──
caso('problemas de forma: topes, < >, fijo fuera de Signature, importe, años, listas', () => {
  const f = ficha();
  const v = (x) => F.problemasForma(edita(f, x), f);
  assert.deepStrictEqual(v({}), []);
  assert.ok(v({ t_title_es: 'x'.repeat(121) }).length);
  assert.ok(v({ t_desc_en: 'x'.repeat(3001) }).length);
  assert.deepStrictEqual(v({ t_desc_en: 'x'.repeat(3000) }), []);
  assert.ok(v({ t_sub_es: 'hola <b>' }).length);
  assert.ok(v({ highlights: new Array(21).fill('a') }).length);
  assert.ok(v({ highlights: ['x'.repeat(161)] }).length);
  assert.ok(v({ tech_specs: [{ l: 'solo rótulo', v: '' }] }).length);
  assert.ok(v({ tech_specs: [{ l: 'x'.repeat(41), v: 'a' }] }).length);
  assert.ok(v({ poolType: 'x'.repeat(81) }).length);
  assert.ok(v({ view: 'x'.repeat(61) }).length);
  assert.ok(v({ linea: 'villa', precio_modo: 'fijo' }).length, 'fijo solo en Signature');
  assert.ok(v({ precio_eur: 'abc' }).length);
  assert.ok(v({ precio_eur: '2000000000' }).length);
  assert.ok(v({ lease_years: '100' }).length);
  assert.ok(v({ lease_years: '0' }).length);
  assert.ok(v({ orden: 'tres' }).length);
  assert.ok(v({ linea: 'villa', unidad_id: 'u9' }).length, 'unidad solo en Signature');
  assert.deepStrictEqual(F.problemasForma(edita(ficha({ linea: 'villa', unidad_id: 'u1', precio_modo: 'desde' }), { view: 'x' }), ficha({ linea: 'villa', unidad_id: 'u1', precio_modo: 'desde' })), [], 'una unidad que ya estaba no se reprocha');
});

// ── errores en español llano ──
caso('errores: 42501, 40001, 22023/23514 sin el nombre de la regla, P0002, red', () => {
  assert.strictEqual(F.errorLegible({ code: '42501', message: 'La ficha pública la edita administración' }), 'Solo administración puede editar la ficha pública.');
  assert.strictEqual(F.errorLegible({ code: '40001', message: 'Otra persona cambió esta ficha; recárgala' }), 'Otra persona cambió esta ficha; recárgala');
  assert.strictEqual(F.errorLegible({ code: '23514', message: 'Algún dato está fuera de rango o falta para guardar la ficha (regla ficha_publicada_completa)' }),
    'Algún dato está fuera de rango o falta para guardar la ficha');
  assert.strictEqual(F.errorLegible({ code: '22023', message: 'El título es demasiado largo' }), 'El título es demasiado largo');
  assert.strictEqual(F.errorLegible({ code: 'P0002', message: 'Ese proyecto no existe' }), 'Ese proyecto ya no existe: recarga la pantalla.');
  assert.strictEqual(F.errorLegible({ code: '42501', message: 'x' }, 'No se pudo publicar'), 'No se pudo publicar: Solo administración puede editar la ficha pública.');
  const G = carga({ lwErrorHumano: (e, p) => (p ? p + ': ' : '') + 'sin conexión' });
  assert.strictEqual(G.errorLegible(new TypeError('Failed to fetch'), 'No se pudo guardar'), 'No se pudo guardar: sin conexión');
  assert.ok(!/ficha_publicada_completa|constraint/i.test(F.errorLegible({ code: '23514', message: 'Algo (regla ficha_precio_fijo_signature)' })));
});

// ── dirección (slug) ──
caso('normalizar y validar el slug', () => {
  assert.strictEqual(F.normalizaSlug('Pura Dalem II'), 'pura-dalem-ii');
  assert.strictEqual(F.normalizaSlug('  Villa  Águila — Ubud!! '), 'villa-aguila-ubud');
  assert.strictEqual(F.normalizaSlug('--a--b--'), 'a-b');
  assert.strictEqual(F.normalizaSlug('x'.repeat(80)).length, 60);
  assert.strictEqual(F.normalizaSlug(null), '');
  assert.ok(F.slugValido('pura-dalem') && F.slugValido('abc'));
  assert.ok(!F.slugValido('ab') && !F.slugValido('Pura-Dalem') && !F.slugValido('a--b') && !F.slugValido('-ab') && !F.slugValido('a'.repeat(61)));
  assert.ok(F.slugValido(F.normalizaSlug('Riverfront II — Small')));
});

// ── sonda de existencia del slug (el servidor edita en silencio si el slug ya existe y no hay p_version) ──
caso('sonda del slug: «ya no existe» = libre; «otra persona cambió» = existe; cualquier otra cosa = no crear', () => {
  assert.strictEqual(F.interpretaSonda({ code: '40001', message: 'Esa ficha ya no existe; recarga la pantalla' }), 'libre');
  assert.strictEqual(F.interpretaSonda({ code: '40001', message: 'Otra persona cambió esta ficha; recárgala' }), 'existe');
  assert.strictEqual(F.interpretaSonda({ code: '42501', message: 'x' }), 'error');
  assert.strictEqual(F.interpretaSonda({ code: '22023', message: 'La dirección solo admite' }), 'error');
  assert.strictEqual(F.interpretaSonda(null), 'error');
  assert.strictEqual(F.interpretaSonda({ message: 'Failed to fetch' }), 'error');
});
caso('la sonda no escribe: manda parche vacío y una versión imposible', async () => {
  const llamadas = [];
  const sb = { rpc: (n, a) => { llamadas.push([n, a]); return Promise.resolve({ error: { code: '40001', message: 'Esa ficha ya no existe; recarga la pantalla' } }); } };
  const r = await F.existeSlug(sb, 'villa-nueva');
  assert.strictEqual(r, 'libre');
  assert.deepStrictEqual(llamadas, [['ficha_publica_guarda', { p_slug: 'villa-nueva', p_cambios: {}, p_version: F.VERSION_IMPOSIBLE }]]);
});

// ── lo que se enseña de lo que sirve la web ──
caso('precio público: desde / fijo / consultar a partir de `publico`', () => {
  assert.strictEqual(F.precioPublico(null), 'Consultar (sin precio)');
  assert.strictEqual(F.precioPublico({ priceEUR: null }), 'Consultar (sin precio)');
  assert.ok(/^Desde /.test(F.precioPublico({ priceEUR: 63875, priceMode: 'from' })));
  assert.ok(!/^Desde/.test(F.precioPublico({ priceEUR: 250000, priceMode: 'fixed' })));
});

// ── el módulo no pinta datos como marcado ──
caso('el módulo no escribe datos de la base con innerHTML sin esc() ni usa sb.from/localStorage', () => {
  const codigo = fuente.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  assert.ok(!/sb\.from\(|localStorage|console\.log|\.insert\(|\.upsert\(/.test(codigo), 'nada de tablas directas, localStorage ni console.log');
  assert.ok(/p_proyecto_id: proy\.id/.test(codigo) && !/p_proyecto\s*:/.test(codigo), 'el proyecto se engancha por id, nunca por nombre');
  assert.ok(!/innerHTML\s*=[^;]*(f|estado|proy|u|m)\.(slug|nombre|codigo)/.test(codigo.replace(/esc\([^)]*\)/g, '')), 'un dato de la base en innerHTML sin esc()');
});

process.on('beforeExit', () => { if (!process.exitCode) console.log('ficha_publica.test.js: ' + n + ' casos ok'); });
