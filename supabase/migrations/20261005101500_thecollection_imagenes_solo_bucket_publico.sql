-- THE COLLECTION v2 · F5b/F9a — coleccion_publica(): solo se anuncian las fotos que EXISTEN en el bucket publico `deck`. 5-oct-2026.
-- Decision del owner (5-oct): usar las del servidor para las casas cuyas fotos estan en `deck-privado`.
-- Hallazgo: el diff F9a comparaba el NUMERO de fotos pero no si su URL respondia; tirta-hikari (8), cube (8), river (9) y aqua (8)
-- devolvian 400 en el bucket publico `deck` (33 imagenes). Su fichero esta fisicamente en `deck-privado`.
-- Revision de Seguridad (5-oct): el primer intento filtraba por deck_bucket_debido() (estado LOGICO) y dejaba sin galeria a 6 fichas
-- (pura-dalem, riverfront-i/ii-small/iii, rurung-anyar, tangkuban-village: 54 fotos) cuyo deck esta «cerrado» pero cuyos ficheros siguen
-- en `deck`. Por eso el filtro mira el bucket FISICO: la foto se anuncia si y solo si existe en storage.objects con bucket_id = 'deck'.
-- Solo cambia el CTE `imgs`; el resto es la funcion de 20261002150000 sin tocar (mismos grants: solo anon, DEFINER, search_path vacio).
-- ROLLBACK: volver a aplicar la funcion de 20261002150000.

create or replace function public.coleccion_publica()
  returns jsonb
  language sql stable security definer set search_path to ''
  as $cp$
