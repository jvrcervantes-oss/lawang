-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 1 (OK del owner 6-oct-2026) · F8b: dossier_datos solo devuelve el proyecto si el usuario lo ve (proyecto_visible).
-- destructivo-ok: solo cambia el cuerpo de una función; no toca filas.
do $$
declare v text; viejo text;
begin
  v := pg_get_functiondef('public.dossier_datos(uuid,uuid[])'::regprocedure);
  if position('proyecto_visible(p_proyecto)' in v) > 0 then return; end if;
  viejo := E'    raise exception ''Sin permiso para montar dossiers.'' using errcode = ''42501'';\n  end if;\n';
  if position(viejo in v) = 0 then raise exception 'ancla F8b no encontrada'; end if;
  v := replace(v, viejo, viejo || E'  if not public.proyecto_visible(p_proyecto) then\n    raise exception ''Ese proyecto no es tuyo'' using errcode = ''42501'';\n  end if;\n');
  execute v;
end $$;
