-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 1 (OK del owner 6-oct-2026) · G1: partes de obra y progreso por fase/zona solo de los proyectos que el agente ve.
-- Se conserva puede('obra'); el proyecto solo estrecha. Hermana de referencia: obra_fotos.
-- OJO: ESTA VERSIÓN SE APLICÓ Y SE REVERTIÓ EN SEGUIDA (puede_proyecto_id no la ejecutan authenticated/lw_lector: la policy daba 42501
-- al leer). La definitiva es 20261006120130_lote1_obra_policy_por_proyecto_v2.sql (usa un envoltorio DEFINER, como obra_fotos).
-- destructivo-ok: solo cambia policies de SELECT; no toca filas.
drop policy if exists obra_partes_trabajo_select on public.obra_partes_trabajo;
create policy obra_partes_trabajo_select on public.obra_partes_trabajo
  for select to authenticated, lw_lector
  using ( public.es_agente() and public.puede('obra') and public.puede_proyecto_id(proyecto_id) );

drop policy if exists obra_progreso_fase_zona_select on public.obra_progreso_fase_zona;
create policy obra_progreso_fase_zona_select on public.obra_progreso_fase_zona
  for select to authenticated, lw_lector
  using ( public.es_agente() and public.puede('obra') and public.puede_proyecto_id(proyecto_id) );
