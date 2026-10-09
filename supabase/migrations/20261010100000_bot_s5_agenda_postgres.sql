-- destructivo-ok: solo construye (2 columnas nuevas en lead_accion, un indice, 3 funciones nuevas). No borra ni reescribe nada.
-- ============================================================================
-- LAWANG — BOT CON CATALOGO EN VIVO Y GESTION DEL CRM — S5 (9-oct-2026): la «Agenda de cierre» lee y escribe en Postgres
-- ----------------------------------------------------------------------------
-- Encargo: encargos/20261008_lawang_bot_catalogo_crm.md, subtarea S5. Decision del owner (8-oct): las citas y llamadas viven en
-- Postgres (la intranet); un solo dueño y un solo escritor. Hasta hoy la pestaña «Agenda» de intranet/leads hablaba con el bot
-- (Redis) a traves de lawang-bot-proxy (citas_listar / citas_guardar / citas_borrar); desde esta migracion habla con estas tres funciones.
--
-- EL DATO TIENE UN DUEÑO:
--   · una cita (llamada/visita) -> dueño: public.lead_accion (tipo llamada|visita). No hay segunda copia: el bot ya no las guarda en Redis
--     cuando BOT_CRM=on, y la agenda de la intranet las lee de aqui.
--   · `ref_origen` guarda el id que la cita tenia en Redis (`appt:<id>`) SOLO en las importadas: es la clave que hace la importacion
--     repetible sin duplicar. `importada_en` dice cuando se importo. Las citas nacidas aqui llevan los dos a NULL.
--
-- UNA SOLA PUERTA, UN SOLO PERMISO (decision de esta migracion): la pestaña y el proxy ya exigian `closers`. crm_agenda y
--   crm_lead_cita_decidir exigen `leads` + lead_a_mi_alcance, que a un closer sin la herramienta `leads` le daria una pestaña
--   visible con errores. Las tres funciones de aqui exigen `closers` y que la empresa del lead sea visible para quien llama
--   (_ve_empresa). NO se usa lead_a_mi_alcance: ese filtro mira «mis campañas» y esconderia citas que antes el closer veia.
--
-- LLAMADORES CON NOMBRE (seguridad_2026 §1.ter — nacen cerradas: sin EXECUTE para anon ni service_role):
--   crm_citas_agenda()                 <- intranet/leads/leads.js, cargarAgenda()
--   crm_cita_guardar(...)              <- intranet/leads/leads.js, guardarCita()  (formulario «Nueva cita» / «Guardar cambios»)
--   crm_cita_cancelar(uuid)            <- intranet/leads/leads.js, borrarCita()   (botón «Borrar» = cancelar; la cita queda en el historial del lead)
--
-- DECISIONES:
--   1. «Borrar» CANCELA (estado 'cancelada', cierra la cita viva): el historial del lead (crm_lead_hilo) conserva que existió. Un DELETE
--      la haria desaparecer sin rastro y el log de decisiones perderia a quien la quito.
--   2. Una cita nueva a mano nace 'confirmada' con origen 'humano' (la crea una persona del equipo). Editar una propuesta del bot la CONFIRMA:
--      quien la guarda esta aceptandola; origen sigue 'bot' (de donde vino) y decidida_por dice quien la acepto.
--   3. El closer: el de la sesion, salvo super_admin o admin de la empresa del lead, que pueden agendar a nombre de otro (misma regla que
--      lawang-bot-proxy tenia en `closerFinal`: nadie atribuye citas a un compañero).
--   4. Mismo candado que el bot: pg_advisory_xact_lock('bot:'||e164) ANTES de mirar la fila, en el mismo orden que bot_lead_cita y
--      crm_lead_cita_decidir. Un guardado y una reprogramacion del bot simultaneos se serializan.
--   5. La agenda no enseña las canceladas. Enseña propuesta, confirmada y hecha (antes enseñaba todo lo no borrado de Redis, pasado incluido).
--   6. Una cita por lead (indice lead_accion_cita_viva): si el lead ya tiene una viva, crear una segunda da error y manda a editar la existente.
--      Antes createAppt actualizaba la existente sin avisar; ahora el equipo lo ve.
--
-- ROLLBACK:  drop function public.crm_citas_agenda(); drop function public.crm_cita_guardar(uuid, text, text, text, text, text);
--            drop function public.crm_cita_cancelar(uuid); drop index public.lead_accion_ref_origen;
--            alter table public.lead_accion drop column ref_origen, drop column importada_en;
--            (y volver a poner citas_* en lawang-bot-proxy, que se retiran en esta misma entrega)
-- ============================================================================

