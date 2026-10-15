/* notas-historial.js — el historial de notas, pieza común de la suite (15-oct-2026)
   ----------------------------------------------------------------------------
   QUÉ ES. Las notas de una ficha como historial: cada nota con su autor y su fecha, que pone el servidor; ninguna se
   edita; se RETIRA con motivo y su texto se borra de verdad (queda solo constancia de quién, cuándo y por qué: UU PDP,
   Legal). La usan dos fichas con el mismo comportamiento:
     · la del cliente (datos.js, /v4/compradores/): cliente_notas_datos / cliente_nota_agrega / cliente_nota_retira
       (supabase/migrations/20261015075011_cliente_notas.sql);
     · la de la parcela (ficha-parcela.js, /v4/proyectos/): unidad_notas_datos / unidad_nota_agrega / unidad_nota_retira
       (owner, 15-oct: «en proyectos, en detalle de parcela mete unas notas»).
   Antes vivía dentro de datos.js; una segunda copia para la parcela habría sido la deuda que suite_lawang.md prohíbe.

   QUIÉN DECIDE QUÉ. La pantalla no decide nada: quién lee, quién escribe y quién retira lo dice la base. Cada nota llega
   con `autor_nombre` y `puede_retirar` calculados en el servidor; el botón «Retirar» sale solo si `puede_retirar` es
   true, y si aun así el servidor lo rechaza, se dice. Por eso esta pieza no mira LW_V4, LW_ROL ni el correo de nadie.

   API. `LW_NOTAS.monta(contenedor, cfg) → { abre(id), cierra() }`. Una sola escucha delegada por contenedor; el id
   abierto vive en el controlador y cada `abre` es un TURNO: una respuesta de un turno viejo no pinta, no limpia el
   borrador y no repinta la lista de la ficha nueva. Lo escrito y no enviado se guarda por id, en memoria: cerrar y
   reabrir la misma ficha lo devuelve; otra ficha nunca lo ve. cfg:
     sb        el cliente de Supabase, una promesa de él o una función que lo devuelve (LW_AUTH es asíncrono);
     rpc       { datos, agrega, retira }: nombres de las funciones de la base;
     argId     el nombre del argumento del id ('p_client' | 'p_unidad');
     motivos   [[clave, rótulo en español], …] para retirar (las claves las valida la base);
     origenes  { origen: rótulo en español } (la nota normal, origen 'nota', no lleva rótulo);
     aviso     texto fijo bajo la caja (no placeholder: se queda a la vista mientras se escribe);
     clases    { in, btn1, btn2 }: las clases de campo y botones de la pantalla que la monta;
     alEstado  función opcional que recibe 'cargando' | 'lista' | 'vacio' | 'caida' | 'sin_permiso'.
   Los rótulos se pasan en español y aquí se traducen con lwT (i18n.js): el diccionario los tiene como clave.

   TRES ESTADOS QUE NO SE PARECEN. «No tienes permiso» (42501), «no se han podido cargar» (caída, con Reintentar) y
   «Sin notas todavía.» se ven distintos: una alarma rota no puede leerse como «todo tranquilo». Toda llamada tiene su
   rama de error (también la promesa rechazada): nunca se queda un «Cargando…» para siempre.

   ENVÍO QUE SE QUEDA SIN RESPUESTA. Solo un error CON código de la base (o de PostgREST) es «no se ha guardado»: sin
   código (red caída, respuesta perdida) no se sabe, se dice así, se recarga la lista y se conserva el borrador para
   que quien escribe mire antes de repetir.

   TEXTO DE UNA NOTA: siempre por esc() y con white-space:pre-wrap; nunca como HTML ni convertido en enlace (Seguridad).

   PRUEBAS: contracts/assets/notas_historial.test.js (node, con un sb falso y un DOM mínimo). */
