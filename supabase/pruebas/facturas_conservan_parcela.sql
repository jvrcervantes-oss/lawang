-- Prueba «las facturas guardan "<proyecto> — <parcela>" desde el enlace» (14/15-oct-2026, migracion 20261014220000_facturas_conservan_parcela,
-- 2.a version tras el revisor: espejo construido en el servidor desde contrato y proyecto; renombrar_proyecto no se toca).
-- Rol REAL donde hay camino de usuario: factura_guarda como el agente autor y renombrar_proyecto como el admin de la empresa, con
-- `set local role authenticated` y sus claims (pg_temp.val, el armazon de cf_borrar_cierre_anula.sql). El trigger, ademas, se mira
-- como postgres (T3-T6): es lo que corre en cualquier UPDATE, venga de donde venga.
-- !! CREA CONTRATOS Y FACTURAS (gasta numeracion de facturas): SOLO EN RAMA, NUNCA EN LA BASE VIVA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261014220000_facturas_conservan_parcela.sql
--           --prueba facturas_conservan_parcela.sql
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada linea acaba en «→ ok» o «→ FALLA». Todo va marcado ZZ-PN.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create temp table _tp (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text) returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
  execute 'set local role authenticated';
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return t;
end $f$;
-- el payload de factura_guarda que manda la pantalla: proyecto_nombre arriba y en datos.fields (de ahi se pinta el papel)
create or replace function pg_temp.doc(p_contrato uuid, p_proy text, p_linea text) returns jsonb language sql immutable as $f$
  select jsonb_build_object('tipo', 'factura', 'sociedad', 'zz_pn', 'contrato_id', p_contrato, 'moneda', 'EUR', 'total', '10',
           'proyecto_nombre', p_proy,
           'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', p_linea, 'importe', '10')),
                                       'fields', jsonb_build_object('proyecto_nombre', p_proy)))
$f$;

insert into _tp values ('A',  gen_random_uuid(), 'zz-pn-agente@prueba.invalid'),
                       ('AE', gen_random_uuid(), 'zz-pn-admin-empresa@prueba.invalid');

