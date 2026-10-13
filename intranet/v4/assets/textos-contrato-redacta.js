/* textos-contrato-redacta.js — «Descríbelo en una frase (asistente)», en la pestaña CONTRATO NUEVO de «Textos de contrato», 13-oct-2026.
   Encargo agencia encargos/20261008_lawang_editor_textos_contrato.md, E10 (owner 13-oct: la persona describe el contrato en una frase y la IA
   le deja un contrato propio en BORRADOR, con sus campos y cláusulas en español, inglés e indonesio; lo ve entero antes de crearlo; nada se activa solo).
   Revisión previa 13-oct (Seguridad + Legal). Lo que manda está en el servidor, no aquí:
     edge editor-ia, accion «redacta»          la frase → nombre, campos y cláusulas en español (aparta del tope el peor caso de las TRES llamadas)
     edge editor-ia, accion «redacta_traduce»  ese español → inglés, y otra llamada → indonesio (solo el español que apuntó la primera: huella)
     editor_ia_estado                           encendido o por qué no, el gasto contra el tope y el PEOR caso de las tres llamadas (se enseña antes)
     plantilla_contrato_crea_desde_asistente    crea el contrato en borrador: vuelve a comprobar las tres huellas, todo lo que llega, el aviso aceptado
                                                y las partes sensibles; el nombre lleva « (IA)» y nunca pisa un contrato existente
   Construido APAGADO como el resto del asistente: mientras la base diga que no está encendido, aquí solo sale una línea con el MOTIVO.
   Lo que se enseña viene del modelo: createElement/textContent siempre; el único HTML es el cuerpo del diálogo, escapado.
   La vista previa NO se edita (la base compara lo que llega con lo que redactó el asistente): se edita en el editor, ya creado. El nombre sí.
   Enganche por data-tc-rd-* e ids, nunca por rótulo. */
