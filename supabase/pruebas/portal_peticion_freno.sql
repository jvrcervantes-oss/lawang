-- Prueba de 20261015235325_portal_peticion_freno (aplicada el 16-oct-2026; escrita como 20261015202000) (15-oct-2026, sesión lawang-cola-2, resto 6; revisión previa #373 Backend + Seguridad).
-- B1 solo service_role ejecuta portal_peticion_freno (anon llamándola de verdad: 42501). B2 las dos tablas en privado, con RLS y sin
-- permisos para anon, authenticated ni service_role. B3 hash mal formado (mayúsculas, 63 hex, vacío, texto) = 22023 y no escribe.
-- B4 el mismo cubo × 1000: 20 'pasa' y 980 'ip', y el global (n de la hora) sube SOLO 20 — una IP frenada no gasta el global
-- (Seguridad #373.1); frenadas_ip = 1 y max_ip = 21: el cubo cuenta una vez, al cruzar su tope, y las 979 frenadas
-- siguientes no tocan la fila de la hora (B4b, por ctid; consulta de deploy del 16-oct). B5 otro hash con los mismos 3 primeros hex comparte cubo (frenado); uno con
-- otro cubo pasa. B6 sin IP: su propio cubo de 20 (la 21.ª 'ip') y no frena a las que traen IP. B7 cortacircuitos: con n = 999 en la
-- hora, la siguiente pasa (1000) y la otra es 'global' con frenadas_global = 1; una frenada por IP no suma frenadas_global. B8 anillo:
-- la fila del cubo y la ranura de la hora con una hora vieja se REINICIAN. B9 columnas: ni correo, ni IP, ni hash. B10 DEFINER con
-- search_path vacío, lock_timeout de 200 ms y sin candado consultivo.
-- La rama de Lawang es solo estructura: las tablas nacen vacías y todo se siembra aquí. Si quedan menos de 40 s para el cambio de
-- hora se espera a la siguiente (las cuentas son por hora); si aun así cambiara, la última línea lo dice con «→ FALLA» y se repite.
-- Sin serial ni identity: no gasta ninguna serie. Siembra filas en privado: SOLO EN RAMA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261015235325_portal_peticion_freno.sql --prueba portal_peticion_freno.sql
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada línea acaba en «→ ok» o «→ FALLA».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
-- un hash de 64 hex que empieza por `p` (el cubo son sus 3 primeros hex)
create or replace function pg_temp.h(p text, relleno text default '0') returns text language sql as $f$
  select p || repeat(relleno, 64 - length(p))
$f$;
create or replace function pg_temp.frena(p text) returns text language plpgsql as $f$
declare v text;
begin
  set local role service_role;
  v := public.portal_peticion_freno(p);
  reset role;
  return v;
end
$f$;

do $todo$
declare
  r text := ''; v text; v_n bigint; k int; pasa int; ip int;
  h0 timestamptz; v_h bigint; f record;
  c_fin constant text := 'FIN DE PRUEBAS PORTAL PETICION FRENO (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS PORTAL PETICION FRENO:%', E'\nP0 esta prueba siembra filas: solo corre en rama → FALLA';
  end if;
  if clock_timestamp() > date_trunc('hour', clock_timestamp(), 'UTC') + interval '59 minutes 20 seconds' then
    perform pg_sleep(41);
  end if;
  h0 := date_trunc('hour', clock_timestamp(), 'UTC');
  v_h := floor(extract(epoch from h0) / 3600)::bigint;
  r := r || pg_temp.l((select count(*) from privado.portal_peticiones_ip) = 0 and (select count(*) from privado.portal_peticiones_hora) = 0,
                      'P0 las dos tablas nacen vacías en la rama');

  -- B1
  r := r || pg_temp.l(not has_function_privilege('anon', 'public.portal_peticion_freno(text)', 'execute')
                      and not has_function_privilege('authenticated', 'public.portal_peticion_freno(text)', 'execute')
                      and has_function_privilege('service_role', 'public.portal_peticion_freno(text)', 'execute'),
                      'B1 solo service_role ejecuta portal_peticion_freno');
  begin
    set local role anon;
    perform public.portal_peticion_freno(pg_temp.h('aaa'));
    v := 'ejecutó';
  exception when insufficient_privilege then v := '42501';
  end;
  reset role;
  r := r || pg_temp.l(v = '42501', 'B1b anon llamándola de verdad: 42501 (' || v || ')');

  -- B2
  select count(*) into v_n
    from (values ('anon'), ('authenticated'), ('service_role')) x(rol),
         (values ('privado.portal_peticiones_ip'), ('privado.portal_peticiones_hora')) t(tabla),
         (values ('select'), ('insert'), ('update'), ('delete')) p(priv)
   where has_table_privilege(x.rol, t.tabla, p.priv);
  r := r || pg_temp.l(v_n = 0 and (select bool_and(relrowsecurity) from pg_class
                                  where oid in ('privado.portal_peticiones_ip'::regclass, 'privado.portal_peticiones_hora'::regclass)),
                      'B2 las dos tablas con RLS y sin permisos para anon, authenticated ni service_role (' || v_n || ')');

  -- B3 hash mal formado: 22023 y no escribe
  foreach v in array array[upper(pg_temp.h('abc', 'f')), pg_temp.h('abc') || '0', left(pg_temp.h('abc'), 63), '', 'una ip en claro'] loop
    begin
      perform pg_temp.frena(v);
      r := r || pg_temp.l(false, 'B3 hash «' || left(v, 12) || '…» (' || length(v) || ') rechazado');
    exception when others then
      reset role;
      r := r || pg_temp.l(sqlstate = '22023', 'B3 hash «' || left(v, 12) || '…» (' || length(v) || ') rechazado con 22023 (' || sqlstate || ')');
    end;
  end loop;
  r := r || pg_temp.l((select count(*) from privado.portal_peticiones_ip) = 0 and (select count(*) from privado.portal_peticiones_hora) = 0,
                      'B3 los rechazados no escriben nada');

  -- B4 el mismo cubo × 1000
  pasa := 0; ip := 0;
  for k in 1..1000 loop
    v := pg_temp.frena(pg_temp.h('abc'));
    if v = 'pasa' then pasa := pasa + 1; elsif v = 'ip' then ip := ip + 1; end if;
  end loop;
  select * into f from privado.portal_peticiones_hora where ranura = (v_h % 768)::int;
  r := r || pg_temp.l(pasa = 20 and ip = 980, 'B4 el mismo cubo × 1000: ' || pasa || ' pasa y ' || ip || ' ip (20 y 980)');
  r := r || pg_temp.l(f.n = 20 and f.frenadas_ip = 1 and f.max_ip = 21 and f.frenadas_global = 0 and f.hora = h0,
                      'B4 el global solo suma las 20 que pasaron su IP (n ' || f.n || ', frenadas_ip ' || f.frenadas_ip || ', max_ip '
                      || f.max_ip || ', frenadas_global ' || f.frenadas_global || ')');
  r := r || pg_temp.l((select n from privado.portal_peticiones_ip where cubo = 2748 and franja = (v_h % 2)::smallint) = 1000,
                      'B4 el cubo abc (2748) sigue contando frenado: 1000');
  -- B4b una frenada más no reescribe la fila de la hora (misma ctid y mismos valores)
  select ctid::text || '|' || n || '|' || frenadas_ip || '|' || max_ip into v from privado.portal_peticiones_hora where ranura = (v_h % 768)::int;
  r := r || pg_temp.l(pg_temp.frena(pg_temp.h('abc')) = 'ip'
                      and v = (select ctid::text || '|' || n || '|' || frenadas_ip || '|' || max_ip
                                 from privado.portal_peticiones_hora where ranura = (v_h % 768)::int),
                      'B4b una petición ya frenada no escribe la fila de la hora (' || v || ')');

  -- B5 mismo cubo con otro hash; otro cubo
  r := r || pg_temp.l(pg_temp.frena(pg_temp.h('abc', 'f')) = 'ip', 'B5 otro hash con los mismos 3 primeros hex comparte cubo: frenado');
  r := r || pg_temp.l(pg_temp.frena(pg_temp.h('abd')) = 'pasa', 'B5 un hash de otro cubo pasa');

  -- B6 sin IP: su propio cubo de 20
  pasa := 0;
  for k in 1..20 loop
    if pg_temp.frena(null) = 'pasa' then pasa := pasa + 1; end if;
  end loop;
  r := r || pg_temp.l(pasa = 20 and pg_temp.frena(null) = 'ip', 'B6 sin IP: 20 pasan (' || pasa || ') y la 21.ª es ip');
  r := r || pg_temp.l((select n from privado.portal_peticiones_ip where cubo = 4096 and franja = (v_h % 2)::smallint) = 21,
                      'B6 las de sin IP van al cubo 4096');
  r := r || pg_temp.l(pg_temp.frena(pg_temp.h('abe')) = 'pasa', 'B6 el cubo sin IP lleno no frena a las que traen IP');

  -- B7 cortacircuitos global
  update privado.portal_peticiones_hora set n = 999 where ranura = (v_h % 768)::int;
  r := r || pg_temp.l(pg_temp.frena(pg_temp.h('b01')) = 'pasa', 'B7 con 999 en la hora, la siguiente pasa (1000)');
  r := r || pg_temp.l(pg_temp.frena(pg_temp.h('b02')) = 'global', 'B7 la 1001 es global');
  select * into f from privado.portal_peticiones_hora where ranura = (v_h % 768)::int;
  r := r || pg_temp.l(f.n = 1001 and f.frenadas_global = 1, 'B7 n ' || f.n || ' y frenadas_global ' || f.frenadas_global || ' (1001 y 1)');
  v_n := f.frenadas_ip;
  r := r || pg_temp.l(pg_temp.frena(pg_temp.h('abc')) = 'ip', 'B7 con el global agotado, una IP frenada sigue siendo ip');
  select * into f from privado.portal_peticiones_hora where ranura = (v_h % 768)::int;
  r := r || pg_temp.l(f.n = 1001 and f.frenadas_global = 1 and f.frenadas_ip = v_n,
                      'B7 la frenada por IP no suma a n, ni a frenadas_global, ni vuelve a contar su cubo (n ' || f.n || ', global '
                      || f.frenadas_global || ', ip ' || f.frenadas_ip || ')');

  -- B8 anillo: cubo y ranura con una hora vieja se reinician
  update privado.portal_peticiones_ip set hora = h0 - interval '2 hours', n = 500 where cubo = 2748 and franja = (v_h % 2)::smallint;
  update privado.portal_peticiones_hora set hora = h0 - interval '768 hours', n = 5000, frenadas_ip = 7, frenadas_global = 3, max_ip = 900
   where ranura = (v_h % 768)::int;
  r := r || pg_temp.l(pg_temp.frena(pg_temp.h('abc')) = 'pasa', 'B8 el cubo con una hora vieja se reinicia: pasa');
  select * into f from privado.portal_peticiones_hora where ranura = (v_h % 768)::int;
  r := r || pg_temp.l(f.hora = h0 and f.n = 1 and f.frenadas_ip = 0 and f.frenadas_global = 0 and f.max_ip = 1,
                      'B8 la ranura de hace 768 h se reinicia (n ' || f.n || ', ip ' || f.frenadas_ip || ', global ' || f.frenadas_global
                      || ', max_ip ' || f.max_ip || ')');
  r := r || pg_temp.l((select n from privado.portal_peticiones_ip where cubo = 2748 and franja = (v_h % 2)::smallint) = 1,
                      'B8 y la fila del cubo vuelve a 1');

  -- B9 columnas
  select string_agg(table_name || '.' || column_name, ',' order by table_name, column_name) into v
    from information_schema.columns where table_schema = 'privado' and table_name in ('portal_peticiones_ip', 'portal_peticiones_hora');
  r := r || pg_temp.l(v = 'portal_peticiones_hora.frenadas_global,portal_peticiones_hora.frenadas_ip,portal_peticiones_hora.hora,'
                        || 'portal_peticiones_hora.max_ip,portal_peticiones_hora.n,portal_peticiones_hora.ranura,'
                        || 'portal_peticiones_ip.cubo,portal_peticiones_ip.franja,portal_peticiones_ip.hora,portal_peticiones_ip.n',
                      'B9 columnas: solo cubo, hora y cuentas (' || v || ')');

  -- B10
  r := r || pg_temp.l((select prosecdef and proconfig @> array['search_path=""', 'lock_timeout=200ms'] and cardinality(proconfig) = 2
                               and prosrc !~* 'advisory' from pg_proc
                        where oid = 'public.portal_peticion_freno(text)'::regprocedure),
                      'B10 DEFINER, search_path vacío, lock_timeout 200ms y sin candado consultivo');

  r := r || pg_temp.l(date_trunc('hour', clock_timestamp(), 'UTC') = h0, 'P1 toda la prueba dentro de la misma hora (si no, repetir)');
  raise exception using message = replace(c_fin, '%', r);
end $todo$;
