-- prueba_aviso_anulacion_cola.sql — AXW-202 C3: lo que añade la migración 20261005030144 (interruptor del aviso de anulación, la RPC que lo
-- encola y la rama `aviso_anulacion_sin_enviar` de auditoria_firmas()) PROBADO POR PERFIL. Se lanza con el MCP supabase-lawang
-- (execute_sql) o psql. El MCP corre como `postgres` y no prueba permisos por sí mismo: cada perfil va con `set local role` + claims.
-- TODO ocurre en una transacción que SIEMPRE se deshace (el DO acaba en `raise exception 'RESULTADO: ...'`): no queda ninguna fila ni se
-- manda ningún correo (el despertador por pg_net solo sale al confirmar la transacción, y esta nunca se confirma).
-- Empieza por «RESULTADO: OK» si todo pasó; cada «FALLA» dice qué.
do $t$
declare
  res   text := '';
  total int  := 0;
  v_c   uuid;
  f_viejo uuid; f_nuevo uuid; f_rol1 uuid; f_rol2 uuid; f_err uuid; f_atasc uuid; f_ok uuid;
  u_super uuid; u_agente uuid;
  n0 int; n int; v text; fid uuid;
  r jsonb;
  perfil record;
  cmd text;
  t timestamptz;
begin
  set local session_replication_role = replica;

  select c.id into v_c from public.contratos c where c.liberado_en is null and not coalesce(c.bloqueado, false) limit 1;
  select u.user_id into u_super  from public.usuarios u where u.activo and u.rol = 'super_admin' limit 1;
  select u.user_id into u_agente from public.usuarios u where u.activo and u.rol = 'agente' limit 1;

  -- ══ 1. el interruptor: existe, nace en «directo», y nadie salvo service_role/postgres lo toca ═════════════
  select valor #>> '{}' into v from public.config_instancia where clave = 'correo_cola_aviso_anulacion';
  total := total + 1; res := res || case when v in ('directo', 'cola') then '' else E'\nFALLA: falta la fila del interruptor o tiene un valor raro: ' || coalesce(v, 'null') end;
  for perfil in
    select * from (values ('anon', 'anon', null::uuid), ('comprador', 'authenticated', gen_random_uuid()),
                          ('agente', 'authenticated', u_agente), ('super_admin', 'authenticated', u_super)) p(nombre, rol, uid) loop
    execute format('set local role %I', perfil.rol);
    perform set_config('request.jwt.claims',
      case when perfil.uid is null then '{}' else json_build_object('sub', perfil.uid, 'role', 'authenticated', 'email', 'x@ejemplo.invalid')::text end, true);
    foreach cmd in array array[
      'update public.config_instancia set valor = ''"cola"''::jsonb where clave = ''correo_cola_aviso_anulacion''',
      'insert into public.config_instancia (clave, valor) values (''correo_cola_aviso_otro'', ''"x"''::jsonb)',
      'delete from public.config_instancia where clave = ''correo_cola_aviso_anulacion'''] loop
      total := total + 1;
      begin execute cmd; res := res || E'\nFALLA: ' || perfil.nombre || ' PUDO escribir el interruptor: ' || left(cmd, 50);
      exception when insufficient_privilege then null;
                when others then res := res || E'\nFALLA: ' || perfil.nombre || ' recibió otro error (' || sqlstate || ') en: ' || left(cmd, 50); end;
    end loop;
    -- la RPC de encolar: solo service_role (ni anon, ni un comprador, ni un agente, ni un super_admin desde el navegador)
    total := total + 1;
    begin perform public.correo_aviso_anulacion_encolar(v_c, 'x@ejemplo.invalid');
      res := res || E'\nFALLA: ' || perfil.nombre || ' PUDO ejecutar correo_aviso_anulacion_encolar';
    exception when insufficient_privilege then null; end;
    reset role;
  end loop;

  -- ══ 2. fixtures (correos inventados @ejemplo.invalid; firmas colgadas de un contrato vivo no bloqueado) ═══════
  -- ana@ : f_viejo  — ronda ANTERIOR (hace 5 días), firmada, con su aviso ya `ok` en la cola   → NO debe elegirse nunca
  --        f_nuevo  — ronda ACTUAL (hace 10 min), sin firmar                                      → la que ancla el aviso
    -- bea@ : f_rol1 (sin firmar) y f_rol2 (firmada) en la MISMA anulación → debe elegir la firmada
  -- cleo@: anulada hace 40 min (fuera de ventana)                       → directo
  -- dani@: anulada hace 10 min pero con motivo «nuevo_enlace»           → directo
  insert into public.contrato_firmas (contrato_id, token_hash, firmante_nombre, firmante_email, estado, expira_en, orden, firmado_en, anulado_en, anulado_motivo, anulado_justificacion)
  select v_c, 'c3hash-' || g.i, 'Prueba ' || g.i, g.email, 'anulado', now() + interval '10 days', 80 + g.i, g.firmado, g.anulado, g.motivo, g.just
    from (values
      (1, 'c3ana@ejemplo.invalid',  now() - interval '6 days',  now() - interval '5 days',    'editar',       'motivo viejo de la primera ronda'),
      (2, 'c3ana@ejemplo.invalid',  null::timestamptz,          now() - interval '10 minutes', 'editar',       null),
      (3, 'C3Bea@ejemplo.invalid',  null,                       now() - interval '9 minutes',  'editar',       null),
      (4, 'c3bea@ejemplo.invalid',  now() - interval '3 days',  now() - interval '9 minutes',  'editar',       'motivo de bea de esta ronda'),
      (5, 'c3cleo@ejemplo.invalid', null,                       now() - interval '40 minutes', 'editar',       null),
      (6, 'c3dani@ejemplo.invalid', null,                       now() - interval '10 minutes', 'nuevo_enlace', null),
      (7, 'c3eva@ejemplo.invalid',  null,                       now() - interval '20 minutes', 'editar',       null),
      (8, 'c3fer@ejemplo.invalid',  null,                       now() - interval '20 minutes', 'editar',       null),
      (9, 'c3gus@ejemplo.invalid',  null,                       now() - interval '20 minutes', 'editar',       null)
    ) g(i, email, firmado, anulado, motivo, just);
  select f.id into f_viejo from public.contrato_firmas f where f.token_hash = 'c3hash-1';
  select f.id into f_nuevo from public.contrato_firmas f where f.token_hash = 'c3hash-2';
  select f.id into f_rol1  from public.contrato_firmas f where f.token_hash = 'c3hash-3';
  select f.id into f_rol2  from public.contrato_firmas f where f.token_hash = 'c3hash-4';
  select f.id into f_err   from public.contrato_firmas f where f.token_hash = 'c3hash-7';
  select f.id into f_atasc from public.contrato_firmas f where f.token_hash = 'c3hash-8';
  select f.id into f_ok    from public.contrato_firmas f where f.token_hash = 'c3hash-9';
  -- el aviso de la ronda anterior ya salió (fila `ok`): si la RPC eligiera f_viejo, correo_encolar diría «nuevo:false» y el aviso nuevo se perdería
  insert into public.correos_cola (clave, firma_id, estado, prioridad, encolado_en, proximo_intento_en, enviado_en)
  values ('aviso_anulacion', f_viejo, 'ok', 5, now() - interval '5 days', now() - interval '5 days', now() - interval '5 days');
  select count(*) into n0 from public.correos_cola;

  -- ══ 3. la RPC como service_role: interruptor apagado, ausente o raro → «directo» y NINGUNA fila ═══════════════
  foreach v in array array['"directo"', '"COLA"', 'true', '""', '{"a":1}'] loop
    update public.config_instancia set valor = v::jsonb where clave = 'correo_cola_aviso_anulacion';
    set local role service_role;
    r := public.correo_aviso_anulacion_encolar(v_c, 'c3ana@ejemplo.invalid');
    reset role;
    total := total + 1; res := res || case when r ->> 'modo' = 'directo' and not r ? 'id' then '' else E'\nFALLA: con el interruptor en ' || v || ' la RPC no devolvió «directo»: ' || r::text end;
  end loop;
  delete from public.config_instancia where clave = 'correo_cola_aviso_anulacion';
  set local role service_role;
  r := public.correo_aviso_anulacion_encolar(v_c, 'c3ana@ejemplo.invalid');
  reset role;
  total := total + 1; res := res || case when r ->> 'modo' = 'directo' then '' else E'\nFALLA: con la clave AUSENTE la RPC no devolvió «directo»' end;
  select count(*) into n from public.correos_cola;
  total := total + 1; res := res || case when n = n0 then '' else E'\nFALLA: con el interruptor apagado la RPC dejó filas en la cola (' || (n - n0) || ')' end;

  -- ══ 4. interruptor ENCENDIDO ═════════════════════════════════════════════════════════════════════════════════
  insert into public.config_instancia (clave, valor, descripcion) values ('correo_cola_aviso_anulacion', '"cola"'::jsonb, 'prueba');
  set local role service_role;
  r := public.correo_aviso_anulacion_encolar(v_c, 'c3ana@ejemplo.invalid');
  reset role;
  select q.firma_id into fid from public.correos_cola q where q.id = (r ->> 'id')::uuid;
  total := total + 1; res := res || case when r ->> 'modo' = 'cola' and (r ->> 'nuevo')::boolean then '' else E'\nFALLA: ana debía encolarse como nueva: ' || r::text end;
  total := total + 1; res := res || case when fid = f_nuevo then '' else E'\nFALLA: ana se ancló en una firma que NO es la de la última anulación (¿la de la ronda vieja?)' end;
  -- segunda vez (doble clic): no crea otra
  set local role service_role;
  r := public.correo_aviso_anulacion_encolar(v_c, 'c3ana@ejemplo.invalid');
  reset role;
  total := total + 1; res := res || case when r ->> 'modo' = 'cola' and not (r ->> 'nuevo')::boolean then '' else E'\nFALLA: el segundo aviso de ana debía ser «nuevo:false»: ' || r::text end;
  -- mayúsculas en el correo de la petición
  set local role service_role;
  r := public.correo_aviso_anulacion_encolar(v_c, 'C3ANA@ejemplo.invalid');
  reset role;
  total := total + 1; res := res || case when r ->> 'modo' = 'cola' and not (r ->> 'nuevo')::boolean then '' else E'\nFALLA: el correo de la petición no se compara sin mayúsculas: ' || r::text end;
  select count(*) into n from public.correos_cola where clave = 'aviso_anulacion' and encolado_en > now() - interval '1 minute';
  total := total + 1; res := res || case when n = 1 then '' else E'\nFALLA: ana debía dejar UNA sola fila viva nueva y deja ' || n end;
  -- la fila `ok` de la ronda vieja no se ha tocado
  total := total + 1; res := res || case when (select q.estado from public.correos_cola q where q.firma_id = f_viejo and q.clave = 'aviso_anulacion') = 'ok' then '' else E'\nFALLA: la fila de la ronda anterior cambió' end;

  -- dos roles, misma anulación, uno firmó → ancla en el que firmó (la variante «ya firmaste» sale de ahí)
  set local role service_role;
  r := public.correo_aviso_anulacion_encolar(v_c, 'c3bea@ejemplo.invalid');
  reset role;
  select q.firma_id into fid from public.correos_cola q where q.id = (r ->> 'id')::uuid;
  total := total + 1; res := res || case when r ->> 'modo' = 'cola' and fid = f_rol2 then '' else E'\nFALLA: bea debía anclarse en la firma que SÍ firmó: ' || r::text end;
  -- fuera de ventana / otro motivo / sin firma / correo ajeno / nulo → directo y sin fila
  select count(*) into n0 from public.correos_cola;
  foreach v in array array['c3cleo@ejemplo.invalid', 'c3dani@ejemplo.invalid', 'c3nadie@ejemplo.invalid', ''] loop
    set local role service_role;
    r := public.correo_aviso_anulacion_encolar(v_c, v);
    reset role;
    total := total + 1; res := res || case when r ->> 'modo' = 'directo' and r ->> 'motivo' = 'sin_anulacion_reciente' then '' else E'\nFALLA: ' || v || ' debía ir «directo» (sin anulación reciente «editar»): ' || r::text end;
  end loop;
  set local role service_role;
  r := public.correo_aviso_anulacion_encolar(v_c, null);
  reset role;
  total := total + 1; res := res || case when r ->> 'modo' = 'directo' then '' else E'\nFALLA: un correo nulo debía ir «directo»' end;
  set local role service_role;
  r := public.correo_aviso_anulacion_encolar(gen_random_uuid(), 'c3ana@ejemplo.invalid');
  reset role;
  total := total + 1; res := res || case when r ->> 'modo' = 'directo' then '' else E'\nFALLA: un contrato que no es el de la firma debía ir «directo»' end;
  select count(*) into n from public.correos_cola;
  total := total + 1; res := res || case when n = n0 then '' else E'\nFALLA: los casos «directo» dejaron filas en la cola' end;

  -- una fila en `error` de esa firma: volver a pedirlo la REABRE (no se traga el aviso)
  update public.correos_cola set estado = 'error', error = 'agotado' where firma_id = f_nuevo and clave = 'aviso_anulacion';
  set local role service_role;
  r := public.correo_aviso_anulacion_encolar(v_c, 'c3ana@ejemplo.invalid');
  reset role;
  total := total + 1; res := res || case when r ->> 'modo' = 'cola' and (r ->> 'reabierto')::boolean and r ->> 'estado' = 'pendiente' then '' else E'\nFALLA: una fila en error debía reabrirse: ' || r::text end;

  -- ══ 5. el aviso fuera del SMTP: auditoria_firmas() y la función auxiliar ═════════════════════════════════════
  -- f_err: fila `error` reciente · f_atasc: pendiente de hace 20 min · f_ok: fila `ok` · f_nuevo: pendiente recién reabierta (no se ve)
  insert into public.correos_cola (clave, firma_id, estado, prioridad, encolado_en, proximo_intento_en, enviado_en, error) values
    ('aviso_anulacion', f_err,   'error',     5, now() - interval '2 hours',  now() - interval '1 hour', null, 'agotado'),
    ('aviso_anulacion', f_atasc, 'pendiente', 5, now() - interval '20 minutes', now() - interval '19 minutes', null, null),
    ('aviso_anulacion', f_ok,    'ok',        5, now() - interval '30 minutes', now() - interval '29 minutes', now() - interval '29 minutes', null);
  perform set_config('request.jwt.claims', json_build_object('sub', u_super, 'role', 'authenticated', 'email', 'x@ejemplo.invalid')::text, true);
  set local role authenticated;
  foreach t in array array[public.correo_cola_aviso_sin_enviar(f_err), public.correo_cola_aviso_sin_enviar(f_atasc)] loop
    total := total + 1; res := res || case when t is not null then '' else E'\nFALLA: el super_admin no ve un aviso sin enviar (error / atascado)' end;
  end loop;
  foreach t in array array[public.correo_cola_aviso_sin_enviar(f_ok), public.correo_cola_aviso_sin_enviar(f_nuevo),
                           public.correo_cola_aviso_sin_enviar(f_viejo), public.correo_cola_aviso_sin_enviar(gen_random_uuid())] loop
    total := total + 1; res := res || case when t is null then '' else E'\nFALLA: la función marcó un aviso que está bien (ok / recién encolado / desconocido)' end;
  end loop;
  select count(*) into n from public.auditoria_firmas() a where a.tipo = 'aviso_anulacion_sin_enviar' and a.contrato_id = v_c;
  total := total + 1; res := res || case when n = 2 then '' else E'\nFALLA: el super_admin debía ver 2 «aviso_anulacion_sin_enviar» (error y atascado) y ve ' || n end;
  select count(*) into n from public.auditoria_firmas() a where a.tipo = 'aviso_anulacion_sin_enviar' and a.severidad = 'aviso' and a.desde is not null and a.detalle like '%NO ha salido%' and a.detalle like '%otra via%';
  total := total + 1; res := res || case when n >= 2 then '' else E'\nFALLA: la rama nueva debe ser «aviso», con fecha y decir que se avise por otra vía' end;
  reset role;
  -- un error de hace 8 días ya no da la alarma (una alarma sin fecha se acaba ignorando)
  update public.correos_cola set encolado_en = now() - interval '8 days' where firma_id = f_err and clave = 'aviso_anulacion';
  set local role authenticated;
  total := total + 1; res := res || case when public.correo_cola_aviso_sin_enviar(f_err) is null then '' else E'\nFALLA: un error de hace 8 días sigue dando la alarma' end;
  reset role;
  -- agente con alcance: la rama sale SOLO de los contratos que la RLS le deja ver (el INVOKER se conserva)
  perform set_config('request.jwt.claims', json_build_object('sub', u_agente, 'role', 'authenticated', 'email', 'x@ejemplo.invalid')::text, true);
  set local role authenticated;
  select count(*) into n0 from public.contratos c where c.id = v_c;
  select count(*) into n from public.auditoria_firmas() a where a.tipo = 'aviso_anulacion_sin_enviar' and a.contrato_id = v_c;
  total := total + 1; res := res || case when n = case when n0 = 1 then 1 else 0 end then '' else E'\nFALLA: el agente ve ' || n || ' avisos de un contrato que ' || case when n0 = 1 then 'SÍ' else 'NO' end || ' ve' end;
  reset role;
  -- comprador (sin ficha): nada; anon: ni la función ni auditoria_firmas
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated', 'email', 'x@ejemplo.invalid')::text, true);
  set local role authenticated;
  total := total + 1; res := res || case when public.correo_cola_aviso_sin_enviar(f_atasc) is null then '' else E'\nFALLA: un comprador averiguó que un aviso no salió' end;
  select count(*) into n from public.auditoria_firmas();
  total := total + 1; res := res || case when n = 0 then '' else E'\nFALLA: un comprador recibió ' || n || ' filas de auditoria_firmas' end;
  reset role;
  perform set_config('request.jwt.claims', '{}', true);
  set local role anon;
  total := total + 1;
  begin perform public.correo_cola_aviso_sin_enviar(f_atasc); res := res || E'\nFALLA: anon PUDO ejecutar correo_cola_aviso_sin_enviar';
  exception when insufficient_privilege then null; end;
  reset role;

  -- ══ 6. las seis ramas de antes siguen (+ la nueva) y la función sigue siendo INVOKER ═════════════════════════
  select pg_get_functiondef('public.auditoria_firmas'::regproc) into v;
  total := total + 1; res := res || case when v like '%''cadena_parada''%' and v like '%''firmante_sin_email''%' and v like '%''enlace_caducado''%'
                                          and v like '%''cerrado_sin_documento''%' and v like '%''firma_atascada''%' and v like '%''enlace_sin_enviar''%'
                                          and v like '%''aviso_anulacion_sin_enviar''%'
                                    then '' else E'\nFALLA: auditoria_firmas() perdió alguna de sus siete ramas' end;
  total := total + 1; res := res || case when not (select p.prosecdef from pg_proc p where p.oid = 'public.auditoria_firmas'::regproc)
                                    then '' else E'\nFALLA: auditoria_firmas() dejó de ser INVOKER (rompe el alcance de 11-sep)' end;

  raise exception 'RESULTADO: % (% comprobaciones)%', case when res = '' then 'OK' else 'HAY FALLOS' end, total, res;
end
$t$;
