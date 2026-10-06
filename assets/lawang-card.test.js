/* Autochequeo de la tarjeta y de la regla de estado:  node assets/lawang-card.test.js
   (lo recoge tools/test.py como todo *.test.js). F7, 6-oct-2026.
   Afirma HECHOS contra todos los sitios donde viven, no funciones sueltas:
     · LawangCard.estado == lw_coleccion_estado (PHP): la MISMA tabla, coleccion/tests/estados_esperados.json,
       contra la RPC real del 6-oct y contra casos sinteticos;
     · sin `live` (data.json) la tarjeta es la de siempre: nada de chip, «Sold out» ni «From» quitado;
     · con dato viejo (stale) NINGUNA tarjeta dice «Available» ni «N of M»: dice «Ask for availability». */
const vm = require('vm'), fs = require('fs'), path = require('path');
const raiz = path.resolve(__dirname, '..');
const w = {};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, 'lawang-card.js'), 'utf8'), { window: w });
const C = w.LawangCard;
let fallos = 0;
function ok(c, m) { if (!c) { fallos++; console.log('FALLO: ' + m); } }

const tabla = JSON.parse(fs.readFileSync(path.join(raiz, 'coleccion/tests/estados_esperados.json'), 'utf8'));
const rpc = JSON.parse(fs.readFileSync(path.join(raiz, 'coleccion/tests/rpc_real_20261006.json'), 'utf8')).properties;

// 1. la tabla
for (const p of rpc) {
  const k = C.estado(p, false).k;
  ok(k === tabla.rpc_6oct[p.id], 'estado de ' + p.id + ': ' + k + ' (esperado ' + tabla.rpc_6oct[p.id] + ')');
}
ok(Object.keys(tabla.rpc_6oct).length === rpc.length, 'la tabla cubre las ' + rpc.length + ' fichas de la RPC');
for (const c of tabla.sinteticos) {
  const k = C.estado({ parcelas: c.parcelas, unitsAvailable: c.unitsAvailable }, !!c.stale).k;
  ok(k === c.esperado, c.nota + ': ' + k + ' (esperado ' + c.esperado + ')');
}

// 2. sin `live`: identica a la de siempre (el chip y «Sold out» no existen; «From» se conserva aunque haya priceMode)
for (const p of rpc) {
  for (const lang of ['en', 'es', 'id']) {
    const a = C.render(p, { lang }), b = C.render(p, { lang, live: false, stale: true });
    ok(a === b, 'sin live, stale no cambia nada (' + p.id + ',' + lang + ')');
    ok(!/lw-prop-state|is-sold|sold-price/.test(a), 'sin live no hay chip ni sold-out (' + p.id + ')');
    ok(/class="from"/.test(a) === (p.priceEUR > 0), 'sin live el «From» de siempre (' + p.id + ')');
    ok(!p.status || /pf-pill (plan|built|constr)/.test(a), 'la pastilla de estado de obra sigue (' + p.id + ')');
  }
}

// 3. con live, dato fresco: lo que pinta cada ficha real
const chip = (p, o) => { const m = C.render(p, Object.assign({ lang: 'en', live: true }, o || {})).match(/lw-prop-state st-(\w+)"><i aria-hidden="true"><\/i>([^<]*)</); return m ? m[1] + ':' + m[2] : null; };
const por = id => rpc.find(p => p.id === id);
ok(chip(por('tirta-hikari')) === 'ok:Available', 'casa unica libre = Available sin contador: ' + chip(por('tirta-hikari')));
ok(chip(por('riverfront-i')) === 'ok:2 of 4 available', 'riverfront-i: ' + chip(por('riverfront-i')));
ok(chip(por('pura-dalem')) === 'few:Last unit', 'pura-dalem: ' + chip(por('pura-dalem')));
ok(chip(por('palm-field-bali')) === 'ok:25 of 36 plots', 'palm-field: ' + chip(por('palm-field-bali')));
ok(chip(por('riverfront-iii')) === null, 'sin parcelas y dato fresco: sin chip (no es «sin dato»)');
ok(chip(por('palm-field-bali'), { lang: 'es' }) === 'ok:25 de 36 parcelas', 'es: ' + chip(por('palm-field-bali'), { lang: 'es' }));
ok(chip(por('palm-field-bali'), { lang: 'id' }) === 'ok:25 dari 36 kavling', 'id: ' + chip(por('palm-field-bali'), { lang: 'id' }));
const fijo = C.render(por('cube'), { lang: 'en', live: true });
ok(!/class="from"/.test(fijo) && /199,000/.test(fijo), 'priceMode fixed: precio sin From');
ok(/class="from"/.test(C.render(por('palm-field-bali'), { lang: 'en', live: true })), 'priceMode from: con From');

// 4. todo vendido: «Sold out» en lugar del precio, tarjeta marcada
const vendida = Object.assign({}, por('river'), { parcelas: [{ codigo: 'U0', estado: 'vendida' }] });
const hv = C.render(vendida, { lang: 'en', live: true });
ok(/is-sold/.test(hv) && /sold-price">Sold out</.test(hv) && !/167,000/.test(hv) && !/class="from"/.test(hv), 'vendida: Sold out en vez del precio');
ok(/st-gone"><i aria-hidden="true"><\/i>Sold</.test(hv), 'vendida: chip Sold');
const reservada = Object.assign({}, por('cube'), { parcelas: [{ codigo: 'U0', estado: 'reservada' }] });
ok(/st-held/.test(C.render(reservada, { lang: 'en', live: true })) && /199,000/.test(C.render(reservada, { lang: 'en', live: true })), 'reservada: chip Reserved y precio visible');

// 5. dato viejo: nada de «Available» / «N of M», y una vendida NO anuncia «Sold out» (no se sabe)
for (const p of rpc.concat([vendida])) {
  for (const lang of ['en', 'es', 'id']) {
    const h = C.render(p, { lang, live: true, stale: true });
    ok(/st-na/.test(h), 'stale: chip «sin dato» en ' + p.id + ',' + lang);
    ok(!/st-(ok|few|held|gone)|is-sold|sold-price/.test(h), 'stale: ningun estado afirmado en ' + p.id + ',' + lang);
    ok(!/ of \d+ (available|plots)|>Available</i.test(h), 'stale: ningun «Available» ni «N of M» en ' + p.id);
  }
}

if (fallos) { console.log(fallos + ' FALLO(S)'); process.exit(1); }
console.log('OK: lawang-card (estado = tabla unica, v1 intacta, stale nunca afirma).');
