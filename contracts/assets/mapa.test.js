/* Test de la ubicación en Google Maps (mapa.js). `node mapa.test.js`; lo corre tools/test.py.

   Los valores son los de `proyectos.ubicacion_maps` en producción el 8-oct-2026: coordenadas
   pegadas a mano (27 de 33 proyectos) y enlaces cortos maps.app.goo.gl (4). Hasta ese día el
   portal solo aceptaba enlaces https y las coordenadas se quedaban sin botón «Ver en el mapa». */
const path = require('path');
const fs = require('fs');
const { lwMapaUbicacion } = require(path.join(__dirname, 'mapa.js'));
const RAIZ = path.join(__dirname, '..', '..');

let fallos = 0;
const es = (que, dio, esperado) => {
  if (JSON.stringify(dio) !== JSON.stringify(esperado)) {
    fallos++; console.error(`  FALLA  ${que}\n         dio ${JSON.stringify(dio)} · esperaba ${JSON.stringify(esperado)}`);
  }
};

// Riverfront II: coordenadas tal cual se pegaron en la intranet
es('coordenadas → enlace y mapa incrustado', lwMapaUbicacion('-8.593945, 115.148629'), {
  abrir: 'https://www.google.com/maps?q=-8.593945,115.148629',
  embed: 'https://maps.google.com/maps?q=-8.593945,115.148629&z=15&output=embed'
});
es('coordenadas con espacios alrededor y zoom del deck', lwMapaUbicacion('  -9.756089, 119.431545 ', 14).embed,
  'https://maps.google.com/maps?q=-9.756089,119.431545&z=14&output=embed');
es('punto y coma como separador', lwMapaUbicacion('-8.48475;114.9619722').abrir, 'https://www.google.com/maps?q=-8.48475,114.9619722');
// Aqua / Cube / River / Tirta Hikari: enlace corto, sin coordenadas que sacar
es('enlace corto → se abre tal cual, sin mapa incrustado', lwMapaUbicacion('https://maps.app.goo.gl/PaqHvbsTWByfdH5W9'),
  { abrir: 'https://maps.app.goo.gl/PaqHvbsTWByfdH5W9', embed: null });
es('enlace largo con @lat,lng', lwMapaUbicacion('https://www.google.com/maps/place/X/@-8.5,115.1,17z').embed,
  'https://maps.google.com/maps?q=-8.5,115.1&z=15&output=embed');
// Black Lava S9 / Sawah Village W17: sin ubicación
es('null → nada', lwMapaUbicacion(null), null);
es('vacío → nada', lwMapaUbicacion('   '), null);
// Lo que no es Google no se convierte en enlace: el portal lo pinta en un href
es('https ajeno → nada', lwMapaUbicacion('https://evil.example/maps'), null);
es('javascript: → nada', lwMapaUbicacion('javascript:alert(1)'), null);
es('http sin s → nada', lwMapaUbicacion('http://maps.google.com/?q=1,2'), null);
es('subdominio de otro dominio → nada', lwMapaUbicacion('https://google.evil.com/maps/@1.1,2.2'), null);
es('google.co.<x> de otro dominio → nada', lwMapaUbicacion('https://www.google.co.evil.com/maps'), null);
es('google.co.id sí es Google', lwMapaUbicacion('https://www.google.co.id/maps/@-8.5,115.1,15z').abrir, 'https://www.google.co.id/maps/@-8.5,115.1,15z');

// Toda página que llama a lwMapaUbicacion (directamente o vía datos.js) tiene que cargar mapa.js:
// si falta, el botón y el mapa desaparecen sin un solo error.
[
  'portal/index.html',
  'intranet/v4/proyectos/index.html',
  'investor-deck/palmfield/index.html',
  'investor-deck/index.php'
].forEach(function (p) {
  const html = fs.readFileSync(path.join(RAIZ, p), 'utf8');
  es(p + ' carga /contracts/assets/mapa.js', /<script src="\/contracts\/assets\/mapa\.js\?v=[^"]+"/.test(html), true);
});

if (fallos) { console.error(`mapa.test.js: ${fallos} fallo(s)`); process.exit(1); }
console.log('mapa.test.js: ok');
