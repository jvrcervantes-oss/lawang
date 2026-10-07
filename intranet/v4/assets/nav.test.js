/* node nav.test.js — el menú de la v4 y la puerta de cada página dicen lo mismo
   (23-sep-2026, S17).
   `CLAVE_MENU` (nav.js) decide qué herramientas ofrece la sidebar a cada
   sesión; `data-herramienta` en el <script> de guard.js de cada página decide
   quién entra. Si se separan, el menú ofrece una herramienta que rebota al hub
   o esconde una que la sesión sí puede abrir. Esto falla en cuanto no casen. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const V4 = path.resolve(__dirname, '..');
const nav = fs.readFileSync(path.join(__dirname, 'nav.js'), 'utf8');
const m = nav.match(/var CLAVE_MENU = (\{[\s\S]*?\});/);
assert.ok(m, 'nav.js ya no declara CLAVE_MENU como objeto literal');
const CLAVE_MENU = Function('return ' + m[1])();

/* MOTION_V (26-sep-2026): nav.js carga motion.js con una versión escrita a mano,
   que sella_assets no ve. El CDN de Hostinger cachea los JS una semana: una
   versión sin subir sirve el motion.js viejo siete días sin un error. */
{
  const mv = nav.match(/var MOTION_V = '([0-9a-f]{8})'/);
  assert.ok(mv, 'nav.js ya no declara MOTION_V como hash de 8');
  const sha = require('crypto').createHash('sha1').update(fs.readFileSync(path.join(__dirname, 'motion.js'), 'utf8').replace(/\r\n/g, '\n')).digest('hex').slice(0, 8);
  assert.strictEqual(mv[1], sha, `MOTION_V (${mv[1]}) no es el sha1 de motion.js (${sha}): súbelo en nav.js`);
}

const norma = k => [].concat(k).slice().sort().join(',');
const errores = [];

for (const carpeta of fs.readdirSync(V4, { withFileTypes: true })) {
  if (!carpeta.isDirectory() || carpeta.name === 'assets') continue;
  const f = path.join(V4, carpeta.name, 'index.html');
  if (!fs.existsSync(f)) continue;
  const s = fs.readFileSync(f, 'utf8');
  /* editores.js confirma con lwConfirmar (dialogo.js) desde S17: sin la
     ETIQUETA real, el botón responde «el diálogo aún no ha cargado». Un
     comentario que menciona dialogo.js no cuenta — así se coló en proyectos/
     y modelos/ la primera vez (23-sep-2026). */
  if (/<script[^>]+src="[^"]*editores\.js/.test(s) && !/<script[^>]+src="[^"]*dialogo\.js/.test(s)) {
    errores.push(`${carpeta.name}: carga editores.js sin <script> de dialogo.js`);
  }
  const g = s.match(/<script[^>]+guard\.js[^>]*>/);
  if (!g) continue;                                   // redirección o puerta: sin guard no hay clave que casar
  const d = g[0].match(/data-herramienta="([^"]*)"/);
  const puerta = d ? norma(d[1].split(',')) : '';
  const menu = CLAVE_MENU[carpeta.name] ? norma(CLAVE_MENU[carpeta.name]) : '';
  /* «Comisiones» es una entrada con cuatro pestañas (23-sep-2026): la entrada
     se ve con CUALQUIERA de sus cuatro casillas y cada pestaña pide la suya.
     Ahí basta con que la casilla de la página esté entre las de la entrada. */
  if (carpeta.name === 'comisiones' && menu.split(',').indexOf(puerta) !== -1) continue;
  if (puerta !== menu) errores.push(`${carpeta.name}: guard.js pide «${puerta || '—'}», el menú «${menu || '—'}»`);
}

// y ninguna entrada del mapa apunta a una carpeta que no existe
for (const k of Object.keys(CLAVE_MENU)) {
  if (!fs.existsSync(path.join(V4, k, 'index.html'))) errores.push(`${k}: está en CLAVE_MENU y no hay intranet/v4/${k}/`);
}

