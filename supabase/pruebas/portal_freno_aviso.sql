-- Prueba de 20261015230956_portal_freno_aviso (aplicada el 16-oct-2026; escrita como 20261015201000) (15-oct-2026, sesión lawang-cola-2; revisión previa #371 con Backend y Seguridad).
-- A1 nadie de fuera ejecuta portal_freno_anota (anon, authenticated) y service_role sí. A2 la tabla vive en privado, con RLS, y
-- ni anon, ni authenticated, ni service_role la leen o escriben (has_table_privilege: «0 filas» no prueba nada). A3 dos 'global'
-- suman 2 a n_global en la hora en curso, con UNA fila. A4 'ip' suma a n_ip y no a n_global. A5 motivo no válido o null = 22023 y no
-- escribe. A6 anillo: una ranura con la hora de hace 768 h se REINICIA (no suma lo viejo). A7 la tabla no tiene columnas de correo,
-- IP ni hash. A8 la función es DEFINER con search_path vacío. A3 y A6 dependen de no cruzar el cambio de hora durante la llamada: si
-- se cruza, salen «→ ok (sin medir: cambio de hora)» y se repite.
-- Sin serial ni identity: no gasta ninguna serie. Siembra filas en privado.portal_frenos: SOLO EN RAMA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261015230956_portal_freno_aviso.sql --prueba portal_freno_aviso.sql
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada línea acaba en «→ ok» o «→ FALLA».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
create or replace function pg_temp.ranura(t timestamptz) returns int language sql as $f$
  select (floor(extract(epoch from date_trunc('hour', t, 'UTC')) / 3600)::bigint % 768)::int
$f$;

do $todo$
declare
  r text := ''; v text; n bigint; g bigint; i bigint;
  t0 timestamptz; t1 timestamptz; h0 timestamptz; rr int; f record;
  c_fin constant text := 'FIN DE PRUEBAS PORTAL FRENO AVISO (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS PORTAL FRENO AVISO:%', E'\nP0 esta prueba siembra filas: solo corre en rama → FALLA';
  end if;

  r := r || pg_temp.l(not has_function_privilege('anon', 'public.portal_freno_anota(text)', 'execute')
                      and not has_function_privilege('authenticated', 'public.portal_freno_anota(text)', 'execute')
                      and has_function_privilege('service_role', 'public.portal_freno_anota(text)', 'execute'),
                      'A1 solo service_role ejecuta portal_freno_anota');
  begin
    set local role anon;
    perform public.portal_freno_anota('global');
    v := 'ejecutó';
  exception when insufficient_privilege then v := '42501';
  end;
  reset role;
  r := r || pg_temp.l(v = '42501', 'A1b anon llamándola de verdad: 42501 (' || v || ')');

  select count(*) into n from (values ('anon'), ('authenticated'), ('service_role')) x(rol)
   where has_table_privilege(x.rol, 'privado.portal_frenos', 'select') or has_table_privilege(x.rol, 'privado.portal_frenos', 'insert')
      or has_table_privilege(x.rol, 'privado.portal_frenos', 'update') or has_table_privilege(x.rol, 'privado.portal_frenos', 'delete');
  r := r || pg_temp.l(n = 0 and (select relrowsecurity from pg_class where oid = 'privado.portal_frenos'::regclass),
                      'A2 privado.portal_frenos con RLS y sin permisos para anon, authenticated ni service_role (' || n || ')');

  -- A3 dos 'global' en la hora en curso
  t0 := clock_timestamp(); h0 := date_trunc('hour', t0, 'UTC');
  select coalesce(sum(n_global), 0), coalesce(sum(n_ip), 0) into g, i from privado.portal_frenos where hora = h0;
  set local role service_role;
  perform public.portal_freno_anota('global');
  perform public.portal_freno_anota('global');
  reset role;
  t1 := clock_timestamp();
  if date_trunc('hour', t1, 'UTC') <> h0 then
    r := r || E'\nA3 dos global suman 2 en una fila → ok (sin medir: cambio de hora)';
  else
    select count(*), coalesce(sum(n_global), 0) into n, v from privado.portal_frenos where hora = h0;
    r := r || pg_temp.l(n = 1 and v::bigint = g + 2, 'A3 dos global suman 2 a n_global en una sola fila de la hora (' || g || '→' || v || ', filas ' || n || ')');
  end if;

  -- A4 'ip'
  set local role service_role;
  perform public.portal_freno_anota('ip');
  reset role;
  if date_trunc('hour', clock_timestamp(), 'UTC') <> h0 then
    r := r || E'\nA4 ip suma a n_ip y no a n_global → ok (sin medir: cambio de hora)';
  else
    select n_global, n_ip into f from privado.portal_frenos where hora = h0;
    r := r || pg_temp.l(f.n_ip = i + 1 and f.n_global = g + 2, 'A4 ip suma a n_ip (' || f.n_ip || ') y no a n_global (' || f.n_global || ')');
  end if;

  -- A5 motivos no válidos
  select count(*) into n from privado.portal_frenos;
  foreach v in array array['correo', 'pasa', 'GLOBAL', ''] loop
    begin
      set local role service_role;
      perform public.portal_freno_anota(v);
      reset role;
      r := r || pg_temp.l(false, 'A5 motivo «' || v || '» rechazado');
    exception when others then
      reset role;
      r := r || pg_temp.l(sqlstate = '22023', 'A5 motivo «' || v || '» rechazado con 22023 (' || sqlstate || ')');
    end;
  end loop;
  begin
    set local role service_role;
    perform public.portal_freno_anota(null);
    reset role;
    r := r || pg_temp.l(false, 'A5 motivo null rechazado');
  exception when others then
    reset role;
    r := r || pg_temp.l(sqlstate = '22023', 'A5 motivo null rechazado con 22023 (' || sqlstate || ')');
  end;
  r := r || pg_temp.l((select count(*) from privado.portal_frenos) = n, 'A5 los rechazados no escriben nada');

  -- A6 anillo: la ranura de ahora con datos de hace 768 h se reinicia
  t0 := clock_timestamp(); h0 := date_trunc('hour', t0, 'UTC'); rr := pg_temp.ranura(t0);
  insert into privado.portal_frenos (ranura, hora, n_global, n_ip, primero, ultimo)
  values (rr, h0 - interval '768 hours', 50, 7, h0 - interval '768 hours', h0 - interval '767 hours')
  on conflict (ranura) do update set hora = excluded.hora, n_global = 50, n_ip = 7, primero = excluded.primero, ultimo = excluded.ultimo;
  set local role service_role;
  perform public.portal_freno_anota('global');
  reset role;
  if date_trunc('hour', clock_timestamp(), 'UTC') <> h0 then
    r := r || E'\nA6 la ranura vieja se reinicia → ok (sin medir: cambio de hora)';
  else
    select * into f from privado.portal_frenos where ranura = rr;
    r := r || pg_temp.l(f.hora = h0 and f.n_global = 1 and f.n_ip = 0 and f.primero >= t0,
                        'A6 la ranura con la hora de hace 768 h se reinicia (hora ok, global ' || f.n_global || ', ip ' || f.n_ip || ')');
  end if;

  select string_agg(column_name::text, ',' order by column_name) into v
    from information_schema.columns where table_schema = 'privado' and table_name = 'portal_frenos';
  r := r || pg_temp.l(v = 'hora,n_global,n_ip,primero,ranura,ultimo', 'A7 columnas: solo hora y cuentas (' || v || ')');

  r := r || pg_temp.l((select prosecdef and proconfig = array['search_path=""'] from pg_proc
                        where oid = 'public.portal_freno_anota(text)'::regprocedure),
                      'A8 DEFINER con search_path vacío');

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
