-- THE COLLECTION v2 · F5b — coleccion_publica(): la lectura pública de The Collection. 2-oct-2026. NO APLICADA (paso 1: diseño + prueba).
-- Encargo: encargos/20261002_lawang_thecollection_v2.md (F5b) y _F1.md (§3 llamadores, §5 estado en tiempo real).
-- Contrato de claves: coleccion/contrato_publico.json (F0). Prueba: contracts/sql/prueba_coleccion_publica.sql.
-- Sin pareja en erp/migraciones/: Lawang es independiente del maestro (28-sep).
--
-- QUÉ ES: una RPC SECURITY DEFINER, sin parámetros, que devuelve {properties:[…], generated_at}. Cada ficha viene EN LA FORMA DE
-- data.json (camelCase, textos {en,es}, tenure/status con su prefijo i18n) para que la SPA cambie solo la fuente. settings (rates,
-- whatsapp, email) y downloads globales NO salen de aquí: siguen en api/config.php (fuera del encargo); lib.php los compone.
--
-- Decisiones, con su porqué:
--   1. Campos ESCRITOS A MANO, nunca select * ni to_jsonb(fila): una columna nueva de fichas_publicas, unidades, modelos o proyectos
--      no se publica sola (criterio F5b). Lo único que pasa «en bloque» son valores sueltos de los jsonb editoriales (ficha->'highlights',
--      textos->'title'…), extraídos por clave; coleccion/lib.php los vuelve a escanear a cualquier profundidad (claves prohibidas).
--   2. Una ficha se sirve solo si publicada_web = true Y proyecto_id NO es nulo Y el proyecto sigue activo. Cierra LAW-489: el
--      ON DELETE SET NULL de F2 deja la ficha sin vínculo en silencio; aquí deja de servirse en vez de publicar una ficha huérfana
--      (sin entrega, sin estado, sin galería).
--   3. DINERO (el owner fija el importe, aquí solo se deriva):
--        · precio_modo 'fijo'  → priceMode 'fixed', priceEUR = fichas_publicas.precio_eur (signature; es EUR por definición).
--        · precio_modo 'desde' → priceMode 'from', priceEUR = MÍNIMO de unidades.precio de las unidades DISPONIBLES del proyecto
--          (convertido a EUR) — un dueño, sin copia manual. Para la línea 'villa' (casa + parcela elegibles) a la unidad que es solo
--          suelo (precio_construccion vacío) se le suma la construcción más barata de los modelos publicados del proyecto
--          (mismo tramo 2026/2027 que catalogo_publico); una unidad que ya trae construcción (p. ej. Pura Dalem) no se suma dos veces.
--          Línea 'land': solo el suelo. Se redondea HACIA ABAJO a euro entero: un «desde» nunca puede quedar por encima del mínimo real.
--          Vendidas/reservadas no cuentan: anunciar «desde» el precio de una parcela que ya no está sería falso.
--        · sin importe derivable (ninguna unidad disponible con precio, modelo sin precio, o moneda sin tipo de cambio) → 'consultar',
--          priceEUR 0. NO se cae al precio_eur manual de la ficha: sería un segundo dueño del «desde» (cuyo CHECK F2 todavía lo exige
--          para publicar: pasa a ser un dato de respaldo sin lector; F3 debe dejar de pedirlo y salud_lawang comparar los dos).
--        · precio_modo 'consultar' → 'consultar'.
--   4. MONEDA. Riverfront I/II están en IDR. En la intranet NO existe un tipo de cambio autoritativo: dinero.js lo dice
--      («no hay tipo de cambio en el sistema»), settings.rates de data.json solo trae EUR/USD/AUD, y la constante 20400 de
--      intranet/v4/assets/datos.js es una estimación de pantalla (21-sep) que no puede fijar un precio público. Por eso la
--      conversión lee config_instancia.clave = 'tc_<moneda>_por_eur' (p. ej. tc_idr_por_eur = IDR por 1 EUR), que DEBE poner el owner;
--      acepta solo un valor numérico positivo, actualizado en los últimos 60 días (un tipo caducado no fija precios), y para IDR entre
--      5.000 y 100.000 (un cero de más no multiplica un precio por diez). Si falta, está caducado o no es plausible: el importe de
--      esa moneda es NULL y el «desde» pasa a 'consultar' (falla cerrado), nunca a un número inventado. Hoy afecta a 0 fichas: las dos
--      de Riverfront son signature con precio fijo en EUR; el mecanismo está para el día que una ficha IDR sea 'desde'.
--   5. ESTADO EN TIEMPO REAL por parcela: parcelas = [{codigo, superficie_m2, estado}] solo de fichas publicadas. Mapeo del owner:
--      disponible→disponible · reservada→reservada · vendida|cobrada|bloqueada|no_disponible→vendida. Un estado que no sea uno de
--      esos seis (futuro) NO se publica (la unidad no sale): no se afirma lo que no se sabe. Nunca sale hora, motivo, comprador,
--      contrato, notas ni precio por unidad. Ficha con unidad_id (las 4 casas sueltas) → solo esa unidad; sin unidad_id → todas las
--      del proyecto. unitsAvailable/unitsTotal se DERIVAN de ese mismo conjunto (solo fichas sin unidad_id).
--   6. Lo que ya tiene dueño se lee por JOIN, la ficha es solo respaldo: beds/baths/built del modelo (modelo_id) y land de la unidad
--      (unidad_id) si existen, si no de las columnas de la ficha; handover de proyectos.fecha_entrega_estimada_proyecto (formato
--      «Q1 2027») y si no de ficha.handover; mapImage de proyectos.ubicacion_maps (en la intranet son coordenadas «lat, lng»: se sirve como
--      https://www.google.com/maps?q=lat,lng, el formato de data.json; un https:// se respeta, cualquier otro texto se ignora; OJO F4(d):
--      la coordenada de Palm Field difiere de la que traía la ficha, manda la intranet) y si no de ficha.mapa_url; masterplanImage de deck_config_proyecto.masterplan_imagen y si no de la ficha.
--   7. images = galería de deck_fotos del proyecto (uso galeria|hero, orden, creado_en), como RUTAS del bucket público `deck` (sin
--      URL: la base URL es infraestructura y la compone lib.php). Una ruta que empieza por «/» o «http» ya es una URL del servidor
--      (las 4 casas sueltas, ficha.imagenes hasta que se suban al bucket) y se sirve tal cual. Misma regla para homeModels[].image
--      y masterplanImage. El navegador solo ve URLs estáticas de imagen, nunca esta RPC.
--   8. Configurador (solo líneas villa/land): landOptions = un escalón por superficie distinta de unidades DISPONIBLES, con su mínimo
--      de suelo (coalesce(precio_suelo, precio)) en EUR y €/m²; homeModels = modelos publicados y activos del proyecto con precio de
--      construcción del tramo vigente. Los precios del configurador SON de lista y públicos (contrato F0). NO SE EMITEN `extras`:
--      en la intranet el precio de un extra depende del modelo (Airbnb Kit 5.000 € en Dune/Dali y 6.000 € en Dream) y la SPA solo sabe
--      una lista por ficha; elegir uno sería inventar. Decide el owner (ver informe). masterplanProject tampoco sale: era el texto con
--      el que la SPA preguntaba a Supabase (F7 lo quita); el estado ya viene resuelto en `parcelas`.
--   9. Superficie mínima: STABLE, SECURITY DEFINER, search_path = '' (todo calificado), sin parámetros libres, `revoke all` de
--      public/anon/authenticated/service_role y grant explícito SOLO a anon. Llamador con nombre: el PHP coleccion/lib.php
--      (fuente 'intranet', clave publicable en servidor, caché 60 s); ningún navegador. NO se amplía catalogo_publico (contrato de
--      /modelo). El auxiliar _coleccion_a_eur no tiene llamador externo: sin permisos para nadie.
--
-- ROLLBACK: drop function public.coleccion_publica(); drop function public._coleccion_a_eur(numeric, text); (nada depende de ellas hasta
-- que lib.php active la fuente 'intranet'; antes de retirarla, devolver LW_COLECCION_FUENTE a datajson).

