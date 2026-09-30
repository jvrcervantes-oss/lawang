-- destructivo-ok: prueba F3 entera dentro de begin … rollback (la migración rehace policies); no escribe nada
-- =====================================================================================
-- PRUEBA POR PERFIL — F3 · visibilidad por equipo (supabase/migrations/20260930065223_f3_visibilidad_por_equipo.sql)
-- Encargo 20260930_lawang_equipos_venta_asistente. Escrita el 30-sep-2026.
--
-- CÓMO SE LANZA: TRES llamadas a execute_sql (MCP), una por TRAMO (la línea `select set_config(
-- 'f3.perfiles', …)` de abajo): 'gestores', 'resto:0' y 'resto:1'. Van por tramos porque la RLS
-- se evalúa de verdad para cada usuario (~1-2 s por usuario entre antes y después) y el MCP corta
-- a los ~60 s. 'gestores' = SM, PM y un super_admin: todos los casos de G, LAW-439, dinero,
-- cambio de equipo y paridad. 'resto:N' = agentes y admins en dos mitades: «nadie más cambia».
-- En cada llamada, la línea-marca MIGRACION_F3 (la que va sola entre dos líneas de «=») se
-- sustituye por el texto ÍNTEGRO de la migración (no una copia a mano: así prueba y migración
-- no se separan). Desde la raíz del repo de Lawang:
--   python -c "import re, sys, pathlib as p; sys.stdout.reconfigure(encoding='utf-8'); t=p.Path('contracts/sql/prueba_f3_visibilidad.sql').read_text(encoding='utf-8'); m=p.Path('supabase/migrations/20260930065223_f3_visibilidad_por_equipo.sql').read_text(encoding='utf-8'); print(re.sub(r'(?m)^-- @@MIGRACION_F3@@$', lambda _: m, t))"
-- Tras aplicar la migración, la misma prueba sin sustituir la marca comprueba el estado vivo
-- (la foto «antes» ya será la de después: los casos que comparan antes/después darán igual).
--
-- Acaba SIEMPRE en ROLLBACK. Corre cada perfil con el ROL REAL (`set local role authenticated`
-- + claims): el MCP corre como postgres (bypassrls) y sin cambiar de rol ninguna policy cuenta.
-- Sin correos ni uids en el fichero (el repo de Lawang es público): las personas se eligen por
-- estructura y la salida solo muestra el prefijo del correo.
--
-- Perfiles:
--   G  = el sales_manager que manda el equipo activo con más ventas congeladas (hoy, Gus).
--        Se le vacían los proyectos_supervisados DESPUÉS de la migración: lo que vea es por equipo.
--   V  = el manager (sales_manager) de otro equipo activo, para el cambio de equipo.
--   Todos los usuarios: foto antes/después de los ids visibles en contratos, clients y facturas.
--
-- RESULTADO 30-sep-2026 (sin aplicar; tres tramos, todo ROLLBACK, producción comprobada intacta):
--   gestores: casos 0-11 en verde. G: 52 ventas de su equipo en 7 proyectos (26 fuera de sus
--   supervisados), las ve todas con PDF, 17 compradores y 71 documentos; de 51 ventas de otro
--   equipo/sin equipo en sus proyectos veía 51 y ahora 0; facturas sin contrato 3 → 0. Cambio de
--   equipo: el SM viejo ve la venta, el nuevo no. Paridad 91/91 con _venta_congela_equipo.
--   Huella de dinero idéntica. resto:0 11 usuarios y resto:1 15 usuarios: ninguno cambia (el
--   tramo resto:1 se pasó con los helpers y la policy de contratos, no con el fichero entero:
--   vale para contratos/clients/facturas, que es lo que compara). El caso 12 (avisos) se añadió
--   después y se probó aparte, en su propio rollback: 1 / 0 / 1.
--   Coste medido con la puerta final (count(*) con RLS, un agente): contratos ~170 → ~240 ms;
--   facturas no se volvió a medir tras poner en línea documento_visible (antes de eso, ~510 → ~740).
-- RESULTADO 30-sep-2026 (tarde, contra la base con F2 y F4 ya aplicadas, ANTES de aplicar F3; ROLLBACK):
--   gestores: casos 0-12 en verde. G: 52 ventas de su equipo en 7 proyectos (26 fuera de sus
--   supervisados), las ve todas con PDF (antes 25), 17 compradores, 71 documentos; ventas de otro
--   equipo en sus proyectos 51 → 0; facturas sin contrato 3 → 0; 4 no-SM iguales; 3 PM iguales;
--   cambio de equipo verde; paridad 90/90; huella de dinero igual; avisos 1/0/1. resto:0 (11) y
--   resto:1 (15) sin cambios (helpers + policy de contratos). F3 aplicada después como
--   20260930065223 por orden del owner.
-- =====================================================================================
begin;
select set_config('f3.perfiles', 'gestores', true);   -- TRAMO: 'gestores' | 'resto:0' | 'resto:1'

create temporary table _f3(orden int, caso text, ok boolean, detalle text) on commit drop;
create temporary table _foto(fase text, uid uuid, pref text, rol text, activo boolean,
  contratos uuid[], clientes uuid[], facturas uuid[], pdf uuid[]) on commit drop;
