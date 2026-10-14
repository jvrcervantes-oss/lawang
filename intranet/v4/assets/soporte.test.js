/* node soporte.test.js — Soporte de la v4 sin conversación que abrir (14-oct-2026).
   Lo que se afirma, ejecutando las piezas REALES de datos.js (el tramo «piezas sin red» del módulo soporte):
     1. «no he podido mirar» (la base no contestó) y «no hay nada» (0 hilos) NO se leen igual, ni en el panel ni en el
        cuadro de respuesta. Antes el cuadro decía «Cuando un cliente escriba…» también con la base caída.
     2. sin hilo, TODO lo que actúa sobre un hilo queda apagado de verdad: los botones con `disabled`, los enlaces sin
        `href` y con `aria-disabled`. Antes «Marcar resuelto», «Ver perfil» y «WhatsApp» seguían encendidos y no hacían nada.
     3. el avatar de quien contesta por el equipo: su `autor` es un correo y salía con una sola letra.
     4. la página y el código enganchan por `data-accion`, no por el rótulo («Ver perfil» en inglés no casaba).
   DOM mínimo hecho a mano, como paginacion.test.js: montar jsdom para cuatro nodos sería traerse una dependencia. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const datos = fs.readFileSync(path.join(__dirname, 'datos.js'), 'utf8');
const pagina = fs.readFileSync(path.join(__dirname, '..', 'soporte', 'index.html'), 'utf8');
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };
const eq = (a, b, m) => { assert.deepStrictEqual(JSON.parse(JSON.stringify(a)), JSON.parse(JSON.stringify(b)), m); n++; };

const A = '/* ── Soporte: piezas sin red (las ejecuta soporte.test.js) ── */', B = '/* ── fin de las piezas sin red de Soporte ── */';
const i = datos.indexOf(A), j = datos.indexOf(B);
assert.ok(i > 0 && j > i, 'no encuentro el tramo «piezas sin red» de Soporte en datos.js');
const c = {};
vm.createContext(c);
vm.runInContext(datos.slice(i, j), c);
const f = nombre => vm.runInContext(nombre, c);
const igual = s => s;

// 1. los dos estados sin hilo, y el caso con hilo
const fallo = f('sinHiloTextos')(null, null, igual);
const vacio = f('sinHiloTextos')([], undefined, igual);
ok(fallo && fallo.fallo === true, 'la base no contestó (hs == null): es un fallo');
ok(vacio && vacio.fallo === false, '0 hilos: no es un fallo');
ok(fallo.texto !== vacio.texto, 'el panel no dice lo mismo con la base caída que sin conversaciones');
ok(fallo.placeholder !== vacio.placeholder, 'el cuadro de respuesta tampoco');
ok(!/Cuando un cliente escriba/.test(fallo.placeholder) && !/Sin conversaciones/.test(fallo.texto), 'con la base caída no se promete que «saldrá aquí» ni se dice que no hay');
ok(/No se han podido leer/.test(fallo.texto) && /No se han podido leer/.test(fallo.placeholder), 'con la base caída, los dos sitios dicen que no se ha podido leer');
eq(vacio, { fallo: false, texto: 'Sin conversaciones todavía.', placeholder: 'Cuando un cliente escriba desde su área, la conversación saldrá aquí.' });
eq(f('sinHiloTextos')(undefined, undefined, igual).fallo, true, 'undefined cuenta como «no he podido mirar», igual que null');
eq(f('sinHiloTextos')([{ id: 'h1' }], { id: 'h1' }, igual), null, 'con hilo elegido no hay nada que apagar');
eq(f('sinHiloTextos')(null, null, s => '[' + s + ']').texto, '[No se han podido leer las conversaciones. Recarga la página.]', 'los textos pasan por el traductor que se le da');
// las frases existen en el diccionario (la clave ES el texto español)
const i18n = fs.readFileSync(path.join(__dirname, '..', '..', '..', 'contracts', 'assets', 'i18n.js'), 'utf8');
[fallo.texto, vacio.texto, vacio.placeholder].forEach(s => ok(i18n.indexOf("'" + s + "':") !== -1, 'falta en i18n.js: ' + s));

