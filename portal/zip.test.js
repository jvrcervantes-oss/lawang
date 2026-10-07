// zip.test.js — el .zip que genera zip.js lo abre un lector independiente (Python zipfile)
// y devuelve los mismos bytes. Un zip «casi válido» abre en unos programas y en otros no,
// así que no basta con que no falle: se lee con otro lector y se comparan los contenidos.
const fs = require('fs'), os = require('os'), path = require('path'), cp = require('child_process');
const { lwZip, crc32 } = require('./zip.js');

let fallos = 0;
function ok(c, m) { if (!c) { fallos++; console.error('FALLO:', m); } }

ok(crc32(new TextEncoder().encode('123456789')) === 0xCBF43926, 'crc32 de «123456789» debe ser CBF43926');

const ficheros = [
  { name: 'Plano planta.pdf', data: Uint8Array.from(Buffer.from('%PDF-1.4 plano')) },
  { name: 'Dossier – Palmfield (ñ).pdf', data: Uint8Array.from(Buffer.from('contenido con acentos áéíóú')) },
  { name: 'vacio.txt', data: new Uint8Array(0) },
  { name: 'binario.bin', data: Uint8Array.from(Array.from({ length: 70000 }, (_, i) => i % 251)) },
];
const zip = lwZip(ficheros, new Date(2026, 9, 7, 12, 30, 40));
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'lwzip-'));
const ruta = path.join(tmp, 'p.zip');
fs.writeFileSync(ruta, Buffer.from(zip));
const py = [
  'import zipfile,sys,json',
  'z=zipfile.ZipFile(sys.argv[1])',
  'assert z.testzip() is None',
  'print(json.dumps({n:list(z.read(n)) if n=="vacio.txt" else len(z.read(n)) for n in z.namelist()}))',
  'print(json.dumps(z.read("Dossier – Palmfield (ñ).pdf").decode("utf8")))',
].join('\n');
const r = cp.spawnSync('python', ['-I', '-c', py, ruta], { encoding: 'utf8' });
ok(r.status === 0, 'Python zipfile no pudo abrir el zip: ' + r.stderr);
if (r.status === 0) {
  const lineas = r.stdout.trim().split('\n');
  const tam = JSON.parse(lineas[0]);
  ok(Object.keys(tam).length === 4, 'deben salir 4 ficheros');
  ok(tam['Plano planta.pdf'] === 14, 'tamaño del plano');
  ok(tam['binario.bin'] === 70000, 'tamaño del binario');
  ok(JSON.parse(lineas[1]) === 'contenido con acentos áéíóú', 'los acentos deben sobrevivir');
  ok('Dossier – Palmfield (ñ).pdf' in tam, 'el nombre con ñ y guion largo debe conservarse');
}
fs.rmSync(tmp, { recursive: true, force: true });
if (fallos) { console.error(fallos + ' fallo(s)'); process.exit(1); }
console.log('zip.test.js — OK');