-- ── 1. origen de las citas importadas de Redis ───────────────────────────────
alter table public.lead_accion
  add column if not exists ref_origen   text,
  add column if not exists importada_en timestamptz;

create unique index if not exists lead_accion_ref_origen
  on public.lead_accion (ref_origen) where ref_origen is not null;

-- ── 2. la agenda ─────────────────────────────────────────────────────────────
create or replace function public.crm_citas_agenda()
returns table (id uuid, lead_id uuid, nombre text, telefono text, tipo text, cuando_ts timestamptz,
               estado text, origen text, responsable text, notas text, decidida_por text, importada_en timestamptz)
language sql stable security definer set search_path = '' as $f$
  select a.id, a.lead_id, l.name, l.whatsapp, a.tipo, a.cuando_ts, a.estado, a.origen, a.responsable, a.que, a.decidida_por, a.importada_en
    from public.lead_accion a
    join public.leads l on l.id = a.lead_id
   where public.puede('closers')
     and a.tipo in ('llamada', 'visita')
     and a.cuando_ts is not null
     and a.estado <> 'cancelada'
     and public._ve_empresa(public.empresa_de_lead(a.lead_id))
   order by a.cuando_ts asc;
$f$;

-- ── 3. crear / editar una cita ───────────────────────────────────────────────
-- p_id NULL = nueva (el lead se busca por telefono: exactamente uno); p_id con valor = editar esa cita (el telefono se ignora: no se mueve
-- una cita a otro lead). p_cuando: ISO sin zona = hora de Bali (como lo manda el datetime-local de la pantalla) o con zona explicita.
create or replace function public.crm_cita_guardar(
  p_id uuid, p_telefono text, p_cuando text, p_closer text default null, p_notas text default null, p_tipo text default 'llamada')
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_tipo  text := coalesce(p_tipo, 'llamada');
  v_s     text := btrim(coalesce(p_cuando, ''));
  v_ts    timestamptz;
  v_loc   timestamp;
  v_lead  uuid;
  v_e164  text;
  v_ids   uuid[];
  v_emp   text;
  v_resp  text;
  v_que   text;
  v_a     public.lead_accion%rowtype;
  v_id    uuid;
begin
  if not public.puede('closers') then
    raise exception 'Sin permiso sobre la agenda de cierre' using errcode = 'PT403';
  end if;
  if v_quien = '' then raise exception 'Sesion sin identidad' using errcode = 'PT403'; end if;
  if v_tipo not in ('llamada', 'visita') then raise exception 'Tipo de cita no valido' using errcode = 'PT400'; end if;
  if v_s !~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}(:?\d{2})?)?$' then
    raise exception 'Fecha y hora no validas' using errcode = 'PT400';
  end if;
  begin
    if v_s ~ '(Z|[+-]\d{2}(:?\d{2})?)$' then v_ts := v_s::timestamptz;
    else v_ts := v_s::timestamp at time zone 'Asia/Makassar'; end if;
  exception when others then
    raise exception 'Fecha y hora no validas' using errcode = 'PT400';
  end;
  v_loc := v_ts at time zone 'Asia/Makassar';

  -- el lead: de la cita que se edita, o del telefono (exactamente uno)
  if p_id is not null then
    select a.lead_id into v_lead from public.lead_accion a where a.id = p_id;
    if v_lead is null then raise exception 'Esa cita no existe' using errcode = 'PT404'; end if;
  else
    v_e164 := public._bot_e164(p_telefono);
    if v_e164 is null then raise exception 'Telefono no valido' using errcode = 'PT400'; end if;
    select coalesce(array_agg(l.id order by l.created_at), '{}') into v_ids
      from public.leads l where public._lw_tel_e164(l.whatsapp) = v_e164;
    if cardinality(v_ids) = 0 then
      raise exception 'No hay ningun lead con ese telefono: dalo de alta en el CRM antes de agendar' using errcode = 'PT404';
    elsif cardinality(v_ids) > 1 then
      raise exception 'Hay varios leads con ese telefono: no se puede elegir uno solo' using errcode = 'PT409';
    end if;
    v_lead := v_ids[1];
  end if;

  v_emp := public.empresa_de_lead(v_lead);
  if not public._ve_empresa(v_emp) then
    raise exception 'Ese lead es de una empresa que no ves' using errcode = 'PT403';
  end if;

  -- mismo candado y mismo orden que el bot: telefono primero, fila despues
  select public._lw_tel_e164(l.whatsapp) into v_e164 from public.leads l where l.id = v_lead;
  if v_e164 is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  end if;

  v_resp := case when public.es_super_admin() or public.es_admin_de(v_emp)
                 then coalesce(nullif(btrim(p_closer), ''), v_quien) else v_quien end;
  v_que  := left(coalesce(nullif(btrim(regexp_replace(coalesce(p_notas, ''), '[[:cntrl:]]', ' ', 'g')), ''),
                          case v_tipo when 'visita' then 'Visita' else 'Llamada de venta' end), 280);

  if p_id is null then
    if exists (select 1 from public.lead_accion a
                where a.lead_id = v_lead and a.completada_en is null and a.tipo in ('llamada', 'visita')) then
      raise exception 'Ese lead ya tiene una cita viva: editala en vez de crear otra' using errcode = 'PT409';
    end if;
    insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por, tipo, cuando_ts, estado, origen, decidida_por, decidida_en)
    values (v_lead, v_que, v_loc::date, v_resp, v_quien, v_tipo, v_ts, 'confirmada', 'humano', v_quien, now())
    returning id into v_id;
  else
    select * into v_a from public.lead_accion a where a.id = p_id for update;
    if v_a.tipo not in ('llamada', 'visita') then raise exception 'Eso es una tarea, no una cita' using errcode = 'PT400'; end if;
    if v_a.completada_en is not null then raise exception 'Esa cita ya esta cerrada' using errcode = 'PT409'; end if;
    update public.lead_accion a
       set tipo = v_tipo, que = v_que, cuando = v_loc::date, cuando_ts = v_ts, responsable = v_resp,
           estado = 'confirmada',
           decidida_por = case when a.estado = 'propuesta' then v_quien else a.decidida_por end,
           decidida_en  = case when a.estado = 'propuesta' then now()    else a.decidida_en  end
     where a.id = p_id;
    v_id := p_id;
  end if;

  return (select jsonb_build_object('id', a.id, 'lead_id', a.lead_id, 'estado', a.estado, 'responsable', a.responsable)
            from public.lead_accion a where a.id = v_id);
