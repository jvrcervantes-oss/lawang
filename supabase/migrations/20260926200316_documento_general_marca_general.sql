-- Reconstruida el 10-oct-2026 desde supabase_migrations.schema_migrations.statements (version y nombre exactos; ya APLICADA en produccion, no se vuelve a aplicar). Su cambio ya esta fundido en: 20260927152500_documento_general_alta_admin.sql (y la funcion vigente, 20261006110000_documento_url_por_idioma.sql)
do $$
declare v_def text; v_nuevo text;
begin
  select pg_get_functiondef('public.documento_proyecto_guarda(uuid,jsonb)'::regprocedure) into v_def;
  if strpos(v_def, 'v.proyecto_id := null; v.general := true;') > 0 then return; end if;
  v_nuevo := replace(v_def,
    'v.proyecto := btrim(p_datos->>''proyecto''); v.proyecto_id := null;',
    'v.proyecto := btrim(p_datos->>''proyecto''); v.proyecto_id := null; v.general := true;');
  if v_nuevo = v_def then raise exception 'documento_proyecto_guarda cambió: no encuentro la rama de los nombres generales'; end if;
  execute v_nuevo;
end $$;;
