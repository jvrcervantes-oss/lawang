/* CIERRES DEL .htaccess (14-oct-2026). Lo que viaja en el repo y NO es una pagina (herramientas .py y su
   compilado, pruebas, piezas internas) tiene que dar 404, y lo publico no puede caer en esas reglas.
   Por que existe: la lista a mano ha fallado cuatro veces, y siempre igual — llega un fichero con un nombre
   que el patron no preveia y el servidor lo sirve con 200 sin un solo error: api/test_ghl.php, los .sql de
   supabase/migrations, los .ts/.toml, y el 14-oct un .pyc versionado (su .py daba 404; el compilado, 200).
   Los patrones se LEEN del .htaccess (no se copian aqui): RedirectMatch 404 casa la ruta de la URL;
   <FilesMatch> con Deny casa el nombre del fichero ya resuelto. No sustituye a pedir la URL en produccion:
   solo prueba que las expresiones dicen lo que creemos. Corre en el gate (tools/test.py: *.test.js de Lawang). */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const ht = fs.readFileSync(path.join(__dirname, '.htaccess'), 'utf8');

// Apache (PCRE) admite `(?i)` al principio; JavaScript no: se pasa a la bandera `i`.
function regla(p) {
  const sinCaja = p.startsWith('(?i)');
  return new RegExp(sinCaja ? p.slice(4) : p, sinCaja ? 'i' : '');
}
const redir = [...ht.matchAll(/^[ \t]*RedirectMatch[ \t]+404[ \t]+(\S+)[ \t]*$/gm)].map(m => m[1]);
const files = [...ht.matchAll(/^[ \t]*<FilesMatch[ \t]+"([^"]+)">[ \t]*$([\s\S]*?)^[ \t]*<\/FilesMatch>/gm)]
  .filter(m => /deny from all|require all denied/i.test(m[2])).map(m => m[1]);

function cierra(ruta) {
  const nombre = ruta.endsWith('/') ? '' : ruta.split('/').pop();
  return redir.filter(p => regla(p).test(ruta)).concat(files.filter(p => nombre && regla(p).test(nombre)));
}

const CERRADAS = [
  // herramientas .py, su compilado y la carpeta donde Python lo deja
  '/publicar_data.py', '/publicar_data.pyc', '/publicar_data.pyo', '/ALGO.PYC',
  '/__pycache__/publicar_data.cpython-314.pyc', '/__pycache__/',
  '/intranet/dossier/tools/__pycache__/pon_renders.cpython-314.pyc',
  '/coleccion/tests/test_publicar_data.py',
  // pruebas: los dos nombres (test_<algo>.php y <algo>_test.php), en cualquier carpeta
  '/api/test_ghl.php', '/modelo/test_modelo.php', '/api/algo_test.php',
  '/coleccion/tests/coleccion_test.php', '/modelo/tests/indexable_test.php', '/modelo/tests/datos.json',
  // piezas internas que ya estaban cerradas: que sigan
  '/coleccion/lib.php', '/modelo/lib.php', '/modelo/datos.php', '/modelo/catalogo_respaldo.json',
  '/supabase/migrations/x.sql', '/assets/portfolio-app.test.js', '/private/leads.csv', '/.git/config',
  // 14-oct-2026 (auditoria C1): el plan financiero de excel/, el arnes .cjs, la configuracion de PHP-FPM y el zip de maquetas
  '/excel/', '/excel/Lamborghini_Sumba_Phase_I_Financial_Plan.xlsx', '/excel/salida/Lamborghini_Sumba_Phase_I.xlsx',
  '/excel/inbox/datos.json', '/excel/schema.json', '/excel/README.md', '/EXCEL/build_plan.py',
  '/intranet/v4/assets/ajustes_correo.harness.cjs', '/api/.user.ini', '/intranet/Lawang Properties UI mockups.zip',
  // 14-oct-2026 (auditoria semanal): por extension, hojas, volcados y notas copiados al hosting en cualquier carpeta
  '/Plan_Financiero.XLSX', '/docs/presupuesto.xls', '/export/leads.csv', '/README.md', '/intranet/NOTAS.md',
  '/data.json.bak', '/api/error.log', '/contracts/templates/templates.json',
];
const PUBLICAS = [
  '/', '/index.html', '/thecollection', '/thecollection.php', '/property/tirta-hikari', '/data.json',
  '/modelo/dali', '/modelo/dali/', '/modelo/tests', '/modelo/v1/dali', '/modelo/index.php', '/modelo/v1.php',
  '/dali', '/palmfield', '/palmfield/index.php', '/investor-deck/palmfield/', '/portfolio', '/qr/balian-hills',
  '/api/coleccion.php', '/api/save.php', '/api/auth.php', '/api/contest.php', '/api/latest.php',
  '/sitemap.xml', '/sitemap.php', '/robots.txt', '/admin.html', '/intranet/v4/home/', '/intranet/dossier/',
  '/assets/portfolio-app.js', '/assets/lawang-card.js', '/assets/python.js', '/assets/copy.css', '/assets/img/pyc.webp',
  // los .zip de docs/ son las subidas del admin (api/upload-doc.php): descargas publicas
  '/docs/1739000000_dossier.zip', '/excelente', '/assets/excel.js', '/intranet/v4/assets/ajustes.js',
  '/docs/1739000000_contrato.pdf', '/docs/1739000000_anexo.docx', '/assets/markdown.js', '/assets/img/csv-icon.webp',
  '/legal-es', '/catalogo.mdx-no',
  '/contracts/templates/texto_cambiado.json', '/contracts/templates/adenda.html', '/contracts/tokens.json',
];

const errores = [];
if (redir.length < 10 || files.length < 3) errores.push(`solo se han leido ${redir.length} RedirectMatch 404 y ${files.length} FilesMatch con Deny: el .htaccess ha cambiado de forma y esta prueba ya no mira nada`);
for (const r of CERRADAS) if (!cierra(r).length) errores.push(`${r} deberia dar 404 y ninguna regla la cierra`);
for (const r of PUBLICAS) { const c = cierra(r); if (c.length) errores.push(`${r} es publica y la cierra ${c.join(' ; ')}`); }
// El compilado no puede depender solo del 404 «bonito»: el cierre de verdad es el <FilesMatch> (nombre resuelto).
for (const n of ['x.py', 'x.pyc', 'x.cpython-314.pyc', 'algo_test.php', 'test_algo.php', 'x.harness.cjs', '.user.ini', 'Plan.xlsx', 'x.xls', 'leads.csv', 'README.md', 'data.json.bak', 'error.log']) {
  if (!files.some(p => regla(p).test(n))) errores.push(`ningun <FilesMatch> con Deny cierra el fichero ${n}`);
}

// excel/ no depende del 404 de la URL: su cierre de verdad es su propio .htaccess (PATH_INFO y doble barra incluidos)
const htExcel = path.join(__dirname, 'excel', '.htaccess');
if (!fs.existsSync(htExcel) || !/^[ 	]*Require all denied[ 	]*$/m.test(fs.readFileSync(htExcel, 'utf8'))) {
  errores.push('excel/.htaccess no existe o no lleva `Require all denied`');
}

assert.deepStrictEqual(errores, [], '\n  ' + errores.join('\n  '));
console.log(`htaccess_cierres.test.js OK (${CERRADAS.length} cerradas, ${PUBLICAS.length} publicas, ${redir.length} + ${files.length} reglas leidas)`);
