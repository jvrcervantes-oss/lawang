/* ═══════════════════════════════════════════════════════════════════════════
   EL ASPECTO DEL DOCUMENTO — portada, marca de agua, tipografía
   Sale de contracts/app.html el 21-ago-2026.
   ═══════════════════════════════════════════════════════════════════════════
   El diseño es COMPARTIDO por tipo de plantilla (tabla contratos_diseno): dos
   Cartas de Reserva se imprimen igual. La copia en localStorage es solo para no
   perder una edición sin guardar, no es la verdad.

   Aquí se genera el CSS que se inyecta en el <head> del documento. Es texto, no
   hojas de estilo sueltas, porque el documento se imprime y se manda por correo:
   un <link> a un CSS externo llega roto al que lo abre.
   ═══════════════════════════════════════════════════════════════════════════ */
/* Caché local por plantilla — solo para no perder una edición sin guardar
   si recargas la página a medias. La fuente real es Supabase
   (contratos_diseno), cargada en loadTemplate(): ver loadSharedDesign()/
   saveSharedDesign() más abajo. */
function loadDesign(slug){
  try{ const s=JSON.parse(localStorage.getItem('lawang_contract_design_'+(slug||(typeof CURRENT!=='undefined'&&CURRENT.slug)||'')));
    return s ? deepMerge(structuredClone(DESIGN_DEFAULT), s) : structuredClone(DESIGN_DEFAULT);
  }catch(_){ return structuredClone(DESIGN_DEFAULT); }
}
function deepMerge(base, over){ for(const k in over){ (over[k] && typeof over[k]==='object' && !Array.isArray(over[k]))
  ? deepMerge(base[k]=base[k]||{}, over[k]) : (base[k]=over[k]); } return base; }
function saveDesign(){ try{ localStorage.setItem('lawang_contract_design_'+CURRENT.slug, JSON.stringify(DESIGN)); }catch(_){} }

/* Diseño COMPARTIDO por tipo de plantilla (tabla contratos_diseno, jul-2026).
   "Guardar como diseño de esta plantilla" lo sube; cualquier agente que
   abra ese tipo de contrato lo recibe como punto de partida. */
async function loadSharedDesign(slug){
  if(!sb) return null;
  const { data } = await sb.from('contratos_diseno').select('design').eq('slug', slug).maybeSingle();
  return data ? data.design : null;
}
async function saveSharedDesign(){
  if(!sb) return;
  const btn=$('#btnSaveDesign'); const t0=btn?btn.textContent:'';
  if(btn){ btn.disabled=true; btn.textContent='Guardando…'; }
  try{
    const { error } = await sb.from('contratos_diseno')
      .upsert({ slug:CURRENT.slug, design:DESIGN, updated_at:new Date().toISOString() });
    if(error) throw error;
    toast('Diseño guardado como plantilla — ya lo ven todos los agentes');
  }catch(err){ toast('No se pudo guardar el diseño: ' + (err.message||err)); }
  if(btn){ btn.disabled=false; btn.textContent=t0; }
}

const COVER_POS = {
  'top-left':'top:14mm;left:18mm;', 'top-center':'top:14mm;left:50%;transform:translateX(-50%);', 'top-right':'top:14mm;right:18mm;',
  'center':'top:50%;left:50%;transform:translate(-50%,-50%);',
  'bottom-left':'bottom:10mm;left:18mm;', 'bottom-center':'bottom:10mm;left:50%;transform:translateX(-50%);', 'bottom-right':'bottom:10mm;right:18mm;',
  'fullbleed':'inset:0;',
};
/* El isotipo de fondo (moanito) se ancla A SANGRE por los lados, no como una
   pieza centrada de ancho fijo → necesita su propio 'bottom-center'. Antes
   compartía el de COVER_POS y por eso el logo inferior no podía acercarse al
   margen sin descolocar el isotipo. */