grant all on _f3, _foto to authenticated;

-- ── perfiles G y V, elegidos por estructura ──
do $$
declare g record; v record;
begin
  select ev.id eq, u.user_id, u.email, coalesce(u.proyectos_supervisados, '{}') sup into g
    from public.equipos_venta ev
    join public.usuarios u on lower(u.email) = lower(ev.manager_email)
   where ev.activo and u.activo and u.rol = 'sales_manager'
   order by (select count(*) from public.contrato_closer k
              where k.equipo_id = ev.id and k.equipo_congelado_en is not null) desc
   limit 1;
  select ev.id eq, u.user_id, u.email into v
    from public.equipos_venta ev
    join public.usuarios u on lower(u.email) = lower(ev.manager_email)
   where ev.activo and u.activo and u.rol = 'sales_manager' and ev.id <> g.eq
   limit 1;
  perform set_config('f3.g_sub', g.user_id::text, true);
  perform set_config('f3.g_email', g.email, true);
  perform set_config('f3.g_eq', g.eq::text, true);
  perform set_config('f3.g_sup', g.sup::text, true);
  perform set_config('f3.v_sub', v.user_id::text, true);
  perform set_config('f3.v_email', v.email, true);
  perform set_config('f3.v_eq', v.eq::text, true);
end $$;

-- ── foto de lo que ve cada usuario (con su rol real) ──
-- La foto del PDF recorre TODOS los contratos (la lista se saca como postgres, antes de cambiar de
-- rol) y agente_ve_contrato_pdf decide con las claims de cada usuario.
create function pg_temp.f3_foto(p_fase text) returns void language plpgsql as $$
declare u record; v_todos uuid[];
begin
  execute 'reset role';
  select array_agg(id order by id) into v_todos from public.contratos;
  for u in select x.user_id, x.email, x.rol, x.activo from public.usuarios x
            where x.user_id is not null and x.email is not null
              and ((current_setting('f3.perfiles') = 'gestores'
                    and (x.rol in ('sales_manager', 'project_manager')
                         or x.user_id = (select s.user_id from public.usuarios s
                                          where s.activo and s.rol = 'super_admin' order by s.user_id limit 1)))
                or (current_setting('f3.perfiles') like 'resto:%'
                    and x.rol not in ('sales_manager', 'project_manager')
                    and abs(hashtext(x.user_id::text)) % 2 = nullif(regexp_replace(current_setting('f3.perfiles'), '\D', '', 'g'), '')::int))
  loop
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u.user_id::text, true);
    perform set_config('request.jwt.claim.email', u.email, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u.user_id, 'email', u.email,
            'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    insert into _foto values (p_fase, u.user_id, split_part(u.email, '@', 1), u.rol, u.activo,
      (select coalesce(array_agg(id order by id), '{}') from public.contratos),
      (select coalesce(array_agg(id order by id), '{}') from public.clients),
      (select coalesce(array_agg(id order by id), '{}') from public.facturas),
      case when u.user_id::text in (current_setting('f3.g_sub'), current_setting('f3.v_sub')) then
        (select coalesce(array_agg(x order by x), '{}') from unnest(v_todos) x
          where public.agente_ve_contrato_pdf('pendientes/' || x::text || '.html'))
      end);
  end loop;
  execute 'reset role';
end $$;
grant execute on function pg_temp.f3_foto(text) to authenticated;

-- ── huella de dinero vista por admin (antes) ──
create function pg_temp.f3_huella() returns text language plpgsql as $$
declare a record; h text;
begin
  execute 'reset role';
  select user_id, email into a from public.usuarios where activo and rol = 'super_admin' limit 1;
  perform set_config('request.jwt.claim.sub', a.user_id::text, true);
  perform set_config('request.jwt.claim.email', a.email, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.user_id, 'email', a.email,
          'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select md5(coalesce((select string_agg(factura_id::text || ':' || pendiente::text, ',' order by factura_id)
                         from public.facturas_pendiente_equipo()), '') || '|' ||
             coalesce((select string_agg(contrato_id::text || ':' || coalesce(cobrado::text, 'null'), ',' order by contrato_id)
                         from public.contratos_cobrado_equipo()), '')) into h;
  execute 'reset role';
  return h;
end $$;
grant execute on function pg_temp.f3_huella() to authenticated;

select set_config('f3.huella_antes', pg_temp.f3_huella(), true);
select pg_temp.f3_foto('antes');

-- =====================================================================================
-- @@MIGRACION_F3@@
-- =====================================================================================

reset role;
-- G sin supervisión por proyecto: lo que vea a partir de aquí es por equipo.
update public.usuarios set proyectos_supervisados = '{}' where user_id = current_setting('f3.g_sub')::uuid;
select pg_temp.f3_foto('despues');

-- ── casos ──
do $$
declare
  g uuid := current_setting('f3.g_sub')::uuid;
  t uuid := current_setting('f3.g_eq')::uuid;
  sup uuid[] := current_setting('f3.g_sup')::uuid[];
  ga _foto; gd _foto;
  v_eq uuid[]; v_neg uuid[]; n int; n2 int; n3 int; np int; d text;
