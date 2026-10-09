-- Prueba de 20261010135000_bot_sin_redis_s5_importar (S5, 9-oct-2026). Se ejecuta como postgres DESPUES de aplicar la migracion.
-- NO deja rastro: un DO que acaba SIEMPRE en excepcion (rollback). «PRUEBA OK: ...» si todo va bien.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback).
do $t$
declare
  v_ok text := ''; v_tok bigint; f text; rl text; j jsonb; n int; h2 text; v_super uuid;
  t constant text := '99990000077';
  now_ms constant bigint := floor(extract(epoch from now()) * 1000)::bigint;
  p jsonb;
  publicas constant text[] := array['bot_importar_chat(jsonb)','bot_importar_cuadre(text)','bot_importar_config(jsonb)','_bot_importar_ms(bigint)'];
begin
  -- A. cierre
  foreach f in array publicas loop
    if not (select prosecdef from pg_proc where oid = ('public.' || f)::regprocedure) then raise exception 'PRUEBA FALLA: % no es DEFINER', f; end if;
    if not exists (select 1 from pg_proc p where p.oid = ('public.' || f)::regprocedure and p.proconfig::text like '%search_path=%') then raise exception 'PRUEBA FALLA: % sin search_path', f; end if;
    if exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = ('public.' || f)::regprocedure and a.grantee = 0) then raise exception 'PRUEBA FALLA: % con PUBLIC', f; end if;
    foreach rl in array array['anon','authenticated','service_role'] loop
      if has_function_privilege(rl, ('public.' || f)::regprocedure, 'execute') then raise exception 'PRUEBA FALLA: % ejecuta %', rl, f; end if;
    end loop;
    if f <> '_bot_importar_ms(bigint)' and not has_function_privilege('bot_lawang', ('public.' || f)::regprocedure, 'execute') then raise exception 'PRUEBA FALLA: bot_lawang no ejecuta %', f; end if;
  end loop;
  v_ok := v_ok || 'cierre (DEFINER, search_path, sin PUBLIC, solo bot_lawang); ';

  -- B. primera importacion con el rol real
  p := jsonb_build_object('tel', t, 'chat', jsonb_build_object(
         'nombre_perfil', 'Prueba', 'intent', 'interested', 'ultimo_mensaje', 'hasta luego', 'ultimo_por', 'humano',
         'creado_ms', now_ms - 900000, 'actualizado_ms', now_ms - 60000, 'archivado', false, 'ultimo_entrante_ms', now_ms - 120000,
         'esperando', true, 'pausado', true, 'pausa_hasta_ms', now_ms + 3600000, 'baja_ms', null, 'baja_acuse', false,
         'seguimientos', 2, 'aviso_nivel', 2, 'aviso_testing', true),
       'mensajes', jsonb_build_array(
         jsonb_build_object('rol','user','por','cliente','contenido','Hola','ts_ms', now_ms - 300000,'wamid','wamid.PRUEBA1'),
         jsonb_build_object('rol','assistant','por','bot','contenido','Hi!','ts_ms', now_ms - 290000),
         jsonb_build_object('rol','assistant','por','humano','por_usuario','ana@x.com','contenido','te llamo','ts_ms', now_ms - 60000,
                            'media', jsonb_build_object('tipo','image','id','MID1'))),
       'escalaciones', jsonb_build_array(jsonb_build_object('nombre','Ana','pregunta','¿precio?','aviso_wamid','wamid.AVISO77','creada_ms', now_ms - 1000)));
  set local role bot_lawang;
  j := public.bot_importar_chat(p);
  reset role;
  if not (j->>'ok')::boolean or j->>'chat' <> 'creado' then raise exception 'PRUEBA FALLA: primera importacion %', j; end if;
  if (j->'mensajes'->>'insertados')::int <> 3 or (j->'escalaciones'->>'insertadas')::int <> 1 then raise exception 'PRUEBA FALLA: conteos 1.a %', j; end if;
  if not exists (select 1 from public.bot_chat where tel = t and pausado and pausa_hasta > now() and aviso_nivel = 2 and seguimientos = 2
                    and esperando and aviso_testing_en is not null and baja_en is null and ultimo_por = 'humano') then raise exception 'PRUEBA FALLA: estado del chat'; end if;
  if (select actividad_en from public.bot_chat where tel = t) > now() - interval '30 seconds' then raise exception 'PRUEBA FALLA: actividad_en se reinicio a now()'; end if;
  if exists (select 1 from public.bot_mensaje where tel = t and ts_origen is null) then raise exception 'PRUEBA FALLA: ts_origen nulo'; end if;
  if (select media from public.bot_mensaje where tel = t and por = 'humano') is distinct from '{"tipo":"image","id":"MID1"}'::jsonb then raise exception 'PRUEBA FALLA: media'; end if;
  v_ok := v_ok || '1.a importacion (estado, actividad real, media solo tipo+id); ';

  -- C. repetible
  set local role bot_lawang;
  j := public.bot_importar_chat(p);
  reset role;
  if (j->'mensajes'->>'insertados')::int <> 0 or (j->'escalaciones'->>'insertadas')::int <> 0 or j->>'chat' <> 'actualizado' then raise exception 'PRUEBA FALLA: 2.a pasada duplica %', j; end if;
  select count(*) into n from public.bot_mensaje where tel = t;
  if n <> 3 then raise exception 'PRUEBA FALLA: % mensajes tras 2 pasadas', n; end if;
  if (select count(*) from public.bot_escalacion where tel = t) <> 1 then raise exception 'PRUEBA FALLA: escalaciones duplicadas'; end if;
  v_ok := v_ok || 'repetible (3 mensajes, 1 escalacion tras 2 pasadas); ';

  -- D. cuadre: md5 con la formula de import_redis.js (digestMensajes)
  set local role bot_lawang;
  j := public.bot_importar_cuadre(t);
  reset role;
  select md5(string_agg(m.rol || chr(1) || m.por || chr(1) || (floor(extract(epoch from m.ts_origen) * 1000)::bigint)::text || chr(1) || m.contenido, chr(2) order by m.ts_origen, m.id))
    into h2 from public.bot_mensaje m where m.tel = t;
  if (j->>'n_mensajes')::int <> 3 or j->>'hash_mensajes' <> h2 or not (j->>'existe')::boolean then raise exception 'PRUEBA FALLA: cuadre %', j; end if;
  if not exists (select 1 from public.bot_mensaje where tel = t and floor(extract(epoch from ts_origen) * 1000)::bigint = now_ms - 300000) then raise exception 'PRUEBA FALLA: el ms de ts_origen no es exacto'; end if;
  v_ok := v_ok || 'cuadre (n, md5, ms exacto); ';

  -- E. SOLO AÑADE RESTRICCIONES
  p := p - 'mensajes' - 'escalaciones';
  p := jsonb_set(p, '{chat,seguimientos}', '0'::jsonb);
  p := jsonb_set(p, '{chat,aviso_nivel}', '0'::jsonb);
  p := jsonb_set(p, '{chat,pausado}', 'true'::jsonb);
  p := jsonb_set(p, '{chat,pausa_hasta_ms}', to_jsonb(now_ms + 60000));
  set local role bot_lawang; perform public.bot_importar_chat(p); reset role;
  if (select pausa_hasta from public.bot_chat where tel = t) < now() + interval '50 minutes' then raise exception 'PRUEBA FALLA: una pausa mas corta acorto la existente'; end if;
  if (select aviso_nivel from public.bot_chat where tel = t) <> 2 or (select seguimientos from public.bot_chat where tel = t) <> 2 then raise exception 'PRUEBA FALLA: bajaron aviso/seguimientos'; end if;
  p := jsonb_set(p, '{chat,pausa_hasta_ms}', 'null'::jsonb);
  set local role bot_lawang; perform public.bot_importar_chat(p); reset role;
  if (select pausa_hasta from public.bot_chat where tel = t) is not null then raise exception 'PRUEBA FALLA: la pausa sin caducidad no gano'; end if;
  p := jsonb_set(p, '{chat,baja_ms}', to_jsonb(now_ms - 5000));
  p := jsonb_set(p, '{chat,baja_acuse}', 'true'::jsonb);
  set local role bot_lawang; perform public.bot_importar_chat(p); reset role;
  if not exists (select 1 from public.bot_chat where tel = t and baja_en is not null and baja_acuse_en is not null and pausado and pausa_hasta is null and pausa_por = 'baja') then
    raise exception 'PRUEBA FALLA: la baja no dejo pausa sin caducidad'; end if;
  p := jsonb_set(p, '{chat,baja_ms}', 'null'::jsonb);
  p := jsonb_set(p, '{chat,pausado}', 'false'::jsonb);
  set local role bot_lawang; perform public.bot_importar_chat(p); reset role;
  if not exists (select 1 from public.bot_chat where tel = t and baja_en is not null and pausado and pausa_hasta is null) then raise exception 'PRUEBA FALLA: un lote sin baja quito la baja o la pausa'; end if;
  v_ok := v_ok || 'solo añade restricciones (pausa mas corta no acorta, sin caducidad gana, baja no se quita); ';

  -- F. mensajes posteriores
  insert into public.bot_mensaje (tel, rol, por, contenido, creado_en, ts_origen) values (t, 'user', 'cliente', 'vivo', now(), now());
  p := jsonb_build_object('tel', t, 'chat', p->'chat', 'mensajes', jsonb_build_array(jsonb_build_object('rol','user','por','cliente','contenido','viejo nuevo','ts_ms', now_ms - 700000)), 'escalaciones', '[]'::jsonb);
  set local role bot_lawang; j := public.bot_importar_chat(p); reset role;
  if not (j->'mensajes'->>'omitidos_posteriores')::boolean or (j->'mensajes'->>'insertados')::int <> 0 then raise exception 'PRUEBA FALLA: debia omitir mensajes %', j; end if;
  if not exists (select 1 from public.bot_chat where tel = t and baja_en is not null) then raise exception 'PRUEBA FALLA: omitir mensajes tambien omitio el estado'; end if;
  v_ok := v_ok || 'mensajes posteriores omitidos sin perder el estado; ';

  -- G. entradas hostiles
  set local role bot_lawang;
  if (public.bot_importar_chat('{"tel":"abc","chat":{}}'::jsonb)->>'error') <> 'telefono_invalido' then raise exception 'PRUEBA FALLA: telefono invalido'; end if;
  if (public.bot_importar_chat('{"tel":"99990000078"}'::jsonb)->>'error') <> 'forma' then raise exception 'PRUEBA FALLA: forma'; end if;
  j := public.bot_importar_chat(jsonb_build_object('tel','99990000078','chat','{"ultimo_por":"hacker","seguimientos":99999}'::jsonb,
         'mensajes', jsonb_build_array(jsonb_build_object('rol','x','por','y','contenido', repeat('a', 9000) || E'\x07','ts_ms','basura','media', jsonb_build_object('tipo','a','id','b','url','http://x')))));
  reset role;
  if not (j->>'ok')::boolean then raise exception 'PRUEBA FALLA: hostil %', j; end if;
  if (select length(contenido) from public.bot_mensaje where tel = '99990000078') <> 4096 then raise exception 'PRUEBA FALLA: contenido sin tope'; end if;
  if exists (select 1 from public.bot_chat where tel = '99990000078' and (ultimo_por is not null or seguimientos > 1000)) then raise exception 'PRUEBA FALLA: campos sin sanear'; end if;
  if (select por from public.bot_mensaje where tel = '99990000078') <> 'bot' then raise exception 'PRUEBA FALLA: por inventado'; end if;
  v_ok := v_ok || 'entradas hostiles saneadas; ';

  -- H. config: una vez, en snake_case, y «volver» funciona despues
  if (select count(*) from public.bot_config_log) = 0 and (select version from public.bot_config) = 1 then
    set local role bot_lawang;
    j := public.bot_importar_config(jsonb_build_object('config', jsonb_build_object('extra','nuevo','bienvenida','hola','pausa_horas',12,'updated_by','a@b.c'),
          'log', jsonb_build_array(
            jsonb_build_object('ts_ms', now_ms - 20000, 'by', 'z', 'prev', jsonb_build_object('extra','','bienvenida','','pausa_horas',0), 'next', jsonb_build_object('extra','v1','bienvenida','','pausa_horas',0)),
            jsonb_build_object('ts_ms', now_ms - 10000, 'by', 'a@b.c', 'prev', jsonb_build_object('extra','v1','bienvenida','','pausa_horas',0), 'next', jsonb_build_object('extra','nuevo','bienvenida','hola','pausa_horas',12)))));
    reset role;
    if j->>'resultado' <> 'importada' then raise exception 'PRUEBA FALLA: config %', j; end if;
    if (select count(*) from public.bot_config_log) <> 2 then raise exception 'PRUEBA FALLA: el trigger sumo una fila de log durante la importacion'; end if;
    if not exists (select 1 from public.bot_config where extra = 'nuevo' and bienvenida = 'hola' and pausa_horas = 12) then raise exception 'PRUEBA FALLA: valores de config'; end if;
    if (select prev->>'pausa_horas' from public.bot_config_log order by id desc limit 1) <> '0' then raise exception 'PRUEBA FALLA: el log no esta en snake_case'; end if;
    set local role bot_lawang; j := public.bot_importar_config(jsonb_build_object('config', jsonb_build_object('extra','otra','bienvenida','','pausa_horas',0), 'log', '[]'::jsonb)); reset role;
    if j->>'resultado' <> 'ya_configurada' or (select extra from public.bot_config) <> 'nuevo' then raise exception 'PRUEBA FALLA: se pudo importar dos veces'; end if;
    select user_id into v_super from public.usuarios where rol = 'super_admin' and activo and ambito = 'global' and coalesce(cardinality(empresas),0) = 0 limit 1;
    if v_super is not null then
      select floor(extract(epoch from actualizado_en) * 1000)::bigint into v_tok from public.bot_config;
      set local role service_role;
      j := public.crm_bot_config_volver(v_super, v_tok, 'prueba');
      reset role;
      if not (j ? 'ok') or (select extra from public.bot_config) <> 'v1' then raise exception 'PRUEBA FALLA: «volver» tras importar %', j; end if;
      v_ok := v_ok || 'config (una vez, snake_case, log sin fila extra, «volver» funciona); ';
    end if;
  else
    v_ok := v_ok || '(config ya editada: parte H omitida); ';
  end if;

  -- I. lead_id
  insert into public.leads (whatsapp, name, source) values ('+99990000079', 'Lead prueba', 'bot-whatsapp-lawang');
  set local role bot_lawang;
  j := public.bot_importar_chat(jsonb_build_object('tel','99990000079','chat','{}'::jsonb));
  reset role;
  if j->>'lead' <> 'enlazado' or (select lead_id from public.bot_chat where tel = '99990000079') is null then raise exception 'PRUEBA FALLA: lead_id %', j; end if;
  v_ok := v_ok || 'lead_id enlazado; ';

  raise exception 'PRUEBA OK: %', v_ok;
end $t$;
