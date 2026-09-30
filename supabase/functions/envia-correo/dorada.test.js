/* node dorada.test.js — PRUEBA DORADA de la piel: lo que sale de contracts/api/lib/plantilla_correo.php (PHP 8.3 local) frente
   a lo que sale de plantilla.ts, con los mismos textos, y tiene que ser IDÉNTICO byte a byte (HTML y texto plano).
   Por qué existe: la edge nueva sustituye al PHP como emisor de TODO el correo de la intranet, pero `lead.php` y
   `booking-notify.php` siguen usando la plantilla PHP: son dos pieles del mismo correo, y las dos pieles se separan
   sin dar error (el estudio ya vio seis versiones de un menú en doce páginas). Este test es lo que las mantiene juntas.
   La fecha: el PHP llama a date() dentro de la función y no admite fecha. Se corre sobre una COPIA temporal donde
   `date(` pasa a `__fdate(` (gmdate de un instante fijo); el test exige encontrar exactamente 4 llamadas, así que si el
   PHP gana o pierde una, falla en voz alta. Además, una pasada con el PHP TAL CUAL (fecha real) confirma que esa
   sustitución no cambia nada más: se comparan ignorando solo la fecha.
   Sin `php` en la máquina NO se salta en silencio: dice «NO COMPROBADO» (y con DORADA_OBLIGATORIA=1 falla). */
const assert = require('assert');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const RAIZ = path.join(__dirname, '..', '..', '..');
const PHP_ORIGINAL = path.join(RAIZ, 'contracts', 'api', 'lib', 'plantilla_correo.php');

function hayPhp() {
  try { execFileSync('php', ['-v'], { stdio: 'pipe' }); return true; } catch { return false; }
}

