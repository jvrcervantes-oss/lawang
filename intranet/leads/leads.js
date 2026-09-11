/* CRM de leads de Meta — Lawang, 9-sep-2026.
   ============================================================================
   Cuatro vistas sobre los mismos datos: Pipeline (el tablero), Bandeja (el hilo
   de cada lead), Campañas (qué trae cada anuncio) y Automatismos (qué hace solo
   el vigilante del estudio).

   TODO PASA POR FUNCIONES DE LA BASE, ninguna consulta directa a `leads`. Esa
   tabla lleva la columna `ip` de 32 personas y la mantiene R13 con un upsert
   cada 4 h; servirla por policy publicaría sola cualquier columna que se añada
   mañana. Las funciones (`crm_*`) devuelven columnas escritas a mano y
   revalidan el permiso dentro.

   EL CONTACTO NO VIAJA EN EL LISTADO. Email y teléfono se piden de uno en uno
   con `crm_lead_contacto`, y esa llamada DEJA RASTRO en `lead_acceso_log`. Es
   deliberado: hasta hoy quedaba constancia de quién movía una tarjeta pero no
   de quién sacaba una agenda de 103 contactos, y esta familia de datos ya tuvo
   una fuga (el leads.csv de Sumba Hills, público del 15 al 27-jul).

   TEXTO DE ORIGEN AJENO. `name`, `email`, `whatsapp` y las respuestas los
   escribe un tercero en un formulario público. Se pintan SIEMPRE escapados, y
   los enlaces se construyen validando el esquema: un `javascript:` en un campo
   de nombre se ejecutaría con la sesión de un admin de la suite.
   ========================================================================== */
const $ = s => document.querySelector(s);

let SB = null, YO = null;
let LEADS = [], ETAPAS = [], CAMPANAS = [], SERIE = [], ACCIONES = [];
let VISTA = 'pipeline';
let CANAL = '', BUSCA = '', FILTRO_B = 'todos';
let ABIERTAS = new Set(), ABIERTO = null, SEL_B = null;
let CARGADO = { panel: false, automatismos: false, setter: false, agenda: false };
let FICHA = null;
let CONVERSACIONES = [], CITAS = [], EDITANDO_CITA = null;

/* Las seis columnas. El orden es el del embudo y no se reordena: la posición
   de una tarjeta ES la información. */
const COLS = [
  ['nuevo',      'Nuevo',      'Acaba de entrar, nadie lo ha tocado'],
  ['contactado', 'Contactado', 'Se le ha escrito o llamado'],
  ['visita',     'Visita',     'Ha visto el terreno o la villa'],
  ['reserva',    'Reserva',    'Carta de reserva firmada'],
  ['contrato',   'Contrato',   'Contrato de compraventa firmado'],
  ['perdido',    'Perdido',    'No sigue adelante'],
];
const COLOR_COL = { nuevo:'#64748B', contactado:'#1D4ED8', visita:'#0F766E',
                    reserva:'#D97706', contrato:'#064E3B', perdido:'#94A3B8' };

/* Nombre legible de cada origen. La lista se queda corta a propósito con un
   canal nuevo: `canal()` devuelve la clave cruda, que es fea pero cierta. */
const NOMBRES = {
  'meta-sumbahills':      'Sumba Hills · Meta',
  'meta-lawang-bali':     'Lawang Bali · Meta',
  'meta-lawang-australia':'Australia · Meta',
  'sumba-hills-qr':       'Sumba Hills · QR',
  'sumbahills-web':       'Sumba Hills · web',
};
const canal = s => NOMBRES[s] || s || 'sin origen';

/* Un solo umbral y un solo acento. Un semáforo de tres colores en una tarjeta
   pequeña no se lee: se convierte en decoración. */
const DIAS_VIEJO = 14;
const TOPE = 20;

/* Etiquetas de las respuestas del formulario. La base ya recorta a estas cuatro
   claves (las de opción cerrada); aquí solo se les pone nombre en castellano. */
const PREGUNTA = {
  budget_range: 'Presupuesto', budget: 'Presupuesto',
  buy_timeline: 'Cuándo compra', purpose: 'Para qué',
};

/* ---------- utilidades ---------- */
/* `esc` y `toast` vienen de suite-comun.js (se carga antes en index.html). NO
   redeclarar aqui: dos `const`/`function` del mismo nombre en el mismo scope
   global revientan el script entero con «Identifier ya declarado» y ninguna
   de las cuatro vistas llega a pintarse (incidente 10-sep-2026). */
const dias = iso => { const d = new Date(iso); return isNaN(d) ? null : Math.floor((Date.now() - d) / 864e5); };
const fecha = iso => { const d = new Date(iso); return isNaN(d) ? (iso || '')
  : d.toLocaleDateString('es-ES', { day:'numeric', month:'short', year:'numeric' }); };
const fechaHora = iso => { const d = new Date(iso); return isNaN(d) ? (iso || '')
  : d.toLocaleString('es-ES', { day:'2-digit', month:'short', hour:'2-digit', minute:'2-digit' }); };
const edad = d => d === null ? '' : (d === 0 ? 'hoy' : d === 1 ? 'ayer' : d + ' días');
/* Sin proveedor de tipo de cambio: se pinta la moneda que devuelve Meta, tal
   cual. Un importe convertido a ojo es peor que un importe en rupias. */
const dinero = (n, mon) => n == null ? '—'
  : new Intl.NumberFormat('es-ES', { maximumFractionDigits: 0 }).format(Number(n)) + (mon ? ' ' + mon : '');

/* Un `href` construido con texto de un tercero. Solo se dejan pasar los tres
   esquemas que esta herramienta usa; cualquier otra cosa devuelve null y el
   botón no se pinta. */
function enlaceSeguro(url){
  try {
    const u = new URL(url, location.origin);
    return ['https:', 'mailto:', 'tel:'].includes(u.protocol) ? u.href : null;
  } catch(e){ return null; }
}

/* ---------- navegación entre vistas ---------- */
function ir(v){
  VISTA = v;
  document.querySelectorAll('.crm-nav button').forEach(b =>
    b.setAttribute('aria-selected', String(b.dataset.v === v)));
  document.querySelectorAll('.crm-vista').forEach(s =>
    s.hidden = s.id !== 'v-' + v);
  if(v === 'panel' && !CARGADO.panel) cargarPanel();
  if(v === 'automatismos' && !CARGADO.automatismos) cargarAutomatismos();
  if(v === 'bandeja') pintarBandeja();
  if(v === 'hoy') cargarHoy();
  if(v === 'setter' && !CARGADO.setter) cargarSetter();
  if(v === 'agenda' && !CARGADO.agenda) cargarAgenda();
}

/* ==========================================================================
   VISTA 0 — HOY (lo que toca hacer)
   --------------------------------------------------------------------------
   Es la primera pestaña a propósito: el tablero dice en qué punto está cada lead, pero
   la pregunta con la que un comercial abre el panel por la mañana es otra — "¿a quién
   tengo que llamar hoy?". Sin esto, la disciplina de seguimiento vive en su cabeza.
   Vencidas y de hoy, nunca el futuro: una lista que incluye "la semana que viene" deja de
   ser una lista de trabajo y se vuelve un calendario que nadie mira.
   Quién decide el día es la BASE (`crm_agenda`, en hora de Bali), no el navegador de quien
   mira: el estudio abre esto desde España y vería el día cambiado.
   ========================================================================== */
let HOY = [], SOLO_MIAS = false;

/* La cuenta de la pestaña se recalcula desde LEADS, que es la lista que ya está en memoria
   y la que se actualiza al poner o cerrar una tarea. Se llama desde los CUATRO sitios que
   cambian una tarea (guardar y cerrar desde la ficha, cerrar desde «Hoy», y la carga
   inicial): si se dejara solo en el arranque, la pestaña diría 2 mientras la pantalla
   enseña 3, que es exactamente lo que pasaba antes de esta línea. */
function actualizarCuentaHoy(){
  const n = LEADS.filter(l => l.accion_cuando && diasHasta(l.accion_cuando) <= 0).length;
  $('#c-hoy').textContent = n;
}

async function cargarHoy(){
  const caja = $('#listaHoy');
  caja.innerHTML = '<p class="vacio">Cargando…</p>';
  const { data, error } = await SB.rpc('crm_agenda', { p_solo_mias: SOLO_MIAS });
  if(error){ caja.innerHTML = '<p class="vacio">No se pudo leer la agenda: ' + esc(error.message) + '</p>'; return; }
  HOY = data || [];
  pintarHoy();
}

function pintarHoy(){
  const vencidas = HOY.filter(a => a.dias_de_retraso > 0).length;
  $('#kpis-hoy').innerHTML = `
    <div class="kpi fuerte"><div class="rot">Para hoy<i class="ph ph-flag"></i></div>
      <p class="cifra">${HOY.length}</p><p class="pie">${SOLO_MIAS ? 'tuyas' : 'de todo el equipo'}</p></div>
    <div class="kpi"><div class="rot">Con retraso<i class="ph ph-warning-circle"></i></div>
      <p class="cifra oro">${vencidas}</p><p class="pie">deberían estar hechas</p></div>`;

  const caja = $('#listaHoy');
  if(!HOY.length){
    caja.innerHTML = `<p class="vacio">Nada pendiente para hoy.${
      SOLO_MIAS ? ' Prueba a mirar las de todo el equipo.' : ' El próximo paso se pone desde la ficha de cada lead.'}</p>`;
    return;
  }
  caja.innerHTML = HOY.map(a => `
    <article class="cita${a.dias_de_retraso > 0 ? ' urge' : ''}" data-lead="${esc(a.lead_id)}">
      <div class="avatar">${esc(iniciales(a.nombre))}</div>
      <div class="cuerpo">
        <div class="cuando">${a.dias_de_retraso > 0
          ? esc(a.dias_de_retraso + (a.dias_de_retraso === 1 ? ' día de retraso' : ' días de retraso'))
          : 'Hoy'}</div>
        <div class="quien">${esc(a.nombre || 'sin nombre')}</div>
        <div class="sub">${esc(a.que)} · ${esc(canal(a.source))}${
          SOLO_MIAS ? '' : ' · ' + esc(a.responsable || '')}</div>
      </div>
      <div class="acciones">
        <button class="btn mini" data-abrir="${esc(a.lead_id)}">Abrir ficha</button>
        <button class="btn mini pri" data-hecho="${esc(a.accion_id)}"><i class="ph ph-check"></i>Hecho</button>
      </div>
    </article>`).join('');

  caja.querySelectorAll('[data-abrir]').forEach(b => b.onclick = ev => {
    ev.stopPropagation();
    abrirFicha(LEADS.find(x => x.id === b.dataset.abrir));
  });
  caja.querySelectorAll('[data-hecho]').forEach(b => b.onclick = async ev => {
    ev.stopPropagation();
    b.disabled = true;
    const { error } = await SB.rpc('crm_lead_accion_completar', { p_accion: b.dataset.hecho });
    if(error){ toast('No se pudo cerrar: ' + error.message); b.disabled = false; return; }
    const fila = HOY.find(a => a.accion_id === b.dataset.hecho);
    const lead = fila && LEADS.find(x => x.id === fila.lead_id);
    if(lead){ lead.accion_id = lead.accion_que = lead.accion_cuando = lead.accion_responsable = null; }
    HOY = HOY.filter(a => a.accion_id !== b.dataset.hecho);
    pintarHoy(); pintarPipeline(); actualizarCuentaHoy();
  });
}

