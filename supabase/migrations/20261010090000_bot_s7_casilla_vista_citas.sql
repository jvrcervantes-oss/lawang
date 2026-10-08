-- destructivo-ok: solo construye (2 columnas nuevas en lead_accion, 5 funciones nuevas). Los 2 «create or replace» son de crm_lead_hilo (misma firma y mismas columnas: la cita deja de salir como «tarea» y sale como «cita»; las demas ramas, intactas). Sin datos que perder.
-- ============================================================================
-- LAWANG — BOT CON CATALOGO EN VIVO Y GESTION DEL CRM — BASE DE DATOS DE LA PANTALLA, S7 (9-oct-2026)
-- ----------------------------------------------------------------------------
-- Encargo: encargos/20261008_lawang_bot_catalogo_crm.md, subtarea S7. Sigue a S3 (20261010080000/0100/0200).
--
-- EL DATO TIENE UN DUEÑO — que se guarda aqui y que NO:
--   · «el bot puede hablar de este proyecto»  -> dueño: proyectos.bot_publico (S3). Esta migracion NO crea otro sitio: solo da la UNICA puerta de escritura.
--   · «Lo que sabe el bot»                    -> NO se guarda. bot_catalogo_ver() llama a bot_catalogo_leer() (la misma fuente que la edge bot-api) y
--                                                lo devuelve tal cual: no hay segunda definicion de «disponible» ni lista de columnas que pueda divergir.
--   · quien/cuando decidio una cita            -> dueño: lead_accion.decidida_por / decidida_en (nuevas). Una cita se decide una vez por estado.
--
-- LLAMADORES CON NOMBRE (seguridad_2026 §1.ter — lo nuevo nace cerrado, sin EXECUTE para anon ni service_role):
--   proyecto_bot_publico_poner(uuid, boolean) <- ficha del proyecto, intranet/v4/proyectos, botón «Bot de WhatsApp» (editores.js, data-accion="bot-publico")
--   proyecto_bot_publico_lee(uuid)            <- el mismo cajon, al abrirse
--   bot_catalogo_ver()                        <- pestaña «Configurar bot» de intranet/leads, bloque «Lo que sabe el bot» (leads.js)
--   crm_lead_cita_decidir(uuid, text)         <- ficha del lead, intranet/leads, botones Confirmar / Cancelar / Hecha de la cita
--   _bot_proyecto_estado(uuid)                <- solo las dos primeras. Sin EXECUTE para nadie.
--
-- DECISIONES (el CEO las ve en el informe):
--   1. QUIEN ENCIENDE LA CASILLA: es_admin_de(empresa del proyecto). Decide que precios y disponibilidad se citan por WhatsApp a cualquiera que escriba:
--      mismo nivel que activar el Investor Deck o la ficha publica. El project_manager, el sales_manager y el agente NO. Un admin de empresa solo
--      el de sus proyectos. Se comprueba en el servidor; el boton de la pantalla se esconde por comodidad, no por seguridad.
--   2. QUIEN VE «LO QUE SABE EL BOT»: la misma regla que lawang-bot-proxy para «Configurar bot»: super_admin o la casilla bot_configurar, y SOLO con
--      alcance global (el bot es uno y mezcla las dos empresas: con alcance acotado veria el catalogo de la otra).
--   3. QUIEN DECIDE UNA CITA: la persona con la herramienta «leads» y el lead a su alcance (lead_a_mi_alcance), como el resto del CRM.
--      Confirmar solo desde «propuesta»; Cancelar desde propuesta o confirmada (libera la cita viva: el bot podra proponer otra); Hecha solo desde confirmada.
--      Al confirmar, si la cita estaba a nombre de «bot», pasa a nombre de quien la confirma.
--   4. CARRERA CON EL BOT: bot_lead_cita reprograma «lo propuesto por el bot y no confirmado». crm_lead_cita_decidir toma el MISMO candado por telefono
--      (pg_advisory_xact_lock 'bot:'||e164, en el mismo orden que el bot: candado de telefono y luego fila) y bloquea la fila: una confirmacion y una
--      reprogramacion simultaneas se serializan y la segunda ve el resultado de la primera.
--   5. crm_lead_hilo: la cita sale con su propia etiqueta ('cita' al crearse; 'cita_estado' al confirmarla/cancelarla/cerrarla) y deja de salir como
--      'tarea'/'tarea_hecha' (que la mezclaba con «el proximo paso»).
--
-- ROLLBACK:  drop function public.proyecto_bot_publico_poner(uuid, boolean); drop function public.proyecto_bot_publico_lee(uuid);
--            drop function public.bot_catalogo_ver(); drop function public.crm_lead_cita_decidir(uuid, text); drop function public._bot_proyecto_estado(uuid);
--            (volver a aplicar crm_lead_hilo de la 20260911033720); alter table public.lead_accion drop column decidida_por, drop column decidida_en;
-- ============================================================================

