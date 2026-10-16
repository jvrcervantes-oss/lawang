-- Prueba de la base del puente MCP (16-oct-2026, migración 20261016110000_mcp_f1_p1_base.sql; se corre también con
-- supabase/propuestas/20261016140000_mcp_f1_abre_conexion.sql (pendiente del OK del owner) aplicada o sin ella: si anon no tiene EXECUTE, la prueba se lo da DENTRO de la
-- transacción, que se deshace). Solo en rama: siembra usuarios en auth.users. Termina en raise: no deja rastro.
-- Lo que prueba (prueba-trampa de #394/#395, cada línea con su resultado):
--   A  default-deny: anon/authenticated sin nada en las 8 tablas ia_*; las funciones del puente con su EXECUTE exacto (aclexplode)
--   B  pide: redirect cambiado en un byte, PKCE plain, recurso ajeno, cliente apagado → error y 0 filas; la buena → petición
--   C  autoriza: contraseña de hace 5 min, sin permiso de IA, petición inventada → error; la buena → código; petición repetida → error
--   D  canjea: verificador malo → invalid_grant; bueno → par de tokens; el mismo código otra vez → invalid_grant y conexión revocada
--   E  llama: la persona dentro de la herramienta es la del token (auth.uid() y auth.email()); queda fila ok en ia_llamadas
--   F  tope del día: la llamada de más → «tope», con su fila; la base de negocio no cambia
--   G  refresca: rota R1→R2; R1 en ≤10 s con R2 sin usar → R3 y R2 muerto; R2 vuelve → revocada; R1 en ≤10 s con R2 ya usado
--      → revocada; R1 otra vez pasados 10 s → invalid_grant, conexión revocada y su access ya no llama
--   H  revocar: otro usuario → 42501; la persona → ok y el access muere en el acto
--   I  día 8 → invalid_token · contraseña cambiada → invalid_token y revocada · permiso quitado → invalid_token · apagado → no llama
--   J  GET y Prefer tx=rollback → rechazados · 300 tokens inventados → 0 escrituras · herramienta fuera de lista → error
-- destructivo-ok: prueba en transacción que termina en raise (rollback)
create temp table _tp (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
-- llamada como la edge: anon, POST, cabeceras de PostgREST
create or replace function pg_temp.edge(p_accion text, p_datos jsonb, p_metodo text default 'POST', p_cab jsonb default '{}')
returns jsonb language plpgsql as $f$
declare t jsonb;
begin
  perform set_config('request.method', p_metodo, true);
  perform set_config('request.headers', p_cab::text, true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  begin
    t := public.ia_puente(p_accion, p_datos);
  exception when others then t := jsonb_build_object('ERR', sqlstate, 'msg', left(sqlerrm, 200));
  end;
  execute 'reset role';
  return t;
end $f$;
-- una RPC con la sesión de una persona (claims con amr password de hace p_hace segundos)
create or replace function pg_temp.sesion(p_uid uuid, p_email text, p_sql text, p_hace integer default 5) returns text
language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email, 'aal', 'aal1',
          'amr', json_build_array(json_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint - p_hace)))::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  execute 'set local role authenticated';
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  return coalesce(t, '(null)');
end $f$;
create or replace function pg_temp.b64(p bytea) returns text language sql immutable as $f$
  select rtrim(translate(encode(p, 'base64'), E'+/\n', '-_'), '=') $f$;

insert into _tp values ('A', gen_random_uuid(), 'zz-mcp-a@prueba.invalid'),
                       ('B', gen_random_uuid(), 'zz-mcp-b@prueba.invalid');

do $todo$
declare
  r text := ''; v text; j jsonb; n bigint; n2 bigint;
  a _tp; b _tp; cli uuid; red text := 'https://claude.ai/api/mcp/auth_callback'; rec text;
  ver text := repeat('v', 50); cha text; pet text; cod text; acc text; ref text; ref2 text; acc2 text; ref3 text; acc3 text; con uuid;
  c_fin constant text := 'FIN DE PRUEBAS MCP P1 BASE (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS MCP P1 BASE:%', E'\nP0 esta prueba siembra usuarios en auth.users: solo corre en rama → FALLA';
  end if;
  select * into a from _tp where et = 'A'; select * into b from _tp where et = 'B';
  cha := pg_temp.b64(sha256(convert_to(ver, 'UTF8')));

  -- ============================================================ montaje (postgres, sin sesión)
  begin
    insert into auth.users (id, instance_id, email, aud, role, encrypted_password, raw_app_meta_data)
      select t.uid, '00000000-0000-0000-0000-000000000000', t.em, 'authenticated', 'authenticated', '$2a$10$zzmcpprueba' || t.et,
             '{"provider":"email"}'::jsonb from _tp t;
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (a.uid, a.em, 'ZZ-MCP A', 'super_admin', 'global', '{}'::text[], '{}'::uuid[], '{}'::uuid[], '{}'::text[], '{}'::text[], true),
      (b.uid, b.em, 'ZZ-MCP B', 'agente', 'global', '{}'::text[], '{}'::uuid[], '{}'::uuid[], '{}'::text[], '{}'::text[], true);
    update public.ia_ajustes set encendido = true, tope_dia = 3 where id;
    select recurso into rec from public.ia_ajustes where id;
    insert into public.ia_clientes (asistente, nombre, redirect_uris, activo) values ('claude', 'Claude', array[red], true) returning id into cli;
    insert into public.ia_permisos (usuario_id) values (a.uid);
    -- la entrada (anon) y el «sí» de la persona (authenticated) se abren JUNTOS (propuestas/20261016140000): o los dos o ninguno
    r := r || pg_temp.l(has_function_privilege('anon', 'public.ia_puente(text,jsonb)', 'execute')
                        = has_function_privilege('authenticated', 'public.ia_conexion_autoriza(text)', 'execute'),
                        'A0 ia_puente (anon) e ia_conexion_autoriza (authenticated) abiertos a la vez o cerrados a la vez');
    if not has_function_privilege('anon', 'public.ia_puente(text,jsonb)', 'execute') then
      grant execute on function public.ia_puente(text, jsonb) to anon;   -- propuestas/20261016140000 lo hace en la viva con el OK del owner
    end if;
    if not has_function_privilege('authenticated', 'public.ia_conexion_autoriza(text)', 'execute') then
      grant execute on function public.ia_conexion_autoriza(text) to authenticated;   -- ídem
    end if;
    -- herramienta de prueba: dueño postgres, como las puertas privado.mcp_<x> de P2; devuelve quién es la persona dentro
    grant create on schema privado to ia_puente_rol;
    create function privado.mcp_zz_quien() returns jsonb language plpgsql security definer set search_path = '' as $q$
    declare p jsonb;
    begin
      p := privado.mcp_puerta('zz_quien', '{}'::jsonb);
      if not coalesce((p ->> 'ok')::boolean, false) then return jsonb_build_object('error', p ->> 'resultado'); end if;
      perform privado.mcp_cierra((p ->> 'llamada')::bigint, 1, 'ok');
      return jsonb_build_object('uid', public.uid_sesion(), 'super', public.es_super_admin());
    end $q$;
    alter function privado.mcp_zz_quien() owner to postgres;
    revoke all on function privado.mcp_zz_quien() from public, anon, authenticated, service_role;
    grant execute on function privado.mcp_zz_quien() to ia_puente_rol;
    create or replace function privado.ia_despacha(p_herramienta text, p_args jsonb) returns jsonb language plpgsql
      security definer set search_path = '' as $q$
    begin
      case p_herramienta
        when 'zz_quien' then return privado.mcp_zz_quien();
        when 'zz_falla' then perform privado.mcp_puerta('zz_falla', '{}'::jsonb); raise exception 'zz: la herramienta lanza';
        else return jsonb_build_object('error', 'herramienta_desconocida');
      end case;
    end $q$;
    alter function privado.ia_despacha(text, jsonb) owner to ia_puente_rol;
    revoke create on schema privado from ia_puente_rol;
    r := r || pg_temp.l(true, 'P montaje: A super admin con permiso de IA, B agente sin permiso, cliente Claude activo, tope 3');
  exception when others then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'P montaje: ' || sqlstate || ' ' || left(sqlerrm, 300)));
  end;

  -- ============================================================ A. default-deny
  select count(*) into n from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname like 'ia\_%' and c.relkind = 'r'
     and (has_table_privilege('anon', c.oid, 'select,insert,update,delete') or has_table_privilege('authenticated', c.oid, 'select,insert,update,delete'));
  r := r || pg_temp.l(n = 0, 'A1 ninguna tabla ia_* abierta a anon ni a authenticated (' || n || ')');
  select count(*) into n from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname like 'ia\_%' and c.relkind = 'r' and not c.relrowsecurity;
  r := r || pg_temp.l(n = 0, 'A2 las 8 tablas ia_* con RLS (' || n || ' sin)');
  select string_agg(p.proname || ':' || x.g, ',' order by p.proname, x.g) into v
    from pg_proc p cross join lateral (select coalesce(r.rolname, 'PUBLIC') g from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) e
                                        left join pg_roles r on r.oid = e.grantee where e.privilege_type = 'EXECUTE'
                                         and coalesce(r.rolname, 'PUBLIC') in ('PUBLIC', 'anon', 'authenticated', 'service_role')) x
   where p.proname in ('mcp_puerta', 'mcp_cierra', 'ia_despacha', 'ia_conexion_motivo', 'ia_token_nuevo', 'ia_revoca', 'ia_auth_usuario',
                       'ia_aleatorio', 'ia_purga', 'ia_conexion_autoriza', 'ia_conexion_revoca', 'ia_puente');
  r := r || pg_temp.l(v = 'ia_conexion_autoriza:authenticated,ia_conexion_revoca:authenticated,ia_puente:anon',
                      'A3 EXECUTE de anon/authenticated/service_role/PUBLIC solo en la entrada y las dos RPC de la persona (' || coalesce(v, '-') || ')');
  r := r || pg_temp.l(not has_schema_privilege('anon', 'privado', 'usage') and not has_schema_privilege('authenticated', 'privado', 'usage'),
                      'A4 anon y authenticated sin USAGE en privado: las mcp_* no se llaman por /rpc');

  -- ============================================================ B. pide
  select count(*) into n from public.ia_peticiones;
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red || '/', 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  r := r || pg_temp.l(j ->> 'error' = 'invalid_redirect_uri', 'B1 redirect con un byte de más → ' || j::text);
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', ver, 'code_challenge_method', 'plain', 'recurso', rec));
  r := r || pg_temp.l(j ->> 'error' = 'invalid_request', 'B2 PKCE plain → ' || j::text);
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', 'https://otro.example/mcp'));
  r := r || pg_temp.l(j ->> 'error' = 'invalid_target', 'B3 recurso ajeno → ' || j::text);
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', gen_random_uuid(), 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  r := r || pg_temp.l(j ->> 'error' = 'invalid_client', 'B4 cliente que no existe → ' || j::text);
  select count(*) into n2 from public.ia_peticiones;
  r := r || pg_temp.l(n2 = n, 'B5 las peticiones malas no escriben nada (' || n || ' → ' || n2 || ')');
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec, 'estado', 'xyz'));
  pet := j ->> 'peticion';
  r := r || pg_temp.l(length(pet) = 43, 'B6 la buena devuelve una petición de 256 bits (' || coalesce(length(pet), 0) || ' caracteres)');

  -- ============================================================ C. autoriza (con la sesión fresca de la persona)
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_autoriza(%L)::text', pet), 300);
  r := r || pg_temp.l(v::jsonb ->> 'error' = 'contrasena_no_reciente', 'C1 contraseña puesta hace 5 min → ' || v);
  v := pg_temp.sesion(b.uid, b.em, format('select public.ia_conexion_autoriza(%L)::text', pet));
  r := r || pg_temp.l(v::jsonb ->> 'error' = 'sin_permiso', 'C2 B sin permiso de IA → ' || v);
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_autoriza(%L)::text', 'inventada'));
  r := r || pg_temp.l(v::jsonb ->> 'error' = 'peticion_invalida', 'C3 petición inventada → ' || v);
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_autoriza(%L)::text', pet));
  cod := v::jsonb ->> 'code';
  r := r || pg_temp.l(length(cod) = 43 and v::jsonb ->> 'state' = 'xyz' and v::jsonb ->> 'redirect_uri' = red, 'C4 A, contraseña de hace 5 s → código, state y su redirect');
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_autoriza(%L)::text', pet));
  r := r || pg_temp.l(v::jsonb ->> 'error' = 'peticion_invalida', 'C5 la misma petición otra vez → ' || v);

  -- ============================================================ D. canjea
  j := pg_temp.edge('canjea', jsonb_build_object('codigo', cod, 'code_verifier', repeat('w', 50), 'cliente_id', cli, 'redirect_uri', red, 'recurso', rec));
  r := r || pg_temp.l(j ->> 'error' = 'invalid_grant', 'D1 verificador PKCE malo → ' || j::text);
  j := pg_temp.edge('canjea', jsonb_build_object('codigo', cod, 'code_verifier', ver, 'cliente_id', cli, 'redirect_uri', red, 'recurso', rec));
  acc := j ->> 'access_token'; ref := j ->> 'refresh_token';
  r := r || pg_temp.l(length(acc) = 43 and length(ref) = 43 and (j ->> 'expires_in')::int between 3500 and 3600, 'D2 verificador bueno → access + refresh (expira en ' || coalesce(j ->> 'expires_in', '-') || ' s)');
  select count(*) into n from public.ia_tokens where hash = sha256(convert_to(acc, 'UTF8'));
  select count(*) into n2 from public.ia_tokens t where t.code_challenge is null and t.tipo = 'acceso' and t.hash::text like '%' || acc || '%';
  r := r || pg_temp.l(n = 1 and n2 = 0, 'D3 la base guarda el hash del token, nunca el token');
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'zz_quien'));
  r := r || pg_temp.l((j ->> 'uid')::uuid = a.uid, 'D4 antes del reuso el access llama (' || j::text || ')');
  j := pg_temp.edge('canjea', jsonb_build_object('codigo', cod, 'code_verifier', ver, 'cliente_id', cli, 'redirect_uri', red, 'recurso', rec));
  select id into con from public.ia_conexiones where usuario_id = a.uid order by creada_en desc limit 1;
  select count(*) into n from public.ia_conexiones where id = con and revocada_motivo = 'reuso_codigo';
  r := r || pg_temp.l(j ->> 'error' = 'invalid_grant' and n = 1, 'D5 el mismo código otra vez → invalid_grant y la conexión revocada por reuso');
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'zz_quien'));
  r := r || pg_temp.l(j ->> 'error' = 'invalid_token', 'D6 y lo que salió de ese código ya no llama → ' || j::text);

  -- conexión nueva para el resto
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_autoriza(%L)::text', j ->> 'peticion'));
  j := pg_temp.edge('canjea', jsonb_build_object('codigo', v::jsonb ->> 'code', 'code_verifier', ver, 'cliente_id', cli, 'redirect_uri', red, 'recurso', rec));
  acc := j ->> 'access_token'; ref := j ->> 'refresh_token';
  select id into con from public.ia_conexiones where usuario_id = a.uid and revocada_en is null;

  -- ============================================================ E. llama: la persona dentro de la herramienta
  select count(*) into n from public.ia_llamadas;
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'zz_quien'));
  r := r || pg_temp.l((j ->> 'uid')::uuid = a.uid and (j ->> 'super')::boolean, 'E1 dentro de la herramienta uid_sesion() = A y es_super_admin() = true (' || j::text || ')');
  r := r || pg_temp.l(auth.uid() = a.uid and auth.email() = a.em, 'E2 auth.uid() y auth.email() resuelven a la persona del token (' || coalesce(auth.uid()::text, '-') || ' ' || coalesce(auth.email(), '-') || ')');
  perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true); perform set_config('request.jwt.claim.email', '', true);
  select count(*) into n2 from public.ia_llamadas where conexion_id = con and resultado = 'ok' and filas = 1 and ms is not null and usuario_id = a.uid;
  r := r || pg_temp.l(n2 >= 1, 'E3 queda la fila en ia_llamadas con usuario, filas y ms');
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'ZZ_QUIEN'));
  r := r || pg_temp.l(j ->> 'error' = 'herramienta_desconocida', 'E4 herramienta fuera de la lista (mayúsculas) → ' || j::text);
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', 'https://otro.example/mcp', 'herramienta', 'zz_quien'));
  r := r || pg_temp.l(j ->> 'error' = 'invalid_token', 'E5 access presentado a otro recurso (RFC 8707) → ' || j::text);
  v := pg_temp.sesion(a.uid, a.em, 'select privado.mcp_zz_quien()::text');
  r := r || pg_temp.l(v like 'ERR42501%', 'E6 la herramienta por /rpc con una sesión normal → 42501 (' || left(v, 80) || ')');

  -- ============================================================ F. tope del día (3; ya van 2 ok contando la de D4)
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'zz_quien'));
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'zz_quien'));
  select count(*) into n from public.ia_llamadas where usuario_id = a.uid and resultado = 'tope';
  r := r || pg_temp.l(j ->> 'error' = 'tope' and n = 1, 'F1 la llamada de más → «tope» y queda su fila (' || j::text || ')');
  update public.ia_ajustes set tope_dia = 100 where id;
  -- F2 una herramienta que lanza: su fila y su cuenta se deshacen con ella; el puente las apunta igual (revisor, 16-oct)
  select x.n into n2 from public.ia_uso x where x.usuario_id = a.uid and x.dia = (now() at time zone 'Asia/Makassar')::date;
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'zz_falla'));
  select count(*) into n from public.ia_llamadas where usuario_id = a.uid and herramienta = 'zz_falla' and resultado = 'error';
  r := r || pg_temp.l(j ->> 'error' = 'server_error' and n = 1
                      and (select x.n from public.ia_uso x where x.usuario_id = a.uid and x.dia = (now() at time zone 'Asia/Makassar')::date) = n2 + 1,
                      'F2 la herramienta lanza → server_error, una fila «error» y cuenta en el tope (' || j::text || ')');

  -- ============================================================ G. refresca
  j := pg_temp.edge('refresca', jsonb_build_object('refresh_token', ref, 'cliente_id', cli));
  ref2 := j ->> 'refresh_token'; acc2 := j ->> 'access_token';
  r := r || pg_temp.l(length(ref2) = 43 and ref2 <> ref, 'G1 refresca R1 → R2 nuevo');
  -- reintento tras un timeout (≤10 s; now() no avanza en la transacción) con el hijo SIN usar: par nuevo y el hijo muere
  j := pg_temp.edge('refresca', jsonb_build_object('refresh_token', ref, 'cliente_id', cli));
  ref3 := j ->> 'refresh_token'; acc3 := j ->> 'access_token';
  r := r || pg_temp.l(length(ref3) = 43 and ref3 <> ref2
                      and exists (select 1 from public.ia_tokens x where x.hash = sha256(convert_to(ref2, 'UTF8'))
                                     and x.usado_en is not null and x.caduca_en <= now()),
                      'G5 R1 otra vez en ≤10 s con R2 sin usar → R3 nuevo y R2 muerto (' || coalesce(j ->> 'error', 'par') || ')');
  -- el hijo matado vuelve a aparecer: es reúso, se revoca todo (nunca dos cadenas vivas: Seguridad, 16-oct)
  j := pg_temp.edge('refresca', jsonb_build_object('refresh_token', ref2, 'cliente_id', cli));
  select count(*) into n from public.ia_conexiones where id = con and revocada_motivo = 'reuso_refresco';
  r := r || pg_temp.l(j ->> 'error' = 'invalid_grant' and n = 1, 'G6 R2 (matado por el reintento) aparece → invalid_grant y conexión revocada');
  j := pg_temp.edge('refresca', jsonb_build_object('refresh_token', ref3, 'cliente_id', cli));
  r := r || pg_temp.l(j ->> 'error' = 'invalid_grant', 'G7 y R3 ya no refresca → ' || j::text);
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc3, 'recurso', rec, 'herramienta', 'zz_quien'));
  r := r || pg_temp.l(j ->> 'error' = 'invalid_token', 'G7b ni el access de R3 llama → ' || j::text);

  -- conexión nueva: reintento en ≤10 s cuando el hijo YA se usó (lo robado siguió la cadena) → reúso
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_autoriza(%L)::text', j ->> 'peticion'));
  j := pg_temp.edge('canjea', jsonb_build_object('codigo', v::jsonb ->> 'code', 'code_verifier', ver, 'cliente_id', cli, 'redirect_uri', red, 'recurso', rec));
  ref := j ->> 'refresh_token';
  select id into con from public.ia_conexiones where usuario_id = a.uid and revocada_en is null;
  j := pg_temp.edge('refresca', jsonb_build_object('refresh_token', ref, 'cliente_id', cli));
  ref2 := j ->> 'refresh_token';
  j := pg_temp.edge('refresca', jsonb_build_object('refresh_token', ref2, 'cliente_id', cli));
  j := pg_temp.edge('refresca', jsonb_build_object('refresh_token', ref, 'cliente_id', cli));
  select count(*) into n from public.ia_conexiones where id = con and revocada_motivo = 'reuso_refresco';
  r := r || pg_temp.l(j ->> 'error' = 'invalid_grant' and n = 1, 'G8 R1 en ≤10 s con R2 ya usado → invalid_grant y conexión revocada');

  -- conexión nueva para G2-G4
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_autoriza(%L)::text', j ->> 'peticion'));
  j := pg_temp.edge('canjea', jsonb_build_object('codigo', v::jsonb ->> 'code', 'code_verifier', ver, 'cliente_id', cli, 'redirect_uri', red, 'recurso', rec));
  ref := j ->> 'refresh_token';
  select id into con from public.ia_conexiones where usuario_id = a.uid and revocada_en is null;
  j := pg_temp.edge('refresca', jsonb_build_object('refresh_token', ref, 'cliente_id', cli));
  ref2 := j ->> 'refresh_token'; acc2 := j ->> 'access_token';
  update public.ia_tokens set usado_en = now() - interval '20 seconds' where hash = sha256(convert_to(ref, 'UTF8'));
  j := pg_temp.edge('refresca', jsonb_build_object('refresh_token', ref, 'cliente_id', cli));
  select count(*) into n from public.ia_conexiones where id = con and revocada_motivo = 'reuso_refresco';
  r := r || pg_temp.l(j ->> 'error' = 'invalid_grant' and n = 1, 'G2 R1 otra vez pasados 10 s → invalid_grant y conexión revocada');
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc2, 'recurso', rec, 'herramienta', 'zz_quien'));
  r := r || pg_temp.l(j ->> 'error' = 'invalid_token', 'G3 el access de R2 ya no llama → ' || j::text);
  j := pg_temp.edge('refresca', jsonb_build_object('refresh_token', ref2, 'cliente_id', cli));
  r := r || pg_temp.l(j ->> 'error' = 'invalid_grant', 'G4 y R2 tampoco refresca → ' || j::text);

  -- ============================================================ H. revocar (conexión nueva)
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_autoriza(%L)::text', j ->> 'peticion'));
  j := pg_temp.edge('canjea', jsonb_build_object('codigo', v::jsonb ->> 'code', 'code_verifier', ver, 'cliente_id', cli, 'redirect_uri', red, 'recurso', rec));
  acc := j ->> 'access_token';
  select id into con from public.ia_conexiones where usuario_id = a.uid and revocada_en is null;
  v := pg_temp.sesion(b.uid, b.em, format('select public.ia_conexion_revoca(%L)::text', con));
  r := r || pg_temp.l(v like 'ERR42501%', 'H1 B revoca la conexión de A → 42501 (' || left(v, 60) || ')');
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_revoca(%L)::text', con));
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'zz_quien'));
  -- revocar caduca sus tokens en el acto: la llamada cae en «token caducado» (sin motivo) antes de mirar la conexión
  r := r || pg_temp.l(j ->> 'error' = 'invalid_token'
                      and exists (select 1 from public.ia_conexiones x where x.id = con and x.revocada_motivo = 'persona'),
                      'H2 A la revoca desde «apps conectadas» → el access muere en el acto y queda revocada por la persona (' || j::text || ')');

  -- ============================================================ I. caducidad, contraseña, permiso, apagado (una conexión cada vez)
  -- I1 día 8
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_autoriza(%L)::text', j ->> 'peticion'));
  j := pg_temp.edge('canjea', jsonb_build_object('codigo', v::jsonb ->> 'code', 'code_verifier', ver, 'cliente_id', cli, 'redirect_uri', red, 'recurso', rec));
  acc := j ->> 'access_token';
  select id into con from public.ia_conexiones where usuario_id = a.uid and revocada_en is null;
  select count(*) into n from public.ia_conexiones where id = con and expira_en between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour';
  r := r || pg_temp.l(n = 1, 'I0 la conexión nace con 7 días');
  update public.ia_conexiones set expira_en = now() - interval '1 second' where id = con;
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'zz_quien'));
  r := r || pg_temp.l(j ->> 'error' = 'invalid_token' and j ->> 'motivo' = 'caducada', 'I1 día 8 → ' || j::text);
  -- I2 contraseña cambiada
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_autoriza(%L)::text', j ->> 'peticion'));
  j := pg_temp.edge('canjea', jsonb_build_object('codigo', v::jsonb ->> 'code', 'code_verifier', ver, 'cliente_id', cli, 'redirect_uri', red, 'recurso', rec));
  acc := j ->> 'access_token';
  update auth.users set encrypted_password = '$2a$10$zzmcpotra' where id = a.uid;
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'zz_quien'));
  select count(*) into n from public.ia_conexiones where usuario_id = a.uid and revocada_motivo = 'contrasena';
  r := r || pg_temp.l(j ->> 'motivo' = 'contrasena' and n = 1, 'I2 contraseña cambiada → no llama y la conexión queda revocada (' || j::text || ')');
  -- I3 permiso quitado
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_autoriza(%L)::text', j ->> 'peticion'));
  j := pg_temp.edge('canjea', jsonb_build_object('codigo', v::jsonb ->> 'code', 'code_verifier', ver, 'cliente_id', cli, 'redirect_uri', red, 'recurso', rec));
  acc := j ->> 'access_token';
  delete from public.ia_permisos where usuario_id = a.uid;
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'zz_quien'));
  r := r || pg_temp.l(j ->> 'motivo' = 'permiso', 'I3 permiso de IA quitado → ' || j::text);
  insert into public.ia_permisos (usuario_id) values (a.uid);
  -- I4 apagado
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_autoriza(%L)::text', j ->> 'peticion'));
  j := pg_temp.edge('canjea', jsonb_build_object('codigo', v::jsonb ->> 'code', 'code_verifier', ver, 'cliente_id', cli, 'redirect_uri', red, 'recurso', rec));
  acc := j ->> 'access_token';
  update public.ia_ajustes set encendido = false where id;
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'zz_quien'));
  r := r || pg_temp.l(j ->> 'motivo' = 'apagado', 'I4 apagado en Ajustes → ' || j::text);
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec));
  r := r || pg_temp.l(j ->> 'error' = 'temporarily_unavailable', 'I5 apagado: no se abren peticiones nuevas → ' || j::text);
  update public.ia_ajustes set encendido = true where id;

  -- ============================================================ J. rutas de abuso
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'zz_quien'), 'GET');
  r := r || pg_temp.l(j ->> 'ERR' = '42501', 'J1 GET (transacción de solo lectura) → rechazado (' || j::text || ')');
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'zz_quien'), 'POST', '{"prefer":"return=representation, TX=rollback"}');
  r := r || pg_temp.l(j ->> 'ERR' = '42501', 'J2 Prefer tx=rollback → rechazado (' || j::text || ')');
  select (select count(*) from public.ia_tokens) + (select count(*) from public.ia_conexiones) + (select count(*) from public.ia_llamadas)
         + (select count(*) from public.ia_peticiones) into n;
  for i in 1..100 loop
    perform pg_temp.edge('llama', jsonb_build_object('access_token', pg_temp.b64(extensions.gen_random_bytes(32)), 'recurso', rec, 'herramienta', 'zz_quien'));
    perform pg_temp.edge('canjea', jsonb_build_object('codigo', pg_temp.b64(extensions.gen_random_bytes(32)), 'code_verifier', ver, 'cliente_id', cli, 'redirect_uri', red, 'recurso', rec));
    perform pg_temp.edge('refresca', jsonb_build_object('refresh_token', pg_temp.b64(extensions.gen_random_bytes(32)), 'cliente_id', cli));
  end loop;
  select (select count(*) from public.ia_tokens) + (select count(*) from public.ia_conexiones) + (select count(*) from public.ia_llamadas)
         + (select count(*) from public.ia_peticiones) into n2;
  r := r || pg_temp.l(n = n2, 'J3 300 tokens y códigos inventados → 0 escrituras (' || n || ' → ' || n2 || ')');
  j := pg_temp.edge('llama', jsonb_build_object('access_token', acc, 'recurso', rec, 'herramienta', 'zz_quien', 'relleno', repeat('x', 5000)));
  r := r || pg_temp.l(j ->> 'error' = 'invalid_request', 'J4 cuerpo de más de 4 KB → ' || j::text);

  -- ============================================================ K deniega («No permitir» en la página de conexión)
  update public.ia_ajustes set encendido = true where id;
  insert into public.ia_permisos (usuario_id) values (a.uid) on conflict do nothing;   -- I3 se lo quitó: K4 debe caer por la petición
  j := pg_temp.edge('pide', jsonb_build_object('cliente_id', cli, 'redirect_uri', red, 'code_challenge', cha, 'code_challenge_method', 'S256', 'recurso', rec, 'estado', 'k-st'));
  pet := j ->> 'peticion';
  j := pg_temp.edge('deniega', jsonb_build_object('peticion', pg_temp.b64(extensions.gen_random_bytes(32))));
  r := r || pg_temp.l(j ->> 'error' = 'peticion_invalida', 'K1 deniega con una petición inventada → ' || j::text);
  j := pg_temp.edge('deniega', jsonb_build_object('peticion', pet));
  r := r || pg_temp.l(j ->> 'redirect_uri' = red and j ->> 'state' = 'k-st', 'K2 deniega la buena → su dirección de vuelta y su state (' || j::text || ')');
  j := pg_temp.edge('deniega', jsonb_build_object('peticion', pet));
  r := r || pg_temp.l(j ->> 'error' = 'peticion_invalida', 'K3 la misma otra vez → ' || j::text);
  v := pg_temp.sesion(a.uid, a.em, format('select public.ia_conexion_autoriza(%L)::text', pet));
  r := r || pg_temp.l(v like '%peticion_invalida%', 'K4 tras denegar, ya no sirve para conectar → ' || v);

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
