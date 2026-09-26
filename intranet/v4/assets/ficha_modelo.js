/* FICHA DEL MODELO, EDITABLE POR BLOQUES — /intranet/v4/modelos/ (23-sep-2026).

   Encargo del owner (diseño B del lienzo «Modelos v4 — propuestas de flujo»,
   aprobado tal cual): la ficha del cajón lateral enseña TODO lo del modelo y
   cada bloque tiene su propio «Editar» que guarda solo lo suyo. Sustituye al
   modal único «Editar datos» (~20 campos en una columna), que escondía precios
   por proyecto, techos, extras y obra detrás de un botón.

   Quién pinta qué: datos.js carga los datos (una sola tanda) y llama a
   `lwFichaModelo.pintar(modelo, ctx)`; este módulo pinta los bloques y pide
   sus escrituras al servidor (RPC con el permiso dentro, 27-sep-2026, LAW-336
   bloque 3; el precio va entero en modelo_precios_guarda). Las filas de «Unidades» (#d-proyectos, con su «Previsión del
   deck») y de «Documentos» (#d-docs, abrir el fichero) conservan los ganchos
   que editores.js delega en esos contenedores — no se reescriben aquí.

   Revisión previa #56 (Datos + Administración), plegada:
   - PRECIO BASE Y TECHOS VAN JUNTOS. `modelo_techos_opciones()` resuelve el
     techo de un proyecto como precio_techo + (precio_proyecto − base). Subir la
     base sin mover los techos ABARATA el techo precargado en los proyectos con
     precio propio (Administración, ROJO). Por eso, en un modelo con techos,
     cambiar la base mueve todos los techos (ahora y 2027) la misma cantidad, y
     el bloque lo enseña antes de guardar. La diferencia la calcula el
     SERVIDOR (base nueva − base de la fila bloqueada), no esta pantalla.
   - NULL en `modelos_villa.precio_construccion` = HEREDA la base (resolución
     única en contracts/assets/modelos_catalogo.js). Se distingue «hereda» de
     «fijado a mano, hoy igual a la base»: el segundo NO se mueve con la base.
     Normalizar uno en otro es una pregunta al owner, no algo que se hace solo.
   - Declarar un proyecto que ya tiene unidades del modelo crea la fila con
     NULL (misma forma que lwDeclaraModelosEnProyecto), salvo que la base sea
     NULL: entonces hereda NADA y se exige precio. El servidor da de alta la
     fila (nunca pisa una creada en otra pestaña: lo dice con su texto).
   - La moneda no se cambia si el modelo ya tiene filas que cuelgan de él
     (techos, extras, precios por proyecto, previsión del deck; lo decide la
     base, revisión #126): no se convierte nada, y un 48.000 EUR leído como IDR es un error
     de tres órdenes de magnitud.
   - `renders_pendientes` NO es «le faltan fotos»: en la web es lo que permite
     publicar la página de un modelo sin fotos (modelo/lib.php). Se rotula así.
   - La web cachea el catálogo 5 min (LW_CAT_TTL): tras guardar se dice.
   - Con el modelo publicado, la dirección web (slug) no se edita: rompe
     /modelo/<slug> y cualquier anuncio que apunte ahí.
   - `modelo_documentos.tipo`: CHECK con exactamente estos 5 valores.
   - `modelo_documentos.techo_clave` (23-sep-2026): a qué techo pertenece el
     documento; NULL = todos. El contrato de Construcción adjunta el plano del
     techo elegido. */
