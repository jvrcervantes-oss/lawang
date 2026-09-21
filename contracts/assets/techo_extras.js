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
  /* Una vivienda siempre lleva techo (corrección del owner, 16-sep: "no puede
     salir -sin elegir-"). Si el modelo tiene variantes y todavía no hay
     ninguna elegida (contrato nuevo, o cambio real de tipología que ya limpió
     TECHO_ELEGIDO en syncTipologiaModelos), se preselecciona la MÁS ECONÓMICA
     — nunca la primera del array, que no tiene por qué venir ordenada.
     Un contrato ya guardado con su techo (o uno huérfano) no se toca aquí. */
  if(!TECHO_ELEGIDO && TECHOS_OPCIONES.length){
    const masBarato = TECHOS_OPCIONES.reduce((min,t)=>Number(t.precio) < Number(min.precio) ? t : min);
    // `por_defecto` (hallazgo MEDIA de Legal en la consulta de deploy, 16-sep):
    // esto lo eligió el software, no el comercial. Se apaga en cuanto el
    // #techoSel dispara un `change` real (parcela_inventario.js) y deja
    // rastro en el propio documento impreso (ver techoExtrasBodyHTML/collect
    // en app.html) — si el comprador disputa esta partida, hay que poder
    // distinguir "nadie lo tocó" de "se negoció y se dejó así a propósito".
    TECHO_ELEGIDO = { ...masBarato, fecha_resuelta: new Date().toISOString(), por_defecto: true };
  }
  refreshTechoExtras();
  syncPrecioTechoExtras();
  /* updateSaveButton() (21-sep-2026, ver CAMPOS_DESCUENTO_COMERCIAL en
     app.html) es quien enseña/oculta el campo de descuento comercial según
     `!!TECHO_ELEGIDO` — sin esta llamada, la preselección automática del
     techo más barato de aquí arriba (TECHO_ELEGIDO recién puesto) dejaba el
     campo oculto hasta que ALGO MÁS disparara updateSaveButton() por su
     cuenta (cualquier tecla en otro campo del formulario). Mismo motivo por
     el que el handler de #techoSel en parcela_inventario.js ya la llama tras
     un cambio manual — esta es la otra vía por la que TECHO_ELEGIDO cambia. */
  if(typeof updateSaveButton === 'function') updateSaveButton();
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
  /* SIN opción "— sin elegir —" (corrección del owner, 16-sep): una vivienda
     siempre lleva techo, así que el desplegable solo sirve para CAMBIAR entre
     variantes, nunca para vaciarlo — la preselección del más económico corre
     en cargarTechosYExtras() en cuanto se resuelven las opciones. Si el
     modelo no tiene ninguna variante, no hay nada que elegir y se avisa. */
  // Aviso "por defecto" visible en el propio editor (hallazgo MEDIA de Legal,
  // consulta de deploy 16-sep) — que quien redacta lo note ANTES de imprimir,
  // no solo al leer el PDF ya generado.
  const avisoPorDefecto = (TECHO_ELEGIDO && TECHO_ELEGIDO.por_defecto)
    ? `<p class="mini">${L({es:'Preseleccionado por ser el más económico — nadie lo ha elegido a mano todavía. El documento lo marca como "por defecto" mientras siga así.',en:'Preselected as the cheapest — no one has chosen it by hand yet. The document marks it "default" while this stays so.',id:'Dipilih otomatis karena paling murah — belum dipilih manual.'})}</p>`
    : '';
  const selectTecho = techosMostrar.length
    ? `<div class="field"><label for="techoSel">${L({es:'Techo',en:'Roof',id:'Atap'})}</label>
        <select class="sui-sel" id="techoSel">${optsTecho}</select>${avisoPorDefecto}</div>`
    : `<div class="field"><label>${L({es:'Techo',en:'Roof',id:'Atap'})}</label>
        <p class="mini">${L({es:'Este modelo no tiene variantes de techo.',en:'This model has no roof variants.',id:'Model ini tidak punya varian atap.'})}</p></div>`;

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
  const lblExtra  = L({es:'Extra',en:'Extra',id:'Ekstra'});
  const lblPrecio = L({es:'Precio',en:'Price',id:'Harga'});
  /* Tabla en vez de checkboxes sueltos uno debajo de otro (aviso del owner,
     16-sep: "no queda claro cómo está"): con nombre y precio en columnas
     propias, alineado a la derecha en cifras tabulares, se lee de un vistazo
     qué está marcado y cuánto suma cada uno — mismo patrón `.reg-tabla` que
     ya usan los registros de envíos/firmas de este mismo documento (incluye
     su propio colapso a tarjeta en móvil, vía `data-l`). */
  const filasExtras = extrasMostrar.map(x=>{
    const marcado = EXTRAS_ELEGIDOS.some(e=>e.extra_id===x.extra_id);
    return `<tr${marcado ? ' class="sel"' : ''}>
      <td style="width:1%;padding-right:0"><input type="checkbox" data-extra-opt="${escAttr(x.extra_id)}" ${marcado ? 'checked' : ''} ${sinTecho ? 'disabled' : ''}></td>
      <td data-l="${escAttr(lblExtra)}">${esc(x.nombre)}${x.huerfano ? ' — <span class="mini">' + L({es:'ya no se ofrece',en:'no longer offered',id:'tidak lagi ditawarkan'}) + '</span>' : ''}</td>
      <td data-l="${escAttr(lblPrecio)}" style="text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums">${fmtImporte(Number(x.precio))} ${esc(x.moneda)}</td>
    </tr>`;
  }).join('');
  const totalExtras = EXTRAS_ELEGIDOS.reduce((t,e)=>t+(Number(e.precio)||0),0);
  const monedaExtras = (TECHO_ELEGIDO && TECHO_ELEGIDO.moneda) || (extrasMostrar[0] && extrasMostrar[0].moneda) || 'EUR';
  const tablaExtras = extrasMostrar.length
    ? `<div class="reg-envoltura"><table class="reg-tabla">
        <thead><tr><th></th><th>${esc(lblExtra)}</th><th style="text-align:right">${esc(lblPrecio)}</th></tr></thead>
        <tbody>${filasExtras}</tbody>
        ${EXTRAS_ELEGIDOS.length ? `<tfoot><tr><td></td><td style="font-weight:600">${L({es:'Total extras',en:'Extras total',id:'Total ekstra'})}</td><td style="text-align:right;font-weight:600;white-space:nowrap;font-variant-numeric:tabular-nums">${fmtImporte(totalExtras)} ${esc(monedaExtras)}</td></tr></tfoot>` : ''}
      </table></div>`
    : `<p class="mini">${L({es:'Este modelo no tiene extras.',en:'This model has no extras.',id:'Model ini tidak punya extra.'})}</p>`;
  const avisoSinTecho = (sinTecho && extrasMostrar.length)
    ? `<p class="mini">${L({es:'Elige un techo para poder añadir extras: sin techo no hay sobre qué sumar su precio.',en:'Choose a roof to add extras: without one there is nothing to add their price to.',id:'Pilih atap dulu untuk menambah ekstra.'})}</p>` : '';

  return selectTecho + `<div class="field" style="grid-column:1/-1"><label>${L({es:'Extras',en:'Extras',id:'Ekstra'})}</label>${avisoSinTecho}${tablaExtras}</div>`;
}
function refreshTechoExtras(){ const b=document.getElementById('techoExtrasBox'); if(b) b.innerHTML=techoExtrasBodyHTML(); }

