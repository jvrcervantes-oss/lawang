/* textos-contrato-ia.js — el asistente de redacción y la traducción por IA de la pantalla «Textos de contrato», 13-oct-2026.
   Encargo agencia encargos/20261008_lawang_editor_textos_contrato.md, E5 (asistente en el párrafo) y E5b (traducir a inglés e indonesio).
   Construido APAGADO (owner 12-oct-2026, «Constrúyelo apagado»): mientras la base diga que no está encendido para la empresa, esta pantalla
   no enseña nada más que una línea en el párrafo abierto, con el MOTIVO que da la base (p. ej. «falta el margen»).
   13-oct-2026 (owner, AXW-104): es el primer «Servicio de AxisWorks» de pago. Ya no hay créditos: cuesta el coste real del proveedor + un
   margen, en dólares, con un tope al mes por empresa. Lo que manda está en el servidor, no aquí:
     editor_ia_estado          si está encendido (o por qué no), el gasto del mes contra el tope y el PEOR caso de cada llamada (se enseña ANTES de pedir)
     edge editor-ia            la propuesta y la traducción (aparta el peor caso del tope, llama al proveedor, valida lo que vuelve)
     editor_ia_aceptada        tras guardar el borrador: qué propuestas quedaron en esa versión (cuenta para el extracto)
     editor_ia_marcas / editor_ia_marca_revisada   «traducido automáticamente, sin revisar» y «ya lo he revisado»
   La configuración (margen, topes, tarifas, empresas, extracto) NO está en esta pantalla: vive en Ajustes → Servicios de AxisWorks
   (ajustes-servicios.js), solo para el super administrador global.
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
    tope_empresa: 'Esta empresa llegó a su tope de este mes; el estudio puede subirlo.',
    tope_global: 'El asistente ha llegado al tope de gasto de este mes de toda la intranet. Avisa al estudio.',
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
  var DEEPL_NO = 'La traducción con DeepL no está configurada: usa la IA.';
  // por qué está apagado, por CLAVE (editor_ia_estado.motivo_clave, o la edge): se traduce aquí; el texto en llano de la base es para Ajustes
  var MOTIVOS = {
    apagado: FRASES.apagado,
    suspendido: 'Los servicios de pago de AxisWorks están suspendidos para esta empresa. Habla con el estudio.',
    sin_configurar: FRASES.no_configurado
  };
  // r = lo que contestó la función: «apagado» trae la clave del motivo y «no_configurado» dice qué motor
  function frase(cod, r) {
    if (cod === 'apagado') return T(MOTIVOS[r && r.motivo_clave] || FRASES.apagado);
    if (cod === 'no_configurado' && r && r.motor === 'deepl') return T(DEEPL_NO);
    return T(FRASES[cod] || 'No ha salido bien. No se ha cambiado nada.');
  }
  // importes en dólares con el formateador único de la suite (dinero.js): «0,35 USD»
  function usd(n) {
    var x = Number(n);
    if (n === null || n === undefined || !isFinite(x)) return '—';
    return typeof window.lwFormatoImporte === 'function' ? window.lwFormatoImporte(x, 'USD') : x.toFixed(2) + ' USD';
  }

  /* ── estado del asistente para la empresa abierta ─────────────────────────────────────────────────────────────────────────── */
  function cargaEstado() {
    if (!E.empresa) return Promise.resolve();
    var emp = E.empresa; IA.empresa = emp; IA.estado = null;
    return API.rpc('editor_ia_estado', { p_empresa: emp }).then(function (r) {
      if (IA.empresa !== emp) return;
      IA.estado = r.error || !r.data ? { error: true } : r.data;
    });
  }
  // Tras cada llamada (buena o rechazada por tope) se vuelve a leer el gasto: el que devuelve la función es el de la RESERVA (peor caso),
  // no el real del cierre. Sin poner el estado a null mientras llega: la caja abierta sigue en pantalla. Si no se puede leer, se dice.
  function refresca() {
    if (!E.empresa || !IA.estado || IA.estado.error) return Promise.resolve();
    var emp = E.empresa;
    return API.rpc('editor_ia_estado', { p_empresa: emp }).then(function (r) {
      if (IA.empresa !== emp || !IA.estado) return;
      if (r.error || !r.data) IA.estado.desfasado = true; else IA.estado = r.data;
      pintaSaldos();
    });
  }
  var encendido = function () { return !!(IA.estado && IA.estado.encendido === true); };
  var lleno = function () { return !!(IA.estado && IA.estado.lleno === true); };
  // lo que como mucho se le FACTURA a la empresa por llamada (coste × (1 + margen), redondeado hacia arriba en la base); DeepL, por párrafo
  function pm() { return (IA.estado && IA.estado.precio_max) || {}; }
  // la misma cuenta que hace la reserva (editor_ia_estado.puede): un botón que la base va a rechazar no se ofrece
  function puede(accion) { return !!(IA.estado && IA.estado.puede && IA.estado.puede[accion] === true); }
  function lineaSaldo() {
    var s = IA.estado || {};
    if (!encendido()) return T('Asistente de redacción: ') + frase('apagado', s);
    var t = T('Este mes: %f facturados; usado el %p % del tope de tu empresa.', { f: usd(s.facturado_usd), p: s.pct });
    if (s.lleno) t += ' ' + frase(s.lleno_por === 'instancia' ? 'tope_global' : 'tope_empresa');
    else if (s.aviso) t += ' ' + T('Queda poco: ya se ha gastado el %p % del tope.', { p: s.pct });
    if (s.desfasado) t += ' ' + T('(sin actualizar: no se ha podido leer el gasto)');
    return t;
  }
  // cada línea de saldo de la pantalla lleva data-tc-ia-saldo; al volver a leer el gasto se repintan todas
  function saldo(extra) {
    var p = el('p', 'tc-peq', ''); p.setAttribute('data-tc-ia-saldo', extra || '');
    pintaSaldo(p); return p;
  }
  function pintaSaldo(p) {
    var s = IA.estado || {}, extra = p.getAttribute('data-tc-ia-saldo');
    p.className = 'tc-peq' + (s.lleno || !encendido() ? ' tc-mal' : s.aviso ? ' tc-ia-saldo-aviso' : '');
    p.textContent = lineaSaldo() + (encendido() && !s.lleno && extra === 'propone' ? ' ' + T('Cada propuesta: como mucho %z.', { z: usd(pm().propone) }) : '');
  }
  function pintaSaldos() {
    var raiz = $('tc-trozos'); if (!raiz) return;
    [].forEach.call(raiz.querySelectorAll('[data-tc-ia-saldo]'), pintaSaldo);
    [].forEach.call(raiz.querySelectorAll('[data-tc-ia-pide]'), function (b) { b.disabled = IA.ocupado || lleno() || !encendido(); });
    [].forEach.call(raiz.querySelectorAll('[data-tc-ia-motor]'), function (b) {
      var mo = b.getAttribute('data-tc-ia-motor');
      b.disabled = lleno() || !encendido() || (mo === 'deepl' ? IA.estado.deepl !== true || !puede('traduce_deepl') : !puede('traduce_ia'));
    });
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
            return { codigo: cod, motivo_clave: d && typeof d.motivo_clave === 'string' ? d.motivo_clave : null, motor: d && d.motor === 'deepl' ? 'deepl' : null };
          });
        }, function () { return { codigo: 'modelo_no_disponible' }; });
    }, function () { return { codigo: 'sin_sesion' }; });
  }
  function confirmaGasto(titulo, texto) {
    if (typeof window.lwConfirmar !== 'function') { window.alert(T('El diálogo aún no ha cargado — prueba de nuevo en un segundo.')); return Promise.resolve(false); }   /* falla cerrado: sin diálogo no hay «sí» */
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
    if (!encendido()) { caja.appendChild(saldo()); return; }                 // el motivo de la base, tal cual (textContent)
    if (p.sens) { caja.appendChild(el('p', 'tc-peq', frase('parte_sensible'))); return; }
    if (lleno()) { caja.appendChild(saldo()); return; }                      // tope del mes alcanzado: ni caja para pedir
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
    var coste = saldo('propone');
    var res = el('div', 'tc-ia-res'); res.setAttribute('aria-live', 'polite');
    caja.appendChild(lab); caja.appendChild(fila); caja.appendChild(coste); caja.appendChild(res);

    function pide() {
      var instr = inp.value.trim();
      if (!instr || IA.ocupado) { if (!instr) muestra(frase('instruccion_requerida'), true); return; }
      if (!encendido() || lleno()) { muestra(lineaSaldo(), true); return; }
      var paso = IA.confirmado ? Promise.resolve(true)
        : confirmaGasto(T('El asistente tiene coste'), T('Cada propuesta cuesta como mucho %z y cuenta para el tope de este mes de tu empresa, también si la descartas. El texto de este párrafo y tu instrucción se envían al proveedor de IA; los datos de los clientes no salen nunca.', { z: usd(pm().propone) }));
      paso.then(function (ok) {
        if (!ok) return;
        IA.confirmado = true; IA.ocupado = true; b.disabled = true; muestra(T('Pidiendo la propuesta…'));
        llama({ accion: 'propone', empresa: E.empresa, slug: E.slug, variante: E.variante, hash: E.ed && E.ed.hash, bloque: p.bloque, lang: E.lang === 'general' ? null : E.lang, instruccion: instr })
          .then(function (r) {
            IA.ocupado = false; b.disabled = lleno();
            refresca();                                                      // el gasto real tras el cierre (y «lleno», que la función no dice)
            if (!r.d) { muestra(frase(r.codigo, r), true); return; }
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
  // Lo que como mucho se FACTURA por una traducción: con IA, una llamada por cláusula; con DeepL, por párrafo × párrafos.
  // DeepL sin tarifa en Ajustes = «no configurado» (hoy no hay cuenta): botón visible pero apagado.
  function maxTraduce(motor, n) { var c = pm(); return motor === 'ia' ? c.traduce_ia : (c.traduce_deepl == null ? null : n * c.traduce_deepl); }
  function pintaTraducir(lang) {
    var conDeepl = IA.estado.deepl === true;
    [].forEach.call($('tc-trozos').querySelectorAll('.tc-sec[data-tc-sec]'), function (caja) {
      var sec = Number(caja.getAttribute('data-tc-sec'));
      var pars = (E.pars || []).filter(function (p) { return p.sec === sec && p.editable; });
      if (!pars.length || pars.some(function (p) { return p.sens; })) return;      // con partes sensibles, a mano
      var nEs = {}; E.trozos.forEach(function (t) { if (t.sec === sec && t.lang === 'es' && t.editable) nEs[t.bloque] = 1; });
      var n = Object.keys(nEs).length; if (!n) return;
      var f = el('div', 'tc-ia-traduce'); f.setAttribute('data-tc-ia-traduce', String(sec));
      f.appendChild(el('span', 'tc-peq', T('Traducir esta cláusula del español:')));
      [['ia', T('Con IA (como mucho %z)', { z: usd(maxTraduce('ia', n)) }), 'tc-btn'],          // la IA, por defecto: primero y destacada
       ['deepl', conDeepl ? T('Con DeepL (como mucho %z)', { z: usd(maxTraduce('deepl', n)) }) : T('Con DeepL (no configurado)'), null]].forEach(function (m) {
        var b = boton(m[1], { 'data-tc-ia-motor': m[0] }, m[2]);
        if (m[0] === 'deepl' && !conDeepl) { b.disabled = true; b.title = T(DEEPL_NO); }
        else if (lleno() || !puede(m[0] === 'ia' ? 'traduce_ia' : 'traduce_deepl')) b.disabled = true;
        b.addEventListener('click', function (e) { e.stopPropagation(); traduce(sec, m[0], n, f); });
        f.appendChild(b);
      });
      if (lleno()) f.appendChild(saldo());
      caja.insertBefore(f, caja.firstChild);
    });
  }
  function traduce(sec, motor, n, f) {
    if (IA.ocupado) return;
    if (motor === 'deepl' && IA.estado.deepl !== true) return;                 // apagado en pantalla; la función lo rechazaría igual (no_configurado)
    if (lleno()) return;
    // se traduce el español GUARDADO (la función lo lee de la base): con cambios sin guardar en el español de esta cláusula, el
    // inglés o el indonesio saldrían de un texto que ya no es el de pantalla
    if (E.trozos.some(function (t) { return t.sec === sec && t.lang === 'es' && Object.prototype.hasOwnProperty.call(E.cambios, t.i); })) {
      var av = f.querySelector('[data-tc-ia-aviso]') || f.appendChild(el('p', 'tc-peq tc-mal')); av.setAttribute('data-tc-ia-aviso', '1');
      av.textContent = T('El español de esta cláusula tiene cambios sin guardar: guárdalos antes de traducir.'); return;
    }
    var lang = E.lang;
    var hay = E.trozos.some(function (t) { return t.sec === sec && t.lang === lang && Object.prototype.hasOwnProperty.call(E.cambios, t.i); });
    confirmaGasto(T('Traducir «%s»', { s: API.tituloSec(sec) }),
      T('Cuesta como mucho %z y cuenta para el tope de este mes de tu empresa. El texto en español de esta cláusula (%n párrafos) se envía al traductor; los datos de los clientes no salen nunca. Lo traducido queda marcado «sin revisar» hasta que lo revises.', { z: usd(maxTraduce(motor, n)), n: n })
      + (hay ? ' ' + T('Lo que has cambiado a mano en esta cláusula en este idioma se sustituye.') : '')).then(function (ok) {
      if (!ok) return;
      IA.ocupado = true;
      var aviso = el('p', 'tc-peq', T('Traduciendo…')); f.appendChild(aviso);
      llama({ accion: 'traduce', motor: motor, destino: lang, empresa: E.empresa, slug: E.slug, variante: E.variante, hash: E.ed && E.ed.hash, sec: sec }).then(function (r) {
        IA.ocupado = false;
        refresca();                                                            // el gasto real tras el cierre (y «lleno»)
        if (!r.d) { aviso.textContent = frase(r.codigo, r); aviso.className = 'tc-peq tc-mal'; return; }
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

  /* ── puesta en marcha ─────────────────────────────────────────────────────────────────────────────────────────────────────── */
  document.addEventListener('lw-tc-listo', function () { cargaEstado(); });
  document.addEventListener('lw-tc-empresa', function () { IA.pendientes = {}; IA.marcasDe = null; IA.confirmado = false; cargaEstado(); });
  document.addEventListener('lw-tc-par-abierto', alAbrirParrafo);
  document.addEventListener('lw-tc-pintado', alPintar);
  document.addEventListener('lw-tc-guardado', alGuardar);
})();
