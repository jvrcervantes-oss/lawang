/* node contracts/propios_permisos.test.js
   Encargo «editor de textos de contrato» · E9 · CONCEDER un contrato propio a un agente (8-oct-2026).
   Sin el slug del contrato propio en `usuarios.tipos_contrato`, la base rechaza al agente con 42501 al emitirlo. El formulario «Permisos de …» de la v4
   (intranet/v4/assets/editores.js) ofrece los 17 + los propios activos (RPC plantilla_contratos_propios_activos, datos.js) y NO quita en silencio lo que la
   persona ya tenía. Afirma, ejecutando el código real de datos.js y leyendo el de editores.js:
     1. los propios se piden por empresa, una empresa fuera de alcance (42501) no rompe a las demás y se guardan {slug: nombre};
     2. `tipoC` enseña el nombre del propio y deja el vocabulario de los 17 como está;
     3. el formulario de permisos suma los propios, conserva marcado lo que la persona ya tiene y no se ofrece, y avisa de la regla de «solo quien lo tiene»;
     4. el alta (13-oct-2026: la edge admin-usuarios ya acepta los propios que existen, preguntando a la base) los ofrece frescos y
        avisa de lo que la edge no dio (`tipos_no_dados`); antes los descartaba en silencio y el alta decía «se conceden después». */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const leer = (...p) => fs.readFileSync(path.join(__dirname, '..', ...p), 'utf8');
const datos = leer('intranet', 'v4', 'assets', 'datos.js');
const editores = leer('intranet', 'v4', 'assets', 'editores.js');
const vocab = leer('contracts', 'assets', 'vocabulario.js');
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };
const plano = x => (x === undefined ? x : JSON.parse(JSON.stringify(x)));   // los objetos del vm tienen otro prototipo
const eq = (a, b, m) => { assert.deepStrictEqual(plano(a), plano(b), m); n++; };

const trozo = datos.slice(datos.indexOf('window.LW_V4.tiposPropios = window.LW_V4.tiposPropios || {};'), datos.indexOf('/* «Hoy» en la fecha LOCAL'));
assert.ok(trozo.includes('function tipoC'), 'no encuentro tipoC en datos.js');

function sbFalso(propios, empresas) {
  const llamadas = [];
  return {
    llamadas,
    from() { const api = { select: () => api, eq: () => api, order: () => Promise.resolve({ data: empresas, error: null }) }; return api; },
    rpc(nombre, a) {
      llamadas.push(a.p_empresa);
      const v = propios[a.p_empresa];
      return Promise.resolve(v === 'NO' ? { data: null, error: { code: '42501' } } : { data: v || [], error: null });
    },
  };
}
const empresas = [{ clave: 'lawang', nombre: 'Lawang' }, { clave: 'sandal_woods', nombre: 'Sandal Woods' }];
function ctx() {
  const c = { window: { LW_V4: {} } };
  vm.createContext(c);
  vm.runInContext(vocab.replace(/\bconst /g, 'var ').replace(/\blet /g, 'var '), c);
  vm.runInContext(trozo.replace(/function (cargaTiposPropios|tipoC)\b/g, 'var $1 = function $1'), c);
  return c;
}