begin
  select * into ga from _foto where fase = 'antes' and uid = g;
  select * into gd from _foto where fase = 'despues' and uid = g;
  if ga.uid is not null then

  -- C0 canario: el cambio de rol y las claims surten efecto
  perform set_config('request.jwt.claim.sub', g::text, true);
  perform set_config('request.jwt.claim.email', current_setting('f3.g_email'), true);
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'email', current_setting('f3.g_email'),
          'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into _f3 values (0, 'C0 canario: rol y claims', current_user = 'authenticated' and auth.uid() = g
    and not public.es_admin(), 'current_user=' || current_user);
  execute 'reset role';

  -- ventas del equipo de G (raíz e hijos), por el mismo ancla que el motor
  select coalesce(array_agg(c.id), '{}') into v_eq from public.contratos c where public._venta_equipo(c.id) = t;
  select count(distinct c.proyecto_id) into np from public.contratos c where c.id = any(v_eq);
  select count(*) into n from unnest(v_eq) x where x = any(gd.contratos);
  select count(*) into n2 from unnest(v_eq) x where x = any(gd.pdf);
  select count(*) into n3 from public.contratos c where c.id = any(v_eq) and not (c.proyecto_id = any(sup));
  insert into _f3 values (1, 'G sin supervisados ve contratos y PDF de TODAS las ventas de su equipo',
    cardinality(v_eq) > 0 and n = cardinality(v_eq) and n2 = cardinality(v_eq),
    format('ventas equipo %s (en %s proyectos, %s fuera de sus supervisados) · ve %s · PDF %s · antes veía %s',
      cardinality(v_eq), np, n3, n, n2,
      (select count(*) from unnest(v_eq) x where x = any(ga.contratos))));

  -- compradores de esas ventas
  select count(distinct cc.client_id), count(distinct cc.client_id) filter (where cc.client_id = any(gd.clientes))
    into n, n2 from public.contrato_compradores cc where cc.contrato_id = any(v_eq);
  insert into _f3 values (2, 'G ve a los compradores de las ventas de su equipo', n > 0 and n = n2,
    format('compradores %s · ve %s', n, n2));

  -- facturas y recibís de esas ventas
  select count(*), count(*) filter (where f.id = any(gd.facturas)) into n, n2
    from public.facturas f where f.contrato_id = any(v_eq);
  insert into _f3 values (3, 'G ve las facturas/recibís de las ventas de su equipo', n = n2,
    format('documentos %s · ve %s', n, n2));

  -- ventas de OTRO equipo (o sin equipo) en los proyectos que supervisaba, no escritas por él
  select coalesce(array_agg(c.id), '{}') into v_neg
    from public.contratos c
   where c.proyecto_id = any(sup)
     and public._venta_equipo(c.id) is distinct from t
     and lower(coalesce(c.creado_por, '')) <> lower(current_setting('f3.g_email'));
  select count(*) into n from unnest(v_neg) x where x = any(ga.contratos);
  select count(*) into n2 from unnest(v_neg) x where x = any(gd.contratos);
  select count(*) into n3 from unnest(v_neg) x where x = any(gd.pdf);
  insert into _f3 values (4, 'G ya NO ve ventas de otro equipo en «sus» proyectos (ni su PDF)',
    n > 0 and n2 = 0 and n3 = 0,
    format('ventas ajenas en sus proyectos %s · antes veía %s · ahora %s · PDF ahora %s',
      cardinality(v_neg), n, n2, n3));

  -- facturas sin contrato de sus proyectos: antes sí, ahora no (solo PM)
  select count(*) filter (where f.id = any(ga.facturas)), count(*) filter (where f.id = any(gd.facturas)) into n, n2
    from public.facturas f
   where f.contrato_id is null and f.proyecto_id = any(sup)
     and lower(coalesce(f.creado_por, '')) <> lower(current_setting('f3.g_email'));
  insert into _f3 values (5, 'G ya no ve facturas SIN contrato de sus proyectos (solo PM)', n2 = 0,
    format('antes %s · ahora %s', n, n2));
  end if;

  -- todos los que no son sales_manager: idénticos (agente, PM, admin, closers…)
  select count(*), string_agg(a.pref || '(' || a.rol || ')', ', ') filter (where
           a.contratos <> d2.contratos or a.clientes <> d2.clientes or a.facturas <> d2.facturas)
    into n, d
    from _foto a join _foto d2 on d2.uid = a.uid and d2.fase = 'despues'
   where a.fase = 'antes' and a.rol <> 'sales_manager';
  insert into _f3 values (6, 'Nadie que no sea sales_manager cambia lo que ve (agentes, PM, admin)', d is null,
    format('%s usuarios comparados · distintos: %s', n, coalesce(d, 'ninguno')));

  -- PM sigue viendo por proyecto (explícito)
  select count(*), count(*) filter (where cardinality(d2.contratos) > 0)
    into n, n2
    from _foto a join _foto d2 on d2.uid = a.uid and d2.fase = 'despues'
   where a.fase = 'antes' and a.rol = 'project_manager' and a.contratos = d2.contratos;
  if exists (select 1 from _foto where fase = 'antes' and rol = 'project_manager') then
    insert into _f3 values (7, 'PM: mismo conjunto antes y después', n = (select count(*) from _foto where fase = 'antes' and rol = 'project_manager'),
      format('%s PM iguales (%s con contratos visibles)', n, n2));
  end if;

  -- admin ve todo
  select count(*) into n from _foto d2 where d2.fase = 'despues' and d2.activo and d2.rol in ('admin', 'super_admin')
     and cardinality(d2.contratos) <> (select count(*) from public.contratos);
  insert into _f3 values (8, 'Admin activo ve todos los contratos', n = 0, format('admins que no ven todo: %s', n));

  -- huella de dinero
  insert into _f3 values (9, 'Huella de dinero (facturas_pendiente_equipo + contratos_cobrado_equipo, admin) idéntica',
    current_setting('f3.huella_antes') = pg_temp.f3_huella(), 'md5 antes = después');
