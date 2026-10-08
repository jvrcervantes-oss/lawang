/* node contracts/plantilla_tipo_slug.test.js
   «Plantillas de contrato por empresa» · S5 (7-oct-2026). Afirma UN hecho contra todos los sitios donde vive (la familia de fallo cara del estudio:
   el mismo dato en varios sitios que se separan):

   1. El mapa tipo de contrato -> plantilla existe DOS veces: `CONTRACT_TIPO` (JS, contracts/assets/vocabulario.js) y `_plantilla_slug_de_tipo` (SQL, migracion
      20261009000000). Si divergen, la base fija a un contrato el texto de OTRA plantilla (o ninguno) sin un solo error. Se exige que sean el mismo mapa.
   2. Las 8 RPC de plantillas de S2 + la nueva: solo tres con EXECUTE para `authenticated` (reducir la exposicion), y cada una la llama contracts/app.html.
      Una RPC concedida sin llamador, o llamada sin concesion, falla aqui.
   3. El visor y el documento: #pvFrame lleva `sandbox` sin allow-scripts; buildDoc() antepone la CSP; firma-get la antepone a todo snapshot.
   4. Los enganches por identificador que la pantalla ya usaba siguen (data-lwt-title, id="pvFrame", name="proyecto_nombre"). */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const leer = (...p) => fs.readFileSync(path.join(__dirname, '..', ...p), 'utf8');
const app = leer('contracts', 'app.html');
const sqlGrant = leer('supabase', 'migrations', '20261009000000_f2_plantillas_s5_1_lectura_y_candados.sql');
const vocab = leer('contracts', 'assets', 'vocabulario.js');
const firmaGet = leer('contracts', 'edge', 'firma-get', 'index.ts');

let n = 0;
const ok = (c, msg) => { assert.ok(c, msg); n++; };

