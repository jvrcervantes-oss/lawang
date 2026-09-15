-- Investor Deck multi-proyecto (15-sep-2026) -- pieza 4/4 (primer intento,
-- ver la migracion siguiente: se renombra a los pocos minutos, misma sesion,
-- antes de desplegarse — se deja el historial completo en vez de reescribirlo).
-- Lectura publica de la config por slug. Primera llamada que hace la plantilla
-- generica (investor-deck/index.php?slug=...): resuelve el slug a un proyecto,
-- exige que este ABIERTO (deck_proyecto_abierto, la misma fuente unica que ya
-- usan las otras 6 funciones investor_deck_*) y devuelve solo lo publicable.
create or replace function public.investor_deck_config(p_slug text)
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

revoke all on function public.investor_deck_config(text) from public;
grant execute on function public.investor_deck_config(text) to anon, authenticated;

comment on function public.investor_deck_config is
  'Config publica del Investor Deck generico por slug de URL. Cero filas = deck no disponible (proyecto sin slug, sin config, o cerrado por deck_proyecto_abierto) -- el front lo trata como "no disponible todavia", nunca como error. Nunca expone columnas internas de deck_config_proyecto (actualizado_por, proyecto_id).';