end $$;

-- ── closer que cambia de equipo: el SM viejo ve lo viejo, el nuevo no ──
reset role;
do $$
declare
  t uuid := current_setting('f3.g_eq')::uuid;
  t2 uuid := current_setting('f3.v_eq')::uuid;
  k record; v_ok_g boolean; v_ok_v boolean; v_eq_desp uuid;
begin
  select cc.contrato_id, cc.closer_email into k
    from public.contrato_closer cc join public.contratos c on c.id = cc.contrato_id
   where cc.equipo_id = t and cc.equipo_congelado_en is not null and c.contrato_padre_id is null
     and lower(coalesce(c.creado_por, '')) not in (lower(current_setting('f3.g_email')), lower(current_setting('f3.v_email')))
     and exists (select 1 from public.equipo_miembros em where em.equipo_id = t
                   and lower(em.closer_email) = lower(cc.closer_email) and em.hasta is null)
   limit 1;
  if current_setting('f3.perfiles') <> 'gestores' then return; end if;
  if k.contrato_id is null then
    insert into _f3 values (10, 'Closer que cambia de equipo', null, 'sin venta congelada de un miembro activo del equipo de G');
    return;
  end if;
  -- traslado: sale del equipo de G ayer, entra en el de V hoy
  update public.equipo_miembros em set hasta = current_date - 1
   where em.equipo_id = t and lower(em.closer_email) = lower(k.closer_email) and em.hasta is null;
  insert into public.equipo_miembros (equipo_id, closer_email, desde, added_by)
  values (t2, k.closer_email, current_date, 'prueba_f3');
  select equipo_id into v_eq_desp from public.contrato_closer where contrato_id = k.contrato_id;

  perform set_config('request.jwt.claim.sub', current_setting('f3.g_sub'), true);
  perform set_config('request.jwt.claim.email', current_setting('f3.g_email'), true);
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('f3.g_sub'),
          'email', current_setting('f3.g_email'), 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_ok_g := exists (select 1 from public.contratos where id = k.contrato_id);
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', current_setting('f3.v_sub'), true);
  perform set_config('request.jwt.claim.email', current_setting('f3.v_email'), true);
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('f3.v_sub'),
          'email', current_setting('f3.v_email'), 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_ok_v := exists (select 1 from public.contratos where id = k.contrato_id);
  execute 'reset role';
  insert into _f3 values (10, 'Closer que cambia de equipo: su venta vieja la ve el SM viejo y NO el nuevo',
    v_ok_g and not v_ok_v and v_eq_desp = t,
    format('SM viejo ve %s · SM nuevo ve %s · equipo congelado sigue en el viejo %s', v_ok_g, v_ok_v, v_eq_desp = t));
end $$;

-- ── paridad: el ancla de la visibilidad = el del congelado (_venta_congela_equipo tras F2) ──
reset role;
do $$
declare r record; n int := 0; malos int := 0;
begin
  if current_setting('f3.perfiles') <> 'gestores' then return; end if;
  create temporary table _pre on commit drop as
    select k.contrato_id, public._venta_equipo(k.contrato_id) eq
      from public.contrato_closer k join public.contratos c on c.id = k.contrato_id
     where k.equipo_congelado_en is null and c.contrato_padre_id is null;
  for r in select contrato_id from _pre loop
    perform public._venta_congela_equipo(r.contrato_id);
  end loop;
  select count(*), count(*) filter (where k.equipo_id is distinct from p.eq) into n, malos
    from _pre p join public.contrato_closer k on k.contrato_id = p.contrato_id;
  insert into _f3 values (11, 'Paridad: equipo de la visibilidad (sin congelar) = el que congelaría _venta_congela_equipo',
    malos = 0, format('%s ventas sin congelar comparadas · distintas %s', n, malos));
end $$;

