/* Test del lector de importes compartido. `node dinero.test.js`.
   ============================================================================
   Cada caso de la primera tabla es una DIVERGENCIA REAL medida el 17-ago-2026
   entre las dos implementaciones que habia. No son casos inventados: son los
   sitios exactos donde las dos versiones daban respuestas distintas sobre
   dinero, y estan aqui para que ninguna vuelva. */
const { lwParseImporte: p, lwFormatoImporte: fmt, lwImporteCanonico: canonFn,
        lwDescuentoCascada: cascada } = require('./dinero.js');

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

/* ══════════════════════════════════════════════════════════════════════════
   lwImporteCanonico — 17-sep-2026. Estaba sin test (el gemelo que SÍ lo tenía
   era lwFormatoImporte, de arriba). Los MISMOS 19 casos viven en el DO $$ de
   sql/carta_cobrado_al_bloquear.sql (lw_importe_texto, la versión de
   Postgres): si una de las dos deriva, uno de los dos tests lo caza. La
   rareza real (`Number(1234).toLocaleString('es-ES')` → "1234", sin punto —
   el separador de miles solo aparece desde 10.000) está aquí exactamente
   porque ya costó una lectura equivocada al escribir la versión de SQL. */
function canon(entrada, esperado, porque){
  const dio = canonFn(entrada);
  if(dio !== esperado){ fallos++; console.error(`  FALLA  lwImporteCanonico(${entrada}) → "${dio}", se esperaba "${esperado}"\n         ${porque}`); }
}
canon(0, '0', 'cero, sin decimales');
canon(1234, '1234', 'CUATRO cifras: es-ES en este runtime NO agrupa — nada de "1.234"');
canon(9999, '9999', 'el limite de abajo del hueco sin agrupar');
canon(10000, '10.000', 'CINCO cifras: aqui empieza a agrupar');
canon(54204, '54.204', 'un precio_total real (RP00164)');
canon(999999, '999.999', 'seis cifras, un solo punto');
canon(1234567890, '1.234.567.890', 'grupo de cabecera de 1 cifra, sigue agrupando igual');
canon(1.5, '1,50', 'decimal con coma, dos cifras siempre que haya parte fraccionaria');
canon(1234.5, '1234,50', 'con decimales pero SIN punto de miles (solo 4 cifras enteras)');
canon(99999.999, '100.000,00', 'el redondeo a 2 decimales cruza a 6 cifras: SÍ agrupa, Y lleva decimales — la decision de mostrar coma es del valor SIN redondear');
canon(9999.001, '9999,00', 'redondea a un entero de 4 cifras: sigue sin punto');

/* ══════════════════════════════════════════════════════════════════════════
   lwDescuentoCascada — el reparto del abono de la Carta de Reserva sobre los
   hitos del Bloqueo, 17-sep-2026. Gemelo del bucle en
   sql/carta_cobrado_al_bloquear.sql: mismos casos, para que ninguna de las
   dos copias derive de la otra sin que un test lo note. */
(function(){
  const c1 = cascada(['24.250','24.250'], 1000);
  if(c1[0] !== '23.250' || c1[1] !== '24.250'){
    fallos++; console.error(`  FALLA  cascada(['24.250','24.250'], 1000) → ${JSON.stringify(c1)}, se esperaba ['23.250','24.250'] — el primer hito absorbe todo lo que quepa`);
  }
  const c2 = cascada(['500','24000'], 1000);
  if(c2[0] !== '0' || c2[1] !== '23.500'){
    fallos++; console.error(`  FALLA  cascada(['500','24000'], 1000) → ${JSON.stringify(c2)}, se esperaba ['0','23.500'] — agota el primero y sigue con el segundo`);
  }
  const c3 = cascada(['250','250'], 1000);
  if(c3[0] !== '0' || c3[1] !== '0'){
    fallos++; console.error(`  FALLA  cascada(['250','250'], 1000) → ${JSON.stringify(c3)}, se esperaba ['0','0'] — nunca baja de 0 aunque el descuento sobre`);
  }
  const c4 = cascada(['24.250','24.250'], 0);
  if(c4[0] !== '24.250' || c4[1] !== '24.250'){
    fallos++; console.error(`  FALLA  cascada(['24.250','24.250'], 0) → ${JSON.stringify(c4)}, se esperaba sin cambios`);
  }
  const c5 = cascada(['10.000','10.000','10.000'], 15000);
  if(c5[0] !== '0' || c5[1] !== '5000' || c5[2] !== '10.000'){
    fallos++; console.error(`  FALLA  cascada(3 hitos, 15000) → ${JSON.stringify(c5)}, se esperaba ['0','5000','10.000'] — reparte entre dos y deja el tercero intacto (5000 sin punto: 4 cifras)`);
  }
})();

/* GUARDRAIL: toda funcion `lw*` del fichero tiene que salir por module.exports.
   Las tres de suma por moneda se escribieron DEBAJO del bloque de exports y se
   quedaron fuera sin sintoma: en el navegador son globales y funcionan, asi que
   lo unico que pasaba es que ningun test de node podia alcanzarlas. Un test que
   no puede ver una funcion es verde sobre nada. */
(function(){
  const src = require('fs').readFileSync(require('path').join(__dirname, 'dinero.js'), 'utf8');
  const declaradas = [...src.matchAll(/^function (lw\w+)/gm)].map(m => m[1]);
  const exportadas = Object.keys(require('./dinero.js'));
  const faltan = declaradas.filter(n => !exportadas.includes(n));
  if(faltan.length){
    fallos++;
    console.error('  FALLA  sin exportar: ' + faltan.join(', ') +
                  '\n         node no las ve, y su test correria por otro camino que produccion');
  }
})();

if(fallos){ console.error(`\ndinero.test.js — ${fallos} fallo(s)`); process.exit(1); }
console.log('OK dinero.test.js — 48 casos: 22 al leer un importe, 10 al escribirlo, 11 de lwImporteCanonico y 5 de lwDescuentoCascada');
