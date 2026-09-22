-- Unificación de Soporte + Mensajes en un solo hilo por comprador (1-sep-2026,
-- owner: "Soporte y mensajes creo que se duplica, unificalo"). Modelo nuevo:
-- mensajes_comprador (ya existía, era "Mensajes") gana una categoría opcional
-- por mensaje y una tabla de estado por hilo (hilo_soporte) que solo cambia el
-- equipo.
--
-- ESTA MIGRACIÓN ES PURAMENTE ADITIVA (hallazgo 7 de la revisión previa de
-- Datos): no borra tabla ni función que algo en producción pudiera seguir
-- llamando durante el rato entre este deploy y el del frontend. El modelo de
-- tickets se retira en una migración FINAL aparte
-- (20260901150000_retirar_tickets.sql), después de desplegar y verificar
-- este frontend nuevo.
--
-- PASADO POR REVISIÓN PREVIA (Seguridad + Datos) antes de escribir esto:
--   1. (Seguridad) La columna `categoria` lleva su propio CHECK, no solo la
--      RPC: cualquier vía futura que escriba directo a la tabla (backfill,
--      admin) no puede colar un valor fuera del enum.
--   2. (Seguridad) La policy de lectura de hilo_soporte para el comprador va
--      SCOPED por portal_accesos (igual que el resto de la suite), no
--      "authenticated" a secas -- mismo criterio que ya usan
--      tickets_comprador y mensajes_comprador.
--   3. (Datos, hallazgo real tras leer la RLS existente) Ni la RPC ni nada
--      del plan original creaba la fila de `hilo_soporte`: el primer
--      mensaje de un comprador nuevo no generaba fila, y un mensaje del
--      EQUIPO no actualizaba `actualizado_en` -- la bandeja (que ordena por
--      esa columna) habría mostrado conversaciones ya respondidas como si
--      llevaran días sin tocarse. Se resuelve con un trigger dedicado
--      `_trg_hilo_soporte_actividad` (AFTER INSERT en mensajes_comprador,
--      para CUALQUIER `de`), separado del trigger de aviso a propósito: ese
--      corta en seco con `if new.de <> 'cliente'` y mezclar los dos ahí
--      habría dejado sin bump de actividad los mensajes del equipo.
--   4. (Datos) Un mensaje nuevo del COMPRADOR reabre el hilo si estaba
--      resuelto (una pregunta nueva no puede quedar "resuelta" sin
--      respuesta) -- lo hace el trigger, nunca un parámetro que pudiera
--      venir del navegador. Un mensaje del EQUIPO solo actualiza
--      `actualizado_en`, nunca fuerza el estado: el equipo sigue siendo el
--      único que decide marcar resuelto (con su propio botón, RLS directa).
--   5. (Datos) La bandeja nueva de /intranet/soporte/ cuelga de guard.js /
--      es_agente(), la misma puerta que el resto de la intranet -- no hay
--      tabla ni ruta sin ese gate.
--
-- destructivo-ok: sin drop de tabla/función existente. Los `drop trigger/
-- function if exists` de más abajo son de objetos que esta misma migración
-- vuelve a crear (idempotencia).

/* ── 1. categoría opcional por mensaje ──────────────────────────────────── */
alter table public.mensajes_comprador
  add column if not exists categoria text
  check (categoria is null or categoria in ('Pagos','Documentación','Obra','Otro'));
comment on column public.mensajes_comprador.categoria is
  'Opcional. La pone el comprador al escribir (nunca el equipo). Null = mensaje suelto, sin categoría.';

/* ── 2. estado del hilo — por comprador, no por mensaje ─────────────────── */
create table if not exists public.hilo_soporte (
  client_id      uuid primary key references public.clients(id) on delete cascade,
  estado         text not null default 'abierto' check (estado in ('abierto','resuelto')),
  actualizado_en timestamptz not null default now()
);
comment on table public.hilo_soporte is
  'Estado (abierto/resuelto) y última actividad del hilo de mensajes_comprador de un cliente. La crea/actualiza SIEMPRE _trg_hilo_soporte_actividad (trigger); el equipo la cambia también directo por RLS (marcar resuelto/reabrir a mano).';
