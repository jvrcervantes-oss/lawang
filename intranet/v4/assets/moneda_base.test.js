// Moneda base del ERP en las cifras de cobro y prefijo confirmado al guardar una sociedad (F3 fase E, 12-oct-2026):
// node moneda_base.test.js
//
// ARNÉS: se ejecuta el código de verdad (trozos de guard.js, datos.js y editores.js) con una base y un diálogo de mentira.
//  A) lwMonedaBase (guard.js): Lawang → 'EUR' siempre; instancia → la moneda de Ajustes o null (nunca EUR por defecto).
//  B) sumaMesBase (datos.js): con EUR suma igual que la función de antes (sumaMesEUR, copiada abajo tal cual); con null no suma.
//  C) conMonedaBase (datos.js): Lawang → en el acto y con 'EUR'; instancia → ESPERA a AXW_MODULOS_LISTOS (la moneda llega tarde);
//     «sin decidir» (se leyó y no hay) y «no se pudo leer» (la comprobación falló) salen distintos.
//  D) guardaSociedad (editores.js): sin el hint falta_confirmo la llamada es UNA y con los mismos argumentos (Lawang); con el hint
//     pregunta en lwConfirmar y reenvía con p_confirmo; cancelar no vuelve a llamar; sin diálogo cargado no se guarda; todo escapado.
// Y se MUTA el código: cada mutación tiene que romper al menos una comprobación, o el test no vale.
const fs = require('fs'), assert = require('assert'), vm = require('vm');
const guard = fs.readFileSync(__dirname + '/../../../contracts/assets/guard.js', 'utf8');
const datos = fs.readFileSync(__dirname + '/datos.js', 'utf8');
const editores = fs.readFileSync(__dirname + '/editores.js', 'utf8');
const espera = (ms) => new Promise((r) => setTimeout(r, ms || 15));

function trozo(src, ini, fin, que) {
  const a = src.indexOf(ini), b = src.indexOf(fin, a + 1);
  assert.ok(a > 0 && b > a, 'no encuentro ' + que);
  return src.slice(a, b);
}
const fGuard = trozo(guard, "  fija('lwMonedaBase',", "  fija('lwEdge',", 'lwMonedaBase en guard.js');
const fSuma = trozo(datos, '  var mesIni = new Date();', '  /* ══════════════ registro por pantalla', 'sumaMesBase/conMonedaBase en datos.js');
const fEspera = trozo(datos, '  function esperaModulos() {', '  /* Lo CONTRACTUAL de la pantalla Clientes', 'esperaModulos en datos.js');
const fSoc = trozo(editores, '      function guardaSociedad(args) {', '      // ── Editar una sociedad que ya existe', 'guardaSociedad en editores.js');

// la función de antes, tal cual estaba en producción hasta hoy (referencia de «con EUR, igual que siempre»)
function sumaMesEURAntes(recibis, mesIni) {
  var eur = 0, otros = 0;
  (recibis || []).forEach(function (f) {
    if (f.anulada) return;
    if (new Date(f.fecha_emision || f.created_at) < mesIni) return;
    if ((f.moneda || 'EUR') === 'EUR') eur += Number(f.total) || 0; else otros++;
  });
  return { eur: eur, otros: otros };
}

function mundoDatos(win, fuenteSuma, fuenteEspera) {
  const ctx = { window: win };
  vm.createContext(ctx);
  vm.runInContext('(function(){' + fuenteSuma + '\n' + fuenteEspera + '\nwindow._t = { sumaMesBase: sumaMesBase, conMonedaBase: conMonedaBase, mesIni: mesIni, SIN_MONEDA: SIN_MONEDA, SIN_LEER_MONEDA: SIN_LEER_MONEDA };})()', ctx);
  return win._t;
}
function guardDe(win, fuenteGuard) {
  const ctx = { window: win, fija: (k, v) => { win[k] = v; } };
  vm.createContext(ctx);
  vm.runInContext(fuenteGuard, ctx);
  return win;
}

