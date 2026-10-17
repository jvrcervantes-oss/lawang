// LAW-471 (17-oct-2026, Administración, revisión previa #428): fija dos reglas de la proforma automática leyendo la fuente.
// 1) precio_total YA ES EL NETO (con techo lo rebaja la pantalla y la base lo acota; en Bloqueo es lista − descuento):
//    la proforma lo usa tal cual y nadie le resta descuento_comercial otra vez (sería cobrar el descuento dos veces).
// 2) El precio sale de la columna precio_total (la que acotan los triggers) antes que del campo datos->fields que
//    escribió la pantalla. Corre con: node contracts/edge/firma-submit/proforma_neto.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert');
const raiz = path.join(__dirname, '..', '..', '..');
const edge = fs.readFileSync(path.join(__dirname, 'index.ts'), 'utf8').replace(/\r\n/g, '\n');
const app = fs.readFileSync(path.join(raiz, 'contracts', 'app.html'), 'utf8').replace(/\r\n/g, '\n');

// firma-submit: las dos funciones de importe (proforma y primer hito) leen la columna primero
const cuerpo = (src, desde, hasta) => {
  const i = src.indexOf(desde);
  assert.ok(i >= 0, 'no se encuentra ' + desde);
  const j = src.indexOf(hasta, i + desde.length);
  return src.slice(i, j < 0 ? undefined : j);
};
for (const [fn, fin] of [['async function enviarProformaTotal', '\nDeno.serve('], ['async function facturarPrimerHito', '\nconst TIPOS_CON_PROFORMA_AUTO']]) {
  const c = cuerpo(edge, fn, fin);
  assert.ok(/const precio = Number\(o\.ct\.precio_total\) \|\| C\.parseImporte\(f\.precio_total\) \|\| 0;/.test(c),
    fn + ': el precio debe salir de la columna precio_total antes que del campo');
  assert.ok(/const moneda = o\.ct\.moneda \|\| f\.moneda \|\| 'EUR';/.test(c),
    fn + ': la moneda debe salir de la columna antes que del campo');
  assert.ok(!/descuento_comercial/.test(c), fn + ': no debe restar descuento_comercial (precio_total ya es el neto)');
}

// app.html: crearProformaAutomatica usa payload.precio_total tal cual
const crea = cuerpo(app, 'async function crearProformaAutomatica', '\n}\n');
assert.ok(/const precio = payload\.precio_total;/.test(crea), 'crearProformaAutomatica debe usar precio_total tal cual');
assert.ok(!/descuento_comercial/.test(crea), 'crearProformaAutomatica no debe restar descuento_comercial');

// las notas de reactivar ya no piden restar el descuento
for (const [nombre, src] of [['firma-submit', edge], ['app.html', app]]) {
  assert.ok(!/comprobar antes que la proforma resta/.test(src), nombre + ': la nota vieja invitaba a restar el descuento dos veces');
  assert.ok(/NO (se le )?resta/.test(src), nombre + ': falta la nota de que la proforma NO resta descuento_comercial');
}
console.log('OK proforma_neto.test.js — la proforma usa precio_total (neto) tal cual, de la columna primero (precio y moneda), sin restar el descuento');