/* ==========================================================================
   CARGA
   ========================================================================== */
async function cargar(){
  const btn = $('#btnRefrescar'); btn.disabled = true;
  try {
    const [l, e] = await Promise.all([
      SB.rpc('crm_leads'),
      SB.from('contrato_tipo_etapa').select('tipo,etapa'),
    ]);
    if(l.error) throw l.error;
    LEADS  = l.data || [];
    ETAPAS = e.error ? [] : (e.data || []);
    pintarPipeline();
    pintarBandeja();
    if(VISTA === 'panel') cargarPanel();
  } catch(err){
    toast('No se pudieron leer los leads: ' + (err.message || err));
    $('#tablero').innerHTML = '<p class="vacio">No se pudo leer la lista. Recarga la página.</p>';
  } finally { btn.disabled = false; }
}

/* ==========================================================================
   VISTA 1 — PIPELINE
   ========================================================================== */
/* Quién soy, para «mis leads». Sale de la sesión, no de un campo editable. */
const yoSoy = () => (YO && YO.email ? YO.email.toLowerCase() : '');
const esMio = l => !!l.dueno && l.dueno.toLowerCase() === yoSoy();

/* Tres filtros de propiedad, no dos. «Sin dueño» merece el suyo porque es la bandeja de
   entrada de verdad: hoy son 104 de 107, y son los que cualquiera puede coger. */
let FILTRO_DUENO = 'todos';

function visibles(){
  const q = BUSCA.trim().toLowerCase();
  return LEADS.filter(l => {
    if(CANAL && l.source !== CANAL) return false;
    if(FILTRO_DUENO === 'mios' && !esMio(l)) return false;
    if(FILTRO_DUENO === 'libres' && l.dueno) return false;
    if(!q) return true;
    return (l.name || '').toLowerCase().includes(q);
  });
}

function kpisPipeline(){
  const f = visibles();
  const sin = f.filter(l => l.estado === 'nuevo').length;
  const parados = f.filter(l => l.estado === 'nuevo' && dias(l.estado_desde) >= DIAS_VIEJO).length;
  const cerrados = f.filter(l => l.estado === 'reserva' || l.estado === 'contrato').length;
  const conv = f.length ? Math.round(cerrados / f.length * 1000) / 10 : 0;
  const sug = f.filter(l => l.sugerencia && l.sugerencia !== l.estado).length;
  $('#kpis-pipeline').innerHTML = `
    <div class="kpi"><div class="rot">Leads<i class="ph ph-users"></i></div>
      <p class="cifra">${f.length}</p><p class="pie">${CANAL ? esc(canal(CANAL)) : 'todos los canales'}</p></div>
    <div class="kpi"><div class="rot">Sin contactar<i class="ph ph-envelope-simple"></i></div>
      <p class="cifra">${sin}</p><p class="pie">${parados} llevan más de ${DIAS_VIEJO} días parados</p></div>
    <div class="kpi"><div class="rot">Reserva o contrato<i class="ph ph-signature"></i></div>
      <p class="cifra oro">${cerrados}</p><p class="pie">de ${f.length} leads</p></div>
    <div class="kpi fuerte"><div class="rot">Conversión<i class="ph ph-trend-up"></i></div>
      <p class="cifra">${conv}%</p><p class="pie">llegan a firmar</p></div>
    ${sug ? `<div class="kpi"><div class="rot">Por confirmar<i class="ph ph-flag"></i></div>
      <p class="cifra oro">${sug}</p><p class="pie">han firmado y siguen en otra columna</p></div>` : ''}`;
}

function avisoTipos(){
  /* Comparaba `l.sugerencia` (una ETAPA: 'reserva'/'contrato') contra un Set de
     TIPOS ('ppjb_bonian', 'hak_sewa_notario'…) y por eso disparaba siempre que
     un lead convertía de verdad: ningún tipo real se llama literalmente
     "reserva" ni "contrato", así que la comparación era falsa siempre y el
     aviso rojo salía en producción con cada conversión legítima (4 leads reales
     hoy, verificado 10-sep-2026 contra Supabase). Ese caso NO se puede detectar
     desde aquí con los datos que manda `crm_leads()`: si el tipo firmado no
     está mapeado, el JOIN de la función ni siquiera genera `sugerencia`, así
     que un lead con `sugerencia_contrato` YA tiene tipo mapeado por
     construcción. Lo único que SÍ se puede ver desde el cliente es una fila de
     `contrato_tipo_etapa` con `etapa` vacía. El caso de LAW-151 (un tipo que ni
     siquiera tiene fila) queda pendiente de un cambio en la función SQL. */
  const sin = ETAPAS.filter(e => !e.etapa).map(e => e.tipo);
  const av = $('#avisoTipos');
  if(!sin.length){ av.hidden = true; return; }
  av.hidden = false;
  av.innerHTML = '<b>Hay tipos de contrato sin columna asignada.</b> Quien firme uno de esos '
    + 'no aparecerá sugerido en Reserva ni en Contrato: ' + esc([...new Set(sin)].join(', '))
    + '. Se arregla desde el estudio, añadiendo su fila en <code>contrato_tipo_etapa</code>.';
}

function barraCanales(){
  const canales = [...new Set(LEADS.map(l => l.source))].sort();
  $('#canales').innerHTML = [['', 'Todos']].concat(canales.map(c => [c, canal(c)]))
    .map(([v, t]) => `<button data-c="${esc(v)}" aria-pressed="${v === CANAL}">${esc(t)}`
      + `<span class="n">${v ? LEADS.filter(l => l.source === v).length : LEADS.length}</span></button>`).join('');
}

/* Cuántos días faltan (o sobran) para una fecha, contados en el día de Bali — el mismo
   criterio que usa `crm_agenda()` en la base. Si el navegador de quien mira está en otro
   huso (el estudio, en España), restar por hora local diría "mañana" a algo que en la
   oficina ya es hoy. */
const HOY_BALI = () => {
  const f = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Makassar', year:'numeric', month:'2-digit', day:'2-digit' });
  return f.format(new Date());   // YYYY-MM-DD
};
const diasHasta = iso => {
  if(!iso) return null;
  const a = new Date(iso + 'T00:00:00Z'), b = new Date(HOY_BALI() + 'T00:00:00Z');
  return isNaN(a) ? null : Math.round((a - b) / 864e5);
};
/* Cómo se lee una fecha de tarea: lo que importa es si corre prisa, no la fecha exacta. */
const cuandoTexto = n => n === null ? ''
  : n < -1 ? Math.abs(n) + ' días de retraso'
  : n === -1 ? 'ayer' : n === 0 ? 'hoy' : n === 1 ? 'mañana' : 'en ' + n + ' días';

/* La línea del dueño en la tarjeta. Tres estados y cada uno dice una cosa distinta:
   · sin dueño  → botón «Es mío»: el 97% de las tarjetas hoy, y es la acción que se espera.
   · mío        → nada llamativo, solo el nombre en verde. Si todas las mías gritaran, el
                  tablero entero sería ruido.
   · de otro    → su nombre, gris. Y si esa persona está desactivada, en rojo: ese lead
                  está huérfano de hecho aunque la columna diga lo contrario, y alguien
                  tiene que reasignarlo (hallazgo de Datos: el dueño muere con el usuario). */
function duenoHTML(l){
  if(!l.dueno) return `<button class="btn mini reclamar" data-mio="${esc(l.id)}"><i class="ph ph-hand-grabbing"></i>Es mío</button>`;
  const nombre = l.dueno_nombre || l.dueno;
  if(l.dueno_activo === false)
    return `<div class="duenio malo"><i class="ph ph-warning-circle"></i>${esc(nombre)} · cuenta desactivada</div>`;
  return `<div class="duenio${esMio(l) ? ' yo' : ''}"><i class="ph ph-user"></i>${esc(nombre)}</div>`;
}

function tarjetaHTML(l){
  const d = dias(l.estado_desde), viejo = d !== null && d >= DIAS_VIEJO;
  /* La sugerencia por email es SUPLENTE desde el 11-sep: si hay vínculo explícito, la base
     ya no la manda. Aquí solo se pinta lo que llegue. */
  const sug = l.sugerencia && l.sugerencia !== l.estado
    ? `<button class="sug" data-sug="${esc(l.id)}"><i class="ph ph-signature"></i> Firmó `
      + `${esc(COLS.find(c => c[0] === l.sugerencia)?.[1] || l.sugerencia)}`
      + `${l.sugerencia_contrato ? ' · ' + esc(l.sugerencia_contrato) : ''} — mover ahí</button>`
    : '';
  const presu = l.respuestas && (l.respuestas.budget_range || l.respuestas.budget);
  /* El próximo paso es lo primero que mira un comercial: va arriba del todo y en rojo si
     ya venció. Un lead sin tarea no pinta nada — un hueco vacío en 107 tarjetas es ruido. */
  const n = diasHasta(l.accion_cuando);
  const tarea = l.accion_que
    ? `<div class="tarea${n !== null && n <= 0 ? ' urge' : ''}">
         <i class="ph ${n !== null && n < 0 ? 'ph-warning-circle' : 'ph-flag'}"></i>
         <span class="q">${esc(l.accion_que)}</span>
         <span class="c">${esc(cuandoTexto(n))}</span></div>`
    : '';
  return `<article class="tarjeta${sug ? ' alto' : ''}" draggable="true" data-id="${esc(l.id)}">
    <div class="fila1"><div class="quien">${esc(l.name || 'sin nombre')}</div></div>
    ${tarea}
    <div class="meta">
      <span class="chip meta">${esc(canal(l.source))}</span>
      <span class="${viejo ? 'viejo' : ''}">${esc(edad(d))}</span>
      ${l.notas ? `<span><i class="ph ph-note"></i> ${l.notas}</span>` : ''}
    </div>
    ${presu || l.contrato_numero ? `<div class="meta">
      ${presu ? `<span class="chip oro">${esc([].concat(presu)[0])}</span>` : ''}
      ${l.contrato_numero ? `<span class="chip verde"><i class="ph ph-file-text"></i>${esc(l.contrato_numero)}</span>` : ''}
    </div>` : ''}
    ${duenoHTML(l)}
    ${sug}</article>`;
}

