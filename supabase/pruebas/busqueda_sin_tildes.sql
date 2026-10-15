-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Prueba de BUSQUEDA SIN TILDES (15-oct-2026, owner: «que no haga falta poner la tilde en los buscadores de Lawang y en todo lo que hagamos»),
-- migracion 20261015130000_busqueda_sin_tildes. Rol REAL: cada llamada va con `set local role authenticated` (o anon) y los claims de la
-- persona (pg_temp.val). Un caso que ENTRA por cada caso que se NIEGA.
--
-- !! SOLO EN RAMA: monta empresa, proyecto, personas, fichas y contratos, y apaga los disparadores de usuario de `contratos` dentro de
--    la transaccion (la prueba mide la busqueda, no el alta: sin numeracion gastada ni comisiones, unidades o avisos arrastrados).
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261015130000_busqueda_sin_tildes.sql --prueba busqueda_sin_tildes.sql
--    Fuera de una rama (sin `erp.en_rama = si`, que pone rama_prueba) se niega a empezar, antes de tocar nada.
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada linea acaba en «→ ok» o «→ FALLA». Todo se deshace con el raise final.
-- La tabla de casos (T) la GENERA el estudio desde contracts/busqueda_casos.json, la misma que prueba el navegador en
-- contracts/busqueda.test.js (que falla si aqui falta un caso): las dos capas aplican EL MISMO algoritmo y se prueban con la misma tabla.
-- FIXTURE PROPIO (la rama recibe solo la estructura), como postgres y SIN sesion (asi pasa el candado de alta de `usuarios`):
--   empresa zz_busca y su proyecto; un super_admin global; dos agentes ACOTADOS a esa empresa (como los reales); una persona en auth.users
--   sin fila en usuarios (no es del equipo); la ficha de A «ZZ-BUSCA José María Muñoz» y la de B «ZZ-BUSCA Siobhán O’Brien»; tres contratos
--   del proyecto: dos de A (uno con la copia del nombre DISTINTA de su ficha, como 46 del vivo el 15-oct) y uno de B.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create temp table _tp (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_rol, 'email', p_email)::text, true);
  execute format('set local role %I', p_rol);
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(t, 'null');
end $f$;
create or replace function pg_temp.err(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then substr(t, 4, 5) end $f$;
create or replace function pg_temp.e(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then left(t, 110) else t end $f$;

insert into _tp values ('jv', gen_random_uuid(), 'zz-busca-super@prueba.invalid'),
                       ('A',  gen_random_uuid(), 'zz-busca-agente-a@prueba.invalid'),
                       ('B',  gen_random_uuid(), 'zz-busca-agente-b@prueba.invalid'),
                       ('X',  gen_random_uuid(), 'zz-busca-fuera@prueba.invalid');   -- en auth.users, sin fila en usuarios

do $todo$
declare
  r text := ''; rp text := ''; v text; v2 text; n bigint; g boolean; x record;
  jv _tp; a _tp; b _tp; fx _tp;
  pL uuid; cA uuid; cB uuid; kA1 uuid; kA2 uuid; kB1 uuid; kA3 uuid;
  c_emp constant text := 'zz_busca';
  c_fin constant text := 'FIN DE PRUEBAS BUSQUEDA SIN TILDES (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS BUSQUEDA SIN TILDES:%', E'\nP0 esta prueba apaga disparadores de contratos y monta filas: solo corre en rama → FALLA';
  end if;
  select * into jv from _tp where et = 'jv'; select * into a from _tp where et = 'A';
  select * into b from _tp where et = 'B';  select * into fx from _tp where et = 'X';

  -- ============================================================ T. la tabla de casos (navegador = servidor)
  for x in select * from (values
    ('José', 'jose'),
    ('JOSÉ MARÍA', 'jose maria'),
    ('MUÑOZ', 'munoz'),
    ('  Ubud  ', 'ubud'),
    ('Balí', 'bali'),
    ('Ødegaard', 'odegaard'),
    ('Strauß', 'strauss'),
    ('Guðrún', 'gudrun'),
    ('Þór', 'thor'),
    ('Yıldız', 'yildiz'),
    ('İSTANBUL', 'istanbul'),
    ('Łódź', 'lodz'),
    ('Ærø', 'aero'),
    ('Œuvre', 'oeuvre'),
    ('Müller', 'muller'),
    ('José', 'jose'),
    ('O''Brien', 'obrien'),
    ('O’Brien', 'obrien'),
    ('D’Souza', 'dsouza'),
    ('Jum’at', 'jumat'),
    ('Col·lell', 'collell'),
    ('Juan · María', 'juan maria'),
    ('Jean-Luc', 'jean luc'),
    ('Jean — Luc', 'jean luc'),
    ('I Gusti  Ngurah', 'i gusti ngurah'),
    ('Mª José', 'ma jose'),
    ('CC-0109', 'cc 0109'),
    ('', ''),
    (null, '')
  ) v(entrada, esperado) loop
    r := r || pg_temp.l(public.normaliza_busqueda(x.entrada) = x.esperado,
                        'T normaliza «' || coalesce(x.entrada, '<null>') || '» -> [' || coalesce(public.normaliza_busqueda(x.entrada), '<null>') || '] esp [' || x.esperado || ']');
  end loop;
  for x in select * from (values
    ('José', 'jose', true),
    ('José', 'JOSÉ', true),
    ('Jose', 'José', true),
    ('Muñoz', 'munoz', true),
    ('Muñoz', 'muñoz', true),
    ('Munoz', 'muñoz', true),
    ('Ubud', 'ubud', true),
    ('O''Brien', 'obrien', true),
    ('O’Brien', 'o''brien', true),
    ('Jean-Luc', 'jean luc', true),
    ('Jean-Luc', 'jean-luc', true),
    ('Müller', 'muller', true),
    ('Müller', 'mueller', false),
    ('İSTANBUL', 'istanbul', true),
    ('Yıldız', 'yildiz', true),
    ('Strauß', 'strauss', true),
    ('Guðrún', 'gudrun', true),
    ('José', 'jose', true),
    ('Col·lell', 'collell', true),
    ('I Gusti  Ngurah', 'gusti ngurah', true),
    ('Jum’at', 'jumat', true),
    ('año', 'ano', true),
    ('María García López', 'maria lopez', false),
    ('I Wayan Sudarma', 'sudarma wayan', false),
    ('Ubud', '', true),
    ('Ubud', '   ', true),
    ('', 'ubud', false)
  ) v(texto, aguja, casa) loop
    r := r || pg_temp.l((public.normaliza_busqueda(x.aguja) = '' or strpos(public.normaliza_busqueda(x.texto), public.normaliza_busqueda(x.aguja)) > 0) = x.casa,
                        'T busca «' || x.aguja || '» en «' || x.texto || '» = ' || x.casa);
  end loop;

  -- ============================================================ N. como nacen: inmutable la que pliega, INVOKER las que leen, cerradas a anon
  for x in select p.proname, p.provolatile, p.prosecdef, p.proconfig,
                  has_function_privilege('anon', p.oid, 'execute') anon, has_function_privilege('authenticated', p.oid, 'execute') auth,
                  has_function_privilege('public', p.oid, 'execute') pub
             from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('normaliza_busqueda','contratos_busca','clientes_busca') loop
    r := r || pg_temp.l(x.proconfig @> array['search_path=""']::text[] and not x.anon and not x.pub and x.auth and not x.prosecdef
                        and (x.proname <> 'normaliza_busqueda' or x.provolatile = 'i'),
                        'N ' || x.proname || ' volatil=' || x.provolatile || ' definer=' || x.prosecdef || ' anon=' || x.anon || ' public=' || x.pub || ' authenticated=' || x.auth);
  end loop;
  select count(*) into n from pg_proc where pronamespace = 'public'::regnamespace and proname in ('normaliza_busqueda','contratos_busca','clientes_busca');
  r := r || pg_temp.l(n = 3, 'N existen las 3 funciones nuevas [' || n || ']');
  r := r || pg_temp.l(char_length(public.normaliza_busqueda(repeat('a', 5000))) = 1000,
                      'N la pieza corta su entrada a 1.000 caracteres (se puede llamar por la API: excepcion en seguridad_2026 §7)');
  v := pg_get_functiondef('public.comprador_buscar(text)'::regprocedure);
  r := r || pg_temp.l((select prosecdef from pg_proc where oid = 'public.comprador_buscar(text)'::regprocedure) and v ~ 'normaliza_busqueda' and v !~* 'ilike',
                      'N comprador_buscar sigue DEFINER, compara con normaliza_busqueda y sin ilike');
  v := pg_get_functiondef('public.contratos_busca(text)'::regprocedure);
  r := r || pg_temp.l(v ~* 'limit 10' and v !~* 'ilike', 'N contratos_busca devuelve como mucho 10 y no usa ilike');

  -- ============================================================ P. montaje del fixture propio (como postgres, SIN sesion)
  perform set_config('request.jwt.claims', '', true);
  begin
    insert into public.empresas (clave, nombre) values (c_emp, 'ZZ-BUSCA Empresa');
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-BUSCA Proyecto', 'zz-busca-proyecto', c_emp, true) returning id into pL;
    insert into auth.users (id, instance_id, email, aud, role) values
      (jv.uid, '00000000-0000-0000-0000-000000000000', jv.em, 'authenticated', 'authenticated'),
      (a.uid,  '00000000-0000-0000-0000-000000000000', a.em,  'authenticated', 'authenticated'),
      (b.uid,  '00000000-0000-0000-0000-000000000000', b.em,  'authenticated', 'authenticated'),
      (fx.uid, '00000000-0000-0000-0000-000000000000', fx.em, 'authenticated', 'authenticated');
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (jv.uid, jv.em, 'ZZ-BUSCA Super admin', 'super_admin', 'global', '{}'::text[], '{}'::uuid[], '{}'::uuid[], '{}'::text[],          '{}'::text[],                 true),
      (a.uid,  a.em,  'ZZ-BUSCA Agente A',    'agente',      'global', array[c_emp], array[pL],    '{}'::uuid[], '{contratos}'::text[], '{contrato_general}'::text[], true),
      (b.uid,  b.em,  'ZZ-BUSCA Agente B',    'agente',      'global', array[c_emp], array[pL],    '{}'::uuid[], '{contratos}'::text[], '{contrato_general}'::text[], true);
    insert into public.clients (full_name, propietario, passport_number, email, phone, address, nationality)
      values ('ZZ-BUSCA José María Muñoz', a.em, 'ZZBUSCAA1', 'zz-busca-a@ejemplo.invalid', '+00 000 0101', 'ZZ-domicilio A', 'ZZ') returning id into cA;
    insert into public.clients (full_name, propietario, passport_number, email, phone, address, nationality)
      values ('ZZ-BUSCA Siobhán O’Brien', b.em, 'ZZBUSCAB1', 'zz-busca-b@ejemplo.invalid', '+00 000 0102', 'ZZ-domicilio B', 'ZZ') returning id into cB;
    alter table public.contratos disable trigger user;
    insert into public.contratos (tipo, numero, comprador_nombre, adq1_client_id, proyecto_id, proyecto_nombre, creado_por, created_at)
      values ('contrato_general', 'ZZB-0001', 'ZZ-BUSCA José María Muñoz', cA, pL, 'ZZ-BUSCA Proyecto', a.em, now() - interval '3 minutes') returning id into kA1;
    insert into public.contratos (tipo, numero, comprador_nombre, adq1_client_id, proyecto_id, proyecto_nombre, creado_por, created_at)
      values ('contrato_general', 'ZZB-0002', 'ZZ-BUSCA Copia Antigua', cA, pL, 'ZZ-BUSCA Proyecto', a.em, now() - interval '2 minutes') returning id into kA2;
    insert into public.contratos (tipo, numero, comprador_nombre, adq1_client_id, proyecto_id, proyecto_nombre, creado_por, created_at)
      values ('contrato_general', 'ZZB-0003', 'ZZ-BUSCA Siobhán O’Brien', cB, pL, 'ZZ-BUSCA Proyecto', b.em, now() - interval '1 minute') returning id into kB1;
    -- contrato que A VE (lo creo A) cuya ficha de comprador es la de B, que A NO ve (Seguridad, 15-oct: el join no debe enseñarla)
    insert into public.contratos (tipo, numero, comprador_nombre, adq1_client_id, proyecto_id, proyecto_nombre, creado_por, created_at)
      values ('contrato_general', 'ZZB-0004', 'ZZ-BUSCA Copia de Ficha Ajena', cB, pL, 'ZZ-BUSCA Proyecto', a.em, now() - interval '10 minutes') returning id into kA3;
    alter table public.contratos enable trigger user;
  exception when others then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'P0 montaje del fixture propio: ' || sqlstate || ' ' || left(sqlerrm, 300)
                                                                 || ' [session_user=' || session_user || ']'));
  end;
  rp := rp || pg_temp.l(pL is not null and cA is not null and cB is not null and kA1 is not null and kA2 is not null and kB1 is not null and kA3 is not null,
                        'P0 fixture propio montado: empresa, proyecto, 4 personas, 2 fichas y 4 contratos [session_user=' || session_user || ']');
  perform set_config('request.jwt.claims', json_build_object('sub', a.uid, 'role', 'authenticated', 'email', a.em)::text, true);
  rp := rp || pg_temp.l(public.es_agente(), 'P1 A es agente activo (es_agente)');
  rp := rp || pg_temp.l(public.alcance_restringido() and not public.es_admin(), 'P2 A tiene el alcance ACOTADO y no es admin');
  rp := rp || pg_temp.l(public.cliente_visible(a.em, cA) and not public.cliente_visible(b.em, cB), 'P3 A ve su ficha y no la de B (cliente_visible)');
  rp := rp || pg_temp.l(kA1 = any (public.mis_contratos_visibles()) and kA2 = any (public.mis_contratos_visibles()) and kA3 = any (public.mis_contratos_visibles())
                        and not kB1 = any (public.mis_contratos_visibles()),
                        'P4 A ve sus tres contratos (tambien el de la ficha ajena) y no el de B (mis_contratos_visibles)');
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);
  rp := rp || pg_temp.l(public.es_admin(), 'P5 el super admin ZZ es admin');
  perform set_config('request.jwt.claims', json_build_object('sub', fx.uid, 'role', 'authenticated', 'email', fx.em)::text, true);
  rp := rp || pg_temp.l(not public.es_agente(), 'P6 X no es del equipo (es_agente = false)');
  perform set_config('request.jwt.claims', '', true);
  v := pg_temp.val(a.uid, a.em, 'select (select auth.uid())::text || ''|'' || (select auth.email()) || ''|'' || current_user');
  rp := rp || pg_temp.l(v = a.uid::text || '|' || a.em || '|authenticated', 'S0 la sesion simulada es la de A con el rol authenticated (' || pg_temp.e(v) || ')');
  r := r || rp;
  if rp ~ 'FALLA' then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'PARADA: el fixture o la sesion no valen; los casos C/K/L no se corren'));
  end if;

  -- ============================================================ C. comprador_buscar (aviso de duplicados del alta; directorio global por nombre, DEFINER)
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.comprador_buscar(%L) where id = %L', 'jose maria munoz', cA));
  r := r || pg_temp.l(v = '1', 'C1 ENTRA: A encuentra «José María Muñoz» tecleando «jose maria munoz» (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.comprador_buscar(%L) where id = %L', 'JOSE MARIA', cA));
  r := r || pg_temp.l(v = '1', 'C2 ENTRA: y en mayusculas sin tildes (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.comprador_buscar(%L) where id = %L', 'siobhan obrien', cB));
  r := r || pg_temp.l(v = '1', 'C3 ENTRA: por nombre el directorio es global (regla de f2_b11, sin cambio): A ve «Siobhán O’Brien» con «siobhan obrien» (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, 'select count(*) from public.comprador_buscar(''%%%'')');
  r := r || pg_temp.l(v = '0', 'C4 NIEGA: un «%%%» tecleado ya no es comodin (con ilike devolvia fichas cualesquiera) (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, 'select count(*) from public.comprador_buscar(''___'')');
  r := r || pg_temp.l(v = '0', 'C5 NIEGA: ni un «___» (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, 'select count(*) from public.comprador_buscar(''zz'')');
  r := r || pg_temp.l(v = '0', 'C6 NIEGA: menos de 3 letras, nada (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.comprador_buscar(%L) where id = %L', 'zzbuscaa1', cA));
  r := r || pg_temp.l(v = '1', 'C7 ENTRA: A encuentra su ficha por pasaporte (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.comprador_buscar(%L) where id = %L', 'ZZBUSCAB1', cB));
  r := r || pg_temp.l(v = '0', 'C8 NIEGA: el pasaporte de una ficha que A no ve no la devuelve (alcance) (' || pg_temp.e(v) || ')');
  v := pg_temp.val(fx.uid, fx.em, 'select count(*) from public.comprador_buscar(''jose maria'')');
  r := r || pg_temp.l(v = '0', 'C9 NIEGA: quien no es del equipo no recibe nada (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.comprador_buscar(%L)', 'z'''''));
  r := r || pg_temp.l(v = '0', 'C10 NIEGA: «z» con dos apostrofos pasa el corte de 3 pero plegado es 1 letra: nada (Seguridad, 15-oct) (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.comprador_buscar(%L) where id = %L', repeat('x', 5000) || 'jose', cA));
  r := r || pg_temp.l(v = '0', 'C11 un texto enorme se corta a 200 en el servidor y no rompe (' || pg_temp.e(v) || ')');

  -- ============================================================ K. contratos_busca (buscador de ventas del asistente de contrato; INVOKER)
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.contratos_busca(%L) where id = %L', 'jose maria munoz', kA1));
  r := r || pg_temp.l(v = '1', 'K1 ENTRA: A encuentra su venta de «José María Muñoz» sin tildes (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.contratos_busca(%L) where id = %L', 'jose maria', kA2));
  r := r || pg_temp.l(v = '1', 'K2 ENTRA: y la venta cuya copia dice «Copia Antigua», por el nombre de HOY de su ficha (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.contratos_busca(%L) where id = %L', 'copia antigua', kA2));
  r := r || pg_temp.l(v = '1', 'K3 ENTRA: y tambien por la copia del contrato (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.contratos_busca(%L) where id = %L', 'zzb 0001', kA1));
  r := r || pg_temp.l(v = '1', 'K4 ENTRA: por numero, con espacio en vez de guion (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, 'select count(*) from public.contratos_busca(''siobhan'')');
  r := r || pg_temp.l(v = '0', 'K5 NIEGA: A no recibe la venta de B (la RLS de contratos decide) (' || pg_temp.e(v) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select count(*) from public.contratos_busca(%L) where id = %L', 'siobhan obrien', kB1));
  r := r || pg_temp.l(v = '1', 'K6 ENTRA: el super admin si la recibe (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, 'select string_agg(numero, '','' order by created_at desc) from public.contratos_busca('''')');
  r := r || pg_temp.l(v = 'ZZB-0002,ZZB-0001,ZZB-0004', 'K7 vacio: las ultimas de A, la mas nueva primero (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, 'select string_agg(numero, '','' order by created_at desc) from public.contratos_busca(''j'')');
  r := r || pg_temp.l(v = 'ZZB-0002,ZZB-0001,ZZB-0004', 'K8 una letra cuenta como vacio, como antes (' || pg_temp.e(v) || ')');
  v  := pg_temp.val(a.uid, a.em, 'select string_agg(id::text, '','' order by id) from public.contratos_busca(''zz busca'')');
  v2 := pg_temp.val(a.uid, a.em, 'select string_agg(id::text, '','' order by id) from public.contratos where numero is not null');
  r := r || pg_temp.l(v = v2 and v <> 'null', 'K9 lo que devuelve a A es exactamente lo que A lee de contratos con su RLS');
  v := pg_temp.val(fx.uid, fx.em, 'select count(*) from public.contratos_busca('''')');
  r := r || pg_temp.l(v = '0', 'K10 NIEGA: quien no es del equipo no recibe nada (' || pg_temp.e(v) || ')');
  v := pg_temp.val(null, null, 'select count(*) from public.contratos_busca(''jose'')', 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'K11 NIEGA: anon no puede llamarla (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.contratos_busca(%L) where id = %L', 'siobhan obrien', kA3));
  r := r || pg_temp.l(v = '0', 'K12 NIEGA: el contrato que A ve NO sale por el nombre de una ficha que A no ve (el join respeta la RLS de clients) (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.contratos_busca(%L) where id = %L', 'copia de ficha ajena', kA3));
  r := r || pg_temp.l(v = '1', 'K13 ENTRA: ese mismo contrato si sale por su copia del nombre (' || pg_temp.e(v) || ')');

  -- ============================================================ L. clientes_busca (edge asistente-peticiones; INVOKER)
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.clientes_busca(%L) where id = %L', 'jose maria', cA));
  r := r || pg_temp.l(v = '1', 'L1 ENTRA: A encuentra su ficha sin tildes (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, 'select count(*) from public.clientes_busca(''siobhan obrien'')');
  r := r || pg_temp.l(v = '0', 'L2 NIEGA: A no recibe la ficha de B (la RLS de clients decide) (' || pg_temp.e(v) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select count(*) from public.clientes_busca(%L) where id = %L', 'siobhan obrien', cB));
  r := r || pg_temp.l(v = '1', 'L3 ENTRA: el super admin si, con «O’Brien» tecleado sin apostrofo (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, 'select count(*) from public.clientes_busca(''j'')');
  r := r || pg_temp.l(v = '0', 'L4 NIEGA: menos de 2 letras, nada (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.clientes_busca(%L) where id = %L', 'zzbuscaa1', cA));
  r := r || pg_temp.l(v = '1', 'L5 ENTRA: por pasaporte, sin mayusculas (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, 'select count(*) from public.clientes_busca(''ZZBUSCAB1'')');
  r := r || pg_temp.l(v = '0', 'L6 NIEGA: ni por el pasaporte de una ficha que A no ve (' || pg_temp.e(v) || ')');
  v := pg_temp.val(fx.uid, fx.em, 'select count(*) from public.clientes_busca(''jose maria'')');
  r := r || pg_temp.l(v = '0', 'L7 NIEGA: quien no es del equipo no recibe nada (' || pg_temp.e(v) || ')');
  v := pg_temp.val(null, null, 'select count(*) from public.clientes_busca(''jose'')', 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'L8 NIEGA: anon no puede llamarla (' || pg_temp.e(v) || ')');
  v := pg_temp.val(null, null, 'select public.normaliza_busqueda(''José'')', 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'L9 NIEGA: anon tampoco llama a normaliza_busqueda (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, 'select public.normaliza_busqueda(''José'')');
  r := r || pg_temp.l(v = 'jose', 'L10 ENTRA: authenticated si (la necesitan las dos INVOKER) (' || pg_temp.e(v) || ')');

  raise exception 'FIN DE PRUEBAS BUSQUEDA SIN TILDES (se deshace todo):%', r;
end $todo$;
