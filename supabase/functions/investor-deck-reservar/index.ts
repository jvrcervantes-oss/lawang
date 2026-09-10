// investor-deck-reservar — cierra el flujo de autoservicio del Investor Deck
// (revisión previa Seguridad+Legal+Desarrollo, 10-sep-2026). Verifica el
// código de un solo uso y, si cuadra, llama a la RPC investor_deck_reservar()
// (service_role, único llamante permitido). Nunca reenvía el texto crudo de un
// error interno — la RPC ya devuelve motivos genéricos, y aquí se mantiene esa
// disciplina en cualquier excepción no prevista.
//
// ⚠️ PENDIENTE DE DESPLIEGUE: mismo motivo que investor-deck-codigo (ver su
// cabecera) — el clasificador de permisos de Auto Mode bloqueó el
// `deploy_edge_function` del MCP para las dos funciones de esta pieza.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(URL_SB, SERVICE);

const ORIGENES = [
  'https://lawangproperties.com',
  'https://www.lawangproperties.com',
];
const corsFor = (req: Request) => {
  const o = req.headers.get('origin') ?? '';
  const ok = ORIGENES.includes(o) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(o);
  return {
    'Access-Control-Allow-Origin': ok ? o : ORIGENES[0],
    'Access-Control-Allow-Headers': 'content-type, authorization, apikey',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    Vary: 'Origin',
  };
};

async function sha256(s: string) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

// cooldown por email, igual de best-effort que en las hermanas de este mismo repo.
const ultimoIntento = new Map<string, number>();
const COOLDOWN_MS = 3000;

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) =>
    new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ ok: false, motivo: 'metodo' }, 405);

  let email = '';
  try {
    const body = await req.json().catch(() => ({}));
    email = String(body.email ?? '').trim().toLowerCase();
    const codigo = String(body.codigo ?? '').trim();
    const consentimiento = body.consentimiento === true;
    const proyecto = String(body.proyecto ?? '').trim();
    const parcela = String(body.parcela_codigo ?? '').trim();
    const nombre = String(body.nombre ?? '').trim();
    const pasaporte = String(body.pasaporte ?? '').trim();
    const telefono = String(body.telefono ?? '').trim();
    const nacionalidad = String(body.nacionalidad ?? '').trim();
    const domicilio = String(body.domicilio ?? '').trim();

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ ok: false, motivo: 'datos_incompletos' });
    if (!consentimiento) return json({ ok: false, motivo: 'falta_consentimiento' });
    if (!proyecto || !parcela || !nombre || !pasaporte) return json({ ok: false, motivo: 'datos_incompletos' });

    const ahora = Date.now();
    const previo = ultimoIntento.get(email) ?? 0;
    if (ahora - previo < COOLDOWN_MS) return json({ ok: false, motivo: 'espera_un_momento' });
    ultimoIntento.set(email, ahora);

    // ── verificación del código ──────────────────────────────────────────
    const codigoHash = await sha256(codigo);
    const { data: fila, error: eSel } = await admin
      .from('investor_deck_verificaciones')
      .select('id, expira_at, usado, intentos')
      .eq('email', email)
      .eq('usado', false)
      .order('creado_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (eSel) {
      console.error('investor-deck-reservar select_verif <' + email + '>: ' + eSel.message);
      return json({ ok: false, motivo: 'no_disponible' });
    }
    if (!fila || new Date(fila.expira_at).getTime() < ahora) {
      return json({ ok: false, motivo: 'codigo_invalido' });
    }
    if (fila.intentos >= 5) {
      return json({ ok: false, motivo: 'codigo_invalido' });
    }
    // hash constante: comparar strings ya es suficiente aquí (no es un secreto
    // de sesión de larga vida, caduca en 10 min y se invalida tras 5 intentos).
    const codigoOk = await admin
      .from('investor_deck_verificaciones')
      .select('codigo_hash')
      .eq('id', fila.id)
      .single();
    if (codigoOk.error || codigoOk.data?.codigo_hash !== codigoHash) {
      await admin.from('investor_deck_verificaciones').update({ intentos: fila.intentos + 1 }).eq('id', fila.id);
      return json({ ok: false, motivo: 'codigo_invalido' });
    }
    await admin.from('investor_deck_verificaciones').update({ usado: true }).eq('id', fila.id);

    // ── la reserva en sí, en la RPC (bloqueo atómico + transacción) ───────
    const { data: resultado, error: eRpc } = await admin.rpc('investor_deck_reservar', {
      p_proyecto: proyecto,
      p_codigo: parcela,
      p_email: email,
      p_nombre: nombre,
      p_pasaporte: pasaporte,
      p_telefono: telefono,
      p_nacionalidad: nacionalidad,
      p_domicilio: domicilio,
    });
    if (eRpc) {
      console.error('investor-deck-reservar rpc <' + email + '>: ' + eRpc.message);
      return json({ ok: false, motivo: 'no_disponible' });
    }
    return json(resultado ?? { ok: false, motivo: 'no_disponible' });
  } catch (e) {
    console.error('investor-deck-reservar excepcion <' + email + '>: ' + String((e as Error)?.message ?? e));
    return json({ ok: false, motivo: 'no_disponible' }, 500);
  }
});
