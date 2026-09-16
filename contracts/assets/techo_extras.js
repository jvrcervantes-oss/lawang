/* Techo y extras del modelo elegido, en el Contrato de Construcción — 16-sep-2026.

   POR QUÉ EXISTE
   --------------
   Las casas de Modelos tienen variantes de techo (`modelo_techos`, precios
   COMPLETOS alternativos, no un recargo) y opcionales (`modelo_extras`), pero
   la Tipología del contrato de Construcción solo traía nombre/m²/precio base —
   nunca se podía elegir techo ni extra, ni salían impresos.

   Revisión previa (Legal + Datos + Seguridad, 16-sep) antes de escribir esto:
   · El precio de cada techo/extra llega YA resuelto por el SERVIDOR
     (`modelo_techos_opciones`/`modelo_extras_opciones`, migración
     `techos_extras_opciones_construccion`) — el tramo 2026/2027 (mismo corte
     que `modelo/lib.php`, nunca el reloj del navegador) y el delta que
     `modelos_villa` ya aplica por proyecto sobre el precio de catálogo se
     deciden ahí, nunca aquí. Este fichero solo SUMA números que ya vienen
     resueltos.
   · Se CONGELA en `datos.techo`/`datos.extras` al guardar (nunca FK viva a
     `modelo_techos`/`modelo_extras`, "El dato tiene un dueño" —
     contexto/patrones_tecnicos.md): un contrato firmado no puede cambiar de
     precio solo porque el catálogo cambie o el reloj cruce el 1-ene-2027.
   · Elegir techo pasa a mandar sobre `precio_total` (decisión del owner: "creo
     que todos los precios deben salir de modelos"), por delante de
     `syncPrecioObraVinculada` (que sigue siendo el que manda cuando el modelo
     no tiene techos definidos — contratos antiguos, sin cambio de conducta).
*/

let TECHO_ELEGIDO   = null;   // {techo_id,clave,nombre,precio,moneda,tramo} | null — CONGELADO al guardar
let EXTRAS_ELEGIDOS = [];     // [{extra_id,clave,nombre,precio,moneda}, …]     — CONGELADO al guardar
let TECHOS_OPCIONES  = [];    // catálogo YA resuelto (tramo+delta) del modelo+proyecto actual
let EXTRAS_OPCIONES  = [];
let TECHO_MODELO_HECHO = null;   // "modeloId§proyectoId" ya resuelto, para no repetir el RPC en cada tecla

/* Trae las opciones del modelo elegido. Nunca lanza (quien llama está pintando
   un formulario): sin red se queda con listas vacías, igual que
   `lwCargarCatalogoModelos`. */
async function cargarTechosYExtras(modeloId, proyectoId){
  if(!sb || !modeloId){ TECHOS_OPCIONES = []; EXTRAS_OPCIONES = []; TECHO_MODELO_HECHO = null; refreshTechoExtras(); return; }
  const firma = modeloId + '§' + (proyectoId || '');
  if(firma === TECHO_MODELO_HECHO) return;
  TECHO_MODELO_HECHO = firma;
  const [t, e] = await Promise.all([
    sb.rpc('modelo_techos_opciones', { p_modelo_id: modeloId, p_proyecto_id: proyectoId || null }),
    sb.rpc('modelo_extras_opciones', { p_modelo_id: modeloId }),
  ]);
  TECHOS_OPCIONES = t.error ? [] : (t.data || []);
  EXTRAS_OPCIONES = e.error ? [] : (e.data || []);
  refreshTechoExtras();
  syncPrecioTechoExtras();
}

/* Un techo/extra guardado que hoy ya no está entre las opciones (retirado del
   catálogo, o `disponible=false`) no se pierde ni se oculta — mismo criterio
   que la tipología con un modelo "huérfano": un documento guardado dice lo
   que decía. Se muestra igual, marcado, y se puede desmarcar. */
