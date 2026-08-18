/* node contracts/aviso_anulacion.test.js
   El correo que avisa al firmante de que su enlace ha dejado de valer.

   Existe porque este texto SALE HACIA UN CLIENTE REAL sin que nadie lo revise
   antes: lo dispara el agente al pulsar «Editar (anula la firma)» y se manda tal
   cual. Un `undefined` colado en el saludo, o el número del contrato sin
   sustituir, es una cara que se pierde delante de un comprador — y no hay
   revisión posterior que lo cace, porque el correo ya salió.

   Lo que se prueba, y por qué cada cosa:
   · que NUNCA aparece `undefined`/`null`/`[object Object]` — el saludo se arma
     con un nombre que puede venir vacío, nulo o con espacios de más;
   · que el número del contrato aparece SIEMPRE (es lo único que le permite al
     comprador saber de qué documento le hablan);
   · que la variante de quien YA FIRMÓ dice que su firma deja de valer, y la de
     quien solo tenía enlace NO se lo dice (sería mentira y le alarmaría);
   · que ninguna variante deja marcas de plantilla sin sustituir.

   `mensajeAnulacion` vive dentro de app.html (HTML plano, sin módulos), así que
   se extrae del fichero real y se evalúa — probar una copia no probaría nada.
   Mismo patrón que cuenta_marcador.test.js. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const app = fs.readFileSync(path.join(__dirname, 'app.html'), 'utf8');

const desde = app.indexOf('function mensajeAnulacion(');
assert.ok(desde > 0, 'mensajeAnulacion ya no está en app.html: este test quedó ciego');
const hasta = app.indexOf('\nasync function avisaAnulacion', desde);
assert.ok(hasta > desde, 'no se encuentra el final de mensajeAnulacion');
const mensajeAnulacion = eval('(' + app.slice(desde, hasta).trim() + ')');

const BASURA = ['undefined', 'null', '[object Object]', 'NaN', '{{', '}}', '${'];
const limpio = (txt, caso) => BASURA.forEach((b) =>
  assert.ok(!txt.includes(b), `«${b}» se ha colado en el correo (${caso}):\n${txt}`));

/* ---- 1. el nombre puede venir de cualquier manera ---- */
const NOMBRES = [
  { firmante_nombre: 'Karim Felipe de Blaye' },   // normal
  { firmante_nombre: '' },                        // vacío
  { firmante_nombre: '   ' },                     // solo espacios
  { firmante_nombre: null },                      // nulo
  {},                                             // ni existe la clave
];
for (const f of NOMBRES) {
  for (const yaFirmo of [true, false]) {
    const txt = mensajeAnulacion(f, 'CR00025', yaFirmo);
    limpio(txt, JSON.stringify(f) + ' yaFirmo=' + yaFirmo);
    assert.ok(txt.includes('CR00025'), 'el correo no nombra el contrato:\n' + txt);
    assert.ok(txt.startsWith('Hola'), 'el correo no empieza saludando:\n' + txt);
    assert.ok(txt.includes('Lawang Tropical Properties'), 'el correo va sin firmar:\n' + txt);
    // un saludo a alguien sin nombre no puede quedar como «Hola ,»
    assert.ok(!/^Hola\s*,/.test(txt) === !!String(f.firmante_nombre || '').trim(),
      'el saludo queda cojo cuando no hay nombre:\n' + txt.split('\n')[0]);
  }
}

/* ---- 2. solo se le dice «tu firma ya no vale» a quien de verdad firmó ---- */
const firmo   = mensajeAnulacion({ firmante_nombre: 'Ana Ruiz' }, 'RP00021', true);
const enlace  = mensajeAnulacion({ firmante_nombre: 'Ana Ruiz' }, 'RP00021', false);
assert.ok(/firma .*deja de ser válida|firma que diste/.test(firmo),
  'a quien ya firmó no se le explica que su firma deja de valer:\n' + firmo);
assert.ok(!/que diste/.test(enlace),
  'a quien solo tenía un enlace se le dice que firmó — y no es verdad:\n' + enlace);
// los dos tienen que decir que el enlace ya no funciona: es el motivo del correo
for (const [txt, caso] of [[firmo, 'ya firmó'], [enlace, 'solo enlace']])
  assert.ok(/no está activo/.test(txt), `el correo no dice que el enlace murió (${caso}):\n${txt}`);

/* ---- 3. solo se nombra al firmante por su nombre de pila ---- */
// el apellido completo en un correo automático suena a carta de banco
assert.ok(firmo.startsWith('Hola Ana,'), 'no saluda por el nombre de pila:\n' + firmo.split('\n')[0]);

console.log('OK  aviso de anulación: ' + (NOMBRES.length * 2 + 2) + ' textos revisados');
