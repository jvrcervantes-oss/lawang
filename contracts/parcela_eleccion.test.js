/* ═══════════════════════════════════════════════════════════════════════════
   QUÉ PARCELA SE PUEDE COGER — 30-sep-2026 (F7, revisión de código)
   `node parcela_eleccion.test.js`. Lo corre `tools/test.py`, y con él el gate.
   ═══════════════════════════════════════════════════════════════════════════
   POR QUÉ EXISTE. El asistente de Nuevo contrato elige la parcela ANTES de que
   exista el formulario, y la primera versión llevaba su propia copia de la
   regla del traspaso: daba por buena, para un Bloqueo, una parcela reservada
   con la Carta de OTRO comprador, y el agente se enteraba al guardar (trigger
   traspaso_carta_estado). Desde este arreglo hay UNA regla —estadoTraspaso /
   eleccionParcela en assets/parcela_inventario.js— con un contexto opcional
   { tipo, ids } para quien pregunta sin formulario. Esto afirma:
     1. Sin contexto, la regla es la de siempre (tipo y compradores del formulario).
     2. Con contexto, decide por el tipo y el cliente contestados, no por la
        plantilla que haya detrás.
     3. La consulta a la base de una Carta ajena deja la respuesta en la unidad y
        la regla la lee con la clave del cliente que preguntó.
     4. El asistente no vuelve a llevar copia propia de la regla.
   ═══════════════════════════════════════════════════════════════════════════ */
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');

const fuente = fs.readFileSync(path.join(__dirname, 'assets', 'parcela_inventario.js'), 'utf8');
const ctx = {
  CONTRACT_TIPO: { carta_reserva: 'carta_reserva', ppjb_parcela: 'reserva_parcela', ppjb_construccion: 'construccion' },
  CURRENT: { slug: 'ppjb_parcela' },
  SAVED_CONTRACT: null,
  FORM: [],
  compradoresDelFormulario() { return { lista: ctx.FORM, fuera: 0 }; },
  sb: null,
  console,
};
vm.createContext(ctx);
vm.runInContext(fuente, ctx, { filename: 'parcela_inventario.js' });
const { estadoTraspaso, eleccionParcela, identificadoresDeFicha, consultarTraspasoRemoto } = ctx;

const carta = (pas, email) => ({ tipo: 'carta_reserva', numero: 'CR00902', adq1_pasaporte: pas, adq1_email: email, extras: [] });
const libre = { codigo: 'B-12', estado: 'disponible', contrato_id: null };
const marcada = { codigo: 'B-13', estado: 'bloqueada', contrato_id: null };
const deAnna = { codigo: 'B-11', estado: 'reservada', contrato_id: 'cr1', ocupante: carta('X123', 'anna@example.com') };
const deBloqueo = { codigo: 'P-07', estado: 'vendida', contrato_id: 'rp1', ocupante: { tipo: 'reserva_parcela', numero: 'RP00901' } };
const sinIds = { codigo: 'B-15', estado: 'reservada', contrato_id: 'cr2', ocupante: carta('', '') };
const anna = { passport_number: ' X123 ', email: 'Anna@Example.com' };
const tom = { passport_number: 'Y456', email: 'tom@example.com' };
let n = 0;
const ok = (t, cond) => { assert.ok(cond, t); n++; };

// 1 · sin contexto: la de siempre, con el formulario
ctx.FORM = [{ pasaporte: 'x123', email: '' }];
ok('formulario con el pasaporte de la Carta → ok', estadoTraspaso(deAnna) === 'ok');
ctx.FORM = [{ pasaporte: 'Y456', email: 'tom@example.com' }];
ok('formulario de otro comprador → otro', estadoTraspaso(deAnna) === 'otro');
ctx.FORM = [];
ok('formulario sin pasaporte ni email → sin_datos', estadoTraspaso(deAnna) === 'sin_datos');
ok('ocupada por un Bloqueo → no', estadoTraspaso(deBloqueo) === 'no');
ctx.CURRENT = { slug: 'carta_reserva' };
ok('una Carta no coge la parcela de otra Carta → no', estadoTraspaso(deAnna) === 'no');
ctx.CURRENT = { slug: 'ppjb_parcela' };

// 2 · con contexto: el tipo y el cliente del asistente, aunque detrás haya otra plantilla
ctx.CURRENT = { slug: 'carta_reserva' };   // la plantilla por defecto de detrás
ctx.FORM = [];
const bloqueo = f => ({ tipo: 'reserva_parcela', ids: identificadoresDeFicha(f) });
ok('ids de ficha: pasaporte y email, limpios', identificadoresDeFicha(anna).join('|') === 'x123|anna@example.com');
ok('Bloqueo para ANNA sobre su Carta → ok', estadoTraspaso(deAnna, bloqueo(anna)) === 'ok');
ok('Bloqueo para TOM sobre la Carta de ANNA → otro', estadoTraspaso(deAnna, bloqueo(tom)) === 'otro');
ok('Bloqueo sin cliente → sin_datos', estadoTraspaso(deAnna, bloqueo(null)) === 'sin_datos');
ok('Carta de ocupante sin identificadores → sin_datos', estadoTraspaso(sinIds, bloqueo(anna)) === 'sin_datos');
ok('Carta nueva sobre la Carta de ANNA → no', estadoTraspaso(deAnna, { tipo: 'carta_reserva', ids: identificadoresDeFicha(anna) }) === 'no');

