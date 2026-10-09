-- Prueba de la migracion 20261010120000_bot_sin_redis_s7_purga (S7 del encargo «bot de Lawang sin Redis», 9-oct-2026).
-- Se ejecuta con el MCP (execute_sql) o psql como postgres, DESPUES de aplicar la migracion (o, como ensayo previo, pegando la migracion entera
-- delante en la MISMA llamada: el raise final deshace tambien el DDL). NO deja rastro: todo ocurre dentro de un DO que acaba SIEMPRE en una
-- excepcion (rollback). Si todo va bien el mensaje empieza por «PRUEBA OK»; si algo falla, por «PRUEBA FALLA» y dice cual.
-- Datos sembrados: hilos de >365 dias y mensajes de >24 meses con telefonos 999777002xx. Nunca se toca un dato real.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); los delete/update son sobre filas sembradas aqui mismo.
do $t$
declare
  v_ok text := '';
  j jsonb; n int; n2 int; r text; lid uuid; lid2 uuid; nota_libre bigint; nota_res bigint; nota_res2 bigint;
  t_viejo constant text := '99977700201';   -- hilo inactivo 400 d, con un mensaje de hace 30 d imposible: todo viejo
  t_activo constant text := '99977700202';  -- hilo activo con un mensaje de hace 25 meses (tope duro) y otro reciente
  t_baja constant text := '99977700203';    -- hilo viejo con baja
  t_pausa constant text := '99977700204';   -- hilo viejo con pausa fija
  t_nuevo constant text := '99977700205';   -- hilo reciente: intacto
  t_olv constant text := '99977700211';     -- para crm_bot_olvidar
  t_olv2 constant text := '99977700212';    -- olvidar sin marca de no contactar
  t_contr constant text := '99977700213';   -- lead en contrato
  v_super uuid; v_super_em text; v_ag uuid; v_ag_em text; v_ae uuid; v_ae_em text;
  c1 jsonb;
