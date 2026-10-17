// 17-oct-2026 (mejora 6, Nuevo cliente en pasos): el alta pone el prefijo del teléfono a partir de la nacionalidad.
// Fija que NINGUNA nacionalidad de la lista se queda sin prefijo (las dos listas de geo.js no pueden separarse en
// silencio) y unos cuantos casos a mano. Corre con: node contracts/assets/geo_prefijo.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert'), vm = require('vm');
const src = fs.readFileSync(path.join(__dirname, 'geo.js'), 'utf8');
const ctx = {};
vm.runInNewContext(src + '\nthis.NACIONALIDADES = NACIONALIDADES; this.prefijoDeNacionalidad = prefijoDeNacionalidad; this.idiomaDeNacionalidad = idiomaDeNacionalidad; this.PAISES_ES = PAISES_ES;', ctx);
const { NACIONALIDADES, prefijoDeNacionalidad: pre, idiomaDeNacionalidad: idi, PAISES_ES } = ctx;
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

const sin = NACIONALIDADES.filter((x) => !/^\+\d{1,4}$/.test(pre(x)));
ok(sin.length === 0, 'nacionalidades sin prefijo: ' + sin.join(', '));
ok(pre('España') === '+34' && pre('Indonesia') === '+62' && pre('Australia') === '+61', 'casos directos');
ok(pre('Estados Unidos') === '+1' && pre('Canadá') === '+1' && pre('Jamaica') === '+1' && pre('República Dominicana') === '+1', '+1 compartido');
ok(pre('Rusia') === '+7' && pre('Kazajistán') === '+7', 'entrada «A / B»');
ok(pre('Birmania (Myanmar)') === '+95', 'lo de entre paréntesis no cuenta');
ok(pre('') === '' && pre(null) === '' && pre('Atlántida') === '', 'sin coincidencia: vacío');
// idioma de comunicación (H4)
const fuera = PAISES_ES.filter((x) => !NACIONALIDADES.includes(x));
ok(fuera.length === 0, 'países de habla hispana que no están en NACIONALIDADES: ' + fuera.join(', '));
ok(idi('Indonesia') === 'id' && idi('España') === 'es' && idi('México') === 'es' && idi('Australia') === 'en', 'casos directos de idioma');
ok(idi('Birmania (Myanmar)') === 'en' && idi('') === '' && idi(null) === '', 'idioma: paréntesis y vacío');
ok(NACIONALIDADES.every((x) => ['es', 'en', 'id'].includes(idi(x))), 'toda nacionalidad da uno de los tres idiomas de la base');
console.log('OK geo_prefijo.test.js — ' + n + ' comprobaciones');
