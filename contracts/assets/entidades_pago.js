/* ═══════════════════════════════════════════════════════════════════════════
   A QUIÉN SE PAGA: cuenta bancaria y sociedad firmante
   Sale de contracts/app.html el 21-ago-2026.
   ═══════════════════════════════════════════════════════════════════════════
   Los datos NO están aquí: viven en `assets/entities.js` (CUENTAS_BANCARIAS y
   SOCIEDADES), que es la fuente única que comparten Contratos y Facturas. Esto
   es solo cómo se eligen y cómo se imprimen.

   ⚠️ Por eso este fichero tiene que cargarse DESPUÉS de entities.js: hay una
   constante que se calcula al cargar (SOCIEDAD_OPTIONS) y lee SOCIEDADES. Si se
   pone antes, sale vacía y el desplegable de sociedad firmante aparece sin
   opciones — sin ningún error.
   ═══════════════════════════════════════════════════════════════════════════ */
/* ---------- cuenta bancaria: desplegable único reusado en varias plantillas ----------
   Las cuentas se cargan de `public.cuentas_bancarias` con cargarCuentasBancarias()
   (assets/entities.js) — desde el 6-ago-2026 ya NO están escritas en ese fichero,
   que es público por web y por el repo de GitHub. Cada plantilla que necesita
   destino de pago trae <!--datos-bancarios--> (ver buildDoc); el agente elige la
   cuenta en el select 'cuenta_bancaria' y aquí se resuelve a la tabla completa.
   Sin selección → no imprime nada: nunca un valor por defecto adivinado en algo
   tan sensible.

   `bankOptions()` es una FUNCIÓN y no una constante calculada al cargar: las
   cuentas llegan por red, así que una constante de módulo se quedaba con la lista
   vacía para toda la sesión según qué ganara la carrera. */
const bankOptions = () => Object.entries(CUENTAS_BANCARIAS).map(([v,c])=>[v,c.label])
  .sort((a,b)=>a[1].localeCompare(b[1],'es'));   // orden alfabético por etiqueta
// Construcción usa SOLO la cuenta de Sandal Woods (Singapur). Las cuentas de
// notario son de ESCROW: al elegir una, datosBancariosHTML imprime sola la
// declaración "depósito en garantía", que solo tiene sentido donde el contrato
// pacta escrow notarial (Reserva de Parcela). Ofrecerlas en los demás invita a
// mandar el dinero al sitio equivocado con una cláusula que nadie pactó.
// Construcción cobra por cuatro vías: la cuenta de Sandal Woods (Singapur), la de
// SAN DAL WOODS en Danamon EUR (23-jul, disponible en todos los contratos) y, para
// las operaciones de Sumba, el escrow del notario y la cuenta del constructor en
// euros (añadidas 22-jul a petición del cliente).
const BANCOS_CONSTRUCCION = ['sandalwoods_dbs_sg', 'sandalwoods_danamon_eur', 'notario_sandy_sumba', 'contractor_sumba_eur'];
function bankOptionsFor(slug){
  const opts = bankOptions();
  if(slug==='ppjb_construccion') return opts.filter(o=>BANCOS_CONSTRUCCION.includes(o[0]));
  if(slug==='ppjb_parcela') return opts;
  return opts.filter(o=>!o[0].startsWith('notario_'));
}
/* ---------- sociedad firmante (Promotor/Constructor): desplegable por contrato ----------
   Las plantillas tokenizadas traen la identidad como {{prom_razon}}, {{prom_marca}}
   (envuelta en <!--opt:prom_marca--> → si la sociedad no tiene marca, la cláusula
   desaparece), {{prom_domicilio}}, {{prom_npwp}}, {{prom_rep}} y el crédito del
   firmante por idioma {{prom_cred_es/en/id}} (nacionalidad + documento, que cambia
   según sea ID indonesio o pasaporte extranjero). El select 'sociedad_firmante'
   elige la sociedad; applyPromotor() rellena esos marcadores en buildDoc. La firma
   gráfica de Lawang solo sale para Tepi Sun Gai (<!--if:sociedad_firmante=tepi_sungai-->
   en las plantillas); las demás dejan línea en blanco para firmar a mano.
   Añadir una sociedad = un bloque más aquí, cero cambios en plantillas. */
