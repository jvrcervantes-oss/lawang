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
  const sha = require('crypto').createHash('sha1').update(fs.readFileSync(path.join(__dirname, 'motion.js'))).digest('hex').slice(0, 8);
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

assert.deepStrictEqual(errores, [], '\n  ' + errores.join('\n  '));
console.log('nav.test.js OK');
