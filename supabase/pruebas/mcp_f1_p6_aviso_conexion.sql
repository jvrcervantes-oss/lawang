-- Prueba de P6 del puente MCP: el correo a la persona en cada conexión nueva (16-oct-2026, migración
-- 20261016135900_mcp_f1_p6_aviso_conexion.sql; se corre con la propuesta 20261016140000 aplicada o sin ella: si authenticated no tiene
-- EXECUTE sobre ia_conexion_autoriza, la prueba se lo da DENTRO de la transacción, que se deshace). Solo en rama: siembra usuarios en
-- auth.users. Termina en raise: no deja rastro. Revisión previa #404 (Seguridad + Base de datos); cada línea con su resultado:
--   A  permisos: las funciones nuevas sin EXECUTE para nadie salvo ia_aviso_conexion_datos (solo service_role); correo_encolar rechaza la clave
--   B  el alta por la RPC REAL como authenticated ⇒ una fila pendiente con su ancla, vars '{}'; reclamar da como destino el correo de
--      AUTH (no la copia de usuarios); revocar antes de enviar NO la cancela; la RPC de datos da el mismo destino; ok ⇒ avisada_en y
--      nada en correos_enviados
--   C  el aviso no sale ⇒ la conexión se corta (sin_aviso) y su token muere: fallo final, tope de antigüedad y sin destinatario
--   D  tope de altas: la 6ª de una persona en una hora (cortadas incluidas) y la 21ª de la base ⇒ demasiadas_altas, sin conexión ni fila
--   E  el nombre del asistente pasa por la regla de las notas; el CHECK ata la clave a su ancla y vars vacío
--   F  «cambia tu contraseña» del correo es verdad: la huella de la conexión lleva la contraseña (propuesta 20261016140000)
-- destructivo-ok: prueba en transacción que termina en raise (rollback)
create temp table _tp (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
create or replace function pg_temp.edge(p_accion text, p_datos jsonb) returns jsonb language plpgsql as $f$
declare t jsonb;
begin
  perform set_config('request.method', 'POST', true);
  perform set_config('request.headers', '{}', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  begin t := public.ia_puente(p_accion, p_datos);
  exception when others then t := jsonb_build_object('ERR', sqlstate, 'msg', left(sqlerrm, 200)); end;
  execute 'reset role';
  return t;
end $f$;
-- una RPC con la sesión de una persona (amr password de hace 5 s), como la página de conexión
create or replace function pg_temp.sesion(p_uid uuid, p_email text, p_sql text) returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email, 'aal', 'aal1',
          'amr', json_build_array(json_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint - 5)))::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  execute 'set local role authenticated';
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  return coalesce(t, '(null)');
end $f$;
-- lo que hace la edge cola-correos-envio / envia-correo: service_role
create or replace function pg_temp.servicio(p_sql text) returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(t, '(null)');
end $f$;
create or replace function pg_temp.b64(p bytea) returns text language sql immutable as $f$
  select rtrim(translate(encode(p, 'base64'), E'+/\n', '-_'), '=') $f$;

insert into _tp values ('A', gen_random_uuid(), 'zz-p6-a@prueba.invalid'),
                       ('B', gen_random_uuid(), 'zz-p6-b@prueba.invalid'),
                       ('C', gen_random_uuid(), 'zz-p6-c-sin-arroba');      -- correo de Auth no válido: sin destinatario
insert into _tp select 'G' || g, gen_random_uuid(), 'zz-p6-g' || g || '@prueba.invalid' from generate_series(1, 4) g;   -- tope global

