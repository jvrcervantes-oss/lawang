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
new Function('exports', extrae('verifica') + extrae('enCadena') + extrae('guardaReparto') +
  'exports.verifica=verifica;exports.enCadena=enCadena;exports.guardaReparto=guardaReparto;')(ctx);

const win = {};
new Function('window', NOTA)(win);
const nota = win.lwNotaCuenta;

/* Cliente de mentira: apunta cada escritura y devuelve las filas que se le digan.
   `filas: []` es el caso que importa — la RLS denegando en silencio. */
function clienteFalso(filas) {
  const log = [];
  return {
    log,
    from(tabla) {
      const q = { _t: tabla, _f: {}, _op: null, _d: null };
      q.select = () => q;
      q.eq = (k, v) => { q._f[k] = v; return q; };
      q.insert = d => { q._op = 'insert'; q._d = d; return q; };
      q.update = d => { q._op = 'update'; q._d = d; return q; };
      q.delete = () => { q._op = 'delete'; return q; };
      q.then = ok => {
        log.push({ tabla, op: q._op, filtro: q._f, datos: q._d });
        return Promise.resolve(ok({ data: filas === undefined ? [{ clave: 'x' }] : filas, error: null }));
      };
      return q;
    }
  };
}
const resumen = l => l.map(x => x.op + ':' + (x.datos && x.datos.clave || x.filtro.clave || '') +
  (x.op === 'update' ? '(' + JSON.stringify(x.datos) + ')' : '')).join(' ');

