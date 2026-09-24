-- Ubicación del proyecto en los investor decks (24-sep-2026, owner: «muéstrala en los
-- investor-decks»). Los decks son públicos (clave publicable, anon), así que leen por
-- una función SECURITY DEFINER con la MISMA puerta que el resto del deck
-- (deck_proyecto_abierto): proyecto sin deck abierto = null, nunca la ubicación.
--
-- Función aparte y no una columna más en deck_config_publico: cambiar el RETURNS TABLE
-- de esa obliga a DROP + CREATE de la función de la que cuelga todo deck público.
--
-- Solo devuelve lo que tiene forma de ubicación («lat, lng» o un enlace de Google
-- Maps): el campo es texto libre y lo que no sea eso no sale a una página pública.
create or replace function public.deck_ubicacion_publica(p_proyecto text)
returns text
language sql
stable
security definer
set search_path to 'public'
as $$
  select case
           when btrim(p.ubicacion_maps) ~ '^-?\d{1,2}(\.\d+)?\s*[,;]\s*-?\d{1,3}(\.\d+)?$' then btrim(p.ubicacion_maps)
           when btrim(p.ubicacion_maps) ~* '^https://([a-z0-9-]+\.)*(google\.[a-z.]+|goo\.gl)/[^\s<>"'']*$' then btrim(p.ubicacion_maps)
         end
    from public.proyectos p
   where p.nombre = p_proyecto
     and public.deck_proyecto_abierto(p.nombre);
$$;

revoke all on function public.deck_ubicacion_publica(text) from public;
grant execute on function public.deck_ubicacion_publica(text) to anon, authenticated;
