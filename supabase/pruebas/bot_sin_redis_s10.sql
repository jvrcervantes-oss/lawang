-- Prueba de la migracion 20261010140000_bot_sin_redis_s10_lectura_intranet (S10 del encargo «bot de Lawang sin Redis», 9-oct-2026).
-- Se ejecuta con el MCP (execute_sql) o psql como postgres, DESPUES de aplicar la migracion. NO deja rastro: todo ocurre dentro de un DO que
-- acaba SIEMPRE en una excepcion (rollback). Si todo va bien el mensaje empieza por «PRUEBA OK»; si algo falla, por «PRUEBA FALLA» y dice cual.
-- A diferencia de S1, aqui se llama con el ROL REAL del navegador (set local role authenticated / anon) y con la sesion de cada perfil
-- (request.jwt.claims). Lo que se afirma: (1) quien no tiene el permiso NO recibe ni una fila y no queda registro; (2) quien lo tiene
-- recibe los datos y su lectura queda apuntada; (3) las notas del equipo no salen; (4) la forma de lo que se devuelve.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); los delete/update son sobre filas sembradas aqui mismo.
do $t$
declare
  v_ok text := '';
  j jsonb; n int; n0 int; r text; b boolean;
  t1 constant text := '99977700101'; t2 constant text := '99977700102'; t3 constant text := '99977700103'; t4 constant text := '99977700104';
  l1 uuid; l3a uuid; l3b uuid;
  v_super uuid; v_super_em text; v_ag uuid; v_ag_em text; v_ae uuid; v_ae_em text; v_sm uuid; v_sm_em text;
  v_sin_perm int;
