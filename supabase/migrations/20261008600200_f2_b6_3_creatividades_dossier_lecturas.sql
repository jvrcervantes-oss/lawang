-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · cierre · bloque 6 · migracion 3 (8-oct-2026): creatividades y dossier por empresa del proyecto + lo que un rol de empresa LEE del deck y de los techos.
--   (1) Creatividades (piezas y dossiers): un super_admin_empresa no necesita la casilla (patron _puede_herr_o_super_empresa del bloque 1); un admin_empresa la necesita, como un admin global.
--       Una creatividad es de la empresa de su proyecto: quien tiene alcance por empresa solo ve, edita, cambia de estado y descarga las de SUS empresas. Una creatividad SIN proyecto (13 de 20 hoy) es general
--       y nace cerrada para un rol de empresa: la sigue viendo todo el que no tiene alcance por empresa (los 34 de hoy). Aprobar/publicar/archivar (v_admin) pasa a ser admin de la empresa del proyecto.
--   (2) dossier_datos (dueno lector): la casilla Dossier/Creatividades tambien la salta un super_admin_empresa; el proyecto sigue pasando por proyecto_visible (empresa).
--       Para eso _puede_herr_o_super_empresa gana EXECUTE para lw_lector (solo lw_lector: sigue sin EXECUTE para authenticated y anon).
--   (3) Lectura del deck (config, preguntas, previsiones, fotos de PROYECTO) y de qué proyectos usa un techo: un rol con alcance por empresa solo lee lo de sus empresas. Las fotos de MODELO (sin proyecto) las lee todo agente.
--       Para los 34 usuarios de hoy es «no restringido» = sin cambio (la comprobacion es una constante por consulta).
-- destructivo-ok: create or replace de funciones y alter policy; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b6.sql (PARTE 3)

create or replace function pg_temp.parchea(p_f regprocedure, p_old text, p_new text, p_n int default 1) returns void language plpgsql as $f$
declare v text; v_c int;
begin
  v := pg_get_functiondef(p_f);
  v_c := (length(v) - length(replace(v, p_old, ''))) / length(p_old);
  if v_c <> p_n then
    raise exception 'parche f2_b6: «%» aparece % veces en %, esperaba %', p_old, v_c, p_f, p_n;
  end if;
  execute replace(v, p_old, p_new);
end $f$;

-- 1. Creatividades -----------------------------------------------------------------------------------------
select pg_temp.parchea('public.creatividad_puede_hacer(text)'::regprocedure,
  $q$public.puede('creatividades')$q$,
  $q$public._puede_herr_o_super_empresa('creatividades')$q$);
select pg_temp.parchea('public.creatividad_puede_hacer(text)'::regprocedure,
  $q$public.puede('dossier')$q$,
  $q$public._puede_herr_o_super_empresa('dossier')$q$);

select pg_temp.parchea('public.creatividad_estado(uuid,text)'::regprocedure,
  $q$if not found then raise exception 'No existe esa creatividad.' using errcode = 'P0002'; end if;$q$,
  $q$if not found then raise exception 'No existe esa creatividad.' using errcode = 'P0002'; end if;
  if public.alcance_restringido() and (c.proyecto_id is null or not public.proyecto_en_alcance(c.proyecto_id)) then
    raise exception 'No existe esa creatividad.' using errcode = 'P0002';
  end if;$q$);
select pg_temp.parchea('public.creatividad_estado(uuid,text)'::regprocedure,
  $q$v_admin := public.es_admin();$q$,
  $q$v_admin := public.es_admin_de(public._empresa_de_proyecto_int(c.proyecto_id));$q$);

select pg_temp.parchea('public.creatividad_guarda(uuid,uuid,text,jsonb,text,text,text,uuid[],uuid[])'::regprocedure,
  $q$v_formato := case when p_datos ? 'formato' then nullif(btrim(coalesce(p_datos->>'formato', '')), '') else v.formato end;$q$,
  $q$if public.alcance_restringido() and (v_proy is null or not public.proyecto_en_alcance(v_proy)) then
    raise exception 'Esa creatividad tiene que ser de un proyecto de tus empresas' using errcode = '42501';
  end if;
  v_formato := case when p_datos ? 'formato' then nullif(btrim(coalesce(p_datos->>'formato', '')), '') else v.formato end;$q$);

select pg_temp.parchea('public.creatividad_descarga(uuid,text)'::regprocedure,
  $q$if not found or not public.creatividad_puede_ver(c.tipo, c.estado) then$q$,
  $q$if not found or not public.creatividad_puede_ver(c.tipo, c.estado)
     or (public.alcance_restringido() and (c.proyecto_id is null or not public.proyecto_en_alcance(c.proyecto_id))) then$q$);

alter policy "creatividades: leer" on public.creatividades
  using ((select public.creatividad_puede_ver(tipo, estado))
         and (not (select public.alcance_restringido()) or (proyecto_id is not null and public.proyecto_en_alcance(proyecto_id))));

-- 2. Dossier -------------------------------------------------------------------------------------------------
grant execute on function public._puede_herr_o_super_empresa(text) to lw_lector;
select pg_temp.parchea('public.dossier_datos(uuid,uuid[])'::regprocedure,
  $q$if not (public.puede('dossier') or public.puede('creatividades')) then$q$,
  $q$if not (public._puede_herr_o_super_empresa('dossier') or public._puede_herr_o_super_empresa('creatividades')) then$q$);

-- 3. Lecturas del deck y de los techos por proyecto -----------------------------------------------------------
alter policy "deck_config_proyecto: leer" on public.deck_config_proyecto
  using (public.es_agente() and (not (select public.alcance_restringido()) or public.proyecto_en_alcance(proyecto_id)));
alter policy "deck_faq: leer" on public.deck_faq
  using (public.es_agente() and (not (select public.alcance_restringido()) or public.proyecto_en_alcance(proyecto_id)));
alter policy "deck_forecast: leer" on public.deck_forecast
  using (public.es_agente() and (not (select public.alcance_restringido()) or public.proyecto_en_alcance(proyecto_id)));
alter policy "deck_forecast_proyecto: leer" on public.deck_forecast_proyecto
  using (public.es_agente() and (not (select public.alcance_restringido()) or public.proyecto_en_alcance(proyecto_id)));
alter policy "deck_fotos: leer" on public.deck_fotos
  using (public.es_agente() and (not (select public.alcance_restringido()) or proyecto_id is null or public.proyecto_en_alcance(proyecto_id)));
alter policy "techo_proyectos: leer" on public.modelo_techo_proyectos
  using (public.es_agente() and (not (select public.alcance_restringido()) or public.proyecto_en_alcance(proyecto_id)));
