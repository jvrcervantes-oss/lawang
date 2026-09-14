/* node contracts/destinos_firmado.test.js
   A quién se le manda el contrato FIRMADO cuando se cierra la última firma.

   Existe por un caso real: CR00056 se firmó el 11-sep-2026 y la copia salió
   SOLO al estudio. La compradora tenía el email únicamente en su fila de firma
   (`contrato_firmas.firmante_email`, tecleado por el agente al generar el
   enlace) y no en el contrato (`fields.adq1_email` estaba vacío). El reparto
   miraba una sola de las dos listas, así que se quedó sin destinatarios y nadie
   se enteró: el estudio recibió su copia y la clienta no. Mismo caso en PA00006.

   Lo que se prueba, y por qué cada cosa:
   · que el firmante entra aunque el contrato NO tenga su email — el fallo real;
   · que el comprador SIN firma electrónica sigue entrando (firma en papel);
   · que nadie recibe dos correos porque su dirección esté en las dos listas,
     ni por diferencias de mayúsculas o espacios — un contrato duplicado en la
     bandeja del cliente parece un error de facturación;
   · que el estudio va siempre y va primero;
   · que una dirección inválida o vacía se descarta en vez de reventar el envío
     de los demás (el bucle es secuencial: un destino malo al principio se
     llevaba por delante a los que venían detrás).

   `destinosFirmado` se importa del fichero real de la Edge, transpilando solo
   lo justo: probar una copia pegada aquí no probaría nada. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const ts = fs.readFileSync(
  path.join(__dirname, '..', 'supabase', 'functions', 'firma-submit', 'index.ts'), 'utf8');

const desde = ts.indexOf('const EMAIL_OK =');
assert.ok(desde > 0, 'EMAIL_OK ya no está en firma-submit: este test quedó ciego');
const hasta = ts.indexOf('\n/* El contrato firmado', desde);
assert.ok(hasta > desde, 'no se encuentra el final de destinosFirmado: este test quedó ciego');

// Deno/TS → JS: fuera las anotaciones de tipo, que es lo único de TS que usa.
const fuente = ts.slice(desde, hasta)
  .replace(/^export /m, '')
  .replace(/: \{ to: string; nombre\?: string; estudio: boolean \}\[\]/g, '')
  .replace(/new Set<string>\(\)/g, 'new Set()')
  .replace(/\(email: unknown, nombre: unknown, estudio: boolean\)/g, '(email, nombre, estudio)')
  .replace(/^\s*(estudioEmail|compradores|firmantes): [^,]+,$/gm, (m) => m.replace(/:.*,$/, ','));

const destinosFirmado = new Function(fuente + '\nreturn destinosFirmado;')();

const ESTUDIO = 'jcervantes@lawangproperties.com';

/* ---- 1. el caso CR00056: el email vive SOLO en la firma ---- */
const caso = destinosFirmado(
  ESTUDIO,
  [{ nombre: 'ANA BELÉN CASTELLANO PÉREZ', email: '' }],
  [{ nombre: 'ANA BELÉN CASTELLANO PÉREZ', email: 'anabelcp86@gmail.com' }],
);
assert.ok(caso.some(d => d.to === 'anabelcp86@gmail.com' && !d.estudio),
  'la firmante NO recibe su copia cuando el contrato no trae su email — es el fallo de CR00056');
assert.strictEqual(caso.length, 2, 'destinos inesperados: ' + JSON.stringify(caso));

/* ---- 2. firma en papel: el comprador está solo en el contrato ---- */
const papel = destinosFirmado(ESTUDIO, [{ nombre: 'Rubén', email: 'ruben@ejemplo.com' }], []);
assert.ok(papel.some(d => d.to === 'ruben@ejemplo.com'),
  'el comprador sin firma electrónica se queda sin copia');

/* ---- 3. nadie recibe dos veces lo mismo ---- */
const doble = destinosFirmado(
  ESTUDIO,
  [{ nombre: 'Ana', email: 'Ana@Ejemplo.com' }],
  [{ nombre: 'Ana Ruiz', email: '  ana@ejemplo.com  ' }],
);
assert.strictEqual(doble.filter(d => d.to.toLowerCase().trim() === 'ana@ejemplo.com').length, 1,
  'la misma dirección sale dos veces (mayúsculas/espacios): ' + JSON.stringify(doble));
// y el estudio tampoco se duplica si coincide con un comprador
const solapa = destinosFirmado(ESTUDIO, [{ nombre: 'Estudio', email: ESTUDIO }], []);
assert.strictEqual(solapa.length, 1, 'el estudio se duplica al coincidir con un comprador');
assert.strictEqual(solapa[0].estudio, true, 'el correo del estudio se degrada a correo de comprador');

/* ---- 4. el estudio va siempre y va primero ---- */
for (const [comp, firm, caso_] of [
  [[], [], 'sin nadie'],
  [[{ nombre: 'X', email: 'x@ejemplo.com' }], [], 'con comprador'],
  [[], [{ nombre: 'Y', email: 'y@ejemplo.com' }], 'con firmante'],
]) {
  const r = destinosFirmado(ESTUDIO, comp, firm);
  assert.strictEqual(r[0] && r[0].to, ESTUDIO, 'el estudio no es el primer destino (' + caso_ + ')');
  assert.strictEqual(r[0].estudio, true, 'el destino del estudio no va marcado (' + caso_ + ')');
}

/* ---- 5. direcciones que no valen se descartan, no revientan ---- */
const sucio = destinosFirmado(ESTUDIO,
  [{ nombre: 'A', email: null }, { nombre: 'B', email: 'sin-arroba' }, { nombre: 'C' }, null],
  [{ nombre: 'D', email: '   ' }, undefined, { nombre: 'E', email: 'e@ejemplo.com' }]);
assert.deepStrictEqual(sucio.map(d => d.to), [ESTUDIO, 'e@ejemplo.com'],
  'una dirección inválida se cuela o se lleva por delante a las buenas: ' + JSON.stringify(sucio));

console.log('OK  destinos del contrato firmado: 5 escenarios, unión comprador+firmante sin duplicados');
