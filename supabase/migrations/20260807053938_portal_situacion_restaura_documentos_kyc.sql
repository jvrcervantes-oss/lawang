-- Restaura los bloques `documentos` y `kyc` de portal_situacion() que se
-- perdieron sin querer en la migracion de esta manana (facturas_enviada_y_portal):
-- esa migracion se escribio copiando el cuerpo de contracts/sql/portal_comprador.sql,
-- que nunca tuvo estos dos bloques versionados -- se habian anadido a mano en
-- el editor SQL de Supabase en algun momento posterior y no se volvieron a
-- guardar en el repo. create or replace function los borro sin que nadie lo
-- pidiera. Reconstruidos aqui a partir del propio front-end (portal/index.html
-- espera exactamente estos campos) y del esquema real de las tablas.
create or replace function public.portal_situacion()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_email text := lower(coalesce(auth.email(), ''));
  r jsonb;
begin
  if not public.es_portal() or v_email = '' then
    raise exception 'solo usuarios del portal' using errcode = '42501';
  end if;

  with mis_clientes as (
    select distinct pa.client_id
      from portal_accesos pa
     where pa.activo and pa.email = v_email
  ),
  mis_ids as (
    select distinct cc.contrato_id as id
      from contrato_compradores cc
      join mis_clientes mc on mc.client_id = cc.client_id
  ),
  cobros as (
    select f.contrato_id,
           coalesce(sum(f.total) filter (where not coalesce(f.anulada, false)
                                           and f.tipo <> 'proforma'), 0) as cobrado
      from facturas f
     where f.contrato_id in (select id from mis_ids)
     group by f.contrato_id
  )
  select jsonb_build_object(
    'nombre', (select cl.full_name from clients cl
                join mis_clientes mc on mc.client_id = cl.id
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
        'cobrado',     coalesce(k.cobrado, 0)
      ) order by c.created_at)
      from contratos c
      join mis_ids m on m.id = c.id
      left join cobros k on k.contrato_id = c.id), '[]'::jsonb),
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
        'cliente',         f.cliente_nombre,
        'proyecto',        f.proyecto_nombre,
        'lineas',          f.datos->'lineas',
        'totales',         f.datos->'totales',
        'fields',          f.datos->'fields'
      ) order by f.fecha_emision desc, f.numero desc)
      from facturas f
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
            from obra_fotos o
           where o.unidad_id = u.id and o.visible), '[]'::jsonb)
      ))
      from unidades u
      join contratos c2 on c2.id = u.contrato_id
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
      from documentos_proyecto dp
     where dp.visible_portal
       and exists (
         select 1 from contratos c3
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
      from documents doc
      join mis_clientes mc2 on mc2.client_id = doc.client_id), '[]'::jsonb),
    'fases', coalesce((
      select jsonb_agg(jsonb_build_object(
               'orden', ff.orden, 'clave', ff.clave, 'es', ff.es, 'en', ff.en)
             order by ff.orden)
        from obra_fases ff), '[]'::jsonb)
  ) into r;
  return r;
end $$;
revoke execute on function public.portal_situacion() from public;
revoke execute on function public.portal_situacion() from anon;
grant execute on function public.portal_situacion() to authenticated;;
