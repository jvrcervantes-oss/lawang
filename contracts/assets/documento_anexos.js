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

/* ═══════════════════════════════════════════════════════════════════════════
   LOS ANEXOS SUBIDOS A MANO VIVEN EN STORAGE — LAW-78, 27-sep-2026
   ═══════════════════════════════════════════════════════════════════════════
   Hasta hoy sus páginas (JPEG en base64) viajaban DENTRO de `datos`: el guardado
   cortaba por tiempo con 6,5 MB y cada lectura del contrato descomprimía los 7 MB
   del mayor. Ahora cada página es un objeto del bucket privado `contratos-anexos`
   y una fila de `contrato_anexo_paginas` (ruta, sha256, bytes), que es la ÚNICA
   fuente del recuento. En `datos.annexes` el anexo manual es solo su ficha
   {id, title, on}. Diseño y porqué: supabase/migrations/20260927220000_law78_*.sql.

   En memoria un anexo manual puede estar de tres formas:
     · en el archivo ...... `almacen` = filas de la tabla, `contrato` = de qué
                            contrato son, `pages` = las imágenes ya bajadas y
                            comprobadas (null en la que falta), `faltan` = [n].
     · viejo (legado) ..... `pages` con el base64 que venía en `datos`, sin
                            `almacen`. Se sigue leyendo; al volver a guardar el
                            contrato se sube primero ENTERO al archivo y solo
                            entonces se guarda sin páginas (migración perezosa).
     · ficha sola ......... ni lo uno ni lo otro: no se puede imprimir.
   `estado` (solo memoria): 'cargando' | 'subiendo' | 'ok' | 'falta' | 'error'.

   El contenido de un id de anexo NO cambia nunca: cada subida, y cada paso de un
   anexo viejo al archivo, estrena un id (`ax-<uuid>`). Antes el id era `ax<n>`,
   recalculado desde el máximo al recargar: quitar ax3 y subir otro reutilizaba
   ax3, y con filas en una tabla eso habría pegado páginas viejas al anexo nuevo.

   Lo que se queda sin usar (una subida a medias, un anexo quitado) no se borra
   en caliente: lo recoge contracts/tools/anexos_barrido.py pasadas 48 h. */
const BUCKET_ANEXOS = 'contratos-anexos';
const PAGINA_MAX_BYTES = 3 * 1024 * 1024;        // = file_size_limit del bucket
/* Tope por MEMORIA del navegador, no del servidor: las páginas se convierten y se
   tienen en memoria como base64 hasta subirlas. Un PDF escaneado de 118 MB cerró
   la pestaña en la medición del 27-sep; 150 páginas / 80 MB de base64 entre todos
   los anexos subidos a mano deja margen a los mayores reales (28 páginas, 5 MB). */
const MAX_PAGINAS_FICHERO = 150;
const TOPE_MEMORIA_BYTES = 80 * 1024 * 1024;
const ES_ALMACEN = a => !a.auto && Array.isArray(a.almacen);
const ES_LEGADO = a => !a.auto && !Array.isArray(a.almacen) && Array.isArray(a.pages) && a.pages.length > 0;
const idAnexoNuevo = () => 'ax-' + crypto.randomUUID();
/* Páginas de un anexo manual: las filas si está en el archivo, las imágenes si es viejo. */
const numPaginas = a => ES_ALMACEN(a) ? a.almacen.length : (a.pages || []).length;

/* Lo que va a `datos.annexes` al guardar el contrato `contratoId`. Un anexo del
   archivo lleva solo su ficha, pero SOLO si sus filas son de ESTE contrato: uno
   que viene de otro (el contrato abierto se borró y se guarda como nuevo) no tiene
   filas aquí, así que viaja como viejo, con sus páginas, y pasa al archivo en el
   siguiente guardado. */
function fichaDatos(a, contratoId){
  if(a.auto) return { ...limpiaMemoria(a), pages:[] };
  if(ES_ALMACEN(a) && contratoId && a.contrato === contratoId) return { id:a.id, title:a.title, on:a.on };
  if(Array.isArray(a.pages) && a.pages.length && a.pages.every(Boolean)) return { id:a.id, title:a.title, on:a.on, pages:a.pages };
  return { id:a.id, title:a.title, on:a.on };
}
function limpiaMemoria(a){ const o = { ...a }; delete o.almacen; delete o.contrato; delete o.estado; delete o.faltan; delete o.error; return o; }

/* Anexos tal como llegan de `datos` al abrir un contrato. Un manual sin páginas es
   del archivo: queda 'cargando' hasta que cargaAnexosAlmacen() lo rellene. */
function normalizaAnexos(lista){
  return (Array.isArray(lista) ? lista : []).filter(a => a && typeof a === 'object').map(a => {
    if(a.auto) return sinPaginas(a);
    if(Array.isArray(a.pages) && a.pages.length) return { id:a.id, title:a.title, on:a.on !== false, pages:a.pages };
    return { id:a.id, title:a.title, on:a.on !== false, pages:[], almacen:[], estado:'cargando' };
  });
}

/* ¿Qué impide guardar (o firmar, con soloIncluidos) el contrato tal como está?
   Devuelve frases que nombran anexo y página. Vacío = se puede. Función pura:
   la prueba documento_anexos.test.js la recorre entera. */
function problemasAnexos(lista, opciones){
  const soloIncluidos = !!(opciones && opciones.soloIncluidos);
  const out = [];
  (lista || []).filter(a => !a.auto && (!soloIncluidos || a.on)).forEach(a => {
    const nom = '«' + (a.title || 'sin título') + '»';
    if(a.estado === 'cargando'){ out.push('el anexo ' + nom + ' aún se está cargando'); return; }
    if(a.estado === 'subiendo'){ out.push('el anexo ' + nom + ' aún se está subiendo'); return; }
    if(a.estado === 'error'){ out.push('no se ha podido comprobar el anexo ' + nom + (a.error ? ' (' + a.error + ')' : '')); return; }
    if(ES_ALMACEN(a)){
      if(!a.almacen.length){ out.push('el anexo ' + nom + ' no tiene páginas en el archivo: vuelve a subirlo o quítalo'); return; }
      const ns = a.almacen.map(r => r.n).sort((x, y) => x - y);
      for(let k = 1; k <= ns[ns.length - 1]; k++) if(!ns.includes(k)) out.push('falta la página ' + k + ' del anexo ' + nom);
      const faltan = new Set(a.faltan || []);
      (a.pages || []).forEach((p, i) => { if(!p) faltan.add(ns[i] || (i + 1)); });
      if((a.pages || []).length < a.almacen.length) for(let i = (a.pages || []).length; i < a.almacen.length; i++) faltan.add(ns[i]);
      [...faltan].sort((x, y) => x - y).forEach(n =>
        out.push('la página ' + n + ' del anexo ' + nom + ' no se ha podido leer o no es la que se subió (su huella no cuadra)'));
      return;
    }
    if(!ES_LEGADO(a)) out.push('el anexo ' + nom + ' no tiene páginas: vuelve a subirlo o quítalo');
  });
  return out;
}