/* MONEDA del techo/extra vs moneda del documento — 16-sep-2026, hallazgo de
   Administración en la consulta de deploy (ALTA): un desajuste no puede
   quedarse en un simple aviso, porque `firma-submit` factura con `moneda`
   tal cual (~15.000x de diferencia real EUR↔IDR, no un matiz estético).
   Casi todo el catálogo es EUR, pero Riverfront I/II son IDR de arriba a
   abajo (catálogo, proyecto y unidades ya coinciden hoy — verificado, no a
   ojo). `MONEDA_DESAJUSTE` es lo que lee `guardarContrato()` (app.html) para
   BLOQUEAR el guardado — un aviso persistente no basta cuando lo que está en
   juego es la cifra que se factura, no solo un campo por rellenar.
   Función propia (no solo dentro de syncPrecioTechoExtras) porque tiene que
   volver a correr si el agente edita `moneda` A MANO después de elegir techo
   — sin esto, el aviso solo se comprobaba al elegir/quitar techo y un cambio
   posterior de moneda podía desincronizarse sin que nadie se enterara hasta
   la firma (segundo hallazgo de Administración, MEDIA). */
let MONEDA_DESAJUSTE = false;
function syncMonedaTechoExtras(){
  const elMon = document.querySelector('[name="moneda"]');
  if(!elMon || !TECHO_ELEGIDO){ MONEDA_DESAJUSTE = false; return; }
  const mon = TECHO_ELEGIDO.moneda || 'EUR';
  const monActual = elMon.value.trim();
  if(!monActual){
    elMon.value = mon; elMon.dispatchEvent(new Event('input', { bubbles:true }));
    MONEDA_DESAJUSTE = false;
    return;
  }
  MONEDA_DESAJUSTE = monActual !== mon;
  if(MONEDA_DESAJUSTE){
    marcarCampoAviso(elMon, `El techo/extra elegido está en ${mon} pero este documento va en ${monActual}. `
      + `El precio que se va a poner es en ${mon}, no en ${monActual} — corrígelo, no se puede guardar así.`);
  }else{
    elMon.classList.remove('campo-aviso');
    const nota = elMon.closest('.field'); if(nota){ const av = nota.querySelector('.aviso-campo'); if(av) av.remove(); }
  }
}

