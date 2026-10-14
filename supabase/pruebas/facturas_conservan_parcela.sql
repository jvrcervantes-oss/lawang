-- Prueba «las facturas conservan "<proyecto> — <parcela>" al editarse» (14-oct-2026, migracion 20261014220000_facturas_conservan_parcela).
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
  r text := ''; v text; n bigint;
  a _tp; ae _tp;
  pL uuid; pLn text; pX uuid; pXn text; k1 uuid; f1 uuid; f2 uuid; f3 uuid; fX uuid;
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
    -- pX empieza por el nombre de pL: el renombrado no debe tocar sus documentos
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-PN Proyecto', 'zz-pn-proyecto', c_emp, true)
      returning id, nombre into pL, pLn;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-PN Proyecto largo', 'zz-pn-proyecto-largo', c_emp, true)
      returning id, nombre into pX, pXn;
    insert into auth.users (id, instance_id, email, aud, role)
      select t.uid, '00000000-0000-0000-0000-000000000000', t.em, 'authenticated', 'authenticated' from _tp t;
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (a.uid,  a.em,  'ZZ-PN Agente',        'agente',        'global',  array[c_emp], array[pL, pX], '{}'::uuid[], '{contratos,facturas}'::text[], '{contrato_general}'::text[], true),
      (ae.uid, ae.em, 'ZZ-PN Admin empresa', 'admin_empresa', 'empresa', array[c_emp], '{}'::uuid[],  '{}'::uuid[], '{contratos,facturas}'::text[], '{}'::text[], true);
    insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por)
      values ('ZZ-PN-K1', 'contrato_general', pL, 'EUR', 1000, '{"hitos":[]}', a.em) returning id into k1;
  exception when others then
    raise exception using message = replace(c_fin, '%', pg_temp.l(false, 'P0 montaje: ' || sqlstate || ' ' || left(sqlerrm, 300)));
  end;

  -- ============================================================ T1-T2: el camino de la pantalla (factura_guarda, agente autor)
  v := pg_temp.val(a.uid, a.em, format('select (select g.id from public.factura_guarda(null, %L::jsonb) g)::text', pg_temp.doc(k1, pLn || c_par, 'Reserva')));
  r := r || pg_temp.l(v !~ '^ERR', 'T1 el agente emite con «proyecto — C5» (' || coalesce(left(v, 120), 'null') || ')');
  if v !~ '^ERR' and v is not null then
    f1 := v::uuid;
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f1) = pLn || c_par, 'T1b al emitir, la columna guarda la parcela');
    v := pg_temp.val(a.uid, a.em, format('select (select g.id from public.factura_guarda(%L::uuid, %L::jsonb) g)::text', f1, pg_temp.doc(k1, pLn || c_par, 'Reserva — concepto nuevo')));
    r := r || pg_temp.l(v !~ '^ERR', 'T2 el agente edita el concepto (' || coalesce(left(v, 120), 'null') || ')');
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f1) = pLn || c_par, 'T2b al EDITAR, la columna conserva la parcela (el fallo de REC00019)');
    r := r || pg_temp.l((select datos #>> '{lineas,0,descripcion}' from public.facturas where id = f1) = 'Reserva — concepto nuevo', 'T2c y el cambio de concepto entro');
  end if;

  -- ============================================================ T3-T6: la regla del trigger (como postgres)
  begin
    insert into public.facturas (tipo, numero, sociedad, contrato_id, proyecto_id, proyecto_nombre, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-PN-F2', 'zz_pn', k1, pL, pLn || c_par, 10, 'EUR', a.em, 'ZZ-PN', '{"fields": {}}'::jsonb) returning id into f2;
    update public.facturas set proyecto_nombre = 'Texto libre — C5' where id = f2;
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f2) = pLn, 'T3 un texto que no empieza por el proyecto se normaliza al nombre (como antes)');
    update public.facturas set proyecto_nombre = pLn || ' ' where id = f2;
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f2) = pLn, 'T4 «proyecto + espacio» sin nada detras se normaliza');
    update public.facturas set proyecto_nombre = pLn || c_par where id = f2;
    begin
      update public.facturas set proyecto_id = pX where id = f2;
      r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f2) = pXn, 'T5 al cambiar de proyecto, la parcela del viejo no se arrastra');
    exception when others then
      r := r || pg_temp.l(false, 'T5 cambiar de proyecto: ' || sqlstate || ' ' || left(sqlerrm, 160));
    end;
    begin
      update public.contratos set proyecto_nombre = pLn || c_par where id = k1;
      r := r || pg_temp.l((select proyecto_nombre from public.contratos where id = k1) = pLn, 'T6 contratos NO cambia: su proyecto_nombre se normaliza siempre');
    exception when others then
      r := r || pg_temp.l(false, 'T6 contratos: ' || sqlstate || ' ' || left(sqlerrm, 160));
    end;
    -- documentos para el renombrado: f3 con parcela en pL (enviada: columna si, datos no); fX en pX con nombre que empieza como pL
    insert into public.facturas (tipo, numero, sociedad, contrato_id, proyecto_id, proyecto_nombre, total, moneda, creado_por, cliente_nombre, datos, enviada)
      values ('factura', 'ZZ-PN-F3', 'zz_pn', k1, pL, pLn || ' — B4', 10, 'EUR', a.em, 'ZZ-PN', jsonb_build_object('fields', jsonb_build_object('proyecto_nombre', pLn || ' — B4')), true)
      returning id into f3;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, proyecto_id, proyecto_nombre, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-PN-FX', 'zz_pn', k1, pX, pXn || ' — Z9', 10, 'EUR', a.em, 'ZZ-PN', jsonb_build_object('fields', jsonb_build_object('proyecto_nombre', pXn || ' — Z9')))
      returning id into fX;
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = fX) = pXn || ' — Z9', 'T6b el montaje de fX conserva su parcela');
  exception when others then
    r := r || pg_temp.l(false, 'T3-T6 montaje/regla: ' || sqlstate || ' ' || left(sqlerrm, 200));
  end;

  -- ============================================================ T7: renombrar_proyecto (admin de la empresa, rol real)
  v := pg_temp.val(a.uid, a.em, format('select public.renombrar_proyecto(%L, %L)::text', pLn, 'ZZ-PN Nuevo'));
  r := r || pg_temp.l(v ~ '^ERR42501', 'T7a el agente no renombra (42501, como antes): ' || left(v, 60));
  v := pg_temp.val(ae.uid, ae.em, format('select public.renombrar_proyecto(%L, %L)::text', pLn, 'ZZ-PN Nuevo'));
  r := r || pg_temp.l(v !~ '^ERR', 'T7 el admin de la empresa renombra (' || left(v, 160) || ')');
  if f1 is not null then
    r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f1) = 'ZZ-PN Nuevo' || c_par, 'T7b la columna con parcela cambia el prefijo');
    r := r || pg_temp.l((select datos #>> '{fields,proyecto_nombre}' from public.facturas where id = f1) = 'ZZ-PN Nuevo' || c_par, 'T7c y su datos.fields (no enviada)');
  end if;
  r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = f3) = 'ZZ-PN Nuevo — B4', 'T7d la ENVIADA cambia la columna');
  r := r || pg_temp.l((select datos #>> '{fields,proyecto_nombre}' from public.facturas where id = f3) = pLn || ' — B4', 'T7e pero no su papel (datos.fields de una enviada no se toca, como antes)');
  r := r || pg_temp.l((select proyecto_nombre from public.facturas where id = fX) = pXn || ' — Z9', 'T7f el otro proyecto cuyo nombre empieza igual NO se toca');
  r := r || pg_temp.l(case when v is null or v ~ '^ERR' then false else (v::jsonb ->> 'facturas')::int >= 2 end, 'T7g el recuento de facturas incluye las de parcela');

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
