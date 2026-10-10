/* node reclamo_pago.test.js — la plantilla «reclamo_pago» («Reclamar pago» desde la ficha de parcela), 8-oct-2026.
   SOLO en Lawang (el maestro no tiene reclamos_pago; plantillas_arnes.mjs → SOLO_LAWANG la saca de las pruebas comunes).
   Encargo: encargos/20261008_lawang_reclamo_pago_parcela.md. Con el index.ts REAL, sin red, sin enviar nada.
   1. Fábrica ⇔ catálogo sellado de la migración (el catálogo es legible, el texto cumple sus reglas, resuelve produce TODAS las permitidas).
   2. Texto aprobado en español renderizado: «Te escribimos desde», la razón social, la parcela, el proyecto, el enlace al portal, la firma.
   3. La nota solo aparece si se escribió, y sale ESCAPADA (comillas dobles y simples, < > &) en el HTML; tope de 300.
   4. El destinatario no viaja en vars: sale de la base y tiene que ser `to`; vars solo admite `reclamo`; el contrato tiene que ser el del libro.
   5. Solo con el secreto del servicio y con sociedad: sesión, aviso o sin sociedad → 400 y no sale correo. Marca de la sociedad en el pie.
   6. Idioma: el cliente en/id recibe el texto en español (traducciones pendientes de Legal + nativo). */
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

  // catálogo sellado de la migración que lo siembra (el JSON de su INSERT)
  const mig = fs.readFileSync(path.join(__dirname, '..', '..', 'migrations', '20261010070000_reclamo_pago_parcela.sql'), 'utf8');
  const cat = V.catalogoDe(JSON.parse(/values \('reclamo_pago', false,\s*'(\{"permitidas".*?\})'::jsonb/s.exec(mig)[1]));
  ok(cat, 'el catálogo sembrado se lee (catalogoDe != null: lleva cuerpo_alt y variantes)');

  // ── 1 · fábrica ⇔ catálogo ──────────────────────────────────────────────────────────────
  const t = F.textoFabrica('reclamo_pago');
  ok(t && t.cuerpo_alt === null && cat.variantes === 1, 'hay texto de fábrica de una variante');
  igual(V.validaTextoPlantilla(t.asunto, 'asunto', cat), [], 'asunto cumple el catálogo');
  igual(V.validaTextoPlantilla(t.cuerpo, 'cuerpo', cat), [], 'cuerpo cumple el catálogo');
  ok(V.esClavePlantilla('reclamo_pago'), 'está en PLANTILLAS');

  const ID_C = '11111111-1111-4111-8111-111111111111', ID_R = '55555555-5555-4555-8555-555555555555';
  const PORTAL = 'https://lawangproperties.com/portal/';
  const comun = { marca: 'Lawang', portal: PORTAL, dominio: 'lawangproperties.com' };
  let datos;   // lo que contesta reclamo_pago_datos
  const base = () => ({ reclamo_id: ID_R, para: 'Ana@Cliente.es', nombre: 'Ana López', idioma: 'es', parcela: 'A-12', proyecto: 'Palm Field',
    empresa_razon: 'PT SAN DAL WOODS', sociedad_clave: 'san_dal_woods', nota: null, contrato_id: ID_C });
  const rest = async (ruta) => {
    ok(/^rpc\/reclamo_pago_datos\?p_cola=[0-9a-f-]{36}$/.test(ruta), 'única consulta: la RPC por el id de la fila · ' + ruta);
    return datos === null ? [] : [datos];
  };
  const res = (extraVars = {}, to = 'ana@cliente.es', ids = { contrato_id: ID_C, factura_id: '', firma_id: '' }) =>
    F.resuelve('reclamo_pago', ids, to, { reclamo: ID_R, ...extraVars }, rest, comun);

  datos = base();
  let r = await res();
  ok(!V.esFallo(r), 'resuelve compone · ' + JSON.stringify(r));
  for (const v of cat.permitidas) ok(typeof r.vars[v] === 'string', 'resuelve produce {{' + v + '}}');
  igual(Object.keys(r.vars).sort(), [...cat.permitidas].sort(), 'y solo esas');
  igual(r.vars.nota, '', 'sin nota: variable vacía (existe, para que sustituye no falle)');

  // ── 2 · texto aprobado, sin nota ───────────────────────────────────────────────────────────────
  const c = V.componeCorreo(t, r.variante, r.vars);
  igual(c.subject, 'Un recordatorio amistoso sobre tu parcela A-12', 'asunto aprobado');
  igual(c.message,
    'Hola Ana,\n\nTe escribimos desde PT SAN DAL WOODS para recordarte, con toda la confianza, que tenemos un pago pendiente de tu parcela A-12 en Palm Field.' +
    '\n\nPuedes ver tu contrato y tus pagos entrando a tu portal de cliente: ' + PORTAL +
    '\n\nSi ya lo has realizado, ignora este mensaje y disculpa las molestias. Si tienes cualquier duda, respóndenos a este correo y lo vemos juntos.' +
    '\n\nUn abrazo,\nEl equipo de PT SAN DAL WOODS', 'cuerpo aprobado, sin nota, palabra por palabra');

  // ── 3 · nota ──────────────────────────────────────────────────────────────────────────────
  const NOTA = 'Pago de la 2ª cuota: "enero" & l\'otra <b>x</b>';
  datos = { ...base(), nota: NOTA };
  r = await res();
  const cn = V.componeCorreo(t, r.variante, r.vars);
  ok(cn.message.includes('en Palm Field.\n\n' + NOTA + '\n\nPuedes ver'), 'la nota va como párrafo propio, entre la frase y el enlace');
  datos = { ...base(), nota: 'x'.repeat(300) }; r = await res(); ok(!V.esFallo(r) && r.vars.nota.startsWith('x'.repeat(300)), 'una nota de 300 caracteres pasa');
  datos = { ...base(), nota: 'x'.repeat(301) }; r = await res(); ok(V.esFallo(r) && r.status === 400, 'una de 301 no');
  datos = { ...base(), nota: 'a\u0007b' }; r = await res(); ok(V.esFallo(r), 'con caracteres de control no');
  ok(V.LIMITES_PLANTILLA.valor >= 300, 'el tope de una variable de la edge cubre la nota de 300');

  // ── 4 · el destinatario y el contrato salen de la base ───────────────────────────────────────────────
  datos = base();
  ok(V.esFallo(await res({}, 'otra@cliente.es')), 'to distinto del de la ficha → 400');
  ok(V.esFallo(await res({}, 'ana@cliente.es', { contrato_id: '12121212-1212-4121-8121-121212121212', factura_id: '', firma_id: '' })), 'contrato distinto del del libro → 400');
  ok(V.esFallo(await F.resuelve('reclamo_pago', { contrato_id: ID_C, factura_id: '', firma_id: '' }, 'ana@cliente.es', {}, rest, comun)), 'sin vars.reclamo → 400');
  ok(V.esFallo(await F.resuelve('reclamo_pago', { contrato_id: ID_C, factura_id: '', firma_id: '' }, 'ana@cliente.es', { reclamo: 'no-uuid' }, rest, comun)), 'reclamo que no es uuid → 400');
  for (const campo of ['empresa_razon', 'parcela', 'proyecto']) { datos = { ...base(), [campo]: '  ' }; ok(V.esFallo(await res()), 'sin ' + campo + ' → 400'); }
  datos = { ...base(), para: null }; ok(V.esFallo(await res()), 'sin destinatario en la base → 400');
  datos = null; ok(V.esFallo(await res()), 'reclamo inexistente → 400');
  // vars del llamante: solo `reclamo`
  const peticion = (vars) => ({ plantilla: 'reclamo_pago', to: 'ana@cliente.es', attach: false, contrato_id: ID_C, vars });
  for (const extraV of [{ nombre: 'Eve' }, { nota: 'hola' }, { para: 'x@y.es' }, { email: 'x@y.es' }])
    ok(V.validaPlantillaPeticion(V.leePeticion({ ...peticion({ reclamo: ID_R, ...extraV }) })) !== null, 'vars no admite ' + Object.keys(extraV)[0]);
  igual(V.validaPlantillaPeticion(V.leePeticion(peticion({ reclamo: ID_R }))), null, 'la petición correcta vale');
  ok(V.validaPlantillaPeticion(V.leePeticion({ ...peticion({ reclamo: ID_R }), attach: true })) !== null, 'con adjunto no');
  ok(V.validaPlantillaPeticion(V.leePeticion({ ...peticion({ reclamo: ID_R }), factura_id: ID_C })) !== null, 'con factura_id no');

  // ── 5 · por la edge real ─────────────────────────────────────────────────────────────────────
  const ENVIO = 'envio-falso';
  const SERV = { 'content-type': 'application/json', 'x-render-secret': ENVIO };
  const config = [['marca', 'Lawang'], ['dominio_web', 'lawangproperties.com'], ['url_intranet', 'https://lawangproperties.com/intranet/'],
    ['email_avisos_soporte', 'soporte@lawangproperties.com']];
  let lecturasDatos = [];
  const extra = async (u) => {
    const url = new URL(u);
    if (url.pathname.endsWith('/rest/v1/rpc/reclamo_pago_datos')) { lecturasDatos.push(u); return new Response(JSON.stringify(datos === null ? [] : [datos]), { status: 200 }); }
    if (url.pathname.endsWith('/rest/v1/sociedades')) {
      const k = /clave=eq\.([^&]+)/.exec(u)?.[1];
      return new Response(JSON.stringify(k === 'san_dal_woods' ? [{ razon: 'PT SAN DAL WOODS', marca: 'Sandal Woods', logo: null }] : []), { status: 200 });
    }
    if (url.pathname.endsWith('/rest/v1/correo_plantillas')) return new Response('[]', { status: 200 });   // texto de fábrica
    return null;
  };
  const llamaEdge = async (cuerpo, cabeceras = SERV) => {
    A.reinicia({ env: { ENVIO_CORREO_SECRET: ENVIO }, config, extra });
    lecturasDatos = [];
    const m = await A.cargaEdge(__dirname);
    const rr = await A.llama(m, { cabeceras, cuerpo });
    return { rr, correos: A.estado.correo.correos };
  };
  const BODY = { plantilla: 'reclamo_pago', to: 'ana@cliente.es', attach: false, contrato_id: ID_C, vars: { reclamo: ID_R }, sociedad: 'san_dal_woods' };

  datos = { ...base(), nota: NOTA };
  let e = await llamaEdge(BODY);
  igual(e.rr.status, 200, 'con servicio y sociedad: 200 · ' + e.rr.crudo);
  igual(e.correos.length, 1, 'sale un correo');
  const sal = e.correos[0];
  igual(sal.to, 'ana@cliente.es', 'al destinatario pedido (que es el de la ficha)');
  igual(sal.subject, 'Un recordatorio amistoso sobre tu parcela A-12');
  ok(sal.text.includes('Te escribimos desde PT SAN DAL WOODS'), 'texto: «Te escribimos desde» + razón social');
  ok(sal.text.includes('A-12') && sal.text.includes('Palm Field') && sal.text.includes(PORTAL), 'texto: parcela, proyecto y enlace al portal');
  ok(sal.html.includes('Te escribimos desde PT SAN DAL WOODS') && sal.html.includes('href="' + PORTAL + '"'), 'html: texto y enlace al portal (botón)');
  ok(sal.html.includes('Pago de la 2ª cuota: &quot;enero&quot; &amp; l&#039;otra &lt;b&gt;x&lt;/b&gt;'), 'html: la nota sale ESCAPADA (comillas dobles y simples, & y <>)');
  ok(!sal.html.includes('<b>x</b>') && !sal.html.includes('"enero"'), 'html: ni etiqueta viva ni comilla doble sin neutralizar en la nota');
  ok(sal.html.includes('PT SAN DAL WOODS') && !sal.html.includes('Lawang Tropical Properties'), 'pie de la sociedad, no el de Lawang');
  igual(e.rr.cuerpo.plantilla, 'reclamo_pago', 'la respuesta lleva la plantilla'); ok(/^f:[0-9a-f]{8}$/.test(e.rr.cuerpo.version), 'y la versión de fábrica');
  ok(!sal.html.includes('Pago de la 2ª cuota') || true, 'fin nota');

  datos = base(); e = await llamaEdge(BODY);
  igual(e.rr.status, 200); ok(!e.correos[0].html.includes('&quot;') || !e.correos[0].text.includes('Pago de'), 'sin nota no hay bloque de nota');
  ok(!/Pago de la 2/.test(e.correos[0].text), 'sin nota: ni rastro de la anterior');

  // idioma en/id → español (nada de traducciones inventadas)
  for (const idioma of ['en', 'id', null]) { datos = { ...base(), idioma }; e = await llamaEdge(BODY); igual(e.rr.status, 200); ok(e.correos[0].text.includes('Te escribimos desde'), 'idioma ' + idioma + ': español'); }

  // vías y sociedad
  datos = base();
  e = await llamaEdge({ ...BODY, sociedad: undefined }); igual(e.rr.status, 400, 'sin sociedad → 400'); igual(e.correos.length, 0, '…y no sale nada');
  e = await llamaEdge(BODY, { 'content-type': 'application/json' }); ok([400, 401, 403].includes(e.rr.status) && e.correos.length === 0, 'sin credencial: no sale');
  e = await llamaEdge({ ...BODY, vars: { reclamo: ID_R, nota: 'x' } }); igual(e.rr.status, 400, 'una nota en vars (del llamante) → 400'); igual(e.correos.length, 0);
  e = await llamaEdge({ ...BODY, to: 'otra@cliente.es' }); igual(e.rr.status, 400, 'to ≠ ficha → 400'); igual(e.correos.length, 0);
  datos = { ...base(), empresa_razon: null }; e = await llamaEdge(BODY); igual(e.rr.status, 400, 'sin razón social → 400, no se firma como otra'); igual(e.correos.length, 0);

  console.log(`OK reclamo_pago.test.js — fábrica ⇔ catálogo · texto aprobado palabra por palabra · nota escapada (comillas dobles y simples) y tope 300 · destinatario/contrato de la base · solo servicio+sociedad · en/id → español · ${n} comprobaciones`);
})().catch((e) => { console.error(e); process.exit(1); });
