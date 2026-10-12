/* textos-contrato-ia.js — el asistente de redacción y la traducción por IA de la pantalla «Textos de contrato», 13-oct-2026.
   Encargo agencia encargos/20261008_lawang_editor_textos_contrato.md, E5 (asistente en el párrafo) y E5b (traducir a inglés e indonesio).
   Construido APAGADO (owner 12-oct-2026, «Constrúyelo apagado»): mientras la base diga que no está encendido para la empresa, esta pantalla
   no enseña nada más que una línea en el párrafo abierto. Lo que manda está en el servidor, no aquí:
     editor_ia_estado          si está encendido y el saldo del mes (para enseñar el coste ANTES de pedir)
     edge editor-ia            la propuesta y la traducción (reserva créditos, llama al proveedor, valida lo que vuelve)
     editor_ia_aceptada        tras guardar el borrador: qué propuestas quedaron en esa versión (cuenta para el extracto)
     editor_ia_marcas / editor_ia_marca_revisada   «traducido automáticamente, sin revisar» y «ya lo he revisado»
     editor_ia_ajustes_datos / editor_ia_ajustes_guarda   la pestaña «Asistente IA» (precios y encendido), solo el super administrador global
   ACEPTAR no escribe nada: mete el texto propuesto en los cambios del editor, como si lo hubiera escrito la persona, y se guarda con el mismo
   botón, el mismo motivo y el mismo validador de la base de siempre. Descartar no escribe nada.
   Las pestañas de inglés e indonesio siguen editables a mano (decisión por defecto del 13-oct: el owner puede pedir dejarlas de solo lectura).
   Todo se pinta con createElement/textContent (parte de lo que se enseña viene de la base o del modelo). Enganche por data-tc-ia-*, nunca por rótulo. */
