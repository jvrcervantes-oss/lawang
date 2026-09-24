/* node contracts/finanzas.test.js — el cálculo del dashboard financiero.
   Los casos son los hallazgos de la revisión previa #62 (24-sep-2026) y las
   reglas de dinero que la suite ya pagó por aprender; cada uno dice cuál. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const RAIZ = path.join(__dirname, '..');

// mismas globales que carga la página, en el mismo orden
global.lwParseImporte = require(path.join(RAIZ, 'contracts', 'assets', 'dinero.js')).lwParseImporte;
const voc = fs.readFileSync(path.join(RAIZ, 'contracts', 'assets', 'vocabulario.js'), 'utf8');
new Function(voc + '; globalThis.lwEsPreliminar = lwEsPreliminar;')();
// entities.js: el resolver de sociedad (lwSociedadContrato) que usa el filtro por empresa
const ent = fs.readFileSync(path.join(RAIZ, 'contracts', 'assets', 'entities.js'), 'utf8');
new Function(ent + '; globalThis.lwSociedadContrato = lwSociedadContrato;')();
const L = require(path.join(RAIZ, 'intranet', 'vencimientos', 'logica.js'));
Object.assign(global, L);
const F = require(path.join(RAIZ, 'contracts', 'assets', 'finanzas.js'));

const HOY = '2026-09-24';
let n = 0;
const caso = (nombre, fn) => { fn(); n++; };

caso('cobros: solo recibís vivos, por moneda, sin mezclar EUR con IDR', () => {
  const c = F.finCobros([
    { total: 1000, moneda: 'EUR', fecha: '2026-09-02', sociedad: 'a' },
    { total: 500,  moneda: 'EUR', fecha: '2026-09-10', anulada: true },
    { total: 2e9,  moneda: 'IDR', fecha: '2026-09-11' },
    { total: 300,  moneda: 'EUR', fecha: '2026-08-31', sociedad: 'b' },
  ], HOY);
  assert.strictEqual(c.EUR.mes, 1000);
  assert.strictEqual(c.EUR.mesAnterior, 300);
  assert.strictEqual(c.EUR.anio, 1300);
  assert.strictEqual(c.IDR.mes, 2e9);
  assert.deepStrictEqual(c.EUR.porSociedadAnio, { a: 1000, b: 300 });
});

caso('cobros: el año anterior compara el MISMO tramo, no el año entero', () => {
  const c = F.finCobros([
    { total: 100, moneda: 'EUR', fecha: '2025-03-01' },
    { total: 900, moneda: 'EUR', fecha: '2025-12-01' },   // después del 24-sep: fuera
  ], HOY);
  assert.strictEqual(c.EUR.anioAnteriorMismoTramo, 100);
});

caso('facturado sin cobrar: solo facturas (ni proforma ni recibí), por su pendiente, y cuenta el criterio de antigüedad', () => {
  const f = F.finFacturadoSinCobrar([
    { tipo: 'factura',  moneda: 'EUR', pendiente: 1000, venc: '2026-09-30', fecha_emision: '2026-09-01' }, // al día
    { tipo: 'factura',  moneda: 'EUR', pendiente: 400,  venc: null,         fecha_emision: '2026-08-10' }, // 45 d por emisión
    { tipo: 'factura',  moneda: 'EUR', pendiente: 0,    venc: null,         fecha_emision: '2026-01-01' }, // saldada
    { tipo: 'proforma', moneda: 'EUR', pendiente: 9999, fecha_emision: '2026-01-01' },
    { tipo: 'recibi',   moneda: 'EUR', pendiente: 9999, fecha_emision: '2026-01-01' },
    { tipo: 'factura',  moneda: 'EUR', pendiente: 50,   anulada: true, fecha_emision: '2026-01-01' },
  ], HOY);
  assert.strictEqual(f.EUR.total, 1400);
  assert.strictEqual(f.EUR.n, 2);
  assert.strictEqual(f.EUR.porVencimiento, 1);
  assert.strictEqual(f.EUR.porEmision, 1);
  assert.strictEqual(f.EUR.tramos.find(t => t.clave === 'al_dia').importe, 1000);
  assert.strictEqual(f.EUR.tramos.find(t => t.clave === 'd60').importe, 400);
});

caso('salidas: una comisión que ya tiene solicitud NO se cuenta dos veces (#62)', () => {
  const s = F.finSalidas(
    [{ estado: 'pendiente', importe: 5000, moneda: 'EUR' }, { estado: 'anulada', importe: 99, moneda: 'EUR' }],
    [{ estado: 'pendiente', importe: 5000, moneda: 'EUR', solicitud_id: 'x' },
     { estado: 'pendiente', importe: 1000, importe_ajustado: 800, moneda: 'EUR', solicitud_id: null },
     { estado: 'pagada',    importe: 7000, moneda: 'EUR', solicitud_id: null }]);
  assert.strictEqual(s.EUR.solicitudes.importe, 5000);
  assert.strictEqual(s.EUR.comisiones.importe, 800);   // manda el importe ajustado
  assert.strictEqual(s.EUR.total, 5800);
});

caso('salidas sin permiso = null, nunca 0 (#62, Datos)', () => {
  const m = F.finModelo({ hoyISO: HOY, contratos: [], recibis: [], facturas: [], unidades: [], vencimientos: [], cobradoPorId: {}, solicitudes: null, comisiones: null });
  assert.strictEqual(Object.keys(m.porMoneda).length, 0);
  const m2 = F.finModelo({ hoyISO: HOY, contratos: [], recibis: [{ total: 1, moneda: 'EUR', fecha: HOY }], facturas: [], unidades: [], vencimientos: [], cobradoPorId: {}, solicitudes: null, comisiones: null });
  assert.strictEqual(m2.porMoneda.EUR.salidas, null);
});

caso('stock: valor por estado y disponible por proyecto; sin precio se cuenta aparte', () => {
  const s = F.finStock([
    { proyecto: 'P1', estado: 'disponible', precio: 100, moneda: 'EUR' },
    { proyecto: 'P1', estado: 'disponible', precio: null, moneda: 'EUR' },
    { proyecto: 'P2', estado: 'vendida',    precio: 300, moneda: 'EUR' },
  ]);
  assert.deepStrictEqual(s.EUR.estados.disponible, { n: 2, valor: 100 });
  assert.strictEqual(s.EUR.sinPrecio, 1);
  assert.deepStrictEqual(s.EUR.porProyecto.P1, { n: 2, valor: 100 });
});

/* Una operación típica: Bloqueo firmado de 100.000 con dos hitos (50 % ya
   vencido, 50 % en 60 días) y 30.000 cobrados. La cascada cubre primero el
   vencido: quedan 20.000 vencidos y 50.000 a 31-90 días. */