/* `precio_total` en Construcción pasa a salir de aquí cuando el modelo elegido
   tiene techo — por delante de `syncPrecioObraVinculada` (parcela_inventario.js),
   que sigue mandando cuando no hay techo elegido (modelos sin variantes, o
   contratos antiguos).
   SIN opción de rechazar al elegir/cambiar un extra (16-sep, corrección del
   owner tras probarlo): la primera versión reutilizaba `avisaPrecioForzado`,
   que ofrece "dejar el precio de antes" — y eso es exactamente lo que NO
   puede pasar cuando el propio agente acaba de marcar un extra: su precio
   ENTRA sí o sí.
   CON modal de confirmación cuando YA había un precio real puesto (16-sep,
   cuarta vuelta — Legal en la consulta de deploy cazó el error de la tercera:
   el candado `readonly` de fieldHTML() impide TECLEAR encima, pero el precio
   previo de una Construcción casi nunca viene de tecleo — viene de
   `syncPrecioObraVinculada()`, automático desde el Bloqueo/Reserva vinculada,
   dinero real. Elegir un techo sustituye ESE precio por el del catálogo de
   techos, y esa sustitución entre dos fuentes automáticas es exactamente el
   caso que alimenta `crearProformaAutomatica()`/`firma-submit` sin que nadie
   lo haya visto — el mismo riesgo que motivó el modal la primera vez, solo
   que mal diagnosticado como "problema de tecleo" la segunda). Si NO había
   precio antes (nada que sustituir), se queda en el toast informativo.

   ASYNC y la escritura DENTRO del `await` (16-sep, quinta vuelta — hallazgo
   ALTA de Administración en la consulta de deploy sobre la preselección
   automática del techo más barato, cargarTechosYExtras()): con `el.value`
   escrito ANTES de abrir el modal, el candado que ese modal representa no
   frenaba nada — el precio ya estaba puesto cuando el agente lo veía, y con
   la preselección automática eso puede pasar sin que nadie haya tocado el
   `<select>`, solo por cargar el modelo o reabrir un contrato anterior al
   16-sep. El agente sigue sin poder RECHAZAR el precio nuevo (eso sigue
   prohibido, decisión del owner: "no debe permitirme dejar el precio en
   48.000") — `lwConfirmar` se llama igual con `cancelar:false` y `aplicar()`
   corre pase lo que pase (Entendido, Escape o clic fuera), nunca según el
   resultado — pero ahora lo ve ANTES de que exista. */