const MARK_POS = { ...COVER_POS, 'bottom-center':'left:0;right:0;bottom:-3%;' };
const DOC_POS = {
  center:'left:50%;top:44%;transform:translate(-50%,-50%);',
  top:'left:50%;top:10%;transform:translateX(-50%);',
  bottom:'left:50%;bottom:10%;transform:translateX(-50%);',
};
const SLOTS = {
  coverLogo:{ label:{es:'Logo · portada',en:'Logo · cover',id:'Logo · sampul'}, kind:'cover', unit:'mm', min:10, max:90 },
  coverEmblem:{ label:{es:'Emblema · portada',en:'Emblem · cover',id:'Lambang · sampul'}, kind:'cover', unit:'mm', min:8, max:60 },
  coverMark:{ label:{es:'Isotipo de fondo · portada',en:'Background mark · cover',id:'Latar · sampul'}, kind:'mark', unit:'%', min:20, max:120 },
  docLogo:  { label:{es:'Logo de cabecera · interior',en:'Header logo · body',id:'Logo kepala · isi'}, kind:'doclogo', unit:'mm', min:10, max:60 },
  docMark:  { label:{es:'Marca de agua · interior',en:'Watermark · body',id:'Cap air · isi'}, kind:'docmark', unit:'mm', min:60, max:220 },
};
const POS_OPTS = {
  cover:[['top-left','Sup. izq.'],['top-center','Sup. centro'],['top-right','Sup. der.'],['center','Centro'],['bottom-left','Inf. izq.'],['bottom-center','Inf. centro'],['bottom-right','Inf. der.']],
  mark:[['bottom-center','Abajo'],['center','Centro'],['top-center','Arriba'],['fullbleed','A sangre']],
  doclogo:[['left','Izquierda'],['center','Centro'],['right','Derecha']],
  docmark:[['center','Centro'],['top','Arriba'],['bottom','Abajo']],
};

/* CSS de idioma: Bahasa (id) SIEMPRE visible + el idioma seleccionado (es|en),
   en 2 COLUMNAS (idioma izq. / Bahasa der.). Los rótulos (h2, título, roles,
   celdas de tabla) siguen apilados para no romperse.
   Nota: las reglas de columna apuntan SOLO a LANG e id — un selector genérico
   [data-lang] re-mostraría el idioma oculto por especificidad.
   float, NO inline-block: Chromium no parte un inline-block entre páginas al
   imprimir/PDF — si un bloque bilingüe (sobre todo <ul>/<ol> con varios
   ítems) no cabía en lo que quedaba de hoja, saltaba ENTERO a la siguiente,
   dejando la mitad de la página en blanco (bug real, visto en PDF generado).
   Un float SÍ es una caja de bloque normal que Chromium puede cortar por
   líneas entre páginas. Contrapartida asumida: las columnas ya no quedan
   perfectamente alineadas fila a fila si una traducción es más larga que la
   otra — normal en bilingües reales, y muchísimo más leve que la página en
   blanco. Ver contract.css (clear:both en h2/.party/table.pays/.pending)
   para que lo que NO es columna de idioma corte el float y recupere el
   ancho completo. */
