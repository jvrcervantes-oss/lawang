// editor-ia — 13-oct-2026. Asistente de redacción (accion «propone») y traducción (accion «traduce», motor IA o DeepL) del
// editor de textos de contrato (/intranet/v4/textos-contrato/). Construido APAGADO: la base rechaza la reserva hasta que el
// owner ponga los precios y encienda una empresa, y sin la clave de su proveedor esta función no llama a nadie.
// La lógica vive en motor.js (se prueba en node con respuestas simuladas: editor-ia.test.js). Aquí solo se cablea Deno.
//
// SECRETOS (los pone el owner; ninguno existe todavía):
//   EDITOR_IA_ANTHROPIC_KEY   clave PROPIA de este asistente, con su límite de gasto en el panel del proveedor. No es la
//                             ANTHROPIC_API_KEY de asistente-peticiones: así encender el editor no gasta de la otra ni al revés.
//   EDITOR_IA_DEEPL_KEY       clave de DeepL (si termina en «:fx» es de la cuenta gratuita y va a su dirección).
// La clave de servicio se usa SOLO para auth.getUser y para editor_ia_cierra (tokens reales); nunca para el texto del contrato.
// verify_jwt = true en config.toml (como asistente-peticiones); dentro se vuelve a comprobar la sesión (getUser) y el rol (RPC).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { crea } from './motor.js';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const admin = createClient(URL_SB, SERVICE);

const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('');

Deno.serve(crea({
  usuario: async (jwt: string) => {
    const { data, error } = await admin.auth.getUser(jwt);
    return error || !data?.user ? null : { id: data.user.id, email: data.user.email ?? '' };
  },
  comoUsuario: (jwt: string) => createClient(URL_SB, ANON, { global: { headers: { Authorization: 'Bearer ' + jwt } } }),
  servicio: admin,
  fetch: (u: string, o: RequestInit) => fetch(u, o),
  claves: { anthropic: Deno.env.get('EDITOR_IA_ANTHROPIC_KEY') ?? '', deepl: Deno.env.get('EDITOR_IA_DEEPL_KEY') ?? '' },
  sha256: async (s: string) => hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s))),
}));