/* Para lo que sale del estudio con aspecto de definitivo (PDF, correo al comprador): con un
   anexo incluido a medias se para y se dice cuál. Devuelve true si se puede seguir. */
function anexosListos(accion){
  const p = problemasAnexos(ANNEXES, { soloIncluidos:true });
  if(!p.length) return true;
  toastMal('No se puede ' + accion + ': ' + p.join('; ') + '.');
  return false;
}

/* Anexos que hay que pasar al archivo al guardar ESTE contrato: los viejos (páginas
   en `datos`) y los del archivo cuyas filas son de otro contrato. */
function anexosAMigrar(lista, contratoId){
  return (lista || []).filter(a => !a.auto && Array.isArray(a.pages) && a.pages.length && a.pages.every(Boolean)
    && (!ES_ALMACEN(a) || a.contrato !== contratoId));
}
/* Sustituye cada anexo migrado por su versión del archivo (id nuevo). Los que no
   llegaron se quedan EXACTAMENTE como estaban: no se quita nada si una subida falla. */
function aplicaMigracion(lista, hechos, contratoId){
  return (lista || []).map(a => {
    const h = hechos && hechos[a.id];
    if(!h) return a;
    return { id:h.id, title:a.title, on:a.on, pages:a.pages, almacen:h.filas, contrato:contratoId, estado:'ok', faltan:[] };
  });
}

