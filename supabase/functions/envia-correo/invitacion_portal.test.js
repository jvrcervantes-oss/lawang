/* node invitacion_portal.test.js — la plantilla «invitacion_portal» («Invitar al portal» desde la ficha de parcela), 15-oct-2026.
   SOLO en Lawang (el maestro no tiene reclamos_pago; plantillas_arnes.mjs → SOLO_LAWANG la saca de las pruebas comunes).
   Migración 20261015101500_invitacion_portal_parcela.sql. Con el index.ts REAL, sin red, sin enviar nada.
   1. Fábrica ⇔ catálogo sellado de la migración (el catálogo es legible, el texto cumple sus reglas, resuelve produce TODAS las permitidas).
   2. Texto aprobado, bilingüe (inglés primero) palabra por palabra; saludo con el nombre de pila (y sin nombre, «Hello» / «Hola»).
   3. El enlace es el del portal (texto y botón, el mismo) y NUNCA lleva token ni #th= (no es un enlace mágico).
   4. La nota: solo si se escribió, una vez, ESCAPADA en el HTML; la regla espejo de _nota_correo_limpia (enlaces, @, dominios,
      6 dígitos, control, 300) se repite aquí. El nombre de la ficha también sale escapado.
   5. El destinatario y el contrato salen de la base; vars solo admite `invitacion`; solo con el secreto del servicio y sin sociedad.
   6. reclamo_pago sigue exigiendo la sociedad (Seguridad #357: el cambio a `soloServicio` no puede aflojarlo). */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

