/* ═══════════════════════════════════════════════════════════════════════════
   LA FECHA DE UN HITO DE PAGO
   Sale de contracts/app.html el 21-ago-2026.
   ═══════════════════════════════════════════════════════════════════════════
   Dos cosas y las dos tienen trampa:

   · el desfase de un hito («a los 3 meses») a fecha concreta — suma meses de
     calendario, no días, que no es lo mismo en febrero;
   · HOY en local y NUNCA `toISOString()`: eso convierte a UTC primero, y en
     Bali (UTC+8) antes de las 08:00 devuelve el día ANTERIOR. Un contrato
     fechado un día antes de firmarse.

   Se imprime en tres grafías porque el documento sale en tres idiomas.
   ═══════════════════════════════════════════════════════════════════════════ */
/* ---------- hitos: UI de la tabla de pagos dinámica ---------- */

/* Desfase de un hito → fecha concreta (18-ago-2026). `vence_meses` suma meses de
   calendario con la regla de Date: si el día no existe en el mes destino
   (31-ene + 1 mes), Date se pasa a marzo — se corrige al ÚLTIMO día del mes
   destino, que es lo que significa "a los 3 meses" en un contrato. `vence_dias`
   suma días exactos. Sin desfase declarado no se inventa fecha: null, y el campo
   queda vacío para que lo ponga el agente. */
/* HOY en local, nunca toISOString(): eso convierte a UTC primero y antes de
   las 2:00 en España la fecha sale de AYER — el mismo fallo que ya se arregló
   dentro de fechaVencimiento(), ahora en UN solo sitio para los defaults de
   formulario y la proforma automática (auditoría 19-ago). */
function hoyLocalISO(){
  const d = new Date();
  return d.getFullYear() + '-' + String(d.getMonth()+1).padStart(2,'0') + '-' + String(d.getDate()).padStart(2,'0');
}

function fechaVencimiento(base, hito){
  const d = new Date(base.getTime());
  if(typeof hito.vence_meses === 'number'){
    const dia = d.getDate();
    d.setMonth(d.getMonth() + hito.vence_meses);
    if(d.getDate() !== dia) d.setDate(0);   // se pasó de mes: último día del destino
  }else if(typeof hito.vence_dias === 'number'){
    d.setDate(d.getDate() + hito.vence_dias);
  }else{
    return null;
  }
  /* En LOCAL, nunca toISOString(): eso convierte a UTC primero, y un contrato
     hecho antes de las 2 de la madrugada en España (UTC+2) saldría con fecha de
     AYER. Es el mismo tipo de error de fecha que ya costó una carta con fecha
     equivocada en otro proyecto del estudio. */
  return d.getFullYear() + '-' + String(d.getMonth()+1).padStart(2,'0') + '-' + String(d.getDate()).padStart(2,'0');
}

/* La fecha de un hito, para IMPRIMIRLA en el documento. Tres grafías porque el
   contrato es trilingüe y "09/03/2026" no significa lo mismo en las tres: en
   inglés se escribe el mes con letra para que nadie lo lea como mes/día. */
const MES_EN = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
function fechaHitoImpresa(iso, lang){
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso||'')); if(!m) return '';
  if(lang==='en') return `${+m[3]} ${MES_EN[+m[2]-1]} ${m[1]}`;
  return `${m[3]}/${m[2]}/${m[1]}`;
}

