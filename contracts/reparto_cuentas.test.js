/* node contracts/reparto_cuentas.test.js
   QUÉ CUENTAS OFRECE CADA CONTRATO — la función que decide el destino del dinero.

   Existe porque el 14-sep-2026 esa decisión salió de cuatro listas escritas a
   mano en JavaScript (`BANCOS_CONSTRUCCION`, `BANCOS_CC00014_TIMON`,
   `BANCO_UNICO` y `CUENTA_DEFAULT`) y pasó a una tabla que el super admin edita
   desde /intranet/cuentas/. El cambio es bueno —cambiar de cuenta ya no exige un
   despliegue— pero mueve el fallo de sitio: antes una lista mal escrita se veía
   en el diff, y ahora `bankOptionsFor` es un filtro que depende de un dato que
   llega por red.

   Los tres modos de fallo que esto fija, y por qué cada uno importa:
   · **Filtrar mal** = ofrecerle al agente una cuenta que este documento nunca
     pactó, o esconderle la única que debía usar.
   · **Degradarse a CERO** cuando el mapeo no ha cargado = un desplegable vacío
     donde va el destino de una transferencia. De ahí se sale escribiendo una
     cuenta a mano, que es el fallo caro. Ante la duda se ofrecen TODAS: el
     agente elige, y elegir entre quince es recuperable; no tener ninguna, no.
   · **Precargar** una cuenta que no se ofrece = imprimir un destino de pago que
     el propio formulario no admite.

   Se extrae la función REAL de `assets/entidades_pago.js` y se evalúa. Probar una
   copia no probaría nada: el 14-ago un nombre de tipo de contrato escrito en dos
   sitios ya enseñó dos cosas distintas en dos pantallas.

   Corre SIN RED: el reparto va de fixture. Que las claves del fixture existan de
   verdad en `plantilla_cuentas` se comprueba contra la base, no aquí. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const SRC = fs.readFileSync(path.join(__dirname, 'assets', 'entidades_pago.js'), 'utf8');

/* Se recortan las dos funciones por su nombre y no se evalúa el fichero entero:
   `entidades_pago.js` toca `document` al cargarse (el listener que repinta el
   resumen de sección), y aquí no hay DOM. */
function extrae(nombre, hasta) {
  const desde = SRC.indexOf('function ' + nombre + '(');
  assert.ok(desde > 0, nombre + ' ya no está en entidades_pago.js: este test quedó ciego');
  const fin = SRC.indexOf(hasta, desde);
  assert.ok(fin > desde, 'no se encuentra el final de ' + nombre);
  return SRC.slice(desde, fin);
}
const codigo =
  'const bankOptions = () => Object.entries(CUENTAS_BANCARIAS).map(([v,c])=>[v,c.label])' +
  "  .sort((a,b)=>a[1].localeCompare(b[1],'es'));\n" +
  extrae('bankOptionsFor', '/* La cuenta precargada') +
  extrae('bankDefaultFor', '/* ---------- sociedad firmante');

/* El estado REAL sembrado el 14-sep, reducido a lo que estas funciones miran.
   Si mañana el owner cambia el reparto desde el panel, este fixture NO se queda
   viejo: no es una copia de la base, es el caso que fija la FORMA de la regla. */
const CUENTAS = {
  contractor_tepisungai:    'Tepi Sun Gai — OCBC',
  sandalwoods_dbs_sg:       'Sandal Woods Limited — DBS Bank Ltd (Singapur)',
  sandalwoods_danamon_eur:  'PT SAN DAL WOODS — Bank Danamon, EUR (Badung)',
  notario_sandy_sumba:      'Notario — Sandy Tandean, Sumba (BNI)',
  contractor_sumba_eur:     'Constructor — Sumba, EUR (Achmad Zaeni · Bank Mandiri)',
  land_balian_usd:          'Terreno — Balian Hills, USD (Lead Bank)',
};
const CUENTAS_BANCARIAS = {};
Object.entries(CUENTAS).forEach(([k, label]) => { CUENTAS_BANCARIAS[k] = { label: label }; });

const PLANTILLA_CUENTAS = {
  // la Carta cobra SIEMPRE en la misma, y precargada (owner, 8-sep-2026)
  carta_reserva:     { claves: ['contractor_tepisungai'], porDefecto: 'contractor_tepisungai' },
  // Construcción: sus cuatro vías, sin precarga
  ppjb_construccion: { claves: ['sandalwoods_dbs_sg', 'sandalwoods_danamon_eur',
                                'notario_sandy_sumba', 'contractor_sumba_eur'], porDefecto: '' },
  // el caso nuevo que antes no podía existir: alguien lo desmarcó todo
  ppjb_reserva:      { claves: [], porDefecto: '' },
};

const hecho = new Function('CUENTAS_BANCARIAS', 'PLANTILLA_CUENTAS',
  codigo + '\n;return { bankOptionsFor, bankDefaultFor };')(CUENTAS_BANCARIAS, PLANTILLA_CUENTAS);
const { bankOptionsFor, bankDefaultFor } = hecho;