(function () {
  'use strict';

  var TC = window.LW_TEXTOS, API = window.LW_TC;
  if (!TC || !API) { console.error('[textos-contrato-redacta] falta textos-contrato-nucleo.js o textos-contrato.js'); return; }
  var T = function (s, h) { return window.lwT ? window.lwT(s, h) : String(s).replace(/%(\w+)/g, function (m, k) { return h && k in h ? h[k] : m; }); };
  var $ = function (id) { return document.getElementById(id); };
  var el = API.el, boton = API.boton, E = API.E;
  var LANGS = ['es', 'en', 'id'];

  var R = { estado: null, empresa: null, ocupado: false, frase: '', es: null, uso: null, tr: {}, trErr: {}, trVa: {}, nombre: '', acepta: false, creando: false, err: null };

  // lo que devuelve la función y una persona puede provocar desde esta caja, en llano
  var FRASES = {
    frase_requerida: 'Describe el contrato en una frase.',
    frase_larga: 'Escribe la descripción en 1000 letras como mucho.',
    dato_real: 'Tu frase lleva datos que no se envían al asistente (correos, teléfonos, números de identidad, importes o enlaces). Describe el tipo de contrato y deja los importes como campo.',
    demasiado_largo: 'La descripción es demasiado larga para el asistente.',
    apagado: 'El asistente no está encendido para esta empresa.',
    tope_minuto: 'Demasiadas consultas seguidas: espera un minuto.',
    tope_empresa: 'Esta empresa llegó a su tope de este mes; el estudio puede subirlo.',
    tope_global: 'El asistente ha llegado al tope de gasto de este mes de toda la intranet. Avisa al estudio.',
    no_configurado: 'El asistente no está configurado todavía. Avisa al estudio.',
    propuesta_cambiada: 'El borrador ha cambiado desde que lo redactó el asistente. Vuelve a pedirlo.',
    redaccion_caducada: 'Este borrador ya no se puede usar: tiene más de 2 horas o ya se creó un contrato con él. Vuelve a pedirlo.',
    ya_traducido: 'Esa traducción ya está hecha o en curso. Espera un momento.',
    intentos: 'Demasiados intentos con esta traducción: vuelve a pedir el borrador entero.',
    propuesta_no_valida: 'El asistente ha devuelto algo que no se puede usar. No se te cobra: prueba a describirlo de otra forma.',
    modelo_no_disponible: 'El asistente no ha contestado. No se te cobra: prueba en un momento.',
    no_autorizado: 'Tu usuario no puede usar el asistente: lo usa la administración de la empresa.',
    sin_sesion: 'Tu sesión ha caducado. Vuelve a entrar; lo que has escrito sigue en pantalla.',
    sesion_invalida: 'Tu sesión ha caducado. Vuelve a entrar; lo que has escrito sigue en pantalla.'
  };
  // propuesta_no_valida trae la categoría de lo que el asistente no redacta: se dice cuál, para que la persona sepa qué quitar de la frase
  var CATEGORIAS = {
    tenencia: 'derechos sobre el terreno o poderes', ley_foro: 'ley aplicable, arbitraje o tribunales (los pone el contrato, fijos)',
    cita_norma: 'citas de leyes', prevalece: 'qué idioma prevalece (lo pone el contrato, fijo)', abusiva: 'cláusulas abusivas',
    rentabilidad: 'rentabilidades garantizadas', escrow: 'depósitos en garantía', impuestos: 'impuestos (van como campo, no como texto)',
    partes_firmas: 'partes o firmas (las pone el contrato, fijas)'
  };
  // lo que contesta la base al crear (hint)
  var FRASES_CREA = {
    aviso: 'Lee y acepta el aviso antes de crear el contrato.',
    origen: 'Este borrador ya no se puede usar. Vuelve a pedirlo.',
    usada: 'Con este borrador ya se creó un contrato.',
    caducada: 'El borrador tiene más de 2 horas: vuelve a pedirlo.',
    traduccion: 'Falta la traducción a inglés o indonesio.',
    forma: 'El borrador no es válido. Vuelve a pedirlo.',
    huella: 'El borrador ha cambiado desde que lo redactó el asistente. Vuelve a pedirlo.'
  };
  function frase(cod, r) {
    if (cod === 'apagado') {
      var m = { suspendido: 'Los servicios de pago de AxisWorks están suspendidos para esta empresa. Habla con el estudio.', sin_configurar: FRASES.no_configurado };
      return T(m[r && r.motivo_clave] || FRASES.apagado);
    }
    if (cod === 'propuesta_no_valida' && r && CATEGORIAS[r.categoria]) return T('El asistente ha escrito algo que no redacta: %c. No se te cobra: prueba a describirlo de otra forma.', { c: T(CATEGORIAS[r.categoria]) });
    return T(FRASES[cod] || 'No ha salido bien. No se ha cambiado nada.');
  }
  function usd(n) {
    var x = Number(n);
    if (n === null || n === undefined || !isFinite(x)) return '—';
    return typeof window.lwFormatoImporte === 'function' ? window.lwFormatoImporte(x, 'USD') : x.toFixed(2) + ' USD';
  }
  var encendido = function () { return !!(R.estado && R.estado.encendido === true); };
  var puede = function () { return !!(R.estado && R.estado.puede && R.estado.puede.redacta_completo === true); };
  function nombreEmpresa() { return ((E.empresas || []).filter(function (x) { return x.clave === E.empresa; })[0] || { nombre: E.empresa }).nombre; }

  /* ── estado y llamada a la edge (con la sesión de la persona) ─────────────────────────────────────────────────────────────── */
  function cargaEstado() {
    if (!E.empresa) return;
    var emp = E.empresa; R.empresa = emp;
    API.rpc('editor_ia_estado', { p_empresa: emp }).then(function (r) {
      if (R.empresa !== emp) return;
      R.estado = r.error || !r.data ? { error: true } : r.data;
      pinta();
    });
  }
  function llama(cuerpo) {
    return E.sb.auth.getSession().then(function (r) {
      var token = r && r.data && r.data.session && r.data.session.access_token;
      if (!token) return { codigo: 'sin_sesion' };
      var url; try { url = window.lwEdge('editor-ia'); } catch (_) { return { codigo: 'no_configurado' }; }
      return fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token, apikey: window.LW_SB_KEY }, body: JSON.stringify(cuerpo) })
        .then(function (resp) {
          return resp.text().then(function (t) {
            var d = null; try { d = JSON.parse(t); } catch (_) { d = null; }
            if (resp.ok && d && (d.propuesta || d.clausulas)) return { d: d };
            var cod = d && typeof d.error === 'string' && /^[a-z_]{3,40}$/.test(d.error) ? d.error : (resp.status === 404 ? 'no_configurado' : 'otro');
            return { codigo: cod, motivo_clave: d && typeof d.motivo_clave === 'string' ? d.motivo_clave : null, categoria: d && typeof d.categoria === 'string' ? d.categoria : null };
          });
        }, function () { return { codigo: 'modelo_no_disponible' }; });
    }, function () { return { codigo: 'sin_sesion' }; });
  }
  function confirma(titulo, texto, botonTxt) {
    if (typeof window.lwConfirmar !== 'function') return Promise.resolve(true);
    return window.lwConfirmar({ titulo: titulo, cuerpo: '<p>' + TC.esc(texto) + '</p>', confirmar: botonTxt });
  }

  /* ── pedir: la frase → español → inglés e indonesio a la vez ──────────────────────────────────────────────────────────────── */
  function pide() {
    var f = R.frase.trim();
    if (R.ocupado) return;
    if (!f) { R.err = frase('frase_requerida'); return pinta(); }
    if (!encendido() || !puede()) return;
    confirma(T('Redactar el contrato con el asistente'),
      T('Redactar el borrador y traducirlo a inglés e indonesio cuesta como mucho %z y cuenta para el tope de este mes de tu empresa, también si no lo usas.', { z: usd(R.estado.precio_max && R.estado.precio_max.redacta_completo) }),
      T('Sí, sigue')).then(function (ok) {
      if (!ok) return;
      R.ocupado = true; R.err = null; R.es = null; R.uso = null; R.tr = {}; R.trErr = {}; R.trVa = {}; R.acepta = false; pinta();
      llama({ accion: 'redacta', empresa: E.empresa, frase: f }).then(function (r) {
        R.ocupado = false;
        if (!r.d) { R.err = frase(r.codigo, r); refresca(); return pinta(); }
        R.es = r.d.propuesta; R.uso = r.d.uso; R.nombre = r.d.propuesta.nombre; R.empresaDe = E.empresa;
        pinta();
        traduce('en'); traduce('id');
      });
    });
  }
  function traduce(lg) {
    if (!R.es || R.trVa[lg]) return;
    R.trVa[lg] = true; delete R.trErr[lg]; pinta();
    var uso = R.uso;
    llama({ accion: 'redacta_traduce', empresa: R.empresaDe, uso: uso, destino: lg, propuesta: R.es }).then(function (r) {
      if (R.uso !== uso) return;                                           // se pidió otro borrador mientras tanto
      R.trVa[lg] = false;
      if (r.d && Array.isArray(r.d.clausulas)) R.tr[lg] = r.d.clausulas; else R.trErr[lg] = frase(r.codigo, r);
      refresca(); pinta();
    });
  }
  function refresca() {
    if (!E.empresa) return;
    var emp = E.empresa;
    API.rpc('editor_ia_estado', { p_empresa: emp }).then(function (r) { if (R.empresa === emp && !r.error && r.data) { R.estado = r.data; pinta(); } });
  }
  function listo() { return !!(R.es && R.tr.en && R.tr.id); }
  // el borrador entero, como lo compara la base: el español del paso (a) y lo traducido en (b), cláusula a cláusula
  function propuestaEntera() {
    return {
      nombre: R.nombre.trim(),
      campos: R.es.campos,
      clausulas: R.es.clausulas.map(function (c, k) {
        return {
          titulo: { es: c.titulo, en: R.tr.en[k].titulo, id: R.tr.id[k].titulo },
          parrafos: c.parrafos.map(function (p, m) { return { es: p, en: R.tr.en[k].parrafos[m], id: R.tr.id[k].parrafos[m] }; })
        };
      })
    };
  }

  /* ── crear: una sola llamada a la base, que lo vuelve a comprobar todo ────────────────────────────────────────────────────── */
  function crea(confirmaSensibles) {
    if (!listo() || !R.acepta || R.creando) return;
    var nom = R.nombre.trim();
    if (nom.length < 3 || nom.length > 75 || /[<>{}&"]/.test(nom)) { R.err = T('Pon un nombre de 3 a 75 letras, sin los signos < > { } & ni comillas dobles.'); return pinta(); }
    R.creando = true; R.err = null; pinta();
    API.rpc('plantilla_contrato_crea_desde_asistente', { p_empresa: R.empresaDe, p_uso: R.uso, p_propuesta: propuestaEntera(), p_acepta_aviso: true, p_confirma_sensibles: confirmaSensibles === true })
      .then(function (r) {
        R.creando = false;
        if (r.error || !r.data) {
          var m = API.msg(r.error || T('la base no ha devuelto el contrato')), h = r.error && r.error.hint;
          if (!confirmaSensibles && /partes sensibles/i.test(m)) {
            pinta();
            return confirma(T('El borrador toca partes sensibles'), m, T('Sí, créalo con el aviso')).then(function (ok) { if (ok) crea(true); });
          }
          R.err = (FRASES_CREA[h] ? T(FRASES_CREA[h]) : T('La base no ha aceptado el contrato.')) + ' ' + T('Mensaje de la base: ') + m;
          return pinta();
        }
        var d = r.data, emp = R.empresaDe;
        E.nombres[d.slug] = d.nombre;
        vacia();
        API.cargaLista().then(function () {
          if (E.empresa !== emp) return;
          if (typeof window.toast === 'function') window.toast(T('Contrato «%n» creado en borrador. Revísalo antes de activarlo.', { n: d.nombre }));
          document.dispatchEvent(new CustomEvent('lw-tc-ir', { detail: { tab: 'textos' } }));
          API.abreEditor(d.slug, 'estandar');
        });
      });
  }
  function vacia() { R.ocupado = false; R.frase = ''; R.es = null; R.uso = null; R.tr = {}; R.trErr = {}; R.trVa = {}; R.nombre = ''; R.acepta = false; R.creando = false; R.err = null; pinta(); }

  /* ── pintado ──────────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function llano(txt, lg) {                                                   // {{cx_…}} → «Etiqueta» del campo en ese idioma
    return String(txt).replace(/\{\{(cx_[a-z0-9_]+)\}\}/g, function (m, k) {
      var c = (R.es.campos || []).filter(function (x) { return x.clave === k; })[0];
      return '«' + (c ? c['etiqueta_' + lg] || c.etiqueta_es : k) + '»';
    });
  }
  var TIPOS = { texto: 'texto', numero: 'número', fecha: 'fecha', importe: 'importe', lista: 'lista', si_no: 'sí / no' };
  function pinta() {
    var sec = $('tc-rd'), caja = $('tc-rd-cuerpo'); if (!sec || !caja) return;
    if (!R.estado || R.estado.error) { sec.hidden = true; return; }                // la base no tiene el asistente (o no contestó): 0 px
    sec.hidden = false; caja.textContent = '';
    if (!encendido()) { caja.appendChild(el('p', 'tc-peq tc-mal', T('Asistente de redacción: ') + frase('apagado', R.estado))); return; }
    caja.appendChild(el('p', 'tc-nota', T('Tu frase se envía a un proveedor externo de IA (Anthropic) para redactar el borrador. No escribas nombres, direcciones, números de pasaporte ni otros datos de clientes: describe el tipo de contrato y deja los importes como campo.')));
    var lab = el('label', null, T('Describe el contrato en una frase. Es una plantilla: sin nombres ni datos de clientes.')); lab.setAttribute('for', 'tc-rd-frase');
    var ta = el('textarea', 'tc-rd-frase'); ta.id = 'tc-rd-frase'; ta.rows = 3; ta.maxLength = 1000; ta.value = R.frase; ta.disabled = R.ocupado;
    ta.setAttribute('placeholder', T('p. ej. compromiso de compra de un pack de mobiliario: precio fijo, pago antes de una fecha límite, garantía del fabricante'));
    ta.setAttribute('data-tc-rd', 'frase');
    var campo = el('div', 'tc-campo'); campo.appendChild(lab); campo.appendChild(ta); caja.appendChild(campo);
    var s = R.estado;
    var linea = T('Este mes: %f facturados; usado el %p % del tope de tu empresa.', { f: usd(s.facturado_usd), p: s.pct });
    caja.appendChild(el('p', 'tc-peq' + (puede() ? '' : ' tc-mal'), (puede() ? T('Redactar y traducir: como mucho %z.', { z: usd(s.precio_max && s.precio_max.redacta_completo) }) + ' ' : frase(s.lleno_por === 'instancia' ? 'tope_global' : 'tope_empresa') + ' ') + linea));
    var fila = el('div', 'tc-barra-fila'), b = boton(R.ocupado ? T('Redactando…') : T('Redactar borrador'), { 'data-tc-rd-pide': '1' }, 'tc-btn');
    b.disabled = R.ocupado || !puede(); fila.appendChild(b);
    if (R.es) fila.appendChild(boton(T('Descartar el borrador'), { 'data-tc-rd-descarta': '1' }));
    caja.appendChild(fila);
    if (R.err) caja.appendChild(el('p', 'tc-nota tc-nota-mal', R.err));
    if (R.es) pintaPrevia(caja);
  }
  function pintaPrevia(caja) {
    var p = el('div', 'tc-rd-previa'); p.setAttribute('aria-live', 'polite');
    p.appendChild(el('p', 'tc-ia-et', T('Borrador del asistente (sin crear todavía)')));
    var ln = el('label', null, T('Nombre del contrato (se le añade « (IA)»)')); ln.setAttribute('for', 'tc-rd-nombre');
    var inp = el('input'); inp.type = 'text'; inp.id = 'tc-rd-nombre'; inp.maxLength = 75; inp.autocomplete = 'off'; inp.value = R.nombre; inp.setAttribute('data-tc-rd', 'nombre');
    var cn = el('div', 'tc-campo'); cn.appendChild(ln); cn.appendChild(inp); p.appendChild(cn);
    p.appendChild(el('p', 'tc-ia-et', T('Campos que pedirá el contrato')));
    if (!R.es.campos.length) p.appendChild(el('p', 'tc-peq', T('ninguno')));
    R.es.campos.forEach(function (c) {
      var t = c.etiqueta_es + ' · ' + c.etiqueta_en + ' · ' + c.etiqueta_id + ' (' + T(TIPOS[c.tipo] || c.tipo) + (c.tipo === 'lista' ? ': ' + c.opciones.join(', ') : '') + ')';
      p.appendChild(el('p', 'tc-peq', t));
    });
    p.appendChild(el('p', 'tc-peq', T('Las partes, la ley aplicable, el arbitraje, el idioma que prevalece y las firmas las pone el contrato, fijas: el asistente no las escribe.')));
    R.es.clausulas.forEach(function (c, k) {
      var bl = el('div', 'tc-rd-clausula');
      LANGS.forEach(function (lg) {
        var cl = lg === 'es' ? c : R.tr[lg] && R.tr[lg][k];
        if (!cl) return;
        bl.appendChild(el('p', 'tc-fuerte', (k + 1) + '. ' + cl.titulo + ' [' + lg.toUpperCase() + ']'));
        cl.parrafos.forEach(function (x) { bl.appendChild(el('p', 'tc-peq', llano(x, lg))); });
      });
      p.appendChild(bl);
    });
    ['en', 'id'].forEach(function (lg) {
      var nom = lg === 'en' ? T('inglés') : T('indonesio');
      if (R.trVa[lg]) p.appendChild(el('p', 'tc-peq', T('Traduciendo al %l…', { l: nom })));
      else if (R.trErr[lg]) {
        var f = el('div', 'tc-barra-fila');
        f.appendChild(el('span', 'tc-peq tc-mal', T('No ha salido la traducción al %l: ', { l: nom }) + R.trErr[lg]));
        f.appendChild(boton(T('Volver a traducir'), { 'data-tc-rd-reintenta': lg }));
        p.appendChild(f);
      }
    });
    if (listo()) {
      var av = el('div', 'tc-nota');
      av.appendChild(el('p', null, T('Este texto lo ha redactado un asistente de IA y el estudio no lo ha revisado. Al activarlo, responde de él %e. La versión en indonesio es la que prevalece y es una traducción automática: antes de usarlo con un cliente, consulte a un abogado o notario que revise la versión en indonesio.', { e: nombreEmpresa() })));
      var lc = el('label', 'tc-check'), ch = el('input'); ch.type = 'checkbox'; ch.checked = R.acepta; ch.setAttribute('data-tc-rd', 'acepta');
      lc.appendChild(ch); lc.appendChild(el('span', null, T('He leído el aviso'))); av.appendChild(lc);
      p.appendChild(av);
      var fc = el('div', 'tc-barra-fila'), bc = boton(R.creando ? T('Creando el contrato…') : T('Crear el contrato en borrador'), { 'data-tc-rd-crea': '1' }, 'tc-btn');
      bc.disabled = !R.acepta || R.creando; fc.appendChild(bc); p.appendChild(fc);
      p.appendChild(el('p', 'tc-peq', T('Se crea en borrador, sin activar. Después lo cambias en el editor como cualquier texto; activarlo lo hace el super administrador de la empresa.')));
    }
    caja.appendChild(p);
  }

  /* ── cableado ─────────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function cablea() {
    var caja = $('tc-rd-cuerpo'); if (!caja) return;
    caja.addEventListener('input', function (ev) {
      var k = ev.target.getAttribute('data-tc-rd');
      if (k === 'frase') R.frase = ev.target.value;
      else if (k === 'nombre') R.nombre = ev.target.value;
    });
    caja.addEventListener('change', function (ev) {
      if (ev.target.getAttribute('data-tc-rd') === 'acepta') { R.acepta = ev.target.checked; pinta(); }
    });
    caja.addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-tc-rd-pide],[data-tc-rd-descarta],[data-tc-rd-reintenta],[data-tc-rd-crea]'); if (!b) return;
      ev.stopPropagation();
      if (b.hasAttribute('data-tc-rd-pide')) pide();
      else if (b.hasAttribute('data-tc-rd-descarta')) vacia();
      else if (b.hasAttribute('data-tc-rd-reintenta')) traduce(b.getAttribute('data-tc-rd-reintenta'));
      else crea(false);
    });
  }
  function inicia() {
    cablea();
    document.addEventListener('lw-tc-listo', cargaEstado);
    document.addEventListener('lw-tc-empresa', function () { R.estado = null; vacia(); cargaEstado(); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', inicia); else inicia();
})();
