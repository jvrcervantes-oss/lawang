// mcp.test.js — 16-oct-2026. Pruebas de la edge `mcp` (motor.js) en node, con la base simulada. `node --test supabase/functions/mcp/`
// Lo que prueban: rutas y metadatos OAuth, que los errores nunca redirigen al asistente, el 401 con su WWW-Authenticate, Origin,
// versión del protocolo, que tools/call solo despacha herramientas de la lista, y que el directorio NO nombra la clave de servicio.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { crea } from './motor.js';
import { HERRAMIENTAS } from './herramientas.js';

const AQUI = dirname(fileURLToPath(import.meta.url));
const EMISOR = 'https://ref.supabase.co/functions/v1/mcp';
const INTRANET = 'https://lawangproperties.com';

function monta(respuestas = {}) {
  const llamadas = [];
  const cerradas = [];
  const atiende = crea({
    recurso: EMISOR, emisor: EMISOR, conectar: INTRANET + '/intranet/ia/conectar/', origenIntranet: INTRANET,
    herramientas: [{ name: 'facturas_no_cobradas', description: 'x', inputSchema: { type: 'object', properties: {} } }],
    puente: async (accion, datos) => {
      llamadas.push({ accion, datos });
      const r = respuestas[accion];
      return typeof r === 'function' ? r(datos) : r ?? { error: 'invalid_request' };
    },
    autoriza: async (sesion, peticion) => {
      llamadas.push({ accion: 'autoriza', sesion, peticion });
      return respuestas.autoriza ?? { error: 'peticion_invalida' };
    },
    cierraSesion: async (sesion) => { cerradas.push(sesion); },
  });
  return { atiende, llamadas, cerradas };
}
const pide = (ruta, op = {}) => new Request('https://ref.supabase.co/functions/v1/mcp' + ruta, op);
const rpc = (cuerpo, cab = {}) => pide('/', { method: 'POST', headers: { Authorization: 'Bearer acc', 'Content-Type': 'application/json', ...cab }, body: JSON.stringify(cuerpo) });

test('metadatos: recurso señala al servidor, servidor sin registro dinámico, S256 y cliente público', async () => {
  const { atiende } = monta();
  const r = await (await atiende(pide('/.well-known/oauth-protected-resource'))).json();
  assert.equal(r.resource, EMISOR);
  assert.deepEqual(r.authorization_servers, [EMISOR]);
  for (const ruta of ['/.well-known/oauth-authorization-server', '/.well-known/openid-configuration']) {
    const s = await (await atiende(pide(ruta))).json();
    assert.equal(s.issuer, EMISOR);
    assert.deepEqual(s.code_challenge_methods_supported, ['S256']);
    assert.deepEqual(s.token_endpoint_auth_methods_supported, ['none']);
    assert.equal(s.authorization_response_iss_parameter_supported, true);
    assert.equal(s.registration_endpoint, undefined);
    assert.equal(s.client_id_metadata_document_supported, undefined);
  }
});

test('/authorize: la buena va a la página de conexión; un error NUNCA redirige al asistente', async () => {
  let { atiende, llamadas } = monta({ pide: { peticion: 'P'.repeat(43) } });
  let r = await atiende(pide('/authorize?response_type=code&client_id=c&redirect_uri=https%3A%2F%2Fclaude.ai%2Fapi%2Fmcp%2Fauth_callback&code_challenge=x&code_challenge_method=S256&state=s'));
  assert.equal(r.status, 302);
  assert.equal(r.headers.get('location'), INTRANET + '/intranet/ia/conectar/?p=' + 'P'.repeat(43));
  assert.equal(llamadas[0].datos.recurso, EMISOR, 'sin resource, el recurso es el propio');
  ({ atiende } = monta({ pide: { error: 'invalid_redirect_uri' } }));
  r = await atiende(pide('/authorize?response_type=code&client_id=c&redirect_uri=https%3A%2F%2Fmalo.example'));
  assert.equal(r.status, 400);
  assert.equal(r.headers.get('location'), null);
  r = await atiende(pide('/authorize?response_type=token'));
  assert.equal(r.status, 400);
});