function pintarPipeline(){
  kpisPipeline(); avisoTipos(); barraCanales();
  const filas = visibles();
  $('#tablero').innerHTML = COLS.map(([k, rotulo, pie]) => {
    const mias = filas.filter(l => (l.estado || 'nuevo') === k);
    const ver = ABIERTAS.has(k) ? mias : mias.slice(0, TOPE);
    return `<section class="lane" data-col="${k}">
      <h3><span class="punto" style="background:${COLOR_COL[k]}"></span>${rotulo}<b>${mias.length}</b></h3>
      <p class="sub">${esc(pie)}</p>
      <div class="pila">${ver.map(tarjetaHTML).join('') || '<p class="vacio">—</p>'}</div>
      ${mias.length > ver.length ? `<button class="mas" data-mas="${k}">Ver las ${mias.length}</button>` : ''}
    </section>`;
  }).join('');
  cablearTablero();
}

function cablearTablero(){
  const t = $('#tablero');
  t.querySelectorAll('[data-mas]').forEach(b => b.onclick = () => { ABIERTAS.add(b.dataset.mas); pintarPipeline(); });
  t.querySelectorAll('[data-sug]').forEach(b => b.onclick = ev => {
    ev.stopPropagation();
    const l = LEADS.find(x => x.id === b.dataset.sug);
    if(l) mover(l, l.sugerencia);
  });
  t.querySelectorAll('[data-mio]').forEach(b => b.onclick = ev => {
    ev.stopPropagation();   // sin esto, reclamar abriría además la ficha
    asignar(LEADS.find(x => x.id === b.dataset.mio), yoSoy());
  });
  t.querySelectorAll('.tarjeta').forEach(c => {
    c.onclick = () => abrirFicha(LEADS.find(x => x.id === c.dataset.id));
    c.ondragstart = ev => { ev.dataTransfer.setData('text/plain', c.dataset.id); c.classList.add('arrastrando'); };
    c.ondragend = () => c.classList.remove('arrastrando');
  });
  t.querySelectorAll('.lane').forEach(col => {
    col.ondragover  = ev => { ev.preventDefault(); col.classList.add('sobre'); };
    col.ondragleave = () => col.classList.remove('sobre');
    col.ondrop = ev => {
      ev.preventDefault(); col.classList.remove('sobre');
      const l = LEADS.find(x => x.id === ev.dataTransfer.getData('text/plain'));
      if(l && (l.estado || 'nuevo') !== col.dataset.col) mover(l, col.dataset.col);
    };
  });
}

/* ---------- mover una tarjeta ---------- */
/* ---------- cambiar de dueño ----------
   Un solo camino para las tres cosas (reclamar, ceder, soltar): la base ya distingue los
   tres casos y devuelve un error distinto en cada uno, así que la pantalla no repite esa
   lógica — solo enseña lo que diga la base. Duplicarla aquí sería tener la regla en dos
   sitios, y es la familia de fallo que este repo ya tiene documentada de sobra.
   `p_previo` es el dueño que esta pantalla tenía pintado: si alguien lo cambió entre medias
   llega un 409 y se recarga en vez de pisarlo. */
async function asignar(lead, email){
  if(!lead) return;
  const previo = lead.dueno || null;
  try {
    const { data, error } = await SB.rpc('crm_lead_asignar', {
      p_lead: lead.id, p_email: email || null, p_previo: previo,
    });
    if(error){
      if(String(error.code) === '409' || /ya no esta como lo tenias/i.test(error.message || '')){
        toast('Ese lead ha cambiado de manos mientras mirabas. Recargo.');
        return cargar();
      }
      throw error;
    }
    const fila = (data || [])[0] || {};
    lead.dueno = fila.responsable || null;
    lead.responsable = fila.responsable || null;
    /* El nombre lo resuelve la base en la siguiente vuelta, pero dejar el correo mientras
       tanto hace que la tarjeta recién reclamada se vea distinta de las demás. Se rellena
       con lo que ya sabemos —mi propia ficha, o el equipo si se llegó a cargar— y si no
       hay nada, el correo, que al menos siempre es cierto. */
    lead.dueno_nombre = !fila.responsable ? null
      : (fila.responsable.toLowerCase() === yoSoy() && FICHA && FICHA.nombre) ? FICHA.nombre
      : ((EQUIPO || []).find(u => u.email.toLowerCase() === fila.responsable.toLowerCase()) || {}).nombre
        || fila.responsable;
    lead.dueno_activo = fila.responsable ? true : null;
    toast(!fila.responsable ? 'Lead devuelto al montón.'
      : (fila.responsable.toLowerCase() === yoSoy() ? 'Ya es tuyo.' : 'Asignado a ' + fila.responsable));
    pintarPipeline(); pintarBandeja();
    if(ABIERTO && ABIERTO.id === lead.id) abrirFicha(lead);
  } catch(err){
    toast('No se pudo cambiar el dueño: ' + (err.message || err));
  }
}

async function mover(lead, estado){
  const previo = { estado: lead.estado, desde: lead.estado_desde };
  lead.estado = estado;                       // optimista: la tarjeta se mueve ya
  pintarPipeline(); pintarBandeja();
  try {
    const { data, error } = await SB.rpc('crm_lead_mover', {
      p_lead: lead.id, p_estado: estado, p_desde: previo.desde,
    });
    if(error){
      /* PT409 llega como HTTP 409: alguien movió la tarjeta mientras se
         arrastraba. No se pisa: se recarga y se dice. */
      if(String(error.code) === '409' || /movido otra persona/i.test(error.message || '')){
        toast('Esa tarjeta la ha movido otra persona. Recargo la lista.');
        return cargar();
      }
      throw error;
    }
    const fila = (data || [])[0];
    if(fila){ lead.estado = fila.estado; lead.estado_desde = fila.estado_desde; lead.responsable = fila.responsable; }
    pintarPipeline(); pintarBandeja();
    if(ABIERTO && ABIERTO.id === lead.id) abrirFicha(lead);
  } catch(err){
    lead.estado = previo.estado; lead.estado_desde = previo.desde;
    pintarPipeline(); pintarBandeja();
    toast('No se pudo guardar el cambio: ' + (err.message || err));
  }
}

/* ==========================================================================
   FICHA DEL LEAD (cajón lateral) — la usan Pipeline y Bandeja
   ========================================================================== */
function cerrarFicha(){ document.querySelectorAll('.velo,.cajon').forEach(x => x.remove()); ABIERTO = null; }
document.addEventListener('keydown', e => { if(e.key === 'Escape') cerrarFicha(); });

function abrirFicha(l){
  if(!l) return;
  cerrarFicha(); ABIERTO = l;
  const r = l.respuestas || {};
  const extras = Object.keys(r).map(k =>
    `<div class="dato"><span>${esc(PREGUNTA[k] || k)}</span><b>${esc([].concat(r[k] || [])[0])}</b></div>`).join('');

  const velo = document.createElement('div'); velo.className = 'velo'; velo.onclick = cerrarFicha;
  const c = document.createElement('aside'); c.className = 'cajon';
  c.innerHTML = `
    <header>
      <button class="cerrar" aria-label="Cerrar">&times;</button>
      <h2>${esc(l.name || 'sin nombre')}</h2>
      <div class="meta" style="margin-top:8px;display:flex;gap:7px;flex-wrap:wrap">
        <span class="chip meta">${esc(canal(l.source))}</span>
        <span class="chip gris">Entró ${esc(fecha(l.created_at))}</span>
        ${l.responsable ? `<span class="chip verde">${esc(l.responsable)}</span>` : ''}
      </div>
    </header>
    <div class="cuerpo">
      <p class="lb">Contacto</p>
      <div id="contacto">
        <p style="font-size:13px;color:var(--mist);margin:0 0 10px">
          ${l.tiene_email || l.tiene_whatsapp
            ? 'Queda registrado quién consulta los datos de contacto y cuándo.'
            : 'Este lead no dejó ni email ni teléfono.'}</p>
        ${l.tiene_email || l.tiene_whatsapp
          ? '<button class="btn pri" id="verContacto"><i class="ph ph-eye"></i>Ver contacto</button>' : ''}
      </div>
      ${extras ? `<p class="lb">Qué contestó en el formulario</p>${extras}` : ''}

      <p class="lb">Quién lo lleva</p>
      <div id="duenoFicha"></div>

      <p class="lb">Próximo paso</p>
      <div id="proximoPaso"></div>

      <p class="lb">Venta</p>
      <div id="haciaContrato"></div>

      <p class="lb">Estado</p>
      <div class="acciones" id="estados" style="display:flex;gap:6px;flex-wrap:wrap">
        ${COLS.map(([k, n]) => `<button class="btn mini" data-e="${k}"
          ${(l.estado || 'nuevo') === k ? 'style="background:var(--primary);border-color:var(--primary);color:#fff"' : ''}
          >${n}</button>`).join('')}
      </div>
      <p class="lb">Notas del equipo</p>
      <textarea id="nota" placeholder="Qué ha pasado con este lead…"></textarea>
      <div style="margin-top:8px"><button class="btn" id="guardarNota"><i class="ph ph-plus"></i>Añadir nota</button></div>
      <div id="hilo" style="margin-top:16px"><p class="vacio">Cargando actividad…</p></div>
      ${FICHA && (FICHA.rol === 'super_admin' || (FICHA.herramientas || []).includes('closers'))
        ? '<p class="lb">Llamada de venta (Fathom.ai)</p><div id="fathom"><p class="vacio">Cargando…</p></div>' : ''}
    </div>`;
  document.body.append(velo, c);
  c.querySelector('.cerrar').onclick = cerrarFicha;
  c.querySelectorAll('#estados button').forEach(b => b.onclick = () => mover(l, b.dataset.e));
  c.querySelector('#guardarNota').onclick = () => guardarNota(l);
  const vc = c.querySelector('#verContacto');
  if(vc) vc.onclick = () => verContacto(l);
  pintarDuenoFicha(l);
  pintarProximoPaso(l);
  pintarHaciaContrato(l);
  pintarHilo(l);
  if(c.querySelector('#fathom')) pintarFathom(l);
}

