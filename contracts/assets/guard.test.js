/* node guard.test.js — la puerta (guard.js) con una sesión simulada (23-sep-2026).
   Ejecuta el guard.js REAL en un sandbox: sin navegador y sin base, con un
   supabase-js falso que devuelve la ficha que se le diga. Comprueba quién entra
   y quién rebota según `data-herramienta` y `data-rol` (LAW-275). */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const CODIGO = fs.readFileSync(path.join(__dirname, 'guard.js'), 'utf8');
// La ficha de la instancia va antes de guard.js en cada página (ERP F3): el test hace lo mismo, con la real.
const INSTANCIA = fs.readFileSync(path.join(__dirname, 'instancia.js'), 'utf8');
// roles.js (LW_ROL) también va antes de guard.js en cada página
const ROLES = fs.readFileSync(path.join(__dirname, 'roles.js'), 'utf8');

function puerta(attrs, ficha, opts) {
  opts = opts || {};
  const salidas = [];
  const el = () => ({ style: {}, appendChild() {}, set innerHTML(v) {}, get parentNode() { return null; } });
  const ctx = {
    console,
    location: { hostname: 'www.lawangproperties.com', search: '', pathname: '/intranet/v4/ajustes/', replace: u => salidas.push(u) },
    document: {
      readyState: 'complete',
      currentScript: { getAttribute: k => (attrs[k] == null ? null : attrs[k]) },
      documentElement: el(),
      createElement: el,
      addEventListener() {},
    },
    URLSearchParams,
    Promise,
  };
  ctx.window = ctx;
  const sb = {
    auth: { getSession: () => Promise.resolve({ data: { session: { user: { id: 'u1', app_metadata: opts.portal ? { portal: true } : {} } } } }),
      signOut: () => { salidas.push('SIGNOUT'); return Promise.resolve(); } },
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: () =>
      opts.fichaFalla ? Promise.reject(new Error('red')) : Promise.resolve({ data: ficha }) }) }) }),
  };
  ctx.supabase = { createClient: () => sb };
  vm.createContext(ctx);
  if (!opts.sinFicha) { vm.runInContext(INSTANCIA, ctx); vm.runInContext(ROLES, ctx); }
  try { vm.runInContext(CODIGO, ctx); } catch (e) { if (!opts.sinFicha) throw e; return Promise.resolve({ entra: false, salidas, error: e.message }); }
  let entra = false;
  ctx.LW_AUTH.then(() => { entra = true; });
  return new Promise(r => setTimeout(() => r({ entra, salidas }), 30));
}


// el helper LW_ROL tal como lo publica guard.js (sin sesión: solo se evalúa el script)
function puertaRol() {
  const ctx = { console, location: { hostname: 'x', search: '', pathname: '/', replace() {} },
    document: { readyState: 'complete', currentScript: { getAttribute: () => null }, documentElement: { style: {}, appendChild() {} },
      createElement: () => ({ style: {}, appendChild() {}, set innerHTML(v) {} }), addEventListener() {} },
    URLSearchParams, Promise };
  ctx.window = ctx;
  ctx.supabase = { createClient: () => ({ auth: { getSession: () => new Promise(() => {}) } }) };
  vm.createContext(ctx);
  vm.runInContext(INSTANCIA, ctx); vm.runInContext(ROLES, ctx); vm.runInContext(CODIGO, ctx);
  return ctx.LW_ROL;
}

const AGENTE = { rol: 'agente', activo: true, herramientas: ['cuentas', 'usuarios'] };
const ADMIN = { rol: 'admin', activo: true, herramientas: ['cuentas'] };
const SUPER = { rol: 'super_admin', activo: true, herramientas: [] };

