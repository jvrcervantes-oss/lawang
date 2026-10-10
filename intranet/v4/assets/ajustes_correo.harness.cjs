// node intranet/v4/assets/ajustes_correo.harness.cjs intranet/v4/assets/ajustes.js [captura.png] [prefijo-capturas]      (HARNESS_MAESTRO=1: con la bandera del ERP maestro)
// Harness de «Ajustes › Correo» (F3.1 + código de confirmación F3.1b; portado a Lawang el 8-oct-2026 desde comercial/demo-erp/pruebas del repo AxisWorks): el ajustes.js REAL,
// en Chromium, con la base, la sesión y la edge `ajustes-correo` SIMULADAS (page.route). Mide el comportamiento, no el código: qué pide a la edge y con
// qué cabeceras y en qué orden (pedir código → guardar), qué pinta con cada respuesta (incluida la edge sin desplegar y cada código de error) y que
// ninguna contraseña queda en la página cuando ya no hace falta.
// En esta PC: PLAYWRIGHT_CORE=C:/Users/jvrce/AppData/Roaming/npm/node_modules/@playwright/mcp/node_modules/playwright-core
const fs = require('fs');
const { chromium } = require(process.env.PLAYWRIGHT_CORE || 'playwright-core');
const RUTA = process.argv[2];
const SHOT = process.argv[3];
const PREF = process.argv[4];
const js = fs.readFileSync(RUTA, 'utf8');
// El diccionario REAL de la suite (lwT, LW_EN, lwLocale): lo traducido se mide contra lo que de verdad se publica, no contra un doble.
const I18N = fs.readFileSync(require('path').join(__dirname, '..', '..', '..', 'contracts', 'assets', 'i18n.js'), 'utf8').replace(/<\/script>/g, '<\/script>');
let fallos = 0;
const ok = (nombre, c, extra = '') => { if (!c) { fallos++; console.log('FALLA  ' + nombre + (extra ? ' → ' + extra : '')); } else console.log('ok     ' + nombre); };
const SECRETO = 'S3cr3t0-del-buz0n!';
const CUENTA = 'Cl4ve-de-la-cuenta';

const pagina = (cfg) => `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>t</title>
<style>[data-lw-panel][hidden]{display:none}body{font-family:system-ui,sans-serif;font-size:14px}.lw-aj-mitad{flex:1}input{border:1px solid #999}button{border:1px solid #888;padding:6px 14px;border-radius:99px}.px-8{padding-left:2rem;padding-right:2rem}.py-5{padding-top:1.25rem;padding-bottom:1.25rem}.flex{display:flex}.flex-col{flex-direction:column}.gap-2{gap:.5rem}.gap-3{gap:.75rem}.gap-4{gap:1rem}.gap-1{gap:.25rem}.flex-wrap{flex-wrap:wrap}.items-center{align-items:center}.border-b{border-bottom:1px solid #ddd}.text-error{color:#b00020}.text-outline{color:#666}.w-full{width:100%}</style></head><body>
<div role="tablist"><button data-lw-tab="empresa">Empresa</button><button data-lw-tab="correo">Correo</button><button data-lw-tab="registro">Registro</button></div>
<section data-lw-panel="empresa"><div id="lw-aj-empresa"></div></section>
<section data-lw-panel="correo"><div><h2>Correo</h2></div><div id="lw-aj-correo"></div></section>
<section data-lw-panel="registro"><div id="lw-aj-registro"></div></section>
<script>
${process.env.HARNESS_MAESTRO ? 'window.AXW_NUCLEO_OPERACION = true;' : ''}
window.__datos = ${JSON.stringify(cfg.datos)};
window.__guardados = [];
var sb = {
  rpc: function (n, a) { if (n === 'ajustes_config_guardar') { window.__guardados.push([a.p_clave, a.p_valor]); window.__datos.valores[a.p_clave] = a.p_valor; return Promise.resolve({ data: { cambiado: true }, error: null }); }
    return Promise.resolve({ data: window.__datos, error: null }); },
  from: function () { throw new Error('el navegador no toca la base'); },
  auth: { getSession: function () { return Promise.resolve({ data: { session: { access_token: 'JWT-DEL-SUPER' } } }); } }
};
window.LW_AUTH = Promise.resolve({ sb: sb });
window.lwDatos = function (n, a) { return Promise.resolve(sb.rpc(n, a)).then(function (r) { return { data: r.data, error: r.error }; }); };
window.lwEdge = function (n) { return 'https://inst.test/functions/v1/' + n; };
window.LW_SB_KEY = 'anon-key';
window.LW_IDIOMA = '${cfg.idioma || 'es'}';
window.LW_T_MISSES = new Set();
window.toast = function (m) { window.__toast = m; };
window.onerror = function (m) { (window.__errores = window.__errores || []).push(String(m)); };
</script>
<script>${I18N}</script>
<script>${js.replace(/<\/script>/g, '<\\/script>')}</script></body></html>`;