end $f$;

-- ── 4. «Borrar» = cancelar ───────────────────────────────────────────────────
create or replace function public.crm_cita_cancelar(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_lead  uuid;
  v_e164  text;
  v_a     public.lead_accion%rowtype;
begin
  if not public.puede('closers') then
    raise exception 'Sin permiso sobre la agenda de cierre' using errcode = 'PT403';
  end if;
  if v_quien = '' then raise exception 'Sesion sin identidad' using errcode = 'PT403'; end if;
  select a.lead_id into v_lead from public.lead_accion a where a.id = p_id;
  if v_lead is null then raise exception 'Esa cita no existe' using errcode = 'PT404'; end if;
  if not public._ve_empresa(public.empresa_de_lead(v_lead)) then
    raise exception 'Ese lead es de una empresa que no ves' using errcode = 'PT403';
  end if;
  select public._lw_tel_e164(l.whatsapp) into v_e164 from public.leads l where l.id = v_lead;
  if v_e164 is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  end if;
  select * into v_a from public.lead_accion a where a.id = p_id for update;
  if v_a.tipo not in ('llamada', 'visita') then raise exception 'Eso es una tarea, no una cita' using errcode = 'PT400'; end if;
  if v_a.completada_en is not null then raise exception 'Esa cita ya esta cerrada' using errcode = 'PT409'; end if;
  update public.lead_accion a
     set estado = 'cancelada', decidida_por = v_quien, decidida_en = now(), completada_en = now(), completada_por = v_quien
   where a.id = p_id;
  return (select jsonb_build_object('id', a.id, 'lead_id', a.lead_id, 'estado', a.estado)
            from public.lead_accion a where a.id = p_id);
end $f$;

-- ── 5. quien puede ejecutar que ──────────────────────────────────────────────
revoke all on function public.crm_citas_agenda()                                                  from public, anon, service_role;
revoke all on function public.crm_cita_guardar(uuid, text, text, text, text, text)                from public, anon, service_role;
revoke all on function public.crm_cita_cancelar(uuid)                                             from public, anon, service_role;
grant execute on function public.crm_citas_agenda()                                               to authenticated;
grant execute on function public.crm_cita_guardar(uuid, text, text, text, text, text)             to authenticated;
grant execute on function public.crm_cita_cancelar(uuid)                                          to authenticated;
