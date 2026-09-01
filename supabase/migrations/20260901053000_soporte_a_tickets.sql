-- Soporte del portal: de "un hilo por comprador" a TICKETS (1-sep-2026,
-- corrección del owner sobre el diseño de esta misma mañana — "elegí mal,
-- soporte debe ser por tickets y no como una conversación continua").
--
-- hilo_soporte pasa de 1 fila por client_id (PK=client_id) a 1 fila por
-- TICKET (PK=id nuevo, client_id deja de ser único: un comprador puede tener
-- varios tickets, incluso de la misma categoría). La categoría —ya existía
-- como etiqueta opcional por MENSAJE— pasa a vivir en el TICKET y hace de
-- título («Pagos», «Documentación», «Obra», «Otro»; «General» es el cajón
-- donde migran las conversaciones que ya existían hoy, ya abierto para no
-- perder contexto). mensajes_comprador se cuelga de un hilo_id concreto en
-- vez de solo de client_id+categoría suelta.
--
-- destructivo-ok: DROP CONSTRAINT hilo_soporte_pkey se sustituye por otra PK
-- en la misma sentencia (ninguna fila se pierde, sigue habiendo exactamente
-- una PK); DROP FUNCTION portal_enviar_mensaje(uuid,text,text) es la firma
-- VIEJA de la misma función, reemplazada por la de abajo — código superseded,
-- no dato. Ninguna fila de hilo_soporte ni de mensajes_comprador se borra en
-- esta migración.

-- 1) hilo_soporte: nueva PK, categoría obligatoria
alter table public.hilo_soporte add column id uuid not null default gen_random_uuid();
alter table public.hilo_soporte add column categoria text;
update public.hilo_soporte set categoria = 'General' where categoria is null;
alter table public.hilo_soporte alter column categoria set not null;
alter table public.hilo_soporte add constraint hilo_soporte_categoria_check
  check (categoria in ('Pagos','Documentación','Obra','Otro','General'));
alter table public.hilo_soporte drop constraint hilo_soporte_pkey;
alter table public.hilo_soporte add constraint hilo_soporte_pkey primary key (id);
create index if not exists hilo_soporte_client_id_idx on public.hilo_soporte(client_id);

-- 2) mensajes_comprador: cada mensaje cuelga de UN ticket. La columna
-- `categoria` de mensajes_comprador se deja EN PAZ (no se borra: no destruye
-- nada tocar una columna que ya no se escribe, y borrarla es DDL destructivo
-- que sí pide permiso aparte) — simplemente deja de usarse, el título ahora
-- vive en el ticket.
alter table public.mensajes_comprador add column hilo_id uuid references public.hilo_soporte(id);
update public.mensajes_comprador mc
   set hilo_id = hs.id
  from public.hilo_soporte hs
 where hs.client_id = mc.client_id;   -- 1:1 en este punto de la migración: todavía no existe ningún ticket nuevo
alter table public.mensajes_comprador alter column hilo_id set not null;
create index if not exists mensajes_comprador_hilo_id_idx on public.mensajes_comprador(hilo_id);

-- 3) trigger de actividad: ya no upsertea por client_id (eso lo hace ahora
-- portal_abrir_ticket al crear el ticket) — solo bumpea EL ticket del mensaje.
create or replace function public._trg_hilo_soporte_actividad()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  update public.hilo_soporte
     set actualizado_en = now(),
         estado = case when new.de = 'cliente' then 'abierto' else estado end
   where id = new.hilo_id;
  return new;
exception when others then
  return new;   -- el mensaje ya se guardó; un fallo aquí no lo deshace
end
$function$;

-- 4) aviso al equipo: la categoría ahora sale del TICKET (join por hilo_id),
-- no de new.categoria (esa columna ya no se rellena en mensajes nuevos).
create or replace function public._trg_aviso_mensaje_comprador()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_nombre text; v_cuerpo text; v_categoria text;
begin
  if new.de <> 'cliente' then return new; end if;
  select c.full_name into v_nombre from public.clients c where c.id = new.client_id;
  select hs.categoria into v_categoria from public.hilo_soporte hs where hs.id = new.hilo_id;
  v_cuerpo :=
    'Nuevo mensaje del comprador en el área de clientes.' || chr(10) || chr(10) ||
    'Comprador: ' || coalesce(v_nombre, 'sin nombre') || chr(10) ||
    'Ticket: ' || coalesce(v_categoria, 'General') || chr(10) ||
    chr(10) ||
    'Mensaje: ' || new.texto || chr(10) || chr(10) ||
    'Responder desde: https://lawangproperties.com/intranet/soporte/?id=' || new.client_id::text;
  perform public._avisar_equipo_soporte(new.client_id, 'Lawang · mensaje de ' || coalesce(v_nombre, 'un comprador'), v_cuerpo);
  return new;
exception when others then
  return new;
end
$function$;

