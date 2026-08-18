/* ═══════════════════════════════════════════════════════════════════════════
   EL MISMO DATO EN VARIOS SITIOS — 17-ago-2026 (auditoría, ficha LAW-48)
   `node listas.test.js`. Lo corre `tools/test.py`, y con él el gate de push.
   ═══════════════════════════════════════════════════════════════════════════
   ESTE TEST NO PRUEBA UNA FUNCIÓN. Afirma un HECHO contra todos los sitios donde
   vive, y falla cuando uno se desvía. Es el tipo de test que más rinde en este
   repo, porque los fallos caros de esta suite no han sido funciones mal escritas:
   han sido listas escritas a mano en dos sitios que se separaron.

   El historial, que es también la lista de casos de abajo:

     · 14-ago-2026 — el nombre de cada tipo de contrato estaba en `TIPO_ES`
       (operaciones) y en `TIPO_LABEL` (contracts): 'reserva_parcela' salía
       «Bloqueo de Parcela» en una pantalla y «Parcela» en la otra, y a una le
       faltaban tres tipos, así que SEIS contratos reales enseñaban la clave
       cruda de la base de datos.
     · 14-ago-2026 — 'poa' estaba en la app y en la numeración pero no en el
       CHECK de Postgres: 400 al guardar un Poder Notarial.
     · 5, 11 y 17-ago-2026 — la lista de herramientas de `admin-usuarios` se
       quedó corta TRES veces respecto al panel de permisos, y las tres pasaron
       desapercibidas porque la función descartaba en silencio.
     · 17-ago-2026 — la casilla del inventario decía «Unidades» donde el hub y
       el menú dicen «Proyectos».

   NO LEE LA BASE DE DATOS a propósito: un test del gate de push no puede
   depender de la red ni de tener a mano la clave secreta. Lee
   `sql/tipos_de_contrato.sql`, que desde hoy es la declaración ÚNICA del lado
   Postgres (de ahí se generan el CHECK y la función de numeración). Que ese
   fichero esté aplicado de verdad es otra comprobación, la del catálogo, y está
   escrita al final del propio .sql.
   ═══════════════════════════════════════════════════════════════════════════ */
const fs = require('fs');
const path = require('path');

const aqui = (...p) => path.join(__dirname, ...p);
const leer = (...p) => fs.readFileSync(aqui(...p), 'utf8');

let fallos = 0;
function comprueba(titulo, a, nombreA, b, nombreB) {
  const sa = new Set(a), sb = new Set(b);
  const soloA = [...sa].filter(x => !sb.has(x));
  const soloB = [...sb].filter(x => !sa.has(x));
  if (soloA.length || soloB.length) {
    fallos++;
    console.error(`\n  FALLA  ${titulo}`);
    if (soloA.length) console.error(`         en ${nombreA} y NO en ${nombreB}: ${soloA.join(', ')}`);
    if (soloB.length) console.error(`         en ${nombreB} y NO en ${nombreA}: ${soloB.join(', ')}`);
  }
}
function igual(titulo, a, b, comoA, comoB) {
  if (a !== b) {
    fallos++;
    console.error(`\n  FALLA  ${titulo}\n         ${comoA} dice "${a}" · ${comoB} dice "${b}"`);
  }
}

/* ── Lectura de cada sitio ────────────────────────────────────────────────
   Se parsea con expresión regular y no evaluando el fichero: `app.html` son
   4.600 líneas que tocan el DOM en cuanto se cargan, así que no se puede
   `require`. La regla al escribir estos lectores: si el bloque cambia de forma,
   el lector devuelve vacío y el test FALLA — nunca pasa por no haber encontrado
   nada. De ahí los `assert` de tamaño mínimo. */
const APP  = leer('app.html');
const VOC  = leer('assets', 'vocabulario.js');
const HERR = leer('assets', 'herramientas.js');
const EDGE = leer('edge', 'admin-usuarios', 'index.ts');
const FSUB = leer('edge', 'firma-submit', 'index.ts');
const SQL  = leer('sql', 'tipos_de_contrato.sql');

