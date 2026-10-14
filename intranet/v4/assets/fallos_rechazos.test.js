// SC-33 (15-oct-2026): «Cannot read properties of undefined (reading 'M_ID')» llegó dos veces desde Home como
// «error de código», sin fichero, y ninguna versión de la intranet ni de supabase-js lee esa propiedad. Una promesa
// rechazada no trae fichero; su pila sí. Esto fija, EJECUTANDO el bloque de nav.js que apunta los fallos sobre un
// window mínimo, que: (1) un rechazo cuya pila es toda de una extensión del navegador no se apunta; (2) uno con una
// línea del propio dominio se apunta con «(ruta:línea)»; (3) uno sin pila se apunta como antes.
// Corre con: node intranet/v4/assets/fallos_rechazos.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert');
const nav = fs.readFileSync(path.join(__dirname, 'nav.js'), 'utf8').replace(/\r\n/g, '\n');
const ini = nav.indexOf('  (function () {\n    if (window.__lwFallos');
const fin = nav.indexOf('  })();\n', ini);
assert.ok(ini > 0 && fin > ini, 'nav.js ya no tiene el bloque que apunta los fallos (window.__lwFallos)');
const bloque = nav.slice(ini, fin + '  })();'.length);

function monta() {
  const oyentes = {};
  const window = { addEventListener: (t, f) => { oyentes[t] = f; } };
  const document = {
    body: null, addEventListener() {}, dispatchEvent() {}, getElementById() { return null; },
  };
  const location = { origin: 'https://lawangproperties.com', pathname: '/intranet/v4/home/' };
  Function('window', 'document', 'location', 'CustomEvent', 'MutationObserver', bloque)(
    window, document, location, function () {}, function () { return { observe() {}, disconnect() {} }; });
  return { B: window.__lwFallos, rechaza: reason => oyentes.unhandledrejection({ reason }) };
}
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

{ // (1) toda la pila es de una extensión: no es nuestro
  const { B, rechaza } = monta();
  const e = new TypeError("Cannot read properties of undefined (reading 'M_ID')");
  e.stack = "TypeError: Cannot read properties of undefined (reading 'M_ID')\n"
    + '    at x (chrome-extension://abcdefghijklmnop/inject.js:1:2345)\n'
    + '    at async y (chrome-extension://abcdefghijklmnop/inject.js:1:999)';
  rechaza(e);
  ok(B.length === 0, 'un rechazo con la pila entera de chrome-extension:// no se apunta');
  const f = new Error('x'); f.stack = 'Error: x\n    at moz-extension://1234-abcd/content.js:3:4';
  rechaza(f);
  ok(B.length === 0, 'tampoco uno de moz-extension://');
}
{ // (2) con una línea nuestra: se apunta con ella
  const { B, rechaza } = monta();
  const e = new TypeError("Cannot read properties of undefined (reading 'clave')");
  e.stack = "TypeError: Cannot read properties of undefined (reading 'clave')\n"
    + '    at https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.110.9/dist/umd/supabase.min.js:7:100\n'
    + '    at https://lawangproperties.com/intranet/v4/assets/editores.js?v=9bf858f0:10447:11';
  rechaza(e);
  ok(B.length === 1, 'un rechazo con un fichero nuestro se apunta');
  ok(B[0].msg === "Cannot read properties of undefined (reading 'clave') (/intranet/v4/assets/editores.js:10447)",
    'y dice la ruta y la línea sin el ?v=: ' + B[0].msg);
  const g = new Error('mixto');
  g.stack = 'Error: mixto\n    at chrome-extension://abc/x.js:1:1\n    at https://lawangproperties.com/contracts/assets/guard.js:5:1';
  rechaza(g);
  ok(B.length === 2 && /guard\.js:5\)$/.test(B[1].msg), 'una pila mezclada (extensión + nuestro) se apunta');
}
{ // (3) sin pila: como antes
  const { B, rechaza } = monta();
  rechaza('texto suelto');
  rechaza({ message: 'JWT expired', code: 'PGRST301' });
  ok(B.length === 2 && B[0].msg === 'texto suelto' && B[1].msg === 'JWT expired', 'sin pila se apunta el mensaje tal cual');
  rechaza(undefined); rechaza(null); rechaza('  ');
  ok(B.length === 2, 'un reject() sin valor (undefined, null, vacío) no se apunta, como antes (revisor, 1.ª vuelta)');
}
{ // (4) el «(ruta:línea)» sobrevive a un mensaje largo, y una URL nuestra citada en el mensaje no cuenta como pila
  const { B, rechaza } = monta();
  const largo = new Error('x'.repeat(400));
  largo.stack = 'Error: ' + largo.message + '\n    at https://lawangproperties.com/intranet/v4/assets/datos.js?v=1:77:3';
  rechaza(largo);
  ok(B.length === 1 && B[0].msg.length <= 300 && / \(\/intranet\/v4\/assets\/datos\.js:77\)$/.test(B[0].msg), 'mensaje largo: conserva el final «(ruta:línea)»');
  const cita = new TypeError('Failed to fetch https://lawangproperties.com/rest/v1/x');
  cita.stack = 'TypeError: Failed to fetch https://lawangproperties.com/rest/v1/x\n    at chrome-extension://abc/bg.js:9:9';
  rechaza(cita);
  ok(B.length === 1, 'una URL nuestra citada en el texto de una extensión no hace «nuestro» el rechazo');
}
{ // la pantalla del alta de cuenta ya no deja el fallo sin decir
  const ed = fs.readFileSync(path.join(__dirname, 'editores.js'), 'utf8');
  const i18n = fs.readFileSync(path.join(__dirname, '..', '..', '..', 'contracts', 'assets', 'i18n.js'), 'utf8');
  ok(/\}\)\.then\(null, function \(e\) \{\n[^\n]*\n\s*toastMal\(lwErrorHumano\(e, edT\('No se pudo abrir el alta de la cuenta'\)\)\);/.test(ed.replace(/\r\n/g, '\n')),
    'editores.js: el alta de «Nueva cuenta de cobro» enseña su fallo');
  ok(i18n.includes("'No se pudo abrir el alta de la cuenta':"), 'i18n.js: la frase nueva tiene inglés');
}
console.log(`fallos_rechazos: ${n} comprobaciones OK`);
