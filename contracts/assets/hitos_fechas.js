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

/* CALENDARIO DE PAGOS ELEGIBLE — 28-sep-2026 (owner; revisión previa #148,
   Legal + Seguridad + Administración). El agente elige UNO de tres
   calendarios cerrados en el Contrato de Construcción; los % no se tocan:
   · estandar     los 5 de fábrica. A la firma NO hay vencimientos: cada uno lo
                  fija el parte de obra de su fase (+14 días, Art. 5).
   · unico_firma  1 × 100 %, vence en la fecha que pone el agente
                  (≥ firma, ≤ firma + 90 días; admin pasa del tope).
   · unico_obra   1 × 100 %, lo fija el parte de preparación. La fecha que
                  escriba el agente es ESTIMADA y va en `fecha_estimada`, nunca
                  en `fecha`: `fecha` crea el vencimiento y la factura
                  automática lo cobraría antes de empezar la obra.
   Y dos que no se eligen, se heredan: `manual` (lo montó un admin: el resto
   solo mueve fechas) y `libre` (contratos de antes del 16-sep, a mano como
   siempre). QUIEN MANDA ES EL SERVIDOR: contrato_guarda rehace la tabla
   entera —importes incluidos— desde el preset y el precio total, y devuelve
   la que guardó; lo de aquí es solo lo que el agente ve mientras edita. */
const CALENDARIOS_ELEGIBLES = ['estandar', 'unico_firma', 'unico_obra'];
/* Tope del pago único a la firma, en días. Manda parametros.construccion.pago_unico_max_dias (Ajustes), que es lo
   que aplica el servidor; 90 es solo el valor mientras llega la lectura, para que pantalla y base no digan cosas
   distintas si un admin lo cambia (revisor de código, 28-sep). */
let PLAZO_PAGO_UNICO_DIAS = 90;
let PLAZO_PAGO_UNICO_LEIDO = false;
function leePlazoPagoUnico(){
  if(PLAZO_PAGO_UNICO_LEIDO || typeof sb === 'undefined' || !sb) return;
  PLAZO_PAGO_UNICO_LEIDO = true;
  Promise.resolve(sb.from('parametros').select('valor').eq('clave', 'construccion.pago_unico_max_dias').maybeSingle())
    .then(r => {
      const v = r && r.data ? Number(r.data.valor) : NaN;
      if(isFinite(v) && v >= 0 && v !== PLAZO_PAGO_UNICO_DIAS){ PLAZO_PAGO_UNICO_DIAS = v; if(typeof refreshHitos === 'function') refreshHitos(); if(typeof updateSaveButton === 'function') updateSaveButton(); }
    }).catch(() => { PLAZO_PAGO_UNICO_LEIDO = false; });
}
function presetCalendario(cal){
  const t = (typeof TOKENS !== 'undefined' && TOKENS) || {};
  const lista = cal === 'estandar'
    ? ((t.hitosDefaults || {}).ppjb_construccion)
    : ((t.hitosCalendarios || {})[cal]);
  return Array.isArray(lista) ? lista.map(h => ({...h})) : null;
}
/* Qué calendario es una tabla YA GUARDADA sin la marca `calendario` (todo lo
   anterior al 28-sep). Misma regla que contrato_calendario_deduce en la base:
   % y concepto en los tres idiomas, en orden, y todos de fábrica. */
function calendarioDeduce(hitos){
  if(!Array.isArray(hitos) || !hitos.length || !hitos.some(h => h && h.fijo)) return 'libre';
  for(const cal of CALENDARIOS_ELEGIBLES){
    const pre = presetCalendario(cal);
    if(pre && pre.length === hitos.length && pre.every((p,i) => {
      const h = hitos[i] || {};
      return parseFloat(h.pct) === parseFloat(p.pct) && (h.es||'') === p.es && (h.en||'') === p.en
          && (h.id||'') === p.id && !!h.fijo;
    })) return cal;
  }
  return 'manual';
}
function fechaFirmaISO(){
  const v = ((document.querySelector('[name="fecha_firma"]') || {}).value || '').trim();
  return /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : hoyLocalISO();
}
function sumaDiasISO(iso, dias){
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso); if(!m) return '';
  return fechaVencimiento(new Date(+m[1], +m[2]-1, +m[3]), { vence_dias: dias });
}
/* Cambiar de calendario sustituye la tabla entera por el preset. El pago
   único a la firma arranca a firma + 14 días, el mismo plazo que el Art. 5 da
   a los hitos: el agente lo mueve si pactó otra cosa. */
