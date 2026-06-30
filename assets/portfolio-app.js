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
  var LINE_ICONS = { signature:"icon-signature", land:"icon-land", villa:"icon-villas", resorts:"icon-resorts" };

  var LAND_PLACEHOLDER = [ {size:400,priceEUR:95000}, {size:600,priceEUR:135000}, {size:1000,priceEUR:210000} ];
  var HOME_PLACEHOLDER = [ {name:"Lontar",beds:2,built:120,priceEUR:215000}, {name:"Banyan",beds:3,built:180,priceEUR:285000}, {name:"Frangipani",beds:4,built:240,priceEUR:360000} ];
  var EXTRAS_PLACEHOLDER = [ {name:"Private pool",priceEUR:28000}, {name:"Sauna",priceEUR:12000}, {name:"Outdoor kitchen",priceEUR:8500}, {name:"Airbnb rental kit",priceEUR:6500}, {name:"Solar energy package",priceEUR:9000} ];

  // ── Estado global ──────────────────────────────────────────
  var S = {
    lang:"en", cur:"EUR",
    line:"all", region:"all", layout:"grid", langOpen:false,
    overlay:null,
    gallery:0, calcTable:false, dlUnlocked:false, dlEmail:"", dlErr:false,
    parcelIdx:-1, modelIdx:-1, extrasSel:{}, step:0
  };
  function resetDetail(){ S.gallery=0; S.calcTable=false; S.dlUnlocked=false; S.dlEmail=""; S.dlErr=false; S.parcelIdx=-1; S.modelIdx=-1; S.extrasSel={}; S.step=0; }

  // ── Helpers ────────────────────────────────────────────────
  function t(key){ var e = L.DICT[key]; if(!e) return key; return (e[S.lang] != null ? e[S.lang] : e.en); }
  function money(eur, cur){ return L.money(eur, cur || S.cur); }
  function esc(s){ return String(s==null?"":s).replace(/[&<>"]/g,function(c){return {"&":"&amp;","<":"&lt;","&gt;":"&gt;",">":"&gt;","\"":"&quot;"}[c];}); }
  function pick(o){ return o ? (o[S.lang] || o.en) : ""; }
  function themeFor(p){ if(p.regionKey==="sumba") return p.line==="land"?"ocean":"sand"; if(p.line==="resorts") return "dusk"; if(p.line==="land") return "jungle"; return "sunset"; }
  function priceHTML(eur, from){ return (from?'<span style="font-size:.62em;opacity:.6;margin-right:6px">'+t("mk.from")+'</span>':'') + money(eur); }
  function statusPillStyle(s){
    if(s==="status.ready")        return "background:var(--clay);color:var(--bone);border-color:var(--clay)";
    if(s==="status.construction") return "background:var(--be);color:var(--bone);border-color:var(--be)";
    return "background:transparent;color:var(--ink-2);border-color:var(--line)";
  }
  function resolveLand(p){ return (p.showLandOptions===true || (p.landOptions&&p.landOptions.length)) ? ((p.landOptions&&p.landOptions.length)?p.landOptions:LAND_PLACEHOLDER) : null; }
  function resolveHomes(p){ return (p.showHomeModels===true || (p.homeModels&&p.homeModels.length)) ? ((p.homeModels&&p.homeModels.length)?p.homeModels:HOME_PLACEHOLDER) : null; }
  function resolveExtras(p){ return (p.showExtras===true || (p.extras&&p.extras.length)) ? ((p.extras&&p.extras.length)?p.extras:EXTRAS_PLACEHOLDER) : null; }
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
    if(url) h += '<img class="ph-img" src="'+esc(url)+'" alt="" style="opacity:1" onerror="this.style.display=\'none\'">';
    if(url && tint>0) h += '<div class="ph-tint" style="background:linear-gradient(180deg,rgba(26,22,15,'+(tint*0.7)+') 0%,transparent 30%,transparent 55%,rgba(26,22,15,'+(tint*1.6)+') 100%)"></div>';
    if(o.label) h += '<div class="ph-label">'+o.label+'</div>';
    h += '</div>';
    return h;
  }

  // ════ TOPBAR ════
  function topbarHTML(){
    var waNum=(L.SETTINGS&&L.SETTINGS.whatsapp)||'34600000000';
    var waUrl='https://wa.me/'+waNum;
    var langName={en:'English',es:'Español'}[S.lang]||'English';
    var nl=function(href,label,active){ return '<a class="nav-link'+(active?' active':'')+'" href="'+href+'">'+label+'</a>'; };
    var cb=function(c,sym){ return '<button data-act="cur:'+c+'" class="'+(S.cur===c?'on':'')+'">'+sym+'</button>'; };
    var li=function(code,flag,name){ return '<li role="option" data-act="lang:'+code+'"'+(S.lang===code?' class="active"':'')+'><span class="lang-opt">'+flag+name+'</span></li>'; };
    var flagEN='<svg class="flag" viewBox="0 0 60 36" aria-hidden="true"><rect width="60" height="36" fill="#012169"/><path d="M0,0 60,36 M60,0 0,36" stroke="#fff" stroke-width="7.2"/><path d="M0,0 60,36 M60,0 0,36" stroke="#C8102E" stroke-width="4"/><path d="M30,0 V36 M0,18 H60" stroke="#fff" stroke-width="12"/><path d="M30,0 V36 M0,18 H60" stroke="#C8102E" stroke-width="7.2"/></svg>';
    var flagES='<svg class="flag" viewBox="0 0 3 2" aria-hidden="true"><rect width="3" height="2" fill="#c60b1e"/><rect y=".5" width="3" height="1" fill="#ffc400"/></svg>';
    var wa='<span class="wa"><svg viewBox="0 0 24 24" fill="#fff" aria-hidden="true"><path d="M17.47 14.38c-.3-.15-1.76-.87-2.03-.97-.27-.1-.47-.15-.67.15-.2.3-.77.97-.94 1.17-.17.2-.35.22-.65.07-.3-.15-1.26-.46-2.4-1.48-.89-.79-1.49-1.77-1.66-2.07-.17-.3-.02-.46.13-.61.13-.13.3-.35.45-.52.15-.17.2-.3.3-.5.1-.2.05-.37-.02-.52-.07-.15-.67-1.62-.92-2.22-.24-.58-.49-.5-.67-.51l-.57-.01c-.2 0-.52.07-.8.37-.27.3-1.04 1.02-1.04 2.48 0 1.46 1.07 2.88 1.22 3.08.15.2 2.1 3.2 5.08 4.49.71.31 1.26.49 1.69.63.71.22 1.36.19 1.87.12.57-.09 1.76-.72 2.01-1.41.25-.7.25-1.29.17-1.41-.07-.12-.27-.2-.57-.35zM12.04 21.5h-.01a9.5 9.5 0 0 1-4.84-1.33l-.35-.2-3.6.94.96-3.51-.23-.36a9.49 9.49 0 0 1-1.45-5.05c0-5.24 4.27-9.5 9.52-9.5a9.46 9.46 0 0 1 9.51 9.51c0 5.24-4.27 9.5-9.51 9.5zM20.52 3.49A11.78 11.78 0 0 0 12.04 0C5.46 0 .1 5.36.1 11.94c0 2.1.55 4.16 1.6 5.98L0 24l6.25-1.64a11.92 11.92 0 0 0 5.79 1.47h.01c6.58 0 11.94-5.36 11.94-11.94a11.86 11.86 0 0 0-3.47-8.4z"/></svg></span>';
    return '<header id="topbar" class="show solid">'
      + '<div id="logo" class="dark"><div id="logo-inner"><img src="assets/img/lawang-logo-v3-dark.png" alt="Lawang Tropical Properties"></div></div>'
      + '<nav id="nav">'+nl('#land','Land',S.line==='land')+nl('#villas','Villas',S.line==='villa')+nl('index.html#services','The Soul',false)+nl('#all','The Portfolio',S.line==='all')+'</nav>'
      + '<div id="nav-actions">'
      +   '<div class="nav-lang-wrap" id="langWrap"><button class="nav-lang" data-act="lang-toggle" aria-haspopup="listbox" aria-expanded="'+(S.langOpen?'true':'false')+'"><svg class="globe" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.5 2.5 15.5 0 18M12 3c-2.5 2.5-2.5 15.5 0 18"/></svg><span>'+langName+'</span><span class="caret">▾</span></button>'
      +     '<ul class="lang-menu'+(S.langOpen?' open':'')+'" id="langMenu" role="listbox">'+li('en',flagEN,'English')+li('es',flagES,'Español')+'</ul></div>'
      +   '<div class="nav-cur">'+cb('EUR','€')+cb('USD','$')+cb('AUD','A$')+'</div>'
      +   '<a class="nav-cta" href="'+waUrl+'" target="_blank" rel="noopener">'+wa+' Let\'s Talk</a>'
      + '</div></header>';
  }

  // ════ MARKETPLACE ════
  function featuredHTML(p){
    if(!p || !((p.imgKeys&&p.imgKeys.length)||(p.images&&p.images.length))) return "";
    var key = (p.imgKeys&&p.imgKeys[0]) || (p.images&&p.images[0]);
    return '<div class="lw-featured" data-go="'+esc(p.id)+'" style="cursor:pointer;position:relative;border-radius:10px;overflow:hidden;margin-bottom:26px">'
      + ph({key:key, w:2000, theme:themeFor(p), kb:true, ratio:"21/6", tint:0, style:"min-height:210px"})
      + '<div style="position:absolute;inset:0;background:linear-gradient(105deg,rgba(22,18,12,.88) 0%,rgba(22,18,12,.5) 48%,rgba(22,18,12,.0) 100%)"></div>'
      + '<div style="position:absolute;inset:0;display:flex;flex-direction:column;justify-content:flex-end;padding:clamp(20px,3vw,38px);color:var(--bone);max-width:600px">'
      +   '<span class="pill clay" style="align-self:flex-start;margin-bottom:12px">'+t("mk.featured")+'</span>'
      +   '<h3 class="display" style="font-size:clamp(26px,3.6vw,44px)">'+esc(pick(p.title))+'</h3>'
      +   '<p style="font-size:15px;opacity:.9;margin-top:8px;max-width:460px">'+esc(pick(p.sub))+'</p>'
      +   '<div style="display:flex;gap:18px;align-items:center;margin-top:16px"><span class="serif" style="font-size:25px">'+priceHTML(p.priceEUR,true)+'</span><button class="btn btn-light">'+t("mk.view")+' <span class="arr">→</span></button></div>'
      + '</div></div>';
  }

  function marketplaceHTML(){
    var lineDescs = { signature:"line.signature.d", land:"line.land.d", villa:"line.villa.d", resorts:"line.resorts.d" };
    var featured = L.PROPERTIES.find(function(p){return p.featured && p.visible!==false;});
    var filtered = L.PROPERTIES.filter(function(p){ return p.visible!==false && (S.line==="all"||p.line===S.line) && (S.region==="all"||p.regionKey===S.region); });

    var lineCards = LINES.map(function(l,i){
      var on = S.line===l;
      return '<div class="reveal" style="transition-delay:'+(i*70)+'ms">'
        + '<button data-act="line:'+l+'" style="text-align:left;width:100%;height:100%;background:'+(on?"var(--tg,#485B37)":"var(--bone)")+';color:'+(on?"var(--bone)":"var(--ink)")+';border:0;cursor:pointer;padding:15px 18px 16px;transition:background .3s,color .3s">'
        +   '<div style="display:flex;align-items:center;gap:11px"><svg style="width:26px;height:26px;flex-shrink:0;color:'+(on?"rgba(245,240,230,0.9)":"var(--clay,#485B37)")+';fill:currentColor" aria-hidden="true"><use href="#'+LINE_ICONS[l]+'"/></svg>'
        +   '<div><div style="font-size:9px;font-weight:600;letter-spacing:.18em;color:'+(on?"rgba(245,240,230,0.6)":"var(--clay,#485B37)")+';text-transform:uppercase">'+String(i+1).padStart(2,"0")+'</div>'
        +   '<div class="serif" style="font-size:19px;font-weight:400;line-height:1.05">'+t(LINE_KEYS[l])+'</div></div></div>'
        +   '<p style="font-size:12px;line-height:1.4;margin-top:9px;margin-bottom:0;opacity:.74">'+t(lineDescs[l])+'</p>'
        + '</button></div>';
    }).join("");

    var chips = '<button class="filter-chip" data-act="line:all" style="'+chipStyle(S.line==="all")+'">'+t("mk.all")+'</button>'
      + LINES.map(function(l){ return '<button class="filter-chip" data-act="line:'+l+'" style="'+chipStyle(S.line===l)+'">'+t(LINE_KEYS[l])+'</button>'; }).join("")
      + '<span style="width:1px;background:var(--line);margin:0 6px"></span>'
      + '<button class="filter-chip" data-act="region:all" style="'+chipStyle(S.region==="all")+'">'+t("mk.all")+'</button>'
      + '<button class="filter-chip" data-act="region:bali" style="'+chipStyle(S.region==="bali")+'">Bali</button>'
      + '<button class="filter-chip" data-act="region:sumba" style="'+chipStyle(S.region==="sumba")+'">Sumba</button>';

    var cards = filtered.map(function(p){ return window.LawangCard.render(p, { lang:S.lang, cur:S.cur, rates:L.RATES, hrefBase:"" }); }).join("");

    var gridCols = S.layout==="list" ? "1fr" : "repeat(auto-fill,minmax(320px,1fr))";
    var gap = S.layout==="list" ? "20px" : "28px";

    var showFeatured = featured && (S.line==="all"||S.line===featured.line) && (S.region==="all"||S.region===featured.regionKey);

    return '<div style="background:var(--bone)">'
      + '<section class="wrap" style="padding-top:clamp(22px,3vw,42px);padding-bottom:22px">'
      +   '<div class="reveal"><div class="eyebrow-row"><span class="kicker">'+t("mk.kicker")+'</span></div>'
      +   '<h1 class="display" style="font-size:clamp(28px,4vw,52px);margin-top:12px;max-width:18ch">'+t("mk.title")+'</h1></div>'
      +   '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:1px;margin-top:22px;background:var(--line);border:1px solid var(--line);border-radius:8px;overflow:hidden">'+lineCards+'</div>'
      + '</section>'
      + (showFeatured ? '<section class="wrap">'+featuredHTML(featured)+'</section>' : "")
      + '<section class="wrap" id="pf-grid" style="scroll-margin-top:90px">'
      +   '<div style="display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap;padding-bottom:18px;border-bottom:1px solid var(--line);margin-bottom:24px">'
      +     '<div style="display:flex;gap:8px;flex-wrap:wrap">'+chips+'</div>'
      +     '<div style="display:flex;align-items:center;gap:14px"><span style="font-size:13px;color:var(--ink-2)">'+filtered.length+' '+t("mk.results")+'</span>'
      +       '<div class="seg" style="color:var(--ink)"><button class="'+(S.layout==="grid"?"on":"")+'" data-act="layout:grid"><span style="color:'+(S.layout==="grid"?"var(--bone)":"inherit")+'">▦</span></button>'
      +       '<button class="'+(S.layout==="list"?"on":"")+'" data-act="layout:list"><span style="color:'+(S.layout==="list"?"var(--bone)":"inherit")+'">≡</span></button></div></div>'
      +   '</div>'
      +   '<div style="display:grid;grid-template-columns:'+gridCols+';gap:'+gap+';padding-bottom:100px">'+cards+'</div>'
      + '</section></div>';
  }
  function chipStyle(active){ return 'appearance:none;border:1px solid '+(active?"var(--ink)":"var(--line)")+';background:'+(active?"var(--ink)":"transparent")+';color:'+(active?"var(--bone)":"var(--ink-2)")+';border-radius:999px;padding:8px 16px;font-size:13px;font-weight:600;cursor:pointer;font-family:var(--sans);white-space:nowrap'; }

  // ════ FICHA — sub-bloques ════
  function galleryHTML(p){
    var media = [];
    (p.imgKeys||[]).forEach(function(k){ media.push({type:"image",key:k}); });
    (p.videos||[]).forEach(function(v){ var o=(typeof v==="string")?{src:v}:(v||{}); var src=o.src||o.url||""; if(src) media.push({type:"video",src:src,poster:o.poster||""}); });
    if(media.length===0) return "";
    var total = media.length;
    var active = ((S.gallery%total)+total)%total;
    var curM = media[active];
    var theme = themeFor(p);
    var arrowBtn = function(side,act,label){ return '<button data-act="'+act+'" aria-label="'+label+'" style="position:absolute;top:50%;'+side+':12px;transform:translateY(-50%);z-index:4;width:38px;height:38px;border-radius:999px;border:none;cursor:pointer;background:rgba(20,16,11,.42);color:var(--bone);font-size:20px;line-height:0;display:grid;place-items:center;backdrop-filter:blur(3px);font-family:var(--sans)">'+(side==="left"?"‹":"›")+'</button>'; };
    var mainInner = curM.type==="video"
      ? '<video src="'+esc(curM.src)+'"'+(curM.poster?' poster="'+esc(curM.poster)+'"':'')+' controls playsinline preload="metadata" style="width:100%;height:100%;object-fit:cover;display:block;background:#000"></video>'
      : ph({key:curM.key, w:2000, theme:theme, kb:true, tint:0.12, style:"position:absolute;inset:0"});
    var main = '<div style="position:relative;grid-column:1;grid-row:1 / span 2;border-radius:10px;overflow:hidden;background:var(--bone-2)">'
      + '<div style="position:absolute;inset:0">'+mainInner+'</div>'
      + (total>1 ? (arrowBtn("left","gal:"+( ((active-1)%total+total)%total ),"Previous")+arrowBtn("right","gal:"+((active+1)%total),"Next")
          + '<div style="position:absolute;right:14px;bottom:13px;z-index:4;background:rgba(20,16,11,.5);color:var(--bone);font-family:var(--sans);font-size:11.5px;font-weight:600;letter-spacing:.1em;padding:4px 11px;border-radius:999px;backdrop-filter:blur(3px)">'+String(active+1).padStart(2,"0")+' <span style="opacity:.55">/ '+String(total).padStart(2,"0")+'</span></div>') : "")
      + '</div>';
    // side previews
    var sideCount = Math.min(2, total-1);
    var sides = "";
    for(var s=1;s<=sideCount;s++){
      var idx=(active+s)%total; var k=s-1; var isLast=(k===sideCount-1); var extra=total-1-sideCount;
      var span = sideCount===1 ? "1 / span 2" : (k===0?"1":"2");
      var m=media[idx];
      var prev = m.type==="video"
        ? (m.poster?'<img src="'+esc(m.poster)+'" alt="" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover">':'<div class="ph-grad ph-'+theme+'" style="position:absolute;inset:0"></div>')+'<div style="position:absolute;inset:0;display:grid;place-items:center;z-index:2"><span style="width:26px;height:26px;border-radius:999px;background:rgba(20,16,11,.55);display:grid;place-items:center"><span style="width:0;height:0;margin-left:2px;border-left:8px solid var(--bone);border-top:5px solid transparent;border-bottom:5px solid transparent"></span></span></div>'
        : ph({key:m.key, theme:theme, tint:0.12, style:"position:absolute;inset:0"});
      sides += '<button class="pdp-tile pdp-side" data-act="gal:'+idx+'" style="grid-column:2;grid-row:'+span+'">'+prev
        + (isLast&&extra>0 ? '<div style="position:absolute;inset:0;background:rgba(20,16,11,.52);display:grid;place-items:center;z-index:3"><span style="font-family:var(--sans);font-size:clamp(20px,2.4vw,30px);color:var(--bone);font-weight:500">+'+extra+'</span></div>' : "")
        + '</button>';
    }
    return '<div><div class="pdp-mosaic" style="box-shadow:0 30px 80px -42px rgba(27,26,21,.45);border-radius:10px">'+main+sides+'</div></div>';
  }

  function techSpecsHTML(p){
    var isF = p.tenure==="tenure.freehold";
    var specs = [ {l:t("glance.tenure"), v:isF?"Freehold HGB":"Leasehold 30yr"} ];
    if(p.built>0) specs.push({l:t("glance.villa"), v:p.built+" m²"});
    if(p.land>0)  specs.push({l:t("glance.land"),  v:p.land+" m²"});
    if(p.beds>0)  specs.push({l:t("pd.spec.beds"), v:p.beds});
    if(p.baths>0) specs.push({l:t("pd.spec.baths"),v:p.baths});
    if(p.pool)    specs.push({l:t("spec.pool"),    v:p.poolType||"Yes"});
    if(p.garage)  specs.push({l:t("spec.garage"),  v:p.garageDesc||"Yes"});
    if(p.furnished&&p.furnished!=="None") specs.push({l:t("spec.furnished"), v:p.furnished});
    // Vista inferida (icono cream sobre fondo oscuro)
    if(window.LawangCard){
      var vw = window.LawangCard.viewFor(p);
      var vwLabel = (window.LawangCard.VIEW_LABEL[vw]||{})[S.lang] || vw;
      specs.unshift({ l:(S.lang==="es"?"Vista":"View"), html:'<img src="assets/img/'+vw+'.png" alt="" style="width:18px;height:18px;object-fit:contain;vertical-align:-3px;margin-right:7px;opacity:.92">'+esc(vwLabel) });
    }
    if(specs.length===0) return "";
    var cells = specs.map(function(sp,i){
      return '<div style="padding:20px 18px;border-right:'+(i===specs.length-1?"none":"1px solid rgba(255,255,255,0.07)")+';border-bottom:1px solid rgba(255,255,255,0.06)">'
        + '<div style="font-size:9px;font-weight:600;letter-spacing:.22em;text-transform:uppercase;color:rgba(245,240,230,0.38);margin-bottom:8px;font-family:var(--sans)">'+esc(sp.l)+'</div>'
        + '<div style="font-family:var(--sans);font-size:1rem;font-weight:500;color:rgba(245,240,230,0.88);line-height:1.2">'+(sp.html!=null?sp.html:esc(sp.v))+'</div></div>';
    }).join("");
    return '<div style="background:#104C4F;border-radius:8px;margin-top:28px;overflow:hidden"><div class="tech-specs-grid" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr))">'+cells+'</div></div>';
  }

  function downloadsHTML(files, p){
    var head = '<div style="font-size:9px;font-weight:700;letter-spacing:.2em;text-transform:uppercase;color:var(--ink-2);margin-bottom:12px">'+t("dl.title")+'</div>';
    var inner;
    if(S.dlUnlocked){
      var rows = files.map(function(f,i){
        var dl = f.url ? '<a href="'+esc(f.url)+'" target="_blank" rel="noopener" download style="border:1px solid var(--line);border-radius:4px;padding:4px 10px;font-size:11px;color:var(--tg);font-family:var(--sans);text-decoration:none">↓</a>'
                       : '<span style="border:1px solid var(--line);border-radius:4px;padding:4px 10px;font-size:11px;color:var(--ink-2);font-family:var(--sans)">↓</span>';
        return '<div style="display:flex;justify-content:space-between;align-items:center;padding:9px 0;border-bottom:'+(i<files.length-1?"1px solid var(--line)":"none")+'">'
          + '<div style="display:flex;align-items:center;gap:10px"><div style="width:28px;height:28px;background:var(--tg-light);border-radius:4px;display:flex;align-items:center;justify-content:center;font-size:8px;font-weight:700;color:var(--tg)">'+(f.ext||"PDF")+'</div>'
          + '<div><div style="font-size:13px">'+esc(f.name)+'</div><div style="font-size:11px;color:var(--ink-2)">'+esc(f.size||"")+(f.size?" · ":"")+(f.url?"":t("dl.coming"))+'</div></div></div>'+dl+'</div>';
      }).join("");
      inner = '<div style="display:flex;align-items:center;gap:7px;font-size:11px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;color:var(--tg);margin-bottom:8px"><span style="width:7px;height:7px;border-radius:999px;background:var(--tg)"></span> '+t("dl.unlocked")+'</div>'+rows;
    } else {
      var locked = files.map(function(f){ return '<div style="display:flex;align-items:center;gap:10px;padding:6px 0;opacity:.5"><div style="width:26px;height:26px;background:var(--tg-light);border-radius:4px;display:flex;align-items:center;justify-content:center;font-size:8px;font-weight:700;color:var(--tg)">'+(f.ext||"PDF")+'</div><div style="font-size:13px">'+esc(f.name)+'</div></div>'; }).join("");
      inner = '<form data-act="dl-submit"><div style="margin-bottom:14px">'+locked+'</div>'
        + '<p style="font-size:12.5px;color:var(--ink);font-weight:600;line-height:1.4;margin-bottom:10px">'+t("dl.gate.title")+'</p>'
        + '<input type="email" id="dl-email" value="'+esc(S.dlEmail)+'" placeholder="you@email.com" aria-label="Email" style="width:100%;padding:10px 12px;border:1px solid '+(S.dlErr?"#b3402e":"var(--line)")+';border-radius:6px;font-size:14px;font-family:var(--sans);outline:none;margin-bottom:'+(S.dlErr?"6px":"10px")+';background:white;box-sizing:border-box">'
        + (S.dlErr?'<div style="font-size:11.5px;color:#b3402e;margin-bottom:10px">'+t("dl.gate.invalid")+'</div>':"")
        + '<button type="submit" style="width:100%;background:var(--clay);color:var(--bone);border:none;border-radius:6px;padding:11px;font-size:13px;font-weight:700;cursor:pointer;font-family:var(--sans)">'+t("dl.gate.cta")+' →</button>'
        + '<p style="font-size:11px;color:var(--ink-2);line-height:1.5;margin-top:10px;opacity:.85">'+t("dl.gate.note")+'</p></form>';
    }
    return '<div style="padding:18px;background:var(--bone);border:1px solid var(--line);border-radius:8px">'+head+inner+'</div>';
  }

  function sidebarHTML(p){
    var isF = p.tenure==="tenure.freehold";
    var waNum = (L.SETTINGS&&L.SETTINGS.whatsapp)||"34600000000";
    var email = (L.SETTINGS&&L.SETTINGS.email)||"hello@lawang.id";
    var title = pick(p.title);
    var waUrl = "https://wa.me/"+waNum+"?text="+encodeURIComponent("Hello! I'm interested in "+title+". Can we schedule a call?");
    var files = (p.downloads&&p.downloads.length)?p.downloads:null;
    var row='display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid var(--line);gap:12px';
    var lbl='font-size:12.5px;color:var(--ink-2);font-weight:500;flex-shrink:0';
    var val='font-size:13px;text-align:right';
    var curRows = ["EUR","USD","AUD"].map(function(c){ return '<div style="font-size:12px;color:var(--ink-2)"><span style="font-weight:600">'+c+'</span> '+money(p.priceEUR,c)+'</div>'; }).join("");
    var units = (p.unitsAvailable!=null&&p.unitsAvailable!=="") ? '<div style="padding:12px 20px;border-bottom:1px solid var(--line);display:flex;align-items:center;justify-content:space-between"><span style="font-size:9px;font-weight:700;letter-spacing:.18em;text-transform:uppercase;color:var(--ink-2)">'+t("glance.units")+'</span><span style="display:inline-flex;align-items:center;gap:7px;font-size:13px;font-weight:600"><span style="width:7px;height:7px;border-radius:999px;background:'+(Number(p.unitsAvailable)>0?"var(--tg)":"var(--ink-2)")+'"></span>'+esc(p.unitsAvailable)+(p.unitsTotal?" / "+esc(p.unitsTotal):"")+'</span></div>' : "";
    return '<div style="display:flex;flex-direction:column;gap:14px">'
      + '<div style="background:var(--bone-2);border:1px solid var(--line);border-radius:10px;overflow:hidden">'
      +   '<div style="padding:22px 20px 18px;border-bottom:1px solid var(--line)"><div style="font-size:9px;font-weight:700;letter-spacing:.18em;text-transform:uppercase;color:var(--ink-2);margin-bottom:10px">'+t("glance.entry")+'</div>'
      +     '<div class="serif" style="font-size:clamp(28px,2.8vw,36px);font-weight:400;line-height:1">'+priceHTML(p.priceEUR,true)+'</div>'
      +     '<div style="display:flex;gap:16px;margin-top:10px;flex-wrap:wrap">'+curRows+'</div>'
      +     '<div style="font-size:11px;color:var(--ink-2);margin-top:6px;opacity:.65">'+t("pd.pricenote")+'</div></div>'
      +   '<div style="padding:12px 20px;border-bottom:1px solid var(--line);display:flex;align-items:baseline;justify-content:space-between"><span style="font-size:9px;font-weight:700;letter-spacing:.18em;text-transform:uppercase;color:var(--ink-2)">'+t("glance.location")+'</span><span style="font-size:13px;font-weight:600">'+esc(p.region)+'</span></div>'
      +   units
      +   '<div style="padding:14px 20px"><div style="font-size:9px;font-weight:700;letter-spacing:.18em;text-transform:uppercase;color:var(--ink-2);margin-bottom:10px">Legal</div>'
      +     '<div style="'+row+'"><span style="'+lbl+'">'+t("glance.tenure")+'</span><span style="'+val+';font-weight:600;color:'+(isF?"var(--tg)":"inherit")+'">'+(isF?"Freehold HGB":"Leasehold 30yr")+'</span></div>'
      +     (isF?'<div style="'+row+'"><span style="'+lbl+'">'+t("glance.ptpma")+'</span><span style="'+val+'">Included · ~€1,000</span></div>':"")
      +     '<div style="'+row+'"><span style="'+lbl+'">'+t("glance.delivery")+'</span><span style="'+val+'">'+(p.handover!=="—"?esc(p.handover):"On request")+'</span></div>'
      +     '<div style="'+row+';border-bottom:none"><span style="'+lbl+'">'+t("glance.status")+'</span><span style="'+val+'">'+t(p.status)+'</span></div></div>'
      + '</div>'
      + '<div style="background:var(--tg);border-radius:8px;overflow:hidden"><div style="padding:18px 20px 14px"><div style="font-size:10px;font-weight:700;letter-spacing:.16em;text-transform:uppercase;color:rgba(245,240,230,0.5);margin-bottom:6px">'+t("wa.title")+'</div><p style="font-size:12.5px;color:rgba(245,240,230,0.7);margin-bottom:0;line-height:1.5">'+t("wa.sub")+'</p></div>'
      +   '<div style="padding:0 20px 20px;display:flex;flex-direction:column;gap:10px"><a href="'+waUrl+'" target="_blank" rel="noopener" style="display:flex;align-items:center;justify-content:center;gap:8px;background:#25D366;color:white;padding:12px 20px;border-radius:6px;font-size:13px;font-weight:700;text-decoration:none;font-family:var(--sans)">✓ '+t("wa.cta")+'</a>'
      +   '<a href="mailto:'+esc(email)+'" style="display:flex;align-items:center;justify-content:center;gap:8px;background:rgba(245,240,230,0.1);border:1px solid rgba(245,240,230,0.25);color:var(--bone);padding:11px 20px;border-radius:6px;font-size:13px;font-weight:600;text-decoration:none;font-family:var(--sans)">'+t("pd.enquire")+' →</a></div></div>'
      + (files?downloadsHTML(files,p):"")
      + '</div>';
  }

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
    return '<div style="margin-top:40px;padding-top:36px;border-top:1px solid var(--line)"><h4 class="serif" style="font-size:clamp(20px,2vw,25px);font-weight:300;margin-bottom:20px">'+t("inv.title")+'</h4>'
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
    var steps = (p.paymentPlan&&p.paymentPlan.length)?p.paymentPlan:L.getPaymentPlan(p);
    var rows = steps.map(function(s,i){ return '<div style="display:grid;grid-template-columns:44px 1fr auto;gap:16px;align-items:start;padding:18px 0;border-bottom:1px solid var(--line)">'
      + '<div style="font-family:var(--sans);font-size:22px;font-weight:300;color:var(--clay);line-height:1;padding-top:4px;opacity:'+(i===0?1:0.45)+'">'+s.step+'</div>'
      + '<div><div style="font-size:14px;font-weight:600;margin-bottom:4px">'+esc(s.label)+'</div><div style="font-size:12.5px;color:var(--ink-2);line-height:1.5">'+esc(s.note)+'</div></div>'
      + '<div style="text-align:right"><div style="font-family:var(--sans);font-size:16px;font-weight:600">'+money(Math.round(price*s.pct/100))+'</div><div style="font-size:11px;color:var(--ink-2);margin-top:2px">'+s.pct+'%</div></div></div>'; }).join("");
    return '<div><h4 class="serif" style="font-size:clamp(20px,2vw,25px);font-weight:300;margin-bottom:22px">'+t("pay.title")+'</h4>'+rows
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
      return '<button data-act="model:'+i+'" style="text-align:left;padding:0;border:2px solid '+(on?"var(--clay)":"var(--line)")+';border-radius:10px;overflow:hidden;cursor:pointer;background:var(--bone-2)"><div style="position:relative;aspect-ratio:4/3">'+(m.image?'<img src="'+esc(m.image)+'" alt="" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover">':'<div class="ph-grad ph-'+themeFor(p)+'" style="position:absolute;inset:0"></div>')+(on?'<span style="position:absolute;top:8px;right:8px;background:var(--clay);color:var(--bone);font-size:9px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;padding:3px 8px;border-radius:999px">'+t("home.selected")+'</span>':"")+'</div><div style="padding:12px 14px 14px"><div class="serif" style="font-size:19px">'+esc(m.name)+'</div><div style="font-size:12px;color:var(--ink-2);margin-top:4px">'+m.beds+' '+t("home.beds")+' · '+m.built+' m²</div><div style="font-size:14px;font-weight:600;margin-top:8px">'+priceHTML(m.priceEUR,true)+'</div></div></button>';
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
    var inner=(bare?"":'<div class="kicker" style="margin-bottom:24px">'+t("fin.title")+'</div>')+breakdown+paymentPlanHTML(p,configuredEUR)+(p.nightlyRate>0?investmentCalcHTML(p,configuredEUR):"");
    return bare?'<div>'+inner+'</div>':'<div style="margin-top:56px;padding-top:40px;border-top:1px solid var(--line)">'+inner+'</div>';
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
    var stepHead = sObj.id!=="pay" ? '<div style="margin-bottom:18px"><h4 class="serif" style="font-size:clamp(20px,2vw,25px);font-weight:300">'+sObj.title+'</h4>'+(sObj.sub?'<p style="font-size:14px;color:var(--ink-2);margin-top:6px;max-width:46ch">'+sObj.sub+'</p>':"")+'</div>' : "";
    var nextBtn = !isLast
      ? '<button '+(canNext?'data-act="step:'+(idx+1)+'"':'disabled')+' style="background:'+(canNext?"var(--clay)":"var(--line)")+';color:var(--bone);border:none;border-radius:999px;padding:11px 26px;font-family:var(--sans);font-size:13px;font-weight:700;cursor:'+(canNext?"pointer":"default")+'">'+((sObj.id==="extras"&&cfg.extrasTotal===0)?t("cfg.skip"):t("cfg.next"))+' →</button>'
      : '<button data-act="cfg-reset" style="background:none;border:1px solid var(--line);border-radius:999px;padding:10px 20px;font-family:var(--sans);font-size:13px;font-weight:600;cursor:pointer;color:var(--ink-2)">↺ '+t("cfg.restart")+'</button>';
    return '<div style="margin-top:56px;padding-top:40px;border-top:1px solid var(--line)"><div class="kicker" style="margin-bottom:8px">'+t("cfg.title")+'</div><p style="font-size:14.5px;color:var(--ink-2);margin-bottom:22px;max-width:46ch">'+t("cfg.sub")+'</p>'
      + '<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:26px">'+prog+totalChip+'</div>'
      + '<div class="cfg-step">'+stepHead+sObj.content+'</div>'
      + '<div style="display:flex;justify-content:space-between;align-items:center;gap:12px;margin-top:30px;padding-top:20px;border-top:1px solid var(--line)">'
      +   '<button '+(idx===0?'disabled':'data-act="step:'+(idx-1)+'"')+' style="background:none;border:1px solid var(--line);border-radius:999px;padding:10px 20px;font-family:var(--sans);font-size:13px;font-weight:600;cursor:'+(idx===0?"default":"pointer")+';opacity:'+(idx===0?0.4:1)+';color:var(--ink)">← '+t("cfg.back")+'</button>'+nextBtn
      + '</div></div>';
  }

  function breadcrumbsHTML(p){
    var sep='<span aria-hidden="true" style="opacity:.4;margin:0 9px">›</span>';
    var lk=function(label,act){ return '<button data-act="'+act+'" style="background:none;border:none;padding:0;cursor:pointer;font:inherit;letter-spacing:.08em;color:var(--ink-2)">'+esc(label)+'</button>'; };
    return '<nav aria-label="Breadcrumb" style="font-family:var(--sans);font-size:11.5px;font-weight:500;text-transform:uppercase;letter-spacing:.08em;display:flex;flex-wrap:wrap;align-items:center;margin-bottom:22px">'
      + lk(t("crumb.home"),"go-home")+sep+lk(t("crumb.portfolio"),"close")+sep+lk(t(LINE_KEYS[p.line]),"close")+sep+'<span style="color:var(--ink);letter-spacing:.08em">'+esc(pick(p.title))+'</span></nav>';
  }

  function mapBlockHTML(p){
    var body = p.mapImage
      ? '<img src="'+esc(p.mapImage)+'" alt="'+t("map.title")+'" style="width:100%;border-radius:10px;display:block;border:1px solid var(--line)">'
      : '<div style="aspect-ratio:16/9;border-radius:10px;border:1px dashed var(--line);background:var(--bone-2);display:grid;place-items:center"><div style="text-align:center;color:var(--ink-2)"><svg viewBox="0 0 24 24" style="width:30px;height:30px;fill:none;stroke:var(--ink-2);stroke-width:1.4;opacity:.7" aria-hidden="true"><path d="M12 21s-7-6.2-7-11a7 7 0 1 1 14 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/></svg><div style="font-size:13px;letter-spacing:.06em;margin-top:10px">'+t("map.soon")+'</div><div style="font-size:14px;color:var(--ink);margin-top:4px;font-weight:600">'+esc(p.region)+'</div></div></div>';
    return '<div style="margin-top:56px;padding-top:40px;border-top:1px solid var(--line)"><div class="kicker" style="margin-bottom:20px">'+t("map.title")+'</div>'+body+'</div>';
  }

  function signatureNoteHTML(p){
    return '<div style="margin-top:56px;padding-top:40px;border-top:1px solid var(--line)"><div style="display:inline-flex;align-items:center;gap:8px;background:var(--dl);color:var(--bone);border-radius:999px;padding:7px 16px;font-family:var(--sans);font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase"><span style="width:7px;height:7px;border-radius:999px;background:var(--bone)"></span> '+t("sig.delivered")+'</div><p style="font-size:15px;color:var(--ink-2);line-height:1.6;margin-top:18px;max-width:52ch">'+t("sig.note")+'</p></div>';
  }

  function propertyHTML(id){
    var p = propById(id);
    if(!p) return '<div class="wrap" style="padding-top:120px;padding-bottom:120px;text-align:center"><p class="serif" style="font-size:28px">Property not found.</p><button class="btn btn-ghost" data-act="close" style="margin-top:20px">'+t("pd.back")+'</button></div>';
    document.title = pick(p.title)+" · Lawang";
    var cfg = configState(p);
    var isSignature = p.line==="signature";
    var hasConfigurator = !isSignature && !!(cfg.landOptions||cfg.models||cfg.extrasList);
    var also = L.PROPERTIES.filter(function(x){return x.line===p.line&&x.id!==p.id;}).slice(0,3);
    var leftMain = isSignature ? signatureNoteHTML(p) : (hasConfigurator ? configuratorHTML(p,cfg) : financialsHTML(p,cfg,false));
    var alsoHTML = also.length>0 ? '<div style="margin-top:80px;padding-top:48px;border-top:1px solid var(--line)"><div class="kicker" style="margin-bottom:28px">'+t("pd.also")+'</div><div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:24px;padding-bottom:40px">'
      + also.map(function(x){ return '<div class="lw-also" data-go="'+esc(x.id)+'" style="padding:3px;background:rgba(72,91,55,0.05);border:1px solid rgba(72,91,55,0.11);border-radius:11px;cursor:pointer"><div style="background:var(--bone-2);border-radius:8px;overflow:hidden">'+ph({key:(x.imgKeys&&x.imgKeys[0]),theme:themeFor(x),ratio:"4/3",tint:0.2})+'<div style="padding:16px 18px"><p class="serif" style="font-size:20px">'+esc(pick(x.title))+'</p><p style="font-size:13px;color:var(--ink-2);margin-top:6px">'+priceHTML(x.priceEUR,true)+'</p></div></div></div>'; }).join("")
      + '</div></div>' : "";
    return '<div style="padding-top:clamp(32px,4vw,56px);padding-bottom:80px"><div class="wrap">'
      + breadcrumbsHTML(p)
      + '<div style="display:flex;justify-content:space-between;align-items:flex-end;gap:clamp(20px,4vw,48px);flex-wrap:wrap;margin-bottom:30px"><div style="flex:1 1 380px;min-width:0">'
      +   '<div style="display:flex;align-items:center;gap:10px;margin-bottom:16px"><span style="font-size:10px;font-weight:600;letter-spacing:.22em;text-transform:uppercase;color:var(--clay);font-family:var(--sans)">'+t(LINE_KEYS[p.line])+'</span><span style="width:1px;height:12px;background:var(--line)"></span><span style="font-size:10px;font-weight:400;letter-spacing:.1em;text-transform:uppercase;color:var(--ink-2);font-family:var(--sans)">'+t(p.status)+'</span></div>'
      +   '<h1 class="display" style="font-size:clamp(34px,5vw,64px)">'+esc(pick(p.title))+'</h1><p style="font-size:18px;color:var(--ink-2);margin-top:14px;max-width:50ch">'+esc(pick(p.sub))+'</p></div>'
      +   '<div style="flex-shrink:0;text-align:right"><div class="serif" style="font-size:clamp(28px,2.8vw,38px);font-weight:400;line-height:1">'+priceHTML(p.priceEUR,true)+'</div></div></div>'
      + galleryHTML(p)
      + techSpecsHTML(p)
      + '<div class="pdp-cols" style="display:grid;grid-template-columns:minmax(0,1.65fr) minmax(0,1fr);gap:clamp(28px,5vw,72px);margin-top:56px;align-items:start">'
      +   '<div><div><div class="kicker">'+t("pd.overview")+'</div><p style="font-family:var(--sans);font-size:clamp(17px,1.7vw,21px);font-weight:300;line-height:1.65;margin-top:18px;color:var(--ink)">'+esc(pick(p.desc))+'</p></div>'
      +     mapBlockHTML(p)+leftMain+'</div>'
      +   '<div style="position:sticky;top:80px">'+sidebarHTML(p)+'</div>'
      + '</div>'+alsoHTML
      + '</div></div>';
  }

  // ════ OVERLAY (ficha sobre el marketplace) ════
  function overlayHTML(id){
    function tg(active){ return 'appearance:none;border:0;background:'+(active?"var(--tg)":"transparent")+';color:'+(active?"#fff":"var(--ink-2)")+';font-family:var(--sans);font-size:11.5px;font-weight:600;letter-spacing:.04em;padding:5px 10px;cursor:pointer'; }
    var wrap='display:inline-flex;border-radius:6px;border:1px solid var(--line);overflow:hidden';
    return '<div id="pf-overlay"><div class="pf-overlay-bar">'
      + '<button data-act="close" style="background:none;border:0;cursor:pointer;color:var(--ink-2);font-size:10px;font-weight:600;letter-spacing:.2em;text-transform:uppercase;display:inline-flex;align-items:center;gap:10px;padding:8px 0;font-family:var(--sans)"><span style="font-size:16px;font-weight:300;letter-spacing:0">←</span> The Portfolio</button>'
      + '<div style="display:flex;align-items:center;gap:10px"><div style="'+wrap+'"><button data-act="lang:en" style="'+tg(S.lang==="en")+'">EN</button><button data-act="lang:es" style="'+tg(S.lang==="es")+'">ES</button></div>'
      + '<div style="'+wrap+'"><button data-act="cur:EUR" style="'+tg(S.cur==="EUR")+'">€</button><button data-act="cur:USD" style="'+tg(S.cur==="USD")+'">$</button><button data-act="cur:AUD" style="'+tg(S.cur==="AUD")+'">A$</button></div></div>'
      + '</div>'+propertyHTML(id)+'</div>';
  }

  // ════ RENDER ════
  var root;
  function render(){
    root.innerHTML = topbarHTML() + marketplaceHTML() + (S.overlay ? overlayHTML(S.overlay) : "");
    document.body.style.overflow = S.overlay ? "hidden" : "";
    if(!S.overlay) document.title = "The Portfolio · Lawang Tropical Properties";
    requestAnimationFrame(function(){ root.querySelectorAll(".reveal").forEach(function(el){ el.classList.add("in"); }); });
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

  function chooseLine(l){ S.line=l; if(l==="all") history.replaceState(null,"",location.pathname+location.search); else history.replaceState(null,"","#"+l); render(); }

  function handleAct(act, el){
    var k=act.split(":"); var cmd=k[0]; var val=k.slice(1).join(":");
    if(cmd==="lang"){ S.lang=val; S.langOpen=false; render(); }
    else if(cmd==="lang-toggle"){ S.langOpen=!S.langOpen; render(); }
    else if(cmd==="cur"){ S.cur=val; render(); }
    else if(cmd==="line"){ chooseLine(val); var g=document.getElementById("pf-grid"); if(g) g.scrollIntoView({behavior:"smooth",block:"start"}); }
    else if(cmd==="region"){ S.region=val; render(); }
    else if(cmd==="layout"){ S.layout=val; render(); }
    else if(cmd==="gal"){ S.gallery=parseInt(val,10)||0; render(); }
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
      var go = e.target.closest("[data-go]");
      if(go){ openProperty(go.getAttribute("data-go")); return; }
      var a = e.target.closest("[data-act]");
      if(a){
        if(a.tagName==="A") return;            // enlaces nativos (mailto, wa, index)
        if(a.closest("form")) { /* submit lo gestiona el form */ }
        e.preventDefault();
        handleAct(a.getAttribute("data-act"), a);
      }
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
    window.addEventListener("hashchange", onHash);
    document.addEventListener("click", function(e){
      if(S.langOpen && !e.target.closest(".nav-lang-wrap")){ S.langOpen=false; render(); }
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

  fetch('data.json?_=' + Date.now()).then(function(r){return r.json();}).then(function(data){
    if(data.properties) L.PROPERTIES = data.properties;
    if(data.downloads)  L.DOWNLOADS  = data.downloads;
    if(data.settings){ if(data.settings.rates){ L.RATES=data.settings.rates; L.EUR_TO_USD=data.settings.rates.USD||1.08; } L.SETTINGS=data.settings; }
    L.PROPERTIES.forEach(function(p){ p.imgKeys=(p.images&&p.images.length)?p.images:[]; });
    fetch('https://open.er-api.com/v6/latest/EUR').then(function(r){return r.json();}).then(function(d){ if(d.result==='success'){ L.RATES={EUR:1,USD:d.rates.USD,AUD:d.rates.AUD}; L.EUR_TO_USD=d.rates.USD; } }).catch(function(){}).finally(start);
  }).catch(start);
})();