(async () => {
  if (!hayPhp()) {
    const msg = 'NO COMPROBADO dorada.test.js — no hay `php` en esta máquina: la piel de plantilla.ts NO se ha comparado con el PHP.';
    if (process.env.DORADA_OBLIGATORIA) { console.error('FALLA ' + msg); process.exit(1); }
    console.log(msg); return;
  }
  const { plantillaHtml, plantillaTexto } = await import('./plantilla.ts');
  const { deduceCta, esFallo, leePeticion } = await import('./valida.ts');

  // ── el PHP, con la fecha fijable ──────────────────────────────────────────────────────────────────────────
  const fuente = fs.readFileSync(PHP_ORIGINAL, 'utf8');
  const llamadas = fuente.match(/\bdate\(/g) || [];
  assert.strictEqual(llamadas.length, 4, `plantilla_correo.php llama a date() ${llamadas.length} veces (se esperaban 4: j, n, Y, Y). Revisa cómo se fija la fecha en esta prueba.`);
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dorada-'));
  const phpFecha = path.join(tmp, 'plantilla_fecha_fija.php');
  fs.writeFileSync(phpFecha, fuente.replace(/\bdate\(/g, '__fdate('));
  const envoltorio = path.join(tmp, 'envoltorio.php');
  fs.writeFileSync(envoltorio, `<?php
$ts = (int)$argv[1];
function __fdate(string $f): string { global $ts; return gmdate($f, $ts); }
require $argv[2];
$casos = json_decode(stream_get_contents(STDIN), true);
$out = [];
foreach ($casos as $c) {
  $out[] = [
    'html'  => lw_plantilla_correo($c['mensaje'], $c['encabezado'], $c['cta'], $c['etiqueta'], $c['contacto']),
    'texto' => lw_texto_plano_correo($c['mensaje'], $c['encabezado'], $c['cta'], $c['contacto']),
  ];
}
echo json_encode($out, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
`);
  const php = (ts, fichero, casos) => JSON.parse(execFileSync('php', ['-d', 'date.timezone=UTC', envoltorio, String(ts), fichero],
    { input: JSON.stringify(casos), encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }));

  // ── los casos ─────────────────────────────────────────────────────────────────────────────────────────────
  const DOM = 'lawangproperties.com', PORTAL = 'https://lawangproperties.com/portal/';
  const CUERPO = [
    'Hola José García,',
    '',
    'Tu <b>contrato</b> "de reserva" & el anexo están listos. Cuesta 5.000.000 IDR (l\'importe final).',
    'Segunda línea del mismo párrafo.',
    '',
    '1. CONDICIONES DE PAGO',
    '• Anticipo del 30 % a la firma',
    '· Resto en tres hitos',
    '- 5.000.000 IDR (un guion NO es viñeta)',
    '',
    '2) NOTAS IMPORTANTES',
    '3. Esto no es un rótulo porque no está en mayúsculas',
    '4. AB no cuenta (menos de tres mayúsculas seguidas)',
    '',
    '',
    '   Párrafo tras varios saltos, con espacios delante   ',
    'Enlace: https://lawangproperties.com/contracts/firmar.html?t=abc.DEF-123',
  ].join('\n');
  const base = { mensaje: CUERPO, encabezado: null, cta: null, etiqueta: null, contacto: null };
  // (cta esperada, calculada por la lógica del PHP send_email.php líneas 308-334; aquí se comprueba que deduceCta la reproduce)
  const pet = (o) => leePeticion({ to: 'x@y.co', attach: false, ...o });
  const deduce = (o, interno) => { const c = deduceCta(pet(o), DOM, PORTAL, interno); assert.ok(!esFallo(c), JSON.stringify(c)); return c; };
  const cIMPUESTO = deduce({ message: 'Hola', cta_url: 'https://lawangproperties.com/intranet/v4/comunicacion/?a=1&b=2', cta_texto: 'Abrir "ahora"' }, false);
  assert.deepStrictEqual(cIMPUESTO, { url: 'https://lawangproperties.com/intranet/v4/comunicacion/?a=1&b=2', texto: 'Abrir "ahora"' });
  const mFirma = 'Firma aquí: https://lawangproperties.com/contracts/firmar.html?t=abc.DEF-123 gracias';
  const cFIRMA = deduce({ message: mFirma }, false);
  assert.deepStrictEqual(cFIRMA, { url: 'https://lawangproperties.com/contracts/firmar.html?t=abc.DEF-123', texto: 'Firmar el documento' });
  const mIntra = 'Responder desde: https://lawangproperties.com/intranet/compradores/?id=42';
  const cINTRA = deduce({ message: mIntra }, true);
  assert.deepStrictEqual(cINTRA, { url: 'https://lawangproperties.com/intranet/compradores/?id=42', texto: 'Abrir en la intranet' });
  const cPORTAL_EXT = deduce({ message: mIntra }, false);   // a un cliente NUNCA se le lleva a /intranet/
  assert.deepStrictEqual(cPORTAL_EXT, { url: PORTAL, texto: 'Entrar · Sign in' });
  const cPORTAL = deduce({ message: 'Sin enlaces' }, false);
  assert.deepStrictEqual(cPORTAL, { url: PORTAL, texto: 'Entrar · Sign in' });
  const cMAILTO = { url: 'mailto:sales@lawangproperties.com', texto: 'Escribir' };
  const cWA = { url: 'https://wa.me/6281234567890', texto: 'WhatsApp' };

  const casos = [
    ['sin botón, sin título', base],
    ['botón impuesto', { ...base, mensaje: 'Hola', cta: cIMPUESTO }],
    ['enlace de firma', { ...base, mensaje: mFirma, cta: cFIRMA }],
    ['intranet a alguien de casa', { ...base, mensaje: mIntra, cta: cINTRA }],
    ['intranet a un cliente → portal', { ...base, mensaje: mIntra, cta: cPORTAL_EXT }],
    ['botón por defecto (portal)', { ...base, mensaje: 'Sin enlaces', cta: cPORTAL }],
    ['mailto (no se repite en claro)', { ...base, cta: cMAILTO }],
    ['wa.me', { ...base, cta: cWA }],
    ['encabezado y etiqueta', { ...base, encabezado: 'Comunicado <importante> "sí"', etiqueta: 'Comunicado al equipo', cta: cPORTAL }],
    ['contacto sales', { ...base, contacto: 'sales', cta: cIMPUESTO }],
    ['contacto admin explícito → admin', { ...base, contacto: null, encabezado: '  Título con espacios  ' }],
    ['mensaje vacío', { ...base, mensaje: '' }],
    ['CRLF y líneas en blanco con espacios', { ...base, mensaje: 'Uno\r\nDos\r\n  \r\nTres\r\n\r\n\r\n• Viñeta\r\n1. TÍTULO EN MAYÚSCULAS ÑÚ' }],
    ['solo espacios y saltos alrededor', { ...base, mensaje: '\n\n  Hola  \n\n' }],
    ['unicode: emoji, ß, ñ', { ...base, mensaje: 'Straße 😀 niño\n\n1. STRASSE GRÖSSE' }],
    ['botón con pareja a medias (texto sin url)', { ...base, cta: { url: '', texto: 'Solo texto' } }],
    ['botón con pareja a medias (url sin texto)', { ...base, cta: { url: 'https://lawangproperties.com/x', texto: '  ' } }],
  ];
  const FECHAS = [Date.UTC(2026, 8, 25, 12) / 1000, Date.UTC(2027, 0, 5, 3) / 1000, Date.UTC(2026, 11, 31, 23, 59, 59) / 1000, Date.UTC(2028, 1, 29, 0, 0, 0) / 1000];

  function difiere(a, b) {
    let i = 0; while (i < a.length && i < b.length && a[i] === b[i]) i++;
    return `primer byte distinto en ${i} (PHP ${a.length} B, TS ${b.length} B)\n   PHP: …${JSON.stringify(a.slice(Math.max(0, i - 60), i + 80))}\n   TS : …${JSON.stringify(b.slice(Math.max(0, i - 60), i + 80))}`;
  }
  const paraTs = (c) => [c.mensaje, c.encabezado ?? '', c.cta, c.etiqueta ?? '',
    { marca: 'Lawang', dominio: DOM, remitente: 'admin@lawangproperties.com', contacto: c.contacto === 'sales' ? 'sales' : null }];

  // ── 1. fecha fija: igualdad byte a byte del HTML y del texto plano ───────────────────────────────────────
  let comparados = 0;
  for (const ts of FECHAS) {
    const hoy = new Date(ts * 1000);
    const dePhp = php(ts, phpFecha, casos.map(([, c]) => c));
    casos.forEach(([nombre, c], i) => {
      const [m, e, cta, et, marca] = paraTs(c);
      const html = plantillaHtml(m, e, cta, et, marca, hoy);
      const texto = plantillaTexto(m, e, cta, marca);
      assert.ok(html === dePhp[i].html, `«${nombre}» (${hoy.toISOString().slice(0, 10)}): el HTML difiere del PHP: ` + difiere(dePhp[i].html, html));
      assert.ok(texto === dePhp[i].texto, `«${nombre}»: el texto plano difiere del PHP: ` + difiere(dePhp[i].texto, texto));
      comparados += 2;
    });
  }

  // ── 2. el PHP TAL CUAL (fecha real de la máquina): la sustitución de date() no cambia nada más ─────────────
  const ahora = Math.floor(Date.now() / 1000);
  const norm = (s) => s.replace(/\d{1,2} (enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre) \d{4}/g, '@@FECHA@@').replace(/&copy; \d{4}/g, '&copy; @@ANIO@@');
  const original = php(ahora, PHP_ORIGINAL, casos.map(([, c]) => c));
  const fija = php(ahora, phpFecha, casos.map(([, c]) => c));
  casos.forEach(([nombre], i) => {
    assert.ok(norm(original[i].html) === norm(fija[i].html) && original[i].texto === fija[i].texto, `«${nombre}»: la copia con fecha fija no equivale al PHP original`);
    assert.ok(/@@FECHA@@/.test(norm(original[i].html)), 'la normalización no encontró la fecha: el test no mide lo que dice');
    const [m, e, cta, et, marca] = paraTs(casos[i][1]);
    assert.ok(norm(plantillaHtml(m, e, cta, et, marca, new Date(ahora * 1000))) === norm(original[i].html), `«${nombre}»: TS y PHP original difieren (ignorando la fecha)`);
  });

  // ── 3. lo que el PHP pone a fuego y el TS toma de dominio_web: con OTRO dominio, sale el otro ─────────────
  const otro = plantillaHtml('Hola', '', null, '', { marca: 'X', dominio: 'otra.example', remitente: 'a@b.co' }, new Date(FECHAS[0] * 1000));
  assert.ok(otro.includes('admin@otra.example') && otro.includes('href="https://otra.example"'));
  assert.ok(!otro.includes('admin@lawangproperties.com'), 'el pie no debe llevar el dominio de Lawang a fuego');

  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(`OK dorada.test.js — ${casos.length} casos × ${FECHAS.length} fechas + pasada con el PHP original: ${comparados} comparaciones byte a byte, 0 diferencias`);
})().catch((e) => { console.error(e); process.exit(1); });
