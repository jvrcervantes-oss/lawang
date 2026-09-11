-- La carpeta de un proyecto que no es tuyo deja de aparecer — 11-sep-2026
--
-- QUÉ PASABA. La policy de lectura de `proyectos` era `es_agente()` a secas: los 29
-- proyectos, para todo el equipo. `unidades` en cambio ya filtraba bien
-- (`unidad_visible(proyecto_id)`), así que en la herramienta Proyectos salían las 29
-- carpetas con los contadores a cero — y los 29 nombres en cada desplegable. Lo
-- reportó el owner justo después de cerrar lo de contratos: «deberían ver sólo las
-- carpetas de los proyectos asignados y en el desplegable igual, ¿no?».
--
-- Una carpeta vacía no es inofensiva: enseña el MAPA del negocio (cuántos proyectos
-- hay, cómo se llaman, en qué resort) a quien solo trabaja en uno.
--
-- DÓNDE SE ARREGLA. En la RLS, no en las pantallas. Los nombres de proyecto los leen
-- con `.from('proyectos')` sin filtro propio la herramienta Proyectos (las carpetas y
-- sus dos desplegables), Modelos, Usuarios, Unidades y las tres pantallas de /v4/:
-- ocho sitios que habría que acordarse de tocar, y el noveno que se escriba mañana.
-- Con la policy puesta se filtran los ocho a la vez y el noveno nace filtrado.
--
-- `proyecto_visible()` es el cuerpo que ya tenía `unidad_visible()`, con el nombre de
-- lo que de verdad decide; `unidad_visible()` pasa a delegar en ella. Así la regla
-- —admin todo · manager lo que supervisa · agente lo que tiene asignado— vive en UN
-- sitio y no en dos que divergen.
--
-- EL ACL NO ES UN DETALLE. Una policy ejecuta la función con los privilegios de quien
-- consulta: si `authenticated` no tuviera EXECUTE, cada SELECT a `proyectos` no
-- devolvería vacío, reventaría con 42501 — y a `proyectos` la lee media intranet. Se
-- clona el ACL exacto de `unidad_visible`, que lleva un mes en pie.
--
-- CONSECUENCIA CONOCIDA, no efecto colateral: quien tenga documentos de un proyecto
-- que no tiene asignado deja de ver ese proyecto por id (el nombre sigue saliendo:
-- `contratos.proyecto_nombre` es texto espejo). Hoy le pasa sobre todo a Yesy, con la
-- ficha de proyectos vacía — LAW-176. Se arregla asignándole sus proyectos, NO
-- añadiendo aquí un «o tengo un contrato ahí»: eso reabriría el filtro por detrás.
--
-- VERIFICADO por impersonación de las 24 fichas activas: admin/super_admin 29
-- proyectos y 462 unidades (sin cambio); Ariadna 6/394; Santiago 3/124; Jairo 2/249;
-- Victor 2/53; Andrea 1/29; Ismael, Jose, Juanjo y David S. 1/228; Miguel y
-- Christian 1/34; Yesy 0/0 (ficha vacía, LAW-176). Ninguna consulta dio 42501.

create or replace function public.proyecto_visible(p_proyecto_id uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select case
    when public.es_admin() then true
    when public.es_manager_de(p_proyecto_id) then true
    when p_proyecto_id is null then false
    else exists (
      select 1 from public.usuarios u
       where u.user_id = (select auth.uid()) and u.activo
         and p_proyecto_id = any (u.proyectos))
  end
$function$;

revoke execute on function public.proyecto_visible(uuid) from public, anon;
grant  execute on function public.proyecto_visible(uuid) to authenticated, service_role;

-- Delega: mismo criterio, una sola copia. El nombre viejo se conserva porque lo usa
-- la policy de `unidades` y ahí se lee mejor («¿veo esta unidad?»).
create or replace function public.unidad_visible(p_proyecto_id uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select public.proyecto_visible(p_proyecto_id)
$function$;

alter policy "agentes leen proyectos" on public.proyectos
  using (public.es_agente() and public.proyecto_visible(id));

-- Y la hermana del mismo barrido: `unidades` se LEÍA filtrada por proyecto pero se
-- ESCRIBÍA sin filtrar — bastaba tener la herramienta. Un agente de un proyecto podía
-- crear o modificar unidades de cualquier otro, por id, sin verlas siquiera. El
-- `with check` impide además mover una unidad a un proyecto que no ve.
-- No afecta a los flujos de servidor (obra_actualizar, sincroniza_unidad_contrato,
-- avanza_unidad_por_cobro, borrar_unidad): son SECURITY DEFINER y no pasan por aquí.
alter policy "agentes con la herramienta crean unidades" on public.unidades
  with check (public.es_agente() and public.puede('unidades') and public.unidad_visible(proyecto_id));

alter policy "agentes con la herramienta actualizan unidades" on public.unidades
  using      (public.es_agente() and public.puede('unidades') and public.unidad_visible(proyecto_id))
  with check (public.es_agente() and public.puede('unidades') and public.unidad_visible(proyecto_id));
