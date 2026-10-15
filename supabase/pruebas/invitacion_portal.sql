-- Prueba «Invitar al portal» desde la ficha de parcela (15-oct-2026, migración 20261015071004_invitacion_portal_parcela.sql).
-- Pliega la revisión previa #357: Seguridad (perfiles con cuenta desactivada, oráculo de _portal_rechazo, revalidación al enviar,
-- topes, nota, equivalencia del login sin fiarse de un recorrido corto) y Base de datos (FK compuesta tipo↔clave, todas las
-- lectoras del libro filtran tipo, Reclamar pago saca el titular de contrato_compradores, copropietarios vigentes).
--
-- !! SIEMBRA contratos, fichas y personas: SOLO EN RAMA, NUNCA EN LA BASE VIVA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261015071004_invitacion_portal_parcela.sql
--           --prueba invitacion_portal.sql,invitacion_portal_reversion.sql,reclamo_pago.sql
--    Fuera de una rama (sin `erp.en_rama = si`, que pone rama_prueba) se niega a empezar, antes de tocar nada.
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada línea acaba en «→ ok» o «→ FALLA». No imprime lo que
-- devuelven las llamadas que entran (contadores, códigos de error y booleanos). Todo lo de prueba va marcado ZZ-IP.
-- FIXTURE PROPIO (la rama recibe SOLO la estructura), como postgres y SIN sesión:
--   · empresas zz_ip (con sociedad zz_ip) y zz_ip_otra, un proyecto de cada una;
--   · personas (auth.users + usuarios): AE admin_empresa de zz_ip; AO admin_empresa de zz_ip_otra; AG agente; EQ2 del equipo cuya
--     cuenta de Auth tiene OTRO correo que su fila de usuarios; PO comprador del portal (Auth, sin fila en usuarios);
--   · parcela U1 con dos contratos vivos: K1 firmado (C1 titular, C2 copropietario, C3 con el correo de AG, C4 sin correo) y K2 sin
--     firmar (C5 revocado, C6 con el correo de C1, C7 con el correo de Auth de EQ2, C8 limpio); parcela U2 con K3 (C9); parcela UO de la
--     otra empresa con KO (CO).
-- MEDIDO: (pendiente; la rama la lanza quien encarga, con turno del orquestador)
-- destructivo-ok: prueba en transacción que termina en raise (rollback); solo en rama
create temp table _tp (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
-- ejecuta p_sql (UN valor) con la sesión de esa persona; 'ERR<sqlstate>:<hint>' si falla
create or replace function pg_temp.val(p_rol text, p_uid uuid, p_email text, p_sql text) returns text language plpgsql as $f$
declare t text; h text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_rol, 'email', p_email)::text, true);
  execute format('set local role %I', p_rol);
  begin execute p_sql into t;
  exception when others then get stacked diagnostics h = pg_exception_hint; t := 'ERR' || sqlstate || ':' || coalesce(h, ''); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return t;
end $f$;

insert into _tp values ('AE',  gen_random_uuid(), 'zz-ip-admin@prueba.invalid'),
                       ('AO',  gen_random_uuid(), 'zz-ip-admin-otra@prueba.invalid'),
                       ('AG',  gen_random_uuid(), 'zz-ip-agente@prueba.invalid'),
                       ('EQ2', gen_random_uuid(), 'zz-ip-equipo-dos@prueba.invalid'),
                       ('PO',  gen_random_uuid(), 'zz-ip-portal@prueba.invalid');

