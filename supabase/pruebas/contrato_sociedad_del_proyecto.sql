-- Prueba de contrato_sociedad_existe del 15-oct-2026 (migracion 20261015073823_contrato_sociedad_del_proyecto): la sociedad
-- firmante de un contrato es la de la empresa de su proyecto, y la base lo exige solo cuando cambia la sociedad o el proyecto.
-- Cada NO lleva al lado un SI que solo cambia en lo que se prueba.
-- S1/S2 alta con la del proyecto entra; con otra se rechaza. S3 alta sin sociedad entra y NO se rellena (decision por defecto).
-- S4 alta que solo trae el NOMBRE del proyecto (este trigger corre antes que trg_espejo_proyecto): se rechaza igual.
-- S12 por contrato_guarda como authenticated (pantalla de antes rebota, la de ahora guarda; sin la clave se conserva, vacía se rechaza).
-- S5 cambiar la sociedad a otra se rechaza. S6 cambiar de proyecto a uno de otra empresa con la sociedad vieja se rechaza; con la
-- del proyecto nuevo entra. S7 un contrato viejo descuadrado (montado con el trigger apagado) se sigue pudiendo tocar (precio,
-- bloqueo) sin que reviente, y corregirlo a la del proyecto entra («corregir al reabrir»). S8 proyecto de una empresa sin
-- sociedad: no se exige nada. S9 hijo de una reserva descuadrada: manda el padre (con la del proyecto se rechaza, con la del
-- padre entra, vacio hereda la del padre, y con el padre ya FIRMADO sigue entrando). S10 documentos vivos mandan: con una
-- factura de otra sociedad no se cambia a la del proyecto (S10), se puede cambiar de proyecto sin tocarla (S10b), y con la
-- factura anulada vuelve a mandar el proyecto (S10c entra, S10d se rechaza).
-- !! CREA CONTRATOS (gasta numeracion) Y MONTA CASOS VIEJOS CON session_replication_role = replica: SOLO EN RAMA, NUNCA EN LA BASE VIVA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261015073823_contrato_sociedad_del_proyecto.sql
--           --prueba contrato_sociedad_del_proyecto.sql
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada linea acaba en «→ ok» o «→ FALLA». Todo va marcado ZZ-SP.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
-- ejecuta y devuelve 'OK' o el error (sqlstate:mensaje)
create or replace function pg_temp.x(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return 'ERR' || sqlstate || ':' || left(sqlerrm, 200);
end $f$;
-- ejecuta p_sql con la sesion de quien se dice (rol authenticated): el resultado en texto, o el error
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else
          json_build_object('sub', p_uid, 'role', p_rol, 'email', p_email)::text end, true);
  execute 'set local role ' || p_rol;
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(t, '(null)');
end $f$;
-- el p_contrato que manda la pantalla a contrato_guarda (contracts/app.html, contractPayload): tipo + datos.fields
create or replace function pg_temp.envio(p_proy_nombre text, p_soc text) returns jsonb language sql as $f$
  select jsonb_build_object('tipo', 'contrato_general',
           'datos', jsonb_build_object('hitos', '[]'::jsonb,
                      'fields', jsonb_strip_nulls(jsonb_build_object('proyecto_nombre', p_proy_nombre, 'sociedad_firmante', p_soc,
                                                                     'adq1_nombre', 'ZZ-SP Comprador'))))
$f$;
-- un contrato de prueba: id, o el error
create or replace function pg_temp.alta(p_num text, p_proy uuid, p_nombre text, p_fields jsonb, p_padre uuid default null) returns text
language plpgsql as $f$
declare v uuid;
begin
  insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, datos, creado_por, contrato_padre_id)
    values (p_num, 'contrato_general', p_proy, p_nombre, 'EUR', 100000,
            jsonb_build_object('hitos', '[]'::jsonb, 'fields', p_fields), 'zz-sp@prueba.invalid', p_padre)
    returning id into v;
  return v::text;
exception when others then
  return 'ERR' || sqlstate || ':' || left(sqlerrm, 200);
end $f$;

