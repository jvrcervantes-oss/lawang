-- REVERSIÓN lote 1 (6-oct-2026). Estado previo medido con pg_get_functiondef / pg_policies antes de aplicar.
-- F1: quitar el bloque añadido
do $$ declare v text; begin v := pg_get_functiondef('public.panel_bancos_datos(integer,integer,uuid)'::regprocedure);
 execute replace(v, E'  if not (public.es_admin() and public.puede(''bancos'')) then\n    raise exception ''panel_bancos_datos: hace falta ser admin con Bancos'' using errcode = ''42501'';\n  end if;\n', ''); end $$;
-- F5
do $$ declare v text; begin v := pg_get_functiondef('public.creatividades_datos(text,text,uuid,integer,uuid)'::regprocedure);
 execute replace(v, E'  if not public.es_agente() then\n    raise exception ''creatividades_datos: sin permiso'' using errcode = ''42501'';\n  end if;\n', ''); end $$;
do $$ declare v text; begin v := pg_get_functiondef('public.creatividad_datos(uuid)'::regprocedure);
 execute replace(v, E'  if not public.es_agente() then\n    raise exception ''creatividad_datos: sin permiso'' using errcode = ''42501'';\n  end if;\n', ''); end $$;
-- F8b
do $$ declare v text; begin v := pg_get_functiondef('public.dossier_datos(uuid,uuid[])'::regprocedure);
 execute replace(v, E'  if not public.proyecto_visible(p_proyecto) then\n    raise exception ''Ese proyecto no es tuyo'' using errcode = ''42501'';\n  end if;\n', ''); end $$;
-- G1 (policy previa: rol {public}, qual es_agente() AND puede('obra'))
drop policy obra_partes_trabajo_select on public.obra_partes_trabajo;
create policy obra_partes_trabajo_select on public.obra_partes_trabajo for select using (es_agente() and puede('obra'));
drop policy obra_progreso_fase_zona_select on public.obra_progreso_fase_zona;
create policy obra_progreso_fase_zona_select on public.obra_progreso_fase_zona for select using (es_agente() and puede('obra'));
-- G5-A (el COMMENT previo era NULL, medido)
comment on function public.hitos_sin_factura(date) is null;
-- G1 v2: tras revertir las policies (arriba): drop function public.agente_ve_proyecto_obra(uuid);