// 2. apagar de verdad, sobre un DOM mínimo
function nodo(tag, attrs) {
  const a = Object.assign({}, attrs);
  return {
    tagName: tag, style: {}, disabled: false, placeholder: attrs && attrs.placeholder, hijos: [], textContent: 'molde',
    getAttribute: k => (k in a ? a[k] : null), setAttribute: (k, v) => { a[k] = String(v); }, removeAttribute: k => { delete a[k]; },
    hasAttribute: k => k in a, appendChild(h) { this.hijos.push(h); return h; },
  };
}
function documento(sin) {
  const els = {
    'enviar-respuesta': nodo('BUTTON', { 'data-accion': 'enviar-respuesta' }),
    'estado-hilo': nodo('BUTTON', { 'data-accion': 'estado-hilo' }),
    'ver-perfil': nodo('A', { 'data-accion': 'ver-perfil', href: '#' }),
    'abrir-whatsapp': nodo('A', { 'data-accion': 'abrir-whatsapp', href: '#' }),
  };
  (sin || []).forEach(k => delete els[k]);
  const convo = nodo('DIV', { id: 'convo' }), ta = nodo('TEXTAREA', { placeholder: 'Escribe la respuesta…' });
  return {
    els, convo, ta,
    getElementById: id => (id === 'convo' ? convo : null),
    createElement: t => nodo(t.toUpperCase(), {}),
    querySelector(sel) {
      if (sel === 'textarea') return ta;
      const m = sel.match(/^\[data-accion="([\w-]+)"\]$/);
      assert.ok(m, 'apagaHilo busca por algo que no es data-accion: ' + sel);
      return els[m[1]] || null;
    },
  };
}
[['fallo', fallo], ['vacío', vacio]].forEach(([nombre, est]) => {
  const d = documento();
  f('apagaHilo')(d, est);
  eq(d.convo.textContent, '', nombre + ': la conversación se vacía');
  eq(d.convo.hijos.length, 1, nombre + ': queda UN aviso');
  eq(d.convo.hijos[0].textContent, est.texto, nombre + ': el aviso dice el texto de su estado');
  eq(d.convo.hijos[0].getAttribute('role'), 'status', nombre + ': el aviso se anuncia (role=status)');
  ['enviar-respuesta', 'estado-hilo'].forEach(k => {
    ok(d.els[k].disabled === true, nombre + ': «' + k + '» queda disabled');
    eq(d.els[k].getAttribute('aria-disabled'), 'true', nombre + ': «' + k + '» lleva aria-disabled');
  });
  ['ver-perfil', 'abrir-whatsapp'].forEach(k => {
    ok(!d.els[k].hasAttribute('href'), nombre + ': «' + k + '» deja de ser un enlace (sin href)');
    eq(d.els[k].getAttribute('aria-disabled'), 'true', nombre + ': «' + k + '» lleva aria-disabled');
    eq(d.els[k].getAttribute('tabindex'), '-1', nombre + ': «' + k + '» sale del orden del tabulador');
  });
  Object.keys(d.els).forEach(k => ok(d.els[k].style.cursor === 'not-allowed' && d.els[k].style.opacity === '.45', nombre + ': «' + k + '» se VE apagado'));
  ok(d.ta.disabled === true, nombre + ': el cuadro de respuesta queda disabled');
  eq(d.ta.placeholder, est.placeholder, nombre + ': y su placeholder es el de su estado');
});
// una página sin alguno de los controles (una instancia que quite WhatsApp) no revienta
f('apagaHilo')(documento(['abrir-whatsapp', 'estado-hilo']), vacio); n++;

// 3. iniciales de quien contesta por el equipo
const ie = f('inicialesEquipo');
eq(ie('andrea.lopez@lawangproperties.com'), 'AL', 'nombre.apellido');
eq(ie('javier_cervantes-ruiz@x.com'), 'JR', 'primera y última parte, con `_` y `-`');
eq(ie('maria.de.la.cruz@x.com'), 'MC', 'salta partículas, como el resto de la suite');
eq(ie('ventas@x.com'), 'VE', 'una sola parte: sus dos primeras letras (antes salía «V»)');
eq(ie('ventas2@x.com'), 'VE', 'los números no son iniciales');
eq(ie('a@x.com'), 'A', 'un correo de una letra no da para más: no se inventa la segunda');
eq(ie('j.cervantes@x.com'), 'JC', 'inicial.apellido');
eq(ie('2024@x.com'), 'EQ', 'sin letras: «EQ»');
eq(ie(''), 'EQ', 'sin autor: «EQ»');
eq(ie(null), 'EQ', 'null: «EQ»');
eq(ie('Andrea López'), 'AL', 'si un día llega un nombre y no un correo, la regla de siempre');
eq(f('inicialesDe')('Ni Made de Suarta', 'C'), 'MS', 'la del cliente no cambia');
eq(f('inicialesDe')('', 'C'), 'C', 'sin nombre de cliente: «C»');

// 4. se engancha por data-accion en la página y en el código
['enviar-respuesta', 'estado-hilo', 'ver-perfil', 'abrir-whatsapp'].forEach(k => {
  eq(pagina.split('data-accion="' + k + '"').length - 1, 1, 'soporte/index.html lleva data-accion="' + k + '" una vez');
});
const mod = datos.slice(datos.indexOf('    soporte: function (sb) {'), datos.indexOf('/* generador-contratos y contratos-inversor eran diseños sin datos'));
assert.ok(mod.length > 2000, 'no encuentro el módulo soporte de datos.js');
ok(!/\/Ver perfil\/|\/WhatsApp\//.test(mod), 'datos.js ya no busca «Ver perfil» / «WhatsApp» por su texto');
ok(/\[data-accion="ver-perfil"\]/.test(mod) && /\[data-accion="abrir-whatsapp"\]/.test(mod), 'los dos enlaces se cablean por data-accion');
ok(/if \(hs == null\) \{ apagaHilo\(document, sinHiloTextos\(null, null, tx\)\); return; \}/.test(mod), 'con la base caída se apaga con el estado de fallo');
ok(/if \(!el\) \{ apagaHilo\(document, sinHiloTextos\(hs, el, tx\)\); return; \}/.test(mod), 'sin hilo se apaga con el estado vacío');
ok(/esEquipo \? inicialesEquipo\(msg\.autor\)/.test(mod), 'el avatar del equipo sale de inicialesEquipo');

console.log('soporte.test.js OK — ' + n + ' comprobaciones');
