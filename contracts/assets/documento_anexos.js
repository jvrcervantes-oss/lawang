/* ═══════════════════════════════════════════════════════════════════════════
   ANEXOS, CLÁUSULAS Y COMPRADORES EXTRA del documento
   Sale de contracts/app.html el 21-ago-2026.
   ═══════════════════════════════════════════════════════════════════════════
   Las tres listas que un contrato puede llevar además de su plantilla. Del
   anexo automático se guarda la FICHA y nunca las páginas: 27 páginas en base64
   dentro del jsonb es lo que engorda la base hasta el límite del plan.

   OJO al orden: `CLAUSES` y `COMPRADORES` se inicializan AL CARGAR leyendo
   localStorage (loadClauses / loadCompradores, que viajan en este mismo
   fichero). No dependen de nada de app.html, y por eso se puede cargar antes.
   ═══════════════════════════════════════════════════════════════════════════ */
/* Del anexo automático se guarda la FICHA, nunca las páginas: 27 páginas en
   base64 son 6-8 MB que no caben en localStorage y engordarían cada fila de
   `contratos` (ya son 97% blobs). Las imágenes se re-derivan del PDF al abrir;
   lo que sí viaja es `on` (si se excluyó a propósito) y `sha` (qué versión del
   pack se anexó de verdad), que no se pueden reconstruir de ninguna otra parte. */
const sinPaginas = a => a.auto ? {...a, pages:[]} : a;
function saveAnnexes(){ try{ localStorage.setItem('lawang_contract_annexes', JSON.stringify(ANNEXES.map(sinPaginas))); }
  catch(_){ toast('Anexos demasiado grandes para guardar; se mantienen solo en esta sesión'); } }