/* MENÚ DECLARADO (27-sep-2026): MENU_V4 es la fuente de las secciones y los nombres del
   menú Y de las casillas de /v4/usuarios/. Se ejecuta el nav.js REAL fuera de la v4 (sale
   temprano, pero antes deja `window.LW_MENU_V4`). */
const vm = require('vm');
const ctxM = { window: {}, location: { pathname: '/fuera/' }, document: { documentElement: { classList: { contains: () => false } } } };
vm.createContext(ctxM);
vm.runInContext(nav, ctxM);
const MENU = ctxM.window.LW_MENU_V4;
assert.ok(Array.isArray(MENU) && MENU.length >= 5, 'nav.js ya no expone window.LW_MENU_V4 antes de salir');
const RAIZ = path.resolve(V4, '..', '..');
const ctxP = { window: { AXW_NUCLEO_OPERACION: true } };
vm.createContext(ctxP);
vm.runInContext(fs.readFileSync(path.join(RAIZ, 'contracts', 'assets', 'herramientas.js'), 'utf8') + '\n;this.__P = LW_PERMISOS.map(p => p[0]);', ctxP);
const PERMISOS = ctxP.__P;
const enMenu = [];
const puerta = carpeta => {
  const f = path.join(V4, carpeta, 'index.html');
  if (!fs.existsSync(f)) return null;
  const g = fs.readFileSync(f, 'utf8').match(/<script[^>]+guard\.js[^>]*>/);
  if (!g) return { herr: '', rol: '' };
  return { herr: ((g[0].match(/data-herramienta="([^"]*)"/) || [])[1] || ''), rol: ((g[0].match(/data-rol="([^"]*)"/) || [])[1] || ''),
    ambito: ((g[0].match(/data-ambito="([^"]*)"/) || [])[1] || '') };
};
// leads y creatividades de la v4 son redirecciones (sin guard): su puerta vive en la herramienta viva
const SIN_PUERTA_V4 = ['leads'];
const casaPuerta = (p, clave, rol, donde) => {
  const q = puerta(p);
  if (!q) return errores.push(`MENU_V4 ${donde}: no hay intranet/v4/${p}/`);
  if (SIN_PUERTA_V4.indexOf(p) !== -1 && !q.herr && !q.rol) return;
  if (clave && norma(q.herr.split(',')) !== norma(clave.split(','))) errores.push(`MENU_V4 ${donde}: la puerta de ${p}/ pide «${q.herr || '—'}» y el menú «${clave}»`);
  if (rol && q.rol !== rol) errores.push(`MENU_V4 ${donde}: la puerta de ${p}/ pide rol «${q.rol || '—'}» y el menú «${rol}»`);
};
/* Empresas (7-oct-2026): una entrada del menú marcada global: true es de TODA la instancia (Ajustes): su puerta tiene que cerrarse
   igual a un rol de empresa (data-ambito="global"), o el menú la esconde y la URL directa la abre. */
const casaAmbito = (e, donde) => {
  const q = e.path && puerta(e.path);
  if (e.global && (!q || q.ambito !== 'global')) errores.push(`MENU_V4 ${donde}: es de la instancia (global: true) y la puerta de ${e.path}/ no lleva data-ambito="global"`);
  if (!e.global && q && q.ambito === 'global') errores.push(`MENU_V4 ${donde}: la puerta de ${e.path}/ es global (data-ambito) y el menú no lo marca global: true`);
};
/* `solo` (7-oct-2026, owner): Comisión de administración = «super-global», Sociedades emisoras = «propietario». La puerta de la página lleva
   el mismo data-ambito, o el menú la esconde y la URL directa la abre. */
const casaSolo = (e, donde) => {
  const q = e.path && puerta(e.path);
  if (e.solo && (!q || q.ambito !== e.solo)) errores.push(`MENU_V4 ${donde}: es solo «${e.solo}» y la puerta de ${e.path}/ lleva data-ambito «${(q && q.ambito) || '—'}»`);
  if (!e.solo && q && (q.ambito === 'super-global' || q.ambito === 'propietario')) errores.push(`MENU_V4 ${donde}: la puerta de ${e.path}/ es «${q.ambito}» y el menú no lo marca solo: '${q.ambito}'`);
};
MENU.forEach(s => s.entradas.forEach(e => {
  const donde = `${s.seccion} › ${e.texto}`;
  // `mismaCasilla` (30-sep-2026, Emitir contrato): la entrada abre con la casilla de OTRA entrada a propósito;
  // no cuenta como casilla repetida, pero su puerta sí se casa abajo (casaPuerta) como la de cualquiera.
  if (e.clave && !e.mismaCasilla) enMenu.push(e.clave);
  (e.claves || []).forEach(c => enMenu.push(c.clave));
  (e.extra || []).forEach(c => enMenu.push(c.clave));
  if (e.path) { casaPuerta(e.path, e.clave || (e.claves || []).map(c => c.clave).join(','), e.rol, donde); casaAmbito(e, donde); casaSolo(e, donde); }
  (e.pestanas || []).forEach(t => { enMenu.push(t.clave); casaPuerta(t.path, t.clave, t.rol, donde + ' › ' + t.texto); });
}));
/* El menú lateral injertado (PANEL_CONTROL_SUPER) tiene que decir lo mismo que MENU_V4 y que la puerta: cada entrada con su `solo` (7-oct-2026). */
{
  const bloque = (nav.match(/var PANEL_CONTROL_SUPER = \[([\s\S]*?)\];/) || [])[1] || '';
  const dePanel = {};
  (bloque.match(/\{[^}]*\}/g) || []).forEach(o => { dePanel[(o.match(/path: '([^']+)'/) || [])[1]] = (o.match(/solo: '([^']+)'/) || [])[1]; });
  MENU.forEach(s => s.entradas.forEach(e => { if (e.solo && dePanel[e.path] !== e.solo) errores.push(`PANEL_CONTROL_SUPER: «${e.path}» debería llevar solo: '${e.solo}' y lleva '${dePanel[e.path] || '—'}'`); }));
  Object.keys(dePanel).forEach(k => { if (!dePanel[k]) errores.push(`PANEL_CONTROL_SUPER: «${k}» no lleva solo: la vería un super de empresa`); });
  if (!/function veSolo\(solo, ficha\)[\s\S]*esPropietario[\s\S]*esSuperGlobal/.test(nav)) errores.push('nav.js: falta veSolo con esPropietario y esSuperGlobal');
}
const dup = enMenu.filter((k, i) => enMenu.indexOf(k) !== i);
if (dup.length) errores.push('MENU_V4: casillas en dos sitios del menú: ' + dup.join(', '));
PERMISOS.filter(k => enMenu.indexOf(k) === -1).forEach(k => errores.push(`«${k}» existe en LW_PERMISOS y MENU_V4 no la sitúa: en Usuarios saldría en «Otras»`));
enMenu.filter(k => PERMISOS.indexOf(k) === -1).forEach(k => errores.push(`MENU_V4 ofrece la casilla «${k}» y LW_PERMISOS (ni la edge admin-usuarios) no la conoce`));

// cada enlace de la sidebar (Stitch + INJERTOS + Panel de control) está en MENU_V4 con el MISMO texto,
// salvo los que pasan a ser pestañas (su nombre manda en la barra de pestañas).
const entradaDe = {}, pestanaDe = {};
MENU.forEach(s => s.entradas.forEach(e => {
  if (e.path) entradaDe[e.path] = e.texto;
  if (e.grupo) entradaDe[e.grupo] = e.texto;
  (e.pestanas || []).forEach(t => { pestanaDe[t.path] = t.texto; });
}));
const sidebar = fs.readFileSync(path.join(V4, 'usuarios', 'index.html'), 'utf8');
const aside = sidebar.slice(sidebar.indexOf('<aside'), sidebar.indexOf('</aside>'));
const vistos = [];
for (const m of aside.matchAll(/data-path="([^"]+)"/g)) {
  const p = m[1]; vistos.push(p);
  if (p === 'login' || p === 'documentacion' || pestanaDe[p]) continue;
  if (!entradaDe[p]) errores.push(`sidebar: «${p}» no está en MENU_V4`);
}
assert.ok(vistos.length > 8, 'no se leyó la sidebar de usuarios/index.html');
const specs = nombre => [...((nav.match(new RegExp('var ' + nombre + ' = \\[([\\s\\S]*?)\\];')) || ['', ''])[1]
  .matchAll(/path:\s*'([^']+)'[^}]*?texto:\s*'([^']+)'/g))];
['INJERTOS', 'PANEL_CONTROL', 'PANEL_CONTROL_SUPER'].forEach(n => {
  const lista = specs(n);
  assert.ok(lista.length, 'nav.js ya no declara ' + n);
  lista.forEach(([, p, t]) => {
    if (pestanaDe[p]) return;
    if (!entradaDe[p]) errores.push(`${n}: «${p}» no está en MENU_V4`);
    else if (entradaDe[p] !== t) errores.push(`${n}: «${p}» se llama «${t}» en el menú y «${entradaDe[p]}» en MENU_V4`);
  });
});

// Documentación NO vuelve al menú ni a la clásica (27-sep-2026)
const navSinComentarios = nav.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
if (/FUERA_V4|\/intranet\/documentacion\//.test(navSinComentarios)) errores.push('nav.js vuelve a mandar a /intranet/documentacion/ (retirada el 27-sep-2026)');
if (CLAVE_MENU.documentacion) errores.push('CLAVE_MENU vuelve a tener «documentacion»: la entrada del menú está retirada (vive en Proyectos)');

/* CABECERA COMPARTIDA (27-sep-2026). La paleta (window.LW_TONOS), la campana y el
   usuario viven en cabecera.js, y datos.js los LEE al cargar: una pantalla que
   cargue datos.js sin cabecera.js DELANTE se queda sin colores ni campana. */
const posScript = (s, fich) => { const m = new RegExp('<script[^>]+src="[^"]*' + fich.replace('.', '\\.') + '[^"]*"').exec(s); return m ? m.index : -1; };
for (const carpeta of fs.readdirSync(V4, { withFileTypes: true })) {
  if (!carpeta.isDirectory() || carpeta.name === 'assets') continue;
  const f = path.join(V4, carpeta.name, 'index.html');
  if (!fs.existsSync(f)) continue;
  const s = fs.readFileSync(f, 'utf8');
  const d = posScript(s, 'assets/datos.js');
  if (d === -1) continue;
  const c = posScript(s, 'assets/cabecera.js');
  if (c === -1 || c > d) errores.push(`${carpeta.name}: carga datos.js sin cabecera.js delante`);
}
/* CROMO v4 EN LAS PÁGINAS VIVAS DE FUERA DE /intranet/v4/ (27-sep-2026, owner: el CRM
   primero y después «archivar lo muerto + v4 en todo lo vivo»). Cada una lleva html.v4 +
   lw4-fijo (sin ellos nav.js sale y nav-montaje no pinta nada), declara su herramienta
   (la entrada que sale marcada; tiene que ser una entrada de MENU_V4, no una ruta nueva),
   carga nav-montaje.css y los tres scripts en orden — avisos.js, cabecera.js antes de
   nav-montaje.js (que la llama) y este antes de nav.js (que recablea el menú que monta).
   Sin topbar.js: serían dos menús. Y los botones que vivían en su barra clásica siguen
   ahí con el mismo id (su JS los ata al cargar). NO van aquí, a propósito: crear
   contraseña (intranet/contrasena/, sin sesión) y facturas en modo ?vista= (documento
   suelto que abren los correos). */
const PAGINAS_CROMO = [
  // [fichero, herramienta activa, ids que su JS ata al cargar, scripts extra delante de nav-montaje]
  ['intranet/leads/index.html', 'leads', ['btnRefrescar'], []],
  ['intranet/obra/index.html', 'obra', [], []],
  ['intranet/creatividades/redes/index.html', 'creatividades', ['btnPng', 'btnGuardar', 'btnEnviar'], []],
  ['intranet/dossier/builder.html', 'creatividades', ['topbar', 'btnGuardarD', 'btnEnviarD', 'sizesel', 'ptitle'], ['contracts/assets/desplegables.js']]
];
for (const [fich, herr, ids, extra] of PAGINAS_CROMO) {
  const s = fs.readFileSync(path.join(RAIZ, fich), 'utf8');
  const h = (s.match(/<html[^>]*>/) || [''])[0];
  if (!/class="[^"]*\bv4\b[^"]*\blw4-fijo\b/.test(h)) errores.push(`${fich}: el <html> no lleva class="v4 lw4-fijo"`);
  if (!new RegExp('data-lw4-herramienta="' + herr + '"').test(h)) errores.push(`${fich}: el <html> no declara data-lw4-herramienta="${herr}"`);
  if (!entradaDe[herr]) errores.push(`${fich}: «${herr}» no es una entrada de MENU_V4 (la marca de activa sale de allí)`);
  if (!/<link[^>]+nav-montaje\.css/.test(s)) errores.push(`${fich}: no carga intranet/v4/assets/nav-montaje.css`);
  const orden = ['contracts/assets/avisos.js', 'assets/cabecera.js', 'assets/nav-montaje.js', 'assets/nav.js'].map(x => posScript(s, x));
  if (orden.some(x => x === -1) || orden.some((x, i) => i && x < orden[i - 1])) errores.push(`${fich}: avisos.js, cabecera.js, nav-montaje.js y nav.js tienen que ir en ese orden`);
  if (posScript(s, 'topbar.js') !== -1) errores.push(`${fich}: vuelve a cargar topbar.js (la barra clásica) junto al menú v4`);
  if (/<header[^>]+class="[^"]*lw-topbar/.test(s)) errores.push(`${fich}: vuelve a llevar el header.lw-topbar de la barra clásica`);
  ids.forEach(id => { if (!new RegExp('id="' + id + '"').test(s)) errores.push(`${fich}: falta #${id} (su JS lo ata al cargar)`); });
  extra.forEach(x => { if (posScript(s, x) === -1) errores.push(`${fich}: no carga ${x}`); });
}
/* desplegables.js es la única copia del cierre de los <details> (salió de topbar.js):
   quien tenga un details.lw-menu tiene que cargarlo. */
for (const fich of ['intranet/dossier/builder.html', 'contracts/app.html', 'intranet/facturas/index.html', 'intranet/leads/index.html']) {
  const s = fs.readFileSync(path.join(RAIZ, fich), 'utf8');
  if (/<details[^>]+class="[^"]*\b(lw|pv)-menu\b/.test(s) && posScript(s, 'contracts/assets/desplegables.js') === -1) errores.push(`${fich}: tiene un details.lw-menu/.pv-menu y no carga desplegables.js`);
}
if (/details\.lw-menu/.test(fs.readFileSync(path.join(RAIZ, 'contracts', 'assets', 'topbar.js'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, ''))) errores.push('topbar.js vuelve a llevar el cierre de los <details>: vive en desplegables.js');

assert.deepStrictEqual(errores, [], '\n  ' + errores.join('\n  '));
console.log('nav.test.js OK (' + enMenu.length + ' casillas situadas en el menú)');
