// node intranet/v4/assets/ajustes_reservas.harness.cjs [salida.json] [modo=super_admin|admin|instancia|instancia_vacia]   (desde la raíz del repo de Lawang; necesita Edge)
// Arnés de Ajustes › Reservas (ajustes-ux, 16-oct-2026): la página REAL (/intranet/v4/ajustes/) servida en local con un Supabase FALSO
// (window.LW_SB, que guard.js usa si existe; datos inventados). Mide:
//  · super_admin: en reposo no se ve ningún «Guardar»; ninguna clave interna (reservas.*, construccion.*) a la vista; cada fila de la base
//    sale con su campo (también una clave que la pantalla no conoce, en «Otros ajustes»); ningún bloque pasa de 3 campos; lo que se MANDA a
//    la base al cambiar cada ajuste es parametro_set {p_clave, p_valor}; lo escrito y sin guardar en otro ajuste sobrevive a guardar uno; en
//    inglés no queda a la vista ninguno de los rótulos en español.
//  · admin: los campos se ven desactivados y no hay ningún «Guardar».
//  · instancia (ERP con el módulo reservas apagado): no sale ninguna fila reservas.*, sí construccion.*, e Impuestos (#lw-imp) va justo
//    detrás de la sección; instancia_vacia (sin filas que enseñar): la sección queda oculta e Impuestos sigue saliendo.
// La interfaz se maneja por data-* (data-clave, data-k, data-guardar), nunca por rótulo. Sale 1 si falla.
const fs = require('fs'), path = require('path'), http = require('http');
const { chromium } = require(process.env.PLAYWRIGHT_CORE || 'C:/Users/jvrce/AppData/Roaming/npm/node_modules/@playwright/mcp/node_modules/playwright-core');
const RAIZ = path.resolve(__dirname, '..', '..', '..');
const [SALIDA, MODO = 'super_admin'] = process.argv.slice(2);
const ROL = MODO === 'admin' ? 'admin' : 'super_admin';
const INSTANCIA = MODO.startsWith('instancia');
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.webp': 'image/webp', '.json': 'application/json' };
const srv = http.createServer((q, r) => {
  let p = decodeURIComponent(q.url.split('?')[0]); if (p.endsWith('/')) p += 'index.html';
  const f = path.join(RAIZ, p);
  if (!fs.existsSync(f)) { r.writeHead(404); r.end(); return; }
  r.writeHead(200, { 'content-type': MIME[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(r);
});
// Las 6 filas reservas.* y la de construccion.* son las de las migraciones de Lawang (20260922134811, 20260928052131). aviso_owner_dias_antes
// no la inserta ninguna migración (la base la lee con un valor por defecto), así que solo va en un modo; «otro.ajuste_raro» es una clave que la
// pantalla no conoce: tiene que salir igual, con su rótulo.
const PARAM = [
  ['reservas.dias_gracia', 3, 'Días de gracia al vencer una reserva', 'El día que vence, aviso a managers; la parcela se libera sola pasados estos días si nadie prorroga o libera. 0 = se libera el mismo día.', 0, 30, 'reservas', 10],
  ['reservas.aviso_dias_antes', 1, 'Aviso previo (días antes del vencimiento)', 'Cuántos días antes de vencer se avisa a los managers. 0 = sin aviso previo.', 0, 15, 'reservas', 20],
  ['reservas.prorrogas_max_manager', 2, 'Prórrogas que puede dar un sales manager', 'Por Carta de Reserva. A partir de ahí, solo un admin.', 0, 10, 'reservas', 30],
  ['reservas.prorroga_dias_max_manager', 30, 'Días máximos por prórroga (sales manager)', null, 1, 365, 'reservas', 40],
  ['reservas.prorroga_dias_max_admin', 180, 'Días máximos por prórroga (admin)', null, 1, 730, 'reservas', 50],
  ['reservas.prorroga_dias_defecto', 15, 'Días propuestos al prorrogar', 'Lo que trae el formulario de prórroga antes de tocarlo.', 1, 365, 'reservas', 60],
  ['construccion.pago_unico_max_dias', 90, 'Pago único a la firma: días máximos desde la firma', 'Hasta cuántos días después de la fecha de firma puede el agente poner el vencimiento del pago único. Un admin puede pasarse.', 0, 365, 'construccion', 10]
];
if (MODO === 'super_admin') PARAM.push(['reservas.aviso_owner_dias_antes', 3, 'Aviso al owner', null, 0, 15, 'reservas', 25], ['otro.ajuste_raro', 7, 'Un ajuste que la pantalla no conoce', null, null, null, 'otro', 1]);
const FILAS = (MODO === 'instancia_vacia' ? PARAM.filter(p => p[0].startsWith('reservas.')) : PARAM)
  .map(r => ({ clave: r[0], valor: r[1], etiqueta: r[2], ayuda: r[3], minimo: r[4], maximo: r[5], grupo: r[6], orden: r[7], actualizado_en: '2026-10-02T04:00:00Z', actualizado_por: 'persona@ejemplo.test' }));
const FALSO = `(function () {
  var ROL = ${JSON.stringify(ROL)};
  var FICHA = { rol: ROL, herramientas: ROL === 'admin' ? ['ajustes'] : [], activo: true, nombre: 'Persona de prueba', notif_visto_hasta: null, ambito: 'global', empresas: null, es_propietario: ROL === 'super_admin' };
  var TABLAS = { usuarios: [FICHA], empresas: [], parametros: ${JSON.stringify(FILAS)}, impuestos: [], sociedades: [] };
  ${INSTANCIA ? "window.AXW_NUCLEO_OPERACION = true; window.axwModuloActivo = function (m) { return m !== 'reservas'; }; window.AXW_MODULOS_LISTOS = Promise.resolve(true);" : ''}
  window.__GUARDADOS = [];
  function cadena(tabla) {
    var filas = (TABLAS[tabla] || []).slice(), uno = false;
    var p = new Proxy({}, { get: function (_, k) {
      if (k === 'then') return function (ok, ko) { return Promise.resolve({ data: uno ? (filas[0] || null) : JSON.parse(JSON.stringify(filas)), error: null }).then(ok, ko); };
      if (k === 'maybeSingle' || k === 'single') return function () { uno = true; return p; };
      return function () { return p; };
    } });
    return p;
  }
  window.LW_SB = {
    auth: {
      getSession: function () { return Promise.resolve({ data: { session: { access_token: 'x', user: { id: 'u-prueba', email: 'persona@ejemplo.test', app_metadata: {} } } } }); },
      getUser: function () { return Promise.resolve({ data: { user: { id: 'u-prueba', email: 'persona@ejemplo.test' } } }); },
      onAuthStateChange: function () { return { data: { subscription: { unsubscribe: function () {} } } }; },
      signOut: function () { return Promise.resolve({}); }
    },
    from: cadena,
    rpc: function (n, a) {
      if (n === 'parametro_set') {
        window.__GUARDADOS.push([n, JSON.parse(JSON.stringify(a || {}))]);
        TABLAS.parametros.forEach(function (r) { if (r.clave === a.p_clave) { r.valor = a.p_valor; r.actualizado_en = new Date().toISOString(); } });
        return Promise.resolve({ data: null, error: null });
      }
      if (n === 'reservas_vencimiento') return Promise.resolve({ data: [], error: null });
      return Promise.resolve({ data: null, error: { message: '(arnés) sin dato para ' + n } });
    },
    storage: { from: function () { return { getPublicUrl: function () { return { data: { publicUrl: '' } }; }, createSignedUrl: function () { return Promise.resolve({ data: null, error: null }); } }; } },
    channel: function () { var c = { on: function () { return c; }, subscribe: function () { return c; } }; return c; },
    removeChannel: function () {},
    functions: { invoke: function () { return Promise.resolve({ data: null, error: { message: '(arnés)' } }); } }
  };
  window.supabase = { createClient: function () { return window.LW_SB; } };
})();
`;
const res = { modo: MODO, pasos: [], fallos: [], toasts: [] };
const ESPANOL = /\b(Guardar|Cuándo vence|Aviso a los managers|Prórrogas por Carta|Al prorrogar|Otros ajustes|Entre \d+ y \d+|Días de gracia|Días como máximo|Pagos de construcción)\b/;
srv.listen(0, async () => {
  const port = srv.address().port;
  const b = await chromium.launch({ channel: 'msedge' });
  const errs = []; let pg;
  async function nueva(idioma) {
    const ctx = await b.newContext({ viewport: { width: 1440, height: 900 } });
    await ctx.addInitScript({ content: "try{localStorage.setItem('lawang_idioma_ui','" + idioma + "')}catch(e){};" + FALSO });
    pg = await ctx.newPage();
    pg.on('pageerror', e => errs.push(String(e.message).slice(0, 200)));
    await abre();
  }
  async function abre() {
    await pg.goto(`http://127.0.0.1:${port}/intranet/v4/ajustes/#reservas`, { waitUntil: 'load' });
    await pg.waitForTimeout(1800);
    await pg.evaluate(() => {
      ['lw-novedades', 'lw-masc'].forEach(i => { const n = document.getElementById(i); if (n) n.remove(); });
    });
  }
  await nueva('es');
  const vistas = () => pg.evaluate(() => {
    const c = document.getElementById('lw-ajustes-lista'); const sec = c && c.closest('section');
    const visible = n => !!n && n.offsetParent !== null;
    return {
      claves: [].map.call(c ? c.querySelectorAll('[data-clave]') : [], f => f.getAttribute('data-clave')),
      guardarVisibles: [].filter.call(c ? c.querySelectorAll('[data-guardar]') : [], visible).length,
      guardarEnDom: c ? c.querySelectorAll('[data-guardar]').length : 0,
      activos: [].filter.call(c ? c.querySelectorAll('[data-k="valor"]') : [], i => !i.disabled).length,
      campos: c ? c.querySelectorAll('[data-k="valor"]').length : 0,
      porBloque: [].map.call(c ? c.querySelectorAll('[data-res-bloque]') : [], b => b.querySelectorAll('[data-clave]').length),
      seccionVisible: visible(sec),
      impTrasSeccion: !!sec && !!sec.nextElementSibling && sec.nextElementSibling.id === 'lw-imp',
      texto: sec ? sec.innerText : '',
      ancho: document.documentElement.scrollWidth
    };
  });
  res.diag = await pg.evaluate(() => ({ esAdmin: !!(window.LW_V4 && window.LW_V4.esAdmin), esSuper: !!(window.LW_V4 && window.LW_V4.esSuperAdmin), url: location.pathname + location.hash, main: (document.querySelector('main') || document.body).innerText.slice(0, 200), idioma: (function () { try { return localStorage.getItem('lawang_idioma_ui'); } catch (e) { return null; } })(), lista: (document.getElementById('lw-ajustes-lista') || {}).innerHTML ? document.getElementById('lw-ajustes-lista').innerText.slice(0, 160) : null }));
  let v = await vistas();
  res.reposo = { claves: v.claves, guardarVisibles: v.guardarVisibles, porBloque: v.porBloque, campos: v.campos };
  const crudas = (v.texto.match(/\b(reservas|construccion|otro)\.[a-z_]+/g) || []);
  if (crudas.length) res.fallos.push('CLAVES INTERNAS A LA VISTA: ' + crudas.join(', '));
  if (v.guardarVisibles) res.fallos.push('EN REPOSO se ven ' + v.guardarVisibles + ' botones Guardar');
  if (v.porBloque.some(n => n > 3)) res.fallos.push('UN BLOQUE CON MÁS DE 3 CAMPOS: ' + v.porBloque.join(', '));
  if (!v.porBloque.length && FILAS.length && MODO !== 'instancia_vacia') res.fallos.push('SIN BLOQUES: la lista no está agrupada');

  if (MODO === 'admin') {
    if (v.activos) res.fallos.push('ADMIN: ' + v.activos + ' campos editables');
    if (v.guardarEnDom) res.fallos.push('ADMIN: ' + v.guardarEnDom + ' botones Guardar');
    if (v.claves.length !== FILAS.length) res.fallos.push('ADMIN: se ven ' + v.claves.length + ' de ' + FILAS.length + ' ajustes');
  } else if (MODO === 'instancia') {
    const esperadas = FILAS.filter(f => !f.clave.startsWith('reservas.')).map(f => f.clave);
    if (JSON.stringify(v.claves) !== JSON.stringify(esperadas)) res.fallos.push('INSTANCIA: se ven ' + JSON.stringify(v.claves) + ', se esperaba ' + JSON.stringify(esperadas));
    if (!v.seccionVisible) res.fallos.push('INSTANCIA: la sección con construccion.* queda oculta');
    if (!v.impTrasSeccion) res.fallos.push('INSTANCIA: Impuestos (#lw-imp) no va justo detrás de la sección');
  } else if (MODO === 'instancia_vacia') {
    if (v.seccionVisible) res.fallos.push('INSTANCIA SIN FILAS: la sección de plazos se ve');
    if (!v.impTrasSeccion) res.fallos.push('INSTANCIA SIN FILAS: Impuestos (#lw-imp) no va justo detrás de la sección');
  } else {
    // ningún ajuste se pierde: cada fila de la base tiene su campo
    const faltan = FILAS.map(f => f.clave).filter(k => v.claves.indexOf(k) < 0);
    if (faltan.length) res.fallos.push('AJUSTES PERDIDOS: ' + faltan.join(', '));
    // lo que se manda: cada ajuste cambiado de uno en uno
    const n0 = () => pg.evaluate(() => window.__GUARDADOS.length);
    async function cambia(clave, valor) {
      const fila = pg.locator(`#lw-ajustes-lista [data-clave="${clave}"]`);
      const inp = fila.locator('[data-k="valor"]');
      await inp.fill(String(valor)); await inp.dispatchEvent('input');
      const antes = await n0();
      const visible = await fila.locator('[data-guardar]').isVisible();
      await fila.locator('[data-guardar]').click({ force: true });
      await pg.waitForTimeout(350);
      const g = (await n0()) > antes ? await pg.evaluate(() => window.__GUARDADOS[window.__GUARDADOS.length - 1]) : null;
      const aviso = await pg.evaluate(() => { const n = document.getElementById('toast'); return n ? n.textContent.trim() : null; });
      res.toasts.push(aviso);
      res.pasos.push({ paso: 'cambia ' + clave, guardarAparece: visible, enviado: g, aviso });
      if (!visible) res.fallos.push('AL CAMBIAR ' + clave + ' no aparece su Guardar');
      if (!g || g[0] !== 'parametro_set' || g[1].p_clave !== clave || g[1].p_valor !== valor || Object.keys(g[1]).length !== 2) res.fallos.push('ENVÍO DISTINTO en ' + clave + ': ' + JSON.stringify(g));
    }
    // a medias en un ajuste, se guarda otro: lo de medias sobrevive
    await pg.locator('#lw-ajustes-lista [data-clave="reservas.dias_gracia"] [data-k="valor"]').fill('5');
    await cambia('reservas.aviso_dias_antes', 2);
    const queda = await pg.locator('#lw-ajustes-lista [data-clave="reservas.dias_gracia"] [data-k="valor"]').inputValue();
    res.conserva = queda;
    if (queda !== '5') res.fallos.push('SE PIERDE LO ESCRITO: días de gracia a medias quedó en «' + queda + '» al guardar otro ajuste');
    for (const [k, val] of [['reservas.dias_gracia', 4], ['reservas.aviso_owner_dias_antes', 2], ['reservas.prorrogas_max_manager', 3], ['reservas.prorroga_dias_max_manager', 20],
      ['reservas.prorroga_dias_defecto', 10], ['reservas.prorroga_dias_max_admin', 120], ['construccion.pago_unico_max_dias', 60], ['otro.ajuste_raro', 8]]) await cambia(k, val);
    const toastCrudo = res.toasts.filter(t => /\b(reservas|construccion)\.[a-z_]+/.test(t));
    if (toastCrudo.length) res.fallos.push('AVISO CON LA CLAVE INTERNA: ' + toastCrudo[0]);
    v = await vistas();
    if (v.guardarVisibles) res.fallos.push('TRAS GUARDAR se ven ' + v.guardarVisibles + ' botones Guardar');
    // en inglés no queda nada en español a la vista
    await nueva('en');
    v = await vistas();
    const es = v.texto.match(new RegExp(ESPANOL.source, 'g')) || [];
    res.ingles = { espanol: es };
    if (es.length) res.fallos.push('EN INGLÉS QUEDA ESPAÑOL: ' + es.join(', '));
    await pg.setViewportSize({ width: 390, height: 844 }); await pg.waitForTimeout(300);
    v = await vistas();
    res.ancho390 = v.ancho;
    if (v.ancho > 390) res.fallos.push('SCROLL HORIZONTAL a 390: ' + v.ancho + ' px');
  }
  res.errs = errs;
  if (errs.length) res.fallos.push('ERRORES DE PÁGINA: ' + errs.join(' | '));
  if (SALIDA) fs.writeFileSync(SALIDA, JSON.stringify(res, null, 1));
  console.log(JSON.stringify(res, null, 1));
  console.log(res.fallos.length ? 'FALLA ' + res.fallos.length : 'ok (' + MODO + '): ' + res.pasos.length + ' envíos, nada se pierde');
  await b.close(); srv.close();
  process.exitCode = res.fallos.length ? 1 : 0;
});
