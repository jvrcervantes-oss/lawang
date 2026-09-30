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
   - TECHOS = SUPLEMENTO (30-sep-2026, owner): la base del modelo (ahora y 2027) es la casa CON su techo base;
     los demás techos suman un suplemento. Cambiar la base ya no mueve los techos. Fórmula única en el servidor
     (`_modelo_techos_opciones`); con precio propio del proyecto no hay doble subida en 2027.
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
   - `modelo_documentos.tipo`: CHECK con exactamente los valores de
     window.lwDocsContrato.TIPOS (contracts/assets/docs_contrato.js; lo vigila
     docs_contrato.test.js contra la migración, las RPC y la edge).
   - `modelo_documentos.techo_clave` (23-sep-2026): a qué techo pertenece el
     documento; NULL = todos.
   - `modelo_documentos.en_contrato` + `orden` (27-sep-2026): qué documentos
     adjunta el contrato de Construcción y en qué orden. Ver bDocs. */
(function () {
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
    // Un bloque puede tener más de un botón (Techos: «Editar» y «Añadir techo», 30-sep-2026): se ocultan todos.
    var botones = Array.prototype.slice.call(api.cab.querySelectorAll('.fm-ed'));
    botones.forEach(function (x) { x.style.display = 'none'; });
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
      botones.forEach(function (x) { x.style.display = ''; });
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
    var b27 = m.precio_construccion_2027 != null ? Number(m.precio_construccion_2027) : null;
    if (v.precio_construccion == null) {
      return base != null ? { cls: '', txt: 'hereda la base · ' + ctx.fmt(base, m.moneda) + (b27 != null ? ' (2027: ' + ctx.fmt(b27, m.moneda) + ')' : '') }
                          : { cls: 'fm-mal', txt: 'sin precio: hereda la base y no hay base' };
    }
    var p = Number(v.precio_construccion);
    // Con precio propio no hay doble subida en 2027 (owner, 30-sep-2026): el mismo precio los dos años.
    if (base != null && p === base && (v.moneda || m.moneda) === m.moneda) return { cls: '', txt: 'fijado a mano · ' + ctx.fmt(p, v.moneda || m.moneda) + ' (igual a la base, no la sigue; también en 2027)' };
    return { cls: '', txt: 'precio propio · ' + ctx.fmt(p, v.moneda || m.moneda) + ' (también en 2027)' };
  }

  function bPrecios(col, m, h, ctx) {
    var base = m.precio_construccion != null ? Number(m.precio_construccion) : null;
    var b = bloque(col, 'precios', 'Precio de construcción', { editar: function (host) {
      // Mismo criterio que modelo_precios_guarda (revisión #126): cualquier fila que cuelgue del modelo
      // (techos, extras, precio por proyecto, previsión del deck) fija la moneda.
      var conCifras = h.filas.length > 0 || h.techos.length > 0 || h.mex.length > 0 ||
        (ctx.FC || []).some(function (x) { return x.modelo_id === m.id; });
      var fila1 = document.createElement('div'); fila1.style.cssText = 'display:grid;grid-template-columns:150px 150px 100px minmax(0,1fr);gap:10px;align-items:end';
      host.appendChild(fila1);
      var iBase = campo(fila1, 'Precio base', base, { num: 1, ph: 'sin precio' });
      // 30-sep-2026: la base es la casa CON su techo base; los demás techos suman un suplemento (bloque Techos).
      var iBase27 = campo(fila1, 'Base 2027', m.precio_construccion_2027, { num: 1, ph: 'sin precio' });
      var lm = document.createElement('label'); lm.className = 'fm-campo'; lm.appendChild(document.createTextNode('Moneda'));
      var sel = document.createElement('select'); sel.className = 'fm-in';
      ['EUR', 'IDR'].forEach(function (x) { var o = document.createElement('option'); o.value = x; o.textContent = x; if ((m.moneda || 'EUR') === x) o.selected = true; sel.appendChild(o); });
      if (conCifras) sel.disabled = true;
      lm.appendChild(sel); fila1.appendChild(lm);
      var ex = document.createElement('p'); ex.className = 'fm-nota'; ex.style.paddingBottom = '10px';
      ex.textContent = conCifras ? 'La moneda no se cambia: el modelo ya tiene techos, extras, precios por proyecto o previsión en ' + (m.moneda || 'EUR') + ' y no se convierten.' : 'La base la heredan los proyectos que no tienen precio propio.';
      fila1.appendChild(ex);

      // Ya no hay que «mover los techos» con la base (30-sep-2026): son suplementos sobre ella.
      if (h.techos.length) nota(host, 'La base es el precio de la casa con su techo base. Los otros techos suman su suplemento encima (bloque Techos).');
      // Administración (consulta 30-sep): son dos cifras independientes; subir la de ahora no arrastra la de 2027.
      nota(host, 'La base de ahora y la de 2027 son independientes: si cambias una, revisa la otra.');

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
        var nb = num(iBase.value), nb27 = chk(num(iBase27.value), 'El precio base 2027');
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

        /* UNA llamada, UNA transacción (modelo_precios_guarda). */
        var cambios = {};
        if (nb !== base) cambios.base = nb;
        if (nb27 !== (m.precio_construccion_2027 == null ? null : Number(m.precio_construccion_2027))) cambios.base_2027 = nb27;
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
      ? '<span class="fm-lbl">Base</span><span style="font-size:22px;font-weight:600">' + esc(ctx.fmt(base, m.moneda)) + '</span>' +
        (m.precio_construccion_2027 != null ? '<span class="fm-lbl" style="margin-left:8px">2027</span><span style="font-size:16px;font-weight:600">' + esc(ctx.fmt(m.precio_construccion_2027, m.moneda)) + '</span>' : '')
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

  /* TECHOS = SUPLEMENTO SOBRE LA CASA (30-sep-2026, owner: «el modelo tiene un precio base con un techo base;
     la diferencia de los demás techos se suma, casi como un extra»). Migración 20260930120000; antes, esa misma
     mañana, los techos llevaban el precio completo (20260930023239).
     - La casa (bloque «Precio de construcción», base ahora y 2027) incluye su TECHO BASE (suplemento 0). Cada
       otro techo suma «+X ahora / +Y desde 2027» sobre la base, o sobre el precio propio del proyecto.
     - Esta pantalla solo recoge: valida, calcula y escribe el servidor (modelo_techo_crea, modelo_techos_guarda_lote).
     - Un techo nunca se borra: se RETIRA (su clave vive en contratos congelados, documentos y fotos de la web).
       El techo base no se retira ni se limita: para cambiarlo, se marca otro como base (con suplemento 0).
     - Alcance: «Todos los proyectos» (por defecto) o solo los marcados, entre los que venden la casa.
     - No es automático al añadir uno: su Anexo Maestro (Documentos, tipo plano) y su foto en la web. */
  function proyectosDeLaCasa(h) {
    return h.filas.filter(function (v) { return v.proyecto_id; })
      .map(function (v) { return { id: v.proyecto_id, nombre: v.proyecto }; });
  }
  function proyectosDelTecho(t, ctx) {
    return (ctx.D.techoProy || []).filter(function (x) { return x.techo_id === t.id; })
      .map(function (x) { return x.proyecto_id; });
  }
  function dondeTecho(t, h, ctx) {
    if (t.alcance !== 'lista') return { txt: 'Todos los proyectos', mal: false };
    var ids = proyectosDelTecho(t, ctx);
    var nombres = proyectosDeLaCasa(h).filter(function (p) { return ids.indexOf(p.id) !== -1; })
      .map(function (p) { return p.nombre; });
    return nombres.length ? { txt: nombres.join(' · '), mal: false }
                          : { txt: 'En ningún proyecto (la casa ya no está en los marcados)', mal: true };
  }
  /* «Todos los proyectos» + una casilla por proyecto donde se vende la casa. */
  function campoAlcance(host, h, ctx, t) {
    var proys = proyectosDeLaCasa(h);
    var antes = t ? proyectosDelTecho(t, ctx) : [];
    var todos = casilla(host, 'Todos los proyectos', !t || t.alcance !== 'lista',
      'Por defecto. Desmárcalo para elegir en qué proyectos se ofrece.');
    var caja = document.createElement('div'); caja.className = 'fm-chips'; caja.style.paddingLeft = '26px';
    host.appendChild(caja);
    var cs = proys.map(function (p) {
      return { id: p.id, i: casilla(caja, p.nombre, antes.indexOf(p.id) !== -1) };
    });
    if (!proys.length) nota(caja, 'Esta casa todavía no está en ningún proyecto: se añade en «Precio de construcción».');
    function sync() { caja.style.display = todos.checked ? 'none' : ''; }
    todos.addEventListener('change', sync); sync();
    return {
      todos: todos, antes: antes,
      sel: function () { return cs.filter(function (c) { return c.i.checked; }).map(function (c) { return c.id; }); }
    };
  }
  function mismoConjunto(a, b) {
    if (a.length !== b.length) return false;
    return a.every(function (x) { return b.indexOf(x) !== -1; });
  }
  function textoSuplemento(x, m, ctx) {
    if (x.es_base) return 'techo base · incluido';
    var a = Number(x.suplemento_ahora) || 0, z = Number(x.suplemento_2027) || 0;
    return '+' + ctx.fmt(a, m.moneda) + (z !== a ? ' · 2027: +' + ctx.fmt(z, m.moneda) : '');
  }
  /* Todo en UNA transacción (modelo_techos_guarda_lote). Si el cambio deja fuera contratos sin firmar, el servidor
     lo deshace todo y responde LW409: se pregunta una vez y se repite confirmado. */
  function guardaLote(ctx, m, precios, edits, confirmado) {
    return rpc(ctx.sb, 'modelo_techos_guarda_lote', { p_id: m.id, p_precios: precios, p_ediciones: edits, p_confirmado: !!confirmado })
      .catch(function (err) {
        if (!err || err.code !== 'LW409' || confirmado) throw err;
        var sigue = typeof window.lwConfirmar === 'function'
          ? window.lwConfirmar({ titulo: 'Cambiar los techos de «' + m.nombre + '»', confirmar: 'Cambiar igualmente',
              cuerpo: '<p>' + esc(err.message) + '</p><p>No se ha guardado nada todavía.</p>' })
          : Promise.resolve(window.confirm(err.message));
        return Promise.resolve(sigue).then(function (ok) {
          if (!ok) return false;   // abreEdicion deja el bloque abierto, sin guardar nada
          return guardaLote(ctx, m, precios, edits, true);
        });
      });
  }

  function bTechos(col, m, h, ctx) {
    var base = m.precio_construccion != null ? Number(m.precio_construccion) : null;
    var base27 = m.precio_construccion_2027 != null ? Number(m.precio_construccion_2027) : null;
    var sinBase = base == null || base27 == null;
    var b = bloque(col, 'techos', 'Techos', { editar: h.techos.length ? function (host) {
      nota(host, 'El techo base va incluido en el precio de la casa. Los demás suman su suplemento: ahora y desde 2027.');
      var grupo = 'fm-base-' + m.id;
      var ins = h.techos.map(function (x) {
        var tarjeta = document.createElement('div');
        tarjeta.style.cssText = 'display:flex;flex-direction:column;gap:8px;padding:12px 14px;border-radius:10px;background:' + C.crema;
        host.appendChild(tarjeta);
        var fila = document.createElement('div'); fila.className = 'fm-tabla'; fila.style.cssText = 'grid-template-columns:minmax(0,1fr) 130px 130px;align-items:start';
        tarjeta.appendChild(fila);
        var n = campo(fila, 'Nombre', x.nombre);
        var a = campo(fila, '+ Ahora', x.es_base ? 0 : x.suplemento_ahora, { num: 1 });
        var z = campo(fila, '+ 2027', x.es_base ? 0 : x.suplemento_2027, { num: 1 });
        var lb = document.createElement('label'); lb.className = 'fm-check';
        var rb = document.createElement('input'); rb.type = 'radio'; rb.name = grupo; rb.checked = !!x.es_base;
        var tb = document.createElement('span'); tb.textContent = 'Techo base (incluido en el precio de la casa)';
        lb.appendChild(rb); lb.appendChild(tb); tarjeta.appendChild(lb);
        var act = casilla(tarjeta, 'Se ofrece', x.activo !== false, 'Desmárcalo para retirarlo: deja de salir en contratos nuevos y en la web. Nunca se borra.');
        var al = campoAlcance(tarjeta, h, ctx, x);
        function sync() {
          // el base no lleva suplemento, no se retira ni se limita
          a.disabled = z.disabled = rb.checked;
          if (rb.checked) { a.value = 0; z.value = 0; act.checked = true; al.todos.checked = true; al.todos.dispatchEvent(new Event('change')); }
          act.disabled = al.todos.disabled = rb.checked;
        }
        rb.addEventListener('change', function () { ins.forEach(function (r) { r.sync(); }); });
        return { x: x, n: n, a: a, z: z, rb: rb, act: act, al: al, sync: sync };
      });
      ins.forEach(function (r) { r.sync(); });
      return function () {
        var precios = [], edits = [];
        ins.forEach(function (r) {
          var nombre = r.n.value.trim() || r.x.nombre;
          var na = chk(num(r.a.value), 'El suplemento de «' + nombre + '»'), nz = chk(num(r.z.value), 'El suplemento 2027 de «' + nombre + '»');
          if (na == null || nz == null) throw new Error('«' + nombre + '» necesita sus dos suplementos (0 si no suma nada)');
          if (na < 0 || nz < 0) throw new Error('El suplemento de «' + nombre + '» no puede ser negativo: si quieres un techo más barato, hazlo base y ajusta el precio de la casa');
          if (na !== Number(r.x.suplemento_ahora) || nz !== Number(r.x.suplemento_2027)) precios.push({ id: r.x.id, suplemento_ahora: na, suplemento_2027: nz });
          var c = {};
          if (r.rb.checked && !r.x.es_base) c.es_base = true;
          if (r.n.value.trim() !== r.x.nombre) c.nombre = r.n.value.trim();
          if (r.act.checked !== (r.x.activo !== false)) c.activo = r.act.checked;
          if (r.al.todos.checked) {
            if (r.x.alcance === 'lista') c.alcance = 'todos';
          } else {
            var sel = r.al.sel();
            if (!sel.length) throw new Error('«' + nombre + '»: marca al menos un proyecto, o deja «Todos los proyectos».');
            if (r.x.alcance !== 'lista' || !mismoConjunto(sel, r.al.antes)) { c.alcance = 'lista'; c.proyectos = sel; }
          }
          if (Object.keys(c).length) edits.push({ id: r.x.id, cambios: c });
        });
        if (!precios.length && !edits.length) return Promise.resolve();
        return guardaLote(ctx, m, precios, edits, false);
      };
    } : null });

    if (EST.admin) {
      var bA = document.createElement('button'); bA.type = 'button'; bA.className = 'fm-ed'; bA.textContent = 'Añadir techo';
      bA.setAttribute('data-real', ''); bA.setAttribute('data-accion', 'anadir-techo');
      bA.addEventListener('click', function (ev) {
        ev.stopPropagation();
        abreEdicion(b, function (host) {
          var primero = !h.techos.length;
          if (sinBase) nota(host, 'Pon antes el precio de la casa, ahora y 2027, en «Precio de construcción»: es el precio con el techo base.', 'rojo');
          if (primero) nota(host, 'Es el primer techo de este modelo: será su techo base, incluido en el precio de la casa (sin suplemento).');
          var n = campo(host, 'Nombre del techo', '', { ph: 'p. ej. Alang-alang' });
          var d = campo(host, 'Descripción (web y ficha)', '', { area: 1, filas: 3 });
          var a = null, z = null;
          if (!primero) {
            var g = document.createElement('div'); g.className = 'fm-tabla'; g.style.cssText = 'grid-template-columns:1fr 1fr;align-items:start'; host.appendChild(g);
            a = campo(g, 'Suplemento ahora', '', { num: 1, ayuda: 'Lo que suma sobre la casa con el techo base' });
            z = campo(g, 'Suplemento 2027', '', { num: 1, ayuda: 'Lo que suma desde el 1-ene-2027' });
          }
          var al = campoAlcance(host, h, ctx, null);
          nota(host, 'Después: sube su Anexo Maestro en «Documentos» (tipo plano, con este techo). Mientras no esté, el contrato avisa y deja enviar igualmente. La foto de este techo en la web tampoco es automática.');
          return function () {
            var nombre = n.value.trim();
            if (!nombre) throw new Error('Pon el nombre del techo');
            var datos = { nombre: nombre, descripcion: d.value.trim(), alcance: al.todos.checked ? 'todos' : 'lista' };
            if (a) {
              datos.suplemento_ahora = chk(num(a.value), 'El suplemento de ahora');
              datos.suplemento_2027 = chk(num(z.value), 'El suplemento de 2027');
              if (datos.suplemento_ahora == null || datos.suplemento_2027 == null) throw new Error('Pon los dos suplementos (0 si no suma nada)');
            }
            if (!al.todos.checked) {
              datos.proyectos = al.sel();
              if (!datos.proyectos.length) throw new Error('Marca al menos un proyecto, o deja «Todos los proyectos».');
            }
            return rpc(ctx.sb, 'modelo_techo_crea', { p_modelo_id: m.id, p_datos: datos });
          };
        });
      });
      b.cab.appendChild(bA);
      b.h.style.flex = '1';   // dos botones: juntos a la derecha, no uno en medio
    }

    if (!h.techos.length) { vacio(b.cuerpo, 'Sin techos: el contrato de Construcción ofrece solo «Ulin» al precio de la casa.'); return; }
    // Dos columnas (cabe a 390 px): el techo con «suplemento · dónde» debajo, y su precio de catálogo.
    var t = document.createElement('div'); t.className = 'fm-tabla'; t.style.gridTemplateColumns = 'minmax(0,1fr) auto';
    t.innerHTML = '<span class="fm-lbl">Acabado</span><span class="fm-lbl">Precio catálogo</span>';
    h.techos.slice().sort(function (p, q) { return (q.es_base ? 1 : 0) - (p.es_base ? 1 : 0) || (p.orden || 0) - (q.orden || 0); }).forEach(function (x) {
      var retirado = x.activo === false, donde = dondeTecho(x, h, ctx);
      var tachado = retirado ? 'color:' + C.apagado + ';text-decoration:line-through;' : '';
      var total = base != null ? base + (Number(x.suplemento_ahora) || 0) : null;
      t.insertAdjacentHTML('beforeend',
        '<span style="min-width:0"><span style="' + tachado + 'font-weight:600">' + esc(x.nombre) + '</span>' +
          '<small style="display:block;font-size:12px;color:' + (x.es_base && !retirado ? C.verde : C.apagado) + '">' + esc(textoSuplemento(x, m, ctx)) + '</small>' +
          '<small style="display:block;font-size:12px;color:' + (retirado ? C.apagado : donde.mal ? C.rojo : C.apagado) + '">' +
          esc(retirado ? 'Retirado' : donde.txt) + '</small></span>' +
        '<span style="' + tachado + 'font-weight:600;white-space:nowrap">' + esc(total != null ? ctx.fmt(total, m.moneda) : '—') + '</span>');
    });
    b.cuerpo.appendChild(t);
    nota(b.cuerpo, 'En los proyectos con precio propio, el techo base cuesta ese precio y los demás le suman su suplemento.');
    if (sinBase) nota(b.cuerpo, 'Falta el precio de la casa (ahora o 2027) en «Precio de construcción»: sin él no se puede ofrecer ningún techo.', 'rojo');
  }

  /* EXTRAS (30-sep-2026, owner: «necesito poder añadir o retirar extras»). Tres acciones, cada una UNA llamada:
     - «Editar»: precio y «se ofrece» de cada extra ACTIVO en este modelo (modelo_extras_guarda, como antes).
     - «Añadir extra»: alta en el catálogo con su precio en este modelo; en los demás modelos queda «no se ofrece»
       hasta que se le ponga precio allí (extra_crea).
     - «Catálogo»: retirar o reactivar extras para TODOS los modelos (extras_catalogo_guarda, una transacción).
       Retirado = no sale en contratos nuevos ni en la web; nunca se borra (los contratos congelan el extra). */
  function guardaCatalogoExtras(ctx, cambios, confirmado) {
    return rpc(ctx.sb, 'extras_catalogo_guarda', { p_cambios: cambios, p_confirmado: !!confirmado })
      .catch(function (err) {
        if (!err || err.code !== 'LW409' || confirmado) throw err;
        var sigue = typeof window.lwConfirmar === 'function'
          ? window.lwConfirmar({ titulo: 'Retirar extras del catálogo', confirmar: 'Retirar igualmente',
              cuerpo: '<p>' + esc(err.message) + '</p><p>No se ha guardado nada todavía.</p>' })
          : Promise.resolve(window.confirm(err.message));
        return Promise.resolve(sigue).then(function (ok) { return ok ? guardaCatalogoExtras(ctx, cambios, true) : false; });
      });
  }

  function bExtras(col, m, h, ctx) {
    var D = ctx.D;
    var activos = D.extras.filter(function (e) { return e.activo !== false; });
    var retirados = D.extras.filter(function (e) { return e.activo === false; });
    var porExtra = {}; h.mex.forEach(function (x) { porExtra[x.extra_id] = x; });
    var b = bloque(col, 'extras', 'Extras', { editar: activos.length ? function (host) {
      var t = document.createElement('div'); t.className = 'fm-tabla'; t.style.gridTemplateColumns = 'minmax(0,1fr) 140px auto'; host.appendChild(t);
      t.innerHTML = '<span class="fm-lbl">Extra</span><span class="fm-lbl">Precio (' + esc(m.moneda || 'EUR') + ')</span><span class="fm-lbl">Se ofrece</span>';
      var ins = activos.map(function (e) {
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

    if (EST.admin) {
      var bA = document.createElement('button'); bA.type = 'button'; bA.className = 'fm-ed'; bA.textContent = 'Añadir extra';
      bA.setAttribute('data-real', ''); bA.setAttribute('data-accion', 'anadir-extra');
      bA.addEventListener('click', function (ev) {
        ev.stopPropagation();
        abreEdicion(b, function (host) {
          var n = campo(host, 'Nombre del extra', '', { ph: 'p. ej. Piscina infinita' });
          var d = campo(host, 'Descripción (web y contrato)', '', { area: 1, filas: 3 });
          var p = campo(host, 'Precio en ' + m.nombre + ' (' + (m.moneda || 'EUR') + ')', '', { num: 1 });
          nota(host, 'Se ofrece solo en ' + m.nombre + '. En los demás modelos aparece como «no se ofrece» hasta que le pongas precio en su ficha.');
          return function () {
            var nombre = n.value.trim();
            if (!nombre) throw new Error('Pon el nombre del extra');
            var precio = chk(num(p.value), 'El precio');
            if (precio == null) throw new Error('Pon el precio del extra en este modelo');
            return rpc(ctx.sb, 'extra_crea', { p_modelo_id: m.id, p_datos: { nombre: nombre, descripcion: d.value.trim(), precio: precio } });
          };
        });
      });
      b.cab.appendChild(bA);

      if (D.extras.length) {
        var bC = document.createElement('button'); bC.type = 'button'; bC.className = 'fm-ed'; bC.textContent = 'Catálogo';
        bC.setAttribute('data-real', ''); bC.setAttribute('data-accion', 'catalogo-extras');
        bC.addEventListener('click', function (ev) {
          ev.stopPropagation();
          abreEdicion(b, function (host) {
            nota(host, 'Retirar un extra lo quita de TODOS los modelos: deja de salir en contratos nuevos y en la web. Nunca se borra y se puede reactivar.');
            var ins = D.extras.map(function (e) {
              return { e: e, c: casilla(host, e.nombre, e.activo !== false, e.activo === false ? 'Retirado del catálogo' : 'En el catálogo') };
            });
            return function () {
              var cambios = ins.filter(function (r) { return r.c.checked !== (r.e.activo !== false); })
                .map(function (r) { return { id: r.e.id, cambios: { activo: r.c.checked } }; });
              if (!cambios.length) return Promise.resolve();
              return guardaCatalogoExtras(ctx, cambios, false);
            };
          });
        });
        b.cab.appendChild(bC);
      }
      b.h.style.flex = '1';
    }

    if (!D.extras.length) { vacio(b.cuerpo, 'No hay extras en el catálogo.'); return; }
    var ofrecidos = activos.filter(function (e) { var x = porExtra[e.id]; return !x || x.disponible !== false; }).length;
    b.h.textContent = b.titulo = 'Extras · ' + ofrecidos + ' de ' + activos.length + ' se ofrecen';
    var ch = document.createElement('div'); ch.className = 'fm-chips';
    ch.innerHTML = activos.map(function (e) {
      var x = porExtra[e.id]; var no = x && x.disponible === false;
      return '<span class="fm-chip' + (no ? ' fm-no' : '') + '">' + esc(e.nombre) + (x && x.precio != null ? ' · ' + esc(ctx.fmt(x.precio, x.moneda || m.moneda)) : '') + '</span>';
    }).join('');
    b.cuerpo.appendChild(ch);
    if (retirados.length) nota(b.cuerpo, 'Retirados del catálogo: ' + retirados.map(function (e) { return e.nombre; }).join(', ') + '.');
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
    // lo que va en el contrato lo dice la casilla (27-sep-2026), no el tipo
    var nMarcados = h.docs.filter(function (d) { return d.en_contrato === true; }).length;
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
     [nMarcados > 0, nMarcados + (nMarcados === 1 ? ' documento marcado' : ' documentos marcados') + ' para el contrato', 'Nada marcado para el contrato: el contrato de Construcción no tendrá anexo']
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

  /* DOCUMENTOS — un bloque, tres secciones (27-sep-2026, owner: «crea una sección
     Dosier, necesito poder marcar si ese documento se carga automáticamente en el
     contrato o no, y mejora "Documentos" porque no queda entendible»; propuesta de
     Diseño en la revisión previa).
       · VAN EN EL CONTRATO — los marcados (casilla `en_contrato`), numerados en el
         orden en que se adjuntan, con el resumen POR TECHO de lo que se adjuntará.
         Manda la casilla: un dosier marcado sale aquí, no en «Dosier».
       · DOSIER — el PDF comercial del modelo (tipo nuevo), sin marcar.
       · OTROS DOCUMENTOS — el resto sin marcar, agrupados por tipo.
     La regla de qué entra la da window.lwDocsContrato (contracts/assets/docs_contrato.js),
     LA MISMA que usa el generador: el resumen por techo es lo que el contrato adjunta.
     Quién puede qué lo decide el servidor (modelo_documentos_guarda): la casilla, el
     orden y el tipo o el techo de lo marcado, solo administración; aquí solo se
     desactiva lo que el servidor va a rechazar, para no dejar pedirlo. */
  var SOLO_ADMIN = 'Solo administración decide qué va en el contrato';
  var DOSIER_NO = 'El dosier es comercial: no va en el contrato';
  /* Letras (owner y Legal, 28-sep-2026; las calcula docs_contrato.js): el plano es el único apéndice que el
     contrato cita y obliga (Apéndice A); lo demás va detrás, B, C, D… por tipo, como informativo. */
  var TXT_CONTRATO = 'Estos documentos se adjuntan al contrato de Construcción. El plano es el Apéndice A: el único que el '
    + 'contrato cita y que obliga. Todo lo demás va detrás como informativo (Apéndice B, C, D…), en este orden de tipo: '
    + 'memoria de calidades, ficha, render, otros. El orden de esta lista solo decide el orden dentro de un mismo tipo. '
    + 'Cada uno entra solo si su techo coincide con el del contrato; los de «Todos los techos» entran siempre. '
    + 'El dosier nunca va en el contrato.';
  // clave de grupo (ordenable): el tipo en el orden del contrato. Las flechas solo mueven dentro del mismo.
  function letraDe(tipo) { var R = reglaDocs(); return R ? ('0' + R.grupo(tipo)).slice(-2) : '99'; }
  function rotuloDe(tipo) { return tipo === 'plano' ? 'Apéndice A' : 'Informativo'; }
  /* Marcados en el orden en que salen en el contrato: por tipo y, dentro, por el orden de Modelos. */
  function porLetra(lista, tipoDe) {
    return lista.map(function (x, i) { return { x: x, i: i }; }).sort(function (a, b) {
      var la = letraDe(tipoDe(a.x)), lb = letraDe(tipoDe(b.x));
      return la < lb ? -1 : la > lb ? 1 : a.i - b.i;
    }).map(function (o) { return o.x; });
  }
  function reglaDocs() { return window.lwDocsContrato; }
  function tipoLbl(t) { var R = reglaDocs(); return R ? R.etiqueta(t) : t; }
  function nomTecho(h, clave) {
    if (!clave) return 'Todos los techos';
    return (h.techos.filter(function (t) { return t.clave === clave; })[0] || { nombre: clave }).nombre;
  }
  function subtitulo(host, texto) {
    var t = document.createElement('h4'); t.className = 'fm-lbl'; t.style.margin = '6px 0 0'; t.textContent = texto; host.appendChild(t); return t;
  }
  /* Resumen por techo de lo que adjuntará el contrato. `docs` = estado (el de la base o
     el que se está editando). Devuelve true si algún techo (o el modelo) sale sin anexo. */
  function resumenContrato(host, h, docs) {
    var R = reglaDocs(); if (!R) return;
    // Solo los techos que se ofrecen (30-sep-2026): un retirado no sale en contratos nuevos, no le falta anexo.
    var vivos = h.techos.filter(function (t) { return t.activo !== false; });
    var techos = vivos.length ? vivos.map(function (t) { return [t.clave, t.nombre]; }) : [['', '']];
    techos.forEach(function (t) {
      var entran = R.apendices(docs, t[0]);
      var p = document.createElement('p'); p.className = 'fm-nota' + (entran.length ? '' : ' fm-ambar');
      var pre = t[1] ? t[1] + ': ' : '';
      p.textContent = entran.length
        ? pre + entran.map(function (ap) { return ap.letra + '. ' + (ap.doc.nombre || 'Documento'); }).join(' · ')
        : (t[1] ? pre + 'nada marcado. El contrato saldrá sin anexo.' : 'Nada marcado: el contrato saldrá sin anexo.');
      host.appendChild(p);
    });
  }
  /* Fila de un documento en la VISTA: dos líneas (nombre; tipo · techo · fecha · cliente),
     abre el fichero al pulsarla (lo delega editores.js en #d-docs). */
  function filaDoc(h, d, ctx, letra) {
    var f = document.createElement('div');
    f.style.cssText = 'display:flex;flex-direction:column;gap:2px;min-height:40px;box-sizing:border-box;justify-content:center;padding:7px 10px;border-radius:10px;background:' + C.crema + ';cursor:pointer;min-width:0';
    if (d.path) { f.setAttribute('data-doc-abrir', ''); f.setAttribute('data-doc-path', d.path); f.setAttribute('role', 'button'); f.tabIndex = 0; }
    var a = document.createElement('span'); a.setAttribute('data-lw', 'doc-titulo');
    a.style.cssText = 'font-size:13.5px;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap';
    a.textContent = d.nombre || 'Documento';
    a.title = d.nombre || '';
    var z = document.createElement('span'); z.setAttribute('data-lw', 'doc-meta');
    z.style.cssText = 'font-size:12px;color:' + C.apagado;
    var partes = [];
    if (letra) partes.push(letra + ' · ' + tipoLbl(d.tipo));
    if (h.techos.length) partes.push('Techo: ' + nomTecho(h, d.techo_clave));
    partes.push('subido ' + ctx.fFecha(d.subido_en));
    if (d.visible_portal) partes.push('Lo ve el cliente');
    z.textContent = partes.join(' · ');
    f.appendChild(a); f.appendChild(z);
    return f;
  }
  /* Reparto en las tres secciones. `docs` son filas {…, en_contrato, tipo}. */
  function reparte(docs) {
    var R = reglaDocs();
    var marcados = R ? R.ordena(docs.filter(function (d) { return d.en_contrato === true; })) : [];
    var resto = docs.filter(function (d) { return d.en_contrato !== true; });
    return {
      marcados: marcados,
      dosier: resto.filter(function (d) { return d.tipo === 'dosier'; }),
      otros: resto.filter(function (d) { return d.tipo !== 'dosier'; })
    };
  }

  function bDocs(col, m, h, ctx) {
    var R = reglaDocs();
    var b = bloque(col, 'docs', 'Documentos', { puede: true, editar: (h.docs.length && R) ? function (host) { return editorDocs(host, m, h, ctx); } : null });
    var caja = contenedorFijo('d-docs');
    caja.style.gap = '8px';
    b.cuerpo.appendChild(caja);
    // Sin la regla no se puede decir qué va en el contrato: «no he podido mirar» se ve distinto de «no hay».
    if (!R) { nota(caja, 'No se ha podido cargar qué documentos van en el contrato (docs_contrato.js). Recarga la página.', 'rojo'); return; }
    if (!h.docs.length) { vacio(caja, 'Ningún documento. Súbelos con «Añadir documento».'); return; }
    var s = reparte(h.docs);

    subtitulo(caja, 'Van en el contrato');
    nota(caja, TXT_CONTRATO);
    if (!s.marcados.length) nota(caja, 'Este modelo no tiene nada marcado para el contrato: el contrato de Construcción saldrá sin anexo.', 'ambar');
    else {
      if (h.techos.length) resumenContrato(caja, h, h.docs);
      porLetra(s.marcados, function (d) { return d.tipo; }).forEach(function (d) { caja.appendChild(filaDoc(h, d, ctx, rotuloDe(d.tipo))); });
    }

    subtitulo(caja, 'Dosier');
    if (!s.dosier.length) vacio(caja, 'Sin dosier. Súbelo con «Añadir documento».');
    s.dosier.forEach(function (d) { caja.appendChild(filaDoc(h, d, ctx)); });

    subtitulo(caja, 'Otros documentos');
    if (!s.otros.length) vacio(caja, 'Ninguno.');
    R.TIPOS.forEach(function (t) {
      if (t[0] === 'dosier') return;
      var grupo = s.otros.filter(function (d) { return d.tipo === t[0]; });
      if (!grupo.length) return;   // los grupos vacíos no se pintan
      var g = document.createElement('p'); g.className = 'fm-nota'; g.style.fontWeight = '600'; g.textContent = t[1];
      caja.appendChild(g);
      grupo.forEach(function (d) { caja.appendChild(filaDoc(h, d, ctx)); });
    });
  }

  /* EDITAR. Cada fila: casilla, tipo, techo, ↑/↓ (solo en «Van en el contrato») y Borrar
     (solo admin). Al marcar o desmarcar, la fila cambia de sección EN VIVO y el resumen por
     techo se recalcula antes de guardar. Guardar manda TODOS los cambios en una llamada
     (modelo_documentos_guarda): el servidor los aplica en una transacción y en el orden que
     no choca con su regla de «un plano marcado por techo»; si algo falla, no queda nada
     aplicado. */
  function editorDocs(host, m, h, ctx) {
    var R = reglaDocs();
    var filas = h.docs.map(function (d) {
      return { d: d, en: d.en_contrato === true, tipo: d.tipo, techo: d.techo_clave || '', el: null };
    });
    // orden de partida: los marcados en su orden, luego el resto
    var orden = R.ordena(h.docs.filter(function (d) { return d.en_contrato === true; })).map(function (d) { return d.id; });
    var marcadas = function () {
      return orden.map(function (id) { return filas.filter(function (r) { return r.d.id === id; })[0]; }).filter(function (r) { return r && r.en; });
    };
    // en el orden en que salen en el contrato: por letra y, dentro, por el orden de la lista
    var marcadasLetra = function () { return porLetra(marcadas(), function (r) { return r.tipo; }); };
    var estado = function () {
      var pos = {}; marcadasLetra().forEach(function (r, i) { pos[r.d.id] = i + 1; });
      return filas.map(function (r) {
        return { id: r.d.id, nombre: r.d.nombre, tipo: r.tipo, techo_clave: r.techo || null, en_contrato: r.en, orden: pos[r.d.id] || 0, subido_en: r.d.subido_en };
      });
    };

    var resumen = document.createElement('div'); resumen.style.cssText = 'display:flex;flex-direction:column;gap:4px';
    var secC = document.createElement('div'), secD = document.createElement('div'), secO = document.createElement('div');
    [secC, secD, secO].forEach(function (s) { s.style.cssText = 'display:flex;flex-direction:column;gap:8px;min-width:0'; });
    subtitulo(host, 'Van en el contrato');
    nota(host, TXT_CONTRATO);
    host.appendChild(resumen); host.appendChild(secC);
    subtitulo(host, 'Dosier'); host.appendChild(secD);
    subtitulo(host, 'Otros documentos'); host.appendChild(secO);
    if (!EST.admin) nota(host, SOLO_ADMIN + ': la casilla, el orden y el tipo o el techo de lo que va en el contrato los cambia administración.');

    function montaFila(r) {
      var f = document.createElement('div');
      f.style.cssText = 'display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:10px;border-radius:10px;background:' + C.crema + ';min-width:0';
      var n = document.createElement('span');
      n.style.cssText = 'flex:1 1 100%;min-width:0;font-size:13.5px;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap';
      n.title = r.d.nombre || '';
      f.appendChild(n);
      var cas = casilla(f, 'Se incluye automáticamente en el contrato', r.en);
      cas.parentNode.style.flex = '1 1 100%';
      cas.parentNode.style.minHeight = '40px'; cas.parentNode.style.alignItems = 'center';
      var s = document.createElement('select'); s.className = 'fm-in'; s.setAttribute('aria-label', 'Tipo de documento');
      s.style.flex = '1 1 180px';
      var esPlano = r.d.tipo === 'plano';
      R.TIPOS.forEach(function (t) {
        // el plano sigue siendo de administración (regla del 25-sep que conserva el servidor)
        if (t[0] === 'plano' && !EST.admin && !esPlano) return;
        var o = document.createElement('option'); o.value = t[0]; o.textContent = t[1]; if (r.tipo === t[0]) o.selected = true; s.appendChild(o);
      });
      f.appendChild(s);
      var t = null;
      if (h.techos.length) {
        t = document.createElement('select'); t.className = 'fm-in'; t.setAttribute('aria-label', 'Techo del documento');
        t.style.flex = '1 1 150px';
        [['', 'Todos los techos']].concat(h.techos.map(function (x) { return [x.clave, x.nombre]; })).forEach(function (o) {
          var e = document.createElement('option'); e.value = o[0]; e.textContent = o[1]; if (r.techo === o[0]) e.selected = true; t.appendChild(e);
        });
        f.appendChild(t);
      }
      var sube = document.createElement('button'), baja = document.createElement('button');
      [[sube, '↑', 'Subir en el orden del contrato'], [baja, '↓', 'Bajar en el orden del contrato']].forEach(function (x) {
        x[0].type = 'button'; x[0].className = 'sui-btn'; x[0].textContent = x[1]; x[0].setAttribute('aria-label', x[2]); x[0].setAttribute('data-real', '');
        x[0].style.cssText = 'min-width:40px;min-height:40px;padding:0 12px';
        f.appendChild(x[0]);
      });
      var borra = null;
      if (EST.admin) {
        borra = document.createElement('button'); borra.type = 'button'; borra.setAttribute('data-real', '');
        borra.style.cssText = 'margin-left:auto;min-height:40px;border:0;background:none;padding:0 4px;font-weight:600;font-size:12.5px;font-family:inherit;color:' + C.rojo + ';text-decoration:underline;cursor:pointer';
        borra.textContent = 'Borrar';
        borra.addEventListener('click', function (ev) {
          ev.stopPropagation();
          if (typeof window.lwBorraDocModelo === 'function') window.lwBorraDocModelo(r.d.id);
        });
        f.appendChild(borra);
      }
      r.el = f; r.n = n; r.cas = cas; r.s = s; r.t = t; r.sube = sube; r.baja = baja;
      cas.addEventListener('change', function () {
        r.en = cas.checked;
        orden = orden.filter(function (id) { return id !== r.d.id; });
        if (r.en) orden.push(r.d.id);          // al marcar, entra el último
        repinta();
      });
      s.addEventListener('change', function () {
        r.tipo = s.value;
        // el dosier nunca va en el contrato: si se retipa a dosier, sale de «Van en el contrato»
        if (r.tipo === 'dosier' && r.en) { r.en = false; cas.checked = false; orden = orden.filter(function (id) { return id !== r.d.id; }); }
        repinta();
      });
      if (t) t.addEventListener('change', function () { r.techo = t.value; repinta(); });
      sube.addEventListener('click', function (ev) { ev.stopPropagation(); mueve(r, -1); });
      baja.addEventListener('click', function (ev) { ev.stopPropagation(); mueve(r, 1); });
    }
    // ↑/↓ solo dentro de la misma letra: el orden nunca cambia la letra
    function mueve(r, paso) {
      var ms = marcadasLetra().map(function (x) { return x.d.id; });
      var i = ms.indexOf(r.d.id), j = i + paso;
      if (i < 0 || j < 0 || j >= ms.length) return;
      var vecino = filas.filter(function (x) { return x.d.id === ms[j]; })[0];
      if (!vecino || letraDe(vecino.tipo) !== letraDe(r.tipo)) return;
      var tmp = ms[i]; ms[i] = ms[j]; ms[j] = tmp;
      orden = ms.concat(orden.filter(function (id) { return ms.indexOf(id) === -1; }));
      repinta();
      try { r.el.querySelector(paso < 0 ? '[aria-label^="Subir"]' : '[aria-label^="Bajar"]').focus(); } catch (e) {}
    }
    function repinta() {
      var ms = marcadasLetra();
      [secC, secD, secO].forEach(function (s) { while (s.firstChild) s.removeChild(s.firstChild); });
      resumen.innerHTML = '';
      var st = estado();
      if (!ms.length) nota(resumen, 'Este modelo no tiene nada marcado para el contrato: el contrato de Construcción saldrá sin anexo.', 'ambar');
      else resumenContrato(resumen, h, st);
      var dup = planosRepetidos(st);
      if (dup) nota(resumen, dup, 'rojo');
      ms.forEach(function (r, i) {
        r.n.textContent = rotuloDe(r.tipo) + ' · ' + (r.d.nombre || 'Documento');
        secC.appendChild(r.el);
      });
      filas.forEach(function (r) {
        var bloqueada = !EST.admin && (r.d.en_contrato === true || r.d.tipo === 'plano');
        var esDosier = r.tipo === 'dosier';
        r.cas.disabled = !EST.admin || esDosier;
        r.s.disabled = bloqueada; if (r.t) r.t.disabled = bloqueada;
        [r.s, r.t].forEach(function (x) { if (x) x.title = x.disabled ? SOLO_ADMIN : ''; });
        r.cas.title = esDosier ? DOSIER_NO : (r.cas.disabled ? SOLO_ADMIN : '');
        r.cas.parentNode.title = r.cas.title;
        var i = ms.indexOf(r);
        var mismaLetra = function (k) { return k >= 0 && k < ms.length && letraDe(ms[k].tipo) === letraDe(r.tipo); };
        r.sube.style.display = r.baja.style.display = r.en ? '' : 'none';
        r.sube.disabled = !EST.admin || !mismaLetra(i - 1);
        r.baja.disabled = !EST.admin || i < 0 || !mismaLetra(i + 1);
        [r.sube, r.baja].forEach(function (x) { x.style.opacity = x.disabled ? '.45' : ''; x.title = !EST.admin ? SOLO_ADMIN : ''; });
        if (r.en) return;
        r.n.textContent = r.d.nombre || 'Documento';
        (r.tipo === 'dosier' ? secD : secO).appendChild(r.el);
      });
      if (!secC.firstChild) vacio(secC, 'Nada marcado.');
      if (!secD.firstChild) vacio(secD, 'Sin dosier. Súbelo con «Añadir documento».');
      if (!secO.firstChild) vacio(secO, 'Ninguno.');
    }
    // Dos planos marcados del mismo techo: el servidor lo rechaza (un plano por techo). Se dice antes.
    function planosRepetidos(st) {
      var vistos = {}, malos = [];
      st.forEach(function (d) {
        if (!d.en_contrato || d.tipo !== 'plano') return;
        var k = d.techo_clave || '';
        if (vistos[k] && malos.indexOf(k) === -1) malos.push(k);
        vistos[k] = 1;
      });
      if (!malos.length) return '';
      return 'Hay más de un plano marcado para ' + malos.map(function (k) { return k ? nomTecho(h, k) : '«Todos los techos»'; }).join(' y ')
        + ': el contrato solo admite uno por techo. Desmarca uno.';
    }
    filas.forEach(montaFila);
    repinta();

    return function () {
      var st = estado();
      var dup = planosRepetidos(st);
      if (dup) throw new Error(dup);
      var porId = {}; st.forEach(function (x) { porId[x.id] = x; });
      var cambios = [];
      filas.forEach(function (r) {
        var ahora = porId[r.d.id], antes = r.d, c = {};
        if (ahora.tipo !== antes.tipo) c.tipo = ahora.tipo;
        if ((ahora.techo_clave || '') !== (antes.techo_clave || '')) c.techo_clave = ahora.techo_clave;
        // casilla y orden: solo administración (quien no lo es ni puede tocarlos, y un orden con huecos
        // —1, 3 tras desmarcar el 2— no puede colarse en su guardado como «cambio de orden»)
        if (EST.admin && ahora.en_contrato !== (antes.en_contrato === true)) c.en_contrato = ahora.en_contrato;
        if (EST.admin && ahora.en_contrato && ahora.orden !== antes.orden) c.orden = ahora.orden;
        // un marcado que se retoca (tipo o techo) el servidor lo desmarca y lo vuelve a marcar: lleva su
        // orden explícito, o volvería el último
        if (EST.admin && ahora.en_contrato && antes.en_contrato === true && (c.tipo !== undefined || c.techo_clave !== undefined)) c.orden = ahora.orden;
        if (Object.keys(c).length) cambios.push({ id: r.d.id, cambios: c });
      });
      if (!cambios.length) return Promise.resolve();
      /* UNA llamada, UNA transacción (revisor de código, 28-sep-2026): antes eran N llamadas sueltas y
         un fallo a medias dejaba el modelo entre el estado viejo y el nuevo. El ORDEN de aplicación
         (desmarcar, retipar, reordenar, marcar) lo decide el servidor, y cualquier error lo deshace todo. */
      return rpc(ctx.sb, 'modelo_documentos_guarda', { p_modelo: m.id, p_cambios: cambios });
    };
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
      p.textContent = 'Los datos del modelo, y qué documentos van en el contrato, los edita administración. Tú puedes subir documentos y cambiar el tipo o el techo de los que no van en el contrato.';
      raiz.insertBefore(p, raiz.firstChild);
    }
  }

  window.lwFichaModelo = { pintar: pintar };
})();
