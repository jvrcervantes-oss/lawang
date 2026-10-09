-- Prueba de la migracion 20261010110000_bot_sin_redis_s1_esquema (S1 del encargo «bot de Lawang sin Redis», 9-oct-2026).
-- Se ejecuta con el MCP (execute_sql) o psql como postgres, DESPUES de aplicar la migracion. NO deja rastro: todo ocurre dentro de un DO que
-- acaba SIEMPRE en una excepcion (rollback). Si todo va bien el mensaje empieza por «PRUEBA OK»; si algo falla, por «PRUEBA FALLA» y dice cual.
-- Se llama a las funciones con el ROL REAL (set local role bot_lawang), no como postgres. El reloj esta CONGELADO dentro de una transaccion:
-- el envejecimiento se simula retrasando filas como postgres, no esperando.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); los delete/update son sobre filas sembradas aqui mismo.
do $t$
declare
  v_ok text := '';
  j jsonb; r text; n int; n2 int; b boolean; ts timestamptz;
  t1 constant text := '99977700001'; t2 constant text := '99977700002'; t3 constant text := '99977700003';
  l1 uuid; l2 uuid; l2b uuid; a1 uuid; a2 uuid;
  w text; mx bigint; mx2 bigint; id_otro bigint;
  v_super uuid; v_super_em text; v_ag uuid; v_ag_em text; v_ae uuid; v_ae_em text; v_sm uuid; v_sm_em text;
  tablas constant text[] := array['bot_chat','bot_mensaje','bot_wamid','bot_escalacion','bot_config','bot_config_log','bot_lecturas_log'];
  seqs constant text[] := array['bot_mensaje_id_seq','bot_escalacion_id_seq','bot_config_log_id_seq','bot_lecturas_log_id_seq'];
  del_bot constant text[] := array[
    'bot_lead_upsert(text,text,text,text)','bot_mensaje_recibir(text,text,text,jsonb)','bot_turno_estado(text,boolean)',
    'bot_turno_cerrar(text,text,jsonb,text,text,boolean,boolean)','bot_eco_operadora(text,text,text,integer)','bot_pausar(text,text,integer)',
    'bot_baja(text,text)','bot_entrega_fallida(text,text,text)','bot_escalar(text,text,text,text)','bot_escalacion_tomar(text)',
    'bot_lead_resumen(text,text,bigint)','bot_citas_recordar()','bot_cita_recordatorio_res(uuid,text)','bot_pausar_humano(text,text,text)',
    'bot_envio_humano(text,text,text,jsonb,text)'];
  internas constant text[] := array[
    '_bot_tel(text)','_bot_limpia(text,integer)','_bot_media(jsonb)','_bot_pausa_humana(text,integer,text)','_bot_conversaciones_autoriza(text,text)',
    '_bot_recordatorio_reinicia()','_bot_lecturas_solo_anade()','_bot_config_antes()','_bot_config_log()'];
  f text; rl text;