(async () => {
  const A = await import('./arnes.mjs');
  const V = await import('./valida.ts');
  const F = await import('./plantillas_fabrica.ts');
  const N = await import('./nota_correo.ts');
  let n = 0;
  const ok = (c, m) => { assert.ok(c, m); n++; };
  const igual = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++; };

  const mig = fs.readFileSync(path.join(__dirname, '..', '..', 'migrations', '20261015101500_invitacion_portal_parcela.sql'), 'utf8');
  const cat = V.catalogoDe(JSON.parse(/values \('invitacion_portal', false,\s*'(\{"permitidas".*?\})'::jsonb/s.exec(mig)[1]));
  ok(cat, 'el catálogo sembrado se lee (catalogoDe != null: lleva cuerpo_alt y variantes)');

  // ── 1 · fábrica ⇔ catálogo ──────────────────────────────────────────────────────────────
  const t = F.textoFabrica('invitacion_portal');
  ok(t && t.cuerpo_alt === null && cat.variantes === 1, 'hay texto de fábrica de una variante');
  igual(V.validaTextoPlantilla(t.asunto, 'asunto', cat), [], 'asunto cumple el catálogo');
  igual(V.validaTextoPlantilla(t.cuerpo, 'cuerpo', cat), [], 'cuerpo cumple el catálogo');
  ok(V.esClavePlantilla('invitacion_portal') && V.PLANTILLAS.invitacion_portal.soloServicio === true, 'está en PLANTILLAS y solo por servicio');
  ok(V.PLANTILLAS.reclamo_pago.soloServicio === true, 'reclamo_pago también marcado soloServicio');

  const ID_C = '11111111-1111-4111-8111-111111111111', ID_I = '66666666-6666-4666-8666-666666666666';
  const PORTAL = 'https://lawangproperties.com/portal/';
  const comun = { marca: 'Lawang', portal: PORTAL, dominio: 'lawangproperties.com' };
  let datos;   // lo que contesta invitacion_portal_datos
  const base = () => ({ invitacion_id: ID_I, para: 'Ben@Cliente.es', nombre: 'BEN OCEAN', parcela: 'SH-1', proyecto: 'Sumba Hills', nota: null, contrato_id: ID_C });
  const rest = async (ruta) => {
    ok(/^rpc\/invitacion_portal_datos\?p_cola=[0-9a-f-]{36}$/.test(ruta), 'única consulta: la RPC por el id de la fila · ' + ruta);
    return datos === null ? [] : [datos];
  };
  const res = (extraVars = {}, to = 'ben@cliente.es', ids = { contrato_id: ID_C, factura_id: '', firma_id: '' }) =>
    F.resuelve('invitacion_portal', ids, to, { invitacion: ID_I, ...extraVars }, rest, comun);

  datos = base();
  let r = await res();
  ok(!V.esFallo(r), 'resuelve compone · ' + JSON.stringify(r));
  for (const v of cat.permitidas) ok(typeof r.vars[v] === 'string', 'resuelve produce {{' + v + '}}');
  igual(Object.keys(r.vars).sort(), [...cat.permitidas].sort(), 'y solo esas');
  igual(r.cta, null, 'botón por defecto: el del portal');

  // ── 2 · texto aprobado, bilingüe ─────────────────────────────────────────────────────────────
  const c = V.componeCorreo(t, r.variante, r.vars);
  igual(c.subject, 'Your Lawang client portal invitation · Tu invitación al portal de cliente de Lawang', 'asunto');
  igual(c.message,
    'Hi Ben,\n\nHere is your invitation to your Lawang client portal. There you can see the contract for your plot SH-1 in Sumba Hills, your payments and your documents.' +
    '\n\nTo sign in, open ' + PORTAL + ' and enter this same email address: we\'ll send you an access link right away. If it doesn\'t arrive within a few minutes, just request it again a little later.' +
    '\n\nPlease take a moment to check that everything is correct. If anything looks wrong, just reply to this email and we\'ll fix it. We will never ask you for your password or card details by email.' +
    '\n\nWarm regards,\nThe Lawang team' +
    '\n\n—\n\n' +
    'Hola Ben:\n\nAquí tienes la invitación a tu portal de cliente de Lawang. Ahí puedes ver el contrato de tu parcela SH-1 en Sumba Hills, tus pagos y tus documentos.' +
    '\n\nPara entrar, abre ' + PORTAL + ' y escribe este mismo correo: te enviaremos al momento un enlace de acceso. Si no te llega en unos minutos, vuelve a pedirlo un poco más tarde.' +
    '\n\nRevisa con calma que todo esté bien. Si ves algo que no cuadra, respóndenos a este correo y lo corregimos. Nunca te pediremos tu contraseña ni datos de tarjeta por correo.' +
    '\n\nUn abrazo,\nEl equipo de Lawang', 'cuerpo aprobado, sin nota, palabra por palabra');
  datos = { ...base(), nombre: '   ' }; r = await res();
  const sn = V.componeCorreo(t, r.variante, r.vars);
  ok(sn.message.startsWith('Hello,\n\n') && sn.message.includes('\n\nHola:\n\n'), 'sin nombre: «Hello,» y «Hola:»');

  // ── 3 · la nota y su regla espejo ──────────────────────────────────────────────────────────────
  const NOTA = 'Cualquier duda: "Ana" & l\'equipo <b>x</b>';
  datos = { ...base(), nota: NOTA }; r = await res();
  const cn = V.componeCorreo(t, r.variante, r.vars);
  ok(cn.message.startsWith(NOTA + '\n\nHi Ben,'), 'la nota va una vez, arriba, como párrafo propio');
  igual(cn.message.split(NOTA).length, 2, 'la nota no se repite en la parte en español');
  for (const mala of ['mira http://x', 'en www.algo', 'a@b', 'paga en evil.ly', 'cuenta 1234567', 'x'.repeat(301), 'a\u0007b']) {
    datos = { ...base(), nota: mala }; r = await res(); ok(V.esFallo(r) && r.status === 400, 'nota rechazada: ' + JSON.stringify(mala.slice(0, 20)));
    ok(!N.notaCorreoValida(mala.replace(/\s+/g, ' ').trim()), 'notaCorreoValida la rechaza: ' + JSON.stringify(mala.slice(0, 20)));
  }
  for (const buena of ['Quedan 2.000 EUR pendientes', 'x'.repeat(300), 'Hola, ¿qué tal? Firma el 12/10.']) ok(N.notaCorreoValida(buena), 'nota válida: ' + buena.slice(0, 20));
  // la regla es la misma que la de la base: sus cinco piezas están en la migración
  for (const pieza of ["'(http|www\\.|@)'", "'[a-z0-9-]\\.[a-z]{2,}'", "'[0-9]{6,}'", "'[[:cntrl:]]'", 'char_length(v) > 300'])
    ok(mig.includes(pieza), 'la base aplica ' + pieza);

  // ── 4 · el destinatario y el contrato salen de la base ───────────────────────────────────────────────
  datos = base();
  ok(V.esFallo(await res({}, 'otra@cliente.es')), 'to distinto del de la ficha → 400');
  ok(V.esFallo(await res({}, 'ben@cliente.es', { contrato_id: '12121212-1212-4121-8121-121212121212', factura_id: '', firma_id: '' })), 'contrato distinto del del libro → 400');
  ok(V.esFallo(await F.resuelve('invitacion_portal', { contrato_id: ID_C, factura_id: '', firma_id: '' }, 'ben@cliente.es', {}, rest, comun)), 'sin vars.invitacion → 400');
  ok(V.esFallo(await F.resuelve('invitacion_portal', { contrato_id: ID_C, factura_id: '', firma_id: '' }, 'ben@cliente.es', { invitacion: 'no-uuid' }, rest, comun)), 'invitacion que no es uuid → 400');
  for (const campo of ['parcela', 'proyecto']) { datos = { ...base(), [campo]: '  ' }; ok(V.esFallo(await res()), 'sin ' + campo + ' → 400'); }
  datos = { ...base(), para: null }; ok(V.esFallo(await res()), 'sin destinatario en la base → 400');
  datos = null; ok(V.esFallo(await res()), 'invitación inexistente → 400');
  const peticion = (vars) => ({ plantilla: 'invitacion_portal', to: 'ben@cliente.es', attach: false, contrato_id: ID_C, vars });
  for (const extraV of [{ nombre: 'Eve' }, { nota: 'hola' }, { para: 'x@y.es' }, { reclamo: ID_I }])
    ok(V.validaPlantillaPeticion(V.leePeticion({ ...peticion({ invitacion: ID_I, ...extraV }) })) !== null, 'vars no admite ' + Object.keys(extraV)[0]);
  igual(V.validaPlantillaPeticion(V.leePeticion(peticion({ invitacion: ID_I }))), null, 'la petición correcta vale');
  ok(V.validaPlantillaPeticion(V.leePeticion({ ...peticion({ invitacion: ID_I }), attach: true })) !== null, 'con adjunto no');

  // ── 5 · por la edge real ─────────────────────────────────────────────────────────────────────
  const ENVIO = 'envio-falso';
  const SERV = { 'content-type': 'application/json', 'x-render-secret': ENVIO };
  const config = [['marca', 'Lawang'], ['dominio_web', 'lawangproperties.com'], ['url_intranet', 'https://lawangproperties.com/intranet/'],
    ['email_avisos_soporte', 'soporte@lawangproperties.com']];
  const extra = async (u) => {
    const url = new URL(u);
    if (url.pathname.endsWith('/rest/v1/rpc/invitacion_portal_datos')) return new Response(JSON.stringify(datos === null ? [] : [datos]), { status: 200 });
    if (url.pathname.endsWith('/rest/v1/rpc/reclamo_pago_datos')) return new Response('[]', { status: 200 });
    if (url.pathname.endsWith('/rest/v1/sociedades')) {
      const k = /clave=eq\.([^&]+)/.exec(u)?.[1];
      return new Response(JSON.stringify(k === 'san_dal_woods' ? [{ razon: 'PT SAN DAL WOODS', marca: 'Sandal Woods', logo: null }] : []), { status: 200 });
    }
    if (url.pathname.endsWith('/rest/v1/correo_plantillas')) return new Response('[]', { status: 200 });   // texto de fábrica
    return null;
  };
  const llamaEdge = async (cuerpo, cabeceras = SERV, o = {}) => {
    A.reinicia({ env: { ENVIO_CORREO_SECRET: ENVIO }, config, extra, ...o });
    const m = await A.cargaEdge(__dirname);
    const rr = await A.llama(m, { cabeceras, cuerpo });
    return { rr, correos: A.estado.correo.correos };
  };
  const BODY = { plantilla: 'invitacion_portal', to: 'ben@cliente.es', attach: false, contrato_id: ID_C, vars: { invitacion: ID_I } };

  datos = { ...base(), nota: NOTA, nombre: 'Ben <script>' };
  let e = await llamaEdge(BODY);
  igual(e.rr.status, 200, 'por servicio, sin sociedad: 200 · ' + e.rr.crudo);
  igual(e.correos.length, 1, 'sale un correo');
  const sal = e.correos[0];
  igual(sal.to, 'ben@cliente.es', 'al destinatario pedido (que es el de la ficha)');
  igual(sal.subject, 'Your Lawang client portal invitation · Tu invitación al portal de cliente de Lawang');
  ok(sal.text.includes('Here is your invitation') && sal.text.includes('Aquí tienes la invitación'), 'texto en inglés y en español');
  ok(sal.html.includes('href="' + PORTAL + '"') && sal.html.includes('Entrar · Sign in'), 'html: botón al portal con su texto de siempre');
  const enlaces = [...sal.html.matchAll(/href="([^"]+)"/g)].map((m) => m[1]).filter((h) => !h.startsWith('mailto:'));
  ok(enlaces.length > 0 && enlaces.every((h) => /^https:\/\/lawangproperties\.com(\/|$)/.test(h)), 'todos los enlaces son del dominio propio · ' + enlaces.join(' '));
  ok(!/#th=|token|access_token/i.test(sal.html + sal.text), 'ni token ni #th=: no es un enlace mágico');
  ok(sal.html.includes('&quot;Ana&quot; &amp; l&#039;equipo &lt;b&gt;x&lt;/b&gt;') && !sal.html.includes('<b>x</b>'), 'html: la nota sale ESCAPADA');
  ok(!sal.html.includes('<script>'), 'html: el nombre de la ficha sale escapado');
  ok(!sal.html.includes('PT SAN DAL WOODS'), 'sin sociedad: firma la marca');
  igual(e.rr.cuerpo.plantilla, 'invitacion_portal', 'la respuesta lleva la plantilla'); ok(/^f:[0-9a-f]{8}$/.test(e.rr.cuerpo.version), 'y la versión de fábrica');

  // vías
  datos = base();
  e = await llamaEdge(BODY, { 'content-type': 'application/json' }); ok([400, 401, 403].includes(e.rr.status) && e.correos.length === 0, 'sin credencial: no sale');
  e = await llamaEdge(BODY, { 'content-type': 'application/json', 'x-suite-token': 'jwt' }, { sesion: true });
  igual(e.rr.status, 400, 'una sesión del equipo no puede mandarla a mano · ' + e.rr.crudo); igual(e.correos.length, 0);
  e = await llamaEdge({ ...BODY, vars: { invitacion: ID_I, nota: 'x' } }); igual(e.rr.status, 400, 'una nota en vars (del llamante) → 400'); igual(e.correos.length, 0);
  e = await llamaEdge({ ...BODY, to: 'otra@cliente.es' }); igual(e.rr.status, 400, 'to ≠ ficha → 400'); igual(e.correos.length, 0);

  // ── 6 · reclamo_pago sigue exigiendo la sociedad ───────────────────────────────────────────────
  e = await llamaEdge({ plantilla: 'reclamo_pago', to: 'ben@cliente.es', attach: false, contrato_id: ID_C, vars: { reclamo: ID_I } });
  igual(e.rr.status, 400, 'reclamo_pago por servicio y SIN sociedad → 400'); igual(e.correos.length, 0);
  ok(/sociedad/.test(e.rr.crudo), 'y dice que falta la sociedad');

  console.log(`OK invitacion_portal.test.js — fábrica ⇔ catálogo · texto bilingüe palabra por palabra · enlace del portal sin token · nota escapada y regla espejo de la base · destinatario/contrato de la base · solo servicio · reclamo sigue con sociedad · ${n} comprobaciones`);
})().catch((e) => { console.error(e); process.exit(1); });