alter table public.hilo_soporte enable row level security;

drop policy if exists "comprador lee su estado" on public.hilo_soporte;
create policy "comprador lee su estado" on public.hilo_soporte
  for select to authenticated
  using (public.es_portal() and client_id in (
    select pa.client_id from public.portal_accesos pa
     where pa.activo and pa.email = lower(coalesce(auth.email(), ''))
  ));
drop policy if exists "equipo lee y cambia el estado" on public.hilo_soporte;
create policy "equipo lee y cambia el estado" on public.hilo_soporte
  for all to authenticated using (public.es_agente()) with check (public.es_agente());
-- Sin policy de INSERT para el comprador: la fila nace siempre dentro del
-- trigger de abajo (security definer), nunca por INSERT directo desde el
-- navegador.

/* ── 3. el trigger que de verdad mantiene hilo_soporte al día ───────────
   AFTER INSERT en mensajes_comprador, para CUALQUIER remitente:
     · siempre hace bump de `actualizado_en` (la bandeja ordena por ahí);
     · si `de='cliente'`, fuerza `estado='abierto'` (reapertura automática);
     · si `de='equipo'`, deja el estado como estuviera -- el equipo lo
       cambia aparte, con su propio botón. */
create or replace function public._trg_hilo_soporte_actividad()
returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.hilo_soporte (client_id, estado, actualizado_en)
    values (new.client_id, 'abierto', now())
  on conflict (client_id) do update
    set actualizado_en = now(),
        estado = case when new.de = 'cliente' then 'abierto' else public.hilo_soporte.estado end;
  return new;
exception when others then
  return new;   -- el mensaje ya se guardó; un fallo aquí no lo deshace
end $$;
revoke all on function public._trg_hilo_soporte_actividad() from public, anon, authenticated;
drop trigger if exists trg_hilo_soporte_actividad on public.mensajes_comprador;
create trigger trg_hilo_soporte_actividad
  after insert on public.mensajes_comprador
  for each row execute function public._trg_hilo_soporte_actividad();

/* ── 4. portal_enviar_mensaje gana categoría opcional (nada más: el estado
   del hilo lo lleva el trigger de arriba, no esta función) ────────────── */
