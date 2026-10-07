-- Prueba del bloque 5 (Fase 2 · USUARIOS, EQUIPO Y EDGES, 8-oct-2026): gestion de personas por empresa, alta, clave, registro de cambios de nivel y quien ve que fichas de `usuarios`.
-- Se ejecuta DESPUES de las migraciones 20261008500000..504000 (o pegada tras ellas en la misma peticion para ensayarlas sin rastro). Todo dentro de UNA transaccion que acaba en raise (rollback).
-- No crea usuarios reales: convierte fichas de agente existentes a roles de empresa (como f2_2b_empresas.sql) y fabrica cuentas de Auth solo dentro de la transaccion.
-- Seccion 0: A/B contra el ORIGINAL (public._f2_b5_originales) de usuario_guarda_permisos y usuario_supervisa_proyecto con los 34 usuarios reales como llamadores: mismo resultado y misma ficha.
-- Secciones 1..8: los casos de empresa. Cada linea OK/FALLO; debe terminar con «FALLOS=0».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); sin drop
create temp table res (n serial, nombre text, ok boolean, detalle text);

create function pg_temp.corre(p_uid uuid, p_email text, p_sent text, p_cons text default null, p_auth boolean default true, p_cons_auth boolean default false) returns text
language plpgsql as $f$
declare v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
  begin
    if p_auth then set local role authenticated; end if;
    if p_sent is not null then execute p_sent; end if;
    if not p_cons_auth then reset role; end if;
    if p_cons is not null then execute p_cons into v; end if;
    raise exception 'RB' using errcode = 'ZZ001', detail = coalesce(v, 'ok');
  exception
    when sqlstate 'ZZ001' then get stacked diagnostics v = pg_exception_detail; return v;
    when others then return 'E' || sqlstate || '|' || left(sqlerrm, 90);
  end;
end $f$;

create function pg_temp.espera(p_nombre text, p_obt text, p_esp text) returns void
language plpgsql as $f$
begin
  insert into res (nombre, ok, detalle)
  values (p_nombre,
          case when p_esp = 'ok' then p_obt = 'ok' when p_esp like 'E%' then p_obt like p_esp || '%' else p_obt = p_esp end,
          p_nombre || '  obtenido=[' || coalesce(p_obt, 'null') || ']  esperado=[' || p_esp || ']');
end $f$;

do $t$
declare
  jv uuid; je text; pep uuid; pepe text; adm uuid; adme text; sm uuid; sme text; ina uuid; inae text;
  a uuid; ae text; s uuid; se text; d uuid; de text; x uuid; xe text; c uuid; ce text;
  t1 uuid; t1e text; t2 uuid; t2e text; t3 uuid; t3e text; t4 uuid; t4e text; t5 uuid; t5e text; t6 uuid; t6e text; t7 uuid; t7e text; t8 uuid; t8e text;
  ag uuid[]; age text[];
  pl uuid; ps uuid; pk uuid;
  cam text[]; i int; j int; k int; cu record; tg uuid[]; tge text[]; o1 text; o2 text; cons text; n_ab int := 0; n_dif int := 0; dif text := '';
  nu uuid := gen_random_uuid(); nu2 uuid := gen_random_uuid(); nu3 uuid := gen_random_uuid(); nu4 uuid := gen_random_uuid(); nu5 uuid := gen_random_uuid(); nu6 uuid := gen_random_uuid(); np uuid := gen_random_uuid();
  v text; fallos int; resumen text; oks int;