function mundoSoc(opts, fuenteSoc) {
  const llamadas = [], dialogos = [];
  const sb = { rpc: (n, a) => { llamadas.push([n, JSON.parse(JSON.stringify(a))]); return Promise.resolve(opts.respuestas.shift() || { data: true, error: null }); } };
  const ctx = {
    sb, Promise, Object, String,
    tH: (s, h) => { var v = String(s); for (var k in (h || {})) v = v.split('%' + k).join(h[k]); return v; },
    esc: (v) => String(v).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'),
    window: {}
  };
  if (opts.dialogo !== false) ctx.lwConfirmar = (o) => { dialogos.push(o); return Promise.resolve(opts.confirma); };
  if (opts.confirmNativo) ctx.window.confirm = () => { dialogos.push('nativo'); return true; };
  vm.createContext(ctx);
  vm.runInContext(fuenteSoc + '\nthis._g = guardaSociedad;', ctx);
  return { g: ctx._g, llamadas, dialogos };
}

async function escenarios(F) {
  const fallos = [];
  const comprueba = (c, m) => { if (!c) fallos.push(m); };

  // ── A) lwMonedaBase
  comprueba(guardDe({}, F.guard).lwMonedaBase() === 'EUR', 'A: Lawang (sin bandera ni moneda) → EUR');
  comprueba(guardDe({ AXW_NUCLEO_OPERACION: true }, F.guard).lwMonedaBase() === null, 'A: instancia sin moneda → null, nunca EUR');
  comprueba(guardDe({ AXW_NUCLEO_OPERACION: true, LW_MONEDA_BASE: 'IDR' }, F.guard).lwMonedaBase() === 'IDR', 'A: instancia con IDR → IDR');
  comprueba(guardDe({ AXW_NUCLEO_OPERACION: true, LW_MONEDA_BASE: 'idr' }, F.guard).lwMonedaBase() === null, 'A: instancia con código raro → null');

  // ── B) sumaMesBase vs la de antes
  const tL = mundoDatos({}, F.suma, F.espera);
  const hoy = new Date(), mesPasado = new Date(hoy.getFullYear(), hoy.getMonth() - 1, 15);
  const rs = [
    { total: 100, moneda: 'EUR', fecha_emision: hoy.toISOString() },
    { total: '50.5', fecha_emision: hoy.toISOString() },
    { total: 70, moneda: 'IDR', fecha_emision: hoy.toISOString() },
    { total: 999, moneda: 'EUR', anulada: true, fecha_emision: hoy.toISOString() },
    { total: 30, moneda: 'EUR', fecha_emision: mesPasado.toISOString() },
    { total: 5, created_at: hoy.toISOString() }
  ];
  const antes = sumaMesEURAntes(rs, tL.mesIni), ahora = tL.sumaMesBase(rs, 'EUR');
  comprueba(ahora.suma === antes.eur && ahora.otros === antes.otros, 'B: con EUR suma igual que antes (' + JSON.stringify(ahora) + ' vs ' + JSON.stringify(antes) + ')');
  const idr = tL.sumaMesBase(rs, 'IDR');
  comprueba(idr.suma === 70 + 50.5 + 5 && idr.otros === 1, 'B: con IDR suma lo de IDR y lo sin moneda (' + JSON.stringify(idr) + ')');
  const nulo = tL.sumaMesBase(rs, null);
  comprueba(nulo.suma === 0 && nulo.otros === 0, 'B: sin moneda no suma nada');

  // ── C) conMonedaBase
  // Lawang: en el acto (síncrono) y con EUR, sin motivo
  let r = null;
  mundoDatos({ lwMonedaBase: guardDe({}, F.guard).lwMonedaBase }, F.suma, F.espera).conMonedaBase((b, m) => { r = [b, m]; });
  comprueba(r && r[0] === 'EUR' && r[1] === '', 'C: Lawang → en el acto con EUR (' + JSON.stringify(r) + ')');
  // instancia: la moneda llega TARDE (la capa la fija justo antes de resolver la promesa)
  {
    const w = { AXW_NUCLEO_OPERACION: true };
    guardDe(w, F.guard);
    let suelta; w.AXW_MODULOS_LISTOS = new Promise((res) => { suelta = res; });
    const t = mundoDatos(w, F.suma, F.espera);
    let got = null; t.conMonedaBase((b, m) => { got = [b, m]; });
    comprueba(got === null, 'C: instancia → no pinta antes de saber la moneda');
    await espera(); w.LW_MONEDA_BASE = 'IDR'; suelta(true); await espera();
    comprueba(got && got[0] === 'IDR' && got[1] === '', 'C: instancia con la moneda tarde → IDR (' + JSON.stringify(got) + ')');
  }
  // instancia: se leyó y no hay moneda → «sin decidir»
  {
    const w = { AXW_NUCLEO_OPERACION: true, AXW_MODULOS_LISTOS: Promise.resolve(true) };
    guardDe(w, F.guard);
    const t = mundoDatos(w, F.suma, F.espera);
    let got = null; t.conMonedaBase((b, m) => { got = [b, m]; }); await espera();
    comprueba(got && got[0] === null && got[1] === t.SIN_MONEDA, 'C: leída y sin moneda → «sin decidir» (' + JSON.stringify(got) + ')');
  }
  // instancia: la comprobación falló → «no se pudo leer», aunque hubiera una moneda vieja colgada
  {
    const w = { AXW_NUCLEO_OPERACION: true, LW_MONEDA_BASE: 'IDR', AXW_MODULOS_LISTOS: Promise.resolve(false) };
    guardDe(w, F.guard);
    const t = mundoDatos(w, F.suma, F.espera);
    let got = null; t.conMonedaBase((b, m) => { got = [b, m]; }); await espera();
    comprueba(got && got[0] === null && got[1] === t.SIN_LEER_MONEDA, 'C: fallo al leer → «no se pudo leer» (' + JSON.stringify(got) + ')');
    comprueba(t.SIN_LEER_MONEDA !== t.SIN_MONEDA, 'C: los dos motivos son textos distintos');
  }

  // ── D) guardaSociedad
  const args = { p_clave: 'pt_x', p_datos: { razon_social: 'PT X', prefijo_serie: 'BBM' }, p_nueva: false };
  {
    // Lawang: la base no devuelve el hint → una sola llamada, mismos argumentos, sin p_confirmo, sin diálogo
    const m = mundoSoc({ respuestas: [{ data: { ok: true }, error: null }], confirma: true, confirmNativo: true }, F.soc);
    const out = await m.g(JSON.parse(JSON.stringify(args)));
    comprueba(m.llamadas.length === 1 && JSON.stringify(m.llamadas[0]) === JSON.stringify(['sociedad_guarda', args]), 'D: sin hint → UNA llamada con los mismos argumentos (' + JSON.stringify(m.llamadas) + ')');
    comprueba(m.dialogos.length === 0, 'D: sin hint → no se pregunta nada');
    comprueba(out && out.data && out.data.ok === true, 'D: sin hint → devuelve la respuesta tal cual');
    // un error normal de la base (no el hint) también pasa tal cual y sin reintento
    const m2 = mundoSoc({ respuestas: [{ data: null, error: { message: 'x', hint: 'otro' } }], confirma: true }, F.soc);
    const o2 = await m2.g(JSON.parse(JSON.stringify(args)));
    comprueba(m2.llamadas.length === 1 && o2.error.hint === 'otro', 'D: otro error → tal cual, sin reintento');
  }
  {
    // hint + confirma → reenvía con p_confirmo = true y el resto igual
    const m = mundoSoc({ respuestas: [{ data: null, error: { message: 'falta', hint: 'falta_confirmo' } }, { data: { ok: 1 }, error: null }], confirma: true, confirmNativo: true }, F.soc);
    const out = await m.g(JSON.parse(JSON.stringify(args)));
    comprueba(m.llamadas.length === 2, 'D: hint + sí → segunda llamada');
    comprueba(m.llamadas[1] && JSON.stringify(m.llamadas[1][1]) === JSON.stringify(Object.assign({}, args, { p_confirmo: true })), 'D: la segunda lleva p_confirmo y el resto igual');
    comprueba(m.dialogos.length === 1 && m.dialogos[0] !== 'nativo', 'D: se pregunta en lwConfirmar, nunca en window.confirm');
    comprueba(out && out.data && out.data.ok === 1, 'D: devuelve la respuesta del reenvío');
  }
  {
    // hint + cancela → no vuelve a llamar, error propio
    const m = mundoSoc({ respuestas: [{ data: null, error: { hint: 'falta_confirmo' } }], confirma: false }, F.soc);
    const out = await m.g(JSON.parse(JSON.stringify(args)));
    comprueba(m.llamadas.length === 1, 'D: cancelar no vuelve a llamar');
    comprueba(out && out.error && /No se ha guardado nada/.test(out.error.message), 'D: cancelar → «No se ha guardado nada»');
  }
  {
    // hint sin diálogo cargado → no se guarda y no se cae a window.confirm
    const m = mundoSoc({ respuestas: [{ data: null, error: { hint: 'falta_confirmo' } }], dialogo: false, confirmNativo: true }, F.soc);
    const out = await m.g(JSON.parse(JSON.stringify(args)));
    comprueba(m.llamadas.length === 1 && m.dialogos.length === 0 && out.error, 'D: sin diálogo → no se guarda ni se usa el nativo');
  }
  {
    // el prefijo entra escapado; vaciarlo lleva su propio texto
    const a2 = { p_clave: 'pt_x', p_datos: { prefijo_serie: '<b>X</b>' }, p_nueva: true };
    const m = mundoSoc({ respuestas: [{ data: null, error: { hint: 'falta_confirmo' } }], confirma: false }, F.soc);
    await m.g(a2);
    comprueba(m.dialogos[0] && m.dialogos[0].cuerpo.indexOf('<b>X') < 0 && m.dialogos[0].cuerpo.indexOf('&lt;b&gt;X') >= 0, 'D: el prefijo va escapado');
    const m3 = mundoSoc({ respuestas: [{ data: null, error: { hint: 'falta_confirmo' } }], confirma: false }, F.soc);
    await m3.g({ p_clave: 'pt_x', p_datos: { prefijo_serie: '' }, p_nueva: false });
    comprueba(m3.dialogos[0] && /sin prefijo/.test(m3.dialogos[0].cuerpo) && !/«»/.test(m3.dialogos[0].cuerpo), 'D: vaciar el prefijo lleva su propio texto');
  }
  return fallos;
}

