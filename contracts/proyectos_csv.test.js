/* node contracts/proyectos_csv.test.js
   Las reglas del import de inventario, que son las que costaron tres incidentes
   —cada uno perdiendo columnas EN SILENCIO— y ahora viven en un solo sitio.

   Se prueba lo que se rompió de verdad, no el parser genérico:
   los alias de Notion, el «m²», la coincidencia de nombre de proyecto, las dos
   columnas que un CSV NO puede tocar, y que «sin dato» no borre una columna. */
const assert = require('assert');
const path = require('path');
const { lwCsvParse, lwCsvNormCab, lwCsvAntiFormula, lwCsvAnaliza, LW_CSV_COLUMNAS } =
  require(path.join(__dirname, 'assets', 'proyectos_csv.js'));
const { lwParseImporte } = require(path.join(__dirname, 'assets', 'dinero.js'));

const CTX = {
  tipos: ['parcela', 'villa'],
  proyectos: ['Bonian Village', 'Sumba Hills'],
  existentes: new Set(['Sumba Hills SH-1']),
  parseImporte: lwParseImporte,
};

let fallos = 0;
const ok = (t, f) => { try { f(); console.log('  ok   ' + t); }
                       catch (e) { fallos++; console.log('  FALLA ' + t + '\n         ' + e.message); } };

ok('parser RFC4180: comas, comillas y saltos DENTRO de un campo', () => {
  const f = lwCsvParse('a,b\n"uno, con coma","dos\ncon salto"\n');
  assert.deepStrictEqual(f, [['a','b'], ['uno, con coma', 'dos\ncon salto']]);
});

ok('"" es una comilla escapada, no el fin del campo', () => {
  assert.deepStrictEqual(lwCsvParse('x\n"di ""hola"""')[1], ['di "hola"']);
});

ok('🔴 «m²» con el superíndice llega a superficie_m2 (se perdía entera)', () => {
  assert.strictEqual(lwCsvNormCab('Superficie (m²)'), 'superficie_m2');
  assert.strictEqual(LW_CSV_COLUMNAS[lwCsvNormCab('m²')], 'superficie_m2');
});

ok('🔴 alias de Notion en inglés: Type / Land / Villa', () => {
  assert.strictEqual(LW_CSV_COLUMNAS[lwCsvNormCab('Type')], 'modelo');
  assert.strictEqual(LW_CSV_COLUMNAS[lwCsvNormCab('Land')], 'precio_suelo');
  assert.strictEqual(LW_CSV_COLUMNAS[lwCsvNormCab('Villa')], 'precio_construccion');
});

ok('🔴 alias con preposición del CSV «SUMBA PLOTS»', () => {
  assert.strictEqual(LW_CSV_COLUMNAS[lwCsvNormCab('Modelo de villa')], 'modelo');
  assert.strictEqual(LW_CSV_COLUMNAS[lwCsvNormCab('Precio de suelo')], 'precio_suelo');
  assert.strictEqual(LW_CSV_COLUMNAS[lwCsvNormCab('Precio de construcción')], 'precio_construccion');
});

ok('un CSV NO puede tocar `estado` ni `contrato_id`', () => {
  const claves = new Set(Object.values(LW_CSV_COLUMNAS));
  assert.ok(!claves.has('estado'), 'estado lo mueve el flujo de contratos, no una hoja de cálculo');
  assert.ok(!claves.has('contrato_id'));
  // y aunque el fichero traiga esas cabeceras, se ignoran
  const r = lwCsvAnaliza('codigo,proyecto,estado,contrato_id\nB1,Bonian Village,vendida,xxx\n', CTX);
  assert.ok(!('estado' in r.analizadas[0]));
  assert.ok(r.ignoradas.includes('estado') && r.ignoradas.includes('contrato_id'));
});

ok('el nombre del proyecto casa por contención y se guarda el DEL CATÁLOGO', () => {
  const r = lwCsvAnaliza('codigo,proyecto\nB1,Bonian Village by Balian Hills\n', CTX);
  assert.strictEqual(r.analizadas[0].proyecto, 'Bonian Village',
    'nunca el nombre del CSV: crearía una segunda variante del mismo proyecto');
  assert.deepStrictEqual(r.analizadas[0].errores, []);
});

ok('un proyecto que NO está en el catálogo es un error, no un alta a ciegas', () => {
  const r = lwCsvAnaliza('codigo,proyecto\nX1,Proyecto Fantasma\n', CTX);
  assert.ok(/no está en el catálogo/.test(r.analizadas[0].errores[0]));
  assert.strictEqual(r.validas.length, 0);
});

ok('distingue alta de actualización contra lo que ya existe', () => {
  const r = lwCsvAnaliza('codigo,proyecto\nSH-1,Sumba Hills\nSH-2,Sumba Hills\n', CTX);
  assert.strictEqual(r.actualiza, 1, 'SH-1 ya existe');
  assert.strictEqual(r.altas, 1, 'SH-2 es nueva');
});

ok('«sin dato» no puede borrar una columna que el CSV ni menciona', () => {
  const r = lwCsvAnaliza('codigo,proyecto\nB1,Bonian Village\n', CTX);
  assert.ok(!r.camposPresentes.has('modelo'),
    'si el CSV no trae `modelo`, al confirmar no se manda esa clave');
  assert.ok(r.camposPresentes.has('codigo') && r.camposPresentes.has('proyecto'));
});

ok('CSV/formula injection: un valor que empieza por = se neutraliza', () => {
  assert.strictEqual(lwCsvAntiFormula('=1+1'), "'=1+1");
  assert.strictEqual(lwCsvAntiFormula('normal'), 'normal');
  const r = lwCsvAnaliza('codigo,proyecto,notas\nB1,Bonian Village,=CMD()\n', CTX);
  assert.strictEqual(r.analizadas[0].notas, "'=CMD()");
});

ok('los importes pasan por lwParseImporte, no por Number()', () => {
  const r = lwCsvAnaliza('codigo,proyecto,precio\nB1,Bonian Village,"1.234.567,89"\n', CTX);
  assert.strictEqual(r.analizadas[0].precio, 1234567.89,
    'un importe con separadores europeos no puede acabar en NaN');
});

ok('un fichero vacío se DICE, no revienta', () => {
  assert.ok(/vac/i.test(lwCsvAnaliza('', CTX).error));
});

ok('sin las columnas obligatorias se dice cuáles faltan', () => {
  assert.ok(/codigo/.test(lwCsvAnaliza('otra,cosa\n1,2\n', CTX).error));
});

ok('la fila que se reporta es la del FICHERO, contando la cabecera', () => {
  const r = lwCsvAnaliza('codigo,proyecto\nB1,Bonian Village\nB2,Bonian Village\n', CTX);
  assert.deepStrictEqual(r.analizadas.map(x => x.fila), [2, 3]);
});

console.log(fallos ? `\n${fallos} fallo(s)` : '\nOK proyectos_csv.test.js — las reglas del import se sostienen');
process.exit(fallos ? 1 : 0);
