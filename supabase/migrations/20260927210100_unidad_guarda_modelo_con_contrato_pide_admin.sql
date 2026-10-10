-- Reconstruida el 10-oct-2026 desde supabase_migrations.schema_migrations.statements (nombre exacto; version real del catalogo 20260927040419, el prefijo sigue al fichero padre para que el orden de replay sea el de aplicacion; ya APLICADA en produccion, no se vuelve a aplicar). Su cambio ya esta fundido en: 20260927210000_unidad_guarda_cambia_modelo.sql
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
