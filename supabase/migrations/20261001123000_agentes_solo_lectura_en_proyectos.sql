-- Agentes en SOLO LECTURA sobre proyectos, parcelas, documentos y obra (1-oct-2026, petición del owner: «cualquier agente puede editar
-- proyectos; solo deberían tener lectura; los admins pueden editar; revisa el resto de herramientas»). Decisiones del owner, 1-oct:
--  · Parcelas: admin/super admin en todo; un project_manager SOLO en los proyectos que supervisa (es_manager_de). agente y sales_manager, lectura.
--  · Documentos de modelos y de proyecto: lectura para agente y sales_manager. Editan admin (todo) y el encargado (solo los de su proyecto).
--    Los documentos de modelos, solo admin (el catálogo ya era de admin: modelo_guarda, precios, techos…).
--  · Obra (avance de fase y fotos): admin y el encargado del proyecto; el agente solo lee.
-- El hueco: unidad_guarda y unidades_importa pedían `es_agente() and puede('unidades')`, y es_agente() es «cualquier usuario activo»; los 18
-- agentes con la casilla Unidades daban de alta, editaban e importaban parcelas (la rama de alta ni miraba el proyecto). modelo_documentos_guarda,
-- _modelo_documento_aplica y modelo_documento_registra pedían SOLO es_agente(): ni la casilla Modelos. documento_proyecto_*: agente + casilla
-- Documentación. obra_*: agente + casilla Obra (1 persona hoy). Probado antes del cambio en contracts/sql/prueba_agentes_solo_lectura_proyectos.sql.
-- La casilla de cada herramienta SIGUE siendo necesaria: quitársela a un encargado concreto corta su escritura sin tocar código.
-- Las lecturas no cambian: obra_puede y documento_proyecto_puede solo las llaman caminos de escritura (la lectura va por RLS y
-- agente_ve_unidad_obra / documento_proyecto_visible).
-- Los PARCHES se hacen con replace sobre la definición viva, exigiendo UNA coincidencia de cada marca (la base no es el .sql del repo) y
-- conservando SECURITY DEFINER y search_path. Idempotente: con las marcas viejas ausentes sale sin tocar; con alguna sí y alguna no, ABORTA.
-- ROLLBACK: volver a poner en cada función la marca vieja (la primera columna de la tabla de parches de abajo, al revés); drop del helper.
-- destructivo-ok: no borra datos; create or replace de funciones.

create or replace function public._puede_editar_proyectos()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.es_admin()
      or exists (select 1 from public.usuarios u
                  where u.user_id = (select auth.uid()) and u.activo and u.rol = 'project_manager')
$$;
-- Sin llamador desde el navegador: solo lo llaman funciones security definer (que lo ejecutan como su dueño).
revoke all on function public._puede_editar_proyectos() from public, anon, authenticated;

