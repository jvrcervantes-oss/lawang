/* ═══════════════════════════════════════════════════════════════════════════
   CALENDARIO DE PAGOS DEL CONTRATO DE CONSTRUCCIÓN — 28-sep-2026
   `node calendario_pagos.test.js`. Lo corre `tools/test.py`, y con él el gate de push.
   ═══════════════════════════════════════════════════════════════════════════
   Los tres calendarios (estándar · pago único a la firma · pago único al inicio
   de obra) viven en DOS sitios a propósito: en tokens.json, para que la pantalla
   los enseñe mientras el agente edita, y en la base
   (contrato_calendario_preset), que es quien monta de verdad la tabla al
   guardar. Si divergen, la pantalla enseña una cosa y se guarda otra — o peor,
   contrato_calendario_deduce deja de reconocer como «estándar» lo que la
   pantalla acaba de montar y el contrato cae a «a medida».
   Y el Art. 5 de la plantilla elige su cláusula por `clausula_pago` con
   <!--if:clausula_pago=…-->; el texto de hitos de siempre va en el bloque de
   valor VACÍO, y tiene que salir idéntico en los dos motores (app.html y el
   del bot) cuando el contrato no trae el campo — que es todo lo firmado. */
const fs = require('fs');
const path = require('path');
const vm = require('vm');

let fallos = 0;
function ok(cond, que){ if(!cond){ fallos++; console.error('  FALLA  ' + que); } }

const AQUI = __dirname;
const tokens = JSON.parse(fs.readFileSync(path.join(AQUI, 'tokens.json'), 'utf8'));
// La definición VIGENTE de contrato_calendario_preset es la de la última migración que la trae (28-sep: la de
// 052131 y, tras la consulta de Legal, la que quita «a la firma» del concepto del pago único).
const DIR_MIG = path.join(AQUI, '..', 'supabase', 'migrations');
const migs = fs.readdirSync(DIR_MIG).filter(f => f.endsWith('.sql')).sort()
  .filter(f => fs.readFileSync(path.join(DIR_MIG, f), 'utf8').includes('-- >>> presets'));
ok(migs.length >= 1, 'hay al menos una migración con los presets entre -- >>> presets / -- <<< presets');
const sql = migs.length ? fs.readFileSync(path.join(DIR_MIG, migs[migs.length - 1]), 'utf8') : '';

// ── 1. Paridad de presets: tokens.json ↔ base ──────────────────────────────
const m = /-- >>> presets\n'([\s\S]*?)'\n-- <<< presets/.exec(sql);
ok(!!m, 'la migración marca los presets entre -- >>> presets y -- <<< presets');
const base = m ? JSON.parse(m[1].replace(/''/g, "'")) : {};
const pantalla = {
  estandar: tokens.hitosDefaults.ppjb_construccion,
  unico_firma: (tokens.hitosCalendarios || {}).unico_firma,
  unico_obra: (tokens.hitosCalendarios || {}).unico_obra
};
for(const cal of Object.keys(pantalla)){
  ok(JSON.stringify(base[cal]) === JSON.stringify(pantalla[cal]),
     `preset «${cal}» igual en tokens.json y en la base\n         base:     ${JSON.stringify(base[cal])}\n         pantalla: ${JSON.stringify(pantalla[cal])}`);
}
ok(Object.keys(base).sort().join() === 'estandar,unico_firma,unico_obra', 'la base no tiene calendarios que la pantalla no conozca');
for(const cal of Object.keys(pantalla)){
  const l = pantalla[cal] || [];
  ok(l.filter(h => h.resto).length === 1, `«${cal}» tiene exactamente un hito resto`);
  ok(l.reduce((t,h) => t + parseFloat(h.pct), 0) === 100, `«${cal}» suma 100 %`);
  ok(l.every(h => h.fijo && h.calculado), `«${cal}»: todos de fábrica y calculados`);
  ok(l.every(h => !('fecha' in h) && !('vence_dias' in h) && !('vence_meses' in h)),
     `«${cal}» no trae fecha de fábrica: el vencimiento lo pone la obra o el agente, nunca la firma sola`);
}

