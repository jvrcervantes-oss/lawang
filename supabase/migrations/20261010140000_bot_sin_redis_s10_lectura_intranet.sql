-- ============================================================================
-- S10 del encargo «bot de Lawang sin Redis» (9-oct-2026): la intranet lee las conversaciones del bot DIRECTAMENTE de Postgres.
--
-- Dos funciones, las unicas por las que el navegador ve el chat del bot:
--   crm_bot_conversaciones()        <- pestaña «Setter IA» de intranet/leads (leads.js, cargarSetter)  · la lista de hilos
--   crm_bot_conversacion(p_tel)     <- misma pestaña (verConversacion)                                 · un hilo + lo que el CRM sabe de ese lead
-- Una funcion interna (sin EXECUTE para nadie) da forma a una fila de la lista, para que lista y hilo digan lo mismo:
--   _crm_bot_conv_fila(bot_chat, text)
--
-- QUIEN PUEDE (decision del encargo, permiso PROPIO, no 'leads'): super_admin o la casilla `bot_conversaciones_ver`, y SOLO con alcance
-- global (el bot es uno y mezcla las dos empresas). La regla NO esta repetida aqui: la decide _bot_conversaciones_autoriza (S1), que ademas
-- APUNTA cada lectura (quien, que telefono, cuando) en bot_lecturas_log, de solo anadir. Las dos funciones la llaman LO PRIMERO, antes de
-- tocar ninguna tabla: sin permiso lanzan 42501 y no devuelven ni una fila. Lo asegura contracts/bot_conversaciones_lectura.test.js (texto)
-- y supabase/pruebas/bot_sin_redis_s10.sql (roles reales).
--
-- EL DATO TIENE UN DUEÑO (patrones_tecnicos.md): los mensajes y el estado operativo son del bot (bot_chat, bot_mensaje); el nombre, las
-- notas y las citas son del CRM (leads, lead_notas, lead_accion) y aqui solo se LEEN por la referencia bot_chat.lead_id. Si el telefono
-- casa con mas de un lead, lead_id es nulo y NO se adivina: la ficha sale vacia. De las notas solo se devuelven las que escribe el bot
-- (tipo='resumen_bot' o autor='bot'): las notas del equipo se ven en el CRM con su permiso 'leads', no con este.
-- Texto no fiable: el contenido de los mensajes, el nombre de perfil, el ultimo mensaje y los resumenes salen de un chat con un tercero (y
-- de un modelo); la pantalla los pinta SIEMPRE escapados.
--
-- LO QUE NO ESTA EN POSTGRES (se omite, no se inventa): `gated` (que leads atiende el bot en modo testing vive en una variable de Railway)
-- sale NULL = «no se sabe desde aqui»; pais, campaña, etiquetas y fecha de viaje eran campos del Redis viejo.
-- La ventana de 24 h de WhatsApp se calcula AQUI (reloj del servidor), nunca con el del navegador.
-- LECTURA, no escritura: pausar, enviar y plantillas siguen por el bot (necesita el token de WhatsApp) y la ruta /humano (S2).
-- Acotado: la lista devuelve a lo sumo 500 hilos (sin cuerpos de mensaje) y el hilo los ultimos 100 mensajes.
-- Funciones VOLATILE a proposito: _bot_conversaciones_autoriza inserta en el registro.
-- REVERSION: drop function public.crm_bot_conversaciones(); drop function public.crm_bot_conversacion(text); drop function public._crm_bot_conv_fila(public.bot_chat, text);
-- ============================================================================

-- ── fila de la lista: una sola forma para lista y hilo ───────────────────────
create or replace function public._crm_bot_conv_fila(c public.bot_chat, p_nombre text)
returns jsonb language sql stable set search_path = '' as $f$
  select jsonb_build_object(
    'phone',          c.tel,
    'name',           coalesce(nullif(btrim(coalesce(p_nombre, '')), ''), c.nombre_perfil),
    'lastMessage',    c.ultimo_mensaje,
    'lastBy',         c.ultimo_por,
    'lastInboundAt',  (extract(epoch from c.ultimo_entrante_en) * 1000)::bigint,
    'activityAt',     (extract(epoch from c.actividad_en) * 1000)::bigint,
    'createdAt',      (extract(epoch from c.creado_en) * 1000)::bigint,
    'intent',         c.intent,
    'followups',      c.seguimientos,
    'paused',         c.pausado and (c.pausa_hasta is null or c.pausa_hasta > now()),
    'optOut',         c.baja_en is not null,
    'gated',          null,
    'ventanaAbierta', coalesce(c.ultimo_entrante_en > now() - interval '24 hours', false),
    'ventanaExpira',  (extract(epoch from c.ultimo_entrante_en + interval '24 hours') * 1000)::bigint,
    'conLead',        c.lead_id is not null)