// Las 4 direcciones YA NO salen por ajustes_config_datos (ni en `editables` ni en `valores`): solo por `estado`.
const DATOS = (extra = {}) => Object.assign({ editables: ['marca', 'email_avisos_reservas', 'email_avisos_crm', 'zona_horaria', 'logo_correo_url', 'asunto_por_defecto'],
  puede_escribir: true, valores: { email_avisos_reservas: 'res@negocio.com' }, actualizado: {} }, extra);
const ESTADO = (o = {}) => ({ ok: true, estado: Object.assign({ configurado: true, host: 'smtp.viejo.com', usuario: 'hola@negocio.com', puerto: 465, nombre: 'Mi Negocio', puesto_en: '2026-10-01T10:00:00Z', puesto_por: 'jefe@negocio.com', hay_previo: false, intentos_recientes: 0, intentos_max: 5 }, o.estado || {}),
  remitente: Object.assign({ email_from: 'hola@negocio.com', efectivo: 'hola@negocio.com', motivo: '', reply_to: 'resp@negocio.com' }, o.remitente || {}),
  avisos: Object.assign({ soporte: 'soporte@negocio.com', sistema: 'sistema@negocio.com' }, o.avisos || {}),
  envios_pausados: !!o.pausados, pide_codigo: o.pide_codigo !== false });
const CODIGO_OK = { status: 200, body: { ok: true, codigo: 'codigo_enviado', caduca_en: 600, correo_enmascarado: 'j***@negocio.com' } };
const err = (status, codigo, extra = {}) => ({ status, body: Object.assign({ ok: false, codigo, error: 'TEXTO-LIBRE-DEL-SERVIDOR <b>x</b>' }, extra) });