const bloqueo = { id: 'b1', tipo: 'reserva_parcela', numero: 'B1', proyecto_nombre: 'P1', comprador_nombre: 'X', precio_total: 100000, moneda: 'EUR', bloqueado: true, contrato_padre_id: null };
const hitosB = [
  { id: 'h1', contrato_id: 'b1', orden: 1, pct: 50, monto: null, fecha: '2026-09-01' },
  { id: 'h2', contrato_id: 'b1', orden: 2, pct: 50, monto: null, fecha: '2026-11-20' },
];

caso('cartera: el desglose SUMA el pendiente y cuadra', () => {
  const c = F.finCartera({ hoyISO: HOY, contratos: [bloqueo], cobradoPorId: { b1: 30000 }, vencimientos: hitosB }).EUR;
  assert.strictEqual(c.cartera, 100000);
  assert.strictEqual(c.pendiente, 70000);
  assert.strictEqual(c.desglose.vencido, 20000);
  assert.strictEqual(c.desglose.d31a90, 50000);
  assert.strictEqual(c.desglose.resto, 0);
  assert.ok(c.desglose.cuadra);
  const d = c.desglose;
  assert.strictEqual(d.vencido + d.d30 + d.d31a90 + d.mas90 + d.sinFecha + d.resto, c.pendiente);
});

caso('cartera: la Carta de Reserva no suma precio pero su cobrado sí se descuenta (328.000 € por una villa de 164.000)', () => {
  const carta = { id: 'c1', tipo: 'carta_reserva', numero: 'C1', proyecto_nombre: 'P1', precio_total: 100000, moneda: 'EUR', bloqueado: true, contrato_padre_id: 'b1' };
  const c = F.finCartera({ hoyISO: HOY, contratos: [bloqueo, carta], cobradoPorId: { b1: 20000, c1: 10000 }, vencimientos: hitosB }).EUR;
  assert.strictEqual(c.cartera, 100000);
  assert.strictEqual(c.cobrado, 30000);
  assert.strictEqual(c.pendiente, 70000);
});

