/* Test del lector de importes compartido. `node dinero.test.js`.
   ============================================================================
   Cada caso de la primera tabla es una DIVERGENCIA REAL medida el 17-ago-2026
   entre las dos implementaciones que habia. No son casos inventados: son los
   sitios exactos donde las dos versiones daban respuestas distintas sobre
   dinero, y estan aqui para que ninguna vuelva. */
const { lwParseImporte: p, lwFormatoImporte: fmt } = require('./dinero.js');

let fallos = 0;
function es(entrada, esperado, porque){
  const dio = p(entrada);
  const ok = Object.is(dio, esperado);
  if(!ok){ fallos++; console.error(`  FALLA  ${JSON.stringify(entrada)} → ${dio}, se esperaba ${esperado}\n         ${porque}`); }
}

// ── Las seis divergencias que motivaron unificar ──────────────────────────
es('-5.000', -5000, 'Contratos se comia el signo y devolvia +5000: un cargo se leia como un abono');
es('1.2345', 1.2345, 'un tipo de cambio lleva cuatro decimales; Facturas lo leia 12345, error de 10.000x');
es('12.34.56', 123456, 'dos separadores son miles, no decimales');
es('1,2,3', 123, 'idem con comas');
es('', null, 'sin numero es null y NO 0: un contrato sin precio no es un contrato de 0 €');
es('abc', null, 'idem');

// ── Lo que las dos ya hacian bien, para que siga igual ────────────────────
es('164.000', 164000, 'miles con punto');
es('1,500', 1500, 'miles con coma');
es('79.000,50', 79000.5, 'miles y decimales');
es('1.500,50', 1500.5, 'idem');
es('1.000.000', 1000000, 'separador repetido = miles');
es('5,00', 5, 'dos decimales a cero');
es('.5', 0.5, 'sin parte entera');
es(',75', 0.75, 'idem con coma');
es('€ 79.000', 79000, 'con simbolo de moneda delante');
es('1 500', 1500, 'con espacio de miles');
es('0', 0, 'cero es un importe, no un vacio');
es(null, null, 'null entra, null sale');
es(undefined, null, 'idem');

// ── Signo, que es lo que fallaba ──────────────────────────────────────────
es('-1.500,50', -1500.5, 'negativo con miles y decimales');
es('- 200', -200, 'con espacio tras el signo');
es('200-', 200, 'un guion al final no es un negativo');

/* ══════════════════════════════════════════════════════════════════════════
   ESCRIBIR un importe — 17-ago-2026 (auditoria)
   ══════════════════════════════════════════════════════════════════════════
   Los tres primeros casos son las divergencias MEDIDAS entre `fmtMoneda` de
   facturas y el `toLocaleString('es')` de Compradores y del Panel. Estan aqui
   por lo mismo que los de arriba: para que ninguna de las dos vuelva.
   El cuarto es el que de verdad no era estetico — la rupia no tiene centimos. */
function fue(n, moneda, esperado, porque){
  const dio = fmt(n, moneda);
  if(dio !== esperado){ fallos++; console.error(`  FALLA  ${n} ${moneda} → "${dio}", se esperaba "${esperado}"\n         ${porque}`); }
}

fue(1234.5,       'EUR', '1.234,50 EUR',     'dos decimales siempre; Compradores daba "1234,5"');
fue(164000,       'EUR', '164.000,00 EUR',   'el precio de una villa real; daba "164.000" sin centimos');
fue(1234567.891,  'EUR', '1.234.567,89 EUR', 'se redondea a la moneda; daba tres decimales');
fue(5000000,      'IDR', '5.000.000 IDR',    'la rupia NO tiene centimos: cero decimales');
fue(1500,         'EUR', '1.500,00 EUR',     'agrupa tambien a cuatro cifras (de-DE, no es-ES)');
fue(0,            'EUR', '0,00 EUR',         'cero es un importe y se imprime');
fue(null,         'EUR', '0,00 EUR',         'sin dato imprime cero: quien no quiera eso comprueba antes');
fue(-5000,        'EUR', '-5.000,00 EUR',    'el signo se conserva, igual que al leer');
fue(99,           '',    '99,00',            'sin moneda no inventa ninguna');
fue(12.345,       'USD', '12,35 USD',        'redondea al alza; Compradores imprimia "12,345"');

if(fallos){ console.error(`\ndinero.test.js — ${fallos} fallo(s)`); process.exit(1); }
console.log('OK dinero.test.js — 32 casos: 22 al leer un importe y 10 al escribirlo');
