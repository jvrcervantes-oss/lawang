// admin-usuarios — alta de usuarios de la suite y reseteo de contraseñas.
//
// Existe porque la Admin API de Supabase (crear usuario, cambiar contraseña)
// necesita `service_role`, y esa clave NO puede vivir en el navegador. Todo lo
// demás (rol, herramientas, activar/desactivar) lo hace el panel directamente
// contra `public.usuarios` con la RLS puesta — no hace falta pasar por aquí.
//
// ⚠️ La autorización se decide SIEMPRE con el JWT de quien llama, nunca con un
// campo del body: un body es texto que escribe el cliente. Desplegar con
// verify_jwt=false (la validación se hace dentro, para poder devolver errores
// legibles en vez de un 401 opaco del gateway).
import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const admin = createClient(URL_SB, SERVICE);

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

// 5-ago-2026: añadidas 'documentacion' y 'obra'. 11-ago-2026: añadida
// 'creatividades' — 3ª vez que esta lista se queda corta respecto al panel
// /usuarios/ y una herramienta se pierde al crear un usuario (no al editar).
//
// 17-ago-2026 (auditoría): la lista sigue AQUÍ y no se lee de
// `assets/herramientas.js`, a propósito — una edge que se descarga código del
// sitio para ejecutarlo es exactamente lo que hay que dejar de hacer (ver el
// hallazgo 01 de la auditoría y `firma-submit`). Lo que cambia es que ya no puede
// quedarse corta en silencio: la comprueba `tools/test_listas_lawang.py`, que
// falla si no coincide con el catálogo, y las desconocidas se RECHAZAN en vez de
// filtrarse (ver abajo). Las tres veces que esta lista se quedó corta pasaron
// desapercibidas por el `.filter()`: descartar sin avisar convierte un error de
// programación en un permiso que falta y que nadie relaciona con esto.
const HERRAMIENTAS = ['contratos', 'facturas', 'operaciones', 'unidades', 'compradores', 'obra', 'dossier', 'documentacion', 'usuarios', 'creatividades', 'vencimientos'];
const ROLES = ['super_admin', 'admin', 'agente'];

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) =>
    new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);

  try {
    // ── quién llama ──────────────────────────────────────────────────────
    const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (!jwt) return json({ error: 'sin_sesion' }, 401);
    const { data: quien, error: eUser } = await admin.auth.getUser(jwt);
    if (eUser || !quien?.user) return json({ error: 'sesion_invalida' }, 401);

    // ── ¿es admin, Y tiene la herramienta? Se pregunta a la tabla, no al token ──
    // La herramienta se exige desde el 18-ago-2026: los admin pasaron a estar
    // limitados por `usuarios.herramientas` y las policies de `usuarios` ahora
    // piden `es_admin() AND puede('usuarios')`. Esta función corre con
    // service_role y se SALTA la RLS, así que sin esta comprobación sería la
    // puerta de servicio por la que un admin sin el permiso seguiría dando de
    // alta usuarios — justo lo que el owner pidió cerrar.
    const { data: ficha, error: eFicha } = await admin
      .from('usuarios').select('rol, activo, herramientas').eq('user_id', quien.user.id).maybeSingle();
    if (eFicha) return json({ error: 'no_se_pudo_comprobar_permiso' }, 500);
    if (!ficha || !ficha.activo || !['super_admin', 'admin'].includes(ficha.rol))
      return json({ error: 'no_autorizado' }, 403);
    const soySuper = ficha.rol === 'super_admin';
    if (!soySuper && !(ficha.herramientas ?? []).includes('usuarios'))
      return json({ error: 'no_autorizado: te falta la herramienta «usuarios»' }, 403);

    const body = await req.json().catch(() => ({}));
    const accion = String(body.accion ?? '');

    // ── crear usuario ────────────────────────────────────────────────────
    if (accion === 'crear') {
      const email = String(body.email ?? '').trim().toLowerCase();
      const password = String(body.password ?? '');
      const rol = String(body.rol ?? 'agente');
      const nombre = String(body.nombre ?? '').trim() || null;
      // Se RECHAZA lo desconocido, no se filtra (17-ago-2026): un `.filter()` aquí
      // deja al usuario creado sin ese permiso y sin que nadie se entere, que es
      // cómo esta lista se quedó corta tres veces. Un 400 se arregla el mismo día.
      const pedidas: string[] = Array.isArray(body.herramientas) ? body.herramientas.map(String) : [];
      const desconocidas = pedidas.filter((h) => !HERRAMIENTAS.includes(h));
      if (desconocidas.length)
        return json({ error: 'herramienta_desconocida', detalle: desconocidas,
                      ayuda: 'Esta función no conoce esa herramienta. Si es nueva, añádela a HERRAMIENTAS en admin-usuarios y redespliega.' }, 400);
      const herramientas: string[] = pedidas;
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: 'email_invalido' }, 400);
      if (password.length < 10) return json({ error: 'password_corta' }, 400);   // 10+: son cuentas con datos de clientes reales
      if (!ROLES.includes(rol)) return json({ error: 'rol_invalido' }, 400);
      // Un admin no puede fabricar admins: sería una escalada de privilegio en
      // un clic. Solo el super_admin reparte poder.
      if (rol !== 'agente' && !soySuper) return json({ error: 'solo_super_admin_crea_admins' }, 403);

      const { data: creado, error: eCrear } = await admin.auth.admin.createUser({
        email, password, email_confirm: true,
        // el flag legacy se mantiene por compatibilidad con es_agente(): si un
        // día se borrara su ficha de `usuarios`, no queda una cuenta huérfana
        // sin poder entrar ni evidencia de qué era.
        app_metadata: { agente: true },
      });
      if (eCrear || !creado?.user) return json({ error: eCrear?.message ?? 'no_se_pudo_crear' }, 400);

      const { error: eFila } = await admin.from('usuarios').insert({
        user_id: creado.user.id, email, nombre, rol, herramientas, activo: true,
        creado_por: quien.user.email ?? null,
      });
      if (eFila) {
        // sin ficha, la cuenta existiría en auth pero sin permisos ni rastro en
        // el panel: se deshace para no dejar usuarios fantasma
        await admin.auth.admin.deleteUser(creado.user.id);
        return json({ error: 'no_se_pudo_registrar: ' + eFila.message }, 500);
      }
      return json({ ok: true, user_id: creado.user.id, email });
    }

    // ── cambiar contraseña ───────────────────────────────────────────────
    if (accion === 'password') {
      const user_id = String(body.user_id ?? '');
      const password = String(body.password ?? '');
      if (!user_id) return json({ error: 'falta_usuario' }, 400);
      if (password.length < 10) return json({ error: 'password_corta' }, 400);
      // un admin no resetea la contraseña de un super_admin (sería apoderarse
      // de su cuenta); el super_admin sí puede con cualquiera
      const { data: destino } = await admin.from('usuarios').select('rol').eq('user_id', user_id).maybeSingle();
      if (destino && destino.rol === 'super_admin' && !soySuper)
        return json({ error: 'no_autorizado' }, 403);
      const { error } = await admin.auth.admin.updateUserById(user_id, { password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    return json({ error: 'accion_desconocida' }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