-- ── avisos (_avisar_managers): el SM recibe los de SU equipo, no los de otro; sin contrato, por proyecto ──
reset role;
do $$
declare g record; c_mio uuid; c_ajeno record; n1 int; n2 int; n3 int;
begin
  if current_setting('f3.perfiles') <> 'gestores' then return; end if;
  select u.email, u.proyectos into g from public.usuarios u where u.user_id = current_setting('f3.g_sub')::uuid;
  select c.id into c_mio from public.contratos c
   where public._venta_equipo(c.id) = current_setting('f3.g_eq')::uuid and c.proyecto_id is not null limit 1;
  select c.id, c.proyecto_id into c_ajeno from public.contratos c
   where c.proyecto_id = any(g.proyectos) and public._venta_equipo(c.id) is distinct from current_setting('f3.g_eq')::uuid limit 1;
  perform public._avisar_managers((select proyecto_id from public.contratos where id = c_mio), 'prueba_f3', 'x', 'x', '/', c_mio);
  perform public._avisar_managers(c_ajeno.proyecto_id, 'prueba_f3', 'y', 'y', '/', c_ajeno.id);
  perform public._avisar_managers(c_ajeno.proyecto_id, 'prueba_f3', 'z', 'z', '/', null);
  select count(*) filter (where titulo = 'x'), count(*) filter (where titulo = 'y'), count(*) filter (where titulo = 'z')
    into n1, n2, n3 from public.notificaciones where tipo = 'prueba_f3' and lower(destinatario) = lower(g.email);
  insert into _f3 values (12, 'Avisos: G recibe el de una venta de su equipo, no el de otro equipo en su proyecto; el de unidad (sin contrato) sí',
    n1 = 1 and n2 = 0 and n3 = 1, format('su equipo %s · otro equipo %s · sin contrato %s', n1, n2, n3));
end $$;

-- ── LAW-439: managers sin equipo, hoy vs tras F3 ──
insert into _f3
select 100 + row_number() over (order by a.pref)::int,
       'LAW-439 ' || a.pref || ' (' || a.rol || case when a.activo then '' else ', INACTIVO' end || ')',
       null,
       format('hoy %s contratos → tras F3 %s · pierde %s (propios que conserva %s) · clientes %s→%s · facturas %s→%s',
         cardinality(a.contratos), cardinality(d.contratos),
         (select count(*) from unnest(a.contratos) x where not x = any(d.contratos)),
         (select count(*) from public.contratos c where c.id = any(d.contratos)
             and lower(coalesce(c.creado_por, '')) = lower(u.email)),
         cardinality(a.clientes), cardinality(d.clientes), cardinality(a.facturas), cardinality(d.facturas))
  from _foto a
  join _foto d on d.uid = a.uid and d.fase = 'despues'
  join public.usuarios u on u.user_id = a.uid
 where a.fase = 'antes' and a.rol in ('sales_manager', 'project_manager')
   and not exists (select 1 from public.equipos_venta ev where ev.activo and lower(ev.manager_email) = lower(u.email));

-- y los dos SM con equipo, para contexto
insert into _f3
select 200 + row_number() over (order by a.pref)::int,
       'SM con equipo ' || a.pref, null,
       format('hoy %s contratos → tras F3 %s (gana %s, pierde %s)',
         cardinality(a.contratos), cardinality(d.contratos),
         (select count(*) from unnest(d.contratos) x where not x = any(a.contratos)),
         (select count(*) from unnest(a.contratos) x where not x = any(d.contratos)))
  from _foto a
  join _foto d on d.uid = a.uid and d.fase = 'despues'
  join public.usuarios u on u.user_id = a.uid
 where a.fase = 'antes' and a.rol = 'sales_manager'
   and exists (select 1 from public.equipos_venta ev where ev.activo and lower(ev.manager_email) = lower(u.email));

select orden, caso, ok, detalle from _f3 order by orden;
rollback;


