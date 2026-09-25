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
  catch(_){ toastMal('Anexos demasiado grandes para guardar; se mantienen solo en esta sesión'); } }
function escAttr(s){ return String(s||'').replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;'); }

if(window.pdfjsLib) pdfjsLib.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';

/* CUÁNTO SE COMPRIME UNA PÁGINA DE ANEXO — 23-ago-2026, decisión del owner.
   ═══════════════════════════════════════════════════════════════════════════
   Estaba en 0.82. Los anexos son lo que más pesa de un contrato firmado: los
   ocho que los llevan ocupan 113 MB de los 358 del bucket, 14 MB cada uno.

   No se decidió a ojo ni por teoría. Se sacó una página REAL de un contrato en
   firma (la ficha Tropical de un `pendientes/`), se generaron las variantes con
   ESTE mismo codificador —el del navegador, no una herramienta de línea de
   comandos que comprime distinto— y el owner comparó las dos imágenes:

     calidad 82 (lo que había) ... 331 kB   100%
     calidad 72 .................. 291 kB    88%
     calidad 65 .................. 267 kB    81%
     calidad 55 (elegida) ........ 190 kB    57%
     75% de tamaño, calidad 78 ... 182 kB    55%

   Se eligió BAJAR CALIDAD y no bajar resolución: el anexo es una ficha
   comercial —render de la villa, planta en foto cenital, texto grande—, no un
   plano acotado. Una foto aguanta la compresión; una línea fina con cotas, no.
   Si algún día se adjunta un plano técnico de verdad, esta cifra hay que
   volver a mirarla CON un plano delante.

   Solo afecta a lo que se adjunte a partir de ahora. Lo ya firmado no se toca
   ni se puede tocar: se archiva exactamente lo que el comprador firmó. */
const CALIDAD_ANEXO = 0.55;

/* LOS PLANOS VAN A MÁS RESOLUCIÓN — 25-sep-2026, decisión del owner.
   ═══════════════════════════════════════════════════════════════════════════
   El día que llegó ese plano técnico (los Anexos Maestros del 23-sep) se
   volvió a mirar, como pedía el comentario de arriba. Una página A4 salía a
   1.190 px (el tope `2` de la escala manda antes que los 1.400) y las cotas
   de los alzados de Dali Bambú no se leían: «FFL +5.207» salía emborronado.

   Se midió con ESTE codificador (pdf.js 3.11 + canvas del navegador) sobre la
   página 2 de Dali Bambú (alzados acotados):
     1.190 px  q0.55 (lo de antes) .. 104 kB   cotas borrosas
     2.000 px  q0.55 ................ 220 kB   se leen todas
     2.000 px  q0.72 ................ 263 kB   igual que la anterior
     2.400 px  q0.72 ................ 336 kB   igual que la anterior
   Lo que hacía falta era RESOLUCIÓN, no calidad: CALIDAD_ANEXO no se toca.

   Y solo en las páginas que lo necesitan. Subir TODO el anexo a 2.000 px
   llevaba el de Dali de 4,3 a 9,4 MB (en base64), y eso engorda el PDF firmado,
   la tanda de correos de firma-submit y el render. Qué página es un plano se
   decide mirando la página ya pintada, no el PDF por dentro: en Dali los planos
   son vectoriales (25.000 trazos) y en Trinity, Temple y Dream son una foto
   incrustada con 3 trazos, así que contar trazos no sirve. Lo que sí comparten
   es el papel: fondo claro y sin color.

   Medido en los 11 planos de Modelos (% de la página casi blanca y gris):
     planos ............................ 67–99   (el más bajo, Dune Sirap p6)
     tablas de especificaciones ........ 66–93
     tabla con foto .................... 41–63
     fotos, portadas y renders ......... 0–47    (Extras, 66)
   Planos y tablas se solapan (67 frente a 66), así que no se puede separar
   uno de otro. Pero equivocarse hacia arriba solo cuesta peso, y hacia abajo
   deja una cota ilegible en un contrato. Por eso el corte va en 60, con margen
   por debajo del plano más pálido: entran todos los planos y también las
   tablas, que llevan letra pequeña y también ganan. Las fotos se quedan como
   estaban, byte a byte.

   Afecta también a un PDF subido a mano (pasa por la misma función). Una
   imagen suelta (compressImage) no cambia. */
const ANCHO_PLANO = 2000;
const CLARO_PLANO = 0.60;

/* Fracción de la página que es papel: casi blanca (el canal más oscuro ≥ 200)
   y sin color (canales a ≤ 24 entre sí). Se mide sobre una miniatura de 120 px.
   La proporción no depende del tamaño y es mucho más barato que leer 2 Mpx. */
function fraccionClara(cv){
  const w = 120, h = Math.max(1, Math.round(cv.height * w / cv.width));
  const m = document.createElement('canvas'); m.width = w; m.height = h;
  const cx = m.getContext('2d'); cx.drawImage(cv, 0, 0, w, h);
  const d = cx.getImageData(0, 0, w, h).data;
  let claro = 0;
  for(let k = 0; k < d.length; k += 4){
    const mx = Math.max(d[k], d[k+1], d[k+2]), mn = Math.min(d[k], d[k+1], d[k+2]);
    if(mn >= 200 && mx - mn <= 24) claro++;
  }
  return claro / (d.length / 4);
}

async function pintarPagina(page, escala){
  const vp = page.getViewport({scale: escala});
  const cv = document.createElement('canvas'); cv.width=vp.width; cv.height=vp.height;
  await page.render({canvasContext:cv.getContext('2d'), viewport:vp}).promise;
  return cv;
}

async function pdfToImages(file){
  // acepta File/Blob o un ArrayBuffer ya leído (el anexo automático necesita el
  // buffer aparte para calcular su hash antes de que pdf.js se lo quede)
  const buf = file instanceof ArrayBuffer ? file : await file.arrayBuffer();
  const pdf = await pdfjsLib.getDocument({data:buf}).promise;
  const out=[];
  for(let i=1;i<=pdf.numPages;i++){
    const page = await pdf.getPage(i);
    const base = page.getViewport({scale:1});
    let cv = await pintarPagina(page, Math.min(1400/base.width, 2));
    // Tope 4×: una página diminuta no se convierte en un lienzo gigante.
    if(fraccionClara(cv) >= CLARO_PLANO) cv = await pintarPagina(page, Math.min(ANCHO_PLANO/base.width, 4));
    out.push(cv.toDataURL('image/jpeg', CALIDAD_ANEXO));
  }
  return out;
}
function compressImage(file){
  return new Promise((res,rej)=>{ const img=new Image(); const url=URL.createObjectURL(file);
    img.onload=()=>{ URL.revokeObjectURL(url); const s=Math.min(1400/img.naturalWidth,1);
      const cv=document.createElement('canvas'); cv.width=Math.round(img.naturalWidth*s); cv.height=Math.round(img.naturalHeight*s);
      cv.getContext('2d').drawImage(img,0,0,cv.width,cv.height); res([cv.toDataURL('image/jpeg', CALIDAD_ANEXO)]); };
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
let AUTO_ANX = '';    // "tipología§techo" cuyo anexo está puesto o pedido (evita un fetch por tecla)
let AUTO_CARGA = '';  // tipología que se está convirtiendo AHORA. Estado propio y no
                      // inferido de ANNEXES: si el PDF no existe, "sin anexo" y "aún
                      // convirtiendo" son el mismo estado y el panel se quedaba
                      // diciendo "Preparando…" para siempre (visto el 30-jul-2026).
/* DE DÓNDE SALE EL PDF DEL ANEXO — 8-sep-2026, encargo del owner.
   ═══════════════════════════════════════════════════════════════════════════
   Hasta hoy: un fichero por tipología en `assets/anexos/`, servido por
   convención de nombre. Funciona, pero para añadir el anexo de un modelo hay que
   pasar por el repo — o sea por nosotros—, y el cliente ya da de alta sus
   modelos solo en `intranet/modelos/`, documentos incluidos.

   Desde hoy manda MODELOS: se busca el documento de tipo `plano` del modelo (el
   más reciente si hay varios) en el bucket privado `modelos`, con URL firmada —
   el mismo camino que ya usa la KTP del apoderado en app.html.

   Y SI ESE MODELO NO TIENE NINGUNO, se cae al PDF estático de siempre. No es
   pereza: hoy `modelo_documentos` está vacía y en `assets/anexos/` solo hay
   `Dali.pdf` y `Tropical.pdf`. Sin la red, este cambio dejaría sin anexo
   automático a los únicos dos que lo tienen. La red se puede retirar el día que
   todos los modelos vivos tengan el suyo subido.

   El SHA se calcula sobre el buffer venga de donde venga, así que el aviso «el
   pack ha cambiado desde que se guardó este contrato» sigue funcionando igual —
   y ahora también detecta que alguien ha sustituido el plano desde Modelos.

   POR TECHO — 23-sep-2026, encargo del owner: el «Anexo Maestro» viene uno
   por modelo Y acabado de techo (Dali Bambu ≠ Dali Sirap: cambian planos,
   secciones y memoria). `modelo_documentos.techo_clave` dice a qué techo
   pertenece cada plano; NULL = vale para cualquiera. Se busca primero el del
   techo elegido y, si no hay, el genérico. Un plano de OTRO techo nunca se
   usa, y con techo elegido tampoco el PDF del repo (no dice de qué techo es):
   mejor sin anexo automático, y avisado, que con los planos del tejado que no es.
   Devuelve { buf, techo } — `techo` es la clave del plano usado, o ''. */
async function bufferDelAnexo(tip, techo){
  const ficha = (typeof fichaDelModelo === 'function') ? fichaDelModelo(tip) : null;
  if(ficha && typeof sb !== 'undefined' && sb){
    /* Si Modelos falla se sigue al PDF estático —mejor un anexo que ninguno—,
       pero NO en silencio: que el modelo TENGA un plano subido y el contrato
       acabe llevando el fichero viejo del repo es exactamente la divergencia que
       este cambio venía a cerrar, y sin aviso nadie la nota hasta que el
       documento está firmado. Se dice qué pasó y con qué se ha quedado. */
    let doc = null;
    try{
      const { data, error } = await sb.from('modelo_documentos')
        .select('path, nombre, tipo, techo_clave, subido_en').eq('modelo_id', ficha.id).eq('tipo', 'plano')
        .order('subido_en', { ascending:false });
      if(error) throw error;
      const planos = data || [];
      doc = (techo && planos.find(d => d.techo_clave === techo)) || planos.find(d => !d.techo_clave) || null;
      if(doc && doc.path){
        const { data:url, error:eUrl } = await sb.storage.from('modelos').createSignedUrl(doc.path, 3600);
        if(eUrl || !url || !url.signedUrl) throw (eUrl || new Error('sin URL firmada'));
        const r = await fetch(url.signedUrl);
        if(!r.ok) throw new Error('HTTP ' + r.status);
        return { buf: await r.arrayBuffer(), techo: doc.techo_clave || '' };
      }
    }catch(e){
      // Solo se avisa si HABÍA algo que traerse. Que un modelo no tenga plano en
      // Modelos es lo normal hoy (la tabla está vacía) y no es un fallo.
      if(doc) toastMal('El plano de ' + tip + ' está en Modelos pero no se ha podido leer ('
                    + ((e && e.message) || 'error') + '). Se usa el PDF de siempre.');
    }
  }
  /* Con un techo real elegido NO se cae al PDF del repo: no dice de qué techo
     es, y el Anexo Maestro es el Apéndice A del contrato (Legal, consulta de
     deploy 23-sep-2026). Mejor sin anexo y avisado que con otro tejado. */
  if(techo) throw new Error('sin plano para el techo ' + techo);
  const r = await fetch('assets/anexos/'+encodeURIComponent(tip)+'.pdf');
  if(!r.ok) throw new Error(r.status);
  return { buf: await r.arrayBuffer(), techo: '' };
}

/* Techo que decide el anexo: el elegido en el contrato (techo_extras.js). El
   «sintético» —modelo sin variantes, la única opción calculada del precio
   base— no es un techo de modelo_techos y no tiene plano propio. */
function techoDelAnexo(){
  const t = (typeof TECHO_ELEGIDO !== 'undefined') ? TECHO_ELEGIDO : null;
  return (t && !t.sintetico && t.clave) ? t.clave : '';
}

async function syncAutoAnnex(){
  const el = document.querySelector('[name="tipologia_construccion"]');
  const tip = el ? el.value.trim() : '';       // sin campo (otra plantilla) → se quita el anexo
  /* Mientras llegan las opciones de techo del modelo no se decide nada: con el
     techo aún vacío se bajaría y convertiría el plano genérico (o el PDF viejo
     del repo) para tirarlo un segundo después. cargarTechosYExtras() vuelve a
     llamar aquí al terminar. */
  if(tip && typeof TECHO_CARGANDO !== 'undefined' && TECHO_CARGANDO && !techoDelAnexo()) return;
  const techo = tip ? techoDelAnexo() : '';
  const clave = tip ? tip + '§' + techo : '';
  if(clave === AUTO_ANX) return;
  AUTO_ANX = clave;
  // La entrada guardada (sin páginas) trae dos cosas que NO se pueden re-derivar:
  // si el agente apagó "Incluir en el contrato", y el hash del PDF que se anexó
  // de verdad. Sin esto, un anexo excluido a propósito volvía a entrar solo al
  // reabrir, al derivar un contrato hijo o al rearrancar la cadena de firma.
  const guardado = ANNEXES.find(a=>a.auto===tip);
  ANNEXES = ANNEXES.filter(a=>!a.auto);
  if(!tip){ AUTO_CARGA=''; saveAnnexes(); rebuildAnnex(); render(); return; }
  AUTO_CARGA = tip; rebuildAnnex();
  try{
    const { buf, techo:techoPlano } = await bufferDelAnexo(tip, techo);
    const sha = await sha256hex(buf);           // antes de pdf.js: se queda el buffer
    const pages = await pdfToImages(buf);
    if(AUTO_ANX !== clave) return;             // cambió de tipología o de techo mientras se convertía
    // El nombre del techo solo va al título si el plano ES de ese techo.
    const nomTecho = techoPlano && TECHO_ELEGIDO && TECHO_ELEGIDO.nombre ? ' · ' + TECHO_ELEGIDO.nombre : '';
    ANNEXES = [{ id:'axauto', auto:tip, techo, sha, title:'Planos y Especificaciones · '+tip+nomTecho,
                 pages, on: guardado ? guardado.on !== false : true },
               ...ANNEXES.filter(a=>!a.auto)];
    // El PDF del servidor es mutable: si cambió desde que se guardó el contrato,
    // el anexo que se ve ya NO es el que se firmó. Se avisa, no se oculta.
    // Si lo que cambió es el TECHO ELEGIDO (el agente eligió otro), el pack
    // distinto es lo esperado y no un cambio en el servidor. Se compara con el
    // techo elegido, no con el del plano encontrado: si alguien retira el plano
    // Sirap de Modelos y el contrato cae a otro, eso SÍ tiene que avisar
    // (Legal, 23-sep). `techo` ausente = guardado antes del 23-sep: se avisa.
    const cambioDeTecho = guardado && guardado.techo !== undefined && guardado.techo !== techo;
    if(guardado && guardado.sha && guardado.sha !== sha && !cambioDeTecho)
      toastMal('OJO: el pack de '+tip+' ha cambiado desde que se guardó este contrato');
    else toast('Anexo de '+tip+' adjuntado ('+pages.length+' pág.)');
  }catch(_){
    if(AUTO_ANX === clave){
      if(techo) toastMal('Sin Anexo Maestro de '+tip+' con el techo elegido: súbelo en Modelos (tipo Plano, con su techo) o añádelo a mano');
      else toast('Sin anexo automático para '+tip+' — súbelo a mano si lo necesitas');
    }
  }
  if(AUTO_CARGA === tip && AUTO_ANX === clave) AUTO_CARGA = '';
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
      catch(err){ toastMal('No se pudo procesar '+f.name); }
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
