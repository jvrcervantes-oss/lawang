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
  if(v === 'setter' && !CARGADO.setter) cargarSetter();
  if(v === 'agenda' && !CARGADO.agenda) cargarAgenda();
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
function visibles(){
  const q = BUSCA.trim().toLowerCase();
  return LEADS.filter(l => {
    if(CANAL && l.source !== CANAL) return false;
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

function tarjetaHTML(l){
  const d = dias(l.estado_desde), viejo = d !== null && d >= DIAS_VIEJO;
  const sug = l.sugerencia && l.sugerencia !== l.estado
    ? `<button class="sug" data-sug="${esc(l.id)}"><i class="ph ph-signature"></i> Firmó `
      + `${esc(COLS.find(c => c[0] === l.sugerencia)?.[1] || l.sugerencia)}`
      + `${l.sugerencia_contrato ? ' · ' + esc(l.sugerencia_contrato) : ''} — mover ahí</button>`
    : '';
  const presu = l.respuestas && (l.respuestas.budget_range || l.respuestas.budget);
  return `<article class="tarjeta${sug ? ' alto' : ''}" draggable="true" data-id="${esc(l.id)}">
    <div class="fila1"><div class="quien">${esc(l.name || 'sin nombre')}</div></div>
    <div class="meta">
      <span class="chip meta">${esc(canal(l.source))}</span>
      <span class="${viejo ? 'viejo' : ''}">${esc(edad(d))}</span>
      ${l.notas ? `<span><i class="ph ph-note"></i> ${l.notas}</span>` : ''}
    </div>
    ${presu ? `<div class="meta"><span class="chip oro">${esc([].concat(presu)[0])}</span></div>` : ''}
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
  pintarHilo(l);
  if(c.querySelector('#fathom')) pintarFathom(l);
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
  // Entrada directa a una pestaña desde el hub (`?v=agenda`, herramientas.js).
  const vInicial = new URLSearchParams(location.search).get('v');
  if(vInicial && document.querySelector('#v-' + vInicial) && (vInicial !== 'agenda' || puedeClosers)) ir(vInicial);
});
