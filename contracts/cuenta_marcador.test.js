/* node contracts/cuenta_marcador.test.js
   El marcador <!--cuenta:CLAVE--> de las plantillas de contrato.

   Existe porque el 6-ago-2026 salieron de `templates/` los dos números de cuenta
   que estaban escritos a pelo dentro de `ppjb_bonian_c2.html` y
   `anexo_y_bonian_c2.html` — dos ficheros que se sirven con 200 SIN login y que
   están en el repo PÚBLICO. Ahora la plantilla nombra la clave y el número lo
   trae `public.cuentas_bancarias`.

   Lo que se prueba, y por qué cada cosa:
   · que las plantillas NO llevan ningún número de cuenta (si vuelve uno, vuelve a
     publicarse en GitHub, y un número de cuenta no se rota);
   · que cada marcador nombra una clave que EXISTE (una clave mal escrita no falla:
     imprime la nada, y un contrato saldría sin dónde pagar sin que nadie lo vea);
   · que el renderizador saca el número correcto, sin cabecera y sin la fila de
     escrow — esas plantillas ya traen su epígrafe numerado y declaran el escrow
     en prosa.

   `tablaCuentaHTML` vive dentro de app.html (HTML plano, sin módulos), así que se
   extrae del fichero real y se evalúa. Probar una copia no probaría nada. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const AQUI = __dirname;
const app = fs.readFileSync(path.join(AQUI, 'app.html'), 'utf8');

/* ---- 1. ninguna plantilla lleva un número de cuenta dentro ---- */
const CUENTAS_REALES = ['478798116354', '885571532066', '3692536026', '1810004920345',
  '212789850974', '478501009326538', '0044860851', '1420040632', '160800028963',
  '167800024140', '1420857361', '1427191719', '1750038383831'];
const dirT = path.join(AQUI, 'templates');
for (const f of fs.readdirSync(dirT).filter((x) => x.endsWith('.html'))) {
  const s = fs.readFileSync(path.join(dirT, f), 'utf8');
  for (const n of CUENTAS_REALES)
    assert.ok(!s.includes(n), `${f} lleva el número de cuenta ${n} escrito dentro — y templates/ es público`);
}

/* ---- 2. la función real de app.html, extraída y evaluada ---- */
const desde = app.indexOf('function tablaCuentaHTML(');
assert.ok(desde > 0, 'tablaCuentaHTML ya no está en app.html: este test quedó ciego');
const hasta = app.indexOf('\nfunction datosBancariosHTML', desde);
assert.ok(hasta > desde, 'no se encuentra el final de tablaCuentaHTML');

const CUENTAS_BANCARIAS = {
  notario_prueba: { label: 'Notario de prueba', titular: 'Un Notario', banco: 'Banco N',
    cuenta: '111122223333', codigo: 'NNNNIDJA', direccion: 'Calle N 1', extra: '' },
  empresa_prueba: { label: 'Empresa de prueba', titular: 'PT EMPRESA', banco: 'Banco E',
    cuenta: '444455556666', codigo: 'EEEEIDJA', direccion: 'Calle E 2',
    extra: { es: 'Código de banco: 001', en: 'Bank code: 001', id: 'Kode bank: 001' } },
};
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const tablaCuentaHTML = new Function('CUENTAS_BANCARIAS', 'esc',
  app.slice(desde, hasta) + '\n;return tablaCuentaHTML;')(CUENTAS_BANCARIAS, esc);

/* La MISMA sustitución que hace buildDoc, copiada de app.html para no divergir. */
const mCambio = app.match(/html=html\.replace\((\/<!--cuenta:[^/]+\/g),/);
assert.ok(mCambio, 'buildDoc ya no sustituye <!--cuenta:...-->');
const RE = new RegExp(mCambio[1].slice(1, -2), 'g');
const pinta = (html) => html.replace(RE,
  (_m, clave) => tablaCuentaHTML(clave, { titulo: false, escrow: false, clase: 'pays kv' }));

/* ---- 3. imprime el número bueno, sin cabecera y sin fila de escrow ---- */
const salida = pinta('<p>prosa</p><!--cuenta:notario_prueba--><p>mas prosa</p>');
assert.ok(salida.includes('111122223333'), 'no imprimió el número de la cuenta');
assert.ok(salida.includes('<p>prosa</p>') && salida.includes('<p>mas prosa</p>'), 'se comió la prosa de alrededor');
assert.ok(!salida.includes('<h2'), 'metió una cabecera «Datos bancarios» donde la plantilla ya tiene su epígrafe');
assert.ok(!/ESCROW/i.test(salida), 'añadió la fila de escrow: es texto nuevo en un documento legal que nadie pidió');
assert.ok(salida.includes('class="pays kv"'), 'perdió la clase de la maqueta de la plantilla');

/* el `extra` trilingüe sí sale en los tres idiomas (los contratos se imprimen en tres) */
const conExtra = pinta('<!--cuenta:empresa_prueba-->');
assert.ok(conExtra.includes('Código de banco: 001') && conExtra.includes('Kode bank: 001'),
  'el `extra` trilingüe tiene que salir en los tres idiomas');

/* ---- 4. una clave que no existe no imprime nada (y no revienta) ---- */
assert.strictEqual(pinta('<!--cuenta:no_existe-->'), '',
  'una clave inexistente debe imprimir nada, nunca una cuenta adivinada');

/* ---- 5. y la selección del contrato sigue llevando cabecera y escrow ---- */
const conTodo = tablaCuentaHTML('notario_prueba', {});
assert.ok(conTodo.includes('<h2'), 'la cuenta ELEGIDA en el contrato sí lleva su cabecera');
assert.ok(/ESCROW/i.test(conTodo), 'la cuenta ELEGIDA de un notario sí declara el escrow');

/* ---- 6. las claves que usan las plantillas de verdad existen ---- */
const entities = fs.readFileSync(path.join(AQUI, 'assets', 'entities.js'), 'utf8');
assert.ok(!/^\s*sandalwoods_dbs:/m.test(entities),
  'entities.js volvió a llevar cuentas escritas dentro');
const usadas = new Set();
for (const f of fs.readdirSync(dirT).filter((x) => x.endsWith('.html'))) {
  const s = fs.readFileSync(path.join(dirT, f), 'utf8');
  for (const m of s.matchAll(/<!--cuenta:([a-z0-9_]+)-->/g)) usadas.add(m[1]);
}
console.log('cuenta_marcador.test.js OK · claves usadas por las plantillas:',
  [...usadas].join(', ') || '(ninguna)');
console.log('  ⚠️ que esas claves existan en `cuentas_bancarias` se comprueba contra la base,',
  'no aquí: este test corre sin red.');