-- 5) portal_enviar_mensaje: cambia de firma (p_client_id,p_texto,p_categoria)
-- a (p_hilo_id,p_texto) — el ticket ya trae su categoría y su comprador, no
-- hace falta que el cliente los repita (y no puede mentir sobre cuáles son).
-- Se DROPEA la firma vieja explícitamente: es código superseded, no dato.
drop function if exists public.portal_enviar_mensaje(uuid, text, text);

create or replace function public.portal_enviar_mensaje(p_hilo_id uuid, p_texto text)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_id uuid; v_de text; v_autor text; v_client_id uuid;
begin
  if btrim(coalesce(p_texto,'')) = '' then raise exception 'mensaje vacío' using errcode = '22023'; end if;

  select client_id into v_client_id from public.hilo_soporte where id = p_hilo_id;
  if v_client_id is null then raise exception 'ticket no encontrado' using errcode = '22023'; end if;

  if public.es_agente() then
    v_de := 'equipo'; v_autor := auth.email();
  elsif public.es_portal() then
    if not exists (select 1 from public.portal_accesos pa
                    where pa.activo and pa.email = lower(coalesce(auth.email(), '')) and pa.client_id = v_client_id) then
      raise exception 'esa ficha no es tuya' using errcode = '42501';
    end if;
    v_de := 'cliente'; v_autor := null;
  else
    raise exception 'sin permiso' using errcode = '42501';
  end if;

  insert into public.mensajes_comprador (client_id, de, autor, texto, hilo_id)
    values (v_client_id, v_de, v_autor, btrim(p_texto), p_hilo_id)
    returning id into v_id;
  return v_id;
end
$function$;

revoke execute on function public.portal_enviar_mensaje(uuid, text) from public;
revoke execute on function public.portal_enviar_mensaje(uuid, text) from anon;
grant execute on function public.portal_enviar_mensaje(uuid, text) to authenticated;

-- 6) portal_abrir_ticket: NUEVO — solo el comprador abre tickets (el equipo
-- responde, no origina; mismo criterio que ya regía "quién escribe primero").
create or replace function public.portal_abrir_ticket(p_client_id uuid, p_categoria text, p_texto text)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_hilo_id uuid;
begin
  if not public.es_portal() then raise exception 'sin permiso' using errcode = '42501'; end if;
  if not exists (select 1 from public.portal_accesos pa
                  where pa.activo and pa.email = lower(coalesce(auth.email(), '')) and pa.client_id = p_client_id) then
    raise exception 'esa ficha no es tuya' using errcode = '42501';
  end if;
  if btrim(coalesce(p_texto,'')) = '' then raise exception 'mensaje vacío' using errcode = '22023'; end if;
  if p_categoria is null or p_categoria not in ('Pagos','Documentación','Obra','Otro') then
    raise exception 'categoría no válida' using errcode = '22023';
  end if;

  insert into public.hilo_soporte (id, client_id, categoria, estado, actualizado_en)
    values (gen_random_uuid(), p_client_id, p_categoria, 'abierto', now())
    returning id into v_hilo_id;

  insert into public.mensajes_comprador (client_id, de, autor, texto, hilo_id)
    values (p_client_id, 'cliente', null, btrim(p_texto), v_hilo_id);

  return v_hilo_id;
end
$function$;

revoke execute on function public.portal_abrir_ticket(uuid, text, text) from public;
revoke execute on function public.portal_abrir_ticket(uuid, text, text) from anon;
grant execute on function public.portal_abrir_ticket(uuid, text, text) to authenticated;

-- 7) portal_situacion(): 'mensajes' (plano) + 'hilo_estado' (escalar) se
-- sustituyen por 'tickets' (un array, cada uno con sus propios mensajes).
create or replace function public.portal_situacion()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
    'firma_pendiente', coalesce((
      select jsonb_agg(jsonb_build_object(
        'contrato_id',  cf.contrato_id,
        'enviado_en',   cf.creado_en,
        'expira_en',    cf.expira_en,
        'enlace',       cf.enlace_firma
      ) order by cf.creado_en desc)
      from public.contrato_firmas cf
      join mis_ids m on m.id = cf.contrato_id
     where cf.estado = 'pendiente'
       and cf.expira_en > now()
       and cf.enlace_firma is not null
       and lower(btrim(cf.firmante_email)) = v_email), '[]'::jsonb),
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
    'tickets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',            hs.id,
        'categoria',     hs.categoria,
        'estado',        hs.estado,
        'actualizado_en', hs.actualizado_en,
        'mensajes', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'id', mm.id, 'de', mm.de, 'autor', mm.autor, 'texto', mm.texto, 'creado_en', mm.creado_en)
                 order by mm.creado_en)
            from public.mensajes_comprador mm
           where mm.hilo_id = hs.id), '[]'::jsonb)
      ) order by hs.actualizado_en desc)
      from public.hilo_soporte hs
      join mis_clientes mc7 on mc7.client_id = hs.client_id), '[]'::jsonb),
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
$function$;
