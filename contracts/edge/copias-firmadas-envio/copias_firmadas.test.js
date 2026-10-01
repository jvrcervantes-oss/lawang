// AXW-127 (1-oct-2026): fija, leyendo las fuentes, las reglas de la cola de copias firmadas que la revisión previa #186
// (Seguridad, Datos, Deploy) dejó escritas. Corre con: node contracts/edge/copias-firmadas-envio/copias_firmadas.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert');
const raiz = path.join(__dirname, '..', '..', '..');
const leer = (...p) => fs.readFileSync(path.join(raiz, ...p), 'utf8').replace(/\r\n/g, '\n');
const edge = leer('contracts', 'edge', 'copias-firmadas-envio', 'index.ts');
const firma = leer('contracts', 'edge', 'firma-submit', 'index.ts');
const firmaEspejo = leer('supabase', 'functions', 'firma-submit', 'index.ts');
const mig = leer('supabase', 'migrations', '20261001160000_axw127_cola_copias_firmadas.sql');
const toml = leer('supabase', 'config.toml');
const trozo = (s, desde, hasta) => { const i = s.indexOf(desde), j = s.indexOf(hasta, i + 1); assert.ok(i >= 0 && j > i, 'no se encuentra ' + desde); return s.slice(i, j); };

// 1. las dos copias de firma-submit idénticas (el despliegue sale de una u otra)
assert.strictEqual(firma, firmaEspejo, 'contracts/edge y supabase/functions de firma-submit han divergido');

// 2. firma-submit: el modo cola es opt-in, encolar recibe SOLO el contrato y MAX_TANDA sigue acotando la petición
assert.ok(/if \(grande && await modoCola\(\)\)/.test(firma), 'la cola solo se usa con el interruptor «cola» y para lo grande');
assert.ok(/valor === 'cola'/.test(firma) && /copias_firmadas_modo/.test(firma), 'interruptor copias_firmadas_modo');
assert.ok(/rpc\('copia_firmada_encolar', \{ p_contrato: contratoId \}\)/.test(firma), 'encolar solo con el contrato: la edge no pasa emails');
assert.ok(/const MAX_TANDA = /.test(firma), 'MAX_TANDA sigue (acota lo que viaja adjunto DENTRO de la petición: fallo del 17-ago)');
assert.ok(/'— se usa el enlace'/.test(firma), 'si el encolado falla ANTES de enviar, cae al camino antiguo');

// 3. los correos de texto del reparto nuevo: URL genérica, sin token, sin enlace firmado, sin query
const nuevo = trozo(firma, 'async function avisarSegunPlan', '/* El contrato firmado, al estudio');
assert.ok(!/createSignedUrl|token|signedUrl|enlace_firma/i.test(nuevo.replace(/\/\/.*$/gm, '')),'el reparto nuevo no lleva token ni URL firmada');
const urls = [...nuevo.matchAll(/SITIO \+ '([^']*)'/g)].map((m) => m[1]).sort();
assert.deepStrictEqual(urls, ['/intranet/v4/operaciones/', '/portal/'], 'solo el portal y la intranet, a secas');
assert.ok(/via: 'copia_firmada', mensaje: cuerpo/.test(nuevo), 'registro con la vía nueva');

// 4. la edge de la cola
assert.ok(/rpc\('cron_copias_firmadas_secret'\)/.test(edge) && !/cron_avisos_manager/.test(edge.replace(/\/\/.*$/gm, '')), 'secreto PROPIO, no el de avisos-manager');
assert.ok(/function igual\(/.test(edge) && /\^ /.test(edge), 'comparación en tiempo constante');
assert.ok(!/req\.json\(|req\.text\(|req\.url|searchParams/.test(edge), 'la edge no lee body ni query');
assert.ok(/const MAX_ADJUNTO = 18_000_000;/.test(edge) && /v_max   constant bigint := 18000000;/.test(mig), 'umbral de adjunto igual en la edge y en la base');
assert.ok(/!== f\.pdf_sha256/.test(edge) && /sha_distinto/.test(edge), 'sha del PDF descargado contra el de la base');
assert.ok(/copia_firmada_ok/.test(edge) && /copia_firmada_fallo/.test(edge) && /BLOQUEO_SMTP/.test(edge), 'cierre por RPC y freno 554');
assert.ok(!/from\('correos_enviados'\)/.test(edge), 'el control de duplicados NO mira correos_enviados (un agente puede escribir ahí)');
assert.ok(/ESPERA_MS = 20_000/.test(edge), '20 s entre correos');
const logs = edge.split('\n').filter((l) => /console\.(log|error|warn)/.test(l)).join('\n');
assert.ok(!/f\.email|\.email\b|\.nombre\b/.test(logs), 'ninguna dirección ni nombre en los logs');
// plantilla fija sin URL ni token
const pl = trozo(edge, 'export function plantilla', 'async function enviar(');
assert.ok(!/https?:|token|signed|SITIO/i.test(pl), 'la plantilla de la cola no lleva URL ni token');
assert.ok(toml.includes('[functions.copias-firmadas-envio]\nverify_jwt = false'), 'verify_jwt=false fijado en config.toml');

// 5. la migración: cerrada, sin red, sin datos del repo público
const funcs = [...mig.matchAll(/create or replace function public\.([a-z_]+)\(/g)].map((m) => m[1]);
assert.ok(funcs.length >= 9, 'faltan funciones en la migración');
for (const f of funcs) {
  const cab = mig.slice(mig.indexOf('function public.' + f + '('));
  assert.ok(/set search_path = ''/.test(cab.slice(0, 700)), f + ' sin search_path vacío');
  assert.ok(new RegExp('revoke execute on function public\\.' + f + '\\([^)]*\\)\\s+from public, anon, authenticated').test(mig), f + ' sin revoke a public/anon/authenticated');
}
assert.ok(!/grant\s+execute[^;]*to\s+(anon|authenticated|public)/i.test(mig), 'ningún grant a anon/authenticated');
assert.ok(!/net\.http_post|cron\.schedule/.test(mig.replace(/^--.*$/gm, '')), 'el despertador y el cron NO van en esta migración');
assert.ok(!/[A-Za-z0-9._-]+@[A-Za-z0-9-]+\.[a-z]{2,}/.test(mig), 'ningún email literal en un repo público');
assert.ok(!/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/.test(mig), 'ningún uuid literal');
assert.ok(/enable row level security/.test(mig) && /revoke all on public\.copias_firmadas_envios from public, anon, authenticated/.test(mig), 'RLS y sin grants');
assert.ok(/'copia_firmada'\]\)/.test(mig), 'el CHECK de via incluye copia_firmada');
assert.ok(/for update of e skip locked/.test(mig) && /interval '15 minutes'/.test(mig), 'reclamo atómico con arrendamiento');
console.log('OK copias_firmadas.test.js — cola cerrada, secreto propio, plantillas sin credencial, migración sin red ni datos');
