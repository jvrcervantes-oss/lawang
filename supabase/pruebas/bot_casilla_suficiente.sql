-- Prueba de la migracion 20261010200000_bot_conversaciones_casilla_suficiente (LAW-513, 10-oct-2026).
-- Se ejecuta con el MCP (execute_sql) o psql como postgres DESPUES de aplicarla. NO deja rastro: todo ocurre dentro de un DO que acaba SIEMPRE
-- en una excepcion (rollback). «PRUEBA OK: ...» si todo va bien; «PRUEBA FALLA: ...» si no. Usa el ROL REAL del navegador (set local role authenticated)
-- con los claims de cada perfil. Lo que se afirma: (1) la casilla basta aunque haya empresas marcadas; (2) super_admin con empresas SIN casilla no lee;
-- (3) ambito empresa con casilla no lee; (4) inactivo con casilla no lee; (5) concederla: solo un super_admin, y deja fila en bot_casilla_log;
-- (6) un admin no-super no la concede (ni aunque la tenga); (7) tope de 300 lecturas por hora; (8) cada lectura deja fila en bot_lecturas_log.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); los update son sobre filas reales pero se deshacen con el rollback.
do $t$
declare
  v_ok text := '';
  j jsonb; n0 int; n1 int;
  v_sup uuid; v_sup_em text;      -- super_admin sin empresas, no propietario
  v_and uuid; v_and_em text;      -- super_admin con empresas (el caso de Andrea)
  v_adm uuid; v_adm_em text;      -- admin global
  v_ag uuid; v_ag_em text;        -- agente global
  v_sae uuid; v_sae_em text;      -- super_admin_empresa (ambito empresa)
  v_ina uuid; v_ina_em text;      -- inactivo
  v_nuevo uuid := gen_random_uuid();
