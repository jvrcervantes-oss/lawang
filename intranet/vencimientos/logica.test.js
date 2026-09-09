/* Test de la lógica del dashboard de vencimientos. `node logica.test.js`.
   Lo corre tools/test.py, y con él el gate de push.

   Los casos no son inventados: son las reglas de dinero que a esta suite ya le
   costaron dinero aprender, aplicadas al dashboard que va a vigilar ~100 M€:
   · la Carta no suma precio pero su cobrado SÍ se descuenta en el Bloqueo
     (el caso de los 328.000 € por una villa de 164.000);
   · un importe desconocido es null, no 0 (un 0 falso se cree; un hueco se
     pregunta — la lección del hub);
   · las monedas no se mezclan en una suma;
   · la cascada cubre por orden de fecha, y un pago parcial se ve como parcial. */
const path = require('path');

/* logica.js espera las globales de la suite (lwParseImporte, lwEsPreliminar):
   se cargan igual que las carga el navegador, evaluándolas antes. */
const fs = require('fs');
/* La herramienta vive bajo `/intranet/` desde el 26-ago-2026, así que la raíz
   del proyecto está DOS niveles arriba, no uno. */
const AQUI = __dirname;
const RAIZ = path.join(__dirname, '..', '..');
const dinero = require(path.join(RAIZ, 'contracts', 'assets', 'dinero.js'));
global.lwParseImporte = dinero.lwParseImporte;
// vocabulario.js no exporta para node: se evalúa como en la página
const voc = fs.readFileSync(path.join(RAIZ, 'contracts', 'assets', 'vocabulario.js'), 'utf8');
new Function(voc + '; globalThis.lwEsPreliminar = lwEsPreliminar;')();
// entities.js igual: define SOCIEDADES y el resolver de sociedad firmante que
// las funciones de empresa (9-sep) llaman como global. Solo datos y funciones
// puras a nivel de fichero — la red vive dentro de cargarCuentasBancarias().
const ent = fs.readFileSync(path.join(RAIZ, 'contracts', 'assets', 'entities.js'), 'utf8');
new Function(ent + '; globalThis.lwSociedadContrato = lwSociedadContrato;')();
const L = require(path.join(AQUI, 'logica.js'));

let fallos = 0;
const es = (que, dio, esperado) => {
  const ok = JSON.stringify(dio) === JSON.stringify(esperado);
  if(!ok){ fallos++; console.error(`  FALLA  ${que}\n         dio ${JSON.stringify(dio)} · esperaba ${JSON.stringify(esperado)}`); }
};

const HOY = '2026-08-18';

/* ── importeVencimiento ── */
es('monto escrito manda, formateado a la española',
   L.importeVencimiento({monto:'82.000', pct:'50'}, {precio_total:100000}), 82000);
es('sin monto, pct sobre el precio',
   L.importeVencimiento({monto:'', pct:'50'}, {precio_total:164000}), 82000);
es('sin monto ni pct: null, nunca 0',
   L.importeVencimiento({monto:'', pct:''}, {precio_total:164000}), null);
es('pct sin precio conocido: null',
   L.importeVencimiento({monto:'', pct:'50'}, {precio_total:null}), null);

/* ── cobradoEfectivo: la Carta descuenta en su Bloqueo ── */
const contratos = [
  {id:'B', tipo:'reserva_parcela', precio_total:82000, moneda:'EUR', bloqueado:true, contrato_padre_id:null, proyecto_nombre:'Bonian'},
  {id:'CA', tipo:'carta_reserva', precio_total:82000, moneda:'EUR', bloqueado:true, contrato_padre_id:'B', proyecto_nombre:'Bonian'},
  {id:'CC', tipo:'construccion', precio_total:82000, moneda:'EUR', bloqueado:true, contrato_padre_id:'B', proyecto_nombre:'Bonian'},
];
const cobrado = { B: 10000, CA: 5000, CC: 20000 };
es('el Bloqueo suma su cobrado + el de su Carta (preliminar)',
   L.cobradoEfectivo(contratos[0], contratos, cobrado), 15000);