(function (root) {
  'use strict';

  function tx(s, h) {
    if (root && typeof root.lwT === 'function') return root.lwT(s, h);
    var v = String(s); for (var k in h) if (Object.prototype.hasOwnProperty.call(h, k)) v = v.split('%' + k).join(h[k]);
    return v;
  }
  function esc(v) {
    return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function fechaHora(iso) {
    if (!iso) return '';
    var d = new Date(iso);
    if (isNaN(d.getTime())) return String(iso);
    var loc = root && typeof root.lwLocale === 'function' ? root.lwLocale() : 'es-ES';
    return d.toLocaleDateString(loc, { day: '2-digit', month: 'short', year: 'numeric' }) + ' · ' +
      d.toLocaleTimeString(loc, { hour: '2-digit', minute: '2-digit' });
  }
  /* El error ya traducido (lwErrorHumano de suite-comun.js), con la frase fija delante si la hay; sin él, el crudo. */
  function errTxt(e, fijo) {
    if (root && typeof root.lwErrorHumano === 'function') return root.lwErrorHumano(e, fijo);
    var crudo = (e && (e.message || e.code)) || '—';
    return fijo ? fijo + ': ' + crudo : crudo;
  }
  function sinPermiso(e) { return !!e && (e.code === '42501' || e.hint === 'sin_permiso'); }
  /* Un error con código lo ha dado la base o PostgREST: la operación NO se hizo. Sin código no se sabe. */
  function conCodigo(e) { return !!e && typeof e.code === 'string' && e.code !== ''; }
  /* `toast` y `toastMal` son `const` de suite-comun.js (ámbito global de los scripts, no `window`): se preguntan por el
     nombre. Sin ellos, el aviso va a la línea de estado de la propia caja. */
  function bien(m, linea) {
    if (typeof toast === 'function') toast(m);   // eslint-disable-line no-undef
    else if (linea) { linea.textContent = m; linea.setAttribute('role', 'status'); }
  }
  function mal(m, linea) {
    if (typeof toastMal === 'function') toastMal(m);   // eslint-disable-line no-undef
    else if (linea) { linea.textContent = m; linea.setAttribute('role', 'alert'); }
  }
  /* Una llamada → {data, error}, también si revienta (sin red, sin sesión, o lanza al llamar). */
  function lee(fn) {
    return new Promise(function (r) { r(fn()); }).then(function (r) { return { data: r ? r.data : null, error: r ? r.error : null }; },
      function (e) { return { data: null, error: e || { message: '—' } }; });
  }

  var GRIS = 'color:rgb(var(--tema-on-surface-variant))';
  var serie = 0;

  function monta(cont, cfg) {
    cfg = cfg || {};
    var C = cfg.clases || {}, rpc = cfg.rpc || {}, ORIGEN = cfg.origenes || {}, MOTIVOS = cfg.motivos || [];
    /* tok: turno de la ficha abierta (lo sube cada abre/cierra). lect: la última lectura pedida (Reintentar y la recarga
       tras añadir comparten turno: solo pinta la más reciente). borradores: lo escrito y no enviado, por id y en memoria
       (cerrar y volver a abrir la misma ficha no lo pierde; nunca pasa a otra). enVuelo: ids con un «Añadir» sin respuesta
       (reabrir esa ficha no vuelve a dejar el botón encendido: sería un doble envío). */
    var st = { id: null, tok: 0, lect: 0, borradores: {}, enVuelo: {} };
    var idAviso = 'lwn-aviso-' + (++serie);

    /* cfg.sb puede ser el cliente, una promesa de él o una función que devuelve cualquiera de los dos. Con el cliente a
       mano la llamada sale en el acto (el botón y la base ven el mismo orden de pulsaciones). */
    function llama(nombre, a) {
      var salio = false;
      return lee(function () {
        var s = typeof cfg.sb === 'function' ? cfg.sb() : cfg.sb;
        var pide = function (x) {
          if (!x || typeof x.rpc !== 'function') throw new Error(tx('Sin sesión'));
          salio = true;
          return x.rpc(nombre, a);
        };
        return s && typeof s.then === 'function' ? s.then(pide) : pide(s);
      }).then(function (r) { if (r.error && !salio) r.noSalio = true; return r; });   // no salió: seguro que no se hizo
    }
    function boton() { return cont.querySelector('[data-accion="nota-agrega"]'); }
    function guardaBorrador() { var ta = q('nota-texto'); if (st.id != null && ta) st.borradores[st.id] = ta.value; }
    function args(id, extra) { var a = {}; a[cfg.argId] = id; for (var k in extra) a[k] = extra[k]; return a; }
    function aviso(estado) { if (typeof cfg.alEstado === 'function') cfg.alEstado(estado); }
    function q(k) { return cont.querySelector('[data-lw="' + k + '"]'); }

    function htmlCaja() {
      return '<div style="margin-top:10px">' +
        '<textarea class="' + esc(C.in || '') + '" data-lw="nota-texto" rows="3" maxlength="4000" aria-label="' + esc(tx('Nueva nota')) + '"' +
        (cfg.aviso ? ' aria-describedby="' + idAviso + '"' : '') + ' style="width:100%;box-sizing:border-box;resize:vertical"></textarea>' +
        (cfg.aviso ? '<p id="' + idAviso + '" data-lw="nota-aviso" style="margin:4px 0 8px;font-size:11.5px;' + GRIS + '">' + esc(tx(cfg.aviso)) + '</p>'
          : '<div style="height:8px"></div>') +
        '<button type="button" class="' + esc(C.btn1 || '') + '" data-accion="nota-agrega">' + esc(tx('Añadir nota')) + '</button>' +
        '<p data-lw="nota-estado" style="margin:6px 0 0;font-size:11.5px"></p></div>';
    }
    function htmlNota(n) {
      /* `autor_email` y un `puede_retirar` ausente solo llegan de un cliente_notas_datos anterior a 20261015210000: con él
         se sigue viendo quién la escribió y se ofrece «Retirar» (el servidor decide y, si no deja, lo dice). */
      var quien = n.origen === 'antigua' ? '' : (n.autor_nombre || n.autor_email || (n.autor_id ? tx('alguien del equipo') : tx('sin autor')));
      var origen = n.origen && n.origen !== 'nota' && ORIGEN[n.origen] ? tx(ORIGEN[n.origen]) : '';
      var meta = [fechaHora(n.creado_en), quien, origen].filter(Boolean).join(' · ');
      return '<article data-lw="nota" data-nota="' + esc(String(n.id)) + '" style="padding:9px 0;border-bottom:1px solid rgb(var(--tema-outline-variant))">' +
        '<p style="margin:0;white-space:pre-wrap;overflow-wrap:anywhere">' + esc(n.texto) + '</p>' +
        '<p style="margin:4px 0 0;font-size:11.5px;' + GRIS + '">' + esc(meta) +
        (n.puede_retirar !== false ? ' · <button type="button" class="' + esc(C.btn2 || '') + '" data-accion="nota-retira">' + esc(tx('Retirar')) + '</button>' : '') +
        '</p></article>';
    }
    function gris(txt, lw) { return '<p data-lw="' + lw + '" style="margin:0;font-size:12.5px;' + GRIS + '">' + esc(txt) + '</p>'; }

    /* Solo la lista: la caja (y lo que haya escrito en ella) no se toca. */
    function pintaLista(r) {
      var l = q('notas-lista'), caja = q('notas-caja');
      if (!l) return;
      if (r.error && sinPermiso(r.error)) {
        l.innerHTML = gris(tx('No tienes permiso para ver las notas.'), 'notas-sin-permiso');
        if (caja) caja.hidden = true;
        return aviso('sin_permiso');
      }
      var d = r.data;
      if (r.error || !d || !Array.isArray(d.notas)) {
        var e = r.error || { message: tx('la respuesta no trae la lista de notas') };
        l.innerHTML = '<div data-lw="notas-caida" role="alert" style="display:flex;gap:10px;align-items:center;flex-wrap:wrap">' +
          '<p style="margin:0;font-size:12.5px;color:rgb(var(--tema-error))">' + esc(tx('No se han podido cargar las notas: %e', { e: errTxt(e) })) + '</p>' +
          '<button type="button" class="' + esc(C.btn2 || '') + '" data-accion="notas-reintenta">' + esc(tx('Reintentar')) + '</button></div>';
        var taC = q('nota-texto');
        if (caja && taC && taC.value.trim()) caja.hidden = false;   // lo escrito no se esconde: se puede enviar igual
        return aviso('caida');
      }
      if (caja) caja.hidden = false;
      if (!d.notas.length) { l.innerHTML = gris(tx('Sin notas todavía.'), 'notas-vacio'); return aviso('vacio'); }
      l.innerHTML = d.notas.map(htmlNota).join('') +
        (d.recortado ? '<p data-lw="notas-recortado" style="margin:8px 0 0;font-size:11.5px;' + GRIS + '">' + esc(tx('Se enseñan las 500 más recientes.')) + '</p>' : '');
      aviso('lista');
    }

    function carga() {
      var id = st.id, tok = st.tok, n = ++st.lect;
      return llama(rpc.datos, args(id))
        .then(function (r) { if (tok === st.tok && n === st.lect) pintaLista(r); });
    }

    function abre(id) {
      guardaBorrador();
      st.id = id;
      st.tok++;
      cont.innerHTML = '<div data-lw="notas-lista">' + gris(tx('Cargando las notas…'), 'notas-cargando') + '</div>' +
        '<div data-lw="notas-caja" hidden>' + htmlCaja() + '</div>';
      if (st.borradores[id]) q('nota-texto').value = st.borradores[id];
      if (st.enVuelo[id]) boton().disabled = true;
      aviso('cargando');
      return carga();
    }
    function cierra() { guardaBorrador(); st.id = null; st.tok++; cont.innerHTML = ''; }

    function agrega(b) {
      var ta = q('nota-texto'), linea = q('nota-estado');
      var t = String((ta && ta.value) || '').trim();
      if (!t) return mal(tx('Escribe la nota antes de añadirla.'), linea);
      var id = st.id;
      if (id == null || st.enVuelo[id]) return null;
      st.enVuelo[id] = true;
      b.disabled = true;
      return llama(rpc.agrega, args(id, { p_texto: t }))
        .then(function (r) {
          delete st.enVuelo[id];
          b.disabled = false;
          var mismo = id === st.id, bA = mismo ? boton() : null, lA = mismo ? q('nota-estado') : null;
          if (bA) bA.disabled = false;
          if (r.error && (conCodigo(r.error) || r.noSalio)) return mal(errTxt(r.error, tx('No se ha guardado la nota')), lA);
          if (r.error) {
            // sin respuesta: no se sabe si se guardó. Se conserva el borrador y se recarga la lista para mirarlo.
            mal(tx('No ha llegado la respuesta del servidor y no se sabe si la nota se ha guardado. Mira la lista antes de volver a añadirla.'), lA);
            return mismo ? carga() : null;
          }
          bien(tx('Nota añadida'), lA);
          // Lo enviado ya está guardado: se vacía donde siga (la caja de esta ficha o su borrador), si nadie lo ha cambiado.
          if (mismo) {
            var taA = q('nota-texto');
            if (taA && taA.value.trim() === t) taA.value = '';
            return carga();
          }
          if (String(st.borradores[id] || '').trim() === t) delete st.borradores[id];
          return null;
        });
    }
    function retira(b, art) {
      var linea = q('nota-estado');
      var motivo = (art.querySelector('[data-lw="nota-motivo"]') || {}).value || '';
      if (!motivo) return mal(tx('Elige por qué se retira.'), linea);
      var id = st.id, nota = Number(art.getAttribute('data-nota'));
      b.disabled = true;
      return llama(rpc.retira, { p_nota: nota, p_motivo: motivo })
        .then(function (r) {
          b.disabled = false;
          var mismo = id === st.id, lA = mismo ? q('nota-estado') : null;
          if (r.error && (conCodigo(r.error) || r.noSalio)) return mal(errTxt(r.error, tx('No se ha retirado la nota')), lA);
          if (r.error) mal(tx('No ha llegado la respuesta del servidor y no se sabe si la nota se ha retirado. Mira la lista.'), lA);
          else bien(tx('Nota retirada'), lA);
          return mismo ? carga() : null;
        });
    }

    /* Una sola escucha por contenedor: si alguien vuelve a montar en el mismo, la anterior se quita (dos escuchas = dos
       envíos por pulsación). */
    if (typeof cont.__lwNotasQuita === 'function') cont.__lwNotasQuita();
    var alPulsar = function (e) {
      var b = e.target && e.target.closest ? e.target.closest('[data-accion]') : null;
      if (!b || !cont.contains(b) || b.disabled) return;
      var acc = b.getAttribute('data-accion');
      var art = b.closest('[data-lw="nota"]');
      if (acc === 'nota-agrega') agrega(b);
      else if (acc === 'notas-reintenta') {
        var l = q('notas-lista');
        if (l) l.innerHTML = gris(tx('Cargando las notas…'), 'notas-cargando');
        aviso('cargando');
        carga();
      } else if (acc === 'nota-retira') {
        if (!art || art.querySelector('[data-lw="nota-retira-caja"]')) return;
        art.insertAdjacentHTML('beforeend', '<div data-lw="nota-retira-caja">' +
          '<div style="margin-top:8px;display:flex;gap:8px;flex-wrap:wrap;align-items:center">' +
          '<select class="' + esc(C.in || '') + '" data-lw="nota-motivo" aria-label="' + esc(tx('Por qué se retira')) + '" style="width:auto"><option value="">' + esc(tx('¿Por qué se retira?')) + '</option>' +
          MOTIVOS.map(function (m) { return '<option value="' + esc(m[0]) + '">' + esc(tx(m[1])) + '</option>'; }).join('') + '</select>' +
          '<button type="button" class="' + esc(C.btn1 || '') + '" data-accion="nota-retira-ok">' + esc(tx('Retirar nota')) + '</button>' +
          '<button type="button" class="' + esc(C.btn2 || '') + '" data-accion="nota-retira-no">' + esc(tx('Cancelar')) + '</button></div>' +
          '<p style="margin:6px 0 0;font-size:11.5px;' + GRIS + '">' + esc(tx('Al retirarla, su texto se borra y no se puede recuperar. Queda constancia de quién la retiró, cuándo y por qué.')) + '</p></div>');
      } else if (acc === 'nota-retira-no') {
        var cajaR = art && art.querySelector('[data-lw="nota-retira-caja"]');
        if (cajaR) cajaR.remove();
      } else if (acc === 'nota-retira-ok' && art) retira(b, art);
    };
    cont.addEventListener('click', alPulsar);
    cont.__lwNotasQuita = function () { cont.removeEventListener('click', alPulsar); };

    return { abre: abre, cierra: cierra };
  }

  var api = { monta: monta };
  if (root) root.LW_NOTAS = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : this);
