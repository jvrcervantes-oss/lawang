// Historial de notas, pieza común (contracts/assets/notas-historial.js, 15-oct-2026): ficha del cliente y ficha de la
// parcela. Con un sb falso y un DOM mínimo hecho a mano (como paginacion.test.js: jsdom sería traerse una dependencia).
// Cubre: cargando · vacío · caída (+ Reintentar) · 42501 · lista · recortado · respuesta sin lista · escape de
// `<img onerror>` · añadir y retirar con error de la base y con rechazo de red · carrera A→B · borrador por ficha ·
// cierra · claves en i18n · la ficha del cliente se pinta sin LW_NOTAS · el cableado de las dos páginas.
// Corre con: node contracts/assets/notas_historial.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert');
const raiz = path.join(__dirname, '..', '..');
const leer = (...p) => fs.readFileSync(path.join(raiz, ...p), 'utf8').replace(/\r\n/g, '\n');
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

// ── DOM mínimo: lo justo para el marcado que genera la pieza ────────────────────────────────────────────────────
const VACIOS = new Set(['input', 'br', 'img', 'meta', 'link', 'hr']);
const decodifica = (t) => t.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&');
const codifica = (t) => String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
class Texto { constructor(t) { this.texto = t; this.parentNode = null; } get textContent() { return decodifica(this.texto); } html() { return this.texto; } }
class El {
  constructor(tag) { this.tagName = tag.toUpperCase(); this.attrs = {}; this.children = []; this.parentNode = null; this.oyentes = {}; this._value = null; this.disabled = false; }
  getAttribute(k) { return Object.prototype.hasOwnProperty.call(this.attrs, k) ? this.attrs[k] : null; }
  setAttribute(k, v) { this.attrs[k] = String(v); }
  hasAttribute(k) { return Object.prototype.hasOwnProperty.call(this.attrs, k); }
  get hidden() { return this.hasAttribute('hidden'); }
  set hidden(v) { if (v) this.attrs.hidden = ''; else delete this.attrs.hidden; }
  get value() { return this._value != null ? this._value : this.tagName === 'TEXTAREA' ? this.textContent : (this.getAttribute('value') || ''); }
  set value(v) { this._value = String(v); }
  get textContent() { return this.children.map((c) => c.textContent).join(''); }
  set textContent(t) { this.children = [new Texto(codifica(t))]; }
  get innerHTML() { return this.children.map((c) => c.html()).join(''); }
  set innerHTML(h) { this.children.forEach((c) => { c.parentNode = null; }); this.children = []; parsea(String(h), this); }
  html() {
    const a = Object.keys(this.attrs).map((k) => ' ' + k + '="' + this.attrs[k] + '"').join('');
    const t = this.tagName.toLowerCase();
    return '<' + t + a + '>' + (VACIOS.has(t) ? '' : this.innerHTML + '</' + t + '>');
  }
  insertAdjacentHTML(pos, h) { assert.strictEqual(pos, 'beforeend'); parsea(String(h), this); }
  remove() { const p = this.parentNode; if (p) p.children = p.children.filter((c) => c !== this); this.parentNode = null; }
  contains(x) { for (let e = x; e; e = e.parentNode) if (e === this) return true; return false; }
  addEventListener(t, f) { (this.oyentes[t] = this.oyentes[t] || []).push(f); }
  removeEventListener(t, f) { this.oyentes[t] = (this.oyentes[t] || []).filter((g) => g !== f); }
  closest(sel) { for (let e = this; e && e instanceof El; e = e.parentNode) if (casa(e, sel)) return e; return null; }
  todos(sel, out = []) { this.children.forEach((c) => { if (c instanceof El) { if (casa(c, sel)) out.push(c); c.todos(sel, out); } }); return out; }
  querySelector(sel) { return this.todos(sel)[0] || null; }
  querySelectorAll(sel) { return this.todos(sel); }
  click() { const ev = { target: this }; for (let e = this; e; e = e.parentNode) (e.oyentes.click || []).forEach((f) => f(ev)); }
}
function casa(el, sel) {
  const m = /^([a-z0-9]*)((?:\[[^\]]+\])*)$/i.exec(sel.trim());
  assert.ok(m, 'selector no soportado por el DOM mínimo: ' + sel);
  if (m[1] && el.tagName !== m[1].toUpperCase()) return false;
  const conds = m[2].match(/\[[^\]]+\]/g) || [];
  return conds.every((c) => { const x = /^\[([^=\]]+)(?:="([^"]*)")?\]$/.exec(c); return x[2] == null ? el.hasAttribute(x[1]) : el.getAttribute(x[1]) === x[2]; });
}
function parsea(h, padre) {
  const re = /<!--[\s\S]*?-->|<\/([a-z0-9]+)\s*>|<([a-z0-9]+)((?:\s+[^\s=>\/]+(?:="[^"]*")?)*)\s*\/?>|[^<]+/gi;
  let cur = padre, m;
  while ((m = re.exec(h))) {
    if (m[0].startsWith('<!--')) continue;
    if (m[1]) { assert.strictEqual(cur.tagName, m[1].toUpperCase(), 'cierre </' + m[1] + '> sin su apertura'); cur = cur.parentNode; continue; }
    if (m[2]) {
      const el = new El(m[2]); el.parentNode = cur; cur.children.push(el);
      (m[3] || '').replace(/([^\s=]+)(?:="([^"]*)")?/g, (x, k, v) => { el.attrs[k] = v == null ? '' : v; return x; });
      if (!VACIOS.has(m[2].toLowerCase())) cur = el;
      continue;
    }
    const t = new Texto(m[0]); t.parentNode = cur; cur.children.push(t);
  }
  assert.strictEqual(cur, padre, 'etiquetas sin cerrar');
}

// ── entorno: toasts, errores, sb falso con respuestas a mano ────────────────────────────────────────────────────
const avisos = [];
global.window = { lwErrorHumano: (e, pre) => (pre ? pre + ': ' : '') + (e.message || e.code) };
global.toast = (m) => avisos.push(['bien', m]);
global.toastMal = (m) => avisos.push(['mal', m]);
const NH = require('./notas-historial.js');
ok(global.window.LW_NOTAS === NH && typeof NH.monta === 'function', 'publica window.LW_NOTAS.monta');

function diferido() { let a, b; const p = new Promise((x, y) => { a = x; b = y; }); return { p, ok: a, ko: b }; }
function sbFalso() {
  const llamadas = [], cola = {};
  return {
    llamadas, cola,
    rpc(nombre, args) { llamadas.push([nombre, args]); const d = diferido(); (cola[nombre] = cola[nombre] || []).push(d); return d.p; }
  };
}
const espera = () => new Promise((r) => setImmediate(r));
async function vacia() { for (let i = 0; i < 6; i++) await espera(); }
const RPC = { datos: 'unidad_notas_datos', agrega: 'unidad_nota_agrega', retira: 'unidad_nota_retira' };
function monta(sb, extra) {
  const cont = new El('div'), estados = [];
  const ctl = NH.monta(cont, Object.assign({ sb, rpc: RPC, argId: 'p_unidad', motivos: [['rectificacion', 'Es incorrecta'], ['otro', 'Otro motivo']],
    origenes: { campo_notas: 'del editor de la parcela o de una importación' }, aviso: 'No escribas aquí datos de compradores (nombres, contacto, importes): van en su ficha.',
    clases: { in: 'cl-in', btn1: 'cl-b1', btn2: 'cl-b2' }, alEstado: (e) => estados.push(e) }, extra || {}));
  return { cont, ctl, estados, q: (k) => cont.querySelector('[data-lw="' + k + '"]'), acc: (k) => cont.querySelectorAll('[data-accion="' + k + '"]') };
}
const nota = (x) => Object.assign({ id: 7, texto: 'Valla rota en el lindero norte', origen: 'nota', creado_en: '2026-10-15T08:30:00Z', autor_id: 'u1', autor_nombre: 'Ana Pérez', puede_retirar: false }, x || {});
const resp = (notas, x) => ({ data: Object.assign({ notas, recortado: false }, x || {}), error: null });

(async () => {
  // 1 · cargando → vacío
  {
    const sb = sbFalso(), t = monta(sb);
    t.ctl.abre('U1');
    ok(/Cargando las notas…/.test(t.q('notas-lista').textContent) && t.q('notas-caja').hidden, 'cargando: lo dice y la caja no sale aún');
    ok(t.estados[0] === 'cargando', 'avisa «cargando»');
    await vacia();
    ok(sb.llamadas[0][0] === 'unidad_notas_datos' && sb.llamadas[0][1].p_unidad === 'U1', 'pide unidad_notas_datos con p_unidad');
    sb.cola.unidad_notas_datos[0].ok(resp([]));
    await vacia();
    ok(t.q('notas-vacio') && /Sin notas todavía\./.test(t.q('notas-lista').textContent) && !t.q('notas-caja').hidden, 'vacío: «Sin notas todavía.» y la caja a la vista');
    ok(t.estados.pop() === 'vacio', 'avisa «vacio»');
    const ta = t.q('nota-texto'), av = t.q('nota-aviso');
    ok(ta.getAttribute('class') === 'cl-in' && t.acc('nota-agrega')[0].getAttribute('class') === 'cl-b1', 'clases por parámetro');
    ok(av && ta.getAttribute('aria-describedby') === av.getAttribute('id') && /datos de compradores/.test(av.textContent), 'aviso fijo a la vista, enlazado a la caja');
    ok(ta.getAttribute('maxlength') === '4000', 'tope de 4000 en la caja');
  }
  // 2 · caída → Reintentar; 42501; respuesta sin lista; rechazo de red
  {
    const sb = sbFalso(), t = monta(sb);
    t.ctl.abre('U1');
    sb.cola.unidad_notas_datos[0].ok({ data: null, error: { code: 'XX000', message: 'se cayó' } });
    await vacia();
    const c = t.q('notas-caida');
    ok(c && c.getAttribute('role') === 'alert' && /No se han podido cargar las notas: se cayó/.test(c.textContent), 'caída: se dice, con el motivo');
    ok(!/Sin notas todavía/.test(t.cont.textContent) && t.q('notas-caja').hidden, 'caída no se parece a «vacío» y no ofrece escribir');
    ok(t.estados.pop() === 'caida', 'avisa «caida»');
    t.acc('notas-reintenta')[0].click();
    ok(sb.llamadas.length === 2 && /Cargando las notas…/.test(t.q('notas-lista').textContent), 'Reintentar vuelve a pedir');
    sb.cola.unidad_notas_datos[1].ok(resp([nota()]));
    await vacia();
    ok(t.cont.querySelectorAll('[data-lw="nota"]').length === 1 && !t.q('notas-caja').hidden, 'tras reintentar, la lista y la caja');
  }
  {
    const sb = sbFalso(), t = monta(sb);
    t.ctl.abre('U1');
    sb.cola.unidad_notas_datos[0].ok({ data: null, error: { code: '42501', message: 'sin permiso' } });
    await vacia();
    ok(t.q('notas-sin-permiso') && /No tienes permiso para ver las notas\./.test(t.cont.textContent) && t.q('notas-caja').hidden, '42501: «No tienes permiso», sin caja');
    ok(!t.q('notas-caida') && !t.q('notas-vacio'), '42501 no es caída ni vacío');
    ok(t.estados.pop() === 'sin_permiso', 'avisa «sin_permiso»');
  }
  {
    const sb = sbFalso(), t = monta(sb);
    t.ctl.abre('U1');
    sb.cola.unidad_notas_datos[0].ok({ data: { recortado: false }, error: null });
    await vacia();
    ok(t.q('notas-caida') && /la respuesta no trae la lista de notas/.test(t.cont.textContent), 'una respuesta sin `notas` es caída, no «sin notas»');
    const sb2 = sbFalso(), t2 = monta(sb2);
    t2.ctl.abre('U1');
    sb2.cola.unidad_notas_datos[0].ko(new TypeError('Failed to fetch'));
    await vacia();
    ok(t2.q('notas-caida') && /Failed to fetch/.test(t2.cont.textContent), 'promesa rechazada: caída, nunca «Cargando…» para siempre');
    const t3 = monta(() => Promise.reject(new Error('Sin sesión')));
    t3.ctl.abre('U1');
    await vacia();
    ok(t3.q('notas-caida') && /Sin sesión/.test(t3.cont.textContent), 'sin sesión (sb rechazado): caída');
  }
  // 3 · lista: autor, origen, retirar solo con puede_retirar, recortado, escape
  {
    const sb = sbFalso(), t = monta(sb);
    t.ctl.abre('U1');
    sb.cola.unidad_notas_datos[0].ok(resp([
      nota({ id: 9, puede_retirar: true }),
      nota({ id: 8, texto: 'Antes de todo', origen: 'antigua', autor_id: null, autor_nombre: null }),
      nota({ id: 6, texto: 'De la importación', origen: 'campo_notas', autor_nombre: null, autor_id: null }),
      nota({ id: 5, texto: '<img src=x onerror=alert(1)>\nsegunda línea', autor_nombre: 'Bob' })
    ], { recortado: true }));
    await vacia();
    const arts = t.cont.querySelectorAll('[data-lw="nota"]');
    ok(arts.length === 4 && t.estados.pop() === 'lista', 'cuatro notas, avisa «lista»');
    ok(arts[0].querySelectorAll('[data-accion="nota-retira"]').length === 1 && t.acc('nota-retira').length === 1, '«Retirar» solo donde puede_retirar es true');
    ok(/Ana Pérez/.test(arts[0].textContent), 'autor por su nombre del servidor');
    ok(!/sin autor/.test(arts[1].textContent) && /Antes de todo/.test(arts[1].textContent), 'la antigua no dice «sin autor» (ya lo dice su origen, si lo hay)');
    ok(/sin autor/.test(arts[2].textContent) && /del editor de la parcela o de una importación/.test(arts[2].textContent), 'sin autor y con el rótulo de su origen');
    ok(!/· nota/.test(arts[0].textContent), 'la nota normal no lleva rótulo de origen');
    ok(arts[3].querySelectorAll('img').length === 0 && /&lt;img src=x onerror=alert\(1\)&gt;/.test(arts[3].innerHTML), 'el texto va escapado: ningún <img> se crea');
    ok(/white-space:pre-wrap/.test(arts[3].children[0].getAttribute('style')), 'pre-wrap: los saltos de línea se ven sin HTML');
    ok(t.q('notas-recortado') && /500 más recientes/.test(t.q('notas-recortado').textContent), 'recortado: lo dice');
  }
  // 4 · añadir: vacío, error de la base, éxito, sin respuesta
  {
    avisos.length = 0;
    const sb = sbFalso(), t = monta(sb);
    t.ctl.abre('U1');
    sb.cola.unidad_notas_datos[0].ok(resp([]));
    await vacia();
    const b = t.acc('nota-agrega')[0];
    t.q('nota-texto').value = '   ';
    b.click();
    ok(avisos.pop()[1] === 'Escribe la nota antes de añadirla.' && sb.llamadas.length === 1, 'vacía: no se manda');
    t.q('nota-texto').value = '  Revisar drenaje  ';
    b.click();
    ok(b.disabled, 'el botón se apaga mientras se envía');
    const [nom, args] = sb.llamadas[1];
    ok(nom === 'unidad_nota_agrega' && args.p_unidad === 'U1' && args.p_texto === 'Revisar drenaje', 'agrega con p_unidad y el texto recortado');
    sb.cola.unidad_nota_agrega[0].ok({ data: null, error: { code: 'P0001', message: 'demasiadas notas seguidas' } });
    await vacia();
    ok(!b.disabled && avisos.pop()[1] === 'No se ha guardado la nota: demasiadas notas seguidas', 'error de la base: se dice con su motivo');
    ok(t.q('nota-texto').value === '  Revisar drenaje  ' && sb.llamadas.length === 2, 'con error no se pierde el borrador ni se recarga');
    b.click();
    sb.cola.unidad_nota_agrega[1].ko(new TypeError('Failed to fetch'));
    await vacia();
    ok(/no se sabe si la nota se ha guardado/.test(avisos.pop()[1]), 'sin respuesta: «no se sabe», nunca «no se ha guardado»');
    ok(t.q('nota-texto').value === '  Revisar drenaje  ' && sb.llamadas[3][0] === 'unidad_notas_datos', 'sin respuesta: borrador intacto y la lista se recarga para mirarlo');
    sb.cola.unidad_notas_datos[1].ok(resp([]));
    await vacia();
    b.click();
    sb.cola.unidad_nota_agrega[2].ok({ data: null, error: { code: '', message: 'Failed to fetch' } });
    await vacia();
    ok(/no se sabe/.test(avisos.pop()[1]), 'un error SIN código tampoco es «no se ha guardado»');
    sb.cola.unidad_notas_datos[2].ok(resp([]));
    await vacia();
    b.click();
    sb.cola.unidad_nota_agrega[3].ok({ data: { id: 11, creado_en: '2026-10-15T09:00:00Z' }, error: null });
    await vacia();
    ok(avisos.pop()[1] === 'Nota añadida' && t.q('nota-texto').value === '', 'éxito: «Nota añadida» y la caja vacía');
    ok(sb.llamadas[sb.llamadas.length - 1][0] === 'unidad_notas_datos', 'y la lista se vuelve a pedir');
  }
  // 5 · retirar: motivo obligatorio, error, éxito; el borrador no se toca
  {
    avisos.length = 0;
    const sb = sbFalso(), t = monta(sb);
    t.ctl.abre('U1');
    sb.cola.unidad_notas_datos[0].ok(resp([nota({ id: 9, puede_retirar: true })]));
    await vacia();
    t.q('nota-texto').value = 'a medias';
    t.acc('nota-retira')[0].click();
    t.acc('nota-retira')[0].click();
    ok(t.cont.querySelectorAll('[data-lw="nota-retira-caja"]').length === 1, 'la caja del motivo sale una vez');
    ok(t.q('nota-motivo').querySelectorAll('option').length === 3, 'motivos de la cfg (+ el vacío)');
    t.acc('nota-retira-no')[0].click();
    ok(!t.q('nota-retira-caja') && t.q('nota-texto').value === 'a medias', 'Cancelar quita solo el motivo; el borrador sigue');
    t.acc('nota-retira')[0].click();
    const okB = t.acc('nota-retira-ok')[0];
    okB.click();
    ok(avisos.pop()[1] === 'Elige por qué se retira.' && sb.llamadas.length === 1, 'sin motivo no se manda');
    t.q('nota-motivo').value = 'rectificacion';
    okB.click();
    ok(sb.llamadas[1][0] === 'unidad_nota_retira' && sb.llamadas[1][1].p_nota === 9 && sb.llamadas[1][1].p_motivo === 'rectificacion', 'retira con p_nota numérico y el motivo');
    sb.cola.unidad_nota_retira[0].ok({ data: null, error: { code: '42501', message: 'no es tuya' } });
    await vacia();
    ok(avisos.pop()[1] === 'No se ha retirado la nota: no es tuya' && sb.llamadas.length === 2, 'si el servidor no deja, se dice');
    okB.click();
    sb.cola.unidad_nota_retira[1].ok({ data: { ok: true }, error: null });
    await vacia();
    ok(avisos.pop()[1] === 'Nota retirada' && sb.llamadas[3][0] === 'unidad_notas_datos', 'éxito: «Nota retirada» y recarga la lista');
    sb.cola.unidad_notas_datos[1].ok(resp([]));
    await vacia();
    ok(t.q('nota-texto').value === 'a medias', 'retirar repinta solo la lista: el borrador sigue');
    okB.click();   // botón de un nodo ya repintado: no hace nada (no está en el contenedor)
    ok(sb.llamadas.length === 4, 'un botón que ya no está en la ficha no manda nada');
  }
  // 6 · carrera A→B, borrador por ficha, cierra
  {
    avisos.length = 0;
    const sb = sbFalso(), t = monta(sb);
    t.ctl.abre('A');
    t.ctl.abre('B');
    sb.cola.unidad_notas_datos[1].ok(resp([nota({ texto: 'nota de B' })]));
    await vacia();
    sb.cola.unidad_notas_datos[0].ok(resp([nota({ texto: 'nota de A' })]));
    await vacia();
    ok(/nota de B/.test(t.cont.textContent) && !/nota de A/.test(t.cont.textContent), 'la respuesta vieja (A) no pinta sobre B');
    t.q('nota-texto').value = 'para B';
    t.ctl.abre('B');
    ok(t.q('nota-texto').value === 'para B', 'reabrir la MISMA ficha conserva el borrador');
    sb.cola.unidad_notas_datos[2].ok(resp([]));
    await vacia();
    t.acc('nota-agrega')[0].click();
    const enviado = sb.llamadas[sb.llamadas.length - 1];
    ok(enviado[0] === 'unidad_nota_agrega' && enviado[1].p_unidad === 'B', 'el id se toma al pulsar');
    t.ctl.abre('C');
    ok(t.q('nota-texto').value === '', 'otra ficha: el borrador no se arrastra (una nota de B nunca acaba en C)');
    const pedidas = sb.llamadas.length;
    sb.cola.unidad_nota_agrega[0].ok({ data: { id: 1 }, error: null });
    await vacia();
    ok(avisos.pop()[1] === 'Nota añadida' && sb.llamadas.length === pedidas, 'la respuesta de B se avisa pero no recarga la lista de C');
    t.q('nota-texto').value = 'en C';
    sb.cola.unidad_notas_datos[3].ok(resp([nota({ texto: 'nota de C' })]));
    await vacia();
    ok(t.q('nota-texto').value === 'en C' && /nota de C/.test(t.cont.textContent), 'C sigue con lo suyo');
    t.ctl.cierra();
    ok(t.cont.children.length === 0, 'cierra vacía el contenedor');
    t.ctl.abre('D'); t.ctl.cierra();
    sb.cola.unidad_notas_datos[4].ok(resp([nota({ texto: 'tarde' })]));
    await vacia();
    ok(t.cont.children.length === 0, 'una respuesta que llega tras cerrar no pinta');
  }
  // 6b · revisión (code-review, 15-oct): reabrir la misma ficha con un «Añadir» en vuelo, sin sesión, lecturas que se
  // cruzan, cerrar y volver, caída con borrador, doble montaje, función vieja del cliente
  {
    avisos.length = 0;
    const sb = sbFalso(), t = monta(sb);
    t.ctl.abre('P');
    sb.cola.unidad_notas_datos[0].ok(resp([]));
    await vacia();
    t.q('nota-texto').value = 'la misma';
    t.acc('nota-agrega')[0].click();
    t.ctl.abre('P');                                       // la ficha se vuelve a abrir con el envío en vuelo
    ok(t.acc('nota-agrega')[0].disabled && t.q('nota-texto').value === 'la misma', 'reabrir con el envío en vuelo: botón apagado y borrador a la vista');
    t.acc('nota-agrega')[0].click();
    ok(sb.llamadas.filter((l) => l[0] === 'unidad_nota_agrega').length === 1, 'no hay segundo envío del mismo texto');
    sb.cola.unidad_notas_datos[1].ok(resp([]));            // la lectura de la reapertura, anterior al alta
    sb.cola.unidad_nota_agrega[0].ok({ data: { id: 3 }, error: null });
    await vacia();
    ok(!t.acc('nota-agrega')[0].disabled && t.q('nota-texto').value === '', 'al llegar la respuesta: botón encendido y caja vacía');
    const ultima = sb.llamadas[sb.llamadas.length - 1];
    ok(ultima[0] === 'unidad_notas_datos' && ultima[1].p_unidad === 'P', 'y la lista de la misma ficha se recarga');
    sb.cola.unidad_notas_datos[2].ok(resp([nota({ id: 3, texto: 'la misma' })]));
    await vacia();
    ok(t.cont.querySelectorAll('[data-lw="nota"]').length === 1, 'la nota nueva se ve');

    // dos lecturas del mismo turno (Reintentar + recarga): la vieja no pinta encima de la nueva
    t.acc('nota-agrega')[0].click();   // vacía: no envía
    t.q('nota-texto').value = 'x';
    t.acc('nota-agrega')[0].click();
    sb.cola.unidad_nota_agrega[1].ko(new TypeError('Failed to fetch'));
    await vacia();
    const nDat = sb.cola.unidad_notas_datos.length;            // recarga tras la duda
    t.cont.querySelector('[data-lw="notas-lista"]').innerHTML = '<div data-lw="notas-caida"><button data-accion="notas-reintenta">r</button></div>';
    t.acc('notas-reintenta')[0].click();
    sb.cola.unidad_notas_datos[nDat].ok(resp([nota({ id: 3 }), nota({ id: 4, texto: 'nueva' })]));   // la más reciente llega antes
    await vacia();
    sb.cola.unidad_notas_datos[nDat - 1].ok(resp([nota({ id: 3 })]));                             // la vieja, después
    await vacia();
    ok(/nueva/.test(t.cont.textContent), 'la lectura vieja no tapa a la nueva');

    // cerrar y volver a abrir la misma ficha conserva lo escrito; otra ficha no lo ve
    t.q('nota-texto').value = 'sin enviar';
    t.ctl.cierra();
    t.ctl.abre('Q');
    ok(t.q('nota-texto').value === '', 'otra ficha no ve el borrador');
    t.ctl.abre('P');
    ok(t.q('nota-texto').value === 'sin enviar', 'cerrar y reabrir la misma ficha conserva el borrador');
    // caída con borrador: la caja no se esconde
    sb.cola.unidad_notas_datos[sb.cola.unidad_notas_datos.length - 1].ok({ data: null, error: { code: 'XX000', message: 'caída' } });
    await vacia();
    ok(t.q('notas-caida') && !t.q('notas-caja').hidden, 'caída con borrador: lo escrito sigue a la vista');
  }
  {
    avisos.length = 0;
    let quiere = { rpc: () => { throw new Error('no debería llamarse'); } };
    const t = monta(() => Promise.reject(new Error('Sin sesión')));
    t.ctl.abre('U1');
    await vacia();
    t.q('notas-caja').hidden = false;
    t.q('nota-texto').value = 'algo';
    t.acc('nota-agrega')[0].click();
    await vacia();
    ok(avisos.pop()[1] === 'No se ha guardado la nota: Sin sesión', 'sin sesión el envío no salió: «no se ha guardado», no «no se sabe»');
    const t2 = monta(null);
    t2.ctl.abre('U1');
    await vacia();
    ok(t2.q('notas-caida') && /Sin sesión/.test(t2.cont.textContent), 'sin cliente: caída con «Sin sesión», no un TypeError');
    void quiere;
  }
  {
    const sb = sbFalso(), cont = new El('div');
    const cfg = { sb, rpc: RPC, argId: 'p_unidad', motivos: [], origenes: {}, clases: {} };
    NH.monta(cont, cfg);
    const ctl = NH.monta(cont, cfg);                        // segundo montaje sobre el mismo contenedor
    ctl.abre('U1');
    sb.cola.unidad_notas_datos[0].ok(resp([]));
    await vacia();
    cont.querySelector('[data-lw="nota-texto"]').value = 'una';
    cont.querySelector('[data-accion="nota-agrega"]').click();
    const envios = sb.llamadas.filter((l) => l[0] === 'unidad_nota_agrega');
    ok(envios.length === 1 && envios[0][1].p_unidad === 'U1', 'dos montajes en el mismo contenedor: una pulsación, un envío, del montaje vivo');
  }
  {
    const sb = sbFalso(), t = monta(sb);
    t.ctl.abre('U1');
    sb.cola.unidad_notas_datos[0].ok(resp([{ id: 1, texto: 'vieja', origen: 'nota', creado_en: '2026-10-15T08:00:00Z', autor_id: 'u1', autor_email: 'ana@x' }]));
    await vacia();
    ok(/ana@x/.test(t.cont.textContent) && t.acc('nota-retira').length === 1,
      'cliente_notas_datos anterior a la migración: se ve el correo del autor y se ofrece «Retirar» (decide el servidor)');
  }

  // 7 · sin toastMal (otra pantalla): el aviso va a la línea de estado de la caja
  {
    const tm = global.toastMal; delete global.toastMal;
    const sb = sbFalso(), t = monta(sb);
    t.ctl.abre('U1');
    sb.cola.unidad_notas_datos[0].ok(resp([]));
    await vacia();
    t.acc('nota-agrega')[0].click();
    const l = t.q('nota-estado');
    ok(l.getAttribute('role') === 'alert' && /Escribe la nota/.test(l.textContent), 'sin toastMal el error se ve en la caja');
    global.toastMal = tm;
  }

  // ── ficha del cliente (datos.js) sobre la pieza, y que se pinta aunque falte LW_NOTAS ─────────────────────────
  const datos = leer('intranet', 'v4', 'assets', 'datos.js');
  const ini = datos.indexOf('/* Notas de la ficha (15-oct-2026');
  const fin = datos.indexOf('var ids = vins.map(function (v) { return v.contrato_id; });', ini);
  ok(ini > 0 && fin > ini, 'datos.js tiene el bloque de notas de la ficha');
  const bloque = datos.slice(ini, fin);
  ok(!/cliente_nota_agrega'\s*,\s*\{|sb\.rpc\('cliente_notas_datos'/.test(bloque) && !/nombreEquipo|LW_ROL|autor_email/.test(bloque), 'datos.js ya no lleva su copia: ni rpc a mano, ni equipo por correo, ni LW_ROL');
  const corre = (win) => {
    const sec = new El('div'), cuerpo = new El('div');
    cuerpo.querySelector = (s) => (s === '[data-cajon-sec="notas"] > div' ? sec : null);
    const H = { nota: (h, alarma) => '<p data-alarma="' + (alarma ? 1 : 0) + '">' + h + '</p>' };
    const esc = (v) => String(v).replace(/&/g, '&amp;').replace(/</g, '&lt;');
    new Function('window', 'cj', 'H', 'esc', 'tx', 'sb', 'c2', bloque)(win, { cuerpo }, H, esc, (s, h) => s.replace('%e', h ? h.e : ''), { soy: 'sb' }, { id: 'CLI-1' });
    return sec;
  };
  {
    const sec = corre({});
    ok(/No se han podido cargar las notas: falta un fichero de la página, recárgala/.test(sec.textContent) && /data-alarma="1"/.test(sec.innerHTML), 'sin LW_NOTAS la sección lo dice (y el resto de la ficha sigue: no lanza)');
    let visto = null, abierto = null;
    corre({ LW_NOTAS: { monta: (c, cfg) => { visto = cfg; return { abre: (id) => { abierto = id; } }; } } });
    ok(visto && visto.argId === 'p_client' && visto.rpc.datos === 'cliente_notas_datos' && visto.rpc.agrega === 'cliente_nota_agrega' && visto.rpc.retira === 'cliente_nota_retira', 'la ficha del cliente monta la pieza con sus tres funciones');
    ok(abierto === 'CLI-1' && visto.clases.in === 'las-in' && visto.sb.soy === 'sb', 'abre el id de la ficha, con las clases las-* y su sb');
  }

  // ── claves en i18n: lo que la pieza traduce y lo que le pasan las dos fichas ─────────────────────────────────
  const i18n = leer('contracts', 'assets', 'i18n.js');
  const claves = new Set();
  i18n.replace(/^\s*'((?:[^'\\]|\\.)*)'\s*:/gm, (x, k) => { claves.add(k.replace(/\\'/g, "'")); return x; });
  const frases = new Set();
  const fuente = leer('contracts', 'assets', 'notas-historial.js');
  fuente.replace(/\btx\('((?:[^'\\]|\\.)*)'/g, (x, k) => { frases.add(k); return x; });
  const FP = require('../../intranet/v4/assets/ficha-parcela.js');
  const cfgP = FP.notasCfg(() => {});
  const cfgC = {}; corre({ LW_NOTAS: { monta: (c, cfg) => { Object.assign(cfgC, cfg); return { abre: () => {} }; } } });
  [cfgP, cfgC].forEach((c) => {
    c.motivos.forEach((m) => frases.add(m[1]));
    Object.keys(c.origenes).forEach((k) => frases.add(c.origenes[k]));
    frases.add(c.aviso);
  });
  ['falta un fichero de la página, recárgala', 'No se han podido cargar las notas: %e', 'Notas'].forEach((k) => frases.add(k));
  const faltan = [...frases].filter((k) => !claves.has(k));
  ok(frases.size > 25 && !faltan.length, 'todas las frases tienen inglés; faltan: ' + faltan.join(' | '));
  ok(cfgP.aviso === 'No escribas aquí datos de compradores (nombres, contacto, importes): van en su ficha.' &&
     /Don\\'t write buyer details here \(names, contact, amounts\): they belong in the buyer\\'s record\./.test(i18n), 'aviso de la parcela con el texto de Legal en ES y EN');

  // ── cableado de las dos páginas ────────────────────────────────────────────────────────────────────────────
  const comp = leer('intranet', 'v4', 'compradores', 'index.html');
  const proy = leer('intranet', 'v4', 'proyectos', 'index.html');
  const posS = (h, s) => { const m = new RegExp('<script src="' + s.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '(\\?v=[0-9a-f]+)?" defer><\\/script>').exec(h); return m ? m.index : -1; };
  ok(posS(comp, '/contracts/assets/notas-historial.js') > 0 && posS(comp, '/contracts/assets/notas-historial.js') < posS(comp, '../assets/datos.js'), 'compradores carga la pieza antes de datos.js');
  ok(posS(proy, '/contracts/assets/notas-historial.js') > 0 && posS(proy, '/contracts/assets/notas-historial.js') < posS(proy, '../assets/ficha-parcela.js'), 'proyectos carga la pieza antes de ficha-parcela.js');

  console.log('notas_historial.test.js: ' + n + ' comprobaciones OK');
})().catch((e) => { console.error(e); process.exit(1); });