function bloque(txt, arranque, quien) {
  const i = txt.indexOf(arranque);
  if (i < 0) { fallos++; console.error(`\n  FALLA  no encuentro «${arranque}» en ${quien} — ¿le cambiaron el nombre?`); return ''; }
  // hasta la primera llave/corchete de cierre a principio de línea
  const resto = txt.slice(i);
  const fin = resto.search(/\n\s*[}\]];/);
  return fin < 0 ? resto : resto.slice(0, fin);
}
/* `[a-z][a-z0-9_]*` y no `[a-z_]+`: los nombres LLEVAN DÍGITOS —`ppjb_bonian_c2`—
   y con la clase sin dígitos este test se estrenó diciendo que faltaba un tipo
   que sí estaba. Lo cazó el mínimo de entradas de más abajo, que es para lo que
   está: un lector roto y un dato que falta se parecen mucho desde aquí. */
const claves = s => [...s.matchAll(/(?:^|[{,\s])([a-z_][a-z0-9_]*)\s*:/gim)].map(m => m[1]);
const valores = s => [...s.matchAll(/:\s*'([^']+)'/g)].map(m => m[1]);

// 1 · app.html — qué tipos conoce la aplicación, y con qué serie
const APP_TIPOS   = valores(bloque(APP, 'const CONTRACT_TIPO = {', 'app.html'));
const PREFIX_BLQ  = bloque(APP, 'const TIPO_PREFIX = {', 'app.html');
const APP_PREFIJO = Object.fromEntries(
  [...PREFIX_BLQ.matchAll(/([a-z_][a-z0-9_]*)\s*:\s*'([A-Z0-9]{2})'/g)].map(m => [m[1], m[2]]));

// 2 · vocabulario.js — cómo se llaman en pantalla
const VOC_TIPOS = claves(bloque(VOC, 'const LW_TIPO_CONTRATO = {', 'vocabulario.js'));

// 3 · sql/tipos_de_contrato.sql — la declaración del lado Postgres
const SQL_FILAS = [...SQL.matchAll(/\[\s*'([a-z][a-z0-9_]*)'\s*,\s*'([A-Z0-9]{2})'\s*,\s*'([a-z0-9_.]+)'\s*\]/g)]
  .map(m => ({ tipo: m[1], prefijo: m[2], secuencia: m[3] }));

// 4 · las dos listas de herramientas
const CAT_PERMISOS = [...bloque(HERR, 'const LW_HERRAMIENTAS = [', 'herramientas.js')
  .matchAll(/herr\s*:\s*(\[[^\]]*\]|'[^']*')/g)]
  .flatMap(m => [...m[1].matchAll(/'([a-z][a-z0-9_]*)'/g)].map(x => x[1]));
const EDGE_HERR = [...(EDGE.match(/const HERRAMIENTAS = \[([^\]]*)\]/) || ['', ''])[1]
  .matchAll(/'([a-z][a-z0-9_]*)'/g)].map(m => m[1]);

// 5 · los tipos que emiten proforma automática, que están en DOS caminos
const proformaDe = (txt, quien) => {
  const m = txt.match(/TIPOS_CON_PROFORMA_AUTO\s*=\s*\[([^\]]*)\]/);
  if (!m) { fallos++; console.error(`\n  FALLA  no encuentro TIPOS_CON_PROFORMA_AUTO en ${quien}`); return []; }
  return [...m[1].matchAll(/'([a-z][a-z0-9_]*)'/g)].map(x => x[1]);
};

/* ── Que los lectores han leído algo ─────────────────────────────────────
   Un test que compara dos listas vacías pasa siempre y no protege nada. */
[['CONTRACT_TIPO', APP_TIPOS, 13], ['TIPO_PREFIX', Object.keys(APP_PREFIJO), 13],
 ['LW_TIPO_CONTRATO', VOC_TIPOS, 13], ['tipos_de_contrato.sql', SQL_FILAS, 13],
 ['LW_HERRAMIENTAS.herr', CAT_PERMISOS, 11], ['HERRAMIENTAS (edge)', EDGE_HERR, 11],
].forEach(([nombre, lista, minimo]) => {
  if (lista.length < minimo) {
    fallos++;
    console.error(`\n  FALLA  de ${nombre} he leído ${lista.length} entradas y esperaba al menos ${minimo}.`);
    console.error(`         O se ha borrado algo, o el bloque cambió de forma y este test dejó de verlo.`);
    console.error(`         Si de verdad hay menos, baja el mínimo en listas.test.js — pero míralo antes.`);
  }
});