begin
  -- ═══ A. CIERRE: nadie ejecuta ni lee nada salvo bot_lawang sus funciones ═══
  foreach f in array tablas loop
    foreach rl in array array['anon','authenticated','service_role','bot_lawang'] loop
      if has_table_privilege(rl, 'public.' || f, 'select,insert,update,delete,truncate,references,trigger') then
        raise exception 'PRUEBA FALLA: % tiene privilegios sobre la tabla %', rl, f; end if;
    end loop;
    if exists (select 1 from pg_class c, aclexplode(c.relacl) a where c.oid = ('public.' || f)::regclass and a.grantee = 0) then
      raise exception 'PRUEBA FALLA: PUBLIC tiene privilegios sobre %', f; end if;
    if not (select relrowsecurity from pg_class where oid = ('public.' || f)::regclass) then raise exception 'PRUEBA FALLA: % sin RLS', f; end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = f) then raise exception 'PRUEBA FALLA: % tiene policies', f; end if;
  end loop;
  foreach f in array seqs loop
    foreach rl in array array['anon','authenticated','service_role','bot_lawang'] loop
      if has_sequence_privilege(rl, 'public.' || f, 'usage,select,update') then raise exception 'PRUEBA FALLA: % usa la secuencia %', rl, f; end if;
    end loop;
  end loop;
  v_ok := v_ok || '7 tablas y 4 secuencias cerradas (RLS sin policies, 0 privilegios); ';

  foreach f in array del_bot || internas loop
    if not exists (select 1 from pg_proc p where p.oid = ('public.' || f)::regprocedure and p.proconfig::text like '%search_path=%') then
      raise exception 'PRUEBA FALLA: % sin search_path fijo', f; end if;
    if (select proacl from pg_proc where oid = ('public.' || f)::regprocedure) is null
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = ('public.' || f)::regprocedure and a.grantee = 0) then
      raise exception 'PRUEBA FALLA: % con proacl nulo o con PUBLIC', f; end if;
    foreach rl in array array['anon','authenticated','service_role'] loop
      if has_function_privilege(rl, ('public.' || f)::regprocedure, 'execute') then raise exception 'PRUEBA FALLA: % ejecuta %', rl, f; end if;
    end loop;
  end loop;
  foreach f in array del_bot loop
    if not has_function_privilege('bot_lawang', ('public.' || f)::regprocedure, 'execute') then raise exception 'PRUEBA FALLA: bot_lawang no ejecuta %', f; end if;
    if not (select prosecdef from pg_proc where oid = ('public.' || f)::regprocedure) then raise exception 'PRUEBA FALLA: % no es SECURITY DEFINER', f; end if;
  end loop;
  foreach f in array internas loop
    if has_function_privilege('bot_lawang', ('public.' || f)::regprocedure, 'execute') then raise exception 'PRUEBA FALLA: bot_lawang ejecuta la interna %', f; end if;
  end loop;
  v_ok := v_ok || '15 funciones del bot: DEFINER+search_path, proacl sin PUBLIC, solo bot_lawang; 9 internas sin EXECUTE para nadie; ';

  -- estructura pedida
  if (select confdeltype from pg_constraint where conrelid = 'public.bot_mensaje'::regclass and contype = 'f' and confrelid = 'public.bot_chat'::regclass) <> 'c' then
    raise exception 'PRUEBA FALLA: bot_mensaje.tel no es ON DELETE CASCADE'; end if;
  if not exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'bot_chat' and indexdef ilike '%(actividad_en)%') then
    raise exception 'PRUEBA FALLA: bot_chat.actividad_en sin indice'; end if;
  begin insert into public.bot_config (id) values (false); raise exception 'PRUEBA FALLA: bot_config admitio id=false';
  exception when check_violation then null; end;
  begin insert into public.bot_config (id) values (true); raise exception 'PRUEBA FALLA: bot_config admitio una segunda fila';
  exception when unique_violation then null; end;
  begin delete from public.bot_config; raise exception 'PRUEBA FALLA: se pudo borrar bot_config';
  exception when insufficient_privilege then null; end;
  begin update public.bot_config set pausa_horas = 721; raise exception 'PRUEBA FALLA: pausa_horas 721';
  exception when check_violation then null; end;
  -- config: version + log automatico en la misma transaccion
  update public.bot_config set extra = 'x', actualizado_por = 'prueba@x';
  if (select version from public.bot_config) <> 2 then raise exception 'PRUEBA FALLA: la version no subio'; end if;
  if not exists (select 1 from public.bot_config_log where usuario = 'prueba@x' and version = 2 and prev->>'extra' = '' and next->>'extra' = 'x') then
    raise exception 'PRUEBA FALLA: bot_config_log sin la fila del cambio'; end if;
  begin update public.bot_config_log set usuario = 'z'; raise exception 'PRUEBA FALLA: se pudo editar bot_config_log';
  exception when insufficient_privilege then null; end;
  begin delete from public.bot_config_log; raise exception 'PRUEBA FALLA: se pudo borrar bot_config_log';
  exception when insufficient_privilege then null; end;
  begin insert into public.bot_chat (tel) values (t1); insert into public.bot_mensaje (tel, rol, por, contenido) values (t1, 'user', 'cliente', repeat('x', 4097));
    raise exception 'PRUEBA FALLA: bot_mensaje admitio 4097';
  exception when check_violation then null; end;
  delete from public.bot_chat where tel = t1;
  begin insert into public.bot_chat (tel) values (t1); insert into public.bot_mensaje (tel, rol, por, contenido, media) values (t1, 'user', 'cliente', 'a', '{"tipo":"image","id":"x","url":"http://x"}');
    raise exception 'PRUEBA FALLA: bot_mensaje admitio media con url';
  exception when check_violation then null; end;
  delete from public.bot_chat where tel = t1;
  v_ok := v_ok || 'FK cascada, indice, config de fila unica con limites y log automatico, 4096 y media cerrados por CHECK; ';

  -- ═══ B. EL CAMINO DEL MENSAJE (con el rol real) ═══
  set local role bot_lawang;
  j := public.bot_mensaje_recibir(t1, 'w1', 'Perfil Uno', jsonb_build_object('texto', 'hola', 'ts', extract(epoch from now())::bigint));
  reset role;
  if (j->>'duplicado')::boolean or (j->>'procesado')::boolean then raise exception 'PRUEBA FALLA: primer recibir %', j; end if;
  if not (select esperando from public.bot_chat where tel = t1) or (select count(*) from public.bot_mensaje where tel = t1) <> 1 then raise exception 'PRUEBA FALLA: recibir no guardo'; end if;
  set local role bot_lawang;
  j := public.bot_mensaje_recibir(t1, 'w1', 'Perfil Uno', jsonb_build_object('texto', 'hola'));
  reset role;
  if not (j->>'duplicado')::boolean or (j->>'procesado')::boolean then raise exception 'PRUEBA FALLA: duplicado sin procesar %', j; end if;
  if (select count(*) from public.bot_mensaje where tel = t1) <> 1 then raise exception 'PRUEBA FALLA: el duplicado inserto otra vez'; end if;
  -- reproceso UNA vez pasados 10 min
  update public.bot_wamid set visto_en = now() - interval '11 minutes' where wamid = 'w1';
  set local role bot_lawang; j := public.bot_mensaje_recibir(t1, 'w1', null, jsonb_build_object('texto', 'hola')); reset role;
  if not coalesce((j->>'reproceso')::boolean, false) or (j->>'duplicado')::boolean then raise exception 'PRUEBA FALLA: sin reproceso %', j; end if;
  update public.bot_wamid set visto_en = now() - interval '11 minutes' where wamid = 'w1';
  set local role bot_lawang; j := public.bot_mensaje_recibir(t1, 'w1', null, jsonb_build_object('texto', 'hola')); reset role;
  if not (j->>'duplicado')::boolean or (j->>'procesado')::boolean or j ? 'reproceso' then raise exception 'PRUEBA FALLA: segundo reproceso %', j; end if;
  if (select count(*) from public.bot_mensaje where tel = t1) <> 1 then raise exception 'PRUEBA FALLA: el reproceso duplico el mensaje'; end if;
  v_ok := v_ok || 'recibir: reclamo atomico, duplicado, reproceso una sola vez; ';

  -- estado
  set local role bot_lawang; j := public.bot_turno_estado(t1, true); reset role;
  if (j->>'baja')::boolean or (j->>'pausado')::boolean or not (j->>'avisar_testing')::boolean or not (j->>'primer_turno')::boolean
     or jsonb_array_length(j->'historial') <> 1 or (j->'config'->>'version')::int <> 2 then raise exception 'PRUEBA FALLA: estado %', j; end if;
  set local role bot_lawang; j := public.bot_turno_estado(t1, true); reset role;
  if (j->>'avisar_testing')::boolean then raise exception 'PRUEBA FALLA: el aviso de testing se repite'; end if;
  set local role bot_lawang; j := public.bot_turno_estado('99977700099'); reset role;
  if j->>'error' <> 'sin_chat' then raise exception 'PRUEBA FALLA: estado de un chat inexistente %', j; end if;
  set local role bot_lawang; j := public.bot_turno_estado('abc'); reset role;
  if j->>'error' <> 'telefono_invalido' then raise exception 'PRUEBA FALLA: telefono invalido %', j; end if;

  -- 4096 por el RPC: se recorta, no falla
  set local role bot_lawang; j := public.bot_mensaje_recibir(t1, 'w2', null, jsonb_build_object('texto', repeat('y', 5000), 'media', jsonb_build_object('tipo','image','id','m1','url','http://x','base64','zzz'))); reset role;
  if (select max(length(contenido)) from public.bot_mensaje where tel = t1) <> 4096 then raise exception 'PRUEBA FALLA: no recorto a 4096'; end if;
  if (select media from public.bot_mensaje where tel = t1 and wamid = 'w2') <> '{"tipo":"image","id":"m1"}'::jsonb then raise exception 'PRUEBA FALLA: media no quedo en {tipo,id}'; end if;

  -- cerrar
  set local role bot_lawang;
  j := public.bot_turno_cerrar(t1, 'w1', jsonb_build_array(jsonb_build_object('texto','respuesta uno','wamid','o1'), jsonb_build_object('texto','respuesta dos')), 'interested', 'interested', false);
  reset role;
  if j->>'avisar' <> 'interested' or (j->>'repetido')::boolean then raise exception 'PRUEBA FALLA: cerrar %', j; end if;
  if (select aviso_nivel from public.bot_chat where tel = t1) <> 1 or (select intent from public.bot_chat where tel = t1) <> 'interested'
     or (select esperando from public.bot_chat where tel = t1) or (select ultimo_por from public.bot_chat where tel = t1) <> 'bot' then raise exception 'PRUEBA FALLA: estado tras cerrar'; end if;
  if (select procesado_en from public.bot_wamid where wamid = 'w1') is null then raise exception 'PRUEBA FALLA: no fijo procesado_en'; end if;
  n := (select count(*) from public.bot_mensaje where tel = t1);
  set local role bot_lawang; j := public.bot_turno_cerrar(t1, 'w1', jsonb_build_array(jsonb_build_object('texto','otra vez')), 'x', 'booking', true); reset role;
  if not (j->>'repetido')::boolean or (select count(*) from public.bot_mensaje where tel = t1) <> n then raise exception 'PRUEBA FALLA: el cierre repetido no es idempotente'; end if;
  set local role bot_lawang; j := public.bot_mensaje_recibir(t1, 'w1', null, jsonb_build_object('texto', 'hola')); reset role;
  if not (j->>'duplicado')::boolean or not (j->>'procesado')::boolean then raise exception 'PRUEBA FALLA: procesado no descarta %', j; end if;
  -- un aviso por nivel
  set local role bot_lawang; j := public.bot_mensaje_recibir(t1, 'w3', null, jsonb_build_object('texto', 'quiero cita')); reset role;
  set local role bot_lawang; j := public.bot_turno_cerrar(t1, 'w3', '[]'::jsonb, null, 'interested', false); reset role;
  if j->'avisar' <> 'null'::jsonb then raise exception 'PRUEBA FALLA: aviso repetido %', j; end if;
  set local role bot_lawang; j := public.bot_mensaje_recibir(t1, 'w4', null, jsonb_build_object('texto', 'reservo')); reset role;
  set local role bot_lawang; j := public.bot_turno_cerrar(t1, 'w4', '[]'::jsonb, null, 'booking', false); reset role;
  if j->>'avisar' <> 'booking' then raise exception 'PRUEBA FALLA: no subio a booking %', j; end if;
  set local role bot_lawang; j := public.bot_turno_cerrar(t1, 'wDESCONOCIDO', '[]'::jsonb); reset role;
  if j->>'error' <> 'wamid_desconocido' then raise exception 'PRUEBA FALLA: cerrar con wamid ajeno %', j; end if;
  v_ok := v_ok || 'estado, 4096 recortado, media {tipo,id}, cerrar idempotente, un aviso por nivel; ';

  -- aislamiento entre telefonos + historial de 20
  set local role bot_lawang; j := public.bot_mensaje_recibir(t2, 'x1', null, jsonb_build_object('texto', 'SECRETO-DE-T2')); reset role;
  insert into public.bot_mensaje (tel, rol, por, contenido) select t1, 'user', 'cliente', 'relleno ' || g from generate_series(1, 25) g;
  set local role bot_lawang; j := public.bot_turno_estado(t1); reset role;
  if jsonb_array_length(j->'historial') <> 20 or j::text like '%SECRETO-DE-T2%' then raise exception 'PRUEBA FALLA: historial %', jsonb_array_length(j->'historial'); end if;
  if (j->'historial'->0->>'ts')::bigint > (j->'historial'->19->>'ts')::bigint then raise exception 'PRUEBA FALLA: historial desordenado'; end if;
  v_ok := v_ok || 'historial = 20 ultimos y sin datos de otro telefono; ';

  -- ═══ C. PAUSA: un solo escritor ═══
  set local role bot_lawang; j := public.bot_pausar_humano(t1, 'pausar', 'ana@x'); reset role;
  if not (j->>'pausado')::boolean or j->'hasta' <> 'null'::jsonb then raise exception 'PRUEBA FALLA: pausar %', j; end if;
  set local role bot_lawang; j := public.bot_eco_operadora(t1, 'e1', 'hola desde el movil', 5); reset role;
  if (j->>'duplicado')::boolean or not (j->>'estaba_pausado')::boolean then raise exception 'PRUEBA FALLA: eco %', j; end if;
  if (select pausa_hasta from public.bot_chat where tel = t1) is not null then raise exception 'PRUEBA FALLA: una pausa manual se volvio caducable'; end if;
  set local role bot_lawang; j := public.bot_eco_operadora(t1, 'e1', 'hola desde el movil', 5); reset role;
  if not (j->>'duplicado')::boolean then raise exception 'PRUEBA FALLA: eco duplicado'; end if;
  if (select count(*) from public.bot_mensaje where tel = t1 and wamid = 'e1' and por = 'humano') <> 1 then raise exception 'PRUEBA FALLA: eco no guardado una vez'; end if;
  set local role bot_lawang; j := public.bot_pausar_humano(t1, 'quitar', 'ana@x'); reset role;
  set local role bot_lawang; j := public.bot_eco_operadora(t1, 'e2', 'otra', 5); reset role;
  if (j->>'estaba_pausado')::boolean then raise exception 'PRUEBA FALLA: estaba_pausado tras quitar'; end if;
  ts := (select pausa_hasta from public.bot_chat where tel = t1);
  if ts is null or ts < now() + interval '4 hours 59 minutes' or ts > now() + interval '5 hours 1 minute' then raise exception 'PRUEBA FALLA: pausa de 5 h %', ts; end if;
  update public.bot_chat set pausa_hasta = now() - interval '1 minute' where tel = t1;
  set local role bot_lawang; j := public.bot_turno_estado(t1); reset role;
  if (j->>'pausado')::boolean then raise exception 'PRUEBA FALLA: la pausa caducada sigue activa'; end if;
  update public.bot_config set pausa_horas = 2, actualizado_por = 'prueba@x';
  set local role bot_lawang; j := public.bot_pausar(t1, 'humano'); reset role;
  if (j->>'hasta')::timestamptz < now() + interval '1 hour 59 minutes' or (j->>'hasta')::timestamptz > now() + interval '2 hours 1 minute' then raise exception 'PRUEBA FALLA: la pausa no lee la config %', j; end if;
  set local role bot_lawang; j := public.bot_pausar(t2, 'humano', 99999); reset role;
  if (j->>'hasta')::timestamptz > now() + interval '720 hours 1 minute' then raise exception 'PRUEBA FALLA: horas sin tope'; end if;
  set local role bot_lawang; j := public.bot_pausar(t1, 'humano', 0); reset role;
  if j->'hasta' <> 'null'::jsonb or not (j->>'pausado')::boolean then raise exception 'PRUEBA FALLA: 0 horas = no caduca %', j; end if;
  set local role bot_lawang; j := public.bot_pausar_humano(t1, 'pausar', ''); reset role;
  if j->>'error' <> 'sin_usuario' then raise exception 'PRUEBA FALLA: pausar sin usuario %', j; end if;
  -- envio humano: registra, pausa, apaga «esperando»
  update public.bot_chat set pausado = false, pausa_hasta = null, esperando = true where tel = t1;
  set local role bot_lawang; j := public.bot_envio_humano(t1, 'respuesta de ana', 'h1', null, 'ana@x'); reset role;
  if not (select pausado from public.bot_chat where tel = t1) or (select esperando from public.bot_chat where tel = t1)
     or (select count(*) from public.bot_mensaje where tel = t1 and wamid = 'h1' and por_usuario = 'ana@x') <> 1 then raise exception 'PRUEBA FALLA: envio humano'; end if;
  v_ok := v_ok || 'pausa: manual no caducable, caduca al leer, hora de la config, tope 720; ';

  -- ═══ D. BAJA ═══
  set local role bot_lawang; j := public.bot_mensaje_recibir(t3, 's1', null, jsonb_build_object('texto', 'STOP')); reset role;
  set local role bot_lawang; j := public.bot_baja(t3, 's1'); reset role;
  if j->>'baja' <> 'nueva' or not (j->>'pausado')::boolean then raise exception 'PRUEBA FALLA: baja nueva %', j; end if;
  ts := (select baja_acuse_en from public.bot_chat where tel = t3);
  set local role bot_lawang; j := public.bot_baja(t3, 's2'); reset role;
  if j->>'baja' <> 'ya_dada' then raise exception 'PRUEBA FALLA: segunda baja %', j; end if;
  set local role bot_lawang; j := public.bot_baja(t3, 's1'); reset role;
  if j->>'baja' <> 'nueva' then raise exception 'PRUEBA FALLA: reintento de la misma baja %', j; end if;
  if (select baja_acuse_en from public.bot_chat where tel = t3) is distinct from ts then raise exception 'PRUEBA FALLA: segundo acuse'; end if;
  set local role bot_lawang; j := public.bot_pausar(t3, 'quitar'); j := public.bot_turno_estado(t3); reset role;
  if not (j->>'baja')::boolean then raise exception 'PRUEBA FALLA: quitar la pausa levanto la baja'; end if;
  set local role bot_lawang; j := public.bot_baja('99977700044', null); reset role;
  if j->>'baja' <> 'nueva' or not exists (select 1 from public.bot_chat where tel = '99977700044' and baja_en is not null) then raise exception 'PRUEBA FALLA: baja sin fila previa'; end if;
  v_ok := v_ok || 'baja: un acuse, reintento idempotente, sobrevive a quitar la pausa, se honra sin fila previa; ';

  -- ═══ E. ESCALACIONES ═══
  set local role bot_lawang;
  j := public.bot_escalar(t1, 'Uno', 'pregunta uno', 'wA'); a1 := null;
  j := public.bot_escalar(t2, 'Dos', 'pregunta dos', 'wB');
  j := public.bot_escalar(t2, 'Dos', 'pregunta dos otra vez', 'wB');
  reset role;
  if j->'id' <> 'null'::jsonb or (select count(*) from public.bot_escalacion) <> 2 then raise exception 'PRUEBA FALLA: aviso duplicado %', j; end if;
  set local role bot_lawang; j := public.bot_escalacion_tomar('wB'); reset role;
  if j->>'tel' <> t2 then raise exception 'PRUEBA FALLA: tomar citando %', j; end if;
  set local role bot_lawang; j := public.bot_escalacion_tomar(null); reset role;
  if j->>'tel' <> t1 then raise exception 'PRUEBA FALLA: tomar la mas antigua %', j; end if;
  set local role bot_lawang; j := public.bot_escalacion_tomar(null); reset role;
  if j <> '{}'::jsonb then raise exception 'PRUEBA FALLA: tomar sin pendientes %', j; end if;
  set local role bot_lawang; j := public.bot_escalar(t1, 'Uno', 'vieja', 'wOld'); reset role;
  update public.bot_escalacion set creada_en = now() - interval '8 days' where aviso_wamid = 'wOld';
  set local role bot_lawang; j := public.bot_escalacion_tomar(null); reset role;
  if j <> '{}'::jsonb then raise exception 'PRUEBA FALLA: tomo una de mas de 7 dias sin citarla'; end if;
  set local role bot_lawang; j := public.bot_escalacion_tomar('wOld'); reset role;
  if j->>'tel' <> t1 then raise exception 'PRUEBA FALLA: citando una vieja'; end if;
  set local role bot_lawang; j := public.bot_escalar('99977700077', 'X', 'p', null); reset role;
  if j->>'error' <> 'sin_chat' then raise exception 'PRUEBA FALLA: escalar sin chat'; end if;
  v_ok := v_ok || 'escalacion_tomar: por cita, por antiguedad, atomica, 7 dias; ';

  -- ═══ F. lead_id: solo lo fija bot_lead_upsert; varios leads = nulo ═══
  insert into public.leads (whatsapp, name, source) values ('+' || t1, 'Lead Uno', 'bot-whatsapp-lawang') returning id into l1;
  if (select lead_id from public.bot_chat where tel = t1) is not null then raise exception 'PRUEBA FALLA: lead_id se fijo solo'; end if;
  set local role bot_lawang; r := public.bot_lead_upsert(t1, null, 'bot-whatsapp-lawang', 'u1'); reset role;
  if r <> 'existente' or (select lead_id from public.bot_chat where tel = t1) is distinct from l1 then raise exception 'PRUEBA FALLA: upsert no enlazo (%)', r; end if;
  insert into public.leads (whatsapp, name, source) values ('+' || t2, 'Dos A', 'bot-whatsapp-lawang') returning id into l2;
  update public.bot_chat set lead_id = l2 where tel = t2;
  insert into public.leads (whatsapp, name, source) values ('+' || t2, 'Dos B', 'bot-whatsapp-lawang') returning id into l2b;
  set local role bot_lawang; r := public.bot_lead_upsert(t2, null, 'bot-whatsapp-lawang', 'u2'); reset role;
  if r <> 'ambiguo' or (select lead_id from public.bot_chat where tel = t2) is not null then raise exception 'PRUEBA FALLA: ambiguo debe dejar lead_id nulo (%)', r; end if;
  v_ok := v_ok || 'bot_lead_upsert enlaza lead_id y lo deja nulo si hay varios; ';

  -- ═══ G. RESUMEN a lead_notas ═══
  update public.bot_config set resumen_cada_n = 5, actualizado_por = 'prueba@x';
  set local role bot_lawang; j := public.bot_mensaje_recibir(t1, 'w9', null, jsonb_build_object('texto', 'mensaje nuevo')); reset role;
  set local role bot_lawang; j := public.bot_turno_cerrar(t1, 'w9', jsonb_build_array(jsonb_build_object('texto','ok')), null, null, false); reset role;
  mx := (select max(id) from public.bot_mensaje where tel = t1);
  if j->'resumir' = 'null'::jsonb or (j->'resumir'->>'hasta_id')::bigint <> mx or jsonb_array_length(j->'resumir'->'mensajes') > 60 then raise exception 'PRUEBA FALLA: debia pedir resumen %', left(j::text, 200); end if;
  id_otro := (select max(id) from public.bot_mensaje where tel = t2);
  set local role bot_lawang; r := public.bot_lead_resumen(t1, 'x', id_otro); reset role;
  if r <> 'hasta_invalido' then raise exception 'PRUEBA FALLA: hasta_id de otro telefono (%)', r; end if;
  set local role bot_lawang; r := public.bot_lead_resumen(t1, '<script>alert(1)</script> ' || repeat('r', 1500), mx); reset role;
  if r <> 'ok' or (select resumen_hasta_id from public.bot_chat where tel = t1) <> mx then raise exception 'PRUEBA FALLA: resumen (%)', r; end if;
  if (select length(texto) from public.lead_notas where lead_id = l1 and tipo = 'resumen_bot') <> 1200 or (select autor from public.lead_notas where lead_id = l1 and tipo = 'resumen_bot') <> 'bot' then raise exception 'PRUEBA FALLA: nota del resumen'; end if;
  set local role bot_lawang; r := public.bot_lead_resumen(t1, 'otra vez', mx); reset role;
  if r <> 'ya_hecho' or (select count(*) from public.lead_notas where lead_id = l1 and tipo = 'resumen_bot') <> 1 then raise exception 'PRUEBA FALLA: resumen duplicado (%)', r; end if;
  set local role bot_lawang; r := public.bot_lead_resumen(t2, 'texto', id_otro); reset role;
  if r <> 'sin_lead' then raise exception 'PRUEBA FALLA: resumen sin lead (%)', r; end if;
  -- tope diario: 6 por lead y dia
  update public.bot_chat set resumen_hasta_id = 0 where tel = t1;
  for n in 1..5 loop
    insert into public.bot_mensaje (tel, rol, por, contenido) values (t1, 'user', 'cliente', 'm' || n) returning id into mx2;
    set local role bot_lawang; r := public.bot_lead_resumen(t1, 'resumen ' || n, mx2); reset role;
    if r <> 'ok' then raise exception 'PRUEBA FALLA: resumen % (%)', n, r; end if;
  end loop;
  insert into public.bot_mensaje (tel, rol, por, contenido) values (t1, 'user', 'cliente', 'm7') returning id into mx2;
  set local role bot_lawang; r := public.bot_lead_resumen(t1, 'resumen 7', mx2); reset role;
  if r <> 'tope' then raise exception 'PRUEBA FALLA: sin tope diario (%)', r; end if;
  v_ok := v_ok || 'resumen: umbral, cursor, idempotente, 1200 caracteres, tope diario, sin lead; ';

  -- ═══ H. RECORDATORIO ═══
  declare ll uuid[]; k int; tt text; ac uuid[];
  begin
    for k in 1..6 loop
      tt := '9997770001' || k;
      insert into public.leads (whatsapp, name, source) values ('+' || tt, 'R' || k, 'bot-whatsapp-lawang') returning id into l1;
      ll := ll || l1;
      insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por, tipo, cuando_ts, estado, origen)
      values (l1, 'cita ' || k, current_date, 'x@x', 'x@x', case when k = 2 then 'visita' else 'llamada' end,
              case k when 3 then now() - interval '5 minutes' when 6 then now() + interval '61 minutes' else now() + interval '55 minutes' end,
              case k when 4 then 'propuesta' when 5 then 'cancelada' else 'confirmada' end, 'humano');
    end loop;
    -- el 5 («cancelada») debe tener completada_en para el indice de cita viva; da igual: ya esta excluido por estado
    set local role bot_lawang; select count(*), coalesce(bool_and(tel ~ '^9997770001[0-9]$'), false) into n, b from public.bot_citas_recordar(); reset role;
    if not b then raise exception 'PRUEBA FALLA: el telefono devuelto no son digitos sin +'; end if;
    if n <> 2 then raise exception 'PRUEBA FALLA: primera tanda esperaba 2 (llamada y visita confirmadas a 55 min), salieron %', n; end if;
    set local role bot_lawang; select count(*) into n from public.bot_citas_recordar(); reset role;
    if n <> 0 then raise exception 'PRUEBA FALLA: la segunda llamada reclamo otra vez (%)', n; end if;
    select id into a1 from public.lead_accion where lead_id = ll[1];
    -- sin resultado pasados 10 min: se reclama de nuevo, UNA vez
    update public.lead_accion set recordatorio_en = now() - interval '11 minutes' where id = a1;
    set local role bot_lawang; select count(*) into n from public.bot_citas_recordar(); reset role;
    if n <> 1 then raise exception 'PRUEBA FALLA: sin reclamo de reintento (%)', n; end if;
    update public.lead_accion set recordatorio_en = now() - interval '11 minutes' where id = a1;
    set local role bot_lawang; select count(*) into n from public.bot_citas_recordar(); reset role;
    if n <> 0 then raise exception 'PRUEBA FALLA: tercer reclamo (%)', n; end if;
    set local role bot_lawang; r := public.bot_cita_recordatorio_res(a1, 'enviado'); reset role;
    if r <> 'ok' then raise exception 'PRUEBA FALLA: resultado (%)', r; end if;
    set local role bot_lawang; r := public.bot_cita_recordatorio_res(a1, 'enviado'); reset role;
    if r <> 'no_aplica' then raise exception 'PRUEBA FALLA: resultado repetido (%)', r; end if;
    set local role bot_lawang; r := public.bot_cita_recordatorio_res(a1, 'otro'); reset role;
    if r <> 'resultado_invalido' then raise exception 'PRUEBA FALLA: resultado invalido (%)', r; end if;
    -- si la cita cambia de hora, vuelve a ser elegible
    update public.lead_accion set cuando_ts = now() + interval '40 minutes' where id = a1;
    if (select recordatorio_en from public.lead_accion where id = a1) is not null or (select recordatorio_intentos from public.lead_accion where id = a1) <> 0 then raise exception 'PRUEBA FALLA: el cambio de hora no reinicio el recordatorio'; end if;
    set local role bot_lawang; select count(*) into n from public.bot_citas_recordar(); reset role;
    if n <> 1 then raise exception 'PRUEBA FALLA: tras reprogramar (%)', n; end if;
    -- un telefono con baja no recibe recordatorio
    insert into public.leads (whatsapp, name, source) values ('+99977700018', 'Baja', 'bot-whatsapp-lawang') returning id into l1;
    insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por, tipo, cuando_ts, estado, origen)
    values (l1, 'cita baja', current_date, 'x@x', 'x@x', 'llamada', now() + interval '30 minutes', 'confirmada', 'humano');
    set local role bot_lawang; j := public.bot_baja('99977700018', null); select count(*) into n from public.bot_citas_recordar(); reset role;
    if n <> 0 then raise exception 'PRUEBA FALLA: recordatorio a un telefono con baja'; end if;
  end;
  v_ok := v_ok || 'recordatorio: solo confirmadas en la hora, una sola vez, reintento unico a los 10 min, reprogramar reinicia, la baja se respeta; ';

  -- ═══ I. permiso bot_conversaciones_ver + registro de lecturas ═══
  select user_id, email into v_super, v_super_em from public.usuarios where rol = 'super_admin' and ambito = 'global' and activo and coalesce(cardinality(empresas),0) = 0 order by user_id limit 1;
  select user_id, email into v_ag, v_ag_em from public.usuarios where rol = 'agente' and ambito = 'global' and activo and not ('bot_conversaciones_ver' = any (herramientas)) order by user_id limit 1;
  select user_id, email into v_ae, v_ae_em from public.usuarios where rol = 'admin_empresa' and ambito = 'empresa' and activo order by user_id limit 1;
  select user_id, email into v_sm, v_sm_em from public.usuarios where rol = 'sales_manager' and ambito = 'global' and activo and coalesce(cardinality(empresas),0) = 0 and not ('bot_conversaciones_ver' = any (herramientas)) order by user_id limit 1;
  if v_super is null or v_ag is null or v_ae is null or v_sm is null then raise exception 'PRUEBA FALLA: faltan perfiles de prueba'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_super, 'role', 'authenticated', 'email', v_super_em)::text, true);
  perform public._bot_conversaciones_autoriza(t1, 'hilo');
  perform public._bot_conversaciones_autoriza(null, 'lista');
  if (select count(*) from public.bot_lecturas_log where usuario = v_super_em) <> 2 or not exists (select 1 from public.bot_lecturas_log where usuario = v_super_em and tel = t1 and accion = 'hilo') then raise exception 'PRUEBA FALLA: lecturas sin registrar'; end if;
  foreach r in array array['agente','admin_empresa','sales_manager','anon'] loop
    perform set_config('request.jwt.claims', case r when 'agente' then json_build_object('sub', v_ag, 'role', 'authenticated', 'email', v_ag_em)::text
                                                     when 'admin_empresa' then json_build_object('sub', v_ae, 'role', 'authenticated', 'email', v_ae_em)::text
                                                     when 'sales_manager' then json_build_object('sub', v_sm, 'role', 'authenticated', 'email', v_sm_em)::text
                                                     else json_build_object('role', 'anon')::text end, true);
    begin perform public._bot_conversaciones_autoriza(t1, 'hilo'); raise exception 'PRUEBA FALLA: % leyo sin permiso', r;
    exception when insufficient_privilege then null; end;
  end loop;
  -- con la casilla: el de alcance restringido sigue sin poder (el bot mezcla las dos empresas); el de alcance global si
  perform set_config('request.jwt.claims', json_build_object('sub', v_super, 'role', 'authenticated', 'email', v_super_em)::text, true);
  update public.usuarios set herramientas = array_append(herramientas, 'bot_conversaciones_ver') where user_id in (v_ag, v_sm);
  perform set_config('request.jwt.claims', json_build_object('sub', v_ag, 'role', 'authenticated', 'email', v_ag_em)::text, true);
  begin perform public._bot_conversaciones_autoriza(t1, 'hilo'); raise exception 'PRUEBA FALLA: un agente de alcance restringido leyo con la casilla';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims', json_build_object('sub', v_sm, 'role', 'authenticated', 'email', v_sm_em)::text, true);
  perform public._bot_conversaciones_autoriza(t1, 'hilo');
  if not exists (select 1 from public.bot_lecturas_log where usuario = v_sm_em) then raise exception 'PRUEBA FALLA: con la casilla no se registro'; end if;
  perform set_config('request.jwt.claims', '', true);
  begin update public.bot_lecturas_log set usuario = 'z'; raise exception 'PRUEBA FALLA: se pudo editar el registro de lecturas';
  exception when insufficient_privilege then null; end;
  begin delete from public.bot_lecturas_log; raise exception 'PRUEBA FALLA: se pudo borrar el registro de lecturas';
  exception when insufficient_privilege then null; end;
  begin truncate public.bot_lecturas_log; raise exception 'PRUEBA FALLA: se pudo vaciar el registro de lecturas';
  exception when insufficient_privilege then null; end;
  perform set_config('bot.purga', 'on', true);
  delete from public.bot_lecturas_log where usuario = v_sm_em;
  perform set_config('bot.purga', 'off', true);
  v_ok := v_ok || 'bot_conversaciones_ver: super_admin y casilla global leen y quedan registrados; agente/admin_empresa/anon/restringido 42501; el registro solo lo borra la purga; ';

  -- ═══ J. borrar la conversacion arrastra sus mensajes y escalaciones ═══
  delete from public.bot_chat where tel = t1;
  if exists (select 1 from public.bot_mensaje where tel = t1) or exists (select 1 from public.bot_escalacion where tel = t1) then raise exception 'PRUEBA FALLA: la cascada dejo filas'; end if;
  v_ok := v_ok || 'borrar bot_chat arrastra bot_mensaje y bot_escalacion; ';

  raise exception 'PRUEBA OK: %', v_ok;
end $t$;