/* HITOS DE FÁBRICA DEL CONTRATO DE CONSTRUCCIÓN — 16-sep-2026, cierre de
   jornada (owner). Hasta hoy los 5 hitos (tokens.json, hitosDefaults.
   ppjb_construccion) eran texto y % libres, iguales que en cualquier otro
   contrato. Dos cosas cambian, cada una con su propia marca por hito (un
   contrato guardado antes de este cambio no lleva ninguna de las dos y sigue
   siendo 100% manual — "un documento guardado dice lo que decía"):
   · `h.fijo` — SOLO los 5 de fábrica. % y concepto (ES/EN/ID) se pintan de
     fábrica en solo lectura; los abre `updateSaveButton()` (app.html) si el
     rol puede — mismo mecanismo que FIJOS_ESTUDIO, con un rol MÁS ESTRECHO
     (ROLES_HITOS_FIJOS: sin sales_manager, el owner dijo "administrador o
     super administrador"). Un hito añadido a mano no la lleva: su % y su
     concepto se quedan libres para cualquiera, como siempre.
   · `h.calculado` — los 5 de fábrica Y cualquier hito añadido a mano
     MIENTRAS ESTE CONTRATO YA TENGA CALENDARIO DE FÁBRICA (algún `h.fijo` —
     `haiFijo`, más abajo; no "mientras sea de Construcción": un contrato de
     Construcción de ANTES de este cambio no tiene ningún `fijo` y sigue
     siendo 100% manual, botones de añadir/quitar incluidos — corrección
     MEDIA de Administración, consulta de deploy 16-sep). Cuando sí hay
     calendario de fábrica, el motivo del owner ("usamos el PRECIO TOTAL
     PROYECTO fijo para calcular los hitos") es de la tabla entera, no solo
     de los cinco. La Cantidad deja de teclearse — sale de PRECIO TOTAL
     PROYECTO × % (recalcularMontosHitos, más abajo; solo el hito marcado
     `resto` absorbe la diferencia de redondeo, nunca "el último del
     array" — corrección ALTA de Legal, misma consulta) — siempre en solo
     lectura, sin excepción de rol: no hay "cifra a mano" que proteger
     cuando la cifra la pone la aritmética. `guardarContrato()` (app.html)
     bloquea el guardado si Σ% de los hitos calculados no da 100 —
     corrección ALTA de Administración, misma consulta: sin esto,
     `total - repartido` podía salir negativo en un documento firmable.
   Vencimiento no cambia para nadie: sigue siendo el desfase de fábrica
   (vence_dias) convertido a fecha editable, "por ahora como está" (owner). */