es('la Construcción NO absorbe el dinero de la Carta (cuelga del mismo padre pero no es suya)',
   L.cobradoEfectivo(contratos[2], contratos, cobrado), 20000);

/* ── cascada ── */
const vencs = [
  {id:'v1', contrato_id:'B', orden:1, pct:'50', monto:'', fecha:'2026-08-01'},
  {id:'v2', contrato_id:'B', orden:2, pct:'50', monto:'', fecha:'2026-11-01'},
];
const c1 = L.cascada(vencs, contratos[0], 15000, HOY);
es('1er hito (41.000): 15.000 cubiertos → parcial y VENCIDO no (está a medias pero pasado)…',
   [c1[0].importe, c1[0].cubierto, c1[0].pendiente, c1[0].estado],
   [41000, 15000, 26000, 'vencido']);
es('2º hito: nada cubierto, futuro → pendiente',
   [c1[1].cubierto, c1[1].estado], [0, 'pendiente']);
es('cobrado de sobra cubre en orden de fecha',
   L.cascada(vencs, contratos[0], 82000, HOY).map(v=>v.estado), ['cobrado','cobrado']);
es('sin fecha va al final de la cascada y se marca sin_fecha',
   L.cascada([{orden:1, pct:'50', monto:'', fecha:null},{orden:2, pct:'50', monto:'', fecha:'2026-09-01'}],
             contratos[0], 0, HOY).map(v=>[v.orden, v.estado]),
   [[2,'pendiente'],[1,'sin_fecha']]);
es('sin fecha pero ya cubierto del todo cuenta como cobrado, no como alerta',
   L.cascada([{orden:1, pct:'100', monto:'', fecha:null}], contratos[0], 82000, HOY)[0].estado,
   'cobrado');

/* ── modeloFinanciero ── */
const modelo = L.modeloFinanciero({
  hoyISO: HOY,
  contratos: contratos.concat([
    {id:'USD1', tipo:'reserva_parcela', precio_total:50000, moneda:'USD', bloqueado:true, contrato_padre_id:null, proyecto_nombre:'Sumba'},
    {id:'POA1', tipo:'poa', precio_total:0, moneda:'EUR', bloqueado:true, contrato_padre_id:null, proyecto_nombre:'Bonian'},
  ]),
  cobradoPorId: cobrado,
  vencimientos: vencs.concat([
    {id:'v3', contrato_id:'CC', orden:1, pct:'25', monto:'', fecha:'2026-09-10'},
    {id:'v4', contrato_id:'CC', orden:2, pct:'25', monto:'', fecha:null},
    {id:'v5', contrato_id:'USD1', orden:1, pct:'100', monto:'', fecha:'2026-08-01'},
  ]),
});
const eur = modelo.EUR, usd = modelo.USD;
es('la cartera EUR no cuenta la Carta (misma villa dos veces)', eur.cartera, 164000);
es('el cobrado EUR sí lo cuenta todo (15.000 del grupo del Bloqueo + 20.000 de la obra)', eur.cobrado, 35000);
es('las monedas no se mezclan: USD va aparte', [usd.cartera, usd.vencido], [50000, 50000]);
es('vencido EUR = lo pendiente del hito pasado', eur.vencido, 26000);
/* La cuenta, entera, porque la primera versión de este caso la hizo mal (esperaba
   500 y olvidó el segundo hito del Bloqueo):
   · obra, hito 10-sep: 25% de 82.000 = 20.500, cubiertos 20.000 → pendientes 500
   · Bloqueo, hito 1-nov (a 75 días del 18-ago, DENTRO de la ventana): 41.000
     pendientes — el cobrado del grupo (15.000) se lo comió entero el hito vencido
   → 41.500. El propio fallo del test demuestra para qué está: la intuición
   redondea, la cascada no. */
