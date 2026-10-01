-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68); pareja IDÉNTICA de erp/migraciones/20260929235900
-- destructivo-ok: LAW-432, OK del owner 29-sep («borralo»); solo un trigger y su función, sin datos (cuerpo en la migración 20260819145810 y anteriores)
-- Desde 20260929013239 el único dueño de la propagación del nombre es trg_proyecto_renombrado.
drop trigger if exists proyectos_propaga_nombre on public.proyectos;
drop function if exists public.propaga_nombre_proyecto();
