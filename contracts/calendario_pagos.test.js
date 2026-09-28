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

if(fallos){ console.error(`\n${fallos} fallo(s) en calendario_pagos.test.js`); process.exit(1); }
console.log('calendario_pagos.test.js: todo ok');