-- ── 1. quien y cuando decidio una cita ───────────────────────────────────────
alter table public.lead_accion
  add column if not exists decidida_por text,
  add column if not exists decidida_en  timestamptz;

-- ── 2. estado de la casilla de un proyecto (interno) ─────────────────────────
-- `visibles` = lo que el bot veria AHORA de este proyecto: se cuenta con bot_catalogo_leer(), no con otra definicion de «disponible».
create or replace function public._bot_proyecto_estado(p_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object(
           'bot_publico', p.bot_publico, 'por', p.bot_publico_por, 'en', p.bot_publico_en, 'activo', p.activo,
           'visibles', (select count(*) from public.bot_catalogo_leer() c where c.proyecto = p.nombre))
    from public.proyectos p where p.id = p_id
$f$;

-- ── 3. la casilla: UNA puerta de escritura, con el rol comprobado aqui ────────
create or replace function public.proyecto_bot_publico_poner(p_proyecto uuid, p_valor boolean)
returns jsonb language plpgsql security definer set search_path = '' as $f$
begin
  if p_proyecto is null or p_valor is null then
    raise exception 'Faltan datos' using errcode = 'PT400';
  end if;
  if not public.es_admin_de(public.empresa_de_proyecto(p_proyecto)) then
    raise exception 'Solo un administrador puede abrir o cerrar un proyecto al bot' using errcode = '42501';
  end if;
  perform 1 from public.proyectos p where p.id = p_proyecto for update;
  if not found then
    raise exception 'Ese proyecto no existe' using errcode = 'PT404';
  end if;
  -- el trigger proyectos_bot_publico_sello pone quien (auth.email()) y cuando solo si el valor CAMBIA
  update public.proyectos p set bot_publico = p_valor where p.id = p_proyecto and p.bot_publico is distinct from p_valor;
  return public._bot_proyecto_estado(p_proyecto);
end $f$;

create or replace function public.proyecto_bot_publico_lee(p_proyecto uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v jsonb;
begin
  if p_proyecto is null or not public.es_admin_de(public.empresa_de_proyecto(p_proyecto)) then
    raise exception 'Solo un administrador puede ver esto' using errcode = '42501';
  end if;
  v := public._bot_proyecto_estado(p_proyecto);
  if v is null then raise exception 'Ese proyecto no existe' using errcode = 'PT404'; end if;
  return v;
end $f$;

-- ── 4. «Lo que sabe el bot»: exactamente lo que devolveria bot_catalogo_leer() ─
-- `unidades` sale de bot_catalogo_leer() fila a fila (to_jsonb de SUS columnas): si alguien añadiera una columna alli, saldria aqui — por eso el gate
-- (check_seguridad.bot_catalogo_salida) vigila esa funcion y no esta. `proyectos_abiertos` distingue «vacio porque nadie ha abierto un proyecto» de
-- «abiertos pero sin unidades disponibles». `bot_conectado` = el rol del bot ya puede entrar a la base (activacion de S4 hecha).
create or replace function public.bot_catalogo_ver()
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo
       and u.ambito = 'global' and coalesce(cardinality(u.empresas), 0) = 0
       and (u.rol = 'super_admin' or 'bot_configurar' = any (u.herramientas))
  ) then
    raise exception 'Sin permiso para ver lo que sabe el bot' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'unidades', coalesce((select jsonb_agg(to_jsonb(c)) from public.bot_catalogo_leer() c), '[]'::jsonb),
    'proyectos_abiertos', (select count(*) from public.proyectos p where p.bot_publico and p.activo),
    'bot_conectado', exists (select 1 from pg_catalog.pg_roles r where r.rolname = 'bot_lawang' and r.rolcanlogin));
end $f$;