test('/conectar: solo desde la intranet; devuelve code+state+iss al asistente y cierra la sesión fresca', async () => {
  const { atiende, cerradas } = monta({ autoriza: { redirect_uri: 'https://claude.ai/api/mcp/auth_callback', code: 'C'.repeat(43), state: 'xyz' } });
  const form = 'peticion=P&sesion=JWT';
  let r = await atiende(pide('/conectar', { method: 'POST', headers: { origin: 'https://malo.example', 'content-type': 'application/x-www-form-urlencoded' }, body: form }));
  assert.equal(r.status, 403);
  r = await atiende(pide('/conectar', { method: 'POST', headers: { origin: INTRANET, 'content-type': 'application/x-www-form-urlencoded' }, body: form }));
  assert.equal(r.status, 302);
  const u = new URL(r.headers.get('location'));
  assert.equal(u.origin + u.pathname, 'https://claude.ai/api/mcp/auth_callback');
  assert.equal(u.searchParams.get('code'), 'C'.repeat(43));
  assert.equal(u.searchParams.get('state'), 'xyz');
  assert.equal(u.searchParams.get('iss'), EMISOR);
  assert.deepEqual(cerradas, ['JWT']);
});

test('/conectar con error vuelve a la intranet, no al asistente, y también cierra la sesión', async () => {
  const { atiende, cerradas } = monta({ autoriza: { error: 'contrasena_no_reciente' } });
  const r = await atiende(pide('/conectar', { method: 'POST', headers: { origin: INTRANET, 'content-type': 'application/x-www-form-urlencoded' }, body: 'peticion=P&sesion=JWT' }));
  assert.equal(r.status, 302);
  assert.equal(r.headers.get('location'), INTRANET + '/intranet/ia/conectar/?error=contrasena_no_reciente');
  assert.deepEqual(cerradas, ['JWT']);
});

test('/token: canje y refresco pasan a la base; errores OAuth con su estado y no-store', async () => {
  const { atiende, llamadas } = monta({
    canjea: { access_token: 'A', refresh_token: 'R', expires_in: 3600 },
    refresca: { error: 'invalid_grant' },
  });
  let r = await atiende(pide('/token', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: 'grant_type=authorization_code&code=C&code_verifier=V&client_id=c&redirect_uri=u' }));
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await r.json(), { access_token: 'A', refresh_token: 'R', token_type: 'Bearer', expires_in: 3600 });
  assert.equal(llamadas[0].datos.code_verifier, 'V');
  r = await atiende(pide('/token', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: 'grant_type=refresh_token&refresh_token=R&client_id=c' }));
  assert.equal(r.status, 400);
  assert.deepEqual(await r.json(), { error: 'invalid_grant' });
  r = await atiende(pide('/token', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' }));
  assert.equal(r.status, 400);
  r = await atiende(pide('/token', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: 'grant_type=password' }));
  assert.deepEqual(await r.json(), { error: 'unsupported_grant_type' });
});

test('MCP: sin token o con token muerto → 401 con resource_metadata; ni siquiera se enseña la lista', async () => {
  const { atiende } = monta({ comprueba: { error: 'invalid_token' } });
  let r = await atiende(pide('/', { method: 'POST', body: '{}' }));
  assert.equal(r.status, 401);
  assert.match(r.headers.get('www-authenticate'), /resource_metadata="https:\/\/ref\.supabase\.co\/functions\/v1\/mcp\/\.well-known\/oauth-protected-resource"/);
  r = await atiende(rpc({ jsonrpc: '2.0', id: 1, method: 'tools/list' }));
  assert.equal(r.status, 401);
});

test('MCP: Origin ajeno 403, sin Origin pasa; versión no admitida 400; GET 405', async () => {
  const { atiende } = monta({ comprueba: { ok: true } });
  assert.equal((await atiende(rpc({ jsonrpc: '2.0', id: 1, method: 'ping' }, { origin: 'https://malo.example' }))).status, 403);
  assert.equal((await atiende(rpc({ jsonrpc: '2.0', id: 1, method: 'ping' }))).status, 200);
  assert.equal((await atiende(rpc({ jsonrpc: '2.0', id: 1, method: 'ping' }, { 'mcp-protocol-version': '1999-01-01' }))).status, 400);
  assert.equal((await atiende(pide('/', { method: 'GET' }))).status, 405);
});

