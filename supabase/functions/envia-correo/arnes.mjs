// Arnés de pruebas de la edge `envia-correo` SIN Deno y SIN red (no hay deno en todas las máquinas).
// Node ≥ 22.18 carga los .ts quitándoles los tipos, así que las pruebas ejecutan el `index.ts` REAL, no una copia:
//   · `Deno` es un doble (env de un mapa, serve/test recogidos);
//   · `npm:nodemailer` lo sustituye nodemailer_falso.mjs (nada se envía, nada abre un socket);
//   · `fetch` es un enrutador local que contesta lo que contestaría Supabase (config, sesión, pausa, PDF).
// Es idéntico en Lawang y en el maestro (test_canon_envia_correo.py lo comprueba).
import { register } from 'node:module';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

register('./arnes_hooks.mjs', import.meta.url);

export const UID = '11111111-2222-3333-4444-555555555555';
export const BASE_ENV = {
  SUPABASE_URL: 'https://ref.supabase.co', SUPABASE_ANON_KEY: 'anon-falsa', SUPABASE_SERVICE_ROLE_KEY: 'service-falsa',
  SMTP_HOST: 'smtp.falso.test', SMTP_PORT: '465', SMTP_USER: 'buzon@ejemplo.com', SMTP_PASS: 'clave-falsa',
  SMTP_FROM: 'buzon@ejemplo.com', SMTP_FROM_NAME: 'Acme',
  RENDER_SECRET: 'render-falso', PDF_SERVICE_URL: 'https://pdf.falso.test',
};
export const CONFIG_BASE = [
  ['marca', 'Acme'], ['dominio_web', 'ejemplo.com'], ['url_intranet', 'https://erp.ejemplo.com/intranet/'],
  ['email_avisos_soporte', 'soporte@ejemplo.com'], ['email_avisos_sistema', 'sistema@ejemplo.com'],
  ['email_avisos_reservas', 'reservas@ejemplo.com'],
];

export const estado = {};
const denoTests = [];
let n = 0;

/** Deja el arnés como nuevo. `env` se suma a BASE_ENV; `config` sustituye a CONFIG_BASE ([clave, valor]). */
export function reinicia({ env = {}, config = CONFIG_BASE, pausado = false, sesion = false, pdf = true } = {}) {
  Object.assign(estado, { env: { ...BASE_ENV, ...env }, config, pausado, sesion, pdf, llamadas: [], logs: [] });
  globalThis.__arnesCorreo = { correos: [], transportes: [], falloSmtp: null };
  estado.correo = globalThis.__arnesCorreo;
}
reinicia();

globalThis.Deno = {
  env: { get: (k) => estado.env[k] },
  serve: () => ({}),
  test: (a, b) => { denoTests.push(typeof a === 'string' ? [a, b] : [a.name, a.fn]); },
};

const PDF = new TextEncoder().encode('%PDF-1.7 falso');
globalThis.fetch = async (url, init = {}) => {
  const u = String(url);
  estado.llamadas.push({ url: u, cabeceras: init.headers ?? {} });
  const json = (o, status = 200) => new Response(JSON.stringify(o), { status });
  if (u.includes('/rest/v1/config_instancia')) return json(estado.config.map(([clave, valor]) => ({ clave, valor })));
  if (u.includes('/auth/v1/user')) return estado.sesion ? json({ id: UID }) : json({}, 401);
  if (u.includes('/rest/v1/usuarios')) return estado.sesion ? json([{ user_id: UID }]) : json([]);
  if (u.includes('/rest/v1/rpc/envios_pausados')) {
    if (estado.pausado === 'error') return new Response('boom', { status: 500 });
    return new Response(estado.pausado ? 'true' : 'false', { status: 200 });
  }
  if (u.endsWith('/render-pdf')) return estado.pdf ? new Response(PDF, { status: 200 }) : new Response('no', { status: 503 });
  throw new Error('arnes: fetch no previsto: ' + u);
};

/** Instancia NUEVA de index.ts (módulo recién evaluado: caché de config y freno de avisos en cero). */
export async function cargaEdge(dir) {
  n += 1;
  const m = await import(pathToFileURL(path.join(dir, 'index.ts')).href + '?arnes=' + n);
  return m.manejador;
}

/** Llama al manejador y devuelve {status, cuerpo (objeto), crudo, logs de esa llamada}. */
export async function llama(manejador, { metodo = 'POST', cabeceras = {}, cuerpo } = {}) {
  const antes = estado.logs.length;
  const orig = { log: console.log, error: console.error };
  console.log = (...a) => { estado.logs.push(a.join(' ')); };
  console.error = (...a) => { estado.logs.push(a.join(' ')); };
  let r;
  try {
    r = await manejador(new Request('https://ref.supabase.co/functions/v1/envia-correo', {
      method: metodo, headers: cabeceras, body: metodo === 'POST' ? JSON.stringify(cuerpo ?? {}) : undefined,
    }));
  } finally { console.log = orig.log; console.error = orig.error; }
  const crudo = await r.text();
  let obj = null; try { obj = JSON.parse(crudo); } catch { /* respuesta sin JSON (204 de OPTIONS) */ }
  return { status: r.status, cuerpo: obj, crudo, logs: estado.logs.slice(antes) };
}

/** La línea JSON de log de una llamada (la de console.log; console.error lleva texto suelto). */
export function lineaJson(res) {
  for (const l of res.logs) { try { const o = JSON.parse(l); if (o.fn === 'envia-correo') return o; } catch { /* no es JSON */ } }
  return null;
}

/** Corre un `*_test.ts` escrito para `deno test` con el doble de Deno.test. Devuelve cuántas pruebas pasaron. */
export async function correDenoTest(fichero) {
  denoTests.length = 0;
  await import(pathToFileURL(fichero).href + '?deno=' + (++n));
  const lote = denoTests.splice(0);
  let ok = 0;
  for (const [nombre, fn] of lote) {
    try { await fn(); ok += 1; } catch (e) { throw new Error(`[${path.basename(fichero)}] «${nombre}»: ${e && e.message ? e.message : e}`); }
  }
  return ok;
}