-- ── 5. decidir una cita (confirmar / cancelar / hecha) ───────────────────────
create or replace function public.crm_lead_cita_decidir(p_accion uuid, p_decision text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_lead  uuid;
  v_e164  text;
  v_a     public.lead_accion%rowtype;
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if p_decision is null or p_decision not in ('confirmar', 'cancelar', 'hecha') then
    raise exception 'Decision no valida' using errcode = 'PT400';
  end if;
  select a.lead_id into v_lead from public.lead_accion a where a.id = p_accion;
  if v_lead is null then
    raise exception 'Esa cita no existe' using errcode = 'PT404';
  end if;
  if not public.lead_a_mi_alcance(v_lead) then
    raise exception 'Esa cita es de un lead que no es de tus campanas' using errcode = 'PT403';
  end if;

  -- mismo candado y mismo orden que bot_lead_cita (telefono primero, fila despues)
  select public._lw_tel_e164(l.whatsapp) into v_e164 from public.leads l where l.id = v_lead;
  if v_e164 is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  end if;
  select * into v_a from public.lead_accion a where a.id = p_accion for update;

  if v_a.tipo not in ('llamada', 'visita') then
    raise exception 'Eso es una tarea, no una cita' using errcode = 'PT400';
  end if;
  if v_a.completada_en is not null then
    raise exception 'Esa cita ya esta cerrada' using errcode = 'PT409';
  end if;

  if p_decision = 'confirmar' then
    if v_a.estado <> 'propuesta' then
      raise exception 'Esa cita ya no esta pendiente de confirmar' using errcode = 'PT409';
    end if;
    update public.lead_accion a
       set estado = 'confirmada', decidida_por = v_quien, decidida_en = now(),
           responsable = case when a.responsable = 'bot' then v_quien else a.responsable end
     where a.id = p_accion;
  elsif p_decision = 'cancelar' then
    update public.lead_accion a
       set estado = 'cancelada', decidida_por = v_quien, decidida_en = now(), completada_en = now(), completada_por = v_quien
     where a.id = p_accion;
  else
    if v_a.estado <> 'confirmada' then
      raise exception 'Solo se marca como hecha una cita confirmada' using errcode = 'PT409';
    end if;
    update public.lead_accion a
       set estado = 'hecha', decidida_por = v_quien, decidida_en = now(), completada_en = now(), completada_por = v_quien
     where a.id = p_accion;
  end if;

  return (select jsonb_build_object('id', a.id, 'lead_id', a.lead_id, 'estado', a.estado, 'responsable', a.responsable)
            from public.lead_accion a where a.id = p_accion);
end $f$;

-- ── 6. el hilo del lead: la cita con su propia etiqueta ──────────────────────
-- Cuerpo vigente leido de la base el 9-oct-2026; cambia SOLO: 'tarea'/'tarea_hecha' ya no incluyen citas, y se añaden 'cita' y 'cita_estado'.
create or replace function public.crm_lead_hilo(p_lead uuid)
returns table (tipo text, cuando timestamptz, autor text, texto text, extra text)
language sql stable security definer set search_path = '' as $f$
  select 'alta', l.created_at, null::text, l.source, null::text
    from public.leads l
   where l.id = p_lead and public.puede('leads') and public.lead_a_mi_alcance(p_lead)
  union all
  select 'estado', g.cuando, g.autor, g.a, g.de
    from public.lead_estado_log g
   where g.lead_id = p_lead and public.puede('leads') and public.lead_a_mi_alcance(p_lead)
  union all
  select 'nota', n.created_at, n.autor, n.texto, null::text
    from public.lead_notas n
   where n.lead_id = p_lead and public.puede('leads') and public.lead_a_mi_alcance(p_lead)
  union all
  select 'tarea', a.creada_en, a.creada_por, a.que, to_char(a.cuando, 'DD-MM-YYYY')
    from public.lead_accion a
   where a.lead_id = p_lead and a.tipo = 'tarea' and public.puede('leads') and public.lead_a_mi_alcance(p_lead)
  union all
  select 'tarea_hecha', a.completada_en, a.completada_por, a.que, null::text
    from public.lead_accion a
   where a.lead_id = p_lead and a.tipo = 'tarea' and a.completada_en is not null
     and public.puede('leads') and public.lead_a_mi_alcance(p_lead)
  union all
  select 'cita', a.creada_en, a.creada_por, a.tipo, to_char(a.cuando_ts at time zone 'Asia/Makassar', 'DD-MM-YYYY HH24:MI')
    from public.lead_accion a
   where a.lead_id = p_lead and a.tipo in ('llamada', 'visita') and public.puede('leads') and public.lead_a_mi_alcance(p_lead)
  union all
  select 'cita_estado', a.decidida_en, a.decidida_por, a.estado, a.tipo
    from public.lead_accion a
   where a.lead_id = p_lead and a.tipo in ('llamada', 'visita') and a.decidida_en is not null
     and public.puede('leads') and public.lead_a_mi_alcance(p_lead)
  union all
  select 'dueno', d.cuando, d.autor, coalesce(d.a, ''), coalesce(d.de, '')
    from public.lead_dueno_log d
   where d.lead_id = p_lead and public.puede('leads') and public.lead_a_mi_alcance(p_lead)
   order by 2 asc;
$f$;

-- ── 7. quien puede ejecutar que ──────────────────────────────────────────────
revoke all on function public._bot_proyecto_estado(uuid)                from public, anon, authenticated, service_role;
revoke all on function public.proyecto_bot_publico_poner(uuid, boolean) from public, anon, service_role;
revoke all on function public.proyecto_bot_publico_lee(uuid)            from public, anon, service_role;
revoke all on function public.bot_catalogo_ver()                        from public, anon, service_role;
revoke all on function public.crm_lead_cita_decidir(uuid, text)         from public, anon, service_role;
grant execute on function public.proyecto_bot_publico_poner(uuid, boolean) to authenticated;
grant execute on function public.proyecto_bot_publico_lee(uuid)            to authenticated;
grant execute on function public.bot_catalogo_ver()                        to authenticated;
grant execute on function public.crm_lead_cita_decidir(uuid, text)         to authenticated;
