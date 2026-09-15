-- destructivo-ok: el DROP FUNCTION retira la funcion `investor_deck_config(text)`
-- creada en la migracion anterior de esta MISMA tanda (hace segundos, nunca
-- desplegada ni usada por nadie) para renombrarla. No toca la TABLA homonima
-- `investor_deck_config` (la de los parametros legales de reserva de Palm
-- Field, de 20260910025145) -- esa es justo el motivo del rename: una funcion
-- y una tabla con el mismo nombre en el mismo esquema es valido en Postgres
-- (catalogos distintos) pero es una trampa para el siguiente que lea el
-- codigo, y `get_advisors` la habria dejado ahi sin avisar (no es un lint que
-- exista). Se detecta y se corrige en la misma sesion, antes de que nadie la
-- use en produccion.
drop function if exists public.investor_deck_config(text);

create or replace function public.deck_config_publico(p_slug text)
returns table(
  proyecto              text,
  titulo                jsonb,
  meta_desc             jsonb,
  tipo_venta            text,
  modelo_destacado_slug text,
  masterplan_activo     boolean,
  masterplan_imagen     text,
  kpis                  jsonb
)
language sql
security definer
stable
set search_path = public
as $$
  select p.nombre, c.titulo, c.meta_desc, c.tipo_venta, m.slug,
         c.masterplan_activo, c.masterplan_imagen, c.kpis
    from public.proyectos p
    join public.deck_config_proyecto c on c.proyecto_id = p.id
    left join public.modelos m on m.id = c.modelo_destacado_id
   where p.slug = p_slug
     and public.deck_proyecto_abierto(p.nombre);
$$;

revoke all on function public.deck_config_publico(text) from public;
grant execute on function public.deck_config_publico(text) to anon, authenticated;

comment on function public.deck_config_publico is
  'Config publica del Investor Deck generico por slug de URL. Nombre elegido a proposito distinto de la tabla `investor_deck_config` (parametros legales de reserva, exclusiva de Palm Field) para no repetir nombre entre una tabla y una funcion sin relacion entre si. Cero filas = deck no disponible -- el front lo trata como "no disponible todavia", nunca como error.';
