/* ════════════════════════════════════════════════════════════
   Lawang — Portfolio (marketplace + ficha) en VANILLA JS
   Port 1:1 de la antigua app React/Babel. Sin build, sin React.
   Re-render completo de #portfolio-root desde el estado S.
   La card de listado usa el módulo compartido window.LawangCard.
   ════════════════════════════════════════════════════════════ */
(function () {
  var L = window.LAWANG;
  var LINES = (L && L.LINES) || ["signature","land","villa","resorts"];
  var LINE_KEYS  = { signature:"line.signature", land:"line.land", villa:"line.villa", resorts:"line.resorts" };
  // Iconos de marca (PNG cream) — mismos que usa la card. En card inactiva (fondo bone)
  // se tiñen a Territorial Green vía filtro; en activa (fondo verde) van en cream original.
  var LINE_CREAM = { signature:"cream-signature", land:"cream-land", villa:"cream-villas", resorts:"cream-resorts" };
  var CREAM_TINT = "filter:brightness(0) saturate(100%) invert(28%) sepia(22%) saturate(560%) hue-rotate(50deg) brightness(94%) contrast(90%);";

  // Sin datos reales no se muestra el configurador — nunca precios inventados (auditoría 15-jul).

  // ── Estado global ──────────────────────────────────────────
  var S = {
    lang:"en", cur:"EUR",
    line:"all", region:"all", layout:"grid", langOpen:false, curOpen:false, page:1, featIdx:0,
    overlay:null,
    gallery:0, calcTable:false, dlUnlocked:false, dlEmail:"", dlErr:false,
    parcelIdx:-1, modelIdx:-1, extrasSel:{}, step:0
  };
  function resetDetail(){ S.gallery=0; S.lightbox=null; S.tab=0; S.tabImg=0; S.calcTable=false; S.dlUnlocked=false; S.dlEmail=""; S.dlErr=false; S.parcelIdx=-1; S.modelIdx=-1; S.extrasSel={}; S.step=0; }

  // ── Helpers ────────────────────────────────────────────────
  function t(key){ var e = L.DICT[key]; if(!e) return key; return (e[S.lang] != null ? e[S.lang] : e.en); }
  function money(eur, cur){ return L.money(eur, cur || S.cur); }
  function esc(s){ return String(s==null?"":s).replace(/[&<>"]/g,function(c){return {"&":"&amp;","<":"&lt;","&gt;":"&gt;",">":"&gt;","\"":"&quot;"}[c];}); }
  function pick(o){ return o ? (o[S.lang] || o.en) : ""; }
  function tl(en,es){ return S.lang==="es" ? es : en; }  // etiqueta bilingüe puntual (evita tocar el DICT por un string suelto)
  function firstImg(p){ return (p.imgKeys&&p.imgKeys[0]) || (p.images&&p.images[0]) || null; }
  function imgUrl(key,w){ return key ? (L.img ? L.img(key,w||1600) : key) : null; }
  function themeFor(p){ if(p.regionKey==="sumba") return p.line==="land"?"ocean":"sand"; if(p.line==="resorts") return "dusk"; if(p.line==="land") return "jungle"; return "sunset"; }
  // "FROM" en versalitas pequeñas — misma regla que la card (.lw-prop-price .from)
  function priceHTML(eur, from){ if(!eur) return '<span style="opacity:.7">'+t("mk.onrequest")+'</span>'; return (from?'<span style="font-size:.5em;font-weight:500;letter-spacing:.08em;text-transform:uppercase;opacity:.6;margin-right:8px">'+t("mk.from")+'</span>':'') + money(eur); }
  function statusPillStyle(s){
    if(s==="status.ready")        return "background:var(--clay);color:var(--bone);border-color:var(--clay)";
    if(s==="status.construction") return "background:var(--be);color:var(--bone);border-color:var(--be)";
    return "background:transparent;color:var(--ink-2);border-color:var(--line)";
  }
  function resolveLand(p){ return (p.landOptions && p.landOptions.length) ? p.landOptions : null; }
  function resolveHomes(p){ return (p.homeModels && p.homeModels.length) ? p.homeModels : null; }
  function resolveExtras(p){ return (p.extras && p.extras.length) ? p.extras : null; }
  function propById(id){ return L.PROPERTIES.find(function(x){return x.id===id;}); }

  // Placeholder de imagen (gradiente temático + img + tinte) — equivalente al <Ph> de React
  function ph(o){
    o = o || {};
    var theme = o.theme || "jungle";
    var url = o.src || (o.key ? L.img(o.key, o.w||1600) : null);
    var st = "position:relative;overflow:hidden;background:#2a2018;" + (o.ratio?("aspect-ratio:"+o.ratio+";"):"") + (o.style||"");
    var tint = (o.tint!=null?o.tint:0.18);
    var h = '<div class="ph '+(o.kb?"ph-kb ":"")+(url?"ph-photo":"ph-horizon")+'" style="'+st+'">';
    h += '<div class="ph-grad ph-'+theme+'"></div>';
    if(url) h += '<img class="ph-img" src="'+esc(url)+'" alt="'+esc(o.label||"")+'" loading="lazy" style="opacity:1" onerror="this.style.display=\'none\'">';
    if(url && tint>0) h += '<div class="ph-tint" style="background:linear-gradient(180deg,rgba(26,22,15,'+(tint*0.7)+') 0%,transparent 30%,transparent 55%,rgba(26,22,15,'+(tint*1.6)+') 100%)"></div>';
    if(o.label) h += '<div class="ph-label">'+o.label+'</div>';
    h += '</div>';
    return h;
  }

  // ════ TOPBAR ════
  // ghost=true → variante "fantasma" para la ficha: transparente sobre el hero, se colorea al scroll (JS)
  function topbarHTML(ghost){
    var waNum=(L.SETTINGS&&L.SETTINGS.whatsapp)||'6281138319862';
    // Mismo mensaje pre-rellenado que el CTA del index.html
    var waMsg='?text=Hello%20LAWANG%20%F0%9F%8C%BF%0A%0AI%27m%20exploring%20thoughtfully%20curated%20investment%20opportunities%20in%20Bali%20and%20would%20love%20to%20learn%20more%20about%20your%20current%20projects.%20%E2%9C%A8';
    var waUrl='https://wa.me/'+waNum+waMsg;
    var langName={en:'English',es:'Español',id:'Bahasa'}[S.lang]||'English';
    var nl=function(href,label,active){ return '<a class="nav-link'+(active?' active':'')+'" href="'+href+'">'+label+'</a>'; };
    // Moneda: mismo desplegable que el idioma (guía Ficha) — antes eran 3 botones segmentados
    var ci=function(code,sym){ return '<li role="option" data-act="cur:'+code+'"'+(S.cur===code?' class="active"':'')+'><span class="lang-opt"><span class="cur-sym">'+sym+'</span>'+code+'</span></li>'; };
    var li=function(code,flag,name){ return '<li role="option" data-act="lang:'+code+'"'+(S.lang===code?' class="active"':'')+'><span class="lang-opt">'+flag+name+'</span></li>'; };
    var flagEN='<svg class="flag" viewBox="0 0 60 36" aria-hidden="true"><rect width="60" height="36" fill="#012169"/><path d="M0,0 60,36 M60,0 0,36" stroke="#fff" stroke-width="7.2"/><path d="M0,0 60,36 M60,0 0,36" stroke="#C8102E" stroke-width="4"/><path d="M30,0 V36 M0,18 H60" stroke="#fff" stroke-width="12"/><path d="M30,0 V36 M0,18 H60" stroke="#C8102E" stroke-width="7.2"/></svg>';
    var flagES='<svg class="flag" viewBox="0 0 3 2" aria-hidden="true"><rect width="3" height="2" fill="#c60b1e"/><rect y=".5" width="3" height="1" fill="#ffc400"/></svg>';
    var flagID='<svg class="flag" viewBox="0 0 3 2" aria-hidden="true"><rect width="3" height="2" fill="#fff"/><rect width="3" height="1" fill="#ce1126"/></svg>';
    var wa='<span class="wa"><svg viewBox="0 0 24 24" fill="#fff" aria-hidden="true"><path d="M17.47 14.38c-.3-.15-1.76-.87-2.03-.97-.27-.1-.47-.15-.67.15-.2.3-.77.97-.94 1.17-.17.2-.35.22-.65.07-.3-.15-1.26-.46-2.4-1.48-.89-.79-1.49-1.77-1.66-2.07-.17-.3-.02-.46.13-.61.13-.13.3-.35.45-.52.15-.17.2-.3.3-.5.1-.2.05-.37-.02-.52-.07-.15-.67-1.62-.92-2.22-.24-.58-.49-.5-.67-.51l-.57-.01c-.2 0-.52.07-.8.37-.27.3-1.04 1.02-1.04 2.48 0 1.46 1.07 2.88 1.22 3.08.15.2 2.1 3.2 5.08 4.49.71.31 1.26.49 1.69.63.71.22 1.36.19 1.87.12.57-.09 1.76-.72 2.01-1.41.25-.7.25-1.29.17-1.41-.07-.12-.27-.2-.57-.35zM12.04 21.5h-.01a9.5 9.5 0 0 1-4.84-1.33l-.35-.2-3.6.94.96-3.51-.23-.36a9.49 9.49 0 0 1-1.45-5.05c0-5.24 4.27-9.5 9.52-9.5a9.46 9.46 0 0 1 9.51 9.51c0 5.24-4.27 9.5-9.51 9.5zM20.52 3.49A11.78 11.78 0 0 0 12.04 0C5.46 0 .1 5.36.1 11.94c0 2.1.55 4.16 1.6 5.98L0 24l6.25-1.64a11.92 11.92 0 0 0 5.79 1.47h.01c6.58 0 11.94-5.36 11.94-11.94a11.86 11.86 0 0 0-3.47-8.4z"/></svg></span>';
    // Revisión cliente 23-jul: el logo de Lawang se queda siempre en el menú (fuera el "‹ The Collection").
    return '<header id="topbar" class="show '+(ghost?'pdp':'solid')+'">'
      + '<div id="logo"'+(ghost?'':' class="dark"')+'><a id="logo-inner" href="index.html" aria-label="Lawang — inicio"><img class="ll-white" src="assets/img/lawang-logo-v3.png" alt="Lawang Tropical Properties"><span class="ll-dark" aria-hidden="true"></span></a></div>'
      + '<nav id="nav">'+nl('#land','The Land',S.line==='land')+nl('#villas','The Villas',S.line==='villa')+nl('index.html#expedition','The Soul',false)+nl('#all','The Collection',false)+'</nav>'
      + '<div id="nav-actions">'
      +   '<div class="nav-lang-wrap" id="langWrap"><button class="nav-lang" data-act="lang-toggle" aria-haspopup="listbox" aria-expanded="'+(S.langOpen?'true':'false')+'"><span>'+langName+'</span><span class="lang-abbr">'+S.lang.toUpperCase()+'</span><span class="caret">▾</span></button>'
      +     '<ul class="lang-menu'+(S.langOpen?' open':'')+'" id="langMenu" role="listbox">'+li('en',flagEN,'English')+li('es',flagES,'Español')+li('id',flagID,'Bahasa')+'</ul></div>'
      +   '<div class="nav-lang-wrap nav-cur-wrap" id="curWrap"><button class="nav-lang" data-act="cur-toggle" aria-haspopup="listbox" aria-expanded="'+(S.curOpen?'true':'false')+'" aria-label="Currency"><span>'+S.cur+'</span><span class="caret">▾</span></button>'
      +     '<ul class="lang-menu'+(S.curOpen?' open':'')+'" role="listbox">'+ci('EUR','€')+ci('USD','$')+ci('AUD','A$')+ci('IDR','Rp')+'</ul></div>'
      +   '<a class="nav-cta" href="'+waUrl+'" target="_blank" rel="noopener"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" style="width:16px;height:16px" aria-hidden="true"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.8 19.8 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.8 19.8 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.9.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/></svg> <span>'+(ghost?tl("Request details","Solicitar detalles"):t("cta.ask"))+'</span></a>'
      + '</div></header>';
  }

  // ════ MARKETPLACE ════
  // Ubicación en dos líneas (guía): "BALI · INDONESIA" + zona (parte antes de la coma de p.region)
  function regionLabelHTML(p, sizeBig){
    var island = p.regionKey==="sumba" ? "Sumba" : "Bali";
    var area = String(p.region||"").split(",")[0];
    return '<span style="display:block;font-family:var(--sans);font-weight:300;font-size:clamp(11px,1.1vw,15px);letter-spacing:.22em;text-transform:uppercase;opacity:.92">'+esc(island)+' · Indonesia</span>'
      + '<span style="display:block;font-family:var(--sans);font-weight:400;font-size:'+(sizeBig?'clamp(15px,1.6vw,21px)':'clamp(13px,1.3vw,17px)')+';letter-spacing:.24em;text-transform:uppercase;margin-top:7px">'+esc(area)+'</span>';
  }

  // Featured según guía Collection: marco fino interior, ubicación arriba-dcha, sub uppercase, dots
  function featuredHTML(p, list){
    if(!p || !((p.imgKeys&&p.imgKeys.length)||(p.images&&p.images.length))) return "";
    var key = (p.imgKeys&&p.imgKeys[0]) || (p.images&&p.images[0]);
    var dots = (list&&list.length>1) ? '<div style="position:absolute;right:clamp(20px,3vw,38px);bottom:clamp(18px,2.6vw,30px);z-index:4;display:flex;gap:8px">'
      + list.map(function(x,i){ return '<button data-act="feat:'+i+'" aria-label="Featured '+(i+1)+'" style="width:9px;height:9px;border-radius:999px;border:1px solid rgba(245,240,230,.85);background:'+(x.id===p.id?'var(--bone)':'transparent')+';cursor:pointer;padding:0"></button>'; }).join("")
      + '</div>' : "";
    return '<div class="lw-featured" data-go="'+esc(p.id)+'" style="cursor:pointer;position:relative;border-radius:12px;overflow:hidden;margin-bottom:26px">'
      + ph({key:key, w:2000, theme:themeFor(p), kb:true, ratio:"21/6", tint:0, style:"min-height:200px"})
      + '<div style="position:absolute;inset:0;background:linear-gradient(105deg,rgba(22,18,12,.82) 0%,rgba(22,18,12,.42) 48%,rgba(22,18,12,.05) 100%)"></div>'
      + '<span style="position:absolute;inset:clamp(12px,1.4vw,18px);border:1px solid rgba(245,240,230,.5);border-radius:8px;pointer-events:none;z-index:3"></span>'
      + '<div style="position:absolute;top:clamp(24px,3vw,40px);right:clamp(24px,3.4vw,44px);z-index:2;text-align:right;color:var(--bone)">'+regionLabelHTML(p,true)+'</div>'
      + '<div style="position:absolute;inset:0;display:flex;flex-direction:column;justify-content:flex-end;padding:clamp(24px,3.4vw,44px);color:var(--bone);max-width:640px">'
      +   '<span class="pill" style="align-self:flex-start;margin-bottom:14px;border-color:rgba(245,240,230,.55);color:var(--bone);background:rgba(22,18,12,.28)">'+t("mk.featured")+'</span>'
      +   '<h3 style="font-family:var(--sans);font-weight:300;font-size:clamp(30px,4.4vw,58px);line-height:.98;letter-spacing:.06em;text-transform:uppercase">'+esc(pick(p.title))+'</h3>'
      +   '<p style="font-family:var(--sans);font-weight:600;font-size:clamp(12px,1.3vw,17px);letter-spacing:.1em;text-transform:uppercase;opacity:.95;margin-top:10px;max-width:560px">'+esc(pick(p.sub))+'</p>'
      + '</div>'+dots+'</div>';
  }

  function marketplaceHTML(){
    var lineDescs = { signature:"line.signature.d", land:"line.land.d", villa:"line.villa.d", resorts:"line.resorts.d" };
    // Featured por línea: cada línea puede tener su propia propiedad destacada.
    // En vista "Todas" se muestra el primer featured (Signature por orden de precio).
    var featCands = L.PROPERTIES.filter(function(p){return p.featured && p.visible!==false && (S.region==="all"||p.regionKey===S.region);});
    var featList = (S.line==="all") ? featCands : featCands.filter(function(p){return p.line===S.line;});
    if(S.featIdx >= featList.length) S.featIdx = 0;
    var featured = featList[S.featIdx];
    var filtered = L.PROPERTIES.filter(function(p){ return p.visible!==false && (S.line==="all"||p.line===S.line) && (S.region==="all"||p.regionKey===S.region); });

    // Portada: 4 categorías destacadas con foto de fondo (Signature / Land / Villas / Resorts).
    // Guía Collection (jul-2026): imágenes ecommerce_card_* · nombre de línea fino arriba,
    // subtítulo en bold debajo, icono cream a la derecha.
    var HERO_CATS = [
      { line:"signature", img:"ecommerce_card_signature.jpg" },
      { line:"land",      img:"ecommerce_card_land.jpg" },
      { line:"villa",     img:"ecommerce_card_residences.jpg" },
      { line:"resorts",   img:"ecommerce_card_resort.jpg" }
    ];
    var lineCards = HERO_CATS.map(function(c,i){
      var on = S.line===c.line;
      return '<button class="lw-cat reveal'+(on?" on":"")+'" data-act="line:'+c.line+'" style="transition-delay:'+(i*70)+'ms;position:relative;border:0;cursor:pointer;padding:0;border-radius:14px;overflow:hidden;min-height:clamp(102px,11vw,143px);display:flex;align-items:center">'
        + '<img src="assets/img/'+c.img+'" alt="" loading="lazy" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover">'
        + '<span style="position:absolute;inset:0;background:linear-gradient(90deg,rgba(20,16,11,.72) 0%,rgba(20,16,11,.44) 55%,rgba(20,16,11,.2) 100%)"></span>'
        + '<span style="position:relative;display:flex;align-items:center;justify-content:space-between;gap:12px;width:100%;padding:0 clamp(14px,1.7vw,22px);text-align:left;color:#F5F0E6">'
        // Ambas líneas en UNA sola línea (revisión cliente 23-jul): el subtítulo más largo
        // ("Hospitalidad de primer nivel") rompía en dos renglones → tipo más pequeña + nowrap.
        +   '<span style="min-width:0"><span style="display:block;font-family:var(--sans);font-weight:300;font-size:clamp(12px,1.15vw,16px);line-height:1;letter-spacing:.2em;text-transform:uppercase;opacity:.88;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'+t("cat."+c.line)+'</span>'
        +     '<span style="display:block;font-family:var(--sans);font-size:clamp(9.5px,.88vw,14px);font-weight:700;letter-spacing:.03em;text-transform:uppercase;margin-top:7px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'+t("cat."+c.line+".sub")+'</span></span>'
        +   '<img src="assets/img/'+LINE_CREAM[c.line]+'.png" alt="" loading="lazy" style="width:clamp(30px,3.2vw,42px);height:auto;flex:none;object-fit:contain">'
        + '</span></button>';
    }).join("");

    // Guía Collection: dos grupos etiquetados — Property (verde) y Destination (tierra)
    var groupLabel = function(pre, word, color){ return '<div style="font-family:var(--sans);font-size:11px;font-weight:400;letter-spacing:.14em;text-transform:uppercase;color:'+(color||'var(--ink-2)')+';margin-bottom:10px">'+pre+' <b style="font-weight:700;color:'+(color||'var(--ink)')+'">'+word+' ⌄</b></div>'; };
    var propChips = '<button class="filter-chip" data-act="line:all" style="'+chipStyle(S.line==="all")+'">'+t("mk.all")+'</button>'
      + LINES.map(function(l){ return '<button class="filter-chip" data-act="line:'+l+'" style="'+chipStyle(S.line===l)+'">'+t(LINE_KEYS[l])+'</button>'; }).join("");
    var destChips = '<button class="filter-chip" data-act="region:all" style="'+chipStyle(S.region==="all","var(--be)")+'">'+t("mk.all")+'</button>'
      + '<button class="filter-chip" data-act="region:bali" style="'+chipStyle(S.region==="bali","var(--be)")+'">Bali</button>'
      + '<button class="filter-chip" data-act="region:sumba" style="'+chipStyle(S.region==="sumba","var(--be)")+'">Sumba</button>';
    var chips = '<div>'+groupLabel(t("mk.browse"),t("mk.property"))+'<div style="display:flex;gap:8px;flex-wrap:wrap">'+propChips+'</div></div>'
      + '<div>'+groupLabel(t("mk.explore"),t("mk.destination"),"var(--be)")+'<div style="display:flex;gap:8px;flex-wrap:wrap">'+destChips+'</div></div>';

    // Paginación: máx 9 propiedades por página.
    var PER_PAGE = 9;
    var totalPages = Math.max(1, Math.ceil(filtered.length / PER_PAGE));
    if(S.page > totalPages) S.page = totalPages;
    if(S.page < 1) S.page = 1;
    var pageStart = (S.page - 1) * PER_PAGE;
    var pageItems = filtered.slice(pageStart, pageStart + PER_PAGE);
    var cards = pageItems.map(function(p){ return window.LawangCard.render(p, { lang:S.lang, cur:S.cur, rates:L.RATES, hrefBase:"" }); }).join("");
    var emptyState = '<div style="grid-column:1/-1;padding:60px 24px;text-align:center;color:var(--ink-2)">'
      + (L.PROPERTIES.length===0
          ? '<p style="font-size:15px;margin:0 0 6px">'+(S.lang==="es"?"No se pudieron cargar las propiedades.":"Properties could not be loaded.")+'</p>'
            + '<p style="font-size:13px;opacity:.7;margin:0">'+(S.lang==="es"?"Abre la página servida por HTTP (no como archivo local) o reintenta.":"Open the page over HTTP (not as a local file) or try again.")+'</p>'
          : '<p style="font-size:15px;margin:0">'+(S.lang==="es"?"No hay propiedades con estos filtros.":"No properties match these filters.")+'</p>')
      + '</div>';

    var gridCols = S.layout==="list" ? "1fr" : "repeat(auto-fill,minmax(320px,1fr))";
    var gap = S.layout==="list" ? "20px" : "28px";

    var showFeatured = !!featured;

    return '<div style="background:var(--bone)">'
      + '<section class="wrap" style="padding-top:clamp(24px,3.2vw,46px);padding-bottom:26px">'
      +   '<div class="reveal" style="text-align:center">'
      +     '<h1 class="display" style="margin:0 auto;font-weight:300;line-height:.98;text-transform:uppercase">'
      +       '<span style="display:block;font-family:var(--sans);font-weight:300;font-size:clamp(17px,2.3vw,30px);letter-spacing:.14em">'+t("mk.title1")+'</span>'
      +       '<span class="hero-serif" style="display:block;font-size:clamp(40px,7vw,92px);letter-spacing:.02em;margin-top:4px">'+t("mk.title2")+'</span>'
      +     '</h1>'
      // Guía Collection: el kicker va DEBAJO del título, gris claro y muy espaciado
      +     '<span style="display:inline-block;margin-top:10px;font-family:var(--sans);font-size:clamp(12px,1.4vw,18px);font-weight:300;letter-spacing:.3em;text-transform:uppercase;color:var(--ss)">'+t("mk.kicker")+'</span></div>'
      +   '<div class="lw-cat-grid" style="display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-top:clamp(19px,2.4vw,32px)">'+lineCards+'</div>'
      + '</section>'
      + (showFeatured ? '<section class="wrap">'+featuredHTML(featured, featList)+'</section>' : "")
      + '<section class="wrap" id="pf-grid" style="scroll-margin-top:90px;padding-bottom:clamp(40px,5vw,64px)">'
      +   '<div style="display:flex;align-items:flex-end;justify-content:space-between;gap:clamp(20px,3vw,44px);flex-wrap:wrap;padding-bottom:20px;border-bottom:1px solid var(--line);margin-bottom:24px">'
      +     chips
      +     '<div style="display:flex;align-items:center;gap:14px;margin-left:auto"><span style="font-size:13px;color:var(--ink-2)">'+filtered.length+' '+t("mk.results")+'</span>'
      +       '<div class="seg" style="color:var(--ink)"><button class="'+(S.layout==="grid"?"on":"")+'" data-act="layout:grid"><span style="color:'+(S.layout==="grid"?"var(--bone)":"inherit")+'">▦</span></button>'
      +       '<button class="'+(S.layout==="list"?"on":"")+'" data-act="layout:list"><span style="color:'+(S.layout==="list"?"var(--bone)":"inherit")+'">≡</span></button></div></div>'
      +   '</div>'
      +   '<div style="display:grid;grid-template-columns:'+gridCols+';gap:'+gap+'">'+(cards||emptyState)+'</div>'
      +   paginationHTML(S.page, totalPages)
      + '</section>'
      + footerHTML()
      + '</div>';
  }
  // accent: color del grupo (verde por defecto; tierra --be para Destination, según guía)
  function chipStyle(active, accent){ accent = accent || "var(--clay)"; return 'appearance:none;border:1px solid '+(active?accent:"var(--line)")+';background:'+(active?accent:"transparent")+';color:'+(active?"var(--bone)":accent)+';border-radius:999px;padding:8px 16px;font-size:12px;font-weight:600;letter-spacing:.08em;text-transform:uppercase;cursor:pointer;font-family:var(--sans);white-space:nowrap'; }
  // ponytail: sin ellipsis — el portfolio no llega a tantas páginas; añadir truncado si algún día supera ~10
  function paginationHTML(page, totalPages){
    if(totalPages<=1) return "";
    // Guía Collection: números planos, activo subrayado, chevrones sin caja
    var cell=function(label,target,o){ o=o||{};
      var col = o.active?"var(--ink)":(o.disabled?"var(--line)":"var(--ink-2)");
      var st='appearance:none;border:none;background:transparent;color:'+col+';min-width:36px;height:40px;padding:0 8px;font-size:15px;font-weight:'+(o.active?700:500)+';font-family:var(--sans);cursor:'+(o.disabled?"default":"pointer")+';display:inline-flex;align-items:center;justify-content:center;text-decoration:'+(o.active?"underline":"none")+';text-underline-offset:6px';
      return '<button '+(o.disabled?"disabled":'data-act="page:'+target+'"')+' style="'+st+'"'+(o.active?' aria-current="page"':'')+' aria-label="'+(o.label||("Page "+target))+'">'+label+'</button>';
    };
    var out=cell("‹",page-1,{disabled:page<=1,label:"Previous page"});
    for(var i=1;i<=totalPages;i++) out+=cell(String(i),i,{active:i===page});
    out+=cell("›",page+1,{disabled:page>=totalPages,label:"Next page"});
    return '<nav aria-label="Pagination" style="display:flex;justify-content:center;gap:8px;flex-wrap:wrap;margin-top:clamp(32px,4vw,48px)">'+out+'</nav>';
  }

  // ════ THE PROCESS + Seven steps — SOBRE la imagen aérea (guía Collection) ════
  // Las 7 tarjetas van montadas sobre el fondo aéreo con overlay oscuro; sustituye
  // al antiguo banner "Own Eternity" separado (el proceso ES ahora el contenido de esa imagen).
  function stepsHTML(){
    var waNum=(L.SETTINGS&&L.SETTINGS.whatsapp)||'6281138319862';
    var waUrl='https://wa.me/'+waNum+'?text='+encodeURIComponent(t("reserve.msg")||"Hello LAWANG");
    var items="";
    for(var n=1;n<=7;n++){
      items += '<div class="proc-card" style="padding:16px 16px 18px;border-top:2px solid var(--ss);background:rgba(20,16,11,.28);-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px);border-radius:0 0 8px 8px">'
        + '<span class="proc-num" style="display:block;font-size:clamp(20px,2vw,26px);color:var(--ss);line-height:1;margin-bottom:9px">'+(n<10?"0":"")+n+'</span>'
        + '<span style="display:block;font-family:var(--sans);font-weight:700;font-size:14px;color:var(--bone);margin-bottom:4px">'+t("proc.s"+n+".t")+'</span>'
        + '<span style="display:block;font-size:12.5px;color:rgba(245,240,230,.78);line-height:1.5">'+t("proc.s"+n+".d")+'</span>'
        + '</div>';
    }
    return '<section class="wrap" id="process" style="padding-block:clamp(28px,4vw,52px);scroll-margin-top:90px">'
      + '<div style="position:relative;border-radius:12px;overflow:hidden">'
      +   '<img src="assets/img/aerial-1.jpg" alt="Aerial view of the Balian coastline, Bali" loading="lazy" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover">'
      +   '<div style="position:absolute;inset:0;background:linear-gradient(180deg,rgba(16,40,42,.82) 0%,rgba(16,40,42,.7) 45%,rgba(10,22,20,.86) 100%)"></div>'
      +   '<span style="position:absolute;inset:clamp(12px,1.4vw,18px);border:1px solid rgba(245,240,230,.35);border-radius:8px;pointer-events:none;z-index:3"></span>'
      +   '<div style="position:absolute;top:clamp(20px,2.6vw,34px);right:clamp(22px,3vw,40px);z-index:2;text-align:right;color:var(--bone)">'
      +     '<span style="display:block;font-family:var(--sans);font-weight:300;font-size:clamp(11px,1.1vw,15px);letter-spacing:.22em;text-transform:uppercase;opacity:.9">Bali · Indonesia</span>'
      +     '<span style="display:block;font-family:var(--sans);font-weight:400;font-size:clamp(15px,1.6vw,21px);letter-spacing:.24em;text-transform:uppercase;margin-top:6px">Balian</span></div>'
      +   '<div style="position:relative;z-index:2;padding:clamp(30px,5vw,62px) clamp(20px,4vw,56px)">'
      +     '<div class="reveal" style="text-align:center;max-width:660px;margin:0 auto clamp(24px,3vw,38px)">'
      +       '<span class="kicker" style="display:inline-block;color:var(--ss)">'+t("ft.reserve.k")+'</span>'
      +       '<h2 class="display" style="font-size:clamp(28px,4.2vw,48px);text-transform:uppercase;font-weight:300;line-height:1;margin:10px 0 0;color:var(--bone)">'+t("proc.title")+'</h2>'
      +       '<p style="font-size:clamp(14px,1.5vw,16px);color:rgba(245,240,230,.82);line-height:1.6;margin:14px 0 0">'+t("ft.reserve.sub")+'</p>'
      +     '</div>'
      +     '<div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,220px),1fr));gap:14px">'+items+'</div>'
      +     '<div style="text-align:center;margin-top:clamp(26px,3.4vw,40px)"><a href="'+waUrl+'" target="_blank" rel="noopener" class="btn btn-light">'+t("ft.reserve.cta")+' <span class="arr">→</span></a></div>'
      +   '</div>'
      + '</div></section>';
  }

  // ════ FOOTER (banda de reserva + barra de contacto) ════
  // Marketplace: proceso de 7 pasos + footer. La ficha usa solo footerCoreHTML() — repetir
  // el bloque #process dentro del overlay duplicaría el id y una sección entera de la home.
  function footerHTML(){ return stepsHTML() + footerCoreHTML(); }

  function footerCoreHTML(){
    var waNum=(L.SETTINGS&&L.SETTINGS.whatsapp)||'6281138319862';
    var email=(L.SETTINGS&&L.SETTINGS.email)||'sales@lawangproperties.com';
    var waUrl='https://wa.me/'+waNum+'?text='+encodeURIComponent(t("reserve.msg")||"Hello LAWANG");
    var tel='+'+waNum.replace(/^(\d{2})(\d{3})(\d{4})(\d+)$/,'$1 $2-$3-$4');
    var icoPhone='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" style="width:15px;height:15px;flex:none" aria-hidden="true"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.8 19.8 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.8 19.8 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.9.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/></svg>';
    var icoMail='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" style="width:15px;height:15px;flex:none" aria-hidden="true"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-10 6L2 7"/></svg>';
    // Franja "discover beyond… / ask why investors stay" eliminada (revisión cliente 23-jul).
    // El teléfono/email siguen en la parte baja del footer (lw-ft-bottom) y en la burbuja de WhatsApp.
    return '<footer class="pf-footer">'
      +   '<div class="lw-ft">'
      +     '<div class="lw-ft-grid">'
      +       '<div>'
      +         '<img class="lw-ft-logo-img" src="assets/img/lawang-logo-v3.png" alt="Lawang Tropical Properties">'
      +         '<div class="lw-ft-sub" style="margin-top:10px">Tropical Properties</div>'
      +         '<p class="lw-ft-tag">Strategic asset investment, structuring and development in Indonesia. Bali · Sumba.</p>'
      +       '</div>'
      +       '<div class="lw-ft-col"><h5>Portfolio</h5>'
      +         '<a href="#signature">Signature</a><a href="#land">Land</a><a href="#villas">Villas</a><a href="#resorts">Resorts</a></div>'
      +       '<div class="lw-ft-col"><h5>Company</h5>'
      +         '<a href="index.html#expedition">The Soul</a><a href="index.html#the-services">What We Do</a><a href="index.html">The Estate</a><a href="#all">Choose your Legacy</a></div>'
      +       '<div class="lw-ft-col"><h5>Divisions</h5>'
      +         '<a href="#all">Tepi Sungai</a><a href="#all">Balian Hills</a><a href="#signature">Riverfront II®</a></div>'
      +     '</div>'
      +   '</div>'
      +   '<div class="lw-ft-bottom">'
      +     '<span class="lw-ft-copy">© 2026 Lawang Tropical Properties · Indonesia</span>'
      +     '<div class="lw-ft-contact">'
      +       '<a class="lw-ft-cti" href="tel:+'+waNum+'">'+icoPhone+tel+'</a>'
      +       '<a class="lw-ft-cti" href="mailto:'+esc(email)+'">'+icoMail+esc(email)+'</a>'
      +     '</div>'
      +     '<div class="lw-ft-legal">'
      +       '<a class="lw-ft-tc" href="#" data-legal="terms">Terms &amp; Conditions</a>'
      +       '<a class="lw-ft-tc" href="#" data-legal="privacy">Privacy Policy</a>'
      +       '<a class="lw-ft-tc" href="accessibility.html">Accessibility</a>'
      +     '</div>'
      +   '</div>'
      + '</footer>';
  }

  // ════ FICHA — sub-bloques ════
  // ── Hero a pantalla completa (guía Ficha, jul-2026): imagen full-bleed del producto,
  //    marca, título display, pill de release, tagline y ubicación. Cae a gradiente temático sin foto.
  // Fila de características bajo el hero (petición cliente jul-2026): habitaciones, baños,
  // superficies y amenities booleanas, cada una con su icono. Solo pinta lo que la propiedad
  // tiene — data-driven. Iconos = trazos SVG inline en currentColor (mismo criterio que el resto
  // de la marca: nada de librerías de iconos por 7 dibujos).
  var FEAT_ICONS = {
    beds:      '<path d="M3 18v-7a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v7"/><path d="M3 18h18"/><path d="M7 9V7a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v2"/>',
    baths:     '<path d="M4 12h16v2.5a4.5 4.5 0 0 1-4.5 4.5h-7A4.5 4.5 0 0 1 4 14.5Z"/><path d="M6 12V6a2 2 0 0 1 4 0"/><path d="M7 21l-1-2M17 21l1-2"/>',
    built:     '<path d="m3 11 9-7 9 7"/><path d="M5 9.6V20h14V9.6"/>',
    land:      '<path d="M4 4h16v16H4z" stroke-dasharray="3.2 2.6"/>',
    type:      '<path d="M20.6 13.4 12 22 2 12V2h10l8.6 8.6a2 2 0 0 1 0 2.8Z"/><circle cx="7" cy="7" r="1.5"/>',
    color:     '<path d="M12 2s6 7 6 11.5A6 6 0 0 1 6 13.5C6 9 12 2 12 2Z"/>',
    tenure:    '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z"/><path d="M14 2v6h6"/>',
    priceM2:   '<rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/>'
  };
  // Revisión cliente 23-jul: juego fijo de características. Normal: habitaciones, baños,
  // m² construidos, m² parcela y tipo. Land: tipo, color del terreno (zonificación, campo
  // nuevo del admin), m² parcela, tenure y precio por m².
  function heroFeatsHTML(p){
    var f = [];
    var typeLabel = t(LINE_KEYS[p.line]);
    if(p.line==="land"){
      f.push({i:"type", t:typeLabel});
      if(p.landColor) f.push({i:"color", t:p.landColor});
      if(p.land>0)    f.push({i:"land",  t:p.land+" m² "+tl("Land","Terreno")});
      f.push({i:"tenure", t:(p.tenure==="tenure.freehold"?"Freehold HGB":"Leasehold "+(p.leaseYears||30)+" yr")});
      // Precio por m²: parcela más barata del configurador o, si no hay, precio/superficie
      var ppm2 = null;
      if(p.landOptions&&p.landOptions.length){
        var rr=p.landOptions.map(function(o){ var s=Number(o.size)||0, pr=Number(o.priceEUR)||0; return (s>0&&pr>0)?pr/s:null; }).filter(Boolean);
        if(rr.length) ppm2 = Math.min.apply(null,rr);
      }
      if(!ppm2 && p.priceEUR>0 && p.land>0) ppm2 = p.priceEUR/p.land;
      if(ppm2) f.push({i:"priceM2", t:money(Math.round(ppm2))+"/m²"});
    } else {
      if(p.beds>0)  f.push({i:"beds",  t:p.beds+" "+tl(p.beds===1?"Bedroom":"Bedrooms", p.beds===1?"Habitación":"Habitaciones")});
      if(p.baths>0) f.push({i:"baths", t:p.baths+" "+tl(p.baths===1?"Bathroom":"Bathrooms", p.baths===1?"Baño":"Baños")});
      if(p.built>0) f.push({i:"built", t:p.built+" m² "+tl("Built","Construidos")});
      if(p.land>0)  f.push({i:"land",  t:p.land+" m² "+tl("Land","Terreno")});
      f.push({i:"type", t:typeLabel});
    }
    if(f.length===0) return "";
    return '<div class="pdp-hero-feats" aria-label="'+tl("Key features","Características")+'">'
      + f.map(function(x){ return '<span><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+FEAT_ICONS[x.i]+'</svg>'+esc(x.t)+'</span>'; }).join("")
      + '</div>';
  }

  // Marca del hero de la ficha, en cascada (petición cliente 23-jul):
  // 1) isotipo propio del proyecto (p.isotype, cargado desde el admin) como <img> tal cual;
  // 2) icono de la vista (cliff/river/jungle/beach/ricefield) — mismo criterio y PNGs que la
  //    card (LawangCard.viewFor respeta p.view del admin o lo infiere del texto). Va como
  //    máscara para teñirse de crema, igual que hacía el isotipo de Lawang;
  // 3) isotipo de Lawang solo si la librería de la card no está (defensivo).
  function heroMarkHTML(p){
    if(p.isotype) return '<img src="'+esc(p.isotype)+'" alt="" style="display:block;height:clamp(52px,6vw,78px);width:auto;max-width:240px;margin:0 auto 26px;object-fit:contain" onerror="this.style.display=\'none\'">';
    if(window.LawangCard && LawangCard.viewFor){
      var vw = LawangCard.viewFor(p);
      var m = 'url(assets/img/'+vw+'-ico.png) center/contain no-repeat';
      return '<span aria-hidden="true" style="display:block;width:clamp(56px,6.5vw,84px);aspect-ratio:1;margin:0 auto 26px;background-color:var(--bone);-webkit-mask:'+m+';mask:'+m+';opacity:.95"></span>';
    }
    return '<span class="lw-iso" aria-hidden="true" style="width:clamp(46px,5.2vw,64px);margin:0 auto 26px;color:var(--bone);opacity:.95"></span>';
  }

  function heroHTML(p){
    var key = firstImg(p);
    var theme = themeFor(p);
    var island = p.regionKey==="sumba" ? "Sumba" : "Bali";
    var area = String(p.region||"").split(",")[0].trim();
    var loc = (area ? area+" · " : "") + island + " · Indonesia";
    var release = (p.featured || p.homeFeatured) ? '<span class="pill" style="align-self:center;margin:0 auto 22px;border-color:rgba(245,240,230,.55);color:var(--bone);background:rgba(20,16,11,.28);backdrop-filter:blur(3px)">'+tl("Featured Release","Lanzamiento destacado")+'</span>' : "";
    var bg = key
      ? '<img src="'+esc(imgUrl(key,2400))+'" alt="" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover" onerror="this.style.display=\'none\'">'
      : '';
    // Guía Ficha p1: el claim va en DOS niveles — el sub de la propiedad en fino y, debajo,
    // el destacado (metaText) grande en negrita. Sin metaText se queda solo el sub, sin inventar línea.
    var claim = pick(p.sub)
      ? '<p style="font-family:var(--sans);font-weight:400;font-size:clamp(14px,1.7vw,26px);letter-spacing:.045em;text-transform:uppercase;line-height:1.3;margin:0 auto;max-width:54ch">'+esc(pick(p.sub))+'</p>' : '';
    if(pick(p.metaText)) claim += '<p class="display" style="font-weight:600;font-size:clamp(26px,4.2vw,52px);letter-spacing:.02em;text-transform:uppercase;line-height:1.08;margin:clamp(6px,1vh,12px) auto 0;max-width:22ch">'+esc(pick(p.metaText))+'</p>';
    return '<section class="pdp-hero" style="position:relative;min-height:clamp(540px,84vh,820px);display:flex;align-items:center;justify-content:center;overflow:hidden;background:#1a160f">'
      + '<div class="ph-grad ph-'+theme+'" style="position:absolute;inset:0;opacity:'+(key?0:1)+'"></div>'
      + bg
      + '<div style="position:absolute;inset:0;background:linear-gradient(180deg,rgba(20,16,11,.5) 0%,rgba(20,16,11,.12) 30%,rgba(20,16,11,.32) 66%,rgba(20,16,11,.8) 100%)"></div>'
      // Marco interior de filete (guía). Marca de agua y migas retiradas del hero (revisión
      // cliente 23-jul): las migas viven ahora en la sección de info, bajo el hero.
      + '<span aria-hidden="true" class="pdp-hero-frame"></span>'
      + '<div style="position:relative;z-index:2;text-align:center;color:var(--bone);padding:clamp(80px,12vh,140px) clamp(20px,6vw,64px) clamp(60px,9vh,100px);max-width:1100px">'
      +   heroMarkHTML(p)
      +   '<h1 class="display" style="font-size:clamp(46px,8.4vw,104px);font-weight:300;letter-spacing:.06em;text-transform:uppercase;line-height:.96;margin:0">'+esc(pick(p.title))+'</h1>'
      +   '<div style="margin-top:clamp(24px,3.4vh,38px)">'+release+'</div>'
      +   claim
      +   '<p style="font-family:var(--sans);font-weight:300;font-size:clamp(11px,1.2vw,15px);letter-spacing:.28em;text-transform:uppercase;opacity:.9;margin-top:clamp(22px,3vh,34px)">'+esc(loc)+'</p>'
      + '</div>'
      + heroFeatsHTML(p)
      + '</section>';
  }

  // Burbuja flotante de WhatsApp (guía Ficha p1, esquina inferior derecha) — visible en toda la ficha.
  function waFloatHTML(p){
    var waNum=(L.SETTINGS&&L.SETTINGS.whatsapp)||'6281138319862';
    var waUrl='https://wa.me/'+waNum+'?text='+encodeURIComponent("Hello! I'm interested in "+pick(p.title)+".");
    return '<a class="pdp-wa-float" href="'+waUrl+'" target="_blank" rel="noopener" aria-label="WhatsApp">'
      + '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12.04 2C6.58 2 2.13 6.45 2.13 11.91c0 1.75.46 3.45 1.32 4.95L2 22l5.25-1.38a9.9 9.9 0 0 0 4.79 1.22c5.46 0 9.91-4.45 9.91-9.91S17.5 2 12.04 2zm5.8 14.02c-.24.68-1.42 1.3-1.95 1.35-.5.05-.96.24-3.24-.68-2.73-1.08-4.45-3.86-4.58-4.04-.13-.18-1.1-1.46-1.1-2.79s.7-1.98.94-2.25c.24-.27.53-.34.7-.34l.5.01c.16 0 .38-.06.59.45.24.57.8 1.98.87 2.12.07.14.12.31.02.49-.09.18-.14.29-.28.45l-.42.49c-.14.14-.28.29-.12.57.16.28.72 1.19 1.55 1.93 1.06.95 1.96 1.24 2.24 1.38.28.14.44.12.6-.07.16-.18.69-.8.87-1.08.18-.28.36-.23.6-.14.24.09 1.55.73 1.82.87.27.14.44.2.5.31.07.11.07.63-.17 1.31z"/></svg></a>';
  }

  // (banner statement "N villas / one residence" eliminado — revisión cliente 23-jul; su hueco lo
  //  ocupa ahora el sistema de pestañas)

  // Lista unificada de media de la galería (fotos + vídeos) — la usan la fila de 3 y el lightbox.
  function mediaList(p){
    var media = [];
    (p.imgKeys||[]).forEach(function(k){ media.push({type:"image",key:k}); });
    (p.videos||[]).forEach(function(v){ var o=(typeof v==="string")?{src:v}:(v||{}); var src=o.src||o.url||""; if(src) media.push({type:"video",src:src,poster:o.poster||""}); });
    return media;
  }
  // Chevron SVG de navegación (galería + lightbox): el glifo de texto era incentrable.
  function chevSVG(side){ return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="'+(side==="left"?"M14.5 5.5 8 12l6.5 6.5":"M9.5 5.5 16 12l-6.5 6.5")+'"/></svg>'; }

  // ── Galería (revisión cliente 23-jul): 2 fotos GRANDES + tira de miniaturas debajo, para
  //    ver de un vistazo cuántas fotos hay. Click en cualquiera = lightbox; las flechas y el
  //    swipe avanzan la ventana. En móvil: 1 grande + miniaturas deslizables.
  function galleryHTML(p){
    var media = mediaList(p);
    if(media.length===0) return "";
    var total = media.length;
    var active = ((S.gallery%total)+total)%total;
    var theme = themeFor(p);
    var playIco = '<div style="position:absolute;inset:0;display:grid;place-items:center;z-index:2"><span style="width:34px;height:34px;border-radius:999px;background:rgba(20,16,11,.55);display:grid;place-items:center"><span style="width:0;height:0;margin-left:3px;border-left:11px solid var(--bone);border-top:7px solid transparent;border-bottom:7px solid transparent"></span></span></div>';
    var tileInner = function(m,w){ return m.type==="video"
      ? (m.poster?'<img src="'+esc(m.poster)+'" alt="" loading="lazy" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover">':'<div class="ph-grad ph-'+theme+'" style="position:absolute;inset:0"></div>')+playIco
      : ph({key:m.key, w:w||1600, theme:theme, tint:0.12, style:"position:absolute;inset:0"}); };
    var tileBtn = function(idx, cls, inner, extra){
      return '<button class="'+cls+'" data-act="lightbox:'+idx+'" aria-label="'+tl("View photo","Ver foto")+'" style="position:relative;flex:1 1 0;min-width:0;border:0;padding:0;margin:0;border-radius:10px;overflow:hidden;cursor:zoom-in;background:var(--bone-2);aspect-ratio:4/3">'+inner+(extra||'')+'</button>';
    };
    // 2 grandes: la activa y la siguiente
    var bigs = "";
    var nBig = Math.min(2, total);
    for(var i=0;i<nBig;i++){
      var idx=(active+i)%total;
      var badge = (i===0 && total>1) ? '<div style="position:absolute;left:13px;bottom:12px;z-index:4;background:rgba(20,16,11,.5);color:var(--bone);font-family:var(--sans);font-size:11.5px;font-weight:600;letter-spacing:.1em;padding:4px 11px;border-radius:999px;backdrop-filter:blur(3px)">'+String(active+1).padStart(2,"0")+' <span style="opacity:.55">/ '+String(total).padStart(2,"0")+'</span></div>' : "";
      bigs += tileBtn(idx, 'pdp-g3-tile'+(i>0?' pdp-g3-extra':''), tileInner(media[idx],1600), badge);
    }
    // Miniaturas: el resto de fotos en orden, hasta 6 visibles, "+N" en la última si hay más
    var thumbs = "";
    var restCount = total - nBig;
    var showTh = Math.min(6, restCount);
    for(var j=0;j<showTh;j++){
      var tIdx=(active+nBig+j)%total;
      var moreOv = (j===showTh-1 && restCount>showTh) ? '<div style="position:absolute;inset:0;background:rgba(20,16,11,.5);display:grid;place-items:center;z-index:3"><span style="font-family:var(--sans);font-size:clamp(15px,1.5vw,20px);color:var(--bone);font-weight:500">+'+(restCount-showTh)+'</span></div>' : "";
      thumbs += tileBtn(tIdx, 'pdp-g3-tile pdp-g3-thumb', tileInner(media[tIdx],700), moreOv);
    }
    var arrow = function(side,to){ return '<button class="pdp-gal-arrow" data-act="gal:'+to+'" aria-label="'+(side==="left"?tl("Previous","Anterior"):tl("Next","Siguiente"))+'" style="'+side+':12px">'+chevSVG(side)+'</button>'; };
    var prev = ((active-1)%total+total)%total, next = (active+1)%total;
    var arrows = total>1 ? (arrow("left", prev) + arrow("right", next)) : "";
    var anim = S.galAnim ? ' gal-anim' : '';
    S.galAnim = false;
    // Las flechas van DENTRO de la fila de grandes (position:relative) para centrarse en ella,
    // no en el bloque grandes+miniaturas.
    return '<div style="margin-top:clamp(20px,2.5vw,30px)">'
      + '<div class="pdp-gal2'+anim+'"'+(total>1?' data-prev="'+prev+'" data-next="'+next+'"':'')+'>'
      +   '<div class="pdp-gal2-big" style="position:relative">'+bigs+arrows+'</div>'
      +   (thumbs?'<div class="pdp-gal2-thumbs">'+thumbs+'</div>':'')
      + '</div>'
      + '</div>';
  }

  // ── Lightbox de la galería: foto/vídeo a tamaño grande sobre fondo oscuro. Se abre pinchando
  //    una miniatura; navega con flechas, swipe y teclado; cierra con ×, Escape o el fondo.
  function lightboxHTML(p){
    var media = mediaList(p); var total = media.length;
    if(!total || S.lightbox==null) return "";
    var i = ((S.lightbox%total)+total)%total; var m = media[i];
    var prev = ((i-1)%total+total)%total, next = (i+1)%total;
    var inner = m.type==="video"
      ? '<video src="'+esc(m.src)+'"'+(m.poster?' poster="'+esc(m.poster)+'"':'')+' controls autoplay playsinline></video>'
      : '<img src="'+esc(imgUrl(m.key,2400))+'" alt="">';
    return '<div class="pdp-lb" data-act="lb-close"'+(total>1?' data-prev="'+prev+'" data-next="'+next+'"':'')+' role="dialog" aria-modal="true" aria-label="'+tl("Photo viewer","Visor de fotos")+'">'
      // lb-noop: para el closest() de la delegación — un click sobre la foto/vídeo no cierra
      + '<div class="pdp-lb-media" data-act="lb-noop">'+inner+'</div>'
      + (total>1 ? '<button class="pdp-gal-arrow" data-act="lightbox:'+prev+'" aria-label="'+tl("Previous","Anterior")+'" style="left:14px">'+chevSVG("left")+'</button>'
                 + '<button class="pdp-gal-arrow" data-act="lightbox:'+next+'" aria-label="'+tl("Next","Siguiente")+'" style="right:14px">'+chevSVG("right")+'</button>' : '')
      + '<button class="pdp-lb-close" data-act="lb-close" aria-label="'+tl("Close","Cerrar")+'">×</button>'
      + '<div class="pdp-lb-count">'+String(i+1).padStart(2,"0")+' / '+String(total).padStart(2,"0")+'</div>'
      + '</div>';
  }

  // Franja de specs — tarjeta CLARA (guía Ficha, jul-2026): SOLO 6 campos según referencia —
  //    Tenure, Delivery, Status, Units, Available, Highlight. Etiqueta verde con filete, valor
  //    grande Burnt Earth; el highlight (metaText) en verde.
  function techSpecsHTML(p){
    // Revisión cliente 23-jul: si el admin trae celdas propias (p.techSpecs = [{l,v}]), mandan
    // ellas — texto libre. Sin ellas, la banda se construye sola como hasta ahora (fallback
    // para las propiedades que el cliente aún no ha tocado).
    if(p.techSpecs && p.techSpecs.length){
      var custom = p.techSpecs.filter(function(sp){ return sp && (sp.l||sp.v); });
      if(custom.length) return specCellsHTML(custom.map(function(sp){ return {l:sp.l||"", v:sp.v||"", hi:!!sp.hi}; }));
    }
    var isF = p.tenure==="tenure.freehold";
    var specs = [];
    specs.push({l:t("glance.tenure"), v:isF?"Freehold HGB":("Leasehold "+(p.leaseYears||30)+"yr")});
    specs.push({l:t("glance.delivery"), v:(p.handover&&p.handover!=="—")?p.handover:tl("On request","A consultar")});
    if(p.status) specs.push({l:t("glance.status"), v:t(p.status)});
    if(p.unitsTotal) specs.push({l:t("glance.units"), v:(p.unitsAvailable!=null&&p.unitsAvailable!==""?p.unitsAvailable+" / "+p.unitsTotal:String(p.unitsTotal))});
    // Available: menor parcela disponible → si no hay parcelas, área construida → terreno
    var avail = null;
    if(p.landOptions&&p.landOptions.length){ var sz=p.landOptions.map(function(o){return Number(o.size)||0;}).filter(Boolean); if(sz.length) avail=tl("From ","Desde ")+Math.min.apply(null,sz)+" m²"; }
    if(!avail && p.built>0) avail = p.built+" m²";
    if(!avail && p.land>0)  avail = p.land+" m²";
    if(avail) specs.push({l:tl("Available","Disponible"), v:avail});
    // El metaText es ahora el claim grande del hero; la 6ª celda la ocupa el dato legal que
    // antes vivía en el sidebar (eliminado según la guía): la PT PMA de las freehold.
    // El importe orientativo de la PT PMA sigue detallado en la nota del plan de pagos; aquí basta
    // "Included" para que el valor quepa en una línea como en la guía.
    if(isF) specs.push({l:t("glance.ptpma"), v:tl("Included","Incluida"), hi:true});
    if(specs.length===0) return "";
    return specCellsHTML(specs);
  }
  // Tarjeta blanca que abraza su contenido (guía Ficha p2): sin height:100% — estirarla dejaba
  // un hueco blanco enorme. flex:auto + nowrap → cada valor en una línea y el sobrante se reparte.
  function specCellsHTML(specs){
    var cells = specs.map(function(sp){
      var val = sp.hi ? 'var(--tg)' : 'var(--be)';
      return '<div style="flex:1 1 auto;padding:22px 24px">'
        + '<div style="display:inline-block;font-size:9px;font-weight:700;letter-spacing:.2em;text-transform:uppercase;color:var(--clay);border-bottom:1.5px solid rgba(72,91,55,.32);padding-bottom:6px;margin-bottom:11px;font-family:var(--sans);white-space:nowrap">'+esc(sp.l)+'</div>'
        + '<div style="font-family:var(--sans);font-size:clamp(18px,1.6vw,23px);font-weight:600;color:'+val+';line-height:1.15;white-space:nowrap">'+esc(sp.v)+'</div></div>';
    }).join("");
    return '<div class="tech-specs-grid" style="background:#fff;border-radius:14px;display:flex;flex-wrap:wrap;box-shadow:0 20px 50px -38px rgba(27,26,21,.4)">'+cells+'</div>';
  }

  // (tarjeta verde "Talk to the team" eliminada — revisión cliente 23-jul; el contacto queda en
  //  la burbuja flotante de WhatsApp y el CTA del topbar)
  // Revisión cliente 23-jul: fuera la tarjeta verde "Talk to the team" — la banda blanca ocupa
  // todo el ancho. El gate de descargas (que vivía en esa columna) se conserva debajo.
  // ── Card de información (revisión cliente 23-jul): a la DERECHA de la tabla blanca, bajo el
  //    carrusel. Overview + toda la ficha técnica que tengamos + mapa (si hay) + descargar dossier
  //    (con la puerta de email). Sustituye a la vieja tarjeta verde de contacto.
  function infoCardHTML(p){
    var overview = pick(p.desc);
    var rows = [];
    var add = function(ico, val){ if(val) rows.push({ico:ico, v:val}); };
    if(p.beds>0)  add("beds",  p.beds+" "+tl(p.beds===1?"Bedroom":"Bedrooms", p.beds===1?"Habitación":"Habitaciones"));
    if(p.baths>0) add("baths", p.baths+" "+tl(p.baths===1?"Bathroom":"Bathrooms", p.baths===1?"Baño":"Baños"));
    if(p.built>0) add("built", p.built+" m² "+tl("built","construidos"));
    if(p.land>0)  add("land",  p.land+" m² "+tl("land","de parcela"));
    if(p.poolType||p.pool) add("pool", (typeof p.poolType==="string"&&p.poolType)?p.poolType:tl("Pool","Piscina"));
    if(p.garage)  add("garage", (typeof p.garageDesc==="string"&&p.garageDesc)?p.garageDesc:tl("Garage","Garaje"));
    if(p.furnished) add("furnished", (typeof p.furnished==="string"&&p.furnished)?p.furnished:tl("Furnished","Amueblada"));
    if(p.style)   add("type", p.style);
    add("type", t(LINE_KEYS[p.line]));  // tipo de propiedad (línea)
    if(p.tenure)  add("tenure", p.tenure==="tenure.freehold"?"Freehold HGB":("Leasehold "+(p.leaseYears||30)+" yr"));
    if(p.status)  add("tenure", t(p.status));
    if(p.handover && p.handover!=="—") add("built", tl("Delivery","Entrega")+": "+p.handover);
    if(p.unitsTotal) add("type", (p.unitsAvailable!=null&&p.unitsAvailable!==""?p.unitsAvailable+" / ":"")+p.unitsTotal+" "+tl("units","unidades"));
    var specsGrid = rows.length ? '<div class="pdp-ic-specs">'+rows.map(function(r){
        return '<div class="pdp-ic-spec"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+(FEAT_ICONS[r.ico]||FEAT_ICONS.type)+'</svg><span>'+esc(r.v)+'</span></div>';
      }).join("")+'</div>' : "";
    var map = mapMediaHTML(p.mapImage);
    // Dossier: SIEMPRE presente (petición cliente 23-jul: "añade descargar el dossier, lo teníamos
    // hecho"). Con archivos → gate de email que los desbloquea; sin archivos → gate que capta el
    // email como lead y confirma envío. downloadsHTML degrada solo si files está vacío.
    var dossier = '<div style="margin-top:clamp(18px,2.2vw,26px)">'+downloadsHTML((p.downloads&&p.downloads.length)?p.downloads:[],p)+'</div>';
    return '<div class="pdp-infocard">'
      + (overview ? '<div class="kicker">'+t("pd.overview")+'</div><p class="pdp-ic-lead">'+esc(overview)+'</p>' : "")
      + specsGrid
      + (map ? '<div style="margin-top:clamp(16px,2vw,22px)">'+map+'</div>' : "")
      + dossier
      + '</div>';
  }

  // ── Planta 3D del territorio (revisión cliente 23-jul): va en la columna derecha, a la altura
  //    del masterplan/configurador de la izquierda. Campo p.plan3dImage del admin; si está vacío no
  //    se pinta nada (nunca un placeholder).
  function plan3dHTML(p){
    if(!p.plan3dImage) return "";
    var url = imgUrl(p.plan3dImage, 1600);
    if(!url) return "";
    return '<figure class="pdp-plan3d">'
      + '<div class="kicker">'+tl("The Territory","El territorio")+'</div>'
      + '<img src="'+esc(url)+'" alt="'+esc(tl("3D site plan","Planta 3D"))+' · '+esc(pick(p.title))+'" loading="lazy" onerror="var f=this.closest(\'.pdp-plan3d\'); if(f) f.remove();">'
      + '</figure>';
  }

  // Imagen full-bleed a pantalla completa (referencia Ficha p3): ancho total, sin márgenes (fuera del .wrap).
  function fullBleedImageHTML(p){
    var key = (p.imgKeys&&p.imgKeys[2]) || (p.imgKeys&&p.imgKeys[1]) || firstImg(p);
    if(!key) return "";
    return '<div style="margin:clamp(48px,6vw,84px) 0;overflow:hidden;background:#1a160f">'
      + '<img src="'+esc(imgUrl(key,2600))+'" alt="'+esc(pick(p.title))+'" loading="lazy" style="display:block;width:100%;height:clamp(360px,82vh,780px);object-fit:cover" onerror="this.style.display=\'none\'">'
      + '</div>';
  }

  // ── Aéreo con hotspots (guía Ficha p3): imagen full-bleed + puntos con línea y etiqueta (2 líneas:
  //    fina + negrita) + "Entry price" abajo-dcha. Datos por propiedad desde el admin (p.aerial).
  //    AERIALS es el fallback del flagship palm-field, cargado antes de que existiera el campo en admin:
  //    en cuanto el cliente lo introduzca en admin.html, p.aerial manda y esta constante puede morir.
  var AERIALS = {
    "palm-field": {
      image: "assets/img/palm-field-aerial.jpg",
      ratio: "2806/1504",
      entryPriceEUR: 95000,
      hotspots: [
        { x:31, y:30, side:"left",  en:{l1:"Gentle", l2:"natural slopes"},          es:{l1:"Pendientes", l2:"naturales suaves"} },
        { x:43, y:24, side:"top",   en:{l1:"Private", l2:"Parking"},                 es:{l1:"Parking", l2:"privado"} },
        { x:64, y:45, side:"right", en:{l1:"High-value", l2:"Investment Area"},      es:{l1:"Zona de alta", l2:"revalorización"} },
        { x:36, y:53, side:"left",  en:{l1:"Your own", l2:"FREEHOLD villa"},         es:{l1:"Tu propia", l2:"villa en FREEHOLD"} },
        { x:43, y:79, side:"left",  en:{l1:"Lifestyle based on", l2:"Safety & comfort"}, es:{l1:"Un estilo de vida de", l2:"seguridad y confort"} }
      ]
    }
  };

  function aerialHotspotsHTML(p){
    var a = p.aerial || AERIALS[p.id];
    if(!a || !a.image) return "";
    var dot = function(h){ return '<span class="pdp-hs" style="position:absolute;left:'+h.x+'%;top:'+h.y+'%;transform:translate(-50%,-50%);width:14px;height:14px;border-radius:999px;border:2px solid #fff;background:rgba(255,255,255,.18);box-shadow:0 0 0 4px rgba(10,14,10,.14);z-index:4"></span>'; };
    var labelTxt = function(h){ var o=h[S.lang]||h.en||{}; return '<span style="font-weight:400">'+esc(o.l1)+'</span><br><b style="font-weight:700">'+esc(o.l2)+'</b>'; };
    var line = 'height:1px;background:rgba(255,255,255,.8);width:clamp(56px,7vw,120px);flex:none';
    var lab = 'font-family:var(--sans);color:#fff;font-size:clamp(14px,1.35vw,19px);line-height:1.25;text-shadow:0 1px 12px rgba(0,0,0,.55)';
    var spots = (a.hotspots||[]).map(function(h){
      var d = dot(h);
      if(h.side==="top"){
        return d + '<div class="pdp-hs" style="position:absolute;left:'+h.x+'%;top:'+h.y+'%;transform:translate(-50%,-100%);padding-bottom:16px;text-align:center;z-index:4;white-space:nowrap"><div style="'+lab+'">'+labelTxt(h)+'</div></div>';
      }
      if(h.side==="right"){
        return d + '<div class="pdp-hs" style="position:absolute;top:'+h.y+'%;left:'+h.x+'%;transform:translateY(-50%);display:flex;align-items:center;z-index:4;white-space:nowrap;padding-left:9px"><div style="'+line+'"></div><div style="'+lab+';text-align:left;padding-left:14px">'+labelTxt(h)+'</div></div>';
      }
      // left (por defecto): etiqueta a la izquierda, línea hacia el punto
      return d + '<div class="pdp-hs" style="position:absolute;top:'+h.y+'%;right:calc(100% - '+h.x+'%);transform:translateY(-50%);display:flex;align-items:center;z-index:4;white-space:nowrap;padding-right:9px"><div style="'+lab+';text-align:right;padding-right:14px">'+labelTxt(h)+'</div><div style="'+line+'"></div></div>';
    }).join("");
    var price = a.entryPriceEUR ? '<div style="position:absolute;right:clamp(22px,4vw,64px);bottom:clamp(34px,7vh,86px);text-align:right;color:#fff;z-index:4;text-shadow:0 2px 16px rgba(0,0,0,.5)">'
      + '<div style="font-family:var(--sans);font-size:clamp(12px,1.2vw,16px);font-weight:500;letter-spacing:.18em;text-transform:uppercase;display:inline-flex;align-items:center;gap:9px">'+tl("Entry price","Precio de entrada")+' <span style="font-size:1.2em;font-weight:300">›</span></div>'
      + '<div class="display" style="font-size:clamp(38px,6.2vw,86px);font-weight:300;letter-spacing:.02em;line-height:1;margin-top:8px">'+priceHTML(a.entryPriceEUR,true)+'</div></div>' : "";
    return '<div class="pdp-aerial" style="position:relative;width:100%;aspect-ratio:'+(a.ratio||"16/9")+';max-height:92vh;overflow:hidden;background:#1a160f;margin:clamp(48px,6vw,84px) 0">'
      + '<img src="'+esc(a.image)+'" alt="'+esc(pick(p.title))+'" loading="lazy" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover">'
      + '<div style="position:absolute;inset:0;z-index:2;background:linear-gradient(90deg,rgba(10,14,10,.4) 0%,rgba(10,14,10,.08) 26%,transparent 50%),linear-gradient(0deg,rgba(10,14,10,.55) 0%,rgba(10,14,10,.05) 26%,transparent 45%)"></div>'
      + spots + price
      + '</div>';
  }

  // (territoryHTML y principlesHTML "Designed to last" eliminados — revisión cliente 23-jul; su
  //  contenido lo sustituye la sección 50/50 de splitSectionHTML)

  function downloadsHTML(files, p){
    files = files || [];
    var head = '<div style="font-size:9px;font-weight:700;letter-spacing:.2em;text-transform:uppercase;color:var(--ink-2);margin-bottom:12px">'+tl("Dossier","Dossier")+'</div>';
    var inner;
    if(S.dlUnlocked && !files.length){
      // Sin archivos cargados aún: el email quedó captado como lead; se confirma el envío manual.
      inner = '<div style="display:flex;align-items:center;gap:7px;font-size:11px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;color:var(--tg);margin-bottom:8px"><span style="width:7px;height:7px;border-radius:999px;background:var(--tg)"></span> '+tl("Request received","Solicitud recibida")+'</div>'
        + '<p style="font-size:12.5px;color:var(--ink-2);line-height:1.5;margin:0">'+tl("Thank you — we'll email the full dossier to you shortly.","Gracias — te enviaremos el dossier completo por email en breve.")+'</p>';
    } else if(S.dlUnlocked){
      var rows = files.map(function(f,i){
        var dl = f.url ? '<a href="'+esc(f.url)+'" target="_blank" rel="noopener" download style="border:1px solid var(--line);border-radius:4px;padding:4px 10px;font-size:11px;color:var(--tg);font-family:var(--sans);text-decoration:none">↓</a>'
                       : '<span style="border:1px solid var(--line);border-radius:4px;padding:4px 10px;font-size:11px;color:var(--ink-2);font-family:var(--sans)">↓</span>';
        return '<div style="display:flex;justify-content:space-between;align-items:center;padding:9px 0;border-bottom:'+(i<files.length-1?"1px solid var(--line)":"none")+'">'
          + '<div style="display:flex;align-items:center;gap:10px"><div style="width:28px;height:28px;background:var(--tg-light);border-radius:4px;display:flex;align-items:center;justify-content:center;font-size:8px;font-weight:700;color:var(--tg)">'+(f.ext||"PDF")+'</div>'
          + '<div><div style="font-size:13px">'+esc(f.name)+'</div><div style="font-size:11px;color:var(--ink-2)">'+esc(f.size||"")+(f.size?" · ":"")+(f.url?"":t("dl.coming"))+'</div></div></div>'+dl+'</div>';
      }).join("");
      inner = '<div style="display:flex;align-items:center;gap:7px;font-size:11px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;color:var(--tg);margin-bottom:8px"><span style="width:7px;height:7px;border-radius:999px;background:var(--tg)"></span> '+t("dl.unlocked")+'</div>'+rows;
    } else {
      var locked = files.length ? '<div style="margin-bottom:14px">'+files.map(function(f){ return '<div style="display:flex;align-items:center;gap:10px;padding:6px 0;opacity:.5"><div style="width:26px;height:26px;background:var(--tg-light);border-radius:4px;display:flex;align-items:center;justify-content:center;font-size:8px;font-weight:700;color:var(--tg)">'+(f.ext||"PDF")+'</div><div style="font-size:13px">'+esc(f.name)+'</div></div>'; }).join("")+'</div>' : "";
      inner = '<form data-act="dl-submit">'+locked
        + '<p style="font-size:12.5px;color:var(--ink);font-weight:600;line-height:1.4;margin-bottom:10px">'+t("dl.gate.title")+'</p>'
        + '<input type="email" id="dl-email" value="'+esc(S.dlEmail)+'" placeholder="you@email.com" aria-label="Email" style="width:100%;padding:10px 12px;border:1px solid '+(S.dlErr?"#b3402e":"var(--line)")+';border-radius:6px;font-size:14px;font-family:var(--sans);margin-bottom:'+(S.dlErr?"6px":"10px")+';background:white;box-sizing:border-box">'
        + (S.dlErr?'<div style="font-size:11.5px;color:#b3402e;margin-bottom:10px">'+t("dl.gate.invalid")+'</div>':"")
        + '<button type="submit" style="width:100%;background:var(--clay);color:var(--bone);border:none;border-radius:6px;padding:11px;font-size:13px;font-weight:700;cursor:pointer;font-family:var(--sans)">'+t("dl.gate.cta")+' →</button>'
        + '<p style="font-size:11px;color:var(--ink-2);line-height:1.5;margin-top:10px;opacity:.85">'+t("dl.gate.note")+'</p></form>';
    }
    return '<div style="padding:18px;background:var(--bone);border:1px solid var(--line);border-radius:8px">'+head+inner+'</div>';
  }

  // El sidebar "Entry price / Location / Legal" desapareció con el calco de la guía (jul-2026):
  // el precio ya vive en la cabecera y en el aéreo, y lo legal pasó a la franja de specs.

  function investmentCalcHTML(p, priceEUR){
    var price = priceEUR!=null?priceEUR:p.priceEUR;
    var rateEUR = p.nightlyRate||150;
    var MGMT=0.20, occs=[0.70,0.80,0.90], yrs=[1,5,10,20,30];
    var annNet=function(o){return rateEUR*365*o*(1-MGMT);};
    var cum=function(o,y){return Math.round(annNet(o)*y);};
    var roi30=function(o){return ((cum(o,30)/price)*100).toFixed(0);};
    var beYr=function(o){return (price/annNet(o)).toFixed(1);};
    var th='padding:10px 8px;font-weight:700;font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:var(--tg)';
    var td=function(b){return 'padding:10px 8px;font-family:var(--sans);font-size:14px;font-weight:'+(b?600:400)+';text-align:right';};
    var table="";
    if(S.calcTable){
      table = '<div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse;font-size:13px"><thead><tr style="border-bottom:2px solid var(--ink)"><th style="'+th+';text-align:left;color:var(--ink-2)">Year</th>'
        + occs.map(function(o){return '<th style="'+th+'">'+Math.round(o*100)+'% occ.</th>';}).join("")+'</tr></thead><tbody>'
        + yrs.map(function(y){ return '<tr style="border-bottom:1px solid var(--line);background:'+(y===30?"var(--tg-light)":"transparent")+'"><td style="padding:10px 8px;font-weight:'+(y===30?600:400)+';font-size:13px">Year '+y+'</td>'+occs.map(function(o){return '<td style="'+td(y===30)+'">'+money(cum(o,y))+'</td>';}).join("")+'</tr>'; }).join("")
        + '<tr style="border-top:2px solid var(--ink);background:var(--bone-2)"><td style="padding:10px 8px;font-size:11px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--ink-2)">ROI 30yr</td>'+occs.map(function(o){return '<td style="'+td(true)+';color:var(--tg)">'+roi30(o)+'%</td>';}).join("")+'</tr>'
        + '<tr style="border-bottom:1px solid var(--line)"><td style="padding:8px 8px;font-size:11px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--ink-2)">Break-even</td>'+occs.map(function(o){return '<td style="padding:8px 8px;text-align:right;font-size:13px;color:var(--ink-2)">'+beYr(o)+' yr</td>';}).join("")+'</tr>'
        + '</tbody></table></div>';
    }
    return '<div style="margin-top:40px;padding-top:36px;border-top:1px solid var(--line)"><h4 class="serif" style="font-size:clamp(19px,1.9vw,23px);font-weight:500;letter-spacing:.04em;text-transform:uppercase;color:#42210B;margin-bottom:20px">'+t("inv.title")+'</h4>'
      + '<div style="display:grid;grid-template-columns:1fr 1fr;gap:2px;background:var(--line);border:1px solid var(--line);border-radius:8px;overflow:hidden;margin-bottom:24px">'
      +   '<div style="background:var(--tg-light);padding:20px 18px"><div style="font-size:9px;font-weight:600;letter-spacing:.2em;text-transform:uppercase;color:var(--clay);margin-bottom:8px">ROI 30 yr · 80% occ.</div><div style="font-family:var(--sans);font-size:34px;font-weight:500;color:var(--tg);line-height:1">'+roi30(0.80)+'%</div></div>'
      +   '<div style="background:var(--tg-light);padding:20px 18px"><div style="font-size:9px;font-weight:600;letter-spacing:.2em;text-transform:uppercase;color:var(--clay);margin-bottom:8px">Break-even · 80% occ.</div><div style="font-family:var(--sans);font-size:34px;font-weight:500;color:var(--tg);line-height:1">'+beYr(0.80)+' <span style="font-size:18px;opacity:.6">yr</span></div></div>'
      + '</div>'
      + '<button data-act="calc-toggle" style="background:none;border:none;cursor:pointer;font-size:12px;font-weight:600;letter-spacing:.08em;color:var(--clay);font-family:var(--sans);padding:6px 0;display:flex;align-items:center;gap:6px;margin-bottom:'+(S.calcTable?"16px":"0")+'">'+(S.calcTable?"Hide projections ↑":"View full projections ↓")+'</button>'
      + table
      + '<p style="font-size:11px;color:var(--ink-2);margin-top:14px;line-height:1.6;opacity:.7">'+t("inv.disclaimer")+'</p></div>';
  }

  function paymentPlanHTML(p, priceEUR){
    var price = priceEUR!=null?priceEUR:p.priceEUR;
    if(!price || !isFinite(price)) return "";  // sin precio no hay % que calcular -> ocultar en vez de mostrar NaN
    var steps = (p.paymentPlan&&p.paymentPlan.length)?p.paymentPlan:L.getPaymentPlan(p);
    if(!steps || !steps.length) return "";
    var rows = steps.map(function(s,i){ return '<div style="display:grid;grid-template-columns:44px 1fr auto;gap:16px;align-items:start;padding:18px 0;border-bottom:1px solid var(--line)">'
      + '<div style="font-family:var(--sans);font-size:22px;font-weight:300;color:var(--clay);line-height:1;padding-top:4px;opacity:'+(i===0?1:0.45)+'">'+s.step+'</div>'
      + '<div><div style="font-size:14px;font-weight:600;margin-bottom:4px">'+esc(s.label)+'</div><div style="font-size:12.5px;color:var(--ink-2);line-height:1.5">'+esc(s.note)+'</div></div>'
      + '<div style="text-align:right"><div style="font-family:var(--sans);font-size:16px;font-weight:600">'+money(Math.round(price*s.pct/100))+'</div><div style="font-size:11px;color:var(--ink-2);margin-top:2px">'+s.pct+'%</div></div></div>'; }).join("");
    return '<div><h4 class="serif" style="font-size:clamp(19px,1.9vw,23px);font-weight:500;letter-spacing:.04em;text-transform:uppercase;color:#42210B;margin-bottom:22px">'+t("pay.title")+'</h4>'+rows
      + '<div style="display:flex;justify-content:space-between;padding:14px 0;border-top:2px solid var(--ink)"><span style="font-weight:700;font-size:14px">Total</span><span style="font-family:var(--sans);font-size:18px;font-weight:700">'+money(price)+'</span></div>'
      + '<p style="font-size:11.5px;color:var(--ink-2);margin-top:14px;line-height:1.65">PT PMA formation (~€1,000) is coordinated separately. Financing options for qualified investors available on request.</p></div>';
  }

  function configState(p){
    var landOptions=resolveLand(p), models=resolveHomes(p), extrasList=resolveExtras(p);
    var safeParcel=(landOptions&&S.parcelIdx>=0&&S.parcelIdx<landOptions.length)?S.parcelIdx:-1;
    var safeModel=(models&&S.modelIdx>=0&&S.modelIdx<models.length)?S.modelIdx:-1;
    var parcelEUR=(landOptions&&landOptions[safeParcel])?(Number(landOptions[safeParcel].priceEUR)||0):0;
    var homeEUR=(models&&models[safeModel])?(Number(models[safeModel].priceEUR)||0):0;
    var extrasTotal=extrasList?extrasList.reduce(function(s,e,i){return S.extrasSel[i]?s+(Number(e.priceEUR)||0):s;},0):0;
    var configuredEUR=(landOptions||models)?(parcelEUR+homeEUR+extrasTotal):(p.priceEUR+extrasTotal);
    return {landOptions:landOptions,models:models,extrasList:extrasList,parcelIdx:safeParcel,modelIdx:safeModel,parcelEUR:parcelEUR,homeEUR:homeEUR,extrasTotal:extrasTotal,configuredEUR:configuredEUR};
  }

  function parcelStepHTML(p, cfg, bare){
    if(!cfg.landOptions) return "";
    var grid='<div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:12px">'+cfg.landOptions.map(function(o,i){var on=i===cfg.parcelIdx;
      return '<button data-act="parcel:'+i+'" style="text-align:left;padding:16px 16px 18px;border:2px solid '+(on?"var(--clay)":"var(--line)")+';border-radius:10px;cursor:pointer;background:'+(on?"var(--tg-light)":"var(--bone-2)")+'"><div style="font-family:var(--sans);font-size:24px;font-weight:600;line-height:1">'+o.size+' <span style="font-size:13px;font-weight:500">m²</span></div><div style="font-size:14px;font-weight:600;margin-top:10px">'+priceHTML(o.priceEUR,true)+'</div>'+(on?'<div style="font-size:9px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--clay);margin-top:8px">✓ '+t("home.selected")+'</div>':"")+'</button>';
    }).join("")+'</div>';
    if(bare) return grid;
    return '<div style="margin-top:56px;padding-top:40px;border-top:1px solid var(--line)"><div class="kicker" style="margin-bottom:8px">'+t("land.title")+'</div><p style="font-size:14.5px;color:var(--ink-2);margin-bottom:24px;max-width:46ch">'+t("land.sub")+'</p>'+grid+'</div>';
  }
  function chooseHomeHTML(p, cfg, bare){
    if(!cfg.models) return "";
    var grid='<div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:14px">'+cfg.models.map(function(m,i){var on=i===cfg.modelIdx;
      return '<button data-act="model:'+i+'" style="text-align:left;padding:0;border:2px solid '+(on?"var(--clay)":"var(--line)")+';border-radius:10px;overflow:hidden;cursor:pointer;background:var(--bone-2)"><div style="position:relative;aspect-ratio:4/3">'+(m.image?'<img src="'+esc(m.image)+'" alt="'+esc(m.name)+'" loading="lazy" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover">':'<div class="ph-grad ph-'+themeFor(p)+'" style="position:absolute;inset:0"></div>')+(on?'<span style="position:absolute;top:8px;right:8px;background:var(--clay);color:var(--bone);font-size:9px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;padding:3px 8px;border-radius:999px">'+t("home.selected")+'</span>':"")+'</div><div style="padding:12px 14px 14px"><div class="serif" style="font-size:19px">'+esc(m.name)+'</div><div style="font-size:12px;color:var(--ink-2);margin-top:4px">'+m.beds+' '+t("home.beds")+' · '+m.built+' m²</div><div style="font-size:14px;font-weight:600;margin-top:8px">'+priceHTML(m.priceEUR,true)+'</div></div></button>';
    }).join("")+'</div>';
    if(bare) return grid;
    return '<div style="margin-top:56px;padding-top:40px;border-top:1px solid var(--line)"><div class="kicker" style="margin-bottom:8px">'+t("home.title")+'</div><p style="font-size:14.5px;color:var(--ink-2);margin-bottom:24px;max-width:46ch">'+t("home.sub")+'</p>'+grid+'</div>';
  }
  function extrasBlockHTML(p, cfg, bare){
    if(!cfg.extrasList) return "";
    var list='<div style="border:1px solid var(--line);border-radius:10px;overflow:hidden">'+cfg.extrasList.map(function(e,i){var on=!!S.extrasSel[i];
      return '<div style="display:flex;align-items:center;justify-content:space-between;gap:14px;padding:14px 16px;border-bottom:'+(i<cfg.extrasList.length-1?"1px solid var(--line)":"none")+';background:'+(on?"var(--tg-light)":"transparent")+'"><div style="min-width:0"><div style="font-size:14.5px;font-weight:600">'+esc(e.name)+'</div>'+(e.note?'<div style="font-size:12px;color:var(--ink-2);margin-top:2px">'+esc(e.note)+'</div>':"")+'</div><div style="display:flex;align-items:center;gap:14px;flex-shrink:0"><span style="font-family:var(--sans);font-size:15px;font-weight:600">'+(e.priceEUR?money(e.priceEUR):"—")+'</span><button data-act="extra:'+i+'" style="border:1px solid '+(on?"var(--clay)":"var(--line)")+';background:'+(on?"var(--clay)":"transparent")+';color:'+(on?"var(--bone)":"var(--ink)")+';border-radius:999px;padding:6px 16px;font-size:12.5px;font-weight:600;cursor:pointer;font-family:var(--sans);white-space:nowrap">'+(on?("✓ "+t("extras.added")):t("extras.add"))+'</button></div></div>';
    }).join("")+'</div>';
    var totalBar = cfg.extrasTotal>0 ? '<div style="display:flex;justify-content:space-between;align-items:center;margin-top:16px;padding-top:14px;border-top:2px solid var(--ink)"><span style="font-weight:700;font-size:13.5px;text-transform:uppercase;letter-spacing:.06em">'+t("extras.total")+'</span><span style="font-family:var(--sans);font-size:18px;font-weight:700">+'+money(cfg.extrasTotal)+'</span></div>' : "";
    var body=list+totalBar;
    if(bare) return body;
    return '<div style="margin-top:56px;padding-top:40px;border-top:1px solid var(--line)"><div class="kicker" style="margin-bottom:8px">'+t("extras.title")+'</div><p style="font-size:14.5px;color:var(--ink-2);margin-bottom:20px;max-width:46ch">'+t("extras.sub")+'</p>'+body+'</div>';
  }

  function financialsHTML(p, cfg, bare){
    var configuredEUR=cfg.configuredEUR!=null?cfg.configuredEUR:p.priceEUR;
    var parcel=(cfg.landOptions&&cfg.landOptions[cfg.parcelIdx])||null;
    var model=(cfg.models&&cfg.models[cfg.modelIdx])||null;
    var selExtras=(cfg.extrasList||[]).filter(function(e,i){return S.extrasSel[i];});
    var showBreak=!!(parcel||model||selExtras.length);
    var bRow='display:flex;justify-content:space-between;align-items:baseline;font-size:14px;padding:4px 0';
    var breakdown="";
    if(showBreak){
      breakdown='<div style="background:var(--tg-light);border:1px solid rgba(72,91,55,.2);border-radius:10px;padding:16px 18px;margin-bottom:28px"><div style="font-size:9px;font-weight:700;letter-spacing:.18em;text-transform:uppercase;color:var(--clay);margin-bottom:12px">'+t("fin.config")+'</div>'
        + (parcel?'<div style="'+bRow+'"><span style="font-weight:600">'+t("cfg.step.land")+' · '+parcel.size+' m²</span><span style="font-family:var(--sans);font-size:15px;font-weight:600">'+money(cfg.parcelEUR)+'</span></div>':"")
        + (model?'<div style="'+bRow+'"><span style="font-weight:600">'+esc(model.name)+'</span><span style="font-family:var(--sans);font-size:15px;font-weight:600">'+money(cfg.homeEUR)+'</span></div>':"")
        + (!parcel&&!model?'<div style="'+bRow+'"><span style="font-weight:600">'+t("fin.base")+'</span><span style="font-family:var(--sans);font-size:15px;font-weight:600">'+money(p.priceEUR)+'</span></div>':"")
        + selExtras.map(function(e){return '<div style="'+bRow+';color:var(--ink-2)"><span>+ '+esc(e.name)+'</span><span>'+money(Number(e.priceEUR)||0)+'</span></div>';}).join("")
        + '<div style="display:flex;justify-content:space-between;align-items:baseline;padding-top:10px;margin-top:6px;border-top:1px solid rgba(72,91,55,.22)"><span style="font-weight:700;font-size:12.5px;text-transform:uppercase;letter-spacing:.06em">'+t("fin.total")+'</span><span style="font-family:var(--sans);font-size:20px;font-weight:700">'+money(configuredEUR)+'</span></div></div>';
    }
    var paymentPlan = paymentPlanHTML(p,configuredEUR);
    var investmentCalc = p.nightlyRate>0 ? investmentCalcHTML(p,configuredEUR) : "";
    var body = breakdown+paymentPlan+investmentCalc;
    if(!body) return "";  // sin desglose, sin plan de pagos y sin ROI -> no hay nada que mostrar en este bloque
    var inner=(bare?"":'<div class="kicker" style="margin-bottom:24px">'+t("fin.title")+'</div>')+body;
    return bare?'<div>'+inner+'</div>':'<div style="margin-top:56px;padding-top:40px;border-top:1px solid var(--line)">'+inner+'</div>';
  }

  // Reserva por WhatsApp con el resumen configurado (parcela/modelo/extras/total/depósito)
  function reserveWaUrl(p, cfg){
    var waNum=(L.SETTINGS&&L.SETTINGS.whatsapp)||'6281138319862';
    var plan=(p.paymentPlan&&p.paymentPlan.length)?p.paymentPlan:L.getPaymentPlan(p);
    var pct=(plan&&plan[0]&&plan[0].pct)||0;
    var total=cfg.configuredEUR!=null?cfg.configuredEUR:p.priceEUR;
    var parcel=(cfg.landOptions&&cfg.landOptions[cfg.parcelIdx])||null;
    var model=(cfg.models&&cfg.models[cfg.modelIdx])||null;
    var selExtras=(cfg.extrasList||[]).filter(function(e,i){return S.extrasSel[i];});
    var lines=[t("reserve.msg"),"","• "+pick(p.title)];
    if(parcel) lines.push("• "+t("cfg.step.land")+" · "+parcel.size+" m² ("+money(parcel.priceEUR)+")");
    if(model)  lines.push("• "+model.name+" ("+money(model.priceEUR)+")");
    if(selExtras.length) lines.push("• "+t("cfg.step.extras")+": "+selExtras.map(function(e){return e.name;}).join(", "));
    lines.push("", t("fin.total")+": "+money(total));
    if(pct) lines.push(t("glance.deposit")+" ("+pct+"%): "+money(Math.round(total*pct/100)));
    return 'https://wa.me/'+waNum+'?text='+encodeURIComponent(lines.join("\n"));
  }

  function configuratorHTML(p, cfg){
    var steps=[];
    if(cfg.landOptions) steps.push({id:"land",label:t("cfg.step.land"),title:t("land.title"),sub:t("land.sub"),required:true,done:cfg.parcelIdx>=0,content:parcelStepHTML(p,cfg,true)});
    if(cfg.models)      steps.push({id:"home",label:t("cfg.step.home"),title:t("home.title"),sub:t("home.sub"),required:true,done:cfg.modelIdx>=0,content:chooseHomeHTML(p,cfg,true)});
    if(cfg.extrasList)  steps.push({id:"extras",label:t("cfg.step.extras"),title:t("extras.title"),sub:t("extras.sub"),required:false,done:true,content:extrasBlockHTML(p,cfg,true)});
    steps.push({id:"pay",label:t("cfg.step.pay"),title:t("fin.title"),sub:null,required:false,done:true,content:financialsHTML(p,cfg,true)});
    var idx=Math.min(S.step,steps.length-1); var sObj=steps[idx]; var isLast=idx>=steps.length-1;
    var reachable=function(i){ return i===0 || steps.slice(0,i).every(function(x){return !x.required||x.done;}); };
    var canNext=!sObj.required||sObj.done;
    var prog=steps.map(function(st,i){var on=i===idx;var ok=reachable(i);var complete=st.required&&st.done&&i!==idx;
      return (i>0?'<span style="width:14px;height:1px;background:var(--line)"></span>':"")
        +'<button '+(ok?'data-act="step:'+i+'"':'disabled')+' style="display:inline-flex;align-items:center;gap:8px;border:1px solid '+(on?"var(--clay)":"var(--line)")+';background:'+(on?"var(--clay)":"transparent")+';color:'+(on?"var(--bone)":(ok?"var(--ink)":"var(--ink-2)"))+';border-radius:999px;padding:6px 14px 6px 7px;font-family:var(--sans);font-size:12.5px;font-weight:600;cursor:'+(ok?"pointer":"default")+';opacity:'+(ok?1:0.5)+'"><span style="width:20px;height:20px;border-radius:999px;display:grid;place-items:center;font-size:11px;font-weight:700;background:'+(on?"rgba(255,255,255,.22)":(complete?"var(--clay)":"var(--bone-2)"))+';color:'+((on||complete)?"var(--bone)":"var(--ink-2)")+'">'+(complete?"✓":(i+1))+'</span>'+st.label+'</button>';
    }).join("");
    var totalChip = cfg.configuredEUR>0 ? '<div style="margin-left:auto;text-align:right"><div style="font-size:9px;font-weight:700;letter-spacing:.16em;text-transform:uppercase;color:var(--ink-2)">'+t("fin.total")+'</div><div style="font-family:var(--sans);font-size:19px;font-weight:700;line-height:1">'+money(cfg.configuredEUR)+'</div></div>' : "";
    var stepHead = sObj.id!=="pay" ? '<div style="margin-bottom:18px"><h4 class="serif" style="font-size:clamp(19px,1.9vw,23px);font-weight:500;letter-spacing:.04em;text-transform:uppercase;color:#42210B">'+sObj.title+'</h4>'+(sObj.sub?'<p style="font-size:14px;color:var(--ink-2);margin-top:6px;max-width:46ch">'+sObj.sub+'</p>':"")+'</div>' : "";
    var nextBtn = !isLast
      ? '<button '+(canNext?'data-act="step:'+(idx+1)+'"':'disabled')+' style="background:'+(canNext?"var(--clay)":"var(--line)")+';color:var(--bone);border:none;border-radius:999px;padding:11px 26px;font-family:var(--sans);font-size:13px;font-weight:700;cursor:'+(canNext?"pointer":"default")+'">'+((sObj.id==="extras"&&cfg.extrasTotal===0)?t("cfg.skip"):t("cfg.next"))+' →</button>'
      : '<div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;justify-content:flex-end">'
        + '<button data-act="cfg-reset" style="background:none;border:1px solid var(--line);border-radius:999px;padding:10px 20px;font-family:var(--sans);font-size:13px;font-weight:600;cursor:pointer;color:var(--ink-2)">↺ '+t("cfg.restart")+'</button>'
        + '<a href="'+reserveWaUrl(p,cfg)+'" target="_blank" rel="noopener" style="display:inline-flex;align-items:center;gap:8px;background:#25D366;color:#fff;border-radius:999px;padding:12px 26px;font-family:var(--sans);font-size:13px;font-weight:700;text-decoration:none;box-shadow:0 6px 18px -6px rgba(37,211,102,.6)"><svg viewBox="0 0 24 24" fill="currentColor" style="width:17px;height:17px"><path d="M12.04 2C6.58 2 2.13 6.45 2.13 11.91c0 1.75.46 3.45 1.32 4.95L2 22l5.25-1.38a9.9 9.9 0 0 0 4.79 1.22c5.46 0 9.91-4.45 9.91-9.91S17.5 2 12.04 2zm5.8 14.02c-.24.68-1.42 1.3-1.95 1.35-.5.05-.96.24-3.24-.68-2.73-1.08-4.45-3.86-4.58-4.04-.13-.18-1.1-1.46-1.1-2.79s.7-1.98.94-2.25c.24-.27.53-.34.7-.34l.5.01c.16 0 .38-.06.59.45.24.57.8 1.98.87 2.12.07.14.12.31.02.49-.09.18-.14.29-.28.45l-.42.49c-.14.14-.28.29-.12.57.16.28.72 1.19 1.55 1.93 1.06.95 1.96 1.24 2.24 1.38.28.14.44.12.6-.07.16-.18.69-.8.87-1.08.18-.28.36-.23.6-.14.24.09 1.55.73 1.82.87.27.14.44.2.5.31.07.11.07.63-.17 1.31z"/></svg>'+t("reserve.cta")+' →</a>'
        + '</div>';
    // Guía Ficha p4: kicker "THE MASTERPLAN" + titular verde grande. El titular se construye con
    // datos reales (nº de parcelas y la más pequeña); sin parcelas cargadas cae al título genérico.
    var head = t("cfg.title");
    if(cfg.landOptions && cfg.landOptions.length){
      var sizes = cfg.landOptions.map(function(o){ return Number(o.size)||0; }).filter(Boolean);
      if(sizes.length) head = cfg.landOptions.length+" "+tl("plots","parcelas")+". "+tl("From","Desde")+" "+Math.min.apply(null,sizes)+" m².";
    }
    return '<div style="margin-top:clamp(40px,5vw,64px)"><div class="kicker">'+tl("The Masterplan","El masterplan")+'</div>'
      + '<h3 class="pdp-block-h">'+esc(head)+'</h3>'
      + '<p style="font-size:14.5px;color:var(--ink-2);margin:14px 0 22px;max-width:46ch">'+t("cfg.sub")+'</p>'
      + '<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:26px">'+prog+totalChip+'</div>'
      + '<div class="cfg-step">'+stepHead+sObj.content+'</div>'
      + '<div style="display:flex;justify-content:space-between;align-items:center;gap:12px;margin-top:30px;padding-top:20px;border-top:1px solid var(--line)">'
      +   '<button '+(idx===0?'disabled':'data-act="step:'+(idx-1)+'"')+' style="background:none;border:1px solid var(--line);border-radius:999px;padding:10px 20px;font-family:var(--sans);font-size:13px;font-weight:600;cursor:'+(idx===0?"default":"pointer")+';opacity:'+(idx===0?0.4:1)+';color:var(--ink)">← '+t("cfg.back")+'</button>'+nextBtn
      + '</div></div>';
  }

  // ghost=true → migas sobre el hero (guía Ficha p1): crema, esquina superior izquierda del hero
  function breadcrumbsHTML(p, ghost){
    var col   = ghost ? 'rgba(245,240,230,.78)' : 'var(--ink-2)';
    var colOn = ghost ? 'var(--bone)' : 'var(--ink)';
    var shadow= ghost ? 'text-shadow:0 1px 10px rgba(0,0,0,.55);' : '';
    var sep='<span aria-hidden="true" style="opacity:.75;margin:0 11px">›</span>';
    // uppercase explícito: el reset de <button> del tema pisa el text-transform heredado del <nav>
    var lk=function(label,act){ return '<button data-act="'+act+'" style="background:none;border:none;padding:0;cursor:pointer;font:inherit;text-transform:uppercase;letter-spacing:.16em;color:'+col+'">'+esc(label)+'</button>'; };
    return '<nav aria-label="Breadcrumb" style="font-family:var(--sans);font-size:clamp(10px,1vw,12.5px);font-weight:400;text-transform:uppercase;letter-spacing:.16em;display:flex;flex-wrap:wrap;align-items:center;'+shadow+(ghost?'':'margin-bottom:22px')+'">'
      + lk(t("crumb.home"),"go-home")+sep+lk(t("crumb.portfolio"),"close")+sep+lk(t(LINE_KEYS[p.line]),"close")+sep+'<span style="color:'+colOn+';letter-spacing:.16em;font-weight:'+(ghost?'600':'500')+'">'+esc(pick(p.title))+'</span></nav>';
  }

  // El campo "mapImage" del admin recibe indistintamente una imagen subida o un enlace de Google Maps
  // (el cliente pegó https://maps.app.goo.gl/… en Palm Field y salía un <img> roto en producción).
  // Se decide por la forma del valor: imagen → <img>; cualquier otra URL → botón al mapa; vacío → nada.
  function mapMediaHTML(url, pins){
    url = String(url||"").trim();
    if(!url) return '';
    if(/\.(jpe?g|png|webp|avif|gif|svg)(\?|#|$)/i.test(url) || url.indexOf("/assets/")===0){
      return '<div class="pdp-map" style="position:relative;border-radius:14px;overflow:hidden;border:1px solid var(--line);background:var(--bone-2);min-height:280px">'
        + '<img src="'+esc(url)+'" alt="'+esc(tl("Location map","Mapa de situación"))+'" loading="lazy" style="display:block;width:100%;height:100%;object-fit:cover" onerror="var b=this.closest(\'.pdp-map\'); if(b) b.remove();">'
        + (pins||'') + '</div>';
    }
    if(!/^https?:\/\//i.test(url)) return '';  // ni imagen ni URL navegable -> no se enseña nada roto
    return '<a class="pdp-map" href="'+esc(url)+'" target="_blank" rel="noopener" style="display:inline-flex;align-items:center;gap:10px;border:1px solid var(--line);border-radius:10px;padding:13px 20px;font-family:var(--sans);font-size:14px;font-weight:600;color:var(--tg);text-decoration:none;background:var(--bone-2)">'
      + '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" style="width:17px;height:17px;flex:none" aria-hidden="true"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>'
      + esc(tl("View on Google Maps","Ver en Google Maps"))+' <span aria-hidden="true">↗</span></a>';
  }

  // (mapBlockHTML y processBannerHTML eliminados — revisión cliente 23-jul; el mapa vive ahora en
  //  la card de info y la franja del proceso se retiró)

  function signatureNoteHTML(p){
    return '<div style="margin-top:56px;padding-top:40px;border-top:1px solid var(--line)"><div style="display:inline-flex;align-items:center;gap:8px;background:var(--dl);color:var(--bone);border-radius:999px;padding:7px 16px;font-family:var(--sans);font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase"><span style="width:7px;height:7px;border-radius:999px;background:var(--bone)"></span> '+t("sig.delivered")+'</div><p style="font-size:15px;color:var(--ink-2);line-height:1.6;margin-top:18px;max-width:52ch">'+t("sig.note")+'</p></div>';
  }

  // ── Sección 50/50 (revisión cliente 24-jul). IZQUIERDA: una imagen con título y subtítulo encima,
  //    nada más. DERECHA: los tipos de vivienda en pestañas (Dali, Dune…) — se pulsa un nombre y se
  //    ven SU título, subtítulo, fotos (la activa grande + miniaturas debajo) y texto.
  //    Admin: p.splitImage · p.splitTitle · p.splitSub · p.tabs[{title,sub,body,images[]}].
  function splitSectionHTML(p){
    var tabs = (p.tabs||p.cards||[]).filter(function(tb){ return pick(tb.title)||pick(tb.body)||(tb.images&&tb.images.length); });
    var title = pick(p.splitTitle), sub = pick(p.splitSub);
    if(!tabs.length && !title) return "";   // sin contenido no se pinta media sección vacía
    var key = p.splitImage || (p.imgKeys&&p.imgKeys[0]) || null;
    var url = key ? imgUrl(key, 1800) : null;
    var left = '<div class="pdp-split-img">'
      + (url ? '<img src="'+esc(url)+'" alt="'+esc(title||pick(p.title))+'" loading="lazy" onerror="this.style.display=\'none\'">'
             : '<div class="ph-grad ph-'+themeFor(p)+'" style="position:absolute;inset:0"></div>')
      + ((title||sub) ? '<div class="pdp-split-cap">'
          + (title ? '<h2>'+esc(title)+'</h2>' : '')
          + (sub   ? '<p>'+esc(sub)+'</p>'     : '')
          + '</div>' : '')
      + '</div>';
    return '<section class="pdp-split-section">'+left+tabsPanelHTML(p,tabs)+'</section>';
  }

  // Panel derecho: cabecera de pestañas + contenido de la activa. Una sola pestaña → sin cabecera
  // (un botón solitario que no lleva a ninguna parte solo estorba).
  function tabsPanelHTML(p, tabs){
    if(!tabs.length) return '<div class="pdp-split-panel"></div>';
    var i = Math.min(Math.max(S.tab||0,0), tabs.length-1);
    var tb = tabs[i];
    var head = tabs.length>1 ? '<div class="pdp-tabs-head">'+tabs.map(function(x,n){
      return '<button class="pdp-tab'+(n===i?' on':'')+'" data-act="tab:'+n+'">'+esc(pick(x.title)||(tl("Type","Tipo")+" "+(n+1)))+'</button>';
    }).join("")+'</div>' : "";
    var imgs = (tb.images||[]).filter(Boolean);
    var j = Math.min(Math.max(S.tabImg||0,0), Math.max(imgs.length-1,0));
    var media = "";
    if(imgs.length){
      media = '<div class="pdp-tab-main"><img src="'+esc(imgUrl(imgs[j],1600))+'" alt="'+esc(pick(tb.title))+'" loading="lazy" onerror="this.style.display=\'none\'"></div>';
      if(imgs.length>1){
        media += '<div class="pdp-tab-thumbs">'+imgs.map(function(u,n){
          return '<button class="pdp-tab-thumb'+(n===j?' on':'')+'" data-act="tabimg:'+n+'" aria-label="'+tl("Photo","Foto")+' '+(n+1)+'"><img src="'+esc(imgUrl(u,420))+'" alt="" loading="lazy" onerror="this.style.display=\'none\'"></button>';
        }).join("")+'</div>';
      }
    }
    return '<div class="pdp-split-panel">'+head
      + '<div class="pdp-tab-body">'
      +   (pick(tb.title) ? '<h3>'+esc(pick(tb.title))+'</h3>' : '')
      +   (pick(tb.sub)   ? '<p class="pdp-tab-sub">'+esc(pick(tb.sub))+'</p>' : '')
      +   media
      +   (pick(tb.body)  ? '<p class="pdp-tab-text">'+esc(pick(tb.body))+'</p>' : '')
      + '</div></div>';
  }

  // ── Imagen a sangre bajada (revisión cliente 23-jul): campo dedicado p.bleedImage; si está vacío,
  //    cae a la lógica actual (aéreo con hotspots o foto de galería).
  function bleedSectionHTML(p){
    if(p.bleedImage){
      var url = imgUrl(p.bleedImage, 2600);
      if(url) return '<div style="margin:clamp(48px,6vw,84px) 0;overflow:hidden;background:#1a160f"><img src="'+esc(url)+'" alt="'+esc(pick(p.title))+'" loading="lazy" style="display:block;width:100%;height:clamp(360px,82vh,780px);object-fit:cover" onerror="this.style.display=\'none\'"></div>';
    }
    return aerialHotspotsHTML(p) || fullBleedImageHTML(p);
  }

  function propertyHTML(id){
    var p = propById(id);
    if(!p) return '<div class="wrap" style="padding-top:120px;padding-bottom:120px;text-align:center"><p class="serif" style="font-size:28px">Property not found.</p><button class="btn btn-ghost" data-act="close" style="margin-top:20px">'+t("pd.back")+'</button></div>';
    document.title = pick(p.title)+" · Lawang";
    var cfg = configState(p);
    var isSignature = p.line==="signature";
    var isDeliveredNotForSale = isSignature && !p.priceEUR;  // signature sin precio = ya vendida/showcase; con precio sigue disponible
    var hasConfigurator = !isSignature && !!(cfg.landOptions||cfg.models||cfg.extrasList);
    var also = L.PROPERTIES.filter(function(x){return x.line===p.line&&x.id!==p.id;}).slice(0,3);
    var leftMain = isDeliveredNotForSale ? signatureNoteHTML(p) : (hasConfigurator ? configuratorHTML(p,cfg) : financialsHTML(p,cfg,false));
    var subText = pick(p.sub);
    // Sub bajo el título: uppercase ligera y grande y, en negrita al final, el régimen de tenencia
    // ("… FREEHOLD LAND.") tal cual la guía Ficha p2. El dato sale de p.tenure, no se escribe a mano.
    var tenureTag = p.tenure==="tenure.freehold" ? tl("Freehold land.","Suelo en freehold.")
                  : (p.tenure ? tl("Leasehold "+(p.leaseYears||30)+" yr.","Leasehold "+(p.leaseYears||30)+" años.") : "");
    var subHTML = (subText||tenureTag) ? '<p style="font-family:var(--sans);font-size:clamp(14px,1.5vw,21px);font-weight:300;letter-spacing:.045em;text-transform:uppercase;color:var(--ink);line-height:1.4;margin-top:clamp(14px,1.6vw,22px);max-width:52ch">'+esc(subText)+(tenureTag?(subText?" ":"")+'<b style="font-weight:700">'+esc(tenureTag)+'</b>':'')+'</p>' : "";
    // "More in this line": mismas cards del marketplace/index (LawangCard) — revisión cliente 23-jul.
    var alsoHTML = also.length>0 ? '<div style="margin-top:clamp(56px,7vw,90px);padding-top:clamp(36px,4vw,52px);border-top:1px solid var(--line)"><div class="kicker" style="margin-bottom:clamp(22px,2.6vw,32px)">'+t("pd.also")+'</div><div class="pdp-also-grid">'
      + also.map(function(x){ return (window.LawangCard&&LawangCard.render) ? LawangCard.render(x,{lang:S.lang,cur:S.cur,rates:L.RATES}) : ''; }).join("")
      + '</div></div>' : "";
    // Cabecera: migas + subtítulo a la izquierda; a la derecha SOLO el precio (revisión cliente
    // 23-jul: fuera "LÍNEA › ESTADO" de encima del precio).
    return '<div>'   // sin padding inferior: el footer cierra la página
      + heroHTML(p)
      + '<div class="wrap pdp-wrap" style="padding-top:clamp(36px,4.5vw,64px)">'
      + '<div style="display:flex;justify-content:space-between;align-items:flex-end;gap:clamp(20px,4vw,48px);flex-wrap:wrap;margin-bottom:clamp(26px,3vw,38px)"><div style="flex:1 1 380px;min-width:0">'
      +   breadcrumbsHTML(p,false)+subHTML+'</div>'
      +   '<div style="flex-shrink:0;text-align:right">'
      +     '<div style="font-family:var(--sans);font-size:clamp(30px,3.2vw,44px);font-weight:600;line-height:1;color:var(--ink);white-space:nowrap">'+priceHTML(p.priceEUR,true)+'</div></div></div>'
      + galleryHTML(p)
      // Revisión cliente 23-jul: 2-col — izq 60% tabla blanca + configurador/payment plan en el
      // hueco de abajo · dcha 40% card overview+técnica+dossier.
      + '<div class="pdp-info-2col" style="margin-top:clamp(24px,3vw,34px)">'
      +   '<div>'+techSpecsHTML(p)+(leftMain?'<div class="pdp-leftmain">'+leftMain+'</div>':"")+'</div>'
      +   '<div>'+infoCardHTML(p)+plan3dHTML(p)+'</div>'
      + '</div>'
      + '</div>'  // /wrap
      // Sección 50/50: imagen + título a la izquierda, tarjetas a la derecha
      + splitSectionHTML(p)
      // Sección de imagen a sangre (la que estaba arriba, bajada aquí)
      + bleedSectionHTML(p)
      + '<div class="wrap pdp-wrap">'
      + alsoHTML
      + '</div>'
      + footerCoreHTML()   // mismo footer del marketplace: franja de contacto + footer verde
      + waFloatHTML(p)
      + lightboxHTML(p)
      + '</div>';
  }

  // ════ OVERLAY (ficha sobre el marketplace) ════
  // El menú es el MISMO topbar del index/marketplace (variante ghost): transparente sobre el hero,
  // se colorea al hacer scroll (syncPdpNav). Navegar por él (#all/#land…) cierra la ficha vía onHash.
  function overlayHTML(id){
    return '<div id="pf-overlay">'+topbarHTML(true)+propertyHTML(id)+'</div>';
  }

  // ════ RENDER ════
  var root, renderedOverlay = null;
  function render(){
    // Conserva el scroll del overlay al re-renderizar por una acción (parcela, modelo, extra,
    // paso, idioma, moneda…). Solo si seguimos en la MISMA propiedad; al abrir/cambiar/cerrar empieza arriba.
    var prevEl = document.getElementById("pf-overlay");
    var savedY = (prevEl && renderedOverlay === S.overlay) ? prevEl.scrollTop : null;
    // La ficha lleva su propio topbar (ghost) DENTRO del overlay → no pintar el del marketplace
    // detrás (evita id="topbar" duplicado).
    root.innerHTML = (S.overlay ? "" : topbarHTML()) + marketplaceHTML() + (S.overlay ? overlayHTML(S.overlay) : "");
    document.body.style.overflow = S.overlay ? "hidden" : "";
    if(!S.overlay) document.title = "The Collection · Lawang Tropical Properties";
    if(savedY != null){ var now = document.getElementById("pf-overlay"); if(now) now.scrollTop = savedY; }
    renderedOverlay = S.overlay;
    if(S.overlay){ var ov = document.getElementById("pf-overlay"); if(ov){ syncPdpNav(ov); ov.addEventListener("scroll", function(){ syncPdpNav(ov); }, {passive:true}); } }
    requestAnimationFrame(function(){ root.querySelectorAll(".reveal").forEach(function(el){ el.classList.add("in"); }); });
  }
  // Topbar de la ficha: transparente arriba, .solid al pasar ~el hero, .scrolled (CTA verde) al iniciar scroll.
  function syncPdpNav(ov){
    var tb = ov.querySelector("#topbar.pdp"); if(!tb) return;
    var hero = ov.querySelector(".pdp-hero");
    var solidAt = hero ? hero.offsetHeight*0.72 : 220;
    var y = ov.scrollTop;
    tb.classList.toggle("solid", y > solidAt);
    tb.classList.toggle("scrolled", y > 8);
    var lg = tb.querySelector("#logo"); if(lg) lg.classList.toggle("dark", y > solidAt);
  }

  // ════ ROUTING + EVENTOS ════
  function lineFromHash(){ var h=(location.hash||"").replace(/^#/,"").toLowerCase(); return ({villas:"villa",villa:"villa",signature:"signature",land:"land",resorts:"resorts"})[h]||"all"; }
  function parseHash(){ var h=location.hash.replace(/^#/,""); return h.indexOf("property/")===0 ? h.slice(9) : null; }

  function openProperty(id){ location.hash = "property/"+id; }
  function closeProperty(){ history.replaceState(null,"",location.pathname+location.search); S.overlay=null; render(); }

  function onHash(){
    var pid = parseHash();
    if(pid){ if(pid!==S.overlay){ S.overlay=pid; resetDetail(); render(); } }
    else { if(S.overlay){ S.overlay=null; } S.line=lineFromHash(); render(); }
  }

  function chooseLine(l){ S.line=l; S.page=1; S.featIdx=0; if(l==="all") history.replaceState(null,"",location.pathname+location.search); else history.replaceState(null,"","#"+l); render(); }

  function handleAct(act, el){
    var k=act.split(":"); var cmd=k[0]; var val=k.slice(1).join(":");
    if(cmd==="lang"){ S.lang=val; S.langOpen=false; render(); }
    else if(cmd==="lang-toggle"){ S.langOpen=!S.langOpen; S.curOpen=false; render(); }
    else if(cmd==="cur"){ S.cur=val; S.curOpen=false; render(); }
    else if(cmd==="cur-toggle"){ S.curOpen=!S.curOpen; S.langOpen=false; render(); }
    else if(cmd==="line"){ chooseLine(val); var g=document.getElementById("pf-grid"); if(g) g.scrollIntoView({behavior:"smooth",block:"start"}); }
    else if(cmd==="region"){ S.region=val; S.page=1; S.featIdx=0; render(); }
    else if(cmd==="feat"){ S.featIdx=parseInt(val,10)||0; render(); }
    else if(cmd==="page"){ S.page=parseInt(val,10)||1; render(); var g=document.getElementById("pf-grid"); if(g) g.scrollIntoView({behavior:"smooth",block:"start"}); }
    else if(cmd==="layout"){ S.layout=val; render(); }
    else if(cmd==="gal"){ S.gallery=parseInt(val,10)||0; S.galAnim=true; render(); }
    else if(cmd==="lightbox"){ S.lightbox=parseInt(val,10)||0; render(); }
    // Tipos de vivienda (sección 50/50): cambiar de pestaña arranca sus fotos por la primera
    else if(cmd==="tab"){ S.tab=parseInt(val,10)||0; S.tabImg=0; render(); }
    else if(cmd==="tabimg"){ S.tabImg=parseInt(val,10)||0; render(); }
    else if(cmd==="lb-close"){ S.lightbox=null; render(); }
    // lb-noop: sin rama a propósito — absorbe el click sobre la foto del lightbox sin cerrarlo
    else if(cmd==="calc-toggle"){ S.calcTable=!S.calcTable; render(); }
    else if(cmd==="parcel"){ S.parcelIdx=parseInt(val,10); render(); }
    else if(cmd==="model"){ S.modelIdx=parseInt(val,10); render(); }
    else if(cmd==="extra"){ var i=parseInt(val,10); S.extrasSel[i]=!S.extrasSel[i]; render(); }
    else if(cmd==="step"){ S.step=parseInt(val,10); render(); }
    else if(cmd==="cfg-reset"){ S.parcelIdx=-1; S.modelIdx=-1; S.extrasSel={}; S.step=0; render(); }
    else if(cmd==="close"){ closeProperty(); }
    else if(cmd==="go-home"){ window.location.href="index.html"; }
  }

  function bindEvents(){
    root.addEventListener("click", function(e){
      // data-act ANTES que data-go: los dots del featured (data-act="feat:N") viven
      // dentro del banner clicable (data-go) y no deben abrir la propiedad.
      var a = e.target.closest("[data-act]");
      if(a){
        if(a.tagName==="A") return;            // enlaces nativos (mailto, wa, index)
        if(a.closest("form")) { /* submit lo gestiona el form */ }
        e.preventDefault();
        handleAct(a.getAttribute("data-act"), a);
        return;
      }
      var go = e.target.closest("[data-go]");
      if(go){ openProperty(go.getAttribute("data-go")); return; }
    });
    root.addEventListener("submit", function(e){
      var f=e.target.closest('[data-act="dl-submit"]');
      if(!f) return;
      e.preventDefault();
      var inp=f.querySelector("#dl-email"); var v=(inp&&inp.value||"").trim();
      S.dlEmail=v;
      if(!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v)){ S.dlErr=true; render(); return; }
      S.dlErr=false; S.dlUnlocked=true;
      var pid=S.overlay;
      try{ fetch("api/lead.php",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:"email="+encodeURIComponent(v)+"&source=downloads&property="+encodeURIComponent(pid||"")}).catch(function(){}); }catch(_){}
      render();
    });
    // Swipe táctil en la galería y en el lightbox (en móvil las flechas no bastan: el gesto
    // natural en un carrusel es arrastrar). Delegado en root porque ambos se re-crean al render.
    var galSwipe = null;
    root.addEventListener("touchstart", function(e){
      var g = e.target.closest(".pdp-lb,.pdp-gal2");
      galSwipe = (g && g.hasAttribute("data-next")) ? {el:g, x:e.touches[0].clientX} : null;
    }, {passive:true});
    root.addEventListener("touchend", function(e){
      if(!galSwipe) return;
      var g = galSwipe.el, dx = e.changedTouches[0].clientX - galSwipe.x; galSwipe = null;
      if(Math.abs(dx) < 45) return;   // umbral: no confundir tap/scroll vertical con swipe
      var to = dx < 0 ? g.getAttribute("data-next") : g.getAttribute("data-prev");
      if(to==null) return;
      if(g.classList.contains("pdp-lb")) S.lightbox = parseInt(to,10)||0;
      else { S.gallery = parseInt(to,10)||0; S.galAnim = true; }
      render();
    }, {passive:true});
    window.addEventListener("hashchange", onHash);
    // a11y: Escape cierra el lightbox si está abierto (si no, la ficha); flechas navegan el lightbox
    document.addEventListener("keydown", function(e){
      if(S.lightbox!=null){
        if(e.key==="Escape"){ S.lightbox=null; render(); return; }
        if(e.key==="ArrowLeft"||e.key==="ArrowRight"){
          var lb=document.querySelector(".pdp-lb"); if(!lb) return;
          var to=lb.getAttribute(e.key==="ArrowRight"?"data-next":"data-prev");
          if(to!=null){ S.lightbox=parseInt(to,10)||0; render(); }
        }
        return;
      }
      if(e.key==="Escape" && S.overlay) closeProperty();
    });
    document.addEventListener("click", function(e){
      if((S.langOpen||S.curOpen) && !e.target.closest(".nav-lang-wrap")){ S.langOpen=false; S.curOpen=false; render(); }
    });
  }

  // ════ INIT (carga data.json + tasas, igual que la app React) ════
  function start(){
    root = document.getElementById("portfolio-root");
    if(!root) return;
    S.overlay = parseHash();
    if(!S.overlay) S.line = lineFromHash();
    bindEvents();
    render();
  }

  // El CDN de Hostinger puede servir un data.json truncado para el patron ?_=.
  // Probamos varias formas de query (no-store) y validamos antes de aceptar.
  function fetchDataResilient(){
    var rnd=function(){return Date.now().toString(36)+Math.random().toString(36).slice(2);};
    var shapes=['?cb='+rnd()+'&r='+rnd(),'?nocache='+rnd()+'&v='+rnd(),'?_='+rnd()];
    var i=0;
    function attempt(){
      return fetch('data.json'+shapes[i],{cache:'no-store'})
        .then(function(r){return r.text();})
        .then(function(txt){
          var d=JSON.parse(txt);
          if(d&&typeof d==='object'&&Array.isArray(d.properties)) return d;
          throw new Error('estructura invalida o truncada ('+txt.length+' bytes)');
        })
        .catch(function(e){ i++; if(i<shapes.length) return attempt(); throw e; });
    }
    return attempt();
  }
  fetchDataResilient().then(function(data){
    if(data.properties) L.PROPERTIES = data.properties;
    if(data.downloads)  L.DOWNLOADS  = data.downloads;
    // merge sobre los defaults: si data.json trae solo USD/AUD, IDR conserva su tasa por defecto
    if(data.settings){ if(data.settings.rates){ L.RATES=Object.assign({},L.RATES,data.settings.rates); L.EUR_TO_USD=data.settings.rates.USD||1.08; } L.SETTINGS=data.settings; }
    L.PROPERTIES.forEach(function(p){ p.imgKeys=(p.images&&p.images.length)?p.images:[]; });
    fetch('https://open.er-api.com/v6/latest/EUR').then(function(r){return r.json();}).then(function(d){ if(d.result==='success'){ var fresh={EUR:1,USD:d.rates.USD,AUD:d.rates.AUD}; if(d.rates.IDR) fresh.IDR=d.rates.IDR; L.RATES=Object.assign({},L.RATES,fresh); L.EUR_TO_USD=d.rates.USD; } }).catch(function(){}).finally(start);
  }).catch(function(err){ console.error('Lawang: no se pudo cargar data.json — el portfolio se mostrará vacío.', err); start(); });
})();
