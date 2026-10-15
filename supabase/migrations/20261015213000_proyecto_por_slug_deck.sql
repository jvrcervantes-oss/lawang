-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68); el maestro recibe estas gemelas en su propia subtarea (LAW-428 2-M)
-- EL DECK PÚBLICO PREGUNTA POR SLUG, NUNCA POR EL NOMBRE DEL PROYECTO — 15-oct-2026, LAW-428 fase 2, tanda A (sesión proyecto-por-id).
-- Encargo: encargos/20260929_lawang_proyecto_por_id.md. Revisión previa #152 (29-sep) y #381 (15-oct, Backend + Seguridad).
--
-- Máxima del owner «todo apunta por ID»: si cambia el nombre de un proyecto, nada se rompe. Hoy las RPC anon del deck reciben el
-- NOMBRE («Palm Field W5») y lo cruzan con el espejo de texto `unidades.proyecto` / `modelos_villa.proyecto` / `documentos_proyecto.proyecto`.
-- Aquí nacen sus gemelas con nombre NUEVO (`*_por_slug`; la misma firma de tipos con otro nombre de argumento no se puede
-- `create or replace`), que reciben el slug (id público, fijo con candado desde la fase 1) y cruzan por `proyecto_id`.
-- Las viejas NO se tocan: las sigue llamando el deck publicado hasta la fase 3 (front) y mueren en la fase 4 (0 llamadas en los logs →
-- revoke → borrado, con la válvula del owner).
--
-- QUÉ CREA
--   · deck_proyecto_abierto_por_id(uuid): el deck de un proyecto está abierto si tiene alguna unidad publicada. Auxiliar: sin grant a nadie
--     (sus llamadoras son DEFINER de postgres).
--   · _proyecto_deck_abierto_de_slug(text): el id del proyecto de ese slug SI su deck está abierto; null si no existe o está cerrado
--     (Seguridad #152: un slug es un identificador, no una credencial: toda gemela anon exige deck abierto). Auxiliar sin grant.
--   · 8 gemelas anon: investor_deck_{documentos,faq,forecast,fotos,modelos,parcelas}_por_slug, deck_ubicacion_publica_por_slug y
--     parcelas_tamanos_disponibles_por_slug. Mismos RETURNS que su vieja; cuerpo = el de la vieja con la resolución por id. Grant solo anon:
--     sus llamadores (investor-deck/index.php, palmfield, partners/*, palmfield/vivo.php) mandan la clave publicable sin token, así que un
--     usuario con sesión también llega como anon (medido por Seguridad, #381); ninguna edge ni la intranet las llama (grep 15-oct).
--     Slug inexistente y deck cerrado dan lo mismo (0 filas / null): no se distingue si el proyecto existe.
-- QUÉ RECABLEA (las que se QUEDAN, en esta misma migración): deck_bucket_debido, deck_config_publico, deck_fotos_desajustes e
--   investor_deck_documento_visible pasan de deck_proyecto_abierto(nombre) a deck_proyecto_abierto_por_id(id). Equivalente hoy, medido el
--   15-oct: 8 decks abiertos por nombre y 8 por id, los mismos; 0 espejos desalineados en unidades, modelos_villa y documentos_proyecto;
--   los 4 documentos sin proyecto_id son «Lawang (general)» (no es un proyecto) y dan false por las dos vías. deck_config_publico pasa además
--   a search_path '' (ya cualificaba todo). `create or replace` conserva owner y proacl (anon en deck_config_publico, como hoy).
-- QUÉ CIERRA: investor_deck_reservar no tiene llamador (palmfield/v2 solo lo nombra en un comentario; 0 llamadas en el repo; anon no la
--   ejecuta desde siempre): se revoca a service_role, que era el último que podía (Seguridad #152 y #381). Se borra en la fase 4.
-- QUÉ NO HACE: unidades_estado_publico_por_slug NO nace (su único llamador, portfolio-app.js, solo corre sin DATA_LIVE y con masterplanProject,
--   vacío en el repo; y un slug se adivina más que un nombre: LAW-430 se revisa con los logs delante). No toca el front ni las viejas.
--   El deck sigue sin límite de uso (como hoy): fila en contexto/seguridad_2026.md §7.
-- VUELTA ATRÁS: supabase/reversion_proyecto_por_slug/REVERSION.sql (cuerpos vivos del 15-oct con su md5, grant a service_role y drop de
--   lo nuevo). Antes, el front a su versión anterior si ya llamaba a las gemelas.

set local lock_timeout = '5s';

-- ── auxiliares (sin grant) ─────────────────────────────────────────────────────────────────────────────────────────────────────────
create function public.deck_proyecto_abierto_por_id(p_proyecto_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.unidades u
     where u.proyecto_id = p_proyecto_id and u.publicado_investor_deck
  );
$$;
revoke all on function public.deck_proyecto_abierto_por_id(uuid) from public, anon, authenticated, service_role;
comment on function public.deck_proyecto_abierto_por_id(uuid) is
  'Deck del proyecto abierto = alguna unidad publicada (por proyecto_id). Gemela por id de deck_proyecto_abierto(text); sin grant: la llaman DEFINER de postgres. LAW-428, 20261015213000.';

create function public._proyecto_deck_abierto_de_slug(p_slug text)
returns uuid language sql stable security definer set search_path = '' as $$
  select p.id from public.proyectos p
   where p.slug = p_slug
     and public.deck_proyecto_abierto_por_id(p.id);
$$;
revoke all on function public._proyecto_deck_abierto_de_slug(text) from public, anon, authenticated, service_role;
comment on function public._proyecto_deck_abierto_de_slug(text) is
  'Id del proyecto de ese slug si su deck está abierto; null si no existe o está cerrado (no se distingue). Sin grant. LAW-428, 20261015213000.';

-- ── recableo de las que se quedan ──────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.deck_bucket_debido(p_ambito text, p_ref uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case
           when p_ambito = 'modelo' then 'deck'
           when p_ambito = 'proyecto' then
             case coalesce((select t.abrir from public.deck_transiciones t
                             where t.proyecto_id = p_ref and t.desde > now() - interval '15 minutes'),
                           public.deck_proyecto_abierto_por_id(p_ref))
               when true then 'deck' else 'deck-privado' end
         end;
$$;

create or replace function public.deck_config_publico(p_slug text)
returns table(proyecto text, titulo jsonb, meta_desc jsonb, tipo_venta text, modelo_destacado_slug text, masterplan_activo boolean,
              masterplan_imagen text, kpis jsonb)
language sql stable security definer set search_path = '' as $$
  select p.nombre, c.titulo, c.meta_desc, c.tipo_venta, m.slug,
         c.masterplan_activo, c.masterplan_imagen, c.kpis
    from public.proyectos p
    join public.deck_config_proyecto c on c.proyecto_id = p.id
    left join public.modelos m on m.id = c.modelo_destacado_id
   where p.slug = p_slug
     and public.deck_proyecto_abierto_por_id(p.id);
$$;

create or replace function public.deck_fotos_desajustes(p_proyecto_id uuid default null)
returns table(name text, bucket_real text, bucket_debido text, proyecto_id uuid, motivo text)
language sql stable security definer set search_path = '' as $$
  with objs as (
    select o.name, o.bucket_id, o.created_at
      from storage.objects o
     where o.bucket_id in ('deck', 'deck-privado')
       and (o.name like 'proyecto/%' or o.name like 'modelo/%')
  ), nombres as (
    select n.name, array_agg(n.bucket_id order by n.bucket_id) as buckets, min(n.created_at) as creado
      from objs n group by n.name
  ), est as (
    select n.name, n.buckets, n.creado, f.ambito, f.proyecto_id, t.abrir as t_abrir, t.desde as t_desde
      from nombres n
      left join public.deck_fotos f on f.path = n.name
      left join public.deck_transiciones t on t.proyecto_id = f.proyecto_id and t.desde > now() - interval '15 minutes'
  ), deb as (
    select e.*,
           case
             when e.ambito is null then case when e.creado > now() - interval '1 hour' then null else 'deck-privado' end
             when e.ambito = 'modelo' then 'deck'
             when e.t_abrir is not null then case when e.t_abrir then 'deck' else 'deck-privado' end
             when public.deck_proyecto_abierto_por_id(e.proyecto_id) then 'deck'
             else 'deck-privado'
           end as debido
      from est e
  )
  select d.name,
         case when cardinality(d.buckets) > 1 then 'ambos' else d.buckets[1] end,
         d.debido,
         d.proyecto_id,
         case when cardinality(d.buckets) > 1 then 'en_ambos' when d.ambito is null then 'huerfano' else 'bucket' end
    from deb d
   where d.debido is not null
     and (cardinality(d.buckets) > 1 or d.buckets[1] <> d.debido)
     and (case when p_proyecto_id is null then d.t_desde is null else d.proyecto_id = p_proyecto_id end)
   order by d.name;
$$;

create or replace function public.investor_deck_documento_visible(d public.documentos_proyecto)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(d.publicado_investor_deck, false)
     and d.confidencial = false             -- cinturon y tirantes: publicado nunca gana a confidencial
     and d.categoria <> 'faq'               -- 'faq' son notas INTERNAS; la publica vive en deck_faq
     and public.deck_proyecto_abierto_por_id(d.proyecto_id)
     and (
       coalesce(d.url, '') <> ''            -- enlace (Drive): igual que antes
       or (
         d.path ~ '^proyectos/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|jpe?g|png|webp|docx|xlsx|pptx)$'
         and d.mime = public.investor_deck_documento_mime(d.path)
         and coalesce(d.bytes, 0) between 1 and 52428800
         and exists (select 1 from storage.objects o
                      where o.bucket_id = 'documentacion' and o.name = d.path
                        and o.metadata->>'mimetype' = public.investor_deck_documento_mime(d.path))
       )
     )
$$;

-- ── las 8 gemelas anon ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
create function public.investor_deck_documentos_por_slug(p_slug text)
returns table(titulo text, titulo_i18n jsonb, descripcion text, url text, url_i18n jsonb, categoria text)
language sql stable security definer set search_path = '' as $$
  select d.titulo, d.titulo_i18n, d.descripcion,
         case when coalesce(d.url, '') <> '' then d.url
              else 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/deck-documento?id=' || d.id::text end,
         case when coalesce(d.url, '') <> '' then d.url_i18n else '{}'::jsonb end,
         d.categoria
    from public.documentos_proyecto d
   where d.proyecto_id = public._proyecto_deck_abierto_de_slug(p_slug)
     and public.investor_deck_documento_visible(d)
   order by d.creado_en desc;
$$;

create function public.investor_deck_faq_por_slug(p_slug text)
returns table(pregunta jsonb, respuesta jsonb, orden integer)
language sql stable security definer set search_path = '' as $$
  select q.pregunta, q.respuesta, q.orden
    from public.deck_faq q
   where q.proyecto_id = public._proyecto_deck_abierto_de_slug(p_slug)
     and q.publicado
   order by q.orden, q.creado_en;
$$;

create function public.investor_deck_forecast_por_slug(p_slug text)
returns table(modelo_slug text, modelo_nombre text, dormitorios integer, adr_medio numeric, adr_optimo numeric, ocupacion_media numeric,
              ocupacion_optima numeric, inversion_base numeric, precio_construccion numeric, moneda text, destacado boolean, orden integer,
              pct_gestion numeric, pct_mantenimiento numeric, pct_impuesto numeric, contrato_vigente text, actualizado_en timestamp with time zone)
language sql stable security definer set search_path = '' as $$
  -- El precio de construccion NO se copia aqui: sale de la MISMA cascada que resuelve investor_deck_modelos_por_slug (nivel 2
  -- heredando del 1), para que la tarjeta del forecast y la de la tipologia no puedan decir cifras distintas.
  select m.slug, m.nombre, m.dormitorios,
         f.adr_medio, f.adr_optimo, f.ocupacion_media, f.ocupacion_optima,
         f.inversion_base,
         coalesce(mv.precio_construccion, m.precio_construccion),
         f.moneda, f.destacado, f.orden,
         c.pct_gestion, c.pct_mantenimiento, c.pct_impuesto, c.contrato_vigente,
         greatest(f.actualizado_en, c.actualizado_en)
    from public.deck_forecast f
    join public.modelos m   on m.id = f.modelo_id
    join public.deck_forecast_proyecto c on c.proyecto_id = f.proyecto_id
    left join public.modelos_villa mv
           on mv.modelo_id = f.modelo_id and mv.proyecto_id = f.proyecto_id
   where f.proyecto_id = public._proyecto_deck_abierto_de_slug(p_slug)
     and f.publicado
     and c.publicado
   order by f.orden, m.nombre;
$$;

create function public.investor_deck_fotos_por_slug(p_slug text)
returns table(uso text, tipo text, path text, pie jsonb, orden integer, modelo_slug text)
language sql stable security definer set search_path = '' as $$
  with v as (select public._proyecto_deck_abierto_de_slug(p_slug) as id)
  select f.uso, f.tipo, f.path, f.pie, f.orden, m.slug
    from v
    join public.deck_fotos f
      on f.proyecto_id = v.id
      or f.modelo_id in (select mv.modelo_id from public.modelos_villa mv
                          where mv.proyecto_id = v.id and mv.modelo_id is not null)
    left join public.modelos m on m.id = f.modelo_id
   order by f.uso, f.orden, f.creado_en;
$$;

create function public.investor_deck_modelos_por_slug(p_slug text)
returns table(slug text, nombre text, dormitorios integer, banos integer, villa_m2 numeric, terraza_m2 numeric, precio numeric, moneda text,
              orden integer)
language sql stable security definer set search_path = '' as $$
  with base as (
    select m.slug, m.nombre, m.dormitorios, m.banos, m.villa_m2, m.terraza_m2, m.orden,
           (mv.precio_construccion is not null) as gana_proyecto,
           mv.precio_construccion as precio_proyecto,
           mv.moneda              as moneda_proyecto,
           m.precio_construccion  as precio_catalogo,
           m.moneda               as moneda_catalogo
      from public.modelos_villa mv
      join public.modelos m on m.id = mv.modelo_id
     where mv.proyecto_id = public._proyecto_deck_abierto_de_slug(p_slug)
       and m.publicado and m.activo
  )
  select b.slug, b.nombre, b.dormitorios, b.banos, b.villa_m2, b.terraza_m2,
         case when b.gana_proyecto then b.precio_proyecto else b.precio_catalogo end,
         case when b.gana_proyecto then coalesce(b.moneda_proyecto, b.moneda_catalogo)
              else b.moneda_catalogo end,
         b.orden
    from base b
   order by b.orden nulls last, b.nombre;
$$;

create function public.investor_deck_parcelas_por_slug(p_slug text)
returns table(codigo text, estado text, superficie_m2 numeric, precio numeric, precio_suelo numeric, precio_construccion numeric,
              cuota_reserva numeric, moneda text)
language sql stable security definer set search_path = '' as $$
  select u.codigo, u.estado, u.superficie_m2,
         coalesce(u.precio, u.precio_suelo) as precio,
         u.precio_suelo,
         u.precio_construccion,
         u.cuota_reserva_investor_deck as cuota_reserva,
         u.moneda
    from public.unidades u
   where u.proyecto_id = public._proyecto_deck_abierto_de_slug(p_slug)
     and u.publicado_investor_deck = true
   order by u.codigo;
$$;

create function public.parcelas_tamanos_disponibles_por_slug(p_slug text)
returns table(superficie_m2 numeric)
language sql stable security definer set search_path = '' as $$
  select distinct u.superficie_m2
    from public.unidades u
   where u.proyecto_id = public._proyecto_deck_abierto_de_slug(p_slug)
     and u.estado = 'disponible'
     and u.publicado_investor_deck = true
   order by u.superficie_m2;
$$;

create function public.deck_ubicacion_publica_por_slug(p_slug text)
returns text language sql stable security definer set search_path = '' as $$
  select case
           when btrim(p.ubicacion_maps) ~ '^-?\d{1,2}(\.\d+)?\s*[,;]\s*-?\d{1,3}(\.\d+)?$' then btrim(p.ubicacion_maps)
           when btrim(p.ubicacion_maps) ~* '^https://([a-z0-9-]+\.)*(google\.[a-z.]+|goo\.gl)/[^\s<>"'']*$' then btrim(p.ubicacion_maps)
         end
    from public.proyectos p
   where p.id = public._proyecto_deck_abierto_de_slug(p_slug);
$$;

do $g$
declare f text;
begin
  foreach f in array array[
      'public.investor_deck_documentos_por_slug(text)', 'public.investor_deck_faq_por_slug(text)',
      'public.investor_deck_forecast_por_slug(text)', 'public.investor_deck_fotos_por_slug(text)',
      'public.investor_deck_modelos_por_slug(text)', 'public.investor_deck_parcelas_por_slug(text)',
      'public.parcelas_tamanos_disponibles_por_slug(text)', 'public.deck_ubicacion_publica_por_slug(text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
    execute format('grant execute on function %s to anon', f);
    execute format('comment on function %s is %L', f,
      'Deck público por SLUG (gemela de la vieja por nombre, LAW-428 fase 2, 20261015213000). Exige deck abierto; slug inexistente = cerrado. Solo anon.');
  end loop;
end $g$;

-- ── cierre de la que no tiene llamador ─────────────────────────────────────────────────────────────────────────────────────────────
revoke execute on function public.investor_deck_reservar(text, text, text, text, text, text, text, text) from service_role;