do $todo$
declare
  r text := ''; v text;
  a _tp; ae _tp;
  pL uuid; pLn text; pX uuid; pXn text; k1 uuid; kX uuid; f1 uuid; f2 uuid; f3 uuid; f4 uuid; f5 uuid; fX uuid;
  c_emp constant text := 'zz_pn';
  c_par constant text := ' — C5';
  c_fin constant text := 'FIN DE PRUEBAS FACTURAS CONSERVAN PARCELA (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS FACTURAS CONSERVAN PARCELA:%', E'\nP0 esta prueba crea contratos y facturas: solo corre en rama → FALLA';
  end if;
  select * into a from _tp where et = 'A'; select * into ae from _tp where et = 'AE';

  -- ============================================================ P. montaje (como postgres, SIN sesion)
  perform set_config('request.jwt.claims', '', true);
  begin
    insert into public.empresas (clave, nombre) values (c_emp, 'ZZ-PN Empresa');
    insert into public.sociedades (clave, label, razon, domicilio) values ('zz_pn', 'ZZ-PN', 'ZZ-PN PT', 'ZZ-domicilio')
      on conflict (clave) do nothing;
    update public.empresas set sociedad_clave = 'zz_pn' where clave = c_emp;
    -- pX empieza por el nombre de pL: ni el renombrado ni un cambio de proyecto pueden dejar restos de uno en el otro
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-PN Proyecto', 'zz-pn-proyecto', c_emp, true)
      returning id, nombre into pL, pLn;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-PN Proyecto largo', 'zz-pn-proyecto-largo', c_emp, true)
      returning id, nombre into pX, pXn;
    insert into auth.users (id, instance_id, email, aud, role)
      select t.uid, '00000000-0000-0000-0000-000000000000', t.em, 'authenticated', 'authenticated' from _tp t;
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (a.uid,  a.em,  'ZZ-PN Agente',        'agente',        'global',  array[c_emp], array[pL, pX], '{}'::uuid[], '{contratos,facturas}'::text[], '{contrato_general}'::text[], true),
      (ae.uid, ae.em, 'ZZ-PN Admin empresa', 'admin_empresa', 'empresa', array[c_emp], '{}'::uuid[],  '{}'::uuid[], '{contratos,facturas}'::text[], '{}'::text[], true);
    -- contratos con su unidad en datos.fields (la fuente de la parcela); sin disparadores: la parcela no existe en el
    -- inventario de la rama y aqui solo importa el texto que lee el espejo
    execute 'set local session_replication_role = replica';
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, datos, creado_por)
      values ('ZZ-PN-K1', 'contrato_general', pL, pLn, 'EUR', 1000, '{"hitos":[],"fields":{"parcela_codigo":"C5"}}', a.em) returning id into k1;
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, datos, creado_por)
      values ('ZZ-PN-KX', 'contrato_general', pX, pXn, 'EUR', 1000, '{"hitos":[],"fields":{"parcela_codigo":"Z9"}}', a.em) returning id into kX;
    execute 'set local session_replication_role = origin';
  exception when others then
    raise exception using message = replace(c_fin, '%', pg_temp.l(false, 'P0 montaje: ' || sqlstate || ' ' || left(sqlerrm, 300)));
  end;

  -- ============================================================ T1-T2: el camino de la pantalla (factura_guarda, agente autor)
  v := pg_temp.val(a.uid, a.em, format('select (select g.id from public.factura_guarda(null, %L::jsonb) g)::text', pg_temp.doc(k1, pLn || c_par, 'Reserva')));
  r := r || pg_temp.l(v !~ '^ERR', 'T1 el agente emite sobre el contrato de C5 (' || coalesce(left(v, 120), 'null') || ')');
  if v !~ '^ERR' and v is not null then
    f1 := v::uuid;
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f1) = pLn || c_par, 'T1b al emitir, la columna es «proyecto — C5»: ' || coalesce((select proyecto_nombre from public.facturas where id = f1), 'null'));
    v := pg_temp.val(a.uid, a.em, format('select (select g.id from public.factura_guarda(%L::uuid, %L::jsonb) g)::text', f1, pg_temp.doc(k1, pLn || c_par, 'Reserva — concepto nuevo')));
    r := r || pg_temp.l(v !~ '^ERR', 'T2 el agente edita el concepto (' || coalesce(left(v, 120), 'null') || ')');
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f1) = pLn || c_par, 'T2b al EDITAR, la columna conserva la parcela (el fallo de REC00019)');
    r := r || pg_temp.l((select datos #>> '{lineas,0,descripcion}' from public.facturas where id = f1) = 'Reserva — concepto nuevo', 'T2c y el cambio de concepto entro');
  end if;
  -- T2d: la pantalla manda OTRO texto (una parcela que el contrato no tiene): la columna no se lo cree
  v := pg_temp.val(a.uid, a.em, format('select (select g.id from public.factura_guarda(null, %L::jsonb) g)::text', pg_temp.doc(k1, 'Cualquier cosa — Z99', 'Otra')));
  if v !~ '^ERR' and v is not null then
    f4 := v::uuid;
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f4) = pLn || c_par, 'T2d el texto que manda la pantalla no cuenta: ' || coalesce((select proyecto_nombre from public.facturas where id = f4), 'null'));
  else
    r := r || pg_temp.l(false, 'T2d emitir con texto ajeno: ' || coalesce(left(v, 160), 'null'));
  end if;

  -- ============================================================ T3-T6: la regla del trigger (como postgres)
  begin
    -- INSERT con proyecto_id vacio y contrato: el texto sale del contrato (el alta de la pantalla)
    insert into public.facturas (tipo, numero, sociedad, contrato_id, proyecto_id, proyecto_nombre, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-PN-F2', 'zz_pn', k1, null, 'lo que sea', 10, 'EUR', a.em, 'ZZ-PN', '{"fields": {}}'::jsonb) returning id into f2;
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f2) = pLn || c_par, 'T3 alta sin proyecto_id: la columna sale del contrato: ' || coalesce((select proyecto_nombre from public.facturas where id = f2), 'null'));
    update public.facturas set proyecto_nombre = 'Texto libre — C5' where id = f2;
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f2) = pLn || c_par, 'T3b un texto libre al editar se recompone desde el enlace');
    -- sin contrato: el nombre a secas aunque llegue «— C5» (decision por defecto del 15-oct)
    insert into public.facturas (tipo, numero, sociedad, contrato_id, proyecto_id, proyecto_nombre, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-PN-F5', 'zz_pn', null, pL, pLn || c_par, 10, 'EUR', a.em, 'ZZ-PN', '{"fields": {}}'::jsonb) returning id into f5;
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f5) = pLn, 'T4 sin contrato enlazado, el nombre del proyecto a secas');
    -- de «X largo» a «X» (el caso MEDIA del revisor): sin restos del largo
    insert into public.facturas (tipo, numero, sociedad, contrato_id, proyecto_id, proyecto_nombre, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-PN-FX', 'zz_pn', kX, pX, 'x', 10, 'EUR', a.em, 'ZZ-PN', jsonb_build_object('fields', jsonb_build_object('proyecto_nombre', pXn || ' — Z9')))
      returning id into fX;
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = fX) = pXn || ' — Z9', 'T5 fX en el proyecto largo: «' || coalesce((select proyecto_nombre from public.facturas where id = fX), 'null') || '»');
    update public.facturas set proyecto_id = pX, contrato_id = kX where id = f2;
    update public.facturas set proyecto_id = pL, contrato_id = k1 where id = f2;
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f2) = pLn || c_par, 'T5b de «X largo» a «X» con su contrato: «' || coalesce((select proyecto_nombre from public.facturas where id = f2), 'null') || '»');
    begin
      update public.contratos set proyecto_nombre = pLn || c_par where id = k1;
      r := r || pg_temp.l((select proyecto_nombre from public.contratos where id = k1) = pLn, 'T6 contratos NO cambia: su proyecto_nombre se normaliza siempre');
    exception when others then
      r := r || pg_temp.l(false, 'T6 contratos: ' || sqlstate || ' ' || left(sqlerrm, 160));
    end;
    -- f3: ENVIADA del contrato de C5 (para el renombrado: columna si, papel no)
    insert into public.facturas (tipo, numero, sociedad, contrato_id, proyecto_id, proyecto_nombre, total, moneda, creado_por, cliente_nombre, datos, enviada)
      values ('factura', 'ZZ-PN-F3', 'zz_pn', k1, pL, 'x', 10, 'EUR', a.em, 'ZZ-PN', jsonb_build_object('fields', jsonb_build_object('proyecto_nombre', pLn || c_par)), true)
      returning id into f3;
  exception when others then
    r := r || pg_temp.l(false, 'T3-T6 montaje/regla: ' || sqlstate || ' ' || left(sqlerrm, 200));
  end;

  -- ============================================================ T7: renombrar_proyecto (admin de la empresa, rol real), SIN tocar la funcion
  v := pg_temp.val(a.uid, a.em, format('select public.renombrar_proyecto(%L, %L)::text', pLn, 'ZZ-PN Proyecto Nuevo'));
  r := r || pg_temp.l(v ~ '^ERR42501', 'T7a el agente no renombra (42501, como antes): ' || left(v, 60));
  -- un nombre que ALARGA el viejo (el caso ALTA del revisor: con la 1.a version salia «… Nuevo Nuevo — C5»)
  v := pg_temp.val(ae.uid, ae.em, format('select public.renombrar_proyecto(%L, %L)::text', pLn, 'ZZ-PN Proyecto Nuevo'));
  r := r || pg_temp.l(v !~ '^ERR', 'T7 el admin de la empresa renombra alargando (' || left(v, 160) || ')');
  if f1 is not null then
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f1) = 'ZZ-PN Proyecto Nuevo' || c_par, 'T7b columna exacta tras alargar: «' || coalesce((select proyecto_nombre from public.facturas where id = f1), 'null') || '»');
    r := r || pg_temp.l((select datos #>> '{fields,proyecto_nombre}' from public.facturas where id = f1) = 'ZZ-PN Proyecto Nuevo' || c_par, 'T7c y su papel (no enviada): «' || coalesce((select datos #>> '{fields,proyecto_nombre}' from public.facturas where id = f1), 'null') || '»');
  end if;
  r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f3) = 'ZZ-PN Proyecto Nuevo' || c_par, 'T7d la ENVIADA cambia la columna');
  r := r || pg_temp.l((select datos #>> '{fields,proyecto_nombre}' from public.facturas where id = f3) = pLn || c_par, 'T7e pero no su papel (datos.fields de una enviada no se toca, como antes)');
  r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = fX) = pXn || ' — Z9', 'T7f el otro proyecto cuyo nombre empieza igual NO se toca');
  -- un nombre que NO alarga (otro choque posible entre el renombrado y el espejo)
  v := pg_temp.val(ae.uid, ae.em, format('select public.renombrar_proyecto(%L, %L)::text', 'ZZ-PN Proyecto Nuevo', 'ZZ-PN Otro'));
  r := r || pg_temp.l(v !~ '^ERR', 'T8 renombrar sin alargar (' || left(v, 160) || ')');
  if f1 is not null then
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f1) = 'ZZ-PN Otro' || c_par, 'T8b columna exacta: «' || coalesce((select proyecto_nombre from public.facturas where id = f1), 'null') || '»');
  end if;
  r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = fX) = pXn || ' — Z9', 'T8c el proyecto largo sigue sin tocar');

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