(async () => {
  // solo rol admin (Ajustes, Condiciones, Equipos de venta, Comunicación)
  let r = await puerta({ 'data-rol': 'admin' }, AGENTE);
  assert.ok(!r.entra && /sin_permiso=Panel/.test(r.salidas[0] || ''), 'un agente no entra en una página de admin: ' + JSON.stringify(r));
  r = await puerta({ 'data-rol': 'admin' }, ADMIN);
  assert.ok(r.entra && !r.salidas.length, 'un admin entra');
  r = await puerta({ 'data-rol': 'admin' }, SUPER);
  assert.ok(r.entra, 'el super admin entra');

  // solo super admin (Comisión de administración, Sociedades)
  r = await puerta({ 'data-rol': 'super_admin' }, ADMIN);
  assert.ok(!r.entra && r.salidas.length, 'un admin no entra en una página de super admin');
  r = await puerta({ 'data-rol': 'super_admin' }, SUPER);
  assert.ok(r.entra, 'el super admin entra en la suya');

  // lista de roles (Equipos de venta, Condiciones: admin + sales manager)
  const SM = { rol: 'sales_manager', activo: true, herramientas: [] };
  const PM = { rol: 'project_manager', activo: true, herramientas: [] };
  r = await puerta({ 'data-rol': 'admin sales_manager' }, SM);
  assert.ok(r.entra, 'un sales manager entra donde la lista lo nombra');
  r = await puerta({ 'data-rol': 'admin sales_manager' }, ADMIN);
  assert.ok(r.entra, 'el admin sigue entrando con la lista');
  r = await puerta({ 'data-rol': 'admin sales_manager' }, SUPER);
  assert.ok(r.entra, 'el super admin entra siempre');
  r = await puerta({ 'data-rol': 'admin sales_manager' }, AGENTE);
  assert.ok(!r.entra, 'un agente no entra aunque haya lista');
  r = await puerta({ 'data-rol': 'admin sales_manager' }, PM);
  assert.ok(!r.entra, 'un project manager no entra si no está en la lista');
  r = await puerta({ 'data-rol': 'admin' }, SM);
  assert.ok(!r.entra, 'con data-rol=admin un sales manager no entra');
  r = await puerta({ 'data-rol': 'adminn' }, SM);
  assert.ok(!r.entra, 'un data-rol mal escrito no abre la puerta');

  // rol + herramienta: hacen falta las dos (Cuentas)
  r = await puerta({ 'data-rol': 'admin', 'data-herramienta': 'cuentas' }, AGENTE);
  assert.ok(!r.entra, 'un agente CON la herramienta cuentas no entra: falta el rol');
  r = await puerta({ 'data-rol': 'admin', 'data-herramienta': 'usuarios' }, ADMIN);
  assert.ok(!r.entra, 'un admin SIN la herramienta usuarios no entra');
  r = await puerta({ 'data-rol': 'admin', 'data-herramienta': 'cuentas' }, ADMIN);
  assert.ok(r.entra, 'admin con la herramienta entra');

  // Ajustes y Comunicados (27-sep-2026): rol admin Y su casilla, como la exige la base
  const ADMIN_SIN = { rol: 'admin', activo: true, herramientas: ['cuentas'] };
  const ADMIN_CON = { rol: 'admin', activo: true, herramientas: ['ajustes', 'comunicacion'] };
  for (const k of ['ajustes', 'comunicacion']) {
    r = await puerta({ 'data-rol': 'admin', 'data-herramienta': k }, ADMIN_SIN);
    assert.ok(!r.entra, 'un admin sin la casilla ' + k + ' no entra');
    r = await puerta({ 'data-rol': 'admin', 'data-herramienta': k }, ADMIN_CON);
    assert.ok(r.entra, 'un admin con la casilla ' + k + ' entra');
    r = await puerta({ 'data-rol': 'admin', 'data-herramienta': k }, { rol: 'agente', activo: true, herramientas: [k] });
    assert.ok(!r.entra, 'un agente con la casilla ' + k + ' no entra: falta el rol');
  }

  // Roles de EMPRESA (7-oct-2026): para la puerta cuentan como admin / super admin, salvo en lo que es de toda la instancia
  const ADMIN_E = { rol: 'admin_empresa', ambito: 'empresa', empresas: ['lawang'], activo: true, herramientas: ['cuentas', 'ajustes'] };
  const SUPER_E = { rol: 'super_admin_empresa', ambito: 'empresa', empresas: ['lawang', 'sandal_woods'], activo: true, herramientas: ['cuentas'] };
  r = await puerta({ 'data-rol': 'admin' }, ADMIN_E);
  assert.ok(r.entra, 'un admin de empresa entra donde entra un admin');
  r = await puerta({ 'data-rol': 'super_admin' }, ADMIN_E);
  assert.ok(!r.entra, 'un admin de empresa NO entra donde pide super admin');
  r = await puerta({ 'data-rol': 'super_admin' }, SUPER_E);
  assert.ok(r.entra, 'un super de empresa entra donde entra un super (la base filtra por empresa)');
  r = await puerta({ 'data-rol': 'admin sales_manager' }, ADMIN_E);
  assert.ok(r.entra, 'el admin de empresa entra con la lista admin + sales_manager');
  r = await puerta({ 'data-rol': 'admin', 'data-ambito': 'global' }, ADMIN_E);
  assert.ok(!r.entra && r.salidas.length, 'una pantalla de la instancia (data-ambito=global) cierra a un rol de empresa');
  r = await puerta({ 'data-rol': 'super_admin', 'data-ambito': 'global' }, SUPER_E);
  assert.ok(!r.entra, 'ni siquiera al super de empresa');
  r = await puerta({ 'data-rol': 'admin', 'data-ambito': 'global' }, ADMIN);
  assert.ok(r.entra, 'el admin global entra como siempre en la pantalla de la instancia');
  r = await puerta({ 'data-rol': 'super_admin', 'data-ambito': 'global' }, SUPER);
  assert.ok(r.entra, 'el super global también');
  // Comisión de administración (data-ambito="super-global", 7-oct-2026, owner): solo los super admins GLOBALES; ni el super de empresa ni un admin
  r = await puerta({ 'data-rol': 'super_admin', 'data-ambito': 'super-global' }, SUPER);
  assert.ok(r.entra, 'el super global entra en la Comisión de administración');
  r = await puerta({ 'data-rol': 'super_admin', 'data-ambito': 'super-global' }, SUPER_E);
  assert.ok(!r.entra && r.salidas.length, 'un super de empresa NO entra en la Comisión de administración');
  r = await puerta({ 'data-rol': 'super_admin', 'data-ambito': 'super-global' }, ADMIN_E);
  assert.ok(!r.entra, 'un admin de empresa tampoco');
  r = await puerta({ 'data-rol': 'super_admin', 'data-ambito': 'super-global' }, ADMIN);
  assert.ok(!r.entra, 'un admin global tampoco');
  // Sociedades emisoras (data-ambito="propietario"): solo el propietario (super global con es_propietario)
  const PROP = { rol: 'super_admin', ambito: 'global', es_propietario: true, activo: true, herramientas: [] };
  r = await puerta({ 'data-rol': 'super_admin', 'data-ambito': 'propietario' }, PROP);
  assert.ok(r.entra, 'el propietario entra en Sociedades emisoras');
  r = await puerta({ 'data-rol': 'super_admin', 'data-ambito': 'propietario' }, SUPER);
  assert.ok(!r.entra && r.salidas.length, 'un super global que no es el propietario NO entra en Sociedades emisoras');
  r = await puerta({ 'data-rol': 'super_admin', 'data-ambito': 'propietario' }, SUPER_E);
  assert.ok(!r.entra, 'un super de empresa tampoco');
  r = await puerta({ 'data-rol': 'super_admin', 'data-ambito': 'propietario' }, Object.assign({}, SUPER_E, { es_propietario: true }));
  assert.ok(!r.entra, 'es_propietario en una ficha de empresa no vale: lo exige el rol super_admin global');
  // las casillas: solo el super GLOBAL se las salta (igual que puede() en la base); el de empresa pasa por su lista
  r = await puerta({ 'data-herramienta': 'obra' }, SUPER_E);
  assert.ok(!r.entra, 'un super de empresa sin la casilla no entra: la lista manda');
  r = await puerta({ 'data-rol': 'admin', 'data-herramienta': 'ajustes' }, ADMIN_E);
  assert.ok(r.entra, 'admin de empresa con rol y casilla entra');
  // el helper público que usan todas las pantallas
  const ROL = puertaRol();
  assert.strictEqual(ROL.esAdmin(ADMIN_E), true); assert.strictEqual(ROL.esSuperAdmin(ADMIN_E), false);
  assert.strictEqual(ROL.esSuperAdmin(SUPER_E), true); assert.strictEqual(ROL.esSuperGlobal(SUPER_E), false);
  assert.strictEqual(ROL.esGlobal(SUPER_E), false); assert.strictEqual(ROL.esGlobal(ADMIN), true);
  assert.strictEqual(ROL.esAdmin(AGENTE), false); assert.strictEqual(ROL.esAdmin(null), false);
  assert.strictEqual(ROL.esGlobal(null), false, 'sin ficha no se enseña nada de la instancia');
  assert.strictEqual(ROL.esEmpresa({ rol: 'agente', ambito: 'empresa' }), true);
  assert.strictEqual(JSON.stringify(ROL.empresas(SUPER_E)), '["lawang","sandal_woods"]'); assert.strictEqual(JSON.stringify(ROL.empresas(ADMIN)), '[]');
  assert.strictEqual(ROL.puedeHerr(SUPER, 'x'), true); assert.strictEqual(ROL.puedeHerr(SUPER_E, 'x'), false);
  assert.strictEqual(ROL.puedeHerr(SUPER_E, 'cuentas'), true);

  // sin ficha legible: la regla general deja entrar (RLS protege); una de dirección, no
  r = await puerta({}, null, { fichaFalla: true });
  assert.ok(r.entra, 'sin data-rol, un fallo leyendo la ficha sigue dejando entrar (comportamiento de siempre)');
  r = await puerta({ 'data-rol': 'admin' }, null, { fichaFalla: true });
  assert.ok(!r.entra && r.salidas.length, 'con data-rol, sin ficha legible no se entra');

  // sin data-rol nada cambia: herramienta de siempre
  r = await puerta({ 'data-herramienta': 'obra' }, AGENTE);
  assert.ok(!r.entra && /sin_permiso=obra/.test(r.salidas[0] || ''), 'herramienta no asignada rebota como siempre');
  r = await puerta({ 'data-herramienta': 'cuentas' }, AGENTE);
  assert.ok(r.entra, 'herramienta asignada entra como siempre');

  // ERP F3: sin la ficha de la instancia, guard.js se para y nadie entra (ni se crea cliente contra ninguna base)
  r = await puerta({ 'data-herramienta': 'cuentas' }, SUPER, { sinFicha: true });
  assert.ok(!r.entra && /instancia\.js/.test(r.error || ''), 'sin instancia.js, guard.js para y no deja entrar');

  // 7-oct-2026 (Andrea): una sesion de CLIENTE (marca portal, sin ficha) guardada en la clave de la intranet ya no rebota a /portal/
  // (el portal guarda la suya en otra clave y no puede cerrarla): se cierra y se va al login
  r = await puerta({}, null, { portal: true });
  assert.ok(!r.entra, 'sin ficha y con marca de portal no se entra');
  assert.ok(r.salidas.indexOf('SIGNOUT') !== -1, 'se cierra la sesion vieja: ' + JSON.stringify(r.salidas));
  assert.ok(!r.salidas.some(u => /^\/portal\//.test(u)), 'no se manda a /portal/ con la sesion viva: ' + JSON.stringify(r.salidas));
  // y quien tiene ficha de equipo entra aunque lleve la marca de portal (manda la ficha)
  r = await puerta({}, AGENTE, { portal: true });
  assert.ok(r.entra && !r.salidas.length, 'con ficha de equipo entra aunque lleve la marca de portal: ' + JSON.stringify(r));
  // 14-oct-2026: el justificante del recibí va a la edge de base `ficheros` (clase justificante_cobro); el resto de
  // acciones de lwFicheros sigue en ficheros-contrato (bbm: recibos encendidos, contratos apagado)
  const llamadas = [];
  const ctxF = { console, location: { hostname: 'x', search: '', pathname: '/', replace() {} },
    document: { readyState: 'complete', currentScript: { getAttribute: () => null }, documentElement: { style: {}, appendChild() {} },
      createElement: () => ({ style: {}, appendChild() {}, set innerHTML(v) {} }), addEventListener() {} },
    URLSearchParams, Promise,
    fetch: (u, o) => { llamadas.push({ u, cuerpo: JSON.parse(o.body), auth: o.headers.authorization });
      return Promise.resolve({ status: 200, json: () => Promise.resolve({ ok: true, path: 'p.pdf', token: 't' }) }); } };
  ctxF.window = ctxF;
  ctxF.supabase = { createClient: () => ({ auth: { getSession: () => new Promise(() => {}) } }) };
  vm.createContext(ctxF);
  vm.runInContext(INSTANCIA, ctxF); vm.runInContext(ROLES, ctxF); vm.runInContext(CODIGO, ctxF);
  const sbF = { auth: { getSession: () => Promise.resolve({ data: { session: { access_token: 'jwt1' } } }) } };
  const d = await ctxF.lwFicheros(sbF, 'justificante_url', { ext: '.pdf' });
  assert.strictEqual(d.path, 'p.pdf');
  assert.ok(/\/functions\/v1\/ficheros$/.test(llamadas[0].u), 'el justificante va a la edge ficheros: ' + llamadas[0].u);
  assert.deepStrictEqual(llamadas[0].cuerpo, { ext: '.pdf', accion: 'subida_url', clase: 'justificante_cobro' });
  assert.strictEqual(llamadas[0].auth, 'Bearer jwt1');
  // una pantalla no puede colar otra clase ni otra acción por los datos: las pone guard.js después
  await ctxF.lwFicheros(sbF, 'justificante_url', { ext: '.pdf', clase: 'deck_foto', accion: 'borra' });
  assert.deepStrictEqual(llamadas[1].cuerpo, { ext: '.pdf', accion: 'subida_url', clase: 'justificante_cobro' });
  await ctxF.lwFicheros(sbF, 'limpia_borradores', {});
  assert.ok(/\/functions\/v1\/ficheros-contrato$/.test(llamadas[2].u), 'lo demás sigue en ficheros-contrato: ' + llamadas[2].u);
  assert.deepStrictEqual(llamadas[2].cuerpo, { accion: 'limpia_borradores' });
  // 17-oct-2026: las fotos de MODELO también se piden al servidor. En una instancia del ERP `deck` es privado y la URL
  // pública que se armaba aquí no carga; la edge firma si es privado y da la misma pública si no (Lawang, sin cambio).
  // Antes del arreglo la fila de modelo nunca salía del navegador.
  const pedidas = [];
  ctxF.fetch = (u, o) => { const c = JSON.parse(o.body); pedidas.push({ u, cuerpo: c });
    return Promise.resolve({ status: 200, json: () => Promise.resolve({ ok: true, caduca_seg: 3600,
      urls: Object.fromEntries(c.foto_ids.map(i => [i, 'https://srv/firmada/' + i])) }) }); };
  const sbFotos = Object.assign({}, sbF, { storage: { from: () => ({ getPublicUrl: p => ({ data: { publicUrl: 'https://pub/' + p } }) }) } });
  const fu = await ctxF.lwFotoUrls(sbFotos, [{ id: 'm1', ambito: 'modelo', path: 'modelos/a.webp' }, { id: 'p1', ambito: 'proyecto', path: 'x.webp' }]);
  assert.strictEqual(pedidas.length, 1, 'una sola llamada para el lote');
  assert.ok(/\/functions\/v1\/ficheros$/.test(pedidas[0].u), 'las URL de fotos las da la edge ficheros: ' + pedidas[0].u);
  assert.deepStrictEqual(pedidas[0].cuerpo, { foto_ids: ['m1', 'p1'], accion: 'urls', clase: 'deck_foto' }, 'la foto de modelo va al servidor como las demás');
  assert.deepStrictEqual(JSON.parse(JSON.stringify(fu.urls)), { m1: 'https://srv/firmada/m1', p1: 'https://srv/firmada/p1' }, 'la URL de la foto de modelo es la del servidor, no una pública armada aquí');
  assert.strictEqual(fu.caduca_seg, 3600);
  // … y ninguna pantalla vuelve a armarse la URL pública de `deck` por su cuenta (eran guard.js y v4/datos.js). La edge
  // (supabase/) sí puede: decide ella si el bucket es público. Los arneses llevan un Storage falso.
  // Las dos formas: getPublicUrl y la ruta /object/public/deck/ montada a mano. Fuera del escaneo quedan las páginas
  // públicas de Lawang (investor-deck/, coleccion/), que el ERP no copia a sus instancias.
  const RAIZ = path.join(__dirname, '..', '..');
  const ARMA_PUBLICA = /storage\.from\(\s*['"]deck['"]\s*\)\.getPublicUrl|\/object\/public\/deck\//;
  // builder.html guarda la ruta del formato viejo solo para que migrate() la traduzca a `deck:<id>`; nunca la pinta.
  const SOLO_RECONOCE = new Set([path.join('intranet', 'dossier', 'builder.html')]);
  const armanPublica = [];
  const recorre = d => {
    for (const n of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, n.name);
      if (n.isDirectory()) { if (n.name !== 'node_modules' && n.name !== 'vendor') recorre(p); continue; }
      if (!/\.(js|html|php)$/.test(n.name) || /^arnes_/.test(n.name) || /\.test\.js$/.test(n.name)) continue;
      if (SOLO_RECONOCE.has(path.relative(RAIZ, p))) continue;
      if (ARMA_PUBLICA.test(fs.readFileSync(p, 'utf8'))) armanPublica.push(path.relative(RAIZ, p));
    }
  };
  ['contracts', 'intranet', 'portal'].forEach(d => { if (fs.existsSync(path.join(RAIZ, d))) recorre(path.join(RAIZ, d)); });
  assert.deepStrictEqual(armanPublica, [], 'URL pública de `deck` armada en el navegador (en una instancia del ERP no carga): ' + armanPublica.join(', '));
  console.log('guard.test.js OK');
})().catch(e => { console.error(e); process.exit(1); });