caso('cartera: un contrato LIBERADO no es cartera, pero se cuenta aparte', () => {
  const lib = { ...bloqueo, id: 'b2', liberado_en: '2026-09-10T00:00:00Z' };
  const c = F.finCartera({ hoyISO: HOY, contratos: [bloqueo, lib], cobradoPorId: { b1: 30000 }, vencimientos: hitosB }).EUR;
  assert.strictEqual(c.cartera, 100000);
  assert.deepStrictEqual(c.liberadas, { n: 1, precio: 100000 });
});

caso('cartera: sin firmar va a «fuera», no a la cartera', () => {
  const borr = { ...bloqueo, id: 'b3', bloqueado: false };
  const c = F.finCartera({ hoyISO: HOY, contratos: [bloqueo, borr], cobradoPorId: { b1: 30000 }, vencimientos: hitosB }).EUR;
  assert.strictEqual(c.cartera, 100000);
  assert.strictEqual(c.fuera.sinFirmar, 1);
});

caso('cartera: un contrato sin calendario va a «resto», no desaparece', () => {
  const sinCal = { ...bloqueo, id: 'b4' };
  const c = F.finCartera({ hoyISO: HOY, contratos: [sinCal], cobradoPorId: {}, vencimientos: [] }).EUR;
  assert.strictEqual(c.desglose.resto, 100000);
  assert.ok(c.desglose.cuadra);
});

caso('cartera: hitos que prometen más de lo que se debe → no cuadra y lo dice', () => {
  const h = [{ id: 'x', contrato_id: 'b1', orden: 1, monto: 150000, pct: null, fecha: '2026-12-01' }];
  const c = F.finCartera({ hoyISO: HOY, contratos: [bloqueo], cobradoPorId: {}, vencimientos: h }).EUR;
  assert.strictEqual(c.desglose.cuadra, false);
  assert.strictEqual(c.desglose.exceso, 50000);
});

caso('serie de caja: 12 meses atrás + mes en curso + 6 adelante; previsto = pendiente, no bruto', () => {
  const m = F.finModelo({ hoyISO: HOY, contratos: [bloqueo], cobradoPorId: { b1: 30000 }, vencimientos: hitosB,
    recibis: [{ total: 30000, moneda: 'EUR', fecha: '2026-09-05' }], facturas: [], unidades: [], solicitudes: [], comisiones: [] });
  const s = F.finSerieCaja(m.porMoneda.EUR, HOY, 12, 6);
  assert.strictEqual(s.length, 19);
  const hoy = s.find(x => x.esHoy);
  assert.strictEqual(hoy.cobrado, 30000);
  assert.strictEqual(s.find(x => x.mes === '2026-11').previsto, 50000);
  assert.strictEqual(s.find(x => x.mes === '2026-11').cobrado, null);
});

caso('por proyecto: un proyecto con stock y sin ventas SALE (Regla 0 bis)', () => {
  const m = F.finModelo({ hoyISO: HOY, contratos: [bloqueo], cobradoPorId: { b1: 30000 }, vencimientos: hitosB, recibis: [], facturas: [], solicitudes: [], comisiones: [],
    unidades: [{ proyecto: 'P9', estado: 'disponible', precio: 500, moneda: 'EUR' }] });
  const nombres = m.porMoneda.EUR.porProyecto.map(p => p.proyecto);
  assert.deepStrictEqual(nombres.sort(), ['P1', 'P9']);
  const p1 = m.porMoneda.EUR.porProyecto.find(p => p.proyecto === 'P1');
  assert.strictEqual(p1.pctCobrado, 30);
});

caso('monedas: EUR primero; IDR nunca se suma con EUR', () => {
  const idr = { ...bloqueo, id: 'i1', moneda: 'IDR', precio_total: 2e9 };
  const m = F.finModelo({ hoyISO: HOY, contratos: [bloqueo, idr], cobradoPorId: {}, vencimientos: [], recibis: [], facturas: [], unidades: [], solicitudes: [], comisiones: [] });
  assert.deepStrictEqual(m.monedas, ['EUR', 'IDR']);
  assert.strictEqual(m.porMoneda.EUR.cartera.cartera, 100000);
  assert.strictEqual(m.porMoneda.IDR.cartera.cartera, 2e9);
});

caso('un importe que ya es número NO pasa por lwParseImporte: 8176.625 no son 8 millones (arnés, 24-sep)', () => {
  const s = F.finSalidas([], [{ estado: 'pendiente', importe: 8176.625, moneda: 'EUR', solicitud_id: null }]);
  assert.strictEqual(s.EUR.comisiones.importe, 8176.63);
});

