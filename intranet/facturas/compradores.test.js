/* node facturas/compradores.test.js — falla si la factura vuelve a salir
   a nombre de un solo comprador cuando el contrato va a varios. */
const assert = require('assert');
const { compradoresDeContrato, nombresFactura, documentosFactura, primerDato } = require('../../contracts/assets/compradores.js');

// caso normal: un solo adquiriente, todo en adq1_*
const uno = compradoresDeContrato({ adq1_nombre:'ANA LOPEZ', adq1_pasaporte:'X1234567',
                                    adq1_domicilio:'Calle 1, Madrid', adq1_email:'ana@x.com' }, []);
assert.strictEqual(uno.length, 1);
assert.strictEqual(nombresFactura(uno), 'ANA LOPEZ');
assert.strictEqual(documentosFactura(uno), 'X1234567');   // sin etiquetar: no hay con quién confundirlo

// el bug que motivó esto: los adquirientes II+ viven en datos.compradores[]
const varios = compradoresDeContrato(
  { adq1_nombre:' ANA  LOPEZ ', adq1_pasaporte:'X1234567', adq1_domicilio:'Calle 1', adq1_email:'ana@x.com' },
  [{ nombre:'BOB SMITH', pasaporte:'P9988', email:'bob@x.com' }, { nombre:'CARL RUIZ' }]);
assert.strictEqual(varios.length, 3);
assert.strictEqual(nombresFactura(varios), 'ANA LOPEZ · BOB SMITH · CARL RUIZ');
assert.strictEqual(documentosFactura(varios), 'ANA LOPEZ: X1234567 · BOB SMITH: P9988');   // Carl no tiene: no se inventa

// formato viejo (2 contratos): adq2_*/adq3_* rellenos y compradores[] vacío
const viejo = compradoresDeContrato({ adq1_nombre:'ANA', adq2_nombre:'BOB', adq3_nombre:'CARL' }, []);
assert.strictEqual(nombresFactura(viejo), 'ANA · BOB · CARL');
assert.strictEqual(documentosFactura(viejo), '');

// la misma persona en los dos formatos se lista una vez
const dup = compradoresDeContrato({ adq1_nombre:'ANA LOPEZ', adq2_nombre:'BOB SMITH' },
                                  [{ nombre:'bob   smith', pasaporte:'P9988' }]);
assert.strictEqual(nombresFactura(dup), 'ANA LOPEZ · BOB SMITH');

// domicilio y email de notificación: el primero que exista, no el del principal si está vacío
const sinDom = compradoresDeContrato({ adq1_nombre:'ANA', adq1_domicilio:'', adq1_email:'' },
                                     [{ nombre:'BOB', domicilio:'Calle 2', email:'bob@x.com' }]);
assert.strictEqual(primerDato(sinDom, 'domicilio'), 'Calle 2');
assert.strictEqual(primerDato(sinDom, 'email'), 'bob@x.com');

// contrato sin compradores (CO00004 no tiene ni adq1_nombre): no revienta ni inventa
assert.deepStrictEqual(compradoresDeContrato({}, null), []);
assert.strictEqual(nombresFactura([]), '');
assert.strictEqual(documentosFactura([]), '');
assert.strictEqual(primerDato([], 'domicilio'), '');

/* ── UNA sola lista para toda la suite — 19-ago-2026 ────────────────────────
   Este módulo vivía en `facturas/` y solo lo usaba Facturas. Contratos calculaba
   el nombre de la operación por su cuenta (`data.adq1_nombre`), así que con
   varios adquirientes la factura decía «A · B» y el contrato de al lado «A»:
   19 contratos reales con esa discrepancia. Lo caro de este estudio no han sido
   funciones mal escritas, han sido dos sitios que dicen lo mismo hasta que uno
   cambia — así que el test que toca es este: afirmar el hecho contra TODOS los
   sitios donde vive. */
const fs = require('fs');
const path = require('path');
/* La herramienta vive bajo `/intranet/` desde el 26-ago-2026, así que la raíz
   del proyecto está DOS niveles arriba, no uno. */
const raiz = (...p) => path.join(__dirname, '..', '..', ...p);

const consumidores = [
  ['facturas/index.html', raiz('intranet', 'facturas', 'index.html')],
  ['contracts/app.html',  raiz('contracts', 'app.html')],
];
consumidores.forEach(([nombre, ruta]) => {
  const txt = fs.readFileSync(ruta, 'utf8');
  assert.ok(/src="[^"]*assets\/compradores\.js/.test(txt),
    nombre + ' no carga la lista compartida de compradores');
});

// y ninguno vuelve a calcular el nombre por su cuenta
const app = fs.readFileSync(raiz('contracts', 'app.html'), 'utf8');
assert.ok(/comprador_nombre: \(typeof nombresFactura/.test(app),
  'contracts/app.html volvió a nombrar la operación sin la lista compartida');

console.log('OK compradores de factura');