/* ---------- quién lleva el lead ----------
   Lo que se puede hacer aquí depende de las MISMAS tres ramas que aplica la base, pero la
   pantalla no las reimplementa: solo decide qué botones tiene sentido enseñar. Si alguien
   se salta la interfaz, la base sigue diciendo que no — por eso el desplegable de reasignar
   solo se pinta a un admin, y aun así la función lo revalida.
   El desplegable se llena de `usuarios`, filtrado a quien puede ver el CRM: asignar un lead
   a alguien que no lo ve es apagarlo en silencio. */
async function pintarDuenoFicha(l){
  const caja = document.querySelector('#duenoFicha'); if(!caja) return;
  const soyAdmin = !!FICHA && (FICHA.rol === 'super_admin' || FICHA.rol === 'admin');
  const mio = esMio(l);

  if(!l.dueno){
    caja.innerHTML = `<p style="font-size:13px;color:var(--mist);margin:0 0 10px">
        Nadie lo lleva todavía. Si lo coges, tus tareas y tu «mis leads» lo incluyen.</p>
      <div style="display:flex;gap:8px;flex-wrap:wrap">
        <button class="btn pri" id="dfMio"><i class="ph ph-hand-grabbing"></i>Es mío</button>
        ${soyAdmin ? '<button class="btn" id="dfOtro">Asignar a otra persona</button>' : ''}
      </div>`;
  } else {
    const nombre = l.dueno_nombre || l.dueno;
    caja.innerHTML = `
      <div class="dato"><span>Lo lleva</span><b>${esc(nombre)}${mio ? ' (tú)' : ''}</b></div>
      ${l.dueno_activo === false ? `<div class="aviso rojo" style="margin:10px 0 0">
        <b>Esa cuenta está desactivada.</b> Este lead está huérfano de hecho: conviene
        reasignarlo a alguien que lo trabaje.</div>` : ''}
      <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:11px">
        ${mio ? '<button class="btn" id="dfSoltar">Soltarlo</button>' : ''}
        ${(mio || soyAdmin) ? '<button class="btn" id="dfOtro">Pasárselo a otra persona</button>' : ''}
        ${(!mio && !soyAdmin) ? `<p style="font-size:12.5px;color:var(--mist);margin:0">
          Lo lleva otra persona. Para cambiarlo, habla con un administrador.</p>` : ''}
      </div>`;
  }

  const bMio = caja.querySelector('#dfMio');
  if(bMio) bMio.onclick = () => asignar(l, yoSoy());
  const bSoltar = caja.querySelector('#dfSoltar');
  if(bSoltar) bSoltar.onclick = () => asignar(l, null);
  const bOtro = caja.querySelector('#dfOtro');
  if(bOtro) bOtro.onclick = () => formularioAsignar(l);
}

/* La lista de a quién se puede asignar se pide una vez por sesión: son 24 filas y no
   cambian mientras alguien mira un tablero. */
let EQUIPO = null;
async function cargarEquipo(){
  if(EQUIPO) return EQUIPO;
  const { data, error } = await SB.from('usuarios')
    .select('email, nombre, rol, activo, herramientas').eq('activo', true);
  EQUIPO = error ? [] : (data || []).filter(u =>
    u.rol === 'super_admin' || (u.herramientas || []).includes('leads'));
  return EQUIPO;
}

async function formularioAsignar(l){
  const caja = document.querySelector('#duenoFicha'); if(!caja) return;
  caja.innerHTML = '<p class="vacio">Cargando el equipo…</p>';
  const equipo = await cargarEquipo();
  if(!equipo.length){
    caja.innerHTML = `<div class="aviso oro" style="margin:0">
      <b>No hay nadie más con acceso al CRM.</b> Un administrador tiene que marcar la
      casilla «Leads» en <a href="/intranet/usuarios/" target="_blank" rel="noopener">Usuarios</a>
      antes de poder repartir leads.</div>
      <div style="margin-top:10px"><button class="btn" id="dfVolver">Volver</button></div>`;
    caja.querySelector('#dfVolver').onclick = () => pintarDuenoFicha(l);
    return;
  }
  caja.innerHTML = `
    <div class="campo"><label for="dfQuien">Pasárselo a</label>
      <select class="sui-sel" id="dfQuien">
        ${equipo.map(u => `<option value="${esc(u.email)}"${
          l.dueno && u.email.toLowerCase() === l.dueno.toLowerCase() ? ' selected' : ''
        }>${esc(u.nombre || u.email)}</option>`).join('')}
      </select></div>
    <div style="display:flex;gap:8px">
      <button class="btn pri" id="dfGuardar"><i class="ph ph-check"></i>Asignar</button>
      <button class="btn" id="dfCancelar">Cancelar</button>
    </div>`;
  caja.querySelector('#dfCancelar').onclick = () => pintarDuenoFicha(l);
  caja.querySelector('#dfGuardar').onclick = () => asignar(l, caja.querySelector('#dfQuien').value);
}

/* ---------- próximo paso ----------
   Una sola tarea viva por lead: la base lo impone con un índice parcial, así que aquí no
   hay lista ni "añadir otra" — o hay una y se cambia, o no hay y se pone. Esa restricción
   es deliberada: una cola de tareas por lead se convierte en un cementerio en dos semanas,
   y lo que un comercial necesita saber es cuál es el SIGUIENTE paso, uno solo. */
function pintarProximoPaso(l){
  const caja = document.querySelector('#proximoPaso'); if(!caja) return;
  const n = diasHasta(l.accion_cuando);
  caja.innerHTML = l.accion_que
    ? `<div class="tarea-ficha${n !== null && n <= 0 ? ' urge' : ''}">
         <div>
           <div class="q">${esc(l.accion_que)}</div>
           <div class="c">${esc(cuandoTexto(n))}${l.accion_responsable ? ' · ' + esc(l.accion_responsable) : ''}</div>
         </div>
         <div style="display:flex;gap:6px;flex-wrap:wrap">
           <button class="btn mini" id="ppHecho"><i class="ph ph-check"></i>Hecho</button>
           <button class="btn mini" id="ppCambiar">Cambiar</button>
         </div>
       </div>`
    : `<button class="btn" id="ppPoner"><i class="ph ph-flag"></i>Poner próximo paso</button>`;

  const hecho = caja.querySelector('#ppHecho');
  if(hecho) hecho.onclick = async () => {
    hecho.disabled = true;
    const { error } = await SB.rpc('crm_lead_accion_completar', { p_accion: l.accion_id });
    if(error){ toast('No se pudo cerrar: ' + error.message); hecho.disabled = false; return; }
    l.accion_id = l.accion_que = l.accion_cuando = l.accion_responsable = null;
    toast('Hecho. Pon el siguiente paso cuando lo tengas.');
    pintarProximoPaso(l); pintarHilo(l); pintarPipeline(); pintarBandeja(); actualizarCuentaHoy();
  };
  const abrir = caja.querySelector('#ppPoner') || caja.querySelector('#ppCambiar');
  if(abrir) abrir.onclick = () => formularioProximoPaso(l);
}

function formularioProximoPaso(l){
  const caja = document.querySelector('#proximoPaso'); if(!caja) return;
  /* Sugerencias de un clic: escribir "Llamar" a mano 107 veces es justo lo que hace que una
     herramienta de seguimiento se abandone. No son una lista cerrada — el campo es libre. */
  const RAPIDAS = ['Llamar', 'Mandar dossier', 'Mandar precios', 'Confirmar visita', 'Hacer seguimiento'];
  const hoy = HOY_BALI();
  caja.innerHTML = `
    <div class="campo"><label for="ppQue">Qué hay que hacer</label>
      <input type="text" id="ppQue" maxlength="280" value="${esc(l.accion_que || '')}" placeholder="Llamar para confirmar presupuesto"></div>
    <div style="display:flex;gap:6px;flex-wrap:wrap;margin:-6px 0 12px">
      ${RAPIDAS.map(t => `<button class="btn mini" data-rap="${esc(t)}">${esc(t)}</button>`).join('')}
    </div>
    <div class="campo"><label for="ppCuando">Cuándo</label>
      <input type="date" id="ppCuando" value="${esc(l.accion_cuando || hoy)}" min="2026-01-01"></div>
    <div style="display:flex;gap:6px;flex-wrap:wrap;margin:-6px 0 12px">
      <button class="btn mini" data-dia="0">Hoy</button>
      <button class="btn mini" data-dia="1">Mañana</button>
      <button class="btn mini" data-dia="3">En 3 días</button>
      <button class="btn mini" data-dia="7">En una semana</button>
    </div>
    <div style="display:flex;gap:8px">
      <button class="btn pri" id="ppGuardar"><i class="ph ph-check"></i>Guardar</button>
      <button class="btn" id="ppCancelar">Cancelar</button>
    </div>`;
  caja.querySelectorAll('[data-rap]').forEach(b => b.onclick = () => {
    caja.querySelector('#ppQue').value = b.dataset.rap;
    caja.querySelector('#ppQue').focus();
  });
  caja.querySelectorAll('[data-dia]').forEach(b => b.onclick = () => {
    const d = new Date(hoy + 'T00:00:00Z');
    d.setUTCDate(d.getUTCDate() + Number(b.dataset.dia));
    caja.querySelector('#ppCuando').value = d.toISOString().slice(0, 10);
  });
  caja.querySelector('#ppCancelar').onclick = () => pintarProximoPaso(l);
  caja.querySelector('#ppGuardar').onclick = async () => {
    const que = caja.querySelector('#ppQue').value.trim();
    const cuando = caja.querySelector('#ppCuando').value;
    if(!que){ toast('Escribe qué hay que hacer.'); return; }
    if(!cuando){ toast('Falta la fecha.'); return; }
    const { data, error } = await SB.rpc('crm_lead_accion_poner', {
      p_lead: l.id, p_que: que, p_cuando: cuando,
    });
    if(error){ toast('No se pudo guardar: ' + error.message); return; }
    const fila = (data || [])[0];
    if(fila){
      l.accion_id = fila.id; l.accion_que = fila.que;
      l.accion_cuando = fila.cuando; l.accion_responsable = fila.responsable;
    }
    toast('Próximo paso guardado.');
    pintarProximoPaso(l); pintarHilo(l); pintarPipeline(); pintarBandeja(); actualizarCuentaHoy();
  };
  caja.querySelector('#ppQue').focus();
}