function cambiaCalendario(cal){
  if(!CALENDARIOS_ELEGIBLES.includes(cal) || cal === CALENDARIO) return;
  const pre = presetCalendario(cal); if(!pre) return;
  if(cal === 'unico_firma') pre[0].fecha = sumaDiasISO(fechaFirmaISO(), 14);
  HITOS = pre; CALENDARIO = cal;
  // Quien cambia con las flechas sigue en el grupo: el repintado rehace los radios y se llevaba el foco
  const conFoco = document.activeElement && document.activeElement.name === 'formaPago';
  refreshHitos();   // repinta también el paso 1
  if(conFoco){ const r = document.querySelector('input[name="formaPago"]:checked'); if(r) r.focus(); }
  if(typeof recalcularMontosHitos === 'function') recalcularMontosHitos();
  if(typeof updateSaveButton === 'function') updateSaveButton();
  if(typeof render === 'function') render();
}
/* Un admin que toca un % o un concepto de fábrica, o añade/quita un hito,
   deja de estar en un calendario de fábrica: pasa a «a medida», y el
   documento deja de imprimir la cláusula de pago único si la tenía. */
function calendarioPasaAManual(){
  if(!CALENDARIOS_ELEGIBLES.includes(CALENDARIO)) return;
  CALENDARIO = 'manual';
  refreshFormaPago();
}

/* FORMA DE PAGO = PASO 1 DEL CONTRATO DE CONSTRUCCIÓN (28-sep-2026, owner: «que
   sea el primer paso, que quede claro que está ahí»). Hasta hoy era un
   desplegable dentro de «Calendario de pagos», a media página: se podía
   redactar el contrato entero sin verlo. Ahora es la primera sección del
   formulario, con tres tarjetas que dicen cómo se reparte el pago y cuándo
   vence cada uno — la decisión que cambia la tabla de pagos y la cláusula del
   Art. 5, a la vista antes que nada. Radios de verdad (teclado y lector de
   pantalla), pintados como tarjetas. */