begin
  select user_id, email into jv, je from public.usuarios where es_propietario;
  select user_id, email into pep, pepe from public.usuarios where rol = 'super_admin' and not es_propietario order by email limit 1;
  select user_id, email into adm, adme from public.usuarios where rol = 'admin' and activo order by email limit 1;
  select user_id, email into sm, sme from public.usuarios where rol = 'project_manager' and activo order by email limit 1;
  select user_id, email into ina, inae from public.usuarios where not activo order by email limit 1;
  select id into pl from public.proyectos where empresa = 'lawang' order by id limit 1;
  select id into ps from public.proyectos where empresa = 'sandal_woods' order by id limit 1;
  select id into pk from public.proyectos where empresa is null order by id limit 1;

  -- ================================================================ SECCION 0: A/B contra el original, 34 llamadores reales
  execute replace((select ddl from public._f2_b5_originales where nombre like 'f:usuario_guarda_permisos%'), 'FUNCTION public.usuario_guarda_permisos', 'FUNCTION pg_temp.o_guarda');
  execute replace((select ddl from public._f2_b5_originales where nombre like 'f:usuario_supervisa_proyecto%'), 'FUNCTION public.usuario_supervisa_proyecto', 'FUNCTION pg_temp.o_supervisa');
  select array_agg(user_id order by email), array_agg(email order by email) into tg, tge
    from (select user_id, email from public.usuarios where user_id in (jv, pep, adm, sm, ina)
          union all (select user_id, email from public.usuarios where rol = 'agente' and activo order by email limit 2)
          union all (select user_id, email from public.usuarios where rol = 'sales_manager' order by email limit 1)) q;
  cam := array[
    '{"nombre":"zz"}', '{"herramientas":["contratos"]}', '{"activo":false}', '{"activo":true}', '{"rol":"admin"}', '{"rol":"agente"}',
    format('{"proyectos":["%s"]}', pl), '{"tipos_contrato":["carta_reserva"]}', '{"proyectos":[]}', '{"nombre":"zz","activo":true}'];
  for cu in select user_id, email from public.usuarios order by email loop
    for i in 1..array_length(tg, 1) loop
      cons := format('select md5((to_jsonb(u) - %L)::text) from public.usuarios u where u.user_id = %L', 'notif_visto_hasta', tg[i]);
      for j in 1..array_length(cam, 1) loop
        o1 := pg_temp.corre(cu.user_id, cu.email, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', tg[i], cam[j]), cons, false);
        o2 := pg_temp.corre(cu.user_id, cu.email, format('select pg_temp.o_guarda(%L, %L::jsonb)', tg[i], cam[j]), cons, false);
        n_ab := n_ab + 1;
        if o1 is distinct from o2 then n_dif := n_dif + 1; if n_dif <= 5 then dif := dif || format(E'  DIF guarda %s -> %s %s: nuevo=[%s] orig=[%s]\n', cu.email, tge[i], cam[j], o1, o2); end if; end if;
      end loop;
      for j in 1..2 loop
        o1 := pg_temp.corre(cu.user_id, cu.email, format('select public.usuario_supervisa_proyecto(%L, %L, %s)', tg[i], pl, (j = 1)::text), cons, false);
        o2 := pg_temp.corre(cu.user_id, cu.email, format('select pg_temp.o_supervisa(%L, %L, %s)', tg[i], pl, (j = 1)::text), cons, false);
        n_ab := n_ab + 1;
        if o1 is distinct from o2 then n_dif := n_dif + 1; if n_dif <= 5 then dif := dif || format(E'  DIF supervisa %s -> %s asignar=%s: nuevo=[%s] orig=[%s]\n', cu.email, tge[i], (j=1), o1, o2); end if; end if;
      end loop;
    end loop;
  end loop;
  perform pg_temp.espera('S0 A/B guarda+supervisa: casos distintos de ' || n_ab, n_dif::text, '0');

  -- ================================================================ preparacion: personas (todo en rollback)
  select array_agg(user_id order by email), array_agg(email order by email) into ag, age
    from (select user_id, email from public.usuarios where rol = 'agente' and activo and cardinality(empresas) = 0
            and email not in ('yanayjefferson@gmail.com','cris.blueiestates@gmail.com','adenovit.b@gmail.com') order by email limit 12) q;
  select user_id, email into a, ae from public.usuarios where email = 'yanayjefferson@gmail.com';
  select user_id, email into s, se from public.usuarios where email = 'cris.blueiestates@gmail.com';
  select user_id, email into d, de from public.usuarios where email = 'adenovit.b@gmail.com';
  x := ag[1]; xe := age[1]; c := ag[2]; ce := age[2];
  t1 := ag[3]; t1e := age[3]; t2 := ag[4]; t2e := age[4]; t3 := ag[5]; t3e := age[5]; t4 := ag[6]; t4e := age[6];
  t5 := ag[7]; t5e := age[7]; t6 := ag[8]; t6e := age[8]; t7 := ag[9]; t7e := age[9]; t8 := ag[10]; t8e := age[10];
  perform set_config('request.jwt.claims', json_build_object('sub', jv, 'role', 'authenticated', 'email', je)::text, true);   -- el propietario monta las fichas de prueba
  -- roles de empresa (como postgres: sin sesion, el candado lo deja pasar)
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{usuarios,contratos,leads}', tipos_contrato = '{carta_reserva}' where user_id = a;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{contratos}', tipos_contrato = '{}' where user_id = s;
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang,sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{usuarios,contratos}', tipos_contrato = '{carta_reserva,construccion}' where user_id = d;
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{contratos}', tipos_contrato = '{}' where user_id = x;  -- SIN la casilla usuarios
  -- personas gestionables y no gestionables
  update public.usuarios set empresas = '{lawang}', herramientas = '{contratos}', tipos_contrato = '{}', proyectos = '{}', proyectos_supervisados = '{}' where user_id = t1;
  update public.usuarios set empresas = '{sandal_woods}', herramientas = '{contratos}', proyectos = '{}', proyectos_supervisados = '{}' where user_id = t2;
  update public.usuarios set empresas = '{lawang,sandal_woods}', herramientas = '{contratos}', proyectos = '{}', proyectos_supervisados = '{}' where user_id = t3;
  update public.usuarios set rol = 'project_manager', empresas = '{lawang}', herramientas = '{contratos}', proyectos = '{}', proyectos_supervisados = array[pl] where user_id = t4;
  update public.usuarios set empresas = '{}', herramientas = '{contratos}', proyectos = '{}', proyectos_supervisados = '{}' where user_id = t5;                       -- global sin empresas
  update public.usuarios set activo = false, empresas = '{lawang}', herramientas = '{contratos,facturas}', proyectos = '{}', proyectos_supervisados = '{}' where user_id = t6; -- inactivo con herramienta ajena
  update public.usuarios set activo = false, empresas = '{sandal_woods}', herramientas = '{contratos}', proyectos = '{}', proyectos_supervisados = '{}' where user_id = t7;    -- inactivo reactivable por S
  update public.usuarios set rol = 'project_manager', empresas = '{sandal_woods}', herramientas = '{contratos}', proyectos = '{}', proyectos_supervisados = '{}' where user_id = t8;

  -- ================================================================ SECCION 1: a quien gestiona cada uno (cambiar el nombre)
  v := '{"nombre":"zz"}';
  perform pg_temp.espera('S1 A -> t1 (lawang)',            pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, v)), 'ok');
  perform pg_temp.espera('S1 A -> t2 (sandal)',            pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t2, v)), 'E42501');
  perform pg_temp.espera('S1 A -> t3 (las dos: no cabe)',  pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t3, v)), 'E42501');
  perform pg_temp.espera('S1 A -> t4 (PM lawang)',         pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t4, v)), 'ok');
  perform pg_temp.espera('S1 A -> t5 (global sin empresas: cardinality)', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t5, v)), 'E42501');
  perform pg_temp.espera('S1 A -> t6 (inactivo lawang)',   pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t6, v)), 'ok');
  perform pg_temp.espera('S1 A -> admin global',           pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', adm, v)), 'E42501');
  perform pg_temp.espera('S1 A -> super global',           pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', pep, v)), 'E42501');
  perform pg_temp.espera('S1 A -> propietario',            pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', jv, v)), 'E42501');
  perform pg_temp.espera('S1 A -> S (otro rol de empresa)', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', s, v)), 'E42501');
  perform pg_temp.espera('S1 A -> D (admin_empresa con sus dos)', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', d, v)), 'E42501');
  perform pg_temp.espera('S1 A -> si mismo (nombre)',      pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', a, v)), 'ok');
  perform pg_temp.espera('S1 A -> si mismo (herramientas)', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', a, '{"herramientas":["usuarios","contratos","leads"]}')), 'E42501');
  perform pg_temp.espera('S1 S (super de sandal, sin casilla usuarios) -> t2', pg_temp.corre(s, se, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t2, v)), 'ok');
  perform pg_temp.espera('S1 S -> t1 (lawang)',            pg_temp.corre(s, se, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, v)), 'E42501');
  perform pg_temp.espera('S1 S -> t3 (las dos)',           pg_temp.corre(s, se, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t3, v)), 'E42501');
  perform pg_temp.espera('S1 S -> t8 (PM sandal)',         pg_temp.corre(s, se, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t8, v)), 'ok');
  perform pg_temp.espera('S1 D (las dos) -> t1',           pg_temp.corre(d, de, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, v)), 'ok');
  perform pg_temp.espera('S1 D -> t2',                     pg_temp.corre(d, de, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t2, v)), 'ok');
  perform pg_temp.espera('S1 D -> t3 (las dos)',           pg_temp.corre(d, de, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t3, v)), 'ok');
  perform pg_temp.espera('S1 D -> t5 (global sin empresas)', pg_temp.corre(d, de, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t5, v)), 'E42501');
  perform pg_temp.espera('S1 X (admin_empresa sin casilla usuarios) -> t1', pg_temp.corre(x, xe, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, v)), 'E42501');
  perform pg_temp.espera('S1 control (agente sin empresas) -> t1', pg_temp.corre(c, ce, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, v)), 'E42501');

  -- ================================================================ SECCION 2: lo que pueden dar
  cons := 'select herramientas::text from public.usuarios where user_id = ';
  perform pg_temp.espera('S2 A da leads (lo tiene) a t1', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, '{"herramientas":["contratos","leads"]}'), cons || quote_literal(t1)), '{contratos,leads}');
  perform pg_temp.espera('S2 A da facturas (no lo tiene) a t1', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, '{"herramientas":["contratos","facturas"]}')), 'E42501');
  perform pg_temp.espera('S2 A quita contratos a t1 (quitar siempre se puede)', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, '{"herramientas":[]}'), cons || quote_literal(t1)), '{}');
  perform pg_temp.espera('S2 S da contratos (lo tiene) a t2', pg_temp.corre(s, se, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t2, '{"herramientas":["contratos"]}')), 'ok');
  perform pg_temp.espera('S2 S da comisiones (no lo tiene) a t2', pg_temp.corre(s, se, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t2, '{"herramientas":["contratos","comisiones"]}')), 'E42501');
  perform pg_temp.espera('S2 A cambia el rol de t1',       pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, '{"rol":"sales_manager"}')), 'E42501');
  perform pg_temp.espera('S2 A manda el mismo rol (no-op)', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, '{"rol":"agente"}')), 'ok');
  perform pg_temp.espera('S2 S sube a t2 a admin',         pg_temp.corre(s, se, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t2, '{"rol":"admin"}')), 'E42501');
  cons := 'select proyectos::text from public.usuarios where user_id = ';
  perform pg_temp.espera('S2 A da un proyecto de lawang a t1', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, format('{"proyectos":["%s"]}', pl)), cons || quote_literal(t1)), '{' || pl || '}');
  perform pg_temp.espera('S2 A da un proyecto de sandal a t1', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, format('{"proyectos":["%s"]}', ps))), 'E42501');
  perform pg_temp.espera('S2 A da Karana (sin empresa) a t1', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, format('{"proyectos":["%s"]}', pk))), 'E42501');
  perform pg_temp.espera('S2 D da los dos proyectos a t3 (las dos empresas)', pg_temp.corre(d, de, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t3, format('{"proyectos":["%s","%s"]}', pl, ps))), 'ok');
  perform pg_temp.espera('S2 D da un proyecto de sandal a t1 (solo lawang)', pg_temp.corre(d, de, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, format('{"proyectos":["%s"]}', ps))), 'E42501');
  perform pg_temp.espera('S2 A da tipo que tiene a t1', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, '{"tipos_contrato":["carta_reserva"]}')), 'ok');
  perform pg_temp.espera('S2 A da tipo que no tiene a t1', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, '{"tipos_contrato":["construccion"]}')), 'E42501');
  perform pg_temp.espera('S2 S (super de empresa) da cualquier tipo a t2', pg_temp.corre(s, se, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t2, '{"tipos_contrato":["construccion"]}')), 'ok');
  cons := 'select activo::text from public.usuarios where user_id = ';
  perform pg_temp.espera('S2 A desactiva a t1', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t1, '{"activo":false}'), cons || quote_literal(t1)), 'false');
  perform pg_temp.espera('S2 A reactiva a t6 (tiene facturas, A no)', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t6, '{"activo":true}')), 'E42501');
  perform pg_temp.espera('S2 S reactiva a t7 (herramientas suyas)', pg_temp.corre(s, se, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', t7, '{"activo":true}'), cons || quote_literal(t7)), 'true');
  perform pg_temp.espera('S2 A no se desactiva a si mismo', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', a, '{"activo":false}')), 'E42501');

  -- ================================================================ SECCION 3: supervision de proyectos
  cons := 'select proyectos_supervisados::text from public.usuarios where user_id = ';
  perform pg_temp.espera('S3 A asigna proyecto lawang a PM t4 (ya lo tiene: idempotente)', pg_temp.corre(a, ae, format('select public.usuario_supervisa_proyecto(%L, %L, true)', t4, pl), cons || quote_literal(t4)), '{' || pl || '}');
  perform pg_temp.espera('S3 A asigna proyecto de sandal a PM t4', pg_temp.corre(a, ae, format('select public.usuario_supervisa_proyecto(%L, %L, true)', t4, ps)), 'E42501');
  perform pg_temp.espera('S3 A asigna Karana a PM t4',   pg_temp.corre(a, ae, format('select public.usuario_supervisa_proyecto(%L, %L, true)', t4, pk)), 'E42501');
  perform pg_temp.espera('S3 A quita la supervision a t4', pg_temp.corre(a, ae, format('select public.usuario_supervisa_proyecto(%L, %L, false)', t4, pl), cons || quote_literal(t4)), '{}');
  perform pg_temp.espera('S3 A asigna a agente t1 (solo PM)', pg_temp.corre(a, ae, format('select public.usuario_supervisa_proyecto(%L, %L, true)', t1, pl)), 'E22023');
  perform pg_temp.espera('S3 A quita supervision a t2 (otra empresa: ahora exige destino)', pg_temp.corre(a, ae, format('select public.usuario_supervisa_proyecto(%L, %L, false)', t2, pl)), 'E42501');
  perform pg_temp.espera('S3 A quita supervision a un global', pg_temp.corre(a, ae, format('select public.usuario_supervisa_proyecto(%L, %L, false)', sm, pl)), 'E42501');
  perform pg_temp.espera('S3 S asigna proyecto de sandal a PM t8', pg_temp.corre(s, se, format('select public.usuario_supervisa_proyecto(%L, %L, true)', t8, ps), cons || quote_literal(t8)), '{' || ps || '}');
  perform pg_temp.espera('S3 S asigna proyecto de lawang a PM t8', pg_temp.corre(s, se, format('select public.usuario_supervisa_proyecto(%L, %L, true)', t8, pl)), 'E42501');
  perform pg_temp.espera('S3 D asigna proyecto de lawang a PM t4', pg_temp.corre(d, de, format('select public.usuario_supervisa_proyecto(%L, %L, true)', t4, pl), cons || quote_literal(t4)), '{' || pl || '}');
  perform pg_temp.espera('S3 X (sin casilla usuarios)', pg_temp.corre(x, xe, format('select public.usuario_supervisa_proyecto(%L, %L, true)', t4, pl)), 'E42501');
  perform pg_temp.espera('S3 control agente', pg_temp.corre(c, ce, format('select public.usuario_supervisa_proyecto(%L, %L, true)', t4, pl)), 'E42501');

  -- ================================================================ SECCION 4: nivel y empresas solo del propietario + registro
  perform pg_temp.espera('S4 A llama a usuario_da_alcance', pg_temp.corre(a, ae, format('select public.usuario_da_alcance(%L, %L, %L::text[])', t1, 'agente', '{lawang}')), 'E42501');
  perform pg_temp.espera('S4 S llama a usuario_da_alcance', pg_temp.corre(s, se, format('select public.usuario_da_alcance(%L, %L, %L::text[])', t2, 'agente', '{sandal_woods}')), 'E42501');
  perform pg_temp.espera('S4 A actualiza `usuarios` directo (sin grant)', pg_temp.corre(a, ae, format('update public.usuarios set empresas = %L where user_id = %L', '{lawang,sandal_woods}', t1)), 'E42501');
  perform pg_temp.espera('S4 A inserta `usuarios` directo (sin grant)', pg_temp.corre(a, ae, format('insert into public.usuarios (user_id, email, rol) values (%L, %L, %L)', gen_random_uuid(), 'x@x.x', 'agente')), 'E42501');
  perform pg_temp.espera('S4 propietario da nivel a una cuenta DESACTIVADA', pg_temp.corre(jv, je, format('select public.usuario_da_alcance(%L, %L, %L::text[])', t6, 'agente', '{lawang}')), 'E22023');
  perform pg_temp.espera('S4 propietario da nivel a un activo', pg_temp.corre(jv, je, format('select public.usuario_da_alcance(%L, %L, %L::text[])', t5, 'agente', '{lawang}')), 'ok');
  perform pg_temp.espera('S4 cuenta los supervisados quitados (t4 supervisa un proyecto de lawang; pasa a sandal)',
    pg_temp.corre(jv, je, null, format('select (public.usuario_da_alcance(%L, %L, %L::text[]))->>%L', t4, 'project_manager', '{sandal_woods}', 'supervisados_quitados')), '1');
  perform pg_temp.espera('S4 deja una fila en el registro (quien, a quien, antes, despues)',
    pg_temp.corre(jv, je, format('select public.usuario_da_alcance(%L, %L, %L::text[])', t5, 'agente', '{lawang,sandal_woods}'),
      format('select (select count(*) from public.usuarios_cambios_alcance where quien = %L and a_quien = %L and accion = %L and (antes->>%L) = %L and (despues->%L) = %L::jsonb)::text',
             jv, t5, 'nivel', 'ambito', 'global', 'empresas', '["lawang","sandal_woods"]'), p_auth => false), '1');
  perform pg_temp.espera('S4 el propietario LEE el registro',
    pg_temp.corre(jv, je, format('select public.usuario_da_alcance(%L, %L, %L::text[])', t5, 'agente', '{lawang}'), 'select (select count(*) > 0 from public.usuarios_cambios_alcance)::text', true, true), 'true');
  perform pg_temp.espera('S4 un admin_empresa NO lee el registro',
    pg_temp.corre(a, ae, null, 'select (select count(*) from public.usuarios_cambios_alcance)::text', true, true), '0');
  perform pg_temp.espera('S4 un super_admin_empresa NO lee el registro',
    pg_temp.corre(s, se, null, 'select (select count(*) from public.usuarios_cambios_alcance)::text', true, true), '0');
  perform pg_temp.espera('S4 anon no toca el registro', pg_temp.corre(a, ae, 'set local role anon; select count(*) from public.usuarios_cambios_alcance', null, false), 'E42501');
  perform pg_temp.espera('S4 authenticated no escribe en el registro', pg_temp.corre(jv, je, format('insert into public.usuarios_cambios_alcance (a_quien, accion, antes, despues) values (%L, %L, %L::jsonb, %L::jsonb)', t5, 'alta', '{}', '{}')), 'E42501');

  -- ================================================================ SECCION 5: alta de personas desde un rol de empresa
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
  select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', u.em, u.cre, now(), now(), u.meta, '{}'::jsonb
    from (values (nu,  'b5-nuevo-1@prueba.invalid', now(), '{}'::jsonb),
                 (nu2, 'b5-nuevo-2@prueba.invalid', now(), '{}'::jsonb),
                 (nu3, 'b5-nuevo-3@prueba.invalid', now() - interval '3 hours', '{}'::jsonb),
                 (nu4, 'b5-nuevo-4@prueba.invalid', now(), '{"agente": true}'::jsonb),
                 (nu5, 'b5-nuevo-5@prueba.invalid', now(), '{}'::jsonb),
                 (nu6, 'b5-nuevo-6@prueba.invalid', now(), '{}'::jsonb)) as u(id, em, cre, meta);
  cons := 'select (select rol || ''/'' || ambito || ''/'' || empresas::text || ''/'' || creado_por from public.usuarios where user_id = ';
  perform pg_temp.espera('S5 A da de alta un agente (nace con sus empresas, global, creado_por = A)',
    pg_temp.corre(a, ae, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu, 'b5-nuevo-1@prueba.invalid', 'Nuevo Uno', 'agente', '{contratos}', '{carta_reserva}'),
                  cons || quote_literal(nu) || ')'), 'agente/global/{lawang}/' || ae);
  perform pg_temp.espera('S5 el alta deja registro', pg_temp.corre(a, ae, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu, 'b5-nuevo-1@prueba.invalid', 'Nuevo Uno', 'agente', '{contratos}', '{}'),
                  format('select (select count(*) from public.usuarios_cambios_alcance where a_quien = %L and accion = %L and quien = %L)::text', nu, 'alta', a), true, false), '1');
  perform pg_temp.espera('S5 A da de alta un sales_manager', pg_temp.corre(a, ae, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu2, 'b5-nuevo-2@prueba.invalid', 'N2', 'sales_manager', '{contratos}', '{}')), 'E42501');
  perform pg_temp.espera('S5 A da de alta un admin', pg_temp.corre(a, ae, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu2, 'b5-nuevo-2@prueba.invalid', 'N2', 'admin_empresa', '{contratos}', '{}')), 'E42501');
  perform pg_temp.espera('S5 A da herramientas que no tiene', pg_temp.corre(a, ae, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu2, 'b5-nuevo-2@prueba.invalid', 'N2', 'agente', '{facturas}', '{}')), 'E42501');
  perform pg_temp.espera('S5 A da tipos que no tiene', pg_temp.corre(a, ae, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu2, 'b5-nuevo-2@prueba.invalid', 'N2', 'agente', '{contratos}', '{construccion}')), 'E42501');
  perform pg_temp.espera('S5 A pide una empresa que no es suya', pg_temp.corre(a, ae, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], %L::text[])', nu2, 'b5-nuevo-2@prueba.invalid', 'N2', 'agente', '{contratos}', '{}', '{sandal_woods}')), 'E42501');
  perform pg_temp.espera('S5 S (super) da de alta un sales_manager de sandal', pg_temp.corre(s, se, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu2, 'b5-nuevo-2@prueba.invalid', 'N2', 'sales_manager', '{contratos}', '{construccion}'),
                  cons || quote_literal(nu2) || ')'), 'sales_manager/global/{sandal_woods}/' || se);
  perform pg_temp.espera('S5 D con dos empresas: sin indicar = las dos', pg_temp.corre(d, de, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu5, 'b5-nuevo-5@prueba.invalid', 'N5', 'agente', '{contratos}', '{}'),
                  cons || quote_literal(nu5) || ')'), 'agente/global/{lawang,sandal_woods}/' || de);
  perform pg_temp.espera('S5 D con dos empresas: subconjunto', pg_temp.corre(d, de, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], %L::text[])', nu6, 'b5-nuevo-6@prueba.invalid', 'N6', 'agente', '{contratos}', '{}', '{sandal_woods}'),
                  cons || quote_literal(nu6) || ')'), 'agente/global/{sandal_woods}/' || de);
  perform pg_temp.espera('S5 X (sin casilla usuarios)', pg_temp.corre(x, xe, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu3, 'b5-nuevo-3@prueba.invalid', 'N3', 'agente', '{contratos}', '{}')), 'E42501');
  perform pg_temp.espera('S5 agente de control', pg_temp.corre(c, ce, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu3, 'b5-nuevo-3@prueba.invalid', 'N3', 'agente', '{contratos}', '{}')), 'E42501');
  perform pg_temp.espera('S5 admin global no tiene esta puerta', pg_temp.corre(adm, adme, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu3, 'b5-nuevo-3@prueba.invalid', 'N3', 'agente', '{contratos}', '{}')), 'E42501');
  perform pg_temp.espera('S5 cuenta de Auth VIEJA (no se convierte una cuenta ajena)', pg_temp.corre(s, se, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu3, 'b5-nuevo-3@prueba.invalid', 'N3', 'agente', '{contratos}', '{}')), 'E22023');
  perform pg_temp.espera('S5 cuenta con el marcador legacy agente', pg_temp.corre(s, se, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu4, 'b5-nuevo-4@prueba.invalid', 'N4', 'agente', '{contratos}', '{}')), 'E22023');
  perform pg_temp.espera('S5 correo que no coincide con la cuenta', pg_temp.corre(s, se, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu5, 'otro@prueba.invalid', 'N5', 'agente', '{contratos}', '{}')), 'E22023');
  insert into public.usuarios (user_id, email, rol) values (nu, 'b5-nuevo-1@prueba.invalid', 'agente');   -- como postgres: ya tiene ficha
  perform pg_temp.espera('S5 una persona que ya tiene ficha', pg_temp.corre(s, se, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu, 'b5-nuevo-1@prueba.invalid', 'Nuevo Uno', 'agente', '{contratos}', '{}')), 'E22023');
  perform pg_temp.espera('S5 un user_id que no existe en Auth', pg_temp.corre(s, se, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', gen_random_uuid(), 'zz@prueba.invalid', 'Z', 'agente', '{contratos}', '{}')), 'E22023');
  perform pg_temp.espera('S5 anon no puede llamar a la funcion de alta', pg_temp.corre(a, ae, format('set local role anon; select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', nu6, 'b5-nuevo-6@prueba.invalid', 'N6', 'agente', '{contratos}', '{}'), null, false), 'E42501');
  -- correo de un comprador del portal: un acceso de portal con ese correo bloquea el alta aunque la cuenta sea nueva
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
  values (np, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b5-portal@prueba.invalid', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);
  insert into public.portal_accesos (email, client_id) select 'b5-portal@prueba.invalid', id from public.clients limit 1;
  perform pg_temp.espera('S5 correo de comprador del portal', pg_temp.corre(s, se, format('select public.usuario_alta_empresa(%L, %L, %L, %L, %L::text[], %L::text[], null)', np, 'b5-portal@prueba.invalid', 'P', 'agente', '{contratos}', '{}')), 'E22023');
  -- el ultimo cerrojo: aunque se saltase la funcion, el candado de alta de la tabla exige la misma regla
  perform pg_temp.espera('S5 candado de alta: insertar con empresas ajenas lo para el trigger (llamada con claims de A, como postgres)',
    pg_temp.corre(a, ae, format('insert into public.usuarios (user_id, email, rol, ambito, empresas) values (%L, %L, %L, %L, %L::text[])', nu3, 'b5-nuevo-3@prueba.invalid', 'agente', 'global', '{sandal_woods}'), null, false), 'E42501');
  perform pg_temp.espera('S5 candado de alta: insertar un admin_empresa lo para el trigger',
    pg_temp.corre(a, ae, format('insert into public.usuarios (user_id, email, rol, ambito, empresas) values (%L, %L, %L, %L, %L::text[])', nu3, 'b5-nuevo-3@prueba.invalid', 'admin_empresa', 'empresa', '{lawang}'), null, false), 'E42501');

  -- ================================================================ SECCION 6: poner la clave de otra cuenta
  perform pg_temp.espera('S6 A puede poner la clave de t5? (global sin empresas)', pg_temp.corre(a, ae, null, format('select public.usuario_puede_poner_clave(%L)::text', t5)), 'false');
  perform pg_temp.espera('S6 A sobre t4 (PM lawang, herramientas suyas)', pg_temp.corre(a, ae, null, format('select public.usuario_puede_poner_clave(%L)::text', t4)), 'true');
  perform pg_temp.espera('S6 A sobre t2 (sandal)', pg_temp.corre(a, ae, null, format('select public.usuario_puede_poner_clave(%L)::text', t2)), 'false');
  perform pg_temp.espera('S6 A sobre t6 (herramienta facturas que A no tiene)', pg_temp.corre(a, ae, null, format('select public.usuario_puede_poner_clave(%L)::text', t6)), 'false');
  perform pg_temp.espera('S6 A sobre el propietario', pg_temp.corre(a, ae, null, format('select public.usuario_puede_poner_clave(%L)::text', jv)), 'false');
  perform pg_temp.espera('S6 A sobre S (otro rol de empresa)', pg_temp.corre(a, ae, null, format('select public.usuario_puede_poner_clave(%L)::text', s)), 'false');
  perform pg_temp.espera('S6 S sobre t8 (PM sandal)', pg_temp.corre(s, se, null, format('select public.usuario_puede_poner_clave(%L)::text', t8)), 'true');
  perform pg_temp.espera('S6 control agente sobre t4', pg_temp.corre(c, ce, null, format('select public.usuario_puede_poner_clave(%L)::text', t4)), 'false');
  perform pg_temp.espera('S6 anon no llama', pg_temp.corre(a, ae, format('set local role anon; select public.usuario_puede_poner_clave(%L)', t4), null, false), 'E42501');

  -- ================================================================ SECCION 7: quien ve que fichas de `usuarios`
  for cu in select * from (values (a, ae, '{lawang}'::text[]), (s, se, '{sandal_woods}'), (d, de, '{lawang,sandal_woods}'), (t1, t1e, '{lawang}'), (t4, t4e, '{lawang}')) q(u, e, em) loop
    perform pg_temp.espera('S7 ' || cu.e || ' ve las fichas esperadas (su ficha + comparten empresa + globales sin empresas)',
      pg_temp.corre(cu.u, cu.e, null, 'select (select count(*) from public.usuarios)::text', true, true),
      (select count(*)::text from public.usuarios w where w.user_id = cu.u or cardinality(w.empresas) = 0 or w.empresas && cu.em));
    perform pg_temp.espera('S7 ' || cu.e || ' (lw_lector) ve lo mismo',
      pg_temp.corre(cu.u, cu.e, 'set local role lw_lector', 'select (select count(*) from public.usuarios)::text', false, true),
      (select count(*)::text from public.usuarios w where w.user_id = cu.u or cardinality(w.empresas) = 0 or w.empresas && cu.em));
  end loop;
  perform pg_temp.espera('S7 A NO ve la ficha de t2 (solo sandal)', pg_temp.corre(a, ae, null, format('select (select count(*) from public.usuarios where user_id = %L)::text', t2), true, true), '0');
  perform pg_temp.espera('S7 A NO ve a S (super de sandal)', pg_temp.corre(a, ae, null, format('select (select count(*) from public.usuarios where user_id = %L)::text', s), true, true), '0');
  perform pg_temp.espera('S7 A ve a t3 (las dos)', pg_temp.corre(a, ae, null, format('select (select count(*) from public.usuarios where user_id = %L)::text', t3), true, true), '1');
  perform pg_temp.espera('S7 A ve al propietario (global sin empresas: nombre de autor)', pg_temp.corre(a, ae, null, format('select (select count(*) from public.usuarios where user_id = %L)::text', jv), true, true), '1');
  perform pg_temp.espera('S7 agente de control (sin restringir) ve TODAS', pg_temp.corre(c, ce, null, 'select (select count(*) from public.usuarios)::text', true, true), (select count(*)::text from public.usuarios));
  perform pg_temp.espera('S7 admin global ve TODAS', pg_temp.corre(adm, adme, null, 'select (select count(*) from public.usuarios)::text', true, true), (select count(*)::text from public.usuarios));

  -- ================================================================ SECCION 8: no hay mas puertas abiertas
  perform pg_temp.espera('S8 los ayudantes privados no se llaman desde fuera (A)', pg_temp.corre(a, ae, format('select public._usuario_gestionable(%L)', t1)), 'E42501');
  perform pg_temp.espera('S8 _alta_empresa_permitida no se llama desde fuera', pg_temp.corre(a, ae, 'select public._alta_empresa_permitida(''agente'',''global'',''{lawang}'',''{}'',''{}'',false)'), 'E42501');
  perform pg_temp.espera('S8 mis_empresas la puede llamar lw_lector', pg_temp.corre(a, ae, 'set local role lw_lector', 'select public.mis_empresas()::text', false, true), '{lawang}');
  perform pg_temp.espera('S8 mis_empresas no la llama anon', pg_temp.corre(a, ae, 'set local role anon; select public.mis_empresas()', null, false), 'E42501');

  select count(*) filter (where not ok), count(*) filter (where ok) into fallos, oks from res;
  select string_agg(case when ok then null else 'FALLO ' || detalle end, E'\n' order by n) into resumen from res;
  raise exception E'B5\n%\n%OK=%  FALLOS=%', coalesce(resumen, ''), dif, oks, fallos;
end $t$;