caso('facturado sin cobrar: separa lo de contratos sin firmar', () => {
  const f = F.finFacturadoSinCobrar([
    { tipo: 'factura', moneda: 'EUR', pendiente: 100, fecha_emision: '2026-09-01', contrato_firmado: true },
    { tipo: 'factura', moneda: 'EUR', pendiente: 300, fecha_emision: '2026-09-01', contrato_firmado: false },
    { tipo: 'factura', moneda: 'EUR', pendiente: 50,  fecha_emision: '2026-09-01', contrato_firmado: null },
  ], HOY);
  assert.strictEqual(f.EUR.total, 450);
  assert.strictEqual(f.EUR.deSinFirmar, 300);
});

caso('% cobrado de lo firmado usa SOLO lo cobrado de lo firmado (salía 122,9 %)', () => {
  const borr = { ...bloqueo, id: 'b5', bloqueado: false };
  const c = F.finCartera({ hoyISO: HOY, contratos: [bloqueo, borr], cobradoPorId: { b1: 30000, b5: 90000 }, vencimientos: hitosB }).EUR;
  assert.strictEqual(c.cobrado, 120000);        // caja real, incluye el borrador
  assert.strictEqual(c.cobradoFirmado, 30000);  // lo que cuenta contra lo firmado
});

caso('quién debe: solo quien debe, lo vencido primero, un comprador con dos contratos sale una vez', () => {
  const b2 = { ...bloqueo, id: 'b6', comprador_nombre: 'Y', precio_total: 50000 };
  const b3 = { ...bloqueo, id: 'b7', comprador_nombre: 'X', precio_total: 10000 };
  const b4 = { ...bloqueo, id: 'b8', comprador_nombre: 'Z', precio_total: 1000 };
  const h2 = [{ id: 'y1', contrato_id: 'b6', orden: 1, pct: 100, monto: null, fecha: '2027-01-01' }];
  const m = F.finModelo({ hoyISO: HOY, contratos: [bloqueo, b2, b3, b4], cobradoPorId: { b1: 30000, b8: 1000 }, vencimientos: hitosB.concat(h2),
    recibis: [], facturas: [], unidades: [], solicitudes: [], comisiones: [] });
  const per = m.porMoneda.EUR.porProyecto.find(p => p.proyecto === 'P1').personas;
  assert.deepStrictEqual(per.map(p => p.nombre), ['X', 'Y']);        // Z ya pagó todo: no sale
  assert.strictEqual(per[0].pendiente, 80000);                      // X: 70.000 + 10.000, sumado
  assert.strictEqual(per[0].vencido, 20000);
  assert.strictEqual(per[1].vencido, 0);
});

caso('filtro por sociedad: la suma de las sociedades ES «Todas», y la Carta sigue a su Bloqueo', () => {
  const a = { ...bloqueo, id: 's1', soc: 'tepi_sungai', proyecto_nombre: 'PA' };
  const b = { ...bloqueo, id: 's2', soc: 'san_dal_woods', proyecto_nombre: 'PB', precio_total: 40000 };
  const carta = { id: 's3', tipo: 'carta_reserva', precio_total: 40000, moneda: 'EUR', bloqueado: true, contrato_padre_id: 's2', soc: 'tepi_sungai', proyecto_nombre: 'PB' };
  const e = { hoyISO: HOY, contratos: [a, b, carta], cobradoPorId: { s1: 1000, s2: 2000, s3: 500 }, vencimientos: [],
    recibis: [{ total: 1000, moneda: 'EUR', fecha: HOY, sociedad: 'tepi_sungai', tipo: 'recibi' }, { total: 2500, moneda: 'EUR', fecha: HOY, sociedad: 'san_dal_woods', tipo: 'recibi' }],
    facturas: [], unidades: [{ proyecto: 'PA', estado: 'disponible', precio: 1, moneda: 'EUR' }], solicitudes: [], comisiones: [] };
  const todas = F.finModelo(e).porMoneda.EUR;
  const t = F.finModelo(F.finFiltraEmpresa(e, 'tepi_sungai')).porMoneda.EUR;
  const s = F.finModelo(F.finFiltraEmpresa(e, 'san_dal_woods')).porMoneda.EUR;
  assert.strictEqual(t.cartera.cartera + s.cartera.cartera, todas.cartera.cartera);
  assert.strictEqual(t.cartera.cobrado + s.cartera.cobrado, todas.cartera.cobrado);
  assert.strictEqual(s.cartera.cobrado, 2500);                      // el de la Carta cuenta en SU Bloqueo
  assert.strictEqual(t.cobros.mes + s.cobros.mes, todas.cobros.mes);
  assert.strictEqual(t.stock, null);                                // el stock no se reparte a ojo
  assert.strictEqual(t.salidas, null);
});

