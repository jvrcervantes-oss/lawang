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

/* ── 6. La marca de la instancia (AxisWorks ERP, F3 2b, 26-sep-2026) ───────
   El núcleo escribe `%marca` y el valor sale de `window.LW_INSTANCIA`. Dos
   cosas que se rompen sin avisar: (a) si se rellena ANTES de buscar la
   traducción, la clave deja de casar y el inglés cae al español; (b) `%marca`
   empieza por `%m`, y un hueco `m` del llamante la partiría en «Xarca». */
win.LW_INSTANCIA = { marca: 'Acme', firma_correo: 'Acme Homes', titulo: 'Acme ERP' };
win.LW_IDIOMA = 'es';
assert.strictEqual(lwT('Sin ficha en %marca'), 'Sin ficha en Acme');
assert.strictEqual(lwT('%c contactos · %m con %marca', { c: 4, m: 2 }), '4 contactos · 2 con Acme',
  'el hueco %m del llamante no puede comerse %marca');
assert.strictEqual(win.lwMarca('Un saludo, %firma_correo'), 'Un saludo, Acme Homes');
win.LW_IDIOMA = 'en';
assert.strictEqual(lwT('Sin ficha en %marca'), 'No Acme record',
  'la clave con %marca tiene que seguir casando con el diccionario');
assert.strictEqual(lwT('%c contactos · %m con %marca', { c: 4, m: 2 }), '4 contacts · 2 with Acme');
delete win.LW_INSTANCIA;
win.LW_IDIOMA = 'es';
assert.strictEqual(lwT('Sin ficha en %marca'), 'Sin ficha en %marca',
  'sin ficha el hueco se ve: un nombre por defecto sería el de otro cliente');

/* ── 7. lwTSuave: el PUNTO DE PASO (toast, lwConfirmar, cajón, modal) ───────
   12-oct-2026 (la demo en inglés). Por ahí pasan rótulos Y DATOS. En español
   tiene que devolver TODO tal cual (también lo que lwT tocaría: «~», %marca);
   en inglés solo traduce claves, y un dato sale exactamente como llegó. */
const { lwTSuave } = win;
win.LW_INSTANCIA = { marca: 'Acme' };
const intactos = ['ana~perez@x.com', 'Promo %marca hoy', 'Guardar cambios', 'frase que no existe', 'KYC · Pendiente', ' con blanco '];
for (const idioma of ['es', undefined]) {
  win.LW_IDIOMA = idioma;
  for (const s of intactos) assert.strictEqual(lwTSuave(s), s, 'sin inglés, lwTSuave devuelve tal cual: ' + JSON.stringify(s));
  const malas = claves.filter(k => lwTSuave(k) !== k);
  assert.deepStrictEqual(malas, [], 'en español lwTSuave devuelve TODAS las claves tal cual: ' + malas.slice(0, 3).join(' · '));
  for (const v of [null, undefined, 3, '', '—', '12.400 EUR']) assert.strictEqual(lwTSuave(v), v);
}
win.LW_IDIOMA = 'en';
assert.strictEqual(lwTSuave('Guardar cambios'), 'Save changes', 'una clave se traduce');
assert.strictEqual(lwTSuave('Save changes'), 'Save changes', 'lo ya traducido sale tal cual');
LW_T_MISSES.clear();
assert.strictEqual(lwTSuave('Save changes'), 'Save changes');
assert.strictEqual(LW_T_MISSES.size, 0, 'y no cuenta como falta');
const hecha = lwT('%n firmados', { n: 7 });
assert.strictEqual(lwTSuave(hecha), hecha, 'lo que ya salió de lwT con sus huecos rellenos sale tal cual');
assert.strictEqual(LW_T_MISSES.size, 0, 'y tampoco cuenta como falta');
assert.strictEqual(lwTSuave('KYC · Pendiente'), 'KYC · ' + LW_EN['Pendiente'], 'un rótulo «A · B» de trozos conocidos se traduce por trozos');
assert.strictEqual(lwTSuave('ana~perez@x.com'), 'ana~perez@x.com', 'un dato con «~» no se corta');
assert.strictEqual(lwTSuave('Promo %marca hoy'), 'Promo %marca hoy', 'un dato con %marca no se rellena');
assert.ok(LW_T_MISSES.has('ana~perez@x.com') && LW_T_MISSES.has('Promo %marca hoy'), 'lo que no es clave se apunta como falta');
delete win.LW_INSTANCIA;

/* ── 8. data-lwt-nodos: traduce los nodos de texto y NO aplana los hijos ─────
   `data-lwt` hace textContent = … y se llevaría por delante un <span data-lw>
   con un dato dentro. Esto traduce solo los nodos de texto hijos directos. */
const texto = v => ({ nodeType: 3, nodeValue: v, nextSibling: null });
const t1 = texto('Los '), hijo = { nodeType: 1, textContent: '8', nextSibling: null }, t2 = texto(' últimos documentos emitidos · la fila abre la ficha');
t1.nextSibling = hijo; hijo.nextSibling = t2;
const el = { firstChild: t1 };
const raiz = { querySelectorAll: sel => sel === '[data-lwt-nodos]' ? [el] : [] };
global.document = { title: 'x', documentElement: {} };
win.LW_IDIOMA = 'es';
win.lwIdiomaAplicar(raiz);
assert.strictEqual(t1.nodeValue + hijo.textContent + t2.nodeValue, 'Los 8 últimos documentos emitidos · la fila abre la ficha', 'en español no se toca');
win.LW_IDIOMA = 'en';
LW_T_MISSES.clear();
win.lwIdiomaAplicar(raiz); win.lwIdiomaAplicar(raiz);   // dos veces: la segunda no puede buscar la frase ya en inglés
assert.strictEqual(t1.nodeValue, LW_EN['Los'] + ' ', 'el blanco de los lados se conserva');
assert.strictEqual(t2.nodeValue, ' ' + LW_EN['últimos documentos emitidos · la fila abre la ficha']);
assert.strictEqual(hijo.textContent, '8', 'el hijo (el dato) queda intacto');
assert.strictEqual(LW_T_MISSES.size, 0, 'repetir la pasada no apunta faltas');
global.document.title = 'Lawang · Contracts';   // ya en inglés: una pasada de un trozo no lo vuelve a buscar (15-oct-2026)
win.lwIdiomaAplicar(raiz);
assert.strictEqual(global.document.title, 'Lawang · Contracts', 'con raíz no se toca el título');
assert.strictEqual(LW_T_MISSES.size, 0, 'ni se apunta como falta');
delete global.document;

console.log('OK i18n.test.js — ' + claves.length +
  ' frases · el español devuelve su entrada en todas · huecos y tipos de contrato cuadran');
