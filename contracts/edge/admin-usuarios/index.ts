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
// /intranet/usuarios/ y una herramienta se pierde al crear un usuario (no al editar).
// 18-ago-2026: añadida 'vencimientos', que hasta hoy compartía la clave de
// 'operaciones' y por eso no aparecía en el panel de permisos.
// 1-sep-2026: añadida 'soporte' (fusión Soporte+Mensajes en un hilo), cazada
// por `listas.test.js` antes de desplegar — la 4ª vez que esta lista se queda
// corta, siempre por el mismo motivo: una herramienta nueva en el catálogo
// que no se replica aquí a mano.
//
// 17-ago-2026 (auditoría): la lista sigue AQUÍ y no se lee de
// `assets/herramientas.js`, a propósito — una edge que se descarga código del
// sitio para ejecutarlo es exactamente lo que hay que dejar de hacer (ver el
// hallazgo 01 de la auditoría y `firma-submit`). Lo que cambia es que ya no puede
// quedarse corta en silencio: la comprueba `contracts/listas.test.js`, que
// falla si no coincide con el catálogo, y las desconocidas se RECHAZAN en vez de
// filtrarse (ver abajo). Las tres veces que esta lista se quedó corta pasaron
// desapercibidas por el `.filter()`: descartar sin avisar convierte un error de
// programación en un permiso que falta y que nadie relaciona con esto.
// 9-sep-2026: añadida 'leads' (CRM de leads de Meta). Es la primera clave nueva desde
// 'vencimientos': las herramientas intermedias (Modelos, Solicitudes) reutilizaron
// 'operaciones' porque esta edge estaba sin poder redesplegarse. Ésta no lo hace: abre
// datos de contacto de un centenar de personas y eso tiene que poder darse cuenta a
// cuenta.
// 'closers' (agenda de cierre): alta el 10-sep, retirada el 11-sep por un
// malentendido y REPUESTA el mismo dia. El owner habia pedido quitar el ATAJO
// del menu lateral, no dar de baja la herramienta: «necesitamos que exista una
// agenda para los closers en el CRM sin duda, pero no es un acceso directo
// desde el menu como estaba». Retirarla entera dejo la pestana «Agenda» viva
// dentro del CRM pero imposible de conceder: solo la veia un super_admin. En
// LW_HERRAMIENTAS lleva `soloPermiso`, que es como se dicen las dos cosas a la
// vez (casilla si, entrada de menu no).
// 'reparto' (11-sep-2026): configurar que closer atiende que campana. Separado de
// 'ranking' por peticion de Seguridad -- quien puede corregir la atribucion de una
// venta mueve el ranking, y el ranking decide la cuota del reparto; juntar las dos
// llaves deja que una misma persona decida que es la #1 y que la #1 reciba el doble.
// 'ranking' (11-sep-2026) es permiso PROPIO y no cuelga de 'leads' a propósito, por el
// mismo criterio que separó 'closers' en su día: lo que abre es cuánto factura y cuánto
// cobra cada comercial, y con ocho de ellos eso no son estadísticas, son cifras de contrato
// (el ticket medio por el número devuelve el importe exacto). El día que se le dé el CRM a
// un comercial no se le puede regalar de paso la tabla de comisiones de sus compañeros.
// 'cuentas' (14-sep-2026): el panel de cuentas de cobro y del reparto por tipo de
// contrato (/intranet/cuentas/). La casilla se concede como cualquier otra, pero
// aquí NO está toda la historia: ESCRIBIR esas tablas exige `es_super_admin()` en
// la propia base, así que un admin con esta casilla marcada solo puede MIRAR el
// reparto. Es deliberado — es el dato que decide adónde transfiere el comprador —
// y se apunta aquí porque desde esta función parece un permiso normal.
// 'comisiones' (23-sep-2026, owner: «comisiones no quiero que las vea nadie
// ahora mismo»): la pantalla de comisiones/solicitudes colgaba de 'operaciones'
// y no se podía quitar sin quitar Operaciones. Clave propia y, A PROPÓSITO, sin
// concedérsela a nadie (al revés que 'vencimientos' el 18-ago): solo la ve un
// super_admin, que `puede()` deja pasar siempre.
const HERRAMIENTAS = ['contratos', 'facturas', 'operaciones', 'unidades', 'compradores', 'obra', 'dossier', 'documentacion', 'usuarios', 'creatividades', 'vencimientos', 'soporte', 'leads', 'closers', 'ranking', 'reparto', 'cuentas', 'comisiones', 'reservas', 'modelos', 'asistente', 'recibos', 'comisiones_reparto', 'comisiones_condiciones', 'comisiones_equipos', 'gastos', 'bancos', 'creatividades_ver'];
// 'creatividades_ver' (24-sep-2026, encargo Creatividades v4, D2): el comercial VE y
// descarga las piezas y dossiers APROBADOS. No escribe en ninguna tabla ni bucket: lo
// garantiza la RLS de `creatividades` y de storage (revisión previa #68, Seguridad).
// 'bancos' (24-sep-2026, módulo Bancos y conciliación), redesplegada con la misma receta.
// 'gastos' (24-sep-2026, módulo Gastos y proveedores). Redesplegada el mismo día
// (LAW-304) desde una carpeta temporal con COPIA REAL de este fichero: en
// Windows `supabase/functions/admin-usuarios` es un stub de texto (symlink sin
// materializar) y desplegarlo subiría el stub. Antes se descargó lo desplegado
// y se comparó con el repo: idéntico salvo esta línea.
// 'comisiones_reparto', 'comisiones_condiciones', 'comisiones_equipos' (23-sep-2026, plan
// del owner): las pestañas de «Comisiones», una casilla cada una; 'comisiones' es
// «Pagos de Lawang». Lo que se ve dentro lo decide el rol en la base.
// 'reservas', 'modelos', 'asistente', 'recibos' (23-sep-2026, owner: «separa
// todo»): colgaban de operaciones/unidades/contratos/facturas. Clave propia de
// vista; la migración 20260923180500_permisos_propios se la dio a quien ya tenía la madre.
// 10-sep-2026: sales_manager/project_manager (encargados de proyecto: ven,
// crean y corrigen contratos/facturas de cualquier agente en los proyectos
// que supervisan — `usuarios.proyectos_supervisados`, distinta de `proyectos`)
// — misma lista que usuarios_rol_check en la base. Si un día divergen, la
// base es la que manda: esto es la primera puerta, la RLS es la que de
// verdad decide.
const ROLES = ['super_admin', 'admin', 'agente', 'sales_manager', 'project_manager'];

