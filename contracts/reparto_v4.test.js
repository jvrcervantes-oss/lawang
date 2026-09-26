/* node contracts/reparto_v4.test.js
   EL DIFF DEL REPARTO DE CUENTAS EN LA v4, Y LA NOTA QUE SE IMPRIME EN EL CONTRATO.

   Existe porque el 18-sep-2026 /intranet/v4/cuentas/ dejó de ser una pantalla de
   mirar: ahora escribe en `plantilla_cuentas`, `proyecto_cuentas`,
   `plantillas_contrato` y `cuentas_bancarias` — las cuatro tablas que deciden
   ADÓNDE TRANSFIERE EL COMPRADOR. La herramienta viva guarda casilla a casilla; la
   v4 es un cajón con un botón, así que hay un DIFF en medio, y un diff mal hecho
   no da error: deja el reparto distinto de lo que la pantalla enseñaba.

   Los cuatro modos de fallo que esto fija:
   · **Borrar de más o insertar de más** — quitarle a un contrato una cuenta que
     nadie tocó, o dejarle una que se había desmarcado.
   · **Precargar una fila que ya no existe** — si la precargada se quita del
     reparto, el UPDATE de `es_default` iría contra una fila recién borrada. No es
     un error de Postgres: es un update de cero filas, que aquí se lee como «la
     RLS te ha denegado» y asustaría con un mensaje falso.
   · **0 FILAS SIN ERROR = DENEGADO.** La RLS de estas cuatro tablas deniega
     devolviendo cero filas y sin lanzar. Sin `verifica`, a un admin que no es
     super admin el cajón le diría «guardado» sin haber guardado: se iría creyendo
     que la cuenta de cobro del comprador es otra.
   · **La nota en el idioma equivocado** — `cuentas_bancarias.extra` es texto
     suelto o {es,en,id}, y esa conversión la comparten la herramienta viva y la
     v4 desde `contracts/assets/nota_cuenta.js`. Si divergen, un contrato en
     inglés imprime la nota en español.

   Desde el 26-sep-2026 (LAW-336 pieza 4) la pantalla ya no escribe: manda cada
   nivel entero a `reparto_cuentas_guarda` y el servidor lo aplica en una
   transacción. Lo que queda en el navegador es `nivelReparto`, que decide QUÉ
   se manda — y eso es lo que se prueba aquí (el servidor, en la migración).

   Se extraen las funciones REALES de `intranet/v4/assets/editores.js` y se evalúan
   con un cliente de Supabase de mentira que apunta lo que se le pide. Probar una
   copia no probaría nada. Corre SIN RED y SIN DOM: estas cuatro no tocan ninguno. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const SRC = fs.readFileSync(path.join(__dirname, '..', 'intranet', 'v4', 'assets', 'editores.js'), 'utf8');
const NOTA = fs.readFileSync(path.join(__dirname, 'assets', 'nota_cuenta.js'), 'utf8');

/* Recorte por llaves y no por una marca de texto: una marca obliga a tocar el
   test cada vez que se mueve la función de sitio, y un test que hay que retocar
   para que siga compilando es un test que se acaba desactivando. */
function extrae(nombre) {
  const desde = SRC.indexOf('function ' + nombre + '(');
  assert.ok(desde > 0, nombre + ' ya no está en editores.js: este test quedó ciego');
  let i = SRC.indexOf('{', desde), n = 0;
  for (let j = i; j < SRC.length; j++) {
    if (SRC[j] === '{') n++;
    else if (SRC[j] === '}' && --n === 0) return SRC.slice(desde, j + 1);
  }
  assert.fail('no se encuentra el final de ' + nombre);
}

const ctx = {};
new Function('exports', extrae('nivelReparto') + 'exports.nivelReparto=nivelReparto;')(ctx);

const win = {};
new Function('window', NOTA)(win);
const nota = win.lwNotaCuenta;

