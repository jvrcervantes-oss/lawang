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

  /* 5. `herramientas` viaja en el orden GUARDADO, no en el de la pantalla (14-oct-2026). El trigger
     usuarios_bloquea_cambio_rol_herramientas compara con `is distinct from` (cuenta el orden): a quien no es super admin
     solo le deja guardar nombre, proyectos o activo si la lista sale IDÉNTICA. Mover «Clientes» en MENU_V4 cambió el
     orden de las casillas y lo habría roto. Se ejecuta la función real de editores.js. */
  const iOrd = editores.indexOf('function ordenHerramientas(');
  assert.ok(iOrd > 0, 'no encuentro ordenHerramientas en editores.js');
  const cOrd = {};
  vm.createContext(cOrd);
  vm.runInContext(editores.slice(iOrd, editores.indexOf('function slugDe(', iOrd)), cOrd);
  const ord = (g, m, o) => vm.runInContext('ordenHerramientas', cOrd)(g, m, o);
  // las casillas como las da permisosPorMenu tras subir «Clientes»: secciones y filas sin casilla (objetos) entre los pares
  const menu = [{ seccion: 'Seguimiento' }, ['leads', 'CRM'], ['operaciones', 'Operaciones'], { seccion: 'Documentación' },
    ['compradores', 'Clientes'], ['contratos', 'Contratos'], ['asistente', 'Asistente'], { info: 'Resumen', nota: 'según rol' },
    ['facturas', 'Cobros · Facturas'], ['unidades', 'Proyectos'], ['modelos', 'Modelos de casas'], ['obra', 'Obra']];
  const enPantalla = marcadas => menu.filter(Array.isArray).map(o => o[0]).filter(k => marcadas.indexOf(k) !== -1);   // lo que recoge el modal
  const guardado = ['contratos', 'facturas', 'unidades', 'modelos', 'obra', 'compradores'];   // orden de antes: Clientes al final
  eq(enPantalla(guardado), ['compradores', 'contratos', 'facturas', 'unidades', 'modelos', 'obra'], 'el caso es real: la pantalla ya no recoge en el orden guardado');
  eq(ord(guardado, enPantalla(guardado), menu), guardado, 'sin tocar casillas, la lista sale idéntica a la guardada (mismo orden)');
  eq(ord(guardado, enPantalla(guardado.filter(k => k !== 'unidades')), menu), ['contratos', 'facturas', 'modelos', 'obra', 'compradores'], 'desmarcar una: el resto, en el orden guardado');
  eq(ord(guardado, enPantalla(guardado.concat(['leads', 'asistente'])), menu), guardado.concat(['leads', 'asistente']), 'marcar nuevas: al final, en el orden de la pantalla');
  eq(ord(['contratos', 'retirada', 'compradores'], ['compradores', 'contratos'], menu), ['contratos', 'retirada', 'compradores'], 'una clave guardada que la pantalla no ofrece viaja tal cual, en su sitio (no se ha podido desmarcar)');
  eq(ord(['contratos', 'retirada'], ['contratos'], menu.concat([['retirada', 'Otra']])), ['contratos'], 'si la pantalla SÍ la ofrece (en «Otras») y se desmarca, se quita');
  eq(ord(['contratos', 'retirada'], ['contratos', 'retirada'], menu.concat([['retirada', 'Otra']])), ['contratos', 'retirada'], '…y si sigue marcada, se conserva en su sitio');
  eq(ord(['contratos'], ['contratos'], menu).indexOf('retirada'), -1, 'no inventa claves que no están ni guardadas ni marcadas');
  eq(ord(null, ['compradores', 'contratos'], menu), ['compradores', 'contratos'], 'sin nada guardado (null): lo marcado, en el orden de la pantalla');
  eq(ord([], [], menu), [], 'vacío y nada marcado: vacío');
  eq(ord(guardado, [], menu), [], 'desmarcarlo todo lo quita todo (todas tenían casilla)');
  eq(ord(guardado, null, menu), [], 'sin lista de marcadas (null) no revienta');
  eq(ord(['contratos', 'compradores'], ['compradores', 'contratos', 'leads']), ['contratos', 'compradores', 'leads'], 'sin opciones: orden guardado y lo nuevo al final, sin conservar lo no ofrecido');
  eq(ord(['contratos', 'retirada'], ['contratos']), ['contratos'], 'sin opciones, lo que no viene marcado no viaja');
  eq(ord(['obra', 'contratos'], ['contratos', 'obra'], ['contratos', 'obra', 'leads']), ['obra', 'contratos'], 'las opciones también pueden ser strings (la rama sin catálogo, que ordena alfabéticamente)');
  eq(ord(['contratos'], ['leads', 'leads', 'contratos'], menu), ['contratos', 'leads'], 'una marcada repetida entra una vez');
  const una = ord(['contratos', 'retirada', 'compradores'], ['compradores', 'leads'], menu);
  eq(ord(['contratos', 'retirada', 'compradores'], una, menu), una, 'aplicarla sobre su propio resultado no cambia nada (el build de las instancias vuelve a ordenar encima)');
  // el cableado: se ordena ANTES de montar el patch, y la línea que el build de las instancias reescribe sigue tal cual y una sola vez
  const ANCLA_BUILD = '              nombre: v.nombre.trim() || null, herramientas: v.herramientas,\n';
  eq(editores.split(ANCLA_BUILD).length - 1, 1, 'la línea de `herramientas` del patch es un ancla de demo-erp/build.py (AxisWorks): tiene que aparecer exactamente una vez');
  const iPatch = editores.indexOf(ANCLA_BUILD), iAsigna = editores.indexOf('v.herramientas = ordenHerramientas(u.herramientas, v.herramientas, ops);');
  ok(iAsigna > 0 && iAsigna < iPatch && iPatch - iAsigna < 400, 'el modal de permisos ordena `v.herramientas` justo antes de montar el patch');
  eq(editores.split("sb.rpc('usuario_guarda_permisos'").length - 1, 1, 'solo un sitio guarda permisos: si aparece otro, tiene que ordenar igual');

  console.log('OK propios_permisos.test.js — ' + n + ' comprobaciones');
})().catch(e => { console.error(e); process.exit(1); });