async function syncPrecioTechoExtras(){
  if(CONTRACT_TIPO[CURRENT.slug] !== 'construccion' || !TECHO_ELEGIDO) return;
  const el = document.querySelector('[name="precio_total"]');
  if(!el) return;
  const mon = TECHO_ELEGIDO.moneda || 'EUR';
  syncMonedaTechoExtras();
  const base = Number(TECHO_ELEGIDO.precio) + EXTRAS_ELEGIDOS.reduce((t,e)=>t+(Number(e.precio)||0),0);
  if(!(base > 0)) return;   // datos raros: mejor no tocar nada
  /* Descuento comercial (21-sep-2026, revisión previa #33): RESTA de la
     fórmula, no la reabre — el candado de fijadoPrecioConstruccion (app.html)
     sigue siendo el único que decide precio_total, esto solo cambia lo que
     ese candado calcula. Se lee directo del campo (no de collect(), que aquí
     no está disponible sin recorrer todo el formulario) — vale 0 si el campo
     no existe todavía (plantilla sin el marcador) o está vacío. Clamp a
     [0, base]: un valor fuera del 15% permitido no se corrige aquí —
     guardarContrato() (app.html) es quien bloquea el guardado — pero tampoco
     se deja imprimir un precio_total negativo mientras se teclea. */
  const elDescuento = document.querySelector('[name="descuento_comercial"]');
  const descuento = elDescuento ? Math.min(Math.max(parseImporte(elDescuento.value) || 0, 0), base) : 0;
  const obra = base - descuento;
  const nuevo = fmtImporte(obra), antes = String(el.value||'').trim();
  if(antes && parseImporte(antes) === obra) return;   // ya cuadra
  const aplicar = () => {
    el.value = nuevo; AUTO_UNIDAD['precio_total'] = nuevo;
    el.dispatchEvent(new Event('input', { bubbles:true }));   // que la vista previa se entere
  };
  const detalle = EXTRAS_ELEGIDOS.length
    ? ' + ' + EXTRAS_ELEGIDOS.map(e=>e.nombre+' '+fmtImporte(Number(e.precio))).join(' + ')
    : '';
  const detalleDescuento = descuento > 0 ? ' − ' + fmtImporte(descuento) + ' (' + lwT('descuento comercial') + ')' : '';
  const desglose = TECHO_ELEGIDO.nombre + ' ' + fmtImporte(Number(TECHO_ELEGIDO.precio)) + detalle + detalleDescuento;
  if(antes){
    await lwConfirmar({
      titulo: 'Precio actualizado',
      cuerpo: `<p>Este documento traía <b>${escAttr(antes)} ${mon}</b> — puesto automáticamente por la Reserva vinculada o por un techo anterior — `
        + `y va a pasar a <b>${escAttr(nuevo)} ${mon}</b>, según el techo y los extras elegidos: ${escAttr(desglose)} ${mon}.</p>`
        + `<p>Este importe alimenta la proforma automática al guardar y la factura al firmar — revísalo antes de seguir.</p>`,
      confirmar: 'Entendido',
      cancelar: false,
    });
    aplicar();
  }else{
    aplicar();
    toast(lwT('Precio puesto a ') + nuevo + ' ' + mon + ' — ' + desglose);
  }
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