function escAttr(s){ return String(s||'').replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;'); }

if(window.pdfjsLib) pdfjsLib.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';

async function pdfToImages(file){
  // acepta File/Blob o un ArrayBuffer ya leído (el anexo automático necesita el
  // buffer aparte para calcular su hash antes de que pdf.js se lo quede)
  const buf = file instanceof ArrayBuffer ? file : await file.arrayBuffer();
  const pdf = await pdfjsLib.getDocument({data:buf}).promise;
  const out=[];
  for(let i=1;i<=pdf.numPages;i++){
    const page = await pdf.getPage(i);
    const base = page.getViewport({scale:1});
    const vp = page.getViewport({scale: Math.min(1400/base.width, 2)});
    const cv = document.createElement('canvas'); cv.width=vp.width; cv.height=vp.height;
    await page.render({canvasContext:cv.getContext('2d'), viewport:vp}).promise;
    out.push(cv.toDataURL('image/jpeg', .82));
  }
  return out;
}
function compressImage(file){
  return new Promise((res,rej)=>{ const img=new Image(); const url=URL.createObjectURL(file);
    img.onload=()=>{ URL.revokeObjectURL(url); const s=Math.min(1400/img.naturalWidth,1);
      const cv=document.createElement('canvas'); cv.width=Math.round(img.naturalWidth*s); cv.height=Math.round(img.naturalHeight*s);
      cv.getContext('2d').drawImage(img,0,0,cv.width,cv.height); res([cv.toDataURL('image/jpeg',.82)]); };
    img.onerror=rej; img.src=url; });
}
async function fileToAnnexPages(file){
  if(file.type==='application/pdf' || /\.pdf$/i.test(file.name)){
    if(!window.pdfjsLib) throw new Error('pdf.js no cargó'); return await pdfToImages(file);
  }
  return await compressImage(file);
}

/* ---------- Anexo automático por tipología ----------
   Al elegir la tipología de vivienda se adjunta su pack de planos y
   especificaciones sin que el agente suba nada. Por CONVENCIÓN de nombre, no por
   una lista a mano: el fichero es `assets/anexos/<Tipología>.pdf`, así que una
   tipología nueva solo necesita su PDF ahí y su opción en tokens.json. Si el PDF
   no existe (Dream, Dune, Trinity, Temple a 30-jul-2026) no hay anexo automático
   y el agente puede seguir subiéndolo a mano como siempre.

   En `assets/anexos/` SOLO van packs de anexo. Los folletos comerciales viven en
   `assets/folletos/` desde el 30-jul: compartían carpeta, y renombrar uno a
   `Dune.pdf` habría metido su "Desde 66.000€" dentro de todos los PPJB firmados
   de Dune. Una carpeta que se lee por convención de nombre no admite vecinos. */
let AUTO_ANX = '';    // tipología cuyo anexo está puesto o pedido (evita un fetch por tecla)
let AUTO_CARGA = '';  // tipología que se está convirtiendo AHORA. Estado propio y no
                      // inferido de ANNEXES: si el PDF no existe, "sin anexo" y "aún
                      // convirtiendo" son el mismo estado y el panel se quedaba
                      // diciendo "Preparando…" para siempre (visto el 30-jul-2026).
async function syncAutoAnnex(){
  const el = document.querySelector('[name="tipologia_construccion"]');
  const tip = el ? el.value.trim() : '';       // sin campo (otra plantilla) → se quita el anexo
  if(tip === AUTO_ANX) return;
  AUTO_ANX = tip;
  // La entrada guardada (sin páginas) trae dos cosas que NO se pueden re-derivar:
  // si el agente apagó "Incluir en el contrato", y el hash del PDF que se anexó
  // de verdad. Sin esto, un anexo excluido a propósito volvía a entrar solo al
  // reabrir, al derivar un contrato hijo o al rearrancar la cadena de firma.
  const guardado = ANNEXES.find(a=>a.auto===tip);
  ANNEXES = ANNEXES.filter(a=>!a.auto);
  if(!tip){ AUTO_CARGA=''; saveAnnexes(); rebuildAnnex(); render(); return; }
  AUTO_CARGA = tip; rebuildAnnex();
  try{
    const r = await fetch('assets/anexos/'+encodeURIComponent(tip)+'.pdf');
    if(!r.ok) throw new Error(r.status);
    const buf = await r.arrayBuffer();
    const sha = await sha256hex(buf);           // antes de pdf.js: se queda el buffer
    const pages = await pdfToImages(buf);
    if(AUTO_ANX !== tip) return;               // cambió de tipología mientras se convertía
    ANNEXES = [{ id:'axauto', auto:tip, sha, title:'Planos y Especificaciones · '+tip,
                 pages, on: guardado ? guardado.on !== false : true },
               ...ANNEXES.filter(a=>!a.auto)];
    // El PDF del servidor es mutable: si cambió desde que se guardó el contrato,
    // el anexo que se ve ya NO es el que se firmó. Se avisa, no se oculta.
    if(guardado && guardado.sha && guardado.sha !== sha)
      toast('OJO: el pack de '+tip+' ha cambiado desde que se guardó este contrato');
    else toast('Anexo de '+tip+' adjuntado ('+pages.length+' pág.)');
  }catch(_){
    if(AUTO_ANX === tip) toast('Sin anexo automático para '+tip+' — súbelo a mano si lo necesitas');
  }
  if(AUTO_CARGA === tip) AUTO_CARGA = '';
  saveAnnexes(); rebuildAnnex(); render();
}

function buildAnnexPanel(){
  const cargando = AUTO_CARGA
    ? `<div class="dz" style="color:var(--muted);font-size:12.5px">Preparando el anexo de ${escAttr(AUTO_CARGA)}…</div>` : '';
  // un anexo sin páginas no se pinta: es la ficha guardada del automático, que
  // aún no ha rehidratado (si no, parpadea un "0 pág." al abrir un contrato)
  const rows = cargando + ANNEXES.filter(a=>a.pages && a.pages.length).map((a,i)=> a.auto ? `
    <div class="dz" data-anx="${a.id}">
      <div class="dz-row">
        <span style="flex:1;font-size:13px">${escAttr(a.title)}</span>
        <span style="font-size:11px;color:var(--muted);white-space:nowrap">${a.pages.length} pág. · automático</span>
      </div>
      <div class="dz-row"><label class="switch"><input type="checkbox" data-anxon="${a.id}" ${a.on?'checked':''}><span class="slider"></span></label>
        <span>Incluir en el contrato</span></div>
    </div>` : `
    <div class="dz" data-anx="${a.id}">
      <div class="dz-row">
        <input class="anx-title" data-anxtitle="${a.id}" value="${escAttr(a.title)}" aria-label="Título del anexo" style="flex:1;font:inherit;font-size:13px;padding:7px 10px;border:1px solid var(--line);border-radius:8px">
        <span style="font-size:11px;color:var(--muted);white-space:nowrap">${a.pages.length} pág.</span>
        <button type="button" class="link-btn" data-anxdel="${a.id}">Quitar</button>
      </div>
      <div class="dz-row"><label class="switch"><input type="checkbox" data-anxon="${a.id}" ${a.on?'checked':''}><span class="slider"></span></label>
        <span>Incluir en el contrato</span></div>
    </div>`).join('') || `<div class="dz" style="color:var(--muted);font-size:12.5px">Aún no hay anexos. Sube un PDF o imágenes para definirlos.</div>`;
  return `<section class="section design collapsed" id="annexPanel">
    <header data-acc><span class="num">📎</span><h2>Anexos</h2><span class="chev">▾</span></header>
    <div class="body">
      ${rows}
      <div class="dz"><label class="up" id="anxUpLabel">+ Añadir anexo (PDF o imágenes)<input type="file" id="anxFile" accept="application/pdf,image/*" multiple></label></div>
    </div>
  </section>`;
}
function wireAnnexPanel(){
  const p=$('#annexPanel'); if(!p) return;
  $('#anxFile').addEventListener('change', async e=>{
    const files=[...e.target.files]; if(!files.length) return;
    const lbl=$('#anxUpLabel'); const t0=lbl.textContent; lbl.textContent='Procesando…';
    for(const f of files){
      try{ const pages=await fileToAnnexPages(f); ANNEXES.push({id:'ax'+(annexSeq++), title:f.name.replace(/\.[^.]+$/,''), pages, on:true}); }
      catch(err){ toast('No se pudo procesar '+f.name); }
    }
    lbl.textContent=t0; saveAnnexes(); rebuildAnnex(); render();
  });
  p.addEventListener('change', e=>{
    const on=e.target.closest('[data-anxon]'); if(on){ const a=ANNEXES.find(x=>x.id===on.dataset.anxon); if(a){ a.on=on.checked; saveAnnexes(); render(); } return; }
    const t=e.target.closest('[data-anxtitle]'); if(t){ const a=ANNEXES.find(x=>x.id===t.dataset.anxtitle); if(a){ a.title=t.value; saveAnnexes(); render(); } }
  });
  p.addEventListener('click', e=>{
    const d=e.target.closest('[data-anxdel]'); if(d){ ANNEXES=ANNEXES.filter(x=>x.id!==d.dataset.anxdel); saveAnnexes(); rebuildAnnex(); render(); }
  });
}
function rebuildAnnex(){ const old=$('#annexPanel'); if(old){ old.outerHTML=buildAnnexPanel(); wireAnnexPanel(); wireAccordions(); } }

/* páginas de anexos incluidos, al final del contrato (portada de anexo + imágenes de página) */
function annexHTML(){
  const on=ANNEXES.filter(a=>a.on && a.pages && a.pages.length);
  if(!on.length) return '';
  // Trilingüe, no L(): el rótulo del anexo es parte del documento y el bahasa
  // tiene que salir siempre, igual que en el resto del contrato.
  const lbl=(n)=>`<span data-lang="es">Anexo ${n}</span><span data-lang="en">Annex ${n}</span><span data-lang="id">Lampiran ${n}</span>`;
  let h='<div class="annexes">';
  on.forEach((a,i)=>{
    h+=`<section class="annex-cover"><div class="annex-label">${lbl(i+1)}</div><div class="annex-name">${escAttr(a.title)}</div></section>`;
    a.pages.forEach(src=>{ h+=`<section class="annex-page"><img src="${src}" alt=""></section>`; });
  });
  return h+'</div>';
}

/* ============================================================
   CLÁUSULAS ADICIONALES — texto propio que se inyecta antes de las
   firmas (marcador <!--extra-clauses--> en la plantilla). Cada cláusula:
   título + cuerpo en ES / EN / Bahasa. El idioma que quede vacío no se
   imprime. Persisten en localStorage (como anexos y diseño).
   ============================================================ */
let CLAUSES = loadClauses();
let clauseSeq = 1 + CLAUSES.reduce((m,c)=>Math.max(m, parseInt(String(c.id||'').replace('cl',''))||0), 0);
function loadClauses(){ try{ return JSON.parse(localStorage.getItem('lawang_contract_clauses'))||[]; }catch(_){ return []; } }
function saveClauses(){ try{ localStorage.setItem('lawang_contract_clauses', JSON.stringify(CLAUSES)); }catch(_){} }

function buildClausePanel(){
  const box=(c,pfx,ta)=>['es','en','id'].map(l=>{
    const v=escAttr(c[pfx+'_'+l]||''); const ph=(pfx==='t'?'Título':'Texto')+' · '+l.toUpperCase();
    const st='font:inherit;font-size:13px;padding:8px 10px;border:1px solid var(--line);border-radius:8px;background:#fdfcf9;width:100%';
    return ta ? `<textarea data-cl="${c.id}" data-clk="${pfx}_${l}" rows="2" placeholder="${ph}" style="${st};resize:vertical">${v}</textarea>`
              : `<input data-cl="${c.id}" data-clk="${pfx}_${l}" value="${v}" placeholder="${ph}" style="${st}">`;
  }).join('');
  const g='display:grid;grid-template-columns:1fr 1fr 1fr;gap:6px';
  const rows = CLAUSES.map((c,i)=>`
    <div class="dz" data-clause="${c.id}">
      <div class="dz-row"><span style="width:auto;font-weight:600;color:var(--dl)">${L({es:'Artículo',en:'Article',id:'Pasal'})} ${i+1}</span>
        <span class="spacer" style="flex:1"></span>
        <label class="switch"><input type="checkbox" data-clon="${c.id}" ${c.on!==false?'checked':''}><span class="slider"></span></label>
        <button type="button" class="link-btn" data-cldel="${c.id}">${L({es:'Quitar',en:'Remove',id:'Hapus'})}</button></div>
      <div class="dz-row" style="display:block"><div style="font-size:11.5px;color:var(--muted);margin-bottom:4px">${L({es:'Título (ES · EN · Bahasa)',en:'Title (ES · EN · Bahasa)',id:'Judul (ES · EN · Bahasa)'})}</div>
        <div style="${g}">${box(c,'t',false)}</div></div>
      <div class="dz-row" style="display:block"><div style="font-size:11.5px;color:var(--muted);margin:6px 0 4px">${L({es:'Texto (ES · EN · Bahasa)',en:'Text (ES · EN · Bahasa)',id:'Teks (ES · EN · Bahasa)'})}</div>
        <div style="${g}">${box(c,'b',true)}</div></div>
    </div>`).join('') || `<div class="dz" style="color:var(--muted);font-size:12.5px">${L({es:'Sin artículos adicionales. Añade uno para insertar texto propio antes de las firmas.',en:'No additional articles yet. Add one to insert your own text before the signatures.',id:'Belum ada pasal tambahan.'})}</div>`;
  return `<section class="section design collapsed" id="clausePanel">
    <header data-acc><span class="num">📝</span><h2>${L({es:'Artículos adicionales',en:'Additional articles',id:'Pasal tambahan'})}</h2><span class="chev">▾</span></header>
    <div class="body">${rows}
      <div class="dz"><button type="button" class="btn ghost" id="clauseAdd">+ ${L({es:'Añadir artículo',en:'Add article',id:'Tambah pasal'})}</button></div>
    </div></section>`;
}
function wireClausePanel(){
  const p=$('#clausePanel'); if(!p) return;
  p.addEventListener('input', e=>{ const el=e.target.closest('[data-cl]'); if(!el) return;
    const c=CLAUSES.find(x=>x.id===el.dataset.cl); if(c){ c[el.dataset.clk]=el.value; saveClauses(); renderDebounced(); } });
  p.addEventListener('change', e=>{ const on=e.target.closest('[data-clon]'); if(on){ const c=CLAUSES.find(x=>x.id===on.dataset.clon); if(c){ c.on=on.checked; saveClauses(); render(); } } });
  p.addEventListener('click', e=>{
    if(e.target.closest('#clauseAdd')){ CLAUSES.push({id:'cl'+(clauseSeq++), on:true}); saveClauses(); rebuildClause(); render(); return; }
    const d=e.target.closest('[data-cldel]'); if(d){ CLAUSES=CLAUSES.filter(x=>x.id!==d.dataset.cldel); saveClauses(); rebuildClause(); render(); }
  });
}
function rebuildClause(){ const old=$('#clausePanel'); if(old){ old.outerHTML=buildClausePanel(); wireClausePanel(); wireAccordions(); } }

/* ============================================================
   ADQUIRIENTES ADICIONALES — Adquiriente I sigue siendo el campo fijo de
   siempre; a partir del II la lista es dinámica y sin tope (antes eran 2
   secciones fijas, II y III). Solo aparece si la plantilla activa trae el
   marcador <!--compradores-extra-->. Mismo patrón que Anexos/Cláusulas
   (localStorage, sin namespacing por plantilla). Cada plantilla conserva su
   propia redacción de la cláusula "Adquiriente N" (ver COMPRADOR_FRASE).
   ============================================================ */
let COMPRADORES = loadCompradores();
let compradorSeq = 1 + COMPRADORES.reduce((m,c)=>Math.max(m, parseInt(String(c.id||'').replace('bc',''))||0), 0);
function loadCompradores(){ try{ return JSON.parse(localStorage.getItem('lawang_contract_compradores'))||[]; }catch(_){ return []; } }
function saveCompradores(){ try{ localStorage.setItem('lawang_contract_compradores', JSON.stringify(COMPRADORES)); }catch(_){} }
function romano(n){ const vals=[[10,'X'],[9,'IX'],[5,'V'],[4,'IV'],[1,'I']]; let r='',x=n;
  for(const [v,s] of vals){ while(x>=v){ r+=s; x-=v; } } return r; }
