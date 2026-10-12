// Sociedades emisoras en Ajustes (12-oct-2026, owner: «Va en Ajustes»): node contracts/roles_sociedades.test.js
// LW_ROL.puedeSociedades tiene que ser el MISMO predicado que sociedad_guarda en cada base: en Lawang, solo el propietario (es_propietario());
// en el ERP maestro (window.AXW_NUCLEO_OPERACION), el rol super_admin global (allí es_propietario es latente). Y la pestaña oculta de Ajustes
// no se abre por la URL: desdeHash solo mira nombres de su lista (un hash raro no llega a querySelector).
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const src = fs.readFileSync(path.join(__dirname, 'assets', 'roles.js'), 'utf8');
const fichas = {
  propietario: { rol: 'super_admin', es_propietario: true, ambito: 'global' },
  super_global: { rol: 'super_admin', es_propietario: false, ambito: 'global' },
  super_empresa: { rol: 'super_admin_empresa', es_propietario: false, ambito: 'empresa' },
  admin: { rol: 'admin' }, agente: { rol: 'agente' }, sin_ficha: null
};
const esperado = {
  lawang: { propietario: true, super_global: false, super_empresa: false, admin: false, agente: false, sin_ficha: false },
  maestro: { propietario: true, super_global: true, super_empresa: false, admin: false, agente: false, sin_ficha: false }
};
let fallos = 0, total = 0;
for (const modo of Object.keys(esperado)) {
  const w = {}; w.window = w;
  if (modo === 'maestro') w.AXW_NUCLEO_OPERACION = true;
  vm.runInNewContext(src, w);
  for (const [k, f] of Object.entries(fichas)) {
    total++;
    const r = w.LW_ROL.puedeSociedades(f);
    if (r !== esperado[modo][k]) { fallos++; console.log('FALLA puedeSociedades ' + modo + ' / ' + k + ': ' + r); }
  }
}
// ajustes.js: la comprobación de la pestaña oculta mira la lista ANTES del selector
const aj = fs.readFileSync(path.join(__dirname, '..', 'intranet', 'v4', 'assets', 'ajustes.js'), 'utf8');
total++;
if (!/var bt = PESTANAS\.indexOf\(h\) >= 0 \? document\.querySelector\(/.test(aj)) { fallos++; console.log('FALLA ajustes.js: desdeHash pasa el hash al selector sin mirar la lista'); }
total++;
if (!/if \(bt && bt\.hidden\) h = '';/.test(aj)) { fallos++; console.log('FALLA ajustes.js: una pestaña oculta se abriría por la URL'); }
console.log((fallos ? 'FALLAN ' + fallos + ' de ' : 'OK ') + total + ' — roles_sociedades.test.js');
process.exit(fallos ? 1 : 0);