drop function if exists public.portal_enviar_mensaje(uuid, text);
create or replace function public.portal_enviar_mensaje(p_client_id uuid, p_texto text, p_categoria text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_de text; v_autor text;
begin
  if btrim(coalesce(p_texto,'')) = '' then raise exception 'mensaje vacío' using errcode = '22023'; end if;
  if p_categoria is not null and p_categoria not in ('Pagos','Documentación','Obra','Otro') then
    raise exception 'categoría no válida' using errcode = '22023';
  end if;
  if public.es_agente() then
    v_de := 'equipo'; v_autor := auth.email();
  elsif public.es_portal() then
    if not exists (select 1 from public.portal_accesos pa
                    where pa.activo and pa.email = lower(coalesce(auth.email(), '')) and pa.client_id = p_client_id) then
      raise exception 'esa ficha no es tuya' using errcode = '42501';
    end if;
    v_de := 'cliente'; v_autor := null;
  else
    raise exception 'sin permiso' using errcode = '42501';
  end if;
  insert into public.mensajes_comprador (client_id, de, autor, texto, categoria)
    values (p_client_id, v_de, v_autor, btrim(p_texto), p_categoria)
    returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.portal_enviar_mensaje(uuid,text,text) from public, anon;
grant execute on function public.portal_enviar_mensaje(uuid,text,text) to authenticated;

/* ── 5. el aviso al equipo lleva la categoría si vino, y enlaza a la
   bandeja nueva (/intranet/soporte/) -- es el sitio pensado para
   responder ahora, no la ficha suelta de un comprador ─────────────────── */
create or replace function public._trg_aviso_mensaje_comprador()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_nombre text; v_cuerpo text;
begin
  if new.de <> 'cliente' then return new; end if;
  select c.full_name into v_nombre from public.clients c where c.id = new.client_id;
  v_cuerpo :=
    'Nuevo mensaje del comprador en el área de clientes.' || chr(10) || chr(10) ||
    'Comprador: ' || coalesce(v_nombre, 'sin nombre') || chr(10) ||
    (case when new.categoria is not null then 'Categoría: ' || new.categoria || chr(10) else '' end) ||
    chr(10) ||
    'Mensaje: ' || new.texto || chr(10) || chr(10) ||
    'Responder desde: https://lawangproperties.com/intranet/soporte/?id=' || new.client_id::text;
  perform public._avisar_equipo_soporte(new.client_id, 'Lawang · mensaje de ' || coalesce(v_nombre, 'un comprador'), v_cuerpo);
  return new;
exception when others then
  return new;
end $$;
-- El trigger que llama a esta función ya existe (creado el 1-sep en
-- 20260901120000); CREATE OR REPLACE de la función basta.

/* ── 6. portal_situacion(): 'mensajes' con categoría e id, nuevo
   'hilo_estado'. 'tickets' se retira en la migración final, junto con las
   tablas -- mientras tanto sigue funcionando igual que hoy. ───────────── */
create or replace function public.portal_situacion()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_email text := lower(coalesce(auth.email(), ''));
  r jsonb;
begin
  if not public.es_portal() or v_email = '' then
    raise exception 'solo usuarios del portal' using errcode = '42501';
  end if;

  with mis_clientes as (
    select distinct pa.client_id
      from public.portal_accesos pa
     where pa.activo and pa.email = v_email
  ),
  mis_ids as (
    select distinct cc.contrato_id as id
      from public.contrato_compradores cc
      join mis_clientes mc on mc.client_id = cc.client_id
  )
  select jsonb_build_object(
    'nombre', (select cl.full_name from public.clients cl
                join mis_clientes mc on mc.client_id = cl.id
                order by cl.created_at limit 1),
    'email', (select cl.email from public.clients cl
                join mis_clientes mc on mc.client_id = cl.id
                order by cl.created_at limit 1),
    'telefono', (select cl.phone from public.clients cl
                join mis_clientes mc on mc.client_id = cl.id
                order by cl.created_at limit 1),
    'pais', (select cl.nationality from public.clients cl
                join mis_clientes mc on mc.client_id = cl.id
                order by cl.created_at limit 1),
    'client_id', (select mc.client_id from mis_clientes mc
                    join public.clients cl on cl.id = mc.client_id
                   order by cl.created_at limit 1),
    'contratos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',          c.id,
        'numero',      c.numero,
        'tipo',        c.tipo,
        'proyecto',    c.proyecto_nombre,
        'parcela',     c.datos->'fields'->>'parcela_codigo',
        'precio',      c.precio_total,
        'precio_txt',  nullif(c.datos->'fields'->>'precio_total', ''),
        'moneda',      c.moneda,
        'fecha_firma', c.fecha_firma,
        'firmado',     coalesce(c.bloqueado, false),
        'pdf',         c.pdf_firmado_path,
        'hitos',       case when jsonb_typeof(c.datos->'hitos') = 'array'
                            then c.datos->'hitos' else '[]'::jsonb end,
        'cobrado',     coalesce(public.contrato_cobrado(c.id), 0)
      ) order by c.created_at)
      from public.contratos c
      join mis_ids m on m.id = c.id), '[]'::jsonb),
    'facturas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',              f.id,
        'numero',          f.numero,
        'tipo',            f.tipo,
        'sociedad',        f.sociedad,
        'contrato_numero', f.contrato_numero,
        'fecha',           f.fecha_emision,
        'total',           f.total,
        'moneda',          f.moneda,
        'cliente',         coalesce(public.contrato_nombres_factura(cf.datos), f.cliente_nombre),
        'proyecto',        f.proyecto_nombre,
        'lineas',          f.datos->'lineas',
        'totales',         f.datos->'totales',
        'fields',          f.datos->'fields'
      ) order by f.fecha_emision desc, f.numero desc)
      from public.facturas f
      join public.contratos cf on cf.id = f.contrato_id
     where f.contrato_id in (select id from mis_ids)
       and not coalesce(f.anulada, false)
       and (f.tipo <> 'proforma' or f.enviada)), '[]'::jsonb),
    'obra', coalesce((
      select jsonb_agg(jsonb_build_object(
        'unidad',          u.codigo,
        'proyecto',        u.proyecto,
        'contrato_numero', c2.numero,
        'fase',            u.obra_fase,
        'fecha_entrega',   u.obra_fecha_entrega,
        'actualizado',     u.obra_actualizado,
        'fotos', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'path', o.path, 'titulo', o.titulo, 'fecha', o.tomada_en)
                 order by o.tomada_en desc, o.creado_en desc)
            from public.obra_fotos o
           where o.unidad_id = u.id and o.visible), '[]'::jsonb)
      ))
      from public.unidades u
      join public.contratos c2 on c2.id = u.contrato_id
      join mis_ids m on m.id = c2.id), '[]'::jsonb),
    'documentos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',          dp.id,
        'titulo',      dp.titulo,
        'descripcion', dp.descripcion,
        'categoria',   dp.categoria,
        'proyecto',    dp.proyecto,
        'url',         dp.url,
        'path',        dp.path
      ) order by dp.creado_en desc)
      from public.documentos_proyecto dp
     where dp.visible_portal
       and exists (
         select 1 from public.contratos c3
         join mis_ids m3 on m3.id = c3.id
        where public.mismo_proyecto(dp.proyecto, c3.proyecto_nombre)
       )), '[]'::jsonb),
    'kyc', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tipo',   doc.doc_type,
        'subido', doc.uploaded_at,
        'caduca', doc.caduca_el,
        'path',   doc.storage_path
      ) order by doc.uploaded_at desc)
      from public.documents doc
      join mis_clientes mc2 on mc2.client_id = doc.client_id), '[]'::jsonb),
    'fases', coalesce((
      select jsonb_agg(jsonb_build_object(
               'orden', ff.orden, 'clave', ff.clave, 'es', ff.es, 'en', ff.en)
             order by ff.orden)
        from public.obra_fases ff), '[]'::jsonb),
    'mensajes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', mc4msg.id, 'de', mc4msg.de, 'autor', mc4msg.autor,
               'texto', mc4msg.texto, 'categoria', mc4msg.categoria, 'creado_en', mc4msg.creado_en)
             order by mc4msg.creado_en)
        from public.mensajes_comprador mc4msg
        join mis_clientes mc4 on mc4.client_id = mc4msg.client_id), '[]'::jsonb),
    'hilo_estado', (select hs.estado from public.hilo_soporte hs
                     join mis_clientes mc6 on mc6.client_id = hs.client_id
                    order by hs.actualizado_en desc limit 1),
    'prefs', coalesce((
      select jsonb_build_object('pref_email', pc.pref_email, 'pref_sms', pc.pref_sms,
                                 'notif_visto_hasta', pc.notif_visto_hasta)
        from public.preferencias_comprador pc
        join mis_clientes mc5 on mc5.client_id = pc.client_id
       order by pc.actualizado_en desc limit 1),
      jsonb_build_object('pref_email', true, 'pref_sms', false, 'notif_visto_hasta', null))
  ) into r;
  return r;
end
$$;

-- Comprobación (la del catálogo, no la de que alguien lo corriera):
--   select tablename from pg_tables where schemaname='public' and tablename = 'hilo_soporte';
--   select proname, pronargs from pg_proc where proname = 'portal_enviar_mensaje';
--   select tgname from pg_trigger where tgname = 'trg_hilo_soporte_actividad';