/* ---------- del lead al contrato ----------
   POR QUÉ HAY UN PASO DE CONFIRMACIÓN Y NO UN BOTÓN DIRECTO (decisión del owner, 11-sep-2026).
   `contracts/app.html` no deja guardar un contrato cuyo comprador no tenga ficha en
   `clients` — es un muro del 18-ago puesto porque teclear a mano creaba clientes duplicados
   (RP00043: 165.800 € con un email metido en el campo del nombre). Y la ficha la crea un
   trigger DESPUÉS de guardar el contrato, así que sin resolverla antes el comercial
   rellenaría un contrato que no puede guardar.
   Aquí no teclea nadie: los datos son los que la propia persona escribió en el formulario.
   Lo que aporta el diálogo es lo que el muro protege de verdad — ver, antes de crear, si
   ese correo ya tiene ficha o si hay otras tarjetas de la misma persona (hoy 7 de 107). */
function pintarHaciaContrato(l){
  const caja = document.querySelector('#haciaContrato'); if(!caja) return;
  if(l.contrato_numero){
    caja.innerHTML = `<div class="dato"><span>Contrato</span><b>${esc(l.contrato_numero)}</b></div>
      <div style="margin-top:9px"><a class="btn" href="/contracts/app.html?contrato=${encodeURIComponent(l.contrato_id)}">
        <i class="ph ph-arrow-square-out"></i>Abrir el contrato</a></div>
      <p style="font-size:12.5px;color:var(--mist);margin:9px 0 0">
        Este lead está enlazado a su contrato de verdad, no por parecido de correo.</p>`;
    return;
  }
  caja.innerHTML = `<button class="btn pri" id="haciaContratoBtn"><i class="ph ph-file-plus"></i>Crear contrato para este lead</button>
    <p style="font-size:12.5px;color:var(--mist);margin:9px 0 0">
      Se abre su ficha de comprador (con los datos que dejó él) y de ahí el contrato.</p>`;
  caja.querySelector('#haciaContratoBtn').onclick = () => dialogoHaciaContrato(l);
}

async function dialogoHaciaContrato(l){
  const caja = document.querySelector('#haciaContrato'); if(!caja) return;
  caja.innerHTML = '<p class="vacio">Comprobando…</p>';
  const { data, error } = await SB.rpc('crm_lead_para_contrato', { p_lead: l.id });
  if(error){ caja.innerHTML = '<p class="vacio">No se pudo comprobar: ' + esc(error.message) + '</p>'; return; }
  const d = (data || [])[0];
  if(!d){ caja.innerHTML = '<p class="vacio">No se pudo leer el lead.</p>'; return; }

  const avisos = [];
  if(d.ficha_existente) avisos.push(
    `<div class="aviso gris" style="margin:0 0 10px"><b>Ya existe una ficha con ese correo:</b> ${esc(d.ficha_existente_nombre || '')}.
     Se usará esa, no se crea otra.</div>`);
  if(d.otros_leads_igual > 0) avisos.push(
    `<div class="aviso oro" style="margin:0 0 10px"><b>Ojo:</b> hay ${d.otros_leads_igual}
     ${d.otros_leads_igual === 1 ? 'tarjeta más' : 'tarjetas más'} con este mismo correo.
     Puede que sea la misma persona duplicada.</div>`);
  if(!d.email) avisos.push(
    `<div class="aviso rojo" style="margin:0 0 10px"><b>Este lead no dejó email.</b>
     Una ficha de comprador necesita un identificador, así que hay que darla de alta a mano
     en <a href="/intranet/compradores/?nuevo=1" target="_blank" rel="noopener">Compradores</a>.</div>`);

  caja.innerHTML = avisos.join('') + `
    <div class="dato"><span>Nombre</span><b>${esc(d.nombre || 'sin nombre')}</b></div>
    <div class="dato"><span>Email</span><b>${esc(d.email || 'no dejó')}</b></div>
    <div class="dato"><span>Teléfono</span><b>${esc(d.whatsapp || 'no dejó')}</b></div>
    <div style="display:flex;gap:8px;margin-top:12px;flex-wrap:wrap">
      ${d.email ? `<button class="btn pri" id="hcSeguir"><i class="ph ph-arrow-right"></i>${
        d.ficha_existente ? 'Usar esa ficha y abrir el contrato' : 'Crear ficha y abrir el contrato'}</button>` : ''}
      <button class="btn" id="hcCancelar">Cancelar</button>
    </div>`;
  caja.querySelector('#hcCancelar').onclick = () => pintarHaciaContrato(l);
  const seguir = caja.querySelector('#hcSeguir');
  if(seguir) seguir.onclick = async () => {
    seguir.disabled = true;
    const { data: f, error: e2 } = await SB.rpc('crm_lead_ficha_crear', { p_lead: l.id });
    if(e2){ toast('No se pudo abrir la ficha: ' + e2.message); seguir.disabled = false; return; }
    const ficha = (f || [])[0];
    if(!ficha || !ficha.client_id){ toast('No se pudo abrir la ficha.'); seguir.disabled = false; return; }
    /* `?cliente=` es el camino que ya existía y está probado (entrada desde Compradores);
       `?lead=` se suma solo para que el contrato se selle contra este lead al guardarlo.
       Ni el nombre ni el correo viajan en la URL: se piden al servidor desde el editor.
       Con la sesión caducada, app.html reenvía `location.search` ENTERO a la página de
       login — si aquí fuera el contacto, acabaría en el historial y en los logs. */
    location.href = '/contracts/app.html?cliente=' + encodeURIComponent(ficha.client_id)
      + '&lead=' + encodeURIComponent(l.id);
  };
}

/* El owner todavía no tiene cuenta de Fathom.ai (10-sep-2026): esto siempre
   enseña "sin llamadas registradas todavía" en producción hasta que exista el
   primer webhook real — nunca se inventa una fila de ejemplo aquí. */
async function pintarFathom(l){
  const caja = document.querySelector('#fathom'); if(!caja) return;
  const { data, error } = await SB.rpc('crm_lead_fathom', { p_lead: l.id });
  if(error){ caja.innerHTML = '<p class="vacio">No se pudo leer.</p>'; return; }
  if(!data || !data.length){ caja.innerHTML = '<p class="vacio">Sin llamadas registradas todavía.</p>'; return; }
  caja.innerHTML = data.map(f => `
    <div class="dato" style="display:block;padding:10px 0">
      <div style="font-size:11.5px;color:var(--mist);margin-bottom:4px">${esc(fechaHora(f.procesado_en))}</div>
      ${f.resumen ? `<p style="margin:0 0 6px">${esc(f.resumen)}</p>` : ''}
      ${(f.objeciones || []).length ? '<p class="lb" style="margin:10px 0 4px">Objeciones</p>' +
        f.objeciones.map(o => `<span class="chip rojo" style="margin:2px">${esc(typeof o === 'string' ? o : (o.text || JSON.stringify(o)))}</span>`).join('') : ''}
      ${f.recording_url ? `<div style="margin-top:8px"><a class="btn mini" target="_blank" rel="noopener" href="${esc(f.recording_url)}"><i class="ph ph-play"></i>Ver grabación</a></div>` : ''}
    </div>`).join('');
}

/* El contacto se pide de uno en uno y la petición queda registrada en la base
   (lead_acceso_log). El registro lo escribe la propia función que entrega el
   dato: uno hecho desde aquí se saltaría apagando el JavaScript. */
async function verContacto(l){
  const caja = document.querySelector('#contacto'); if(!caja) return;
  caja.innerHTML = '<p style="font-size:13px;color:var(--mist);margin:0">Pidiendo…</p>';
  const { data, error } = await SB.rpc('crm_lead_contacto', { p_lead: l.id, p_que: 'contacto' });
  if(error){ caja.innerHTML = '<p class="vacio">No se pudo leer el contacto.</p>'; return; }
  const c = (data || [])[0] || {};
  const tel = (c.whatsapp || '').replace(/[^0-9]/g, '');
  const mail = c.email ? enlaceSeguro('mailto:' + c.email) : null;
  const wa   = tel ? enlaceSeguro('https://wa.me/' + tel) : null;
  caja.innerHTML = `
    <div class="dato"><span>Email</span><b>${esc(c.email || 'no dejó')}</b></div>
    <div class="dato"><span>Teléfono</span><b>${esc(c.whatsapp || 'no dejó')}</b></div>
    <div style="display:flex;gap:7px;flex-wrap:wrap;margin-top:11px">
      ${mail ? `<a class="btn" href="${esc(mail)}" data-reg="email"><i class="ph ph-envelope"></i>Escribir</a>` : ''}
      ${wa ? `<a class="btn oro" target="_blank" rel="noopener" href="${esc(wa)}" data-reg="whatsapp"><i class="ph ph-whatsapp-logo"></i>WhatsApp</a>` : ''}
    </div>`;
  /* Abrir WhatsApp o el correo es un contacto real: se registra aparte del
     simple "he mirado la ficha". */
  caja.querySelectorAll('[data-reg]').forEach(a => a.addEventListener('click', () => {
    SB.rpc('crm_lead_contacto', { p_lead: l.id, p_que: a.dataset.reg });
  }));
}

async function pintarHilo(l){
  const caja = document.querySelector('#hilo'); if(!caja) return;
  const { data, error } = await SB.rpc('crm_lead_hilo', { p_lead: l.id });
  if(error){ caja.innerHTML = '<p class="vacio">No se pudo leer la actividad.</p>'; return; }
  caja.innerHTML = '<div class="hilo">' + (data || []).slice().reverse().map(ev => {
    const ico = { alta:'ph-download-simple', estado:'ph-arrow-right', nota:'ph-note' }[ev.tipo] || 'ph-circle';
    let texto;
    if(ev.tipo === 'alta')   texto = 'Entró por <b>' + esc(canal(ev.texto)) + '</b>';
    else if(ev.tipo === 'estado') texto = 'Pasó de <b>' + esc(nombreCol(ev.extra)) + '</b> a <b>' + esc(nombreCol(ev.texto)) + '</b>';
    else                     texto = esc(ev.texto);
    return `<div class="ev ${ev.tipo}"><div class="ico"><i class="ph ${ico}"></i></div>
      <div><div class="qué">${texto}</div>
      <div class="cuando">${esc(fechaHora(ev.cuando))}${ev.autor ? ' · ' + esc(ev.autor) : ''}</div></div></div>`;
  }).join('') + '</div>';
}
const nombreCol = k => (COLS.find(c => c[0] === k) || [null, k])[1];

