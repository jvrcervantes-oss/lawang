-- Alinea las policies de proyectos/tipos_vivienda con el patron ya
-- establecido (obra_fases: TO authenticated explicito). Sin esto, un
-- llamante anon dispara "permission denied for function es_agente" en vez
-- del [] limpio que da el resto de la suite cuando no hay sesion -- no es
-- un agujero (anon nunca ve datos, con o sin esto: es_agente() no tiene
-- EXECUTE de anon), es una inconsistencia que un verificador de produccion
-- señalo hoy mismo.
alter policy "agentes leen proyectos" on public.proyectos to authenticated;
alter policy "agentes dan de alta proyectos" on public.proyectos to authenticated;
alter policy "admin desactiva proyectos" on public.proyectos to authenticated;
alter policy "agentes leen tipos_vivienda" on public.tipos_vivienda to authenticated;
alter policy "agentes dan de alta tipos_vivienda" on public.tipos_vivienda to authenticated;
alter policy "admin desactiva tipos_vivienda" on public.tipos_vivienda to authenticated;
;