-- #####################################################################################
-- PARTE 2 — AJUSTES DE F3 (supabase/migrations/20260930081209_f3_ajustes_visibilidad.sql y
-- 20260930081234_f3_ajustes_destructivo.sql). Escrita el 30-sep-2026. Se lanza SOLO este bloque
-- (desde «PARTE 2» hasta el final), en varias llamadas a execute_sql, una por TRAMO (la línea
-- `select set_config('f3aj.perfiles', …)`): '1-2', '3-4', '5-6', '7-8' = posiciones de la lista
-- de perfiles (los SM con equipo, el PM con más proyectos, el agente con más contratos, un admin
-- y un super_admin, en orden de rol y correo). Con la policy vieja cada perfil tarda ~10 s y el
-- MCP corta a ~60 s. Los casos 21-25 van en el tramo que empieza en 1. Acaba en ROLLBACK.
--
-- POR QUÉ NO SE APLICA LA MIGRACIÓN DENTRO DE LA PRUEBA (a diferencia de la parte 1): rehacer
-- policies coge un bloqueo exclusivo de contratos/facturas mientras dure la transacción, y esta
-- prueba tarda decenas de segundos: la intranet se quedaría sin poder leer. Por eso cada tabla se
-- mira de tres formas a la vez, sin tocar ninguna policy:
--   A = la policy VIEJA (la de F3, fila a fila con puede_ver_contrato / documento_visible /
--       cliente_visible), evaluada como postgres con las claims del usuario;
--   B = la policy NUEVA (con mis_contratos_visibles / mis_proyectos_supervisados), igual;
--   C = lo que devuelve de verdad la RLS viva con `set local role authenticated`.
-- Antes de aplicar: se antepone al bloque (tras el begin) la parte de FUNCIONES de las dos
-- migraciones (guardia, A, funciones de D, parches B y C, y E) — no toca policies — y se exige
-- A = B (C es aún la policy vieja, = A). Después de aplicar: el bloque tal cual; se exige
-- A = B = C (C ya es la policy nueva). Arrays ordenados por id: igualdad = diferencia simétrica vacía.
-- Casos:
--   20  paridad A = B = C por perfil y tabla (contratos, facturas, recibi_aplicaciones,
--       contrato_vencimientos, contrato_firmas, contrato_eventos, correos_enviados, clients,
--       documents), con el tiempo de C (count(*) con RLS, una pasada).
--   21  SM inactivo no ve: G con activo=false → _sm_ve_venta, puede_ver_contrato y
--       mis_contratos_visibles no le dan ninguna venta de su equipo.
--   22  JWT de agente sin fila en usuarios con el correo del manager: ya no ve el equipo.
--   23  crm_contrato_closer_set sobre una venta que V no ve → PT404; sobre una que ve → pasa la
--       puerta (PT409 por p_previo falso).
--   24  usuario_supervisa_proyecto asignando a un SM → 22023; a un PM → pasa.
--   25  contrato_visible ya no existe.
-- Sin correos ni uids en el fichero: los perfiles se eligen por estructura y la salida solo
-- muestra rol + prefijo del correo.
-- RESULTADO 30-sep-2026:
--   ANTES de aplicar (funciones antepuestas, policies sin tocar, ROLLBACK; tramos 1-2, 3-4, 5-6,
--   7-8): 72/72 paridades A = B = C en verde (8 perfiles × 9 tablas: 4 SM con equipo —Gus,
--   Victor, Carmen y el cuarto—, el PM con 12 proyectos, el usuario con más contratos —hoy un
--   sales_manager SIN equipo—, un admin y un super_admin); casos 21-25 en verde. Un primer intento aplicando la migración DENTRO de la
--   prueba cortó por tiempo (60 s) con bloqueo exclusivo sobre contratos/facturas: rollback
--   comprobado, producción intacta; de ahí el diseño A/B/C de arriba.
--   Aplicadas 20260930081209 y 20260930081234 (08:12 UTC). Huella de dinero
--   (comisiones_devengadas 10:90d2f4e0…, solicitudes_pago 9:c596a487…) igual antes y después;
--   0 filas nuevas. get_advisors: nada nuevo salvo el aviso esperado de EXECUTE a authenticated
--   en las dos funciones nuevas (las policies las necesitan).
--   DESPUÉS (tramos 1-2 y 3-8, ROLLBACK): 72/72 A = B = C con la RLS viva ya nueva; 21-25 verde.
--   Tiempos count(*) con RLS, antes → después (ms): SM facturas 630-750 → 13-29; SM contratos
--   ~230-270 → 12-15; SM contrato_vencimientos ~600-680 → 13-20; SM contrato_eventos ~1050-1290
--   → 13-15; PM facturas ~315-346 → 2; PM contratos ~170-196 → 2; SM sin equipo facturas ~530 → 2.
--   Aparte, el rol='agente' con más contratos (6 tablas, A = B = C en verde): contratos 246 → 2,
--   facturas 607 → 2, contrato_vencimientos 538 → 5, contrato_eventos 1083 → 2.
--   clients y documents siguen ~200-330 ms para SM/PM/agente: cliente_visible fila a fila, fuera de
--   este encargo (misma receta aplicable, con su propia semántica).
-- #####################################################################################
begin;
select set_config('f3aj.perfiles', '1-2', true);   -- TRAMO: '1-2' | '3-4' | '5-6' | '7-8'
create temporary table _aj(orden int, caso text, ok boolean, detalle text) on commit drop;
create temporary table _perfil(uid uuid, email text, pref text) on commit drop;
create temporary table _pred(tabla text, viejo text, nuevo text) on commit drop;
grant all on _aj, _perfil, _pred to authenticated;

insert into _perfil
select s.user_id, s.email, s.pref from (
  select u.user_id, u.email, u.rol || ':' || split_part(u.email, '@', 1) pref,
         row_number() over (order by u.rol, u.email) ord
    from public.usuarios u
   where u.activo and u.user_id is not null
     and ((u.rol = 'sales_manager' and exists (select 1 from public.equipos_venta ev
                                                 where ev.activo and lower(ev.manager_email) = lower(u.email)))
          or u.user_id in (
               (select x.user_id from public.usuarios x where x.activo and x.rol = 'project_manager'
                 order by cardinality(coalesce(x.proyectos_supervisados, '{}'::uuid[])) desc limit 1),
               (select x.user_id from public.usuarios x where x.activo and x.rol not in ('admin', 'super_admin')
                 order by (select count(*) from public.contratos c where c.creado_por = x.email) desc limit 1),
               (select x.user_id from public.usuarios x where x.activo and x.rol = 'admin' order by x.user_id limit 1),
               (select x.user_id from public.usuarios x where x.activo and x.rol = 'super_admin' order by x.user_id limit 1)))) s
 where s.ord between split_part(current_setting('f3aj.perfiles'), '-', 1)::int
                 and split_part(current_setting('f3aj.perfiles'), '-', 2)::int;

