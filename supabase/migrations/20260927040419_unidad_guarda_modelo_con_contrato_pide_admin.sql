-- Reconstruida el 10-oct-2026 desde supabase_migrations.schema_migrations.statements (version y nombre exactos; ya APLICADA en produccion, no se vuelve a aplicar). Aqui el prefijo es la version real A PROPOSITO, no padre+100: el bloque do parchea el texto de unidad_guarda que dejan 20260927010000/011500 y no tiene salida si ya esta hecho; detras de 20260927210000_unidad_guarda_cambia_modelo.sql (que ya trae este cambio fundido) no encuentra el texto y hace raise exception.
do $do$
declare d text; n text;
begin
  d := pg_get_functiondef('public.unidad_guarda(uuid,jsonb,text)'::regprocedure);
  n := replace(d, E'or coalesce(v_mon, v_old.moneda) is distinct from v_old.moneda;',
                  E'or coalesce(v_mon, v_old.moneda) is distinct from v_old.moneda\n           or public.modelo_norm(v_modelo) is distinct from public.modelo_norm(v_old.modelo);');
  n := replace(n, 'su precio, moneda, superficie, código y proyecto solo los cambia un admin',
                  'su modelo, precio, moneda, superficie, código y proyecto solo los cambia un admin');
  if n = d or position('modelo_norm(v_modelo)' in n) = 0 or position('su modelo, precio' in n) = 0 then
    raise exception 'patch no aplicado';
  end if;
  execute n;
end $do$;
