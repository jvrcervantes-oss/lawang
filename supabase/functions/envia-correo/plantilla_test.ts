// Prueba SIN RED de la plantilla de LAWANG:  node plantilla.test.js  ·  npx --yes deno test plantilla_test.ts
// La igualdad con el PHP (el test que importa) está en dorada.test.js; aquí, lo que se puede afirmar sin php.
import { plantillaHtml, plantillaTexto, esc } from './plantilla.ts';

function ok(c: boolean, msg: string) { if (!c) throw new Error(msg); }
const m = { marca: 'Lawang', dominio: 'lawangproperties.com', remitente: 'admin@lawangproperties.com' };
const dia = new Date(Date.UTC(2026, 8, 25));

Deno.test('plantilla Lawang: todo el texto se escapa y el plano dice lo mismo', () => {
  const html = plantillaHtml('Hola <script>x</script>\n\n• punto "uno"\n1. SECCIÓN DOS', 'Tít<u>lo',
    { url: 'https://lawangproperties.com/?a=1&b=2', texto: 'Ir' }, '', m, dia);
  ok(!html.includes('<script>') && html.includes('&lt;script&gt;'), 'escapa cuerpo');
  ok(!html.includes('Tít<u>lo'), 'escapa titular');
  ok(html.includes('https://lawangproperties.com/?a=1&amp;b=2'), 'escapa href');
  ok(html.includes('25 septiembre 2026'), 'fecha'); ok(html.includes('&quot;uno&quot;'), 'viñeta'); ok(html.includes('1. SECCIÓN DOS'), 'rótulo');
  const txt = plantillaTexto('Hola', 'Título', { url: 'mailto:a@b.co', texto: 'Escribir' }, m);
  ok(txt.includes('Título') && txt.includes('Escribir: a@b.co') && txt.includes('admin@lawangproperties.com'), 'plano');
  ok(esc(`<a href="x">'&'</a>`) === '&lt;a href=&quot;x&quot;&gt;&#039;&amp;&#039;&lt;/a&gt;', 'esc = htmlspecialchars ENT_QUOTES');
});

Deno.test('plantilla Lawang: documento completo, modo claro forzado (30-sep-2026) y sin terceros', () => {
  const html = plantillaHtml('Hola', '', null, '', m, dia);
  ok(html.startsWith('<!DOCTYPE html>') && html.endsWith('</html>'), 'documento completo');
  ok(html.includes('<meta name="color-scheme" content="light only">'), 'meta color-scheme');
  ok(html.includes('<meta name="supported-color-schemes" content="light only">'), 'meta supported-color-schemes');
  ok(html.includes(':root{color-scheme:light only;supported-color-schemes:light only;}'), ':root color-scheme');
  ok((html.match(/@font-face\{font-family:'Neue Kabel'/g) || []).length === 3, 'tres @font-face de Neue Kabel');
  ok(!/fonts\.googleapis|fonts\.gstatic/.test(html), 'nada de Google Fonts (la IP del lector a un tercero)');
  ok(html.includes('lawang-logo-correo-halo.png') && html.includes('correo-grano.png') && html.includes('correo-moanito.png'), 'logo con halo, grano y marca de agua');
  ok(html.includes('admin@lawangproperties.com') && !html.includes('sales@'), 'admin@ por defecto');
  ok(plantillaHtml('Hola', '', null, '', { ...m, contacto: 'sales' }, dia).includes('sales@lawangproperties.com'), 'sales@ si se pide');
  ok(plantillaHtml('Hola', '', null, '', { ...m, contacto: null }, dia).includes('admin@'), 'null → admin@');
  ok(html.includes('>Lawang Properties</td>'), 'rótulo por defecto');
  ok(plantillaHtml('Hola', '', null, 'Comunicado al equipo', m, dia).includes('>Comunicado al equipo</td>'), 'etiqueta propia');
});