es('próximos 90 días EUR = 500 de la obra + 41.000 del Bloqueo del 1-nov',
   eur.proximos90, 41500);
es('un vencimiento sin fecha del contrato de obra queda contado como alerta', eur.nSinFecha, 1);
es('el POA no genera aviso de "sin calendario" (no es una venta por hitos)',
   eur.avisos.filter(a=>a.contrato.id==='POA1').length, 0);
es('los hitos del Bloqueo suman 100: sin aviso de pct',
   eur.avisos.filter(a=>a.tipo==='pct_no_100' && a.contrato.id==='B').length, 0);
es('los de la obra suman 50 (faltan 2 hitos): AVISO',
   eur.avisos.filter(a=>a.tipo==='pct_no_100' && a.contrato.id==='CC').length, 1);

/* ── la Carta suelta: su señal es dinero en caja aunque su precio no cuente ── */
const conSuelta = L.modeloFinanciero({
  hoyISO: HOY,
  contratos: [
    {id:'B', tipo:'reserva_parcela', precio_total:82000, moneda:'EUR', bloqueado:true, contrato_padre_id:null, proyecto_nombre:'Bonian'},
    {id:'CSUELTA', tipo:'carta_reserva', precio_total:82000, moneda:'EUR', contrato_padre_id:null, proyecto_nombre:'Bonian'},
  ],
  cobradoPorId: { B: 0, CSUELTA: 5000 },
  vencimientos: [],
});
es('la señal de una Carta SIN Bloqueo cuenta como cobrado', conSuelta.EUR.cobrado, 5000);
es('…pero su precio sigue sin entrar en cartera (no es de fiar)', conSuelta.EUR.cartera, 82000);

/* ── los borradores NO entran (cliente, 18-ago): crear el contrato no marca
   dinero como esperado — se espera a la firma. Su cobrado real sí cuenta. ── */
const conBorrador = L.modeloFinanciero({
  hoyISO: HOY,
  contratos: [
    {id:'F', tipo:'reserva_parcela', precio_total:100000, moneda:'EUR', bloqueado:true, contrato_padre_id:null, proyecto_nombre:'P'},
    {id:'DRAFT', tipo:'reserva_parcela', precio_total:900000, moneda:'EUR', bloqueado:false, contrato_padre_id:null, proyecto_nombre:'P'},
  ],
  cobradoPorId: { F: 0, DRAFT: 7000 },
  vencimientos: [
    {id:'vf', contrato_id:'F', orden:1, pct:'100', monto:'', fecha:'2026-09-01'},
    {id:'vd', contrato_id:'DRAFT', orden:1, pct:'100', monto:'', fecha:'2026-08-01'},
  ],
});
es('el borrador no aporta cartera (900.000 fuera)', conBorrador.EUR.cartera, 100000);
es('ni vencimientos: su hito pasado NO es vencido', conBorrador.EUR.vencido, 0);
es('ni filas en la tabla', conBorrador.EUR.filas.map(f=>f.id), ['vf']);
es('pero su cobrado real sí es caja', conBorrador.EUR.cobrado, 7000);

/* ── aging del vencido: cada euro con su edad ── */
const agFilas = [
  { estado:'vencido', fecha:'2026-08-10', pendiente:1000 },   // 8 días  → 1-30
  { estado:'vencido', fecha:'2026-07-01', pendiente:2000 },   // 48 días → 31-60
  { estado:'vencido', fecha:'2026-05-01', pendiente:4000 },   // 109 días → +90
  { estado:'cobrado', fecha:'2026-05-01', pendiente:0 },      // cobrado no es deuda
  { estado:'pendiente', fecha:'2026-09-01', pendiente:500 },  // futuro no es deuda
];
const ag = L.agingVencido(agFilas, HOY);
es('aging: cada vencido cae en su tramo por días de retraso',
   ag.map(t=>[t.etiqueta, t.importe, t.n]),
   [['1–30 días',1000,1],['31–60 días',2000,1],['61–90 días',0,0],['+90 días',4000,1]]);
