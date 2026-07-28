/* ════════════════════════════════════════════════════════════
   Lawang — Property Card render (FUENTE ÚNICA compartida)
   window.LawangCard.render(p, opts) -> HTML string de una .lw-prop
   opts: { lang:'en'|'es', cur:'EUR'|'USD'|'AUD', rates:{...}, hrefBase:'', imgBase:'' }
   Independiente del stack: lo usan index.html y thecollection.html.
   ════════════════════════════════════════════════════════════ */
(function () {
  var LINE_CREAM = { signature:'cream-signature', land:'cream-land', villa:'cream-villas', resorts:'cream-resorts' };
  var LINE_LABEL = {
    signature:{ en:'Signature', es:'Signature' },
    land:     { en:'Land',      es:'Terrenos' },
    villa:    { en:'Villas',    es:'Villas' },
    resorts:  { en:'Resorts',   es:'Resorts' }
  };
  var TENURE = { 'tenure.leasehold':{ en:'Leasehold', es:'Leasehold' }, 'tenure.freehold':{ en:'Freehold', es:'Freehold' } };
  var STATUS = {
    'status.offplan':      { c:'plan',   en:'Off-plan',          es:'En plano' },
    'status.land':         { c:'plan',   en:'Titled land',       es:'Terreno titulado' },
    'status.ready':        { c:'built',  en:'Built',             es:'Construida' },
    'status.construction': { c:'constr', en:'Under construction',es:'En construcción' }
  };
  var VIEW_LABEL = {
    beach:    { en:'Beachfront', es:'Frente al mar' },
    cliff:    { en:'Clifftop',   es:'Acantilado' },
    jungle:   { en:'Jungle',     es:'Selva' },
    ricefield:{ en:'Rice fields',es:'Arrozales' },
    river:    { en:'Riverside',  es:'Río' }
  };
  var SYMS = { EUR:'€', USD:'$', AUD:'A$', IDR:'Rp ' };
  var DEFAULT_RATES = { EUR:1, USD:1.08, AUD:1.65, IDR:17500 };
  // Iconos de specs (área construida / dormitorios / parcela)
  var ICO_AREA = '<svg class="lw-mi" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/></svg>';
  var ICO_BED  = '<svg class="lw-mi" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M3 18v-6a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v6M3 18h18M3 20v-2M21 20v-2M6 10V8a2 2 0 0 1 2-2h3v4"/></svg>';
  var ICO_LAND = '<svg class="lw-mi" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3 3 8l9 5 9-5-9-5ZM3 16l9 5 9-5"/></svg>';

  function themeFor(p) {
    if (p.regionKey === 'sumba') return p.line === 'land' ? 'ocean' : 'sand';
    if (p.line === 'resorts') return 'dusk';
    if (p.line === 'land') return 'jungle';
    return 'sunset';
  }
  // Vista de la propiedad: si el admin la fijó (p.view) se respeta; si está en
  // "Auto" se infiere del texto de la propiedad.
  function viewFor(p) {
    if (p.view && VIEW_LABEL[p.view]) return p.view;
    var s = (((p.sub && p.sub.en) || '') + ' ' + ((p.desc && p.desc.en) || '') + ' ' + ((p.title && p.title.en) || '')).toLowerCase();
    if (/clifftop|cliff|bluff/.test(s)) return 'cliff';
    if (/rivermouth|riverside|river|valley/.test(s)) return 'river';
    if (/beachfront|beach|surf|seafront|ocean/.test(s)) return 'beach';
    if (/rice|paddy/.test(s)) return 'ricefield';
    return 'jungle';
  }
  function money(eur, cur, rates) {
    rates = rates || DEFAULT_RATES;
    var v = Math.round((eur || 0) * (rates[cur] || 1));
    return (SYMS[cur] || '€') + v.toLocaleString('en-US');
  }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) {
      return { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;' }[c];
    });
  }
  function imgUrl(k) {
    return (typeof k === 'string' && /^(https?:|\/|\.)/.test(k)) ? k : null;
  }
  function pick(obj, lang) { return obj ? (obj[lang] || obj.en) : ''; }

  function render(p, opts) {
    opts = opts || {};
    var lang = opts.lang || 'en';
    var cur = opts.cur || 'EUR';
    var rates = opts.rates || DEFAULT_RATES;
    var base = opts.hrefBase != null ? opts.hrefBase : '';   // '' = misma página (portfolio); '/thecollection' = index
    var href = base + '#property/' + esc(p.id);
    var ten = (TENURE[p.tenure] || TENURE['tenure.freehold']);
    var st = STATUS[p.status] || { c:'plan', en:'', es:'' };
    var creamIco = LINE_CREAM[p.line] || 'cream-signature';
    var lineLabel = pick(LINE_LABEL[p.line], lang);
    var view = viewFor(p);
    var keys = (p.imgKeys && p.imgKeys.length) ? p.imgKeys : (p.images || []);
    var img0 = keys.length ? imgUrl(keys[0]) : null;

    // Specs con icono: área construida · dormitorios · parcela
    var meta = '';
    if (p.built > 0) meta += '<span class="lw-m">' + ICO_AREA + '<b>' + p.built + '</b> m²</span>';
    if (p.beds  > 0) meta += '<span class="lw-m">' + ICO_BED + '<b>' + p.beds + '</b> ' + (lang === 'es' ? 'hab' : (p.beds > 1 ? 'rooms' : 'room')) + '</span>';
    var extra = p.metaText ? (typeof p.metaText === 'string' ? p.metaText : pick(p.metaText, lang))
                           : (p.land > 0 ? p.land + ' m² ' + (lang === 'es' ? 'parcela' : 'land') : '');
    if (extra) meta += '<span class="lw-m lw-m-txt">' + ICO_LAND + esc(extra) + '</span>';

    var fromTxt = lang === 'es' ? 'Desde' : 'From';

    // Ubicación en dos tonos (guía): "SOUTH BUWIT," bold + "TABANAN" ligero
    var region = String(p.region || '');
    var ci = region.indexOf(',');
    var locHTML = ci >= 0 ? '<b>' + esc(region.slice(0, ci + 1)) + '</b> ' + esc(region.slice(ci + 1).trim())
                          : '<b>' + esc(region) + '</b>';

    return '<article class="lw-prop"><a href="' + href + '">'
      + '<div class="lw-prop-media ph-' + themeFor(p) + '">'
      + (img0 ? '<img class="lw-prop-img" src="' + esc(img0) + '" alt="" loading="lazy" onerror="this.remove()">' : '')
      + '<span class="lw-prop-view"><img src="assets/img/' + view + '-ico.png" alt="" loading="lazy">' + esc(pick(VIEW_LABEL[view], lang)) + '</span>'
      + '<span class="lw-prop-line"><img class="lw-line-ico" src="assets/img/' + creamIco + '.png" alt="" loading="lazy">' + esc(lineLabel) + '</span></div>'
      + '<div class="lw-prop-body">'
      + '<div class="lw-prop-pills">' + (p.tenure ? '<span class="pf-pill ten">' + esc(ten[lang] || ten.en) + '</span>' : '')
      + ((st[lang] || st.en) ? '<span class="pf-pill ' + st.c + '">' + esc(st[lang] || st.en) + '</span>' : '') + '</div>'
      + '<span class="lw-prop-loc">' + locHTML + '</span>'
      + '<h3 class="lw-prop-title">' + esc(pick(p.title, lang)) + '</h3>'
      + '<p class="lw-prop-sub">' + esc(pick(p.sub, lang)) + '</p>'
      + '<div class="lw-prop-meta">' + meta + '</div>'
      + '<div class="lw-prop-foot"><span class="lw-prop-price">' + (p.priceEUR > 0 ? '<span class="from">' + fromTxt + '</span>' + money(p.priceEUR, cur, rates) : (lang === 'es' ? 'Consultar precio' : 'Price on request')) + '</span></div></div></a></article>';
  }

  window.LawangCard = { render: render, themeFor: themeFor, money: money, viewFor: viewFor, VIEW_LABEL: VIEW_LABEL };
})();