async function guardarNota(l){
  const ta = document.querySelector('#nota'); const texto = (ta.value || '').trim();
  if(!texto) return;
  const { error } = await SB.rpc('crm_lead_nota', { p_lead: l.id, p_texto: texto });
  if(error){ toast('No se pudo guardar la nota: ' + error.message); return; }
  ta.value = ''; l.notas = (l.notas || 0) + 1;
  pintarHilo(l); pintarPipeline(); pintarBandeja();
}

/* ==========================================================================
   VISTA 2 — BANDEJA
   --------------------------------------------------------------------------
   El mockup la dibuja como una bandeja de mensajes con conversaciones de
   WhatsApp e Instagram. Aquí NO se finge ninguna: los leads de Lawang llegan
   por formulario de Meta y por la web, no por un canal de mensajería
   conectado al CRM. Lo que sí existe —y es lo que se pinta— es el hilo real de
   cada lead: cuándo entró, qué contestó, por qué columnas ha pasado, quién lo
   movió y qué notas ha dejado el equipo.
   ========================================================================== */
function bandejaFiltrada(){
  const q = BUSCA_B.trim().toLowerCase();
  return LEADS.filter(l => {
    if(FILTRO_B === 'sintocar' && l.estado !== 'nuevo') return false;
    if(FILTRO_B === 'parados' && !(dias(l.estado_desde) >= DIAS_VIEJO)) return false;
    if(q && !(l.name || '').toLowerCase().includes(q)) return false;
    return true;
  }).sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
}
let BUSCA_B = '';

function pintarBandeja(){
  const filas = bandejaFiltrada();
  const cont = $('#bandeja');
  if(!filas.length){ cont.innerHTML = '<div class="caja"><p class="vacio">Ningún lead con ese filtro.</p></div>'; return; }
  cont.innerHTML = `<div class="caja"><div class="tabla-scroll"><table class="tabla">
    <thead><tr><th>Lead</th><th>Origen</th><th>Estado</th><th>Última actividad</th><th>Notas</th><th></th></tr></thead>
    <tbody>${filas.map(l => {
      const d = dias(l.estado_desde), viejo = d !== null && d >= DIAS_VIEJO;
      return `<tr data-id="${esc(l.id)}" style="cursor:pointer">
        <td><b>${esc(l.name || 'sin nombre')}</b>
          ${l.sugerencia && l.sugerencia !== l.estado
            ? `<div><span class="chip oro">Firmó ${esc(nombreCol(l.sugerencia))}</span></div>` : ''}</td>
        <td><span class="chip meta">${esc(canal(l.source))}</span></td>
        <td><span class="chip gris">${esc(nombreCol(l.estado))}</span></td>
        <td class="${viejo ? '' : ''}" style="${viejo ? 'color:var(--danger);font-weight:600' : ''}">${esc(edad(d))}</td>
        <td class="num">${l.notas || ''}</td>
        <td style="text-align:right"><i class="ph ph-caret-right" style="color:var(--mist)"></i></td>
      </tr>`;
    }).join('')}</tbody></table></div></div>`;
  cont.querySelectorAll('tr[data-id]').forEach(tr =>
    tr.onclick = () => abrirFicha(LEADS.find(x => x.id === tr.dataset.id)));
}

/* ==========================================================================
   VISTA 3 — CAMPAÑAS
   ========================================================================== */
async function cargarPanel(){
  CARGADO.panel = true;
  const [c, s] = await Promise.all([SB.rpc('crm_campanas'), SB.rpc('crm_serie_semanal', { p_semanas: 8 })]);
  CAMPANAS = c.error ? [] : (c.data || []);
  SERIE    = s.error ? [] : (s.data || []);
  pintarPanel();
}

function pintarPanel(){
  const totalLeads = LEADS.length;
  const leads7 = LEADS.filter(l => dias(l.created_at) <= 7).length;
  const gasto = CAMPANAS.reduce((a, c) => a + Number(c.gasto || 0), 0);
  const leadsCamp = CAMPANAS.reduce((a, c) => a + Number(c.leads || 0), 0);
  const mon = (CAMPANAS.find(c => c.moneda) || {}).moneda || '';
  const cpl = leadsCamp ? gasto / leadsCamp : null;
  const hayGasto = CAMPANAS.length > 0;

  $('#kpis-panel').innerHTML = `
    <div class="kpi"><div class="rot">Leads recibidos<i class="ph ph-users"></i></div>
      <p class="cifra">${totalLeads}</p><p class="pie">${leads7} en los últimos 7 días</p></div>
    <div class="kpi"><div class="rot">Coste por lead<i class="ph ph-tag"></i></div>
      <p class="cifra oro">${cpl == null ? '—' : dinero(Math.round(cpl), mon)}</p>
      <p class="pie">${hayGasto ? 'de las campañas medidas' : 'sin datos de gasto todavía'}</p></div>
    <div class="kpi"><div class="rot">Invertido<i class="ph ph-currency-circle-dollar"></i></div>
      <p class="cifra">${hayGasto ? dinero(gasto, mon) : '—'}</p>
      <p class="pie">${hayGasto ? CAMPANAS.length + ' campañas' : 'pendiente de la primera vuelta'}</p></div>
    <div class="kpi fuerte"><div class="rot">Firmas<i class="ph ph-signature"></i></div>
      <p class="cifra">${LEADS.filter(l => l.sugerencia).length}</p>
      <p class="pie">leads con contrato firmado</p></div>`;

  const av = $('#avisoPanel');
  if(!hayGasto){
    av.hidden = false;
    av.innerHTML = '<b>Todavía no hay cifras de gasto.</b> Las trae el vigilante de AxisWorks en su '
      + 'próxima vuelta (cada 4 horas). Los leads de abajo sí son reales y están completos.';
  } else av.hidden = true;

  $('#grafica').innerHTML = grafica();
  $('#subCampanas').textContent = hayGasto
    ? CAMPANAS.length + ' campañas con datos · última actualización ' + fecha(CAMPANAS[0].ultimo)
    : 'Sin datos de campaña todavía.';
  $('#tCampanas').innerHTML = `
    <thead><tr><th>Campaña</th><th class="num">Invertido</th><th class="num">Leads</th>
      <th class="num">Coste/lead</th><th class="num">Clics</th><th class="num">7 días</th></tr></thead>
    <tbody>${CAMPANAS.length ? CAMPANAS.map(c => {
      const cp = c.leads ? Number(c.gasto || 0) / c.leads : null;
      return `<tr><td><b>${esc(c.nombre || c.cliente)}</b><div style="font-size:11.5px;color:var(--mist)">${esc(c.cliente)}</div></td>
        <td class="num">${dinero(c.gasto, c.moneda)}</td>
        <td class="num">${c.leads ?? '—'}</td>
        <td class="num">${cp == null ? '—' : dinero(Math.round(cp), c.moneda)}</td>
        <td class="num">${c.clics ?? '—'}</td>
        <td class="num">${c.leads_7d ?? 0} leads</td></tr>`;
    }).join('') : '<tr><td colspan="6"><p class="vacio">Aún no hay datos de campañas.</p></td></tr>'}</tbody>`;
}

/* Gráfica en SVG a mano: dos series, leads (barras) y gasto (línea). Sin
   librería — la página no puede cargar scripts de fuera y una dependencia más
   para dos series no se sostiene. */
function grafica(){
  if(!SERIE.length) return '<p class="vacio">Sin datos todavía.</p>';
  const W = 720, H = 220, P = { t: 14, r: 46, b: 30, l: 42 };
  const maxL = Math.max(1, ...SERIE.map(s => Number(s.leads || 0)));
  const gastos = SERIE.map(s => s.gasto == null ? null : Number(s.gasto));
  const maxG = Math.max(1, ...gastos.map(g => g || 0));
  const n = SERIE.length;
  const bw = (W - P.l - P.r) / n * .55;
  const x = i => P.l + (W - P.l - P.r) * (i + .5) / n;
  const yL = v => H - P.b - (H - P.t - P.b) * (v / maxL);
  const yG = v => H - P.b - (H - P.t - P.b) * (v / maxG);
  const conGasto = gastos.filter(g => g != null).length;

  const barras = SERIE.map((s, i) =>
    `<rect x="${x(i) - bw / 2}" y="${yL(Number(s.leads || 0))}" width="${bw}"
      height="${Math.max(0, H - P.b - yL(Number(s.leads || 0)))}" rx="3" fill="#064E3B" opacity=".85"/>`).join('');
  const puntos = SERIE.map((s, i) => gastos[i] == null ? null : `${x(i)},${yG(gastos[i])}`).filter(Boolean);
  const linea = puntos.length > 1
    ? `<polyline points="${puntos.join(' ')}" fill="none" stroke="#D97706" stroke-width="2.5"
        stroke-linejoin="round" stroke-linecap="round"/>` : '';
  const marcas = SERIE.map((s, i) => gastos[i] == null ? '' :
    `<circle cx="${x(i)}" cy="${yG(gastos[i])}" r="3.5" fill="#D97706"/>`).join('');
  const ejeX = SERIE.map((s, i) =>
    `<text x="${x(i)}" y="${H - 9}" text-anchor="middle" font-size="10.5" fill="#64748B">${
      new Date(s.semana).toLocaleDateString('es-ES', { day: 'numeric', month: 'short' })}</text>`).join('');

  return `<div style="overflow-x:auto"><svg viewBox="0 0 ${W} ${H}" width="100%" height="${H}"
      role="img" aria-label="Leads y gasto por semana" style="min-width:520px">
    <line x1="${P.l}" y1="${H - P.b}" x2="${W - P.r}" y2="${H - P.b}" stroke="#E2E8F0"/>
    <text x="6" y="${P.t + 8}" font-size="10.5" fill="#064E3B">${maxL} leads</text>
    ${conGasto ? `<text x="${W - P.r + 6}" y="${P.t + 8}" font-size="10.5" fill="#D97706">gasto</text>` : ''}
    ${barras}${linea}${marcas}${ejeX}
  </svg></div>
  <p style="font-size:12.5px;color:var(--mist);margin:8px 0 0">
    <b style="color:#064E3B">■</b> leads por semana
    ${conGasto ? ' · <b style="color:#D97706">—</b> invertido en Meta'
      : ' · el gasto aparecerá cuando el vigilante haga su primera vuelta'}</p>`;
}