(function () {
  var TIPOS_DOC = [['plano', 'Plano · anexo del contrato'], ['calidades', 'Memoria de calidades'], ['ficha', 'Ficha'], ['render', 'Render'], ['otro', 'Otro']];
  var C = { lagoon: '#104C4F', tinta: '#1b1c19', gris: '#2E3437', apagado: '#5E625A', borde: '#E4DCCB', crema: '#FBF9F4', lino: '#F5F0E6',
            rojo: '#93000a', rojoBg: '#ffdad6', ambar: '#634A00', ambarBg: '#FBEFBE', verde: '#485B37' };

  function esc(v) { return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function num(s) { var t = String(s == null ? '' : s).trim().replace(/\./g, '').replace(',', '.'); return t === '' ? null : Number(t); }
  function numDec(s) { var t = String(s == null ? '' : s).trim().replace(',', '.'); return t === '' ? null : Number(t); }
  // NaN viajaría como null en el JSON (y borraría el dato): se para aquí con su nombre
  function chk(v, etq) { if (v != null && !isFinite(v)) throw new Error(etq + ' no es un número'); return v; }
  function norm(s) { return String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim(); }

  /* Toda escritura va por el servidor (27-sep-2026, LAW-336 bloque 3): RPC
     SECURITY DEFINER con el permiso y la validación dentro, que LANZA si no
     guarda — ya no hay «0 filas = la RLS lo denegó» que vigilar aquí. El
     precio base, los techos, los precios por proyecto y las altas van en UNA
     transacción (modelo_precios_guarda): antes eran una cadena de escrituras
     con «deshacer» a mano en el navegador. */
  function rpc(sb, fn, args) {
    return sb.rpc(fn, args).then(function (r) {
      if (r.error) throw r.error;
      return r.data;
    });
  }
  function mensaje(e) {
    var m = (e && e.message) || String(e);
    if (/duplicate key|23505|unique constraint/i.test(m)) return 'Ya existe una fila para ese proyecto (quizá creada desde otra pestaña): recarga la página.';
    return m;
  }

  var CSS = '' +
    '#fm-bloques{flex-shrink:0;display:grid;grid-template-columns:minmax(0,1.35fr) minmax(0,1fr);gap:18px;align-items:start}' +
    '@media (max-width:1100px){#fm-bloques{grid-template-columns:minmax(0,1fr)}}' +
    '.fm-col{display:flex;flex-direction:column;gap:14px;min-width:0}' +
    '.fm-b{border:1px solid #E7E4DC;border-radius:12px;padding:20px 24px;display:flex;flex-direction:column;gap:14px;background:#fff;min-width:0;box-shadow:0 1px 2px rgba(0,0,0,.05)}' +
    '.fm-b.fm-edit{border:2px solid ' + C.lagoon + ';background:#FBFDFC}' +
    '.fm-b.fm-suave{background:' + C.lino + ';border-color:' + C.lino + '}' +
    '.fm-cab{display:flex;justify-content:space-between;align-items:center;gap:10px}' +
    '.fm-cab h3{margin:0;font:700 15px/1.3 Jost,system-ui,sans-serif;letter-spacing:.025em;text-transform:uppercase;color:' + C.lagoon + '}' +
    '.fm-b.fm-edit .fm-cab h3{color:' + C.lagoon + '}' +
    '.fm-ed{border:1px solid #E7E4DC;background:#fff;font:500 13px Jost,system-ui,sans-serif;color:' + C.lagoon + ';cursor:pointer;padding:5px 14px;border-radius:9999px;box-shadow:0 1px 2px rgba(0,0,0,.05)}' +
    '.fm-ed:hover{background:#fafaf9}' +
    '.fm-4{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}' +
    '.fm-dato{background:' + C.crema + ';border-radius:10px;padding:9px 11px;min-width:0}' +
    '.fm-lbl{font-size:10.5px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:' + C.apagado + '}' +
    '.fm-val{font-size:20px;font-weight:600;color:' + C.tinta + ';white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
    '.fm-txt{margin:0;font-size:14px;line-height:1.5;color:' + C.gris + ';white-space:pre-line}' +
    '.fm-vacio{margin:0;font-size:13px;line-height:1.5;color:' + C.apagado + '}' +
    '.fm-fila{display:grid;grid-template-columns:minmax(0,1fr) 54px minmax(0,1.1fr);gap:10px;align-items:center;padding:7px 10px;border-radius:10px;background:' + C.crema + ';font-size:13.5px}' +
    '.fm-fila.fm-aviso{background:' + C.ambarBg + ';color:' + C.ambar + '}' +
    '.fm-fila.fm-mal{background:' + C.rojoBg + ';color:' + C.rojo + '}' +
    '.fm-fila b{font-weight:600}' +
    '.fm-nota{margin:0;font-size:12.5px;line-height:1.45;color:' + C.apagado + '}' +
    '.fm-nota.fm-ambar{color:' + C.ambar + ';font-weight:600}' +
    '.fm-nota.fm-rojo{color:' + C.rojo + ';font-weight:600}' +
    '.fm-chips{display:flex;flex-wrap:wrap;gap:6px}' +
    '.fm-chip{padding:4px 11px;border-radius:999px;background:' + C.lino + ';font-size:12.5px;color:' + C.gris + '}' +
    '.fm-chip.fm-no{background:none;border:1px dashed #BEB3A5;color:' + C.apagado + ';text-decoration:line-through}' +
    '.fm-in{height:42px;box-sizing:border-box;border:1px solid #E7E4DC;border-radius:8px;padding:0 14px;font:400 14px/1.43 Jost,system-ui,sans-serif;background:rgba(250,250,249,.5);color:#1c1917;width:100%;min-width:0;transition:border-color .16s,box-shadow .2s,background-color .16s}' +
    '.fm-in:hover{border-color:#d6cfc2}' +
    'textarea.fm-in{height:auto;padding:10px 14px;line-height:1.45;resize:vertical}' +
    '.fm-in:focus{outline:none;background:#fff;border-color:' + C.lagoon + ';box-shadow:0 0 0 2px ' + C.lagoon + '}' +
    '.fm-campo{display:flex;flex-direction:column;gap:4px;font-size:12px;font-weight:700;letter-spacing:.05em;text-transform:uppercase;color:#44403c;min-width:0}' +
    '.fm-check{display:flex;align-items:flex-start;gap:8px;font-size:13.5px;font-weight:600;color:' + C.gris + '}' +
    '.fm-check input{width:18px;height:18px;margin-top:1px;accent-color:' + C.lagoon + ';flex:0 0 auto}' +
    '.fm-check small{display:block;font-weight:500;color:' + C.apagado + ';font-size:12px}' +
    '.fm-pie{display:flex;justify-content:flex-end;gap:8px;align-items:center;flex-wrap:wrap}' +
    '.fm-btn{height:40px;padding:0 24px;border-radius:9999px;border:1px solid #E7E4DC;background:#fff;font:500 14px Jost,system-ui,sans-serif;color:#44403c;cursor:pointer;box-shadow:0 1px 2px rgba(0,0,0,.05);transition:background .15s,transform .12s cubic-bezier(.23,1,.32,1)}' +
    '.fm-btn:hover{background:#fafaf9}.fm-btn:active{transform:scale(.97)}' +
    '.fm-btn.fm-pri{border:0;background:' + C.lagoon + ';color:#fff;letter-spacing:.025em}' +
    '.fm-btn.fm-pri:hover{background:#0B3638}' +
    '.fm-btn:disabled{opacity:.55;cursor:default}' +
    '.fm-error{margin:0;padding:8px 10px;border-radius:9px;background:' + C.rojoBg + ';color:' + C.rojo + ';font-size:13px;font-weight:600}' +
    '.fm-lista{margin:0;padding-left:18px;font-size:13px;line-height:1.55;color:' + C.gris + '}' +
    '.fm-ok{color:' + C.verde + '}' +
    '.fm-tabla{display:grid;gap:6px 12px;font-size:13.5px;align-items:center}';

  function inyectaCSS() {
    if (document.getElementById('fm-css')) return;
    var s = document.createElement('style'); s.id = 'fm-css'; s.textContent = CSS;
    document.head.appendChild(s);
  }

  var EST = { admin: false, ctx: null, m: null };
  if (window.LW_AUTH && window.LW_AUTH.then) {
    window.LW_AUTH.then(function (aut) {
      var r = aut && aut.ficha && aut.ficha.rol;
      EST.admin = r === 'admin' || r === 'super_admin';
      if (EST.m) pintar(EST.m, EST.ctx);   // el rol llega después del primer pintado
    });
  }

  /* ---------- lo que el bloque necesita saber del modelo ---------- */
  function hechos(m, ctx) {
    var D = ctx.D;
    var filas = D.villas.filter(function (v) { return v.modelo_id === m.id; })
      .sort(function (a, b) { return String(a.proyecto).localeCompare(String(b.proyecto)); });
    var techos = D.techos.filter(function (t) { return t.modelo_id === m.id; })
      .sort(function (a, b) { return (a.orden || 0) - (b.orden || 0); });
    var mex = D.modeloExtras.filter(function (x) { return x.modelo_id === m.id; });
    var docs = D.docs.filter(function (d) { return d.modelo_id === m.id; });
    var fotos = (D.fotos[m.id] || []).length;
    var udsProy = {}, idProy = {};
    D.unidades.forEach(function (u) {
      if (u.modelo_id !== m.id) return;
      var k = u.proyecto || 'Sin proyecto';
      udsProy[k] = (udsProy[k] || 0) + 1;
      if (u.proyecto_id) idProy[k] = u.proyecto_id;
    });
    // Unidades que NOMBRAN el modelo pero no están enlazadas (modelo_id NULL):
    // no heredan nada y el renombrado no las arrastra (Datos: 81 «Dream» en
    // Sumba Hills). Solo se avisa: enlazarlas es un cambio masivo de datos.
    var sinEnlazar = {};
    var n = norm(m.nombre);
    D.unidades.forEach(function (u) {
      if (u.modelo_id || !u.modelo || norm(u.modelo) !== n) return;
      var k = u.proyecto || 'Sin proyecto';
      sinEnlazar[k] = (sinEnlazar[k] || 0) + 1;
    });
    var conFila = {}; filas.forEach(function (v) { conFila[v.proyecto] = 1; });
    var sinFila = Object.keys(udsProy).filter(function (k) { return !conFila[k] && k !== 'Sin proyecto'; });
    return { filas: filas, techos: techos, mex: mex, docs: docs, fotos: fotos, udsProy: udsProy, idProy: idProy, sinEnlazar: sinEnlazar, sinFila: sinFila };
  }

  /* ---------- andamiaje de un bloque ---------- */
  function bloque(col, clave, titulo, opts) {
    opts = opts || {};
    var s = document.createElement('section');
    s.className = 'fm-b' + (opts.suave ? ' fm-suave' : '');
    s.setAttribute('data-bloque', clave);
    var cab = document.createElement('div'); cab.className = 'fm-cab';
    var h = document.createElement('h3'); h.textContent = titulo; cab.appendChild(h);
    var cuerpo = document.createElement('div'); cuerpo.style.cssText = 'display:flex;flex-direction:column;gap:10px;min-width:0';
    s.appendChild(cab); s.appendChild(cuerpo);
    col.appendChild(s);
    var api = { s: s, cab: cab, h: h, cuerpo: cuerpo, titulo: titulo };
    if (opts.editar && (opts.puede == null ? EST.admin : opts.puede)) {
      var b = document.createElement('button'); b.type = 'button'; b.className = 'fm-ed'; b.textContent = opts.textoEditar || 'Editar';
      b.setAttribute('data-real', '');
      b.addEventListener('click', function (ev) { ev.stopPropagation(); abreEdicion(api, opts.editar); });
      cab.appendChild(b);
      api.btn = b;
    }
    return api;
  }

  /* Convierte el bloque en formulario: `editar(host)` monta los campos y
     devuelve `guardar()` (una promesa). Error = el bloque sigue abierto con el
     motivo; éxito = recarga con ?modelo= (el cajón se reabre en esta ficha). */
  function abreEdicion(api, editar) {
    var vista = document.createElement('div');
    while (api.cuerpo.firstChild) vista.appendChild(api.cuerpo.firstChild);
    api.s.classList.add('fm-edit');
    api.h.textContent = api.titulo + ' · editando';
    if (api.btn) api.btn.style.display = 'none';
    var host = document.createElement('div'); host.style.cssText = 'display:flex;flex-direction:column;gap:10px;min-width:0';
    api.cuerpo.appendChild(host);
    var guardar = editar(host);
    var err = document.createElement('p'); err.className = 'fm-error'; err.style.display = 'none';
    var pie = document.createElement('div'); pie.className = 'fm-pie';
    var bC = document.createElement('button'); bC.type = 'button'; bC.className = 'fm-btn'; bC.textContent = 'Cancelar'; bC.setAttribute('data-real', '');
    var bG = document.createElement('button'); bG.type = 'button'; bG.className = 'fm-btn fm-pri'; bG.textContent = 'Guardar'; bG.setAttribute('data-real', '');
    pie.appendChild(bC); pie.appendChild(bG);
    api.cuerpo.appendChild(err); api.cuerpo.appendChild(pie);
    bC.addEventListener('click', function (ev) {
      ev.stopPropagation();
      api.cuerpo.innerHTML = '';
      while (vista.firstChild) api.cuerpo.appendChild(vista.firstChild);
      api.s.classList.remove('fm-edit'); api.h.textContent = api.titulo;
      if (api.btn) api.btn.style.display = '';
    });
    bG.addEventListener('click', function (ev) {
      ev.stopPropagation();
      err.style.display = 'none'; bG.disabled = true; bC.disabled = true; bG.textContent = 'Guardando…';
      Promise.resolve().then(guardar).then(function (res) {
        if (res === false) { bG.disabled = false; bC.disabled = false; bG.textContent = 'Guardar'; return; }  // cancelado por el usuario
        bG.textContent = 'Guardado';
        location.reload();
      }, function (e) {
        err.textContent = 'No se ha guardado: ' + mensaje(e); err.style.display = '';
        bG.disabled = false; bC.disabled = false; bG.textContent = 'Guardar';
      });
    });
    var primero = host.querySelector('input:not([type=checkbox]),textarea,select');
    if (primero) try { primero.focus(); } catch (e) {}
  }

  function campo(host, etiqueta, valor, o) {
    o = o || {};
    var l = document.createElement('label'); l.className = 'fm-campo';
    l.appendChild(document.createTextNode(etiqueta));
    var i = document.createElement(o.area ? 'textarea' : 'input');
    i.className = 'fm-in';
    if (o.area) i.rows = o.filas || 4; else i.type = 'text';
    if (o.num) i.inputMode = 'decimal';
    i.value = valor == null ? '' : valor;
    if (o.ph) i.placeholder = o.ph;
    if (o.soloLectura) { i.readOnly = true; i.style.background = C.lino; }
    l.appendChild(i);
    if (o.ayuda) { var a = document.createElement('small'); a.style.cssText = 'font-weight:500;color:' + C.apagado; a.textContent = o.ayuda; l.appendChild(a); }
    host.appendChild(l);
    return i;
  }
  function casilla(host, etiqueta, marcado, ayuda) {
    var l = document.createElement('label'); l.className = 'fm-check';
    var i = document.createElement('input'); i.type = 'checkbox'; i.checked = !!marcado;
    var t = document.createElement('span'); t.textContent = etiqueta;
    if (ayuda) { var sm = document.createElement('small'); sm.textContent = ayuda; t.appendChild(sm); }
    l.appendChild(i); l.appendChild(t); host.appendChild(l);
    return i;
  }
  function nota(host, texto, tono) {
    var p = document.createElement('p'); p.className = 'fm-nota' + (tono ? ' fm-' + tono : ''); p.textContent = texto; host.appendChild(p); return p;
  }
  function vacio(host, texto) { var p = document.createElement('p'); p.className = 'fm-vacio'; p.textContent = texto; host.appendChild(p); }

  /* ================= los bloques ================= */

  function bTecnica(col, m, ctx) {
    var b = bloque(col, 'tecnica', 'Ficha técnica', { editar: function (host) {
      var g = document.createElement('div'); g.className = 'fm-4'; host.appendChild(g);
      var d = campo(g, 'Dormitorios', m.dormitorios, { num: 1 }), ba = campo(g, 'Baños', m.banos, { num: 1 }),
          v = campo(g, 'Villa (m²)', m.villa_m2, { num: 1 }), t = campo(g, 'Terraza (m²)', m.terraza_m2, { num: 1 });
      nota(host, 'Lo heredan todas las unidades que usan este modelo.');
      return function () {
        return rpc(ctx.sb, 'modelo_guarda', { p_id: m.id, p_cambios: {
          dormitorios: chk(numDec(d.value), 'Dormitorios'), banos: chk(numDec(ba.value), 'Baños'),
          villa_m2: chk(numDec(v.value), 'Villa (m²)'), terraza_m2: chk(numDec(t.value), 'Terraza (m²)')
        } });
      };
    } });
    var g = document.createElement('div'); g.className = 'fm-4';
    [['Dormitorios', m.dormitorios], ['Baños', m.banos], ['Villa', m.villa_m2 != null ? m.villa_m2 + ' m²' : null], ['Terraza', m.terraza_m2 != null ? m.terraza_m2 + ' m²' : null]].forEach(function (x) {
      var c = document.createElement('div'); c.className = 'fm-dato';
      c.innerHTML = '<div class="fm-lbl">' + esc(x[0]) + '</div><div class="fm-val">' + esc(x[1] == null ? '—' : x[1]) + '</div>';
      g.appendChild(c);
    });
    b.cuerpo.appendChild(g);
    if (ctx.sinFicha(m)) nota(b.cuerpo, 'Sin ficha técnica: las unidades de este modelo no heredan dormitorios, baños ni superficie.', 'rojo');
  }

  function estadoFila(v, m, ctx) {
    var base = m.precio_construccion != null ? Number(m.precio_construccion) : null;
    if (v.precio_construccion == null) {
      return base != null ? { cls: '', txt: 'hereda la base · ' + ctx.fmt(base, m.moneda) } : { cls: 'fm-mal', txt: 'sin precio: hereda la base y no hay base' };
    }
    var p = Number(v.precio_construccion);
    if (base != null && p === base && (v.moneda || m.moneda) === m.moneda) return { cls: '', txt: 'fijado a mano · ' + ctx.fmt(p, v.moneda || m.moneda) + ' (igual a la base, no la sigue)' };
    return { cls: '', txt: 'precio propio · ' + ctx.fmt(p, v.moneda || m.moneda) };
  }

  function bPrecios(col, m, h, ctx) {
    var base = m.precio_construccion != null ? Number(m.precio_construccion) : null;
    var b = bloque(col, 'precios', 'Precio de construcción', { editar: function (host) {
      // Mismo criterio que modelo_precios_guarda (revisión #126): cualquier fila que cuelgue del modelo
      // (techos, extras, precio por proyecto, previsión del deck) fija la moneda.
      var conCifras = h.filas.length > 0 || h.techos.length > 0 || h.mex.length > 0 ||
        (ctx.FC || []).some(function (x) { return x.modelo_id === m.id; });
      var fila1 = document.createElement('div'); fila1.style.cssText = 'display:grid;grid-template-columns:170px 110px minmax(0,1fr);gap:10px;align-items:end';
      host.appendChild(fila1);
      var iBase = campo(fila1, 'Precio base', base, { num: 1, ph: 'sin precio' });
      var lm = document.createElement('label'); lm.className = 'fm-campo'; lm.appendChild(document.createTextNode('Moneda'));
      var sel = document.createElement('select'); sel.className = 'fm-in';
      ['EUR', 'IDR'].forEach(function (x) { var o = document.createElement('option'); o.value = x; o.textContent = x; if ((m.moneda || 'EUR') === x) o.selected = true; sel.appendChild(o); });
      if (conCifras) sel.disabled = true;
      lm.appendChild(sel); fila1.appendChild(lm);
      var ex = document.createElement('p'); ex.className = 'fm-nota'; ex.style.paddingBottom = '10px';
      ex.textContent = conCifras ? 'La moneda no se cambia: el modelo ya tiene techos, extras, precios por proyecto o previsión en ' + (m.moneda || 'EUR') + ' y no se convierten.' : 'La base la heredan los proyectos que no tienen precio propio.';
      fila1.appendChild(ex);

      var prev = document.createElement('div'); host.appendChild(prev);
      function pintaPrevia() {
        prev.innerHTML = '';
        var nb = num(iBase.value);
        if (!h.techos.length) return;
        if (base == null || nb == null) {
          if (nb !== base) nota(prev, 'Este modelo tiene techos y la base estaba vacía: los techos no se mueven solos. Revisa el bloque Techos después.', 'ambar');
          return;
        }
        var d = nb - base;
        if (!d) return;
        nota(prev, 'Los techos se mueven con la base (' + (d > 0 ? '+' : '') + ctx.fmt(d, m.moneda) + '), si no el techo precargado en los proyectos con precio propio cambiaría al revés:', 'ambar');
        var ul = document.createElement('ul'); ul.className = 'fm-lista';
        h.techos.forEach(function (t) {
          var li = document.createElement('li');
          li.textContent = t.nombre + ': ' + ctx.fmt(t.precio_ahora, m.moneda) + ' → ' + ctx.fmt(Number(t.precio_ahora) + d, m.moneda) +
            (t.precio_2027 != null ? ' · 2027: ' + ctx.fmt(t.precio_2027, m.moneda) + ' → ' + ctx.fmt(Number(t.precio_2027) + d, m.moneda) : '');
          ul.appendChild(li);
        });
        prev.appendChild(ul);
      }
      iBase.addEventListener('input', pintaPrevia);

      var ins = [];
      if (h.filas.length) {
        nota(host, 'Precio por proyecto: vacío = hereda la base.');
        h.filas.forEach(function (v) {
          var f = document.createElement('div'); f.style.cssText = 'display:grid;grid-template-columns:minmax(0,1fr) 54px 150px;gap:10px;align-items:center';
          f.innerHTML = '<span style="font-size:13.5px;font-weight:600">' + esc(v.proyecto) + '</span><span style="font-size:13px;color:' + C.apagado + '">' + (h.udsProy[v.proyecto] || 0) + ' uds</span>';
          var i = document.createElement('input'); i.className = 'fm-in'; i.type = 'text'; i.inputMode = 'decimal';
          i.value = v.precio_construccion == null ? '' : v.precio_construccion; i.placeholder = 'hereda';
          f.appendChild(i); host.appendChild(f);
          ins.push({ v: v, i: i });
        });
      }
      var nuevas = [];
      if (h.sinFila.length) {
        nota(host, 'Proyectos con unidades de este modelo y sin fila de precio:', 'ambar');
        h.sinFila.forEach(function (k) {
          var f = document.createElement('div'); f.style.cssText = 'display:grid;grid-template-columns:minmax(0,1fr) 54px 150px;gap:10px;align-items:center';
          var lab = document.createElement('label'); lab.className = 'fm-check'; lab.style.fontSize = '13.5px';
          var chk = document.createElement('input'); chk.type = 'checkbox';
          lab.appendChild(chk); lab.appendChild(document.createTextNode('Declarar en ' + k));
          f.appendChild(lab);
          var u = document.createElement('span'); u.style.cssText = 'font-size:13px;color:' + C.apagado; u.textContent = h.udsProy[k] + ' uds'; f.appendChild(u);
          var i = document.createElement('input'); i.className = 'fm-in'; i.type = 'text'; i.inputMode = 'decimal';
          i.placeholder = base != null ? 'hereda' : 'precio (obligatorio)';
          i.addEventListener('input', function () { if (i.value.trim()) chk.checked = true; });
          f.appendChild(i); host.appendChild(f);
          nuevas.push({ proyecto: k, chk: chk, i: i });
        });
      }

      return function () {
        var sb = ctx.sb;
        var nb = num(iBase.value);
        var monedaNueva = sel.value || m.moneda || 'EUR';
        if (nb != null && !(nb >= 0)) throw new Error('el precio base no es un número');
        var cambiosFila = ins.filter(function (x) {
          var nv = num(x.i.value); var ov = x.v.precio_construccion == null ? null : Number(x.v.precio_construccion);
          return nv !== ov;
        });
        var altas = nuevas.filter(function (x) { return x.chk.checked; });
        for (var a = 0; a < altas.length; a++) {
          if (num(altas[a].i.value) == null && nb == null) throw new Error('«' + altas[a].proyecto + '» necesita precio: el modelo no tiene precio base que heredar');
        }
        cambiosFila.forEach(function (x) { if (num(x.i.value) == null && nb == null) throw new Error('«' + x.v.proyecto + '» quedaría sin precio: no hay base que heredar'); });
        chk(nb, 'El precio base');
        cambiosFila.forEach(function (x) { chk(num(x.i.value), 'El precio de ' + x.v.proyecto); });
        altas.forEach(function (x) {
          chk(num(x.i.value), 'El precio de ' + x.proyecto);
          if (!h.idProy[x.proyecto]) throw new Error('«' + x.proyecto + '» no tiene ficha de proyecto enlazada: no se puede declarar desde aquí');
        });

        /* UNA llamada, UNA transacción: la diferencia de los techos la calcula
           el servidor (base nueva − base de la fila bloqueada), nunca aquí. */
        var cambios = {};
        if (nb !== base) cambios.base = nb;
        if (monedaNueva !== (m.moneda || 'EUR')) cambios.moneda = monedaNueva;
        if (cambiosFila.length) cambios.villas = cambiosFila.map(function (x) { return { id: x.v.id, precio: num(x.i.value) }; });
        if (altas.length) cambios.altas = altas.map(function (x) { return { proyecto_id: h.idProy[x.proyecto], precio: num(x.i.value) }; });
        if (!Object.keys(cambios).length) return Promise.resolve();
        return rpc(sb, 'modelo_precios_guarda', { p_id: m.id, p_cambios: cambios }).then(function (res) {
          // Los contratos NO firmados guardan el precio que se eligió en pantalla y no se recalculan solos
          // (recalcular = cambiar un precio que el cliente vio): se dice cuántos hay, como mínimo.
          var n = res && res.contratos_no_firmados_min;
          if (!('base' in cambios) || !n) return;
          var txt = n + (n === 1 ? ' contrato sin firmar usa' : ' contratos sin firmar usan') + ' este modelo (al menos): conservan el precio con el que se generaron. Si alguno debe llevar el precio nuevo, regenéralo desde el generador.';
          if (typeof window.lwConfirmar === 'function') return window.lwConfirmar({ titulo: 'Precio guardado', cuerpo: '<p>' + esc(txt) + '</p>', confirmar: 'Entendido', cancelar: false })
            .then(function () {}, function () { /* MUDO A PROPOSITO: el precio ya está guardado; si el aviso falla, se recarga igual */ });
          window.alert(txt);
        });
      };
    } });

    var cab = document.createElement('div'); cab.style.cssText = 'display:flex;align-items:baseline;gap:10px;flex-wrap:wrap';
    cab.innerHTML = base != null
      ? '<span class="fm-lbl">Base</span><span style="font-size:22px;font-weight:600">' + esc(ctx.fmt(base, m.moneda)) + '</span>'
      : '<span class="fm-lbl">Base</span><span style="font-size:16px;font-weight:600;color:' + C.rojo + '">sin precio de catálogo</span>';
    b.cuerpo.appendChild(cab);
    if (!h.filas.length && !h.sinFila.length) { vacio(b.cuerpo, 'No está declarado en ningún proyecto.'); return; }
    var lista = document.createElement('div'); lista.style.cssText = 'display:flex;flex-direction:column;gap:5px';
    h.filas.forEach(function (v) {
      var e = estadoFila(v, m, ctx);
      var f = document.createElement('div'); f.className = 'fm-fila ' + e.cls;
      f.innerHTML = '<b>' + esc(v.proyecto) + '</b><span>' + (h.udsProy[v.proyecto] || 0) + ' uds</span><span>' + esc(e.txt) + '</span>';
      lista.appendChild(f);
    });
    h.sinFila.forEach(function (k) {
      var f = document.createElement('div'); f.className = 'fm-fila fm-aviso';
      f.innerHTML = '<b>' + esc(k) + '</b><span>' + h.udsProy[k] + ' uds</span><span>sin fila de precio · se declara en «Editar»</span>';
      lista.appendChild(f);
    });
    b.cuerpo.appendChild(lista);
    var mano = h.filas.filter(function (v) { return v.precio_construccion != null && base != null && Number(v.precio_construccion) === base; }).length;
    if (mano) nota(b.cuerpo, mano + (mano === 1 ? ' proyecto tiene' : ' proyectos tienen') + ' la base escrita a mano: si cambias la base, esos no se mueven.');
  }

  function bTechos(col, m, h, ctx) {
    var base = m.precio_construccion != null ? Number(m.precio_construccion) : null;
    var b = bloque(col, 'techos', 'Techos', { editar: h.techos.length ? function (host) {
      var t = document.createElement('div'); t.className = 'fm-tabla'; t.style.gridTemplateColumns = 'minmax(0,1fr) 140px 140px'; host.appendChild(t);
      t.innerHTML = '<span class="fm-lbl">Acabado</span><span class="fm-lbl">Ahora</span><span class="fm-lbl">2027</span>';
      var ins = h.techos.map(function (x) {
        var n = document.createElement('span'); n.textContent = x.nombre; n.style.fontWeight = '600'; t.appendChild(n);
        var a = document.createElement('input'); a.className = 'fm-in'; a.type = 'text'; a.inputMode = 'decimal'; a.value = x.precio_ahora == null ? '' : x.precio_ahora; t.appendChild(a);
        var z = document.createElement('input'); z.className = 'fm-in'; z.type = 'text'; z.inputMode = 'decimal'; z.value = x.precio_2027 == null ? '' : x.precio_2027; t.appendChild(z);
        return { x: x, a: a, z: z };
      });
      nota(host, 'Son precios completos de la villa con ese techo. El más barato debería coincidir con el precio base' + (base != null ? ' (' + ctx.fmt(base, m.moneda) + ')' : '') + '.');
      return function () {
        var lista = [];
        ins.forEach(function (r) {
          var na = chk(num(r.a.value), 'El precio de «' + r.x.nombre + '»'), nz = chk(num(r.z.value), 'El precio 2027 de «' + r.x.nombre + '»');
          if (na === (r.x.precio_ahora == null ? null : Number(r.x.precio_ahora)) && nz === (r.x.precio_2027 == null ? null : Number(r.x.precio_2027))) return;
          if (na == null) throw new Error('«' + r.x.nombre + '» necesita precio ahora');
          lista.push({ id: r.x.id, precio_ahora: na, precio_2027: nz });
        });
        if (!lista.length) return Promise.resolve();
        return rpc(ctx.sb, 'modelo_techos_guarda', { p_id: m.id, p_techos: lista });
      };
    } : null });
    if (!h.techos.length) { vacio(b.cuerpo, 'Sin techos: el contrato de Construcción no ofrece elegir acabado de techo.'); return; }
    var t = document.createElement('div'); t.className = 'fm-tabla'; t.style.gridTemplateColumns = 'minmax(0,1fr) 120px 120px';
    t.innerHTML = '<span class="fm-lbl">Acabado</span><span class="fm-lbl">Ahora</span><span class="fm-lbl">2027</span>' +
      h.techos.map(function (x) { return '<span>' + esc(x.nombre) + '</span><span style="font-weight:600">' + esc(ctx.fmt(x.precio_ahora, m.moneda)) + '</span><span>' + esc(x.precio_2027 != null ? ctx.fmt(x.precio_2027, m.moneda) : '—') + '</span>'; }).join('');
    b.cuerpo.appendChild(t);
    var min = Math.min.apply(null, h.techos.map(function (x) { return Number(x.precio_ahora); }));
    if (base != null && min !== base) nota(b.cuerpo, 'El techo más barato (' + ctx.fmt(min, m.moneda) + ') no coincide con la base (' + ctx.fmt(base, m.moneda) + '): el precio de techo en cada proyecto sale desplazado.', 'ambar');
  }

  function bExtras(col, m, h, ctx) {
    var D = ctx.D;
    var porExtra = {}; h.mex.forEach(function (x) { porExtra[x.extra_id] = x; });
    var b = bloque(col, 'extras', 'Extras', { editar: D.extras.length ? function (host) {
      var t = document.createElement('div'); t.className = 'fm-tabla'; t.style.gridTemplateColumns = 'minmax(0,1fr) 140px auto'; host.appendChild(t);
      t.innerHTML = '<span class="fm-lbl">Extra</span><span class="fm-lbl">Precio (' + esc(m.moneda || 'EUR') + ')</span><span class="fm-lbl">Se ofrece</span>';
      var ins = D.extras.map(function (e) {
        var ex = porExtra[e.id] || null;
        var n = document.createElement('span'); n.textContent = e.nombre; n.style.fontWeight = '600'; t.appendChild(n);
        var p = document.createElement('input'); p.className = 'fm-in'; p.type = 'text'; p.inputMode = 'decimal'; p.value = ex && ex.precio != null ? ex.precio : ''; p.placeholder = 'sin precio'; t.appendChild(p);
        var l = document.createElement('label'); l.className = 'fm-check'; var c = document.createElement('input'); c.type = 'checkbox';
        c.checked = !ex || ex.disponible !== false;   // sin fila = se ofrece, igual que en vivo
        l.appendChild(c); t.appendChild(l);
        return { e: e, ex: ex, p: p, c: c };
      });
      return function () {
        var lista = [];
        ins.forEach(function (r) {
          var np = chk(num(r.p.value), 'El precio de «' + r.e.nombre + '»'), disp = r.c.checked;
          if (r.ex) {
            if (np === (r.ex.precio == null ? null : Number(r.ex.precio)) && disp === (r.ex.disponible !== false)) return;
            lista.push({ extra_id: r.e.id, precio: np, disponible: disp });
          } else if (np != null || !disp) {
            // sin fila = «se ofrece, sin precio propio»: solo se crea fila cuando hay algo que decir
            lista.push({ extra_id: r.e.id, precio: np, disponible: disp });
          }
        });
        if (!lista.length) return Promise.resolve();
        // la moneda del extra la pone el servidor: SIEMPRE la del modelo
        return rpc(ctx.sb, 'modelo_extras_guarda', { p_id: m.id, p_extras: lista });
      };
    } : null });
    if (!D.extras.length) { vacio(b.cuerpo, 'No hay extras en el catálogo.'); return; }
    var ofrecidos = D.extras.filter(function (e) { var x = porExtra[e.id]; return !x || x.disponible !== false; }).length;
    b.h.textContent = b.titulo = 'Extras · ' + ofrecidos + ' de ' + D.extras.length + ' se ofrecen';
    var ch = document.createElement('div'); ch.className = 'fm-chips';
    ch.innerHTML = D.extras.map(function (e) {
      var x = porExtra[e.id]; var no = x && x.disponible === false;
      return '<span class="fm-chip' + (no ? ' fm-no' : '') + '">' + esc(e.nombre) + (x && x.precio != null ? ' · ' + esc(ctx.fmt(x.precio, x.moneda || m.moneda)) : '') + '</span>';
    }).join('');
    b.cuerpo.appendChild(ch);
  }

  function bAcabados(col, m, ctx) {
    var lista = Array.isArray(m.acabados) ? m.acabados : [];
    var b = bloque(col, 'acabados', 'Acabados (web)', { editar: function (host) {
      nota(host, 'Salen en la página del modelo en la web. Nombre y una línea de descripción.');
      var caja = document.createElement('div'); caja.style.cssText = 'display:flex;flex-direction:column;gap:8px'; host.appendChild(caja);
      var filas = [];
      function fila(n, d) {
        var f = document.createElement('div'); f.style.cssText = 'display:grid;grid-template-columns:170px minmax(0,1fr) auto;gap:8px;align-items:start';
        var a = document.createElement('input'); a.className = 'fm-in'; a.type = 'text'; a.value = n || ''; a.placeholder = 'Nombre';
        var z = document.createElement('input'); z.className = 'fm-in'; z.type = 'text'; z.value = d || ''; z.placeholder = 'Descripción';
        var q = document.createElement('button'); q.type = 'button'; q.className = 'fm-btn'; q.textContent = 'Quitar'; q.setAttribute('data-real', '');
        var r = { f: f, a: a, z: z };
        q.addEventListener('click', function (ev) { ev.stopPropagation(); f.remove(); filas.splice(filas.indexOf(r), 1); });
        f.appendChild(a); f.appendChild(z); f.appendChild(q); caja.appendChild(f); filas.push(r);
      }
      lista.forEach(function (x) { fila(x && x.n, x && x.d); });
      if (!lista.length) fila('', '');
      var mas = document.createElement('button'); mas.type = 'button'; mas.className = 'fm-btn'; mas.textContent = '+ Añadir acabado'; mas.setAttribute('data-real', '');
      mas.style.alignSelf = 'flex-start';
      mas.addEventListener('click', function (ev) { ev.stopPropagation(); fila('', ''); });
      host.appendChild(mas);
      return function () {
        // Solo {n, d}: la web deriva n_en/d_en si faltan (modelo/catalogo.php).
        var out = filas.map(function (r) { return { n: r.a.value.trim(), d: r.z.value.trim() }; }).filter(function (x) { return x.n; });
        return rpc(ctx.sb, 'modelo_guarda', { p_id: m.id, p_cambios: { acabados: out.length ? out : null } });
      };
    } });
    if (!lista.length) { vacio(b.cuerpo, 'Sin acabados.'); return; }
    var ul = document.createElement('ul'); ul.className = 'fm-lista';
    ul.innerHTML = lista.map(function (x) { return '<li><b>' + esc(x && x.n) + '</b>' + (x && x.d ? ' — ' + esc(x.d) : '') + '</li>'; }).join('');
    b.cuerpo.appendChild(ul);
  }

  function bWeb(col, m, h, ctx) {
    var tieneFicha = !ctx.sinFicha(m) && m.dormitorios != null && m.banos != null && m.villa_m2 != null && m.terraza_m2 != null;
    var tienePrecio = m.precio_construccion != null;
    var incl = (m.alcance && m.alcance.incluido) || [];
    var plano = h.docs.some(function (d) { return d.tipo === 'plano'; });
    // Condición REAL de la web: publicado AND activo AND (fotos OR renders_pendientes)
    var seVe = m.publicado && m.activo && (h.fotos > 0 || m.renders_pendientes);
    var b = bloque(col, 'web', 'En la web', { suave: 1, editar: function (host) {
      var p = casilla(host, 'Publicado', m.publicado, 'la web enseña este modelo con esta ficha y este precio');
      var r = casilla(host, 'Publicar su página aunque aún no tenga fotos', m.renders_pendientes, 'si no, un modelo sin fotos no tiene página en la web');
      nota(host, 'La web tarda hasta 5 minutos en reflejar el cambio.');
      return function () {
        return rpc(ctx.sb, 'modelo_guarda', { p_id: m.id, p_cambios: { publicado: p.checked, renders_pendientes: r.checked } });
      };
    } });
    var est = document.createElement('p'); est.style.cssText = 'margin:0;font-size:14px;font-weight:600;color:' + (seVe ? C.verde : C.gris);
    est.textContent = seVe ? 'Se ve en la web · /modelo/' + (m.slug || '') :
      (!m.activo ? 'No se ve: está inactivo' : !m.publicado ? 'No se ve: no está publicado' : 'No se ve: no tiene fotos (y no se ha marcado publicar sin fotos)');
    b.cuerpo.appendChild(est);
    var ul = document.createElement('ul'); ul.style.cssText = 'margin:0;padding:0;list-style:none;display:flex;flex-direction:column;gap:5px;font-size:13.5px';
    [[tieneFicha, 'Ficha técnica completa', 'Falta la ficha técnica'],
     [tienePrecio, 'Precio base', 'Sin precio base'],
     [!!(m.descripcion && m.descripcion.trim()), 'Texto para la web', 'Sin texto para la web'],
     [h.fotos > 0, h.fotos + (h.fotos === 1 ? ' foto' : ' fotos') + ' del deck', 'Sin fotos'],
     [incl.length > 0, 'Qué incluye la obra', 'Falta «la obra incluye»'],
     [plano, 'Plano (anexo del contrato)', 'Sin plano: el contrato de Construcción no tendrá anexo']
    ].forEach(function (x) {
      var li = document.createElement('li');
      li.style.color = x[0] ? C.gris : C.ambar; if (!x[0]) li.style.fontWeight = '600';
      li.textContent = (x[0] ? '✓ ' : '! ') + (x[0] ? x[1] : x[2]);
      ul.appendChild(li);
    });
    b.cuerpo.appendChild(ul);
  }

  function bTexto(col, m, ctx) {
    var b = bloque(col, 'texto', 'Texto para la web', { editar: function (host) {
      var t = campo(host, 'Descripción', m.descripcion, { area: 1, filas: 5, ayuda: 'la publica la página del modelo' });
      return function () { return rpc(ctx.sb, 'modelo_guarda', { p_id: m.id, p_cambios: { descripcion: t.value.trim() || null } }); };
    } });
    if (m.descripcion && m.descripcion.trim()) { var p = document.createElement('p'); p.className = 'fm-txt'; p.textContent = m.descripcion; b.cuerpo.appendChild(p); }
    else vacio(b.cuerpo, 'Sin texto: la web no tiene qué contar de este modelo.');
  }

  function bObra(col, m, ctx) {
    var incl = (m.alcance && m.alcance.incluido) || [], noi = (m.alcance && m.alcance.no_incluido) || [];
    var b = bloque(col, 'obra', 'La obra incluye', { editar: function (host) {
      var a = campo(host, 'Incluye (una línea por punto)', incl.join('\n'), { area: 1, filas: 6, ayuda: 'solo lo verificado en el anexo de obra de ESTE modelo — copiarlo de otro es inventarse un contrato' });
      var z = campo(host, 'No incluye (una línea por punto)', noi.join('\n'), { area: 1, filas: 3 });
      return function () {
        var l = function (s) { return String(s || '').split('\n').map(function (x) { return x.trim(); }).filter(Boolean); };
        var i = l(a.value), n = l(z.value);
        return rpc(ctx.sb, 'modelo_guarda', { p_id: m.id, p_cambios: { alcance: (i.length || n.length) ? { incluido: i, no_incluido: n } : null } });
      };
    } });
    if (!incl.length && !noi.length) { vacio(b.cuerpo, 'Sin definir.'); return; }
    var ul = document.createElement('ul'); ul.className = 'fm-lista';
    ul.innerHTML = incl.map(function (x) { return '<li>' + esc(x) + '</li>'; }).join('');
    b.cuerpo.appendChild(ul);
    if (noi.length) nota(b.cuerpo, 'No incluye: ' + noi.join(' · '));
  }

  function bDocs(col, m, h, ctx) {
    // Policy `modelo_docs: escribir` (25-sep-2026): cualquiera del equipo sube y
    // retipa documentos, SALVO el plano (Anexo Maestro), que es solo de admin.
    var b = bloque(col, 'docs', 'Documentos', { puede: true, textoEditar: h.techos.length ? 'Cambiar tipo o techo' : 'Cambiar tipo', editar: h.docs.length ? function (host) {
      var ins = h.docs.map(function (d) {
        var f = document.createElement('div'); f.style.cssText = 'display:grid;grid-template-columns:minmax(0,1fr) 210px' + (h.techos.length ? ' 150px' : '') + ';gap:10px;align-items:center';
        var n = document.createElement('span'); n.textContent = d.nombre || 'Documento'; n.style.cssText = 'font-size:13.5px;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap';
        var s = document.createElement('select'); s.className = 'fm-in';
        /* El plano (Anexo Maestro) solo lo decide administración (25-sep-2026,
           policy `modelo_docs: escribir`): un agente no convierte otro documento
           en plano ni toca el que ya lo es. */
        var bloqueado = !EST.admin && d.tipo === 'plano';
        TIPOS_DOC.forEach(function (t) {
          if (t[0] === 'plano' && !EST.admin && !bloqueado) return;
          var o = document.createElement('option'); o.value = t[0]; o.textContent = t[1]; if (d.tipo === t[0]) o.selected = true; s.appendChild(o);
        });
        if (bloqueado) { s.disabled = true; s.title = 'El Anexo Maestro solo lo cambia administración'; }
        f.appendChild(n); f.appendChild(s);
        // Techo del documento (23-sep-2026): el Anexo Maestro viene uno por
        // techo y el contrato adjunta el del techo elegido. «Todos» = NULL.
        var t = null;
        if (h.techos.length) {
          t = document.createElement('select'); t.className = 'fm-in'; t.setAttribute('aria-label', 'Techo del documento');
          [['', 'Todos los techos']].concat(h.techos.map(function (x) { return [x.clave, x.nombre]; })).forEach(function (o) {
            var e = document.createElement('option'); e.value = o[0]; e.textContent = o[1]; if ((d.techo_clave || '') === o[0]) e.selected = true; t.appendChild(e);
          });
          if (bloqueado) t.disabled = true;
          f.appendChild(t);
        }
        host.appendChild(f);
        return { d: d, s: s, t: t };
      });
      nota(host, 'El de tipo «Plano» es el que el contrato de Construcción adjunta al elegir este modelo' + (h.techos.length ? ': primero el del techo elegido y, si no hay, el de «Todos los techos».' : '.'));
      return function () {
        var p = Promise.resolve();
        ins.forEach(function (r) {
          var cambio = {};
          if (r.s.disabled) return;
          if (r.s.value !== r.d.tipo) cambio.tipo = r.s.value;
          if (r.t && r.t.value !== (r.d.techo_clave || '')) cambio.techo_clave = r.t.value || null;
          if (!Object.keys(cambio).length) return;
          // el plano (Anexo Maestro) lo vuelve a comprobar el servidor: solo administración
          p = p.then(function () { return rpc(ctx.sb, 'modelo_documento_cambia', { p_id: r.d.id, p_cambios: cambio }); });
        });
        return p;
      };
    } : null });
    var caja = contenedorFijo('d-docs');
    b.cuerpo.appendChild(caja);
    if (!h.docs.length) { vacio(caja, 'Ningún documento. Súbelos con «Añadir documento», abajo.'); return; }
    h.docs.forEach(function (d) {
      var f = document.createElement('div');
      f.style.cssText = 'display:flex;justify-content:space-between;gap:10px;align-items:center;padding:8px 10px;border-radius:10px;background:' + C.crema + ';cursor:pointer';
      if (d.path) { f.setAttribute('data-doc-abrir', ''); f.setAttribute('data-doc-path', d.path); }
      var tipo = (TIPOS_DOC.filter(function (t) { return t[0] === d.tipo; })[0] || [d.tipo, d.tipo || '—'])[1];
      var techo = d.techo_clave ? (h.techos.filter(function (t) { return t.clave === d.techo_clave; })[0] || { nombre: d.techo_clave }).nombre : '';
      f.innerHTML = '<span data-lw="doc-titulo" style="font-size:13.5px;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + esc(d.nombre || 'Documento') + '</span>' +
        '<span data-lw="doc-meta" style="font-size:12px;color:' + C.apagado + ';white-space:nowrap">' + esc(tipo + (techo ? ' · ' + techo : '') + ' · ' + ctx.fFecha(d.subido_en) + (d.visible_portal ? ' · visible al cliente' : '')) + '</span>';
      // Borrar (25-sep-2026, SC-21: «no me deja borrar documentos dados de alta»):
      // no existía ni aquí ni en la clásica. Solo admin porque «modelos bucket:
      // borrar» es es_admin() — a un agente se le borraría la fila y el fichero
      // quedaría huérfano. El click lo delega editores.js en #d-docs.
      if (EST.admin) {
        var bb = document.createElement('button'); bb.type = 'button'; bb.setAttribute('data-real', '');
        bb.setAttribute('data-doc-borrar', ''); bb.setAttribute('data-doc-id', d.id);
        bb.style.cssText = 'flex:none;border:0;background:none;padding:0;font-weight:600;font-size:11.5px;font-family:inherit;color:' + C.rojo + ';text-decoration:underline;cursor:pointer';
        bb.textContent = 'Borrar';
        f.appendChild(bb);
      }
      caja.appendChild(f);
    });
  }

  function bUnidades(col, m, h, ctx) {
    var total = Object.keys(h.udsProy).reduce(function (a, k) { return a + h.udsProy[k]; }, 0);
    var b = bloque(col, 'unidades', 'Unidades · ' + total, {});
    var caja = contenedorFijo('d-proyectos');
    b.cuerpo.appendChild(caja);
    var claves = Object.keys(h.udsProy).sort(function (a, z) { return h.udsProy[z] - h.udsProy[a]; });
    if (!claves.length) vacio(caja, 'Ninguna unidad usa este modelo todavía.');
    claves.forEach(function (k) {
      // Mismos ganchos que antes (data-proyecto-fila / -nombre / -id y el botón
      // data-forecast-proyecto): el click lo delega editores.js en #d-proyectos.
      var f = document.createElement('div');
      f.setAttribute('data-proyecto-fila', ''); f.setAttribute('data-proyecto-nombre', k);
      f.style.cssText = 'display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:4px 10px;padding:7px 10px;border-radius:10px;background:' + C.crema;
      f.innerHTML = '<span data-lw="p-nombre" style="font-size:13.5px;flex:1 1 auto;min-width:0">' + esc(k) + '</span><span data-lw="p-n" style="font-size:13.5px;font-weight:600;color:' + C.lagoon + '">' + h.udsProy[k] + '</span>';
      var pid = h.idProy[k];
      if (pid) {
        f.setAttribute('data-proyecto-id', pid);
        var bf = document.createElement('button'); bf.type = 'button'; bf.setAttribute('data-forecast-proyecto', ''); bf.setAttribute('data-real', '');
        bf.style.cssText = 'border:0;background:none;padding:0;font-weight:600;font-size:11.5px;font-family:inherit;color:' + C.lagoon + ';text-decoration:underline;cursor:pointer';
        bf.textContent = 'Previsión del deck';
        f.appendChild(bf);
        // LAW-273: la base de la previsión frente a suelo + construcción de hoy
        var fc = ctx.FC.filter(function (x) { return x.modelo_id === m.id && x.proyecto_id === pid; })[0];
        var deb = fc && fc.inversion_base != null && ctx.baseDeberia ? ctx.baseDeberia(m, k) : null;
        if (deb && Math.abs(Number(fc.inversion_base) - deb.valor) >= 1) {
          var dif = Number(fc.inversion_base) - deb.valor;
          var av = document.createElement('p');
          av.style.cssText = 'margin:0;flex-basis:100%;font-size:11.5px;line-height:1.4;color:' + C.rojo;
          av.textContent = 'Previsión del deck: la base (' + ctx.fmt(Number(fc.inversion_base), 'EUR') + ') no cuadra con construcción + la parcela más barata (' + ctx.fmt(deb.valor, 'EUR') + ') — ' + (dif > 0 ? '+' : '') + ctx.fmt(dif, 'EUR') + '. O es un precio de paquete pactado, o se ha quedado vieja.';
          f.appendChild(av);
        }
      }
      caja.appendChild(f);
    });
    var se = Object.keys(h.sinEnlazar);
    if (se.length) {
      var tot = se.reduce(function (a, k) { return a + h.sinEnlazar[k]; }, 0);
      nota(b.cuerpo, tot + (tot === 1 ? ' unidad nombra' : ' unidades nombran') + ' «' + m.nombre + '» sin estar enlazadas al modelo (' +
        se.map(function (k) { return k + ': ' + h.sinEnlazar[k]; }).join(' · ') + '): no heredan su ficha ni su precio.', 'ambar');
    }
  }

  function bIdentidad(col, m, ctx) {
    var b = bloque(col, 'identidad', 'Identidad', { editar: function (host) {
      var n = campo(host, 'Nombre', m.nombre);
      var s = campo(host, 'Dirección en la web', m.slug, m.publicado
        ? { soloLectura: 1, ayuda: 'publicado: cambiarla rompe /modelo/' + m.slug + ' y los anuncios que apunten ahí. Despublícalo primero si de verdad hay que cambiarla.' }
        : { ayuda: '/modelo/<dirección> — solo minúsculas, números y guiones' });
      var a = casilla(host, 'Activo en el catálogo', m.activo, 'si no, no se ofrece en contratos ni en la web');
      var no = campo(host, 'Notas internas', m.notas, { area: 1, filas: 3, ayuda: 'nunca las ve la web' });
      return function () {
        var sb = ctx.sb;
        var nombre = n.value.trim(), slug = s.value.trim().toLowerCase();
        if (!nombre) throw new Error('el nombre no puede quedar vacío');
        if (!/^[a-z0-9-]+$/.test(slug)) throw new Error('la dirección solo admite minúsculas, números y guiones');
        var paso = Promise.resolve(true);
        if (nombre !== m.nombre) {
          /* trg_modelo_renombrado propaga el nombre a unidades.modelo y
             modelos_villa.modelo por modelo_id: se dice ANTES a cuántas. */
          paso = Promise.all([
            sb.from('unidades').select('id', { count: 'exact', head: true }).eq('modelo_id', m.id),
            sb.from('modelos_villa').select('id', { count: 'exact', head: true }).eq('modelo_id', m.id)
          ]).then(function (rs) {
            var fe = (rs[0] && rs[0].error) || (rs[1] && rs[1].error);
            if (fe) throw new Error('no se ha podido calcular a cuántas filas afecta el renombrado: ' + fe.message);
            var radio = [rs[0].count ? rs[0].count + ' unidad(es)' : '', rs[1].count ? rs[1].count + ' precio(s) por proyecto' : ''].filter(Boolean).join(' y ');
            if (typeof window.lwConfirmar !== 'function') return window.confirm('Renombrar a «' + nombre + '»: se propaga a ' + (radio || 'ninguna fila') + '.');
            return window.lwConfirmar({ titulo: 'Renombrar «' + m.nombre + '» a «' + nombre + '»',
              cuerpo: '<p>El nombre nuevo se propaga solo a <b>' + esc(radio || 'ninguna fila todavía') + '</b>. Lo ya impreso en un documento firmado no se toca.</p>',
              confirmar: 'Renombrar' });
          });
        }
        return paso.then(function (ok) {
          if (!ok) return false;
          return rpc(sb, 'modelo_guarda', { p_id: m.id, p_cambios: { nombre: nombre, slug: slug, activo: a.checked, notas: no.value.trim() || null } })
            .then(function () {
              if (slug !== m.slug) { try { history.replaceState(null, '', '?modelo=' + encodeURIComponent(slug)); } catch (e) { /* MUDO A PROPOSITO: solo la URL; si falla, la recarga abre la ficha por defecto */ } }
            }, function (e) {
              if (/duplicate key|unique constraint/i.test((e && e.message) || '') && /slug/i.test(e.message)) throw new Error('ya hay un modelo en esa dirección (' + slug + ')');
              throw e;
            });
        });
      };
    } });
    var t = document.createElement('div'); t.className = 'fm-tabla'; t.style.gridTemplateColumns = '110px minmax(0,1fr)';
    t.innerHTML = '<span class="fm-lbl">Dirección</span><span>/modelo/' + esc(m.slug || '—') + '</span>' +
      '<span class="fm-lbl">Catálogo</span><span>' + (m.activo ? 'Activo' : 'Inactivo') + '</span>' +
      '<span class="fm-lbl">Notas</span><span style="white-space:pre-line">' + esc(m.notas || '—') + '</span>';
    b.cuerpo.appendChild(t);
  }

  /* #d-docs y #d-proyectos son SIEMPRE los mismos elementos (los del HTML):
     editores.js les engancha al arrancar el click delegado de «abrir
     documento» y «Previsión del deck». Recrearlos perdería esos clicks. */
  var FIJOS = {};
  function contenedorFijo(id) {
    var e = FIJOS[id] || document.getElementById(id);
    if (!e) { e = document.createElement('div'); e.id = id; }
    FIJOS[id] = e;
    e.innerHTML = '';
    e.style.cssText = 'display:flex;flex-direction:column;gap:6px';
    return e;
  }

  /* ================= pintado ================= */
  function pintar(m, ctx) {
    EST.m = m; EST.ctx = ctx;
    inyectaCSS();
    var raiz = document.getElementById('fm-bloques');
    if (!raiz) return;
    ['d-docs', 'd-proyectos'].forEach(function (id) { if (!FIJOS[id]) FIJOS[id] = document.getElementById(id); });
    raiz.innerHTML = '';
    var h = hechos(m, ctx);
    var izq = document.createElement('div'); izq.className = 'fm-col';
    var der = document.createElement('div'); der.className = 'fm-col';
    raiz.appendChild(izq); raiz.appendChild(der);
    bTecnica(izq, m, ctx);
    bPrecios(izq, m, h, ctx);
    bTechos(izq, m, h, ctx);
    bExtras(izq, m, h, ctx);
    bAcabados(izq, m, ctx);
    bWeb(der, m, h, ctx);
    bTexto(der, m, ctx);
    bObra(der, m, ctx);
    bDocs(der, m, h, ctx);
    bUnidades(der, m, h, ctx);
    bIdentidad(der, m, ctx);
    if (!EST.admin) {
      var p = document.createElement('p'); p.className = 'fm-nota'; p.style.gridColumn = '1 / -1';
      p.textContent = 'Los datos del modelo y su Anexo Maestro los edita administración. Tú puedes subir los demás documentos y cambiar su tipo.';
      raiz.insertBefore(p, raiz.firstChild);
    }
  }

  window.lwFichaModelo = { pintar: pintar };
})();