function techoExtrasBodyHTML(){
  if(!TECHO_MODELO_HECHO){
    return `<p class="mini">${L({es:'Elige antes una Tipología de vivienda.',en:'Choose a Housing Typology first.',id:'Pilih dulu Tipologi hunian.'})}</p>`;
  }
  const techosMostrar = [...TECHOS_OPCIONES];
  if(TECHO_ELEGIDO && !techosMostrar.some(t=>t.techo_id===TECHO_ELEGIDO.techo_id))
    techosMostrar.push({ ...TECHO_ELEGIDO, huerfano:true });
  const optsTecho = techosMostrar.map(t=>
    `<option value="${escAttr(t.techo_id)}" ${TECHO_ELEGIDO && TECHO_ELEGIDO.techo_id===t.techo_id ? 'selected' : ''}>`
    + `${esc(t.nombre)} — ${fmtImporte(Number(t.precio))} ${esc(t.moneda)}`
    + `${t.huerfano ? ' — ' + L({es:'ya no está en el catálogo',en:'no longer in the catalogue',id:'tidak ada lagi di katalog'}) : ''}`
    + `</option>`).join('');
  const selectTecho = `<div class="field"><label for="techoSel">${L({es:'Techo',en:'Roof',id:'Atap'})}</label>
    <select class="sui-sel" id="techoSel"><option value="">${L({es:'— sin elegir —',en:'— not chosen —',id:'— belum dipilih —'})}</option>${optsTecho}</select>
    ${!TECHOS_OPCIONES.length && !TECHO_ELEGIDO ? `<p class="mini">${L({es:'Este modelo no tiene variantes de techo.',en:'This model has no roof variants.',id:'Model ini tidak punya varian atap.'})}</p>` : ''}
    </div>`;

  /* Los extras SOLO se pueden marcar con un techo ya elegido (revisión de
     código, 16-sep: sin esto, un extra marcado sin techo se imprimía en el
     contrato como "incluido" pero `syncPrecioTechoExtras` no lo sumaba a
     `precio_total` — el cliente pagaba de menos por un extra que el papel
     decía que tenía). El techo es la base sobre la que se suman; sin base no
     hay dónde sumar. Uno ya elegido en un contrato guardado se sigue viendo
     (nunca se pierde un dato guardado), pero deshabilitado hasta que se
     vuelva a elegir techo. */
  const sinTecho = !TECHO_ELEGIDO;
  const extrasMostrar = [...EXTRAS_OPCIONES];
  EXTRAS_ELEGIDOS.forEach(e=>{ if(!extrasMostrar.some(x=>x.extra_id===e.extra_id)) extrasMostrar.push({ ...e, huerfano:true }); });
  const extrasHTML = extrasMostrar.map(x=>{
    const marcado = EXTRAS_ELEGIDOS.some(e=>e.extra_id===x.extra_id);
    return `<label class="mini" style="display:block;padding:4px 0">
      <input type="checkbox" data-extra-opt="${escAttr(x.extra_id)}" ${marcado ? 'checked' : ''} ${sinTecho ? 'disabled' : ''}>
      ${esc(x.nombre)} — ${fmtImporte(Number(x.precio))} ${esc(x.moneda)}${x.huerfano ? ' — ' + L({es:'ya no se ofrece',en:'no longer offered',id:'tidak lagi ditawarkan'}) : ''}</label>`;
  }).join('') || `<p class="mini">${L({es:'Este modelo no tiene extras.',en:'This model has no extras.',id:'Model ini tidak punya extra.'})}</p>`;
  const avisoSinTecho = (sinTecho && extrasMostrar.length)
    ? `<p class="mini">${L({es:'Elige un techo para poder añadir extras: sin techo no hay sobre qué sumar su precio.',en:'Choose a roof to add extras: without one there is nothing to add their price to.',id:'Pilih atap dulu untuk menambah ekstra.'})}</p>` : '';

  return selectTecho + `<div class="field" style="grid-column:1/-1"><label>${L({es:'Extras',en:'Extras',id:'Ekstra'})}</label>${avisoSinTecho}${extrasHTML}</div>`;
}
function refreshTechoExtras(){ const b=$('[data-sec="techo_extras"] .body'); if(b) b.innerHTML=techoExtrasBodyHTML(); }

/* `precio_total` en Construcción pasa a salir de aquí cuando el modelo elegido
   tiene techo — por delante de `syncPrecioObraVinculada` (parcela_inventario.js),
   que sigue mandando cuando no hay techo elegido (modelos sin variantes, o
   contratos antiguos). Reutiliza `avisaPrecioForzado`: mismo aviso, mismo
   respeto a un precio ya negociado a mano. */
async function syncPrecioTechoExtras(){
  if(CONTRACT_TIPO[CURRENT.slug] !== 'construccion' || !TECHO_ELEGIDO) return;
  const el = document.querySelector('[name="precio_total"]');
  if(!el) return;
  const mon = TECHO_ELEGIDO.moneda || 'EUR';
  const obra = Number(TECHO_ELEGIDO.precio) + EXTRAS_ELEGIDOS.reduce((t,e)=>t+(Number(e.precio)||0),0);
  if(!(obra > 0)) return;   // datos raros: mejor no tocar nada
  const nuevo = fmtImporte(obra), antes = String(el.value||'').trim();
  if(antes && parseImporte(antes) === obra) return;   // ya cuadra
  const detalle = EXTRAS_ELEGIDOS.length
    ? ' + ' + EXTRAS_ELEGIDOS.map(e=>escAttr(e.nombre)+' '+fmtImporte(Number(e.precio))).join(' + ')
    : '';
  const queEsTexto = `el <b>techo y extras</b> elegidos: ${escAttr(TECHO_ELEGIDO.nombre)} ${fmtImporte(Number(TECHO_ELEGIDO.precio))}${detalle} ${mon}`;
  if(!antes){ el.value = nuevo; AUTO_UNIDAD['precio_total'] = nuevo; return; }
  el.value = nuevo; AUTO_UNIDAD['precio_total'] = nuevo;
  await avisaPrecioForzado({ antes, nuevo, tipoDoc:'construccion', unidad:{ codigo:'', moneda: mon }, el, queEsTexto });
}

/* Fila del extra elegido, para el documento — mismo espíritu que
   `hitosRowsHTML()` (assets/hitos_fechas.js): {{moneda}} literal, resuelto en
   el pase genérico de marcadores que corre justo después dentro de buildDoc(). */
function extrasConstruccionRowsHTML(){
  return (EXTRAS_ELEGIDOS||[]).map(e=>
    `<tr><td>${esc(e.nombre)}</td><td class="amt"><span class="mny">${esc(String(e.precio))}</span> {{moneda}}</td></tr>`
  ).join('');
}

if(typeof module !== 'undefined' && module.exports)
  module.exports = { extrasConstruccionRowsHTML };
