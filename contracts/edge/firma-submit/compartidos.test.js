/* ═══════════════════════════════════════════════════════════════════════════
   El paquete que la edge de firma lleva dentro, EVALUADO — 17-ago-2026
   `node compartidos.test.js`. Lo corre tools/test.py, y con él el gate de push.
   ═══════════════════════════════════════════════════════════════════════════
   POR QUÉ. Hasta hoy esta función se bajaba cinco `.js` de lawangproperties.com y
   los ejecutaba con `new Function`, teniendo la `service_role` en memoria
   (auditoría, hallazgo 01). Ahora el código viaja dentro, en
   `compartidos.generated.ts`, que genera `tools/empaqueta_edge.py`.

   Ese cambio mueve el riesgo de sitio si nadie comprueba dos cosas, y son
   exactamente las que este test comprueba:

     1. QUE EL PAQUETE SE EVALÚA FUERA DEL NAVEGADOR. Son ficheros pensados para
        una página HTML: si alguno tocara `document` o `window` al cargarse, la
        edge reventaría al emitir la primera factura — y se descubriría con un
        comprador esperando su documento, no aquí.
     2. QUE DEFINE TODO LO QUE LA EDGE LE PIDE. `EXPORTA` es la lista de nombres
        que `index.ts` saca a la caja. Si un fichero deja de definir uno,
        `Object.assign` lo pondría a `undefined` y la factura saldría a medias en
        vez de fallar: el peor modo de fallo de los dos.

   `empaqueta_edge.py --check` ya vigila que el paquete corresponda a los ficheros
   del repo. Eso es otra cosa: aquello compara textos, esto ejecuta.

   ⚠️ Estar en verde aquí NO significa que producción lo tenga. El paquete vive en
   el repo y la función que corre en Supabase es una copia subida aparte: hay que
   redesplegar, y comprobarlo leyendo la función desplegada. */
const fs = require('fs');
const path = require('path');

const TS = fs.readFileSync(path.join(__dirname, 'compartidos.generated.ts'), 'utf8');
let fallos = 0;
const falla = (que, detalle) => { fallos++; console.error(`  FALLA  ${que}\n         ${detalle}`); };

/* Se lee el array del `.ts` sin compilar nada: `JSON.stringify` escapa los saltos
   de línea, así que dentro de las cadenas NO hay ninguno literal — por eso
   `\n];` solo puede ser el cierre del array y el corte es inequívoco. Si el
   generador dejara de usar JSON, esto deja de encontrarlo y el test falla, que es
   lo correcto: no se puede validar un paquete que no se sabe leer. */
function arrayDe(nombre) {
  const marca = `export const ${nombre}: string[] = [`;
  const abre = TS.indexOf(marca);
  if (abre < 0) return null;
  /* El corchete de apertura es el ÚLTIMO de la marca, no el primero que aparezca
     después: `string[]` también lleva uno, y buscando `indexOf('[')` se empezaba a
     leer ahí — el `]` de la anotación de tipo entraba en el JSON y el parseo
     fallaba diciendo que el paquete tenía otra forma. */
  const desde = abre + marca.length - 1;
  const hasta = TS.indexOf('\n];', desde);
  if (hasta < 0) return null;
  const cuerpo = TS.slice(desde + 1, hasta)
    .replace(/\/\*[^*]*\*\//g, '')   // los comentarios /* ruta */ que intercala el generador
    .replace(/,\s*$/, '');           // y la coma final, que TypeScript admite y JSON no
  try { return JSON.parse('[' + cuerpo + ']'); }
  catch (e) { return null; }
}

const FUENTES = arrayDe('FUENTES');
const EXPORTA = arrayDe('EXPORTA');

if (!FUENTES || !EXPORTA) {
  falla('no he podido leer el paquete generado',
        'compartidos.generated.ts no tiene la forma que este test sabe leer. ¿Cambió empaqueta_edge.py?');
} else {
  if (FUENTES.length !== 5)
    falla(`el paquete trae ${FUENTES.length} ficheros y esperaba 5`,
          'si de verdad son otros tantos, cámbialo en empaqueta_edge.py Y aquí — pero míralo antes.');

  /* La evaluación, igual que la hace index.ts. Sin `document` ni `window`: si algo
     los tocara al cargarse, aquí se ve. */
  const caja = {};
  try {
    new Function('caja', FUENTES.join('\n;\n') +
      '\n;Object.assign(caja,{' + EXPORTA.join(',') + '});')(caja);
  } catch (e) {
    falla('el paquete no se puede evaluar fuera del navegador', String(e && e.message));
  }

  const sinDefinir = EXPORTA.filter((k) => caja[k] === undefined);
  if (sinDefinir.length)
    falla(`la edge pide ${EXPORTA.length} nombres y el paquete no define ${sinDefinir.length}`,
          'sin definir: ' + sinDefinir.join(', ') + ' → la factura saldría a medias en vez de fallar.');

  /* Y que además HACEN lo que la factura necesita. Tres comprobaciones, una por
     capa: leer un importe, escribirlo y sumar. Los valores son los de un contrato
     real (164.000 € de una villa) para que un fallo se lea como lo que es. */
  const prueba = (que, dio, esperado) => {
    if (dio !== esperado) falla(que, `dio ${JSON.stringify(dio)} y esperaba ${JSON.stringify(esperado)}`);
  };
  if (typeof caja.parseImporte === 'function') prueba('parseImporte("164.000")', caja.parseImporte('164.000'), 164000);
  if (typeof caja.fmtMoneda === 'function')    prueba('fmtMoneda(164000,"EUR")', caja.fmtMoneda(164000, 'EUR'), '164.000,00 EUR');
  if (typeof caja.fmtMoneda === 'function')    prueba('fmtMoneda(5000000,"IDR") — la rupia no tiene céntimos', caja.fmtMoneda(5000000, 'IDR'), '5.000.000 IDR');
  if (typeof caja.calcTotales === 'function')
    prueba('calcTotales de una línea sin impuesto',
           caja.calcTotales([{ descripcion: 'Total del proyecto', importe: '164000' }], 'EUR', { pct: '' }).total, 164000);
  if (typeof caja.documentoPagina !== 'function')
    falla('documentoPagina no es una función', 'es lo que maqueta el papel: sin ella no hay factura automática.');
}

if (fallos) {
  console.error(`\ncompartidos.test.js — ${fallos} fallo(s). La edge de firma no podría emitir`);
  console.error('la factura automática con este paquete.\n');
  process.exit(1);
}
console.log(`OK compartidos.test.js — ${FUENTES.length} ficheros empaquetados, ${EXPORTA.length} nombres definidos y evaluados sin navegador`);
