/* Ajustes → «Servicios de AxisWorks» (AXW-104, decisión del owner 13-oct-2026). Primer servicio de pago: el asistente de IA del editor
 * de textos de contrato. Encargo agencia encargos/20261008_lawang_editor_textos_contrato.md (E11). Migración 20261013060136.
 *
 * Qué hace esta pieza (y solo esto), solo para el super administrador GLOBAL (el estudio):
 *  · margen % sobre el coste real del proveedor, tope por defecto por empresa, tope de toda la intranet, aviso %, y las tarifas del
 *    proveedor (coste real por millón de tokens). Lee por `servicios_axisworks_datos`, escribe por `servicios_axisworks_guarda`.
 *  · por empresa: asistente encendido, «suspendido por impago» (interruptor manual: nada se apaga solo) y tope propio.
 *  · el extracto mensual por empresa (coste del proveedor, coste no repercutido, coste facturable, margen, total sin impuestos) y el
 *    registro de cambios.
 * Lo que NO hace: decidir quién puede. La base comprueba `es_super_admin()` en las dos funciones (42501 si no); aquí la pestaña solo se
 * destapa para quien la base va a dejar, y en una instancia del ERP no se destapa (allí estas funciones no existen: erp/instancias.json).
 * Todo se pinta con createElement/textContent (los nombres de empresa vienen de la base). Enganche por data-*, nunca por rótulo.
 *
 * Forma (owner, 16-oct-2026: «que todo esté por pasos o bien separadito»; norma del 15-oct: 1-3 campos por paso):
 *  · arriba un resumen del mes, sin campos: qué es esto y cómo va;
 *  · tres pasos con su propio Guardar: 1 «cuánto se cobra» (margen), 2 «hasta dónde se gasta» (dos topes y el aviso), 3 «lo que cobra el
 *    proveedor» (las dos tarifas, plegado: casi nunca cambia). El motivo (lo exige la base) aparece solo cuando ese paso tiene un cambio;
 *  · cada empresa en su tarjeta; encender/apagar o suspender abre SU paso con el motivo dentro, antes de confirmar (hasta el 16-oct se
 *    confirmaba y después se rechazaba por falta de motivo, y había que repetirlo todo);
 *  · al guardar un bloque, lo escrito y sin guardar en los demás se conserva (antes el repintado lo borraba).
 * Cada bloque lleva data-srv-bloque; los campos siguen siendo data-srv-in y el envío es el mismo {p_empresa, p_campos, p_motivo}.
 */