$f$;

-- ── la lista ─────────────────────────────────────────────────────────────────
create or replace function public.crm_bot_conversaciones()
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_chats jsonb;
  v_hay   boolean;
begin
  perform public._bot_conversaciones_autoriza(null, 'lista');      -- LO PRIMERO: sin permiso, 42501 y ni una fila
  with t as (
    select c as chat, l.name as lead_nombre,
           row_number() over (order by c.actividad_en desc, c.tel) as rn
      from public.bot_chat c
      left join public.leads l on l.id = c.lead_id
     where not c.archivado
     order by c.actividad_en desc, c.tel
     limit 501
  )
  select coalesce(jsonb_agg(public._crm_bot_conv_fila(t.chat, t.lead_nombre) order by t.rn) filter (where t.rn <= 500), '[]'::jsonb),
         coalesce(bool_or(t.rn > 500), false)
    into v_chats, v_hay
    from t;
  return jsonb_build_object('chats', v_chats, 'hayMas', v_hay);
end $f$;

-- ── un hilo + lo que el CRM sabe de ese lead ─────────────────────────────────
create or replace function public.crm_bot_conversacion(p_tel text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_tel   text;
  v_c     public.bot_chat%rowtype;
  v_msgs  jsonb;
  v_hay   boolean;
  v_lead  jsonb := null;
  v_notas jsonb := '[]'::jsonb;
  v_citas jsonb := '[]'::jsonb;
  v_nombre text := null;
begin
  perform public._bot_conversaciones_autoriza(p_tel, 'hilo');      -- LO PRIMERO: valida el telefono, comprueba el permiso y lo apunta
  v_tel := public._bot_tel(p_tel);
  select * into v_c from public.bot_chat where tel = v_tel;
  if not found then
    return jsonb_build_object('chat', null, 'mensajes', '[]'::jsonb, 'hayMas', false, 'lead', null, 'notas', '[]'::jsonb, 'citas', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'role', m.rol,
           'by', case m.por when 'humano' then 'human' when 'bot' then 'bot' else 'client' end,
           'byUser', m.por_usuario, 'content', m.contenido, 'media', m.media,
           'ts', (extract(epoch from coalesce(m.ts_origen, m.creado_en)) * 1000)::bigint) order by m.id), '[]'::jsonb)
    into v_msgs
    from (select x.* from public.bot_mensaje x where x.tel = v_tel order by x.id desc limit 100) m;
  v_hay := (select count(*) from public.bot_mensaje x where x.tel = v_tel) > 100;

  if v_c.lead_id is not null then
    select jsonb_build_object('name', l.name, 'source', l.source, 'project', l.project,
                              'createdAt', (extract(epoch from l.created_at) * 1000)::bigint), l.name
      into v_lead, v_nombre
      from public.leads l where l.id = v_c.lead_id;
    select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'tipo', n.tipo, 'autor', n.autor, 'texto', left(n.texto, 4000),
                                                 'ts', (extract(epoch from n.created_at) * 1000)::bigint) order by n.created_at desc, n.id desc), '[]'::jsonb)
      into v_notas
      from (select y.* from public.lead_notas y
             where y.lead_id = v_c.lead_id and (y.tipo = 'resumen_bot' or y.autor = 'bot')
             order by y.created_at desc, y.id desc limit 20) n;
    select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'tipo', a.tipo, 'estado', a.estado, 'que', left(a.que, 200),
                                                 'ts', (extract(epoch from a.cuando_ts) * 1000)::bigint) order by a.cuando_ts desc), '[]'::jsonb)
      into v_citas
      from (select z.* from public.lead_accion z
             where z.lead_id = v_c.lead_id and z.tipo in ('llamada', 'visita') and z.cuando_ts is not null
             order by z.cuando_ts desc limit 10) a;
  end if;

  return jsonb_build_object('chat', public._crm_bot_conv_fila(v_c, v_nombre), 'mensajes', v_msgs, 'hayMas', v_hay,
                            'lead', v_lead, 'notas', v_notas, 'citas', v_citas);
end $f$;

-- ── concesiones: solo `authenticated` ejecuta las dos de lectura (el permiso lo decide la funcion); la interna, nadie ──
revoke all on function public._crm_bot_conv_fila(public.bot_chat, text) from public, anon, authenticated, service_role;
revoke all on function public.crm_bot_conversaciones()                  from public, anon, service_role;
revoke all on function public.crm_bot_conversacion(text)                from public, anon, service_role;
grant execute on function public.crm_bot_conversaciones()               to authenticated;
grant execute on function public.crm_bot_conversacion(text)             to authenticated;
