// portal-acceso — entrada de autoservicio al portal del comprador (8-sep-2026).
//
// Hermana de `portal-invitar`, no una acción suya, porque el modelo de
// autorización es el contrario: `portal-invitar` decide con el JWT de un admin
// de la suite; ésta se llama SIN sesión (quien entra al portal todavía no tiene
// cuenta). Colgar una acción sin autenticar de la función que autoriza por JWT
// es la clase de mezcla que acaba abriendo la que no tocaba.
//
// Qué hace: pregunta a `portal_autoservicio()` si a ese correo le corresponde
// el portal (ficha de comprador con contrato, no del equipo, no revocado). Si
// sí, se asegura de que exista la cuenta de Auth con `app_metadata.portal` y le
// manda el enlace de entrada. La REGLA vive en SQL, aquí solo lo que exige
// service_role.
//
// ⚠️ Respuesta uniforme a propósito: un correo que no da acceso recibe
// exactamente lo mismo que uno que sí. Si contestara distinto, este formulario
// sería un buscador público de «¿quién ha comprado en Lawang?».
//
// La única excepción es `reintentar:true` cuando el envío falla de verdad, y es
// deliberada: sí, distingue a un elegible de uno que no lo es. Se acepta porque
// el fallo contrario ya ocurrió y es peor — el 8-sep había 18 invitaciones a
// compradores reales con CERO entradas, y la sospecha es que varias nunca
// salieron (SMTP por defecto de Supabase, ~4 correos/hora) mientras la pantalla
// decía «enviado». Decirle a alguien que revise un buzón donde no hay nada es la
// avería que estamos arreglando; no se puede reintroducir aquí.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const admin = createClient(URL_SB, SERVICE);

const PORTAL_URL = 'https://lawangproperties.com/portal/';

const ORIGENES = [
  'https://lawangproperties.com',
  'https://www.lawangproperties.com',
  'https://sumbahills.lawangproperties.com',
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

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) =>
    new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);

  let email = '';
  try {
    const body = await req.json().catch(() => ({}));
    email = String(body.email ?? '').trim().toLowerCase();

    // El motivo real solo viaja al log: es lo único que permite auditar por qué
    // alguien no entró, sin decírselo a quien pregunta desde fuera.
    const anota = (m: string) => console.log('portal-acceso ' + m + ' <' + email + '>');

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      anota('email_invalido');
      return json({ ok: true });
    }

    const { data: veredicto, error: eRpc } = await admin.rpc('portal_autoservicio', { p_email: email });
    if (eRpc) {
      console.error('portal-acceso rpc_fallo <' + email + '>: ' + eRpc.message);
      return json({ error: 'no_disponible' }, 500);
    }
    const v = (veredicto ?? {}) as { elegible?: boolean; motivo?: string; creadas?: number };
    if (!v.elegible) {
      anota('sin_derecho:' + (v.motivo ?? '?'));
      return json({ ok: true });
    }
    if (v.creadas) anota('acceso_creado_por_regla:' + v.creadas);

    // ── la cuenta de Auth ────────────────────────────────────────────────
    // Mismo paginado de 1000 que portal-invitar: sobra con los volúmenes de la
    // promotora, y si algún día no sobra hay que cambiarlo en los DOS sitios.
    const { data: lista, error: eLista } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (eLista) {
      console.error('portal-acceso listUsers <' + email + '>: ' + eLista.message);
      return json({ error: 'no_disponible' }, 500);
    }
    let user = (lista?.users ?? []).find((u) => (u.email ?? '').toLowerCase() === email) ?? null;

    if (!user) {
      const { data: creado, error: eCrear } = await admin.auth.admin.createUser({
        email, email_confirm: true,
        app_metadata: { portal: true },
      });
      if (eCrear || !creado?.user) {
        console.error('portal-acceso createUser <' + email + '>: ' + (eCrear?.message ?? 'sin usuario'));
        return json({ error: 'no_disponible' }, 500);
      }
      user = creado.user;
      anota('cuenta_creada');
    } else if (!(user.app_metadata as Record<string, unknown> | null)?.portal) {
      // Existe la cuenta pero sin el claim: sin él, `es_portal()` es false y el
      // portal se abriría vacío. Solo llega aquí quien ya pasó el filtro de la
      // regla, así que ponérselo no amplía a nadie.
      const { error: eMeta } = await admin.auth.admin.updateUserById(user.id, {
        app_metadata: { ...(user.app_metadata ?? {}), portal: true },
      });
      if (eMeta) {
        console.error('portal-acceso claim <' + email + '>: ' + eMeta.message);
        return json({ error: 'no_disponible' }, 500);
      }
      anota('claim_puesto');
    }

    // ── el enlace ────────────────────────────────────────────────────────
    // `shouldCreateUser:false` sigue siendo obligatorio: la cuenta ya está
    // creada arriba, y dejarlo en true convertiría este endpoint en un alta
    // abierta para cualquier correo si algún día la regla fallara.
    // El freno contra el abuso (mandarle enlaces a un comprador a base de
    // repetir el formulario) es el rate-limit de GoTrue por correo, no algo
    // propio — verificar que sigue ahí si se cambia de proveedor de Auth.
    const pub = createClient(URL_SB, ANON);
    const { error: eOtp } = await pub.auth.signInWithOtp({
      email,
      options: { shouldCreateUser: false, emailRedirectTo: PORTAL_URL },
    });
    if (eOtp) {
      console.error('portal-acceso envio <' + email + '>: ' + eOtp.message);
      return json({ ok: true, reintentar: true });
    }
    anota('enlace_enviado');
    return json({ ok: true });
  } catch (e) {
    console.error('portal-acceso excepcion <' + email + '>: ' + String((e as Error)?.message ?? e));
    return json({ error: 'no_disponible' }, 500);
  }
});
