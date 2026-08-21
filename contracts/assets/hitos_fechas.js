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

function hitosBodyHTML(){
  const rows = HITOS.map((h,i)=>`
    <div class="dz" data-hito="${i}">
      <div class="dz-row"><span style="width:auto;font-weight:600;color:var(--dl)">${L({es:'Hito',en:'Milestone',id:'Tahap'})} ${i+1}</span>
        <span class="spacer" style="flex:1"></span>
        <button type="button" class="link-btn" data-hdel="${i}">${L({es:'Quitar',en:'Remove',id:'Hapus'})}</button></div>
      <div class="grid2">
        <div class="field"><label for="${hid(i,'pct')}">%</label><input id="${hid(i,'pct')}" type="number" step="0.01" data-hi="${i}" data-hkey="pct" value="${escAttr(h.pct)}"></div>
        <div class="field"><label for="${hid(i,'monto')}">${L({es:'Cantidad',en:'Amount',id:'Jumlah'})}</label><input id="${hid(i,'monto')}" data-hi="${i}" data-hkey="monto" value="${escAttr(h.monto)}"></div>
        <div class="field"><label for="${hid(i,'fecha')}">${L({es:'Vencimiento',en:'Due date',id:'Jatuh tempo'})}</label>
          <input id="${hid(i,'fecha')}" type="date" data-hi="${i}" data-hkey="fecha" value="${escAttr(h.fecha||'')}">
          ${!h.fecha && h.timing ? `<span style="display:block;font-size:11px;color:var(--muted);margin-top:3px">${L({es:'Este contrato decía',en:'This contract said',id:'Kontrak ini menyebut'})}: «${esc(h.timing)}»</span>` : ''}
        </div>
        <div class="field"><label for="${hid(i,'es')}">${L({es:'Texto (Español)',en:'Text (Spanish)',id:'Teks (Spanyol)'})}</label><input id="${hid(i,'es')}" data-hi="${i}" data-hkey="es" value="${escAttr(h.es)}"></div>
        <div class="field"><label for="${hid(i,'en')}">${L({es:'Texto (English)',en:'Text (English)',id:'Teks (Inggris)'})}</label><input id="${hid(i,'en')}" data-hi="${i}" data-hkey="en" value="${escAttr(h.en)}"></div>
        <div class="field"><label for="${hid(i,'id')}">${L({es:'Texto (Bahasa)',en:'Text (Bahasa)',id:'Teks (Bahasa)'})}</label><input id="${hid(i,'id')}" data-hi="${i}" data-hkey="id" value="${escAttr(h.id)}"></div>
      </div>
    </div>`).join('');
  const total = HITOS.reduce((t,h)=>t+(parseFloat(h.pct)||0),0);
  return rows + `<div class="dz-row" style="margin-top:10px">
    <button type="button" class="btn ghost" id="hitoAdd">+ ${L({es:'Añadir hito',en:'Add milestone',id:'Tambah tahap'})}</button>
    <span class="spacer" style="flex:1"></span>
    <span style="font-size:12px;color:${Math.round(total)===100?'var(--muted)':'var(--be)'}">Σ ${total}%</span>
  </div>`;
}
function refreshHitos(){ const b=$('[data-sec="pagos"] .body'); if(b) b.innerHTML=hitosBodyHTML(); }
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