// (SOCIEDADES vive en assets/entities.js — compartido con /facturas)
// soloFacturas (12-ago): gate para una sociedad sin rep/cred todavía — sin
// eso applyPromotor() firmaría un contrato con huecos en blanco. Hoy NINGUNA
// sociedad lo lleva (sandal_woods_ltd lo tuvo mientras le faltaba el
// representante, 12-ago, y se le quitó al rellenarlo — ver entities.js).
// ⚠️ Este filtro NO cubre el otro hallazgo abierto sobre sandal_woods_ltd:
// las 9 plantillas de contrato declaran al Promotor "sociedad de
// nacionalidad Indonesia", falso para esa Ltd de Hong Kong. No hay
// mecanismo que lo bloquee — quien la elija para FIRMAR un contrato real
// (no solo para facturar) tiene que corregir esa frase a mano en el
// documento antes de imprimirlo.
const SOCIEDAD_OPTIONS = Object.entries(SOCIEDADES).filter(([,c])=>!c.soloFacturas).map(([v,c])=>[v, c.label]);   // orden de inserción: Tepi Sun Gai primero (default)
function applyPromotor(data){
  const key = data.sociedad_firmante || (CURRENT && SOCIEDAD_DEFAULT[CURRENT.slug]) || 'tepi_sungai';   // vacío → default de la plantilla (o Tepi Sun Gai)
  const soc = SOCIEDADES[key] || SOCIEDADES.tepi_sungai;
  data.prom_razon=soc.razon; data.prom_marca=soc.marca||''; data.prom_domicilio=soc.domicilio;
  data.prom_npwp=soc.npwp; data.prom_rep=soc.rep;
  // opcionales: si la sociedad no los tiene, el <!--opt:--> de la plantilla
  // borra la frase entera en vez de imprimir el marcador
  data.prom_nib=soc.nib||''; data.prom_rep_npwp=soc.rep_npwp||'';
  // soc.cred llega de cargarFirmantesCred() (entities.js, tabla con RLS) — si
  // esa carga falló, soc.cred queda sin poner: mismo criterio que el resto de
  // opcionales de aquí arriba, en vez de reventar el documento entero.
  const credProm = soc.cred || {es:'',en:'',id:''};
  data.prom_cred_es=credProm.es; data.prom_cred_en=credProm.en; data.prom_cred_id=credProm.id;
  // Firmante (10-ago): "Gestión del contrato" solo guardaba quién firma sin que
  // se imprimiera en ningún sitio — a petición del cliente, ahora SÍ decide el
  // nombre y las credenciales personales que salen en {{prom_rep}}/{{prom_cred_*}}
  // (comparecencia + bloque de firma), igual en las nueve plantillas que ya
  // imprimen {{prom_razon}}. Si coincide con el representante por defecto de la
  // sociedad elegida, no hay nada que sobrescribir. Si es otro, se buscan SUS
  // credenciales propias (nacionalidad/documento) en FIRMANTES_CRED, no las de
  // la sociedad — mismo caso que ya anticipaba el comentario de
  // SOCIEDADES.tepi_sungai.rep: "si algún documento concreto lo firma otra
  // persona, va escrito EN ESE documento, no aquí". La identidad de la
  // sociedad (razón, domicilio, NPWP, marca) no cambia: sigue siendo la que se
  // firma, solo cambia QUIÉN la representa hoy.
  // ⚠️ 11-ago-2026: esto buscaba antes `Object.values(SOCIEDADES).find(s =>
  // s.rep === data.firmante)` — funcionaba mientras cada nombre siguiera
  // siendo el rep ACTUAL de alguna sociedad. Al cambiar tepi_sungai.rep, un
  // contrato ya creado con el rep anterior dejaba de encontrar a nadie y el
  // documento imprimía en silencio al rep nuevo (hallazgo Legal, contratos
  // CC00020/CC00019/RP00031/CR00018). FIRMANTES_CRED (entities.js) desacopla
  // esto: guarda a cualquiera que YA pudo aparecer firmando, no solo al rep
  // vigente de hoy.
  if(data.firmante && data.firmante !== soc.rep){
    const otro = FIRMANTES_CRED[data.firmante];
    if(otro){
      data.prom_rep = data.firmante;
      data.prom_rep_npwp = otro.rep_npwp || '';
      data.prom_cred_es = otro.cred.es; data.prom_cred_en = otro.cred.en; data.prom_cred_id = otro.cred.id;
    }
    // si `otro` no está (nombre no reconocido, o cargarFirmantesCred() falló y
    // FIRMANTES_CRED sigue vacío), se queda con lo de soc de arriba: nunca en
    // blanco a medias entre el firmante pedido y el por defecto.
  }
}
/* etiqueta legible del régimen de tenencia (el select guarda un código; el contrato
   imprime esto — ver buildDoc). Los bloques <!--if:regimen_tenencia=CODE--> siguen
   usando el código crudo, no se ven afectados. */
const REGIMEN_LABEL = { hgb:'HGB (Hak Guna Bangunan)', leasehold:'Hak Sewa (Leasehold)', hak_milik:'Hak Milik (SHM)' };
/* Tabla de UNA cuenta, por su clave. Sale de datosBancariosHTML() para poder
   pintar también las cuentas FIJAS de una plantilla (ver el marcador
   <!--cuenta:CLAVE--> en buildDoc): los dos documentos del C2 de Bonian llevan
   DOS cuentas a propósito —el escrow del notario para el hito 1 y la de empresa
   para los hitos 2 a 8— y el select de contrato solo da una.
   `o.titulo`: cabecera «Datos bancarios». Las plantillas que ya traen su propio
   epígrafe numerado la piden a false.
   `o.escrow`: la fila «Naturaleza de la cuenta … ESCROW» que se añade sola a las
   claves `notario_*`. A false donde el texto del contrato ya lo declara en prosa
   —como el C2— para no meter una frase nueva en un documento legal sin que nadie
   la haya pedido.
   `o.clase`: clase de la tabla, para respetar la maqueta de cada plantilla. */
