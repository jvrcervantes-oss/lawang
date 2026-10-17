/* node aviso_ia_conexion.test.js — la plantilla «aviso_ia_conexion» (aviso a la persona de cada asistente conectado al puente MCP),
   16-oct-2026, P6. SOLO en Lawang (plantillas_arnes.mjs → SOLO_LAWANG). Migración 20261017015111_mcp_f1_p6_aviso_conexion.sql.
   Con el index.ts REAL, sin red, sin enviar nada.
   1. Fábrica ⇔ catálogo sellado de la migración (resuelve produce TODAS las permitidas; las obligatorias del aviso no se pueden quitar).
   2. Texto bilingüe (inglés primero) palabra por palabra; hora de Bali; asistente de la lista cerrada y, si lo tiene, su nombre.
   3. El destinatario y el asistente salen de la base (`to` ≠ el de la RPC → 400); vars solo admite `aviso`; ningún id de documento.
   4. Por la edge real: solo con el secreto del servicio; botón a «Apps conectadas»; también a una dirección del dominio propio
      (Seguridad #404, punto 3: la vía de aviso interno no debe quedarse con él). */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

(async () => {
  const A = await import('./arnes.mjs');
  const V = await import('./valida.ts');
  const F = await import('./plantillas_fabrica.ts');
  let n = 0;
  const ok = (c, m) => { assert.ok(c, m); n++; };
  const igual = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++; };

  // por el final del nombre: la versión la pone apply_migration al aplicarla
  const dirMig = path.join(__dirname, '..', '..', 'migrations');
  const p6 = fs.readdirSync(dirMig).filter((f) => f.endsWith('_mcp_f1_p6_aviso_conexion.sql'));
  igual(p6.length, 1, 'una sola migración *_mcp_f1_p6_aviso_conexion.sql');
  const mig = fs.readFileSync(path.join(dirMig, p6[0]), 'utf8');
  const crudo = JSON.parse(/values \('aviso_ia_conexion', false,\s*'(\{"permitidas".*?\})'::jsonb/s.exec(mig)[1]);
  const cat = V.catalogoDe(crudo);
  ok(cat, 'el catálogo sembrado se lee');
  igual([...crudo.obligatorias.cuerpo].sort(), ['asistente', 'aviso_en', 'aviso_es', 'cuando', 'enlace'], 'obligatorias: asistente, cuándo, enlace y las dos frases «si no has sido tú»');

  // ── 1 · fábrica ⇔ catálogo ──────────────────────────────────────────────────────────────
  const t = F.textoFabrica('aviso_ia_conexion');
  ok(t && t.cuerpo_alt === null && cat.variantes === 1, 'hay texto de fábrica de una variante');
  igual(V.validaTextoPlantilla(t.asunto, 'asunto', cat), [], 'asunto cumple el catálogo');
  igual(V.validaTextoPlantilla(t.cuerpo, 'cuerpo', cat), [], 'cuerpo cumple el catálogo');
  ok(!/\{\{/.test(t.asunto), 'el asunto no lleva variables (el nombre del asistente nunca va en el asunto)');
  for (const quita of ['{{enlace}}', '{{aviso_en}}', '{{aviso_es}}', '{{asistente}}', '{{cuando}}'])
    ok(V.validaTextoPlantilla(t.cuerpo.split(quita).join(''), 'cuerpo', cat).length > 0, 'un texto editado sin ' + quita + ' no vale');
  ok(V.esClavePlantilla('aviso_ia_conexion') && V.PLANTILLAS.aviso_ia_conexion.soloServicio === true, 'está en PLANTILLAS y solo por servicio');
  igual(V.PLANTILLAS.aviso_ia_conexion.ids, [], 'sin ids de documento');

  const ID_Q = '77777777-7777-4777-8777-777777777777', ID_K = '88888888-8888-4888-8888-888888888888';
  const PORTAL = 'https://lawangproperties.com/portal/', APPS = 'https://lawangproperties.com/intranet/v4/ia/';
  const comun = { marca: 'Lawang', portal: PORTAL, dominio: 'lawangproperties.com' };
  let datos;   // lo que contesta ia_aviso_conexion_datos
  // 16-oct 14:05 UTC = 22:05 en Bali (WITA, UTC+8)
  const base = () => ({ conexion_id: ID_K, para: 'Ana@Lawangproperties.com', nombre: 'ANA maría', asistente: 'claude', nombre_asistente: 'Claude', creada_en: '2026-10-16T14:05:09+00:00' });
  const rest = async (ruta) => {
    ok(/^rpc\/ia_aviso_conexion_datos\?p_cola=[0-9a-f-]{36}$/.test(ruta), 'única consulta: la RPC por el id de la fila · ' + ruta);
    return datos === null ? [] : [datos];
  };
  const SIN = { contrato_id: '', factura_id: '', firma_id: '' };
  const res = (extraVars = {}, to = 'ana@lawangproperties.com') => F.resuelve('aviso_ia_conexion', SIN, to, { aviso: ID_Q, ...extraVars }, rest, comun);

  datos = base();
  let r = await res();
  ok(!V.esFallo(r), 'resuelve compone · ' + JSON.stringify(r));
  igual(Object.keys(r.vars).sort(), [...cat.permitidas].sort(), 'produce todas las permitidas y solo esas');
  igual(r.cta, { url: APPS, texto: 'Apps conectadas · Connected apps' }, 'botón a Apps conectadas');

  // ── 2 · texto bilingüe ─────────────────────────────────────────────────────────────
  const c = V.componeCorreo(t, r.variante, r.vars);
  igual(c.subject, 'An assistant was connected to your Lawang account · Se ha conectado un asistente a tu cuenta de Lawang', 'asunto');
  igual(c.message,
    'Hi Ana,\n\nClaude was connected to your Lawang account on 16/10/2026 22:05 (Bali time). From now on it can look up intranet data on your behalf, with your permissions.' +
    '\n\nYou can see your connected assistants and remove any of them at any time in Connected apps: ' + APPS +
    '\n\nIf it wasn\'t you, remove it now in Connected apps and change your password: changing it cuts off every connected assistant.' +
    '\n\nThe Lawang team' +
    '\n\n—\n\n' +
    'Hola Ana:\n\nSe ha conectado Claude a tu cuenta de Lawang el 16/10/2026 22:05 (hora de Bali). Desde ahora puede consultar datos de la intranet en tu nombre, con tus permisos.' +
    '\n\nPuedes ver tus asistentes conectados y quitar cualquiera cuando quieras en Apps conectadas: ' + APPS +
    '\n\nSi no has sido tú, quítala ahora en Apps conectadas y cambia tu contraseña: al cambiarla se cortan todos los asistentes conectados.' +
    '\n\nEl equipo de Lawang', 'cuerpo palabra por palabra');
  datos = { ...base(), nombre: null }; r = await res();
  ok(V.componeCorreo(t, r.variante, r.vars).message.startsWith('Hello,\n\n'), 'sin nombre: «Hello,»');
  datos = { ...base(), nombre_asistente: 'Claude de Ana' }; r = await res();
  igual(r.vars.asistente, 'Claude (Claude de Ana)', 'el nombre propio va tras el asistente de la lista cerrada');
  datos = { ...base(), nombre_asistente: null }; r = await res();
  igual(r.vars.asistente, 'Claude', 'sin nombre propio (o rechazado por la base): solo el de la lista');
  datos = { ...base(), asistente: 'chatgpt', nombre_asistente: null }; r = await res();
  igual(r.vars.asistente, 'ChatGPT', 'ChatGPT');

  // ── 3 · lo que sale de la base ─────────────────────────────────────────────────────
  datos = base();
  ok(V.esFallo(await res({}, 'otra@lawangproperties.com')), 'to distinto del correo de la persona → 400');
  datos = { ...base(), asistente: 'otro' }; ok(V.esFallo(await res()), 'asistente fuera de la lista → 400');
  datos = { ...base(), creada_en: null }; ok(V.esFallo(await res()), 'sin fecha → 400');
  datos = { ...base(), para: null }; ok(V.esFallo(await res()), 'sin destinatario en la base → 400');
  datos = null; ok(V.esFallo(await res()), 'aviso inexistente → 400');
  datos = base();
  ok(V.esFallo(await F.resuelve('aviso_ia_conexion', SIN, 'ana@lawangproperties.com', {}, rest, comun)), 'sin vars.aviso → 400');
  ok(V.esFallo(await F.resuelve('aviso_ia_conexion', SIN, 'ana@lawangproperties.com', { aviso: 'no-uuid' }, rest, comun)), 'aviso que no es uuid → 400');
  const peticion = (vars, extra = {}) => ({ plantilla: 'aviso_ia_conexion', to: 'ana@lawangproperties.com', attach: false, vars, ...extra });
  igual(V.validaPlantillaPeticion(V.leePeticion(peticion({ aviso: ID_Q }))), null, 'la petición correcta vale');
  for (const extraV of [{ asistente: 'Evil' }, { enlace: 'x' }, { aviso_en: 'x' }, { para: 'x@y.es' }])
    ok(V.validaPlantillaPeticion(V.leePeticion(peticion({ aviso: ID_Q, ...extraV }))) !== null, 'vars no admite ' + Object.keys(extraV)[0]);
  ok(V.validaPlantillaPeticion(V.leePeticion(peticion({ aviso: ID_Q }, { contrato_id: ID_K }))) !== null, 'con un contrato_id no');

  // ── 4 · por la edge real ─────────────────────────────────────────────────────────────────────
  const ENVIO = 'envio-falso';
  const SERV = { 'content-type': 'application/json', 'x-render-secret': ENVIO };
  const config = [['marca', 'Lawang'], ['dominio_web', 'lawangproperties.com'], ['url_intranet', 'https://lawangproperties.com'],
    ['email_avisos_soporte', 'soporte@lawangproperties.com']];
  const extra = async (u) => {
    const url = new URL(u);
    if (url.pathname.endsWith('/rest/v1/rpc/ia_aviso_conexion_datos')) return new Response(JSON.stringify(datos === null ? [] : [datos]), { status: 200 });
    if (url.pathname.endsWith('/rest/v1/correo_plantillas')) return new Response('[]', { status: 200 });   // texto de fábrica
    return null;
  };
  const llamaEdge = async (cuerpo, cabeceras = SERV, o = {}) => {
    A.reinicia({ env: { ENVIO_CORREO_SECRET: ENVIO }, config, extra, ...o });
    const m = await A.cargaEdge(__dirname);
    const rr = await A.llama(m, { cabeceras, cuerpo });
    return { rr, correos: A.estado.correo.correos };
  };
  const BODY = { plantilla: 'aviso_ia_conexion', to: 'ana@lawangproperties.com', attach: false, vars: { aviso: ID_Q } };

  datos = { ...base(), nombre: 'Ana <script>', nombre_asistente: 'Claude & <b>co</b>' };
  let e = await llamaEdge(BODY);
  igual(e.rr.status, 200, 'por servicio, a una dirección del dominio propio: 200 · ' + e.rr.crudo);
  igual(e.correos.length, 1, 'sale un correo');
  const sal = e.correos[0];
  igual(sal.to, 'ana@lawangproperties.com', 'a la persona de la conexión');
  ok(sal.text.includes('was connected to your Lawang account') && sal.text.includes('Se ha conectado'), 'texto en inglés y en español');
  ok(sal.html.includes('href="' + APPS + '"') && sal.html.includes('Apps conectadas · Connected apps'), 'html: botón a Apps conectadas (no se lo quita la vía de aviso interno)');
  const enlaces = [...sal.html.matchAll(/href="([^"]+)"/g)].map((m) => m[1]).filter((h) => !h.startsWith('mailto:'));
  ok(enlaces.length > 0 && enlaces.every((h) => /^https:\/\/lawangproperties\.com(\/|$)/.test(h)), 'todos los enlaces son del dominio propio · ' + enlaces.join(' '));
  ok(!sal.html.includes('<script>') && !sal.html.includes('<b>co</b>'), 'html: nombre de la persona y del asistente escapados');
  ok(/^f:[0-9a-f]{8}$/.test(e.rr.cuerpo.version), 'versión de fábrica');

  datos = { ...base(), para: 'ana@gmail.com' };
  e = await llamaEdge({ ...BODY, to: 'ana@gmail.com' });
  igual(e.rr.status, 200, 'y a una dirección de fuera · ' + e.rr.crudo); igual(e.correos.length, 1);

  // vías
  datos = base();
  e = await llamaEdge(BODY, { 'content-type': 'application/json' }); ok([400, 401, 403].includes(e.rr.status) && e.correos.length === 0, 'sin credencial: no sale');
  e = await llamaEdge(BODY, { 'content-type': 'application/json', 'x-suite-token': 'jwt' }, { sesion: true });
  igual(e.rr.status, 400, 'una sesión del equipo no puede mandarla a mano · ' + e.rr.crudo); igual(e.correos.length, 0);
  e = await llamaEdge({ ...BODY, to: 'otra@lawangproperties.com' }); igual(e.rr.status, 400, 'to ≠ el de la base → 400'); igual(e.correos.length, 0);

  console.log(`OK aviso_ia_conexion.test.js — fábrica ⇔ catálogo sellado · bilingüe palabra por palabra en hora de Bali · destinatario y asistente de la base · solo servicio · botón a Apps conectadas también al dominio propio · ${n} comprobaciones`);
})().catch((e) => { console.error(e); process.exit(1); });