do $todo$
declare
  r text := ''; v text;
  p1 uuid; p1b uuid; p2 uuid; p3 uuid; k1 uuid; k3 uuid; k6 uuid; k7 uuid; kp uuid; k10 uuid; f10 uuid;
  ad uuid := gen_random_uuid(); c_ad constant text := 'zz-sp-admin@prueba.invalid'; k12 uuid;
  c_fin constant text := 'FIN DE PRUEBAS SOCIEDAD DEL PROYECTO (se deshace todo):%';
  c_rech constant text := 'ERR23514:La sociedad firmante «%» no es la del proyecto%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS SOCIEDAD DEL PROYECTO:%', E'\nP0 esta prueba crea contratos y monta casos sin disparadores: solo corre en rama → FALLA';
  end if;

  -- ============================================================ P. montaje (como postgres)
  begin
    insert into public.sociedades (clave, label, razon, domicilio) values
      ('zz_sp1', 'ZZ-SP 1', 'ZZ-SP PT 1', 'ZZ-domicilio'), ('zz_sp2', 'ZZ-SP 2', 'ZZ-SP PT 2', 'ZZ-domicilio')
      on conflict (clave) do nothing;
    insert into public.empresas (clave, nombre) values ('zz_sp_e1', 'ZZ-SP Empresa 1'), ('zz_sp_e2', 'ZZ-SP Empresa 2'), ('zz_sp_e3', 'ZZ-SP Empresa 3');
    update public.empresas set sociedad_clave = 'zz_sp1' where clave = 'zz_sp_e1';
    update public.empresas set sociedad_clave = 'zz_sp2' where clave = 'zz_sp_e2';   -- zz_sp_e3 se queda SIN sociedad (S8)
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-SP Proyecto 1', 'zz-sp-proyecto-1', 'zz_sp_e1', true) returning id into p1;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-SP Proyecto 1b', 'zz-sp-proyecto-1b', 'zz_sp_e1', true) returning id into p1b;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-SP Proyecto 2', 'zz-sp-proyecto-2', 'zz_sp_e2', true) returning id into p2;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-SP Proyecto 3', 'zz-sp-proyecto-3', 'zz_sp_e3', true) returning id into p3;
    r := r || pg_temp.l(true, 'P montaje: 2 sociedades, 3 empresas (la 3 sin sociedad), 3 proyectos');
  exception when others then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'P montaje: ' || sqlstate || ' ' || left(sqlerrm, 300)));
  end;

  -- ============================================================ S1/S2 alta
  v := pg_temp.alta('ZZ-SP-K1', p1, null, '{"sociedad_firmante": "zz_sp1"}');
  r := r || pg_temp.l(v !~ '^ERR', 'S1 alta en el proyecto 1 con SU sociedad entra (' || left(v, 90) || ')');
  if v !~ '^ERR' then k1 := v::uuid; end if;
  v := pg_temp.alta('ZZ-SP-K2', p1, null, '{"sociedad_firmante": "zz_sp2"}');
  r := r || pg_temp.l(v like c_rech, 'S2 alta en el proyecto 1 con la sociedad de OTRA empresa se rechaza (' || left(v, 120) || ')');

  -- ============================================================ S3 sin sociedad: entra y no se rellena
  v := pg_temp.alta('ZZ-SP-K3', p1, null, '{}');
  r := r || pg_temp.l(v !~ '^ERR'
                      and (select c.datos->'fields'->>'sociedad_firmante' from public.contratos c where c.id::text = v) is null,
                      'S3 alta sin sociedad entra y la base NO la rellena (' || left(v, 90) || ')');
  if v !~ '^ERR' then k3 := v::uuid; end if;

  -- ============================================================ S4 solo el nombre del proyecto
  v := pg_temp.alta('ZZ-SP-K4', null, 'ZZ-SP Proyecto 1', '{"sociedad_firmante": "zz_sp2"}');
  r := r || pg_temp.l(v like c_rech, 'S4 alta con solo el NOMBRE del proyecto 1 y otra sociedad se rechaza igual (' || left(v, 120) || ')');
  v := pg_temp.alta('ZZ-SP-K4b', null, 'ZZ-SP Proyecto 1', '{"sociedad_firmante": "zz_sp1"}');
  r := r || pg_temp.l(v !~ '^ERR', 'S4b la misma alta por nombre con SU sociedad entra (' || left(v, 90) || ')');

  -- ============================================================ S5 cambiar la sociedad
  v := pg_temp.x(format($q$update public.contratos set datos = jsonb_set(datos, '{fields,sociedad_firmante}', '"zz_sp2"') where id = %L$q$, k1));
  r := r || pg_temp.l(v like c_rech, 'S5 cambiar la sociedad de K1 a la de otra empresa se rechaza (' || left(v, 120) || ')');
  v := pg_temp.x(format($q$update public.contratos set datos = jsonb_set(datos, '{fields,sociedad_firmante}', '"zz_sp1"') where id = %L$q$, k3));
  r := r || pg_temp.l(v = 'OK', 'S5b poner a K3 (sin sociedad) la de su proyecto entra (' || left(v, 90) || ')');

  -- ============================================================ S6 cambiar de proyecto
  v := pg_temp.x(format($q$update public.contratos set proyecto_id = %L, proyecto_nombre = 'ZZ-SP Proyecto 2' where id = %L$q$, p2, k1));
  r := r || pg_temp.l(v like c_rech, 'S6 pasar K1 al proyecto 2 (otra empresa) con la sociedad vieja se rechaza (' || left(v, 120) || ')');
  v := pg_temp.x(format($q$update public.contratos set proyecto_id = %L, proyecto_nombre = 'ZZ-SP Proyecto 2',
                          datos = jsonb_set(datos, '{fields,sociedad_firmante}', '"zz_sp2"') where id = %L$q$, p2, k1));
  r := r || pg_temp.l(v = 'OK' and (select c.proyecto_id from public.contratos c where c.id = k1) = p2,
                      'S6b pasarlo al proyecto 2 CON la sociedad del 2 entra (' || left(v, 90) || ')');

  -- ============================================================ S7 contrato viejo descuadrado
  begin
    set local session_replication_role = replica;   -- montaje de un caso viejo sin disparadores (ALTER TABLE choca con los diferidos pendientes)
    v := pg_temp.alta('ZZ-SP-K7', p1, null, '{"sociedad_firmante": "zz_sp2"}');
    set local session_replication_role = origin;
    if v !~ '^ERR' then k7 := v::uuid; end if;
  exception when others then
    r := r || pg_temp.l(false, 'S7 montaje del descuadrado: ' || sqlstate || ' ' || left(sqlerrm, 200));
  end;
  if k7 is not null then
    v := pg_temp.x(format($q$update public.contratos set precio_total = 120000 where id = %L$q$, k7));
    r := r || pg_temp.l(v = 'OK', 'S7 a un descuadrado viejo se le puede cambiar el precio sin tocar la sociedad (' || left(v, 90) || ')');
    v := pg_temp.x(format($q$update public.contratos set datos = jsonb_set(datos, '{fields,resort}', '"ZZ-SP resort"') where id = %L$q$, k7));
    r := r || pg_temp.l(v = 'OK', 'S7b y otro campo de sus datos, tambien (' || left(v, 90) || ')');
    v := pg_temp.x(format($q$update public.contratos set datos = jsonb_set(datos, '{fields,sociedad_firmante}', '"zz_sp1"') where id = %L$q$, k7));
    r := r || pg_temp.l(v = 'OK', 'S7c corregirlo a la sociedad de su proyecto entra («corregir al reabrir») (' || left(v, 90) || ')');
  end if;

  -- ============================================================ S8 empresa sin sociedad
  v := pg_temp.alta('ZZ-SP-K8', p3, null, '{"sociedad_firmante": "zz_sp2"}');
  r := r || pg_temp.l(v !~ '^ERR', 'S8 proyecto de una empresa sin sociedad: cualquier sociedad activa entra, como antes (' || left(v, 90) || ')');

  -- ============================================================ S9 hijo de una reserva descuadrada
  begin
    set local session_replication_role = replica;   -- montaje de un caso viejo sin disparadores (ALTER TABLE choca con los diferidos pendientes)
    v := pg_temp.alta('ZZ-SP-KP', p1, null, '{"sociedad_firmante": "zz_sp2"}');
    set local session_replication_role = origin;
    if v !~ '^ERR' then kp := v::uuid; end if;
  exception when others then
    r := r || pg_temp.l(false, 'S9 montaje del padre: ' || sqlstate || ' ' || left(sqlerrm, 200));
  end;
  if kp is not null then
    v := pg_temp.alta('ZZ-SP-K9', p1, null, '{"sociedad_firmante": "zz_sp1"}', kp);
    r := r || pg_temp.l(v like 'ERR23514:La sociedad firmante «zz_sp1» no coincide con la del contrato del que cuelga%',
                        'S9 hijo con la del proyecto de un padre descuadrado: manda el padre y se rechaza (' || left(v, 120) || ')');
    v := pg_temp.alta('ZZ-SP-K9b', p1, null, '{"sociedad_firmante": "zz_sp2"}', kp);
    r := r || pg_temp.l(v !~ '^ERR', 'S9b hijo con la sociedad de su padre entra aunque no sea la del proyecto: con padre no aplica la del proyecto (' || left(v, 90) || ')');
    v := pg_temp.alta('ZZ-SP-K9c', p1, null, '{}', kp);
    r := r || pg_temp.l(v !~ '^ERR' and (select c.datos->'fields'->>'sociedad_firmante' from public.contratos c where c.id::text = v) = 'zz_sp2',
                        'S9c hijo sin sociedad hereda la del padre y entra (' || left(v, 90) || ')');
    -- el mismo padre ya FIRMADO (bloqueado): sigue habiendo salida para sus hijos
    begin
      set local session_replication_role = replica;
      update public.contratos set bloqueado = true where id = kp;
      set local session_replication_role = origin;
    exception when others then
      r := r || pg_temp.l(false, 'S9d montaje del padre firmado: ' || sqlstate || ' ' || left(sqlerrm, 200));
    end;
    v := pg_temp.alta('ZZ-SP-K9d', p1, null, '{"sociedad_firmante": "zz_sp2"}', kp);
    r := r || pg_temp.l(v !~ '^ERR', 'S9d hijo de un padre FIRMADO y descuadrado, con la sociedad del padre, entra (' || left(v, 90) || ')');
  end if;

  -- ============================================================ S10 documentos vivos mandan
  begin
    set local session_replication_role = replica;   -- montaje de un caso viejo sin disparadores (ALTER TABLE choca con los diferidos pendientes)
    v := pg_temp.alta('ZZ-SP-K10', p1, null, '{"sociedad_firmante": "zz_sp2"}');
    set local session_replication_role = origin;
    if v !~ '^ERR' then k10 := v::uuid; end if;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-SP-F10', 'zz_sp2', k10, 1000, 'EUR', 'zz-sp@prueba.invalid', 'ZZ-SP', '{"fields": {}}'::jsonb) returning id into f10;
  exception when others then
    r := r || pg_temp.l(false, 'S10 montaje (contrato descuadrado con factura): ' || sqlstate || ' ' || left(sqlerrm, 200));
  end;
  if f10 is not null then
    v := pg_temp.x(format($q$update public.contratos set datos = jsonb_set(datos, '{fields,sociedad_firmante}', '"zz_sp1"') where id = %L$q$, k10));
    r := r || pg_temp.l(v like 'ERR23514:La sociedad firmante «zz_sp1» no es la de sus facturas o recib%',
                        'S10 con una factura viva de zz_sp2, pasarlo a la sociedad del proyecto se rechaza (' || left(v, 120) || ')');
    -- a otro proyecto de la MISMA empresa 1 (zz_sp1), sin tocar la sociedad zz_sp2: sin documentos lo frenaría la regla del proyecto
    v := pg_temp.x(format($q$update public.contratos set proyecto_id = %L, proyecto_nombre = 'ZZ-SP Proyecto 1b' where id = %L$q$, p1b, k10));
    r := r || pg_temp.l(v = 'OK', 'S10b con documentos mandan ellos: cambiar a otro proyecto de zz_sp1 sin tocar su zz_sp2 entra (' || left(v, 90) || ')');
    set local session_replication_role = replica;   -- anular a pelo, sin el flujo de anulación (no es lo que se prueba)
    update public.facturas set anulada = true where id = f10;
    set local session_replication_role = origin;
    v := pg_temp.x(format($q$update public.contratos set datos = jsonb_set(datos, '{fields,sociedad_firmante}', '"zz_sp1"') where id = %L$q$, k10));
    r := r || pg_temp.l(v = 'OK', 'S10c con la factura anulada, pasarlo a la sociedad de su proyecto entra (' || left(v, 90) || ')');
    v := pg_temp.x(format($q$update public.contratos set datos = jsonb_set(datos, '{fields,sociedad_firmante}', '"zz_sp2"') where id = %L$q$, k10));
    r := r || pg_temp.l(v like c_rech, 'S10d y sin documentos vivos vuelve a mandar el proyecto: devolverlo a zz_sp2 se rechaza (' || left(v, 120) || ')');
    v := pg_temp.x(format($q$update public.contratos set datos = jsonb_set(datos, '{fields,sociedad_firmante}', '""') where id = %L$q$, k10));
    r := r || pg_temp.l(v like 'ERR23514:La sociedad firmante no se puede dejar vacía (era «zz_sp1»)%', 'S11 vaciar la sociedad de un contrato que la tenia se rechaza (' || left(v, 120) || ')');
    v := pg_temp.x(format($q$update public.contratos set datos = datos #- '{fields,sociedad_firmante}' where id = %L$q$, k10));
    r := r || pg_temp.l(v = 'OK' and (select c.datos->'fields'->>'sociedad_firmante' from public.contratos c where c.id = k10) = 'zz_sp1',
                        'S11b si la clave sociedad_firmante ni llega (plantilla sin el campo) se conserva la de antes (' || left(v, 120) || ')');
  end if;

  -- ============================================================ S12 por contrato_guarda, como authenticated (lo que hace la pantalla)
  -- contrato_guarda reescribe proyecto_nombre pero NO proyecto_id: la fila sigue en su proyecto (consulta de Backend, 15-oct).
  -- La pantalla, en un contrato guardado, manda el proyecto de la FILA y su sociedad (syncProyectoGuardado): eso tiene que entrar.
  begin
    insert into auth.users (id, instance_id, email, aud, role)
      values (ad, '00000000-0000-0000-0000-000000000000', c_ad, 'authenticated', 'authenticated');
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo)
      values (ad, c_ad, 'ZZ-SP Admin', 'admin', 'global', '{}'::text[], '{}'::uuid[], '{}'::uuid[], '{contratos}'::text[], '{}'::text[], true);
    v := pg_temp.val(ad, c_ad, format('select (public.contrato_guarda(null, %L::jsonb))->>''id''', pg_temp.envio('ZZ-SP Proyecto 1', 'zz_sp1')));
  exception when others then
    v := 'ERR' || sqlstate || ':' || left(sqlerrm, 200);
  end;
  r := r || pg_temp.l(v !~ '^ERR', 'S12 alta por contrato_guarda (admin, authenticated) en el proyecto 1 con su sociedad entra (' || left(v, 120) || ')');
  if v !~ '^ERR' then
    k12 := v::uuid;
    r := r || pg_temp.l((select c.proyecto_id from public.contratos c where c.id = k12) = p1, 'S12a la base lo deja en el proyecto 1 (por el nombre, en el alta)');
    v := pg_temp.val(ad, c_ad, format('select (public.contrato_guarda(%L, %L::jsonb))->>''id''', k12, pg_temp.envio('ZZ-SP Proyecto 2', 'zz_sp2')));
    r := r || pg_temp.l(v like c_rech and (select c.proyecto_id from public.contratos c where c.id = k12) = p1,
                        'S12b la pantalla de antes (proyecto 2 en el desplegable y su sociedad) rebota: proyecto_id no cambia por el nombre (' || left(v, 120) || ')');
    v := pg_temp.val(ad, c_ad, format('select (public.contrato_guarda(%L, %L::jsonb))->>''id''', k12, pg_temp.envio('ZZ-SP Proyecto 1', 'zz_sp1')));
    r := r || pg_temp.l(v = k12::text, 'S12c la pantalla de ahora (el proyecto de la fila y su sociedad) vuelve a guardar sin problema (' || left(v, 120) || ')');
    v := pg_temp.val(ad, c_ad, format('select (public.contrato_guarda(%L, %L::jsonb))->>''id''', k12, pg_temp.envio('ZZ-SP Proyecto 1', null)));
    r := r || pg_temp.l(v = k12::text and (select c.datos->'fields'->>'sociedad_firmante' from public.contratos c where c.id = k12) = 'zz_sp1',
                        'S12d por contrato_guarda sin la clave de la sociedad: guarda y la conserva (' || left(v, 120) || ')');
    v := pg_temp.val(ad, c_ad, format('select (public.contrato_guarda(%L, %L::jsonb))->>''id''', k12, pg_temp.envio('ZZ-SP Proyecto 1', '')));
    r := r || pg_temp.l(v like 'ERR23514:La sociedad firmante no se puede dejar vacía%',
                        'S12e por contrato_guarda con la sociedad vacía se rechaza (' || left(v, 120) || ')');
  end if;

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
