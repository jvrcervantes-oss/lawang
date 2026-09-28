-- AXW-58 (28-sep-2026, Seguridad): endurecimiento sin cambio de comportamiento.
-- deck_ubicacion_publica(text) es SECURITY DEFINER y la ejecuta anon (investor decks
-- públicos: investor-deck/index.php y investor-deck/palmfield/index.html), pero nació con
-- search_path = 'public'. El estándar del estudio para toda DEFINER abierta a anon es
-- search_path = '' (contexto/seguridad_2026.md): así ningún objeto con el mismo nombre
-- en un esquema del path puede suplantar lo que la función llama.
-- El cuerpo ya califica todo con public. (proyectos, deck_proyecto_abierto) y lo demás
-- (btrim, ~, ~*) vive en pg_catalog, que se busca siempre: devuelve exactamente lo mismo.
alter function public.deck_ubicacion_publica(text) set search_path = '';

do $$
begin
  if not has_function_privilege('anon', 'public.deck_ubicacion_publica(text)', 'EXECUTE') then
    raise exception 'AXW-58: el deck público perdería la ubicación';
  end if;
end $$;