es('aging con nada vencido: los 4 tramos igual, a cero — un tramo que falta miente',
   L.agingVencido([], HOY).map(t=>t.importe), [0,0,0,0]);

/* ── trimestres naturales: la cifra que cierra contabilidad ── */
const triFilas = [
  { fecha:'2026-09-15', pendiente:10000 },   // T3 2026
  { fecha:'2026-08-20', pendiente:5000 },    // T3 2026
  { fecha:'2026-11-01', pendiente:20000 },   // T4 2026
  { fecha:'2027-02-10', pendiente:7000 },    // T1 2027 (cruza el año)
  { fecha:'2026-12-31', pendiente:1,   },    // borde: último día de T4
  { fecha:'2026-07-01', pendiente:999, estado:'vencido' },  // T3 pero PASADO… sigue en su trimestre
  { fecha:null, pendiente:3000 },            // sin fecha no entra en ningún trimestre
  { fecha:'2026-10-05', pendiente:0 },       // sin pendiente no cuenta
];
const tri = L.porTrimestre(triFilas, HOY, 4);
es('4 trimestres naturales desde el corriente, con el cruce de año bien',
   tri.map(t=>t.trimestre), ['T3 2026','T4 2026','T1 2027','T2 2027']);
es('T3 suma lo del trimestre corriente (incluido lo ya vencido dentro de él)',
   tri[0].importe, 10000 + 5000 + 999);
es('T4 con el borde del 31-dic dentro', tri[1].importe, 20001);
es('T1 2027 tras el cambio de año', tri[2].importe, 7000);
es('T2 2027 vacío es 0, no ausente', tri[3].importe, 0);

/* ── mesesVentana ── */
const meses = L.mesesVentana(HOY);
es('15 meses, de 3 atrás a 11 adelante, sin huecos',
   [meses.length, meses[0], meses[3], meses[14]], [15, '2026-05', '2026-08', '2027-07']);
es('la ventana cruza el cambio de año sin romperse',
   L.mesesVentana('2026-12-15')[4], '2027-01');

/* ── empresa (sociedad firmante): resolver, herencia y el invariante ──
   9-sep-2026. La regla del resolver vive en entities.js (la misma del
   generador); aquí se prueba que el panel la aplica y que el filtro no puede
   perder dinero: la suma de los modelos por empresa ES el modelo de «Todas»,
   agregado a agregado Y POR MONEDA — un cruce mal compuesto entre el filtro
   de empresa y el de moneda mezclaría importes sin que un total único lo note. */
es('resolver: manda lo elegido', lwSociedadContrato('san_dal_woods', 'reserva_parcela'), 'san_dal_woods');
es('resolver: vacío cae al default global (lo que imprime el documento)',
   lwSociedadContrato('', 'reserva_parcela'), 'tepi_sungai');
es('resolver: vacío en ppjb_reserva cae a SAN DAL WOODS, su default de plantilla',
   lwSociedadContrato(null, 'ppjb_reserva'), 'san_dal_woods');

const empContratos = [
  // dos empresas × dos monedas, con huecos a propósito
  {id:'T1', tipo:'reserva_parcela', soc:'tepi_sungai',   precio_total:100000, moneda:'EUR', bloqueado:true, contrato_padre_id:null, proyecto_nombre:'Bonian'},
  {id:'T2', tipo:'construccion',    soc:'',              precio_total:50000,  moneda:'EUR', bloqueado:true, contrato_padre_id:null, proyecto_nombre:'Bonian'},   // vacío → tepi
  {id:'S1', tipo:'reserva_parcela', soc:'san_dal_woods', precio_total:80000,  moneda:'EUR', bloqueado:true, contrato_padre_id:null, proyecto_nombre:'Mejan'},
  {id:'S2', tipo:'ppjb_bonian',     soc:'san_dal_woods', precio_total:900000000, moneda:'IDR', bloqueado:true, contrato_padre_id:null, proyecto_nombre:'Mejan'},
  // Carta hija con el campo VACÍO colgando de un padre san_dal_woods: por su
  // propio campo resolvería tepi_sungai y su cobrado se perdería del filtro
  {id:'CA1', tipo:'carta_reserva', soc:'', precio_total:80000, moneda:'EUR', bloqueado:true, contrato_padre_id:'S1', proyecto_nombre:'Mejan'},
  // typo histórico: no está en SOCIEDADES — debe tener su propio chip, no desaparecer
  {id:'X1', tipo:'reserva_parcela', soc:'sociedad_typo', precio_total:10000, moneda:'EUR', bloqueado:true, contrato_padre_id:null, proyecto_nombre:'Bonian'},
];
const empPorId = {}; for(const c of empContratos) empPorId[c.id] = c;
es('herencia: la Carta hija va con la empresa de su PADRE, no con su propio default',
   L.empresaDeContrato(empContratos[4], empPorId), 'san_dal_woods');