// ── 2. La pantalla clasifica igual que la base ─────────────────────────────
const ctx = { TOKENS: tokens, document: { querySelector: () => null }, console };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(AQUI, 'assets', 'hitos_fechas.js'), 'utf8'), ctx);
const deduce = ctx.calendarioDeduce;
ok(typeof deduce === 'function', 'hitos_fechas.js define calendarioDeduce');
if(typeof deduce === 'function'){
  const c = x => JSON.parse(JSON.stringify(x));
  ok(deduce(c(pantalla.estandar)) === 'estandar', 'los 5 de fábrica = estandar');
  ok(deduce(c(pantalla.unico_firma)) === 'unico_firma', 'preset de firma = unico_firma');
  ok(deduce(c(pantalla.unico_obra)) === 'unico_obra', 'preset de obra = unico_obra');
  ok(deduce([]) === 'libre' && deduce(null) === 'libre', 'sin hitos = libre');
  ok(deduce([{ pct: '50', es: 'A' }, { pct: '50', es: 'B' }]) === 'libre', 'sin ninguna marca de fábrica = libre (contratos de antes del 16-sep)');
  const tocado = c(pantalla.estandar); tocado[0].pct = '30'; tocado[1].pct = '20';
  ok(deduce(tocado) === 'manual', 'un % de fábrica tocado = manual');
  const seis = c(pantalla.estandar).concat([{ pct: '0', es: 'Extra', fijo: false }]);
  ok(deduce(seis) === 'manual', 'un hito añadido a los de fábrica = manual');
  const conFecha = c(pantalla.unico_firma); conFecha[0].fecha = '2026-10-01'; conFecha[0].monto = '67.000';
  ok(deduce(conFecha) === 'unico_firma', 'fecha e importe no cambian el calendario');
}

// ── 3. El Art. 5 en los dos motores ────────────────────────────────────────
const tpl = fs.readFileSync(path.join(AQUI, 'templates', 'ppjb_construccion.html'), 'utf8');
// motor de app.html (buildDoc), copiado de su línea
const motorApp = (html, data) => html.replace(/<!--if:([a-z0-9_]+)=([a-z0-9_]*)-->[\s\S]*?<!--\/if:\1-->/g,
  (mm, k, v) => (v === '' ? (data[k] == null || data[k] === '') : data[k] === v) ? mm : '');
ok(fs.readFileSync(path.join(AQUI, 'app.html'), 'utf8').includes(
  "html=html.replace(/<!--if:([a-z0-9_]+)=([a-z0-9_]*)-->[\\s\\S]*?<!--\\/if:\\1-->/g,(m,k,v)=> (v === '' ? (data[k] == null || data[k] === '') : data[k]===v) ? m : '');"),
  'app.html sigue usando el motor <!--if:--> que prueba este test');
const { plantillaTexto } = require('./bot/plantilla_texto.js');

const LI_HITOS_1 = 'Los pagos deberán realizarse en la etapa establecida para garantizar la continuidad de la obra.';
const LI_HITOS_3 = 'Cada hito será exigible al inicio de la fase de obra que designa';
const LI_FIRMA_1 = 'El CONSTRUCTOR no estará obligado a iniciar los trabajos';
const LI_FIRMA_3 = 'El pago único será exigible en la fecha indicada en la tabla';
const LI_OBRA_3 = 'exigible al inicio de la fase de preparación del terreno';
const cuenta = (s, t) => s.split(t).length - 1;

for(const [nombre, render] of [['app', d => motorApp(tpl, d)], ['bot', d => plantillaTexto(tpl, 'es', d)]]){
  for(const d of [{}, { clausula_pago: '' }]){
    const s = render(d);
    ok(cuenta(s, LI_HITOS_1) === 1 && cuenta(s, LI_HITOS_3) === 1, `${nombre} sin clausula_pago: el texto de hitos de siempre, una vez`);
    ok(!s.includes(LI_FIRMA_1) && !s.includes(LI_FIRMA_3) && !s.includes(LI_OBRA_3), `${nombre} sin clausula_pago: nada de pago único`);
  }
  const f = render({ clausula_pago: 'unico_firma' });
  ok(cuenta(f, LI_FIRMA_1) === 1 && cuenta(f, LI_FIRMA_3) === 1, `${nombre} unico_firma: sus dos puntos`);
  ok(!f.includes(LI_HITOS_1) && !f.includes(LI_HITOS_3) && !f.includes(LI_OBRA_3), `${nombre} unico_firma: sin los de hitos ni obra`);
  const o = render({ clausula_pago: 'unico_obra' });
  ok(cuenta(o, LI_HITOS_1) === 1 && cuenta(o, LI_OBRA_3) === 1, `${nombre} unico_obra: primer punto de siempre + exigible al inicio`);
  ok(!o.includes(LI_HITOS_3) && !o.includes(LI_FIRMA_1) && !o.includes(LI_FIRMA_3), `${nombre} unico_obra: sin el de hitos ni los de firma`);
}
// …y en los tres idiomas: ningún bloque se queda sin su pareja
for(const cal of ['', 'unico_obra', 'unico_firma']){
  const s = motorApp(tpl, { clausula_pago: cal });
  const art5 = s.slice(s.indexOf('<!--/seccion-hitos-->'), s.indexOf('<!--datos-bancarios-->'));
  const n = ['es', 'en', 'id'].map(l => {
    const ul = new RegExp('<ul data-lang="' + l + '">([\\s\\S]*?)</ul>').exec(art5);
    return ul ? cuenta(ul[1], '<li>') : -1;
  });
  ok(n.every(x => x === 3), `Art. 5 «${cal || 'hitos'}»: 3 puntos en ES, EN e ID (dio ${n.join('/')})`);
}
ok(!/<!--if:clausula_pago/.test(motorApp(tpl, {}).replace(/<!--if:clausula_pago=[a-z_]*-->[\s\S]*?<!--\/if:clausula_pago-->/g, '')),
   'no queda ningún <!--if:clausula_pago--> sin cerrar');