function langCSS(){
  const L2=`.doc p[data-lang="${LANG}"],.doc ul[data-lang="${LANG}"],.doc ol[data-lang="${LANG}"]`;
  const IDs=`.doc p[data-lang="id"],.doc ul[data-lang="id"],.doc ol[data-lang="id"]`;
  return `[data-lang]{display:none!important}[data-lang="${LANG}"]{display:revert!important}`
    + `[data-lang="id"]{display:block!important}.doc [data-lang="id"]{color:#6b6c66}`
    // clear:left/right (no solo float) — sin esto los floats se empaquetan
    // horizontalmente en cualquier hueco libre (comportamiento normal de
    // CSS float) y un bloque LANG podía colarse al lado del ID anterior en
    // vez de apilarse bajo el bloque LANG anterior. clear fuerza dos
    // columnas realmente independientes, cada una apilada contra sí misma.
    // columnas simétricas 47%/47% → 6% de canalón (~10mm sobre la caja de texto
    // A4 con márgenes de 18mm). Con el 2% anterior (3,5mm) las dos lenguas se
    // leían como un solo bloque; este aire es lo que las separa de un vistazo.
    // float izq/der + clear = dos columnas independientes.
    + `${L2},${IDs}{width:47%;box-sizing:border-box}`
    // clear:both en la columna base (no clear:left) — cada pareja arranca una
    // fila nueva. Con clear:left cada columna se apilaba contra sí misma y, en
    // cuanto un párrafo español era más largo que su bahasa, la pareja se iba
    // desalineando y el desfase se acumulaba: al final del contrato el Pasal 3
    // quedaba a la altura del Artículo 2 (visible en el Artículo 15, el último).
    // Coste: un hueco en blanco cuando una versión es más corta. Barato al lado
    // de que el lector no pueda emparejar las cláusulas.
    + `${L2}{float:left;clear:both}`
    + `${IDs}{float:right;clear:right}`
    // Los RÓTULOS (h2/h3) también en dos columnas: el idioma base centrado en su
    // columna y el Bahasa centrado en la suya, en vez de apilados a lo ancho de
    // la página. Van aparte porque sus data-lang son <span> dentro de UN solo
    // elemento — las reglas de arriba solo alcanzan a p/ul/ol de nivel de bloque.
    // El ::after es obligatorio: sin él el h2 queda con altura 0 (solo floats
    // dentro) y su margen inferior se come el arranque de la cláusula.
    + `.doc h2>[data-lang="${LANG}"],.doc h3>[data-lang="${LANG}"]{float:left;clear:left;width:47%;box-sizing:border-box;text-align:center}`
    + `.doc h2>[data-lang="id"],.doc h3>[data-lang="id"]{float:right;clear:right;width:47%;box-sizing:border-box;text-align:center}`
    + `.doc h2::after,.doc h3::after{content:"";display:table;clear:both}`;
}