const empVencs = [
  {id:'ev1', contrato_id:'T1', orden:1, pct:'50', monto:'', fecha:'2026-07-01'},   // vencido
  {id:'ev2', contrato_id:'T1', orden:2, pct:'50', monto:'', fecha:'2026-09-01'},   // próximo
  {id:'ev3', contrato_id:'S1', orden:1, pct:'100', monto:'', fecha:'2026-08-25'},  // próximos 30
  {id:'ev4', contrato_id:'S2', orden:1, pct:'100', monto:'', fecha:null},          // sin fecha (IDR)
  {id:'ev5', contrato_id:'X1', orden:1, pct:'100', monto:'', fecha:'2026-06-01'},  // vencido del typo
];
const empCobrado = { T1:20000, S1:5000, CA1:15000, X1:0 };
const empEntrada = { hoyISO:HOY, contratos:empContratos, cobradoPorId:empCobrado, vencimientos:empVencs };

es('las empresas salen de los DATOS: el typo tiene chip propio, y ordena por cartera',
   L.empresasFinancieras(empEntrada, [{sociedad:'sandal_woods_ltd', tipo:'factura'}]),
   ['san_dal_woods','tepi_sungai','sociedad_typo','sandal_woods_ltd']);

const todo = L.modeloFinanciero(empEntrada);
const porEmpresa = L.empresasFinancieras(empEntrada, []).map(e => L.modeloFinanciero(L.filtraEmpresa(empEntrada, e)));
for(const mon of Object.keys(todo)){
  const suma = campo => Math.round(porEmpresa.reduce((t,M) => t + ((M[mon]||{})[campo]||0), 0)*100)/100;
  for(const campo of ['cartera','cobrado','pendiente','vencido','proximos30','proximos90','nSinFecha'])
    es(`invariante ${mon}: la suma de las empresas es «Todas» en ${campo}`, suma(campo), Math.round((todo[mon][campo]||0)*100)/100);
  const prevTodo = Object.values(todo[mon].porMes).reduce((t,x)=>t+x.previsto,0);
  const prevSuma = porEmpresa.reduce((t,M)=>t+Object.values((M[mon]||{porMes:{}}).porMes).reduce((u,x)=>u+x.previsto,0),0);
  es(`invariante ${mon}: el previsto por mes tampoco pierde filas`, Math.round(prevSuma), Math.round(prevTodo));
}
es('el cobrado de la Carta hija sigue en la empresa del padre al filtrar',
   L.modeloFinanciero(L.filtraEmpresa(empEntrada, 'san_dal_woods')).EUR.cobrado, 20000);
es('filtrar por «todas» devuelve la entrada intacta',
   L.filtraEmpresa(empEntrada, 'todas').contratos.length, empContratos.length);

if(fallos){ console.error(`\nlogica.test.js — ${fallos} fallo(s)`); process.exit(1); }
console.log('OK logica.test.js — cascada, cartera sin dobles, monedas separadas, aging, trimestres, avisos de calidad y empresas sin perder un euro');
