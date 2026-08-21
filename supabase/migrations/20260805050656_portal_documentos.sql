-- destructivo-ok: solo "drop policy if exists" sobre policies que este script recrea; ningún dato ni objeto ajeno se toca
-- ============================================================================
-- Documentos en el portal del comprador — 5-ago-2026
-- ----------------------------------------------------------------------------
-- El comprador ve TRES cosas suyas además de contratos y facturas:
--   · la documentación de su promoción que el equipo haya marcado para él,
--   · lo que él mismo entregó (KYC), con su caducidad.
--
-- `visible_portal` es una decisión EXPLÍCITA y arranca en false para todo lo ya
-- guardado. No se reutiliza `confidencial`: "no confidencial" significa que se
-- puede compartir dentro del estudio, que no es lo mismo que publicarlo en el
-- portal de un comprador. Los dos documentos que hay hoy son confidenciales
-- (dossier comercial y tabla de precios), así que nadie ve nada por defecto.
-- ============================================================================
alter table public.documentos_proyecto
  add column if not exists visible_portal boolean not null default false;

comment on column public.documentos_proyecto.visible_portal is
  'Si el comprador lo ve en /portal/. Decisión explícita del equipo; nunca se deduce de `confidencial`.';

-- ── el nombre del proyecto no casa exacto entre tablas ──────────────────────
-- Los contratos dicen "Palm Field" y la documentación "Palm Field by Balian
-- Hills". Comparar con `=` no encuentra nada, y renombrar datos de producción
-- para que cuadren es peor: se compara conteniendo, en minúsculas.
create or replace function public.mismo_proyecto(a text, b text)
returns boolean language sql immutable set search_path = '' as $$
  select a is not null and b is not null and (
    lower(btrim(a)) = lower(btrim(b))
    or lower(btrim(a)) like '%' || lower(btrim(b)) || '%'
    or lower(btrim(b)) like '%' || lower(btrim(a)) || '%')
$$;

create or replace function public.portal_situacion()
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_email text := lower(coalesce(auth.email(), ''));
  r jsonb;
begin
  if not public.es_portal() or v_email = '' then
    raise exception 'solo usuarios del portal' using errcode = '42501';
  end if;

  update portal_accesos
     set ultimo_acceso = now(), accesos = accesos + 1
   where email = v_email and activo;

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
  mis_proyectos as (
    select distinct c.proyecto_nombre as p
      from contratos c join mis_ids m on m.id = c.id
     where c.proyecto_nombre is not null
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
        'id', c.id, 'numero', c.numero, 'tipo', c.tipo,
        'proyecto', c.proyecto_nombre,
        'parcela', c.datos->'fields'->>'parcela_codigo',
        'precio', c.precio_total,
        'precio_txt', nullif(c.datos->'fields'->>'precio_total', ''),
        'moneda', c.moneda, 'fecha_firma', c.fecha_firma,
        'firmado', coalesce(c.bloqueado, false),
        'pdf', c.pdf_firmado_path,
        'hitos', case when jsonb_typeof(c.datos->'hitos') = 'array'
                      then c.datos->'hitos' else '[]'::jsonb end,
        'cobrado', coalesce(k.cobrado, 0)
      ) order by c.created_at)
      from contratos c
      join mis_ids m on m.id = c.id
      left join cobros k on k.contrato_id = c.id), '[]'::jsonb),
    'facturas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'numero', f.numero, 'tipo', f.tipo, 'sociedad', f.sociedad,
        'contrato_numero', f.contrato_numero, 'fecha', f.fecha_emision,
        'total', f.total, 'moneda', f.moneda, 'cliente', f.cliente_nombre,
        'proyecto', f.proyecto_nombre,
        'lineas', f.datos->'lineas', 'totales', f.datos->'totales',
        'fields', f.datos->'fields'
      ) order by f.fecha_emision desc, f.numero desc)
      from facturas f
     where f.contrato_id in (select id from mis_ids)
       and not coalesce(f.anulada, false)), '[]'::jsonb),
    'obra', coalesce((
      select jsonb_agg(jsonb_build_object(
        'unidad', u.codigo, 'proyecto', u.proyecto, 'contrato_numero', c2.numero,
        'fase', u.obra_fase, 'fecha_entrega', u.obra_fecha_entrega,
        'actualizado', u.obra_actualizado,
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
    -- documentación de SU promoción, solo la marcada para el portal
    'documentos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', dp.id, 'titulo', dp.titulo, 'descripcion', dp.descripcion,
        'categoria', dp.categoria, 'proyecto', dp.proyecto,
        'path', dp.path, 'url', dp.url, 'mime', dp.mime, 'bytes', dp.bytes,
        'fecha', dp.creado_en
      ) order by dp.categoria, dp.titulo)
      from documentos_proyecto dp
     where dp.visible_portal
       and exists (select 1 from mis_proyectos mp where public.mismo_proyecto(dp.proyecto, mp.p))), '[]'::jsonb),
    -- lo que el propio comprador entregó
    'kyc', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tipo', dc.doc_type, 'path', dc.storage_path, 'estado', dc.status,
        'subido', dc.uploaded_at, 'caduca', dc.caduca_el
      ) order by dc.uploaded_at desc)
      from documents dc
      join mis_clientes mc on mc.client_id = dc.client_id
     where dc.storage_path is not null), '[]'::jsonb),
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
grant execute on function public.portal_situacion() to authenticated;

-- ── ficheros: cada bucket con su comprobación ───────────────────────────────
create or replace function public.portal_ve_documento(p_name text)
returns boolean language sql stable security definer set search_path = public as
$$ select public.es_portal() and exists (
     select 1
       from documentos_proyecto dp
      where dp.visible_portal
        and dp.path = p_name
        and exists (
          select 1
            from portal_accesos pa
            join contrato_compradores cc on cc.client_id = pa.client_id
            join contratos c on c.id = cc.contrato_id
           where pa.activo
             and pa.email = lower(coalesce(auth.email(), ''))
             and public.mismo_proyecto(dp.proyecto, c.proyecto_nombre))) $$;

create or replace function public.portal_ve_kyc(p_name text)
returns boolean language sql stable security definer set search_path = public as
$$ select public.es_portal() and exists (
     select 1
       from documents dc
       join portal_accesos pa on pa.client_id = dc.client_id
      where pa.activo
        and pa.email = lower(coalesce(auth.email(), ''))
        and dc.storage_path = p_name) $$;

revoke execute on function public.portal_ve_documento(text) from public;
revoke execute on function public.portal_ve_documento(text) from anon;
grant execute on function public.portal_ve_documento(text) to authenticated;
revoke execute on function public.portal_ve_kyc(text) from public;
revoke execute on function public.portal_ve_kyc(text) from anon;
grant execute on function public.portal_ve_kyc(text) to authenticated;

drop policy if exists "portal lee la documentacion compartida" on storage.objects;
create policy "portal lee la documentacion compartida" on storage.objects
  for select to authenticated
  using (bucket_id = 'documentacion' and public.portal_ve_documento(name));

drop policy if exists "portal lee sus propios documentos kyc" on storage.objects;
create policy "portal lee sus propios documentos kyc" on storage.objects
  for select to authenticated
  using (bucket_id = 'kyc' and public.portal_ve_kyc(name));;
