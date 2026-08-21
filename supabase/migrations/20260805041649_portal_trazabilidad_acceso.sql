-- Trazabilidad del portal — 5-ago-2026
-- Quién entró y cuándo. Se apunta al leer la situación (que es lo que hace el
-- portal nada más abrirse), así el equipo ve en la ficha del comprador si de
-- verdad ha entrado o el enlace se quedó sin abrir. No es una tabla de log:
-- interesa la última visita y cuántas van, no cada pulsación.
alter table public.portal_accesos
  add column if not exists ultimo_acceso timestamptz,
  add column if not exists accesos int not null default 0;

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

  -- el rastro de entrada, antes de responder
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
       and not coalesce(f.anulada, false)), '[]'::jsonb),
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
