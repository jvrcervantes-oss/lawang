/* node intranet/leads/bot_lectura.test.js — S10 del encargo «bot de Lawang sin Redis» (9-oct-2026).
   Ejecuta el codigo REAL de leads.js (cortado por sus marcas, como propios_permisos.test.js) con un navegador de mentira y afirma:
     1. Un texto del cliente, un nombre, un resumen del bot o una nota con HTML NUNCA llega al DOM como HTML (esc en todo texto de fuera).
     2. El resumen del bot sale marcado con data-tipo="resumen_bot" (el codigo engancha por el identificador, no por el rotulo) y las
        notas sueltas del bot con data-tipo="nota"; las citas llevan data-cita-id y data-estado.
     3. La lectura de Postgres distingue «sin permiso» (42501) de «no se pudo leer» y ninguna se confunde con «sin conversaciones».
     4. Desde el 10-oct-2026 (LAW-513) la lectura es SIEMPRE la de la base: ya no existe el origen 'proxy' (las acciones del proxy se retiraron, 410) ni la vuelta atras a el. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const src = fs.readFileSync(path.join(__dirname, 'leads.js'), 'utf8');
const corta = (ini, fin) => {
  const a = src.indexOf(ini), b = src.indexOf(fin, a + ini.length);
  assert.ok(a > 0 && b > a, 'no encuentro ' + ini + ' … ' + fin + ' en leads.js');
  return src.slice(a, b);
};
const lectura = corta('/* ORIGEN DE LA LECTURA DE CONVERSACIONES', 'async function llamarBot(accion, extra){');
const ficha = corta('const INTENCION =', 'async function pausarLead(');
const kpis = corta('function kpisSetter(){', '/* Hora corta para la lista');
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

function mundo(opts = {}) {
  const celdas = {};
  const elem = sel => celdas[sel] || (celdas[sel] = { innerHTML: '', dataset: {}, hidden: false, querySelectorAll: () => [], setAttribute() {} });
  const ctx = {
    console, Date, String, Object, Array, isNaN, Error, JSON,
    location: { search: opts.search || '' },
    $: elem,
    esc: v => String(v == null ? '' : v).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])),
    lwT: (s, h) => { let t = String(s); Object.keys(h || {}).forEach(k => { t = t.replace('%' + k, h[k]); }); return t; },
    lwLocale: () => 'es-ES',
    fechaHora: iso => 'F(' + iso + ')',
    PUEDE_CLOSERS: false,
    requestAnimationFrame: f => f(), document: { fonts: null },
    CONVERSACIONES: [],
    SB: { rpc: async (nombre, args) => (opts.rpc ? opts.rpc(nombre, args) : { data: null, error: null }) },
    llamarBot: async accion => (opts.proxy ? opts.proxy(accion) : []),
  };
  vm.createContext(ctx);
  vm.runInContext(lectura + '\n' + ficha + '\n' + kpis + '\nthis.__x = { errorBotPg, leerConversaciones, leerHilo, pintarFicha, pintarHiloChat, kpisSetter, BOT_PG, setErr: v => { SETTER_ERROR = v; }, setConv: v => { CONVERSACIONES = v; } };', ctx);
  return { ctx, celdas, x: ctx.__x, elem };
}

(async () => {
  // 1 + 2. la ficha desde la base: nada llega como HTML
  {
    const { x, celdas, elem } = mundo({ search: '?bot=pg' });
    ok(x.BOT_PG === true, '?bot=pg debe abrir la lectura de Postgres');
    x.pintarFicha({
      phone: '628', name: 'N<b>x</b>', intent: 'interested', createdAt: 1790000000000, followups: 2,
      crm: { source: 'bot<script>', project: 'p"q' },
      notasLista: [
        { id: 1, tipo: 'resumen_bot', texto: 'resumen <img src=x onerror=alert(1)> y <script>alert(2)</script>', ts: 1790000000000 },
        { id: 2, tipo: 'nota', texto: 'nota "con" comillas & <b>', ts: null },
      ],
      citasLista: [{ id: 'abc"def', tipo: 'llamada', estado: 'confirmada', que: '<i>llamada</i>', ts: 1790000000000 }],
    });
    const html = elem('#waFicha').innerHTML;
    ['<img', '<script', '<i>llamada', 'N<b>x', 'bot<script', '& <b>'].forEach(t => ok(!html.includes(t), 'HTML de fuera sin escapar en la ficha: ' + t));
    ok(html.includes('&lt;img src=x onerror=alert(1)&gt;'), 'el resumen debe verse como texto');
    ok(/data-tipo="resumen_bot"/.test(html) && /data-tipo="nota"/.test(html), 'las notas llevan data-tipo');
    ok(/data-nota-id="1"/.test(html) && /data-nota-id="2"/.test(html), 'las notas llevan data-nota-id');
    ok(/data-cita-id="abc&quot;def" data-estado="confirmada"/.test(html), 'la cita lleva su id y estado escapados');
    ok(/Resumen del bot/.test(html), 'el resumen se rotula');
    ok(html.includes('bot&lt;script&gt;') && html.includes('p&quot;q'), 'origen y proyecto del CRM escapados');
    ok(html.indexOf('resumen') < html.indexOf('nota &quot;con&quot;'), 'el orden de las notas es el que manda la base');
  }
  // 4. proxy: la ficha de siempre
  {
    const { x, elem } = mundo();
    x.pintarFicha({ phone: '1', notes: 'nota vieja <b>', history: [{ type: 'appt', when: '2026-10-10T10:00:00Z', title: 'Llamada' }] });
    const html = elem('#waFicha').innerHTML;
    ok(html.includes('nota vieja &lt;b&gt;') && !html.includes('vieja <b>') && /class="cita con-meet"/.test(html) && !/data-tipo/.test(html), 'con el origen proxy la ficha sigue igual');
  }
  // 1. el hilo
  {
    const { x, elem } = mundo({ search: '?bot=pg' });
    elem('#hiloConv');
    x.pintarHiloChat([
      { id: 1, role: 'user', by: 'client', content: 'hola <script>alert(1)</script>', ts: 1790000000000 },
      { id: 2, role: 'assistant', by: 'human', byUser: 'ana@x', content: '<img src=x onerror=1>', ts: 1790000100000, media: { tipo: 'image<b>', id: 'm1' } },
    ], true);
    const html = elem('#hiloConv').innerHTML;
    ['<script', '<img', 'image<b>'].forEach(t => ok(!html.includes(t), 'HTML sin escapar en el hilo: ' + t));
    ok(/data-tipo="hay_mas"/.test(html), 'avisa de que solo se ven los ultimos 100');
    ok(/wa-b sale humana/.test(html) && /wa-b entra/.test(html), 'by=human sigue pintando «Respuesta del equipo»');
    ok(html.includes('Adjunto: image&lt;b&gt;'), 'el adjunto se rotula con el tipo escapado');
  }
  // 3. errores
  {
    const sinPermiso = mundo({ search: '?bot=pg', rpc: async () => ({ data: null, error: { code: '42501', message: 'Sin permiso para leer las conversaciones del bot' } }) });
    let e1; try { await sinPermiso.x.leerConversaciones(); } catch (e) { e1 = e; }
    ok(e1 && e1.sinPermiso === true && /No tienes permiso/.test(e1.message), '42501 = sin permiso');
    let e1b; try { await sinPermiso.x.leerHilo('628'); } catch (e) { e1b = e; }
    ok(e1b && e1b.sinPermiso === true, '42501 en el hilo = sin permiso');
    const roto = mundo({ search: '?bot=pg', rpc: async () => ({ data: null, error: { code: '57014', message: 'statement timeout' } }) });
    let e2; try { await roto.x.leerConversaciones(); } catch (e) { e2 = e; }
    ok(e2 && e2.sinPermiso === false && /No se pudo leer: statement timeout/.test(e2.message), 'otro fallo = no se pudo leer, con su causa');
    const bien = mundo({ search: '?bot=pg', rpc: async n => ({ data: n === 'crm_bot_conversaciones' ? { chats: [{ phone: '1' }], hayMas: false } : { mensajes: [{ id: 1 }], hayMas: true, notas: [], citas: [], lead: null, chat: null }, error: null }) });
    ok((await bien.x.leerConversaciones()).length === 1, 'la lista es chats');
    const h = await bien.x.leerHilo('1');
    ok(h.pg === true && h.mensajes.length === 1 && h.hayMas === true, 'el hilo trae mensajes y hayMas');
    // la lectura es SIEMPRE la de la base: el proxy ya no sirve conversaciones (410) y la pantalla no las pide por ahi
    ok(!/const LECTURA_BOT\b/.test(lectura), 'ya no hay interruptor de origen (no hay vuelta atras al proxy)');
    ok(mundo().x.BOT_PG === true, 'la lectura es la de Postgres');
    ok(!/llamarBot\(\s*'conversacion(es)?'/.test(lectura), 'leads.js no pide conversaciones al proxy');
    // el tope por hora (PT429) se explica, no se confunde con «sin permiso»
    const tope = mundo({ rpc: async () => ({ data: null, error: { code: 'PT429', message: 'Demasiadas lecturas' } }) });
    let e3; try { await tope.x.leerConversaciones(); } catch (e) { e3 = e; }
    ok(e3 && e3.sinPermiso === false && /Demasiadas lecturas/.test(e3.message), 'PT429 = demasiadas lecturas, no «sin permiso»');
    // «no se pudo mirar» no se pinta como «0 conversaciones»
    const k = mundo();
    k.x.setErr(true); k.x.kpisSetter();
    ok(k.elem('#kpis-setter').innerHTML === '', 'con error no hay KPIs (un 0 aqui mentiria)');
    k.x.setErr(false); k.x.setConv([]); k.x.kpisSetter();
    ok(/cifra/.test(k.elem('#kpis-setter').innerHTML), 'sin error y sin conversaciones si hay KPIs (0 de verdad)');
  }
  console.log('bot_lectura.test.js OK (' + n + ' comprobaciones)');
})().catch(e => { console.error(e); process.exit(1); });
