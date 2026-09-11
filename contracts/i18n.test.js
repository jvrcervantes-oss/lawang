/* ============================================================================
   Guardrail del diccionario de interfaz — `assets/i18n.js`
   ----------------------------------------------------------------------------
   POR QUÉ EXISTE. Toda la suite se traduce sobre una promesa: **en español,
   `lwT()` devuelve su entrada**, así que la vista de siempre queda idéntica
   por construcción y no por haberla revisado. Esa promesa es lo único que
   hace barata cada entrada nueva del diccionario — y es exactamente lo que se
   rompió tres veces el 11-sep-2026 mientras se montaba:

     · normalizar la clave se comía el blanco final de `'No se pudo guardar: '`
       y el error salía pegado a los dos puntos (74 sitios);
     · envolver dentro de una cadena normal se comía el espacio de los bordes
       y `'<p>Se pierden <b>'` quedaba como «Se pierdentus ediciones» (28);
     · re-citar un literal que ya llevaba un escape (`entre sí`) duplicaba
       la barra e imprimía «sí».

   Las tres eran regresiones DEL ESPAÑOL, y ninguna la caza `node --check`.
   Este fichero las convierte en un test, que es el peldaño siguiente de la
   escalera: prosa → regla → guardrail mecánico.

   Corre en node, sin navegador:  node contracts/i18n.test.js
   ========================================================================== */
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const AQUI = __dirname;
const leer = f => fs.readFileSync(path.join(AQUI, 'assets', f), 'utf8');

/* i18n.js se cuelga de `window`; aquí se le da uno de mentira. */
const win = {};
new Function('window', leer('i18n.js'))(win);
const { lwT, lwLocale, LW_EN, LW_T_MISSES } = win;

const claves = Object.keys(LW_EN);
assert.ok(claves.length > 500,
  'el diccionario se ha quedado corto: ¿se ha truncado el fichero?');

/* ── 1. EN ESPAÑOL, `lwT()` DEVUELVE SU ENTRADA ─────────────────────────────
   La invariante que sostiene todo lo demás. Se comprueba sobre TODAS las
   claves, no sobre una muestra: el fallo de los 74 avisos estaba en unas
   pocas y habría pasado cualquier muestreo. */
win.LW_IDIOMA = 'es';
const rotas = claves.filter(k => lwT(k) !== (k.includes('~') ? k.split('~')[0] : k));
assert.deepStrictEqual(rotas, [],
  'en español lwT() tiene que devolver su entrada tal cual, y no lo hace en: '
  + rotas.slice(0, 5).map(JSON.stringify).join(', '));

assert.strictEqual(lwT('una frase que no está en el diccionario'),
                   'una frase que no está en el diccionario',
                   'una frase sin entrada también sale tal cual');
assert.strictEqual(lwT('%n días', { n: 3 }), '3 días',
                   'los huecos se rellenan también en español');
assert.strictEqual(lwLocale(), 'es-ES');

/* ── 2. EN INGLÉS traduce, y lo que falte cae al español ──────────────────── */
win.LW_IDIOMA = 'en';
assert.strictEqual(lwT('Guardar cambios'), 'Save changes');
assert.strictEqual(lwT('%n días', { n: 3 }), '3 days');
assert.strictEqual(lwT('Acceso~puerta'), 'Sign in',
                   'el sufijo de contexto no se imprime nunca');
assert.strictEqual(lwT('frase que no existe'), 'frase que no existe',
                   'sin traducción cae al español: nunca una clave cruda en pantalla');
assert.ok(LW_T_MISSES.has('frase que no existe'),
          'lo que falta tiene que quedar anotado en LW_T_MISSES');
assert.strictEqual(lwLocale(), 'en-GB');

/* ── 3. El blanco de los bordes ─────────────────────────────────────────────
   `'No se pudo guardar: '` lleva su espacio porque detrás se le concatena el
   mensaje de error. `lwT` le da una segunda oportunidad a la misma frase sin
   blanco, y tiene que DEVOLVERLO. */
assert.strictEqual(lwT('No se pudo guardar: '), 'Could not save: ',
                   'el blanco final del aviso tiene que sobrevivir a la traducción');
win.LW_IDIOMA = 'es';
assert.strictEqual(lwT('No se pudo guardar: '), 'No se pudo guardar: ');
win.LW_IDIOMA = 'en';

/* ── 4. Ninguna entrada vacía ni con los huecos desparejados ────────────────
   Un `%n` que está en la clave y no en la traducción imprime el número en
   español y lo pierde en inglés, sin avisar. */
const vacias = claves.filter(k => !LW_EN[k] || !String(LW_EN[k]).trim());
assert.deepStrictEqual(vacias, [], 'entradas sin traducción: ' + vacias.join(', '));

const huecos = s => (String(s).match(/%[a-z]/g) || []).sort().join('');
const desparejas = claves.filter(k => huecos(k) !== huecos(LW_EN[k]));
assert.deepStrictEqual(desparejas, [],
  'los %huecos de la clave y de su traducción no coinciden en: '
  + desparejas.slice(0, 5).join(' · '));

/* ── 5. El tipo de contrato: se traduce el RÓTULO, nunca la clave ───────────
   `vocabulario.js` es la fuente única de cómo se llama cada documento, y su
   rótulo es la columna «Tipo» de media suite. La clave (`ppjb_bonian_c2`) es
   lo que guarda la base: si se tradujera, dejaría de cruzar con nada. */
const ctx = {};
new Function('window', 'ctx',
  leer('vocabulario.js') + '\nctx.lwTipoContrato = lwTipoContrato;')(win, ctx);
const tipo = ctx.lwTipoContrato;

win.LW_IDIOMA = 'es';
assert.strictEqual(tipo('reserva_parcela'), 'Bloqueo de Parcela');
win.LW_IDIOMA = 'en';
assert.strictEqual(tipo('reserva_parcela'), 'Plot Hold');
assert.strictEqual(tipo('carta_reserva'), 'Reservation Letter');
assert.strictEqual(tipo('tipo_que_no_existe'), 'tipo_que_no_existe',
  'el fallback no adivina: un tipo nuevo sale con su clave cruda, fea pero cierta');
assert.strictEqual(tipo(''), '—');

console.log('OK i18n.test.js — ' + claves.length +
  ' frases · el español devuelve su entrada en todas · huecos y tipos de contrato cuadran');
