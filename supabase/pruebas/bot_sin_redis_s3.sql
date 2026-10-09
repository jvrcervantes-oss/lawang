-- Prueba de la migracion 20261010120000_bot_sin_redis_s3_config (S3 del encargo «bot de Lawang sin Redis», 9-oct-2026).
-- Se ejecuta con el MCP (execute_sql) o psql como postgres, DESPUES de aplicar la migracion. NO deja rastro: todo ocurre dentro de un DO que
-- acaba SIEMPRE en una excepcion (rollback). «PRUEBA OK: ...» si todo va bien; «PRUEBA FALLA: ...» y cual si no.
-- Se llama con el ROL REAL de la edge (set local role service_role) y con bot_lawang para comprobar que NO puede. Reloj congelado dentro de la
-- transaccion: now() no avanza, asi que el token (updatedAt) cambia respecto al estado de antes de la prueba, no entre dos guardados de la prueba.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); el unico update es sobre la fila unica de bot_config, deshecho por el rollback.
do $t$
declare
  v_ok text := '';
  j jsonb; t0 bigint; t1 bigint; n int; f text; rl text; v_orig record;
  v_super uuid; v_sin uuid; e text;
  publicas constant text[] := array['crm_bot_config_leer(uuid)','crm_bot_config_guardar(uuid,text,text,integer,bigint,text)','crm_bot_config_volver(uuid,bigint,text)'];
  internas constant text[] := array['_crm_bot_config_autoriza(uuid)','_crm_bot_config_json()','_crm_bot_config_limpia(text)'];