-- viejo = USING de F3 (20260930065223); nuevo = USING de 20260930081209. clients y documents no
-- cambian de policy: viejo = nuevo (lo que se mide es que A y E2 no les muevan nada).
insert into _pred values
 ('contratos',
  $p$public.puede_ver_contrato(id)$p$,
  $p$(select public.es_admin()) or ((select public.es_agente()) and (coalesce(creado_por = (select auth.email()), false) or id = any ((select public.mis_contratos_visibles())::uuid[])))$p$),
 ('facturas',
  $p$public.es_agente() and public.documento_visible(creado_por, proyecto_id, contrato_id)$p$,
  $p$(select public.es_agente()) and ((select public.es_admin()) or coalesce(creado_por = (select auth.email()), false) or proyecto_id = any ((select public.mis_proyectos_supervisados())::uuid[]) or contrato_id = any ((select public.mis_contratos_visibles())::uuid[]))$p$),
 ('recibi_aplicaciones',
  $p$public.es_agente() and exists (select 1 from public.facturas d where d.id = any (array[x.recibi_id, x.factura_id]) and public.documento_visible(d.creado_por, d.proyecto_id, d.contrato_id))$p$,
  $p$(select public.es_agente()) and exists (select 1 from public.facturas d where d.id = any (array[x.recibi_id, x.factura_id]) and ((select public.es_admin()) or coalesce(d.creado_por = (select auth.email()), false) or d.proyecto_id = any ((select public.mis_proyectos_supervisados())::uuid[]) or d.contrato_id = any ((select public.mis_contratos_visibles())::uuid[])))$p$),
 ('contrato_vencimientos',
  $p$public.es_agente() and public.puede_ver_contrato(contrato_id)$p$,
  $p$(select public.es_agente()) and contrato_id is not null and ((select public.es_admin()) or contrato_id = any ((select public.mis_contratos_visibles())::uuid[]))$p$),
 ('contrato_firmas',
  $p$public.es_agente() and public.puede_ver_contrato(contrato_id)$p$,
  $p$(select public.es_agente()) and contrato_id is not null and ((select public.es_admin()) or contrato_id = any ((select public.mis_contratos_visibles())::uuid[]))$p$),
 ('contrato_eventos',
  $p$public.es_super_admin() or (public.es_agente() and evento <> all (array['editado_estando_firmado', 'desbloqueado_estando_firmado', 'factura_sin_bloquear', 'cobro_a_factura_huerfana', 'cobro_a_otro_comprador', 'comprador_sin_ficha']::text[]) and public.puede_ver_contrato(contrato_id))$p$,
  $p$(select public.es_super_admin()) or ((select public.es_agente()) and evento <> all (array['editado_estando_firmado', 'desbloqueado_estando_firmado', 'factura_sin_bloquear', 'cobro_a_factura_huerfana', 'cobro_a_otro_comprador', 'comprador_sin_ficha']::text[]) and contrato_id is not null and ((select public.es_admin()) or contrato_id = any ((select public.mis_contratos_visibles())::uuid[])))$p$),
 ('correos_enviados',
  $p$public.es_agente() and (public.es_admin() or coalesce(enviado_por = (select auth.email()), false) or public.puede_ver_contrato(contrato_id))$p$,
  $p$(select public.es_agente()) and ((select public.es_admin()) or coalesce(enviado_por = (select auth.email()), false) or contrato_id = any ((select public.mis_contratos_visibles())::uuid[]))$p$),
 ('clients',
  $p$public.es_agente() and public.cliente_visible(propietario, id)$p$,
  $p$public.es_agente() and public.cliente_visible(propietario, id)$p$),
 ('documents',
  $p$public.es_agente() and retirado_el is null and exists (select 1 from public.clients c where c.id = x.client_id and public.cliente_visible(c.propietario, c.id))$p$,
  $p$public.es_agente() and retirado_el is null and exists (select 1 from public.clients c where c.id = x.client_id and public.cliente_visible(c.propietario, c.id))$p$);

create function pg_temp.aj_claims(p_uid uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('request.jwt.claim.email', p_email, true);
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'email', p_email, 'role', 'authenticated')::text, true);
end $$;
grant execute on function pg_temp.aj_claims(uuid, text) to authenticated;

do $$
declare u record; p record; a text[]; b text[]; c text[]; t0 timestamptz; ms numeric; n bigint;
begin
  for u in select * from _perfil order by pref loop
    for p in select * from _pred loop
      execute 'reset role';
      perform pg_temp.aj_claims(u.uid, u.email);
      execute format('select coalesce(array_agg(x.id::text order by x.id), ''{}'') from public.%I x where %s', p.tabla, p.viejo) into a;
      execute format('select coalesce(array_agg(x.id::text order by x.id), ''{}'') from public.%I x where %s', p.tabla, p.nuevo) into b;
      execute 'set local role authenticated';
      execute format('select coalesce(array_agg(x.id::text order by x.id), ''{}'') from public.%I x', p.tabla) into c;
      t0 := clock_timestamp();
      execute format('select count(*) from public.%I', p.tabla) into n;
      ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
      execute 'reset role';
      insert into _aj values (20, 'Paridad ' || u.pref || ' · ' || p.tabla,
        a = b and a = c,
        format('vieja %s · nueva %s · RLS viva %s filas · %s ms', cardinality(a), cardinality(b), cardinality(c), ms));
    end loop;
  end loop;
  execute 'reset role';
end $$;

