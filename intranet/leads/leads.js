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
lwIdiomaAplicar();   // traduce la HTML de index.html; en espanol no toca el DOM

let SB = null, YO = null;
let LEADS = [], ETAPAS = [], CAMPANAS = [], SERIE = [], ACCIONES = [];
/* Arranca en «Hoy» (11-sep-2026, owner). La pregunta con la que se abre esta pantalla
   por la mañana no es «cómo va el embudo», es «a quién llamo». */
let VISTA = 'hoy';
let CANAL = '', BUSCA = '', FILTRO_B = 'todos';
let ABIERTAS = new Set(), ABIERTO = null, SEL_B = null;
let CARGADO = { panel: false, automatismos: false, setter: false, agenda: false };
let FICHA = null;
let CONVERSACIONES = [], CITAS = [], EDITANDO_CITA = null;
let CHAT_ABIERTO = null;   // teléfono del hilo abierto en Setter IA, o null
/* La ficha del lead arranca abierta solo si hay sitio para las tres columnas. Por
   debajo de eso se superpone al chat, y abrirla sola taparía lo que vienes a leer. */
let FICHA_ABIERTA = window.matchMedia('(min-width: 1100px)').matches;
let PUEDE_CLOSERS = false;   // lo fija LW_AUTH al arrancar; gobierna el botón de agendar

/* Las seis columnas. El orden es el del embudo y no se reordena: la posición
   de una tarjeta ES la información. */