caso('incluir sin firmar: suma los borradores a la cartera; apagado por defecto', () => {
  const borr = { ...bloqueo, id: 'b9', bloqueado: false };
  const e = { hoyISO: HOY, contratos: [bloqueo, borr], cobradoPorId: {}, vencimientos: [] };
  assert.strictEqual(F.finCartera(e).EUR.cartera, 100000);
  assert.strictEqual(F.finCartera({ ...e, incluirSinFirmar: true }).EUR.cartera, 200000);
});

caso('gastos: al proveedor total − PPh; la retención es salida aparte hasta ingresarse; anulado fuera (#64)', () => {
  const g = F.finGastos([
    { estado: 'pagado', moneda: 'EUR', total: 1100, base: 1000, pph_retenido: 20, pagado_el: '2026-09-10', fecha: '2026-09-01', proyecto_nombre: 'P1', grupo: 'construccion' },
    { estado: 'pendiente', moneda: 'EUR', total: 500, base: 500, pph_retenido: 0, vence_el: '2026-09-01', fecha: '2026-08-01', proyecto_nombre: 'P1', grupo: 'general' },
    { estado: 'pendiente', moneda: 'EUR', total: 300, base: 300, pph_retenido: 0, vence_el: '2026-10-15', fecha: '2026-09-20', grupo: 'suelo' },
    { estado: 'anulado',  moneda: 'EUR', total: 9999, base: 9999, pph_retenido: 0, fecha: '2026-09-01' },
  ], HOY).EUR;
  assert.strictEqual(g.pagadoMes, 1080);            // al proveedor, sin la retención
  assert.strictEqual(g.pphPorIngresar, 20);         // la retención, pendiente hacia la DJP
  assert.strictEqual(g.pendientePagar, 800);
  assert.strictEqual(g.vencidoPagar, 500);
  assert.strictEqual(g.aPagarPorMes['2026-10'], 300);
  assert.strictEqual(g.porProyecto['General (sin proyecto)'].pendiente, 300);
  assert.strictEqual(g.baseAnioPorGrupo.suelo, 300); // el suelo va en su propio grupo
});

caso('gastos: al ingresar la retención pasa a caja de ese mes y deja de estar pendiente', () => {
  const g = F.finGastos([{ estado: 'pagado', moneda: 'EUR', total: 1000, base: 1000, pph_retenido: 20, pagado_el: '2026-08-10', pph_ingresado_el: '2026-09-05', fecha: '2026-08-01' }], HOY).EUR;
  assert.strictEqual(g.pphPorIngresar, 0);
  assert.strictEqual(g.pagadoPorMes['2026-08'], 980);
  assert.strictEqual(g.pagadoPorMes['2026-09'], 20);
});

caso('comisiones pagadas: pagadas y no anuladas, importe ajustado, proyecto por su contrato raíz', () => {
  const c = F.finComisionesPagadas([
    { pagado_en: '2026-09-02T10:00:00Z', importe: 1000, importe_ajustado: 900, moneda: 'EUR', contrato_raiz_id: 'b1' },
    { pagado_en: '2026-09-02T10:00:00Z', anulado_en: '2026-09-03', importe: 500, moneda: 'EUR', contrato_raiz_id: 'b1' },
    { pagado_en: null, importe: 700, moneda: 'EUR' },
    { pagado_en: '2026-09-04', importe: 100, moneda: 'EUR', contrato_raiz_id: 'zz' },
  ], { b1: 'P1' }, HOY).EUR;
  assert.strictEqual(c.mes, 1000);
  assert.strictEqual(c.porProyecto.P1, 900);
  assert.strictEqual(c.porProyecto['Comisiones sin proyecto'], 100);
});