/* ==========================================================================
   VISTA 4 — AUTOMATISMOS
   --------------------------------------------------------------------------
   El mockup dibuja un constructor de flujos con nodos editables, retardos y
   plantillas de WhatsApp. Aquí se enseña lo que EXISTE y se ejecuta de verdad:
   el vigilante de campañas de AxisWorks, con sus reglas y su historial real de
   acciones. No hay editor porque no hay motor que ejecute lo que se editara, y
   un constructor que no ejecuta nada es peor que no tenerlo: promete.
   ========================================================================== */
const REGLAS = [
  { n: 'Recogida de leads', ico: 'ph-download-simple', cada: 'cada 4 h',
    q: 'Baja a este CRM los leads de los formularios de Meta que estén en anuncios activos.',
    hace: 'Escribe la ficha del lead. Nunca toca su estado ni sus notas.' },
  { n: 'Freno por sequía', ico: 'ph-pause', cada: 'cada 4 h',
    q: 'Un conjunto de anuncios que lleva días sin traer un solo lead.',
    hace: 'Lo pausa para no seguir gastando en algo que no convierte.' },
  { n: 'Reparto del presupuesto', ico: 'ph-scales', cada: 'cada 4 h',
    q: 'Compara el coste por lead de cada conjunto dentro de su tope mensual.',
    hace: 'Sube o baja el presupuesto diario, y reactiva lo que él mismo pausó cuando vuelve a caber.' },
  { n: 'Tope de gasto', ico: 'ph-shield-check', cada: 'cada 4 h',
    q: 'El gasto acumulado del mes contra el tope acordado.',
    hace: 'Pausa la campaña al cruzarlo. Es la jaula: ninguna otra regla puede saltársela.' },
  { n: 'Limpieza de público', ico: 'ph-funnel', cada: 'máx. 1 cada 7 días',
    q: 'Franjas de edad y género con clics y gasto suficientes y cero leads.',
    hace: 'Las excluye del público. Reversible y anotado.' },
];

async function cargarAutomatismos(){
  CARGADO.automatismos = true;
  const { data, error } = await SB.rpc('crm_automatismos', { p_limite: 60 });
  ACCIONES = error ? [] : (data || []);
  pintarAutomatismos();
}

function pintarAutomatismos(){
  const ultima = ACCIONES[0];
  $('#kpis-auto').innerHTML = `
    <div class="kpi"><div class="rot">Reglas activas<i class="ph ph-flow-arrow"></i></div>
      <p class="cifra">${REGLAS.length}</p><p class="pie">se revisan cada 4 horas</p></div>
    <div class="kpi"><div class="rot">Acciones registradas<i class="ph ph-list-checks"></i></div>
      <p class="cifra">${ACCIONES.length}</p><p class="pie">las últimas que constan</p></div>
    <div class="kpi fuerte"><div class="rot">Última actuación<i class="ph ph-clock"></i></div>
      <p class="cifra" style="font-size:20px">${ultima ? esc(fechaHora(ultima.cuando)) : '—'}</p>
      <p class="pie">${ultima ? esc(ultima.campana) : 'sin registro'}</p></div>`;

  /* El flujo real, de izquierda a derecha. Cuatro pasos, y el último dice la
     verdad incómoda: mover la tarjeta lo hace una persona. */
  const pasos = [
    { ico:'ph-megaphone',       t:'Anuncio en Meta',      s:'Facebook e Instagram' },
    { ico:'ph-file-text',       t:'Formulario instantáneo', s:'El lead deja sus datos' },
    { ico:'ph-download-simple', t:'Recogida automática',  s:'Cada 4 h, sin tocar nada' },
    { ico:'ph-kanban',          t:'Entra en «Nuevo»',     s:'Y de ahí lo mueve una persona' },
  ];
  $('#flujo').innerHTML = '<div style="display:flex;gap:10px;flex-wrap:wrap;align-items:stretch">'
    + pasos.map((p, i) => `<div style="flex:1 1 170px;background:var(--canvas);border:1px solid var(--line);
        border-radius:var(--r-box);padding:13px">
        <div style="display:flex;align-items:center;gap:8px;color:var(--primary)">
          <i class="ph ${p.ico}" style="font-size:18px"></i>
          <b style="font-family:var(--sans);font-size:13.5px">${p.t}</b></div>
        <p style="margin:6px 0 0;font-size:12px;color:var(--mist)">${p.s}</p>
        ${i < pasos.length - 1 ? '' : ''}</div>`).join('')
    + '</div>';

  $('#subReglas').textContent = 'Qué mira cada una y qué puede hacer.';
  $('#reglas').innerHTML = REGLAS.map(r => `
    <div style="display:grid;grid-template-columns:34px 1fr;gap:12px;padding:12px 0;border-top:1px solid var(--line-soft)">
      <div style="width:34px;height:34px;border-radius:8px;background:var(--primary-soft);color:var(--primary);
        display:grid;place-items:center"><i class="ph ${r.ico}" style="font-size:17px"></i></div>
      <div><div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
          <b style="font-family:var(--sans);font-size:14px">${r.n}</b>
          <span class="chip gris">${r.cada}</span></div>
        <p style="margin:5px 0 0;font-size:13px">${r.q}</p>
        <p style="margin:3px 0 0;font-size:12.5px;color:var(--mist)">${r.hace}</p></div>
    </div>`).join('');

  $('#subAcciones').textContent = ACCIONES.length
    ? 'Las ' + ACCIONES.length + ' últimas actuaciones sobre las campañas de Lawang.'
    : 'Todavía no consta ninguna actuación.';
  $('#tAcciones').innerHTML = `
    <thead><tr><th>Cuándo</th><th>Campaña</th><th>Qué hizo</th><th>Por qué</th></tr></thead>
    <tbody>${ACCIONES.length ? ACCIONES.map(a => `<tr>
      <td style="white-space:nowrap">${esc(fechaHora(a.cuando))}</td>
      <td>${esc(a.campana)}</td>
      <td><span class="chip ${/pausa/i.test(a.accion) ? 'rojo' : /reactiv|sube/i.test(a.accion) ? 'verde' : 'gris'}">${esc(a.accion)}</span></td>
      <td>${esc(a.motivo || '')}</td></tr>`).join('')
      : '<tr><td colspan="4"><p class="vacio">Sin actuaciones registradas.</p></td></tr>'}</tbody>`;
}

/* ==========================================================================
   VISTA 5 — SETTER IA (bot de WhatsApp)
   --------------------------------------------------------------------------
   Datos del bot (`lawang-bot`, Redis), NO del CRM de leads (Postgres) — nunca
   se llama a `lawang-bot-proxy` con datos de aquí ni al revés sin querer. El
   proxy guarda la clave del bot como secreto de la función: esta pantalla
   nunca ve `ADMIN_PASSWORD`.
   ========================================================================== */
async function llamarBot(accion, extra){
  const { data: ses } = await SB.auth.getSession();
  const token = ses && ses.session && ses.session.access_token;
  const r = await fetch('https://vtulllundrfennhjddhc.supabase.co/functions/v1/lawang-bot-proxy', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || '') },
    body: JSON.stringify(Object.assign({ accion }, extra || {})),
  });
  const cuerpo = await r.json().catch(() => ({}));
  if(!r.ok) throw new Error(cuerpo.error || ('El bot respondió ' + r.status));
  return cuerpo;
}

async function cargarSetter(){
  CARGADO.setter = true;
  const av = $('#avisoSetter');
  try {
    CONVERSACIONES = await llamarBot('conversaciones');
    av.hidden = true;
  } catch(err){
    CONVERSACIONES = [];
    av.hidden = false;
    av.innerHTML = err.message === 'lawang-bot-proxy no configurado (falta LAWANG_BOT_ADMIN_KEY)'
      ? 'El puente con el bot todavía no está activado por el estudio.'
      : 'No se pudo leer el bot: ' + esc(err.message);
  }
  pintarSetter();
}

const iniciales = nombre => (nombre || '').trim().split(/\s+/).slice(0, 2).map(p => p[0] || '').join('').toUpperCase() || '?';

function kpisSetter(){
  const activas = CONVERSACIONES.filter(l => !l.paused).length;
  const pausadas = CONVERSACIONES.length - activas;
  $('#kpis-setter').innerHTML = `
    <div class="kpi"><div class="rot">Conversaciones<i class="ph ph-chats-circle"></i></div>
      <p class="cifra">${CONVERSACIONES.length}</p><p class="pie">con el bot de WhatsApp</p></div>
    <div class="kpi fuerte"><div class="rot">IA activa<i class="ph ph-robot"></i></div>
      <p class="cifra">${activas}</p><p class="pie">respondiendo sola ahora mismo</p></div>
    <div class="kpi"><div class="rot">En pausa<i class="ph ph-pause"></i></div>
      <p class="cifra oro">${pausadas}</p><p class="pie">las lleva una persona</p></div>`;
}

function pintarSetter(){
  kpisSetter();
  const filas = CONVERSACIONES.slice().sort((a, b) => (b.lastInboundAt || 0) - (a.lastInboundAt || 0));
  $('#tSetter').innerHTML = filas.length ? filas.map(l => `
    <article class="conversacion${l.paused ? '' : ' activa'}" data-phone="${esc(l.phone)}">
      <div class="avatar">${esc(iniciales(l.name))}</div>
      <div class="cuerpo">
        <div class="quien">${esc(l.name || 'sin nombre')}</div>
        <div class="sub">${esc(l.phone || '')} · ${l.lastInboundAt ? esc(fechaHora(new Date(l.lastInboundAt).toISOString())) : 'sin actividad'}</div>
      </div>
      ${l.paused
        ? '<span class="chip gris"><i class="ph ph-pause"></i> Pausada</span>'
        : '<span class="chip verde"><i class="ph ph-robot"></i> IA activa</span>'}
      <div class="acciones">
        <button class="btn mini" data-pausar="${esc(l.phone)}" data-a="${l.paused ? '0' : '1'}">
          ${l.paused ? 'Reanudar IA' : 'Pausar IA'}</button>
      </div>
    </article>`).join('') : '<p class="vacio">Sin conversaciones todavía.</p>';
  $('#tSetter').querySelectorAll('[data-pausar]').forEach(b => b.onclick = ev => {
    ev.stopPropagation();
    pausarLead(b.dataset.pausar, b.dataset.a === '1');
  });
  $('#tSetter').querySelectorAll('.conversacion').forEach(c => c.onclick = () => verConversacion(c.dataset.phone));
}