/* CSS que reskin-ea portada+interior según DESIGN (se inyecta en el <head> del doc) */
function designStyle(){
  const d=DESIGN;
  const color = d.coverColor || CURRENT.cover || '#104C4F';
  let css = `:root{--brand-deep:${color};}`;

  // portada · isotipo de fondo (moanito). Custom → sin filtro de blanqueo.
  const markSrc = d.coverMark.src || 'assets/brand/tiki-totem.png';
  css += `.lwcov .moai{${MARK_POS[d.coverMark.pos]||MARK_POS['bottom-center']}`
       + `height:${d.coverMark.pos==='fullbleed'?'auto':d.coverMark.size+'%'};`
       + `background-image:url("${markSrc}");background-position:${d.coverMark.pos==='fullbleed'?'center':'center bottom'};`
       + `background-size:${d.coverMark.pos==='fullbleed'?'cover':'contain'};`
       + `opacity:${d.coverMark.op};${d.coverMark.src?'filter:none;':''}}`;

  // portada · logo
  if(d.coverLogo.src){
    // La caja del logo es cuadrada pero el lockup es apaisado → con
    // background-position:center quedaba flotando en mitad de la caja, lejos del
    // borde, y encima pisaba el título. Anclando el dibujo al lado de su propia
    // posición, el logo se pega de verdad al margen que el usuario ha elegido.
    const anchor = d.coverLogo.pos.startsWith('bottom') ? 'center bottom'
                 : d.coverLogo.pos.startsWith('top')    ? 'center top' : 'center';
    css += `.lwcov .cov-logo{display:block;${COVER_POS[d.coverLogo.pos]||COVER_POS['top-center']}`
         + `width:${d.coverLogo.size}mm;height:${d.coverLogo.size}mm;`
         + `background-position:${anchor};`
         + `background-image:url("${d.coverLogo.src}");opacity:${d.coverLogo.op};}`;
  }
  // portada · imagen de fondo (sobre el color base; el usuario elige color O imagen)
  if(d.coverBg && d.coverBg.src){
    const fit=d.coverBg.pos, bg = fit==='repeat' ? 'center/auto repeat' : `center/${fit} no-repeat`;
    css += `.lwcov .cover-bg{display:block;background:url("${d.coverBg.src}") ${bg};opacity:${d.coverBg.op};}`;
  }
  // portada · profundidad (degradado) y textura (grano), editables
  css += `.lwcov .grad{opacity:${d.coverGrad};}.lwcov .grain{opacity:${d.coverGrain};}`;
  // portada · emblema de la esquina — SOLO si el usuario sube una imagen (sin default)
  if(d.coverEmblem.src){
    css += `.lwcov .emblem{display:block;${COVER_POS[d.coverEmblem.pos]||COVER_POS['top-right']}`
         + `width:${d.coverEmblem.size}mm;height:${d.coverEmblem.size}mm;`
         + `background:url("${d.coverEmblem.src}") no-repeat center/contain;opacity:${d.coverEmblem.op};}`;
  }
  // interior · marca de agua (funciona en plantillas con .doc)
  if(d.docMark.src){
    css += `.doc-watermark{display:none;}`;
    // position:fixed → marca de agua en CADA página (impresión) y persistente en el visor
    css += `.doc::before{content:"";position:fixed;${DOC_POS[d.docMark.pos]||DOC_POS.center}`
         + `height:${d.docMark.size}mm;width:100%;background:url("${d.docMark.src}") no-repeat center/contain;`
         + `opacity:${d.docMark.op};z-index:0;pointer-events:none;}`;
  }
  // interior · logo de cabecera EN CADA PÁGINA. position:fixed → Chromium lo
  // repite en todas las páginas al imprimir (igual que la marca de agua). Va en
  // la banda del margen superior; se agranda @page margin-top para que el cuerpo
  // no lo pise. z-index:1 = sobre la marca de agua (0) pero DEBAJO de la portada
  // y los anexos (2, opacos) → no aparece en portada ni en las páginas de anexo.
  if(d.docLogo.src){
    // la tabla envolvente .doc-runhead ya existe siempre (ver applyEditsAndTag + CSS del
    // head); aquí solo se pinta el logo en la celda del thead + un aire bajo él.
    css += `.doc-runhead>thead>tr>td{padding-bottom:6mm;}`
         + `.doc-brand-logo{display:block;height:${d.docLogo.size}mm;`
         + `background:url("${d.docLogo.src}") no-repeat ${d.docLogo.pos}/contain;opacity:${d.docLogo.op};}`;
  }
  // interior · IMAGEN DE FONDO por página (antes blanco). Mismo truco fijo que la
  // marca de agua → se repite en cada página impresa; z-index:-1 la deja detrás
  // del texto (z-index:1) y de la marca de agua (0). pos: cover|contain|repeat.
  // Sangra a borde de folio: @page va a margen 0 y los márgenes de texto los reserva
  // la tabla .doc-runhead (thead/tfoot), así el fijo cubre todo el A4 (ver CSS del head).
  if(d.docBg.src){
    const fit = d.docBg.pos;
    const bg  = fit==='repeat' ? 'center/auto repeat' : `center/${fit} no-repeat`;
    css += `.doc::after{content:"";position:fixed;inset:0;background:url("${d.docBg.src}") ${bg};`
         + `opacity:${d.docBg.op};z-index:-1;pointer-events:none;}`;
  }
  return css;
}

