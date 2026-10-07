-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · cierre · bloque 6 · migracion 4 (8-oct-2026): documentos de proyecto, obra y uso de plantillas por empresa del proyecto.
--   Lo que ya hacia el bloque 1 (_puede_editar_proyectos y es_manager_de reconocen a un rol de empresa por la empresa del proyecto) se completa con lo que quedaba:
--   (1) CASILLAS: puede('x') solo salta las casillas al super GLOBAL. Un super_admin_empresa no necesita la casilla Documentacion/Obra en SU empresa (_puede_herr_o_super_empresa, bloque 1); el objeto sigue acotado
--       por es_manager_de / puede_proyecto (empresa del proyecto). Un admin_empresa SI necesita la casilla, igual que un admin global. Funciones: documento_proyecto_puede/guarda/registra, obra_puede/actualizar/
--       confirmar_avance/contratos_afectados/datos_cobro y agente_ve_proyecto_obra (la usan las policies de obra_partes_trabajo y obra_progreso_fase_zona).
--   (2) documento_proyecto_borra: «admin con casilla» pasa a _puede_admin_de(empresa del documento, 'documentacion') (admin de esa empresa con casilla, o super de esa empresa). Para un global es lo mismo que antes.
--       Publicar/retirar un documento del dosier de inversores (documento_proyecto_guarda/registra) lo decide el admin de la empresa del PROYECTO. «Documento general de la empresa» y los proyectos
--       «Lawang (general)»/«Sumba (general)» siguen siendo de un admin global (no tienen empresa).
--   (3) plantillas_uso (contratos emitidos por tipo): un super_admin_empresa la ve de los contratos de SUS empresas; el super global, de todos.
--   NO se tocan: las puertas de mantenimiento/ajustes (config_instancia, mantenimiento, ajustes_log: de toda la instancia, cerradas a un rol de empresa por es_admin()/es_super_admin()), la edge `ficheros`
--   (mira es_admin antes de subir fotos del deck y documentos de modelo) ni los documentos de modelo (catalogo compartido).
-- destructivo-ok: create or replace de funciones; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b6.sql (PARTE 4)

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

-- 1. Documentos de proyecto ------------------------------------------------------------------------------------
select pg_temp.parchea('public.documento_proyecto_puede(uuid)'::regprocedure,
  $q$public._puede_editar_proyectos() and public.puede('documentacion')$q$,
  $q$public._puede_editar_proyectos() and public._puede_herr_o_super_empresa('documentacion')$q$);

select pg_temp.parchea('public.documento_proyecto_guarda(uuid,jsonb)'::regprocedure,
  $q$public._puede_editar_proyectos() and public.puede('documentacion')$q$,
  $q$public._puede_editar_proyectos() and public._puede_herr_o_super_empresa('documentacion')$q$);
select pg_temp.parchea('public.documento_proyecto_guarda(uuid,jsonb)'::regprocedure,
  $q$if v.publicado_investor_deck is distinct from coalesce(v_old.publicado_investor_deck, false) and not v_admin then$q$,
  $q$if v.publicado_investor_deck is distinct from coalesce(v_old.publicado_investor_deck, false) and not (v_admin or public.es_admin_de(public._empresa_de_proyecto_int(v.proyecto_id))) then$q$);
select pg_temp.parchea('public.documento_proyecto_guarda(uuid,jsonb)'::regprocedure,
  $q$if p_id is not null and coalesce(v_old.publicado_investor_deck, false) and not v_admin$q$,
  $q$if p_id is not null and coalesce(v_old.publicado_investor_deck, false) and not (v_admin or public.es_admin_de(public._empresa_de_proyecto_int(v_old.proyecto_id)))$q$);

select pg_temp.parchea('public.documento_proyecto_registra(uuid,uuid,text,jsonb)'::regprocedure,
  $q$public._puede_editar_proyectos() and public.puede('documentacion')$q$,
  $q$public._puede_editar_proyectos() and public._puede_herr_o_super_empresa('documentacion')$q$);
select pg_temp.parchea('public.documento_proyecto_registra(uuid,uuid,text,jsonb)'::regprocedure,
  $q$if v_pub and not public.es_admin() then$q$,
  $q$if v_pub and not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto)) then$q$);

select pg_temp.parchea('public.documento_proyecto_borra(uuid,uuid,boolean)'::regprocedure,
  $q$if not (public.es_admin() and public.puede('documentacion')) then$q$,
  $q$if not public._puede_admin_de(public._empresa_de_proyecto_int((select d.proyecto_id from public.documentos_proyecto d where d.id = p_id)), 'documentacion') then$q$);

-- 2. Obra --------------------------------------------------------------------------------------------------------
select pg_temp.parchea('public.obra_puede(uuid)'::regprocedure,
  $q$public.puede('obra')$q$, $q$public._puede_herr_o_super_empresa('obra')$q$);
select pg_temp.parchea('public.obra_actualizar(uuid,text,date)'::regprocedure,
  $q$and puede('obra')$q$, $q$and public._puede_herr_o_super_empresa('obra')$q$);
select pg_temp.parchea('public.obra_confirmar_avance(uuid,text,text,text,integer,text,uuid[])'::regprocedure,
  $q$public.puede('obra')$q$, $q$public._puede_herr_o_super_empresa('obra')$q$);
select pg_temp.parchea('public.obra_contratos_afectados(uuid,text,text,text)'::regprocedure,
  $q$public.puede('obra')$q$, $q$public._puede_herr_o_super_empresa('obra')$q$);
select pg_temp.parchea('public.obra_datos_cobro(uuid,text,text,text)'::regprocedure,
  $q$public.puede('obra')$q$, $q$public._puede_herr_o_super_empresa('obra')$q$);
select pg_temp.parchea('public.agente_ve_proyecto_obra(uuid)'::regprocedure,
  $q$public.puede('obra')$q$, $q$public._puede_herr_o_super_empresa('obra')$q$);

-- 3. Uso de las plantillas (contratos emitidos por tipo) --------------------------------------------------------------
select pg_temp.parchea('public.plantillas_uso()'::regprocedure,
  $q$where public.es_super_admin()$q$,
  $q$where public.es_super_admin_de(public._empresa_de_contrato_int(ct.id))$q$);
