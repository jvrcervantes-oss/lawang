/**
 * Motor compartido del configurador villa -> techo -> extras, para paginas de PRODUCTO
 * (/dali y /modelo/<id>) — nacido 14-sep-2026 al copiar el diseno y estructura de
 * /palmfield a las fichas de modelo (encargo del owner). Es el mismo motor de tres pasos
 * que /palmfield estreno el 7-sep (ver el docblock de palmfield/index.php), adaptado a
 * dos cosas que las paginas de producto SI tienen y la landing de campana no:
 *   - Selector de divisa de 4 monedas en la barra (EUR/USD/AUD/IDR, lw_divisas()),
 *     no el toggle AUD/EUR de 2 botones dentro de la tarjeta.
 *   - CTA = WhatsApp con la configuracion en el texto, no "Book a Call" (las paginas de
 *     producto dejaron de agendar el 11-sep-2026).
 * /palmfield NO carga este fichero: su motor sigue vivo en su propio <script>, con su
 * propio toggle y su propia tarjeta de reserva — no se toca.
 *
 * Recibe el catalogo YA resuelto por PHP (lw_au_catalogo(), modelo/datos.php) y solo
 * pinta: ningun precio se calcula aqui. Un objeto de opciones por pagina; nada de estado
 * global entre dali y modelo.
 */
