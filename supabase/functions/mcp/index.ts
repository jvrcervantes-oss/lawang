// mcp — 16-oct-2026. Puente MCP de Lawang (encargos/20261015_erp_mcp.md, «Lawang F1-P3»). La lógica vive en motor.js (probada en
// node: mcp.test.js); aquí solo se cablea Deno.
// SIN LLAVES (regla 1 del encargo): usa la URL del proyecto y la clave PUBLICABLE (SUPABASE_ANON_KEY, que Supabase inyecta en toda
// edge). Nunca la clave de servicio: mcp.test.js falla si este directorio la nombra.
// verify_jwt = false en config.toml: el asistente trae un token OPACO del puente (no un JWT de Supabase) y el 401 tiene que salir de
// aquí con su WWW-Authenticate (si lo diera la pasarela, el asistente no encontraría el servidor de autorización).
import { crea } from './motor.js';
import { HERRAMIENTAS } from './herramientas.js';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const PUBLICA = Deno.env.get('SUPABASE_ANON_KEY')!;
const EMISOR = URL_SB.replace(/\/$/, '') + '/functions/v1/mcp';
const INTRANET = 'https://lawangproperties.com';

async function rpc(nombre: string, cuerpo: unknown, bearer = PUBLICA) {
  const r = await fetch(`${URL_SB}/rest/v1/rpc/${nombre}`, {
    method: 'POST',
    headers: { apikey: PUBLICA, Authorization: 'Bearer ' + bearer, 'Content-Type': 'application/json' },
    body: JSON.stringify(cuerpo),
    signal: AbortSignal.timeout(8000),
  });
  if (r.status === 401 || r.status === 403) return { error: 'invalid_request' };
  if (!r.ok) return { error: 'server_error' };
  return await r.json();
}

Deno.serve(crea({
  recurso: EMISOR,
  emisor: EMISOR,
  conectar: INTRANET + '/intranet/v4/ia/conectar/',
  origenIntranet: INTRANET,
  herramientas: HERRAMIENTAS,
  puente: (accion: string, datos: unknown) => rpc('ia_puente', { p_accion: accion, p_datos: datos }),
  autoriza: (sesion: string, peticion: string) => rpc('ia_conexion_autoriza', { p_peticion: peticion }, sesion),
  cierraSesion: (sesion: string) =>
    fetch(`${URL_SB}/auth/v1/logout?scope=local`, {
      method: 'POST',
      headers: { apikey: PUBLICA, Authorization: 'Bearer ' + sesion },
      signal: AbortSignal.timeout(5000),
    }),
}));