do $parche$
declare
  -- función, marca vieja, marca nueva
  v_p text[][] := array[
    -- parcelas
    array['unidad_guarda', 'public.es_agente() and public.puede(''unidades'')', 'public._puede_editar_proyectos() and public.puede(''unidades'')'],
    array['unidad_guarda', '''No tienes la herramienta Unidades''', '''Editar parcelas es de administración o del encargado del proyecto'''],
    array['unidad_guarda', 'v_proy := public._unidad_proyecto(v_nproy);',
          'v_proy := public._unidad_proyecto(v_nproy); if not public.es_manager_de(v_proy) then raise exception ''No eres el encargado de ese proyecto'' using errcode = ''42501''; end if;'],
    array['unidad_guarda', 'not found or not public.unidad_visible(v_old.proyecto_id)', 'not found or not public.es_manager_de(v_old.proyecto_id)'],
    array['unidades_importa', 'public.es_agente() and public.puede(''unidades'')', 'public._puede_editar_proyectos() and public.puede(''unidades'')'],
    array['unidades_importa', '''No tienes la herramienta Unidades''', '''Importar parcelas es de administración o del encargado del proyecto'''],
    array['unidades_importa', 'v_proy := public._unidad_proyecto(v_nproy);',
          'v_proy := public._unidad_proyecto(v_nproy); if not public.es_manager_de(v_proy) then raise exception ''Fila %: no eres el encargado de ese proyecto'', coalesce(f->>''fila'', ''?'') using errcode = ''42501''; end if;'],
    array['unidades_importa', 'if not public.unidad_visible(v_old.proyecto_id) then', 'if not public.es_manager_de(v_old.proyecto_id) then'],
    -- documentos de modelos: solo admin
    array['modelo_documentos_guarda', 'if not public.es_agente() then raise exception ''Solo el equipo cambia documentos''', 'if not public.es_admin() then raise exception ''Solo administración cambia los documentos de un modelo'''],
    array['_modelo_documento_aplica', 'if not public.es_agente() then raise exception ''Solo el equipo cambia documentos''', 'if not public.es_admin() then raise exception ''Solo administración cambia los documentos de un modelo'''],
    array['modelo_documento_registra', 'if not public.es_agente() then raise exception ''Solo el equipo sube documentos''', 'if not public.es_admin() then raise exception ''Solo administración sube documentos de un modelo'''],
    -- documentos de proyecto: admin y encargado
    array['documento_proyecto_guarda', 'public.es_agente() and public.puede(''documentacion'')', 'public._puede_editar_proyectos() and public.puede(''documentacion'')'],
    array['documento_proyecto_guarda', '''La documentación exige la herramienta «Documentación»''', '''Editar la documentación es de administración o del encargado del proyecto'''],
    array['documento_proyecto_guarda', 'public.puede_proyecto(v_old.proyecto, v_old.proyecto_id)', 'public.es_manager_de(v_old.proyecto_id)'],
    array['documento_proyecto_guarda', 'public.puede_proyecto(v.proyecto, v.proyecto_id)', 'public.es_manager_de(v.proyecto_id)'],
    array['documento_proyecto_registra', 'public.es_agente() and public.puede(''documentacion'')', 'public._puede_editar_proyectos() and public.puede(''documentacion'')'],
    array['documento_proyecto_registra', 'public.puede_proyecto_id(p_proyecto)', 'public.es_manager_de(p_proyecto)'],
    array['documento_proyecto_puede', 'public.es_agente() and public.puede(''documentacion'')', 'public._puede_editar_proyectos() and public.puede(''documentacion'')'],
    array['documento_proyecto_puede', 'public.puede_proyecto_id(p_proyecto_id)', 'public.es_manager_de(p_proyecto_id)'],
    -- obra: admin y encargado
    array['obra_puede', 'public.es_agente() and public.puede(''obra'')', 'public._puede_editar_proyectos() and public.puede(''obra'')'],
    array['obra_puede', 'public.puede_proyecto_id(u.proyecto_id)', 'public.es_manager_de(u.proyecto_id)'],
    array['obra_confirmar_avance', 'public.puede(''obra'') and public.puede_proyecto(v_proyecto_nombre)', 'public._puede_editar_proyectos() and public.puede(''obra'') and public.es_manager_de(p_proyecto_id)'],
    array['obra_actualizar', 'es_agente() and puede(''obra'')', 'public._puede_editar_proyectos() and puede(''obra'')'],
    array['obra_actualizar', 'not puede_proyecto(v_proyecto)', 'not public.es_manager_de((select pp.id from public.proyectos pp where pp.nombre = v_proyecto limit 1))']
  ];
  f text; d text; d0 text; n int; nviejas int; ntot int; i int;
begin
  for f in select distinct v_p[g][1] from generate_series(1, array_length(v_p, 1)) g loop
    select pg_get_functiondef(p.oid) into d from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f;
    if d is null then raise exception 'agentes_solo_lectura: falta public.%', f using errcode = '55000'; end if;
    d0 := d; nviejas := 0; ntot := 0;
    for i in 1 .. array_length(v_p, 1) loop
      continue when v_p[i][1] <> f;
      ntot := ntot + 1;
      n := (length(d) - length(replace(d, v_p[i][2], ''))) / length(v_p[i][2]);
      if n = 1 then nviejas := nviejas + 1;
      elsif n <> 0 then raise exception 'agentes_solo_lectura: la marca % aparece % veces en % (se esperaba 1); la función viva cambió, revisar', i, n, f using errcode = '55000';
      end if;
    end loop;
    if nviejas = 0 then continue; end if;                       -- ya aplicado
    if nviejas <> ntot then raise exception 'agentes_solo_lectura: % está a medias (% de % marcas viejas); revisar a mano', f, nviejas, ntot using errcode = '55000'; end if;
    for i in 1 .. array_length(v_p, 1) loop
      continue when v_p[i][1] <> f;
      d := replace(d, v_p[i][2], v_p[i][3]);
    end loop;
    if d = d0 then raise exception 'agentes_solo_lectura: % no cambió', f using errcode = '55000'; end if;
    execute d;
  end loop;
end $parche$;