// 11-sep-2026: preselección de tipos de contrato al crear (encargo del owner).
// Mismos valores que LW_TIPO_CONTRATO en contracts/assets/vocabulario.js —
// duplicado A PROPÓSITO, mismo motivo que HERRAMIENTAS de arriba: una edge que
// se descarga código del sitio para ejecutarlo es lo que hay que evitar.
// ⚠️ 24-sep-2026: `tipos_contrato` vacío YA NO significa "TODOS": el trigger
// contratos_tipo_permitido BLOQUEA a un agente sin tipos (verificado en la base).
// Aquí SÍ se filtra en vez de rechazar lo desconocido:
// un tipo nuevo que aún no esté en esta lista simplemente no se preselecciona,
// no bloquea el alta de nadie.
const TIPOS_CONTRATO = [
  'carta_reserva', 'carta_reserva_ampliada', 'carta_reserva_hak_sewa', 'carta_reserva_pma',
  'reserva_parcela', 'construccion', 'contrato_general', 'commercial_offer', 'acuerdo_comercial',
  'protocolo_operativo', 'ppjb_bonian', 'ppjb_bonian_c2', 'hak_sewa_notario', 'poa',
  'cc00014_timon', 'adenda', 'carta_reserva_investor_deck',
];

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
      // Un admin solo reparte herramientas que ÉL tiene (LAW-343, 27-sep-2026): el trigger
      // usuarios_bloquea_cambio_rol_herramientas ya exige super admin para cambiarlas después, pero
      // el alta pasaba por aquí con service role y dejaba regalar, p. ej., «Comisiones».
      if (!soySuper) {
        const mias = new Set((ficha.herramientas ?? []).map(String));
        const ajenas = pedidas.filter((h) => !mias.has(h));
        if (ajenas.length) return json({ error: 'herramienta_que_no_tienes', detalle: ajenas,
                                         ayuda: 'Solo puedes dar herramientas que tienes tú. Pide a un super admin el resto.' }, 403);
      }
      const herramientas: string[] = pedidas;
      const tipos_contrato: string[] = (Array.isArray(body.tipos_contrato) ? body.tipos_contrato.map(String) : [])
        .filter((t: string) => TIPOS_CONTRATO.includes(t));
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
        user_id: creado.user.id, email, nombre, rol, herramientas, tipos_contrato, activo: true,
        creado_por: quien.user.email ?? null,
      });
      if (eFila) {
        // sin ficha, la cuenta existiría en auth pero sin permisos ni rastro en
        // el panel: se deshace para no dejar usuarios fantasma
        await admin.auth.admin.deleteUser(creado.user.id);
        return json({ error: 'no_se_pudo_registrar: ' + eFila.message }, 500);
      }

      // Correo de bienvenida (17-sep-2026, encargo del owner: avisar al alta).
      // SOLO notifica que la cuenta existe y el email de acceso — la
      // CONTRASEÑA NO VIAJA por aquí: en la revisión previa Seguridad la marcó
      // como no aceptable para cuentas que tocan datos de compradores reales
      // (un email es un canal persistente y reenviable, al revés que el aviso
      // verbal que usa hoy quien da de alta). Eso no cambia: el admin le sigue
      // diciendo la contraseña a mano.
      // Vía de envío: se reenvía el MISMO jwt del admin ya validado arriba,
      // como X-Suite-Token — la vía "sesión" que ya usan contratos y facturas
      // desde el navegador (send_email.php, vía 1). Cero secretos nuevos.
      let emailEnviado = false;
      let emailError: string | null = null;
      try {
        const saludo = nombre ? nombre.split(' ')[0] : email;
        const mensaje = `Hola ${saludo},\n\n`
          + `Se ha creado tu cuenta de acceso a la intranet de Lawang Tropical Properties.\n\n`
          + `Usuario: ${email}\n\n`
          + `La contraseña te la habrá dado quien te ha dado de alta. Si no la tienes, pídesela.`;
        // 8s de tope (revisión de deploy, Seguridad, 17-sep): sin esto un SMTP
        // lento colgaba el alta del tiempo que tardara send_email.php en
        // resolver, convirtiendo un fallo de correo en un alta que parece
        // atascada — cuando el diseño es justo que un fallo de correo no
        // afecte al alta.
        const ac = new AbortController();
        const to_ = setTimeout(() => ac.abort(), 8000);
        let rEmail: Response;
        try {
          rEmail = await fetch('https://lawangproperties.com/contracts/api/send_email.php', {
            method: 'POST',
            headers: { 'content-type': 'application/json', 'X-Suite-Token': jwt },
            body: JSON.stringify({
              to: email, subject: 'Tu acceso a la intranet — Lawang Tropical Properties',
              message: mensaje, attach: false,
              cta_url: 'https://lawangproperties.com/intranet/', cta_texto: 'Entrar a la intranet',
            }),
            signal: ac.signal,
          });
        } finally {
          clearTimeout(to_);
        }
        const tEmail = await rEmail.text();
        if (rEmail.ok && tEmail.includes('"ok":true')) {
          emailEnviado = true;
        } else {
          // el detalle real (puede llevar host/puerto SMTP) se loguea server-side
          // y no viaja al navegador del admin — mismo criterio que send_email.php
          // no expone su propia config al que lo llama.
          console.error('admin-usuarios: fallo al enviar bienvenida a ' + email + ': ' + tEmail.slice(0, 300));
          emailError = 'no_se_pudo_enviar';
        }
      } catch (e) {
        console.error('admin-usuarios: excepción al enviar bienvenida a ' + email + ': ' + String((e as Error)?.message ?? e));
        emailError = 'no_se_pudo_enviar';
      }
      // un fallo de correo NO revierte el alta: la cuenta ya existe y funciona;
      // el panel avisa con email_error para que el admin le diga la contraseña
      // a mano, como hasta ahora.
      return json({ ok: true, user_id: creado.user.id, email, email_enviado: emailEnviado, email_error: emailError });
    }

    // ── solicitudes de alta desde /formacion/ (24-sep-2026) ──────────────
    // La edge pública `alta-colaborador` solo deja una fila en
    // `solicitudes_colaborador`; la cuenta nace AQUÍ, con el clic de un admin.
    // Revisión previa #61: cualquier fila activa de `usuarios` pasa es_agente()
    // y puede LEER el directorio de compradores, así que esta es la puerta.
    if (accion === 'activar_solicitud') {
      const id = String(body.solicitud_id ?? '');
      const { data: sol } = await admin.from('solicitudes_colaborador')
        .select('id, email, nombre, estado').eq('id', id).maybeSingle();
      if (!sol) return json({ error: 'solicitud_no_encontrada' }, 404);
      if (sol.estado !== 'pendiente') return json({ error: 'solicitud_ya_' + sol.estado }, 409);
      const email = String(sol.email).trim().toLowerCase();

      // Herramientas del comercial (5 %). Lista cerrada aquí, no del body: el
      // panel puede quitar alguna, nunca añadir fuera de esta lista.
      const BASE_COMERCIAL = ['leads', 'contratos', 'compradores', 'reservas', 'comisiones_reparto'];
      const pedidas: string[] = Array.isArray(body.herramientas) ? body.herramientas.map(String) : BASE_COMERCIAL;
      const herramientas = pedidas.filter((h) => BASE_COMERCIAL.includes(h));
      const tipos_contrato: string[] = (Array.isArray(body.tipos_contrato) ? body.tipos_contrato.map(String) : [])
        .filter((t: string) => TIPOS_CONTRATO.includes(t));
      // `tipos_contrato` vacío BLOQUEA a un agente (trigger contratos_tipo_permitido,
      // verificado 24-sep) y `proyectos` vacío = ninguno: sin los dos, no trabaja.
      if (!tipos_contrato.length) return json({ error: 'elige_tipos_de_contrato' }, 400);
      const pedidosProy: string[] = Array.isArray(body.proyectos) ? body.proyectos.map(String) : [];
      const { data: proyOk } = pedidosProy.length
        ? await admin.from('proyectos').select('id').in('id', pedidosProy)
        : { data: [] as { id: string }[] };
      const proyectos = (proyOk ?? []).map((p: { id: string }) => p.id);
      if (!proyectos.length) return json({ error: 'elige_proyectos' }, 400);

      const { data: ya } = await admin.from('usuarios').select('user_id').eq('email', email).maybeSingle();
      if (ya) return json({ error: 'ya_es_usuario' }, 409);

      // Sin app_metadata.agente (Seguridad #61-7): si un día se borra la fila de
      // `usuarios`, la cuenta NO debe seguir siendo agente por el claim.
      // Si el email ya existe en Auth (p. ej. un comprador del /portal/),
      // createUser falla y NO se reutiliza esa cuenta: eso convertiría a un
      // comprador en agente con acceso a los datos de los demás.
      const { data: creado, error: eCrear } = await admin.auth.admin.createUser({ email, email_confirm: true });
      if (eCrear || !creado?.user) {
        const existe = /already|registered|exists/i.test(eCrear?.message ?? '');
        return json({ error: existe ? 'email_ya_existe_en_auth' : (eCrear?.message ?? 'no_se_pudo_crear') }, existe ? 409 : 400);
      }
      const { error: eFila } = await admin.from('usuarios').insert({
        user_id: creado.user.id, email, nombre: sol.nombre, rol: 'agente', herramientas, tipos_contrato,
        proyectos, activo: true, creado_por: quien.user.email ?? null,
      });
      if (eFila) {
        await admin.auth.admin.deleteUser(creado.user.id);
        return json({ error: 'no_se_pudo_registrar: ' + eFila.message }, 500);
      }
      await admin.from('solicitudes_colaborador').update({
        estado: 'activada', user_id: creado.user.id, revisado_por: quien.user.email ?? null, revisado_en: new Date().toISOString(),
      }).eq('id', sol.id);

      // Enlace para crear la contraseña: SOLO viaja por email al buzón ya
      // verificado; nunca en la respuesta ni en logs (Seguridad #61-8). Se
      // construye con el token hasheado: la página lo canjea con verifyOtp, sin
      // depender de la lista de redirecciones de Auth.
      let emailEnviado = false;
      try {
        const { data: link, error: eLink } = await admin.auth.admin.generateLink({ type: 'recovery', email });
        const th = link?.properties?.hashed_token;
        if (eLink || !th) throw new Error('sin_enlace');
        const url = 'https://lawangproperties.com/intranet/contrasena/?th=' + encodeURIComponent(th);
        const saludo = String(sol.nombre || email).split(' ')[0];
        const ac = new AbortController();
        const to_ = setTimeout(() => ac.abort(), 8000);
        try {
          const r = await fetch('https://lawangproperties.com/contracts/api/send_email.php', {
            method: 'POST',
            headers: { 'content-type': 'application/json', 'X-Suite-Token': jwt },
            body: JSON.stringify({
              to: email, subject: 'Ya eres comercial de Lawang: crea tu contraseña',
              message: `Hola ${saludo},\n\nHemos activado tu acceso a la intranet de Lawang.\n\n`
                + `Usuario: ${email}\n\nPulsa el botón para crear tu contraseña. El enlace caduca pronto y solo sirve una vez; `
                + `si caduca, pídenos otro.\n\nYour access to the Lawang intranet is active. Use the button to set your password.`,
              attach: false, cta_url: url, cta_texto: 'Crear mi contraseña',
            }),
            signal: ac.signal,
          });
          const t = await r.text();
          emailEnviado = r.ok && t.includes('"ok":true');
          if (!emailEnviado) console.error('admin-usuarios activar: fallo email a ' + email + ': ' + t.slice(0, 200));
        } finally { clearTimeout(to_); }
      } catch (e) {
        console.error('admin-usuarios activar: sin enlace/email para ' + email + ': ' + String((e as Error)?.message ?? e));
      }
      return json({ ok: true, user_id: creado.user.id, email, email_enviado: emailEnviado });
    }

    if (accion === 'descartar_solicitud') {
      const id = String(body.solicitud_id ?? '');
      const { error } = await admin.from('solicitudes_colaborador').update({
        estado: 'descartada', revisado_por: quien.user.email ?? null, revisado_en: new Date().toISOString(),
      }).eq('id', id).eq('estado', 'pendiente');
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    if (accion === 'estado_referido') {
      const id = String(body.id ?? '');
      const estado = String(body.estado ?? '');
      if (!['nuevo', 'en_crm', 'descartado'].includes(estado)) return json({ error: 'estado_invalido' }, 400);
      const { error } = await admin.from('referidos_contactos').update({
        estado, revisado_por: quien.user.email ?? null, revisado_en: new Date().toISOString(),
      }).eq('id', id);
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    // ── reenviar enlace de contraseña a un usuario ya activado ───────────
    if (accion === 'reenviar_enlace') {
      const id = String(body.solicitud_id ?? '');
      const { data: sol } = await admin.from('solicitudes_colaborador')
        .select('email, nombre, estado, user_id').eq('id', id).maybeSingle();
      if (!sol || sol.estado !== 'activada') return json({ error: 'solicitud_no_activada' }, 409);
      // una cuenta desactivada en Usuarios no recibe sesión de recuperación (Seguridad capa 1 #6)
      const { data: vivo } = await admin.from('usuarios').select('activo').eq('user_id', sol.user_id).maybeSingle();
      if (!vivo || !vivo.activo) return json({ error: 'usuario_inactivo' }, 409);
      const { data: link, error: eLink } = await admin.auth.admin.generateLink({ type: 'recovery', email: sol.email });
      const th = link?.properties?.hashed_token;
      if (eLink || !th) return json({ error: 'sin_enlace' }, 500);
      const url = 'https://lawangproperties.com/intranet/contrasena/?th=' + encodeURIComponent(th);
      const acR = new AbortController();
      const toR = setTimeout(() => acR.abort(), 8000);
      const r = await fetch('https://lawangproperties.com/contracts/api/send_email.php', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'X-Suite-Token': jwt },
        signal: acR.signal,
        body: JSON.stringify({
          to: sol.email, subject: 'Crea tu contraseña — Lawang',
          message: `Hola ${String(sol.nombre || '').split(' ')[0]},\n\nAquí tienes un enlace nuevo para crear tu contraseña de la intranet de Lawang.`,
          attach: false, cta_url: url, cta_texto: 'Crear mi contraseña',
        }),
      });
      clearTimeout(toR);
      const t = await r.text();
      return json({ ok: r.ok && t.includes('"ok":true') });
    }

    // ── cambiar contraseña ───────────────────────────────────────────────
    if (accion === 'password') {
      const user_id = String(body.user_id ?? '');
      const password = String(body.password ?? '');
      if (!user_id) return json({ error: 'falta_usuario' }, 400);
      if (password.length < 10) return json({ error: 'password_corta' }, 400);
      // Poner la contraseña de otro es quedarse con su cuenta (26-sep-2026, revisión de las
      // edges con service_role). Solo cuentas del EQUIPO: una cuenta de Auth sin ficha en
      // `usuarios` (un comprador del portal) no se toca desde aquí — antes `destino` nulo
      // pasaba. Y un admin solo con las de rango inferior: ni super_admin ni otro admin
      // (sí la suya propia). El super_admin puede con cualquiera del equipo.
      const { data: destino } = await admin.from('usuarios').select('rol').eq('user_id', user_id).maybeSingle();
      if (!destino) return json({ error: 'no_es_cuenta_del_equipo' }, 403);
      if (!soySuper && user_id !== quien.user.id && ['super_admin', 'admin'].includes(destino.rol))
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