(async () => {
  // 1. carga por empresa
  let c = ctx();
  const sb = sbFalso({ lawang: [{ slug: 'lawang_contrato_de_obra', nombre: 'Contrato de obra' }], sandal_woods: 'NO' }, empresas);
  const lista = await vm.runInContext('cargaTiposPropios', c)(sb);
  eq(sb.llamadas, ['lawang', 'sandal_woods'], 'una llamada por empresa');
  eq(lista.map(f => f.slug), ['lawang_contrato_de_obra'], 'la empresa que contesta 42501 se salta sin romper a las demás');
  eq(c.window.LW_V4.tiposPropios, { lawang_contrato_de_obra: 'Contrato de obra' });
  eq(lista[0].empresaNombre, 'Lawang');
  // 2. etiquetas
  eq(vm.runInContext("tipoC('lawang_contrato_de_obra')", c), 'Contrato de obra', 'el propio se llama por su nombre');
  eq(vm.runInContext("tipoC('reserva_parcela')", c), vm.runInContext("lwTipoContrato('reserva_parcela')", c), 'los 17 siguen por el vocabulario');
  eq(vm.runInContext("tipoC('algo_desconocido')", c), 'algo_desconocido', 'lo que no conoce nadie sale tal cual');
  // sin red de empresas: no rompe
  c = ctx();
  const roto = { from() { const api = { select: () => api, eq: () => api, order: () => Promise.reject(new Error('sin red')) }; return api; }, rpc() { throw new Error('no debería'); } };
  eq(await vm.runInContext('cargaTiposPropios', c)(roto), [], 'si no se leen las empresas, no hay propios y nada se rompe');
  // el formulario pide frescos
  c = ctx();
  const s1 = sbFalso({ lawang: [] }, empresas), s2 = sbFalso({ lawang: [{ slug: 'lawang_nuevo', nombre: 'Nuevo' }] }, empresas);
  await vm.runInContext('cargaTiposPropios', c)(s1);
  const fresco = await vm.runInContext('cargaTiposPropios', c)(s2, true);
  eq(fresco.map(f => f.slug), ['lawang_nuevo'], 'con `fresco` vuelve a preguntar: un propio recién activado sale sin recargar');

  // 3. el formulario de permisos
  ok(/var variasEmp = \(rs\[4\] \|\| \[\]\)\.length > 1/.test(editores), 'variasEmp no lee empresasCat antes de declararla (var hoisted = undefined: reventaba el modal)');
  ok(/cargaTiposPropios\(aut\.sb\);/.test(datos), 'datos.js arranca la carga de nombres para los listados');
  ok(/cargaTiposPropios\(sb, true\)/.test(editores), 'el formulario de permisos pide los propios frescos');
  ok(/tiposCat\.push\(\[f\.slug,/.test(editores), 'suma los propios a las casillas');
  ok(/' — no disponible ahora'/.test(editores), 'lo que la persona ya tiene y no se ofrece se enseña marcado (guardar no se lo quita en silencio)');
  ok(/solo los puede conceder quien ya los tiene/.test(editores), 'avisa de la regla de la base (nadie concede lo que no tiene)');
  ok(/\(u\.empresas \|\| \[\]\)\.length \|\| u\.empresas\.indexOf\(f\.empresa\) !== -1/.test(editores), 'con empresas marcadas, solo los propios de esas empresas');
  // 4. el alta ofrece los propios (la edge los acepta desde el 13-oct) y no calla lo que la edge no dio
  const iAlta = editores.indexOf("var btnAlta = ata('invitar-miembro'");
  assert.ok(iAlta > 0, 'no encuentro el botón de alta');
  const btnAlta = editores.slice(iAlta, editores.indexOf("if (btnAlta && new URLSearchParams", iAlta));
  ok(/cargaTiposPropios\(sb, true\)/.test(btnAlta), 'el alta pide los propios frescos (un propio recién activado sale sin recargar)');
  ok(/ops\.push\(\[f\.slug,[^\n]*contrato propio/.test(btnAlta), 'el alta suma los propios a las casillas, marcados «contrato propio»');
  ok(/return conPropios\(\[\]\)/.test(btnAlta), 'si no se pueden leer, el alta se abre con los 17 (no se bloquea)');
  const guardaAlta = editores.slice(editores.indexOf("accion: 'crear', email: email"), editores.indexOf('history.replaceState(null', editores.indexOf("accion: 'crear', email: email")));
  ok(/d\.tipos_no_dados/.test(guardaAlta), 'tras crear, avisa de los tipos que la edge no dio (tipos_no_dados)');
  ok(!/se conceden después, en los permisos de la persona/.test(editores), 'el alta ya no dice que los propios se conceden después');

  console.log('OK propios_permisos.test.js — ' + n + ' comprobaciones');
})().catch(e => { console.error(e); process.exit(1); });
