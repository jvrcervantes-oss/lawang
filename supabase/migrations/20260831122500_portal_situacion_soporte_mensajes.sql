-- portal_situacion() suma tickets/mensajes/preferencias (31-ago-2026), sobre
-- las tablas de la migración anterior. Sigue siendo UN solo viaje de red
-- (mismo criterio que ya usa esta función para contratos/facturas/obra):
-- tickets y mensajes de un comprador real son pocos, no hace falta paginar.
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
    -- client_id "principal" (el más antiguo): con lo que hoy tiene el portal
    -- (una persona, no una familia con dos fichas distintas) basta para que
    -- el crear-ticket/mensaje tenga a qué apuntar sin preguntar primero.
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
    'tickets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', tc.id, 'asunto', tc.asunto, 'categoria', tc.categoria,
        'estado', tc.estado, 'creado_en', tc.creado_en,
        'mensajes', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'de', tm.de, 'autor', tm.autor, 'texto', tm.texto, 'creado_en', tm.creado_en)
                 order by tm.creado_en)
            from public.tickets_comprador_mensajes tm
           where tm.ticket_id = tc.id), '[]'::jsonb)
      ) order by tc.creado_en desc)
      from public.tickets_comprador tc
      join mis_clientes mc3 on mc3.client_id = tc.client_id), '[]'::jsonb),
    'mensajes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'de', mc4msg.de, 'autor', mc4msg.autor, 'texto', mc4msg.texto, 'creado_en', mc4msg.creado_en)
             order by mc4msg.creado_en)
        from public.mensajes_comprador mc4msg
        join mis_clientes mc4 on mc4.client_id = mc4msg.client_id), '[]'::jsonb),
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
