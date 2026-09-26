-- Revisor de código sobre B4 (27-sep-2026): el alta de documentos en «Lawang (general)» / «Sumba (general)» fallaba
-- con «Ese proyecto no existe» (no son filas de `proyectos`; hoy hay 19 documentos así, con proyecto_id null) y la
-- documentación clásica los ofrece los primeros (lista cerrada: la misma GENERALES de la pantalla). Un ADMIN puede dar de alta en esos nombres «(general)»; nadie más.
-- Y la comprobación de 152000 (documento publicado) comparaba la descripción sin normalizar: '' frente a null
-- contaba como cambio. Parche con marca sobre la función viva (idempotente, falla si cambió).
do $$
declare v_def text; v_nuevo text;
begin
  select pg_get_functiondef('public.documento_proyecto_guarda(uuid,jsonb)'::regprocedure) into v_def;
  if strpos(v_def, 'B4 general alta admin') > 0 then return; end if;
  v_nuevo := replace(v_def,
    '    select p.id, p.nombre into v_pid, v_nombre from public.proyectos p where p.nombre = btrim(coalesce(p_datos->>''proyecto'', ''''));
    if v_pid is null then raise exception ''Ese proyecto no existe'' using errcode = ''22023''; end if;
    v.proyecto := v_nombre; v.proyecto_id := v_pid;',
    '    select p.id, p.nombre into v_pid, v_nombre from public.proyectos p where p.nombre = btrim(coalesce(p_datos->>''proyecto'', ''''));
    -- B4 general alta admin: «<Marca> (general)» no es un proyecto; solo un admin archiva ahí
    if v_pid is null and v_admin and btrim(coalesce(p_datos->>''proyecto'', '''')) in (''Lawang (general)'', ''Sumba (general)'') then
      v.proyecto := btrim(p_datos->>''proyecto''); v.proyecto_id := null;
    else
      if v_pid is null then raise exception ''Ese proyecto no existe'' using errcode = ''22023''; end if;
      v.proyecto := v_nombre; v.proyecto_id := v_pid;
    end if;');
  if v_nuevo = v_def then raise exception 'documento_proyecto_guarda cambió: no encuentro el alta por nombre de proyecto'; end if;
  v_def := v_nuevo;
  v_nuevo := replace(v_def,
    'or v.descripcion is distinct from v_old.descripcion or v.categoria',
    'or nullif(btrim(coalesce(v.descripcion, '''')), '''') is distinct from nullif(btrim(coalesce(v_old.descripcion, '''')), '''') or v.categoria');
  if v_nuevo = v_def then raise exception 'documento_proyecto_guarda cambió: no encuentro la comprobación del documento publicado'; end if;
  execute v_nuevo;
end $$;
