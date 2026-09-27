/* node intranet/leads/buscador.test.js — falla si el buscador del CRM vuelve a
   aceptar lo que rellena el navegador (incidente 27-sep-2026, tablero vacío). */
const assert = require('assert');
const { busquedaAceptable } = require('./buscador.js');
const YO = 'sales@lawangproperties.com';

// el caso del incidente: el gestor de contraseñas escribe el email de la sesión
assert.strictEqual(busquedaAceptable({ valor: YO, tocado: false, esInputEvent: false, emailSesion: YO }), false);
// ni aunque llegue como InputEvent, ni con otra caja, ni con espacios
assert.strictEqual(busquedaAceptable({ valor: ' Sales@LawangProperties.com ', tocado: true, esInputEvent: true, emailSesion: YO }), false);

// relleno automático de otro valor: Event genérico sin tecleo previo
assert.strictEqual(busquedaAceptable({ valor: 'otra@cuenta.com', tocado: false, esInputEvent: false, emailSesion: YO }), false);
// antes de conocer la sesión, la regla del tecleo sigue funcionando
assert.strictEqual(busquedaAceptable({ valor: YO, tocado: false, esInputEvent: false, emailSesion: '' }), false);

// lo legítimo pasa: teclear, pegar (tocado), IME/dictado (InputEvent)
assert.strictEqual(busquedaAceptable({ valor: 'Lead 3', tocado: true, esInputEvent: true, emailSesion: YO }), true);
assert.strictEqual(busquedaAceptable({ valor: 'Lead 3', tocado: true, esInputEvent: false, emailSesion: YO }), true);
assert.strictEqual(busquedaAceptable({ valor: 'Lead 3', tocado: false, esInputEvent: true, emailSesion: YO }), true);

// vaciar siempre vale (incluido el botón ✕ del type=search, que no teclea)
assert.strictEqual(busquedaAceptable({ valor: '', tocado: false, esInputEvent: false, emailSesion: YO }), true);
assert.strictEqual(busquedaAceptable({ valor: null, tocado: false, esInputEvent: false, emailSesion: YO }), true);

console.log('buscador.test.js OK');