function formaPagoCerrada(){
  return (typeof LOCKED !== 'undefined' && LOCKED)
    || (typeof EN_FIRMA !== 'undefined' && (EN_FIRMA.vivas + EN_FIRMA.firmadas) > 0);
}
const FORMAS_PAGO = [
  { cal:'estandar', ico:'stacked_bar_chart',
    tit:{es:'Por hitos',en:'By milestones',id:'Per tahap'},
    rep:{es:'5 pagos · 25/25/25/20/5 %',en:'5 payments · 25/25/25/20/5 %',id:'5 pembayaran · 25/25/25/20/5 %'},
    cuando:()=>({es:'Cada pago vence 14 días después de que la obra entre en su fase.',en:'Each payment falls due 14 days after the works enter its phase.',id:'Setiap pembayaran jatuh tempo 14 hari setelah pekerjaan memasuki fasenya.'}) },
  { cal:'unico_firma', ico:'event',
    tit:{es:'Pago único a la firma',en:'Single payment on signing',id:'Pembayaran tunggal saat tanda tangan'},
    rep:{es:'1 pago · 100 %',en:'1 payment · 100 %',id:'1 pembayaran · 100 %'},
    cuando:()=>({es:`Vence en la fecha que pongas, como muy tarde ${PLAZO_PAGO_UNICO_DIAS} días después de la firma.`,en:`Falls due on the date you set, at most ${PLAZO_PAGO_UNICO_DIAS} days after signing.`,id:`Jatuh tempo pada tanggal yang Anda tetapkan, paling lambat ${PLAZO_PAGO_UNICO_DIAS} hari setelah penandatanganan.`}) },
  { cal:'unico_obra', ico:'construction',
    tit:{es:'Pago único al inicio de obra',en:'Single payment when works start',id:'Pembayaran tunggal saat pekerjaan dimulai'},
    rep:{es:'1 pago · 100 %',en:'1 payment · 100 %',id:'1 pembayaran · 100 %'},
    cuando:()=>({es:'Vence 14 días después de que empiece la obra. La fecha que pongas es solo estimada.',en:'Falls due 14 days after works start. Any date you set is only an estimate.',id:'Jatuh tempo 14 hari setelah pekerjaan dimulai. Tanggal yang Anda isi hanya perkiraan.'}) }
];
function formaPagoBodyHTML(){
  leePlazoPagoUnico();
  const cal = CALENDARIO || 'estandar';
  const cerrado = formaPagoCerrada();
  // Un calendario a medida lo cambia solo un admin (la base lo rechaza a los demás): las tarjetas se pintan
  // cerradas y updateSaveButton() las abre si el rol resulta ser admin — mismo patrón que los hitos de fábrica.
  const soloAdmin = !cerrado && cal === 'manual';
  const abreAdmin = soloAdmin && typeof puedeHitosFijos === 'function' && puedeHitosFijos();
  const tarjetas = FORMAS_PAGO.map(f => {
    const sel = f.cal === cal;
    return `<label class="fp-op${sel ? ' sel' : ''}">
      <input type="radio" name="formaPago" value="${f.cal}"${sel ? ' checked' : ''}${(cerrado || (soloAdmin && !abreAdmin)) ? ' disabled' : ''}${soloAdmin ? ' data-cal-manual' : ''}>
      <span class="fp-ico" data-ico="${f.ico}" aria-hidden="true"></span>
      <span class="fp-tit">${esc(L(f.tit))}</span>
      <span class="fp-rep">${esc(L(f.rep))}</span>
      <span class="fp-cuando">${esc(L(f.cuando()))}</span>
    </label>`;
  }).join('');
  const aviso = cerrado
    ? L({es:'El contrato está enviado a firma o firmado: la forma de pago ya no se cambia.',en:'The contract has been sent for signature or signed: the payment method can no longer change.',id:'Kontrak sudah dikirim untuk ditandatangani atau sudah ditandatangani: cara pembayaran tidak bisa diubah.'})
    : cal === 'manual'
    ? L({es:'Este contrato tiene un calendario a medida, montado por administración. Solo un administrador puede cambiar la forma de pago.',en:'This contract has a custom schedule set up by admin. Only an admin can change the payment method.',id:'Kontrak ini memakai jadwal khusus dari admin. Hanya admin yang dapat mengubah cara pembayaran.'})
    : cal === 'libre'
    ? L({es:'Este contrato es anterior a las formas de pago y su calendario se editó a mano. Si eliges una, la tabla de pagos se sustituye.',en:'This contract predates payment methods and its schedule was edited by hand. Choosing one replaces the payment table.',id:'Kontrak ini dibuat sebelum ada cara pembayaran dan jadwalnya diedit manual. Memilih salah satu akan mengganti tabel pembayaran.'})
    : '';
  return `<p class="fp-intro">${esc(L({es:'Elige primero cómo pagará el comprador la obra. Decide la tabla de pagos y lo que dice el Art. 5 del contrato.',en:'First choose how the buyer will pay for the works. It sets the payment table and what Article 5 of the contract says.',id:'Pilih dulu bagaimana pembeli membayar pekerjaan. Ini menentukan tabel pembayaran dan isi Pasal 5 kontrak.'}))}</p>
    <div class="fp-opciones" role="radiogroup" aria-label="${escAttr(L({es:'Forma de pago',en:'Payment method',id:'Cara pembayaran'}))}">${tarjetas}</div>
    ${aviso ? `<p class="fp-aviso">${esc(aviso)}</p>` : ''}
    ${cal === 'unico_firma' || cal === 'estandar' || cal === 'unico_obra' ? `<p class="fp-descuento">${esc(L({es:'¿Hay descuento por pagar al contado? Va en «Descuento comercial».',en:'Cash discount? It goes in «Commercial discount».',id:'Ada diskon tunai? Masukkan di «Diskon komersial».'}))}</p>` : ''}`;
}
/* Solo repinta si cambia algo de lo que enseña. No es una optimización: se llama desde aplicarEstadoFirma(),
   que corre en cada `input` del formulario vía updateSaveButton(), y el `input` de un radio llega ANTES que su
   `change`. Repintar ahí destruía el radio recién pulsado, el `change` salía de un nodo suelto y la forma de pago
   no cambiaba nunca (revisor de código, 28-sep, reproducido en Edge). Con la firma, repintar solo cuando algo
   cambia es seguro desde cualquier sitio. */