test('MCP: initialize y tools/list con token vivo; notificación → 202', async () => {
  const { atiende } = monta({ comprueba: { ok: true } });
  let r = await (await atiende(rpc({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18' } }))).json();
  assert.equal(r.result.protocolVersion, '2025-06-18');
  assert.deepEqual(r.result.capabilities, { tools: { listChanged: false } });
  r = await (await atiende(rpc({ jsonrpc: '2.0', id: 2, method: 'tools/list' }))).json();
  assert.deepEqual(r.result.tools.map((t) => t.name), ['facturas_no_cobradas']);
  assert.equal((await atiende(rpc({ jsonrpc: '2.0', method: 'notifications/initialized' }))).status, 202);
});

test('MCP tools/call: solo herramientas de la lista; pasa el access y el recurso; token muerto → 401; error → isError', async () => {
  let { atiende, llamadas } = monta({ llama: { datos: [{ factura_id: 'f' }] } });
  let r = await (await atiende(rpc({ jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'contratos_equipo' } }))).json();
  assert.equal(r.error.code, -32602);
  assert.equal(llamadas.length, 0, 'una herramienta fuera de la lista ni llega a la base');
  r = await (await atiende(rpc({ jsonrpc: '2.0', id: 4, method: 'tools/call', params: { name: 'facturas_no_cobradas', arguments: { x: 1 } } }))).json();
  assert.deepEqual(r.result.structuredContent, { datos: [{ factura_id: 'f' }] });
  assert.deepEqual(llamadas[0], { accion: 'llama', datos: { access_token: 'acc', recurso: EMISOR, herramienta: 'facturas_no_cobradas', argumentos: { x: 1 } } });
  ({ atiende } = monta({ llama: { error: 'invalid_token', motivo: 'revocada' } }));
  assert.equal((await atiende(rpc({ jsonrpc: '2.0', id: 5, method: 'tools/call', params: { name: 'facturas_no_cobradas' } }))).status, 401);
  ({ atiende } = monta({ llama: { error: 'tope' } }));
  r = await (await atiende(rpc({ jsonrpc: '2.0', id: 6, method: 'tools/call', params: { name: 'facturas_no_cobradas' } }))).json();
  assert.equal(r.result.isError, true);
});

test('MCP: cuerpo malo, lotes y peticiones enormes se rechazan sin llamar a la base', async () => {
  const { atiende, llamadas } = monta();
  assert.equal((await atiende(pide('/', { method: 'POST', headers: { Authorization: 'Bearer acc' }, body: '{no' }))).status, 400);
  assert.equal((await atiende(rpc([{ jsonrpc: '2.0', id: 1, method: 'ping' }]))).status, 400);
  assert.equal((await atiende(pide('/', { method: 'POST', headers: { Authorization: 'Bearer acc' }, body: 'x'.repeat(20000) }))).status, 413);
  assert.equal(llamadas.length, 0);
});

test('sin llaves: el directorio de la edge no nombra la clave de servicio ni pide tokens de Auth', () => {
  for (const f of readdirSync(AQUI)) {
    if (f.endsWith('.test.js')) continue;
    const t = readFileSync(join(AQUI, f), 'utf8');
    assert.doesNotMatch(t, /SERVICE_ROLE|service_role|sb_secret_|auth\/v1\/token/, f);
  }
});

test('herramientas: nombres únicos en minúscula, esquema de objeto y descripción que avisa de que son datos', () => {
  const nombres = HERRAMIENTAS.map((h) => h.name);
  assert.equal(new Set(nombres).size, nombres.length);
  for (const h of HERRAMIENTAS) {
    assert.match(h.name, /^[a-z_]+$/);
    assert.equal(h.inputSchema?.type, 'object');
    assert.equal(h.inputSchema?.additionalProperties, false);
    assert.ok(h.description && h.description.length < 600);
    assert.equal(h.annotations?.readOnlyHint, true);
  }
});
