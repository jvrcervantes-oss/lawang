create or replace function public.investor_deck_modelos(p_proyecto text)
returns table(
  slug        text,
  nombre      text,
  dormitorios integer,
  banos       integer,
  villa_m2    numeric,
  terraza_m2  numeric,
  precio      numeric,
  moneda      text,
  orden       integer
)
language sql
security definer
stable
set search_path = public
as $$
  -- `gana` elige de que fila sale el precio, y la moneda viaja CON el, nunca aparte.
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
       and m.publicado
       and m.activo
       -- opt-in de publicacion: solo proyectos que el owner ha abierto al data room.
       and exists (
             select 1 from public.unidades u
              where u.proyecto = mv.proyecto
                and u.publicado_investor_deck
           )
  )
  select slug, nombre, dormitorios, banos, villa_m2, terraza_m2,
         case when gana_proyecto then precio_proyecto else precio_catalogo end as precio,
         case when gana_proyecto then coalesce(moneda_proyecto, moneda_catalogo)
              else moneda_catalogo end                                        as moneda,
         orden
    from base
   order by orden nulls last, nombre;
$$;

revoke all on function public.investor_deck_modelos(text) from public;
grant execute on function public.investor_deck_modelos(text) to anon, authenticated;

comment on function public.investor_deck_modelos is
  'Lectura publica y acotada del catalogo de modelos ASIGNADOS a un proyecto, para el data room de inversores. Solo proyectos con unidades publicado_investor_deck=true (hoy: Palm Field W5). Precio = nivel 2 de la cascada (modelos_villa) heredando del nivel 1 (modelos) cuando es NULL, y la moneda sale SIEMPRE de la misma fila que el precio. Nunca notas ni renders_pendientes.';;
