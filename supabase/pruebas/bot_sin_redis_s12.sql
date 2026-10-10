-- Prueba de la migracion 20261010170000_bot_sin_redis_s12_consentimiento (S12 del encargo «bot de Lawang sin Redis», 10-oct-2026).
-- Se ejecuta con el MCP (execute_sql) o psql como postgres, DESPUES de aplicar la migracion. NO deja rastro: todo ocurre dentro de un DO que acaba
-- SIEMPRE en una excepcion (rollback). «PRUEBA OK ...» si todo va bien; «PRUEBA FALLA: ...» y dice cual si no.
-- Parte 1 (escenarios) como postgres: las funciones son DEFINER y bot_lawang no lee las tablas por diseno. Parte 2 (al final): las mismas llamadas con el ROL REAL. Telefonos CANARIO sinteticos 999777000xx: ningun mensaje real a nadie.
-- Dentro de una transaccion now() esta congelado: el envejecimiento se simula retrasando filas como postgres.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); los update/delete son sobre filas sembradas aqui mismo (telefonos canario).
do $t$
declare
  j jsonb; r text; n int; f text; rl text;
  t1 constant text := '99977700121'; t2 constant text := '99977700122'; t3 constant text := '99977700123'; t4 constant text := '99977700124';
  t5 constant text := '99977700125'; t6 constant text := '99977700126'; t7 constant text := '99977700127'; t8 constant text := '99977700128';
  t9 constant text := '99977700129'; t10 constant text := '99977700130'; t11 constant text := '99977700131';
  fns constant text[] := array['bot_consentimiento_preguntar(text,text,text,text,boolean)','bot_consentimiento_enviada(text,text,boolean)',
    'bot_consentimiento_responder(text,text,text,text)','bot_seguimiento_candidatos()','bot_seguimiento_reservar(text,text)',
    'bot_seguimiento_registrar(text,text,text,text,text)'];
  internas constant text[] := array['_bot_cs_norm(text)','_bot_cs_sin_cola(text)','_bot_cs_clase(text)','_bot_cs_debido(bot_chat)'];
