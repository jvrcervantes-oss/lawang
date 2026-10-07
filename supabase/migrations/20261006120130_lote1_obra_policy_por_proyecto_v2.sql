-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 1 · G1 v2: igual que 20261006115808 pero la policy llama a un envoltorio DEFINER (patrón de obra_fotos / agente_ve_unidad_obra),
-- porque puede_proyecto_id solo la ejecutan postgres y service_role (medido 6-oct: la v1 daba 42501 a todo authenticated).
-- destructivo-ok: solo cambia policies de SELECT y añade una función; no toca filas.
create or replace function public.agente_ve_proyecto_obra(p_proyecto uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select public.es_agente() and public.puede('obra') and public.puede_proyecto_id(p_proyecto) $$;
revoke all on function public.agente_ve_proyecto_obra(uuid) from public, anon;
grant execute on function public.agente_ve_proyecto_obra(uuid) to authenticated, lw_lector, service_role;

drop policy if exists obra_partes_trabajo_select on public.obra_partes_trabajo;
create policy obra_partes_trabajo_select on public.obra_partes_trabajo
  for select to authenticated, lw_lector using ( public.agente_ve_proyecto_obra(proyecto_id) );

drop policy if exists obra_progreso_fase_zona_select on public.obra_progreso_fase_zona;
create policy obra_progreso_fase_zona_select on public.obra_progreso_fase_zona
  for select to authenticated, lw_lector using ( public.agente_ve_proyecto_obra(proyecto_id) );