// ── 4. % o cantidad (14-oct-2026): la cantidad tecleada vuelve EXACTA desde su % ──
// La base rehace la cantidad con round(precio · pct) / 100 (contrato_calendario_reparte). Aquí se repite en
// enteros (BigInt), sin coma flotante: céntimos = round(P·Q / 10^(2+dec)), P = precio en céntimos.
const dinero = require('./assets/dinero.js');
const escala = s => { const [e, d = ''] = String(s).split('.'); return { n: BigInt(e + d), dec: d.length }; };
const centimosBase = (precio, pct) => {
  const P = escala(precio), Q = escala(pct);
  const den = 10n ** BigInt(P.dec + Q.dec);                 // precio·pct, y /100 · 100 céntimos se anulan
  return (P.n * Q.n * 2n + den) / (2n * den);                // redondeo half-up (todo positivo)
};
const aCent = s => { const [e, d = ''] = String(s).split('.'); return BigInt(e + (d + '00').slice(0, 2)); };
// los 10 casos medidos contra la función viva el 14-oct (10/10 exactos con 12 decimales)
for(const [precio, imp] of [['333333','10000'],['287500.5','10000'],['287500','12345.67'],['5250000000','1000000000'],
    ['4987654321','123456789'],['150000','37500'],['99999.99','0.01'],['1000','1'],['9876543210','1234567890.12'],['3150000000','787500000']]){
  const pct = dinero.lwPctDeImporte(parseFloat(imp), parseFloat(precio));
  ok(pct !== null && centimosBase(precio, pct) === aCent(imp), `${imp} sobre ${precio}: el % ${pct} devuelve la cantidad exacta (dio ${pct === null ? 'null' : centimosBase(precio, pct)} céntimos)`);
  ok(pct === null || !/\.\d{3}$/.test(pct), `${imp} sobre ${precio}: el % ${pct} no tiene exactamente 3 decimales`);
}
ok(dinero.lwPctDeImporte(150000, 0) === null, 'sin precio total no hay %');
ok(dinero.lwPctDeImporte(200000, 150000) === null, 'una cantidad mayor que el precio no cabe');
ok(dinero.lwPctDeImporte(-1, 150000) === null && dinero.lwPctDeImporte(NaN, 150000) === null, 'negativa o no numérica: null');
ok(dinero.lwPctDeImporte(18187.5, 145500) === '12.5', '«12.5», sin ceros de cola');
ok(dinero.lwPctSeguro('12.123') === '12.1230' && dinero.lwPctSeguro('12.12') === '12.12' && dinero.lwPctSeguro('12.1234') === '12.1234',
   'lwPctSeguro solo toca los de exactamente 3 decimales');
ok(dinero.lwParseImporte(dinero.lwPctSeguro('12.123')) === 12.123, 'y así el parser común lo lee como 12.123, no como 12123');
// La columna impresa suma 100 (resto mayor), y lo de 2 decimales o menos no cambia
const suma = l => Math.round(l.reduce((t, s) => t + parseFloat(s || 0), 0) * 100) / 100;
{
  const precio = 287500, imps = [10000, 10000, 10000];
  const pcts = imps.map(x => dinero.lwPctDeImporte(x, precio));
  const lista = pcts.concat([String(100 - pcts.reduce((t, p) => t + parseFloat(p), 0))]);   // el resto, a mano
  const imp = dinero.lwPctImpresos(lista);
  ok(suma(lista.map(p => parseFloat(p).toFixed(2))) !== 100, 'el caso de prueba SÍ descuadra redondeando uno a uno (si no, no prueba nada)');
  ok(suma(imp) === 100, `la columna impresa suma 100 (dio ${imp.join(' + ')})`);
  ok(imp.every((s, i) => Math.abs(parseFloat(s) - parseFloat(lista[i])) < 0.01 + 1e-9), 'cada % impreso está a menos de una centésima del real');
}
ok(JSON.stringify(dinero.lwPctImpresos(['25', '25', '25', '20', '5'])) === '["25","25","25","20","5"]', 'los 5 de fábrica salen tal cual');
ok(JSON.stringify(dinero.lwPctImpresos(['62.50', '37.5', ''])) === '["62.50","37.5",""]', 'con 2 decimales o menos, ni una letra cambia');
ok(dinero.lwTextoPct('62.50') === '62.50' && dinero.lwTextoPct(62.5) === '62.5' && dinero.lwTextoPct('3.478254820426') === '3.48',
   'lwTextoPct: con 2 decimales o menos, tal cual; con más, a 2');

if(fallos){ console.error(`\n${fallos} fallo(s) en calendario_pagos.test.js`); process.exit(1); }
console.log('calendario_pagos.test.js: todo ok');