/* ── bytes ↔ data URL (sin FileReader: también corre en la prueba de node) ── */
function dataUrlABytes(u){
  const s = String(u || ''); const bin = atob(s.slice(s.indexOf(',') + 1));
  const out = new Uint8Array(bin.length); for(let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function bytesADataUrl(b){
  let bin = ''; for(let i = 0; i < b.length; i += 32768) bin += String.fromCharCode.apply(null, b.subarray(i, i + 32768));
  return 'data:image/jpeg;base64,' + btoa(bin);
}

/* Sube las páginas de UN anexo por la edge `ficheros` (clase anexo_contrato):
   ruta del servidor → subida por URL firmada → registro. El sha lo calcula el
   servidor leyendo lo subido; aquí se compara con el de las páginas que se tienen
   en memoria, y si no cuadra se para con la página. Devuelve las filas. Lanza un
   Error con `.pagina` si algo falla (lo ya subido lo recoge el barrido). */
async function subePaginasAnexo(contratoId, anexoId, pages, alAvanzar){
  if(typeof window.lwFichero !== 'function') throw new Error('no ha cargado la conexión con el archivo: recarga la página');
  const filas = new Array(pages.length);
  let hechas = 0, siguiente = 0, fallo = null;
  const una = async i => {
    const n = i + 1;
    try{
      const bytes = dataUrlABytes(pages[i]);
      if(bytes.length > PAGINA_MAX_BYTES) throw new Error('pesa más de ' + mbAnexo(PAGINA_MAX_BYTES));
      const sha = await sha256hex(bytes);
      const u = await window.lwFichero(sb, 'anexo_contrato', 'subida_url', { contrato_id:contratoId, n });
      const up = await sb.storage.from(u.bucket).uploadToSignedUrl(u.path, u.token,
        new Blob([bytes], { type:'image/jpeg' }), { contentType:'image/jpeg' });
      if(up.error) throw up.error;
      const r = await window.lwFichero(sb, 'anexo_contrato', 'registra', { contrato_id:contratoId, anexo_id:anexoId, n, path:u.path });
      if(r.sha256 !== sha) throw new Error('lo que ha llegado al archivo no es la página que se subió');
      filas[i] = { n, path:u.path, sha256:r.sha256, bytes:r.bytes };
      hechas++; if(alAvanzar) alAvanzar(hechas, pages.length);
    }catch(e){ if(!fallo) fallo = Object.assign(new Error((e && e.message) || 'error'), { pagina:n }); }
  };
  // tres a la vez: 28 páginas en serie son ~30 s; más en paralelo no gana y satura el móvil
  const hilo = async () => { while(!fallo && siguiente < pages.length) await una(siguiente++); };
  await Promise.all([hilo(), hilo(), hilo()]);
  if(fallo) throw fallo;
  return filas;
}

/* Al abrir un contrato: filas de la tabla (RLS) → URLs firmadas de 300 s → bytes →
   sha comparado con la fila → data URL en `pages`. Las URLs no se guardan en ningún
   sitio. Carrera: si mientras tanto se abre otro contrato, lo bajado se tira.
   «No he podido mirar» (estado 'error') y «falta una página» ('falta') se pintan
   distinto: una consulta caída no puede parecer un anexo sin páginas. */
/* La carga en curso, para quien tiene que esperarla antes de sacar el documento (el
   «Descargar borrador» de la v4 imprime nada más abrir: code-review, 27-sep). */
let CARGA_ANEXOS = Promise.resolve();
/* Texto de la subida en curso: mientras hay una, el panel no ofrece otra (se repinta
   entero y un input vivo dejaría arrancar una segunda en paralelo; code-review, 27-sep). */
let SUBIDA_ANEXO = '';
async function cargaAnexosAlmacen(contratoId){
  const actual = () => (typeof SAVED_CONTRACT !== 'undefined' && SAVED_CONTRACT && SAVED_CONTRACT.id) === contratoId;
  const pendientes = ANNEXES.filter(a => ES_ALMACEN(a) && a.estado === 'cargando');
  if(!pendientes.length) return;
  const marca = (estado, error) => { pendientes.forEach(a => { a.estado = estado; a.error = error; }); };
  let filas;
  try{
    const { data, error } = await sb.from('contrato_anexo_paginas').select('anexo_id, n, path, sha256, bytes')
      .eq('contrato_id', contratoId).order('anexo_id').order('n');
    if(error) throw error;
    filas = data || [];
  }catch(e){
    if(!actual()) return;
    marca('error', 'no se ha podido consultar el archivo: ' + ((e && e.message) || 'error'));
    rebuildAnnex(); render(); return;
  }
  if(!actual()) return;
  for(const a of pendientes){
    a.almacen = filas.filter(f => f.anexo_id === a.id).map(f => ({ n:f.n, path:f.path, sha256:f.sha256, bytes:f.bytes }));
    a.contrato = contratoId; a.pages = []; a.faltan = [];
    if(!a.almacen.length){ a.estado = 'falta'; continue; }
    let urls = [];
    try{
      const { data, error } = await sb.storage.from(BUCKET_ANEXOS).createSignedUrls(a.almacen.map(f => f.path), 300);
      if(error) throw error;
      urls = data || [];
    }catch(e){
      if(!actual()) return;
      a.estado = 'error'; a.error = 'no se ha podido pedir el acceso a sus páginas'; continue;
    }
    for(let i = 0; i < a.almacen.length; i++){
      const f = a.almacen[i];
      const u = (urls.find(x => x && x.path === f.path) || urls[i] || {}).signedUrl;
      let img = null;
      try{
        if(!u) throw new Error('sin URL');
        const r = await fetch(u);
        if(!r.ok) throw new Error('HTTP ' + r.status);
        const b = new Uint8Array(await r.arrayBuffer());
        if(await sha256hex(b) === f.sha256) img = bytesADataUrl(b);
      }catch(_){ img = null; /* MUDO A PROPOSITO: la página queda en null y `faltan` la nombra en el panel y al guardar/firmar */ }
      if(!actual()) return;
      a.pages.push(img);
      if(!img) a.faltan.push(f.n);
    }
    a.estado = a.faltan.length ? 'falta' : 'ok';
  }
  if(!actual()) return;
  rebuildAnnex(); render();
}

/* CUÁNTO PUEDEN PESAR LOS ANEXOS QUE AÚN VIAJAN EN `datos` — 27-sep-2026, medido en producción.
   (Desde LAW-78 solo los VIEJOS: los del archivo no pesan en `datos`.)
   ═══════════════════════════════════════════════════════════════════════════
   Los manuales viajan CON sus páginas (JPEG en base64) dentro de `datos`, y
   `contrato_guarda` tiene 8 s (statement_timeout del rol `authenticated`):
     · 0,6 MB de cuerpo ...... se guardó en 1,2 s (el mayor que pasó, 26/27-sep)
     · 6,5 MB de cuerpo ...... cortado DOS veces a los 10-11 s (PostgREST 57014,
                               «canceling statement due to statement timeout»,
                               27-sep 11:16 y 11:17 UTC). Nadie supo por qué.
   El tope de 4 MB NO está medido: es la interpolación lineal de esos dos puntos
   (~1,7 s/MB → 8 s ≈ 4,5 MB) con algo de margen. Si el servidor cambia (páginas
   fuera de `datos`, a Storage), esto se revisa con otra medida, no a ojo.
   Referencia de lo que ocupa: 10 páginas de plano ≈ 2,9 MB; el Anexo Maestro de
   Dali Sirap entero serían 6,9 MB — el automático no viaja en `datos`, por eso
   no cuenta aquí.
   DESDE LAW-78 (27-sep-2026, tarde) lo usa solo guardarContrato (app.html), para los
   anexos VIEJOS que no han podido pasar al archivo en ese guardado: los nuevos van a
   Storage y ya no pesan en `datos`, así que la subida no tiene este tope (tiene el de
   memoria, TOPE_MEMORIA_BYTES). Medido ese día con el rol real y ROLLBACK: guardar
   RP00180 sin páginas (5,2 MB en la fila) tardó 402 ms — el peso que corta es el del
   CUERPO que se manda, no el de la fila vieja que se lee. */
const TOPE_DATOS_BYTES = 4 * 1024 * 1024;
const mbAnexo = n => (n / 1048576).toLocaleString('es-ES', { maximumFractionDigits:1, minimumFractionDigits:1 }) + ' MB';
const pesoPaginas = a => (a.pages || []).reduce((t, p) => t + String(p || '').length, 0);
/* Lo que ocupan en memoria los manuales. */
function pesoAnexosManuales(){ return ANNEXES.filter(a => !a.auto).reduce((t, a) => t + pesoPaginas(a), 0); }
/* Lo que ocupan en memoria TODOS, automáticos incluidos (tope del navegador, TOPE_MEMORIA_BYTES).
   Desde el 27-sep-2026 los automáticos pueden ser varios, y un dosier comercial convertido
   pesa como diez planos: dejarlos fuera de la cuenta era dar por libre memoria que no lo está. */
function pesoAnexosEnMemoria(){ return ANNEXES.reduce((t, a) => t + pesoPaginas(a), 0); }

/* CUÁNTO PESA EL DOCUMENTO QUE SALE — 27-sep-2026. Con varios documentos automáticos
   (un dosier son decenas de páginas de render) el contrato puede pasar umbrales que
   antes no se tocaban. Verificados en el código ese día:
     · 15 MB: por encima, el PDF firmado se manda por ENLACE y no adjunto
       (firma-submit MAX_ADJUNTO; app.html COPIA_MAX_ADJUNTO, la copia por correo).
     · 20 MB la tanda (PDF × destinatarios) de firma-submit: también pasa a enlace.
   No bloquea nada (el enlace funciona): se AVISA en el panel, para que quien envía
   sepa que el comprador recibirá un enlace y no el PDF. El peso del PDF se estima
   con los bytes de las imágenes (base64 × 3/4), que son casi todo el documento. */
const UMBRAL_ENLACE_BYTES = 15 * 1024 * 1024;
function pesoIncluidosEstimado(){
  return Math.round(ANNEXES.filter(a => a.on).reduce((t, a) => t + pesoPaginas(a), 0) * 0.75);
}
function avisoPesoAnexos(){
  const b = pesoIncluidosEstimado();
  if(b <= UMBRAL_ENLACE_BYTES) return '';
  return 'Los anexos incluidos suman unos ' + mbAnexo(b) + ': el PDF pasará de ' + mbAnexo(UMBRAL_ENLACE_BYTES)
    + ' y al comprador le llegará por enlace, no adjunto. Si no hacen falta todos, apaga alguno.';
}
/* Lo que pesan en `datos`: solo los VIEJOS (los del archivo viajan como ficha). */
function pesoAnexosEnDatos(){ return ANNEXES.filter(ES_LEGADO).reduce((t, a) => t + pesoPaginas(a), 0); }

/* El borrador local (localStorage) guarda SOLO las fichas de los anexos automáticos
   (LAW-78): nunca bytes ni URLs. Un anexo subido a mano es del contrato guardado —sin
   contrato no hay dónde subirlo— y al reabrirlo sale de la base, no de aquí. Antes el
   borrador llevaba las páginas en base64: no cabían (20 páginas = 5,1 MB) y el borrador
   ANTERIOR resucitaba otra lista de anexos al recargar. La clave vieja con páginas la
   limpia loadAnnexes() (documento_diseno.js) al cargar. */
function saveAnnexes(){
  try{ localStorage.setItem('lawang_contract_annexes', JSON.stringify(ANNEXES.filter(a => a.auto).map(a => fichaDatos(a)))); }
  catch(_){
    try{ localStorage.removeItem('lawang_contract_annexes'); }catch(_e){ /* MUDO A PROPOSITO: sin localStorage no hay borrador viejo que pueda resucitar */ }
  }
}
function escAttr(s){ return String(s||'').replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;'); }

/* Huella del PDF del anexo (el aviso «el pack ha cambiado desde que se guardó»).
   VIVE AQUÍ, y no en app.html, desde el 27-sep-2026: estaba en app.html junto a
   la firma remota, y cuando la firma pasó al servidor (c1db7ddc, 26-sep, LAW-336
   pieza 5) se borró con ella. Este fichero era ya su único llamador: cada anexo
   automático moría en un ReferenceError que el catch convertía en «no tiene Anexo
   Maestro» — todos los modelos, todos los techos, un día entero. Quien la necesita
   la define; no se hereda de otra pantalla. Lo vigila documento_anexos.test.js. */
async function sha256hex(s){
  const b = await crypto.subtle.digest('SHA-256', typeof s === 'string' ? new TextEncoder().encode(s) : s);
  return [...new Uint8Array(b)].map(x => x.toString(16).padStart(2, '0')).join('');
}

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

/* `topeBytes` (27-sep-2026): con un tope, la conversión se corta en cuanto lo
   acumulado lo pasa, en vez de convertir el PDF entero para descubrir al final que
   no se puede guardar — y sin acumular páginas hasta tumbar la pestaña (un PDF
   escaneado de 118 MB la cerró en la medición). El error dice cuánto llevaba. */
async function pdfToImages(file, topeBytes){
  // acepta File/Blob o un ArrayBuffer ya leído (el anexo automático necesita el
  // buffer aparte para calcular su hash antes de que pdf.js se lo quede)
  const buf = file instanceof ArrayBuffer ? file : await file.arrayBuffer();
  const pdf = await pdfjsLib.getDocument({data:buf}).promise;
  const out=[];
  let peso = 0;
  try{
  for(let i=1;i<=pdf.numPages;i++){
    const page = await pdf.getPage(i);
    const base = page.getViewport({scale:1});
    let cv = await pintarPagina(page, Math.min(1400/base.width, 2));
    // Tope 4×: una página diminuta no se convierte en un lienzo gigante.
    if(fraccionClara(cv) >= CLARO_PLANO) cv = await pintarPagina(page, Math.min(ANCHO_PLANO/base.width, 4));
    const img = cv.toDataURL('image/jpeg', CALIDAD_ANEXO);
    cv.width = cv.height = 0;               // suelta la memoria del lienzo ya
    page.cleanup();
    peso += img.length;
    out.push(img);
    if(topeBytes && peso > topeBytes)
      throw Object.assign(new Error('pasa del tope'), { tope:{ paginas:i, total:pdf.numPages, bytes:peso } });
  }
  }finally{ pdf.destroy(); }   // también si una página revienta: la memoria de pdf.js se suelta siempre
  return out;
}
function compressImage(file){
  return new Promise((res,rej)=>{ const img=new Image(); const url=URL.createObjectURL(file);
    img.onload=()=>{ URL.revokeObjectURL(url); const s=Math.min(1400/img.naturalWidth,1);
      const cv=document.createElement('canvas'); cv.width=Math.round(img.naturalWidth*s); cv.height=Math.round(img.naturalHeight*s);
      cv.getContext('2d').drawImage(img,0,0,cv.width,cv.height); res([cv.toDataURL('image/jpeg', CALIDAD_ANEXO)]); };
    img.onerror=rej; img.src=url; });
}
async function fileToAnnexPages(file, topeBytes){
  if(file.type==='application/pdf' || /\.pdf$/i.test(file.name)){
    if(!window.pdfjsLib) throw new Error('pdf.js no cargó'); return await pdfToImages(file, topeBytes);
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
let AUTO_AVISO = null; // {clave, mal, texto} del último intento sin anexo: se queda PINTADO en el panel.
                      // Un toast se va en segundos; el panel es lo que se mira antes de enviar.
/* DE DÓNDE SALE EL PDF DEL ANEXO — 8-sep-2026, encargo del owner. (HISTORIA: desde el
   27-sep-2026 ya no se elige por tipo `plano` sino por la casilla `en_contrato`; ver
   «VARIOS DOCUMENTOS, ELEGIDOS POR UNA CASILLA» más abajo.)
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
/* TRES SALIDAS DISTINTAS, Y SE TIENEN QUE VER DISTINTAS — 27-sep-2026.
   Hasta hoy todo fallo acababa en el mismo «no tiene Anexo Maestro»: con el plano
   de Dali Sirap en Modelos, legible por la comercial, el contrato decía que no
   existía (el fallo era un ReferenceError, ver sha256hex arriba). Una alarma que
   no ha podido mirar no puede decir «no hay nada». Por eso aquí se lanza un
   error MARCADO y quien llama (syncAutoAnnex) elige el mensaje:
     · `sinPlano`   — se miró y ese modelo/techo no tiene plano en Modelos (neutro);
     · `plano`      — lo hay, con su nombre, pero no se ha podido bajar (rojo);
     · ni lo uno ni lo otro — no se ha podido ni mirar (catálogo o consulta, rojo).
   Aquí no se enseña ningún toast: antes este fichero sacaba el suyo y el de
   syncAutoAnnex lo tapaba medio segundo después con el mensaje contrario.

   SIN RED DEL REPO — 25-sep-2026, decisión del owner: «el Anexo Maestro es el
   ÚNICO documento que debe cargarse en el contrato de Construcción». Sin plano en
   Modelos ya no se cae a `assets/anexos/<Tipología>.pdf`: no hay anexo automático
   y se avisa (Legal, revisión previa #86). */
function errorAnexo(msg, extra){ return Object.assign(new Error(msg), extra || {}); }

/* VARIOS DOCUMENTOS, ELEGIDOS POR UNA CASILLA — 27-sep-2026, owner («necesito poder
   marcar si ese documento se carga automáticamente en el contrato o no»).
   ═══════════════════════════════════════════════════════════════════════════
   Hasta hoy entraba UN documento, el de tipo `plano` del techo elegido (o el
   genérico si no había). Desde hoy entran TODOS los documentos del modelo con la
   casilla `en_contrato`, en su `orden`, cada uno si su techo es el del contrato o
   no tiene techo. La regla vive en docs_contrato.js (window.lwDocsContrato) y la
   comparte la ficha del modelo, que enseña por techo lo que se va a adjuntar: una
   sola regla, para que lo que se ve allí sea lo que se adjunta aquí.
   Nunca se mira el tipo: un dosier marcado entra, un plano sin marcar no.

   Cada documento es un anexo automático con id `axauto-<id del documento>`, su
   `sha` y su aviso «ha cambiado desde que se guardó». El id por documento es lo
   que permite cruzar `on` y `sha` con el documento correcto al reabrir: con un
   único `axauto` para varios se cruzarían entre sí.

   COMPATIBILIDAD: los contratos de antes guardan UNA ficha `axauto` sin id de
   documento. Era el plano del techo (o el genérico), así que se traduce a la ficha
   de ese mismo plano, conservando `on` (si estaba apagado sigue apagado) y `sha`.
   Lo firmado no se toca: es el documento emitido, no esta lista. */
const idAuto = d => 'axauto-' + d.id;
function fichaGuardadaDe(guardados, d, docs, techo){
  const propia = guardados.find(a => a.id === idAuto(d));
  if(propia) return propia;
  const vieja = guardados.find(a => a.id === 'axauto');
  if(!vieja || d.tipo !== 'plano') return null;
  const planos = docs.filter(x => x.tipo === 'plano');
  const equivalente = (techo && planos.find(x => x.techo_clave === techo)) || planos.find(x => !x.techo_clave) || null;
  return equivalente && equivalente.id === d.id ? vieja : null;
}
/* Título del anexo en la portada del contrato. El plano conserva el de siempre
   (los contratos que ya lo llevan no cambian de texto); el nombre del techo solo
   va si el documento ES de ese techo. */
/* LETRA Y TÍTULO (owner, 28-sep-2026): cada documento sale como «Apéndice <letra de su
   tipo>» con su título en los tres idiomas (docs_contrato.js → apendices()). El nombre
   del modelo y, si el documento es de un techo, el del techo, van detrás. `title` es la
   versión en español, para el panel de Anexos y el bot; el documento imprime `nombres`. */
function nombresAuto(ap, tip){
  const d = ap.doc;
  const nomTecho = d.techo_clave && typeof TECHO_ELEGIDO !== 'undefined' && TECHO_ELEGIDO && TECHO_ELEGIDO.nombre ? ' · ' + TECHO_ELEGIDO.nombre : '';
  const cola = ' · ' + tip + nomTecho;
  return { es: ap.titulo.es + cola, en: ap.titulo.en + cola, id: ap.titulo.id + cola };
}

/* Qué documentos entran (sin bajarlos). TRES salidas, y se tienen que ver distintas
   (27-sep-2026): una alarma que no ha podido mirar no puede decir «no hay nada».
     · lista vacía ........ se miró y no hay nada marcado para este techo (neutro);
     · error `sinPlano` ... el modelo no está en el catálogo (neutro);
     · otro error ......... no se ha podido ni mirar (rojo). */
async function documentosDelContrato(tip, techo){
  if(typeof sb === 'undefined' || !sb) throw errorAnexo('sin conexión con la base');
  if(!window.lwDocsContrato) throw errorAnexo('no ha cargado la regla de documentos del contrato (docs_contrato.js)');
  // Sin catálogo no se sabe qué modelo es: eso es «no he podido mirar», no «no tiene».
  if(typeof CATALOGO_MODELOS === 'undefined' || !CATALOGO_MODELOS) throw errorAnexo('el catálogo de Modelos no ha cargado');
  const ficha = (typeof fichaDelModelo === 'function') ? fichaDelModelo(tip) : null;
  if(!ficha) throw errorAnexo(tip + ' no está en el catálogo de Modelos', { sinPlano:true });
  const { data, error } = await sb.from('modelo_documentos')
    .select('id, path, nombre, tipo, techo_clave, subido_en, en_contrato, orden').eq('modelo_id', ficha.id).eq('en_contrato', true);
  if(error) throw errorAnexo('no se han podido consultar los documentos de Modelos: ' + (error.message || 'error'));
  // La regla se aplica aquí también (además del filtro de la consulta): es la misma que enseña la ficha.
  // apendices(): los que entran, ya con su letra (A, B, D…) y su rótulo trilingüe, ordenados por letra
  return window.lwDocsContrato.apendices((data || []).filter(d => d && d.path), techo);
}
async function bajaDocumento(d){
  const { data:url, error:eUrl } = await sb.storage.from('modelos').createSignedUrl(d.path, 3600);
  if(eUrl || !url || !url.signedUrl) throw (eUrl || new Error('sin URL firmada'));
  const r = await fetch(url.signedUrl);
  if(!r.ok) throw new Error('HTTP ' + r.status);
  return await r.arrayBuffer();
}

/* Anexos subidos a mano (27-sep-2026, owner: «debo poder subir el PDF que quiera,
   como antes»). Del 25-sep al 27-sep, en Construcción el Anexo Maestro era el ÚNICO
   anexo: se ocultaba la subida y se retiraban los manuales de los borradores. El owner
   lo revierte: en cualquier contrato se suben los PDF o imágenes que se quiera, y los
   documentos marcados del modelo (automáticos, desde Modelos) van además, no en su lugar. */

/* Techo que decide el anexo: el elegido en el contrato (techo_extras.js). El
   «sintético» —modelo sin variantes, la única opción calculada del precio
   base— no es un techo de modelo_techos y no tiene documentos propios. */
function techoDelAnexo(){
  const t = (typeof TECHO_ELEGIDO !== 'undefined') ? TECHO_ELEGIDO : null;
  return (t && !t.sintetico && t.clave) ? t.clave : '';
}

const SIN_MARCADOS = 'Este modelo no tiene documentos marcados para el contrato (con este techo): el contrato irá sin anexo.';

async function syncAutoAnnex(){
  const el = document.querySelector('[name="tipologia_construccion"]');
  const tip = el ? el.value.trim() : '';       // sin campo (otra plantilla) → se quitan los automáticos
  /* Mientras llegan las opciones de techo del modelo no se decide nada: con el
     techo aún vacío se bajarían y convertirían los documentos genéricos para
     tirarlos un segundo después. cargarTechosYExtras() vuelve a llamar aquí. */
  if(tip && typeof TECHO_CARGANDO !== 'undefined' && TECHO_CARGANDO && !techoDelAnexo()) return;
  const techo = tip ? techoDelAnexo() : '';
  const clave = tip ? tip + '§' + techo : '';
  if(clave === AUTO_ANX) return;
  AUTO_ANX = clave;
  // Las fichas guardadas (sin páginas) traen dos cosas que NO se pueden re-derivar:
  // si el agente apagó "Incluir en el contrato", y el hash del PDF que se anexó de
  // verdad. Sin esto, un anexo excluido a propósito volvía a entrar solo al reabrir,
  // al derivar un contrato hijo o al rearrancar la cadena de firma.
  const guardados = ANNEXES.filter(a => a.auto === tip);
  ANNEXES = ANNEXES.filter(a => !a.auto);
  if(!tip){ AUTO_CARGA=''; AUTO_AVISO=null; saveAnnexes(); rebuildAnnex(); render(); return; }
  AUTO_CARGA = tip; AUTO_AVISO = null; rebuildAnnex();
  const conTecho = techo ? ' con el techo elegido' : '';
  let docs = null;
  try{
    docs = await documentosDelContrato(tip, techo);
  }catch(e){
    if(AUTO_ANX === clave){
      const motivo = (e && e.message) || 'error';
      if(e && e.sinPlano){
        AUTO_AVISO = { clave, mal:false, texto: tip + ' no está en el catálogo de Modelos: el contrato irá sin anexo.' };
        toast(AUTO_AVISO.texto);
      }else{
        /* Fallo, no ausencia: las fichas guardadas (sin páginas, no se imprimen) se
           conservan, para que guardar ahora no borre del contrato su `on` ni el `sha`
           de lo que se anexó — lo único que no se puede re-derivar al reintentar. */
        ANNEXES = [...guardados.map(sinPaginas), ...ANNEXES.filter(a=>!a.auto)];
        AUTO_AVISO = { clave, mal:true, texto: 'No se ha podido comprobar qué documentos de ' + tip + ' van en el contrato (' + motivo + '). Recarga la página antes de seguir.' };
        toastMal(AUTO_AVISO.texto);
      }
    }
  }
  if(docs && AUTO_ANX === clave && !docs.length){
    AUTO_AVISO = { clave, mal:false, texto: SIN_MARCADOS };
    toast(tip + ': ' + SIN_MARCADOS.charAt(0).toLowerCase() + SIN_MARCADOS.slice(1)
      + ' Si debe llevarlo, pídeselo a administración (Modelos → Documentos → Editar, casilla «Se incluye automáticamente en el contrato»'
      + (techo ? ', con su techo' : '') + ').');
  }
  if(docs && docs.length){
    const hechos = [], fallos = [], cambiados = [];
    let paginas = 0;
    const soloDocs = docs.map(ap => ap.doc);
    for(const ap of docs){
      const d = ap.doc;
      const g = fichaGuardadaDe(guardados, d, soloDocs, techo);
      const nombre = d.nombre || d.path;
      try{
        let buf;
        try{ buf = await bajaDocumento(d); }
        catch(e){ throw errorAnexo('no se ha podido descargar: ' + ((e && e.message) || 'error')); }
        let sha, pages;
        try{
          sha = await sha256hex(buf);               // antes de pdf.js: se queda el buffer
          /* Tope de MEMORIA del navegador, contando los manuales y los automáticos ya
             convertidos: un documento comercial grande pesa 10-17 MB en PDF (medido el 27-sep-2026 sobre
             los de producción; la columna tamano_bytes de 5 dosieres estaba desfasada y decía 17-50 MB). */
          const libre = TOPE_MEMORIA_BYTES - pesoAnexosManuales() - hechos.reduce((t, a) => t + pesoPaginas(a), 0);
          pages = await pdfToImages(buf, Math.max(libre, 1));
          if(!pages.length) throw new Error('el PDF no tiene páginas');
        }catch(e){
          if(e && e.tope) throw errorAnexo('es demasiado grande para convertirlo en este navegador (a la página ' + e.tope.paginas + ' de ' + e.tope.total
            + ' ya ocupaba ' + mbAnexo(e.tope.bytes) + '): desmárcalo en Modelos o súbelo con menos páginas');
          throw errorAnexo('no se ha podido convertir a páginas: ' + ((e && e.message) || 'error'));
        }
        if(AUTO_ANX !== clave) return;             // cambió de tipología o de techo mientras se convertía
        const nombres = nombresAuto(ap, tip);
        const a = { id:idAuto(d), auto:tip, techo, sha, letra:ap.letra, tipo:d.tipo, nombres,
                    title:'Apéndice ' + ap.letra + ' — ' + nombres.es, pages, on: g ? g.on !== false : true };
        hechos.push(a); paginas += pages.length;
        // El PDF del servidor es mutable: si cambió desde que se guardó el contrato, el anexo
        // que se ve ya NO es el que se firmó. Se avisa, no se oculta. Si lo que cambió es el
        // TECHO ELEGIDO, el documento distinto es lo esperado. `techo` ausente = ficha de
        // antes del 23-sep: se avisa.
        const cambioDeTecho = g && g.techo !== undefined && g.techo !== techo;
        if(g && g.sha && g.sha !== sha && !cambioDeTecho) cambiados.push(a.title);
      }catch(e){
        if(AUTO_ANX !== clave) return;
        fallos.push('Apéndice ' + ap.letra + ' «' + nombre + '» ' + ((e && e.message) || 'error'));
        // su ficha guardada sobrevive sin páginas (no se imprime, no se pierde su `on` ni su `sha`)
        if(g) hechos.push({ ...sinPaginas(g), id:idAuto(d) });
      }
    }
    if(AUTO_ANX !== clave) return;
    ANNEXES = [...hechos, ...ANNEXES.filter(a=>!a.auto)];
    if(fallos.length){
      AUTO_AVISO = { clave, mal:true, faltan: fallos.slice(), texto: (fallos.length === 1 ? 'Un documento marcado para el contrato no se ha podido adjuntar: ' : fallos.length + ' documentos marcados para el contrato no se han podido adjuntar: ')
        + fallos.join('; ') + '. Recarga la página; si sigue, avisa.' };
      toastMal(AUTO_AVISO.texto);
    }else if(cambiados.length){
      toastMal('OJO: ' + (cambiados.length === 1 ? '«' + cambiados[0] + '» ha cambiado' : cambiados.length + ' documentos del contrato han cambiado ('
        + cambiados.map(t => '«' + t + '»').join(', ') + ')') + ' desde que se guardó este contrato');
    }else toast(hechos.length === 1 ? 'Anexo de ' + tip + ' adjuntado (' + paginas + ' pág.)'
                                    : 'Anexos de ' + tip + ' adjuntados: ' + hechos.length + ' documentos (' + paginas + ' pág.)');
  }
  if(AUTO_CARGA === tip && AUTO_ANX === clave) AUTO_CARGA = '';
  saveAnnexes(); rebuildAnnex(); render();
}

/* ¿Hay un contrato guardado y editable al que subir páginas? (sin fila no hay dónde) */
function contratoParaAnexos(){
  const id = (typeof SAVED_CONTRACT !== 'undefined' && SAVED_CONTRACT && SAVED_CONTRACT.id) || null;
  const bloqueado = (typeof LOCKED !== 'undefined' && LOCKED)
    || (typeof EN_FIRMA !== 'undefined' && EN_FIRMA && (EN_FIRMA.vivas || EN_FIRMA.firmadas));
  return { id, bloqueado: !!bloqueado };
}

/* Qué se ve de un anexo manual al lado de su título: páginas, y su estado si no está bien.
   «Cargando», «falta» y «no se ha podido comprobar» son cosas distintas y se leen distintas. */
function estadoAnexoManual(a){
  const n = numPaginas(a);
  if(a.estado === 'cargando') return { txt:'cargando…', mal:false };
  if(a.estado === 'subiendo') return { txt:'subiendo…', mal:false };
  if(a.estado === 'error') return { txt:'no se ha podido comprobar' + (a.error ? ': ' + a.error : ''), mal:true };
  if(ES_ALMACEN(a)){
    const p = problemasAnexos([a]);
    return p.length ? { txt:n + ' pág. · ' + p.length + (p.length === 1 ? ' problema' : ' problemas') + ': ' + p[0], mal:true }
                    : { txt:n + ' pág.', mal:false };
  }
  if(ES_LEGADO(a)) return { txt:n + ' pág. · ' + mbAnexo(pesoPaginas(a)) + ' · pasa al archivo al guardar', mal:false };
  return { txt:'sin páginas: vuelve a subirlo o quítalo', mal:true };
}

function buildAnnexPanel(){
  const cargando = AUTO_CARGA
    ? `<div class="dz" style="color:var(--muted);font-size:12.5px">Preparando los documentos de ${escAttr(AUTO_CARGA)} para el contrato…</div>` : '';
  // `clave`: un aviso es de ESTE contrato y tipología/techo; al abrir otro (app.html pone
  // AUTO_ANX a cero) no se arrastra.
  const aviso = (!AUTO_CARGA && AUTO_AVISO && AUTO_AVISO.clave === AUTO_ANX)
    ? `<div class="dz anx-aviso" role="status" style="font-size:12.5px;color:${AUTO_AVISO.mal ? 'var(--be)' : 'var(--muted)'}">${escAttr(AUTO_AVISO.texto)}</div>` : '';
  // El automático sin páginas no se pinta: es su ficha guardada, que aún no ha
  // rehidratado (si no, parpadea un "0 pág." al abrir un contrato). Los manuales se
  // pintan SIEMPRE (LAW-78): uno que carga, al que le falta una página o que no se ha
  // podido comprobar tiene que verse, con su estado.
  const txtPeso = AUTO_CARGA ? '' : avisoPesoAnexos();
  const peso = txtPeso ? `<div class="dz anx-aviso" role="status" style="font-size:12.5px;color:var(--be)">${escAttr(txtPeso)}</div>` : '';
  const rows = cargando + aviso + peso + ANNEXES.filter(a => !a.auto || (a.pages && a.pages.length)).map(a => {
    const id = escAttr(a.id);
    if(a.auto) return `
    <div class="dz" data-anx="${id}">
      <div class="dz-row">
        <span style="flex:1;font-size:13px">${escAttr(a.title)}</span>
        <span style="font-size:11px;color:var(--muted);white-space:nowrap">${a.pages.length} pág. · automático</span>
      </div>
      <div class="dz-row"><label class="switch"><input type="checkbox" data-anxon="${id}" ${a.on?'checked':''}><span class="slider"></span></label>
        <span>Incluir en el contrato</span></div>
    </div>`;
    const st = estadoAnexoManual(a);
    return `
    <div class="dz" data-anx="${id}">
      <div class="dz-row">
        <input class="anx-title" data-anxtitle="${id}" value="${escAttr(a.title)}" aria-label="Título del anexo" style="flex:1;font:inherit;font-size:13px;padding:7px 10px;border:1px solid var(--line);border-radius:8px">
        <span style="font-size:11px;color:${st.mal ? 'var(--be)' : 'var(--muted)'};max-width:45%">${escAttr(st.txt)}</span>
        <button type="button" class="link-btn" data-anxdel="${id}" ${a.estado === 'subiendo' ? 'disabled' : ''}>Quitar</button>
      </div>
      <div class="dz-row"><label class="switch"><input type="checkbox" data-anxon="${id}" ${a.on?'checked':''}><span class="slider"></span></label>
        <span>Incluir en el contrato</span></div>
    </div>`;
  }).join('') || `<div class="dz" style="color:var(--muted);font-size:12.5px">Aún no hay anexos. Sube un PDF o imágenes para definirlos.</div>`;
  const c = contratoParaAnexos();
  const subir = SUBIDA_ANEXO
    ? `<div class="dz" style="color:var(--muted);font-size:12.5px" id="anxUpLabel" role="status">${escAttr(SUBIDA_ANEXO)}</div>`
    : !c.id
    ? `<div class="dz" style="color:var(--muted);font-size:12.5px">Guarda el contrato para poder añadirle anexos: las páginas se guardan con él.</div>`
    : c.bloqueado ? ''
    : `<div class="dz"><label class="up" id="anxUpLabel">+ Añadir anexo (PDF o imágenes)<input type="file" id="anxFile" accept="application/pdf,image/*" multiple></label></div>`;
  // Seguridad (revisión previa LAW-78): un pasaporte subido aquí acaba impreso en el
  // contrato y en cada copia que se manda. La identidad va a la ficha del comprador.
  const kyc = `<div class="dz" style="color:var(--muted);font-size:12px">Los documentos de identidad (pasaporte, KTP, NPWP) van a la ficha del comprador (KYC), no aquí.</div>`;
  return `<section class="section design collapsed" id="annexPanel">
    <header data-acc><span class="num">📎</span><h2>Anexos</h2><span class="chev">▾</span></header>
    <div class="body">
      ${rows}
      ${subir}
      ${kyc}
    </div>
  </section>`;
}
function wireAnnexPanel(){
  const p=$('#annexPanel'); if(!p) return;
  const inp=$('#anxFile');
  if(inp) inp.addEventListener('change', async e=>{
    const files=[...e.target.files]; if(!files.length) return;
    const c = contratoParaAnexos();
    if(!c.id){ toastMal('Guarda el contrato antes de añadirle anexos: las páginas se guardan con él.'); return; }
    if(c.bloqueado){ toastMal('Este contrato está enviado a firma o bloqueado: no admite anexos nuevos.'); return; }
    // El panel se repinta durante la subida: el progreso se escribe en SUBIDA_ANEXO y en el
    // #anxUpLabel que haya EN ESE MOMENTO, nunca en una referencia vieja que ya no está en la página.
    const avisa = t => { SUBIDA_ANEXO = t; const l = $('#anxUpLabel'); if(l) l.textContent = t; };
    avisa('Procesando…'); rebuildAnnex();
    /* Cada fichero es un anexo: se convierte a páginas (tope de MEMORIA del navegador,
       no del servidor), se sube página a página por la edge y solo entra en la lista
       cuando TODAS han llegado y su huella cuadra. Uno que falla no entra, y se dice
       en qué página; lo que llegó a subirse lo recoge el barrido. */
    for(const f of files){
      const libre = TOPE_MEMORIA_BYTES - pesoAnexosEnMemoria();
      let nuevo = null;
      try{
        if(libre <= 0) throw Object.assign(new Error('sin sitio'), { tope:{ paginas:0, total:0, bytes:0 } });
        const pages = await fileToAnnexPages(f, libre);
        if(pages.length > MAX_PAGINAS_FICHERO) throw new Error('tiene ' + pages.length + ' páginas y el máximo por fichero son ' + MAX_PAGINAS_FICHERO);
        nuevo = { id:idAnexoNuevo(), title:f.name.replace(/\.[^.]+$/,''), pages, on:true, estado:'subiendo' };
        ANNEXES.push(nuevo); rebuildAnnex();
        avisa('Subiendo «' + nuevo.title + '»…');
        const filas = await subePaginasAnexo(c.id, nuevo.id, pages, (k, n) => avisa('Subiendo «' + nuevo.title + '»: ' + k + ' de ' + n + '…'));
        Object.assign(nuevo, { almacen:filas, contrato:c.id, estado:'ok', faltan:[] });
        toast('Anexo «' + nuevo.title + '» subido (' + filas.length + ' pág.). Guarda el contrato para que quede en él.');
      }catch(err){
        if(nuevo) ANNEXES = ANNEXES.filter(x => x !== nuevo);
        if(err && err.tope){
          const t = err.tope;
          toastMal('«' + f.name + '» es demasiado grande para convertirlo en este navegador'
            + (t.total ? ' (a la página ' + t.paginas + ' de ' + t.total + ' ya ocupaba ' + mbAnexo(t.bytes) + ')' : '')
            + '. Sube solo las páginas que hacen falta, o pártelo en varios ficheros.');
        }else if(err && err.pagina){
          toastMal('«' + f.name + '» no se ha subido: falló la página ' + err.pagina + ' (' + err.message + '). No se ha añadido; prueba otra vez.');
        }else toastMal('No se pudo procesar '+f.name+' ('+((err && err.message) || 'error')+')');
      }
    }
    SUBIDA_ANEXO = ''; saveAnnexes(); rebuildAnnex(); render();
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

/* páginas de anexos incluidos, al final del contrato (portada de anexo + imágenes de página).
   Una página que falta: en la vista previa se ve un hueco MARCADO; en el documento que se
   firma (SIGN_MODE) no puede haber hueco — se para con el anexo y la página. */
function annexHTML(){
  const on=ANNEXES.filter(a=>a.on && ((a.pages && a.pages.length) || ES_ALMACEN(a)));
  if(!on.length) return '';
  const firmando = typeof SIGN_MODE !== 'undefined' && SIGN_MODE;
  if(firmando){
    const p = problemasAnexos(ANNEXES, { soloIncluidos:true });
    if(p.length) throw new Error('No se puede generar el documento: ' + p.join('; '));
  }
  // Trilingüe, no L(): el rótulo del anexo es parte del documento y el bahasa
  // tiene que salir siempre, igual que en el resto del contrato.
  const lbl=(n)=>`<span data-lang="es">Anexo ${n}</span><span data-lang="en">Annex ${n}</span><span data-lang="id">Lampiran ${n}</span>`;
  /* Los automáticos salen con la LETRA DE APÉNDICE de su tipo y el título en los tres idiomas
     (owner, 28-sep-2026: el Art. 3 remite a «Apéndice A – Planos», «B – Especificaciones»). El título
     editable a mano no cambia la letra. Los subidos a mano siguen como «Anexo 1, 2…», numerados entre ellos. */
  const lblAp=(l)=>`<span data-lang="es">Apéndice ${escAttr(l)}</span><span data-lang="en">Appendix ${escAttr(l)}</span><span data-lang="id">Lampiran ${escAttr(l)}</span>`;
  const nomAp=(a)=>a.nombres ? `<span data-lang="es">${escAttr(a.nombres.es)}</span><span data-lang="en">${escAttr(a.nombres.en)}</span><span data-lang="id">${escAttr(a.nombres.id)}</span>` : escAttr(a.title);
  let nManual = 0;
  const hueco=(t)=>`<section class="annex-page"><div style="border:2px dashed #b3261e;color:#b3261e;padding:40px;text-align:center;font:14px sans-serif">${escAttr(t)}</div></section>`;
  let h='<div class="annexes">';
  on.forEach((a)=>{
    h+= (a.auto && a.letra)
      ? `<section class="annex-cover"><div class="annex-label">${lblAp(a.letra)}</div><div class="annex-name">${nomAp(a)}</div></section>`
      : `<section class="annex-cover"><div class="annex-label">${lbl(++nManual)}</div><div class="annex-name">${escAttr(a.title)}</div></section>`;
    if(ES_ALMACEN(a) && !(a.pages && a.pages.length)){
      h+=hueco(a.estado === 'cargando' ? 'Cargando las páginas de este anexo…'
        : 'No se han podido cargar las páginas de este anexo. Este documento no se puede enviar a firma así.');
      return;
    }
    a.pages.forEach((src,k)=>{
      const n = ES_ALMACEN(a) && a.almacen[k] ? a.almacen[k].n : k + 1;
      h+= src ? `<section class="annex-page"><img src="${src}" alt=""></section>`
              : hueco('Falta la página ' + n + ' de este anexo: no se ha podido cargar. Este documento no se puede enviar a firma así.');
    });
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
