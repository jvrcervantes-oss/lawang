-- Foto de no-regresion del bloque 5 (8-oct-2026): lo que cada uno de los usuarios reales VE de la tabla `usuarios` (con authenticated y con lw_lector)
-- y lo que le dicen sus puertas de personas. JWT simulado con email + set local role. Termina en raise (sin rastro).
-- El md5 final debe ser IDENTICO antes y despues de cada migracion del bloque 5 (los 34 usuarios no cambian: ninguno tiene empresas ni rol de empresa).
-- destructivo-ok: solo lectura; termina en raise
do $t$
declare u record; out text := ''; o text; h text; n bigint; b boolean;
begin
  for u in select user_id, email from public.usuarios order by email loop
    o := u.email;
    perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
    set local role authenticated;
    select md5(coalesce(string_agg(user_id::text, ',' order by user_id::text),'')), count(*) into h, n from public.usuarios;
    o := o || '|a' || left(h,6) || ':' || n;
    -- ficha completa visible (por si una columna cambia de valor): md5 de la fila entera
    select md5(coalesce(string_agg((to_jsonb(x) - 'notif_visto_hasta')::text, ',' order by user_id::text),'')) into h from public.usuarios x;
    o := o || '|r' || left(h,6);
    b := public.es_admin(); o := o || '|ad' || b::text;
    b := public.es_super_admin(); o := o || '|su' || b::text;
    b := public.es_agente(); o := o || '|ag' || b::text;
    b := public.puede('usuarios'); o := o || '|pu' || b::text;
    reset role;
    set local role lw_lector;
    select md5(coalesce(string_agg(user_id::text, ',' order by user_id::text),'')), count(*) into h, n from public.usuarios;
    o := o || '|l' || left(h,6) || ':' || n;
    reset role;
    out := out || o || E'\n';
  end loop;
  raise exception E'FOTOB5\nMD5=%\nFILAS=%', md5(out), (select count(*) from regexp_split_to_table(out, E'\n')) - 1;
end $t$;