const COLS = [
  ['nuevo',      lwT('Nuevo'),      lwT('Acaba de entrar, nadie lo ha tocado')],
  ['contactado', lwT('Contactado'), lwT('Se le ha escrito o llamado')],
  ['visita',     lwT('Visita'),     lwT('Ha visto el terreno o la villa')],
  ['reserva',    lwT('Reserva'),    lwT('Carta de reserva firmada')],
  ['contrato',   lwT('Contrato'),   lwT('Contrato de compraventa firmado')],
  ['perdido',    lwT('Perdido'),    lwT('No sigue adelante')],
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
const canal = s => NOMBRES[s] || s || lwT('sin origen');

/* Un solo umbral y un solo acento. Un semáforo de tres colores en una tarjeta
   pequeña no se lee: se convierte en decoración. */
const DIAS_VIEJO = 14;
const TOPE = 20;

/* Etiquetas de las respuestas del formulario. La base ya recorta a estas cuatro
   claves (las de opción cerrada); aquí solo se les pone nombre en castellano. */
const PREGUNTA = {
  budget_range: lwT('Presupuesto'), budget: lwT('Presupuesto'),
  buy_timeline: lwT('Cuándo compra'), purpose: lwT('Para qué'),
};

/* ---------- utilidades ---------- */
/* `esc` y `toast` vienen de suite-comun.js (se carga antes en index.html). NO
   redeclarar aqui: dos `const`/`function` del mismo nombre en el mismo scope
   global revientan el script entero con «Identifier ya declarado» y ninguna
   de las cuatro vistas llega a pintarse (incidente 10-sep-2026). */
const dias = iso => { const d = new Date(iso); return isNaN(d) ? null : Math.floor((Date.now() - d) / 864e5); };
const fecha = iso => { const d = new Date(iso); return isNaN(d) ? (iso || '')
  : d.toLocaleDateString(lwLocale(), { day:'numeric', month:'short', year:'numeric' }); };
const fechaHora = iso => { const d = new Date(iso); return isNaN(d) ? (iso || '')
  : d.toLocaleString(lwLocale(), { day:'2-digit', month:'short', hour:'2-digit', minute:'2-digit' }); };
const edad = d => d === null ? '' : (d === 0 ? lwT('hoy') : d === 1 ? lwT('ayer') : lwT('%n días', { n: d }));
/* Sin proveedor de tipo de cambio: se pinta la moneda que devuelve Meta, tal
   cual. Un importe convertido a ojo es peor que un importe en rupias. */
const dinero = (n, mon) => n == null ? '—'
  : new Intl.NumberFormat(lwLocale(), { maximumFractionDigits: 0 }).format(Number(n)) + (mon ? ' ' + mon : '');

/* Un `href` construido con texto de un tercero. Solo se dejan pasar los tres
   esquemas que esta herramienta usa; cualquier otra cosa devuelve null y el
   botón no se pinta. */
function enlaceSeguro(url){
  try {
    const u = new URL(url, location.origin);
    return ['https:', 'mailto:', 'tel:'].includes(u.protocol) ? u.href : null;
  } catch(e){ return null; }
}

/* ==========================================================================
   LA URL ES EL ESTADO
   --------------------------------------------------------------------------
   Antes la pestaña vivía solo en memoria: estabas en Setter IA y la barra de
   direcciones seguía diciendo `/intranet/leads/`. Eso rompe tres cosas que la
   gente da por hechas — recargar te devolvía al principio, «atrás» te sacaba de
   la herramienta entera, y no se podía pasar un enlace a un compañero diciendo
   «mira esta conversación».

   Ahora manda el hash y nadie más: pulsar una pestaña NO pinta, solo cambia la
   URL; es `hashchange` quien pinta. Con una sola dirección de flujo no hay forma
   de que la vista y la barra se desincronicen.

     #pipeline · #setter · #agenda …      una vista
     #setter/62881037978255               una vista y un hilo abierto

   El `?v=` que usa el hub (`herramientas.js`) se sigue aceptando y se traduce a
   hash al entrar, para no tener que tocar los enlaces del hub.
   ========================================================================== */
const VISTAS_OCULTABLES = { agenda: '#tabAgenda', closers: '#tabClosers' };

function vistaPermitida(v){
  if(!document.querySelector('#v-' + v)) return false;
  const tab = VISTAS_OCULTABLES[v];
  return !tab || !document.querySelector(tab).hidden;
}

function aplicarRuta(){
  const crudo = decodeURIComponent(location.hash.replace(/^#/, ''));
  const [vPedida, phone] = crudo.split('/');
  const v = vistaPermitida(vPedida) ? vPedida : 'hoy';
  if(v !== VISTA) ir(v);
  // El hilo solo existe dentro de Setter IA; en cualquier otra vista se cierra.
  if(v !== 'setter'){ if(CHAT_ABIERTO) cerrarChat(); return; }
  if(phone && phone !== CHAT_ABIERTO) verConversacion(phone);
  else if(!phone && CHAT_ABIERTO) cerrarChat();
}

window.addEventListener('hashchange', aplicarRuta);

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
  if(v === 'closers') cargarClosers();
}

/* ==========================================================================
   VISTA 7 — CLOSERS (dirección)
   --------------------------------------------------------------------------
   POR QUÉ NO SALE DE `contratos.creado_por`, QUE ERA LO OBVIO. Esa columna es quién pulsó
   «crear» en la intranet, no quién cerró: hay un caso probado donde la reserva la creó una
   persona y su construcción —mismo comprador, mismo negocio— otra distinta. Un ranking así
   mide quién usa más la herramienta. La atribución vive en su propia tabla y se rellena a
   mano una vez sobre el histórico; a partir de ahí se sella al cerrar.

   Y SE ENSEÑAN SIEMPRE LAS DOS CIFRAS, firmado y cobrado, porque no dicen lo mismo: de los
   3,4 M firmados solo ha entrado un 4,7%, y el orden cambia según cuál se mire. El puesto
   lo decide el COBRADO (decisión del owner): premiar la firma es premiar papel sin pagar.
   ========================================================================== */
let RANKING = [], ATRIBUIR = [], SOLO_RAICES = false, SOLO_PENDIENTES = true;
/* Quien gestiona el CRM (tiene `ranking` o `reparto`). Decide que pestanas de
   direccion se ven; la puerta de verdad sigue siendo la de la base. */
let GESTOR_CRM = false, REPARTO = [];

async function cargarClosers(){
  const [r, a, p] = await Promise.all([
    SB.rpc('crm_ranking_closers', { p_solo_raices: SOLO_RAICES }),
    SB.rpc('crm_contratos_para_atribuir', { p_solo_pendientes: SOLO_PENDIENTES }),
    SB.rpc('crm_reparto_config'),
  ]);
  RANKING  = r.error ? [] : (r.data || []);
  ATRIBUIR = a.error ? [] : (a.data || []);
  REPARTO  = p.error ? [] : (p.data || []);
  await cargarEquipo();
  pintarClosers();
  pintarReparto();
}

/* ---------- quién atiende cada campaña ----------
   Lo que se configura es la CAMPAÑA, nunca el lead: se marca quién la atiende y el sistema
   reparte sus leads entre ellos. El reparto elige al que más lejos esté de su cuota, y la
   cuota sale del ranking de arriba — el primero por dinero cobrado recibe el doble que el
   resto. Por eso las dos cosas viven en la misma pantalla: la de abajo configura, la de
   arriba explica por qué a uno le tocan más. */
function pintarReparto(){
  const caja = $('#tReparto'); if(!caja) return;
  const sinConfigurar = REPARTO.filter(x => !x.activo).length;
  $('#subReparto').textContent = REPARTO.length
    ? lwT('%n campañas', { n: REPARTO.length }) + ' · ' + (sinConfigurar
        ? lwT('%n sin reparto automático', { n: sinConfigurar }) : lwT('todas con reparto automático'))
    : lwT('Todavía no ha entrado ningún lead.');

  caja.innerHTML = REPARTO.length ? REPARTO.map(o => {
    const suyos = o.closers || [];
    return `<article class="cita${o.activo ? ' con-meet' : ''}">
      <div class="avatar">${esc(iniciales(canal(o.source)))}</div>
      <div class="cuerpo">
        <div class="quien">${esc(canal(o.source))}</div>
        <div class="sub">${o.leads_totales} leads${
          o.leads_sin_dueno > 0 ? ' · <b>' + o.leads_sin_dueno + ' sin dueño</b>' : ''}</div>
        <div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:9px">
          ${(EQUIPO || []).map(u => {
            const dentro = suyos.some(c => c.toLowerCase() === u.email.toLowerCase());
            return `<button class="btn mini${dentro ? ' pri' : ''}"
              data-rc="${esc(o.source)}" data-mail="${esc(u.email)}" data-dentro="${dentro ? '1' : '0'}">
              ${dentro ? '<i class="ph ph-check"></i>' : ''}${esc(u.nombre || u.email)}</button>`;
          }).join('') || '<span class="chip gris">' + lwT('nadie tiene acceso al CRM todavía') + '</span>'}
        </div>
        ${o.activo && !suyos.length ? `<div class="aviso rojo" style="margin:9px 0 0">
          <b>${lwT('Reparto encendido pero sin nadie asignado.')}</b> ${lwT('Sus leads se quedarán sin dueño.')}</div>` : ''}
      </div>
      <div class="acciones" style="flex-direction:column;align-items:flex-end;gap:7px">
        <label style="display:flex;align-items:center;gap:6px;font:600 12px/1 var(--text);color:var(--mist)">
          <input type="checkbox" data-activo="${esc(o.source)}" ${o.activo ? 'checked' : ''}>
          ${lwT('Reparto automático')}
        </label>
        <label style="display:flex;align-items:center;gap:6px;font:500 11.5px/1 var(--text);color:var(--mist)">
          tope
          <input type="number" min="1" max="50" value="${o.tope_sin_contactar}"
            data-tope="${esc(o.source)}" style="width:56px;padding:4px 6px;border:1px solid var(--line);border-radius:var(--r-ctrl)">
        </label>
      </div>
    </article>`;
  }).join('') : '<p class="vacio">' + lwT('Todavía no ha entrado ningún lead, así que no hay campañas que configurar.') + '</p>';

  caja.querySelectorAll('[data-rc]').forEach(b => b.onclick = () =>
    marcarCloser(b.dataset.rc, b.dataset.mail, b.dataset.dentro !== '1'));
  caja.querySelectorAll('[data-activo]').forEach(c => c.onchange = () =>
    guardarOrigen(c.dataset.activo, c.checked, null));
  caja.querySelectorAll('[data-tope]').forEach(i => i.onchange = () =>
    guardarOrigen(i.dataset.tope, null, Number(i.value)));
}

async function marcarCloser(source, email, incluir){
  const { error } = await SB.rpc('crm_reparto_closer_set',
    { p_source: source, p_email: email, p_incluir: incluir });
  /* El mensaje de la base se enseña tal cual: el más probable es «no puedes añadirte a ti
     mismo a un origen», que es una regla de negocio, no un fallo — y explicarla con otras
     palabras aquí sería tener la regla escrita en dos sitios. */
  if(error){ toast(error.message); return; }
  cargarClosers();
}

async function guardarOrigen(source, activo, tope){
  const { error } = await SB.rpc('crm_reparto_origen_set',
    { p_source: source, p_activo: activo, p_tope: tope, p_dias: null });
  if(error){ toast(lwT('No se pudo guardar: ') + error.message); return; }
  toast(lwT(activo === true ? 'Reparto automático encendido.'
      : activo === false ? 'Reparto automático apagado.' : 'Tope guardado.'));
  cargarClosers();
}

function pintarClosers(){
  const sinAtribuir = RANKING.find(x => x.closer_email === '(sin atribuir)');
  const conNombre   = RANKING.filter(x => x.closer_email !== '(sin atribuir)');
  const firmado = RANKING.reduce((s, x) => s + Number(x.firmado || 0), 0);
  const cobrado = RANKING.reduce((s, x) => s + Number(x.cobrado || 0), 0);
  const pct = firmado ? Math.round(cobrado / firmado * 1000) / 10 : 0;

  $('#kpis-closers').innerHTML = `
    <div class="kpi"><div class="rot">${lwT('Firmado')}<i class="ph ph-file-text"></i></div>
      <p class="cifra">${dinero(Math.round(firmado), 'EUR')}</p>
      <p class="pie">${RANKING.reduce((s, x) => s + Number(x.contratos || 0), 0)} contratos</p></div>
    <div class="kpi fuerte"><div class="rot">${lwT('Cobrado')}<i class="ph ph-coins"></i></div>
      <p class="cifra">${dinero(Math.round(cobrado), 'EUR')}</p>
      <p class="pie">${pct}% de lo firmado ha entrado</p></div>
    <div class="kpi"><div class="rot">${lwT('Comerciales')}<i class="ph ph-users-three"></i></div>
      <p class="cifra">${conNombre.length}</p>
      <p class="pie">${lwT('con al menos una venta atribuida')}</p></div>`;

  /* El aviso no es decorativo: mientras queden ventas sin atribuir, el ranking está
     incompleto y decir lo contrario sería mentir con una tabla bien maquetada. */
  const av = $('#avisoAtribucion');
  if(sinAtribuir && sinAtribuir.contratos > 0){
    av.hidden = false;
    av.innerHTML = `<b>${lwT('El ranking todavía no está completo.')}</b> ${lwT('Hay')}
      <b>${sinAtribuir.contratos} ventas sin atribuir</b> (${dinero(Math.round(sinAtribuir.firmado), 'EUR')}
      firmados) que no cuentan para nadie. Se asignan abajo, en «A quién se atribuye cada venta».`;
  } else av.hidden = true;

  $('#subRanking').textContent = SOLO_RAICES
    ? lwT('Contando solo el contrato raíz de cada cadena. El puesto lo decide el dinero cobrado.')
    : lwT('Contando todo lo firmado, cadenas incluidas. El puesto lo decide el dinero cobrado.');

  $('#tRanking').innerHTML = `
    <thead><tr><th></th><th>${lwT('Comercial')}</th><th class="num">${lwT('Cobrado')}</th><th class="num">${lwT('Firmado')}</th>
      <th class="num">${lwT('Ventas')}</th><th class="num">${lwT('Ticket medio')}</th></tr></thead>
    <tbody>${RANKING.length ? RANKING.map(x => {
      const sin = x.closer_email === '(sin atribuir)';
      const conv = Number(x.firmado) ? Math.round(Number(x.cobrado) / Number(x.firmado) * 100) : 0;
      return `<tr${x.es_tuyo ? ' style="background:var(--primary-soft)"' : ''}>
        <td class="num">${sin ? '—' : (x.puesto === 1 ? '<i class="ph ph-trophy" style="color:var(--gold)"></i> 1' : x.puesto)}</td>
        <td><b>${esc(sin ? lwT('Sin atribuir') : (x.closer_nombre || x.closer_email))}</b>
          ${x.es_tuyo ? '<span class="chip verde" style="margin-left:6px">' + lwT('tú') + '</span>' : ''}
          ${x.encadenados > 0 ? `<div style="font-size:11.5px;color:var(--mist)">${x.encadenados} de cadena</div>` : ''}</td>
        <td class="num"><b>${dinero(Math.round(x.cobrado || 0), 'EUR')}</b>
          <div style="font-size:11.5px;color:var(--mist)">${conv}% de lo suyo</div></td>
        <td class="num">${dinero(Math.round(x.firmado || 0), 'EUR')}</td>
        <td class="num">${x.contratos}</td>
        <td class="num">${dinero(Math.round(x.ticket_medio || 0), 'EUR')}</td>
      </tr>`;
    }).join('') : '<tr><td colspan="6"><p class="vacio">' + lwT('Todavía no hay ninguna venta atribuida.') + '</p></td></tr>'}</tbody>`;

  pintarAtribuir();
}

function pintarAtribuir(){
  $('#subAtribuir').textContent = SOLO_PENDIENTES
    ? lwT(ATRIBUIR.length === 1 ? '%n venta sin atribuir' : '%n ventas sin atribuir', { n: ATRIBUIR.length })
    : lwT('%n ventas firmadas en total', { n: ATRIBUIR.length });

  $('#tAtribuir').innerHTML = `
    <thead><tr><th>${lwT('Contrato')}</th><th>${lwT('Comprador')}</th><th class="num">${lwT('Importe')}</th>
      <th class="num">${lwT('Cobrado')}</th><th>${lwT('Quién lo cerró')}</th></tr></thead>
    <tbody>${ATRIBUIR.length ? ATRIBUIR.map(c => `
      <tr>
        <td><b>${esc(c.numero || '')}</b>
          <div style="font-size:11.5px;color:var(--mist)">${esc(c.proyecto || '')}${
            c.es_hijo ? ' · <span class="chip gris">' + lwT('de cadena') + '</span>' : ''}</div></td>
        <td>${esc(c.comprador || 'sin nombre')}</td>
        <td class="num">${dinero(Math.round(c.precio_total || 0), c.moneda || 'EUR')}</td>
        <td class="num">${Number(c.cobrado) ? dinero(Math.round(c.cobrado), c.moneda || 'EUR') : '—'}</td>
        <td>
          <select class="sui-sel" data-atrib="${esc(c.contrato_id)}" data-previo="${esc(c.closer_email || '')}">
            <option value="">${lwT('— sin atribuir —')}</option>
            ${(EQUIPO_TODO || []).map(u => `<option value="${esc(u.email)}"${
              c.closer_email && u.email.toLowerCase() === c.closer_email.toLowerCase() ? ' selected' : ''
            }>${esc(u.nombre || u.email)}</option>`).join('')}
          </select>
          ${c.creado_por && !c.closer_email
            ? `<div style="font-size:11px;color:var(--mist);margin-top:3px">lo creó ${esc(c.creado_por)}</div>` : ''}
        </td>
      </tr>`).join('') : '<tr><td colspan="5"><p class="vacio">' + lwT('Todas las ventas están atribuidas.') + '</p></td></tr>'}</tbody>`;

  $('#tAtribuir').querySelectorAll('[data-atrib]').forEach(s => s.onchange = () => atribuir(s));
}

async function atribuir(sel){
  sel.disabled = true;
  const { error } = await SB.rpc('crm_contrato_closer_set', {
    p_contrato: sel.dataset.atrib,
    p_email: sel.value || null,
    p_previo: sel.dataset.previo || null,
  });
  sel.disabled = false;
  if(error){
    if(String(error.code) === '409' || /ya no es la que tenias/i.test(error.message || '')){
      toast(lwT('Otra persona ha cambiado esa atribución. Recargo.'));
      return cargarClosers();
    }
    toast(lwT('No se pudo guardar: ') + error.message);
    return cargarClosers();
  }
  sel.dataset.previo = sel.value || '';
  /* Se recarga entero y no solo la fila: cambiar una atribución mueve el ranking de arriba,
     y dejar la tabla de puestos desfasada mientras se rellena el histórico es justo lo que
     haría desconfiar de la cifra. */
  cargarClosers();
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
  caja.innerHTML = '<p class="vacio">' + lwT('Cargando…') + '</p>';
  const { data, error } = await SB.rpc('crm_agenda', { p_solo_mias: SOLO_MIAS });
  if(error){ caja.innerHTML = '<p class="vacio">No se pudo leer la agenda: ' + esc(error.message) + '</p>'; return; }
  HOY = data || [];
  pintarHoy();
}

function pintarHoy(){
  const vencidas = HOY.filter(a => a.dias_de_retraso > 0).length;
  $('#kpis-hoy').innerHTML = `
    <div class="kpi fuerte"><div class="rot">${lwT('Para hoy')}<i class="ph ph-flag"></i></div>
      <p class="cifra">${HOY.length}</p><p class="pie">${lwT(SOLO_MIAS ? 'tuyas' : 'de todo el equipo')}</p></div>
    <div class="kpi"><div class="rot">${lwT('Con retraso')}<i class="ph ph-warning-circle"></i></div>
      <p class="cifra oro">${vencidas}</p><p class="pie">${lwT('deberían estar hechas')}</p></div>`;

  const caja = $('#listaHoy');
  if(!HOY.length){
    caja.innerHTML = `<p class="vacio">Nada pendiente para hoy.${
      ' ' + lwT(SOLO_MIAS ? 'Prueba a mirar las de todo el equipo.' : 'El próximo paso se pone desde la ficha de cada lead.')}</p>`;
    return;
  }
  caja.innerHTML = HOY.map(a => `
    <article class="cita${a.dias_de_retraso > 0 ? ' urge' : ''}" data-lead="${esc(a.lead_id)}">
      <div class="avatar">${esc(iniciales(a.nombre))}</div>
      <div class="cuerpo">
        <div class="cuando">${a.dias_de_retraso > 0
          ? esc(lwT(a.dias_de_retraso === 1 ? '%n día de retraso' : '%n días de retraso', { n: a.dias_de_retraso }))
          : lwT('Hoy')}</div>
        <div class="quien">${esc(a.nombre || 'sin nombre')}</div>
        <div class="sub">${esc(a.que)} · ${esc(canal(a.source))}${
          SOLO_MIAS ? '' : ' · ' + esc(a.responsable || '')}</div>
      </div>
      <div class="acciones">
        <button class="btn mini" data-abrir="${esc(a.lead_id)}">${lwT('Abrir ficha')}</button>
        <button class="btn mini pri" data-hecho="${esc(a.accion_id)}"><i class="ph ph-check"></i>${lwT('Hecho')}</button>
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
    if(error){ toast(lwT('No se pudo cerrar: ') + error.message); b.disabled = false; return; }
    const fila = HOY.find(a => a.accion_id === b.dataset.hecho);
    const lead = fila && LEADS.find(x => x.id === fila.lead_id);
    if(lead){ lead.accion_id = lead.accion_que = lead.accion_cuando = lead.accion_responsable = null; }
    HOY = HOY.filter(a => a.accion_id !== b.dataset.hecho);
    pintarHoy(); pintarPipeline(); actualizarCuentaHoy();
  });
}

/* ---------- qué alcance tengo, y por qué ----------
   Desde el 11-sep la campaña decide qué leads ve cada uno. Eso deja un caso nuevo que ANTES
   no existía: alguien con la casilla «Leads» y sin ninguna campaña asignada abre la
   herramienta y no ve nada. Sin este aviso, eso se lee como que el CRM está roto — y la
   persona escribe para preguntar, o peor, deja de abrirlo.
   El número sale de la base (`crm_mi_alcance`), no de contar lo que llegó: si algún día el
   filtro falla, aquí se vería el desajuste en vez de taparlo. */
async function pintarAlcance(){
  const av = $('#avisoAlcance');
  const { data, error } = await SB.rpc('crm_mi_alcance');
  if(error || !data || !data.length){ av.hidden = true; return; }
  const a = data[0];
  if(a.es_gestor){ av.hidden = true; return; }   // dirección lo ve todo: no hay nada que explicar

  const cuantas = (a.campanas || []).length;
  if(!cuantas){
    av.hidden = false;
    av.className = 'aviso oro';
    av.innerHTML = '<b>' + lwT('Todavía no tienes ninguna campaña asignada.') + '</b> Por eso esta pantalla '
      + lwT('aparece vacía: verás los leads en cuanto dirección te asigne una. No es un fallo de la herramienta.');
    return;
  }
  av.hidden = false;
  av.className = 'aviso gris';
  av.innerHTML = lwT(cuantas === 1 ? 'Ves los leads de tu campaña' : 'Ves los leads de tus %n campañas', { n: cuantas })
    + ': <b>' + (a.campanas || []).map(c => esc(canal(c))).join(' · ') + '</b>'
    + ' — ' + lwT(a.leads_visibles === 1 ? '%n lead' : '%n leads', { n: a.leads_visibles }) + '. '
    + lwT('Los de otras campañas los llevan otras personas.');
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
    toast(lwT('No se pudieron leer los leads: ') + (err.message || err));
    $('#tablero').innerHTML = '<p class="vacio">' + lwT('No se pudo leer la lista. Recarga la página.') + '</p>';
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
    <div class="kpi"><div class="rot">${lwT('Leads')}<i class="ph ph-users"></i></div>
      <p class="cifra">${f.length}</p><p class="pie">${CANAL ? esc(canal(CANAL)) : lwT('todos los canales')}</p></div>
    <div class="kpi"><div class="rot">${lwT('Sin contactar')}<i class="ph ph-envelope-simple"></i></div>
      <p class="cifra">${sin}</p><p class="pie">${parados} llevan más de ${DIAS_VIEJO} días parados</p></div>
    <div class="kpi"><div class="rot">${lwT('Reserva o contrato')}<i class="ph ph-signature"></i></div>
      <p class="cifra oro">${cerrados}</p><p class="pie">de ${f.length} leads</p></div>
    <div class="kpi fuerte"><div class="rot">${lwT('Conversión')}<i class="ph ph-trend-up"></i></div>
      <p class="cifra">${conv}%</p><p class="pie">llegan a firmar</p></div>
    ${sug ? `<div class="kpi"><div class="rot">${lwT('Por confirmar')}<i class="ph ph-flag"></i></div>
      <p class="cifra oro">${sug}</p><p class="pie">${lwT('han firmado y siguen en otra columna')}</p></div>` : ''}`;
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
  av.innerHTML = '<b>' + lwT('Hay tipos de contrato sin columna asignada.') + '</b> Quien firme uno de esos '
    + lwT('no aparecerá sugerido en Reserva ni en Contrato: ') + ' ' + esc([...new Set(sin)].join(', '))
    + '. ' + lwT('Se arregla desde el estudio, añadiendo su fila en') + ' <code>contrato_tipo_etapa</code>.';
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
  /* `en-CA` NO es el idioma de nadie aqui: es el truco para que `format()`
     devuelva AAAA-MM-DD. No pasa por `lwLocale()` a proposito — esto es una
     CLAVE de fecha en hora de Bali, no un texto que alguien lea. */
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
  : n === -1 ? lwT('ayer') : n === 0 ? lwT('hoy') : n === 1 ? lwT('mañana') : lwT('en %n días', { n });

/* La línea del dueño en la tarjeta. Tres estados y cada uno dice una cosa distinta:
   · sin dueño  → botón «Es mío»: el 97% de las tarjetas hoy, y es la acción que se espera.
   · mío        → nada llamativo, solo el nombre en verde. Si todas las mías gritaran, el
                  tablero entero sería ruido.
   · de otro    → su nombre, gris. Y si esa persona está desactivada, en rojo: ese lead
                  está huérfano de hecho aunque la columna diga lo contrario, y alguien
                  tiene que reasignarlo (hallazgo de Datos: el dueño muere con el usuario). */
function duenoHTML(l){
  if(!l.dueno) return `<button class="btn mini reclamar" data-mio="${esc(l.id)}"><i class="ph ph-hand-grabbing"></i>${lwT('Es mío')}</button>`;
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
        toast(lwT('Ese lead ha cambiado de manos mientras mirabas. Recargo.'));
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
    toast(!fila.responsable ? lwT('Lead devuelto al montón.')
      : (fila.responsable.toLowerCase() === yoSoy() ? lwT('Ya es tuyo.') : lwT('Asignado a %q', { q: fila.responsable })));
    pintarPipeline(); pintarBandeja();
    if(ABIERTO && ABIERTO.id === lead.id) abrirFicha(lead);
  } catch(err){
    toast(lwT('No se pudo cambiar el dueño: ') + (err.message || err));
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
        toast(lwT('Esa tarjeta la ha movido otra persona. Recargo la lista.'));
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
    toast(lwT('No se pudo guardar el cambio: ') + (err.message || err));
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
      <p class="lb">${lwT('Contacto')}</p>
      <div id="contacto">
        <p style="font-size:13px;color:var(--mist);margin:0 0 10px">
          ${l.tiene_email || l.tiene_whatsapp
            ? 'Queda registrado quién consulta los datos de contacto y cuándo.'
            : 'Este lead no dejó ni email ni teléfono.'}</p>
        ${l.tiene_email || l.tiene_whatsapp
          ? '<button class="btn pri" id="verContacto"><i class="ph ph-eye"></i>' + lwT('Ver contacto') + '</button>' : ''}
      </div>
      ${extras ? `<p class="lb">${lwT('Qué contestó en el formulario')}</p>${extras}` : ''}

      <p class="lb">${lwT('Quién lo lleva')}</p>
      <div id="duenoFicha"></div>

      <p class="lb">${lwT('Próximo paso')}</p>
      <div id="proximoPaso"></div>

      <p class="lb">${lwT('Venta')}</p>
      <div id="haciaContrato"></div>

      <p class="lb">${lwT('Estado')}</p>
      <div class="acciones" id="estados" style="display:flex;gap:6px;flex-wrap:wrap">
        ${COLS.map(([k, n]) => `<button class="btn mini" data-e="${k}"
          ${(l.estado || 'nuevo') === k ? 'style="background:var(--primary);border-color:var(--primary);color:#fff"' : ''}
          >${n}</button>`).join('')}
      </div>
      <p class="lb">${lwT('Notas del equipo')}</p>
      <textarea id="nota" placeholder="Qué ha pasado con este lead…"></textarea>
      <div style="margin-top:8px"><button class="btn" id="guardarNota"><i class="ph ph-plus"></i>${lwT('Añadir nota')}</button></div>
      <div id="hilo" style="margin-top:16px"><p class="vacio">${lwT('Cargando actividad…')}</p></div>
      ${FICHA && (FICHA.rol === 'super_admin' || (FICHA.herramientas || []).includes('closers'))
        ? '<p class="lb">' + lwT('Llamada de venta (Fathom.ai)') + '</p><div id="fathom"><p class="vacio">' + lwT('Cargando…') + '</p></div>' : ''}
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
        ${lwT('Nadie lo lleva todavía. Si lo coges, tus tareas y tu «mis leads» lo incluyen.')}</p>
      <div style="display:flex;gap:8px;flex-wrap:wrap">
        <button class="btn pri" id="dfMio"><i class="ph ph-hand-grabbing"></i>${lwT('Es mío')}</button>
        ${soyAdmin ? '<button class="btn" id="dfOtro">' + lwT('Asignar a otra persona') + '</button>' : ''}
      </div>`;
  } else {
    const nombre = l.dueno_nombre || l.dueno;
    caja.innerHTML = `
      <div class="dato"><span>Lo lleva</span><b>${esc(nombre)}${mio ? ' (tú)' : ''}</b></div>
      ${l.dueno_activo === false ? `<div class="aviso rojo" style="margin:10px 0 0">
        <b>${lwT('Esa cuenta está desactivada.')}</b> ${lwT('Este lead está huérfano de hecho: conviene reasignarlo a alguien que lo trabaje.')}</div>` : ''}
      <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:11px">
        ${mio ? '<button class="btn" id="dfSoltar">' + lwT('Soltarlo') + '</button>' : ''}
        ${(mio || soyAdmin) ? '<button class="btn" id="dfOtro">' + lwT('Pasárselo a otra persona') + '</button>' : ''}
        ${(!mio && !soyAdmin) ? `<p style="font-size:12.5px;color:var(--mist);margin:0">
          ${lwT('Lo lleva otra persona. Para cambiarlo, habla con un administrador.')}</p>` : ''}
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
let EQUIPO = null, EQUIPO_TODO = null;
async function cargarEquipo(){
  if(EQUIPO) return EQUIPO;
  const { data, error } = await SB.from('usuarios')
    .select('email, nombre, rol, activo, herramientas').eq('activo', true);
  /* Dos listas distintas a propósito, y conviene no confundirlas:
     · EQUIPO      — a quién se le puede DAR un lead. Tiene que poder verlo, o el lead se
                     apaga en silencio en manos de quien no abre el CRM.
     · EQUIPO_TODO — a quién se le puede ATRIBUIR una venta ya cerrada. Aquí no hace falta
                     que vea el CRM: se está registrando un hecho del pasado, y varias de
                     las ventas del histórico las cerró gente que hoy ni entra aquí. */
  EQUIPO_TODO = error ? [] : (data || []);
  EQUIPO = EQUIPO_TODO.filter(u =>
    u.rol === 'super_admin' || (u.herramientas || []).includes('leads'));
  return EQUIPO;
}

async function formularioAsignar(l){
  const caja = document.querySelector('#duenoFicha'); if(!caja) return;
  caja.innerHTML = '<p class="vacio">' + lwT('Cargando el equipo…') + '</p>';
  const equipo = await cargarEquipo();
  if(!equipo.length){
    caja.innerHTML = `<div class="aviso oro" style="margin:0">
      <b>${lwT('No hay nadie más con acceso al CRM.')}</b> ${lwT('Un administrador tiene que marcar la casilla «Leads» en')} <a href="/intranet/usuarios/" target="_blank" rel="noopener">${lwT('Usuarios')}</a>
      ${lwT('antes de poder repartir leads.')}</div>
      <div style="margin-top:10px"><button class="btn" id="dfVolver">${lwT('Volver')}</button></div>`;
    caja.querySelector('#dfVolver').onclick = () => pintarDuenoFicha(l);
    return;
  }
  caja.innerHTML = `
    <div class="campo"><label for="dfQuien">${lwT('Pasárselo a')}</label>
      <select class="sui-sel" id="dfQuien">
        ${equipo.map(u => `<option value="${esc(u.email)}"${
          l.dueno && u.email.toLowerCase() === l.dueno.toLowerCase() ? ' selected' : ''
        }>${esc(u.nombre || u.email)}</option>`).join('')}
      </select></div>
    <div style="display:flex;gap:8px">
      <button class="btn pri" id="dfGuardar"><i class="ph ph-check"></i>${lwT('Asignar')}</button>
      <button class="btn" id="dfCancelar">${lwT('Cancelar')}</button>
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
           <button class="btn mini" id="ppHecho"><i class="ph ph-check"></i>${lwT('Hecho')}</button>
           <button class="btn mini" id="ppCambiar">${lwT('Cambiar')}</button>
         </div>
       </div>`
    : `<button class="btn" id="ppPoner"><i class="ph ph-flag"></i>${lwT('Poner próximo paso')}</button>`;

  const hecho = caja.querySelector('#ppHecho');
  if(hecho) hecho.onclick = async () => {
    hecho.disabled = true;
    const { error } = await SB.rpc('crm_lead_accion_completar', { p_accion: l.accion_id });
    if(error){ toast(lwT('No se pudo cerrar: ') + error.message); hecho.disabled = false; return; }
    l.accion_id = l.accion_que = l.accion_cuando = l.accion_responsable = null;
    toast(lwT('Hecho. Pon el siguiente paso cuando lo tengas.'));
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
    <div class="campo"><label for="ppQue">${lwT('Qué hay que hacer')}</label>
      <input type="text" id="ppQue" maxlength="280" value="${esc(l.accion_que || '')}" placeholder="Llamar para confirmar presupuesto"></div>
    <div style="display:flex;gap:6px;flex-wrap:wrap;margin:-6px 0 12px">
      ${RAPIDAS.map(t => `<button class="btn mini" data-rap="${esc(t)}">${esc(t)}</button>`).join('')}
    </div>
    <div class="campo"><label for="ppCuando">${lwT('Cuándo')}</label>
      <input type="date" id="ppCuando" value="${esc(l.accion_cuando || hoy)}" min="2026-01-01"></div>
    <div style="display:flex;gap:6px;flex-wrap:wrap;margin:-6px 0 12px">
      <button class="btn mini" data-dia="0">${lwT('Hoy')}</button>
      <button class="btn mini" data-dia="1">${lwT('Mañana')}</button>
      <button class="btn mini" data-dia="3">${lwT('En 3 días')}</button>
      <button class="btn mini" data-dia="7">${lwT('En una semana')}</button>
    </div>
    <div style="display:flex;gap:8px">
      <button class="btn pri" id="ppGuardar"><i class="ph ph-check"></i>${lwT('Guardar')}</button>
      <button class="btn" id="ppCancelar">${lwT('Cancelar')}</button>
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
    if(!que){ toast(lwT('Escribe qué hay que hacer.')); return; }
    if(!cuando){ toast(lwT('Falta la fecha.')); return; }
    const { data, error } = await SB.rpc('crm_lead_accion_poner', {
      p_lead: l.id, p_que: que, p_cuando: cuando,
    });
    if(error){ toast(lwT('No se pudo guardar: ') + error.message); return; }
    const fila = (data || [])[0];
    if(fila){
      l.accion_id = fila.id; l.accion_que = fila.que;
      l.accion_cuando = fila.cuando; l.accion_responsable = fila.responsable;
    }
    toast(lwT('Próximo paso guardado.'));
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
    caja.innerHTML = `<div class="dato"><span>${lwT('Contrato')}</span><b>${esc(l.contrato_numero)}</b></div>
      <div style="margin-top:9px"><a class="btn" href="/contracts/app.html?contrato=${encodeURIComponent(l.contrato_id)}">
        <i class="ph ph-arrow-square-out"></i>${lwT('Abrir el contrato')}</a></div>
      <p style="font-size:12.5px;color:var(--mist);margin:9px 0 0">
        ${lwT('Este lead está enlazado a su contrato de verdad, no por parecido de correo.')}</p>`;
    return;
  }
  caja.innerHTML = `<button class="btn pri" id="haciaContratoBtn"><i class="ph ph-file-plus"></i>${lwT('Crear contrato para este lead')}</button>
    <p style="font-size:12.5px;color:var(--mist);margin:9px 0 0">
      ${lwT('Se abre su ficha de comprador (con los datos que dejó él) y de ahí el contrato.')}</p>`;
  caja.querySelector('#haciaContratoBtn').onclick = () => dialogoHaciaContrato(l);
}

async function dialogoHaciaContrato(l){
  const caja = document.querySelector('#haciaContrato'); if(!caja) return;
  caja.innerHTML = '<p class="vacio">' + lwT('Comprobando…') + '</p>';
  const { data, error } = await SB.rpc('crm_lead_para_contrato', { p_lead: l.id });
  if(error){ caja.innerHTML = '<p class="vacio">No se pudo comprobar: ' + esc(error.message) + '</p>'; return; }
  const d = (data || [])[0];
  if(!d){ caja.innerHTML = '<p class="vacio">' + lwT('No se pudo leer el lead.') + '</p>'; return; }

  const avisos = [];
  if(d.ficha_existente) avisos.push(
    `<div class="aviso gris" style="margin:0 0 10px"><b>${lwT('Ya existe una ficha con ese correo:')}</b> ${esc(d.ficha_existente_nombre || '')}.
     Se usará esa, no se crea otra.</div>`);
  if(d.otros_leads_igual > 0) avisos.push(
    `<div class="aviso oro" style="margin:0 0 10px"><b>${lwT('Ojo:')}</b> hay ${d.otros_leads_igual}
     ${d.otros_leads_igual === 1 ? 'tarjeta más' : 'tarjetas más'} con este mismo correo.
     Puede que sea la misma persona duplicada.</div>`);
  if(!d.email) avisos.push(
    `<div class="aviso rojo" style="margin:0 0 10px"><b>${lwT('Este lead no dejó email.')}</b>
     ${lwT('Una ficha de comprador necesita un identificador, así que hay que darla de alta a mano en')} <a href="/intranet/compradores/?nuevo=1" target="_blank" rel="noopener">${lwT('Compradores')}</a>.</div>`);

  caja.innerHTML = avisos.join('') + `
    <div class="dato"><span>${lwT('Nombre')}</span><b>${esc(d.nombre || 'sin nombre')}</b></div>
    <div class="dato"><span>${lwT('Email')}</span><b>${esc(d.email || 'no dejó')}</b></div>
    <div class="dato"><span>${lwT('Teléfono')}</span><b>${esc(d.whatsapp || 'no dejó')}</b></div>
    <div style="display:flex;gap:8px;margin-top:12px;flex-wrap:wrap">
      ${d.email ? `<button class="btn pri" id="hcSeguir"><i class="ph ph-arrow-right"></i>${
        d.ficha_existente ? 'Usar esa ficha y abrir el contrato' : 'Crear ficha y abrir el contrato'}</button>` : ''}
      <button class="btn" id="hcCancelar">${lwT('Cancelar')}</button>
    </div>`;
  caja.querySelector('#hcCancelar').onclick = () => pintarHaciaContrato(l);
  const seguir = caja.querySelector('#hcSeguir');
  if(seguir) seguir.onclick = async () => {
    seguir.disabled = true;
    const { data: f, error: e2 } = await SB.rpc('crm_lead_ficha_crear', { p_lead: l.id });
    if(e2){ toast(lwT('No se pudo abrir la ficha: ') + e2.message); seguir.disabled = false; return; }
    const ficha = (f || [])[0];
    if(!ficha || !ficha.client_id){ toast(lwT('No se pudo abrir la ficha.')); seguir.disabled = false; return; }
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
  if(error){ caja.innerHTML = '<p class="vacio">' + lwT('No se pudo leer.') + '</p>'; return; }
  if(!data || !data.length){ caja.innerHTML = '<p class="vacio">' + lwT('Sin llamadas registradas todavía.') + '</p>'; return; }
  caja.innerHTML = data.map(f => `
    <div class="dato" style="display:block;padding:10px 0">
      <div style="font-size:11.5px;color:var(--mist);margin-bottom:4px">${esc(fechaHora(f.procesado_en))}</div>
      ${f.resumen ? `<p style="margin:0 0 6px">${esc(f.resumen)}</p>` : ''}
      ${(f.objeciones || []).length ? '<p class="lb" style="margin:10px 0 4px">' + lwT('Objeciones') + '</p>' +
        f.objeciones.map(o => `<span class="chip rojo" style="margin:2px">${esc(typeof o === 'string' ? o : (o.text || JSON.stringify(o)))}</span>`).join('') : ''}
      ${f.recording_url ? `<div style="margin-top:8px"><a class="btn mini" target="_blank" rel="noopener" href="${esc(f.recording_url)}"><i class="ph ph-play"></i>${lwT('Ver grabación')}</a></div>` : ''}
    </div>`).join('');
}

/* El contacto se pide de uno en uno y la petición queda registrada en la base
   (lead_acceso_log). El registro lo escribe la propia función que entrega el
   dato: uno hecho desde aquí se saltaría apagando el JavaScript. */
async function verContacto(l){
  const caja = document.querySelector('#contacto'); if(!caja) return;
  caja.innerHTML = '<p style="font-size:13px;color:var(--mist);margin:0">' + lwT('Pidiendo…') + '</p>';
  const { data, error } = await SB.rpc('crm_lead_contacto', { p_lead: l.id, p_que: 'contacto' });
  if(error){ caja.innerHTML = '<p class="vacio">' + lwT('No se pudo leer el contacto.') + '</p>'; return; }
  const c = (data || [])[0] || {};
  const tel = (c.whatsapp || '').replace(/[^0-9]/g, '');
  const mail = c.email ? enlaceSeguro('mailto:' + c.email) : null;
  const wa   = tel ? enlaceSeguro('https://wa.me/' + tel) : null;
  caja.innerHTML = `
    <div class="dato"><span>${lwT('Email')}</span><b>${esc(c.email || 'no dejó')}</b></div>
    <div class="dato"><span>${lwT('Teléfono')}</span><b>${esc(c.whatsapp || 'no dejó')}</b></div>
    <div style="display:flex;gap:7px;flex-wrap:wrap;margin-top:11px">
      ${mail ? `<a class="btn" href="${esc(mail)}" data-reg="email"><i class="ph ph-envelope"></i>${lwT('Escribir')}</a>` : ''}
      ${wa ? `<a class="btn oro" target="_blank" rel="noopener" href="${esc(wa)}" data-reg="whatsapp"><i class="ph ph-whatsapp-logo"></i>${lwT('WhatsApp')}</a>` : ''}
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
  if(error){ caja.innerHTML = '<p class="vacio">' + lwT('No se pudo leer la actividad.') + '</p>'; return; }
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
  if(error){ toast(lwT('No se pudo guardar la nota: ') + error.message); return; }
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
  if(!filas.length){ cont.innerHTML = '<div class="caja"><p class="vacio">' + lwT('Ningún lead con ese filtro.') + '</p></div>'; return; }
  cont.innerHTML = `<div class="caja"><div class="tabla-scroll"><table class="tabla">
    <thead><tr><th>${lwT('Lead')}</th><th>${lwT('Origen')}</th><th>${lwT('Estado')}</th><th>${lwT('Última actividad')}</th><th>${lwT('Notas')}</th><th></th></tr></thead>
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
    <div class="kpi"><div class="rot">${lwT('Leads recibidos')}<i class="ph ph-users"></i></div>
      <p class="cifra">${totalLeads}</p><p class="pie">${leads7} en los últimos 7 días</p></div>
    <div class="kpi"><div class="rot">${lwT('Coste por lead')}<i class="ph ph-tag"></i></div>
      <p class="cifra oro">${cpl == null ? '—' : dinero(Math.round(cpl), mon)}</p>
      <p class="pie">${hayGasto ? 'de las campañas medidas' : 'sin datos de gasto todavía'}</p></div>
    <div class="kpi"><div class="rot">${lwT('Invertido')}<i class="ph ph-currency-circle-dollar"></i></div>
      <p class="cifra">${hayGasto ? dinero(gasto, mon) : '—'}</p>
      <p class="pie">${hayGasto ? CAMPANAS.length + ' campañas' : 'pendiente de la primera vuelta'}</p></div>
    <div class="kpi fuerte"><div class="rot">${lwT('Firmas')}<i class="ph ph-signature"></i></div>
      <p class="cifra">${LEADS.filter(l => l.sugerencia).length}</p>
      <p class="pie">${lwT('leads con contrato firmado')}</p></div>`;

  const av = $('#avisoPanel');
  if(!hayGasto){
    av.hidden = false;
    av.innerHTML = '<b>' + lwT('Todavía no hay cifras de gasto.') + '</b> Las trae el vigilante de AxisWorks en su '
      + 'próxima vuelta (cada 4 horas). Los leads de abajo sí son reales y están completos.';
  } else av.hidden = true;

  $('#grafica').innerHTML = grafica();
  $('#subCampanas').textContent = hayGasto
    ? CAMPANAS.length + ' campañas con datos · última actualización ' + fecha(CAMPANAS[0].ultimo)
    : 'Sin datos de campaña todavía.';
  $('#tCampanas').innerHTML = `
    <thead><tr><th>${lwT('Campaña')}</th><th class="num">${lwT('Invertido')}</th><th class="num">${lwT('Leads')}</th>
      <th class="num">${lwT('Coste/lead')}</th><th class="num">${lwT('Clics')}</th><th class="num">${lwT('7 días')}</th></tr></thead>
    <tbody>${CAMPANAS.length ? CAMPANAS.map(c => {
      const cp = c.leads ? Number(c.gasto || 0) / c.leads : null;
      return `<tr><td><b>${esc(c.nombre || c.cliente)}</b><div style="font-size:11.5px;color:var(--mist)">${esc(c.cliente)}</div></td>
        <td class="num">${dinero(c.gasto, c.moneda)}</td>
        <td class="num">${c.leads ?? '—'}</td>
        <td class="num">${cp == null ? '—' : dinero(Math.round(cp), c.moneda)}</td>
        <td class="num">${c.clics ?? '—'}</td>
        <td class="num">${c.leads_7d ?? 0} leads</td></tr>`;
    }).join('') : '<tr><td colspan="6"><p class="vacio">' + lwT('Aún no hay datos de campañas.') + '</p></td></tr>'}</tbody>`;
}

/* Gráfica en SVG a mano: dos series, leads (barras) y gasto (línea). Sin
   librería — la página no puede cargar scripts de fuera y una dependencia más
   para dos series no se sostiene. */
function grafica(){
  if(!SERIE.length) return '<p class="vacio">' + lwT('Sin datos todavía.') + '</p>';
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
      new Date(s.semana).toLocaleDateString(lwLocale(), { day: 'numeric', month: 'short' })}</text>`).join('');

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
    <div class="kpi"><div class="rot">${lwT('Reglas activas')}<i class="ph ph-flow-arrow"></i></div>
      <p class="cifra">${REGLAS.length}</p><p class="pie">${lwT('se revisan cada 4 horas')}</p></div>
    <div class="kpi"><div class="rot">${lwT('Acciones registradas')}<i class="ph ph-list-checks"></i></div>
      <p class="cifra">${ACCIONES.length}</p><p class="pie">${lwT('las últimas que constan')}</p></div>
    <div class="kpi fuerte"><div class="rot">${lwT('Última actuación')}<i class="ph ph-clock"></i></div>
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
    <thead><tr><th>${lwT('Cuándo')}</th><th>${lwT('Campaña')}</th><th>${lwT('Qué hizo')}</th><th>${lwT('Por qué')}</th></tr></thead>
    <tbody>${ACCIONES.length ? ACCIONES.map(a => `<tr>
      <td style="white-space:nowrap">${esc(fechaHora(a.cuando))}</td>
      <td>${esc(a.campana)}</td>
      <td><span class="chip ${/pausa/i.test(a.accion) ? 'rojo' : /reactiv|sube/i.test(a.accion) ? 'verde' : 'gris'}">${esc(a.accion)}</span></td>
      <td>${esc(a.motivo || '')}</td></tr>`).join('')
      : '<tr><td colspan="4"><p class="vacio">' + lwT('Sin actuaciones registradas.') + '</p></td></tr>'}</tbody>`;
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
  if(!r.ok){
    // El codigo numerico de Meta viaja aparte del texto: sin el no se puede traducir
    // el fallo a una frase con accion (ver ERRORES_META).
    const e = new Error(cuerpo.error || ('El bot respondió ' + r.status));
    e.code = cuerpo.code ?? null; e.detalle = cuerpo.detalle || '';
    throw e;
  }
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
  /* Si se entró por un enlace directo (`#setter/62…`), el hilo se abrió ANTES de que
     llegara este listado, así que su cabecera se pintó sin nombre ni estado de IA —
     solo con el teléfono. Ahora que hay datos, se repinta. */
  if(CHAT_ABIERTO) verConversacion(CHAT_ABIERTO);
}

const iniciales = nombre => (nombre || '').trim().split(/\s+/).slice(0, 2).map(p => p[0] || '').join('').toUpperCase() || '?';

function kpisSetter(){
  const activas = CONVERSACIONES.filter(l => !l.paused).length;
  const pausadas = CONVERSACIONES.length - activas;
  $('#kpis-setter').innerHTML = `
    <div class="kpi"><div class="rot">${lwT('Conversaciones')}<i class="ph ph-chats-circle"></i></div>
      <p class="cifra">${CONVERSACIONES.length}</p><p class="pie">${lwT('con el bot de WhatsApp')}</p></div>
    <div class="kpi fuerte"><div class="rot">IA activa<i class="ph ph-robot"></i></div>
      <p class="cifra">${activas}</p><p class="pie">respondiendo sola ahora mismo</p></div>
    <div class="kpi"><div class="rot">${lwT('En pausa')}<i class="ph ph-pause"></i></div>
      <p class="cifra oro">${pausadas}</p><p class="pie">${lwT('las lleva una persona')}</p></div>`;
}

/* Hora corta para la lista: hoy → "14:32", esta semana → "mar", más viejo → "3 sep".
   WhatsApp hace exactamente esto y por un motivo práctico: la fecha completa en cada
   fila no cabe sin empujar al nombre, que es lo que de verdad se busca al escanear. */
function horaCorta(ts){
  if(!ts) return '';
  const d = new Date(ts), ahora = new Date();
  /* round, no floor: los dos extremos están puestos a medianoche, pero en la semana del
     cambio de hora la diferencia es n·24h ± 1h y `floor` devolvería n-1 — un mensaje de
     hoy etiquetado «ayer». Se ve una vez al año y nadie lo relaciona con el DST. */
  const dias = Math.round((ahora.setHours(0,0,0,0) - new Date(ts).setHours(0,0,0,0)) / 86400000);
  if(dias === 0) return d.toLocaleTimeString(lwLocale(), { hour: '2-digit', minute: '2-digit' });
  if(dias === 1) return 'ayer';
  if(dias < 7)   return d.toLocaleDateString(lwLocale(), { weekday: 'short' });
  return d.toLocaleDateString(lwLocale(), { day: 'numeric', month: 'short' });
}

function pintarSetter(){
  kpisSetter();
  const filas = CONVERSACIONES.slice().sort((a, b) => (b.lastInboundAt || 0) - (a.lastInboundAt || 0));
  /* La fila es un div con role=button y NO un <button>, porque lleva dentro otro botón
     —el de pausar— y un <button> dentro de otro es HTML inválido: el navegador deshace
     el anidamiento y la fila se parte en dos. El teclado se cubre a mano más abajo. */
  $('#tSetter').innerHTML = filas.length ? filas.map(l => `
    <div class="wa-fila" role="button" tabindex="0" data-phone="${esc(l.phone)}"
         aria-current="${String(l.phone === CHAT_ABIERTO)}">
      <div class="avatar">${esc(iniciales(l.name))}</div>
      <div class="cuerpo">
        <div class="arriba">
          <span class="quien">${esc(l.name || l.phone || 'sin nombre')}</span>
          <span class="hora">${esc(horaCorta(l.lastInboundAt))}</span>
        </div>
        <div class="abajo">
          <span class="punto ${l.optOut ? 'baja' : l.gated ? 'frenado' : l.paused ? 'pausa' : 'ia'}" title="${
            l.optOut ? 'Pidió la baja (STOP)'
            : l.gated ? 'Modo testing: el bot NO va a contestar a este lead'
            : l.paused ? 'En pausa — la lleva una persona' : 'IA activa'}"></span>
          <span class="previo">${esc(l.lastMessage || 'Sin mensajes todavía')}</span>
        </div>
      </div>
      <button type="button" class="wa-acc" data-pausar="${esc(l.phone)}" data-a="${l.paused ? '0' : '1'}"
              title="${l.paused ? 'Reanudar la IA en esta conversación' : 'Pausar la IA — a partir de ahí contesta una persona'}"
              aria-label="${l.paused ? 'Reanudar IA' : 'Pausar IA'}">
        <i class="ph ${l.paused ? 'ph-play' : 'ph-pause'}"></i>
      </button>
    </div>`).join('') : '<p class="vacio">' + lwT('Sin conversaciones todavía.') + '</p>';

  $('#tSetter').querySelectorAll('.wa-fila').forEach(c => {
    c.onclick = () => irAConversacion(c.dataset.phone);
    c.onkeydown = ev => {
      if(ev.key !== 'Enter' && ev.key !== ' ') return;
      ev.preventDefault();                       // Espacio no debe hacer scroll de la lista
      irAConversacion(c.dataset.phone);
    };
  });
  /* stopPropagation: sin esto, pausar desde la lista abriría además la conversación. */
  $('#tSetter').querySelectorAll('[data-pausar]').forEach(b => b.onclick = ev => {
    ev.stopPropagation();
    pausarLead(b.dataset.pausar, b.dataset.a === '1');
  });
}

/* Abrir un hilo cambia la URL, y es la URL la que abre el hilo (ver aplicarRuta).
   Así el enlace de una conversación se puede pegar en un chat del equipo y el
   botón «atrás» del navegador hace lo que se espera. */
function irAConversacion(phone){
  location.hash = '#setter/' + encodeURIComponent(phone);
}

function cerrarChat(){
  CHAT_ABIERTO = null;
  $('#wa').dataset.abierto = '0';
  $('#wa').dataset.ficha = '0';   // sin conversacion no hay ficha que ensenar
  const c = $('#waChat');
  c.dataset.vacio = '1';
  c.innerHTML = `<div class="wa-nada"><i class="ph ph-chats-circle"></i>
    <p>${lwT('Elige una conversación')}</p>
    <span>${lwT('Los mensajes del bot con cada lead, tal y como los ve el cliente.')}</span></div>`;
  $('#tSetter').querySelectorAll('.wa-fila').forEach(f => f.setAttribute('aria-current', 'false'));
}

async function verConversacion(phone){
  CHAT_ABIERTO = phone;
  const lead = CONVERSACIONES.find(x => x.phone === phone) || { phone };
  $('#wa').dataset.abierto = '1';
  $('#tSetter').querySelectorAll('.wa-fila').forEach(f =>
    f.setAttribute('aria-current', String(f.dataset.phone === phone)));

  const c = $('#waChat');
  c.dataset.vacio = '0';
  c.innerHTML = `
    <div class="wa-cab">
      <button type="button" class="wa-volver" id="waVolver" aria-label="Volver a la lista"><i class="ph ph-arrow-left"></i></button>
      <div class="avatar">${esc(iniciales(lead.name))}</div>
      <div class="cuerpo">
        <div class="quien">${esc(lead.name || 'sin nombre')}</div>
        <div class="sub">+${esc(phone)}</div>
      </div>
      ${lead.optOut
        ? '<span class="chip rojo"><i class="ph ph-prohibit"></i>' + lwT('Baja (STOP)') + '</span>'
        : lead.gated
          ? '<span class="chip oro"><i class="ph ph-flask"></i>' + lwT('Frenada (testing)') + '</span>'
          : lead.paused
            ? '<span class="chip gris"><i class="ph ph-pause"></i>' + lwT('Pausada') + '</span>'
            : '<span class="chip verde"><i class="ph ph-robot"></i> IA activa</span>'}
      <button class="btn mini" data-pausar="${esc(phone)}" data-a="${lead.paused ? '0' : '1'}">
        ${lead.paused ? 'Reanudar IA' : 'Pausar IA'}</button>
      <button type="button" class="btn mini" id="waInfo" aria-pressed="${String(FICHA_ABIERTA)}"
              title="Mostrar u ocultar la ficha del lead"><i class="ph ph-info"></i></button>
    </div>
    <div class="wa-hilo" id="hiloConv"><p class="vacio">${lwT('Cargando…')}</p></div>
    <div class="wa-pie" id="waPie"></div>`;
  $('#waVolver').onclick = () => { location.hash = '#setter'; };
  c.querySelector('[data-pausar]').onclick = ev => {
    const b = ev.currentTarget;
    pausarLead(b.dataset.pausar, b.dataset.a === '1');
  };
  $('#waInfo').onclick = () => {
    FICHA_ABIERTA = !FICHA_ABIERTA;
    $('#wa').dataset.ficha = FICHA_ABIERTA ? '1' : '0';
    $('#waInfo').setAttribute('aria-pressed', String(FICHA_ABIERTA));
  };
  $('#wa').dataset.ficha = FICHA_ABIERTA ? '1' : '0';
  pintarFicha(lead);
  pintarCaja(lead);

  try {
    const historia = await llamarBot('conversacion', { phone });
    if(CHAT_ABIERTO !== phone) return;   // se cambió de conversación mientras cargaba
    pintarHiloChat(historia || []);
  } catch(err){
    if(CHAT_ABIERTO !== phone) return;
    $('#hiloConv').innerHTML = '<p class="vacio">' + lwT('No se pudo leer la conversación.') + '</p>';
  }
}

/* ==========================================================================
   CAJA DE ESCRIBIR DEL COMERCIAL
   --------------------------------------------------------------------------
   Solo aparece cuando el bot NO va a contestar a ese lead — pausado a mano, o
   frenado por el modo testing. Si apareciera con la IA activa, dos voces
   escribirían en el mismo chat y el cliente vería la conversación cruzada.

   LA VENTANA DE 24 h LA DECIDE EL SERVIDOR. `ventanaAbierta`/`ventanaExpira`
   vienen ya resueltos del bot; aquí NO se recalcula con el reloj del navegador,
   porque uno desfasado daría por abierta una ventana cerrada y el mensaje
   rebotaría con un error críptico. Lo de aquí es solo pintura.
   ========================================================================== */
const ERRORES_META = {
  131047: 'Han pasado más de 24 h desde su último mensaje: ya solo se le puede escribir con una plantilla.',
  131026: 'Ese número no tiene WhatsApp.',
  131051: 'Tipo de mensaje no admitido.',
  132000: 'La plantilla espera otro número de datos.',
  132001: 'Esa plantilla no existe en este idioma.',
  132012: 'Un dato de la plantilla tiene un formato que Meta no acepta.',
  132015: 'Esa plantilla está pausada por Meta por baja calidad.',
  132016: 'Esa plantilla está deshabilitada por Meta.',
  131042: 'La cuenta de WhatsApp está restringida por facturación: no sale ningún mensaje.',
  131031: 'La cuenta de WhatsApp está suspendida.',
  190: 'El token de WhatsApp ha caducado. Avisa al estudio.',
  80007: 'Demasiados mensajes seguidos. Espera un momento.',
};
/* Meta devuelve un blob JSON; un comercial ante `{"error":{"message":"(#131047)…"}}`
   no sabe qué hacer. Se traduce a una frase con acción, y solo si no hay traducción
   se enseña el original — nunca en vez de. */
function explicaError(err){
  const txt = String((err && err.message) || err || '');
  const codigo = err && err.code;
  if(codigo && ERRORES_META[codigo]) return ERRORES_META[codigo];
  const m = /\(#(\d+)\)/.exec(txt);
  if(m && ERRORES_META[m[1]]) return ERRORES_META[m[1]];
  if(/opt_out/.test(txt)) return 'Este lead pidió la baja (STOP). No se le puede escribir.';
  if(/lead_desconocido/.test(txt)) return 'Ese teléfono no es un lead de este bot.';
  return 'No se pudo enviar: ' + txt.slice(0, 200);
}

const quedaPara = ts => {
  const h = Math.floor((ts - Date.now()) / 3600000);
  return h >= 1 ? `quedan ${h} h` : 'queda menos de 1 h';
};

function pintarCaja(lead){
  const pie = $('#waPie');
  if(!pie) return;
  const botCalla = lead.paused || lead.gated;

  if(lead.optOut){
    pie.innerHTML = `<p class="wa-aviso rojo"><i class="ph ph-prohibit"></i>
      ${lwT('Este lead pidió la baja (STOP). El sistema no le enviará nada más, ni bot ni persona.')}</p>`;
    return;
  }
  if(!botCalla){
    pie.innerHTML = `<p class="wa-aviso"><i class="ph ph-robot"></i>
      ${lwT('La IA está atendiendo esta conversación.')} <b>${lwT('Pausa la IA')}</b> ${lwT('arriba si quieres contestar tú.')}</p>`;
    return;
  }
  if(lead.ventanaAbierta){
    pie.innerHTML = `
      <div class="wa-caja">
        <textarea id="waTexto" rows="1" placeholder="Escribe tu respuesta…" maxlength="4000"></textarea>
        <button type="button" class="btn pri" id="waEnviar"><i class="ph ph-paper-plane-tilt"></i>${lwT('Enviar')}</button>
      </div>
      <p class="wa-nota">Ventana de WhatsApp abierta — ${esc(quedaPara(lead.ventanaExpira))} para escribir texto libre.</p>`;
    const ta = $('#waTexto');
    // Crece con el texto, como cualquier chat, pero con tope para no comerse el hilo.
    ta.oninput = () => { ta.style.height = 'auto'; ta.style.height = Math.min(ta.scrollHeight, 140) + 'px'; };
    ta.onkeydown = ev => {
      if(ev.key === 'Enter' && !ev.shiftKey){ ev.preventDefault(); enviarTexto(lead.phone); }
    };
    $('#waEnviar').onclick = () => enviarTexto(lead.phone);
    return;
  }
  // Ventana cerrada: el texto libre no se entrega. Se explica y se ofrece la única vía real.
  pie.innerHTML = `
    <p class="wa-aviso oro"><i class="ph ph-clock-countdown"></i>
      ${lead.lastInboundAt
        ? 'Han pasado más de 24 h desde su último mensaje.'
        : 'Este lead nunca ha escrito al bot.'}
      WhatsApp solo permite contactarle con una <b>plantilla aprobada</b>.</p>
    <div class="wa-caja">
      <select id="waPlantilla"><option value="">${lwT('Cargando plantillas…')}</option></select>
      <button type="button" class="btn pri" id="waEnviarP" disabled><i class="ph ph-paper-plane-tilt"></i>${lwT('Enviar')}</button>
    </div>
    <div id="waParams"></div>`;
  cargarPlantillas(lead);
}

let PLANTILLAS = null;
async function cargarPlantillas(lead){
  const sel = $('#waPlantilla');
  try {
    if(!PLANTILLAS) PLANTILLAS = await llamarBot('plantillas');
  } catch(err){
    sel.innerHTML = '<option value="">' + lwT('No se pudieron leer las plantillas') + '</option>';
    return;
  }
  if(!PLANTILLAS.length){
    sel.innerHTML = '<option value="">' + lwT('No hay ninguna plantilla aprobada todavía') + '</option>';
    return;
  }
  /* La CATEGORÍA se enseña porque es dinero: una MARKETING se factura por mensaje.
     Quien elige tiene que saber cuál está eligiendo. */
  sel.innerHTML = '<option value="">' + lwT('Elige una plantilla…') + '</option>' + PLANTILLAS.map((t, i) =>
    `<option value="${i}">${esc(t.name)} · ${esc(t.language)} · ${esc(t.category)}</option>`).join('');
  sel.onchange = () => {
    const t = PLANTILLAS[sel.value];
    const cont = $('#waParams');
    $('#waEnviarP').disabled = !t;
    if(!t){ cont.innerHTML = ''; return; }
    /* Se piden los parámetros exactos ANTES de gastar el envío: mandar una plantilla con
       el número de datos equivocado cuesta un 132000 y el intento ya está consumido. */
    cont.innerHTML = `<p class="wa-previo">${esc(t.body)}</p>` +
      Array.from({ length: t.vars }, (_, i) =>
        `<input class="wa-param" data-i="${i}" placeholder="Dato ${i + 1}" maxlength="300">`).join('');
  };
  $('#waEnviarP').onclick = () => {
    const t = PLANTILLAS[$('#waPlantilla').value];
    if(!t) return;
    const params = [...document.querySelectorAll('.wa-param')].map(i => i.value.trim());
    if(params.some(p => !p)) return toast(lwT('Rellena todos los datos de la plantilla.'));
    enviarPlantilla(lead.phone, t, params);
  };
}

async function enviarTexto(phone){
  const ta = $('#waTexto'); const text = (ta.value || '').trim();
  if(!text) return;
  const btn = $('#waEnviar'); btn.disabled = true; ta.disabled = true;
  try {
    await llamarBot('enviar', { phone, text });
    ta.value = '';
    toast(lwT('Enviado.'));
    await cargarSetter();   // el envío pausa la IA: hay que releer estado, lista y ficha
  } catch(err){
    toast(explicaError(err));
  } finally { btn.disabled = false; ta.disabled = false; }
}

async function enviarPlantilla(phone, t, params){
  const btn = $('#waEnviarP'); btn.disabled = true;
  try {
    await llamarBot('enviar_plantilla', { phone, template: t.name, lang: t.language, params });
    toast(lwT('Plantilla enviada.'));
    await cargarSetter();
  } catch(err){
    toast(explicaError(err));
  } finally { btn.disabled = false; }
}

/* ---------- Ficha del lead, columna derecha del chat ----------
   Todo sale del listado que Setter IA YA tiene cargado (`conversaciones` →
   /admin/api/leads del bot): ni una llamada más, ni un dato del CRM de Postgres.
   Lo que no está, no se dibuja: una fila «Campaña: —» ocupa lo mismo que una con
   dato y no dice nada. */
/* Rotulo de cada intencion; las claves son las que escribe el bot. */
const INTENCION = { exploring: lwT('Explorando'), interested: lwT('Interesado'), booking: lwT('Quiere reservar'), escalate: lwT('Escalado') };
const ESTADO_COM = { won: 'Ganado', lost: 'Perdido', noshow: 'No se presentó' };

function pintarFicha(lead){
  const f = $('#waFicha');
  const filas = [
    [lwT('Intención'),   INTENCION[lead.intent] || lead.intent],
    ['Estado',      ESTADO_COM[lead.status] || lead.status],
    [lwT('País'),        lead.country],
    ['Campaña',     lead.campaign],
    /* travelDate lo extrae el bot de la conversación, así que puede venir en
       cualquier forma ("noviembre", "14/11"...). Se formatea SOLO si es una fecha
       de verdad; si no, se enseña tal cual — inventarle un formato sería perderla. */
    [lwT('Fecha de viaje'), lead.travelDate && !isNaN(new Date(lead.travelDate))
      ? new Date(lead.travelDate).toLocaleDateString(lwLocale(), { day: '2-digit', month: 'short', year: 'numeric' })
      : lead.travelDate],
    [lwT('Primer contacto'), lead.createdAt ? fechaHora(new Date(lead.createdAt).toISOString()) : ''],
    [lwT('Seguimientos enviados'), lead.followups],
  ].filter(([, v]) => v !== undefined && v !== null && v !== '' && v !== 0)
   .map(([k, v]) => `<div class="dato"><span>${esc(k)}</span><b>${esc(v)}</b></div>`).join('');

  const tags = (lead.tags || []).map(t => `<span class="chip gris">${esc(t)}</span>`).join('');
  /* Las citas viven en el historial del lead como eventos type:'appt' — es donde las
     escribe el bot, así que se leen de ahí y no de una segunda fuente. */
  const citas = (lead.history || []).filter(h => h.type === 'appt')
    .sort((a, b) => String(b.when || '').localeCompare(String(a.when || '')))
    .map(h => `<div class="cita con-meet"><div class="cuerpo">
        <div class="cuando">${esc(h.when ? fechaHora(new Date(h.when).toISOString()) : 'sin fecha')}</div>
        <div class="quien">${esc(h.title || lwT('Llamada'))}</div></div></div>`).join('');

  f.innerHTML = `
    <p class="lb">${lwT('El lead')}</p>
    ${filas || '<p class="nada">' + lwT('El bot todavía no ha sacado datos de esta conversación.') + '</p>'}
    ${tags ? `<p class="lb">${lwT('Etiquetas')}</p><div class="etiquetas">${tags}</div>` : ''}
    <p class="lb">${lwT('Notas del bot')}</p>
    ${lead.notes ? `<div class="notas">${esc(lead.notes)}</div>` : '<p class="nada">' + lwT('Sin notas.') + '</p>'}
    <p class="lb">${lwT('Citas')}</p>
    ${citas || '<p class="nada">' + lwT('Ninguna agendada.') + '</p>'}
    ${PUEDE_CLOSERS ? `<button type="button" class="btn pri" id="waAgendar">
        <i class="ph ph-calendar-plus"></i>${lwT('Agendar llamada')}</button>` : ''}`;

  /* Agendar NO abre un formulario nuevo: lleva al de la pestaña Agenda, que ya existe
     con sus siete campos, su validación y su closer por sesión. Duplicarlo aquí sería
     exactamente la deuda que la Regla 0 de la suite prohíbe. */
  const btn = $('#waAgendar');
  if(btn) btn.onclick = () => {
    location.hash = '#agenda';
    $('#agTelefono').value = lead.phone || '';
    $('#agNombre').value = lead.name || '';
    $('#agTelefono').focus();
    toast(lwT('Rellena la fecha y guarda: el teléfono y el nombre ya van puestos.'));
  };
}

function pintarHiloChat(historia){
  const hilo = $('#hiloConv');
  if(!historia.length){ hilo.innerHTML = '<p class="vacio">' + lwT('Sin mensajes.') + '</p>'; return; }
  let ultimoDia = '';
  hilo.innerHTML = historia.map(m => {
    const d = m.ts ? new Date(m.ts) : null;
    const dia = d ? d.toLocaleDateString(lwLocale(), { day: 'numeric', month: 'long', year: 'numeric' }) : '';
    const separador = dia && dia !== ultimoDia ? `<div class="wa-dia">${esc(dia)}</div>` : '';
    if(dia) ultimoDia = dia;
    const entra = m.role === 'user';
    const humana = !entra && m.by === 'human';
    return separador + `<div class="wa-b ${entra ? 'entra' : 'sale'}${humana ? ' humana' : ''}">
      ${humana ? '<span class="firma">' + lwT('Respuesta del equipo') + '</span>' : ''}
      <div class="txt">${esc(m.content || '')}</div>
      <span class="meta">${d ? esc(d.toLocaleTimeString(lwLocale(), { hour: '2-digit', minute: '2-digit' })) : ''}</span>
    </div>`;
  }).join('');
  /* Se abre por el final, como cualquier chat. Pero NO basta con hacerlo aquí: en ese
     instante las fuentes web todavía pueden estar cargando, el texto se remaqueta más
     alto después y el hilo se queda a media altura con el último mensaje cortado (visto
     en el banco de pruebas, 11-sep). Se fija tras el primer frame y otra vez cuando las
     fuentes estén listas — si ya lo estaban, `ready` resuelve en el acto y no cuesta nada. */
  const alFinal = () => { hilo.scrollTop = hilo.scrollHeight; };
  alFinal();
  requestAnimationFrame(alFinal);
  if(document.fonts && document.fonts.ready) document.fonts.ready.then(alFinal);
}

async function pausarLead(phone, paused){
  try {
    await llamarBot('pausar', { phone, paused });
    const l = CONVERSACIONES.find(x => x.phone === phone);
    if(l) l.paused = paused;
    pintarSetter();
    /* La cabecera del hilo abierto lleva su propio chip y su propio botón: sin esto
       seguiría diciendo «IA activa» junto a una conversación que acabas de pausar. */
    if(CHAT_ABIERTO === phone) verConversacion(phone);
    toast(lwT(paused ? 'IA pausada para ese lead.' : 'IA reanudada para ese lead.'));
  } catch(err){ toast(lwT('No se pudo cambiar el estado: ') + err.message); }
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
  catch(err){ CITAS = []; toast(lwT('No se pudieron leer las citas: ') + err.message); }
  pintarAgenda();
}

function kpisAgenda(filas){
  const hoy = new Date(); hoy.setHours(0, 0, 0, 0);
  const futuras = filas.filter(c => new Date(c.when) >= new Date());
  const conMeet = filas.filter(c => c.meetLink).length;
  const proxima = futuras[0];
  $('#kpis-agenda').innerHTML = `
    <div class="kpi"><div class="rot">${lwT('Citas agendadas')}<i class="ph ph-calendar"></i></div>
      <p class="cifra">${filas.length}</p><p class="pie">${futuras.length} todavía por llegar</p></div>
    <div class="kpi"><div class="rot">${lwT('Con Meet listo')}<i class="ph ph-video-camera"></i></div>
      <p class="cifra oro">${conMeet}</p><p class="pie">${filas.length - conMeet} sin enlace automático</p></div>
    <div class="kpi fuerte"><div class="rot">${lwT('Próxima llamada')}<i class="ph ph-clock"></i></div>
      <p class="cifra" style="font-size:19px">${proxima ? esc(fechaHora(proxima.when)) : '—'}</p>
      <p class="pie">${proxima ? esc(proxima.name || proxima.phone || lwT('sin nombre')) : lwT('nada agendado por delante')}</p></div>`;
}

function pintarAgenda(){
  const filas = CITAS.slice().sort((a, b) => new Date(a.when) - new Date(b.when));
  kpisAgenda(filas);
  const hayMeetActivo = filas.some(c => c.meetLink);
  $('#avisoAgendaMeet').hidden = filas.length === 0 || hayMeetActivo;
  $('#subAgenda').textContent = filas.length
    ? lwT(filas.length === 1 ? '%n cita agendada' : '%n citas agendadas', { n: filas.length })
    : lwT('Sin citas agendadas todavía.');
  $('#tAgenda').innerHTML = filas.length ? filas.map(c => `
    <article class="cita${c.meetLink ? ' con-meet' : ''}">
      <div class="avatar">${esc(iniciales(c.name || c.phone))}</div>
      <div class="cuerpo">
        <div class="cuando">${esc(fechaHora(c.when))}</div>
        <div class="quien">${esc(c.name || c.phone || 'sin nombre')}</div>
        <div class="sub">${c.phone ? esc(c.phone) + ' · ' : ''}closer: ${esc(c.closer || '—')}${c.notes ? ' · ' + esc(c.notes) : ''}</div>
      </div>
      ${c.meetLink
        ? `<a class="btn mini pri" target="_blank" rel="noopener" href="${esc(c.meetLink)}"><i class="ph ph-video-camera"></i>${lwT('Unirse')}</a>`
        : '<span class="chip gris">' + lwT('sin enlace todavía') + '</span>'}
      <div class="acciones">
        <button class="btn mini" data-editar="${esc(c.id)}">${lwT('Editar')}</button>
        <button class="btn mini" data-borrar="${esc(c.id)}">${lwT('Borrar')}</button>
      </div>
    </article>`).join('') : '<p class="vacio">' + lwT('Sin citas agendadas.') + '</p>';
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
  if(!when){ toast(lwT('Falta la fecha y hora.')); return; }
  const payload = {
    id: EDITANDO_CITA || undefined,
    phone: $('#agTelefono').value.replace(/[^0-9]/g, ''),
    name: $('#agNombre').value.trim(),
    title: lwT('Llamada de venta'),
    when,
    closer: $('#agCloser').value.trim(),
    notes: $('#agNotas').value.trim(),
  };
  try {
    await llamarBot('citas_guardar', payload);
    toast(lwT(EDITANDO_CITA ? 'Cita actualizada.' : 'Cita agendada.'));
    limpiarFormularioAgenda();
    cargarAgenda();
  } catch(err){ toast(lwT('No se pudo guardar la cita: ') + err.message); }
}

async function borrarCita(id){
  /* `lwConfirmar`, no `confirm()`: el nativo congela la extension de Chrome
     desde la que opera el equipo (regla de contexto/suite_lawang.md). Estaba
     aqui desde el 11-sep y se cambia al pasar a traducir su texto. */
  const seguro = await lwConfirmar({
    titulo: lwT('Borrar esta cita'),
    cuerpo: lwT('Si tiene evento de Calendar, se borra también.'),
    confirmar: lwT('Borrar'), tono: 'peligro',
  });
  if(!seguro) return;
  try { await llamarBot('citas_borrar', { id }); toast(lwT('Cita borrada.')); cargarAgenda(); }
  catch(err){ toast(lwT('No se pudo borrar: ') + err.message); }
}

/* ==========================================================================
   ARRANQUE
   ========================================================================== */
$('#nav').addEventListener('click', e => {
  const b = e.target.closest('[data-v]'); if(!b) return;
  // Solo se mueve la URL. Pintar es cosa de aplicarRuta(), vía hashchange.
  const destino = '#' + b.dataset.v;
  if(location.hash === destino) aplicarRuta();   // mismo hash: hashchange no dispara
  else location.hash = destino;
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
$('#filtroCadenas').addEventListener('click', e => {
  const b = e.target.closest('[data-raices]'); if(!b) return;
  SOLO_RAICES = b.dataset.raices === '1';
  $('#filtroCadenas').querySelectorAll('button').forEach(x =>
    x.setAttribute('aria-pressed', String(x === b)));
  cargarClosers();
});
$('#filtroAtribuir').addEventListener('click', e => {
  const b = e.target.closest('[data-pend]'); if(!b) return;
  SOLO_PENDIENTES = b.dataset.pend === '1';
  $('#filtroAtribuir').querySelectorAll('button').forEach(x =>
    x.setAttribute('aria-pressed', String(x === b)));
  cargarClosers();
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
  PUEDE_CLOSERS = puedeClosers;   // el boton «Agendar llamada» de la ficha del chat va detras de este permiso
  /* SOLO POR CASILLA, no por rol (decisión del owner, 11-sep-2026). La primera versión de
     esta línea dejaba pasar a cualquier `admin` por serlo, y eso metía en la tabla de
     comisiones a los cuatro admins sin que nadie lo hubiera decidido — entre ellos la
     operadora de marketing, que no tiene por qué ver cuánto factura cada comercial. Al
     revés, los sales managers (que sí gestionan ventas) se quedaban fuera.
     El super_admin sigue pasando porque pasa por todo, igual que en el resto de la suite. */
  const puedeRanking = !!ficha && (ficha.rol === 'super_admin' ||
    (ficha.herramientas || []).includes('ranking'));
  const puedeReparto = !!ficha && (ficha.rol === 'super_admin' ||
    (ficha.herramientas || []).includes('reparto'));
  /* «Gestor del CRM» = cualquiera de las dos llaves de dirección. Campañas (gasto en
     publicidad, coste por lead) y Automatismos (lo que hace el vigilante del estudio) no son
     información para un comercial: abre esta herramienta para llamar a gente, no para
     auditar el presupuesto de marketing. Owner, 11-sep-2026. */
  GESTOR_CRM = puedeRanking || puedeReparto;
  $('#tabClosers').hidden = !GESTOR_CRM;
  $('#tabCampanas').hidden = !GESTOR_CRM;
  $('#tabAutomatismos').hidden = !GESTOR_CRM;
  await pintarAlcance();
  await cargar();
  $('#c-pipeline').textContent = LEADS.length;
  /* La cuenta de «Hoy» se calcula del listado que ya está cargado, sin una llamada más:
     lo que `crm_agenda()` devuelve es exactamente lo mismo filtrado por fecha. */
  actualizarCuentaHoy();
  if(VISTA === 'hoy') cargarHoy();
  /* Entrada directa desde el hub (`?v=agenda`, herramientas.js): se traduce a hash y se
     limpia de la barra, para que a partir de ahí exista UNA sola forma de decir dónde
     estás. `replaceState` en vez de asignar location.search: así no recarga la página. */
  const vInicial = new URLSearchParams(location.search).get('v');
  if(vInicial && vistaPermitida(vInicial) && !location.hash){
    history.replaceState(null, '', location.pathname + '#' + vInicial);
  }
  aplicarRuta();
});