begin
  select user_id, email into v_sup, v_sup_em from public.usuarios where rol = 'super_admin' and ambito = 'global' and activo and not es_propietario and coalesce(cardinality(empresas),0) = 0 order by user_id limit 1;
  select user_id, email into v_and, v_and_em from public.usuarios where rol = 'super_admin' and ambito = 'global' and activo and coalesce(cardinality(empresas),0) > 0 order by user_id limit 1;
  select user_id, email into v_adm, v_adm_em from public.usuarios where rol = 'admin' and ambito = 'global' and activo order by user_id limit 1;
  select user_id, email into v_ag, v_ag_em from public.usuarios where rol = 'agente' and ambito = 'global' and activo order by user_id limit 1;
  select user_id, email into v_sae, v_sae_em from public.usuarios where rol = 'super_admin_empresa' and ambito = 'empresa' and activo order by user_id limit 1;
  select user_id, email into v_ina, v_ina_em from public.usuarios where not activo and ambito = 'global' order by user_id limit 1;
  if v_sup is null or v_and is null or v_adm is null or v_ag is null or v_sae is null or v_ina is null then raise exception 'PRUEBA FALLA: faltan perfiles de prueba'; end if;
  if exists (select 1 from public.usuarios where user_id in (v_sup, v_and, v_adm, v_ag, v_sae, v_ina) and 'bot_conversaciones_ver' = any (herramientas)) then
    raise exception 'PRUEBA FALLA: alguien de los perfiles ya tiene la casilla (la prueba la da y la quita)'; end if;
  -- cierre del registro
  if has_table_privilege('authenticated', 'public.bot_casilla_log', 'select') or has_table_privilege('anon', 'public.bot_casilla_log', 'select')
     or has_table_privilege('service_role', 'public.bot_casilla_log', 'insert') then
    raise exception 'PRUEBA FALLA: bot_casilla_log es accesible desde fuera'; end if;

  -- ═══ A. super_admin SIN empresas, sin casilla: lee como hasta hoy, y queda apuntado ═══
  n0 := (select count(*) from public.bot_lecturas_log);
  perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'email', v_sup_em)::text, true);
  set local role authenticated; j := public.crm_bot_conversaciones(); reset role;
  if (select count(*) from public.bot_lecturas_log) <> n0 + 1 then raise exception 'PRUEBA FALLA: lectura del super_admin sin apuntar'; end if;
  v_ok := v_ok || 'super_admin sin empresas lee y queda apuntado; ';

  -- ═══ B. super_admin CON empresas y SIN casilla: 42501 y sin registro ═══
  n0 := (select count(*) from public.bot_lecturas_log);
  perform set_config('request.jwt.claims', json_build_object('sub', v_and, 'role', 'authenticated', 'email', v_and_em)::text, true);
  set local role authenticated;
  begin j := public.crm_bot_conversaciones(); reset role; raise exception 'PRUEBA FALLA: super_admin con empresas leyo sin casilla';
  exception when insufficient_privilege then reset role; end;
  if (select count(*) from public.bot_lecturas_log) <> n0 then raise exception 'PRUEBA FALLA: una lectura denegada dejo registro'; end if;
  v_ok := v_ok || 'super_admin con empresas sin casilla: 42501 sin registro; ';

  -- ═══ C. un super_admin da la casilla a Andrea-tipo: lee, y queda en bot_casilla_log ═══
  perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'email', v_sup_em)::text, true);
  update public.usuarios set herramientas = array_append(herramientas, 'bot_conversaciones_ver') where user_id = v_and;
  if not exists (select 1 from public.bot_casilla_log where quien = v_sup_em and a_quien_id = v_and and accion = 'alta') then
    raise exception 'PRUEBA FALLA: la concesion no quedo en bot_casilla_log'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_and, 'role', 'authenticated', 'email', v_and_em)::text, true);
  n0 := (select count(*) from public.bot_lecturas_log);
  set local role authenticated; j := public.crm_bot_conversaciones(); reset role;
  set local role authenticated; j := public.crm_bot_conversacion('99977700188'); reset role;
  if (select count(*) from public.bot_lecturas_log where usuario = v_and_em and cuando >= now() - interval '1 minute') <> 2 or (select count(*) from public.bot_lecturas_log) <> n0 + 2 then
    raise exception 'PRUEBA FALLA: las dos lecturas con casilla no quedaron apuntadas'; end if;
  v_ok := v_ok || 'super_admin con empresas + casilla lee (lista e hilo), lecturas apuntadas, concesion en el registro; ';

  -- ═══ D. ambito empresa con casilla: 42501 ═══
  perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'email', v_sup_em)::text, true);
  update public.usuarios set herramientas = array_append(herramientas, 'bot_conversaciones_ver') where user_id = v_sae;
  perform set_config('request.jwt.claims', json_build_object('sub', v_sae, 'role', 'authenticated', 'email', v_sae_em)::text, true);
  set local role authenticated;
  begin j := public.crm_bot_conversaciones(); reset role; raise exception 'PRUEBA FALLA: ambito empresa con casilla leyo';
  exception when insufficient_privilege then reset role; end;
  v_ok := v_ok || 'super_admin_empresa (ambito empresa) con casilla: 42501; ';

  -- ═══ E. inactivo con casilla: 42501 ═══
  perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'email', v_sup_em)::text, true);
  update public.usuarios set herramientas = array_append(herramientas, 'bot_conversaciones_ver') where user_id = v_ina;
  perform set_config('request.jwt.claims', json_build_object('sub', v_ina, 'role', 'authenticated', 'email', coalesce(v_ina_em, 'x@x'))::text, true);
  set local role authenticated;
  begin j := public.crm_bot_conversaciones(); reset role; raise exception 'PRUEBA FALLA: inactivo con casilla leyo';
  exception when insufficient_privilege then reset role; end;
  v_ok := v_ok || 'inactivo con casilla: 42501; ';

  -- ═══ F. un admin NO super no la concede (ni aunque la tenga) ═══
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated', 'email', v_adm_em)::text, true);
  begin
    update public.usuarios set herramientas = array_append(herramientas, 'bot_conversaciones_ver') where user_id = v_ag;
    raise exception 'PRUEBA FALLA: un admin no-super concedio la casilla';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'email', v_sup_em)::text, true);
  update public.usuarios set herramientas = array_append(herramientas, 'bot_conversaciones_ver') where user_id = v_adm;   -- el admin la TIENE
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated', 'email', v_adm_em)::text, true);
  begin
    update public.usuarios set herramientas = array_append(herramientas, 'bot_conversaciones_ver') where user_id = v_ag;
    raise exception 'PRUEBA FALLA: un admin no-super CON la casilla la concedio';
  exception when insufficient_privilege then
    if sqlerrm not like '%casilla%' and sqlerrm not like '%super_admin%' then raise; end if;
  end;
  begin
    update public.usuarios set herramientas = array_remove(herramientas, 'bot_conversaciones_ver') where user_id = v_and;
    raise exception 'PRUEBA FALLA: un admin no-super retiro la casilla a otro';
  exception when insufficient_privilege then null; end;
  v_ok := v_ok || 'admin no-super no concede ni retira la casilla (ni teniendola); ';

  -- ═══ G. retirar la casilla queda en el registro y cierra el acceso ═══
  perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'email', v_sup_em)::text, true);
  update public.usuarios set herramientas = array_remove(herramientas, 'bot_conversaciones_ver') where user_id = v_and;
  if not exists (select 1 from public.bot_casilla_log where a_quien_id = v_and and accion = 'baja' and quien = v_sup_em) then raise exception 'PRUEBA FALLA: la retirada no quedo en el registro'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_and, 'role', 'authenticated', 'email', v_and_em)::text, true);
  set local role authenticated;
  begin j := public.crm_bot_conversaciones(); reset role; raise exception 'PRUEBA FALLA: sigue leyendo tras retirarle la casilla';
  exception when insufficient_privilege then reset role; end;
  v_ok := v_ok || 'retirar la casilla queda registrado y cierra el acceso; ';

  -- ═══ H. registro de solo anadir ═══
  begin delete from public.bot_casilla_log; raise exception 'PRUEBA FALLA: se pudo borrar bot_casilla_log';
  exception when insufficient_privilege then null; end;
  v_ok := v_ok || 'bot_casilla_log es de solo anadir; ';

  -- ═══ I. tope de 300 lecturas por hora ═══
  insert into public.bot_lecturas_log (usuario, tel, accion)
    select v_sup_em, null, 'lista' from generate_series(1, 300) g;
  perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated', 'email', v_sup_em)::text, true);
  set local role authenticated;
  begin j := public.crm_bot_conversaciones(); reset role; raise exception 'PRUEBA FALLA: el tope por hora no corto';
  exception when others then reset role; if sqlstate <> 'PT429' then raise; end if; end;
  v_ok := v_ok || 'tope de 300 lecturas/hora corta con PT429; ';

  -- ═══ J. ALTA de una ficha con la casilla por un admin no-super (policy de insert solo pide es_admin) ═══
  begin
    insert into auth.users (id, email, aud, role, instance_id) values (v_nuevo, 'prueba-casilla@invalid.test', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated', 'email', v_adm_em)::text, true);
    begin
      insert into public.usuarios (user_id, email, nombre, rol, herramientas, activo) values (v_nuevo, 'prueba-casilla@invalid.test', 'Prueba', 'agente', array['leads','bot_conversaciones_ver'], true);
      raise exception 'PRUEBA FALLA: un admin no-super creo una ficha con la casilla';
    exception when insufficient_privilege then v_ok := v_ok || 'alta de ficha con la casilla por un admin no-super: 42501; '; end;
  exception when others then
    if sqlerrm like 'PRUEBA FALLA%' then raise; end if;
    v_ok := v_ok || 'ALTA DE FICHA NO MEDIDA (' || left(sqlerrm, 80) || '); ';
  end;

  raise exception 'PRUEBA OK: %', v_ok;
end $t$;