(async function () {
  const F = { guard: fGuard, suma: fSuma, espera: fEspera, soc: fSoc };
  const fallos = await escenarios(F);
  assert.deepStrictEqual(fallos, [], 'fallos con el código real:\n  ' + fallos.join('\n  '));

  // mutaciones: cada una tiene que romper al menos una comprobación
  const muta = [
    ['conMonedaBase no espera a la capa', 'suma', '    var espera = esperaModulos();\n    if (!espera)', '    var espera = null;\n    if (!espera)'],
    ['«no se pudo leer» = «sin decidir»', 'suma', '(ok ? SIN_MONEDA : SIN_LEER_MONEDA)', 'SIN_MONEDA'],
    ['sumaMesBase suma sin moneda', 'suma', "    if (!base) return { suma: 0, otros: 0 };", ''],
    ['instancia con EUR por defecto', 'guard', ": null;\n    return m || 'EUR';", ": 'EUR';\n    return m || 'EUR';"],
    ['siempre p_confirmo', 'soc', "Promise.resolve(sb.rpc('sociedad_guarda', args))", "Promise.resolve(sb.rpc('sociedad_guarda', Object.assign({}, args, { p_confirmo: true })))"],
    ['reenvía aunque se cancele', 'soc', 'if (!ok) return nada;', ''],
    ['sin escapar', 'soc', "'<p>' + esc(cuerpo) + '</p>'", "'<p>' + cuerpo + '</p>'"]
  ];
  for (const [nombre, k, de, a] of muta) {
    assert.ok(F[k].indexOf(de) >= 0, 'mutación «' + nombre + '»: no encuentro el texto a mutar');
    const F2 = Object.assign({}, F); F2[k] = F[k].split(de).join(a);
    let f2;
    try { f2 = await escenarios(F2); } catch (e) { f2 = ['excepción: ' + e.message]; }
    assert.ok(f2.length > 0, 'la mutación «' + nombre + '» no rompe ninguna comprobación: el test no la caza');
  }
  console.log('moneda_base.test.js: OK (' + muta.length + ' mutaciones cazadas)');
})().catch((e) => { console.error(e.message || e); process.exit(1); });