do $todo$
declare
  r text := ''; v text; n bigint; n2 bigint; b boolean; j jsonb;
  ae _tp; ao _tp; ag _tp; eq2 _tp; po _tp;
  c_eq2_auth constant text := 'zz-ip-equipo-dos-auth@prueba.invalid';
  pL uuid; pOt uuid; u1 uuid; u2 uuid; uo uuid; k1 uuid; k2 uuid; k3 uuid; ko uuid;
  c1 uuid; c2 uuid; c3 uuid; c4 uuid; c5 uuid; c6 uuid; c7 uuid; c8 uuid; c9 uuid; co uuid;
  i1 uuid; i2 uuid; q1 uuid; qp uuid; rr uuid; qr uuid; rx uuid;
  c_fin constant text := 'FIN DE PRUEBAS INVITACION PORTAL (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS INVITACION PORTAL:%', E'\nP0 esta prueba siembra contratos y personas: solo corre en rama → FALLA';
  end if;
  select * into ae from _tp where et = 'AE'; select * into ao from _tp where et = 'AO'; select * into ag from _tp where et = 'AG';
  select * into eq2 from _tp where et = 'EQ2'; select * into po from _tp where et = 'PO';

  -- ============================================================ P. montaje (como postgres, SIN sesión)
  perform set_config('request.jwt.claims', '', true);
  begin
    insert into public.empresas (clave, nombre) values ('zz_ip', 'ZZ-IP Empresa'), ('zz_ip_otra', 'ZZ-IP Otra');
    insert into public.sociedades (clave, label, razon, domicilio) values ('zz_ip', 'ZZ-IP', 'ZZ-IP PT', 'ZZ-domicilio') on conflict (clave) do nothing;
    update public.empresas set sociedad_clave = 'zz_ip' where clave = 'zz_ip';
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-IP Proyecto', 'zz-ip-proyecto', 'zz_ip', true) returning id into pL;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-IP Proyecto otra', 'zz-ip-proyecto-otra', 'zz_ip_otra', true) returning id into pOt;
    insert into auth.users (id, instance_id, email, aud, role)
      select t.uid, '00000000-0000-0000-0000-000000000000', case when t.et = 'EQ2' then c_eq2_auth else t.em end, 'authenticated', 'authenticated' from _tp t;
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (ae.uid,  ae.em,  'ZZ-IP Admin',       'admin_empresa', 'empresa', array['zz_ip'],      '{}'::uuid[], '{}'::uuid[], '{unidades,compradores}'::text[], '{}'::text[], true),
      (ao.uid,  ao.em,  'ZZ-IP Admin otra',  'admin_empresa', 'empresa', array['zz_ip_otra'], '{}'::uuid[], '{}'::uuid[], '{unidades,compradores}'::text[], '{}'::text[], true),
      (ag.uid,  ag.em,  'ZZ-IP Agente',      'agente',        'global',  array['zz_ip'],      array[pL],    '{}'::uuid[], '{unidades}'::text[], '{contrato_general}'::text[], true),
      (eq2.uid, eq2.em, 'ZZ-IP Equipo dos',  'agente',        'global',  array['zz_ip'],      array[pL],    '{}'::uuid[], '{unidades}'::text[], '{contrato_general}'::text[], true);
    -- la rama nace de la ESTRUCTURA del volcado: los catálogos que siembran las migraciones vienen vacíos. El 23503 de
    -- unidades_tipo_fkey (ensayo del 15-oct) lo quita el modo replica de abajo; tipos_vivienda se siembra para que la parcela
    -- quede válida igualmente, y la plantilla SÍ hace falta (la cola se escribe ya en origin). Mismas filas que la viva
    insert into public.tipos_vivienda (clave, etiqueta) values ('parcela', 'Parcela') on conflict (clave) do nothing;
    insert into public.correo_plantillas (clave, activa, variables, version)   -- como 20261010070000 (la cola la exige por FK: D3, E5)
    values ('reclamo_pago', false,
            '{"permitidas":["saludo","parcela","proyecto","empresa","nota","enlace","marca","firma"],"obligatorias":{"asunto":["parcela"],"cuerpo":["parcela","enlace"],"cuerpo_alt":[]},"variantes":1}'::jsonb, 0)
    on conflict (clave) do nothing;
    insert into public.clients (full_name, email) values ('ZZ-IP Uno', 'zz-ip-uno@prueba.invalid') returning id into c1;
    insert into public.clients (full_name, email) values ('ZZ-IP Dos', 'zz-ip-dos@prueba.invalid') returning id into c2;
    insert into public.clients (full_name, email) values ('ZZ-IP Tres', ag.em) returning id into c3;
    insert into public.clients (full_name, email) values ('ZZ-IP Cuatro', null) returning id into c4;
    insert into public.clients (full_name, email) values ('ZZ-IP Cinco', 'zz-ip-cinco@prueba.invalid') returning id into c5;
    -- mismo correo que C1 (B7, correo_repetido): clients_email_tipo_key solo deja repetirlo con otro tipo (una sociedad compradora)
    insert into public.clients (full_name, email, tipo) values ('ZZ-IP Zeta', 'zz-ip-uno@prueba.invalid', 'empresa') returning id into c6;
    insert into public.clients (full_name, email) values ('ZZ-IP Siete', c_eq2_auth) returning id into c7;
    insert into public.clients (full_name, email) values ('ZZ-IP Ocho', 'zz-ip-ocho@prueba.invalid') returning id into c8;
    insert into public.clients (full_name, email) values ('ZZ-IP Nueve', 'zz-ip-nueve@prueba.invalid') returning id into c9;
    insert into public.clients (full_name, email) values ('ZZ-IP Otra', 'zz-ip-otra@prueba.invalid') returning id into co;
    -- parcelas y contratos SIN disparadores (como facturas_conservan_parcela.sql): en la rama no hay inventario, precios ni cobros
    -- con los que los disparadores de unidades/contratos cuadren, y aquí solo importan las columnas que leen los candidatos.
    -- Lo que esos disparadores rellenarían va a mano: unidades.proyecto_id (resuelve_proyecto_id), contratos.numero
    -- (set_contrato_numero), proyecto_nombre (espejo) y datos_fields (de él sale sociedad_firmante, 20260926210000)
    execute 'set local session_replication_role = replica';
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo) values ('ZZ-IP-1', 'ZZ-IP Proyecto', pL, 'parcela') returning id into u1;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo) values ('ZZ-IP-2', 'ZZ-IP Proyecto', pL, 'parcela') returning id into u2;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo) values ('ZZ-IP-O', 'ZZ-IP Proyecto otra', pOt, 'parcela') returning id into uo;
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, unidad_id, fecha_firma, datos, datos_fields)
      select 'ZZ-IP-K1', 'contrato_general', pL, 'ZZ-IP Proyecto', u1, current_date, d, d -> 'fields'
        from (select '{"fields": {"proyecto_nombre": "ZZ-IP Proyecto", "sociedad_firmante": "zz_ip"}}'::jsonb as d) x returning id into k1;
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, unidad_id, fecha_firma, datos, datos_fields)
      select 'ZZ-IP-K2', 'contrato_general', pL, 'ZZ-IP Proyecto', u1, null, d, d -> 'fields'
        from (select '{"fields": {"proyecto_nombre": "ZZ-IP Proyecto", "sociedad_firmante": "zz_ip"}}'::jsonb as d) x returning id into k2;
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, unidad_id, fecha_firma, datos, datos_fields)
      select 'ZZ-IP-K3', 'contrato_general', pL, 'ZZ-IP Proyecto', u2, current_date, d, d -> 'fields'
        from (select '{"fields": {"proyecto_nombre": "ZZ-IP Proyecto", "sociedad_firmante": "zz_ip"}}'::jsonb as d) x returning id into k3;
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, unidad_id, fecha_firma, datos, datos_fields)
      select 'ZZ-IP-KO', 'contrato_general', pOt, 'ZZ-IP Proyecto otra', uo, current_date, d, d -> 'fields'
        from (select '{"fields": {"proyecto_nombre": "ZZ-IP Proyecto otra"}}'::jsonb as d) x returning id into ko;
    execute 'set local session_replication_role = origin';
    -- los compradores DESPUÉS de los contratos (trg_compradores_desde_datos sincroniza al guardar el contrato, que ya no se toca)
    insert into public.contrato_compradores (contrato_id, client_id, rol) values
      (k1, c1, 'adquiriente_1'), (k1, c2, 'adquiriente_2'), (k1, c3, 'adquiriente_3'), (k1, c4, 'adquiriente_4'),
      (k2, c5, 'adquiriente_1'), (k2, c6, 'adquiriente_2'), (k2, c7, 'adquiriente_3'), (k2, c8, 'adquiriente_4'),
      (k3, c9, 'adquiriente_1'), (ko, co, 'adquiriente_1');
    insert into public.portal_accesos (email, client_id, activo, creado_por) values ('zz-ip-cinco@prueba.invalid', c5, false, 'zz-ip');
    insert into public.portal_accesos (email, client_id, activo, creado_por, ultimo_acceso, accesos) values ('zz-ip-dos@prueba.invalid', c2, true, 'zz-ip', now(), 1);
  exception when others then
    raise exception using message = replace(c_fin, '%', pg_temp.l(false, 'P0 montaje: ' || sqlstate || ' ' || left(sqlerrm, 300)));
  end;
  select count(*) into n from public.contrato_compradores where contrato_id in (k1, k2, k3, ko);
  r := r || pg_temp.l(n = 10, 'P1 los 10 compradores siguen enlazados tras el montaje (' || n || ')');

  -- ============================================================ A. permisos por perfil (un SÍ y un NO por perfil)
  begin
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select count(*)::text from public.invitacion_portal_destinatarios(%L)', u1));
  r := r || pg_temp.l(v = '8', 'A1 admin de la empresa: ve a las 8 personas de la parcela, copropietarios incluidos (' || v || ')');
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select count(*)::text from public.invitacion_portal_historial(%L)', u1));
  r := r || pg_temp.l(v = '0', 'A1b admin de la empresa: historial vacío (' || v || ')');
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select count(*)::text from public.invitacion_portal_destinatarios(%L)', uo));
  r := r || pg_temp.l(v like 'ERR42501%', 'A2 admin de la empresa NO ve la parcela de otra empresa (' || v || ')');
  v := pg_temp.val('authenticated', ao.uid, ao.em, format('select public.invitacion_portal_encolar(%L, array[%L]::uuid[], null)::text', u1, c1));
  r := r || pg_temp.l(v like 'ERR42501%', 'A3 admin de OTRA empresa: no puede invitar en esta parcela (' || v || ')');
  v := pg_temp.val('authenticated', ao.uid, ao.em, format('select count(*)::text from public.invitacion_portal_destinatarios(%L)', uo));
  r := r || pg_temp.l(v = '1', 'A3b …y sí en la suya (' || v || ')');
  v := pg_temp.val('authenticated', ag.uid, ag.em, format('select count(*)::text from public.invitacion_portal_destinatarios(%L)', u1));
  r := r || pg_temp.l(v like 'ERR42501%', 'A4 agente: no (' || v || ')');
  v := pg_temp.val('authenticated', ag.uid, ag.em, format('select public.invitacion_portal_prueba(%L, null)', u1));
  r := r || pg_temp.l(v like 'ERR42501%', 'A4b agente: ni la prueba (' || v || ')');
  v := pg_temp.val('authenticated', po.uid, po.em, format('select count(*)::text from public.invitacion_portal_destinatarios(%L)', u1));
  r := r || pg_temp.l(v like 'ERR42501%', 'A5 comprador del portal (sesión sin fila en usuarios): no (' || v || ')');
  v := pg_temp.val('anon', null, null, format('select count(*)::text from public.invitacion_portal_destinatarios(%L)', u1));
  r := r || pg_temp.l(v like 'ERR42501%', 'A6 anónimo: sin EXECUTE (' || v || ')');
  update public.usuarios set activo = false where user_id = ae.uid;
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select count(*)::text from public.invitacion_portal_destinatarios(%L)', u1));
  r := r || pg_temp.l(v like 'ERR42501%', 'A7 cuenta desactivada: no (' || v || ')');
  update public.usuarios set activo = true where user_id = ae.uid;
  -- las internas, cerradas para todos los que llegan de fuera (Seguridad #357 punto 2: _portal_rechazo sería un oráculo de correos)
  foreach v in array array['select public._portal_rechazo(''zz-ip-agente@prueba.invalid'')',
                           'select public._nota_correo_limpia(''x'')',
                           format('select count(*)::text from public._invitacion_portal_candidatos(%L)', u1),
                           format('select count(*)::text from public.invitacion_portal_datos(%L)', gen_random_uuid())] loop
    r := r || pg_temp.l(pg_temp.val('authenticated', po.uid, po.em, v) like 'ERR42501%', 'A8 comprador del portal no ejecuta: ' || left(v, 50));
    r := r || pg_temp.l(pg_temp.val('authenticated', ae.uid, ae.em, v) like 'ERR42501%', 'A8b admin no ejecuta: ' || left(v, 50));
    r := r || pg_temp.l(pg_temp.val('anon', null, null, v) like 'ERR42501%', 'A8c anónimo no ejecuta: ' || left(v, 50));
  end loop;
  -- ACL en el catálogo (proacl, no has_function_privilege: el permiso llega por PUBLIC, seguridad_2026 §1.ter)
  select count(*) into n from pg_proc p
   where p.oid in ('public._portal_rechazo(text)'::regprocedure, 'public._nota_correo_limpia(text)'::regprocedure,
                   'public._invitacion_portal_candidatos(uuid)'::regprocedure)
     and p.proacl is not null
     and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0
                        or a.grantee in (select oid from pg_roles where rolname in ('anon', 'authenticated', 'service_role', 'lw_lector')));
  r := r || pg_temp.l(n = 3, 'A9 _portal_rechazo, _nota_correo_limpia y _invitacion_portal_candidatos: sin EXECUTE para nadie de fuera (' || n || ' de 3)');
  select count(*) into n from pg_proc p
   where p.oid in ('public.invitacion_portal_datos(uuid)'::regprocedure, 'public.portal_autoservicio(text)'::regprocedure)
     and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0
                        or a.grantee in (select oid from pg_roles where rolname in ('anon', 'authenticated', 'lw_lector')))
     and exists (select 1 from aclexplode(p.proacl) a where a.grantee = (select oid from pg_roles where rolname = 'service_role'));
  r := r || pg_temp.l(n = 2, 'A10 invitacion_portal_datos y portal_autoservicio: solo service_role (' || n || ' de 2)');
  select count(*) into n from pg_proc p
   where p.proname in ('invitacion_portal_destinatarios', 'invitacion_portal_encolar', 'invitacion_portal_historial', 'invitacion_portal_prueba')
     and p.pronamespace = 'public'::regnamespace and p.prosecdef
     and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 or a.grantee in (select oid from pg_roles where rolname in ('anon', 'lw_lector')))
     and exists (select 1 from aclexplode(p.proacl) a where a.grantee = (select oid from pg_roles where rolname = 'authenticated'));
  r := r || pg_temp.l(n = 4, 'A11 las 4 de pantalla: DEFINER, authenticated sí, anon/public no (' || n || ' de 4)');
  exception when others then   -- la sección se deshace sola; el error sale como línea en rojo y la prueba sigue
    r := r || pg_temp.l(false, 'A sección cortada: ' || sqlstate || ' ' || left(sqlerrm, 300));
  end;

  -- ============================================================ B. a quién se puede invitar y por qué no
  begin
  perform set_config('request.jwt.claims', json_build_object('sub', ae.uid, 'role', 'authenticated', 'email', ae.em)::text, true);
  select jsonb_object_agg(d.client_id::text, jsonb_build_object('s', d.seleccionable, 'm', d.motivo, 'f', d.firmado, 'r', d.rol, 'a', d.ultimo_acceso is not null, 'e', d.email_oculto))
    into j from public.invitacion_portal_destinatarios(u1) d;
  perform set_config('request.jwt.claims', '', true);
  r := r || pg_temp.l((j->c1::text->>'s')::boolean and j->c1::text->>'m' is null, 'B1 titular firmado: invitable');
  r := r || pg_temp.l((j->c2::text->>'s')::boolean and j->c2::text->>'r' = 'adquiriente_2', 'B2 copropietario (adquiriente_2): invitable');
  r := r || pg_temp.l((j->c2::text->>'a')::boolean and not (j->c1::text->>'a')::boolean, 'B3 «ya ha entrado» sale de portal_accesos por client_id (C2 sí, C1 no)');
  r := r || pg_temp.l(j->c3::text->>'m' = 'correo_equipo', 'B4 ficha con el correo de alguien del equipo: correo_equipo (' || coalesce(j->c3::text->>'m', 'null') || ')');
  r := r || pg_temp.l(j->c4::text->>'m' = 'sin_email', 'B5 sin correo: sin_email');
  r := r || pg_temp.l(j->c5::text->>'m' = 'acceso_revocado', 'B6 revocado: acceso_revocado (manda sobre la regla)');
  r := r || pg_temp.l(j->c6::text->>'m' = 'correo_repetido' and j->c1::text->>'m' is null, 'B7 mismo correo que otra persona de la parcela: la segunda, correo_repetido');
  r := r || pg_temp.l(j->c7::text->>'m' = 'correo_equipo', 'B8 correo de una cuenta de Auth del equipo con otro correo en usuarios: correo_equipo');
  r := r || pg_temp.l((j->c8::text->>'s')::boolean and not (j->c8::text->>'f')::boolean, 'B9 contrato sin firmar: invitable, firmado=false como dato');
  r := r || pg_temp.l(j->c1::text->>'e' = 'z***@prueba.invalid' and position('zz-ip-uno' in j::text) = 0, 'B10 el correo sale enmascarado y el completo no llega al navegador');
  exception when others then   -- la sección se deshace sola; el error sale como línea en rojo y la prueba sigue
    r := r || pg_temp.l(false, 'B sección cortada: ' || sqlstate || ' ' || left(sqlerrm, 300));
  end;

  -- ============================================================ C. encolar
  begin
  select count(*) into n from public.reclamos_pago;
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select public.invitacion_portal_encolar(%L, array[%L, %L]::uuid[], %L)::text', u1, c1, c2, 'Hola, revisa todo, por favor'));
  r := r || pg_temp.l(v not like 'ERR%' and (v::jsonb->>'n') = '2', 'C1 invitar a titular y copropietario: 2 en cola (' || left(v, 40) || ')');
  select count(*) into n2 from public.reclamos_pago r2 join public.correos_cola q on q.id = r2.cola_id
   where r2.unidad_id = u1 and r2.tipo = 'invitacion_portal' and q.clave = 'invitacion_portal' and not r2.prueba and r2.creado_por = ae.em;
  r := r || pg_temp.l(n2 = 2, 'C1b libro (tipo invitacion_portal) + cola (clave invitacion_portal), quién de la sesión (' || n2 || ')');
  select id, cola_id into i1, q1 from public.reclamos_pago where unidad_id = u1 and client_id = c1 and tipo = 'invitacion_portal' and not prueba;
  select id into i2 from public.reclamos_pago where unidad_id = u1 and client_id = c2 and tipo = 'invitacion_portal' and not prueba;
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select public.invitacion_portal_encolar(%L, array[%L]::uuid[], null)::text', u1, c1));
  r := r || pg_temp.l(v = 'ERR22023:doble_clic', 'C2 la misma persona otra vez en 10 s: doble_clic (' || v || ')');
  select count(*) into n from public.reclamos_pago;
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select public.invitacion_portal_encolar(%L, array[%L]::uuid[], null)::text', u1, c9));
  r := r || pg_temp.l(v = 'ERR22023:destinatario_ajeno_a_la_parcela', 'C3 persona de otra parcela: destinatario_ajeno_a_la_parcela (' || v || ')');
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select public.invitacion_portal_encolar(%L, array[%L, %L]::uuid[], null)::text', u1, c8, c3));
  r := r || pg_temp.l(v = 'ERR22023:correo_equipo', 'C4 un lote con una no invitable: rechazado entero con su motivo (' || v || ')');
  select count(*) into n2 from public.reclamos_pago;
  r := r || pg_temp.l(n2 = n, 'C4b los rechazados no dejan filas en el libro');
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select public.invitacion_portal_encolar(%L, %L::uuid[], null)::text', u1,
         (select array_agg(gen_random_uuid()) from generate_series(1, 11))));
  r := r || pg_temp.l(v = 'ERR22023:demasiados_destinatarios', 'C5 11 personas: demasiados_destinatarios (' || v || ')');
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select public.invitacion_portal_encolar(%L, array[]::uuid[], null)::text', u1));
  r := r || pg_temp.l(v = 'ERR22023:sin_destinatarios', 'C6 nadie marcado: sin_destinatarios (' || v || ')');
  foreach v in array array['paga en evil.ly', 'cuenta 1234567', 'a@b', 'mira http://x', 'en www.algo', repeat('x', 301),
                           'BCA 123 456 7890', 'llama al 0812-3456-7890', 'IBAN ES12 3456 7890 1234'] loop
    r := r || pg_temp.l(pg_temp.val('authenticated', ae.uid, ae.em, format('select public.invitacion_portal_encolar(%L, array[%L]::uuid[], %L)::text', u1, c8, v))
                        = 'ERR22023:nota_invalida', 'C7 nota rechazada: ' || left(v, 20));
  end loop;
  r := r || pg_temp.l(public._nota_correo_limpia('  Quedan 2.000 EUR   pendientes ') = 'Quedan 2.000 EUR pendientes', 'C7b una nota normal pasa, normalizada');
  r := r || pg_temp.l(public._nota_correo_limpia('Quedan 25.000.000 IDR antes del 15/10/2026') is not null, 'C7c importe con miles agrupados y fecha pasan');
  -- Reclamar pago no ve las invitaciones (Base de datos #357 punto 3)
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select (select ultimo_reclamo_en is null from public.reclamo_pago_destinatarios(%L) where client_id = %L)::text', u1, c1));
  r := r || pg_temp.l(v = 'true', 'C8a «último recordatorio» de Reclamar pago no cuenta la invitación del titular (' || coalesce(v, 'null') || ')');
  insert into public.reclamos_pago (unidad_id, contrato_id, client_id, creado_por, tipo) values (u1, k1, c1, ae.em, 'reclamo_pago') returning id into rr;
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select count(*)::text from public.reclamo_pago_historial(%L)', u1));
  r := r || pg_temp.l(v = '1', 'C8 el historial de Reclamar pago solo enseña su reclamo, no las 2 invitaciones (' || v || ')');
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select count(*)::text from public.invitacion_portal_historial(%L)', u1));
  r := r || pg_temp.l(v = '2', 'C8b y el de invitaciones, solo las suyas (' || v || ')');
  -- tope global por hora: 13 invitaciones más (como postgres) + las 2 = 15
  insert into public.reclamos_pago (unidad_id, contrato_id, client_id, creado_por, tipo)
    select u2, k3, c9, ae.em, 'invitacion_portal' from generate_series(1, 13);
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select public.invitacion_portal_encolar(%L, array[%L]::uuid[], null)::text', u1, c8));
  r := r || pg_temp.l(v = 'ERR22023:tope_hora', 'C9 con 15 invitaciones en la última hora (toda la base): tope_hora (' || v || ')');
  delete from public.reclamos_pago where unidad_id = u2 and tipo = 'invitacion_portal';
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select public.invitacion_portal_encolar(%L, array[%L]::uuid[], null)::text', u1, c8));
  r := r || pg_temp.l(v not like 'ERR%', 'C9b por debajo del tope vuelve a dejar (' || left(v, 30) || ')');
  -- freno por persona (Seguridad 15-oct): pasados los 10 s del doble clic, la misma persona sigue frenada 24 h; un envío fallido la libera
  update public.reclamos_pago set creado_en = now() - interval '1 minute' where unidad_id = u1 and client_id = c8 and tipo = 'invitacion_portal';
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select public.invitacion_portal_encolar(%L, array[%L]::uuid[], null)::text', u1, c8));
  r := r || pg_temp.l(v = 'ERR22023:ya_invitado', 'C10 la misma persona al minuto: ya_invitado (24 h por persona y parcela) (' || v || ')');
  update public.correos_cola q set estado = 'error', error = 'prueba de rama'
    from public.reclamos_pago r2 where r2.cola_id = q.id and r2.unidad_id = u1 and r2.client_id = c8 and r2.tipo = 'invitacion_portal';
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select public.invitacion_portal_encolar(%L, array[%L]::uuid[], null)::text', u1, c8));
  r := r || pg_temp.l(v not like 'ERR%', 'C10b si la anterior falló, se puede volver a invitar (' || left(v, 30) || ')');
  exception when others then   -- la sección se deshace sola; el error sale como línea en rojo y la prueba sigue
    r := r || pg_temp.l(false, 'C sección cortada: ' || sqlstate || ' ' || left(sqlerrm, 300));
  end;

  -- ============================================================ D. «Enviarme una prueba»
  begin
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select public.invitacion_portal_prueba(%L, null)', u1));
  r := r || pg_temp.l(v = 'z***@prueba.invalid', 'D1 la prueba va a quien pulsa, enmascarado (' || v || ')');
  select cola_id into qp from public.reclamos_pago where unidad_id = u1 and prueba and tipo = 'invitacion_portal' order by creado_en desc limit 1;
  select count(*) into n from public.reclamos_pago where prueba and tipo = 'invitacion_portal' and creado_por = ae.em;
  r := r || pg_temp.l(n = 1 and qp is not null, 'D1b una fila de prueba, con su cola');
  for n in 1..4 loop perform pg_temp.val('authenticated', ae.uid, ae.em, format('select public.invitacion_portal_prueba(%L, null)', u1)); end loop;
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select public.invitacion_portal_prueba(%L, null)', u1));
  r := r || pg_temp.l(v = 'ERR22023:tope_pruebas', 'D2 la sexta prueba en una hora: tope_pruebas (' || v || ')');
  v := pg_temp.val('authenticated', ae.uid, ae.em, format('select public.reclamo_pago_prueba(%L, null)', u1));
  r := r || pg_temp.l(v = 'z***@prueba.invalid', 'D3 el tope es por correo: Reclamar pago tiene el suyo y su prueba sale (' || v || ')');
  exception when others then   -- la sección se deshace sola; el error sale como línea en rojo y la prueba sigue
    r := r || pg_temp.l(false, 'D sección cortada: ' || sqlstate || ' ' || left(sqlerrm, 300));
  end;

  -- ============================================================ E. la cola: vigencia al enviar, datos, FK, cierre
  begin
  r := r || pg_temp.l(public._reclamo_pago_vigente(i1), 'E1 la invitación del titular está vigente');
  r := r || pg_temp.l(public._reclamo_pago_vigente(i2), 'E2 la del COPROPIETARIO también (no hereda la condición adq1/firma/sociedad del reclamo)');
  update public.clients set email = eq2.em where id = c1;   -- eq2.em, no ag.em: C3 ya lo tiene (clients_email_tipo_key)
  r := r || pg_temp.l(not public._reclamo_pago_vigente(i1), 'E3 si la ficha pasa a un correo del equipo mientras espera, ya no está vigente (se cancela al enviar)');
  update public.clients set email = 'zz-ip-uno@prueba.invalid' where id = c1;
  r := r || pg_temp.l(public._reclamo_pago_vigente(i1), 'E3b y vuelve con la ficha buena');
  select count(*) into n from public.invitacion_portal_datos(q1) d where d.para = 'zz-ip-uno@prueba.invalid' and d.contrato_id = k1 and d.nota = 'Hola, revisa todo, por favor' and d.parcela = 'ZZ-IP-1';
  r := r || pg_temp.l(n = 1, 'E4 invitacion_portal_datos: destinatario de la ficha, contrato del libro, nota y parcela');
  insert into public.correos_cola (clave, reclamo_id, prioridad) values ('reclamo_pago', rr, 7) returning id into qr;
  update public.reclamos_pago set cola_id = qr where id = rr;
  select count(*) into n from public.invitacion_portal_datos(qr);
  select count(*) into n2 from public.reclamo_pago_datos(q1);
  r := r || pg_temp.l(n = 0 and n2 = 0, 'E5 el id de cola de un reclamo no compone una invitación, ni al revés');
  insert into public.reclamos_pago (unidad_id, contrato_id, client_id, creado_por, tipo) values (u1, k1, c1, ae.em, 'invitacion_portal') returning id into rx;
  begin
    insert into public.correos_cola (clave, reclamo_id, prioridad) values ('reclamo_pago', rx, 7);
    r := r || pg_temp.l(false, 'E6 una fila de cola con clave reclamo_pago colgada de una invitación entró');
  exception when foreign_key_violation then
    r := r || pg_temp.l(true, 'E6 FK compuesta: la clave de la cola tiene que ser el tipo del libro (23503)');
  end;
  update public.correos_cola set estado = 'enviando', reclamado_hasta = now() + interval '4 minutes' where id in (q1, qp);
  select count(*) into n from public.correos_enviados where contrato_id = k1;
  b := public.correo_cola_ok(q1, 'zz-ip-uno@prueba.invalid', 'f:12345678');
  select count(*) into n2 from public.correos_enviados where contrato_id = k1 and via = 'invitacion_portal' and plantilla = 'invitacion_portal'
     and asunto = 'Invitación al portal' and para = 'zz-ip-uno@prueba.invalid';
  r := r || pg_temp.l(b and n2 = 1, 'E7 cerrar ok una invitación real: correos_enviados con vía y plantilla invitacion_portal, en su contrato');
  b := public.correo_cola_ok(qp, ae.em, 'f:12345678');
  select count(*) into n2 from public.correos_enviados where contrato_id = k1;
  r := r || pg_temp.l(b and n2 = n + 1, 'E8 cerrar ok una prueba no deja registro de «correo enviado» en el contrato');
  exception when others then   -- la sección se deshace sola; el error sale como línea en rojo y la prueba sigue
    r := r || pg_temp.l(false, 'E sección cortada: ' || sqlstate || ' ' || left(sqlerrm, 300));
  end;

  -- ============================================================ F. el login del portal no cambia (Seguridad #357 punto 2)
  begin
  -- universo: clients ∪ usuarios ∪ portal_accesos ∪ casos sintéticos; se compara con los tres rechazos copiados LETRA A LETRA de
  -- 20260908013953 (antes de esta migración). Sin escribir: la función que escribe (portal_autoservicio) va en F3, aparte.
  select count(*) into n from (
    select e from (select email as e from public.clients union select email from public.usuarios union select email from public.portal_accesos
                   union select unnest(array[null, '', '   ', 'ZZ-IP-AGENTE@PRUEBA.INVALID', '  zz-ip-cinco@prueba.invalid ', 'sin-arroba', 'a@b',
                                             'a@b.c', 'zz ip@prueba.invalid', c_eq2_auth])) u) x
   where public._portal_rechazo(x.e) is distinct from (
     -- «w.em» y no «v»: v es variable de este bloque y PL/pgSQL no sabe si es la columna o la variable (rama del 15-oct)
     with w as (select lower(btrim(coalesce(x.e, ''))) as em)
     select case when (select w.em from w) !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then 'email_invalido'
                 when exists (select 1 from public.usuarios u where lower(btrim(u.email)) = (select w.em from w)) then 'equipo'
                 when exists (select 1 from public.portal_accesos pa where pa.email = (select w.em from w) and not pa.activo) then 'revocado' end);
  r := r || pg_temp.l(n = 0, 'F1 _portal_rechazo da lo mismo que los tres rechazos de antes en todo el universo (' || n || ' diferencias)');
  select count(*) into n from (select email as e from public.clients union select email from public.usuarios union select email from public.portal_accesos) u
   where public._portal_rechazo(u.e) is not null and public.portal_elegible(u.e, k1);
  r := r || pg_temp.l(n = 0, 'F2 portal_elegible (que NO se toca) nunca deja pasar un correo que el helper rechaza (' || n || ')');
  r := r || pg_temp.l((public.portal_autoservicio(ag.em)->>'motivo') = 'equipo'
                      and (public.portal_autoservicio('zz-ip-cinco@prueba.invalid')->>'motivo') = 'revocado'
                      and (public.portal_autoservicio('sin-arroba')->>'motivo') = 'email_invalido'
                      and (public.portal_autoservicio('zz-ip-ocho@prueba.invalid')->>'elegible')::boolean
                      and (public.portal_autoservicio('zz-ip-nadie@prueba.invalid')->>'motivo') = 'sin_ficha',
                      'F3 portal_autoservicio: equipo, revocado, email_invalido, elegible y sin_ficha como siempre');
  select count(*) into n from pg_proc p where p.oid = 'public.portal_autoservicio(text)'::regprocedure and p.prosecdef
     and position('_portal_rechazo' in p.prosrc) > 0 and position('public.usuarios' in p.prosrc) = 0 and position('not pa.activo' in p.prosrc) = 0;
  r := r || pg_temp.l(n = 1, 'F4 portal_autoservicio ya no lleva su copia de los rechazos: llama al helper');
  exception when others then   -- la sección se deshace sola; el error sale como línea en rojo y la prueba sigue
    r := r || pg_temp.l(false, 'F sección cortada: ' || sqlstate || ' ' || left(sqlerrm, 300));
  end;

  -- ============================================================ G. todas las lectoras del libro, conocidas (Base de datos #357 punto 3)
  begin
  select string_agg(p.proname, ',' order by p.proname) into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prosrc ilike '%reclamos_pago%'
     and p.proname not in ('_reclamo_pago_destino', '_reclamo_pago_vigente', 'correo_cola_reclamar', 'correo_cola_ok',
                           'reclamo_pago_datos', 'reclamo_pago_destinatarios', 'reclamo_pago_encolar', 'reclamo_pago_historial', 'reclamo_pago_prueba',
                           'invitacion_portal_datos', 'invitacion_portal_destinatarios', 'invitacion_portal_encolar', 'invitacion_portal_historial',
                           'invitacion_portal_prueba');
  r := r || pg_temp.l(v is null, 'G1 ninguna lectora nueva del libro sin revisar su filtro por tipo (' || coalesce(v, 'ninguna') || ')');
  select string_agg(p.proname, ',' order by p.proname) into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('_reclamo_pago_vigente', 'reclamo_pago_datos', 'reclamo_pago_destinatarios', 'reclamo_pago_encolar', 'reclamo_pago_historial',
                       'reclamo_pago_prueba', 'invitacion_portal_datos', 'invitacion_portal_destinatarios', 'invitacion_portal_encolar',
                       'invitacion_portal_historial', 'invitacion_portal_prueba')
     and position('tipo' in p.prosrc) = 0;
  r := r || pg_temp.l(v is null, 'G2 las que leen un tipo concreto lo filtran (' || coalesce(v, 'todas') || ')');
  exception when others then   -- la sección se deshace sola; el error sale como línea en rojo y la prueba sigue
    r := r || pg_temp.l(false, 'G sección cortada: ' || sqlstate || ' ' || left(sqlerrm, 300));
  end;

  -- ============================================================ H. Reclamar pago saca el titular de contrato_compradores (Base de datos #357 punto 4)
  begin
  -- (sin tocar el contrato: un update dispararía la resincronización de compradores desde datos, que no los trae)
  select count(*) into n from public.contratos where id = k3 and adq1_client_id is null;
  r := r || pg_temp.l(n = 1, 'H0 K3 tiene adq1_client_id vacío (la copia que antes leía Reclamar pago)');
  select count(*) into n from public._reclamo_pago_candidatos(u2) c where c.client_id = c9 and c.seleccionable and c.orden = 1;
  r := r || pg_temp.l(n = 1, 'H1 un contrato firmado con su titular en contrato_compradores y adq1_client_id vacío: el titular se puede reclamar');
  select count(*) into n from public._reclamo_pago_candidatos(u1) c where c.client_id in (c2, c3, c4) ;
  r := r || pg_temp.l(n = 0, 'H2 Reclamar pago sigue yendo SOLO al titular (adquiriente_1), no a los copropietarios');
  exception when others then   -- la sección se deshace sola; el error sale como línea en rojo y la prueba sigue
    r := r || pg_temp.l(false, 'H sección cortada: ' || sqlstate || ' ' || left(sqlerrm, 300));
  end;

  raise exception 'FIN DE PRUEBAS INVITACION PORTAL (se deshace todo):%', r;
end $todo$;