(async function () {
  const ANTES = [
    { slug: 'carta_reserva', clave: 'tepi_sungai', es_default: true },
    { slug: 'carta_reserva', clave: 'land_balian', es_default: false }
  ];
  const nivel = ctx.nivelReparto;

  // 1 — no tocar nada no manda nada. Un cajón abierto y cerrado con «Guardar»
  //     no puede dejar rastro en una tabla que decide el destino del dinero.
  assert.strictEqual(nivel({ slug: 'carta_reserva' }, ANTES,
    { claves: ['land_balian', 'tepi_sungai'], def: 'tepi_sungai' }), null,
    'el mismo conjunto en otro orden se tomó por un cambio');
  console.log('✓ sin cambios no se manda nada (el orden no cuenta)');

  // 2 — se manda el conjunto ENTERO tras el cambio, no el diff: el servidor lo
  //     aplica en una transacción y no queda un reparto a medias.
  let n = nivel({ slug: 'carta_reserva' }, ANTES, { claves: ['tepi_sungai', 'notario_ayu'], def: 'tepi_sungai' });
  assert.deepStrictEqual(n.claves, ['tepi_sungai', 'notario_ayu']);
  assert.strictEqual(n.slug, 'carta_reserva');
  assert.strictEqual(n.proyecto_id, undefined, 'la regla general no lleva proyecto');
  console.log('✓ se manda el conjunto entero del nivel');

  // 3 — `antes` viaja siempre: con él el servidor para si alguien cambió el
  //     reparto mientras el cajón estaba abierto, en vez de pisarlo.
  assert.deepStrictEqual(n.antes, ['tepi_sungai', 'land_balian']);
  console.log('✓ viaja lo que había, para que el servidor detecte un cambio ajeno');

  // 4 — cambiar solo la precargada también es un cambio
  n = nivel({ slug: 'carta_reserva' }, ANTES, { claves: ['tepi_sungai', 'land_balian'], def: 'land_balian' });
  assert.ok(n && n.def === 'land_balian', 'cambiar la precargada no se mandó');
  console.log('✓ cambiar la precargada se manda');

  // 5 — «ninguna precargada» es def null explícito, no «sin cambios»
  n = nivel({ slug: 'carta_reserva' }, ANTES, { claves: ['tepi_sungai', 'land_balian'], def: undefined });
  assert.ok(n && n.def === null, 'quitar la precarga no se mandó como null');
  console.log('✓ «ninguna precargada» se manda como null');

  // 6 — el nivel de proyecto lleva proyecto_id y slug de la misma definición
  n = nivel({ proyecto_id: 'p1', slug: '*' }, [], { claves: ['notario_wiryasa'], def: null });
  assert.strictEqual(n.proyecto_id, 'p1');
  assert.strictEqual(n.slug, '*');
  console.log('✓ la excepción por proyecto lleva proyecto_id y slug');

  // 7 — no comparte el array de la pantalla: mutarlo después no cambia lo enviado
  const ahora = { claves: ['a1'], def: null };
  n = nivel({ slug: 's' }, [], ahora);
  ahora.claves.push('a2');
  assert.deepStrictEqual(n.claves, ['a1']);
  console.log('✓ lo enviado es una copia');

  // 9 — la nota del contrato: las tres formas que de verdad hay en la base
  assert.strictEqual(nota.aJson({ es: '', en: '', id: '' }), '',
    'sin nota debe guardarse cadena vacía: la fila «Nota» no se imprime');
  assert.strictEqual(nota.aJson({ es: 'Pago en IDR', en: '', id: '' }), 'Pago en IDR',
    'con un solo idioma se guarda texto plano, como estaba');
  assert.deepStrictEqual(nota.aJson({ es: 'Pago en IDR', en: 'Payment in IDR', id: '' }),
    { es: 'Pago en IDR', en: 'Payment in IDR', id: '' },
    'LAW-247: el bahasa que falta se queda vacío, nunca cae al español — el ' +
    'bahasa prevalece legalmente y una copia disfrazada de traducción es peor ' +
    'que un hueco visible');
  assert.deepStrictEqual(nota.aJson({ es: 'Pago en IDR', en: '', id: 'Pembayaran dalam IDR' }),
    { es: 'Pago en IDR', en: 'Pago en IDR', id: 'Pembayaran dalam IDR' },
    'el inglés que falta SÍ sigue cayendo al español (fuera de alcance de LAW-247); ' +
    'el bahasa que sí se escribió se conserva tal cual');
  assert.deepStrictEqual(nota.lee({ es: 'a', en: 'b' }), { es: 'a', en: 'b', id: '' });
  assert.deepStrictEqual(nota.lee('texto viejo'), { es: 'texto viejo', en: '', id: '' },
    'no sabe leer la nota de texto plano que ya está en la base');
  assert.deepStrictEqual(nota.lee(null), { es: '', en: '', id: '' });
  // ida y vuelta: lo que se lee y se vuelve a guardar sin tocar nada no cambia
  ['', 'Pago en IDR'].forEach(v => assert.strictEqual(nota.aJson(nota.lee(v)), v,
    'leer y volver a guardar sin tocar nada cambió la nota: ' + JSON.stringify(v)));
  console.log('✓ la nota del contrato: vacía, plana, y los tres idiomas con respaldo');

  console.log('\nreparto_v4: todo OK');
})().catch(e => { console.error('\n✗ ' + (e && e.message || e)); process.exit(1); });