window.lwAuCfgInit = function (opts) {
  'use strict';
  var CFG      = opts.cfg;               // {tasaAud, divisas, divFecha, modelos:{id:{...}}}
  var WA_NUM   = opts.waNum;
  var urlBase  = opts.urlBase;           // '/dali' o '/modelo/dune' — el path NUNCA lo mueve esto
  var villaDef = opts.villaDefault;
  var waIntro  = opts.waIntro;           // "Hi, I'd like information about "

  function $(id) { return document.getElementById(id); }
  function txt(id, s) { var e = $(id); if (e) e.textContent = s; }

  var S = {villa: villaDef, techo: 'sirap', extras: {}, div: 'EUR'};
  try { var _g = localStorage.getItem('lw_deck_cur'); if (CFG.divisas[_g]) S.div = _g; } catch (e) {}
  // 22-sep-2026: `opts.ocultarVilla` — en una ficha de UN modelo, elegir OTRA villa desde
  // dentro del propio configurador no aplica (para eso está "More from the collection").
  // /dali no manda esta opción y sigue con sus 3 pasos de siempre. STEPS traduce el índice
  // visible (1..N, lo que ve el usuario) al data-paso real del HTML (que no cambia).
  // Isla/ubicación de parcela/extras pasan a ser 3 pasos propios (antes uno solo).
  var STEPS = opts.ocultarVilla ? [2, 3, 4, 5] : [1, 2, 3];
  var PASOS = STEPS.length, paso = 1;

  function eur(n) { return '€' + Number(n).toLocaleString('en-US'); }
  function divFmt(n, cod) {
    var d = (CFG.divisas || {})[cod];
    if (!d) return eur(n);
    var v = Number(n) * d.tasa;
    v = cod === 'IDR' ? Math.round(v / 1000) * 1000 : Math.round(v / 10) * 10;
    return d.sim + v.toLocaleString('en-US');
  }
  function pinta(n) { return divFmt(n, S.div); }
  // El euro (moneda del contrato) siempre debajo, salvo que ya se este mostrando en euros.
  function alterna(n) { return S.div === 'EUR' ? '' : eur(n); }

  function modelo() { return CFG.modelos[S.villa] || null; }
  function techoActivo() {
    var m = modelo();
    if (!m) return null;
    return m.techos[S.techo] || m.techos.sirap || null;
  }
  function precioVilla() {
    var t = techoActivo();
    return t ? t.eur : 0;
  }
  function extrasElegidos() {
    var m = modelo(), out = [];
    if (!m) return out;
    (m.extras || []).forEach(function (x) { if (S.extras[x.id]) out.push(x); });
    return out;
  }

  function pintaTechos() {
    var m = modelo(), cont = $('lw-techos');
    if (!m || !cont) return;
    var base = Math.min.apply(null, ['sirap', 'bambu']
      .filter(function (k) { return m.techos[k]; })
      .map(function (k) { return m.techos[k].eur; }));
    cont.innerHTML = '';
    ['sirap', 'bambu'].forEach(function (k) {
      var t = m.techos[k];
      if (!t) return;
      var d = t.eur - base;
      var l = document.createElement('label');
      l.className = 'op';
      l.innerHTML =
        '<input type="radio" name="lw-techo" value="' + k + '"' + (k === S.techo ? ' checked' : '') + '>' +
        '<span><span class="op__nb"></span></span>' +
        (d ? '<span class="op__pr" data-eur="' + d + '"><b></b><i></i></span>'
           : '<span class="op__pr"><b>Included</b></span>');
      l.querySelector('.op__nb').textContent = t.nombre;
      if (d) {
        l.querySelector('b').textContent = '+ ' + pinta(d);
        l.querySelector('i').textContent = '+ ' + alterna(d);
      }
      cont.appendChild(l);
    });
  }
  function pintaExtras() {
    var m = modelo(), cont = $('lw-extras');
    if (!m || !cont) return;
    cont.innerHTML = '';
    (m.extras || []).forEach(function (x) {
      var l = document.createElement('label');
      l.className = 'op';
      l.innerHTML =
        '<input type="checkbox" name="lw-extra" value="' + x.id + '"' + (S.extras[x.id] ? ' checked' : '') + '>' +
        '<span><span class="op__nb"></span><span class="op__sp"></span></span>' +
        '<span class="op__pr" data-eur="' + x.eur + '"><b></b><i></i></span>';
      l.querySelector('.op__nb').textContent = x.nombre;
      l.querySelector('.op__sp').textContent = x.desc || '';
      l.querySelector('b').textContent = '+ ' + pinta(x.eur);
      l.querySelector('i').textContent = '+ ' + alterna(x.eur);
      cont.appendChild(l);
    });
  }

  function muestraPaso(n) {
    paso = n;
    var real = STEPS[n - 1];
    document.querySelectorAll('.cfg__step').forEach(function (s) {
      s.hidden = Number(s.getAttribute('data-paso')) !== real;
    });
    txt('lw-paso-lb', 'Step ' + n + ' of ' + PASOS);
    var a = $('lw-atras'); if (a) a.hidden = n === 1;
    var sig = $('lw-siguiente');
    if (sig && sig.firstChild) sig.firstChild.textContent = n === PASOS ? 'See my figure ' : 'Next ';
    var p = $('lw-puntos');
    if (p) {
      p.innerHTML = '';
      for (var i = 1; i <= PASOS; i++) {
        var d = document.createElement('span');
        d.className = 'punto' + (i === n ? ' is-on' : '');
        p.appendChild(d);
      }
    }
  }
  function avanza(dir) {
    var n = paso + dir;
    if (n < 1) n = 1;
    if (n > PASOS) {
      var r = document.querySelector('.res');
      if (r) r.scrollIntoView({behavior: 'smooth', block: 'center'});
      return;
    }
    muestraPaso(n);
  }
  var sigB = $('lw-siguiente'); if (sigB) sigB.addEventListener('click', function () { avanza(1); });
  var atrB = $('lw-atras');     if (atrB) atrB.addEventListener('click', function () { avanza(-1); });

  function recalcular() {
    var m = modelo();
    if (!m) return;
    var t   = techoActivo();
    var pv  = precioVilla();
    var els = extrasElegidos();
    var pe  = 0;
    els.forEach(function (x) { pe += x.eur; });
    var total = pv + pe;

    txt('lw-r-villa', m.villa);
    txt('lw-r-villa-sub', (t ? t.nombre + ' roof · ' : '') + m.specs);
    txt('lw-r-villa-pr', pinta(pv));
    txt('lw-r-extras', els.length ? 'Extras (' + els.length + ')' : 'Extras');
    txt('lw-r-extras-sub', els.length
      ? els.map(function (x) { return x.nombre; }).join(', ')
      : 'None selected');
    txt('lw-r-extras-pr', els.length ? pinta(pe) : '—');
    txt('lw-total', pinta(total));
    var alt = alterna(total);
    txt('lw-total-alt', alt ? '≈ ' + alt : '');
    txt('lw-movil-pr', pinta(total));

    document.querySelectorAll('.cfg .op__pr[data-eur]').forEach(function (nodo) {
      var v   = Number(nodo.getAttribute('data-eur'));
      var mas = (nodo.closest('#lw-extras') || nodo.closest('#lw-techos')) ? '+ ' : '';
      var b   = nodo.querySelector('b'), i = nodo.querySelector('i');
      if (b) b.textContent = mas + pinta(v);
      if (i) i.textContent = mas + alterna(v);
    });
    // Precio fijo pintado por PHP (chip del hero, barra movil de entrada): lleva su valor
    // en euros en data-eur-fijo y se repinta desde ahi al cambiar de divisa. Atributo propio
    // a proposito — data-eur ya lo usa el configurador con otra estructura (un <b> y un <i>
    // que recalcular() repinta), y escribir textContent sobre esos nodos les borra los hijos.
    document.querySelectorAll('[data-eur-fijo]').forEach(function (el) {
      var v = parseFloat(el.getAttribute('data-eur-fijo'));
      if (!isNaN(v)) el.textContent = divFmt(v, S.div);
    });

    // Se PARTE de la query que ya hay y solo se borran las claves propias: barrerla entera
    // se llevaria utm_* y fbclid, que es de donde sale la atribucion de la campaña. El PATH
    // nunca se toca aqui — elegir otra villa en el configurador no navega a su ficha propia.
    var p = new URLSearchParams(location.search);
    ['villa', 'roof', 'extras', 'cur'].forEach(function (k) { p.delete(k); });
    if (S.villa !== villaDef) p.set('villa', S.villa);
    if (S.techo !== 'sirap')  p.set('roof', S.techo);
    if (els.length) p.set('extras', els.map(function (x) { return x.id; }).join(','));
    if (S.div !== 'EUR') p.set('cur', S.div);
    var q = p.toString();
    history.replaceState(history.state, '', urlBase + (q ? '?' + q : ''));

    var wt = waIntro + m.villa + '.'
           + (t ? ' ' + t.nombre + ' roof, ' + eur(pv) + '.' : '')
           + (els.length ? ' Extras: ' + els.map(function (x) { return x.nombre; }).join(', ') + '.' : '');
    var href = 'https://wa.me/' + WA_NUM + '?text=' + encodeURIComponent(wt);
    document.querySelectorAll('a[href*="wa.me/"]').forEach(function (a) { a.href = href; });
  }

  document.addEventListener('change', function (e) {
    var t = e.target;
    if (!t) return;
    if (t.type === 'radio') {
      if (t.name === 'lw-villa') { S.villa = t.value; pintaTechos(); pintaExtras(); }
      else if (t.name === 'lw-techo') {
        S.techo = t.value;
        // Hero cinematico (solo en paginas de producto que lo definen — /dali no lo tiene):
        // el techo bambu ensena la vista alternativa, sirap vuelve a la vista de dia real.
        if (window.lwSetView) window.lwSetView(t.value === 'bambu' ? 'roof' : 'day');
      }
      else { return; }
      recalcular();
      // 22-sep-2026: el techo YA NO avanza solo en paginas con foto cinematica
      // (lwSetView) — el visitante necesita poder alternar sirap/bambu para comparar
      // las dos fotos sin que el paso se cierre debajo. /dali no define lwSetView y
      // sigue avanzando solo al elegir techo, como pidio el owner el 7-sep-2026.
      var saltaSolo = t.name === 'lw-techo' && window.lwSetView;
      if (paso < PASOS && !saltaSolo) avanza(1);
      return;
    }
    if (t.type === 'checkbox' && t.name === 'lw-extra') {
      if (t.checked) S.extras[t.value] = true; else delete S.extras[t.value];
      recalcular();
    }
  });

  // ── Selector de divisa de la barra: 4 monedas, mismo componente que ya monto /dali
  //    el 11-sep-2026 (lw_divisas(), guardado en localStorage bajo 'lw_deck_cur', mismas
  //    clases .lw-lang__* que idioma-web.js — sale identico al del investor deck). ──────
  (function () {
    var host = document.getElementById('lw-div-sel');
    if (!host) return;
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'lw-lang__btn';
    btn.setAttribute('aria-haspopup', 'listbox');
    btn.setAttribute('aria-expanded', 'false');
    btn.setAttribute('aria-label', 'Currency');
    btn.innerHTML = '<span class="lw-lang__cur"></span><span class="lw-lang__caret" aria-hidden="true">▾</span>';
    var ul = document.createElement('ul');
    ul.className = 'lw-lang__menu';
    ul.setAttribute('role', 'listbox');
    Object.keys(CFG.divisas).forEach(function (c) {
      var li = document.createElement('li');
      li.setAttribute('role', 'option');
      li.setAttribute('data-div', c);
      li.textContent = c + '  ' + CFG.divisas[c].sim.trim();
      ul.appendChild(li);
    });
    host.appendChild(btn); host.appendChild(ul);

    function refleja() {
      btn.querySelector('.lw-lang__cur').textContent = S.div;
      Array.prototype.forEach.call(ul.children, function (li) {
        var on = li.getAttribute('data-div') === S.div;
        li.classList.toggle('is-on', on);
        li.setAttribute('aria-selected', on ? 'true' : 'false');
      });
    }
    function cierra() { ul.classList.remove('is-open'); btn.setAttribute('aria-expanded', 'false'); }
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var abierto = ul.classList.toggle('is-open');
      btn.setAttribute('aria-expanded', abierto ? 'true' : 'false');
    });
    ul.addEventListener('click', function (e) {
      var li = e.target.closest ? e.target.closest('li[data-div]') : null;
      if (!li) return;
      S.div = li.getAttribute('data-div');
      try { localStorage.setItem('lw_deck_cur', S.div); } catch (err) {}
      refleja(); cierra(); recalcular(); pintaTechos(); pintaExtras();
    });
    document.addEventListener('click', function (e) { if (!host.contains(e.target)) cierra(); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') cierra(); });
    refleja();
  }());

  // Estado desde la query (enlace compartible)
  var q  = new URLSearchParams(location.search);
  var vq = q.get('villa'); if (vq && CFG.modelos[vq]) S.villa = vq;
  var tq = q.get('roof');  if (tq === 'sirap' || tq === 'bambu') S.techo = tq;
  var cq = q.get('cur');   if (CFG.divisas[cq]) S.div = cq;
  var validos = {};
  ((CFG.modelos[S.villa] || {}).extras || []).forEach(function (x) { validos[x.id] = true; });
  (q.get('extras') || '').split(',').forEach(function (id) {
    if (validos[id]) S.extras[id] = true;
  });

  var rv = document.querySelector('input[name="lw-villa"][value="' + S.villa + '"]');
  if (rv) rv.checked = true;

  pintaTechos();
  pintaExtras();
  muestraPaso(1);
  recalcular();
  // Enlace compartido con ?roof=bambu: el hero arranca ya en la vista alternativa,
  // no solo el radio marcado.
  if (window.lwSetView && S.techo === 'bambu') window.lwSetView('roof');
};