const claves = (slug) => bankOptionsFor(slug).map((o) => o[0]).sort();

/* ---- 1. filtra por lo que dice la tabla, exactamente ---- */
assert.deepStrictEqual(claves('carta_reserva'), ['contractor_tepisungai'],
  'la Carta de Reserva ofrece UNA cuenta: la que el owner marcó, y ninguna más');
assert.deepStrictEqual(claves('ppjb_construccion'),
  ['contractor_sumba_eur', 'notario_sandy_sumba', 'sandalwoods_danamon_eur', 'sandalwoods_dbs_sg'],
  'Construcción ofrece sus cuatro vías');
assert.ok(!claves('ppjb_construccion').includes('land_balian_usd'),
  'una cuenta que no está marcada NO se ofrece: sería un destino que este contrato no pactó');

/* ---- 2. ordena por etiqueta, no por clave ---- */
const etiquetas = bankOptionsFor('ppjb_construccion').map((o) => o[1]);
assert.deepStrictEqual(etiquetas, [...etiquetas].sort((a, b) => a.localeCompare(b, 'es')),
  'el desplegable va alfabético por lo que se LEE, que es como lo busca el agente');

/* ---- 3. una plantilla sin cuentas marcadas ofrece CERO, y lo hace a propósito ----
   No se rellena con todas «por si acaso»: el owner desmarcó a conciencia, y
   ofrecer lo contrario de lo que dice el panel es peor que no ofrecer nada.
   Quien abra ese contrato recibe un aviso (ver app.html). */
assert.deepStrictEqual(claves('ppjb_reserva'), [],
  'una plantilla con la lista vacía en la tabla no ofrece ninguna cuenta');

/* ---- 4. y si el MAPEO no ha cargado, se ofrecen TODAS ---- */
const sinMapeo = new Function('CUENTAS_BANCARIAS', 'PLANTILLA_CUENTAS',
  codigo + '\n;return bankOptionsFor;')(CUENTAS_BANCARIAS, {});
assert.strictEqual(sinMapeo('carta_reserva').length, Object.keys(CUENTAS).length,
  'sin mapeo cargado se ofrecen TODAS las activas, nunca cero: un select vacío donde va el ' +
  'destino de una transferencia acaba en una cuenta escrita a mano');
// y la diferencia entre los dos casos es real, no un matiz: «vacío porque lo
// desmarcaron» y «vacío porque no cargó» tienen que dar resultados distintos
assert.notStrictEqual(claves('ppjb_reserva').length, sinMapeo('ppjb_reserva').length,
  'desmarcado a mano y no-cargado NO pueden comportarse igual');

/* ---- 5. la precargada ---- */
assert.strictEqual(bankDefaultFor('carta_reserva'), 'contractor_tepisungai',
  'la Carta precarga la cuenta que el owner marcó');
assert.strictEqual(bankDefaultFor('ppjb_construccion'), '',
  'sin precargada marcada no se adivina ninguna: la norma de entidades_pago.js');
assert.strictEqual(bankDefaultFor('no_existe'), '',
  'una plantilla desconocida no precarga nada, y no revienta');
// invariante que la base garantiza con una clave ajena y aquí se dice en voz
// alta: precargar lo que no se ofrece imprimiría un destino que el formulario
// no admite
Object.keys(PLANTILLA_CUENTAS).forEach((slug) => {
  const def = bankDefaultFor(slug);
  if (def) assert.ok(claves(slug).includes(def),
    slug + ': la cuenta precargada tiene que estar entre las ofrecidas');
});

/* ---- 6. las listas a mano no han vuelto ----
   Se miran sobre el código SIN COMENTARIOS, y es la diferencia entre un guardián
   y un estorbo: los cuatro nombres siguen escritos en los comentarios a
   propósito —explican qué había antes aquí y por qué se fue—, y un check que los
   confunda con código falla el primer día y se desactiva el segundo. Misma
   lección que `tools/no_destruir.py` pagó dos veces (11-sep-2026). */
const sinComentarios = (s) => s.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/[^\n]*/g, ' ');
const CODIGO_PAGO = sinComentarios(SRC);
const CODIGO_APP = sinComentarios(fs.readFileSync(path.join(__dirname, 'app.html'), 'utf8'));
for (const muerta of ['BANCOS_CONSTRUCCION', 'BANCOS_CC00014_TIMON', 'BANCO_UNICO']) {
  assert.ok(!new RegExp('const\\s+' + muerta + '\\s*=').test(CODIGO_PAGO),
    muerta + ' ha vuelto a entidades_pago.js: el reparto vive en `plantilla_cuentas`, ' +
    'y dos sitios decidiendo qué cuentas se ofrecen es el bug que este cambio cerró');
}
assert.ok(!/const\s+CUENTA_DEFAULT\s*=/.test(CODIGO_APP),
  'CUENTA_DEFAULT ha vuelto a app.html: la precarga la decide el panel, no el código');

console.log('reparto_cuentas.test.js OK · bankOptionsFor y bankDefaultFor leen la tabla,');
console.log('  degradan a TODAS si el mapeo no cargó, y las cuatro listas a mano siguen fuera.');