(function () {
  'use strict';
  function T(s, h) { if (window.lwT) return window.lwT(s, h); var v = String(s); for (var k in h) if (Object.prototype.hasOwnProperty.call(h, k)) v = v.split('%' + k).join(h[k]); return v; }
  function aviso(t) { if (typeof toast === 'function') toast(t); }
  function el(tag, cls, txt) { var e = document.createElement(tag); if (cls) e.className = cls; if (txt != null) e.textContent = txt; return e; }
  // Esta página no carga lawang.css (su [hidden]{display:none!important}): una clase flex le gana a [hidden]. Ocultar SIEMPRE por aquí.
  function oculta(n, si) { n.hidden = !!si; n.style.display = si ? 'none' : ''; }
  function usd(n) {
    var x = Number(n);
    if (n === null || n === undefined || n === '' || !isFinite(x)) return '—';
    /* Con céntimos A PROPÓSITO (16-oct-2026, decisión por defecto de ajustes-ux): la v4 enseña los importes sin decimales, pero esto es la
       base de una factura y son importes de pocos dólares (0,40 USD salía «0 USD»). Se usa la excepción explícita de datos.js
       (`opts.decimales > 0`). Para volver a la regla general de la v4: quitar `{ decimales: 2 }`. */
    return typeof window.lwFormatoImporte === 'function' ? window.lwFormatoImporte(x, 'USD', { decimales: 2 }) : x.toFixed(2) + ' USD';
  }
  function fecha(x) { if (!x) return '—'; var d = new Date(x); return isNaN(d) ? String(x) : d.toLocaleString(window.lwLocale ? window.lwLocale() : 'es-ES'); }
  function mes(p) { var d = new Date(String(p) + 'T00:00:00'); return isNaN(d) ? String(p) : d.toLocaleDateString(window.lwLocale ? window.lwLocale() : 'es-ES', { month: 'long', year: 'numeric' }); }

  var sb = null, D = null;
  var C_ETQ = 'font-label-md text-[11px] tracking-[0.16em] uppercase text-outline font-bold';
  var C_INPUT = 'w-full md:w-40 rounded-lg border border-control-border/50 bg-surface-container-lowest px-3 py-2.5 font-body-md text-body-md';
  var C_BTN = 'shrink-0 px-5 py-2.5 rounded-full bg-primary-container text-on-primary hover:bg-primary font-label-md text-label-md';
  var C_BTN2 = 'shrink-0 px-4 py-2 rounded-full border border-outline-variant text-on-surface hover:bg-surface-container font-label-md text-label-md';
  var C_PEQ = 'font-body-sm text-body-sm text-outline';
  var C_CARD = 'bg-surface-container-lowest rounded-xl shadow-sm overflow-hidden';

  // El nombre de cada ajuste en el registro de cambios (la clave de la base no se enseña).
  function nombreCampo(k) {
    return ({ margen_pct: T('Margen sobre el coste (%)'), aviso_pct: T('Avisar al llegar al (%) del tope'), tope_usd_defecto: T('Tope por empresa y mes (USD de coste)'),
      tope_instancia_usd: T('Tope de toda la intranet y mes (USD de coste)'), tarifa_entrada_usd_mtok: T('Tarifa de entrada del proveedor'),
      tarifa_salida_usd_mtok: T('Tarifa de salida del proveedor'), tarifa_deepl_usd_mcar: T('Tarifa de DeepL'), tope_usd: T('Tope propio (USD de coste al mes)'),
      editor_ia: T('Asistente de textos'), suspendido: T('Suspendida por impago') })[k] || null;   // null = no es un ajuste (actualizado_por, actualizado_en…): no se enseña
  }
  function valorTxt(k, v) {
    if (v === null || v === undefined || v === '') return T('vacío');
    if (k === 'editor_ia') return v ? T('encendido') : T('apagado');
    if (typeof v === 'boolean') return v ? T('sí') : T('no');
    return String(v);
  }

  /* ── un campo numérico con su etiqueta y su ayuda ─────────────────────────────────────────────────────────── */
  function campoNum(clave, etiqueta, valor, ayuda, paso) {
    var f = el('label', 'flex flex-col gap-1'); f.setAttribute('data-srv-campo', clave);
    f.appendChild(el('span', 'font-label-md text-label-md text-on-surface', etiqueta));
    var i = el('input', C_INPUT); i.type = 'number'; i.step = paso || 'any'; i.min = '0'; i.inputMode = 'decimal';
    i.value = valor == null ? '' : String(valor); i.setAttribute('data-srv-in', clave); i.setAttribute('data-srv-antes', i.value);
    f.appendChild(i);
    var a = el('span', C_PEQ, ayuda || ''); a.setAttribute('data-srv-ayuda', clave); if (!ayuda) oculta(a, true);
    f.appendChild(a);
    return f;
  }
  // Solo lo que ha cambiado. Un número que el navegador no entiende («12,5» en algunos) llega como '' y NO se manda como vacío: se para
  // y se dice (code-review 13-oct: vaciar el margen apagaba el servicio sin avisar). Vacío solo vale donde vacío significa algo (tope
  // propio = el de por defecto; DeepL = sin configurar); la base lo vuelve a comprobar.
  var PUEDE_VACIO = { tope_usd: 1, tarifa_deepl_usd_mcar: 1 };
  function leeCambios(raiz) {
    var c = {}, n = 0, mal = null;
    [].forEach.call(raiz.querySelectorAll('[data-srv-in]'), function (i) {
      if (mal) return;
      var clave = i.getAttribute('data-srv-in'), v = i.value.trim();
      if (i.validity && i.validity.badInput) { mal = i; return; }
      if (i.value === i.getAttribute('data-srv-antes')) return;               // sin tocar (también un margen aún vacío): no frena lo demás
      if ((v === '' && !PUEDE_VACIO[clave]) || (v !== '' && !isFinite(Number(v)))) { mal = i; return; }
      c[clave] = v === '' ? null : Number(v); n++;
    });
    return { campos: n ? c : null, mal: mal };
  }
  function hayCambio(bloque) {
    return [].some.call(bloque.querySelectorAll('[data-srv-in]'), function (i) { return i.value !== i.getAttribute('data-srv-antes') || (i.validity && i.validity.badInput); });
  }
  // La fila «motivo + Guardar» de un bloque: escondida hasta que el bloque tiene un cambio (el motivo no cuenta como campo en reposo).
  function filaMotivo(bloque, empresa) {
    var f = el('div', 'flex flex-col gap-2 pt-4 border-t border-outline-variant/40'); f.setAttribute('data-srv-guardar-fila', '1'); oculta(f, true);
    var id = 'lw-srv-mot-' + (empresa || bloque.getAttribute('data-srv-bloque'));
    var lab = el('label', 'font-label-md text-label-md text-on-surface', T('¿Por qué lo cambias?')); lab.htmlFor = id;
    f.appendChild(lab);
    var fila = el('div', 'flex flex-col md:flex-row gap-3 md:items-center');
    var m = el('input', 'w-full md:w-96 rounded-lg border border-control-border/50 bg-surface-container-lowest px-3 py-2.5 font-body-md text-body-md');
    m.id = id; m.maxLength = 300; m.setAttribute('placeholder', T('Motivo del cambio (queda en el registro)')); m.setAttribute('data-srv-motivo', '1');
    var b = el('button', C_BTN, T('Guardar')); b.type = 'button'; b.setAttribute('data-accion', 'servicios-guardar'); b.setAttribute('data-real', '1');
    if (empresa) b.setAttribute('data-srv-empresa', empresa);
    b.addEventListener('click', function (ev) { ev.stopPropagation(); guarda(bloque, empresa || null, m, b); });
    fila.appendChild(m); fila.appendChild(b); f.appendChild(fila);
    f.appendChild(el('span', C_PEQ, T('Queda en el registro de cambios, abajo, con tu nombre y la hora.')));
    return f;
  }
  function vigila(bloque) {
    function mira() { var f = bloque.querySelector('[data-srv-guardar-fila]'); if (f) oculta(f, !hayCambio(bloque)); }
    bloque.addEventListener('input', mira); bloque.addEventListener('change', mira);
    bloque.__srvMira = mira;
  }

  // Lo escrito y sin guardar en los bloques que NO se acaban de guardar sobrevive al repintado (y qué plegables estaban abiertos).
  function capturaPendiente(salvo) {
    var raiz = document.getElementById('lw-srv'), p = { inp: {}, mot: {}, abiertos: {} };
    if (!raiz) return p;
    [].forEach.call(raiz.querySelectorAll('[data-srv-bloque]'), function (b) {
      if (salvo && b === salvo) return;
      var id = b.getAttribute('data-srv-bloque');
      [].forEach.call(b.querySelectorAll('[data-srv-in]'), function (i) { if (i.value !== i.getAttribute('data-srv-antes')) p.inp[id + '|' + i.getAttribute('data-srv-in')] = i.value; });
      var m = b.querySelector('[data-srv-motivo]'); if (m && m.value) p.mot[id] = m.value;
    });
    [].forEach.call(raiz.querySelectorAll('details[data-srv-plegable]'), function (d) { if (d.open) p.abiertos[d.getAttribute('data-srv-plegable')] = 1; });
    return p;
  }
  function devuelvePendiente(p) {
    var raiz = document.getElementById('lw-srv'); if (!raiz || !p) return;
    [].forEach.call(raiz.querySelectorAll('[data-srv-bloque]'), function (b) {
      var id = b.getAttribute('data-srv-bloque');
      [].forEach.call(b.querySelectorAll('[data-srv-in]'), function (i) { var k = id + '|' + i.getAttribute('data-srv-in'); if (Object.prototype.hasOwnProperty.call(p.inp, k)) i.value = p.inp[k]; });
      var m = b.querySelector('[data-srv-motivo]'); if (m && p.mot[id]) m.value = p.mot[id];
      b.dispatchEvent(new Event('input'));
    });
    [].forEach.call(raiz.querySelectorAll('details[data-srv-plegable]'), function (d) { if (p.abiertos[d.getAttribute('data-srv-plegable')]) d.open = true; });
  }

  function guarda(bloque, empresa, m, b, extra) {
    var lc = extra ? { campos: extra, mal: null } : leeCambios(bloque), campos = lc.campos;
    if (lc.mal) { aviso(T('Escribe un número en este campo (con punto para los decimales); no se ha guardado nada.')); lc.mal.focus(); return; }
    if (!campos) { aviso(T('No has cambiado nada.')); return; }
    var motivo = (m && m.value || '').trim();
    if (motivo.length < 3) { aviso(T('Escribe el motivo del cambio (queda en el registro).')); if (m) m.focus(); return; }
    b.disabled = true;
    sb.rpc('servicios_axisworks_guarda', { p_empresa: empresa, p_campos: campos, p_motivo: motivo }).then(function (r) {
      b.disabled = false;
      if (r.error) { aviso(T('No se ha guardado: %m', { m: r.error.message || T('sin detalle') })); return; }
      aviso(T('Guardado.'));
      carga(capturaPendiente(extra ? null : bloque));   // un interruptor no guarda el tope de su tarjeta: lo escrito ahí también se conserva
    });
  }

  /* ── pintar ───────────────────────────────────────────────────────────────────────────────────────────────── */
  function cabecera(etq, titulo, texto) {
    var h = el('div', 'px-8 pt-8 pb-4 flex flex-col gap-1 border-b border-outline-variant/40');
    if (etq) h.appendChild(el('span', C_ETQ, etq));
    h.appendChild(el('h2', 'font-headline-sm text-headline-sm text-deep-lagoon tracking-tight', titulo));
    if (texto) h.appendChild(el('p', C_PEQ, texto));
    return h;
  }
  function seccion(etq, titulo, texto, bloque) {
    var s = el('section', C_CARD);
    s.appendChild(cabecera(etq, titulo, texto));
    var c = el('div', 'px-8 py-6 flex flex-col gap-4'); s.appendChild(c);
    if (bloque) s.setAttribute('data-srv-bloque', bloque);
    return { s: s, c: c };
  }
  // Un bloque que casi nunca se toca: plegado, con su resumen a la vista.
  function seccionPlegada(etq, titulo, resumenTxt, texto, bloque) {
    var s = el('section', C_CARD); s.setAttribute('data-srv-bloque', bloque);
    var d = el('details', 'group'); d.setAttribute('data-srv-plegable', bloque);
    var su = el('summary', 'list-none cursor-pointer px-8 py-6 flex items-start justify-between gap-4');
    var t = el('div', 'flex flex-col gap-1');
    t.appendChild(el('span', C_ETQ, etq));
    t.appendChild(el('h2', 'font-headline-sm text-headline-sm text-deep-lagoon tracking-tight', titulo));
    t.appendChild(el('p', 'font-body-sm text-body-sm text-on-surface-variant', resumenTxt));
    su.appendChild(t);
    var ic = el('span', 'material-symbols-outlined text-[22px] text-outline transition-transform group-open:rotate-180 shrink-0', 'expand_more'); ic.setAttribute('aria-hidden', 'true');
    su.appendChild(ic);
    d.appendChild(su);
    var c = el('div', 'px-8 pb-6 pt-4 flex flex-col gap-4 border-t border-outline-variant/40');
    if (texto) c.appendChild(el('p', C_PEQ, texto));
    d.appendChild(c); s.appendChild(d);
    return { s: s, c: c };
  }
  function barra(gasto, tope, avisoPct) {
    var g = Number(gasto) || 0, t = Number(tope) || 0, pct = t > 0 ? Math.min(100, Math.round(g / t * 100)) : 0;
    var alta = t > 0 && avisoPct != null && pct >= Number(avisoPct);
    var b = el('div', 'h-1.5 w-full rounded-full bg-surface-container overflow-hidden');
    var r = el('div', 'h-full rounded-full ' + (alta ? 'bg-burnt-earth' : 'bg-primary-container')); r.style.width = pct + '%';
    b.appendChild(r);
    b.setAttribute('role', 'img'); b.setAttribute('aria-label', T('%p % del tope gastado', { p: pct })); b.setAttribute('data-srv-barra', alta ? 'aviso' : 'normal');
    return b;
  }
  function cifra(etq, valor, sub) {
    var c = el('div', 'rounded-xl bg-surface-container-low px-5 py-4 flex flex-col gap-1');
    c.appendChild(el('span', C_ETQ, etq));
    c.appendChild(el('span', 'font-headline-sm text-headline-sm text-deep-lagoon tracking-tight', valor));
    if (sub) c.appendChild(sub);
    return c;
  }

  function pintaResumen(raiz, I, empresas) {
    var a = seccion(T('Servicios de AxisWorks'), T('Qué es y cómo va este mes'),
      T('Los servicios de pago que AxisWorks da a esta intranet. Hoy hay uno: el asistente que redacta y traduce los textos de contrato. Cada empresa paga lo que cobra el proveedor de IA más tu margen, en la factura mensual de mantenimiento.'));
    a.s.setAttribute('data-srv-resumen', '1');
    var malla = el('div', 'grid grid-cols-1 md:grid-cols-3 gap-4');
    var sub = el('div', 'flex flex-col gap-2');
    sub.appendChild(barra(I.gasto_usd, I.tope_instancia_usd, I.aviso_pct));
    sub.appendChild(el('span', C_PEQ, T('de %t de tope · %p, hora de Bali', { t: usd(I.tope_instancia_usd), p: mes(D.periodo) })));
    malla.appendChild(cifra(T('Gasto de este mes'), usd(I.gasto_usd), sub));
    var enc = empresas.filter(function (e) { return e.editor_ia && !e.suspendido; }).length;
    malla.appendChild(cifra(T('Empresas usándolo'), T('%n de %t', { n: enc, t: empresas.length }), el('span', C_PEQ, T('con el asistente encendido y sin suspender'))));
    var sus = empresas.filter(function (e) { return e.suspendido; }).length;
    malla.appendChild(cifra(T('Suspendidas por impago'), String(sus), el('span', C_PEQ, sus ? T('se quita en su tarjeta, en «Empresas»') : T('ninguna'))));
    a.c.appendChild(malla);
    if (I.margen_pct == null) a.c.appendChild(el('p', 'font-body-sm text-body-sm text-error', T('Falta el margen: sin él el asistente no arranca. Ponlo en el paso 1.')));
    if (I.actualizado_en) a.c.appendChild(el('p', C_PEQ, T('Último cambio de estos ajustes: %q, %f.', { q: I.actualizado_por || '—', f: fecha(I.actualizado_en) })));
    raiz.appendChild(a.s);
  }

  function pinta() {
    var raiz = document.getElementById('lw-srv'); if (!raiz) return;
    raiz.textContent = '';
    var I = D.instancia || {}, Tf = D.tarifas || {}, empresas = D.empresas || [];

    pintaResumen(raiz, I, empresas);

    // Paso 1 · cuánto se cobra (1 campo)
    var p1 = seccion(T('Paso %n de 3', { n: 1 }), T('Cuánto se cobra'),
      T('Lo que paga cada empresa = lo que cobra el proveedor de IA + este margen.'), 'precio');
    var ej = el('p', 'font-body-sm text-body-sm text-on-surface-variant'); ej.setAttribute('data-srv-ejemplo', '1');
    function ejemplo() {
      var i = p1.c.querySelector('[data-srv-in="margen_pct"]'), m = i && i.value !== '' ? Number(i.value) : NaN;
      ej.textContent = isFinite(m) ? T('Ejemplo: si el proveedor cobra %c, la empresa paga %p.', { c: usd(10), p: usd(10 * (1 + m / 100)) })
        : T('Sin margen el asistente no arranca: ponlo tú.');
    }
    var g1 = el('div', 'flex flex-col gap-3');
    g1.appendChild(campoNum('margen_pct', T('Margen sobre el coste (%)'), I.margen_pct, null, '0.01'));
    g1.appendChild(ej);
    p1.c.appendChild(g1);
    p1.c.appendChild(filaMotivo(p1.s, null));
    p1.s.addEventListener('input', ejemplo); ejemplo();
    vigila(p1.s);
    raiz.appendChild(p1.s);

    // Paso 2 · hasta dónde se gasta (3 campos)
    var p2 = seccion(T('Paso %n de 3', { n: 2 }), T('Hasta dónde se gasta cada mes'),
      T('Los topes cuentan lo que AxisWorks paga al proveedor. Al llegar, el servicio se para hasta el mes siguiente o hasta que lo subas aquí.'), 'topes');
    var g2 = el('div', 'grid grid-cols-1 md:grid-cols-3 gap-5');
    g2.appendChild(campoNum('tope_usd_defecto', T('Tope por empresa y mes (USD de coste)'), I.tope_usd_defecto, null, '0.01'));
    g2.appendChild(campoNum('tope_instancia_usd', T('Tope de toda la intranet y mes (USD de coste)'), I.tope_instancia_usd,
      T('Pon aquí el mismo límite de gasto que tiene la clave en la consola del proveedor: si las empresas suman más, el proveedor corta a mitad de una consulta.'), '0.01'));
    g2.appendChild(campoNum('aviso_pct', T('Avisar al llegar al (%) del tope'), I.aviso_pct, T('La empresa ve un aviso cuando ha gastado este tanto por ciento de su tope.'), '1'));
    p2.c.appendChild(g2);
    function maximo() {
      var a = p2.c.querySelector('[data-srv-ayuda="tope_usd_defecto"]'), ti = p2.c.querySelector('[data-srv-in="tope_usd_defecto"]'), t = ti && ti.value !== '' ? Number(ti.value) : NaN;
      var mi = p1.c.querySelector('[data-srv-in="margen_pct"]'), m = mi && mi.value !== '' ? Number(mi.value) : NaN;
      oculta(a, !(isFinite(m) && isFinite(t)));
      a.textContent = a.hidden ? '' : T('Máximo facturable por empresa y mes: %f (tope × (1 + margen)).', { f: usd(t * (1 + m / 100)) });
    }
    p2.c.appendChild(filaMotivo(p2.s, null));
    p2.s.addEventListener('input', maximo); p1.s.addEventListener('input', maximo); maximo();
    vigila(p2.s);
    raiz.appendChild(p2.s);

    // Paso 3 · lo que cobra el proveedor (2 campos, plegado: solo cambia si el proveedor cambia sus precios)
    var p3 = seccionPlegada(T('Paso %n de 3', { n: 3 }), T('Lo que cobra el proveedor'),
      T('%m · entrada %e · salida %s por millón de tokens', { m: Tf.modelo || '—', e: usd(Tf.tarifa_entrada_usd_mtok), s: usd(Tf.tarifa_salida_usd_mtok) }),
      T('Lo que cobra el proveedor de IA por cada millón de «tokens» (trozos de texto) que lee y que escribe. Se copia de su página de precios y solo cambia si el proveedor cambia sus precios.'), 'proveedor');
    var g3 = el('div', 'grid grid-cols-1 md:grid-cols-2 gap-5');
    g3.appendChild(campoNum('tarifa_entrada_usd_mtok', T('Coste del proveedor: USD por millón de tokens de entrada (%m)', { m: Tf.modelo || '' }), Tf.tarifa_entrada_usd_mtok, null, '0.0001'));
    g3.appendChild(campoNum('tarifa_salida_usd_mtok', T('Coste del proveedor: USD por millón de tokens de salida (%m)', { m: Tf.modelo || '' }), Tf.tarifa_salida_usd_mtok, null, '0.0001'));
    p3.c.appendChild(g3);
    p3.c.appendChild(filaMotivo(p3.s, null));
    vigila(p3.s);
    raiz.appendChild(p3.s);

    // Empresas: una tarjeta por empresa
    var b = seccion(null, T('Empresas'),
      T('Enciende el asistente a cada empresa y, si no paga, suspéndela: se apagan todos sus servicios de pago hasta que quites la suspensión. Nada se apaga solo.'));
    if (!empresas.length) b.c.appendChild(el('p', C_PEQ, T('No hay empresas activas. Se dan de alta en Sociedades.')));
    empresas.forEach(function (e) {
      var nombre = e.nombre || e.clave;
      var fila = el('div', 'rounded-xl border border-outline-variant/50 px-5 py-4 flex flex-col gap-3');
      fila.setAttribute('data-srv-empresa-fila', e.clave); fila.setAttribute('data-srv-bloque', 'emp:' + e.clave);
      var cab = el('div', 'flex flex-wrap items-center gap-2');
      cab.appendChild(el('h3', 'font-label-md text-label-md text-on-surface mr-2', nombre));
      cab.appendChild(el('span', 'inline-flex items-center rounded-full px-3 py-1 font-label-md text-[12px] ' + (e.editor_ia ? 'bg-primary-container text-on-primary' : 'bg-surface-container text-on-surface-variant'),
        e.editor_ia ? T('Asistente encendido') : T('Asistente apagado')));
      if (e.suspendido) cab.appendChild(el('span', 'inline-flex items-center rounded-full px-3 py-1 font-label-md text-[12px] border border-error/40 text-error', T('Suspendida por impago')));
      fila.appendChild(cab);
      var gasto = el('div', 'flex flex-col gap-1');
      gasto.appendChild(barra(e.gasto_usd, e.tope_efectivo_usd, I.aviso_pct));
      gasto.appendChild(el('span', C_PEQ, T('Este mes: %g de %t de coste.', { g: usd(e.gasto_usd), t: usd(e.tope_efectivo_usd) })));
      fila.appendChild(gasto);
      if (e.falta && e.editor_ia && !e.suspendido) fila.appendChild(el('p', 'font-body-sm text-body-sm text-error', e.falta));

      var botones = el('div', 'flex flex-wrap gap-2');
      var paso = el('div', 'rounded-xl bg-surface-container-low px-5 py-4 flex flex-col gap-3'); paso.setAttribute('data-srv-paso', e.clave); oculta(paso, true);
      function abrePaso(clave, valor, titulo, efecto, boton) {
        paso.textContent = ''; oculta(paso, false);
        paso.appendChild(el('span', 'font-label-md text-label-md text-on-surface', titulo));
        paso.appendChild(el('p', 'font-body-sm text-body-sm text-on-surface-variant', efecto));
        var id = 'lw-srv-paso-' + e.clave;
        var lab = el('label', 'font-label-md text-label-md text-on-surface', T('¿Por qué?')); lab.htmlFor = id; paso.appendChild(lab);
        var m = el('input', 'w-full md:w-96 rounded-lg border border-control-border/50 bg-surface-container-lowest px-3 py-2.5 font-body-md text-body-md');
        m.id = id; m.maxLength = 300; m.setAttribute('placeholder', T('Motivo del cambio (queda en el registro)')); m.setAttribute('data-srv-motivo-paso', '1');
        paso.appendChild(m);
        var acc = el('div', 'flex flex-wrap gap-2');
        var ok = el('button', C_BTN, boton); ok.type = 'button'; ok.setAttribute('data-accion', 'servicios-confirmar'); ok.setAttribute('data-real', '1'); ok.setAttribute('data-srv-empresa', e.clave);
        var no = el('button', C_BTN2, T('Cancelar')); no.type = 'button'; no.setAttribute('data-accion', 'servicios-cancelar');
        ok.addEventListener('click', function (ev) { ev.stopPropagation(); var c = {}; c[clave] = valor; guarda(fila, e.clave, m, ok, c); });
        no.addEventListener('click', function (ev) { ev.stopPropagation(); oculta(paso, true); paso.textContent = ''; });
        acc.appendChild(ok); acc.appendChild(no); paso.appendChild(acc);
        m.focus();
      }
      function interruptor(clave, valor, txt, titulo, efecto, boton) {
        var x = el('button', C_BTN2, txt); x.type = 'button'; x.setAttribute('data-accion', 'servicios-' + clave); x.setAttribute('data-real', '1');
        x.setAttribute('data-srv-empresa', e.clave);
        x.addEventListener('click', function (ev) { ev.stopPropagation(); abrePaso(clave, valor, titulo, efecto, boton); });
        botones.appendChild(x);
      }
      if (e.editor_ia) interruptor('editor_ia', false, T('Apagar el asistente de textos'), T('Apagar el asistente de textos a %e', { e: nombre }),
        T('La empresa deja de poder usar el asistente de textos. Lo ya gastado no cambia.'), T('Sí, apagarlo'));
      else interruptor('editor_ia', true, T('Encender el asistente de textos'), T('Encender el asistente de textos a %e', { e: nombre }),
        T('La empresa puede usar el asistente de textos desde ahora, y lo que gaste cuenta para su tope.'), T('Sí, encenderlo'));
      if (e.suspendido) interruptor('suspendido', false, T('Quitar la suspensión'), T('Quitar la suspensión a %e', { e: nombre }),
        T('La empresa vuelve a poder usar los servicios que tenga encendidos.'), T('Sí, quitarla'));
      else interruptor('suspendido', true, T('Suspender por impago'), T('Suspender por impago a %e', { e: nombre }),
        T('Se apagan todos los servicios de pago de esta empresa hasta que quites la suspensión. Nada se apaga solo.'), T('Sí, suspenderla'));
      fila.appendChild(botones);
      fila.appendChild(paso);
      var g = el('div', 'flex flex-col gap-1');
      g.appendChild(campoNum('tope_usd', T('Tope propio (USD de coste al mes)'), e.tope_usd,
        T('Vacío = el tope por empresa del paso 2 (%t).', { t: usd(I.tope_usd_defecto) }), '0.01'));
      fila.appendChild(g);
      fila.appendChild(filaMotivo(fila, e.clave));
      vigila(fila);
      b.c.appendChild(fila);
    });
    raiz.appendChild(b.s);

    // Extracto mensual
    var x = seccion(null, T('Extracto para la factura de mantenimiento'),
      T('Últimos tres meses, por empresa, en USD y sin impuestos (el mes es el de Bali). Se factura solo lo que terminó bien; lo que falló después de enviarse lo pagó AxisWorks al proveedor y no se repercute. Cada consulta guarda su margen: un cambio de margen no cambia lo ya gastado.'));
    var filas = D.extracto || [];
    if (!filas.length) x.c.appendChild(el('p', C_PEQ, T('Todavía no hay consultas.')));
    else {
      var envolt = el('div', 'overflow-x-auto');
      var tb = el('table', 'w-full text-left border-collapse font-body-sm text-body-sm');
      var cab2 = el('tr');
      [T('Mes'), T('Empresa'), T('Consultas (bien / mal / en curso)'), T('Coste del proveedor'), T('Coste no repercutido'), T('Coste facturable'), T('Margen'), T('Total sin impuestos')].forEach(function (h) {
        cab2.appendChild(el('th', 'py-2 pr-4 font-label-md text-label-md text-outline', h));
      });
      tb.appendChild(cab2);
      filas.forEach(function (f) {
        var tr = el('tr', 'border-t border-outline-variant/30');
        var nom = (empresas.filter(function (e) { return e.clave === f.empresa; })[0] || {}).nombre || f.empresa;
        var total = usd(f.total_sin_impuestos_usd) + (f.margenes_pct && f.margenes_pct.length ? ' (' + f.margenes_pct.join(' / ') + ' %)' : '');
        [mes(f.periodo), nom, f.hechas + ' / ' + f.fallidas + ' / ' + f.en_vuelo, usd(f.coste_proveedor_usd), usd(f.coste_no_repercutido_usd),
         usd(f.coste_facturable_usd), usd(f.margen_usd), total].forEach(function (v) { tr.appendChild(el('td', 'py-2 pr-4 text-on-surface whitespace-nowrap', v)); });
        tb.appendChild(tr);
        if (f.coste_incompleto) {
          var tr2 = el('tr'); var td = el('td', 'pb-2 font-body-sm text-body-sm text-error', T('Coste incompleto: alguna consulta se cortó sin saber cuánto cobró el proveedor (cuenta contra el tope al máximo posible; no se factura).'));
          td.colSpan = 8; tr2.appendChild(td); tb.appendChild(tr2);
        }
      });
      envolt.appendChild(tb); x.c.appendChild(envolt);
    }
    raiz.appendChild(x.s);

    // Registro: quién, cuándo, de qué (en palabras) y qué cambió, con su antes y su después
    var r = seccion(null, T('Registro de cambios'), null);
    var reg = D.registro || [];
    if (!reg.length) r.c.appendChild(el('p', C_PEQ, T('Sin cambios todavía.')));
    var lista = el('ul', 'flex flex-col'); r.c.appendChild(lista);
    reg.forEach(function (l) {
      var li = el('li', 'flex flex-col gap-1 py-3 border-b border-outline-variant/30');
      var amb = l.ambito === 'instancia' ? T('Toda la intranet') : l.ambito === 'tarifas' ? T('Lo que cobra el proveedor') : ((empresas.filter(function (e) { return e.clave === l.ambito; })[0] || {}).nombre || l.ambito || '—');
      li.appendChild(el('span', 'font-label-md text-label-md text-on-surface', amb + (l.motivo ? ' · «' + l.motivo + '»' : '')));
      var antes = l.antes || {}, despues = l.despues || {}, cambios = [];
      Object.keys(despues).forEach(function (k) { if (nombreCampo(k) && JSON.stringify(antes[k]) !== JSON.stringify(despues[k])) cambios.push(nombreCampo(k) + ': ' + valorTxt(k, antes[k]) + ' → ' + valorTxt(k, despues[k])); });
      if (cambios.length) li.appendChild(el('span', 'font-body-sm text-body-sm text-on-surface-variant', cambios.join(' · ')));
      li.appendChild(el('span', C_PEQ, fecha(l.fecha) + ' · ' + (l.autor || '—')));
      lista.appendChild(li);
    });
    raiz.appendChild(r.s);
  }

  function carga(pendiente) {
    var raiz = document.getElementById('lw-srv'); if (!raiz) return Promise.resolve();
    return window.lwDatos('servicios_axisworks_datos').then(function (r) {
      if (r.error || !r.data) {
        raiz.textContent = '';
        raiz.appendChild(el('p', 'px-8 py-6 font-body-md text-body-md text-error', T('No se han podido leer los servicios: %m. Recarga la página.', { m: (r.error && r.error.message) || T('sin respuesta') })));
        return;
      }
      D = r.data; pinta(); devuelvePendiente(pendiente);
    });
  }

  function arranca() {
    var bt = document.querySelector('[data-lw-tab="servicios"]');
    if (!bt || !window.LW_AUTH || window.AXW_NUCLEO_OPERACION) return;   // en una instancia del ERP no existe (erp/instancias.json)
    window.LW_AUTH.then(function (aut) {
      if (!aut || !aut.sb || !window.LW_ROL || !window.LW_ROL.esSuperGlobal(aut.ficha)) return;
      sb = aut.sb;
      bt.hidden = false;
      // la pestaña estaba oculta cuando ajustes.js leyó el #: si la URL ya pedía esta, que se abra ahora
      if (location.hash === '#servicios') window.dispatchEvent(new HashChangeEvent('hashchange'));
      carga();
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