function buildDesignPanel(){
  const d=DESIGN, pct=v=>Math.round(v*100);
  const color = d.coverColor || CURRENT.cover;

  // tarjeta de un asset (logo / emblema / isotipo / marca de agua)
  const card=(key)=>{
    const s=d[key], cfg=SLOTS[key], opts=POS_OPTS[cfg.kind];
    const def=DEFAULT_SLOTS[key], active=!!(s.src||def);
    const thumb = s.src ? `background-image:url("${s.src}")` : (def?`background-image:url("${def}")`:'');
    const state = s.src ? 'Imagen propia' : (def?'Por defecto':'Sin imagen · sube una');
    return `<div class="dcard ${active?'':'empty'}" data-slot="${key}">
      <div class="dcard-head">
        <div class="dthumb" style="${thumb}">${thumb?'':'▦'}</div>
        <div class="dcard-title"><b>${L(cfg.label)}</b><span>${state}</span></div>
        <label class="dbtn upload">${s.src?'Cambiar':'Subir'}<input type="file" accept="image/*" data-df="${key}"></label>
        ${s.src?`<button type="button" class="dbtn ghost" data-dclear="${key}">Quitar</button>`:''}
      </div>
      <div class="dcard-ctl">
        <div class="dctl"><label>Posición</label>
          <select data-dp="${key}">${opts.map(o=>`<option value="${o[0]}" ${s.pos===o[0]?'selected':''}>${o[1]}</option>`).join('')}</select></div>
        <div class="dctl"><label>Tamaño <span class="v">${s.size}${cfg.unit}</span></label>
          <input type="range" min="${cfg.min}" max="${cfg.max}" value="${s.size}" data-dsize="${key}" data-unit="${cfg.unit}"></div>
        <div class="dctl full"><label>Opacidad <span class="v">${pct(s.op)}%</span></label>
          <input type="range" min="0" max="100" value="${pct(s.op)}" data-dop="${key}"></div>
      </div>
    </div>`;
  };

  // tarjeta de fondo de página (portada o interior): sin "Tamaño" (no aplica a
  // un fondo), Ajuste = cover/contain/mosaico. Reusa el wiring genérico (data-df/dp/dop).
  const bgCard=(key,label)=>{
    const s=d[key], thumb = s.src ? `background-image:url("${s.src}")` : '';
    const fits=[['cover','Rellenar'],['contain','Ajustar'],['repeat','Mosaico']];
    return `<div class="dcard ${s.src?'':'empty'}" data-slot="${key}">
      <div class="dcard-head">
        <div class="dthumb" style="${thumb}">${thumb?'':'▦'}</div>
        <div class="dcard-title"><b>${label}</b><span>${s.src?'Imagen propia':'Sin imagen · sube una'}</span></div>
        <label class="dbtn upload">${s.src?'Cambiar':'Subir'}<input type="file" accept="image/*" data-df="${key}"></label>
        ${s.src?`<button type="button" class="dbtn ghost" data-dclear="${key}">Quitar</button>`:''}
      </div>
      <div class="dcard-ctl">
        <div class="dctl"><label>Ajuste</label>
          <select data-dp="${key}">${fits.map(o=>`<option value="${o[0]}" ${s.pos===o[0]?'selected':''}>${o[1]}</option>`).join('')}</select></div>
        <div class="dctl full"><label>Opacidad <span class="v">${pct(s.op)}%</span></label>
          <input type="range" min="0" max="100" value="${pct(s.op)}" data-dop="${key}"></div>
      </div>
    </div>`;
  };

  /* Solo admin/super_admin, y escondido hasta que se pulsa «Diseño» en la
     barra (19-ago-2026, encargo del owner: «que solo sea un botón que ven los
     administradores, igual que Editar texto»). Mismo criterio que CAN_EDIT_TEXT
     y por el mismo motivo: el color de portada, el logo y la marca de agua son
     decisiones de marca, y además «Guardar como diseño de esta plantilla» las
     escribe para TODOS los agentes, no solo para quien las toca.
     Sin panel no hay nada que enganchar: wireDesignPanel() y rebuildDesign()
     salen solos si no lo encuentran, y el diseño se sigue aplicando igual
     porque lo pinta DESIGN, no este marcado. */
  if(!CAN_EDIT_TEXT) return '';
  return `<section class="section design collapsed" id="designPanel" hidden>
    <header data-acc><span class="num">🎨</span><h2>Diseño / Marca</h2><span class="chev">▾</span></header>
    <div class="body">
      <div class="dz" style="border-top:none;padding-top:0">
        <button type="button" class="btn ghost" id="btnSaveDesign" style="width:100%">Guardar como diseño de esta plantilla</button>
        <p style="font-size:11px;color:var(--muted);margin:6px 2px 0">Lo verán todos los agentes al abrir "${L(CURRENT.name)}" — no solo tú.</p>
      </div>
      <div class="dsec">Portada</div>
      <div class="drow"><span class="dlab">Color de fondo</span>
        <input type="color" class="dswatch" id="coverColor" value="${color}">
        <button type="button" class="dbtn ghost" id="coverColorReset">Color del tipo</button></div>
      <div class="drow"><span class="dlab">Degradado</span>
        <input type="range" min="0" max="100" value="${pct(d.coverGrad)}" data-dscalar="coverGrad"><span class="dval">${pct(d.coverGrad)}%</span></div>
      <div class="drow"><span class="dlab">Textura</span>
        <input type="range" min="0" max="40" value="${pct(d.coverGrain)}" data-dscalar="coverGrain"><span class="dval">${pct(d.coverGrain)}%</span></div>
      ${bgCard('coverBg','Fondo de página · portada')}
      ${card('coverLogo')}${card('coverEmblem')}${card('coverMark')}
      <div class="dsec">Interior</div>
      ${card('docLogo')}${card('docMark')}
      ${bgCard('docBg','Fondo de página · interior')}
    </div>
  </section>`;
}

