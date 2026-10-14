-- Prueba «el espejo del comprador solo sobre fichas que quien guarda puede ver, y el tipo permitido tambien al editar»
-- (14-oct-2026, migracion 20261014101500_espejo_cliente_visible). Rol REAL: cada llamada va con `set local role authenticated` y los
-- claims (sub + email) de la persona, puestos FUERA del bloque con `exception` (pg_temp.val), para que el rol no se deshaga.
-- Un caso que ENTRA por cada caso que se NIEGA. El 42501 de la guarda se distingue del de un GRANT por el mensaje.
--
-- !! CREA CONTRATOS por contrato_guarda (gasta numeracion, que un rollback no devuelve): SOLO EN RAMA, NUNCA EN LA BASE VIVA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261014101500_espejo_cliente_visible.sql --prueba espejo_cliente_visible.sql
--    Fuera de una rama (sin `erp.en_rama = si`, que pone rama_prueba) se niega a empezar, antes de tocar nada.
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada linea acaba en «→ ok» o «→ FALLA».
-- No imprime lo que devuelve contrato_guarda (lleva `fields`): solo codigos de error y booleanos. Las fichas y textos de prueba van
-- marcados ZZ-. Todo se deshace con el raise final (personas, fichas, contratos y enlaces).
-- FIXTURE PROPIO (14-oct-2026, 2.a version): la rama recibe SOLO la estructura, sin una fila; la 1.a version «escogia» un super admin,
--   dos agentes y un proyecto de los que hubiera y dio 14/44 (todo «Sin sesion»: no habia nadie). Ahora la prueba monta lo suyo, como
--   postgres y SIN sesion (asi pasa el candado de alta de `usuarios`, que exige session_user postgres para dar una empresa):
--     · empresa zz_espejo y proyecto activo «ZZ-ESPEJO Proyecto» de esa empresa;
--     · 3 personas (fila en auth.users + usuarios): un super_admin global y dos agentes ACOTADOS a esa empresa (ambito global con
--       empresas = {zz_espejo}, como los agentes reales), con la herramienta contratos, ese proyecto y un solo tipo (contrato_general);
--     · 3 fichas de cliente (una de A, dos de B).
--   No siembra parcela ni catalogos: contrato_general no lleva parcela (contrato_tipo_etapa: «contrato», no «reserva»), los tres tipos
--   que se usan (contrato_general, adenda, carta_reserva) estan en la lista fija de _trg_contrato_tipo_valido / set_contrato_numero /
--   _plantilla_slug_de_tipo, y con comisiones_interruptor sin fila _venta_modo_declara no pide la clave `venta` (en el vivo SI esta
--   encendido: ese tramo no lo cubre esta prueba, ni lo toca la migracion).
--   Antes de los casos van las aserciones P*/S0: si el montaje, una puerta o la sesion no valen, la prueba PARA ahi y lo dice en una linea.
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
create or replace function pg_temp.err(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then substr(t, 4, 5) end $f$;
-- solo el error (nunca el jsonb de una llamada que entra)
create or replace function pg_temp.e(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then left(t, 110) else 'sin error' end $f$;
create or replace function pg_temp.pago(p_tipo text, p_proy text, p_adq1 uuid, p_fields jsonb, p_comp jsonb) returns jsonb language sql immutable as $f$
  select jsonb_build_object('tipo', p_tipo, 'datos', jsonb_strip_nulls(jsonb_build_object(
           'adq1_client_id', p_adq1, 'compradores', p_comp,
           'fields', jsonb_build_object('proyecto_nombre', p_proy, 'adq1_nombre', 'ZZ-ESPEJO lo que manda la pantalla') || coalesce(p_fields, '{}'::jsonb))))
$f$;

-- Personas SINTETICAS: el id y el correo se fijan aqui; las filas (auth.users + usuarios) se crean dentro del bloque, tras la guardia de rama.
-- Correos en minusculas: cliente_visible compara propietario = auth.email() sin lower().
insert into _tp values ('jv', gen_random_uuid(), 'zz-espejo-super@prueba.invalid'),
                       ('A',  gen_random_uuid(), 'zz-espejo-agente-a@prueba.invalid'),
                       ('B',  gen_random_uuid(), 'zz-espejo-agente-b@prueba.invalid');

do $todo$
declare
  r text := ''; v text; n bigint; g boolean;
  jv _tp; a _tp; b _tp;
  pL uuid; pLn text; cA uuid; cB uuid; cB2 uuid; kA text; kB text; k6 text; k7 text;
  c_guarda constant text := 'otra empresa o de otro comercial';
  c_emp    constant text := 'zz_espejo';
  c_fin    constant text := 'FIN DE PRUEBAS ESPEJO CLIENTE VISIBLE (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS ESPEJO CLIENTE VISIBLE:%', E'\nP0 esta prueba crea contratos (gasta numeracion): solo corre en rama → FALLA';
  end if;
  select * into jv from _tp where et = 'jv'; select * into a from _tp where et = 'A'; select * into b from _tp where et = 'B';

  -- ============================================================ P. montaje del fixture propio (como postgres, SIN sesion)
  -- Sin cambio de rol aqui dentro: el sub-bloque con exception solo sirve para que un montaje roto salga en UNA linea con su error.
  perform set_config('request.jwt.claims', '', true);
  begin
    insert into public.empresas (clave, nombre) values (c_emp, 'ZZ-ESPEJO Empresa');
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-ESPEJO Proyecto', 'zz-espejo-proyecto', c_emp, true)
      returning id, nombre into pL, pLn;
    insert into auth.users (id, instance_id, email, aud, role) values
      (jv.uid, '00000000-0000-0000-0000-000000000000', jv.em, 'authenticated', 'authenticated'),
      (a.uid,  '00000000-0000-0000-0000-000000000000', a.em,  'authenticated', 'authenticated'),
      (b.uid,  '00000000-0000-0000-0000-000000000000', b.em,  'authenticated', 'authenticated');
    -- valores FINALES en el alta (nada de update despues: cambiar `empresas` con sesion lo hace solo el propietario).
    -- Dos agentes ACOTADOS a la empresa (ambito global + empresas, como los agentes reales), con Contratos, el proyecto y un solo tipo.
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (jv.uid, jv.em, 'ZZ-ESPEJO Super admin', 'super_admin', 'global', '{}'::text[],   '{}'::uuid[], '{}'::uuid[], '{}'::text[],          '{}'::text[],                 true),
      (a.uid,  a.em,  'ZZ-ESPEJO Agente A',    'agente',      'global', array[c_emp],   array[pL],    '{}'::uuid[], '{contratos}'::text[], '{contrato_general}'::text[], true),
      (b.uid,  b.em,  'ZZ-ESPEJO Agente B',    'agente',      'global', array[c_emp],   array[pL],    '{}'::uuid[], '{contratos}'::text[], '{contrato_general}'::text[], true);
    -- Fichas ZZ-: una de A, dos de B
    insert into public.clients (full_name, propietario, passport_number, email, phone, address, nationality)
      values ('ZZ-ESPEJO Cliente de A', a.em, 'ZZESPEJOA1', 'zz-espejo-a@ejemplo.invalid', '+00 000 0001', 'ZZ-domicilio A', 'ZZ') returning id into cA;
    insert into public.clients (full_name, propietario, passport_number, email, phone, address, nationality)
      values ('ZZ-ESPEJO Cliente de B', b.em, 'ZZESPEJOB1', 'zz-espejo-b@ejemplo.invalid', '+00 000 0002', 'ZZ-domicilio B', 'ZZ') returning id into cB;
    insert into public.clients (full_name, propietario, passport_number, email, phone, address, nationality)
      values ('ZZ-ESPEJO Segundo de B', b.em, 'ZZESPEJOB2', 'zz-espejo-b2@ejemplo.invalid', '+00 000 0003', 'ZZ-domicilio B2', 'ZZ') returning id into cB2;
  exception when others then
    raise exception using message = replace(c_fin, '%', pg_temp.l(false, 'P0 montaje del fixture propio: ' || sqlstate || ' ' || left(sqlerrm, 300)
                                                               || ' [session_user=' || session_user || ']'));
  end;
  r := r || pg_temp.l(pL is not null and cA is not null and cB is not null and cB2 is not null
         and (select count(*) from public.usuarios u where u.user_id in (jv.uid, a.uid, b.uid) and u.activo) = 3
         and (select count(*) from public.clients c where c.id in (cA, cB, cB2) and c.propietario in (a.em, b.em)) = 3,
       'P0 fixture propio montado: empresa, proyecto activo, 3 personas (auth.users + usuarios) y 3 fichas con su dueno [session_user=' || session_user
       || ', dueno de contrato_guarda=' || coalesce((select pg_get_userbyid(p.proowner) || ' bypassrls=' || (select rolbypassrls from pg_roles where oid = p.proowner)::text
                                                       from pg_proc p where p.oid = 'public.contrato_guarda(uuid,jsonb)'::regprocedure), '?') || ']');

  -- Las puertas EXACTAS de contrato_guarda y de la regla, medidas una a una con los claims de A (como postgres: son DEFINER y solo leen auth.uid()).
  perform set_config('request.jwt.claims', json_build_object('sub', a.uid, 'role', 'authenticated', 'email', a.em)::text, true);
  g := public.es_agente();                                      r := r || pg_temp.l(g, 'P1 A es agente activo (es_agente)');
  g := public._puede_herr_o_super_empresa('contratos');         r := r || pg_temp.l(g, 'P2 A tiene la herramienta contratos');
  g := public.proyecto_visible(pL);                             r := r || pg_temp.l(g, 'P3 A ve el proyecto ZZ (proyecto_visible: su empresa y su lista de proyectos)');
  g := public.alcance_restringido() and not public.es_admin();  r := r || pg_temp.l(g, 'P4 A tiene el alcance ACOTADO y no es admin (de eso dependen F2, E2, E3, E6, M1 y H4)');
  g := public.cliente_visible(a.em, cA) and not public.cliente_visible(b.em, cB);
                                                                r := r || pg_temp.l(g, 'P5 cliente_visible (la regla de siempre, sin tocar): A ve su ficha y no la de B');
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);
  g := public.es_admin() and public.cliente_visible(b.em, cB);  r := r || pg_temp.l(g, 'P6 el super admin ZZ es admin y ve la ficha de B');
  perform set_config('request.jwt.claims', '', true);

  -- S0, la sesion simulada POR EL CAMINO REAL (rol authenticated + claims, por pg_temp.val): una llamada sin datos a contrato_guarda no
  -- escribe ni gasta numero. Sin sesion reconocida da 42501 «Sin sesion» (lo que dio la 1.a version en 30 lineas); con ella pasa la puerta
  -- de sesion y la de permiso y cae en la validacion: 22023 «Contrato sin datos».
  v := pg_temp.val(a.uid, a.em, $q$select public.contrato_guarda(null, '{}'::jsonb)::text$q$);
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and v ~ 'Contrato sin datos', 'S0 la sesion simulada se reconoce: contrato_guarda sin datos pasa la sesion y el permiso y da 22023, no «Sin sesion» (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, 'select (select auth.uid())::text || ''|'' || (select auth.email()) || ''|'' || current_user');
  r := r || pg_temp.l(v = a.uid::text || '|' || a.em || '|authenticated', 'S0b ... con auth.uid(), auth.email() y el rol authenticated de A (' || pg_temp.e(v) || ')');

  if r ~ 'FALLA' then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'PARADA: el fixture o la sesion no valen; los casos F/E/M/T/H/X no se corren (arreglar lo de arriba antes)'));
  end if;

  -- ============================================================ F. la regla es la de comprador_ficha (y sigue dando lo mismo)
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.comprador_ficha(%L)', cA));
  r := r || pg_temp.l(v = '1', 'F1 ENTRA: A abre la ficha de SU cliente (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.comprador_ficha(%L)', cB));
  r := r || pg_temp.l(v = '0', 'F2 NIEGA: A no recibe la ficha del cliente de B (' || pg_temp.e(v) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select count(*) from public.comprador_ficha(%L)', cB));
  r := r || pg_temp.l(v = '1', 'F3 ENTRA: el super admin abre cualquier ficha (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select public._cliente_ficha_visible(%L)::text', cA));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ 'permission denied', 'F4 la funcion de la regla no se llama desde el navegador: 42501 del GRANT, no de la guarda (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from (select public._contrato_clientes_comprueba(null, %L::jsonb)) q', jsonb_build_object('adq1_client_id', cB)));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ 'permission denied', 'F5 ... ni la puerta (' || pg_temp.e(v) || ')');

  -- ============================================================ E. alta por contrato_guarda
  v := pg_temp.val(a.uid, a.em, format('select public.contrato_guarda(null, %L::jsonb)::text', pg_temp.pago('contrato_general', pLn, cA, null, null)));
  r := r || pg_temp.l(v !~ '^ERR', 'E1 ENTRA: A guarda un contrato a SU cliente (' || pg_temp.e(v) || ')');
  kA := case when v !~ '^ERR' then (v::jsonb) ->> 'id' end;
  select count(*) into n from public.contratos where id::text = kA and adq1_client_id = cA
     and datos->'fields'->>'adq1_pasaporte' = 'ZZESPEJOA1' and datos->'fields'->>'adq1_domicilio' = 'ZZ-domicilio A';
  r := r || pg_temp.l(n = 1, 'E1b ... y la ficha de su cliente se espeja en el contrato (pasaporte y domicilio)');
  select count(*) into n from public.contrato_compradores where contrato_id::text = kA and client_id = cA and rol = 'adquiriente_1';
  r := r || pg_temp.l(n = 1, 'E1c ... y queda enlazado como adquiriente_1');

  v := pg_temp.val(a.uid, a.em, format('select public.contrato_guarda(null, %L::jsonb)::text', pg_temp.pago('contrato_general', pLn, cB, null, null)));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ c_guarda, 'E2 NIEGA: A no guarda un contrato al cliente de B: 42501 de la guarda (' || pg_temp.e(v) || ')');
  r := r || pg_temp.l(v !~ 'ZZESPEJOB1' and v !~ 'ZZ-domicilio B', 'E2b ... y la respuesta no trae nada de la ficha de B');
  select count(*) into n from public.contratos where lower(creado_por) = lower(a.em) and adq1_client_id = cB;
  r := r || pg_temp.l(n = 0, 'E2c ... y no queda ningun contrato de A con el cliente de B');

  v := pg_temp.val(a.uid, a.em, format('select public.contrato_guarda(null, %L::jsonb)::text',
         pg_temp.pago('contrato_general', pLn, cA, null, jsonb_build_array(jsonb_build_object('client_id', cB2, 'nombre', 'ZZ-ESPEJO Segundo')))));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ c_guarda, 'E3 NIEGA: tampoco como segundo comprador (compradores[].client_id) (' || pg_temp.e(v) || ')');

  v := pg_temp.val(b.uid, b.em, format('select public.contrato_guarda(null, %L::jsonb)::text',
         pg_temp.pago('contrato_general', pLn, cB, null, jsonb_build_array(jsonb_build_object('client_id', cB2, 'nombre', 'ZZ-ESPEJO Segundo')))));
  r := r || pg_temp.l(v !~ '^ERR', 'E4 ENTRA: B guarda con sus dos clientes (' || pg_temp.e(v) || ')');
  kB := case when v !~ '^ERR' then (v::jsonb) ->> 'id' end;
  select count(*) into n from public.contrato_compradores where contrato_id::text = kB and client_id in (cB, cB2);
  r := r || pg_temp.l(n = 2, 'E4b ... y quedan los dos enlazados (' || n || ')');

  v := pg_temp.val(jv.uid, jv.em, format('select public.contrato_guarda(null, %L::jsonb)::text', pg_temp.pago('contrato_general', pLn, cB, null, null)));
  r := r || pg_temp.l(v !~ '^ERR', 'E5 ENTRA: el super admin guarda un contrato al cliente de cualquiera (' || pg_temp.e(v) || ')');
  select count(*) into n from public.contratos where id::text = (case when v !~ '^ERR' then (v::jsonb) ->> 'id' end) and datos->'fields'->>'adq1_pasaporte' = 'ZZESPEJOB1';
  r := r || pg_temp.l(n = 1, 'E5b ... con la ficha espejada');

  -- coincidencia por pasaporte con una ficha que no ve: se guarda, NO se enlaza y no viaja ningun dato de la ficha
  v := pg_temp.val(a.uid, a.em, format('select public.contrato_guarda(null, %L::jsonb)::text',
         pg_temp.pago('contrato_general', pLn, cA, null, jsonb_build_array(jsonb_build_object('nombre', 'ZZ-ESPEJO tecleado', 'pasaporte', 'ZZESPEJOB2')))));
  r := r || pg_temp.l(v !~ '^ERR', 'E6 ENTRA: A teclea a mano un segundo comprador cuyo pasaporte es el de una ficha de B: el contrato se guarda (' || pg_temp.e(v) || ')');
  k6 := case when v !~ '^ERR' then (v::jsonb) ->> 'id' end;
  select count(*) into n from public.contrato_compradores where contrato_id::text = k6 and rol = 'adquiriente_2';
  r := r || pg_temp.l(n = 0, 'E6b NIEGA: ... pero NO queda enlazado a la ficha de B (' || n || ')');
  r := r || pg_temp.l(v !~ 'ZZ-domicilio B2' and v !~ 'zz-espejo-b2', 'E6c ... y la respuesta no trae nada de esa ficha');
  v := pg_temp.val(b.uid, b.em, format('select public.contrato_guarda(null, %L::jsonb)::text',
         pg_temp.pago('contrato_general', pLn, cB, null, jsonb_build_array(jsonb_build_object('nombre', 'ZZ-ESPEJO tecleado', 'pasaporte', 'ZZESPEJOB2')))));
  select count(*) into n from public.contrato_compradores where contrato_id::text = (case when v !~ '^ERR' then (v::jsonb) ->> 'id' end) and rol = 'adquiriente_2' and client_id = cB2;
  r := r || pg_temp.l(v !~ '^ERR' and n = 1, 'E7 ENTRA: el mismo tecleo hecho por B (que si ve la ficha) SI enlaza (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select public.contrato_guarda(null, %L::jsonb)::text',
         pg_temp.pago('contrato_general', pLn, null, jsonb_build_object('adq1_pasaporte', 'ZZESPEJOB1'), null)));
  k7 := case when v !~ '^ERR' then (v::jsonb) ->> 'id' end;
  select count(*) into n from public.contrato_compradores where contrato_id::text = k7;
  r := r || pg_temp.l(v !~ '^ERR' and n = 0 and v !~ 'ZZ-domicilio B', 'E8 A teclea el pasaporte del cliente de B como Adquiriente I sin ficha: se guarda, sin enlace y sin datos de la ficha (' || pg_temp.e(v) || ')');

  -- ============================================================ M. edicion
  v := pg_temp.val(a.uid, a.em, format('select public.contrato_guarda(%L, %L::jsonb)::text', kA, pg_temp.pago('contrato_general', pLn, cB, null, null)));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ c_guarda, 'M1 NIEGA: A no cambia el cliente de su borrador por el de B (' || pg_temp.e(v) || ')');
  select count(*) into n from public.contratos where id::text = kA and adq1_client_id = cA;
  r := r || pg_temp.l(n = 1, 'M1b ... y el borrador sigue con su cliente');
  v := pg_temp.val(a.uid, a.em, format('select public.contrato_guarda(%L, %L::jsonb)::text', kA,
         pg_temp.pago('contrato_general', pLn, cA, jsonb_build_object('adq1_domicilio', 'ZZ-domicilio que manda la pantalla'), null)));
  select count(*) into n from public.contratos where id::text = kA and datos->'fields'->>'adq1_domicilio' = 'ZZ-domicilio A';
  r := r || pg_temp.l(v !~ '^ERR' and n = 1, 'M2 ENTRA: A vuelve a guardar su borrador con su cliente, y manda la FICHA, no lo que mande la pantalla (' || pg_temp.e(v) || ')');

  -- ============================================================ T. tipo permitido, por los dos caminos (A solo tiene contrato_general)
  v := pg_temp.val(a.uid, a.em, format('select public.contrato_guarda(null, %L::jsonb)::text', pg_temp.pago('adenda', pLn, cA, null, null)));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ 'permiso para emitir', 'T1 NIEGA (alta): A no da de alta un tipo que no tiene (' || pg_temp.e(v) || ')');
  r := r || pg_temp.l(kA is not null, 'T2 ENTRA (alta): A da de alta el tipo que tiene (es E1)');
  v := pg_temp.val(a.uid, a.em, format('select public.contrato_guarda(%L, %L::jsonb)::text', kA, pg_temp.pago('adenda', pLn, cA, null, null)));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ 'permiso para emitir', 'T3 NIEGA (edicion): A no convierte su borrador a un tipo que no tiene (' || pg_temp.e(v) || ')');
  select count(*) into n from public.contratos where id::text = kA and tipo = 'contrato_general';
  r := r || pg_temp.l(n = 1, 'T3b ... y el borrador conserva su tipo');
  r := r || pg_temp.l(true, 'T4 ENTRA (edicion): A guarda su borrador sin cambiar el tipo (es M2)');
  -- le quitan el tipo: lo que ya tenia se sigue pudiendo guardar; uno nuevo, no
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);
  update public.usuarios set tipos_contrato = '{carta_reserva}' where user_id = a.uid;
  perform set_config('request.jwt.claims', '', true);
  v := pg_temp.val(a.uid, a.em, format('select public.contrato_guarda(%L, %L::jsonb)::text', kA, pg_temp.pago('contrato_general', pLn, cA, null, null)));
  r := r || pg_temp.l(v !~ '^ERR', 'T5 ENTRA: a A le quitan el tipo y aun guarda el borrador que ya tenia de ese tipo (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select public.contrato_guarda(null, %L::jsonb)::text', pg_temp.pago('contrato_general', pLn, cA, null, null)));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ 'permiso para emitir', 'T6 NIEGA: ... pero no da de alta uno nuevo de ese tipo (' || pg_temp.e(v) || ')');
  select count(*) into n from pg_trigger t where t.tgrelid = 'public.contratos'::regclass and t.tgname = 'trg_contratos_tipo_permitido' and t.tgenabled = 'O'
     and pg_get_triggerdef(t.oid) ~ 'BEFORE INSERT OR UPDATE OF tipo';
  r := r || pg_temp.l(n = 1, 'T7 el trigger salta en INSERT y en UPDATE OF tipo');
  select count(*) into n from pg_proc p where p.oid = 'public.contratos_tipo_permitido()'::regprocedure
     and p.prosrc ~ 'v_rol is distinct from ''agente''';
  r := r || pg_temp.l(n = 1, 'T8 sigue aplicando SOLO a rol = agente: sales_manager y project_manager, sin limite de tipos, como antes');

  -- ============================================================ H. borrador heredado (enlazado a una ficha ajena ANTES del cierre)
  -- Se simula por el camino de servidor (sin sesion), que no cambia: espeja y enlaza como hoy.
  update public.contratos set datos = jsonb_set(datos, '{adq1_client_id}', to_jsonb(cB::text)) where id::text = kA;
  select count(*) into n from public.contratos where id::text = kA and adq1_client_id = cB and datos->'fields'->>'adq1_pasaporte' = 'ZZESPEJOB1';
  r := r || pg_temp.l(n = 1, 'S1 sin sesion (servidor) el espejo se comporta como antes: copia la ficha');
  select count(*) into n from public.contrato_compradores where contrato_id::text = kA and rol = 'adquiriente_1' and client_id = cB;
  r := r || pg_temp.l(n = 1, 'S1b ... y enlaza');
  v := pg_temp.val(a.uid, a.em, format('select public.contrato_guarda(%L, %L::jsonb)::text', kA,
         pg_temp.pago('contrato_general', pLn, cB, jsonb_build_object('adq1_domicilio', 'ZZ-domicilio que manda la pantalla'), null)));
  r := r || pg_temp.l(v !~ '^ERR', 'H1 ENTRA: A sigue pudiendo guardar el borrador que YA tenia ese cliente (la fila no se congela) (' || pg_temp.e(v) || ')');
  select count(*) into n from public.contratos where id::text = kA and datos->'fields'->>'adq1_domicilio' = 'ZZ-domicilio que manda la pantalla';
  r := r || pg_temp.l(n = 1, 'H2 NIEGA: ... pero ya NO se re-espeja la ficha que no ve (queda lo que mando la pantalla)');
  select count(*) into n from public.contrato_compradores where contrato_id::text = kA and rol = 'adquiriente_1' and client_id = cB;
  r := r || pg_temp.l(n = 1, 'H3 ... y el enlace que ya existia se conserva (no se toca lo existente)');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.comprador_ficha(%L)', cB));
  r := r || pg_temp.l(v = '0', 'H4 NIEGA: ni con el enlace heredado recibe A la ficha de B (agente con alcance acotado) (' || pg_temp.e(v) || ')');

  -- ============================================================ X. exposicion
  select count(*) into n from pg_proc p
   where p.oid in ('public._cliente_ficha_visible(uuid)'::regprocedure, 'public._contrato_clientes_comprueba(uuid,jsonb)'::regprocedure,
                   'public.espeja_comprador(jsonb)'::regprocedure, 'public.sincronizar_compradores(uuid)'::regprocedure,
                   'public.contratos_tipo_permitido()'::regprocedure)
     and p.prosecdef and 'search_path=""' = any (p.proconfig)
     and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute');
  r := r || pg_temp.l(n = 5, 'X1 las 2 nuevas, el espejo, el enlace y el trigger de tipo: DEFINER, search_path vacio, sin EXECUTE para anon ni authenticated (' || n || ')');
  select count(*) into n from pg_proc p
   where p.oid in ('public.contrato_guarda(uuid,jsonb)'::regprocedure, 'public.comprador_ficha(uuid)'::regprocedure)
     and p.prosecdef and 'search_path=""' = any (p.proconfig)
     and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute');
  r := r || pg_temp.l(n = 2, 'X2 contrato_guarda y comprador_ficha conservan DEFINER, search_path y permisos (authenticated si, anon no) (' || n || ')');
  select count(*) into n from pg_proc p where p.oid = 'public.contrato_guarda(uuid,jsonb)'::regprocedure
     and position('perform public._contrato_clientes_comprueba(p_id, v_datos);' in p.prosrc) between 1 and position('insert into public.contratos' in p.prosrc);
  r := r || pg_temp.l(n = 1, 'X3 en contrato_guarda la comprobacion va ANTES de la primera escritura');

  raise exception 'FIN DE PRUEBAS ESPEJO CLIENTE VISIBLE (se deshace todo):%', r;
end $todo$;
