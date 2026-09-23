/* node catalogo.test.js — S18 del encargo de paridad v4 (23-sep-2026).
   Falla si:
   1) una herramienta del catálogo (`LW_HERRAMIENTAS`, contracts/assets/
      herramientas.js) no tiene ruta en la v4 — ni pantalla ni redirección.
      Cuando la v4 sustituya a la intranet de siempre, esa herramienta
      desaparecería sin que nadie lo notara;
   2) una pantalla v4 que carga guard.js no declara QUIÉN entra: ni
      `data-herramienta` ni `data-rol`. Sin ninguna de las dos entra cualquier
      ficha activa del equipo (LAW-275). Única excepción declarada: Home;
   3) una pantalla del Panel de control (PANEL_CONTROL / PANEL_CONTROL_SUPER de
      nav.js, más Usuarios, que se mueve dentro) no pide el mismo rol en la
      puerta que el menú exige para enseñarla. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const V4 = path.resolve(__dirname, '..');
const RAIZ = path.resolve(V4, '..', '..');
const errores = [];

// --- 1) catálogo → ruta v4 ---
const ctx = { window: {} };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(RAIZ, 'contracts', 'assets', 'herramientas.js'), 'utf8') + '\n;this.__H = LW_HERRAMIENTAS;', ctx);
const HERR = ctx.__H;
assert.ok(Array.isArray(HERR) && HERR.length > 10, 'no se pudo leer LW_HERRAMIENTAS');
/* Las tres cuyo href clásico no se llama como su carpeta v4. Cada una con su
   motivo — una fila nueva aquí es una decisión, no un atajo para callar el test. */
