/* node admin_usuarios_herramientas.test.js — LAW-343 (27-sep-2026): en la edge admin-usuarios, un admin
   que no es super admin solo da herramientas que ÉL tiene, en las DOS altas (crear y activar_solicitud).
   Prueba estática sobre el código de la edge (como listas.test.js): si alguien reescribe una de las dos
   ramas y quita la comprobación, esto falla antes de desplegar. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, 'edge', 'admin-usuarios', 'index.ts'), 'utf8');
const rama = (accion) => {
  const i = src.indexOf("accion === '" + accion + "'");
  assert.ok(i > 0, 'no encuentro la acción ' + accion);
  const j = src.indexOf("if (accion === '", i + 10);
  return src.slice(i, j > 0 ? j : undefined);
};

const crear = rama('crear');
assert.ok(/new Set\(\(ficha\.herramientas/.test(crear), 'crear: calcula las herramientas de quien da el alta');
assert.ok(/if \(!soySuper\)[\s\S]{0,400}herramienta_que_no_tienes/.test(crear), 'crear: rechaza las que no tiene (403)');
assert.ok(crear.indexOf('herramienta_que_no_tienes') < crear.indexOf('createUser'), 'crear: comprueba ANTES de crear la cuenta');

const activar = rama('activar_solicitud');
assert.ok(/new Set\(\(ficha\.herramientas/.test(activar), 'activar_solicitud: calcula las herramientas de quien activa');
assert.ok(/soySuper \|\| mias\.has\(h\)/.test(activar), 'activar_solicitud: solo da las que tiene quien activa');
assert.ok(/herramientas_no_dadas/.test(activar), 'activar_solicitud: devuelve las que no ha podido dar');
assert.ok(activar.indexOf('mias.has') < activar.indexOf('createUser'), 'activar_solicitud: filtra ANTES de crear la cuenta');

console.log('admin_usuarios_herramientas.test.js OK');
