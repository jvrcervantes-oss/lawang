/* Ajustes → «Servicios de AxisWorks» (AXW-104, decisión del owner 13-oct-2026). Primer servicio de pago: el asistente de IA del editor
 * de textos de contrato. Encargo agencia encargos/20261008_lawang_editor_textos_contrato.md (E11). Migración 20261013210000.
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
 */
(function () {
  'use strict';
  function T(s, h) { if (window.lwT) return window.lwT(s, h); var v = String(s); for (var k in h) if (Object.prototype.hasOwnProperty.call(h, k)) v = v.split('%' + k).join(h[k]); return v; }
  function aviso(t) { if (typeof toast === 'function') toast(t); }
  function el(tag, cls, txt) { var e = document.createElement(tag); if (cls) e.className = cls; if (txt != null) e.textContent = txt; return e; }
  function usd(n) {
    var x = Number(n);
    if (n === null || n === undefined || n === '' || !isFinite(x)) return '—';
    return typeof window.lwFormatoImporte === 'function' ? window.lwFormatoImporte(x, 'USD') : x.toFixed(2) + ' USD';
  }
  function fecha(x) { if (!x) return '—'; var d = new Date(x); return isNaN(d) ? String(x) : d.toLocaleString(window.lwLocale ? window.lwLocale() : 'es-ES'); }
  function mes(p) { var d = new Date(String(p) + 'T00:00:00'); return isNaN(d) ? String(p) : d.toLocaleDateString(window.lwLocale ? window.lwLocale() : 'es-ES', { month: 'long', year: 'numeric' }); }

  var sb = null, D = null;
  var C_ETQ = 'font-label-md text-[11px] tracking-[0.16em] uppercase text-outline font-bold';
  var C_INPUT = 'w-full md:w-40 rounded-lg border border-control-border/50 bg-surface-container-lowest px-3 py-2.5 font-body-md text-body-md';
  var C_BTN = 'shrink-0 px-5 py-2.5 rounded-full bg-primary-container text-on-primary hover:bg-primary font-label-md text-label-md';
  var C_BTN2 = 'shrink-0 px-4 py-2 rounded-full border border-outline-variant text-on-surface hover:bg-surface-container font-label-md text-label-md';
  var C_PEQ = 'font-body-sm text-body-sm text-outline';

  /* ── un campo numérico con su etiqueta y su ayuda ─────────────────────────────────────────────────────────── */
  function campoNum(clave, etiqueta, valor, ayuda, paso) {
    var f = el('label', 'flex flex-col gap-1'); f.setAttribute('data-srv-campo', clave);
    f.appendChild(el('span', 'font-label-md text-label-md text-on-surface', etiqueta));
    var i = el('input', C_INPUT); i.type = 'number'; i.step = paso || 'any'; i.min = '0'; i.inputMode = 'decimal';
    i.value = valor == null ? '' : String(valor); i.setAttribute('data-srv-in', clave); i.setAttribute('data-srv-antes', i.value);
    f.appendChild(i);
    if (ayuda) f.appendChild(el('span', C_PEQ, ayuda));
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
  function filaMotivo(raiz, accion, empresa) {
    var f = el('div', 'flex flex-col md:flex-row gap-3 md:items-center pt-2');
    var m = el('input', 'w-full md:w-96 rounded-lg border border-control-border/50 bg-surface-container-lowest px-3 py-2.5 font-body-md text-body-md');
    m.maxLength = 300; m.setAttribute('placeholder', T('Motivo del cambio (queda en el registro)')); m.setAttribute('data-srv-motivo', '1');
    var b = el('button', C_BTN, T('Guardar')); b.type = 'button'; b.setAttribute('data-accion', 'servicios-guardar'); b.setAttribute('data-real', '1');
    if (empresa) b.setAttribute('data-srv-empresa', empresa);
    b.addEventListener('click', function (ev) { ev.stopPropagation(); guarda(raiz, empresa || null, m, b); });
    f.appendChild(m); f.appendChild(b);
    return f;
  }

  function guarda(raiz, empresa, m, b, extra) {
    var lc = extra ? { campos: extra, mal: null } : leeCambios(raiz), campos = lc.campos;
    if (lc.mal) { aviso(T('Escribe un número en este campo (con punto para los decimales); no se ha guardado nada.')); lc.mal.focus(); return; }
    if (!campos) { aviso(T('No has cambiado nada.')); return; }
    var motivo = (m && m.value || '').trim();
    if (motivo.length < 3) { aviso(T('Escribe el motivo del cambio (queda en el registro).')); if (m) m.focus(); return; }
    b.disabled = true;
    sb.rpc('servicios_axisworks_guarda', { p_empresa: empresa, p_campos: campos, p_motivo: motivo }).then(function (r) {
      b.disabled = false;
      if (r.error) { aviso(T('No se ha guardado: %m', { m: r.error.message || T('sin detalle') })); return; }
      aviso(T('Guardado.'));
      carga();
    });
  }

  /* ── pintar ───────────────────────────────────────────────────────────────────────────────────────────────── */
  function seccion(etq, titulo, texto) {
    var s = el('section', 'bg-surface-container-lowest rounded-xl shadow-sm overflow-hidden');
    var h = el('div', 'px-8 pt-8 pb-4 flex flex-col gap-1 border-b border-outline-variant/40');
    h.appendChild(el('span', C_ETQ, etq));
    h.appendChild(el('h2', 'font-headline-sm text-headline-sm text-deep-lagoon tracking-tight', titulo));
    if (texto) h.appendChild(el('p', C_PEQ, texto));
    s.appendChild(h);
    var c = el('div', 'px-8 py-6 flex flex-col gap-4'); s.appendChild(c);
    return { s: s, c: c };
  }

  function pinta() {
    var raiz = document.getElementById('lw-srv'); if (!raiz) return;
    raiz.textContent = '';
    var I = D.instancia || {}, Tf = D.tarifas || {};

    // 1. el precio y los topes de toda la intranet
    var a = seccion(T('Servicios de AxisWorks'), T('Precio y topes'),
      T('Lo que cuesta cada servicio de pago = el coste real del proveedor + este margen. Se cobra en la factura mensual de mantenimiento. Los topes cuentan el coste real (lo que AxisWorks paga al proveedor); al llegar, el servicio se para hasta el mes siguiente o hasta que se suba aquí.'));
    var malla = el('div', 'grid grid-cols-1 md:grid-cols-2 gap-5');
    malla.appendChild(campoNum('margen_pct', T('Margen sobre el coste (%)'), I.margen_pct,
      I.margen_pct == null ? T('Sin margen el asistente no arranca: ponlo tú.') : null, '0.01'));
    malla.appendChild(campoNum('aviso_pct', T('Avisar al llegar al (%) del tope'), I.aviso_pct, null, '1'));
    malla.appendChild(campoNum('tope_usd_defecto', T('Tope por empresa y mes (USD de coste)'), I.tope_usd_defecto,
      I.margen_pct == null ? null : T('Máximo facturable por empresa y mes: %f (tope × (1 + margen)).', { f: usd(Number(I.tope_usd_defecto) * (1 + Number(I.margen_pct) / 100)) }), '0.01'));
    malla.appendChild(campoNum('tope_instancia_usd', T('Tope de toda la intranet y mes (USD de coste)'), I.tope_instancia_usd,
      T('Pon aquí el mismo límite de gasto que tiene la clave en la consola del proveedor: si las empresas suman más, el proveedor corta a mitad de una consulta.'), '0.01'));
    malla.appendChild(campoNum('tarifa_entrada_usd_mtok', T('Coste del proveedor: USD por millón de tokens de entrada (%m)', { m: Tf.modelo || '' }), Tf.tarifa_entrada_usd_mtok, null, '0.0001'));
    malla.appendChild(campoNum('tarifa_salida_usd_mtok', T('Coste del proveedor: USD por millón de tokens de salida (%m)', { m: Tf.modelo || '' }), Tf.tarifa_salida_usd_mtok, null, '0.0001'));
    a.c.appendChild(malla);
    a.c.appendChild(el('p', C_PEQ, T('Gasto de este mes (%p, hora de Bali), todas las empresas: %g de %t.', { p: mes(D.periodo), g: usd(I.gasto_usd), t: usd(I.tope_instancia_usd) })
      + (I.actualizado_en ? ' ' + T('Último cambio: %q, %f.', { q: I.actualizado_por || '—', f: fecha(I.actualizado_en) }) : '')));
    a.c.appendChild(filaMotivo(a.c, 'instancia', null));
    raiz.appendChild(a.s);

    // 2. por empresa: encendido, impago y tope propio
    var b = seccion(T('Servicios de AxisWorks'), T('Empresas'),
      T('«Suspender por impago» apaga todos los servicios de pago de esa empresa hasta que lo quites tú: nada se apaga solo. Tope propio vacío = el tope por defecto.'));
    (D.empresas || []).forEach(function (e) {
      var fila = el('div', 'flex flex-col gap-3 py-4 border-b border-outline-variant/30'); fila.setAttribute('data-srv-empresa-fila', e.clave);
      fila.appendChild(el('span', 'font-label-md text-label-md text-on-surface', e.nombre || e.clave));
      var est = T('Asistente de textos: %a. Este mes: %g de %t de coste.', { a: e.editor_ia ? T('encendido') : T('apagado'), g: usd(e.gasto_usd), t: usd(e.tope_efectivo_usd) });
      if (e.suspendido) est += ' ' + T('SUSPENDIDO POR IMPAGO.');
      else if (e.falta && e.editor_ia) est += ' ' + e.falta;
      fila.appendChild(el('p', e.suspendido ? 'font-body-sm text-body-sm text-error' : C_PEQ, est));
      var botones = el('div', 'flex flex-wrap gap-2');
      var m = null;
      function interruptor(clave, valor, txt) {
        var x = el('button', C_BTN2, txt); x.type = 'button'; x.setAttribute('data-accion', 'servicios-' + clave); x.setAttribute('data-real', '1');
        x.setAttribute('data-srv-empresa', e.clave);
        x.addEventListener('click', function (ev) {
          ev.stopPropagation();
          var c = {}; c[clave] = valor;
          var q = window.lwConfirmar ? window.lwConfirmar({ titulo: txt, cuerpo: '<p>' + String(e.nombre || e.clave).replace(/[&<>"']/g, '') + '</p>', confirmar: T('Sí, cambiar') }) : Promise.resolve(true);
          q.then(function (si) { if (si) guarda(fila, e.clave, m, x, c); });
        });
        botones.appendChild(x);
      }
      interruptor('editor_ia', !e.editor_ia, e.editor_ia ? T('Apagar el asistente de textos') : T('Encender el asistente de textos'));
      interruptor('suspendido', !e.suspendido, e.suspendido ? T('Quitar la suspensión') : T('Suspender por impago'));
      fila.appendChild(botones);
      var g = el('div', 'flex flex-col md:flex-row gap-3 md:items-end');
      g.appendChild(campoNum('tope_usd', T('Tope propio (USD de coste al mes)'), e.tope_usd, null, '0.01'));
      fila.appendChild(g);
      var fm = filaMotivo(fila, 'empresa', e.clave); m = fm.querySelector('[data-srv-motivo]');
      fila.appendChild(fm);
      b.c.appendChild(fila);
    });
    raiz.appendChild(b.s);

    // 3. extracto mensual
    var x = seccion(T('Servicios de AxisWorks'), T('Extracto para la factura de mantenimiento'),
      T('Últimos tres meses, por empresa, en USD y sin impuestos (el mes es el de Bali). Se factura solo lo que terminó bien; lo que falló después de enviarse lo pagó AxisWorks al proveedor y no se repercute. Cada consulta guarda su margen: un cambio de margen no cambia lo ya gastado.'));
    var filas = D.extracto || [];
    if (!filas.length) x.c.appendChild(el('p', C_PEQ, T('Todavía no hay consultas.')));
    else {
      var envolt = el('div', 'overflow-x-auto');
      var tb = el('table', 'w-full text-left border-collapse font-body-sm text-body-sm');
      var cab = el('tr');
      [T('Mes'), T('Empresa'), T('Consultas (bien / mal / en curso)'), T('Coste del proveedor'), T('Coste no repercutido'), T('Coste facturable'), T('Margen'), T('Total sin impuestos')].forEach(function (h) {
        cab.appendChild(el('th', 'py-2 pr-4 font-label-md text-label-md text-outline', h));
      });
      tb.appendChild(cab);
      filas.forEach(function (f) {
        var tr = el('tr', 'border-t border-outline-variant/30');
        var nom = ((D.empresas || []).filter(function (e) { return e.clave === f.empresa; })[0] || {}).nombre || f.empresa;
        var total = usd(f.total_sin_impuestos_usd) + (f.margenes_pct && f.margenes_pct.length ? ' (' + f.margenes_pct.join(' / ') + ' %)' : '');
        [mes(f.periodo), nom, f.hechas + ' / ' + f.fallidas + ' / ' + f.en_vuelo, usd(f.coste_proveedor_usd), usd(f.coste_no_repercutido_usd),
         usd(f.coste_facturable_usd), usd(f.margen_usd), total].forEach(function (v) { tr.appendChild(el('td', 'py-2 pr-4 text-on-surface', v)); });
        tb.appendChild(tr);
        if (f.coste_incompleto) {
          var tr2 = el('tr'); var td = el('td', 'pb-2 font-body-sm text-body-sm text-error', T('Coste incompleto: alguna consulta se cortó sin saber cuánto cobró el proveedor (cuenta contra el tope al máximo posible; no se factura).'));
          td.colSpan = 8; tr2.appendChild(td); tb.appendChild(tr2);
        }
      });
      envolt.appendChild(tb); x.c.appendChild(envolt);
    }
    raiz.appendChild(x.s);

    // 4. registro
    var r = seccion(T('Servicios de AxisWorks'), T('Registro de cambios'), null);
    var reg = D.registro || [];
    if (!reg.length) r.c.appendChild(el('p', C_PEQ, T('Sin cambios todavía.')));
    reg.forEach(function (l) {
      var p = el('p', C_PEQ);
      p.textContent = fecha(l.fecha) + ' · ' + (l.autor || '—') + ' · ' + (l.ambito || '') + ' · ' + (l.motivo || '');
      r.c.appendChild(p);
    });
    raiz.appendChild(r.s);
  }

  function carga() {
    var raiz = document.getElementById('lw-srv'); if (!raiz) return Promise.resolve();
    return window.lwDatos('servicios_axisworks_datos').then(function (r) {
      if (r.error || !r.data) {
        raiz.textContent = '';
        raiz.appendChild(el('p', 'px-8 py-6 font-body-md text-body-md text-error', T('No se han podido leer los servicios: %m. Recarga la página.', { m: (r.error && r.error.message) || T('sin respuesta') })));
        return;
      }
      D = r.data; pinta();
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