function firmaFormaPago(){
  return [CALENDARIO || 'estandar', formaPagoCerrada() ? 1 : 0,
          (typeof puedeHitosFijos === 'function' && puedeHitosFijos()) ? 1 : 0,
          (typeof LANG !== 'undefined' ? LANG : ''), PLAZO_PAGO_UNICO_DIAS].join('|');
}
function refreshFormaPago(){
  const b = document.getElementById('formaPagoBox'); if(!b) return;
  const f = firmaFormaPago();
  if(b.getAttribute('data-firma') === f) return;
  b.innerHTML = formaPagoBodyHTML();
  b.setAttribute('data-firma', f);
}

/* Dentro de «Calendario de pagos» ya no se elige: se recuerda qué forma de pago
   hay y se lleva de vuelta al paso 1 para cambiarla. */
function calendarioResumenHTML(){
  const f = FORMAS_PAGO.find(x => x.cal === CALENDARIO);
  const nombre = f ? L(f.tit)
    : CALENDARIO === 'manual' ? L({es:'A medida (administración)',en:'Custom (admin)',id:'Khusus (admin)'})
    : L({es:'Calendario anterior, a mano',en:'Earlier schedule, by hand',id:'Jadwal lama, manual'});
  return `<p class="fp-resumen"><span>${esc(L({es:'Forma de pago',en:'Payment method',id:'Cara pembayaran'}))}:</span> <b>${esc(nombre)}</b>
    <button type="button" class="link-btn" data-ir-forma-pago>${esc(L({es:'Cambiar en el paso 1',en:'Change in step 1',id:'Ubah di langkah 1'}))}</button></p>`;
}

/* La celda de vencimiento de cada hito, según el calendario (28-sep-2026):
   en el estándar no hay fecha que poner —la pone la obra—, en el pago único
   al inicio de obra la fecha es una estimación con su propia clave, y en el
   pago único a la firma es la fecha real, acotada. El resto, como siempre. */
