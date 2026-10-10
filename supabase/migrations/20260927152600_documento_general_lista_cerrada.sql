-- Reconstruida el 10-oct-2026 desde supabase_migrations.schema_migrations.statements (nombre exacto; version real del catalogo 20260926200154, el prefijo sigue al fichero padre para que el orden de replay sea el de aplicacion; ya APLICADA en produccion, no se vuelve a aplicar). Su cambio ya esta fundido en: 20260927152500_documento_general_alta_admin.sql (y la funcion vigente, 20261006110000_documento_url_por_idioma.sql)
do $$
declare v_def text; v_nuevo text;
begin
  select pg_get_functiondef('public.documento_proyecto_guarda(uuid,jsonb)'::regprocedure) into v_def;
  v_nuevo := replace(v_def,
    'btrim(coalesce(p_datos->>''proyecto'', '''')) ~ ''^[[:alnum:] ]{2,40} \(general\)$''',
    'btrim(coalesce(p_datos->>''proyecto'', '''')) in (''Lawang (general)'', ''Sumba (general)'')');
  if v_nuevo = v_def then
    if strpos(v_def, 'in (''Lawang (general)'', ''Sumba (general)'')') > 0 then return; end if;
    raise exception 'documento_proyecto_guarda cambió: no encuentro la regla de los nombres generales';
  end if;
  execute v_nuevo;
end $$;