async function pausarLead(phone, paused){
  try {
    await llamarBot('pausar', { phone, paused });
    const l = CONVERSACIONES.find(x => x.phone === phone);
    if(l) l.paused = paused;
    pintarSetter();
    toast(paused ? 'IA pausada para ese lead.' : 'IA reanudada para ese lead.');
  } catch(err){ toast('No se pudo cambiar el estado: ' + err.message); }
}

async function verConversacion(phone){
  cerrarFicha();
  const velo = document.createElement('div'); velo.className = 'velo'; velo.onclick = cerrarFicha;
  const c = document.createElement('aside'); c.className = 'cajon';
  c.innerHTML = `<header><button class="cerrar" aria-label="Cerrar">&times;</button><h2>${esc(phone)}</h2></header>
    <div class="cuerpo"><div id="hiloConv" class="hilo"><p class="vacio">Cargando…</p></div></div>`;
  document.body.append(velo, c);
  c.querySelector('.cerrar').onclick = cerrarFicha;
  ABIERTO = { id: '__conv__' };   // reutiliza cerrarFicha() sin chocar con la ficha de un lead
  try {
    const historia = await llamarBot('conversacion', { phone });
    $('#hiloConv').innerHTML = (historia || []).map(m => `
      <div class="ev ${m.role === 'user' ? 'alta' : 'nota'}"><div class="ico"><i class="ph ${m.role === 'user' ? 'ph-user' : 'ph-robot'}"></i></div>
      <div><div class="qué">${esc(m.content || '')}</div>
      <div class="cuando">${m.ts ? esc(fechaHora(new Date(m.ts).toISOString())) : ''}${m.by ? ' · ' + esc(m.by) : ''}</div></div></div>`).join('')
      || '<p class="vacio">Sin mensajes.</p>';
  } catch(err){ $('#hiloConv').innerHTML = '<p class="vacio">No se pudo leer la conversación.</p>'; }
}

/* ==========================================================================
   VISTA 6 — AGENDA DE CIERRE (citas del bot + closer)
   --------------------------------------------------------------------------
   El enlace de Google Meet solo llega si el estudio activó Calendar en el
   bot (CALENDAR_ID+GOOGLE_SERVICE_ACCOUNT en Railway) — sin eso, `meetLink`
   viene vacío y se avisa en vez de fingir un botón que no lleva a ningún
   sitio.
   ========================================================================== */
async function cargarAgenda(){
  CARGADO.agenda = true;
  try { CITAS = await llamarBot('citas_listar'); }
  catch(err){ CITAS = []; toast('No se pudieron leer las citas: ' + err.message); }
  pintarAgenda();
}

function kpisAgenda(filas){
  const hoy = new Date(); hoy.setHours(0, 0, 0, 0);
  const futuras = filas.filter(c => new Date(c.when) >= new Date());
  const conMeet = filas.filter(c => c.meetLink).length;
  const proxima = futuras[0];
  $('#kpis-agenda').innerHTML = `
    <div class="kpi"><div class="rot">Citas agendadas<i class="ph ph-calendar"></i></div>
      <p class="cifra">${filas.length}</p><p class="pie">${futuras.length} todavía por llegar</p></div>
    <div class="kpi"><div class="rot">Con Meet listo<i class="ph ph-video-camera"></i></div>
      <p class="cifra oro">${conMeet}</p><p class="pie">${filas.length - conMeet} sin enlace automático</p></div>
    <div class="kpi fuerte"><div class="rot">Próxima llamada<i class="ph ph-clock"></i></div>
      <p class="cifra" style="font-size:19px">${proxima ? esc(fechaHora(proxima.when)) : '—'}</p>
      <p class="pie">${proxima ? esc(proxima.name || proxima.phone || 'sin nombre') : 'nada agendado por delante'}</p></div>`;
}

function pintarAgenda(){
  const filas = CITAS.slice().sort((a, b) => new Date(a.when) - new Date(b.when));
  kpisAgenda(filas);
  const hayMeetActivo = filas.some(c => c.meetLink);
  $('#avisoAgendaMeet').hidden = filas.length === 0 || hayMeetActivo;
  $('#subAgenda').textContent = filas.length ? filas.length + (filas.length === 1 ? ' cita agendada' : ' citas agendadas') : 'Sin citas agendadas todavía.';
  $('#tAgenda').innerHTML = filas.length ? filas.map(c => `
    <article class="cita${c.meetLink ? ' con-meet' : ''}">
      <div class="avatar">${esc(iniciales(c.name || c.phone))}</div>
      <div class="cuerpo">
        <div class="cuando">${esc(fechaHora(c.when))}</div>
        <div class="quien">${esc(c.name || c.phone || 'sin nombre')}</div>
        <div class="sub">${c.phone ? esc(c.phone) + ' · ' : ''}closer: ${esc(c.closer || '—')}${c.notes ? ' · ' + esc(c.notes) : ''}</div>
      </div>
      ${c.meetLink
        ? `<a class="btn mini pri" target="_blank" rel="noopener" href="${esc(c.meetLink)}"><i class="ph ph-video-camera"></i>Unirse</a>`
        : '<span class="chip gris">sin enlace todavía</span>'}
      <div class="acciones">
        <button class="btn mini" data-editar="${esc(c.id)}">Editar</button>
        <button class="btn mini" data-borrar="${esc(c.id)}">Borrar</button>
      </div>
    </article>`).join('') : '<p class="vacio">Sin citas agendadas.</p>';
  $('#tAgenda').querySelectorAll('[data-editar]').forEach(b => b.onclick = () => cargarCitaEnFormulario(b.dataset.editar));
  $('#tAgenda').querySelectorAll('[data-borrar]').forEach(b => b.onclick = () => borrarCita(b.dataset.borrar));
}

function cargarCitaEnFormulario(id){
  const c = CITAS.find(x => x.id === id); if(!c) return;
  EDITANDO_CITA = id;
  $('#agCitaId').value = id;
  $('#agTelefono').value = c.phone || '';
  $('#agNombre').value = c.name || '';
  $('#agCuando').value = (c.when || '').slice(0, 16);
  $('#agCloser').value = c.closer || '';
  $('#agNotas').value = c.notes || '';
  $('#btnAgendarGuardar').innerHTML = '<i class="ph ph-check"></i>Guardar cambios';
  $('#btnAgendarCancelar').hidden = false;
  $('#v-agenda').scrollIntoView({ behavior: 'auto' });
}

function limpiarFormularioAgenda(){
  EDITANDO_CITA = null;
  ['agCitaId','agTelefono','agNombre','agCuando','agCloser','agNotas'].forEach(id => { $('#' + id).value = ''; });
  $('#btnAgendarGuardar').innerHTML = '<i class="ph ph-calendar-plus"></i>Agendar';
  $('#btnAgendarCancelar').hidden = true;
}

async function guardarCita(){
  const when = $('#agCuando').value;
  if(!when){ toast('Falta la fecha y hora.'); return; }
  const payload = {
    id: EDITANDO_CITA || undefined,
    phone: $('#agTelefono').value.replace(/[^0-9]/g, ''),
    name: $('#agNombre').value.trim(),
    title: 'Llamada de venta',
    when,
    closer: $('#agCloser').value.trim(),
    notes: $('#agNotas').value.trim(),
  };
  try {
    await llamarBot('citas_guardar', payload);
    toast(EDITANDO_CITA ? 'Cita actualizada.' : 'Cita agendada.');
    limpiarFormularioAgenda();
    cargarAgenda();
  } catch(err){ toast('No se pudo guardar la cita: ' + err.message); }
}

async function borrarCita(id){
  if(!confirm('¿Borrar esta cita? Si tiene evento de Calendar, se borra también.')) return;
  try { await llamarBot('citas_borrar', { id }); toast('Cita borrada.'); cargarAgenda(); }
  catch(err){ toast('No se pudo borrar: ' + err.message); }
}

/* ==========================================================================
   ARRANQUE
   ========================================================================== */
$('#nav').addEventListener('click', e => {
  const b = e.target.closest('[data-v]'); if(!b) return;
  ir(b.dataset.v);
});
$('#canales').addEventListener('click', e => {
  const b = e.target.closest('[data-c]'); if(!b) return;
  CANAL = b.dataset.c; pintarPipeline();
});
$('#q').addEventListener('input', e => { BUSCA = e.target.value; pintarPipeline(); });
$('#qb').addEventListener('input', e => { BUSCA_B = e.target.value; pintarBandeja(); });
$('#filtroBandeja').addEventListener('click', e => {
  const b = e.target.closest('[data-fb]'); if(!b) return;
  FILTRO_B = b.dataset.fb;
  $('#filtroBandeja').querySelectorAll('button').forEach(x =>
    x.setAttribute('aria-pressed', String(x === b)));
  pintarBandeja();
});
$('#filtroDueno').addEventListener('click', e => {
  const b = e.target.closest('[data-d]'); if(!b) return;
  FILTRO_DUENO = b.dataset.d;
  $('#filtroDueno').querySelectorAll('button').forEach(x =>
    x.setAttribute('aria-pressed', String(x === b)));
  pintarPipeline();
});
$('#filtroHoy').addEventListener('click', e => {
  const b = e.target.closest('[data-mias]'); if(!b) return;
  SOLO_MIAS = b.dataset.mias === '1';
  $('#filtroHoy').querySelectorAll('button').forEach(x =>
    x.setAttribute('aria-pressed', String(x === b)));
  cargarHoy();
});
$('#btnRefrescar').addEventListener('click', cargar);
$('#btnRefrescarSetter').addEventListener('click', cargarSetter);
$('#btnAgendarGuardar').addEventListener('click', guardarCita);
$('#btnAgendarCancelar').addEventListener('click', limpiarFormularioAgenda);

window.LW_AUTH.then(async ({ sb, session, ficha }) => {
  SB = sb; YO = session && session.user; FICHA = ficha;
  const puedeClosers = !ficha || ficha.rol === 'super_admin' || (ficha.herramientas || []).includes('closers');
  $('#tabAgenda').hidden = !puedeClosers;
  await cargar();
  $('#c-pipeline').textContent = LEADS.length;
  /* La cuenta de «Hoy» se calcula del listado que ya está cargado, sin una llamada más:
     lo que `crm_agenda()` devuelve es exactamente lo mismo filtrado por fecha. */
  actualizarCuentaHoy();
  // Entrada directa a una pestaña desde el hub (`?v=agenda`, herramientas.js).
  const vInicial = new URLSearchParams(location.search).get('v');
  if(vInicial && document.querySelector('#v-' + vInicial) && (vInicial !== 'agenda' || puedeClosers)) ir(vInicial);
});