caso('caja neta por proyecto = recibís − gastos pagados − comisiones pagadas; sin permiso de gastos = null', () => {
  const base = { hoyISO: HOY, contratos: [bloqueo], cobradoPorId: { b1: 30000 }, vencimientos: hitosB, facturas: [], unidades: [], solicitudes: [],
    recibis: [{ tipo: 'recibi', total: 30000, moneda: 'EUR', fecha: '2026-09-05', proyecto_nombre: 'P1' }],
    comisiones: [{ estado: 'pagada', pagado_en: '2026-09-06', importe: 1000, moneda: 'EUR', contrato_raiz_id: 'b1' }] };
  const con = F.finModelo({ ...base, gastos: [{ estado: 'pagado', moneda: 'EUR', total: 5000, base: 5000, pph_retenido: 0, pagado_el: '2026-09-07', fecha: '2026-09-07', proyecto_nombre: 'P1' }] }).porMoneda.EUR;
  const p1 = con.porProyecto.find(p => p.proyecto === 'P1');
  assert.strictEqual(p1.cajaNeta, 24000);
  assert.strictEqual(p1.gastosBase, 5000);
  const serie = F.finSerieCaja(con, HOY, 12, 6).find(x => x.esHoy);
  assert.strictEqual(serie.pagado, 6000);
  assert.strictEqual(serie.neto, 24000);
  const sin = F.finModelo({ ...base, gastos: null }).porMoneda.EUR;
  assert.strictEqual(sin.gastos, null);
  assert.strictEqual(sin.porProyecto.find(p => p.proyecto === 'P1').cajaNeta, null);
  assert.strictEqual(F.finSerieCaja(sin, HOY, 12, 6).find(x => x.esHoy).pagado, null);
});

caso('filtro por sociedad: los gastos se recortan por su columna sociedad', () => {
  const e = { hoyISO: HOY, contratos: [], cobradoPorId: {}, vencimientos: [], recibis: [], facturas: [], unidades: [], solicitudes: [], comisiones: [],
    gastos: [{ sociedad: 'tepi_sungai', estado: 'pendiente', moneda: 'EUR', total: 10, base: 10, pph_retenido: 0 },
             { sociedad: 'san_dal_woods', estado: 'pendiente', moneda: 'EUR', total: 5, base: 5, pph_retenido: 0 }] };
  assert.strictEqual(F.finModelo(F.finFiltraEmpresa(e, 'san_dal_woods')).porMoneda.EUR.gastos.pendientePagar, 5);
});

caso('destino de los cobros: la caja es propia + sin clasificar; terceros y escrow fuera, y la suma cuadra (LAW-305)', () => {
  const c = F.finCobros([
    { total: 1000, moneda: 'EUR', fecha: '2026-09-02', destino: 'propia', proyecto_nombre: 'P1' },
    { total: 700,  moneda: 'EUR', fecha: '2026-09-03', destino: 'tercero', proyecto_nombre: 'P1' },
    { total: 300,  moneda: 'EUR', fecha: '2026-09-04', destino: 'escrow', proyecto_nombre: 'P1' },
    { total: 200,  moneda: 'EUR', fecha: '2026-09-05', proyecto_nombre: 'P1' },   // sin dato = sin clasificar
  ], HOY).EUR;
  assert.strictEqual(c.anio, 2200);                 // cobrado: todo lo que pagó el comprador
  assert.strictEqual(c.anioCaja, 1200);             // caja: propia + sin clasificar
  assert.deepStrictEqual(c.porDestinoAnio, { propia: 1000, tercero: 700, escrow: 300, sin_clasificar: 200 });
  const d = c.porDestinoAnio;
  assert.strictEqual(d.propia + d.tercero + d.escrow + d.sin_clasificar, c.anio);
  assert.strictEqual(c.porMesCaja['2026-09'], 1200);
  assert.strictEqual(c.porMesTerceros['2026-09'], 1000);
  assert.strictEqual(c.porProyectoCaja.P1, 1200);
});

caso('caja neta por proyecto y serie de caja NO cuentan lo cobrado en cuentas de terceros', () => {
  const m = F.finModelo({ hoyISO: HOY, contratos: [bloqueo], cobradoPorId: {}, vencimientos: [], facturas: [], unidades: [], solicitudes: [], comisiones: [], gastos: [],
    recibis: [{ total: 1000, moneda: 'EUR', fecha: '2026-09-05', proyecto_nombre: 'P1', destino: 'propia' },
              { total: 5000, moneda: 'EUR', fecha: '2026-09-05', proyecto_nombre: 'P1', destino: 'tercero' }] }).porMoneda.EUR;
  assert.strictEqual(m.porProyecto.find(p => p.proyecto === 'P1').cajaNeta, 1000);
  const s = F.finSerieCaja(m, HOY, 12, 6).find(x => x.esHoy);
  assert.strictEqual(s.cobrado, 1000);
  assert.strictEqual(s.aTerceros, 5000);
});

console.log('finanzas.test.js OK — ' + n + ' casos');