// ---- 1. el mapa tipo -> plantilla
const ctx = {};
vm.createContext(ctx);
vm.runInContext(vocab.replace(/\bconst (CONTRACT_TIPO|TIPO_SLUG)\b/g, 'var $1'), ctx);
const jsMapa = Object.fromEntries(Object.entries(ctx.CONTRACT_TIPO).map(([slug, tipo]) => [tipo, slug]));   // tipo -> slug
const bloque = sqlGrant.slice(sqlGrant.indexOf('create function public._plantilla_slug_de_tipo'), sqlGrant.indexOf('revoke all on function public._plantilla_slug_de_tipo'));
const sqlMapa = Object.fromEntries([...bloque.matchAll(/\('([a-z0-9_]+)', '([a-z0-9_]+)'\)/g)].map(m => [m[1], m[2]]));
assert.deepStrictEqual(sqlMapa, jsMapa, 'tipo->plantilla: el SQL y vocabulario.js difieren');
n++;
ok(Object.keys(sqlMapa).length === 17, 'los 17 tipos');
// E9 (8-oct-2026): la migracion que abre el mapa a los contratos propios lleva LOS MISMOS 17 pares (no una copia que se separe)
const sqlPropio = leer('supabase', 'migrations', '20261010040000_f2_editor_e9_tipo_propio.sql');
const bloquePropio = sqlPropio.slice(sqlPropio.indexOf('create or replace function public._plantilla_slug_de_tipo'), sqlPropio.indexOf('revoke all on function public._plantilla_slug_de_tipo'));
const sqlMapaPropio = Object.fromEntries([...bloquePropio.matchAll(/\('([a-z0-9_]+)', '([a-z0-9_]+)'\)/g)].map(m => [m[1], m[2]]));
assert.deepStrictEqual(sqlMapaPropio, sqlMapa, 'tipo->plantilla: la migracion E9 difiere de la de S5');
n++;
// estatutos_sw y los dos anexos no tienen tipo (no se guardan como contrato): no pueden aparecer en el mapa
['estatutos_sw', 'anexo_x_bonian_c2', 'anexo_y_bonian_c2'].forEach(s => ok(!Object.values(sqlMapa).includes(s), s + ' no tiene tipo'));
// la migracion de vinculos usa la MISMA funcion (no una lista aparte)
const vinc = leer('supabase', 'migrations', '20261009000100_f2_plantillas_s5_2_vincula_borradores.sql');
ok(vinc.includes('public._plantilla_slug_de_tipo(c.tipo)'), 'la carga de vinculos usa _plantilla_slug_de_tipo');
ok(!/from \(values/i.test(vinc), 'la carga de vinculos no lleva otra copia del mapa');

// ---- 2. exposicion: tres RPC con llamador
const concedidas = (sqlGrant.match(/grant execute on function ([^;]*?) to authenticated;/s) || [])[1] || '';
const nombres = [...concedidas.matchAll(/public\.([a-z_]+)\(/g)].map(m => m[1]).sort();
assert.deepStrictEqual(nombres, ['plantilla_contrato_cuerpo', 'plantilla_contrato_cuerpo_de_contrato', 'plantilla_contrato_fija']);
n++;
nombres.forEach(r => ok(app.includes("'" + r + "'"), r + ' tiene llamador en contracts/app.html'));
['plantilla_contrato_guarda_borrador', 'plantilla_contrato_activa', 'plantilla_contrato_descarta_borrador', 'plantilla_contrato_cuerpo_version',
 'plantilla_contrato_version_de_contrato', 'plantilla_contrato_versiones_lista'].forEach(r => {
  ok(!app.includes("'" + r + "'"), r + ' sigue sin llamador en app.html (hasta S7)');
  ok(!concedidas.includes(r), r + ' no se concede en S5');
});
ok(/revoke all on function[^;]*plantilla_contrato_activa/s.test(sqlGrant) && /revoke all on function[^;]*plantilla_contrato_descarta_borrador/s.test(sqlGrant), 'activa y descarta se re-revocan tras redefinirse');
// interbloqueo: el candado asesor antes del for update en las dos funciones redefinidas
['plantilla_contrato_activa', 'plantilla_contrato_descarta_borrador'].forEach(f => {
  const i = sqlGrant.indexOf('create or replace function public.' + f);
  const cuerpo = sqlGrant.slice(i, sqlGrant.indexOf('end $$;', i));
  ok(cuerpo.indexOf('pg_advisory_xact_lock') > 0 && cuerpo.indexOf('pg_advisory_xact_lock') < cuerpo.indexOf('for update'), f + ': candado asesor antes del for update');
});

// ---- 3. visor y documento
const tagPv = (app.match(/<iframe id="pvFrame"[^>]*>/) || [''])[0];
ok(/sandbox="([^"]*)"/.test(tagPv), '#pvFrame lleva sandbox');
const sb = tagPv.match(/sandbox="([^"]*)"/)[1].split(/\s+/);
ok(!sb.includes('allow-scripts'), 'el visor NO permite scripts');
ok(sb.includes('allow-same-origin') && sb.includes('allow-modals'), 'same-origin (leer el documento) y modals (imprimir): medidos en la prueba de Playwright');
ok(/fr\.setAttribute\('sandbox', 'allow-same-origin allow-modals'\)/.test(app), 'el iframe de borrador lleva el mismo sandbox');
ok(/return anteponeCSP\(html\);\n\}/.test(app), 'buildDoc devuelve el documento con la CSP antepuesta');
ok(/script-src 'none'/.test(app) && /default-src 'none'/.test(app) && /frame-src 'none'/.test(app), 'cspDocumento: sin scripts, sin marcos, default none');
ok(/const conCsp = /.test(firmaGet) && /html = conCsp\(html\)/.test(firmaGet), 'firma-get antepone la CSP al snapshot');
ok(/CSP_DOCUMENTO/.test(firmaGet) && /script-src 'none'/.test(firmaGet), 'firma-get: misma politica');

// ---- 4. enganches que no cambian
['id="pvFrame"', 'data-lwt-title', "name === 'proyecto_nombre'"].forEach(s => ok(app.includes(s), 'sigue ' + s));
ok(!/\r/.test(app) && !/\r/.test(firmaGet), 'sin CRLF');

console.log('plantilla_tipo_slug.test.js: ' + n + ' comprobaciones OK');