begin
  -- ═══ A. cierre ═══
  foreach f in array publicas || internas loop
    if not exists (select 1 from pg_proc p where p.oid = ('public.' || f)::regprocedure and p.proconfig::text like '%search_path=%') then
      raise exception 'PRUEBA FALLA: % sin search_path fijo', f; end if;
    if (select proacl from pg_proc where oid = ('public.' || f)::regprocedure) is null
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = ('public.' || f)::regprocedure and a.grantee = 0) then
      raise exception 'PRUEBA FALLA: % con proacl nulo o con PUBLIC', f; end if;
    foreach rl in array array['anon','authenticated','bot_lawang'] loop
      if has_function_privilege(rl, ('public.' || f)::regprocedure, 'execute') then raise exception 'PRUEBA FALLA: % ejecuta %', rl, f; end if;
    end loop;
  end loop;
  foreach f in array publicas loop
    if not has_function_privilege('service_role', ('public.' || f)::regprocedure, 'execute') then raise exception 'PRUEBA FALLA: service_role no ejecuta %', f; end if;
    if not (select prosecdef from pg_proc where oid = ('public.' || f)::regprocedure) then raise exception 'PRUEBA FALLA: % no es SECURITY DEFINER', f; end if;
  end loop;
  foreach f in array internas loop
    if has_function_privilege('service_role', ('public.' || f)::regprocedure, 'execute') then raise exception 'PRUEBA FALLA: service_role ejecuta la interna %', f; end if;
  end loop;
  if has_table_privilege('bot_lawang', 'public.bot_config', 'select,insert,update,delete,truncate')
     or has_table_privilege('service_role', 'public.bot_config', 'select,insert,update,delete,truncate') then
    raise exception 'PRUEBA FALLA: alguien tiene privilegios directos sobre bot_config'; end if;
  v_ok := v_ok || '6 funciones: search_path fijo, sin PUBLIC, solo service_role ejecuta las 3 publicas, bot_lawang/anon/authenticated nada, bot_config sin privilegios directos; ';

  -- ═══ B. permiso ═══
  select user_id into v_super from public.usuarios where rol = 'super_admin' and activo and ambito = 'global' and coalesce(cardinality(empresas),0) = 0 limit 1;
  select user_id into v_sin from public.usuarios where activo and rol <> 'super_admin' and not ('bot_configurar' = any (coalesce(herramientas,'{}'))) limit 1;
  if v_super is null then raise exception 'PRUEBA FALLA: no hay super_admin global para probar'; end if;
  select * into v_orig from public.bot_config;

  set local role service_role;
  begin perform public.crm_bot_config_leer(v_sin); e := 'sin error'; exception when others then e := sqlstate; end;
  if v_sin is not null and e <> '42501' then raise exception 'PRUEBA FALLA: usuario sin casilla debia dar 42501 y dio %', e; end if;
  begin perform public.crm_bot_config_leer(gen_random_uuid()); e := 'sin error'; exception when others then e := sqlstate; end;
  if e <> '42501' then raise exception 'PRUEBA FALLA: uuid desconocido debia dar 42501 y dio %', e; end if;
  begin perform public.crm_bot_config_leer(null); e := 'sin error'; exception when others then e := sqlstate; end;
  if e <> '42501' then raise exception 'PRUEBA FALLA: uuid nulo debia dar 42501 y dio %', e; end if;
  begin perform public.crm_bot_config_guardar(v_sin, 'x', 'y', 0, 1, 'a@x'); e := 'sin error'; exception when others then e := sqlstate; end;
  if v_sin is not null and e <> '42501' then raise exception 'PRUEBA FALLA: guardar sin casilla (%)', e; end if;
  begin perform public.crm_bot_config_volver(gen_random_uuid(), 1, 'a@x'); e := 'sin error'; exception when others then e := sqlstate; end;
  if e <> '42501' then raise exception 'PRUEBA FALLA: volver sin permiso (%)', e; end if;
  reset role;
  v_ok := v_ok || 'sin permiso = 42501 en las tres (usuario sin casilla, uuid desconocido, nulo); ';

  -- bot_lawang no puede ejecutarlas ni escribir la tabla
  set local role bot_lawang;
  begin perform public.crm_bot_config_guardar(v_super, 'hack', '', 0, 1, 'bot'); e := 'sin error'; exception when others then e := sqlstate; end;
  reset role;
  if e <> '42501' then raise exception 'PRUEBA FALLA: bot_lawang pudo llamar a guardar (%)', e; end if;
  set local role bot_lawang;
  begin update public.bot_config set extra = 'hack'; e := 'sin error'; exception when others then e := sqlstate; end;
  reset role;
  if e <> '42501' then raise exception 'PRUEBA FALLA: bot_lawang pudo escribir bot_config (%)', e; end if;
  v_ok := v_ok || 'bot_lawang no puede escribir bot_config ni llamar a guardar; ';

  -- ═══ C. leer / guardar / concurrencia / log ═══
  set local role service_role; j := public.crm_bot_config_leer(v_super); reset role;
  t0 := (j->'config'->>'updatedAt')::bigint;
  if t0 is null or j->'config'->>'extra' is distinct from v_orig.extra or (j->'config'->>'pausaHoras')::int <> v_orig.pausa_horas then raise exception 'PRUEBA FALLA: leer %', j; end if;
  n := (select count(*) from public.bot_config_log);

  set local role service_role; j := public.crm_bot_config_guardar(v_super, E'Hola <<<mundo>>>\r\nlinea', 'Bienvenida', 24, t0, 'ana@x'); reset role;
  if not coalesce((j->>'ok')::boolean, false) then raise exception 'PRUEBA FALLA: guardar con el token vigente %', j; end if;
  if j->'config'->>'extra' <> E'Hola ‹‹‹mundo›››\nlinea' then raise exception 'PRUEBA FALLA: no neutralizo <<< >>> / CRLF: %', j->'config'->>'extra'; end if;
  if j->'config'->>'updatedBy' <> 'ana@x' or (j->'config'->>'pausaHoras')::int <> 24 then raise exception 'PRUEBA FALLA: respuesta %', j; end if;
  t1 := (j->'config'->>'updatedAt')::bigint;
  if t1 = t0 then raise exception 'PRUEBA FALLA: el token no cambio tras guardar'; end if;
  if (select count(*) from public.bot_config_log) <> n + 1 then raise exception 'PRUEBA FALLA: no dejo UNA fila de log'; end if;
  if (select (prev->>'extra') from public.bot_config_log order by id desc limit 1) is distinct from v_orig.extra
     or (select usuario from public.bot_config_log order by id desc limit 1) <> 'ana@x' then raise exception 'PRUEBA FALLA: el log no guarda el valor anterior ni el autor'; end if;
  v_ok := v_ok || 'guardar neutraliza <<< >>>, sube la version y deja UNA fila de log con el prev en la misma transaccion; ';

  -- segundo guardado con el token VIEJO: conflicto, no escribe, devuelve el estado actual
  set local role service_role; j := public.crm_bot_config_guardar(v_super, 'pisado', 'x', 1, t0, 'bea@x'); reset role;
  if not coalesce((j->>'conflicto')::boolean, false) or j->'config'->>'extra' <> E'Hola ‹‹‹mundo›››\nlinea' then raise exception 'PRUEBA FALLA: debia dar conflicto con el estado actual %', j; end if;
  if (select count(*) from public.bot_config_log) <> n + 1 then raise exception 'PRUEBA FALLA: el conflicto escribio log'; end if;
  set local role service_role; j := public.crm_bot_config_volver(v_super, t0, 'bea@x'); reset role;
  if not coalesce((j->>'conflicto')::boolean, false) then raise exception 'PRUEBA FALLA: volver con token viejo debia dar conflicto %', j; end if;
  v_ok := v_ok || 'token viejo = conflicto (guardar y volver), sin escribir; ';

  -- limites
  set local role service_role;
  begin perform public.crm_bot_config_guardar(v_super, repeat('a', 2001), '', 0, t1, 'a@x'); e := 'sin error'; exception when others then e := sqlstate; end;
  if e <> 'PT400' then reset role; raise exception 'PRUEBA FALLA: extra de 2001 (%)', e; end if;
  begin perform public.crm_bot_config_guardar(v_super, '', repeat('a', 501), 0, t1, 'a@x'); e := 'sin error'; exception when others then e := sqlstate; end;
  if e <> 'PT400' then reset role; raise exception 'PRUEBA FALLA: bienvenida de 501 (%)', e; end if;
  begin perform public.crm_bot_config_guardar(v_super, '', '', 721, t1, 'a@x'); e := 'sin error'; exception when others then e := sqlstate; end;
  if e <> 'PT400' then reset role; raise exception 'PRUEBA FALLA: 721 h (%)', e; end if;
  begin perform public.crm_bot_config_guardar(v_super, '', '', -1, t1, 'a@x'); e := 'sin error'; exception when others then e := sqlstate; end;
  if e <> 'PT400' then reset role; raise exception 'PRUEBA FALLA: -1 h (%)', e; end if;
  begin perform public.crm_bot_config_guardar(v_super, '', '', 0, null, 'a@x'); e := 'sin error'; exception when others then e := sqlstate; end;
  if e <> 'PT400' then reset role; raise exception 'PRUEBA FALLA: sin token (%)', e; end if;
  reset role;
  v_ok := v_ok || 'limites 2000/500/0-720 y token obligatorio = PT400; ';

  -- ═══ D. volver ═══
  set local role service_role; j := public.crm_bot_config_volver(v_super, t1, 'cris@x'); reset role;
  if not coalesce((j->>'ok')::boolean, false) or j->'config'->>'extra' is distinct from v_orig.extra or (j->'config'->>'pausaHoras')::int <> v_orig.pausa_horas
     or j->'config'->>'updatedBy' <> 'cris@x' then raise exception 'PRUEBA FALLA: volver no restauro lo anterior %', j; end if;
  if (select count(*) from public.bot_config_log) <> n + 2 then raise exception 'PRUEBA FALLA: volver no dejo su fila de log'; end if;
  if jsonb_array_length(j->'log') <> least(n + 2, 50) then raise exception 'PRUEBA FALLA: el log de la respuesta %', j->'log'; end if;
  v_ok := v_ok || 'volver restaura el valor anterior como una edicion mas (version y log nuevos); ';

  -- ═══ E. el bot lo ve por bot_turno_estado ═══
  set local role bot_lawang; j := public.bot_mensaje_recibir('99977700301', 'wamid.s3.1', 'Prueba', jsonb_build_object('texto', 'hola')); reset role;
  t1 := (select floor(extract(epoch from actualizado_en)*1000)::bigint from public.bot_config);
  set local role service_role;
  j := public.crm_bot_config_guardar(v_super, 'Ofrece la oferta', 'Hola', 6, t1, 'ana@x');
  reset role;
  if not coalesce((j->>'ok')::boolean, false) then raise exception 'PRUEBA FALLA: guardar para el bot %', j; end if;
  set local role bot_lawang; j := public.bot_turno_estado('99977700301', false); reset role;
  if j->'config'->>'extra' is distinct from 'Ofrece la oferta' then raise exception 'PRUEBA FALLA: bot_turno_estado no devuelve la config nueva %', j->'config'; end if;
  v_ok := v_ok || 'el bot lee lo guardado dentro de bot_turno_estado; ';

  raise exception 'PRUEBA OK: %', v_ok;
end $t$;