function tablaCuentaHTML(key, o){
  o = o || {};
  const c = CUENTAS_BANCARIAS[key];
  if(!c) return '';
  // val puede ser un dato (número de cuenta, dirección…) o un texto con palabras.
  // Si lleva palabras se pasa como {es,en,id} y se imprime en los tres idiomas,
  // como la etiqueta: si no, al cambiar a inglés la fila salía en español.
  const celda = v => (v && typeof v === 'object')
    ? `<span data-lang="es">${esc(String(v.es||''))}</span><span data-lang="en">${esc(String(v.en||v.es||''))}</span><span data-lang="id">${esc(String(v.id||v.es||''))}</span>`
    : esc(String(v));
  const row=(esL,enL,idL,val)=> !val ? '' : `<tr><td><span data-lang="es">${esL}</span><span data-lang="en">${enL}</span><span data-lang="id">${idL}</span></td><td>${celda(val)}</td></tr>`;
  // Cuentas de notario (clave notario_*) = depósito en garantía (ESCROW). Se añade
  // una fila que lo declara. ponytail: título/valor por defecto — el cliente puede
  // afinar el texto exacto aquí sin tocar nada más.
  const esNotario = key.startsWith('notario_');
  const filaNotario = (esNotario && o.escrow !== false)
    ? row('Naturaleza de la cuenta','Account type','Jenis rekening', {
        es:'Cuenta ESCROW de notario designado — depósito en garantía',
        en:'ESCROW account of the appointed notary — funds held in escrow',
        id:'Rekening ESCROW notaris yang ditunjuk — dana dititipkan pada rekening penampungan (escrow)' })
    : '';
  const titulo = o.titulo === false ? ''
    : `<h2><span data-lang="es">Datos bancarios</span><span data-lang="en">Bank details</span><span data-lang="id">Rincian bank</span></h2>`;
  return `${titulo}
    <table class="${o.clase || 'pays'}"><tbody>
      ${filaNotario}
      ${row('Titular','Account holder','Pemegang rekening', c.titular)}
      ${row('Banco','Bank','Bank', c.banco)}
      ${row('Número de cuenta','Account number','Nomor rekening', c.cuenta)}
      ${row('Código Swift / Routing','Swift / Routing code','Kode Swift / Routing', c.codigo)}
      ${row('Domicilio del banco','Bank address','Alamat bank', c.direccion)}
      ${row('Nota','Note','Catatan', c.extra)}
    </tbody></table>`;
}
/* la cuenta que el agente ELIGE en el select del contrato */
function datosBancariosHTML(){ return tablaCuentaHTML(collect().cuenta_bancaria, {}); }

/* acordeón: click en la cabecera pliega/despliega (e inicializa pads al abrir) */
function wireAccordions(){
  document.querySelectorAll('#form [data-acc]').forEach(h=>{
    if(h._acc) return; h._acc=1;
    h.addEventListener('click', e=>{
      if(e.target.closest('.switch')||e.target.closest('.opt-toggle')) return;  // no plegar al togglear opcional
      const sec=h.closest('.section'); sec.classList.toggle('collapsed');
      if(!sec.classList.contains('collapsed')) ensurePads(sec);
    });
  });
}

/* pads de firma: init sólo cuando el canvas es visible (si no, mide 0) */
function ensurePads(root){ root.querySelectorAll('.section:not(.collapsed):not(.off) .sigpad-wrap:not([data-init])').forEach(w=>{ w.setAttribute('data-init','1'); initPad(w); }); }

/* toggle de idioma → re-etiqueta campos, conserva valores y firmas */
function applyLang(){
  SECTIONS.forEach(s=>{
    const sec=$(`[data-sec="${s.id}"]`); if(!sec) return;
    sec.querySelector('h2').textContent = L(s.title);
    s.fields.forEach(f=>{
      const el = sec.querySelector(`[name="${f[0]}"]`);
      const lab = el ? el.closest('.field').querySelector('label')
                     : sec.querySelector(`.field[data-key="${f[0]}"] label`);
      if(lab) lab.textContent = L(f[1]);
    });
  });
  document.querySelectorAll('#langToggle button').forEach(b=> b.classList.toggle('on', b.dataset.l===LANG));
  refreshHitos();   // re-etiqueta la UI de hitos (los valores viven en HITOS, no se pierden)
  render();
}
