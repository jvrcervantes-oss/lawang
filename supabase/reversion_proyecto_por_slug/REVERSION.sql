-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- REVERSION de 20261015213000_proyecto_por_slug_deck.sql (15-oct-2026, sesion proyecto-por-id, LAW-428 fase 2 tanda A).
-- ORDEN: 1) el front del deck a su version anterior si ya llama a las *_por_slug (fase 3), 2) ESTE fichero, en una transaccion.
-- Devuelve LITERALES las 4 recableadas a su cuerpo vivo del 15-oct (md5(prosrc) anotado en cada una; pg_get_functiondef del volcado
-- de ese dia), devuelve a service_role el EXECUTE de investor_deck_reservar y borra las 10 funciones nuevas (nadie mas las llama).
-- destructivo-ok: solo borra funciones que creo la migracion; no hay datos
set local lock_timeout = '5s';

-- deck_bucket_debido: md5(prosrc) vivo 15-oct = 552772d19094a3b561ba7b100993a8df
CREATE OR REPLACE FUNCTION public.deck_bucket_debido(p_ambito text, p_ref uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case
           when p_ambito = 'modelo' then 'deck'
           when p_ambito = 'proyecto' then
             case coalesce((select t.abrir from public.deck_transiciones t
                             where t.proyecto_id = p_ref and t.desde > now() - interval '15 minutes'),
                           public.deck_proyecto_abierto((select p.nombre from public.proyectos p where p.id = p_ref)))
               when true then 'deck' else 'deck-privado' end
         end;
$function$;

-- deck_config_publico: md5(prosrc) vivo 15-oct = b150b9788fe01a4aafe4fd17f7bb9d47
CREATE OR REPLACE FUNCTION public.deck_config_publico(p_slug text)
 RETURNS TABLE(proyecto text, titulo jsonb, meta_desc jsonb, tipo_venta text, modelo_destacado_slug text, masterplan_activo boolean, masterplan_imagen text, kpis jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.nombre, c.titulo, c.meta_desc, c.tipo_venta, m.slug,
         c.masterplan_activo, c.masterplan_imagen, c.kpis
    from public.proyectos p
    join public.deck_config_proyecto c on c.proyecto_id = p.id
    left join public.modelos m on m.id = c.modelo_destacado_id
   where p.slug = p_slug
     and public.deck_proyecto_abierto(p.nombre);
$function$;

-- deck_fotos_desajustes: md5(prosrc) vivo 15-oct = 1f5e81946df42465fec8d8e045a9e4f8
CREATE OR REPLACE FUNCTION public.deck_fotos_desajustes(p_proyecto_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(name text, bucket_real text, bucket_debido text, proyecto_id uuid, motivo text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with objs as (
    select o.name, o.bucket_id, o.created_at
      from storage.objects o
     where o.bucket_id in ('deck', 'deck-privado')
       and (o.name like 'proyecto/%' or o.name like 'modelo/%')
  ), nombres as (
    select n.name, array_agg(n.bucket_id order by n.bucket_id) as buckets, min(n.created_at) as creado
      from objs n group by n.name
  ), est as (
    select n.name, n.buckets, n.creado, f.ambito, f.proyecto_id, p.nombre, t.abrir as t_abrir, t.desde as t_desde
      from nombres n
      left join public.deck_fotos f on f.path = n.name
      left join public.proyectos p on p.id = f.proyecto_id
      left join public.deck_transiciones t on t.proyecto_id = f.proyecto_id and t.desde > now() - interval '15 minutes'
  ), deb as (
    select e.*,
           case
             when e.ambito is null then case when e.creado > now() - interval '1 hour' then null else 'deck-privado' end
             when e.ambito = 'modelo' then 'deck'
             when e.t_abrir is not null then case when e.t_abrir then 'deck' else 'deck-privado' end
             when public.deck_proyecto_abierto(e.nombre) then 'deck'
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
$function$;

-- investor_deck_documento_visible: md5(prosrc) vivo 15-oct = 8bdaa2c7673cfc83d4786386b005bf23
CREATE OR REPLACE FUNCTION public.investor_deck_documento_visible(d public.documentos_proyecto)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(d.publicado_investor_deck, false)
     and d.confidencial = false             -- cinturon y tirantes: publicado nunca gana a confidencial
     and d.categoria <> 'faq'               -- 'faq' son notas INTERNAS; la publica vive en deck_faq
     and public.deck_proyecto_abierto(d.proyecto)
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
$function$;

grant execute on function public.investor_deck_reservar(text, text, text, text, text, text, text, text) to service_role;
drop function public.investor_deck_documentos_por_slug(text);
drop function public.investor_deck_faq_por_slug(text);
drop function public.investor_deck_forecast_por_slug(text);
drop function public.investor_deck_fotos_por_slug(text);
drop function public.investor_deck_modelos_por_slug(text);
drop function public.investor_deck_parcelas_por_slug(text);
drop function public.parcelas_tamanos_disponibles_por_slug(text);
drop function public.deck_ubicacion_publica_por_slug(text);
drop function public._proyecto_deck_abierto_de_slug(text);
drop function public.deck_proyecto_abierto_por_id(uuid);