do $todo$
declare
  r text := ''; v text; j jsonb; n bigint; n2 bigint; i int;
  a _tp; b _tp; c _tp; cli uuid; red text := 'https://claude.ai/api/mcp/auth_callback'; rec text;
  ver text := repeat('v', 50); cha text; con uuid; con2 uuid; fila uuid; acc text;
  c_fin constant text := 'FIN DE PRUEBAS MCP P6 AVISO (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS MCP P6 AVISO:%', E'\nP0 esta prueba siembra usuarios en auth.users: solo corre en rama → FALLA';
  end if;
  select * into a from _tp where et = 'A'; select * into b from _tp where et = 'B'; select * into c from _tp where et = 'C';
  cha := pg_temp.b64(sha256(convert_to(ver, 'UTF8')));

  -- ============================================================ montaje (postgres, sin sesión)
  begin
    insert into auth.users (id, instance_id, email, aud, role, encrypted_password, raw_app_meta_data)
      select t.uid, '00000000-0000-0000-0000-000000000000', t.em, 'authenticated', 'authenticated', '$2a$10$zzp6prueba' || t.et,
             '{"provider":"email"}'::jsonb from _tp t;
    -- usuarios.email de A es OTRO a propósito: el aviso tiene que ir al correo de Auth, nunca a esta copia
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo)
      select t.uid, case when t.et = 'A' then 'zz-p6-copia-vieja@prueba.invalid' else t.em end, 'ZZ-P6 ' || t.et, 'super_admin', 'global',
             '{}'::text[], '{}'::uuid[], '{}'::uuid[], '{}'::text[], '{}'::text[], true from _tp t;
    insert into public.ia_ajustes default values on conflict do nothing;   -- la fila única que siembra 073011 (una rama sin filas no la trae)
    update public.ia_ajustes set encendido = true, tope_dia = 50 where id;
    select recurso into rec from public.ia_ajustes where id;
    insert into public.ia_clientes (asistente, nombre, redirect_uris, activo) values ('claude', 'Claude de prueba', array[red], true) returning id into cli;
    insert into public.ia_permisos (usuario_id) select t.uid from _tp t;
    if not has_function_privilege('anon', 'public.ia_puente(text,jsonb)', 'execute') then
      grant execute on function public.ia_puente(text, jsonb) to anon;              -- 20261016140000 lo hace en la viva
    end if;
    if not has_function_privilege('authenticated', 'public.ia_conexion_autoriza(text)', 'execute') then
      grant execute on function public.ia_conexion_autoriza(text) to authenticated; -- ídem
    end if;
    -- lo que hubiera en la cola de la rama no cuenta: sale del turno (se deshace al final)
    update public.correos_cola q set proximo_intento_en = now() + interval '30 days' where q.estado = 'pendiente';
    r := r || pg_temp.l(true, 'P montaje: A, B, C y 4 más con permiso de IA; cliente Claude activo');
  exception when others then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'P montaje: ' || sqlstate || ' ' || left(sqlerrm, 300)));
  end;

  -- ============================================================ A. permisos
  select string_agg(p.oid::regprocedure::text || ':' || x.g, ',' order by 1) into v
    from pg_proc p cross join lateral (select coalesce(r2.rolname, 'PUBLIC') g from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) e
                                        left join pg_roles r2 on r2.oid = e.grantee where e.privilege_type = 'EXECUTE'
                                         and coalesce(r2.rolname, 'PUBLIC') in ('PUBLIC', 'anon', 'authenticated', 'service_role', 'lw_lector')) x
   where p.proname in ('ia_aviso_conexion', 'ia_aviso_fallido', 'ia_aviso_destino', 'ia_aviso_nombre', 'ia_aviso_conexion_datos');
  r := r || pg_temp.l(v = 'ia_aviso_conexion_datos(uuid):service_role',
                      'A1 EXECUTE de anon/authenticated/service_role/PUBLIC/lw_lector: solo ia_aviso_conexion_datos a service_role (' || coalesce(v, '-') || ')');
  select string_agg(p.proname || '=' || pg_get_userbyid(p.proowner) || case when p.prosecdef then '/definer' else '/invoker' end, ',' order by p.proname) into v
    from pg_proc p where p.proname in ('ia_aviso_conexion', 'ia_aviso_fallido', 'ia_aviso_destino', 'ia_aviso_nombre', 'ia_aviso_conexion_datos');
  r := r || pg_temp.l(v = 'ia_aviso_conexion=postgres/definer,ia_aviso_conexion_datos=postgres/definer,ia_aviso_destino=postgres/invoker,ia_aviso_fallido=postgres/definer,ia_aviso_nombre=postgres/invoker',
                      'A2 dueños y tipo (' || coalesce(v, '-') || ')');
  v := pg_temp.servicio('select public.correo_encolar(''aviso_ia_conexion'', null, null, null, ''{}''::jsonb)::text');
  r := r || pg_temp.l(v like 'ERR22023:clave_no_soportada_aun%', 'A3 correo_encolar rechaza la clave (solo entra por el trigger) → ' || v);
  v := pg_temp.sesion(a.uid, a.em, format('select count(*)::text from public.ia_aviso_conexion_datos(%L)', gen_random_uuid()));
  r := r || pg_temp.l(v like 'ERR42501%', 'A4 una sesión no lee los datos del aviso → ' || left(v, 40));

  -- ============================================================ B. el alta por la RPC real
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_autoriza(%L)::text', j ->> 'peticion'));
  select id into con from public.ia_conexiones where usuario_id = a.uid;
  r := r || pg_temp.l(v::jsonb ? 'code' and con is not null, 'B1 A conecta por ia_conexion_autoriza como authenticated → código');
  select count(*) into n from public.correos_cola q
   where q.ia_conexion_id = con and q.clave = 'aviso_ia_conexion' and q.estado = 'pendiente' and q.vars = '{}'::jsonb and q.prioridad = 2
     and num_nonnulls(q.firma_id, q.contrato_id, q.factura_id, q.reclamo_id) = 0;
  select q.id into fila from public.correos_cola q where q.ia_conexion_id = con;
  r := r || pg_temp.l(n = 1 and (select count(*) from public.correos_cola q where q.ia_conexion_id = con) = 1,
                      'B2 exactamente una fila pendiente, ancla ia_conexion_id, vars vacío, prioridad 2');
  perform privado.ia_revoca(con, 'persona');   -- la persona la quita antes de que salga el correo
  v := pg_temp.servicio('select coalesce(string_agg(x.id::text || ''|'' || coalesce(x.para, ''-''), '',''), ''-'') from public.correo_cola_reclamar(10) x');
  r := r || pg_temp.l(v = fila::text || '|' || a.em, 'B3 revocada antes de enviar: reclamar la entrega igual, al correo de Auth (no a la copia de usuarios) → ' || v);
  v := pg_temp.servicio(format('select x.para || ''|'' || x.asistente || ''|'' || coalesce(x.nombre_asistente, ''-'') || ''|'' || x.nombre from public.ia_aviso_conexion_datos(%L) x', fila));
  r := r || pg_temp.l(v = a.em || '|claude|Claude de prueba|ZZ-P6 A', 'B4 la RPC de datos: mismo destino, asistente y nombre → ' || v);
  v := pg_temp.servicio(format('select count(*)::text from public.ia_aviso_conexion_datos(%L)', (select x.id from public.correos_cola x where x.ia_conexion_id is null limit 1)));
  r := r || pg_temp.l(v in ('0', '(null)'), 'B5 con el id de otra fila de la cola no devuelve nada → ' || v);
  select count(*) into n from public.correos_enviados;
  v := pg_temp.servicio(format('select public.correo_cola_ok(%L, %L, ''f:0123abcd'')::text', fila, a.em));
  select count(*) into n2 from public.correos_enviados;
  r := r || pg_temp.l(v = 'true' and n2 = n and (select avisada_en is not null from public.ia_conexiones where id = con)
                      and (select estado from public.correos_cola where id = fila) = 'ok',
                      'B6 ok ⇒ fila ok, avisada_en puesto y nada en correos_enviados (' || n || ' → ' || n2 || ')');
  r := r || pg_temp.l((select revocada_motivo from public.ia_conexiones where id = con) = 'persona', 'B7 y la conexión sigue cortada por la persona (el aviso no la toca)');

  -- ============================================================ C. si el aviso no sale, la conexión se corta
  -- C1 fallo final (lo que marca la edge con un 400 terminal)
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  v := pg_temp.sesion(b.uid, b.em, format('select public.ia_conexion_autoriza(%L)::text', j ->> 'peticion'));
  j := pg_temp.edge('canjea', jsonb_build_object('codigo', v::jsonb ->> 'code', 'code_verifier', ver, 'cliente_id', cli, 'redirect_uri', red, 'recurso', rec));
  acc := j ->> 'access_token';
  select id into con2 from public.ia_conexiones where usuario_id = b.uid;
  select q.id into fila from public.correos_cola q where q.ia_conexion_id = con2;
  r := r || pg_temp.l(length(acc) = 43 and (select revocada_en is null from public.ia_conexiones where id = con2), 'C0 B conectada y con token mientras el aviso va de camino');
  perform pg_temp.servicio('select count(*)::text from public.correo_cola_reclamar(10)');
  v := pg_temp.servicio(format('select public.correo_cola_fallo(%L, ''HTTP 400'', p_terminal => true)::text', fila));
  r := r || pg_temp.l((select estado from public.correos_cola where id = fila) = 'error'
                      and (select revocada_motivo from public.ia_conexiones where id = con2) = 'sin_aviso',
                      'C1 fallo final del aviso ⇒ conexión cortada con motivo sin_aviso (' || v || ')');
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'mcp_resumen_semana'));
  r := r || pg_temp.l(j ->> 'error' = 'invalid_token', 'C2 y su token ya no llama → ' || j::text);
  -- C3 tope de antigüedad (envíos en pausa 24 h)
  update public.ia_conexiones set creada_en = creada_en - interval '2 hours';   -- fuera del tope de altas de esta hora
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  v := pg_temp.sesion(b.uid, b.em, format('select public.ia_conexion_autoriza(%L)::text', j ->> 'peticion'));
  select id into con2 from public.ia_conexiones where usuario_id = b.uid and revocada_en is null;
  update public.correos_cola set encolado_en = now() - interval '25 hours' where ia_conexion_id = con2;
  perform pg_temp.servicio('select count(*)::text from public.correo_cola_reclamar(10)');
  r := r || pg_temp.l((select error from public.correos_cola where ia_conexion_id = con2) = 'tope_antiguedad'
                      and (select revocada_motivo from public.ia_conexiones where id = con2) = 'sin_aviso',
                      'C3 aviso caducado (24 h) ⇒ conexión cortada con sin_aviso');
  -- C3b envíos EN PAUSA: la edge vuelve antes de reclamar, así que la cola nunca corta. Lo corta el puente en el siguiente uso.
  insert into public.mantenimiento (id, envios_pausados, motivo, cambiado_en) values (1, true, 'P6 C3b', now())
  on conflict (id) do update set envios_pausados = true;
  update public.ia_conexiones set creada_en = creada_en - interval '2 hours';
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  v := pg_temp.sesion(b.uid, b.em, format('select public.ia_conexion_autoriza(%L)::text', j ->> 'peticion'));
  j := pg_temp.edge('canjea', jsonb_build_object('codigo', v::jsonb ->> 'code', 'code_verifier', ver, 'cliente_id', cli, 'redirect_uri', red, 'recurso', rec));
  acc := j ->> 'access_token';
  select id into con2 from public.ia_conexiones where usuario_id = b.uid and revocada_en is null;
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'mcp_resumen_semana'));
  r := r || pg_temp.l(public.envios_pausados() and con2 is not null and j ->> 'error' is distinct from 'invalid_token',
                      'C3b con los envíos en pausa y el aviso recién encolado, el token llama (aún dentro de las 24 h) → ' || left(j::text, 60));
  update public.ia_conexiones set creada_en = now() - interval '25 hours' where id = con2;
  update public.correos_cola set encolado_en = now() - interval '25 hours' where ia_conexion_id = con2;
  -- «apps conectadas» (20261016230000) ya la enseña cortada antes de su siguiente uso, sin escribir nada
  if position('sin_aviso' in pg_get_functiondef('public.ia_mis_conexiones()'::regprocedure)) > 0 then
    v := pg_temp.sesion(b.uid, b.em, 'select public.ia_mis_conexiones()::text');
    select x into j from jsonb_array_elements(case when v like '{%' then v::jsonb -> 'conexiones' else '[]'::jsonb end) x where x ->> 'id' = con2::text;
    r := r || pg_temp.l(j ->> 'viva' = 'false' and j ->> 'revocada_motivo' = 'sin_aviso' and j ->> 'revocada_en' is not null
                        and (select revocada_en is null from public.ia_conexiones where id = con2),
                        'C3b «apps conectadas» la enseña cortada (sin_aviso) y la fila aún no está revocada → ' || left(coalesce(j::text, v), 90));
  else
    r := r || pg_temp.l(false, 'C3b «apps conectadas» OMITIDA: la 20261016230000 no está aplicada en esta rama');
  end if;
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'mcp_resumen_semana'));
  r := r || pg_temp.l(j ->> 'error' = 'invalid_token'
                      and (select revocada_motivo from public.ia_conexiones where id = con2) = 'sin_aviso'
                      and (select estado from public.correos_cola where ia_conexion_id = con2) = 'pendiente',
                      'C3b pasadas 24 h sin aviso y sin reclamar (pausa) ⇒ el puente corta con sin_aviso → ' || left(j::text, 60));
  update public.mantenimiento set envios_pausados = false where id = 1;
  -- C4 sin destinatario: el correo de Auth de C no es válido
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  v := pg_temp.sesion(c.uid, c.em, format('select public.ia_conexion_autoriza(%L)::text', j ->> 'peticion'));
  select id into con2 from public.ia_conexiones where usuario_id = c.uid;
  perform pg_temp.servicio('select count(*)::text from public.correo_cola_reclamar(10)');
  r := r || pg_temp.l(con2 is not null and (select error from public.correos_cola where ia_conexion_id = con2) = 'sin_destinatario'
                      and (select revocada_motivo from public.ia_conexiones where id = con2) = 'sin_aviso',
                      'C4 sin destinatario válido ⇒ conexión cortada con sin_aviso (' || left(v, 60) || ')');

  -- ============================================================ D. tope de altas
  update public.ia_conexiones set creada_en = creada_en - interval '2 hours';
  for i in 1..6 loop
    select count(*) into n from public.ia_conexiones;
    select count(*) into n2 from public.correos_cola;
    j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
    v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_autoriza(%L)::text', j ->> 'peticion'));
    -- crear y cortar en bucle: max_conexiones (solo las vivas) no lo frena
    perform privado.ia_revoca(x.id, 'persona') from public.ia_conexiones x where x.usuario_id = a.uid and x.revocada_en is null;
    if i <= 5 then
      if v not like '{%' or not (v::jsonb ? 'code') then
        r := r || pg_temp.l(false, 'D1 alta ' || i || ' de 5 en la hora debería valer → ' || v); exit;
      end if;
    else
      r := r || pg_temp.l(i = 6 and v like 'ERRP0001:demasiadas_altas%' and (select count(*) from public.ia_conexiones) = n
                          and (select count(*) from public.correos_cola) = n2,
                          'D1 la 6ª alta de A en una hora (5 cortadas) ⇒ demasiadas_altas, sin conexión ni fila de cola → ' || left(v, 60));
    end if;
  end loop;
  update public.ia_conexiones set creada_en = creada_en - interval '2 hours';
  begin
    insert into public.ia_conexiones (usuario_id, cliente_id, recurso, huella, aal, expira_en)
      select t.uid, cli, rec, 'h', 'aal1', now() + interval '7 days' from _tp t, generate_series(1, 5) where t.et like 'G%';
    r := r || pg_temp.l((select count(*) from public.ia_conexiones where creada_en > now() - interval '1 hour') = 20, 'D2 20 altas de 4 personas en la hora valen');
    begin
      insert into public.ia_conexiones (usuario_id, cliente_id, recurso, huella, aal, expira_en) values (b.uid, cli, rec, 'h', 'aal1', now() + interval '7 days');
      r := r || pg_temp.l(false, 'D3 la 21ª de la base debería fallar');
    exception when others then
      r := r || pg_temp.l(sqlerrm = 'demasiadas_altas', 'D3 la 21ª alta de la base en una hora (otra persona) ⇒ ' || sqlerrm);
    end;
  exception when others then
    r := r || pg_temp.l(false, 'D2 ' || sqlstate || ' ' || left(sqlerrm, 200));
  end;

  -- ============================================================ E. nombre del asistente y CHECK
  update public.ia_clientes set nombre = 'Entra en www.evil.example' where id = cli;
  v := pg_temp.servicio(format('select coalesce(x.nombre_asistente, ''(null)'') || ''|'' || x.asistente from public.ia_aviso_conexion_datos(%L) x',
                               (select q.id from public.correos_cola q join public.ia_conexiones k on k.id = q.ia_conexion_id where k.usuario_id = a.uid limit 1)));
  r := r || pg_temp.l(v = '(null)|claude', 'E1 un nombre con forma de enlace no llega al correo (solo «Claude») → ' || v);
  begin
    update public.ia_clientes set nombre = 'Claude' || chr(10) || 'Bcc: x' where id = cli;
    r := r || pg_temp.l(false, 'E2 un nombre con salto de línea debería fallar');
  exception when check_violation then r := r || pg_temp.l(true, 'E2 un nombre con caracteres de control no se guarda (ia_clientes_nombre_limpio)');
  end;
  begin
    insert into public.correos_cola (clave, ia_conexion_id, vars, prioridad) values ('invitacion_portal', con, '{}'::jsonb, 7);
    r := r || pg_temp.l(false, 'E3 otra clave con el ancla de conexión debería fallar');
  exception when check_violation or unique_violation then r := r || pg_temp.l(true, 'E3 otra clave con ia_conexion_id ⇒ rechazada (' || sqlerrm || ')');
  end;
  begin
    update public.correos_cola set vars = '{"asistente":"Evil"}'::jsonb where ia_conexion_id = con;
    r := r || pg_temp.l(false, 'E4 el aviso con vars debería fallar');
  exception when check_violation then r := r || pg_temp.l(true, 'E4 el aviso con vars no vacío ⇒ rechazado (correos_cola_ia_clave)');
  end;

  -- ============================================================ F. la frase «cambia tu contraseña»
  r := r || pg_temp.l(pg_get_functiondef('privado.ia_auth_usuario(uuid)'::regprocedure) ~ 'encrypted_password',
                      'F1 la huella de la conexión lleva la contraseña: cambiarla corta las conexiones, como dice el correo (sin la 140000 no se cumple y el correo mentiría)');

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