function celdaFecha(h, i, esConstruccion, notaTiming){
  const etiqueta = escAttr(L({es:'Vencimiento, hito',en:'Due date, milestone',id:'Jatuh tempo, tahap'})) + ' ' + (i+1);
  if(esConstruccion && CALENDARIO === 'estandar'){
    return `<span class="mini">${esc(L({es:'Al iniciar su fase de obra (+14 días)',en:'When its construction phase starts (+14 days)',id:'Saat fase konstruksinya dimulai (+14 hari)'}))}</span>`;
  }
  if(esConstruccion && CALENDARIO === 'unico_obra'){
    return `<div class="field"><input id="${hid(i,'fecha_estimada')}" type="date" data-hi="${i}" data-hkey="fecha_estimada" value="${escAttr(h.fecha_estimada||'')}"
        min="${escAttr(fechaFirmaISO())}" aria-label="${escAttr(L({es:'Fecha estimada, hito',en:'Estimated date, milestone',id:'Tanggal perkiraan, tahap'}))} ${i+1}"></div>
      <span class="hito-nota">${esc(L({es:'Estimada — la real la fija el inicio de obra',en:'Estimated — the real one is set when works start',id:'Perkiraan — tanggal sebenarnya ditetapkan saat pekerjaan dimulai'}))}</span>`;
  }
  const acota = esConstruccion && CALENDARIO === 'unico_firma';
  const topes = acota
    ? ` min="${escAttr(fechaFirmaISO())}"` + ((typeof puedeHitosFijos === 'function' && puedeHitosFijos()) ? '' : ` max="${escAttr(sumaDiasISO(fechaFirmaISO(), PLAZO_PAGO_UNICO_DIAS))}"`)
    : '';
  return `<div class="field"><input id="${hid(i,'fecha')}" type="date" data-hi="${i}" data-hkey="fecha" value="${escAttr(h.fecha||'')}"${topes}
        aria-label="${etiqueta}"></div>${notaTiming}`;
}
function hitosBodyHTML(){
  const esConstruccion = typeof CONTRACT_TIPO !== 'undefined' && CONTRACT_TIPO[CURRENT.slug] === 'construccion';
  // Moneda del documento junto a la Cantidad de cada hito (17-sep-2026,
  // owner) — se lee del campo `moneda` del propio contrato, la misma fuente
  // que ya usa syncMonedaTechoExtras(): no se inventa ni se traduce, es
  // literalmente la que va a ir en el documento impreso.
  const monedaDoc = (document.querySelector('[name="moneda"]') || {}).value || '';
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
       Vencimiento). El botón ▸ EN·ID vive en la fila del título (17-sep,
       owner: "súbelo a la fila del concepto") — es del CONCEPTO, así que
       tiene más sentido pegado a él que suelto entre los números. La fila de
       datos se queda en 4 columnas: %, Cantidad, Vencimiento y quitar. */
    return `
    <tr class="hito-titulo" data-hito="${i}">
      <td colspan="4"><div class="hito-titulo-fila"><span class="hito-num">${i+1}.</span><div class="field"><input id="${hid(i,'es')}" data-hi="${i}" data-hkey="es" value="${escAttr(h.es)}"${lockTxt}
        aria-label="${escAttr(L({es:'Concepto (Español), hito',en:'Concept (Spanish), milestone',id:'Konsep (Spanyol), tahap'}))} ${i+1}"
        placeholder="${escAttr(L({es:'Concepto (Español)',en:'Concept (Spanish)',id:'Konsep (Spanyol)'}))}"></div><button type="button" class="link-btn hito-mas-btn" data-hmas="${i}" aria-expanded="false" aria-controls="hito-mas-${i}"
          title="${escAttr(L({es:'Concepto en inglés y bahasa',en:'Concept in English and Bahasa',id:'Konsep dalam bahasa Inggris dan Indonesia'}))}">EN·ID ▸</button></div></td>
    </tr>
    <tr class="hito-fila" data-hito="${i}">
      <td class="pct"><div class="field"><input id="${hid(i,'pct')}" type="number" step="0.01" data-hi="${i}" data-hkey="pct" value="${escAttr(h.pct)}"${lockPct}
        aria-label="% ${L({es:'del hito',en:'of milestone',id:'tahap'})} ${i+1}"></div></td>
      <td class="monto"><div class="field hito-monto-grupo"><input id="${hid(i,'monto')}" data-hi="${i}" data-hkey="monto" value="${escAttr(h.monto)}"${lockMonto}
        aria-label="${escAttr(L({es:'Cantidad, hito',en:'Amount, milestone',id:'Jumlah, tahap'}))} ${i+1}"><span class="hito-moneda">${esc(monedaDoc)}</span></div></td>
      <td class="fecha">${celdaFecha(h, i, esConstruccion, notaTiming)}</td>
      <td class="acciones">${btnDel}</td>
    </tr>
    <tr class="hito-mas" id="hito-mas-${i}" data-hito-mas="${i}" hidden>
      <td colspan="4">
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
    ? `<p class="mini" data-hito-admin-aviso>${L({es:'Añadir o quitar pagos, o cambiar su % o su concepto, es cosa de administración (admin o super administrador). Para otro reparto, elige otra forma de pago en el paso 1.',en:'Adding or removing payments, or changing their % or wording, is an admin/super-admin action. For a different split, choose another payment method in step 1.',id:'Menambah/menghapus pembayaran atau mengubah % dan teksnya hanya untuk admin/super admin. Untuk pembagian lain, pilih cara pembayaran lain di langkah 1.'})}</p>`
    : '';
  /* Abono de la Carta de Reserva — se enseña aquí, y no solo en el toast del
     guardado, porque un toast se desvanece en segundos y esto tiene que
     "no desaparecer en silencio" (regla 4 del encargo, hallazgo ALTA de
     Legal en la consulta de deploy del 17-sep: el sobrante que el trigger sí
     calcula no aparecía en NINGÚN sitio visible — ni en el PDF, que es
     correcto y a propósito, ni en pantalla, que no lo era). Vive DENTRO de
     hitosBodyHTML() y no en un sitio aparte para que se repinte solo cada
     vez que refreshHitos() corre — abrir el contrato, editar un campo,
     reordenar hitos — sin tener que acordarse de llamarlo en cada punto por
     separado. Fuente: CAMPOS_HEREDADOS, la misma que ya usa collect() para
     imprimir la cláusula del documento (app.html) — nunca un cálculo propio
     aquí, nunca un RPC a contrato_cobrado(). */
  const cc = (typeof CAMPOS_HEREDADOS !== 'undefined') ? CAMPOS_HEREDADOS : {};
  const avisoCartaCobrado = (cc.carta_cobrado_importe || cc.carta_cobrado_sobrante) ? `
  <p class="sui-aviso" role="status">
    ${cc.carta_cobrado_importe ? esc(L({
        es:`Se han descontado ${cc.carta_cobrado_importe} ya cobrados en la Carta de Reserva ${cc.carta_cobrado_numeros || ''}.`,
        en:`${cc.carta_cobrado_importe} already paid under Reservation Letter ${cc.carta_cobrado_numeros || ''} has been deducted.`,
        id:`Sebesar ${cc.carta_cobrado_importe} yang telah dibayarkan pada Surat Reservasi ${cc.carta_cobrado_numeros || ''} telah dikurangkan.`
      })) : ''}
    ${cc.carta_cobrado_sobrante ? ' ⚠️ ' + esc(L({
        es:`Sobran ${cc.carta_cobrado_sobrante} cobrados en la Carta que este Bloqueo no puede absorber (su precio es menor) — decide a mano qué hacer con ese resto.`,
        en:`${cc.carta_cobrado_sobrante} paid under the Letter is left over — this Deed's price cannot absorb it (it is lower) — decide by hand what to do with the rest.`,
        id:`Sisa ${cc.carta_cobrado_sobrante} yang dibayarkan pada Surat tidak dapat diserap oleh Perjanjian ini (harganya lebih rendah) — tentukan secara manual apa yang harus dilakukan dengan sisa tersebut.`
      })) : ''}
  </p>` : '';
  return `${esConstruccion ? calendarioResumenHTML() : ''}<div class="hitos-tabla-wrap"><table class="hitos-tabla"><thead><tr>
      <th>%</th>
      <th>${L({es:'Cantidad',en:'Amount',id:'Jumlah'})}</th>
      <th>${L({es:'Vencimiento',en:'Due date',id:'Jatuh tempo'})}</th>
      <th></th>
    </tr></thead><tbody>${rows}</tbody></table></div>
  <div class="dz-row" style="margin-top:10px">
    ${btnAdd}
    <span class="spacer" style="flex:1"></span>
    <span style="font-size:12px;color:${Math.round(total)===100?'var(--muted)':'var(--be)'}">Σ ${total}%</span>
  </div>${avisoAdmin}${avisoCartaCobrado}`;
}
/* Repinta también el paso 1 (forma de pago): abrir un contrato guardado, derivarlo, guardarlo o cambiar de
   idioma cambian CALENDARIO/LOCKED y todos pasan por aquí. Sin esto las tarjetas se quedaban con la forma de
   pago del borrador por defecto (revisor de código, 28-sep). */
function refreshHitos(){ const b=$('[data-sec="pagos"] .body'); if(b) b.innerHTML=hitosBodyHTML(); refreshFormaPago(); }

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
  if(idxResto >= 0){
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

  /* Abono de la Carta de Reserva, ya cobrado y congelado al traspasar la
     parcela (17-sep-2026) — ver sql/carta_cobrado_al_bloquear.sql, que es
     quien lo CALCULA de verdad, una sola vez, al guardar el Bloqueo por
     primera vez. Aquí solo se REAPLICA sobre lo que acaba de calcularse
     arriba, cada vez que `precio_total` cambia: el 50/50 base se recalcula
     con el precio nuevo y el descuento —que es un número fijo, no un
     porcentaje— se resta otra vez en cascada, en el MISMO orden que usa el
     trigger (`lwDescuentoCascada`, dinero.js — misma función, no una tercera
     copia). Antes del primer guardado no hay nada que leer aquí: recién
     derivado (derivarContrato() limpia CAMPOS_HEREDADOS), este bloque no
     hace nada y el 50/50 de arriba se queda tal cual — es justo lo que pide
     la regla 7 del encargo. NUNCA se llama a `contrato_cobrado()` por RPC
     para "adelantarlo": la única fuente es lo que el propio contrato ya
     guardó. */
  const descuento = parseImporte((typeof CAMPOS_HEREDADOS !== 'undefined' && CAMPOS_HEREDADOS.carta_cobrado_importe) || '');
  if(descuento > 0){
    // Solo sobre los hitos `calculado` — igual que el reparto de arriba
    // (`if(!h.calculado) return;`). Un hito escrito a mano por el agente NO
    // entra en la cascada: ni se le resta el descuento, ni "gasta" parte de
    // él, porque su importe no es una fracción del total que este bloque
    // controle — es un valor que el agente tecleó a propósito (hallazgo
    // code-review 17-sep: la primera versión pisaba también los manuales).
    const idxCalc = [], montosCalc = [];
    HITOS.forEach((h,i)=>{ if(h.calculado){ idxCalc.push(i); montosCalc.push(h.monto); } });
    const nuevos = lwDescuentoCascada(montosCalc, descuento);
    idxCalc.forEach((i,k)=>{
      aplicar(i, nuevos[k]);
      // Espejo de la marca que pone la base (carta_cobrado_aplica_hitos): el
      // hito que absorbió descuento imprime el importe con (*) y sin el "50%"
      // que ya no es verdad. Solo render — la base la recalcula y pisa al guardar.
      HITOS[i].descontado = parseImporte(nuevos[k]) !== parseImporte(montosCalc[k]);
    });
  }
}
function hitosRowsHTML(){
  // {{moneda}} literal: se resuelve en el pase genérico de marcadores que buildDoc()
  // corre justo después de insertar estas filas (ver buildDoc: hitos → luego {{...}}).
  return HITOS.map((h,i)=>{
    // .mny marca "esto es un importe" para que idrEquiv() le añada la equivalencia en IDR
    // Hito DESCONTADO (22-sep-2026): su importe ya no es el % del precio porque
    // absorbió el abono de la Carta de Reserva (la marca la pone la base,
    // carta_cobrado_aplica_hitos; aquí la espeja recalcularMontosHitos). Se
    // imprime el importe con (*) y la celda % en blanco — `pct` sigue en el
    // dato (Σ%=100 al guardar y contrato_vencimientos lo leen), solo no se
    // enseña. La nota (*) vive en la plantilla, bajo la tabla (Legal).
    const descontado = !!h.descontado;
    const monto = (h.monto||'') ? `<span class="mny">${esc(String(h.monto))}</span> {{moneda}}${descontado ? ' (*)' : ''}` : '';
    // % vacío o 0 → celda en blanco, sin "0%". Un hito puede ser un importe
    // cerrado (la reserva) sin porcentaje del total que lo represente.
    const pct = (descontado || String(h.pct||'').trim()==='' || parseFloat(h.pct)===0) ? '' : esc(String(h.pct))+'%';
    /* La celda de timing imprime la FECHA de vencimiento cuando el hito la tiene
       (18-ago-2026: los pagos se controlan por fecha de calendario, no por texto
       libre). Con espacios por idioma, porque "09/03/2026" en inglés se lee como
       mes/día: allí va "9 Mar 2026". Los contratos de ANTES del cambio no llevan
       fecha y conservan su texto de timing tal cual — reabrirlos no les cambia ni
       una letra del documento. */
    /* Pago único al inicio de obra (28-sep-2026): su fecha es una ESTIMACIÓN
       y sale como tal — la cláusula del Art. 5 dice que no determina cuándo
       se debe el pago; imprimirla a secas daría dos vencimientos distintos en
       el mismo documento (Legal, revisión previa #148). */
    const cuando = h.fecha
      ? `<span data-lang="es">${esc(fechaHitoImpresa(h.fecha,'es'))}</span><span data-lang="en">${esc(fechaHitoImpresa(h.fecha,'en'))}</span><span data-lang="id">${esc(fechaHitoImpresa(h.fecha,'id'))}</span>`
      : h.fecha_estimada
      ? `<span data-lang="es">Estimada: ${esc(fechaHitoImpresa(h.fecha_estimada,'es'))}</span><span data-lang="en">Estimated: ${esc(fechaHitoImpresa(h.fecha_estimada,'en'))}</span><span data-lang="id">Perkiraan: ${esc(fechaHitoImpresa(h.fecha_estimada,'id'))}</span>`
      : esc(String(h.timing||''));
    return `<tr><td class="n">${i+1}</td><td>`
    + `<span data-lang="es">${esc(String(h.es||''))}</span><span data-lang="en">${esc(String(h.en||''))}</span><span data-lang="id">${esc(String(h.id||''))}</span>`
    + `</td><td class="pct">${pct}</td>`
    + `<td class="amt">${monto}</td>`
    + `<td class="timing">${cuando}</td></tr>`;
  }).join('');
}