const ALIAS = {
  '/contracts/': 'contratos',                     // el generador vive en /contracts/; la v4 lo llama Contratos
  '/intranet/facturas/?tipo=recibi': 'recibos',   // Recibos es una vista de Facturas en la clásica
  '/intranet/solicitudes/': 'comisiones',         // Solicitudes se renombró Comisiones (14-sep)
};
function carpetaV4(href) {
  if (ALIAS[href]) return ALIAS[href];
  const m = href.match(/^\/intranet\/(?:v4\/)?([^/?#]+)/);
  return m ? m[1].toLowerCase() : null;
}
HERR.forEach(t => {
  const c = carpetaV4(t.href || '');
  if (!c) return errores.push(`catálogo «${t.nombre}»: href ${t.href} no se sabe traducir a una ruta v4`);
  if (!fs.existsSync(path.join(V4, c, 'index.html'))) errores.push(`catálogo «${t.nombre}» (${t.href}): no hay intranet/v4/${c}/ — ni pantalla ni redirección`);
});

// --- 2) y 3) puertas de cada pantalla ---
const nav = fs.readFileSync(path.join(__dirname, 'nav.js'), 'utf8');
const pathsDe = nombre => {
  const m = nav.match(new RegExp('var ' + nombre + ' = \\[([\\s\\S]*?)\\];'));
  assert.ok(m, 'nav.js ya no declara ' + nombre);
  return (m[1].match(/path:\s*'([^']+)'/g) || []).map(x => x.match(/'([^']+)'/)[1]);
};
const SOLO_ADMIN = pathsDe('PANEL_CONTROL').concat(['usuarios']);   // Usuarios se MUEVE al Panel (injertaPanelControl)
const SOLO_SUPER = pathsDe('PANEL_CONTROL_SUPER');
const SIN_PUERTA_PROPIA = { home: 'el inicio: lo ve todo el equipo, y cada tarjeta enlaza a una puerta con su clave' };

for (const d of fs.readdirSync(V4, { withFileTypes: true })) {
  if (!d.isDirectory() || d.name === 'assets') continue;
  const f = path.join(V4, d.name, 'index.html');
  if (!fs.existsSync(f)) continue;
  const g = fs.readFileSync(f, 'utf8').match(/<script[^>]+guard\.js[^>]*>/);
  if (!g) continue;                                  // redirección o puerta de entrada
  const herr = /data-herramienta="[^"]+"/.test(g[0]);
  const rol = (g[0].match(/data-rol="([^"]+)"/) || [])[1] || '';
  const roles = rol.split(/\s+/).filter(Boolean);
  if (!herr && !rol && !SIN_PUERTA_PROPIA[d.name]) errores.push(`${d.name}: guard.js sin data-herramienta ni data-rol — entra cualquier ficha activa`);
  if (SOLO_SUPER.includes(d.name) && rol !== 'super_admin') errores.push(`${d.name}: el menú la enseña solo al super admin y la puerta pide «${rol || 'nada'}»`);
  else if (SOLO_ADMIN.includes(d.name) && !roles.includes('admin') && rol !== 'super_admin') errores.push(`${d.name}: el menú la enseña solo a admin y la puerta pide «${rol || 'nada'}»`);
}
/* PUERTAS FIJAS — decisión del owner, no se tocan nunca. Condiciones es
   solo de administración: el 23-sep-2026 una sesión le quitó el candado para
   que entraran los Sales Managers y quedó abierta a cualquier ficha; el owner:
   «vuelve a solo admin y esto no se mueve nunca». Va aparte de SOLO_ADMIN a
   propósito: sacarla del Panel de control en nav.js no la libera de aquí. Si
   un Sales Manager necesita configurar algo, va en otra pantalla. */
/* 23-sep-2026, misma tarde, el owner la amplía y luego lo agrupa todo bajo
   «Comisiones» («Necesitamos agrupar y controlar lo que se ve por permisos»):
   cada pestaña pide SU casilla, y Condiciones/Equipos además el rol admin o
   sales_manager. Sigue fijado: solo el owner lo cambia. */
const PUERTA_FIJA = {
  comisiones:      { rol: '',                    herr: 'comisiones' },
  reparto:         { rol: '',                    herr: 'comisiones_reparto' },
  condiciones:     { rol: 'admin sales_manager', herr: 'comisiones_condiciones' },
  'equipos-venta': { rol: 'admin sales_manager', herr: 'comisiones_equipos' }
};
Object.keys(PUERTA_FIJA).forEach(p => {
  const f = path.join(V4, p, 'index.html');
  const g = fs.existsSync(f) && fs.readFileSync(f, 'utf8').match(/<script[^>]+guard\.js[^>]*>/);
  const rol = g ? ((g[0].match(/data-rol="([^"]+)"/) || [])[1] || '') : '(sin página)';
  const herr = g ? ((g[0].match(/data-herramienta="([^"]+)"/) || [])[1] || '') : '(sin página)';
  const q = PUERTA_FIJA[p];
  if (rol !== q.rol || herr !== q.herr) errores.push(`${p}: puerta FIJADA por el owner (rol «${q.rol || 'ninguno'}», casilla «${q.herr}») y pide rol «${rol || 'ninguno'}», casilla «${herr || 'ninguna'}» — no se cambia`);
});
// cada pestaña de Comisiones que pinta nav.js pide la casilla con la que nav.js la enseña
const PEST = [...(nav.match(/var PESTANAS_COMISIONES = \[([\s\S]*?)\];/) || ['', ''])[1].matchAll(/path:\s*'([^']+)',\s*clave:\s*'([^']+)'/g)];
assert.ok(PEST.length === 4, 'nav.js ya no declara las 4 pestañas de PESTANAS_COMISIONES');
PEST.forEach(([, p, clave]) => {
  if (!PUERTA_FIJA[p] || PUERTA_FIJA[p].herr !== clave) errores.push(`${p}: nav.js la enseña con la casilla «${clave}» y la puerta fijada pide otra`);
});
[...SOLO_ADMIN, ...SOLO_SUPER].forEach(p => {
  if (!fs.existsSync(path.join(V4, p, 'index.html'))) errores.push(`${p}: está en el Panel de control de nav.js y no hay intranet/v4/${p}/`);
});

assert.deepStrictEqual(errores, [], '\n  ' + errores.join('\n  '));
console.log('catalogo.test.js OK (' + HERR.length + ' herramientas del catálogo con ruta v4)');
