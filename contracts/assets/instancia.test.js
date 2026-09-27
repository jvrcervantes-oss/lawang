/* instancia.test.js — ERP F3 lote 3 (27-sep-2026), encargos/20260924_estudio_erp_modular.md.
   Lo que decidía el código con NOMBRES de proyecto de Lawang vive ahora en la ficha de la instancia
   (instancia.js: `masterplans`, `proyectos_con_fases`). Este test afirma el hecho en los sitios donde vive:
   1) la ficha está congelada entera (lo anidado también: si no, cualquiera la pisa en la página);
   2) cada masterplan de la ficha existe en el repo (una ruta rota deja el botón «Plano» abriendo un error);
   3) ningún nombre de proyecto de la ficha vuelve a escribirse como literal en el código compartido que la lee
      (si reaparece, esa pantalla vuelve a decidir por el nombre de un cliente, que es lo que F3 quita).
   Ejecutar: node contracts/assets/instancia.test.js */
const fs = require('fs'), path = require('path'), vm = require('vm'), assert = require('assert');
const RAIZ = path.join(__dirname, '..', '..');
const ctx = { window: {} }; ctx.window.window = ctx.window; vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, 'instancia.js'), 'utf8'), ctx);
const F = ctx.window.LW_INSTANCIA;

// 1) congelada entera
assert.ok(F && Object.isFrozen(F), 'la ficha existe y está congelada');
assert.ok(F.masterplans && typeof F.masterplans === 'object' && Object.isFrozen(F.masterplans), 'masterplans congelado');
assert.ok(Array.isArray(F.proyectos_con_fases) && Object.isFrozen(F.proyectos_con_fases), 'proyectos_con_fases congelado');

// 2) cada masterplan apunta a un .json que existe
const mps = Object.keys(F.masterplans);
for (const n of mps) {
  const ruta = F.masterplans[n];
  assert.ok(/^\/investor-deck\/masterplan\/[a-z0-9-]+\.json$/.test(ruta), n + ': ruta de masterplan con forma rara: ' + ruta);
  assert.ok(fs.existsSync(path.join(RAIZ, ruta.slice(1))), n + ': no existe ' + ruta);
}

// 3) los nombres de la ficha no vuelven como literal al código que la lee
const LECTORES = ['intranet/v4/proyectos/index.html', 'intranet/v4/assets/editores.js'];
const nombres = Array.from(new Set(mps.concat(Array.from(F.proyectos_con_fases))));
for (const rel of LECTORES) {
  // Fichero entero, sin quitar comentarios: quitarlos con una regex se come código (un `'*/*'` abre un comentario
  // falso) y el test pasaría sin mirar. Una nota histórica puede nombrar un proyecto, pero sin comillas.
  const t = fs.readFileSync(path.join(RAIZ, rel), 'utf8');
  for (const n of nombres) {
    const lit = [ "'" + n + "'", '"' + n + '"' ];
    for (const l of lit) assert.ok(!t.includes(l), rel + ': el nombre de proyecto ' + l + ' vuelve a estar escrito en el código (va en la ficha)');
  }
}
console.log('instancia.test.js OK (' + mps.length + ' masterplans, ' + F.proyectos_con_fases.length + ' con fases, ' + LECTORES.length + ' lectores limpios)');
