/* INVESTOR DECK — los RPC publicos del contenido nuevo, y las dos funciones
   viejas pasando a usar la regla compartida `deck_proyecto_abierto()`.
   11-sep-2026. Porques completos en
   supabase/migrations/20260911180000_deck_contenido_intranet.sql

   ⚠️ `investor_deck_parcelas` NO se toca, y no es un olvido: esa funcion NO tiene
   la copia del predicado -- filtra `publicado_investor_deck` FILA A FILA sobre
   `unidades`, que es el opt-in de verdad. Es el ORIGEN de la regla, no una copia.
   Meterle `deck_proyecto_abierto()` cambiaria su alcance: pasaria a devolver TODAS
   las parcelas de un proyecto con una sola marcada. */

create or replace function public.investor_deck_fotos(p_proyecto text)
returns table(uso text, tipo text, path text, pie jsonb, orden integer, modelo_slug text)
language sql security definer stable set search_path = public as $$
  select f.uso, f.tipo, f.path, f.pie, f.orden, m.slug
    from public.deck_fotos f
    left join public.modelos m on m.id = f.modelo_id
   where public.deck_proyecto_abierto(p_proyecto)
     and (
       f.proyecto_id = (select p.id from public.proyectos p where p.nombre = p_proyecto)
       or f.modelo_id in (
         select mv.modelo_id from public.modelos_villa mv
          where mv.proyecto = p_proyecto and mv.modelo_id is not null
       )
     )
   order by f.uso, f.orden, f.creado_en;
$$;
revoke all on function public.investor_deck_fotos(text) from public;
grant execute on function public.investor_deck_fotos(text) to anon, authenticated;
comment on function public.investor_deck_fotos is
  'Fotos publicas del data room de un proyecto: las suyas mas las de los modelos que tiene asignados (un modelo es compartido entre proyectos, su foto no cuelga de ninguno). Solo proyectos abiertos. El `path` es del bucket publico `deck`.';

create or replace function public.investor_deck_faq(p_proyecto text)
returns table(pregunta jsonb, respuesta jsonb, orden integer)
language sql security definer stable set search_path = public as $$
  select q.pregunta, q.respuesta, q.orden
    from public.deck_faq q
   where public.deck_proyecto_abierto(p_proyecto)
     and q.publicado
     and q.proyecto_id = (select p.id from public.proyectos p where p.nombre = p_proyecto)
   order by q.orden, q.creado_en;
$$;
revoke all on function public.investor_deck_faq(text) from public;
grant execute on function public.investor_deck_faq(text) to anon, authenticated;
comment on function public.investor_deck_faq is
  'FAQ publica del investor deck. Lee de deck_faq, NUNCA de documentos_proyecto (alli categoria=faq son notas internas del equipo).';

create or replace function public.investor_deck_forecast(p_proyecto text)
returns table(
  modelo_slug text, modelo_nombre text, dormitorios integer,
  adr_medio numeric, adr_optimo numeric,
  ocupacion_media numeric, ocupacion_optima numeric,
  inversion_base numeric, precio_construccion numeric, moneda text,
  destacado boolean, orden integer,
  pct_gestion numeric, pct_mantenimiento numeric, pct_impuesto numeric,
  contrato_vigente text, actualizado_en timestamptz
)
language sql security definer stable set search_path = public as $$
  -- El precio de construccion NO se copia aqui: sale de la MISMA cascada que
  -- resuelve investor_deck_modelos (nivel 2 heredando del 1), para que la tarjeta
  -- del forecast y la de la tipologia no puedan decir cifras distintas.
  select m.slug, m.nombre, m.dormitorios,
         f.adr_medio, f.adr_optimo, f.ocupacion_media, f.ocupacion_optima,
         f.inversion_base,
         coalesce(mv.precio_construccion, m.precio_construccion),
         f.moneda, f.destacado, f.orden,
         c.pct_gestion, c.pct_mantenimiento, c.pct_impuesto, c.contrato_vigente,
         greatest(f.actualizado_en, c.actualizado_en)
    from public.deck_forecast f
    join public.modelos m   on m.id = f.modelo_id
    join public.proyectos p on p.id = f.proyecto_id
    join public.deck_forecast_proyecto c on c.proyecto_id = f.proyecto_id
    left join public.modelos_villa mv
           on mv.modelo_id = f.modelo_id and mv.proyecto = p.nombre
   where public.deck_proyecto_abierto(p_proyecto)
     and p.nombre = p_proyecto
     and f.publicado
     and c.publicado
   order by f.orden, m.nombre;
$$;
revoke all on function public.investor_deck_forecast(text) from public;
grant execute on function public.investor_deck_forecast(text) to anon, authenticated;
comment on function public.investor_deck_forecast is
  'Prevision de alquiler Ano 1 publicada de un proyecto. Devuelve los DATOS, no el resultado: el calculo (bruto, gastos, neto, ROI) lo hace el front con una sola formula. Sin los % del contrato publicados no devuelve nada, porque el neto sale de restarlos.';

create or replace function public.investor_deck_documentos(p_proyecto text)
returns table(titulo text, descripcion text, url text, categoria text)
language sql security definer stable set search_path = public as $$
  select d.titulo, d.descripcion, d.url, d.categoria
    from public.documentos_proyecto d
   where d.proyecto = p_proyecto
     and d.publicado_investor_deck
     and d.confidencial = false     -- cinturon y tirantes: publicado nunca gana a confidencial
     and d.categoria <> 'faq'       -- 'faq' son notas INTERNAS; la publica vive en deck_faq
     and d.url is not null
     and d.url <> ''
     and public.deck_proyecto_abierto(d.proyecto)
   order by d.creado_en desc;
$$;

create or replace function public.investor_deck_modelos(p_proyecto text)
returns table(
  slug text, nombre text, dormitorios integer, banos integer,
  villa_m2 numeric, terraza_m2 numeric, precio numeric, moneda text, orden integer
)
language sql security definer stable set search_path = public as $$
  with base as (
    select m.slug, m.nombre, m.dormitorios, m.banos, m.villa_m2, m.terraza_m2, m.orden,
           (mv.precio_construccion is not null) as gana_proyecto,
           mv.precio_construccion as precio_proyecto,
           mv.moneda              as moneda_proyecto,
           m.precio_construccion  as precio_catalogo,
           m.moneda               as moneda_catalogo
      from public.modelos_villa mv
      join public.modelos m on m.id = mv.modelo_id
     where mv.proyecto = p_proyecto
       and m.publicado and m.activo
       and public.deck_proyecto_abierto(mv.proyecto)
  )
  select slug, nombre, dormitorios, banos, villa_m2, terraza_m2,
         case when gana_proyecto then precio_proyecto else precio_catalogo end,
         case when gana_proyecto then coalesce(moneda_proyecto, moneda_catalogo)
              else moneda_catalogo end,
         orden
    from base
   order by orden nulls last, nombre;
$$;;