/* ── LOS TIPOS DE CONTRATO ───────────────────────────────────────────────── */
const SQL_TIPOS = SQL_FILAS.map(f => f.tipo);

comprueba('los tipos de la app no son los que admite la base de datos',
  APP_TIPOS, 'CONTRACT_TIPO (app.html)', SQL_TIPOS, 'tipos_de_contrato.sql');

comprueba('hay un tipo sin nombre visible: el listado enseñaría la clave cruda',
  SQL_TIPOS, 'tipos_de_contrato.sql', VOC_TIPOS, 'LW_TIPO_CONTRATO (vocabulario.js)');

comprueba('hay un tipo sin serie de numeración en la app',
  SQL_TIPOS, 'tipos_de_contrato.sql', Object.keys(APP_PREFIJO), 'TIPO_PREFIX (app.html)');

// El prefijo, uno a uno: dos listas pueden tener los mismos tipos y no el mismo
// prefijo, y eso emite un contrato con la serie de otro.
SQL_FILAS.forEach(f => {
  if (APP_PREFIJO[f.tipo])
    igual(`el tipo «${f.tipo}» tiene dos series distintas`,
      APP_PREFIJO[f.tipo], f.prefijo, 'TIPO_PREFIX (app.html)', 'tipos_de_contrato.sql');
});

// Dos tipos con el mismo prefijo comparten serie: dos documentos distintos con
// números que se pisan.
const porPrefijo = {};
SQL_FILAS.forEach(f => { (porPrefijo[f.prefijo] = porPrefijo[f.prefijo] || []).push(f.tipo); });
Object.entries(porPrefijo).filter(([, t]) => t.length > 1).forEach(([p, t]) => {
  fallos++;
  console.error(`\n  FALLA  la serie ${p} la usan ${t.length} tipos: ${t.join(', ')}\n         Dos tipos con la misma serie emiten números repetidos.`);
});

/* ── LAS HERRAMIENTAS ────────────────────────────────────────────────────── */
comprueba('el catálogo y la edge de usuarios no conocen las mismas herramientas',
  CAT_PERMISOS, 'LW_HERRAMIENTAS (herramientas.js)', EDGE_HERR, 'admin-usuarios/index.ts');

// El panel de permisos ya NO tiene lista propia (17-ago): la deriva del catálogo.
// Si alguien le vuelve a escribir una, esto lo dice.
const PANEL = fs.readFileSync(aqui('..', 'usuarios', 'index.html'), 'utf8');
if (/const HERRAMIENTAS = \[/.test(PANEL)) {
  fallos++;
  console.error('\n  FALLA  /usuarios/ ha vuelto a tener su propia lista de herramientas.');
  console.error('         Tiene que ser `const HERRAMIENTAS = LW_PERMISOS`. Con lista propia, sus');
  console.error('         etiquetas divergen del hub — ya pasó con «Unidades» vs «Proyectos».');
}

/* ── LA PROFORMA AUTOMÁTICA ──────────────────────────────────────────────
   Está por duplicado a propósito (son dos caminos: al guardar y al firmar), y
   por eso mismo necesita quien los compare. */
comprueba('los tipos que emiten proforma automática no coinciden entre los dos caminos',
  proformaDe(APP, 'app.html'), 'app.html (al guardar)',
  proformaDe(FSUB, 'firma-submit'), 'firma-submit (al firmar)');

/* ── Salida ──────────────────────────────────────────────────────────────── */
if (fallos) {
  console.error(`\nlistas.test.js — ${fallos} divergencia(s). Cada una es un dato que dice`);
  console.error('dos cosas distintas según dónde se mire. No es estilo: es el fallo.\n');
  process.exit(1);
}
console.log(`OK listas.test.js — ${SQL_FILAS.length} tipos de contrato y ${EDGE_HERR.length} herramientas, de acuerdo en los 6 sitios donde viven`);