-- 21-25 · casos de A, B, C y E1 (solo en el tramo que empieza en 1)
do $$
declare g record; v record; pm record; sa record; c_g uuid; c_v uuid; v_proy uuid; e text;
begin
  if split_part(current_setting('f3aj.perfiles'), '-', 1) <> '1' then return; end if;
  execute 'reset role';
  select ev.id eq, u.user_id, u.email into g
    from public.equipos_venta ev join public.usuarios u on lower(u.email) = lower(ev.manager_email)
   where ev.activo and u.activo and u.rol = 'sales_manager'
   order by (select count(*) from public.contrato_closer k where k.equipo_id = ev.id and k.equipo_congelado_en is not null) desc
   limit 1;
  select ev.id eq, u.user_id, u.email into v
    from public.equipos_venta ev join public.usuarios u on lower(u.email) = lower(ev.manager_email)
   where ev.activo and u.activo and u.rol = 'sales_manager' and ev.id <> g.eq
   order by u.user_id limit 1;
  select user_id, email into pm from public.usuarios where activo and rol = 'project_manager' order by user_id limit 1;
  select user_id, email into sa from public.usuarios where activo and rol = 'super_admin' order by user_id limit 1;
  select id into v_proy from public.proyectos order by id limit 1;
  -- una venta del equipo de G que ni G ni V firmaron como autores
  select c.id into c_g from public.contratos c
   where public._venta_equipo(c.id) = g.eq
     and lower(coalesce(c.creado_por, '')) not in (lower(g.email), lower(v.email))
   order by c.id limit 1;
  select c.id into c_v from public.contratos c where public._venta_equipo(c.id) = v.eq order by c.id limit 1;

  -- 21 · G inactivo (las funciones DEFINER se llaman como postgres con las claims de G)
  update public.usuarios set activo = false where user_id = g.user_id;
  perform pg_temp.aj_claims(g.user_id, g.email);
  insert into _aj values (21, 'SM inactivo no ve las ventas de su equipo',
    c_g is not null and not public._sm_ve_venta(c_g) and not public.puede_ver_contrato(c_g)
      and not (c_g = any (public.mis_contratos_visibles())),
    format('_sm_ve_venta=%s puede_ver=%s en_mis=%s', public._sm_ve_venta(c_g), public.puede_ver_contrato(c_g),
           c_g = any (public.mis_contratos_visibles())));
  update public.usuarios set activo = true where user_id = g.user_id;

  -- 22 · JWT de agente sin fila en usuarios, con el correo de G
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000f3a', true);
  perform set_config('request.jwt.claim.email', g.email, true);
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-4000-8000-000000000f3a', 'email', g.email,
          'role', 'authenticated', 'app_metadata', json_build_object('agente', true))::text, true);
  insert into _aj values (22, 'JWT de agente sin fila activa con el correo del manager: no ve el equipo',
    public.es_agente() and not public._sm_ve_venta(c_g) and not public.puede_ver_contrato(c_g)
      and not (c_g = any (public.mis_contratos_visibles())),
    format('es_agente=%s puede_ver=%s', public.es_agente(), public.puede_ver_contrato(c_g)));

  -- 23 · crm_contrato_closer_set, con V como usuario con la herramienta «ranking»
  perform pg_temp.aj_claims(sa.user_id, sa.email);   -- el trigger de usuarios solo deja tocar herramientas a un super_admin
  update public.usuarios set herramientas = array_append(coalesce(herramientas, '{}'), 'ranking') where user_id = v.user_id;
  perform pg_temp.aj_claims(v.user_id, v.email);
  execute 'set local role authenticated';
  begin
    perform public.crm_contrato_closer_set(c_g, null, 'previo-falso');
    e := 'sin error';
  exception when others then e := sqlstate;
  end;
  begin
    perform public.crm_contrato_closer_set(c_v, null, 'previo-falso');
    e := e || ' / sin error';
  exception when others then e := e || ' / ' || sqlstate;
  end;
  execute 'reset role';
  insert into _aj values (23, 'crm_contrato_closer_set: venta no visible → PT404; visible → pasa la puerta (PT409)',
    e = 'PT404 / PT409', e);

  -- 24 · usuario_supervisa_proyecto (como super_admin)
  perform pg_temp.aj_claims(sa.user_id, sa.email);
  execute 'set local role authenticated';
  begin
    perform public.usuario_supervisa_proyecto(g.user_id, v_proy, true);
    e := 'sin error';
  exception when others then e := sqlstate;
  end;
  begin
    perform public.usuario_supervisa_proyecto(pm.user_id, v_proy, true);
    e := e || ' / ok';
  exception when others then e := e || ' / ' || sqlstate;
  end;
  execute 'reset role';
  insert into _aj values (24, 'supervisa: a un SM → 22023; a un PM → pasa', e = '22023 / ok', e);

  -- 25 · contrato_visible borrada
  insert into _aj values (25, 'contrato_visible ya no existe',
    to_regprocedure('public.contrato_visible(text,uuid)') is null,
    coalesce(to_regprocedure('public.contrato_visible(text,uuid)')::text, 'borrada'));
end $$;

reset role;
select orden, caso, ok, detalle from _aj order by orden, caso;
rollback;