begin
  -- A. CIERRE
  foreach f in array fns || internas || array['bot_baja(text,text)','bot_turno_estado(text,boolean)','_bot_olvidar_tel(text,boolean)','bot_purga()'] loop
    if not exists (select 1 from pg_proc p where p.oid = ('public.' || f)::regprocedure and p.proconfig::text like '%search_path=%') then raise exception 'PRUEBA FALLA: % sin search_path fijo', f; end if;
    if (select proacl from pg_proc where oid = ('public.' || f)::regprocedure) is null
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = ('public.' || f)::regprocedure and a.grantee = 0) then raise exception 'PRUEBA FALLA: % con PUBLIC o proacl nulo', f; end if;
    foreach rl in array array['anon','authenticated','service_role'] loop
      if has_function_privilege(rl, ('public.' || f)::regprocedure, 'execute') then raise exception 'PRUEBA FALLA: % ejecuta %', rl, f; end if;
    end loop;
  end loop;
  foreach f in array fns || array['bot_baja(text,text)','bot_turno_estado(text,boolean)'] loop
    if not has_function_privilege('bot_lawang', ('public.' || f)::regprocedure, 'execute') then raise exception 'PRUEBA FALLA: bot_lawang no ejecuta %', f; end if;
    if not (select prosecdef from pg_proc where oid = ('public.' || f)::regprocedure) then raise exception 'PRUEBA FALLA: % no es DEFINER', f; end if;
  end loop;
  foreach f in array internas || array['_bot_olvidar_tel(text,boolean)','bot_purga()'] loop
    if has_function_privilege('bot_lawang', ('public.' || f)::regprocedure, 'execute') then raise exception 'PRUEBA FALLA: bot_lawang ejecuta la interna %', f; end if;
  end loop;
  -- NINGUNA funcion que el bot puede llamar recibe un estado: el modelo no tiene por donde escribirlo
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
             and p.proname in ('bot_consentimiento_preguntar','bot_consentimiento_enviada','bot_consentimiento_responder','bot_seguimiento_reservar','bot_seguimiento_registrar')
             and array_to_string(coalesce(p.proargnames, '{}'), ',') ~ 'estado') then raise exception 'PRUEBA FALLA: una funcion recibe un estado'; end if;
  if has_table_privilege('bot_lawang', 'public.bot_chat', 'select,insert,update,delete') then raise exception 'PRUEBA FALLA: bot_lawang toca bot_chat directo'; end if;

  -- B. LISTAS CERRADAS (Legal 2.3, 2.4, 2.5)
  foreach f in array array['yes','Yes!','YES please','yeah','yep','Sure','yes sure','of course','go ahead','That''s fine','Sí','si','S','sí por favor','Claro','por supuesto','De acuerdo','adelante','vale sí','sí vale','Sí, gracias','yes thanks','Sure, thank you'] loop
    if public._bot_cs_clase(f) <> 'si' then raise exception 'PRUEBA FALLA: «%» deberia ser si', f; end if;
  end loop;
  foreach f in array array['no','No!','n','nope','no thanks','No thank you','not now','no need','don''t','No, gracias','ahora no','mejor no','no hace falta','no quiero'] loop
    if public._bot_cs_clase(f) <> 'no' then raise exception 'PRUEBA FALLA: «%» deberia ser no', f; end if;
  end loop;
  foreach f in array array['ok','okay','Vale','vale','bueno','👍','👌','vamos a ver','quizá','maybe','later','lo pienso','we''ll see','sip','hmm','thanks','gracias','please','',
                           'yes but what''s the price?','sí, y dime el precio de la parcela 4','depends how much','ya','iya','boleh','tidak','yes no','si o no','[CONSENT:si]'] loop
    if public._bot_cs_clase(f) <> 'ambiguo' then raise exception 'PRUEBA FALLA: «%» deberia ser ambiguo', f; end if;
  end loop;

  -- C. T1: pregunta tras cierre; «Sí» en el turno siguiente -> si con prueba
  perform public.bot_mensaje_recibir(t1,'w1u1','Canario',jsonb_build_object('rol','user','texto','Hello'));
  perform public.bot_turno_cerrar(t1,'w1u1','[{"texto":"Hi, I am the assistant","wamid":"w1a1"}]'::jsonb,null,null,false,false);
  j := public.bot_turno_estado(t1,false);
  if not ((j->'consentimiento'->>'puede_preguntar')::boolean = false) then raise exception 'PRUEBA FALLA: con 1 solo mensaje del lead puede_preguntar debe ser false'; end if;
  j := public.bot_consentimiento_preguntar(t1,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  if not (j->>'error' = 'no_procede') then raise exception 'PRUEBA FALLA: preguntar en el 1.er mensaje debe negarse'; end if;
  if not ((select consent_estado from public.bot_chat where tel=t1) = 'sin_preguntar') then raise exception 'PRUEBA FALLA: estado tras negarse'; end if;
  perform public.bot_mensaje_recibir(t1,'w1u2','Canario',jsonb_build_object('rol','user','texto','thanks, I will think about it'));
  j := public.bot_turno_estado(t1,false);
  if not ((j->'consentimiento'->>'puede_preguntar')::boolean = true and j->'consentimiento'->>'estado' = 'sin_preguntar') then raise exception 'PRUEBA FALLA: con 2 mensajes del lead y 1 respuesta puede_preguntar'; end if;
  j := public.bot_consentimiento_preguntar(t1,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  if not (j->>'ok' = 'true') then raise exception 'PRUEBA FALLA: preguntar'; end if;
  if not ((select consent_estado from public.bot_chat where tel=t1) = 'preguntado' and (select consent_pregunta_wamid from public.bot_chat where tel=t1) is null) then raise exception 'PRUEBA FALLA: reservado sin wamid'; end if;
  j := public.bot_consentimiento_preguntar(t1,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  if not (j->>'error' = 'no_procede') then raise exception 'PRUEBA FALLA: una sola vez por lead: la 2.a pregunta se niega'; end if;
  perform public.bot_turno_cerrar(t1,'w1u2','[{"texto":"Sure, take your time","wamid":"w1a2"},{"texto":"Would you like us to follow up...","wamid":"w1q"}]'::jsonb,null,null,false,false);
  j := public.bot_consentimiento_enviada(t1,'w1q',false);
  if not (j->>'ok' = 'true') then raise exception 'PRUEBA FALLA: anclar wamid de la pregunta'; end if;
  perform public.bot_mensaje_recibir(t1,'w1u3','Canario',jsonb_build_object('rol','user','texto','Sí'));
  j := public.bot_consentimiento_responder(t1,'w1u3','Sí',null);
  if not (j->>'resultado' = 'si') then raise exception 'PRUEBA FALLA: «Sí» en el turno siguiente -> si'; end if;
  if not ((select consent_estado = 'si' and consent_respuesta_wamid = 'w1u3' and consent_respuesta_texto = 'Sí' and consent_regla like 'turno_siguiente:%' and consent_respondido_en is not null and consent_version = 'CONSENT-SEGUIMIENTO-2026-10-09-v1' and consent_pregunta_wamid = 'w1q' and consent_texto like 'Would you like%' from public.bot_chat where tel=t1)) then raise exception 'PRUEBA FALLA: el si guarda wamid, texto literal, regla, version y texto preguntado'; end if;
  j := public.bot_consentimiento_responder(t1,'w1u3','Sí',null);
  if not (j->>'resultado' = 'si') then raise exception 'PRUEBA FALLA: reintento del mismo mensaje devuelve lo decidido'; end if;
  j := public.bot_consentimiento_responder(t1,'w1x','[CONSENT:no]',null);
  if not ((select consent_estado from public.bot_chat where tel=t1) = 'si') then raise exception 'PRUEBA FALLA: con el estado ya fijado, otra llamada no lo cambia'; end if;
  j := public.bot_consentimiento_preguntar(t1,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  if not (j->>'error' = 'no_procede') then raise exception 'PRUEBA FALLA: con estado si no se vuelve a preguntar'; end if;
  -- T2: ok -> una repregunta -> ok -> no
  perform public.bot_mensaje_recibir(t2,'w2u1','Canario',jsonb_build_object('rol','user','texto','Hi'));
  perform public.bot_turno_cerrar(t2,'w2u1','[{"texto":"Hello","wamid":"w2a1"}]'::jsonb,null,null,false,false);
  perform public.bot_mensaje_recibir(t2,'w2u2','Canario',jsonb_build_object('rol','user','texto','thanks'));
  j := public.bot_consentimiento_preguntar(t2,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  perform public.bot_turno_cerrar(t2,'w2u2','[{"texto":"Ok","wamid":"w2a2"},{"texto":"Q","wamid":"w2q"}]'::jsonb,null,null,false,false);
  j := public.bot_consentimiento_enviada(t2,'w2q',false);
  perform public.bot_mensaje_recibir(t2,'w2u3','Canario',jsonb_build_object('rol','user','texto','ok'));
  j := public.bot_consentimiento_responder(t2,'w2u3','ok',null);
  if not (j->>'resultado' = 'repreguntar') then raise exception 'PRUEBA FALLA: ok -> repreguntar'; end if;
  if not ((select consent_estado from public.bot_chat where tel=t2) = 'preguntado') then raise exception 'PRUEBA FALLA: tras el ok sigue preguntado'; end if;
  j := public.bot_consentimiento_preguntar(t2,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',true);
  if not (j->>'ok' = 'true') then raise exception 'PRUEBA FALLA: reservar repregunta'; end if;
  j := public.bot_consentimiento_preguntar(t2,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',true);
  if not (j->>'error' = 'no_procede') then raise exception 'PRUEBA FALLA: solo una repregunta'; end if;
  perform public.bot_turno_cerrar(t2,'w2u3','[{"texto":"Just to be sure","wamid":"w2r"}]'::jsonb,null,null,false,false);
  j := public.bot_consentimiento_enviada(t2,'w2r',true);
  if not (j->>'ok' = 'true') then raise exception 'PRUEBA FALLA: anclar repregunta'; end if;
  perform public.bot_mensaje_recibir(t2,'w2u4','Canario',jsonb_build_object('rol','user','texto','ok'));
  j := public.bot_consentimiento_responder(t2,'w2u4','ok',null);
  if not (j->>'resultado' = 'no') then raise exception 'PRUEBA FALLA: ok tras repregunta -> no'; end if;
  if not ((select consent_estado='no' and consent_regla='ambiguo_tras_repregunta' from public.bot_chat where tel=t2)) then raise exception 'PRUEBA FALLA: regla ambiguo_tras_repregunta'; end if;
  j := public.bot_consentimiento_preguntar(t2,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  if not (j->>'error' = 'no_procede') then raise exception 'PRUEBA FALLA: tras no no se pregunta mas'; end if;
  -- T3: maybe -> repregunta -> yes -> si
  perform public.bot_mensaje_recibir(t3,'w3u1','Canario',jsonb_build_object('rol','user','texto','Hi'));
  perform public.bot_turno_cerrar(t3,'w3u1','[{"texto":"Hello","wamid":"w3a1"}]'::jsonb,null,null,false,false);
  perform public.bot_mensaje_recibir(t3,'w3u2','Canario',jsonb_build_object('rol','user','texto','thanks'));
  j := public.bot_consentimiento_preguntar(t3,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  perform public.bot_turno_cerrar(t3,'w3u2','[{"texto":"Ok","wamid":"w3a2"},{"texto":"Q","wamid":"w3q"}]'::jsonb,null,null,false,false);
  j := public.bot_consentimiento_enviada(t3,'w3q',false);
  perform public.bot_mensaje_recibir(t3,'w3u3','Canario',jsonb_build_object('rol','user','texto','maybe'));
  j := public.bot_consentimiento_responder(t3,'w3u3','maybe',null);
  if not (j->>'resultado' = 'repreguntar') then raise exception 'PRUEBA FALLA: maybe -> repreguntar'; end if;
  j := public.bot_consentimiento_preguntar(t3,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',true);
  perform public.bot_turno_cerrar(t3,'w3u3','[{"texto":"R","wamid":"w3r"}]'::jsonb,null,null,false,false);
  j := public.bot_consentimiento_enviada(t3,'w3r',true);
  perform public.bot_mensaje_recibir(t3,'w3u4','Canario',jsonb_build_object('rol','user','texto','yes'));
  j := public.bot_consentimiento_responder(t3,'w3u4','yes',null);
  if not (j->>'resultado' = 'si') then raise exception 'PRUEBA FALLA: yes tras repregunta -> si'; end if;
  -- T4: si que CITA la pregunta con mensajes en medio -> si; sin cita no
  perform public.bot_mensaje_recibir(t4,'w4u1','Canario',jsonb_build_object('rol','user','texto','Hi'));
  perform public.bot_turno_cerrar(t4,'w4u1','[{"texto":"Hello","wamid":"w4a1"}]'::jsonb,null,null,false,false);
  perform public.bot_mensaje_recibir(t4,'w4u2','Canario',jsonb_build_object('rol','user','texto','thanks'));
  j := public.bot_consentimiento_preguntar(t4,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  perform public.bot_turno_cerrar(t4,'w4u2','[{"texto":"Ok","wamid":"w4a2"},{"texto":"Q","wamid":"w4q"}]'::jsonb,null,null,false,false);
  j := public.bot_consentimiento_enviada(t4,'w4q',false);
  perform public.bot_mensaje_recibir(t4,'w4u3','Canario',jsonb_build_object('rol','user','texto','what is the price of plot 4?'));
  perform public.bot_turno_cerrar(t4,'w4u3','[{"texto":"It is ...","wamid":"w4a3"}]'::jsonb,null,null,false,false);
  perform public.bot_mensaje_recibir(t4,'w4u4','Canario',jsonb_build_object('rol','user','texto','ok'));
  j := public.bot_consentimiento_responder(t4,'w4u4','ok',null);
  if not (j->>'resultado' = 'no_cuenta' and j->>'estado' = 'preguntado') then raise exception 'PRUEBA FALLA: ok tras otra respuesta del bot, sin cita, no cuenta'; end if;
  perform public.bot_mensaje_recibir(t4,'w4u5','Canario',jsonb_build_object('rol','user','texto','yes'));
  j := public.bot_consentimiento_responder(t4,'w4u5','yes',null);
  if not (j->>'resultado' = 'no_cuenta' and (select consent_estado from public.bot_chat where tel=t4) = 'preguntado') then raise exception 'PRUEBA FALLA: un yes sin cita fuera del turno siguiente no cuenta'; end if;
  perform public.bot_mensaje_recibir(t4,'w4u6','Canario',jsonb_build_object('rol','user','texto','yes'));
  j := public.bot_consentimiento_responder(t4,'w4u6','yes','w4q');
  if not (j->>'resultado' = 'si' and (select consent_regla like 'cita:%' and consent_respuesta_cita='w4q' from public.bot_chat where tel=t4)) then raise exception 'PRUEBA FALLA: yes que cita la pregunta -> si (regla cita)'; end if;
  -- T5: la operadora escribe entre la pregunta y el si -> no cuenta
  perform public.bot_mensaje_recibir(t5,'w5u1','Canario',jsonb_build_object('rol','user','texto','Hi'));
  perform public.bot_turno_cerrar(t5,'w5u1','[{"texto":"Hello","wamid":"w5a1"}]'::jsonb,null,null,false,false);
  perform public.bot_mensaje_recibir(t5,'w5u2','Canario',jsonb_build_object('rol','user','texto','thanks'));
  j := public.bot_consentimiento_preguntar(t5,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  perform public.bot_turno_cerrar(t5,'w5u2','[{"texto":"Ok","wamid":"w5a2"},{"texto":"Q","wamid":"w5q"}]'::jsonb,null,null,false,false);
  j := public.bot_consentimiento_enviada(t5,'w5q',false);
  perform public.bot_eco_operadora(t5,'w5echo','Hola, soy Ana',null);
  perform public.bot_mensaje_recibir(t5,'w5u3','Canario',jsonb_build_object('rol','user','texto','sí'));
  j := public.bot_consentimiento_responder(t5,'w5u3','sí',null);
  if not (j->>'resultado' = 'no_cuenta') then raise exception 'PRUEBA FALLA: con la operadora en medio un si no cuenta'; end if;
  -- T6: STOP a la pregunta -> revocado
  perform public.bot_mensaje_recibir(t6,'w6u1','Canario',jsonb_build_object('rol','user','texto','Hi'));
  perform public.bot_turno_cerrar(t6,'w6u1','[{"texto":"Hello","wamid":"w6a1"}]'::jsonb,null,null,false,false);
  perform public.bot_mensaje_recibir(t6,'w6u2','Canario',jsonb_build_object('rol','user','texto','thanks'));
  j := public.bot_consentimiento_preguntar(t6,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  perform public.bot_turno_cerrar(t6,'w6u2','[{"texto":"Ok","wamid":"w6a2"},{"texto":"Q","wamid":"w6q"}]'::jsonb,null,null,false,false);
  j := public.bot_consentimiento_enviada(t6,'w6q',false);
  perform public.bot_mensaje_recibir(t6,'w6u3','Canario',jsonb_build_object('rol','user','texto','STOP'));
  j := public.bot_baja(t6,'w6u3');
  if not (j->>'baja' = 'nueva') then raise exception 'PRUEBA FALLA: baja nueva'; end if;
  if not ((select consent_estado='revocado' and consent_revocado_en is not null and consent_revocado_wamid='w6u3' from public.bot_chat where tel=t6)) then raise exception 'PRUEBA FALLA: STOP revoca el consentimiento en la misma llamada'; end if;
  j := public.bot_consentimiento_responder(t6,'w6u3','yes','w6q');
  if not (j->>'resultado' = 'sin_efecto') then raise exception 'PRUEBA FALLA: con baja nada se registra'; end if;
  j := public.bot_consentimiento_preguntar(t6,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  if not (j->>'error' = 'no_procede') then raise exception 'PRUEBA FALLA: con baja no se pregunta'; end if;
  -- T7: reenganche 48h y 7d: solo con si vigente, max 2
  perform public.bot_mensaje_recibir(t7,'w7u1','Canario',jsonb_build_object('rol','user','texto','Hi'));
  perform public.bot_turno_cerrar(t7,'w7u1','[{"texto":"Hello","wamid":"w7a1"}]'::jsonb,null,null,false,false);
  perform public.bot_mensaje_recibir(t7,'w7u2','Canario',jsonb_build_object('rol','user','texto','thanks'));
  j := public.bot_consentimiento_preguntar(t7,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  perform public.bot_turno_cerrar(t7,'w7u2','[{"texto":"Ok","wamid":"w7a2"},{"texto":"Q","wamid":"w7q"}]'::jsonb,null,null,false,false);
  j := public.bot_consentimiento_enviada(t7,'w7q',false);
  perform public.bot_mensaje_recibir(t7,'w7u3','Canario',jsonb_build_object('rol','user','texto','si'));
  j := public.bot_consentimiento_responder(t7,'w7u3','si',null);
  perform public.bot_turno_cerrar(t7,'w7u3','[{"texto":"Noted","wamid":"w7a3"}]'::jsonb,null,null,false,false);
  select count(*) into n from public.bot_seguimiento_candidatos() where tel = t7;
  if not (n = 0) then raise exception 'PRUEBA FALLA: recien consentido no esta debido'; end if;
  update public.bot_mensaje set creado_en = creado_en - interval '49 hours' where tel = t7;
  update public.bot_chat set consent_respondido_en = now() - interval '49 hours' where tel = t7;
  select count(*) into n from public.bot_seguimiento_candidatos() where tel = t7 and plantilla = '48h' and idioma = 'en';
  if not (n = 1) then raise exception 'PRUEBA FALLA: a las 49 h toca 48h'; end if;
  j := public.bot_seguimiento_reservar(t7,'7d');
  if not (j->>'error' = 'no_procede') then raise exception 'PRUEBA FALLA: no se puede reservar la plantilla que no toca'; end if;
  j := public.bot_seguimiento_reservar(t7,'48h');
  if not (j->>'ok' = 'true' and j->>'idioma' = 'en') then raise exception 'PRUEBA FALLA: reservar 48h'; end if;
  j := public.bot_seguimiento_reservar(t7,'48h');
  if not (j->>'error' = 'no_procede') then raise exception 'PRUEBA FALLA: la reserva es de un solo uso (sin doble envio)'; end if;
  r := public.bot_seguimiento_registrar(t7,'48h','w7t48','enviado','Hi Ana');
  if not (r = 'ok') then raise exception 'PRUEBA FALLA: registrar 48h'; end if;
  r := public.bot_seguimiento_registrar(t7,'48h','w7t48','enviado','Hi Ana');
  if not (r = 'no_aplica') then raise exception 'PRUEBA FALLA: registrar dos veces no duplica'; end if;
  if not ((select count(*) from public.bot_mensaje where tel=t7 and wamid='w7t48') = 1) then raise exception 'PRUEBA FALLA: la plantilla queda en el hilo una vez'; end if;
  select count(*) into n from public.bot_seguimiento_candidatos() where tel = t7;
  if not (n = 0) then raise exception 'PRUEBA FALLA: tras el 48h no hay otro hasta el 7d'; end if;
  update public.bot_mensaje set creado_en = creado_en - interval '6 days' where tel = t7;
  update public.bot_chat set consent_ancla_en = consent_ancla_en - interval '6 days', consent_envio1_en = consent_envio1_en - interval '6 days', consent_respondido_en = now() - interval '6 days' where tel = t7;
  select count(*) into n from public.bot_seguimiento_candidatos() where tel = t7 and plantilla = '7d';
  if not (n = 1) then raise exception 'PRUEBA FALLA: a los 7 d toca 7d (el 48h guardado en el hilo NO mueve el ancla)'; end if;
  j := public.bot_seguimiento_reservar(t7,'7d');
  if not (j->>'ok' = 'true') then raise exception 'PRUEBA FALLA: reservar 7d'; end if;
  r := public.bot_seguimiento_registrar(t7,'7d','w7t7','enviado','Hi Ana');
  if not (r = 'ok' and (select consent_estado from public.bot_chat where tel=t7) = 'usado') then raise exception 'PRUEBA FALLA: el 7d agota el consentimiento'; end if;
  select count(*) into n from public.bot_seguimiento_candidatos() where tel = t7;
  if not (n = 0) then raise exception 'PRUEBA FALLA: tras 2 envios, ninguno mas'; end if;
  j := public.bot_seguimiento_reservar(t7,'48h');
  if not (j->>'error' = 'no_procede') then raise exception 'PRUEBA FALLA: no hay tercer envio'; end if;
  -- T8: el lead contesta tras el 48h -> no hay 7d
  perform public.bot_mensaje_recibir(t8,'w8u1','Canario',jsonb_build_object('rol','user','texto','Hi'));
  perform public.bot_turno_cerrar(t8,'w8u1','[{"texto":"Hello","wamid":"w8a1"}]'::jsonb,null,null,false,false);
  perform public.bot_mensaje_recibir(t8,'w8u2','Canario',jsonb_build_object('rol','user','texto','thanks'));
  j := public.bot_consentimiento_preguntar(t8,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  perform public.bot_turno_cerrar(t8,'w8u2','[{"texto":"Ok","wamid":"w8a2"},{"texto":"Q","wamid":"w8q"}]'::jsonb,null,null,false,false);
  j := public.bot_consentimiento_enviada(t8,'w8q',false);
  perform public.bot_mensaje_recibir(t8,'w8u3','Canario',jsonb_build_object('rol','user','texto','si'));
  j := public.bot_consentimiento_responder(t8,'w8u3','si',null);
  perform public.bot_turno_cerrar(t8,'w8u3','[{"texto":"Noted","wamid":"w8a3"}]'::jsonb,null,null,false,false);
  update public.bot_mensaje set creado_en = creado_en - interval '49 hours' where tel = t8;
  update public.bot_chat set consent_respondido_en = now() - interval '49 hours' where tel = t8;
  j := public.bot_seguimiento_reservar(t8,'48h');
  if not (j->>'ok' = 'true') then raise exception 'PRUEBA FALLA: t8 reserva 48h'; end if;
  r := public.bot_seguimiento_registrar(t8,'48h','w8t48','enviado','x');
  perform public.bot_mensaje_recibir(t8,'w8u9','Canario',jsonb_build_object('rol','user','texto','hello again'));
  update public.bot_mensaje set creado_en = creado_en - interval '6 days' where tel = t8 and wamid <> 'w8u9';
  update public.bot_chat set consent_ancla_en = consent_ancla_en - interval '6 days', consent_envio1_en = consent_envio1_en - interval '6 days', consent_respondido_en = now() - interval '6 days' where tel = t8;
  select count(*) into n from public.bot_seguimiento_candidatos() where tel = t8;
  if not (n = 0) then raise exception 'PRUEBA FALLA: si el lead respondio no sale el 7d'; end if;
  if not ((select consent_estado from public.bot_chat where tel=t8) = 'usado') then raise exception 'PRUEBA FALLA: el consentimiento se da por usado'; end if;
  j := public.bot_seguimiento_reservar(t8,'7d');
  if not (j->>'error' = 'no_procede') then raise exception 'PRUEBA FALLA: reservar el 7d tras respuesta se niega'; end if;
  -- T9: STOP entre la lista y el envio gana
  perform public.bot_mensaje_recibir(t9,'w9u1','Canario',jsonb_build_object('rol','user','texto','Hi'));
  perform public.bot_turno_cerrar(t9,'w9u1','[{"texto":"Hello","wamid":"w9a1"}]'::jsonb,null,null,false,false);
  perform public.bot_mensaje_recibir(t9,'w9u2','Canario',jsonb_build_object('rol','user','texto','thanks'));
  j := public.bot_consentimiento_preguntar(t9,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  perform public.bot_turno_cerrar(t9,'w9u2','[{"texto":"Ok","wamid":"w9a2"},{"texto":"Q","wamid":"w9q"}]'::jsonb,null,null,false,false);
  j := public.bot_consentimiento_enviada(t9,'w9q',false);
  perform public.bot_mensaje_recibir(t9,'w9u3','Canario',jsonb_build_object('rol','user','texto','si'));
  j := public.bot_consentimiento_responder(t9,'w9u3','si',null);
  perform public.bot_turno_cerrar(t9,'w9u3','[{"texto":"Noted","wamid":"w9a3"}]'::jsonb,null,null,false,false);
  update public.bot_mensaje set creado_en = creado_en - interval '49 hours' where tel = t9;
  update public.bot_chat set consent_respondido_en = now() - interval '49 hours' where tel = t9;
  select count(*) into n from public.bot_seguimiento_candidatos() where tel = t9;
  if not (n = 1) then raise exception 'PRUEBA FALLA: t9 esta en la lista'; end if;
  j := public.bot_baja(t9,'w9stop');
  j := public.bot_seguimiento_reservar(t9,'48h');
  if not (j->>'error' = 'no_procede') then raise exception 'PRUEBA FALLA: STOP entre la lista y el envio: no sale'; end if;
  -- T10: la operadora interviene -> no hay seguimiento; pausa tambien
  perform public.bot_mensaje_recibir(t10,'w10u1','Canario',jsonb_build_object('rol','user','texto','Hi'));
  perform public.bot_turno_cerrar(t10,'w10u1','[{"texto":"Hello","wamid":"w10a1"}]'::jsonb,null,null,false,false);
  perform public.bot_mensaje_recibir(t10,'w10u2','Canario',jsonb_build_object('rol','user','texto','thanks'));
  j := public.bot_consentimiento_preguntar(t10,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  perform public.bot_turno_cerrar(t10,'w10u2','[{"texto":"Ok","wamid":"w10a2"},{"texto":"Q","wamid":"w10q"}]'::jsonb,null,null,false,false);
  j := public.bot_consentimiento_enviada(t10,'w10q',false);
  perform public.bot_mensaje_recibir(t10,'w10u3','Canario',jsonb_build_object('rol','user','texto','si'));
  j := public.bot_consentimiento_responder(t10,'w10u3','si',null);
  perform public.bot_turno_cerrar(t10,'w10u3','[{"texto":"Noted","wamid":"w10a3"}]'::jsonb,null,null,false,false);
  update public.bot_mensaje set creado_en = creado_en - interval '49 hours' where tel = t10;
  update public.bot_chat set consent_respondido_en = now() - interval '49 hours' where tel = t10;
  perform public.bot_eco_operadora(t10,'w10echo','Hola',null);
  select count(*) into n from public.bot_seguimiento_candidatos() where tel = t10;
  if not (n = 0) then raise exception 'PRUEBA FALLA: tras intervencion de la operadora no hay seguimiento'; end if;
  perform public.bot_mensaje_recibir(t11,'w11u1','Canario',jsonb_build_object('rol','user','texto','Hi'));
  perform public.bot_turno_cerrar(t11,'w11u1','[{"texto":"Hello","wamid":"w11a1"}]'::jsonb,null,null,false,false);
  perform public.bot_mensaje_recibir(t11,'w11u2','Canario',jsonb_build_object('rol','user','texto','thanks'));
  j := public.bot_consentimiento_preguntar(t11,'CONSENT-SEGUIMIENTO-2026-10-09-v1','en','Would you like us to follow up here on WhatsApp? Please reply YES or NO. lawangproperties.com/legal#privacy',false);
  perform public.bot_turno_cerrar(t11,'w11u2','[{"texto":"Ok","wamid":"w11a2"},{"texto":"Q","wamid":"w11q"}]'::jsonb,null,null,false,false);
  j := public.bot_consentimiento_enviada(t11,'w11q',false);
  perform public.bot_mensaje_recibir(t11,'w11u3','Canario',jsonb_build_object('rol','user','texto','si'));
  j := public.bot_consentimiento_responder(t11,'w11u3','si',null);
  perform public.bot_turno_cerrar(t11,'w11u3','[{"texto":"Noted","wamid":"w11a3"}]'::jsonb,null,null,false,false);
  update public.bot_mensaje set creado_en = creado_en - interval '49 hours' where tel = t11;
  update public.bot_chat set consent_respondido_en = now() - interval '49 hours' where tel = t11;
  perform public.bot_pausar(t11,'humano',2);
  j := public.bot_seguimiento_reservar(t11,'48h');
  if not (j->>'error' = 'no_procede') then raise exception 'PRUEBA FALLA: con el chat pausado no sale'; end if;
  -- T11: caduca a los 30 dias; sin consentimiento nunca
  update public.bot_mensaje set creado_en = creado_en - interval '40 days' where tel = t4;
  update public.bot_chat set consent_respondido_en = now() - interval '40 days' where tel = t4;
  select count(*) into n from public.bot_seguimiento_candidatos() where tel = t4;
  if not (n = 0) then raise exception 'PRUEBA FALLA: consentimiento de hace 40 dias no sale'; end if;
  if not ((select consent_estado from public.bot_chat where tel=t4) = 'caducado') then raise exception 'PRUEBA FALLA: queda caducado'; end if;
  select count(*) into n from public.bot_seguimiento_candidatos() where tel in (t2,t5,t6);
  if not (n = 0) then raise exception 'PRUEBA FALLA: no, preguntado sin respuesta, o revocado: nunca'; end if;
  -- D. OLVIDO Y PURGA
  j := public._bot_olvidar_tel(t1, true);
  if not ((select consent_estado='revocado' and consent_texto is null and consent_respuesta_texto is null and consent_repregunta_texto is null and consent_respuesta_wamid='w1u3' and consent_pregunta_wamid='w1q' and consent_version is not null and baja_en is not null from public.bot_chat where tel=t1)) then raise exception 'PRUEBA FALLA: olvidar vacia textos y conserva estado, version y wamids'; end if;
  if not (not exists (select 1 from public.bot_mensaje where tel=t1)) then raise exception 'PRUEBA FALLA: olvidar borra el hilo'; end if;
  update public.bot_chat set actividad_en = now() - interval '400 days' where tel in (t1, t2, t6);
  j := public.bot_purga();
  if not (exists (select 1 from public.bot_chat where tel=t1 and consent_estado='revocado') and exists (select 1 from public.bot_chat where tel=t6 and consent_estado='revocado' and baja_en is not null)) then raise exception 'PRUEBA FALLA: la purga conserva la marca revocado (sin plazo)'; end if;
  if not ((select consent_texto is null and consent_respuesta_texto is null and consent_repregunta_texto is null from public.bot_chat where tel=t6)) then raise exception 'PRUEBA FALLA: la purga vacia los textos al reducir a la marca'; end if;
  if not (not exists (select 1 from public.bot_chat where tel=t2)) then raise exception 'PRUEBA FALLA: la purga borra al inactivo sin marca (estado no)'; end if;

  raise exception 'PRUEBA OK parte 1: cierre de las funciones nuevas y sustituidas, listas cerradas, preguntar solo tras cierre y una vez, si/no con prueba, repregunta unica, cita vs turno siguiente, operadora, STOP, reenganche 48h/7d (max 2, nunca tras respuesta/operadora/pausa/STOP, caduca a 30 d), olvido y purga';
end $t$;