function hitosBodyHTML(){
  const esConstruccion = typeof CONTRACT_TIPO !== 'undefined' && CONTRACT_TIPO[CURRENT.slug] === 'construccion';
  // El candado de Añadir/Quitar va por si ESTE contrato usa de verdad el
  // calendario de fábrica (al menos un hito `fijo`), no por el TIPO de
  // contrato (corrección MEDIA de Administración, consulta de deploy
  // 16-sep): con el corte por tipo, un contrato de Construcción guardado
  // ANTES de hoy —sin ningún hito `fijo`, "sigue siendo 100% manual"— perdía
  // igualmente sus botones para cualquiera que no fuera admin/super_admin,
  // contradiciendo el propio punto de partida de este cambio.
  const haiFijo = HITOS.some(h=>h.fijo);
  const rows = HITOS.map((h,i)=>{
    const fijo = esConstruccion && !!h.fijo;
    const calculado = esConstruccion && !!h.calculado;
    // `readonly` de fábrica SIEMPRE al pintar (igual que FIJOS_ESTUDIO): el
    // rol todavía no se conoce en el primer render; updateSaveButton() lo
    // abre después si toca. `data-fijo-hito` es lo que esa función busca.
    const lockPct = fijo ? ` readonly data-fijo-hito class="dato-fijo"` : '';
    const lockTxt = fijo ? ` readonly data-fijo-hito class="dato-fijo"` : '';
    // Cantidad calculada: sin excepción de rol, así que no necesita esperar
    // a updateSaveButton() — se pinta bloqueada y se queda así siempre.
    const lockMonto = calculado ? ` readonly class="dato-fijo" title="${escAttr(L({es:'Lo calcula el % sobre el precio total del proyecto. No se edita a mano.',en:'Calculated from the % of the total project price. Not editable by hand.',id:'Dihitung dari % harga total proyek. Tidak bisa diubah manual.'}))}"` : '';
    // Quitar un hito de fábrica, o añadir uno nuevo, reparte de nuevo el
    // 100% oficial de la obra: si este contrato tiene calendario de fábrica
    // se pinta oculto de fábrica y updateSaveButton() lo revela solo a quien
    // puede (mismo `data-hito-admin` en el botón de abajo). "X" en vez de
    // "Quitar" (17-sep-2026, owner) — el texto se mantiene en el `title`/
    // `aria-label` para quien use lector de pantalla o pase el ratón.
    const tituloQuitar = escAttr(L({es:'Quitar hito',en:'Remove milestone',id:'Hapus tahap'})) + ' ' + (i+1);
    const btnDel = haiFijo
      ? `<button type="button" class="link-btn hito-x" data-hdel="${i}" data-hito-admin style="display:none" title="${tituloQuitar}" aria-label="${tituloQuitar}">✕</button>`
      : `<button type="button" class="link-btn hito-x" data-hdel="${i}" title="${tituloQuitar}" aria-label="${tituloQuitar}">✕</button>`;
    const notaTiming = !h.fecha && h.timing
      ? `<span class="hito-nota">${L({es:'Este contrato decía',en:'This contract said',id:'Kontrak ini menyebut'})}: «${esc(h.timing)}»</span>` : '';
    /* TABLA, NO TARJETAS (17-sep-2026, owner: "de una vista se vea mucho
       mejor, ahora hay demasiado scroll"). Antes cada hito era un bloque de
       3 filas (label encima de cada campo) — 5 hitos de fábrica eran
       15 filas visibles solo para leerlos. Las etiquetas de columna van UNA
       VEZ en <thead>, y el Concepto (owner: "texto" pasa a llamarse
       "concepto") ya no es una columna más — es el TÍTULO de cada hito, en
       su propia fila de ancho completo, con el número delante ("1. Prepa­
       ración del terreno..."); debajo va la fila de datos (%, Cantidad,
       Vencimiento) más los dos botones de acción. Inglés y bahasa se van a
       una fila hermana oculta que abre el botón ▸ — la "tabla desplegable"
       que pidió: no hace falta ver los tres idiomas para saber qué hito es. */
    return `
    <tr class="hito-titulo" data-hito="${i}">
      <td colspan="5"><div class="hito-titulo-fila"><span class="hito-num">${i+1}.</span><div class="field"><input id="${hid(i,'es')}" data-hi="${i}" data-hkey="es" value="${escAttr(h.es)}"${lockTxt}
        aria-label="${escAttr(L({es:'Concepto (Español), hito',en:'Concept (Spanish), milestone',id:'Konsep (Spanyol), tahap'}))} ${i+1}"
        placeholder="${escAttr(L({es:'Concepto (Español)',en:'Concept (Spanish)',id:'Konsep (Spanyol)'}))}"></div></div></td>
    </tr>
    <tr class="hito-fila" data-hito="${i}">
      <td class="pct"><div class="field"><input id="${hid(i,'pct')}" type="number" step="0.01" data-hi="${i}" data-hkey="pct" value="${escAttr(h.pct)}"${lockPct}
        aria-label="% ${L({es:'del hito',en:'of milestone',id:'tahap'})} ${i+1}"></div></td>
      <td class="monto"><div class="field"><input id="${hid(i,'monto')}" data-hi="${i}" data-hkey="monto" value="${escAttr(h.monto)}"${lockMonto}
        aria-label="${escAttr(L({es:'Cantidad, hito',en:'Amount, milestone',id:'Jumlah, tahap'}))} ${i+1}"></div></td>
      <td class="fecha"><div class="field"><input id="${hid(i,'fecha')}" type="date" data-hi="${i}" data-hkey="fecha" value="${escAttr(h.fecha||'')}"
        aria-label="${escAttr(L({es:'Vencimiento, hito',en:'Due date, milestone',id:'Jatuh tempo, tahap'}))} ${i+1}"></div>${notaTiming}</td>
      <td class="acciones">
        <button type="button" class="link-btn hito-mas-btn" data-hmas="${i}" aria-expanded="false" aria-controls="hito-mas-${i}"
          title="${escAttr(L({es:'Concepto en inglés y bahasa',en:'Concept in English and Bahasa',id:'Konsep dalam bahasa Inggris dan Indonesia'}))}">EN·ID ▸</button>
      </td>
      <td class="acciones">${btnDel}</td>
    </tr>
    <tr class="hito-mas" id="hito-mas-${i}" data-hito-mas="${i}" hidden>
      <td colspan="5">
        <div class="grid2">
          <div class="field"><label for="${hid(i,'en')}">${L({es:'Concepto (English)',en:'Concept (English)',id:'Konsep (Inggris)'})}</label><input id="${hid(i,'en')}" data-hi="${i}" data-hkey="en" value="${escAttr(h.en)}"${lockTxt}></div>
          <div class="field"><label for="${hid(i,'id')}">${L({es:'Concepto (Bahasa)',en:'Concept (Bahasa)',id:'Konsep (Bahasa)'})}</label><input id="${hid(i,'id')}" data-hi="${i}" data-hkey="id" value="${escAttr(h.id)}"${lockTxt}></div>
        </div>
      </td>
    </tr>`;
  }).join('');
  const total = HITOS.reduce((t,h)=>t+(parseFloat(h.pct)||0),0);
  const btnAdd = haiFijo
    ? `<button type="button" class="btn ghost" id="hitoAdd" data-hito-admin style="display:none">+ ${L({es:'Añadir hito',en:'Add milestone',id:'Tambah tahap'})}</button>`
    : `<button type="button" class="btn ghost" id="hitoAdd">+ ${L({es:'Añadir hito',en:'Add milestone',id:'Tambah tahap'})}</button>`;
  // Por qué no hay botones ni campos abiertos (hallazgo MEDIA de Legal,
  // consulta de deploy 16-sep): un candado sin explicación se lee como un
  // fallo. VISIBLE de fábrica (asume que no se puede, igual que los botones
  // asumen lo contrario) y updateSaveButton() lo esconde en cuanto el rol
  // resulta ser admin/super_admin.
  const avisoAdmin = haiFijo
    ? `<p class="mini" data-hito-admin-aviso>${L({es:'Añadir o quitar hitos, y editar el % y el concepto de los cinco de fábrica, es de administración (admin o super administrador) desde el 16-sep-2026.',en:'Adding or removing milestones, and editing the % and wording of the five factory ones, has been an admin/super-admin action since 16-Sep-2026.',id:'Menambah/menghapus tahap serta mengubah % dan teks lima tahap standar, sejak 16-Sep-2026 hanya untuk admin/super admin.'})}</p>`
    : '';
  return `<div class="hitos-tabla-wrap"><table class="hitos-tabla"><thead><tr>
      <th>%</th>
      <th>${L({es:'Cantidad',en:'Amount',id:'Jumlah'})}</th>
      <th>${L({es:'Vencimiento',en:'Due date',id:'Jatuh tempo'})}</th>
      <th></th>
      <th></th>
    </tr></thead><tbody>${rows}</tbody></table></div>
  <div class="dz-row" style="margin-top:10px">
    ${btnAdd}
    <span class="spacer" style="flex:1"></span>
    <span style="font-size:12px;color:${Math.round(total)===100?'var(--muted)':'var(--be)'}">Σ ${total}%</span>
  </div>${avisoAdmin}`;
}
function refreshHitos(){ const b=$('[data-sec="pagos"] .body'); if(b) b.innerHTML=hitosBodyHTML(); }