(async function () {
  const ANTES = [
    { slug: 'carta_reserva', clave: 'tepi_sungai', es_default: true },
    { slug: 'carta_reserva', clave: 'land_balian', es_default: false }
  ];

  // 1 — no tocar nada no escribe nada. Un cajón abierto y cerrado con «Guardar»
  //     no puede dejar rastro en una tabla que decide el destino del dinero.
  let sb = clienteFalso();
  assert.strictEqual(await ctx.guardaReparto(sb, 'plantilla_cuentas', { slug: 'carta_reserva' },
    ANTES, { claves: ['tepi_sungai', 'land_balian'], def: 'tepi_sungai' }), null);
  assert.strictEqual(sb.log.length, 0, 'escribió sin que cambiara nada: ' + resumen(sb.log));
  console.log('✓ sin cambios no se escribe nada');

  // 2 — añadir una y quitar otra: exactamente un insert y un delete
  sb = clienteFalso();
  await ctx.guardaReparto(sb, 'plantilla_cuentas', { slug: 'carta_reserva' },
    ANTES, { claves: ['tepi_sungai', 'notario_ayu'], def: 'tepi_sungai' });
  assert.strictEqual(sb.log.length, 2, 'escrituras de más o de menos: ' + resumen(sb.log));
  const del = sb.log.find(x => x.op === 'delete'), ins = sb.log.find(x => x.op === 'insert');
  assert.strictEqual(del.filtro.clave, 'land_balian');
  assert.strictEqual(del.filtro.slug, 'carta_reserva', 'el borrado no se acotó a este contrato');
  assert.strictEqual(ins.datos.clave, 'notario_ayu');
  assert.strictEqual(ins.datos.slug, 'carta_reserva');
  console.log('✓ un insert y un delete, y los dos acotados a su contrato');

  // 3 — cambiar la precargada es UN update. El trigger `un_solo_default_por_plantilla`
  //     desmarca sola a la anterior: dos sentencias en orden serían una carrera.
  sb = clienteFalso();
  await ctx.guardaReparto(sb, 'plantilla_cuentas', { slug: 'carta_reserva' },
    ANTES, { claves: ['tepi_sungai', 'land_balian'], def: 'land_balian' });
  assert.strictEqual(sb.log.length, 1, resumen(sb.log));
  assert.strictEqual(sb.log[0].op, 'update');
  assert.strictEqual(sb.log[0].datos.es_default, true);
  assert.strictEqual(sb.log[0].filtro.clave, 'land_balian');
  console.log('✓ cambiar la precargada es un solo update (lo demás lo hace el trigger)');

  // 4 — «ninguna precargada» va explícita y ACOTADA al contrato: no hay trigger
  //     que desmarque, y sin el `.eq(slug)` dejaría sin precarga a los otros 7.
  sb = clienteFalso();
  await ctx.guardaReparto(sb, 'plantilla_cuentas', { slug: 'carta_reserva' },
    ANTES, { claves: ['tepi_sungai', 'land_balian'], def: null });
  assert.strictEqual(sb.log.length, 1, resumen(sb.log));
  assert.strictEqual(sb.log[0].datos.es_default, false);
  assert.strictEqual(sb.log[0].filtro.slug, 'carta_reserva', 'desmarcó la precarga de TODA la tabla');
  assert.strictEqual(sb.log[0].filtro.es_default, true);
  console.log('✓ «ninguna precargada» se acota a su contrato');

  // 5 — si la precargada se QUITA del reparto, no queda update huérfano: la fila
  //     ya no existe y el update daría cero filas, que aquí significa «denegado».
  sb = clienteFalso();
  await ctx.guardaReparto(sb, 'plantilla_cuentas', { slug: 'carta_reserva' },
    ANTES, { claves: ['land_balian'], def: null });
  assert.ok(!sb.log.some(x => x.op === 'update'),
    'dejó un update contra la fila que acababa de borrar: ' + resumen(sb.log));
  assert.strictEqual(sb.log.length, 1, resumen(sb.log));
  console.log('✓ quitar la precargada no deja un update contra una fila borrada');

  // 6 — el nivel de proyecto lleva DOS columnas en el filtro y en el insert, y
  //     salen de la misma definición: dos listas a mano acabarían separándose.
  sb = clienteFalso();
  await ctx.guardaReparto(sb, 'proyecto_cuentas', { proyecto_id: 'p1', slug: '*' },
    [], { claves: ['notario_wiryasa'], def: null });
  assert.strictEqual(sb.log[0].datos.proyecto_id, 'p1');
  assert.strictEqual(sb.log[0].datos.slug, '*');
  console.log('✓ la excepción por proyecto escribe proyecto_id y slug');

  // 7 — CERO FILAS SIN ERROR = LA RLS LO PARÓ. Nunca «guardado».
  sb = clienteFalso([]);
  const r = await ctx.guardaReparto(sb, 'plantilla_cuentas', { slug: 'carta_reserva' },
    ANTES, { claves: ['tepi_sungai', 'land_balian', 'notario_ayu'], def: 'tepi_sungai' });
  assert.ok(r && r.error, 'un insert de CERO filas se dio por bueno');
  assert.ok(/no tienes permiso/.test(r.error.message), r.error.message);
  console.log('✓ 0 filas sin error se lee como denegado');

  // 8 — y la cadena se PARA en la primera que falla: no sigue escribiendo detrás
  //     de una denegación, que dejaría el reparto a medias.
  sb = clienteFalso([]);
  await ctx.guardaReparto(sb, 'plantilla_cuentas', { slug: 'carta_reserva' },
    ANTES, { claves: ['notario_ayu'], def: 'notario_ayu' });
  assert.strictEqual(sb.log.length, 1, 'siguió escribiendo tras una denegación: ' + resumen(sb.log));
  console.log('✓ la cadena se para en la primera escritura denegada');

  // 9 — la nota del contrato: las tres formas que de verdad hay en la base
  assert.strictEqual(nota.aJson({ es: '', en: '', id: '' }), '',
    'sin nota debe guardarse cadena vacía: la fila «Nota» no se imprime');
  assert.strictEqual(nota.aJson({ es: 'Pago en IDR', en: '', id: '' }), 'Pago en IDR',
    'con un solo idioma se guarda texto plano, como estaba');
  assert.deepStrictEqual(nota.aJson({ es: 'Pago en IDR', en: 'Payment in IDR', id: '' }),
    { es: 'Pago en IDR', en: 'Payment in IDR', id: 'Pago en IDR' },
    'el idioma que falta debe caer al español, no salir en blanco en un contrato firmado');
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
