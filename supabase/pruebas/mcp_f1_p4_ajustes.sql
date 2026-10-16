-- Prueba de las funciones de las pantallas del MCP (16-oct-2026, migración 20261016073530_mcp_f1_p4_ajustes.sql, sobre P1).
-- Solo en rama: siembra usuarios en auth.users. Termina en raise: no deja rastro.
-- Lo que prueba (cada línea con su resultado):
--   A  default-deny: anon sin EXECUTE en las 6; authenticated sin EXECUTE en los ayudantes privado.ia_*
--   B  un agente (no super admin) → 42501 en datos, guarda, cliente y permiso; desde dentro de una llamada del asistente → 42501
--   C  ia_ajustes_guarda: campo desconocido, fuera de rango y encender con tope 0 → error; lo bueno → se guarda con quién
--   D  ia_cliente_guarda: dirección ajena, http, con consulta o de OTRO asistente → error; la buena → cliente; apagarlo → sus
--      conexiones vivas quedan revocadas en el acto
--   E  ia_permiso_guarda: usuario inactivo → error; conceder → permiso; quitar → sin permiso y conexiones revocadas en el acto
--   F  ia_peticion_datos: petición inventada → error; buena → asistente y «puede»; sin permiso → puede=false; no gasta la petición
--   G  ia_mis_conexiones: cada persona ve solo las suyas
-- destructivo-ok: prueba en transacción que termina en raise (rollback)
create temp table _tp (et text primary key, uid uuid, em text, rol text, activo boolean);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
-- una RPC con la sesión de una persona; p_ia fija axw.ia_conexion como dentro de una llamada del asistente
create or replace function pg_temp.sesion(p_uid uuid, p_email text, p_sql text, p_ia boolean default false) returns text
language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email,
          'aal', 'aal1')::text, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  if p_ia then perform set_config('axw.ia_conexion', gen_random_uuid()::text, true); end if;
  execute 'set local role authenticated';
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('axw.ia_conexion', '', true);
  return coalesce(t, '(null)');
end $f$;

-- una respuesta que no es JSON (un error) no tumba la prueba: sale en su línea como FALLA
create or replace function pg_temp.js(p text) returns jsonb language plpgsql immutable as $f$
begin return p::jsonb; exception when others then return jsonb_build_object('ERR', left(p, 200)); end $f$;

insert into _tp values ('A', gen_random_uuid(), 'zz-mcp4-a@prueba.invalid', 'super_admin', true),
                       ('B', gen_random_uuid(), 'zz-mcp4-b@prueba.invalid', 'agente', true),
                       ('C', gen_random_uuid(), 'zz-mcp4-c@prueba.invalid', 'agente', false);

