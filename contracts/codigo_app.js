/* ═══════════════════════════════════════════════════════════════════════════
   «EL CÓDIGO DE LA APP DE CONTRATOS» — 21-ago-2026
   Lo usan los .test.js. No lo carga ninguna página.
   ═══════════════════════════════════════════════════════════════════════════
   POR QUÉ EXISTE. Los tests leían `app.html` y buscaban dentro. El 21-ago se
   sacaron de ahí cinco bloques a `assets/*.js` (el fichero tenía 5.831 líneas) y
   DOS TESTS SE PUSIERON EN ROJO al momento: seguían mirando solo el .html, así
   que lo que se había mudado les parecía borrado.

   Cazarlo estaba bien —eso es tener red— pero arreglarlo test a test habría
   dejado la misma trampa para la siguiente extracción: nadie se acuerda de
   actualizar tres tests cuando mueve una función.

   Así que «el código de la app» pasa a ser lo que de verdad se ejecuta: el
   .html MÁS todos los assets que ese .html carga, descubiertos leyendo sus
   propias etiquetas <script src>. Mover código de un sitio a otro deja de ser
   un cambio visible para los tests, que es lo correcto: no ha cambiado nada de
   lo que la app hace.
   ═══════════════════════════════════════════════════════════════════════════ */
const fs = require('fs');
const path = require('path');

const AQUI = __dirname;

function html() {
  return fs.readFileSync(path.join(AQUI, 'app.html'), 'utf8');
}

/** Los assets que app.html carga, en el MISMO orden que el navegador. */
function assets() {
  return [...html().matchAll(/<script src="(?:\/contracts\/)?assets\/([\w.-]+\.js)\?/g)]
    .map(m => m[1])
    .filter(n => fs.existsSync(path.join(AQUI, 'assets', n)));
}

/** El .html y sus assets, concatenados. Es lo que hay que registrar. */
function todo() {
  return [html(), ...assets().map(n => fs.readFileSync(path.join(AQUI, 'assets', n), 'utf8'))]
    .join('\n/* ── siguiente fichero ── */\n');
}

module.exports = { html, assets, todo };