begin
  -- ═══ A. CIERRE DE LAS FUNCIONES ═══
  if has_function_privilege('anon', 'public.crm_bot_conversaciones()', 'execute') or has_function_privilege('anon', 'public.crm_bot_conversacion(text)', 'execute') then
    raise exception 'PRUEBA FALLA: anon ejecuta las funciones de lectura'; end if;
  if has_function_privilege('service_role', 'public.crm_bot_conversaciones()', 'execute') or has_function_privilege('service_role', 'public.crm_bot_conversacion(text)', 'execute') then
    raise exception 'PRUEBA FALLA: service_role ejecuta las funciones de lectura'; end if;
  if has_function_privilege('bot_lawang', 'public.crm_bot_conversaciones()', 'execute') or has_function_privilege('bot_lawang', 'public.crm_bot_conversacion(text)', 'execute') then
    raise exception 'PRUEBA FALLA: el bot ejecuta las funciones de lectura de la intranet'; end if;
  if not (has_function_privilege('authenticated', 'public.crm_bot_conversaciones()', 'execute') and has_function_privilege('authenticated', 'public.crm_bot_conversacion(text)', 'execute')) then
    raise exception 'PRUEBA FALLA: authenticated no puede llamarlas (la intranet no podria leer)'; end if;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('public.crm_bot_conversaciones()'::regprocedure, 'public.crm_bot_conversacion(text)'::regprocedure) and a.grantee = 0) then
    raise exception 'PRUEBA FALLA: PUBLIC ejecuta una funcion de lectura'; end if;
  if has_function_privilege('authenticated', 'public._crm_bot_conv_fila(public.bot_chat, text)', 'execute')
     or has_function_privilege('anon', 'public._crm_bot_conv_fila(public.bot_chat, text)', 'execute') then
    raise exception 'PRUEBA FALLA: la funcion interna _crm_bot_conv_fila es ejecutable desde fuera'; end if;
  if not (select prosecdef from pg_proc where oid = 'public.crm_bot_conversaciones()'::regprocedure and proconfig @> array['search_path=""'])
     or not (select prosecdef from pg_proc where oid = 'public.crm_bot_conversacion(text)'::regprocedure and proconfig @> array['search_path=""']) then
    raise exception 'PRUEBA FALLA: las funciones de lectura deben ser SECURITY DEFINER con search_path fijo'; end if;
  v_ok := v_ok || 'solo authenticated ejecuta (anon/service_role/bot_lawang/PUBLIC no), definer con search_path fijo, la interna cerrada; ';

  -- ═══ semilla ═══
  select user_id, email into v_super, v_super_em from public.usuarios where rol = 'super_admin' and ambito = 'global' and activo and coalesce(cardinality(empresas),0) = 0 order by user_id limit 1;
  select user_id, email into v_ag, v_ag_em from public.usuarios where rol = 'agente' and ambito = 'global' and activo and not ('bot_conversaciones_ver' = any (herramientas)) order by user_id limit 1;
  select user_id, email into v_ae, v_ae_em from public.usuarios where rol = 'admin_empresa' and ambito = 'empresa' and activo order by user_id limit 1;
  select user_id, email into v_sm, v_sm_em from public.usuarios where rol = 'sales_manager' and ambito = 'global' and activo and coalesce(cardinality(empresas),0) = 0 and not ('bot_conversaciones_ver' = any (herramientas)) order by user_id limit 1;
  if v_super is null or v_ag is null or v_ae is null or v_sm is null then raise exception 'PRUEBA FALLA: faltan perfiles de prueba'; end if;

  insert into public.leads (whatsapp, name, source, project) values ('+' || t1, 'Lead Uno', 'bot-whatsapp-lawang', 'palmfield') returning id into l1;
  insert into public.leads (whatsapp, name, source) values ('+' || t3, 'Tres A', 'bot-whatsapp-lawang') returning id into l3a;
  insert into public.leads (whatsapp, name, source) values ('+' || t3, 'Tres B', 'bot-whatsapp-lawang') returning id into l3b;
  insert into public.bot_chat (tel, lead_id, nombre_perfil, intent, ultimo_mensaje, ultimo_por, ultimo_entrante_en, actividad_en, seguimientos)
    values (t1, l1, 'Perfil <b>Uno</b>', 'interested', 'hola <script>x</script>', 'cliente', now() - interval '2 hours', now() - interval '2 hours', 3);
  insert into public.bot_chat (tel, nombre_perfil, ultimo_entrante_en, actividad_en, pausado, pausa_hasta)
    values (t2, 'Dos', now() - interval '25 hours', now() - interval '25 hours', true, now() - interval '1 hour');           -- pausa CADUCADA = no pausado
  insert into public.bot_chat (tel, lead_id, nombre_perfil, actividad_en) values (t3, null, 'Tres ambiguo', now() - interval '3 days');   -- el telefono casa con 2 leads: lead_id nulo
  insert into public.bot_chat (tel, nombre_perfil, actividad_en, baja_en, pausado) values (t4, 'Cuatro baja', now() - interval '4 days', now(), true);
  insert into public.bot_mensaje (tel, rol, por, contenido, creado_en)
    select t1, case when g % 2 = 1 then 'user' else 'assistant' end, case when g % 2 = 1 then 'cliente' else 'bot' end, 'msg ' || g, now() - make_interval(mins => 200 - g)
      from generate_series(1, 130) g;
  insert into public.bot_mensaje (tel, rol, por, por_usuario, contenido, creado_en) values (t1, 'assistant', 'humano', 'ana@lawang', 'respuesta del equipo', now() - interval '1 minute');
  insert into public.bot_mensaje (tel, rol, por, contenido) values (t2, 'user', 'cliente', 'solo uno');
  insert into public.lead_notas (lead_id, texto, autor, tipo) values (l1, 'NOTA HUMANA PRIVADA', 'ana@lawang', 'nota');
  insert into public.lead_notas (lead_id, texto, autor, tipo) values (l1, 'nota del bot', 'bot', 'nota');
  insert into public.lead_notas (lead_id, texto, autor, tipo, ref_hasta_id) values (l1, 'resumen <img src=x onerror=1>', 'bot', 'resumen_bot', 10);
  insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por, tipo, cuando_ts, estado, origen)
    values (l1, 'llamada con el cliente', current_date, 'x@x', 'x@x', 'llamada', now() + interval '1 day', 'confirmada', 'humano');
  insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por, tipo, cuando_ts, estado, origen)
    values (l1, 'tarea que no es cita', current_date, 'x@x', 'x@x', 'tarea', now() + interval '2 days', 'confirmada', 'humano');
  n0 := (select count(*) from public.bot_lecturas_log);

  -- ═══ B. SIN PERMISO: ni una fila, 42501, y NO queda registro ═══
  foreach r in array array['anon', 'agente', 'admin_empresa', 'sales_manager'] loop
    perform set_config('request.jwt.claims', case r when 'agente' then json_build_object('sub', v_ag, 'role', 'authenticated', 'email', v_ag_em)::text
                                                     when 'admin_empresa' then json_build_object('sub', v_ae, 'role', 'authenticated', 'email', v_ae_em)::text
                                                     when 'sales_manager' then json_build_object('sub', v_sm, 'role', 'authenticated', 'email', v_sm_em)::text
                                                     else json_build_object('role', 'anon')::text end, true);
    execute case when r = 'anon' then 'set local role anon' else 'set local role authenticated' end;
    begin j := public.crm_bot_conversaciones(); reset role; raise exception 'PRUEBA FALLA: % obtuvo la lista sin permiso (%)', r, left(j::text, 80);
    exception when insufficient_privilege then reset role; end;
    execute case when r = 'anon' then 'set local role anon' else 'set local role authenticated' end;
    begin j := public.crm_bot_conversacion(t1); reset role; raise exception 'PRUEBA FALLA: % obtuvo el hilo sin permiso (%)', r, left(j::text, 80);
    exception when insufficient_privilege then reset role; end;
  end loop;
  if (select count(*) from public.bot_lecturas_log) <> n0 then raise exception 'PRUEBA FALLA: una lectura denegada dejo registro'; end if;
  v_ok := v_ok || 'anon/agente/admin_empresa/sales_manager sin casilla: 42501 en lista e hilo y sin registro; ';

  -- ═══ C. CON PERMISO: super_admin ═══
  perform set_config('request.jwt.claims', json_build_object('sub', v_super, 'role', 'authenticated', 'email', v_super_em)::text, true);
  set local role authenticated;
  j := public.crm_bot_conversaciones();
  reset role;
  if jsonb_typeof(j->'chats') <> 'array' or (j->>'hayMas')::boolean then raise exception 'PRUEBA FALLA: forma de la lista %', left(j::text, 200); end if;
  if (select count(*) from jsonb_array_elements(j->'chats') c where c->>'phone' in (t1, t2, t3, t4)) <> 4 then raise exception 'PRUEBA FALLA: faltan hilos sembrados'; end if;
  -- orden: el mas reciente primero (t1 hace 2 h antes que t2 hace 25 h)
  if (select min(ord) from (select row_number() over () ord, c->>'phone' ph from jsonb_array_elements(j->'chats') c) q where ph = t1)
   > (select min(ord) from (select row_number() over () ord, c->>'phone' ph from jsonb_array_elements(j->'chats') c) q where ph = t2) then
    raise exception 'PRUEBA FALLA: la lista no va por actividad descendente'; end if;
  declare c1 jsonb; c2 jsonb; c4 jsonb; begin
    select c into c1 from jsonb_array_elements(j->'chats') c where c->>'phone' = t1;
    select c into c2 from jsonb_array_elements(j->'chats') c where c->>'phone' = t2;
    select c into c4 from jsonb_array_elements(j->'chats') c where c->>'phone' = t4;
    if c1->>'name' <> 'Lead Uno' then raise exception 'PRUEBA FALLA: el nombre sale del lead (dueño) y no del perfil: %', c1->>'name'; end if;
    if (c1->>'ventanaAbierta')::boolean is not true or (c2->>'ventanaAbierta')::boolean is not false then raise exception 'PRUEBA FALLA: ventana de 24 h (%, %)', c1->>'ventanaAbierta', c2->>'ventanaAbierta'; end if;
    if (c2->>'paused')::boolean is not false then raise exception 'PRUEBA FALLA: una pausa caducada cuenta como pausada'; end if;
    if (c4->>'optOut')::boolean is not true or (c4->>'paused')::boolean is not true then raise exception 'PRUEBA FALLA: la baja debe verse (optOut y pausada)'; end if;
    if not (c1 ? 'gated') or jsonb_typeof(c1->'gated') <> 'null' then raise exception 'PRUEBA FALLA: gated debe ser NULL (no se sabe desde la base)'; end if;
    if c1->>'lastMessage' <> 'hola <script>x</script>' or c1->>'followups' <> '3' then raise exception 'PRUEBA FALLA: campos del hilo %', c1; end if;
    if c1 ? 'contenido' or c1 ? 'mensajes' then raise exception 'PRUEBA FALLA: la lista no debe traer cuerpos de mensaje'; end if;
  end;
  if (select count(*) from public.bot_lecturas_log where usuario = v_super_em and accion = 'lista' and tel is null) <> 1 then raise exception 'PRUEBA FALLA: la lectura de la lista no quedo apuntada'; end if;
  v_ok := v_ok || 'lista: super_admin la recibe, orden por actividad, nombre del lead, ventana 24 h y pausa caducada calculadas en servidor, baja visible, gated NULL, sin cuerpos, lectura apuntada; ';

  -- hilo
  set local role authenticated;
  j := public.crm_bot_conversacion('+' || t1);                 -- con + y todo: se normaliza
  reset role;
  if j->'chat'->>'phone' <> t1 then raise exception 'PRUEBA FALLA: hilo de otro telefono %', j->'chat'; end if;
  if jsonb_array_length(j->'mensajes') <> 100 or not (j->>'hayMas')::boolean then raise exception 'PRUEBA FALLA: el hilo debe traer 100 y avisar de que hay mas (%)', jsonb_array_length(j->'mensajes'); end if;
  if (j->'mensajes'->99->>'content') <> 'respuesta del equipo' or (j->'mensajes'->99->>'by') <> 'human' or (j->'mensajes'->99->>'role') <> 'assistant'
     or (j->'mensajes'->99->>'byUser') <> 'ana@lawang' then raise exception 'PRUEBA FALLA: ultimo mensaje %', j->'mensajes'->99; end if;
  if (j->'mensajes'->0->>'content') <> 'msg 32' then raise exception 'PRUEBA FALLA: los 100 son los ULTIMOS (primero %)', j->'mensajes'->0->>'content'; end if;
  if exists (select 1 from jsonb_array_elements(j->'mensajes') m with ordinality o(m, i) where i > 1 and (m->>'id')::bigint <= (j->'mensajes'->((i-2)::int)->>'id')::bigint) then
    raise exception 'PRUEBA FALLA: el hilo no va ascendente por id'; end if;
  if (select count(*) from jsonb_array_elements(j->'mensajes') m where m->>'by' = 'client') = 0 or (select count(*) from jsonb_array_elements(j->'mensajes') m where m->>'by' = 'bot') = 0 then
    raise exception 'PRUEBA FALLA: faltan los dos lados del chat'; end if;
  -- ficha del CRM: solo lo del bot, nunca la nota del equipo
  if jsonb_array_length(j->'notas') <> 2 or j::text like '%NOTA HUMANA PRIVADA%' then raise exception 'PRUEBA FALLA: las notas del equipo no deben salir (%)', j->'notas'; end if;
  if not exists (select 1 from jsonb_array_elements(j->'notas') x where x->>'tipo' = 'resumen_bot' and x->>'texto' like 'resumen <img%') then
    raise exception 'PRUEBA FALLA: el resumen debe llegar marcado tipo=resumen_bot'; end if;
  if jsonb_array_length(j->'citas') <> 1 or (j->'citas'->0->>'tipo') <> 'llamada' then raise exception 'PRUEBA FALLA: solo citas (llamada/visita): %', j->'citas'; end if;
  if j->'lead'->>'name' <> 'Lead Uno' or j->'lead'->>'project' <> 'palmfield' then raise exception 'PRUEBA FALLA: lead %', j->'lead'; end if;
  if not exists (select 1 from public.bot_lecturas_log where usuario = v_super_em and accion = 'hilo' and tel = t1) then raise exception 'PRUEBA FALLA: la lectura del hilo no quedo apuntada'; end if;
  v_ok := v_ok || 'hilo: telefono normalizado, ultimos 100 ascendentes con hayMas, por=humano -> by human, ficha con solo notas del bot y resumen marcado, solo citas, lectura apuntada; ';

  -- telefono ambiguo (2 leads) = sin ficha; telefono sin chat = vacio, pero apuntado
  set local role authenticated;
  j := public.crm_bot_conversacion(t3);
  reset role;
  if j->'lead' <> 'null'::jsonb or j->'notas' <> '[]'::jsonb or j->'citas' <> '[]'::jsonb then raise exception 'PRUEBA FALLA: telefono ambiguo con ficha %', j; end if;
  set local role authenticated;
  j := public.crm_bot_conversacion('99977700199');
  reset role;
  if j->'chat' <> 'null'::jsonb or j->'mensajes' <> '[]'::jsonb then raise exception 'PRUEBA FALLA: telefono sin chat %', j; end if;
  if not exists (select 1 from public.bot_lecturas_log where usuario = v_super_em and tel = '99977700199') then raise exception 'PRUEBA FALLA: preguntar por un telefono sin chat tambien se apunta'; end if;
  set local role authenticated;
  begin j := public.crm_bot_conversacion('no-es-telefono'); reset role; raise exception 'PRUEBA FALLA: telefono invalido aceptado';
  exception when others then reset role; if sqlstate <> 'PT400' then raise; end if; end;
  v_ok := v_ok || 'telefono ambiguo -> sin ficha (no se adivina); sin chat -> vacio y apuntado; invalido -> PT400; ';

  -- ═══ D. la casilla: global la tiene, restringido no ═══
  perform set_config('request.jwt.claims', json_build_object('sub', v_super, 'role', 'authenticated', 'email', v_super_em)::text, true);
  update public.usuarios set herramientas = array_append(herramientas, 'bot_conversaciones_ver') where user_id in (v_sm, v_ae);
  perform set_config('request.jwt.claims', json_build_object('sub', v_sm, 'role', 'authenticated', 'email', v_sm_em)::text, true);
  set local role authenticated; j := public.crm_bot_conversacion(t1); reset role;
  if jsonb_array_length(j->'mensajes') <> 100 then raise exception 'PRUEBA FALLA: con la casilla no lee'; end if;
  if not exists (select 1 from public.bot_lecturas_log where usuario = v_sm_em and accion = 'hilo') then raise exception 'PRUEBA FALLA: lectura con casilla sin apuntar'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_ae, 'role', 'authenticated', 'email', v_ae_em)::text, true);
  set local role authenticated;
  begin j := public.crm_bot_conversaciones(); reset role; raise exception 'PRUEBA FALLA: alcance de empresa con casilla leyo el bot (mezcla las dos empresas)';
  exception when insufficient_privilege then reset role; end;
  v_ok := v_ok || 'con la casilla y alcance global lee y queda apuntado; con la casilla pero alcance de empresa 42501; ';

  raise exception 'PRUEBA OK: %', v_ok;
end $t$;