/* Cantidad de cada hito "calculado" — ver la nota grande de arriba. Se
   recalcula en dos momentos: cuando `precio_total` cambia (enganchado en
   aplicarReglasCampos(), app.html — "único punto por el que pasa 'un campo
   cambió'") y cuando el propio % de un hito calculado se edita a mano
   (parcela_inventario.js, listener de `data-hkey`). Parchea el `<input>` en
   sitio si ya está pintado, nunca `refreshHitos()`: eso reconstruye toda la
   sección y machaca lo que el agente esté tecleando en OTRO hito en ese
   mismo instante. */
function recalcularMontosHitos(){
  if(!Array.isArray(HITOS) || !HITOS.some(h=>h.calculado)) return;
  const elP = document.querySelector('[name="precio_total"]');
  const total = elP ? parseImporte(elP.value) : 0;
  const aplicar = (i, nuevo) => {
    if(HITOS[i].monto === nuevo) return;
    HITOS[i].monto = nuevo;
    const el = document.getElementById(hid(i,'monto'));
    if(el) el.value = nuevo;
  };
  if(!(total > 0)){
    // Sin precio total no hay nada que repartir — se limpia en vez de dejar
    // un importe calculado que ya no corresponde a ningún total.
    HITOS.forEach((h,i)=>{ if(h.calculado) aplicar(i, ''); });
    return;
  }
  /* Solo el hito marcado `resto:true` (el 5º de fábrica, "Revisión y
     entrega" — tokens.json) se lleva la diferencia de redondeo, NUNCA "el
     último del array" (corrección ALTA de Legal, consulta de deploy 16-sep:
     un hito añadido a mano con su propio % pasaba a ser el último y se
     llevaba el resto ajeno en vez de calcular el suyo — el documento
     imprimía su % real junto a un importe que no le correspondía). Sin esto
     no es un capricho de redondeo: la misma página enseña el precio total Y
     los importes, `fmtImporte()` redondea a 2 decimales, y redondear
     25/25/25/20/5 por separado puede dejar la suma un céntimo por encima o
     por debajo del total (aritmética de dinero:
     reference_aritmetica_de_dinero_funcion_pura_y_test.md). */
  let repartido = 0, idxResto = -1;
  HITOS.forEach((h,i)=>{
    if(!h.calculado) return;
    if(h.resto){ idxResto = i; return; }   // se calcula al final, con lo que sobre
    const pct = parseFloat(h.pct) || 0;
    const importe = pct > 0 ? Math.round(total * pct) / 100 : 0;
    repartido += importe;
    aplicar(i, importe ? fmtImporte(importe) : '');
  });
  if(idxResto < 0) return;   // ningún hito reclama el resto: nada más que hacer
  /* Nunca negativo (corrección ALTA de Administración, misma consulta): si
     Σ% de los hitos calculados no suma 100 —un admin editó un % de fábrica
     sin recuadrar los demás, o un hito añadido a mano se pasa del hueco que
     queda—, `total - repartido` podía salir negativo, y una Cantidad
     negativa en un calendario de pagos firmable es peor que una en blanco.
     Esto es solo el cinturón de PANTALLA para que ni transitoriamente se
     vea ese número; `guardarContrato()` (app.html) bloquea el guardado de
     verdad cuando Σ%≠100. */
  aplicar(idxResto, fmtImporte(Math.max(0, total - repartido)));
}
function hitosRowsHTML(){
  // {{moneda}} literal: se resuelve en el pase genérico de marcadores que buildDoc()
  // corre justo después de insertar estas filas (ver buildDoc: hitos → luego {{...}}).
  return HITOS.map((h,i)=>{
    // .mny marca "esto es un importe" para que idrEquiv() le añada la equivalencia en IDR
    const monto = (h.monto||'') ? `<span class="mny">${esc(String(h.monto))}</span> {{moneda}}` : '';
    // % vacío o 0 → celda en blanco, sin "0%". Un hito puede ser un importe
    // cerrado (la reserva) sin porcentaje del total que lo represente.
    const pct = (String(h.pct||'').trim()==='' || parseFloat(h.pct)===0) ? '' : esc(String(h.pct))+'%';
    /* La celda de timing imprime la FECHA de vencimiento cuando el hito la tiene
       (18-ago-2026: los pagos se controlan por fecha de calendario, no por texto
       libre). Con espacios por idioma, porque "09/03/2026" en inglés se lee como
       mes/día: allí va "9 Mar 2026". Los contratos de ANTES del cambio no llevan
       fecha y conservan su texto de timing tal cual — reabrirlos no les cambia ni
       una letra del documento. */
    const cuando = h.fecha
      ? `<span data-lang="es">${esc(fechaHitoImpresa(h.fecha,'es'))}</span><span data-lang="en">${esc(fechaHitoImpresa(h.fecha,'en'))}</span><span data-lang="id">${esc(fechaHitoImpresa(h.fecha,'id'))}</span>`
      : esc(String(h.timing||''));
    return `<tr><td class="n">${i+1}</td><td>`
    + `<span data-lang="es">${esc(String(h.es||''))}</span><span data-lang="en">${esc(String(h.en||''))}</span><span data-lang="id">${esc(String(h.id||''))}</span>`
    + `</td><td class="pct">${pct}</td>`
    + `<td class="amt">${monto}</td>`
    + `<td class="timing">${cuando}</td></tr>`;
  }).join('');
}
