/* node guard.test.js — la puerta (guard.js) con una sesión simulada (23-sep-2026).
   Ejecuta el guard.js REAL en un sandbox: sin navegador y sin base, con un
   supabase-js falso que devuelve la ficha que se le diga. Comprueba quién entra
   y quién rebota según `data-herramienta` y `data-rol` (LAW-275). */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const CODIGO = fs.readFileSync(path.join(__dirname, 'guard.js'), 'utf8');

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
    auth: { getSession: () => Promise.resolve({ data: { session: { user: { id: 'u1', app_metadata: {} } } } }) },
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: () =>
      opts.fichaFalla ? Promise.reject(new Error('red')) : Promise.resolve({ data: ficha }) }) }) }),
  };
  ctx.supabase = { createClient: () => sb };
  vm.createContext(ctx);
  vm.runInContext(CODIGO, ctx);
  let entra = false;
  ctx.LW_AUTH.then(() => { entra = true; });
  return new Promise(r => setTimeout(() => r({ entra, salidas }), 30));
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

  console.log('guard.test.js OK');
})().catch(e => { console.error(e); process.exit(1); });