/* eventos del panel (delegados). rebuild solo al subir/quitar imagen (cambia
   la estructura de la tarjeta); pos/tamaño/opacidad/escalares = solo re-render. */
function wireDesignPanel(){
  const panel=$('#designPanel'); if(!panel) return;
  const readout=(el,txt)=>{ const box=el.closest('.dctl,.drow'); const v=box&&box.querySelector('.v,.dval'); if(v) v.textContent=txt; };
  $('#coverColor').addEventListener('input',e=>{ DESIGN.coverColor=e.target.value; saveDesign(); render(); });
  $('#coverColorReset').addEventListener('click',()=>{ DESIGN.coverColor=''; saveDesign(); $('#coverColor').value=CURRENT.cover; render(); });
  $('#btnSaveDesign').addEventListener('click', saveSharedDesign);
  panel.addEventListener('change',e=>{
    const f=e.target.closest('[data-df]'); if(f && f.files[0]){ readImg(f.files[0], src=>{ DESIGN[f.dataset.df].src=src; saveDesign(); rebuildDesign(); render(); }); return; }
    const p=e.target.closest('[data-dp]'); if(p){ DESIGN[p.dataset.dp].pos=p.value; saveDesign(); render(); }
  });
  panel.addEventListener('input',e=>{
    const sz=e.target.closest('[data-dsize]'); if(sz){ DESIGN[sz.dataset.dsize].size=+sz.value; readout(sz, sz.value+(sz.dataset.unit||'')); saveDesign(); render(); return; }
    const op=e.target.closest('[data-dop]'); if(op){ DESIGN[op.dataset.dop].op=+op.value/100; readout(op, op.value+'%'); saveDesign(); render(); return; }
    const sc=e.target.closest('[data-dscalar]'); if(sc){ DESIGN[sc.dataset.dscalar]=+sc.value/100; readout(sc, sc.value+'%'); saveDesign(); render(); }
  });
  panel.addEventListener('click',e=>{
    const c=e.target.closest('[data-dclear]'); if(c){ DESIGN[c.dataset.dclear].src=''; saveDesign(); rebuildDesign(); render(); }
  });
}
function rebuildDesign(){
  const old=$('#designPanel'); if(!old) return;
  // rebuildDesign() corre al subir o quitar una imagen, o sea CON el panel
  // abierto: sin recordar el estado, el marcado nuevo vuelve `hidden` y
  // `collapsed` y el panel se cierra en las narices de quien lo estaba usando
  const visible = !old.hidden, abierto = !old.classList.contains('collapsed');
  old.outerHTML = buildDesignPanel(); wireDesignPanel(); wireAccordions();
  const nuevo = $('#designPanel');
  if(nuevo){ nuevo.hidden = !visible; nuevo.classList.toggle('collapsed', !abierto); }
}
function readImg(file, cb){ const r=new FileReader(); r.onload=()=>cb(r.result); r.readAsDataURL(file); }

/* ============================================================
   ANEXOS — se definen (PDF o imágenes → imágenes de página), se marcan
   "incluir" y se añaden al final del contrato como páginas NO editables.
   ============================================================ */
let ANNEXES = loadAnnexes();
let annexSeq = 1 + ANNEXES.reduce((m,a)=>Math.max(m, parseInt(String(a.id||'').replace('ax',''))||0), 0);
function loadAnnexes(){ try{ return JSON.parse(localStorage.getItem('lawang_contract_annexes'))||[]; }catch(_){ return []; } }