const el = (u, f) => eleccionParcela(u, bloqueo(f));
ok('libre y disponible → se ofrece', !el(libre, anna).bloqueada && !el(libre, anna).tomada);
ok('marcada a mano sin contrato → bloqueada', el(marcada, anna).bloqueada);
ok('Carta de otro comprador → bloqueada (lo que se colaba)', el(deAnna, tom).bloqueada && el(deAnna, tom).modo === 'otro');
ok('Carta del mismo cliente → se ofrece', !el(deAnna, anna).bloqueada && el(deAnna, anna).modo === 'ok');
ok('ocupada por un Bloqueo → bloqueada', el(deBloqueo, anna).bloqueada);
ctx.SAVED_CONTRACT = { id: 'cr1' };
ok('con contexto ninguna unidad es «del contrato abierto»', el(deAnna, tom).tomada);
ok('sin contexto, la del contrato abierto no cuenta como tomada', !eleccionParcela(deAnna).tomada);
ctx.SAVED_CONTRACT = null;
ctx.CURRENT = { slug: 'ppjb_parcela' };

// 3 · Carta de otro agente: por_comprobar hasta que la base contesta, y con la clave de quien preguntó
(async () => {
  const oculta = () => ({ codigo: 'B-20', estado: 'reservada', contrato_id: 'ajeno', ocupante: null, ocupanteOculto: true });
  let u = oculta();
  ok('oculta sin preguntar → por_comprobar, y NO bloquea (se pregunta al elegirla)',
    el(u, anna).modo === 'por_comprobar' && !el(u, anna).bloqueada);
  let pedido = null;
  ctx.sb = { rpc: (nombre, args) => { pedido = { nombre, args }; return Promise.resolve({ data: { numero: 'CR00950', estado: args.p_ids.includes('x123') ? 'ok' : 'otro' }, error: null }); } };
  ok('la base dice ok para ANNA', await consultarTraspasoRemoto(u, 'PRB Village', identificadoresDeFicha(anna)) === 'ok');
  ok('pregunta por ESA parcela y ese proyecto', pedido.nombre === 'parcela_traspaso_estado' && pedido.args.p_codigo === 'B-20' && pedido.args.p_proyecto === 'PRB Village');
  ok('oculta comprobada para ANNA → se ofrece', el(u, anna).modo === 'ok' && !el(u, anna).bloqueada);
  ok('la misma respuesta no vale para TOM → por_comprobar otra vez', el(u, tom).modo === 'por_comprobar');
  u = oculta();
  await consultarTraspasoRemoto(u, 'PRB Village', identificadoresDeFicha(tom));
  ok('oculta de otro comprador → bloqueada con motivo «otro»', el(u, tom).modo === 'otro' && el(u, tom).bloqueada);
  u = oculta();
  ctx.sb = { rpc: () => Promise.resolve({ data: null, error: null }) };
  ok('sin Carta detrás → no', await consultarTraspasoRemoto(u, 'PRB Village', ['x']) === 'no');
  ok('…y queda bloqueada como «ya asignada»', el(u, anna).bloqueada && el(u, anna).modo === 'no');
  u = oculta();
  ctx.sb = { rpc: () => Promise.resolve({ data: null, error: { message: 'red' } }) };
  let lanzo = false;
  try { await consultarTraspasoRemoto(u, 'PRB Village', ['x']); } catch (_) { lanzo = true; }
  ok('si la base no contesta LANZA (no se confunde con «de otro comprador»)', lanzo && el(u, anna).modo === 'por_comprobar');

  // 4 · el asistente usa la regla compartida y no lleva copia
  const asi = fs.readFileSync(path.join(__dirname, 'assets', 'asistente-contrato.js'), 'utf8');
  ok('el asistente decide con eleccionParcela', /eleccionParcela\(u, ctxParcela\(\)\)/.test(asi));
  ok('el asistente no lleva copia de TIPOS_CEDEN_PARCELA', !/TIPOS_CEDEN_PARCELA/.test(asi));
  ok('el asistente cierra con la regla del editor antes de escribir la parcela', /comprobarTraspasoRemoto\(u\)/.test(asi));
  console.log('parcela_eleccion.test.js: ' + n + ' comprobaciones en verde');
})().catch(e => { console.error('FALLA ' + e.message); process.exit(1); });
