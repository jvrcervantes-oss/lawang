-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Prueba de BUSQUEDA SIN TILDES (15-oct-2026, owner: «que no haga falta poner la tilde en los buscadores de Lawang y en todo lo que hagamos»).
-- Se pasa DESPUES de la migracion 20261015130000_busqueda_sin_tildes.sql (o detras de ella en la rama de ensayo). Una sola peticion:
-- casos + llamadas con el rol real + raise final que lo revierte todo. Despues: f2_b11_directorio.sql y f2_b3_empresas.sql (comprador_buscar).
-- La tabla de casos la GENERA el estudio desde contracts/busqueda_casos.json (la misma que prueba el navegador en contracts/busqueda.test.js,
-- que falla si aqui falta un caso): las dos capas aplican EL MISMO algoritmo y se prueban con la misma tabla.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); no escribe datos
create function pg_temp.t(p_uid uuid, p_email text, p_sql text, p_esp text, p_et text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare got text; r text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role',p_rol,'email',p_email)::text, true);
  execute format('set local role %I', p_rol);
  begin execute p_sql into r; got := coalesce(r,'null'); exception when others then got := sqlstate; end;
  reset role;
  return case when got = p_esp then 'OK   ' else 'FALLO' end || ' ' || p_et || ' [' || got || ' esp ' || p_esp || ']';
end $f$;
do $t$
declare
  r text := ''; fallos int; x record; ctl uuid; e_ctl text; adm uuid; e_adm text; cli uuid; nom text; q text; kid uuid; knom text; n int;
begin
  -- 0. la tabla de casos (navegador = servidor)
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
    r := r || case when public.normaliza_busqueda(x.entrada) = x.esperado then 'OK   ' else 'FALLO' end
          || ' normaliza ' || coalesce(x.entrada, '<null>') || ' -> [' || public.normaliza_busqueda(x.entrada) || '] esp [' || x.esperado || ']' || E'\n';
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
    r := r || case when (public.normaliza_busqueda(x.aguja) = '' or strpos(public.normaliza_busqueda(x.texto), public.normaliza_busqueda(x.aguja)) > 0) = x.casa
                   then 'OK   ' else 'FALLO' end || ' busca «' || x.aguja || '» en «' || x.texto || '» = ' || x.casa || E'\n';
  end loop;

  -- 1. como nacen las funciones: inmutable la que pliega, INVOKER las que leen, search_path fijo, cerradas a anon
  for x in select p.proname, p.provolatile, p.prosecdef, p.proconfig,
                  has_function_privilege('anon', p.oid, 'execute') anon, has_function_privilege('authenticated', p.oid, 'execute') auth
             from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('normaliza_busqueda','contratos_busca','clientes_busca') loop
    r := r || case when x.proconfig = '{search_path=""}' and not x.anon and x.auth and not x.prosecdef
                         and (x.proname <> 'normaliza_busqueda' or x.provolatile = 'i') then 'OK   ' else 'FALLO' end
          || ' ' || x.proname || ' volatil=' || x.provolatile || ' definer=' || x.prosecdef || ' anon=' || x.anon || ' authenticated=' || x.auth || E'\n';
  end loop;
  select count(*) into n from pg_proc where pronamespace = 'public'::regnamespace and proname in ('normaliza_busqueda','contratos_busca','clientes_busca');
  r := r || case when n = 3 then 'OK   ' else 'FALLO' end || ' existen las 3 funciones nuevas [' || n || ']' || E'\n';
  r := r || case when (select prosecdef from pg_proc where oid = 'public.comprador_buscar(text)'::regprocedure)
                  and pg_get_functiondef('public.comprador_buscar(text)'::regprocedure) ~ 'normaliza_busqueda'
                  and pg_get_functiondef('public.comprador_buscar(text)'::regprocedure) !~* 'ilike' then 'OK   ' else 'FALLO' end
        || ' comprador_buscar sigue DEFINER, compara con normaliza_busqueda y sin ilike' || E'\n';

  -- muestras: un agente global sin empresas (el «control» de f2_b11, que ve todas las fichas), un admin global (ve todos los contratos)
  -- y un cliente con letras no ASCII en el nombre
  select user_id, email into ctl, e_ctl from public.usuarios
   where activo and ambito = 'global' and cardinality(coalesce(empresas,'{}')) = 0 and rol not in ('admin','super_admin') order by email limit 1;
  select user_id, email into adm, e_adm from public.usuarios where activo and rol = 'admin' and ambito = 'global' order by email limit 1;
  if adm is null then select user_id, email into adm, e_adm from public.usuarios where activo and rol = 'super_admin' and ambito = 'global' order by email limit 1; end if;
  select c.id, c.full_name into cli, nom from public.clients c
   where c.full_name ~ '[^[:ascii:]]' and char_length(public.normaliza_busqueda(c.full_name)) >= 6 order by c.id limit 1;
  q := public.normaliza_busqueda(nom);   -- sin tildes ni mayusculas: lo que teclea alguien sin la tilde
  r := r || case when ctl is not null and adm is not null and cli is not null then 'OK   ' else 'FALLO' end
        || ' muestras: agente de control, admin global y cliente con letras no ASCII en el nombre' || E'\n';

  -- 2. comprador_buscar (aviso de duplicados del alta): sin tildes, sin comodines, minimo 3
  r := r || pg_temp.t(ctl, e_ctl, format('select count(*)::text from public.comprador_buscar(%L) where id = %L', q, cli), '1', 'comprador_buscar encuentra la ficha tecleando sin tildes') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select count(*)::text from public.comprador_buscar(%L) where id = %L', upper(q), cli), '1', 'y en mayusculas') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, 'select count(*)::text from public.comprador_buscar(''%%%'')', '0', 'un «%%%» tecleado ya no devuelve fichas cualesquiera (antes: 8)') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, 'select count(*)::text from public.comprador_buscar(''___'')', '0', 'ni un «___»') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, 'select count(*)::text from public.comprador_buscar(''ab'')', '0', 'menos de 3 letras: nada') || E'\n';
  r := r || pg_temp.t(gen_random_uuid(), 'cuenta.portal.tildes@example.com', format('select count(*)::text from public.comprador_buscar(%L)', q), '0', 'quien no es del equipo: nada') || E'\n';

  -- 3. contratos_busca (buscador de ventas del asistente de contrato): las mismas filas que contratos_equipo(), sin tildes y por la ficha.
  --    Con el admin global (ve todos los contratos) para que lo esperado no dependa de la visibilidad; la RLS la cubre la llamada de «quien no es del equipo».
  r := r || pg_temp.t(adm, e_adm,
        'select (array(select id from public.contratos_busca('''')) = array(select id from public.contratos_equipo() where numero is not null order by created_at desc limit 10))::text',
        'true', 'contratos_busca vacio = las 10 ultimas de contratos_equipo() (lo de hoy)') || E'\n';
  r := r || pg_temp.t(adm, e_adm,
        'select (array(select id from public.contratos_busca(''x'')) = array(select id from public.contratos_busca('''')))::text',
        'true', 'una letra = como vacio (minimo 2, lo de hoy)') || E'\n';
  select c.id, c.comprador_nombre into kid, knom from public.contratos c
   where c.numero is not null and c.comprador_nombre ~ '[^[:ascii:]]' and char_length(public.normaliza_busqueda(c.comprador_nombre)) >= 6 order by c.created_at desc limit 1;
  r := r || pg_temp.t(adm, e_adm, format('select count(*)::text from public.contratos_busca(%L) where id = %L', public.normaliza_busqueda(knom), kid),
        '1', 'contratos_busca encuentra la venta por el nombre tecleado sin tildes') || E'\n';
  -- el nombre de la FICHA (unida por adq1_client_id) cuando la copia del contrato dice otra cosa (Base de datos: 46 contratos asi el 15-oct)
  kid := null;
  select c.id, k2.full_name into kid, knom from public.contratos c join public.clients k2 on k2.id = c.adq1_client_id
   where c.numero is not null and strpos(public.normaliza_busqueda(c.comprador_nombre), public.normaliza_busqueda(k2.full_name)) = 0
     and char_length(public.normaliza_busqueda(k2.full_name)) >= 6 order by c.created_at desc limit 1;
  if kid is not null then
    r := r || pg_temp.t(adm, e_adm, format('select count(*)::text from public.contratos_busca(%L) where id = %L', public.normaliza_busqueda(knom), kid),
          '1', 'contratos_busca encuentra la venta por el nombre de su ficha aunque la copia del contrato diga otro') || E'\n';
  else
    r := r || 'OK    (sin contrato cuya copia del nombre difiera de su ficha: caso no medible hoy)' || E'\n';
  end if;
  r := r || pg_temp.t(adm, e_adm, 'select count(*)::text from public.contratos_busca(''zzzzqqqq-no-existe'')', '0', 'contratos_busca sin coincidencias: 0') || E'\n';
  r := r || pg_temp.t(adm, e_adm, 'select (count(*) <= 10)::text from public.contratos_busca(''a'')', 'true', 'contratos_busca devuelve 10 como mucho') || E'\n';
  r := r || pg_temp.t(gen_random_uuid(), 'cuenta.portal.tildes@example.com', 'select count(*)::text from public.contratos_busca('''')', '0', 'quien no es del equipo: ninguna venta') || E'\n';
  r := r || pg_temp.t(null, null, 'select count(*)::text from public.contratos_busca('''')', '42501', 'anon: sin permiso', 'anon') || E'\n';

  -- 4. clientes_busca (edge asistente-peticiones): sin tildes, con la RLS de quien pide
  r := r || pg_temp.t(ctl, e_ctl, format('select count(*)::text from public.clientes_busca(%L) where id = %L', q, cli),
        '1', 'clientes_busca encuentra la ficha sin tildes (el agente de control ve todas, f2_b11)') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, 'select count(*)::text from public.clientes_busca(''a'')', '0', 'clientes_busca: menos de 2 letras, nada') || E'\n';
  r := r || pg_temp.t(gen_random_uuid(), 'cuenta.portal.tildes@example.com', format('select count(*)::text from public.clientes_busca(%L)', q), '0', 'quien no es del equipo: nada (RLS)') || E'\n';
  r := r || pg_temp.t(null, null, format('select count(*)::text from public.clientes_busca(%L)', q), '42501', 'anon: sin permiso', 'anon') || E'\n';
  r := r || pg_temp.t(null, null, 'select public.normaliza_busqueda(''x'')', '42501', 'anon no ejecuta normaliza_busqueda', 'anon') || E'\n';

  fallos := (length(r) - length(replace(r, 'FALLO', ''))) / 5;
  raise exception E'\n%FALLOS=%', r, fallos;
end $t$;
