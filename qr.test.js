/* QR DINAMICOS (12-oct-2026): el QR impreso de Balian Hills codifica /qr/balian-hills y el
   .htaccess lo manda al WhatsApp. Si la regla desaparece o pierde un flag, el QR ya impreso deja
   de funcionar sin un solo error en el servidor: un 404 que solo ve quien lo escanea.
   Corre en el gate (tools/test.py descubre los *.test.js de Lawang). */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const ht = fs.readFileSync(path.join(__dirname, '.htaccess'), 'utf8');
const errores = [];

const QR = {
  'balian-hills': 'https://wa.me/6281138305237?text=Hello\\%21\\%20I\\%27m\\%20interested\\%20in\\%20Balian\\%20Hills\\%20and\\%20would\\%20love\\%20to\\%20receive\\%20more\\%20information\\%20about\\%20the\\%20freehold\\%20land\\%20and\\%20ocean-view\\%20villas.\\%20Thank\\%20you\\%21',
};

for (const [nombre, destino] of Object.entries(QR)) {
  const linea = ht.split(/\r?\n/).find(l => l.trim().startsWith(`RewriteRule ^qr/${nombre}/?$ `));
  if (!linea) { errores.push(`.htaccess: falta la regla del QR /qr/${nombre} (hay QR impresos que apuntan ahi)`); continue; }
  const [, , dest, flags = ''] = linea.trim().split(/\s+/);
  // Cambiar el destino es legitimo (para eso es dinamico): entonces se actualiza tambien aqui.
  if (dest !== destino) errores.push(`/qr/${nombre}: el destino no es el esperado; si el cambio es a proposito, actualiza qr.test.js`);
  // 302 y no 301 (el navegador guardaria la redireccion para siempre); NE o el %20 sale doble codificado.
  if (!/R=302/.test(flags)) errores.push(`/qr/${nombre}: tiene que ser R=302, no ${flags}`);
  if (!/\bNE\b/.test(flags)) errores.push(`/qr/${nombre}: falta NE; sin el, Apache codifica dos veces el %20 del destino`);
  // Un % sin escapar en la sustitucion es una retrorreferencia de RewriteCond (%2 en %21) y se come caracteres.
  if (/(^|[^\\])%\d/.test(dest)) errores.push(`/qr/${nombre}: hay un % sin escapar (\\%) en el destino`);
}

if (!/SetEnvIf Request_URI "\^\/qr\/" LW_QR/.test(ht) || !/Header always set Cache-Control "no-store" env=LW_QR/.test(ht)) {
  errores.push('.htaccess: falta el no-store de /qr/ (LW_QR); sin el, el CDN o el navegador guardan la redireccion');
}

assert.deepStrictEqual(errores, [], '\n  ' + errores.join('\n  '));
console.log('qr.test.js OK (' + Object.keys(QR).length + ' QR dinamicos)');