(function () {
  'use strict';

  var TC = window.LW_TEXTOS, API = window.LW_TC;
  if (!TC || !API) { console.error('[textos-contrato-ia] falta textos-contrato-nucleo.js o textos-contrato.js'); return; }
  var T = function (s, h) { return window.lwT ? window.lwT(s, h) : String(s).replace(/%(\w+)/g, function (m, k) { return h && k in h ? h[k] : m; }); };
  var $ = function (id) { return document.getElementById(id); };
  var el = API.el, boton = API.boton, E = API.E;

  var IA = { estado: null, empresa: null, confirmado: false, pendientes: {}, marcas: null, marcasDe: null, marcasLocal: {}, ocupado: false };

  var FRASES = {
    apagado: 'El asistente no está encendido para esta empresa.',
    tope_minuto: 'Demasiadas consultas seguidas: espera un minuto.',
    tope_empresa: 'Tu empresa ha gastado los créditos de este mes.',
    tope_global: 'El asistente ha llegado a su tope de este mes. Avisa al estudio.',
    no_configurado: 'El asistente no está configurado todavía. Avisa al estudio.',
    texto_cambiado: 'El texto ha cambiado desde que lo abriste. Guarda o deshaz, vuelve a abrirlo y pídelo otra vez.',
    parte_sensible: 'El asistente no trabaja en las partes sensibles: cámbialas a mano.',
    dato_real: 'Este texto lleva datos que no se envían al asistente (correos, teléfonos, números de identidad o importes).',
    demasiado_largo: 'Este texto es demasiado largo para el asistente.',
    instruccion_larga: 'Escribe la instrucción en 300 letras como mucho.',
    instruccion_requerida: 'Escribe qué quieres cambiar.',
    propuesta_no_valida: 'El asistente ha devuelto algo que no se puede usar (cambiaba campos o partes que no debe). No se te cobra: prueba a decirlo de otra forma.',
    modelo_no_disponible: 'El asistente no ha contestado. No se te cobra: prueba en un momento.',
    forma_distinta: 'Esta cláusula no tiene la misma forma en los dos idiomas: tradúcela con IA o a mano.',
    no_autorizado: 'Tu usuario no puede usar el asistente: lo usa la administración de la empresa.',
    sin_sesion: 'Tu sesión ha caducado. Vuelve a entrar; lo que has escrito sigue en pantalla.',
    sesion_invalida: 'Tu sesión ha caducado. Vuelve a entrar; lo que has escrito sigue en pantalla.',
    parrafo_no_editable: 'Este párrafo no se puede cambiar con el asistente.',
    solo_global: 'Este texto no lo puede cambiar una empresa sola.'
  };
  function frase(cod) { return T(FRASES[cod] || 'No ha salido bien. No se ha cambiado nada.'); }

  /* ── estado del asistente para la empresa abierta ─────────────────────────────────────────────────────────────────────────── */
  function cargaEstado() {
    if (!E.empresa) return Promise.resolve();
    var emp = E.empresa; IA.empresa = emp; IA.estado = null;
    return API.rpc('editor_ia_estado', { p_empresa: emp }).then(function (r) {
      if (IA.empresa !== emp) return;
      IA.estado = r.error || !r.data ? { error: true } : r.data;
    });
  }
  var encendido = function () { return !!(IA.estado && IA.estado.encendido === true); };
  function lineaSaldo(n) {
    var s = IA.estado || {};
    return T('Cada propuesta gasta %c créditos. Este mes tu empresa lleva %u de %t (incluidos: %i).', { c: n, u: s.usados, t: s.tope, i: s.incluidos });
  }

  /* ── llamada a la edge con la sesión de la persona ────────────────────────────────────────────────────────────────────────── */
  function llama(cuerpo) {
    return E.sb.auth.getSession().then(function (r) {
      var token = r && r.data && r.data.session && r.data.session.access_token;
      if (!token) return { codigo: 'sin_sesion' };
      var url; try { url = window.lwEdge('editor-ia'); } catch (_) { return { codigo: 'no_configurado' }; }
      return fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token, apikey: window.LW_SB_KEY }, body: JSON.stringify(cuerpo) })
        .then(function (resp) {
          return resp.text().then(function (t) {
            var d = null; try { d = JSON.parse(t); } catch (_) { d = null; }
            if (resp.ok && d && d.propuesta) return { d: d };
            var cod = d && typeof d.error === 'string' && /^[a-z_]{3,40}$/.test(d.error) ? d.error : (resp.status === 404 ? 'no_configurado' : 'otro');
            return { codigo: cod };
          });
        }, function () { return { codigo: 'modelo_no_disponible' }; });
    }, function () { return { codigo: 'sin_sesion' }; });
  }
  function confirmaGasto(titulo, texto) {
    if (typeof window.lwConfirmar !== 'function') return Promise.resolve(true);
    return window.lwConfirmar({ titulo: titulo, cuerpo: '<p>' + TC.esc(texto) + '</p>', confirmar: T('Sí, sigue') });
  }
  function textoLlano(txt) {                                                    // {{campo}} → «Etiqueta», para enseñar antes / después
    return TC.segmentos(txt).map(function (g) { return g.m ? '«' + ((E.cxEt && E.cxEt[g.k]) || TC.etiquetaMarcador(g.k, E.campos)) + '»' : g.v; }).join('');
  }
  function aplica(propuesta, uso, motivo) {
    Object.keys(propuesta).forEach(function (i) {
      var t = E.trozos[i]; if (!t) return;
      if (propuesta[i] === TC.ws(t.texto)) delete E.cambios[i]; else E.cambios[i] = propuesta[i];
      IA.pendientes[i] = { uso: uso, texto: propuesta[i] };                  // «aceptada» solo si al guardar sigue tal cual
    });
    IA.pendSlug = E.slug + '|' + E.variante;
    var m = $('tc-motivo'); if (m && !m.value.trim() && motivo) m.value = motivo.slice(0, 300);
    API.pintaDocumento(false);
  }

  /* ── E5: el asistente en el párrafo abierto ───────────────────────────────────────────────────────────────────────────────── */
  function alAbrirParrafo(ev) {
    var key = ev.detail && ev.detail.key, p = key && API.parPorKey(key), d = p && $('tc-trozos').querySelector('[data-tc-par="' + key + '"]');
    if (!p || !d || IA.estado === null) return;
    var caja = el('div', 'tc-ia-caja'); caja.setAttribute('data-tc-ia-caja', key);
    d.parentNode.insertBefore(caja, d.nextSibling);                            // FUERA del párrafo: lo que se escribe aquí no es texto del contrato
    if (IA.estado.error) return;                                               // la base no tiene el asistente (o no contestó): 0 px, como antes
    if (!encendido()) { caja.appendChild(el('p', 'tc-peq', T('Asistente de redacción: ') + frase('apagado'))); return; }
    if (p.sens) { caja.appendChild(el('p', 'tc-peq', frase('parte_sensible'))); return; }
    if (p.trozos.some(function (t) { return Object.prototype.hasOwnProperty.call(E.cambios, t.i); })) {
      caja.appendChild(el('p', 'tc-peq', T('Este párrafo tiene cambios sin guardar: guárdalos o deshazlos para pedir una propuesta.'))); return;
    }
    var lab = el('label', 'tc-peq', T('Asistente de redacción: dime qué cambiar en este párrafo')), id = 'tc-ia-in-' + key.replace(/[^0-9a-z]/gi, '-');
    lab.setAttribute('for', id);
    var inp = el('input', 'tc-ia-input'); inp.id = id; inp.type = 'text'; inp.maxLength = 300; inp.autocomplete = 'off';
    inp.setAttribute('placeholder', T('p. ej. cambia el plazo a 14 días'));
    inp.addEventListener('beforeinput', function (e) { e.stopPropagation(); });   // el papel bloquea pegar y saltos de línea en el contrato; aquí no aplica
    inp.addEventListener('keydown', function (e) { e.stopPropagation(); if (e.key === 'Enter') { e.preventDefault(); pide(); } });
    var fila = el('div', 'tc-barra-fila'), b = boton(T('Pedir propuesta'), { 'data-tc-ia-pide': key }, 'tc-btn');
    b.addEventListener('click', function (e) { e.stopPropagation(); pide(); });
    fila.appendChild(inp); fila.appendChild(b);
    var coste = el('p', 'tc-peq', lineaSaldo(IA.estado.creditos.propone));
    var res = el('div', 'tc-ia-res'); res.setAttribute('aria-live', 'polite');
    caja.appendChild(lab); caja.appendChild(fila); caja.appendChild(coste); caja.appendChild(res);

    function pide() {
      var instr = inp.value.trim();
      if (!instr || IA.ocupado) { if (!instr) muestra(frase('instruccion_requerida'), true); return; }
      var paso = IA.confirmado ? Promise.resolve(true)
        : confirmaGasto(T('El asistente gasta créditos'), T('Cada propuesta gasta %c créditos de la bolsa de tu empresa, también si la descartas. El texto de este párrafo y tu instrucción se envían al proveedor de IA; los datos de los clientes no salen nunca.', { c: IA.estado.creditos.propone }));
      paso.then(function (ok) {
        if (!ok) return;
        IA.confirmado = true; IA.ocupado = true; b.disabled = true; muestra(T('Pidiendo la propuesta…'));
        llama({ accion: 'propone', empresa: E.empresa, slug: E.slug, variante: E.variante, hash: E.ed && E.ed.hash, bloque: p.bloque, lang: E.lang === 'general' ? null : E.lang, instruccion: instr })
          .then(function (r) {
            IA.ocupado = false; b.disabled = false;
            if (!r.d) { muestra(frase(r.codigo), true); if (r.codigo === 'apagado') cargaEstado(); return; }
            actualizaSaldo(r.d); coste.textContent = lineaSaldo(IA.estado.creditos.propone);
            pintaPropuesta(r.d, instr);
          });
      });
    }
    function muestra(txt, mal) { res.textContent = ''; res.appendChild(el('p', 'tc-peq' + (mal ? ' tc-mal' : ''), txt)); }
    function pintaPropuesta(d, instr) {
      res.textContent = '';
      if (d.sin_cambios) { res.appendChild(el('p', 'tc-peq', T('El asistente no ha cambiado nada.') + (d.nota ? ' ' + d.nota : ''))); return; }
      var antes = p.trozos.filter(function (t) { return t.editable; }).map(function (t) { return textoLlano(TC.ws(t.texto)); }).join(' ');
      var despues = p.trozos.filter(function (t) { return t.editable; }).map(function (t) { return textoLlano(Object.prototype.hasOwnProperty.call(d.propuesta, t.i) ? d.propuesta[t.i] : TC.ws(t.texto)); }).join(' ');
      res.appendChild(el('p', 'tc-ia-et', T('Antes')));
      res.appendChild(el('p', 'tc-ia-antes', antes));
      res.appendChild(el('p', 'tc-ia-et', T('Después (propuesta del asistente, sin guardar)')));
      res.appendChild(el('p', 'tc-ia-despues', despues));
      var f = el('div', 'tc-barra-fila');
      var ac = boton(T('Usar esta propuesta'), { 'data-tc-ia-acepta': key }, 'tc-btn'), de = boton(T('Descartar'), { 'data-tc-ia-descarta': key });
      ac.addEventListener('click', function (e) {
        e.stopPropagation();
        API.deshacerPar();
        aplica(d.propuesta, d.uso, T('Asistente IA: %i', { i: instr }));
        if (typeof window.toast === 'function') window.toast(T('Propuesta puesta en el texto. Revísala y guarda el borrador.'));
      });
      de.addEventListener('click', function (e) { e.stopPropagation(); res.textContent = ''; res.appendChild(el('p', 'tc-peq', T('Propuesta descartada: no se ha cambiado nada.'))); });
      f.appendChild(ac); f.appendChild(de); res.appendChild(f);
    }
  }
  function actualizaSaldo(d) { if (IA.estado && typeof d.usados === 'number') { IA.estado.usados = d.usados; IA.estado.tope = d.tope; IA.estado.incluidos = d.incluidos; } }

  /* ── E5b: «Traducir del español» en inglés e indonesio, y «traducido sin revisar» ─────────────────────────────────────────── */
  function sha(txt) {
    if (!window.crypto || !window.crypto.subtle) return Promise.resolve(null);
    return window.crypto.subtle.digest('SHA-256', new TextEncoder().encode(txt)).then(function (b) {
      return Array.prototype.map.call(new Uint8Array(b), function (x) { return ('0' + x.toString(16)).slice(-2); }).join('');
    });
  }
  function valor(t) { return Object.prototype.hasOwnProperty.call(E.cambios, t.i) ? E.cambios[t.i] : TC.ws(t.texto); }
  function cargaMarcas() {
    var de = E.empresa + '|' + E.slug + '|' + E.variante;
    if (IA.marcasDe === de || !IA.estado || IA.estado.error) return Promise.resolve();
    IA.marcasDe = de; IA.marcas = {};
    return API.rpc('editor_ia_marcas', { p_empresa: E.empresa, p_slug: E.slug, p_variante: E.variante }).then(function (r) {
      if (IA.marcasDe !== de || r.error || !Array.isArray(r.data)) return;
      r.data.forEach(function (m) { IA.marcas[m.lang + '|' + m.huella] = true; });
    });
  }
  function alPintar() {
    if (!E.slug || E.lang === 'es' || E.lang === 'general' || IA.estado === null || IA.estado.error) return;
    var lang = E.lang;
    cargaMarcas().then(function () { pintaMarcas(lang); });
    if (encendido() && (E.langs || []).indexOf('es') !== -1) pintaTraducir(lang);
  }
  function pintaMarcas(lang) {
    if (E.lang !== lang) return;
    (E.pars || []).forEach(function (p) {
      if (E.edicion === p.key) return;
      var ts = p.trozos.filter(function (t) { return t.editable; });
      Promise.all(ts.map(function (t) { return sha(valor(t)); })).then(function (hs) {
        var sin = hs.filter(function (h) { return h && (IA.marcas[lang + '|' + h] || IA.marcasLocal[lang + '|' + h]); });
        var d = $('tc-trozos').querySelector('[data-tc-par="' + p.key + '"]');
        if (!sin.length || !d || E.lang !== lang || d.nextSibling && d.nextSibling.getAttribute && d.nextSibling.getAttribute('data-tc-ia-marca') === p.key) return;
        var n = el('div', 'tc-aviso-rev tc-ia-marca'); n.setAttribute('data-tc-ia-marca', p.key); n.setAttribute('role', 'status');
        n.appendChild(el('span', null, T('Traducido automáticamente, sin revisar.')));
        var b = boton(T('Ya lo he revisado'), { 'data-tc-ia-revisado': p.key });
        b.addEventListener('click', function (e) {
          e.stopPropagation(); b.disabled = true;
          sin.forEach(function (h) { delete IA.marcasLocal[lang + '|' + h]; });
          API.rpc('editor_ia_marca_revisada', { p_empresa: E.empresa, p_slug: E.slug, p_variante: E.variante, p_lang: lang, p_huellas: sin }).then(function (r) {
            if (r.error) { b.disabled = false; n.appendChild(el('span', 'tc-peq tc-mal', T('No se ha podido anotar. Prueba otra vez.'))); return; }
            sin.forEach(function (h) { delete IA.marcas[lang + '|' + h]; });
            if (n.parentNode) n.parentNode.removeChild(n);
          });
        });
        n.appendChild(b);
        d.parentNode.insertBefore(n, d.nextSibling);
      });
    });
  }
  function pintaTraducir(lang) {
    var c = IA.estado.creditos;
    [].forEach.call($('tc-trozos').querySelectorAll('.tc-sec[data-tc-sec]'), function (caja) {
      var sec = Number(caja.getAttribute('data-tc-sec'));
      var pars = (E.pars || []).filter(function (p) { return p.sec === sec && p.editable; });
      if (!pars.length || pars.some(function (p) { return p.sens; })) return;      // con partes sensibles, a mano
      var nEs = {}; E.trozos.forEach(function (t) { if (t.sec === sec && t.lang === 'es' && t.editable) nEs[t.bloque] = 1; });
      var n = Object.keys(nEs).length; if (!n) return;
      var f = el('div', 'tc-ia-traduce'); f.setAttribute('data-tc-ia-traduce', String(sec));
      f.appendChild(el('span', 'tc-peq', T('Traducir esta cláusula del español:')));
      [['deepl', T('Con DeepL (%c créditos)', { c: n * c.traduce_deepl })], ['ia', T('Con IA (%c créditos)', { c: n * c.traduce_ia })]].forEach(function (m) {
        var b = boton(m[1], { 'data-tc-ia-motor': m[0] });
        b.addEventListener('click', function (e) { e.stopPropagation(); traduce(sec, m[0], n, f); });
        f.appendChild(b);
      });
      caja.insertBefore(f, caja.firstChild);
    });
  }
  function traduce(sec, motor, n, f) {
    if (IA.ocupado) return;
    // se traduce el español GUARDADO (la función lo lee de la base): con cambios sin guardar en el español de esta cláusula, el
    // inglés o el indonesio saldrían de un texto que ya no es el de pantalla
    if (E.trozos.some(function (t) { return t.sec === sec && t.lang === 'es' && Object.prototype.hasOwnProperty.call(E.cambios, t.i); })) {
      var av = f.querySelector('[data-tc-ia-aviso]') || f.appendChild(el('p', 'tc-peq tc-mal')); av.setAttribute('data-tc-ia-aviso', '1');
      av.textContent = T('El español de esta cláusula tiene cambios sin guardar: guárdalos antes de traducir.'); return;
    }
    var cr = n * IA.estado.creditos[motor === 'ia' ? 'traduce_ia' : 'traduce_deepl'], lang = E.lang;
    var hay = E.trozos.some(function (t) { return t.sec === sec && t.lang === lang && Object.prototype.hasOwnProperty.call(E.cambios, t.i); });
    confirmaGasto(T('Traducir «%s»', { s: API.tituloSec(sec) }),
      T('Gasta %c créditos (%n párrafos). El texto en español de esta cláusula se envía al traductor; los datos de los clientes no salen nunca. Lo traducido queda marcado «sin revisar» hasta que lo revises.', { c: cr, n: n })
      + (hay ? ' ' + T('Lo que has cambiado a mano en esta cláusula en este idioma se sustituye.') : '')).then(function (ok) {
      if (!ok) return;
      IA.ocupado = true;
      var aviso = el('p', 'tc-peq', T('Traduciendo…')); f.appendChild(aviso);
      llama({ accion: 'traduce', motor: motor, destino: lang, empresa: E.empresa, slug: E.slug, variante: E.variante, hash: E.ed && E.ed.hash, sec: sec }).then(function (r) {
        IA.ocupado = false;
        if (!r.d) { aviso.textContent = frase(r.codigo); aviso.className = 'tc-peq tc-mal'; if (r.codigo === 'apagado') cargaEstado(); return; }
        actualizaSaldo(r.d);
        var hs = Object.keys(r.d.propuesta).map(function (i) { return sha(r.d.propuesta[i]); });
        Promise.all(hs).then(function (lista) {
          lista.forEach(function (h) { if (h) IA.marcasLocal[lang + '|' + h] = true; });
          aplica(r.d.propuesta, r.d.uso, T('Traducción automática de «%s»', { s: API.tituloSec(sec) }));
          if (typeof window.toast === 'function') window.toast(T('Cláusula traducida. Revísala y guarda el borrador.'));
        });
      });
    });
  }

  /* ── tras guardar: qué propuestas quedaron en la versión ──────────────────────────────────────────────────────────────────── */
  function alGuardar(ev) {
    var v = ev.detail && ev.detail.version, usos = {};
    if (!v || IA.pendSlug !== E.slug + '|' + E.variante) { IA.pendientes = {}; return; }
    // el aviso llega ANTES de vaciar E.cambios: cuenta como aceptada la propuesta que se guarda tal cual la dio el asistente
    // (si se deshizo, o se retocó a mano después, no)
    Object.keys(IA.pendientes).forEach(function (i) { var p = IA.pendientes[i]; if (E.cambios[i] === p.texto) usos[p.uso] = 1; });
    IA.pendientes = {};
    Object.keys(usos).forEach(function (u) {
      // MUDO A PROPOSITO: es solo la marca «aceptada» del extracto; el borrador ya está guardado y el uso ya contó
      API.rpc('editor_ia_aceptada', { p_uso: u, p_version: v });
    });
  }

  /* ── la pestaña «Asistente IA»: precios y encendido (solo el super administrador global) ──────────────────────────────────── */
  var CAMPOS_INST = [
    ['precio_credito', 'Precio de un crédito', 'num'], ['moneda', 'Moneda', 'moneda'],
    ['creditos_propuesta', 'Créditos por propuesta', 'ent'], ['creditos_traduccion_ia', 'Créditos por párrafo traducido con IA', 'ent'],
    ['creditos_traduccion_deepl', 'Créditos por párrafo traducido con DeepL', 'ent'], ['tope_global_mensual', 'Tope de créditos al mes de toda la intranet', 'ent'],
    ['factura_a', 'A quién se factura', 'factura'], ['caducan', 'Los créditos no usados caducan a fin de mes', 'sino'],
    ['prueba_creditos', 'Créditos de prueba por empresa (no se facturan)', 'ent'],
    ['tarifa_entrada_usd_mtok', 'Coste del proveedor de IA: dólares por millón de tokens de entrada', 'num'],
    ['tarifa_salida_usd_mtok', 'Coste del proveedor de IA: dólares por millón de tokens de salida', 'num'],
    ['tarifa_deepl_usd_mcar', 'Coste de DeepL: dólares por millón de caracteres', 'num']
  ];
  function control(tipo, valor) {
    var c;
    if (tipo === 'moneda' || tipo === 'factura' || tipo === 'sino') {
      c = el('select', null);
      var ops = tipo === 'moneda' ? [['', T('Sin poner')], ['EUR', 'EUR'], ['USD', 'USD'], ['IDR', 'IDR']]
        : tipo === 'factura' ? [['', T('Sin poner')], ['instancia', T('A Lawang, todo junto')], ['empresa', T('A cada empresa por separado')]]
        : [['', T('Sin poner')], ['true', T('Sí')], ['false', T('No')]];
      ops.forEach(function (o) { var op = el('option', null, o[1]); op.value = o[0]; c.appendChild(op); });
      c.value = valor === null || valor === undefined ? '' : String(valor);
    } else {
      c = el('input', null); c.type = 'number'; c.min = '0'; c.step = tipo === 'ent' ? '1' : 'any';
      c.value = valor === null || valor === undefined ? '' : String(valor);
    }
    c.setAttribute('data-tc-ia-tipo', tipo);
    return c;
  }
  function leeControl(c) {
    var v = c.value, t = c.getAttribute('data-tc-ia-tipo');
    if (v === '') return null;
    if (t === 'sino') return v === 'true';
    if (t === 'moneda' || t === 'factura') return v;
    return Number(v);
  }
  function campoFila(nombre, ctrl) {
    var f = el('label', 'tc-campo tc-ia-campo'); f.appendChild(el('span', 'tc-peq', nombre)); f.appendChild(ctrl); return f;
  }
  function cargaAjustes() {
    var panel = $('tc-ia-ajustes'); if (!panel) return;
    panel.textContent = ''; panel.appendChild(el('p', 'tc-vacio', T('Trayendo los precios del asistente…')));
    API.rpc('editor_ia_ajustes_datos', {}).then(function (r) {
      panel.textContent = '';
      if (r.error || !r.data) { panel.appendChild(el('p', 'tc-vacio tc-mal', T('No he podido leer los precios del asistente: ') + API.msg(r.error))); return; }
      pintaAjustes(panel, r.data);
    });
  }
  function guardaAjustes(empresa, campos, motivo, estado) {
    if (!Object.keys(campos).length) { estado.textContent = T('No has cambiado nada.'); return; }
    if (motivo.length < 3) { estado.textContent = T('Escribe el motivo del cambio (mínimo tres letras): queda en el registro.'); estado.className = 'tc-peq tc-mal'; return; }
    estado.textContent = T('Guardando…'); estado.className = 'tc-peq';
    API.rpc('editor_ia_ajustes_guarda', { p_empresa: empresa, p_campos: campos, p_motivo: motivo }).then(function (r) {
      if (r.error) { estado.textContent = T('No se ha guardado: ') + API.msg(r.error); estado.className = 'tc-peq tc-mal'; return; }
      if (typeof window.toast === 'function') window.toast(T('Guardado.'));
      cargaAjustes(); cargaEstado();
    });
  }
  function pintaAjustes(panel, d) {
    var inst = d.instancia || {};
    panel.appendChild(el('p', 'tc-peq', T('Todo nace vacío y apagado. Mientras falte un dato o una empresa esté apagada, el servidor rechaza cualquier consulta y no se gasta nada. La clave del proveedor no va aquí: se pone en los secretos de la función editor-ia (EDITOR_IA_ANTHROPIC_KEY y EDITOR_IA_DEEPL_KEY).')));
    // la instancia
    var s1 = el('section', 'tc-seccion'); s1.appendChild(el('h2', null, T('Precios de toda la intranet')));
    var malla = el('div', 'tc-ia-malla'), ctrls = {};
    CAMPOS_INST.forEach(function (c) { ctrls[c[0]] = control(c[2], inst[c[0]]); malla.appendChild(campoFila(T(c[1]), ctrls[c[0]])); });
    s1.appendChild(malla);
    var mot = el('input', 'tc-ia-input'); mot.type = 'text'; mot.maxLength = 300; mot.setAttribute('placeholder', T('Motivo del cambio (queda en el registro)'));
    var est = el('p', 'tc-peq'), bg = boton(T('Guardar precios'), { 'data-tc-ia-guarda': 'instancia' }, 'tc-btn');
    bg.addEventListener('click', function () {
      var campos = {};
      CAMPOS_INST.forEach(function (c) {
        var antes = inst[c[0]] === undefined || inst[c[0]] === null ? null : ((c[2] === 'num' || c[2] === 'ent') ? Number(inst[c[0]]) : inst[c[0]]);
        var v = leeControl(ctrls[c[0]]); if (v !== antes) campos[c[0]] = v;
      });
      guardaAjustes(null, campos, mot.value.trim(), est);
    });
    var fila = el('div', 'tc-barra-fila'); fila.appendChild(campoFila(T('Motivo'), mot)); fila.appendChild(bg);
    s1.appendChild(fila); s1.appendChild(est); panel.appendChild(s1);
    // las empresas
    var s2 = el('section', 'tc-seccion'); s2.appendChild(el('h2', null, T('Cada empresa')));
    s2.appendChild(el('p', 'tc-peq', T('Este mes la intranet lleva %u créditos.', { u: d.usados_instancia })));
    (d.empresas || []).forEach(function (e) {
      var caja = el('div', 'tc-ia-empresa');
      caja.appendChild(el('h3', null, e.nombre + ' · ' + (e.encendido ? T('encendido') : T('apagado'))));
      if (e.falta) caja.appendChild(el('p', 'tc-peq', e.falta));
      var on = el('input', null); on.type = 'checkbox'; on.checked = !!e.encendido; on.setAttribute('data-tc-ia-encendido', e.clave);
      var inc = control('ent', e.creditos_incluidos), tope = control('ent', e.tope_mensual);
      var m = el('div', 'tc-ia-malla');
      var lon = el('label', 'tc-chk'); lon.appendChild(on); lon.appendChild(el('span', null, T('Encendido para esta empresa')));
      m.appendChild(lon); m.appendChild(campoFila(T('Créditos incluidos al mes'), inc)); m.appendChild(campoFila(T('Tope de créditos al mes'), tope));
      caja.appendChild(m);
      caja.appendChild(el('p', 'tc-peq', T('Este mes lleva %u créditos.', { u: e.usados })));
      var mo = el('input', 'tc-ia-input'); mo.type = 'text'; mo.maxLength = 300; mo.setAttribute('placeholder', T('Motivo del cambio (queda en el registro)'));
      var es = el('p', 'tc-peq'), b = boton(T('Guardar esta empresa'), { 'data-tc-ia-guarda': e.clave }, 'tc-btn');
      b.addEventListener('click', function () {
        var campos = {}, vi = leeControl(inc), vt = leeControl(tope);
        if (on.checked !== !!e.encendido) campos.encendido = on.checked;
        if (vi !== e.creditos_incluidos) campos.creditos_incluidos = vi;
        if (vt !== e.tope_mensual) campos.tope_mensual = vt;
        guardaAjustes(e.clave, campos, mo.value.trim(), es);
      });
      var f = el('div', 'tc-barra-fila'); f.appendChild(campoFila(T('Motivo'), mo)); f.appendChild(b);
      caja.appendChild(f); caja.appendChild(es); s2.appendChild(caja);
    });
    panel.appendChild(s2);
    // extracto y registro
    var s3 = el('section', 'tc-seccion'); s3.appendChild(el('h2', null, T('Extracto de los tres últimos meses')));
    if (!(d.extracto || []).length) s3.appendChild(el('p', 'tc-peq', T('Todavía no hay ningún uso.')));
    else {
      var tb = el('table', 'tc-tabla'), cab = el('tr', null);
      [T('Mes'), T('Empresa'), T('Consultas'), T('Fallidas'), T('Sin cerrar'), T('Créditos hechos'), T('De prueba'), T('Créditos facturables'), T('Incluidos'), T('Exceso'), T('Importe'), T('Aceptadas'), T('Coste real (USD)')].forEach(function (h) { cab.appendChild(el('th', null, h)); });
      tb.appendChild(cab);
      d.extracto.forEach(function (x) {
        var tr = el('tr', null);
        [String(x.periodo).slice(0, 7), x.empresa, x.llamadas, x.fallidas, x.pendientes, x.creditos, x.creditos_prueba, x.facturables, x.incluidos === null ? '—' : x.incluidos, x.exceso, x.importe + (x.moneda ? ' ' + x.moneda : ''), x.aceptadas, x.coste_usd + (x.coste_incompleto ? ' (' + T('sin tarifa') + ')' : '')].forEach(function (v) { tr.appendChild(el('td', null, String(v))); });
        tb.appendChild(tr);
      });
      s3.appendChild(tb);
    }
    panel.appendChild(s3);
    var s4 = el('section', 'tc-seccion'); s4.appendChild(el('h2', null, T('Registro de cambios de precios')));
    if (!(d.registro || []).length) s4.appendChild(el('p', 'tc-peq', T('Nadie ha cambiado los precios todavía.')));
    (d.registro || []).forEach(function (l) { s4.appendChild(el('p', 'tc-peq', API.fFechaHora(l.fecha) + ' · ' + l.autor + ' · ' + l.ambito + ' · ' + l.motivo)); });
    panel.appendChild(s4);
  }
  function cablePestana() {
    var b = document.querySelector('[data-tc-ia-pestana]'), panel = document.querySelector('[data-tc-panel="ia"]');
    if (!b || !panel) return;
    var rol = window.LW_ROL, global = rol && rol.esSuperAdmin(E.ficha) && rol.esGlobal(E.ficha);
    if (!global) return;                                                       // solo el super administrador global; la base lo vuelve a comprobar
    b.hidden = false;
    b.addEventListener('click', function (e) {
      e.stopPropagation();
      [].forEach.call(document.querySelectorAll('[data-tc-pestana]'), function (x) { x.setAttribute('aria-selected', 'false'); });
      [].forEach.call(document.querySelectorAll('[data-tc-panel]'), function (x) { x.hidden = x !== panel; });
      b.setAttribute('aria-selected', 'true');
      cargaAjustes();
    });
    // las otras pestañas (textos-contrato-config.js) esconden este panel solas; aquí solo se desmarca el botón
    [].forEach.call(document.querySelectorAll('[data-tc-pestana]'), function (x) { x.addEventListener('click', function () { b.setAttribute('aria-selected', 'false'); panel.hidden = true; }); });
  }

  /* ── puesta en marcha ─────────────────────────────────────────────────────────────────────────────────────────────────────── */
  document.addEventListener('lw-tc-listo', function () { cargaEstado(); cablePestana(); });
  document.addEventListener('lw-tc-empresa', function () { IA.pendientes = {}; IA.marcasDe = null; IA.confirmado = false; cargaEstado(); });
  document.addEventListener('lw-tc-par-abierto', alAbrirParrafo);
  document.addEventListener('lw-tc-pintado', alPintar);
  document.addEventListener('lw-tc-guardado', alGuardar);
})();
