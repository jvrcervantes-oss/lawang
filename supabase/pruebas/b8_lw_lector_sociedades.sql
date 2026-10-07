-- LAW-496 · bloque 8: lw_lector sin SELECT sobre sociedades, y nada que dependa de ello sigue funcionando igual. Termina en raise (sin rastro).
-- destructivo-ok: ensayo en transaccion que acaba en rollback
do $t$
declare r text; n1 jsonb; n2 jsonb; u record; k int := 0;
begin
  -- antes: lo que devuelven las RPC que tocan sociedades, para un admin real
  select user_id, email into u from public.usuarios where rol in ('super_admin','admin') order by email limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
  set local role authenticated;
  n1 := public.sociedades_ajustes_datos();
  reset role;
  revoke select on public.sociedades from lw_lector;
  assert not has_table_privilege('lw_lector','public.sociedades','select'), 'lw_lector aun lee sociedades';
  assert not has_any_column_privilege('lw_lector','public.sociedades','select'), 'lw_lector aun lee columnas de sociedades';
  assert has_any_column_privilege('authenticated','public.sociedades','select'), 'authenticated perdio sus columnas';
  perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
  set local role authenticated;
  n2 := public.sociedades_ajustes_datos();
  reset role;
  assert n1 = n2, 'sociedades_ajustes_datos cambio';
  -- lw_lector ya no puede leerla
  begin
    set local role lw_lector; perform 1 from public.sociedades limit 1; k := 1;
  exception when insufficient_privilege then k := 0; end;
  reset role;
  assert k = 0, 'lw_lector todavia lee sociedades';
  raise exception 'B8 OK (rollback)';
end $t$;
