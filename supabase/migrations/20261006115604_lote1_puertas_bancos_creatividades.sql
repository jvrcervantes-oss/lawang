-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 1 (OK del owner 6-oct-2026) · F1 + F5: puerta explícita en panel_bancos_datos, creatividades_datos y creatividad_datos.
-- Defensa en profundidad: la RLS ya filtraba; esto cierra además las etiquetas de cuentas bancarias (F1) y evita que
-- una futura policy/dueño distinto abra las creatividades (F5). Parche sobre la función viva (conserva dueño lw_lector y ACL).
-- destructivo-ok: solo cambia el cuerpo de tres funciones; no toca filas.
do $$
declare v text; viejo text;
begin
  -- F1
  v := pg_get_functiondef('public.panel_bancos_datos(integer,integer,uuid)'::regprocedure);
  viejo := E'    raise exception ''panel_bancos_datos: sin sesión'' using errcode = ''42501'';\n  end if;\n';
  if position('es_admin() and public.puede(''bancos'')' in v) = 0 then
    if position(viejo in v) = 0 then raise exception 'ancla F1 no encontrada'; end if;
    v := replace(v, viejo, viejo || E'  if not (public.es_admin() and public.puede(''bancos'')) then\n    raise exception ''panel_bancos_datos: hace falta ser admin con Bancos'' using errcode = ''42501'';\n  end if;\n');
    execute v;
  end if;
  -- F5 creatividades_datos
  v := pg_get_functiondef('public.creatividades_datos(text,text,uuid,integer,uuid)'::regprocedure);
  viejo := E'    raise exception ''creatividades_datos: sin sesión'' using errcode = ''42501'';\n  end if;\n';
  if position('public.es_agente()' in v) = 0 then
    if position(viejo in v) = 0 then raise exception 'ancla F5a no encontrada'; end if;
    v := replace(v, viejo, viejo || E'  if not public.es_agente() then\n    raise exception ''creatividades_datos: sin permiso'' using errcode = ''42501'';\n  end if;\n');
    execute v;
  end if;
  -- F5 creatividad_datos
  v := pg_get_functiondef('public.creatividad_datos(uuid)'::regprocedure);
  viejo := E'    raise exception ''creatividad_datos: sin sesión'' using errcode = ''42501'';\n  end if;\n';
  if position('public.es_agente()' in v) = 0 then
    if position(viejo in v) = 0 then raise exception 'ancla F5b no encontrada'; end if;
    v := replace(v, viejo, viejo || E'  if not public.es_agente() then\n    raise exception ''creatividad_datos: sin permiso'' using errcode = ''42501'';\n  end if;\n');
    execute v;
  end if;
end $$;