begin
  -- ═══ A. siembra ═══
  insert into public.bot_chat (tel, nombre_perfil, intent, ultimo_mensaje, actividad_en, creado_en) values
    (t_viejo, 'Viejo', 'x', 'hola', now() - interval '400 days', now() - interval '401 days'),
    (t_activo, 'Activo', 'x', 'hola', now() - interval '1 day', now() - interval '26 months'),
    (t_nuevo, 'Nuevo', 'x', 'hola', now() - interval '2 days', now() - interval '3 days');
  insert into public.bot_chat (tel, nombre_perfil, intent, ultimo_mensaje, actividad_en, baja_en, baja_acuse_en, pausado, pausa_por) values
    (t_baja, 'Baja', 'x', 'stop', now() - interval '400 days', now() - interval '400 days', now() - interval '400 days', true, 'baja');
  insert into public.bot_chat (tel, nombre_perfil, intent, ultimo_mensaje, actividad_en, pausado, pausa_hasta, pausa_por) values
    (t_pausa, 'Pausa', 'x', 'hola', now() - interval '400 days', true, null, 'ana@x');
  insert into public.bot_mensaje (tel, rol, por, contenido, creado_en) values
    (t_viejo, 'user', 'cliente', 'm1', now() - interval '401 days'), (t_viejo, 'assistant', 'bot', 'm2', now() - interval '400 days'),
    (t_activo, 'user', 'cliente', 'muy viejo', now() - interval '25 months'), (t_activo, 'user', 'cliente', 'reciente', now() - interval '1 day'),
    (t_baja, 'user', 'cliente', 'stop', now() - interval '400 days'),
    (t_pausa, 'user', 'cliente', 'hola', now() - interval '400 days'),
    (t_nuevo, 'user', 'cliente', 'hola', now() - interval '2 days');
  insert into public.bot_escalacion (tel, nombre, pregunta, creada_en) values (t_viejo, 'Viejo', 'pregunta', now() - interval '400 days'),
    (t_nuevo, 'Nuevo', 'pregunta', now() - interval '2 days');
  insert into public.bot_wamid (wamid, tel, visto_en) values ('s7-viejo', t_nuevo, now() - interval '11 days'), ('s7-ok', t_nuevo, now() - interval '9 days');
  insert into public.bot_lecturas_log (usuario, tel, accion, cuando) values ('x@x', t_nuevo, 'hilo', now() - interval '13 months'), ('x@x', t_nuevo, 'hilo', now() - interval '11 months');
  insert into public.bot_acciones_log (cuando, accion, resultado, detalle) values (now() - interval '91 days', 'nota', 'ok', 's7-viejo'), (now() - interval '89 days', 'nota', 'ok', 's7-ok');
  insert into public.bot_olvidos_log (cuando, usuario, tel_hash, motivo, resultado) values (now() - interval '25 months', 'x@x', repeat('a', 64), 'otro', '{}'), (now() - interval '1 day', 'x@x', repeat('b', 64), 'otro', '{}');
  -- lead con resumen del bot y nota libre (sobreviven / no sobreviven segun el caso)
  insert into public.leads (name, whatsapp, email, ip, campaign_id, adset_id, ad_id, form_id, respuestas, source, project)
    values ('Lead Purga', '+' || t_viejo, 'a@b.c', '1.2.3.4', 'c1', 'as1', 'ad1', 'f1', '{"p":1}'::jsonb, 'meta', 'palm-field') returning id into lid;
  insert into public.lead_notas (lead_id, texto, autor) values (lid, 'nota libre', 'ana@x') returning id into nota_libre;
  insert into public.lead_notas (lead_id, texto, autor, tipo, ref_hasta_id) values (lid, 'resumen', 'bot', 'resumen_bot', 1) returning id into nota_res;
  update public.bot_chat set lead_id = lid where tel = t_viejo;

  -- ═══ B. la purga ═══
  j := public.bot_purga();
  if exists (select 1 from public.bot_mensaje where tel = t_viejo) or exists (select 1 from public.bot_escalacion where tel = t_viejo)
     or exists (select 1 from public.bot_chat where tel = t_viejo) then raise exception 'PRUEBA FALLA: el hilo de 400 d sigue %', j; end if;
  if (j->>'bot_mensaje_hilo_inactivo')::int <> 4 then raise exception 'PRUEBA FALLA: debia borrar 4 mensajes de hilos inactivos (viejo 2, baja 1, pausa 1) %', j; end if;
  if (j->>'bot_chat_borrados')::int <> 1 then raise exception 'PRUEBA FALLA: debia borrar 1 conversacion (la vieja sin marca) %', j; end if;
  v_ok := v_ok || 'hilo >365 d borrado entero; ';
  -- baja y pausa fija: se quedan, sin contenido
  select count(*) into n from public.bot_chat where tel in (t_baja, t_pausa) and nombre_perfil is null and ultimo_mensaje is null and intent is null;
  if n <> 2 then raise exception 'PRUEBA FALLA: baja y pausa fija debian quedarse reducidas a la marca (%)', n; end if;
  if (select baja_en from public.bot_chat where tel = t_baja) is null or (select pausado from public.bot_chat where tel = t_pausa) is not true then
    raise exception 'PRUEBA FALLA: la purga olvido una baja o una pausa'; end if;
  if exists (select 1 from public.bot_mensaje where tel in (t_baja, t_pausa)) then raise exception 'PRUEBA FALLA: los mensajes de baja/pausa debian purgarse'; end if;
  v_ok := v_ok || 'bajas y pausas fijas conservadas como marca sin contenido; ';
  -- tope 24 m
  if exists (select 1 from public.bot_mensaje where tel = t_activo and contenido = 'muy viejo') then raise exception 'PRUEBA FALLA: el mensaje de 25 meses sigue'; end if;
  if not exists (select 1 from public.bot_mensaje where tel = t_activo and contenido = 'reciente') or not exists (select 1 from public.bot_chat where tel = t_activo) then
    raise exception 'PRUEBA FALLA: el tope de 24 m borro de mas'; end if;
  if (j->>'bot_mensaje_tope_24m')::int <> 1 then raise exception 'PRUEBA FALLA: tope 24 m contó %', j; end if;
  v_ok := v_ok || 'tope 24 m borra el mensaje viejo de un hilo activo y respeta el reciente; ';
  -- intactos
  if (select count(*) from public.bot_mensaje where tel = t_nuevo) <> 1 or (select count(*) from public.bot_escalacion where tel = t_nuevo) <> 1 or not exists (select 1 from public.bot_chat where tel = t_nuevo) then
    raise exception 'PRUEBA FALLA: toco un hilo reciente'; end if;
  -- resumenes y notas: intactos
  if not exists (select 1 from public.lead_notas where id = nota_res) or not exists (select 1 from public.lead_notas where id = nota_libre) then raise exception 'PRUEBA FALLA: la purga toco lead_notas'; end if;
  v_ok := v_ok || 'hilos recientes y lead_notas (resumenes incluidos) intactos; ';
  -- wamid y logs
  if exists (select 1 from public.bot_wamid where wamid = 's7-viejo') or not exists (select 1 from public.bot_wamid where wamid = 's7-ok') then raise exception 'PRUEBA FALLA: bot_wamid (10 d)'; end if;
  if (select count(*) from public.bot_lecturas_log where usuario = 'x@x') <> 1 then raise exception 'PRUEBA FALLA: bot_lecturas_log 12 meses'; end if;
  if exists (select 1 from public.bot_acciones_log where detalle = 's7-viejo') or not exists (select 1 from public.bot_acciones_log where detalle = 's7-ok') then raise exception 'PRUEBA FALLA: bot_acciones_log 90 d'; end if;
  if exists (select 1 from public.bot_olvidos_log where tel_hash = repeat('a', 64)) or not exists (select 1 from public.bot_olvidos_log where tel_hash = repeat('b', 64)) then raise exception 'PRUEBA FALLA: bot_olvidos_log 24 m'; end if;
  v_ok := v_ok || 'bot_wamid 10 d, lecturas 12 m, acciones 90 d, olvidos 24 m; ';
  -- su log: solo conteos
  if not exists (select 1 from public.bot_purga_log where tabla = 'bot_mensaje' and filas = 4) then raise exception 'PRUEBA FALLA: sin traza de la purga'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'bot_purga_log' and column_name not in ('id', 'cuando', 'tabla', 'filas', 'motivo')) then
    raise exception 'PRUEBA FALLA: bot_purga_log tiene columnas de contenido'; end if;
  v_ok := v_ok || 'traza solo con conteos; ';
  -- idempotente
  j := public.bot_purga();
  if (j->>'bot_mensaje_hilo_inactivo')::int <> 0 or (j->>'bot_chat_borrados')::int <> 0 or (j->>'bot_chat_reducidos_a_la_marca')::int <> 0 then raise exception 'PRUEBA FALLA: 2a ejecucion no es no-op %', j; end if;
  v_ok := v_ok || '2a ejecucion no-op; ';

  -- ═══ C. los logs siguen siendo de solo anadir fuera de la purga ═══
  begin delete from public.bot_acciones_log; raise exception 'PRUEBA FALLA: se pudo borrar bot_acciones_log sin la purga';
  exception when insufficient_privilege then null; end;
  begin update public.bot_acciones_log set detalle = 'z'; raise exception 'PRUEBA FALLA: se pudo editar bot_acciones_log';
  exception when insufficient_privilege then null; end;
  begin truncate public.bot_acciones_log; raise exception 'PRUEBA FALLA: se pudo vaciar bot_acciones_log';
  exception when insufficient_privilege then null; end;
  begin delete from public.bot_purga_log; raise exception 'PRUEBA FALLA: se pudo borrar bot_purga_log fuera de la purga';
  exception when insufficient_privilege then null; end;
  begin delete from public.bot_olvidos_log; raise exception 'PRUEBA FALLA: se pudo borrar bot_olvidos_log fuera de la purga';
  exception when insufficient_privilege then null; end;
  begin delete from public.bot_config_log; raise exception 'PRUEBA FALLA: bot_config_log dejo de ser solo anade';
  exception when insufficient_privilege then null; end;
  v_ok := v_ok || 'logs de solo anadir fuera de la purga (la compartida sigue cerrando bot_config_log); ';

  -- ═══ D. cierre de privilegios ═══
  foreach r in array array['anon', 'authenticated', 'service_role', 'bot_lawang'] loop
    if has_function_privilege(r, 'public.bot_purga()', 'execute') or has_function_privilege(r, 'public.bot_olvidos_reaplicar()', 'execute')
       or has_function_privilege(r, 'public._bot_olvidar_tel(text,boolean)', 'execute') then raise exception 'PRUEBA FALLA: % ejecuta la purga/el olvido interno', r; end if;
    if has_table_privilege(r, 'public.bot_purga_log', 'select,insert,update,delete') or has_table_privilege(r, 'public.bot_olvidos_log', 'select,insert,update,delete')
       or has_table_privilege(r, 'public.lead_notas_retiradas', 'select,insert,update,delete') then raise exception 'PRUEBA FALLA: % toca las trazas', r; end if;
  end loop;
  foreach r in array array['anon', 'service_role', 'bot_lawang'] loop
    if has_function_privilege(r, 'public.crm_bot_olvidar(text,text,boolean)', 'execute') or has_function_privilege(r, 'public.lead_nota_retirar(bigint,text)', 'execute') then
      raise exception 'PRUEBA FALLA: % ejecuta crm_bot_olvidar/lead_nota_retirar', r; end if;
  end loop;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a where a.grantee = 0 and p.oid in ('public.bot_purga()'::regprocedure, 'public.crm_bot_olvidar(text,text,boolean)'::regprocedure,
       'public.lead_nota_retirar(bigint,text)'::regprocedure, 'public.bot_olvidos_reaplicar()'::regprocedure, 'public._bot_olvidar_tel(text,boolean)'::regprocedure)) then
    raise exception 'PRUEBA FALLA: PUBLIC ejecuta alguna funcion nueva'; end if;
  set local role bot_lawang;
  begin perform public.bot_purga(); reset role; raise exception 'PRUEBA FALLA: bot_lawang pudo lanzar la purga';
  exception when insufficient_privilege then reset role; end;
  if not exists (select 1 from cron.job where jobname = 'bot_purga' and schedule = '23 3 * * *' and command like '%bot_purga()%') then raise exception 'PRUEBA FALLA: el job pg_cron no existe'; end if;
  v_ok := v_ok || 'solo el job/postgres ejecuta la purga; pg_cron programado; ';

  -- ═══ E. crm_bot_olvidar ═══
  select user_id, email into v_super, v_super_em from public.usuarios where rol = 'super_admin' and ambito = 'global' and activo and coalesce(cardinality(empresas),0) = 0 order by user_id limit 1;
  select user_id, email into v_ag, v_ag_em from public.usuarios where rol = 'agente' and ambito = 'global' and activo order by user_id limit 1;
  select user_id, email into v_ae, v_ae_em from public.usuarios where rol = 'admin_empresa' and ambito = 'empresa' and activo order by user_id limit 1;
  if v_super is null or v_ag is null or v_ae is null then raise exception 'PRUEBA FALLA: faltan perfiles de prueba'; end if;
  -- lead de t_olv con todo; otro lead en contrato
  insert into public.bot_chat (tel, nombre_perfil, intent, ultimo_mensaje) values (t_olv, 'Olvidame', 'x', 'hola'), (t_olv2, 'Sin marca', 'x', 'hola'), (t_contr, 'Contrato', 'x', 'hola');
  insert into public.bot_mensaje (tel, rol, por, contenido) values (t_olv, 'user', 'cliente', 'a'), (t_olv, 'assistant', 'bot', 'b'), (t_olv2, 'user', 'cliente', 'a'), (t_contr, 'user', 'cliente', 'a');
  insert into public.bot_escalacion (tel, nombre, pregunta) values (t_olv, 'O', 'q');
  insert into public.bot_wamid (wamid, tel) values ('s7-olv-1', t_olv), ('s7-olv-2', t_olv2);
  insert into public.leads (name, whatsapp, email, ip, campaign_id, adset_id, ad_id, form_id, respuestas, source, project)
    values ('Lead Olvido', '+' || t_olv, 'o@b.c', '9.9.9.9', 'c1', 'as1', 'ad1', 'f1', '{"p":1}'::jsonb, 'meta', 'palm-field') returning id into lid;
  insert into public.lead_notas (lead_id, texto, autor) values (lid, 'libre 1', 'ana@x'), (lid, 'libre bot', 'bot');
  insert into public.lead_notas (lead_id, texto, autor, tipo, ref_hasta_id) values (lid, 'RESUMEN QUE SE QUEDA', 'bot', 'resumen_bot', 7) returning id into nota_res2;
  insert into public.leads (name, whatsapp, email, ip, campaign_id, source, project) values ('Lead Contrato', '+' || t_contr, 'c@b.c', '8.8.8.8', 'c9', 'meta', 'palm-field') returning id into lid2;
  insert into public.lead_notas (lead_id, texto, autor) values (lid2, 'nota de contrato', 'ana@x');
  update public.lead_estado set estado = 'contrato' where lead_id = lid2;
  if not exists (select 1 from public.lead_estado where lead_id = lid2 and estado = 'contrato') then raise exception 'PRUEBA FALLA: no pude poner el lead en contrato (siembra)'; end if;

  -- sin permiso
  foreach r in array array['agente', 'admin_empresa', 'anon'] loop
    perform set_config('request.jwt.claims', case r when 'agente' then json_build_object('sub', v_ag, 'role', 'authenticated', 'email', v_ag_em)::text
                                                     when 'admin_empresa' then json_build_object('sub', v_ae, 'role', 'authenticated', 'email', v_ae_em)::text
                                                     else json_build_object('role', 'anon')::text end, true);
    begin perform public.crm_bot_olvidar(t_olv); raise exception 'PRUEBA FALLA: % pudo olvidar', r;
    exception when insufficient_privilege then null; end;
    begin perform public.lead_nota_retirar(nota_res2, 'otro'); raise exception 'PRUEBA FALLA: % pudo retirar un resumen', r;
    exception when insufficient_privilege then null; end;
  end loop;
  if not exists (select 1 from public.bot_mensaje where tel = t_olv) then raise exception 'PRUEBA FALLA: un sin-permiso borro datos'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_super, 'role', 'authenticated', 'email', v_super_em)::text, true);
  begin perform public.crm_bot_olvidar('abc'); raise exception 'PRUEBA FALLA: telefono invalido aceptado'; exception when sqlstate 'PT400' then null; end;
  begin perform public.crm_bot_olvidar(t_olv, 'por_gusto'); raise exception 'PRUEBA FALLA: motivo invalido aceptado'; exception when sqlstate 'PT400' then null; end;
  v_ok := v_ok || 'olvidar/retirar: solo admin global (agente, admin de empresa y anon rechazados); ';

  c1 := public.crm_bot_olvidar(t_olv);
  if exists (select 1 from public.bot_mensaje where tel = t_olv) or exists (select 1 from public.bot_escalacion where tel = t_olv) or exists (select 1 from public.bot_wamid where tel = t_olv) then
    raise exception 'PRUEBA FALLA: quedan filas del telefono %', c1; end if;
  if (select count(*) from public.bot_chat where tel = t_olv) <> 1 or (select baja_en from public.bot_chat where tel = t_olv) is null
     or (select nombre_perfil from public.bot_chat where tel = t_olv) is not null or (select lead_id from public.bot_chat where tel = t_olv) is not null then
    raise exception 'PRUEBA FALLA: bot_chat debia quedar solo como marca de baja'; end if;
  if not exists (select 1 from public.lead_notas where id = nota_res2) then raise exception 'PRUEBA FALLA: el olvido borro el resumen (decision 6)'; end if;
  if exists (select 1 from public.lead_notas where lead_id = (select id from public.leads where whatsapp = '+' || t_olv) and tipo = 'nota') then raise exception 'PRUEBA FALLA: quedan notas libres'; end if;
  select count(*) into n from public.leads where whatsapp = '+' || t_olv and email is null and ip is null and campaign_id is null and adset_id is null and ad_id is null and form_id is null and respuestas is null and name = 'Lead Olvido';
  if n <> 1 then raise exception 'PRUEBA FALLA: ficha minima (sin email/IP/atribucion/respuestas, con nombre)'; end if;
  v_ok := v_ok || 'olvido: 0 filas del telefono salvo la marca de baja, resumen intacto, ficha minima; ';
  -- traza hasheada
  if not exists (select 1 from public.bot_olvidos_log where tel_hash = public._bot_tel_hash(t_olv) and usuario = v_super_em)
     or exists (select 1 from public.bot_olvidos_log where resultado::text like '%' || t_olv || '%' or tel_hash like '%' || t_olv || '%') then
    raise exception 'PRUEBA FALLA: traza del olvido ausente o con el telefono en claro'; end if;
  v_ok := v_ok || 'traza con telefono hasheado y solo conteos; ';
  -- idempotente
  c1 := public.crm_bot_olvidar(t_olv);
  if (c1->>'bot_mensaje')::int <> 0 then raise exception 'PRUEBA FALLA: segundo olvido'; end if;
  -- sin marca de no contactar y sin baja previa: se borra la fila
  c1 := public.crm_bot_olvidar(t_olv2, 'oposicion', false);
  if exists (select 1 from public.bot_chat where tel = t_olv2) or exists (select 1 from public.bot_mensaje where tel = t_olv2) or exists (select 1 from public.bot_wamid where tel = t_olv2) then
    raise exception 'PRUEBA FALLA: p_no_contactar=false debia borrar la conversacion %', c1; end if;
  -- lead en contrato: ficha intacta, chat si se borra
  c1 := public.crm_bot_olvidar(t_contr);
  if (c1->>'fichas_conservadas_por_contrato')::int <> 1 or not exists (select 1 from public.leads where id = lid2 and email = 'c@b.c' and ip = '8.8.8.8')
     or not exists (select 1 from public.lead_notas where lead_id = lid2 and tipo = 'nota') then raise exception 'PRUEBA FALLA: toco la ficha de un lead en contrato %', c1; end if;
  if exists (select 1 from public.bot_mensaje where tel = t_contr) then raise exception 'PRUEBA FALLA: lead en contrato: el chat debia borrarse'; end if;
  v_ok := v_ok || 'sin marca = fila borrada; lead en contrato conserva su ficha; ';

  -- reaplicar tras restaurar un backup
  perform set_config('request.jwt.claims', '', true);
  insert into public.bot_mensaje (tel, rol, por, contenido) values (t_olv, 'user', 'cliente', 'resucitado');
  insert into public.bot_wamid (wamid, tel) values ('s7-olv-3', t_olv);
  j := public.bot_olvidos_reaplicar();
  if (j->>'telefonos_reaplicados')::int < 1 or exists (select 1 from public.bot_mensaje where tel = t_olv) or exists (select 1 from public.bot_wamid where tel = t_olv) then
    raise exception 'PRUEBA FALLA: reaplicar no volvio a borrar %', j; end if;
  v_ok := v_ok || 'reaplicar olvidos tras restaurar backup; ';

  -- ═══ F. lead_nota_retirar ═══
  perform set_config('request.jwt.claims', json_build_object('sub', v_super, 'role', 'authenticated', 'email', v_super_em)::text, true);
  begin perform public.lead_nota_retirar(nota_libre, 'otro'); raise exception 'PRUEBA FALLA: retiro una nota que no es resumen'; exception when sqlstate 'PT404' then null; end;
  begin perform public.lead_nota_retirar(nota_res2, 'por_gusto'); raise exception 'PRUEBA FALLA: motivo invalido'; exception when sqlstate 'PT400' then null; end;
  j := public.lead_nota_retirar(nota_res2, 'dato_sensible');
  if exists (select 1 from public.lead_notas where id = nota_res2) or not exists (select 1 from public.lead_notas_retiradas where nota_id = nota_res2 and usuario = v_super_em and motivo = 'dato_sensible') then
    raise exception 'PRUEBA FALLA: retirada sin efecto o sin traza'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'lead_notas_retiradas' and column_name in ('texto', 'contenido')) then raise exception 'PRUEBA FALLA: la traza guarda contenido'; end if;
  perform set_config('request.jwt.claims', '', true);
  begin update public.lead_notas_retiradas set motivo = 'otro'; raise exception 'PRUEBA FALLA: se pudo editar la traza de retiradas'; exception when insufficient_privilege then null; end;
  v_ok := v_ok || 'lead_nota_retirar: solo resumenes, motivo cerrado, traza sin contenido e inmutable; ';

  raise exception 'PRUEBA OK: %', v_ok;
end $t$;