do $todo$
declare
  r text := ''; v text; j jsonb; n bigint; f text;
  a _tp; b _tp; c _tp; cli uuid; cli2 uuid; con_a uuid; con_b uuid; pet text := repeat('P', 43);
  red text := 'https://claude.ai/api/mcp/auth_callback';
  c_fin constant text := 'FIN DE PRUEBAS MCP P4 AJUSTES (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS MCP P4 AJUSTES:%', E'\nP0 esta prueba siembra usuarios en auth.users: solo corre en rama → FALLA';
  end if;
  select * into a from _tp where et = 'A'; select * into b from _tp where et = 'B'; select * into c from _tp where et = 'C';

  -- ============================================================ montaje (postgres)
  begin
    insert into auth.users (id, instance_id, email, aud, role, encrypted_password, raw_app_meta_data)
      select t.uid, '00000000-0000-0000-0000-000000000000', t.em, 'authenticated', 'authenticated', '$2a$10$zzmcp4' || t.et,
             '{"provider":"email"}'::jsonb from _tp t;
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo)
      select t.uid, t.em, 'ZZ-MCP4 ' || t.et, t.rol, 'global', '{}'::text[], '{}'::uuid[], '{}'::uuid[], '{}'::text[], '{}'::text[], t.activo
        from _tp t;
    update public.ia_ajustes set encendido = false, tope_dia = 0 where id;
    if not has_function_privilege('authenticated', 'public.ia_peticion_datos(text)', 'execute') then
      grant execute on function public.ia_peticion_datos(text) to authenticated;   -- propuestas/20261016140000 lo hace en la viva con el OK del owner
    end if;
    insert into public.ia_clientes (asistente, nombre, redirect_uris, activo) values ('claude', 'Claude', array[red], true) returning id into cli;
    insert into public.ia_permisos (usuario_id) values (a.uid), (b.uid);
    insert into public.ia_conexiones (usuario_id, cliente_id, recurso, huella, aal, expira_en)
      values (a.uid, cli, 'https://x.invalid/mcp', 'h', 'aal1', now() + interval '7 days') returning id into con_a;
    insert into public.ia_conexiones (usuario_id, cliente_id, recurso, huella, aal, expira_en)
      values (b.uid, cli, 'https://x.invalid/mcp', 'h', 'aal1', now() + interval '7 days') returning id into con_b;
    insert into public.ia_peticiones (id_hash, cliente_id, redirect_uri, code_challenge, recurso, estado)
      values (privado.ia_hash(pet), cli, red, repeat('c', 43), 'https://x.invalid/mcp', 'st');
    r := r || pg_temp.l(true, 'P montaje: A super admin, B agente, C inactivo; A y B con permiso y una conexión viva cada uno');
  exception when others then
    raise exception 'FIN DE PRUEBAS MCP P4 AJUSTES:%', E'\nP montaje: ' || sqlerrm || ' → FALLA';
  end;

  -- ============================================================ A default-deny
  foreach f in array array['public.ia_peticion_datos(text)', 'public.ia_mis_conexiones()', 'public.ia_ajustes_datos()',
                           'public.ia_ajustes_guarda(jsonb)', 'public.ia_cliente_guarda(uuid,text,text,text[],boolean)',
                           'public.ia_permiso_guarda(uuid,boolean)'] loop
    r := r || pg_temp.l(not has_function_privilege('anon', f, 'execute') and has_function_privilege('authenticated', f, 'execute'),
                        'A1 ' || f || ': anon no, authenticated sí');
  end loop;
  foreach f in array array['privado.ia_pantalla_uid()', 'privado.ia_gestor_uid()', 'privado.ia_redirect_valida(text,text)',
                           'privado.ia_equipo()'] loop
    r := r || pg_temp.l(not has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'),
                        'A2 ' || f || ': ni anon ni authenticated');
  end loop;

  -- ============================================================ B quién
  v := pg_temp.sesion(b.uid, b.em, 'select public.ia_ajustes_datos()::text');
  r := r || pg_temp.l(v like 'ERR42501%', 'B1 agente lee Ajustes › IA → ' || left(v, 80));
  v := pg_temp.sesion(b.uid, b.em, 'select public.ia_ajustes_guarda(''{"tope_dia":50}'')::text');
  r := r || pg_temp.l(v like 'ERR42501%', 'B2 agente guarda el tope → ' || left(v, 80));
  v := pg_temp.sesion(b.uid, b.em, format('select public.ia_cliente_guarda(null, ''claude'', ''X'', array[%L], true)::text', red));
  r := r || pg_temp.l(v like 'ERR42501%', 'B3 agente crea un cliente → ' || left(v, 80));
  v := pg_temp.sesion(b.uid, b.em, format('select public.ia_permiso_guarda(%L, true)::text', b.uid));
  r := r || pg_temp.l(v like 'ERR42501%', 'B4 agente se da permiso → ' || left(v, 80));
  v := pg_temp.sesion(a.uid, a.em, 'select public.ia_ajustes_guarda(''{"encendido":true,"tope_dia":50}'')::text', true);
  r := r || pg_temp.l(v like 'ERR42501%', 'B5 super admin DESDE una llamada del asistente → ' || left(v, 80));
  v := pg_temp.sesion(a.uid, a.em, 'select public.ia_mis_conexiones()::text', true);
  r := r || pg_temp.l(v like 'ERR42501%', 'B6 «apps conectadas» desde una llamada del asistente → ' || left(v, 80));
  v := pg_temp.sesion(null, null, 'select public.ia_mis_conexiones()::text');
  r := r || pg_temp.l(v like 'ERR42501%', 'B7 sin sesión → ' || left(v, 80));

  -- ============================================================ C interruptor
  v := pg_temp.sesion(a.uid, a.em, 'select public.ia_ajustes_guarda(''{"encendido":true,"recurso":"https://malo.invalid/"}'')::text');
  r := r || pg_temp.l(pg_temp.js(v) ->> 'error' = 'campo_desconocido', 'C1 campo que no se edita (recurso) → ' || v);
  v := pg_temp.sesion(a.uid, a.em, 'select public.ia_ajustes_guarda(''{"tope_dia":9999}'')::text');
  r := r || pg_temp.l(pg_temp.js(v) ->> 'error' = 'fuera_de_rango', 'C2 tope 9999 → ' || v);
  v := pg_temp.sesion(a.uid, a.em, 'select public.ia_ajustes_guarda(''{"tope_dia":"mucho"}'')::text');
  r := r || pg_temp.l(pg_temp.js(v) ->> 'error' = 'datos_invalidos', 'C3 tope no numérico → ' || v);
  v := pg_temp.sesion(a.uid, a.em, 'select public.ia_ajustes_guarda(''{"encendido":true}'')::text');
  r := r || pg_temp.l(pg_temp.js(v) ->> 'error' = 'falta_tope', 'C4 encender con tope 0 → ' || v);
  select count(*) into n from public.ia_ajustes where id and not encendido and tope_dia = 0;
  r := r || pg_temp.l(n = 1, 'C5 tras los rechazos sigue apagado y con tope 0');
  v := pg_temp.sesion(a.uid, a.em, 'select public.ia_ajustes_guarda(''{"encendido":true,"tope_dia":40,"max_conexiones":3}'')::text');
  select count(*) into n from public.ia_ajustes where id and encendido and tope_dia = 40 and max_conexiones = 3 and actualizado_por = a.uid;
  r := r || pg_temp.l(pg_temp.js(v) ->> 'ok' = 'true' and n = 1, 'C6 encender con tope 40 → ' || v || ', guardado con quién');
  v := pg_temp.sesion(a.uid, a.em, 'select public.ia_ajustes_datos()::text');
  j := pg_temp.js(v);
  r := r || pg_temp.l((j -> 'ajustes' ->> 'tope_dia') = '40' and jsonb_array_length(j -> 'conexiones') >= 2
                      and exists (select 1 from jsonb_array_elements(j -> 'usuarios') x where x ->> 'user_id' = b.uid::text and (x ->> 'permiso')::boolean)
                      and not exists (select 1 from jsonb_array_elements(j -> 'usuarios') x where x ->> 'user_id' = c.uid::text),
                      'C7 super admin lee Ajustes › IA: tope, conexiones vivas, B con permiso y C (inactivo) fuera');

  -- ============================================================ D clientes
  foreach f in array array['https://evil.example/cb', 'http://claude.ai/api/mcp/auth_callback', 'https://claude.ai.evil.com/cb',
                           'https://claude.ai/api/mcp/auth_callback?x=1', 'https://claude.ai@evil.com/cb',
                           'https://chatgpt.com/connector_platform_oauth_redirect'] loop
    v := pg_temp.sesion(a.uid, a.em, format('select public.ia_cliente_guarda(null, ''claude'', ''Claude 2'', array[%L], true)::text', f));
    r := r || pg_temp.l(pg_temp.js(v) ->> 'error' = 'redirect_uri', 'D1 Claude con vuelta ' || f || ' → ' || left(v, 60));
  end loop;
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_cliente_guarda(null, ''gemini'', ''G'', array[%L], true)::text', red));
  r := r || pg_temp.l(pg_temp.js(v) ->> 'error' = 'asistente', 'D2 asistente fuera de lista → ' || v);
  v := pg_temp.sesion(a.uid, a.em, 'select public.ia_cliente_guarda(null, ''chatgpt'', ''ChatGPT'', array[''https://chatgpt.com/connector_platform_oauth_redirect''], false)::text');
  cli2 := (pg_temp.js(v) ->> 'id')::uuid;
  select count(*) into n from public.ia_clientes where id = cli2 and asistente = 'chatgpt' and not activo and creado_por = a.uid;
  r := r || pg_temp.l(n = 1, 'D3 cliente ChatGPT nuevo, apagado, con quién lo creó → ' || v);
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_cliente_guarda(%L, ''claude'', ''Claude'', array[%L], false)::text', cli, red));
  select count(*) into n from public.ia_conexiones where cliente_id = cli and revocada_en is not null and revocada_motivo = 'cliente';
  r := r || pg_temp.l(pg_temp.js(v) ->> 'ok' = 'true' and n = 2, 'D4 apagar el cliente Claude → sus 2 conexiones revocadas en el acto (' || n || ')');
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_cliente_guarda(%L, ''claude'', ''Claude'', array[%L], true)::text', gen_random_uuid(), red));
  r := r || pg_temp.l(pg_temp.js(v) ->> 'error' = 'no_existe', 'D5 cliente inventado → ' || v);
  -- vuelta a la normalidad para F/G: cliente encendido y conexiones nuevas
  update public.ia_clientes set activo = true where id = cli;
  insert into public.ia_conexiones (usuario_id, cliente_id, recurso, huella, aal, expira_en)
    values (b.uid, cli, 'https://x.invalid/mcp', 'h', 'aal1', now() + interval '7 days') returning id into con_b;

  -- ============================================================ E permisos
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_permiso_guarda(%L, true)::text', c.uid));
  r := r || pg_temp.l(pg_temp.js(v) ->> 'error' = 'usuario_inactivo', 'E1 permiso a un usuario inactivo → ' || v);
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_permiso_guarda(%L, true)::text', gen_random_uuid()));
  r := r || pg_temp.l(pg_temp.js(v) ->> 'error' = 'usuario_inactivo', 'E2 permiso a un id inventado → ' || v);
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_permiso_guarda(%L, false)::text', b.uid));
  select count(*) into n from public.ia_conexiones where id = con_b and revocada_motivo = 'permiso';
  r := r || pg_temp.l(pg_temp.js(v) ->> 'ok' = 'true' and n = 1 and not exists (select 1 from public.ia_permisos where usuario_id = b.uid and quitado_en is null)
                      and exists (select 1 from public.ia_permisos where usuario_id = b.uid and quitado_por = a.uid),
                      'E3 quitar el permiso a B → sin permiso, la fila guarda quién se lo quitó y su conexión revocada en el acto');
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_permiso_guarda(%L, true)::text', b.uid));
  select count(*) into n from public.ia_permisos where usuario_id = b.uid and concedido_por = a.uid and quitado_en is null and quitado_por is null;
  r := r || pg_temp.l(n = 1, 'E4 volver a darle permiso → con quién lo concedió y sin la marca de quitado');

  -- ============================================================ F página de conexión
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_peticion_datos(%L)::text', repeat('Q', 43)));
  r := r || pg_temp.l(pg_temp.js(v) ->> 'error' = 'peticion_invalida', 'F1 petición inventada → ' || v);
  v := pg_temp.sesion(a.uid, a.em, 'select public.ia_peticion_datos(''corta'')::text');
  r := r || pg_temp.l(pg_temp.js(v) ->> 'error' = 'peticion_invalida', 'F2 petición con forma rara → ' || v);
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_peticion_datos(%L)::text', pet));
  r := r || pg_temp.l(pg_temp.js(v) ->> 'asistente' = 'claude' and (pg_temp.js(v) ->> 'puede')::boolean
                      and pg_temp.js(v) ->> 'destino' = 'claude.ai' and (pg_temp.js(v) ->> 'quedan_s')::integer between 1 and 300,
                      'F3 A con permiso, con el dominio de vuelta y los segundos que le quedan → ' || v);
  update public.ia_permisos set quitado_en = now() where usuario_id = b.uid;
  v := pg_temp.sesion(b.uid, b.em, format('select public.ia_peticion_datos(%L)::text', pet));
  r := r || pg_temp.l(not (pg_temp.js(v) ->> 'puede')::boolean and pg_temp.js(v) ->> 'motivo' = 'sin_permiso', 'F4 B sin permiso → ' || v);
  select count(*) into n from public.ia_peticiones where id_hash = privado.ia_hash(pet) and usada_en is null;
  r := r || pg_temp.l(n = 1, 'F5 consultar la petición no la gasta');

  -- ============================================================ G apps conectadas
  v := pg_temp.sesion(b.uid, b.em, 'select public.ia_mis_conexiones()::text');
  j := pg_temp.js(v);
  r := r || pg_temp.l(not exists (select 1 from jsonb_array_elements(j -> 'conexiones') x where x ->> 'id' = con_a::text)
                      and exists (select 1 from jsonb_array_elements(j -> 'conexiones') x where x ->> 'id' = con_b::text)
                      and not (j ->> 'permiso')::boolean,
                      'G1 B ve solo las suyas y que no tiene permiso (' || jsonb_array_length(j -> 'conexiones') || ' conexiones)');

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