with
tramo as (select public.catalogo_tramo_activo() as t),
fichas as (
  select f.id, f.slug, f.linea, f.region_key, f.region, f.en_coleccion, f.destacada, f.destacada_home, f.orden,
         f.proyecto_id, f.modelo_id, f.unidad_id, f.precio_modo, f.precio_eur, f.tenure, f.lease_years, f.estado_obra,
         f.dormitorios, f.banos, f.construido_m2, f.parcela_m2, f.textos, f.ficha,
         p.ubicacion_maps, p.fecha_entrega_estimada_proyecto as p_entrega
    from public.fichas_publicas f
    join public.proyectos p on p.id = f.proyecto_id
   where f.publicada_web and coalesce(p.activo, true)
),
uni as (
  select f.id as ficha_id, f.linea, u.codigo, u.codigo_orden, u.superficie_m2, u.moneda, u.precio, u.precio_suelo,
         u.precio_construccion, u.estado,
         case u.estado when 'disponible' then 'disponible' when 'reservada' then 'reservada' else 'vendida' end as estado_pub
    from fichas f
    join public.unidades u on u.proyecto_id = f.proyecto_id and (f.unidad_id is null or u.id = f.unidad_id)
   where u.estado in ('disponible', 'reservada', 'vendida', 'cobrada', 'bloqueada', 'no_disponible')
),
parcelas as (
  select u.ficha_id,
         jsonb_agg(jsonb_strip_nulls(jsonb_build_object('codigo', u.codigo, 'superficie_m2', u.superficie_m2, 'estado', u.estado_pub))
                   order by u.codigo_orden nulls last, u.codigo) as j,
         count(*) as total,
         count(*) filter (where u.estado_pub = 'disponible') as disponibles
    from uni u group by u.ficha_id
),
mods as (
  select distinct on (f.id, m.id)
         f.id as ficha_id, m.id as modelo_id, m.nombre, m.dormitorios, m.villa_m2, m.orden,
         case when tr.t = '2026' then m.precio_construccion
              else coalesce(m.precio_construccion_2027, m.precio_construccion) end as precio_raw,
         public._coleccion_a_eur(case when tr.t = '2026' then m.precio_construccion
                                      else coalesce(m.precio_construccion_2027, m.precio_construccion) end, m.moneda) as eur,
         (select d.path from public.deck_fotos d where d.modelo_id = m.id order by d.orden, d.creado_en limit 1) as foto
    from fichas f
    cross join tramo tr
    join public.modelos_villa mv on mv.proyecto_id = f.proyecto_id and mv.modelo_id is not null
    join public.modelos m on m.id = mv.modelo_id and m.publicado and m.activo
   where f.linea = 'villa' and (f.modelo_id is null or m.id = f.modelo_id)
   order by f.id, m.id
),
mod_min as (
  select m.ficha_id,
         case when bool_or(m.precio_raw is not null and m.eur is null) then null else min(m.eur) end as eur
    from mods m group by m.ficha_id
),
mods_json as (
  select m.ficha_id,
         jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'name', m.nombre, 'beds', m.dormitorios, 'built', m.villa_m2,
           'priceEUR', floor(m.eur), 'image', m.foto)) order by m.orden, m.nombre) as j
    from mods m group by m.ficha_id
),
desde as (
  select z.ficha_id,
         case when bool_or(z.t is null) then null else floor(min(z.t)) end as eur
    from (select u.ficha_id,
                 public._coleccion_a_eur(u.precio, u.moneda)
                 + case when u.linea = 'villa' and coalesce(u.precio_construccion, 0) = 0 then mm.eur else 0 end as t
            from uni u
            left join mod_min mm on mm.ficha_id = u.ficha_id
           where u.estado = 'disponible' and u.precio > 0) z
   group by z.ficha_id
),
precio as (
  select f.id as ficha_id,
         case when f.precio_modo = 'fijo'  and f.precio_eur > 0 then 'fixed'
              when f.precio_modo = 'desde' and d.eur > 0        then 'from'
              else 'consultar' end as modo,
         case when f.precio_modo = 'fijo'  and f.precio_eur > 0 then f.precio_eur
              when f.precio_modo = 'desde' and d.eur > 0        then d.eur
              else 0 end as eur
    from fichas f left join desde d on d.ficha_id = f.id
),
tamanos as (
  select u.ficha_id, u.superficie_m2 as size,
         floor(min(public._coleccion_a_eur(coalesce(u.precio_suelo, u.precio), u.moneda))) as eur
    from uni u
   where u.linea in ('villa', 'land') and u.estado = 'disponible'
     and u.superficie_m2 > 0 and coalesce(u.precio_suelo, u.precio) > 0
   group by u.ficha_id, u.superficie_m2
),
land_json as (
  select t.ficha_id,
         jsonb_agg(jsonb_build_object('size', t.size, 'pricePerM2', round(t.eur / t.size), 'priceEUR', t.eur) order by t.size) as j
    from tamanos t where t.eur is not null group by t.ficha_id
),
imgs as (
  -- Solo las fotos que existen FISICAMENTE en el bucket publico `deck`. Las de un proyecto con el deck cerrado pueden estar en `deck-privado`
  -- (AXW-66, 28-sep) y su URL publica da 400; el estado logico (deck_bucket_debido) no sirve de filtro porque diverge de donde estan los
  -- ficheros. Una ficha sin ninguna foto publica cae a ficha->'imagenes' (rutas del servidor que la web ya publica hoy): cero exposicion nueva.
  select f.id as ficha_id, jsonb_agg(d.path order by d.orden, d.creado_en) as j
    from fichas f
    join public.deck_fotos d on d.ambito = 'proyecto' and d.proyecto_id = f.proyecto_id and d.uso in ('galeria', 'hero')
    join storage.objects o on o.bucket_id = 'deck' and o.name = d.path
   group by f.id
)
select jsonb_build_object(
  'properties', coalesce((
    select jsonb_agg(x.j order by x.orden, x.slug)
      from (
        select f.orden, f.slug,
          jsonb_strip_nulls(
            jsonb_build_object(
              'id', f.slug, 'line', f.linea, 'region', f.region, 'regionKey', f.region_key,
              'featured', f.destacada, 'status', case when f.estado_obra is not null then 'status.' || f.estado_obra end,
              'tenure', case when f.tenure is not null then 'tenure.' || f.tenure end, 'leaseYears', f.lease_years,
              'handover', coalesce(case when f.p_entrega is not null
                                        then 'Q' || extract(quarter from f.p_entrega)::int || ' ' || extract(year from f.p_entrega)::int end,
                                   nullif(f.ficha->>'handover', '')),
              'visible', true, 'inCollection', f.en_coleccion, 'homeFeatured', f.destacada_home,
              'title', f.textos->'title', 'sub', f.textos->'sub', 'desc', f.textos->'desc', 'metaText', f.textos->'meta',
              'splitTitle', f.textos->'split_title', 'splitSub', f.textos->'split_sub',
              'highlights', coalesce(f.ficha->'highlights', '[]'::jsonb),
              'tabs', coalesce(f.ficha#>'{diseno,tabs}', '[]'::jsonb),
              'techSpecs', coalesce(f.ficha->'tech_specs', '[]'::jsonb),
              'beds', coalesce(mo.dormitorios, f.dormitorios), 'baths', coalesce(mo.banos, f.banos),
              'built', coalesce(mo.villa_m2, f.construido_m2), 'land', coalesce(uf.superficie_m2, f.parcela_m2),
              'pool', f.ficha#>'{equipamiento,pool}', 'poolType', f.ficha#>'{equipamiento,poolType}',
              'garage', f.ficha#>'{equipamiento,garage}', 'garageDesc', f.ficha#>'{equipamiento,garageDesc}',
              'furnished', f.ficha#>'{equipamiento,furnished}', 'style', f.ficha#>'{equipamiento,style}',
              'view', f.ficha->'view'
            )
            || jsonb_build_object(
              'priceEUR', pr.eur, 'priceMode', pr.modo,
              'paymentPlan', coalesce(f.ficha->'payment_plan', '[]'::jsonb),
              'unitsAvailable', case when f.unidad_id is null then pa.disponibles end,
              'unitsTotal', case when f.unidad_id is null then pa.total end,
              'parcelas', coalesce(pa.j, '[]'::jsonb),
              'images', coalesce(im.j, f.ficha->'imagenes', '[]'::jsonb),
              'videos', coalesce(f.ficha->'videos', '[]'::jsonb),
              'aerial', f.ficha->'aerial',
              'logo', f.ficha#>'{diseno,logo}', 'isotype', f.ficha#>'{diseno,isotype}', 'landColor', f.ficha#>'{diseno,landColor}',
              'splitImage', f.ficha#>'{diseno,splitImage}', 'bleedImage', f.ficha#>'{diseno,bleedImage}',
              'plan3dImage', f.ficha#>'{diseno,plan3dImage}',
              'mapImage', coalesce(
                case when f.ubicacion_maps ~ '^\s*-?[0-9]+([.][0-9]+)?\s*,\s*-?[0-9]+([.][0-9]+)?\s*$'
                       then 'https://www.google.com/maps?q=' || regexp_replace(f.ubicacion_maps, '\s', '', 'g')
                     when f.ubicacion_maps ~ '^https://' then f.ubicacion_maps end,
                f.ficha->>'mapa_url'),
              'masterplanImage', coalesce(dc.masterplan_imagen, f.ficha->>'masterplan_imagen'),
              'masterplanPlots', coalesce(f.ficha->'masterplan_pins', '[]'::jsonb),
              'downloads', coalesce(f.ficha->'downloads', '[]'::jsonb),
              'landOptions', coalesce(lj.j, '[]'::jsonb),
              'homeModels', coalesce(mj.j, '[]'::jsonb)
            )
          ) as j
          from fichas f
          join precio pr on pr.ficha_id = f.id
          left join parcelas pa on pa.ficha_id = f.id
          left join imgs im on im.ficha_id = f.id
          left join land_json lj on lj.ficha_id = f.id
          left join mods_json mj on mj.ficha_id = f.id
          left join public.modelos mo on mo.id = f.modelo_id
          left join public.unidades uf on uf.id = f.unidad_id
          left join public.deck_config_proyecto dc on dc.proyecto_id = f.proyecto_id
      ) x), '[]'::jsonb),
  'generated_at', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
)
$cp$;

revoke all on function public.coleccion_publica() from public, anon, authenticated, service_role;
grant execute on function public.coleccion_publica() to anon;