-- ── 1. Conversión a EUR (auxiliar interno) ──────────────────────────────────────────────────────────────────────────────────
create or replace function public._coleccion_a_eur(p_importe numeric, p_moneda text)
  returns numeric
  language sql stable security definer set search_path to ''
  as $cp$
  select case
    when p_importe is null or p_moneda is null then null
    when upper(p_moneda) = 'EUR' then p_importe
    else (
      select p_importe / t.tc
        from (select case when (c.valor #>> '{}') ~ '^[0-9]+([.][0-9]+)?$' then (c.valor #>> '{}')::numeric end as tc
                from public.config_instancia c
               where c.clave = 'tc_' || lower(p_moneda) || '_por_eur'
                 and c.actualizado_en >= now() - interval '60 days') t
       where t.tc > 0
         and (upper(p_moneda) <> 'IDR' or t.tc between 5000 and 100000))
  end
$cp$;
revoke all on function public._coleccion_a_eur(numeric, text) from public, anon, authenticated, service_role;
comment on function public._coleccion_a_eur(numeric, text) is
  'Auxiliar de coleccion_publica (The Collection v2, 2-oct-2026): importe → EUR con config_instancia.tc_<moneda>_por_eur (moneda por 1 EUR, ≤ 60 días, IDR entre 5.000 y 100.000). NULL si no hay tipo válido. Sin llamador externo: sin permisos.';

-- ── 2. La RPC pública ──────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.coleccion_publica()
  returns jsonb
  language sql stable security definer set search_path to ''
  as $cp$
with
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
         case when public.catalogo_tramo_activo() = '2026' then m.precio_construccion
              else coalesce(m.precio_construccion_2027, m.precio_construccion) end as precio_raw,
         public._coleccion_a_eur(case when public.catalogo_tramo_activo() = '2026' then m.precio_construccion
                                      else coalesce(m.precio_construccion_2027, m.precio_construccion) end, m.moneda) as eur,
         (select d.path from public.deck_fotos d where d.modelo_id = m.id order by d.orden, d.creado_en limit 1) as foto
    from fichas f
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
  select f.id as ficha_id, jsonb_agg(d.path order by d.orden, d.creado_en) as j
    from fichas f
    join public.deck_fotos d on d.ambito = 'proyecto' and d.proyecto_id = f.proyecto_id and d.uso in ('galeria', 'hero')
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
comment on function public.coleccion_publica() is
  'The Collection v2 (F5b, 2-oct-2026). Lectura pública de las fichas publicadas (publicada_web y proyecto vinculado) en la forma de data.json. SECURITY DEFINER, sin parámetros, campos escritos a mano. LLAMADOR CON NOMBRE: el PHP coleccion/lib.php (fuente intranet, clave publicable en servidor, caché 60 s); ningún navegador. Devuelve {properties, generated_at}; cada ficha: id, line, region, regionKey, featured, status, tenure, leaseYears, handover, visible, inCollection, homeFeatured, title, sub, desc, metaText, splitTitle, splitSub, highlights, tabs, techSpecs, beds, baths, built, land, pool, poolType, garage, garageDesc, furnished, style, view, priceEUR, priceMode (fixed|from|consultar), paymentPlan, unitsAvailable, unitsTotal, parcelas [{codigo, superficie_m2, estado: disponible|reservada|vendida}], images (rutas del bucket deck o URLs del servidor), videos, aerial, logo, isotype, landColor, splitImage, bleedImage, plan3dImage, mapImage, masterplanImage, masterplanPlots, downloads, landOptions [{size, pricePerM2, priceEUR}], homeModels [{name, beds, built, priceEUR, image}]. Sin extras ni masterplanProject (ver cabecera de la migración).';