(async () => {
  const exe = process.env.CHROMIUM_EXE || 'C:/Users/jvrce/AppData/Local/ms-playwright/chromium-1243/chrome-win64/chrome.exe';
  const b = await chromium.launch({ executablePath: fs.existsSync(exe) ? exe : undefined });
  async function abre(cfg, respuestas, hash = '#correo', ancho = 1440) {
    const ctx = await b.newContext({ viewport: { width: ancho, height: 1100 } });
    const p = await ctx.newPage();
    const llamadas = [];
    await p.route('https://inst.test/functions/v1/ajustes-correo', async (r) => {
      const req = r.request();
      if (req.method() === 'OPTIONS') return r.fulfill({ status: 204, headers: { 'access-control-allow-origin': 'https://inst.test', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'POST' } });
      const cuerpo = JSON.parse(req.postData() || '{}');
      llamadas.push({ cuerpo, cab: req.headers() });
      const x = respuestas(cuerpo, llamadas.length);
      if (x === 'abort') return r.abort('failed');
      return r.fulfill({ status: x.status, contentType: x.html ? 'text/html' : 'application/json', headers: { 'access-control-allow-origin': 'https://inst.test' }, body: x.html || JSON.stringify(x.body) });
    });
    await p.route('https://inst.test/', (r) => r.fulfill({ contentType: 'text/html', body: pagina(cfg) }));
    await p.goto('https://inst.test/' + hash);
    return { p, ctx, llamadas };
  }
  const txt = (p, sel) => p.$eval(sel, (e) => e.textContent).catch(() => null);
  const cam = (c) => '[data-correo-campo="' + c + '"]';
  const valor = (p, c) => p.$eval(cam(c), (e) => e.value).catch(() => null);
  const hay = async (p, sel) => (await p.$$(sel)).length > 0;
  const espera = (p, sel) => p.waitForSelector(sel, { timeout: 4000 });
  const sinSecretos = async (p) => { const h = await p.content(); const v = await p.evaluate(() => [...document.querySelectorAll('input')].map((i) => i.value).join('|')); return !h.includes(SECRETO) && !v.includes(SECRETO) && !h.includes(CUENTA) && !v.includes(CUENTA); };
  const foto = async (p, nombre) => { if (PREF) await p.screenshot({ path: PREF + nombre + '.png', fullPage: true }); };

  // 1. Estado configurado: UNA llamada (estado), con la sesión; servidor plegado con «puesta el … por …» y Cambiar; las 4 direcciones salen del estado
  {
    const { p, ctx, llamadas } = await abre({ datos: DATOS() }, (c) => ({ status: 200, body: ESTADO() }));
    await espera(p, '[data-correo-fila="email_from"]');
    ok('estado: UNA llamada a la edge, acción estado', llamadas.length === 1 && llamadas[0].cuerpo.accion === 'estado');
    ok('estado: va con Bearer de la sesión y apikey, sin secretos', llamadas[0].cab.authorization === 'Bearer JWT-DEL-SUPER' && llamadas[0].cab.apikey === 'anon-key');
    ok('muestra servidor, usuario y puerto', /smtp\.viejo\.com/.test(await txt(p, '[data-correo="servidor-actual"]')) && /465/.test(await txt(p, '[data-correo="servidor-actual"]')));
    const cp = await txt(p, '[data-correo="contrasena-puesta"]');
    ok('contraseña write-only: «puesta el … por …» y ni rastro de la clave', /puesta el/.test(cp) && /jefe@negocio\.com/.test(cp) && /••••/.test(cp), cp);
    ok('el formulario del servidor está plegado hasta pulsar Cambiar', !(await hay(p, cam('host'))) && await hay(p, '[data-accion="correo-servidor-editar"]'));
    for (const [k, v] of [['email_from', 'hola@negocio.com'], ['email_reply_to', 'resp@negocio.com'], ['email_avisos_soporte', 'soporte@negocio.com'], ['email_avisos_sistema', 'sistema@negocio.com']])
      ok('dirección ' + k + ' sale del estado de la edge', await valor(p, 'dir-' + k) === v, String(await valor(p, 'dir-' + k)));
    ok('el formulario base ya NO ofrece las 4 direcciones (se cambian con código)', !(await hay(p, '[data-ajuste="email_from"], [data-ajuste="email_reply_to"], [data-ajuste="email_avisos_soporte"], [data-ajuste="email_avisos_sistema"]')));
    ok('el formulario base conserva reservas, CRM y asunto (sin código)', (await p.$$('[data-ajuste="email_avisos_reservas"], [data-ajuste="email_avisos_crm"], [data-ajuste="asunto_por_defecto"]')).length === 3);
    ok('el texto de «qué lee esto» del asunto es el del envío de correos', /envío de correos/.test(await txt(p, '[data-ajuste-fila="asunto_por_defecto"]')));
    ok('sin error de JS', !(await p.evaluate(() => window.__errores)));
    await foto(p, '1_configurado');
    if (SHOT) await p.screenshot({ path: SHOT, fullPage: true });
    await p.fill('[data-ajuste="asunto_por_defecto"]', 'Hola desde ERP');
    await p.click('[data-ajuste-clave="asunto_por_defecto"]');
    await p.waitForFunction(() => window.__guardados.length === 1);
    ok('el asunto se guarda por ajustes_config_guardar (sin código) y no toca la edge', JSON.stringify(await p.evaluate(() => window.__guardados)) === JSON.stringify([['asunto_por_defecto', 'Hola desde ERP']]) && llamadas.length === 1);
    await ctx.close();
  }

  // 2. Servidor: Cambiar → Pedir código → (bloqueado, código en el correo de la sesión) → Probar y guardar → todo limpio
  {
    const { p, ctx, llamadas } = await abre({ datos: DATOS() }, (c) => c.accion === 'estado' ? { status: 200, body: ESTADO() }
      : c.accion === 'pedir_codigo' ? CODIGO_OK
      : { status: 200, body: Object.assign(ESTADO({ estado: { host: 'smtp.nuevo.com', usuario: 'envios@negocio.com', puesto_por: 'yo@negocio.com' } }), { guardado: true, aviso: 'enviado', prueba_enviada_a: 'yo@negocio.com' }) });
    await espera(p, '[data-accion="correo-servidor-editar"]');
    await p.click('[data-accion="correo-servidor-editar"]');
    await espera(p, cam('host'));
    ok('Cambiar abre el formulario con host, usuario y nombre del estado y la contraseña VACÍA', await valor(p, 'host') === 'smtp.viejo.com' && await valor(p, 'user') === 'hola@negocio.com' && await valor(p, 'nombre') === 'Mi Negocio' && await valor(p, 'pass') === '');
    const pw = await p.$eval(cam('pass'), (e) => ({ t: e.type, a: e.autocomplete }));
    ok('contraseña: type=password y autocomplete=new-password', pw.t === 'password' && pw.a === 'new-password');
    // Desde el asistente de 3 pasos (e0e88e58, 9-oct) el puerto no es una casilla: es una línea fija. Que no haya NINGUNA casilla de puerto
    // es lo que importa (nadie puede mandar otro); que viaje 465 lo miden los cuerpos de pedir_codigo y probar_y_guardar más abajo.
    ok('puerto 465 fijo: línea informativa y ninguna casilla de puerto editable', /465/.test(await txt(p, '[data-correo="puerto-fijo"]') || '') && !(await hay(p, cam('port') + ', #lw-aj-correo-servidor input[name="port"], #lw-aj-correo-servidor input[type="number"]')));
    await p.fill(cam('host'), '  smtp.nuevo.com ');
    await p.fill(cam('user'), 'envios@negocio.com');
    await p.fill(cam('pass'), SECRETO);
    await p.fill(cam('nombre'), '');
    await p.click('[data-accion="correo-servidor-pedir"]');
    await espera(p, '[data-correo="codigo-info"]');
    const c1 = llamadas[1].cuerpo;
    ok('pedir_codigo: cuerpo = accion, alcance servidor, host recortado, port 465, user, pass; sin nombre vacío', c1.accion === 'pedir_codigo' && c1.alcance === 'servidor' && c1.host === 'smtp.nuevo.com' && c1.port === 465 && c1.user === 'envios@negocio.com' && c1.pass === SECRETO && !('nombre' in c1) && !('codigo' in c1), JSON.stringify(c1));
    const info = await txt(p, '[data-correo="codigo-info"]');
    ok('enseña el correo ENMASCARADO al que se mandó, la caducidad (10 minutos) y que sirve una vez', /j\*\*\*@negocio\.com/.test(info) && /10 minutos/.test(info) && /una sola vez/.test(info), info);
    ok('con un código pedido los datos quedan bloqueados (readonly) y la contraseña SIGUE en la casilla (el código está atado a ella)',
      await p.$eval(cam('host'), (e) => e.readOnly) && await p.$eval(cam('user'), (e) => e.readOnly) && await p.$eval(cam('pass'), (e) => e.readOnly && e.value) === SECRETO);
    ok('host distinto del actual → pide ya la contraseña de la cuenta (current-password)', await p.$eval(cam('reauth'), (e) => e.type + '/' + e.autocomplete) === 'password/current-password');
    ok('el código NO viaja en el navegador de vuelta: no hay 6 cifras en la página', !/\b\d{6}\b/.test(await p.evaluate(() => document.body.innerText)));
    await foto(p, '2_pidiendo_codigo');
    // código mal formado: no gasta llamada
    await p.fill(cam('codigo'), '12ab');
    await p.click('[data-accion="correo-servidor-probar"]');
    ok('código con letras: lo dice y no llama a la edge', /6 cifras/.test(await txt(p, '[data-correo="resultado"]')) && llamadas.length === 2);
    await p.fill(cam('codigo'), '123456');
    await p.fill(cam('reauth'), CUENTA);
    await p.click('[data-accion="correo-servidor-probar"]');
    await p.waitForFunction(() => /Guardado/.test((document.querySelector('[data-correo="resultado"]') || {}).textContent || ''));
    const c2 = llamadas[2].cuerpo;
    ok('probar_y_guardar: los MISMOS datos + codigo + contrasena_actual', c2.accion === 'probar_y_guardar' && c2.host === 'smtp.nuevo.com' && c2.port === 465 && c2.user === 'envios@negocio.com' && c2.pass === SECRETO && c2.codigo === '123456' && c2.contrasena_actual === CUENTA && !('nombre' in c2), JSON.stringify(c2));
    const r = await txt(p, '[data-correo="resultado"]');
    ok('resultado: guardado + a quién llegó la prueba + aviso previo enviado', /yo@negocio\.com/.test(r) && /servidor anterior/.test(r), r);
    ok('el estado pintado pasa al servidor nuevo y el formulario se pliega', /smtp\.nuevo\.com/.test(await txt(p, '[data-correo="servidor-actual"]')) && !(await hay(p, cam('host'))));
    ok('NINGUNA contraseña (ni la del buzón ni la de la cuenta) queda en la página', await sinSecretos(p));
    await foto(p, '3_guardado');
    await ctx.close();
  }

  // 3. Fallos al probar con un código pedido: lo que mantiene el código y lo que lo tira
  {
    let paso = 0;
    const { p, ctx, llamadas } = await abre({ datos: DATOS() }, (c) => {
      if (c.accion === 'estado') return { status: 200, body: ESTADO() };
      if (c.accion === 'pedir_codigo') return CODIGO_OK;
      paso++;
      if (paso === 1) return err(422, 'prueba_fallida', { error: '<img src=x onerror=window.__xss=1>535 Authentication failed for ADMIN-HOST-INTERNO', fase: 'verify', smtp_code: 'EAUTH', smtp_response_code: 535, detalle_code: '' });
      if (paso === 2) return err(401, 'reautenticar');
      if (paso === 3) return err(401, 'clave_actual_incorrecta');
      if (paso === 4) return err(429, 'demasiados_intentos');
      if (paso === 5) return err(503, 'envios_pausados');
      return err(403, 'codigo_no_valido');
    });
    await espera(p, '[data-accion="correo-servidor-editar"]');
    await p.click('[data-accion="correo-servidor-editar"]');
    await espera(p, cam('host'));
    await p.fill(cam('host'), 'smtp.otro.com');
    await p.fill(cam('user'), 'u@negocio.com');
    await p.fill(cam('pass'), SECRETO);
    await p.click('[data-accion="correo-servidor-pedir"]');
    await espera(p, cam('codigo'));
    const prueba = async (reauth) => {
      await p.fill(cam('codigo'), '654321');
      if (reauth) await p.fill(cam('reauth'), CUENTA);
      const n = llamadas.length;
      await p.click('[data-accion="correo-servidor-probar"]');
      await p.waitForFunction((n0) => ((document.querySelector('[data-correo="resultado"]') || {}).textContent || '').length > 0 && !document.querySelector('[data-accion="correo-servidor-probar"]:disabled'), n).catch(() => {});
      await p.waitForTimeout(150);
    };
    await prueba(true);
    let r = await txt(p, '[data-correo="resultado"]');
    ok('prueba_fallida: mensaje traducido + «código técnico» EAUTH 535', /no ha aceptado la prueba/.test(r) && /iniciar sesión/.test(r) && /EAUTH 535/.test(r), r);
    ok('prueba_fallida: NADA del texto del servidor ni HTML ejecutado', !/ADMIN-HOST|Authentication failed|<img|TEXTO-LIBRE/.test(await p.evaluate(() => document.body.innerText)) && !(await p.evaluate(() => window.__xss)));
    ok('prueba_fallida: el código NO se ha gastado → sigue pidiendo el código y los datos quedan bloqueados para repetir', await hay(p, cam('codigo')) && await p.$eval(cam('host'), (e) => e.readOnly) && await valor(p, 'pass') === SECRETO);
    ok('la contraseña de la cuenta se vació en cuanto se leyó', await valor(p, 'reauth') === '');
    await prueba(false);
    r = await txt(p, '[data-correo="resultado"]');
    ok('reautenticar: mensaje claro y sigue el campo de la contraseña de la cuenta', /Confirma tu contraseña/.test(r) && await hay(p, cam('reauth')), r);
    await prueba(true);
    ok('clave_actual_incorrecta: mensaje', /no es la contraseña de tu cuenta/.test(await txt(p, '[data-correo="resultado"]')));
    await prueba(true);
    ok('429: «demasiados intentos» (o códigos pedidos)', /Demasiados intentos/.test(await txt(p, '[data-correo="resultado"]')));
    await prueba(true);
    ok('envios_pausados: explicado como pausa, no como contraseña mala, y el botón queda desactivado', /pausa/.test(await txt(p, '[data-correo="resultado"]')) && /no es un fallo de la contraseña/.test(await txt(p, '[data-correo="resultado"]')) && await p.$eval('[data-accion="correo-servidor-probar"]', (e) => e.disabled));
    // codigo_no_valido: tira el código, desbloquea y VACÍA la contraseña
    await p.evaluate(() => { document.querySelector('[data-accion="correo-servidor-probar"]').disabled = false; });
    const ctx2 = await abre({ datos: DATOS() }, (c) => c.accion === 'estado' ? { status: 200, body: ESTADO() } : c.accion === 'pedir_codigo' ? CODIGO_OK : err(403, 'codigo_no_valido'));
    await espera(ctx2.p, '[data-accion="correo-servidor-editar"]');
    await ctx2.p.click('[data-accion="correo-servidor-editar"]');
    await ctx2.p.fill(cam('host'), 'smtp.otro.com');
    await ctx2.p.fill(cam('pass'), SECRETO);
    await ctx2.p.click('[data-accion="correo-servidor-pedir"]');
    await espera(ctx2.p, cam('codigo'));
    await ctx2.p.fill(cam('codigo'), '000000');
    await ctx2.p.fill(cam('reauth'), CUENTA);
    await ctx2.p.click('[data-accion="correo-servidor-probar"]');
    await ctx2.p.waitForFunction(() => /código no vale/.test((document.querySelector('[data-correo="resultado"]') || {}).textContent || ''));
    const rr = await txt(ctx2.p, '[data-correo="resultado"]');
    ok('codigo_no_valido: un solo mensaje (incorrecto, caducado, usado o de otros datos), sin pistas del servidor', /no vale/.test(rr) && /Pide uno nuevo/.test(rr) && !/TEXTO-LIBRE/.test(rr), rr);
    ok('codigo_no_valido: vuelve a «Pedir código», desbloquea los datos y vacía las contraseñas', await hay(ctx2.p, '[data-accion="correo-servidor-pedir"]') && !(await hay(ctx2.p, cam('codigo'))) && await ctx2.p.$eval(cam('host'), (e) => !e.readOnly) && await sinSecretos(ctx2.p));
    await ctx2.ctx.close();
    await ctx.close();
  }

  // 4. Fallos al PEDIR el código: cada uno en llano y sin dejar nada pedido ni contraseñas en pantalla
  for (const [codigo, status, esperado] of [['codigo_no_enviado', 502, /No se ha podido mandar el código/], ['demasiados_intentos', 429, /Demasiados intentos o códigos/], ['codigo_no_disponible', 503, /confirmación por código no está disponible/],
                                            ['sin_dominio_web', 400, /no tiene dominio configurado/], ['host_no_resuelve', 400, /no existe/], ['host_privado', 400, /red interna/], ['envios_pausados', 503, /pausa/],
                                            ['sin_correo_usuario', 400, /no tiene un correo válido/], ['sin_sesion', 401, /sesión ha caducado/], ['no_super_admin', 403, /super admin/], ['origen', 403, /no está autorizada/]]) {
    const { p, ctx } = await abre({ datos: DATOS() }, (c) => c.accion === 'estado' ? { status: 200, body: ESTADO() } : err(status, codigo));
    await espera(p, '[data-accion="correo-servidor-editar"]');
    await p.click('[data-accion="correo-servidor-editar"]');
    await p.fill(cam('host'), 'smtp.otro.com');
    await p.fill(cam('pass'), SECRETO);
    await p.click('[data-accion="correo-servidor-pedir"]');
    await p.waitForFunction(() => /No se pidió el código/.test((document.querySelector('[data-correo="resultado"]') || {}).textContent || ''));
    const r = await txt(p, '[data-correo="resultado"]');
    ok('pedir → ' + codigo + ': mensaje en llano', esperado.test(r) && !/TEXTO-LIBRE|<b>/.test(r), r);
    ok('pedir → ' + codigo + ': nada queda pedido (sigue «Pedir código»), contraseña vaciada', await hay(p, '[data-accion="correo-servidor-pedir"]') && !(await hay(p, cam('codigo'))) && await sinSecretos(p));
    await ctx.close();
  }
  {
    // datos que faltan: ni se llama a la edge
    const { p, ctx, llamadas } = await abre({ datos: DATOS() }, (c) => ({ status: 200, body: ESTADO() }));
    await espera(p, '[data-accion="correo-servidor-editar"]');
    await p.click('[data-accion="correo-servidor-editar"]');
    await p.click('[data-accion="correo-servidor-pedir"]');
    ok('sin contraseña del buzón: lo dice y no llama a la edge', /Rellena el servidor/.test(await txt(p, '[data-correo="resultado"]')) && llamadas.length === 1);
    await p.click('[data-accion="correo-servidor-cancelar"]');
    ok('Cancelar pliega el formulario', !(await hay(p, cam('host'))));
    await ctx.close();
  }

  // 5. Direcciones: Pedir código → 6 cifras → Guardar (por la edge, nunca por la RPC de config)
  {
    let guardadas = 0;
    const { p, ctx, llamadas } = await abre({ datos: DATOS() }, (c) => {
      if (c.accion === 'estado') return { status: 200, body: ESTADO(guardadas ? { remitente: { email_from: 'nuevo@negocio.com', efectivo: 'nuevo@negocio.com' } } : {}) };
      if (c.accion === 'pedir_codigo') return CODIGO_OK;
      guardadas++;
      return { status: 200, body: { ok: true, guardado: true, cambiado: true, aviso: 'sin_destinatario', clave: c.clave } };
    });
    await espera(p, '[data-correo-fila="email_from"]');
    const f = '[data-correo-fila="email_from"] ';
    await p.click(f + '[data-accion="correo-ajuste-pedir"]');
    ok('mismo valor que el actual: lo dice y no llama a la edge', /ya es el actual/.test(await txt(p, '[data-correo="resultado-email_from"]')) && llamadas.length === 1);
    await p.fill(cam('dir-email_from'), 'no-es-un-correo');
    await p.click(f + '[data-accion="correo-ajuste-pedir"]');
    ok('valor que no es un correo: lo dice y no llama a la edge', /dirección de correo completa/.test(await txt(p, '[data-correo="resultado-email_from"]')) && llamadas.length === 1);
    await p.fill(cam('dir-email_from'), ' nuevo@negocio.com ');
    await p.click(f + '[data-accion="correo-ajuste-pedir"]');
    await espera(p, cam('dir-codigo-email_from'));
    const c1 = llamadas[1].cuerpo;
    ok('pedir_codigo del ajuste: accion, alcance ajuste, clave y valor recortado; sin contraseña ni código', c1.accion === 'pedir_codigo' && c1.alcance === 'ajuste' && c1.clave === 'email_from' && c1.valor === 'nuevo@negocio.com' && Object.keys(c1).length === 4, JSON.stringify(c1));
    ok('el valor queda bloqueado mientras hay un código pedido', await p.$eval(cam('dir-email_from'), (e) => e.readOnly));
    ok('solo esa dirección pide código: las demás siguen con «Pedir código»', (await p.$$('[data-accion="correo-ajuste-pedir"]:not([disabled])')).length === 3);
    await foto(p, '4_direccion_codigo');
    await p.fill(cam('dir-codigo-email_from'), '12345');
    await p.click(f + '[data-accion="correo-ajuste-guardar"]');
    ok('código de 5 cifras: no llama a la edge', /6 cifras/.test(await txt(p, '[data-correo="resultado-email_from"]')) && llamadas.length === 2);
    await p.fill(cam('dir-codigo-email_from'), '123456');
    await p.click(f + '[data-accion="correo-ajuste-guardar"]');
    await p.waitForFunction(() => /Guardado/.test((document.querySelector('[data-correo="resultado-email_from"]') || {}).textContent || ''));
    const c2 = llamadas[2].cuerpo;
    ok('guardar_ajuste: accion, clave, valor y codigo (nada más)', c2.accion === 'guardar_ajuste' && c2.clave === 'email_from' && c2.valor === 'nuevo@negocio.com' && c2.codigo === '123456' && Object.keys(c2).length === 4, JSON.stringify(c2));
    ok('aviso «sin otro destinatario» explicado', /nadie más a quien avisar/.test(await txt(p, '[data-correo="resultado-email_from"]')));
    await p.waitForFunction(() => /nuevo@negocio\.com/.test((document.querySelector('[data-correo="actual-email_from"]') || {}).textContent || ''));
    ok('el valor actual sale de la edge (estado de nuevo) y la casilla vuelve a pedir código', llamadas[3].cuerpo.accion === 'estado' && await hay(p, f + '[data-accion="correo-ajuste-pedir"]'));
    ok('NUNCA por la RPC de config: __guardados vacío', (await p.evaluate(() => window.__guardados)).length === 0);
    // Responder a: vaciarlo es válido
    await p.fill(cam('dir-email_reply_to'), '');
    await p.click('[data-correo-fila="email_reply_to"] [data-accion="correo-ajuste-pedir"]');
    await espera(p, cam('dir-codigo-email_reply_to'));
    ok('«Responder a» puede quedar vacío', llamadas.filter((l) => l.cuerpo.accion === 'pedir_codigo').pop().cuerpo.valor === '');
    // caducidad local: pasados 11 min no se gasta la llamada
    const n = llamadas.length;
    await p.evaluate(() => { const o = Date.now; Date.now = () => o() + 11 * 60000; });
    await p.fill(cam('dir-codigo-email_reply_to'), '111111');
    await p.click('[data-correo-fila="email_reply_to"] [data-accion="correo-ajuste-guardar"]');
    ok('código caducado en pantalla: lo dice, no llama y vuelve a pedir', /caducado/.test(await txt(p, '[data-correo="resultado-email_reply_to"]')) && llamadas.length === n && await hay(p, '[data-correo-fila="email_reply_to"] [data-accion="correo-ajuste-pedir"]'));
    await ctx.close();
  }
  for (const [codigo, status, esperado] of [['codigo_no_valido', 403, /código no vale/], ['from_ajeno', 400, /mismo dominio/], ['buzon_ajeno', 400, /dominio de la instalación/], ['valor_no_valido', 400, /no es válido/],
                                            ['clave_no_editable', 400, /no se puede cambiar/], ['sin_dominio_web', 400, /no tiene dominio/], ['sin_cambios', 400, /ya es el actual/], ['base_no_responde', 502, /La base no ha respondido/]]) {
    const { p, ctx } = await abre({ datos: DATOS() }, (c) => c.accion === 'estado' ? { status: 200, body: ESTADO() } : c.accion === 'pedir_codigo' ? CODIGO_OK : err(status, codigo));
    await espera(p, '[data-correo-fila="email_avisos_sistema"]');
    await p.fill(cam('dir-email_avisos_sistema'), 'otro@negocio.com');
    await p.click('[data-correo-fila="email_avisos_sistema"] [data-accion="correo-ajuste-pedir"]');
    await espera(p, cam('dir-codigo-email_avisos_sistema'));
    await p.fill(cam('dir-codigo-email_avisos_sistema'), '999999');
    await p.click('[data-correo-fila="email_avisos_sistema"] [data-accion="correo-ajuste-guardar"]');
    await p.waitForFunction(() => /No se guardó/.test((document.querySelector('[data-correo="resultado-email_avisos_sistema"]') || {}).textContent || ''));
    const r = await txt(p, '[data-correo="resultado-email_avisos_sistema"]');
    ok('guardar_ajuste → ' + codigo + ': mensaje en llano', esperado.test(r) && !/TEXTO-LIBRE|<b>/.test(r), r);
    const sigue = codigo === 'base_no_responde';
    ok('guardar_ajuste → ' + codigo + (sigue ? ': el código sigue (se puede repetir)' : ': hay que pedir otro código; lo escrito se conserva'), sigue ? await hay(p, cam('dir-codigo-email_avisos_sistema')) : (await hay(p, '[data-correo-fila="email_avisos_sistema"] [data-accion="correo-ajuste-pedir"]') && await valor(p, 'dir-email_avisos_sistema') === 'otro@negocio.com'));
    await ctx.close();
  }

  // 6. La edge sin desplegar: 404 de la plataforma, 500 y sin respuesta (red/CORS)
  for (const [nombre, resp, esperado] of [['404', () => ({ status: 404, body: { code: 'NOT_FOUND', message: 'Requested function was not found' } }), /todavía no está disponible/],
                                          ['502 HTML', () => ({ status: 502, html: '<html>Bad gateway SECRETO-INTERNO</html>' }), /todavía no está disponible/],
                                          ['sin red / CORS', () => 'abort', /No se ha podido contactar/]]) {
    const { p, ctx } = await abre({ datos: DATOS() }, resp);
    await p.waitForSelector('[data-correo="estado"] [data-accion="correo-estado-reintentar"]');
    const t = await txt(p, '[data-correo="estado"]');
    ok('edge ' + nombre + ': mensaje claro y botón Reintentar', esperado.test(t) && !/SECRETO-INTERNO|NOT_FOUND|Requested function/.test(t), t);
    ok('edge ' + nombre + ': el resto del formulario de Correo sigue funcionando', (await p.$$('[data-ajuste="email_avisos_reservas"]')).length === 1);
    await foto(p, '5_edge_caida_' + nombre.replace(/\W/g, ''));
    await ctx.close();
  }

  // 7. Un admin (no super): no se llama a la edge · sin pepper en la edge (pide_codigo=false): nada se puede pedir
  {
    const { p, ctx, llamadas } = await abre({ datos: DATOS({ puede_escribir: false }) }, () => ({ status: 403, body: { ok: false, codigo: 'no_super_admin' } }));
    await p.waitForSelector('#lw-aj-correo-servidor h2');
    await p.waitForTimeout(300);
    ok('admin sin super: no se llama a la edge', llamadas.length === 0);
    ok('admin sin super: lo dice', /Solo el super admin/.test(await txt(p, '#lw-aj-correo-servidor')));
    ok('admin sin super: sin botones de pedir código', !(await hay(p, '[data-accion^="correo-"]')));
    await ctx.close();
  }
  {
    const { p, ctx } = await abre({ datos: DATOS() }, () => ({ status: 200, body: ESTADO({ pide_codigo: false }) }));
    await espera(p, '[data-correo="sin-codigo"]');
    ok('sin código disponible en la edge: se explica y TODOS los «Pedir código» están desactivados', /no está disponible/.test(await txt(p, '[data-correo="sin-codigo"]')) && (await p.$$('[data-accion="correo-ajuste-pedir"]:not([disabled])')).length === 0);
    await ctx.close();
  }

  // 8. Otra pestaña, idioma, XSS por el estado, móvil
  {
    const { p, ctx, llamadas } = await abre({ datos: DATOS(), idioma: 'en' }, (c) => ({ status: 200, body: ESTADO({ remitente: { motivo: 'dominio_distinto', efectivo: 'envios@otro.com' }, estado: { intentos_recientes: 2 } }) }), '#empresa');
    await p.waitForTimeout(400);
    ok('en otra pestaña (#empresa) no se llama a la edge', llamadas.length === 0);
    await p.evaluate(() => { location.hash = 'correo'; });
    await espera(p, '[data-correo-fila="email_from"]');
    ok('al abrir Correo se pide el estado una vez', llamadas.length === 1);
    ok('desajuste de dominio visible (y apunta a «Addresses»)', /envios@otro\.com/.test(await txt(p, '[data-correo="desajuste-dominio"]')) && /Addresses/.test(await txt(p, '[data-correo="desajuste-dominio"]')));
    ok('intentos recientes visibles', /2 of 5/.test(await txt(p, '[data-correo="estado"]')));
    ok('en inglés: cabeceras, botones y ayudas traducidas', /Outgoing mail server/.test(await txt(p, '#lw-aj-correo-servidor')) && /Request code/.test(await txt(p, '[data-correo-fila="email_from"]')) && /Email addresses/.test(await txt(p, '#lw-aj-correo-servidor')) && /Reply to/.test(await txt(p, '#lw-aj-correo-servidor')));
    // Nada de la pestaña Correo se queda en español con la interfaz en inglés (LW_T_MISSES lo anota el propio lwT del diccionario de la suite)
    const faltan = await p.evaluate(() => [...window.LW_T_MISSES].filter((s) => /[A-Za-z]{3}/.test(s) && !/^[\s—·:.,()0-9]*$/.test(s)));
    ok('en inglés: ninguna frase de Ajustes › Correo sin traducir', faltan.length === 0, JSON.stringify(faltan.slice(0, 8)));
    await ctx.close();
  }
  {
    const { p, ctx } = await abre({ datos: DATOS() }, () => ({ status: 200, body: ESTADO({ estado: { host: '<img src=x onerror=window.__xss=1>', usuario: '"><script>window.__xss=2</script>', puesto_por: '<img src=x onerror=window.__xss=3>' }, avisos: { soporte: '<img src=x onerror=window.__xss=4>' }, remitente: { email_from: '"><svg onload=window.__xss=5>' } }) }));
    await espera(p, '[data-correo-fila="email_from"]');
    ok('estado con HTML hostil: no se ejecuta y se ve como texto', !(await p.evaluate(() => window.__xss)) && /<img src=x/.test(await txt(p, '[data-correo="servidor-actual"]')));
  await ctx.close();
  }
  {
    const { p, ctx } = await abre({ datos: DATOS() }, (c) => c.accion === 'estado' ? { status: 200, body: ESTADO() } : CODIGO_OK, '#correo', 390);
    await espera(p, '[data-correo-fila="email_from"]');
    await p.fill(cam('dir-email_from'), 'nuevo@negocio.com');
    await p.click('[data-correo-fila="email_from"] [data-accion="correo-ajuste-pedir"]');
    await espera(p, cam('dir-codigo-email_from'));
    ok('móvil 390px: sin desbordamiento horizontal con el código pedido', await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1));
    await foto(p, '6_movil_390');
    await ctx.close();
  }
  await b.close();
  console.log(fallos ? '\n' + fallos + ' FALLO(S)' : '\ntodo en verde');
  process.exit(fallos ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
