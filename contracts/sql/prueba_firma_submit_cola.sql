-- prueba_firma_submit_cola.sql — AXW-202 C2: lo que añade la migración 20261005015830 (interruptor de firma-submit y aviso
-- `enlace_sin_enviar` en auditoria_firmas()) PROBADO POR PERFIL. Se lanza con el MCP supabase-lawang (execute_sql) o psql.
-- El MCP corre como `postgres` y no prueba permisos por sí mismo: cada perfil va con `set local role` + claims.
-- TODO ocurre en una transacción que SIEMPRE se deshace (el DO acaba en `raise exception 'RESULTADO: ...'`): no queda ninguna fila.
-- Datos de prueba: firmas inventadas (correos @ejemplo.invalid) colgadas de un contrato vivo no bloqueado; filas de la cola puestas
-- a mano con la antigüedad que cada caso necesita. Empieza por «RESULTADO: OK» si todo pasó; cada «FALLA» dice qué.
do $t$
declare
  res   text := '';
  total int  := 0;
  v_c   uuid;
  fa uuid; fb uuid; fc uuid; fd uuid; fe uuid; ff uuid;
  u_super uuid; u_agente uuid;
  n0 int; n int; v text;
  perfil record;
  cmd text;
  t timestamptz;
begin
  set local session_replication_role = replica;

  select c.id into v_c from public.contratos c where c.liberado_en is null and not coalesce(c.bloqueado, false) limit 1;
  select u.user_id into u_super  from public.usuarios u where u.activo and u.rol = 'super_admin' limit 1;
  select u.user_id into u_agente from public.usuarios u where u.activo and u.rol = 'agente' limit 1;

  -- ══ 1. el interruptor: existe, nace en «directo», y NADIE salvo service_role/postgres lo toca ═════════════
  select valor #>> '{}' into v from public.config_instancia where clave = 'correo_cola_firma_submit';
  total := total + 1; res := res || case when v in ('directo', 'cola') then '' else E'\nFALLA: falta la fila del interruptor o tiene un valor raro: ' || coalesce(v, 'null') end;
  for perfil in
    select * from (values ('anon', 'anon', null::uuid), ('comprador', 'authenticated', gen_random_uuid()),
                          ('agente', 'authenticated', u_agente), ('super_admin', 'authenticated', u_super)) p(nombre, rol, uid) loop
    execute format('set local role %I', perfil.rol);
    perform set_config('request.jwt.claims',
      case when perfil.uid is null then '{}' else json_build_object('sub', perfil.uid, 'role', 'authenticated', 'email', 'x@ejemplo.invalid')::text end, true);
    foreach cmd in array array[
      'update public.config_instancia set valor = ''"cola"''::jsonb where clave = ''correo_cola_firma_submit''',
      'insert into public.config_instancia (clave, valor) values (''correo_cola_otro'', ''"x"''::jsonb)',
      'delete from public.config_instancia where clave = ''correo_cola_firma_submit'''] loop
      total := total + 1;
      begin execute cmd; res := res || E'\nFALLA: ' || perfil.nombre || ' PUDO escribir el interruptor: ' || left(cmd, 50);
      exception when insufficient_privilege then null;
                when others then res := res || E'\nFALLA: ' || perfil.nombre || ' recibió otro error (' || sqlstate || ') en: ' || left(cmd, 50); end;
    end loop;
    reset role;
  end loop;

  -- ══ 2. fixtures ═══════════════════════════════════════════════════════════════════════════════════════════
  -- fa: pendiente, fila `pendiente` de hace 20 min (atascada)        → se ve
  -- fb: pendiente, fila `error` reciente                              → se ve
  -- fc: pendiente, fila `pendiente` de hace 3 min (reintento normal)  → NO se ve
  -- fd: pendiente, fila `ok`                                          → NO se ve
  -- fe: pendiente, SIN fila (interruptor apagado, salió directo)      → NO se ve
  -- ff: ANULADA con fila `error`                                      → NO se ve (el hecho ya no importa)
  insert into public.contrato_firmas (contrato_id, token_hash, firmante_nombre, firmante_email, estado, expira_en, orden, enlace_firma, anulado_en)
  select v_c, 'c2hash-' || g, 'Prueba ' || g, 'C2Prueba' || g || '@ejemplo.invalid', 'pendiente', now() + interval '10 days', 90 + g,
         'https://ejemplo.invalid/contracts/firmar.html?t=c2prueba' || g, case when g = 6 then now() else null end
    from generate_series(1, 6) g;
  select f.id into fa from public.contrato_firmas f where f.token_hash = 'c2hash-1';
  select f.id into fb from public.contrato_firmas f where f.token_hash = 'c2hash-2';
  select f.id into fc from public.contrato_firmas f where f.token_hash = 'c2hash-3';
  select f.id into fd from public.contrato_firmas f where f.token_hash = 'c2hash-4';
  select f.id into fe from public.contrato_firmas f where f.token_hash = 'c2hash-5';
  select f.id into ff from public.contrato_firmas f where f.token_hash = 'c2hash-6';
  insert into public.correos_cola (clave, firma_id, estado, prioridad, encolado_en, proximo_intento_en, error) values
    ('enlace_firma_cadena', fa, 'pendiente', 1, now() - interval '20 minutes', now() - interval '19 minutes', null),
    ('enlace_firma_cadena', fb, 'error',     1, now() - interval '2 minutes',  now() - interval '1 minute',   'agotado'),
    ('enlace_firma_cadena', fc, 'pendiente', 1, now() - interval '3 minutes',  now() + interval '1 minute',   null),
    ('enlace_firma_cadena', fd, 'ok',        1, now() - interval '30 minutes', now() - interval '29 minutes', null),
    ('enlace_firma_cadena', ff, 'error',     1, now() - interval '30 minutes', now() - interval '29 minutes', 'agotado');

  -- ══ 3. la función auxiliar: solo contesta a un agente, y solo «desde cuándo» ══════════════════════════════
  perform set_config('request.jwt.claims', json_build_object('sub', u_super, 'role', 'authenticated', 'email', 'x@ejemplo.invalid')::text, true);
  set local role authenticated;
  foreach t in array array[public.correo_cola_firma_sin_enviar(fa), public.correo_cola_firma_sin_enviar(fb)] loop
    total := total + 1; res := res || case when t is not null then '' else E'\nFALLA: el super_admin no ve una firma sin enviar' end;
  end loop;
  foreach t in array array[public.correo_cola_firma_sin_enviar(fc), public.correo_cola_firma_sin_enviar(fd),
                           public.correo_cola_firma_sin_enviar(fe), public.correo_cola_firma_sin_enviar(gen_random_uuid())] loop
    total := total + 1; res := res || case when t is null then '' else E'\nFALLA: la función marcó una firma que está bien (fc/fd/fe/desconocida)' end;
  end loop;
  reset role;
  -- comprador (sin ficha de usuario) y anon: no
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated', 'email', 'x@ejemplo.invalid')::text, true);
  set local role authenticated;
  t := public.correo_cola_firma_sin_enviar(fa);
  total := total + 1; res := res || case when t is null then '' else E'\nFALLA: un comprador (no agente) averiguó que una firma no se envió' end;
  reset role;
  perform set_config('request.jwt.claims', '{}', true);
  set local role anon;
  total := total + 1;
  begin perform public.correo_cola_firma_sin_enviar(fa); res := res || E'\nFALLA: anon PUDO ejecutar correo_cola_firma_sin_enviar';
  exception when insufficient_privilege then null; end;
  total := total + 1;
  begin perform * from public.auditoria_firmas(); res := res || E'\nFALLA: anon PUDO ejecutar auditoria_firmas';
  exception when insufficient_privilege then null; end;
  reset role;

  -- ══ 4. auditoria_firmas(): la rama nueva, por perfil ═════════════════════════════════════════════════════
  perform set_config('request.jwt.claims', json_build_object('sub', u_super, 'role', 'authenticated', 'email', 'x@ejemplo.invalid')::text, true);
  set local role authenticated;
  select count(*) into n from public.auditoria_firmas() a where a.tipo = 'enlace_sin_enviar' and a.contrato_id = v_c;
  total := total + 1; res := res || case when n = 2 then '' else E'\nFALLA: el super_admin debía ver 2 «enlace_sin_enviar» (fa y fb) y ve ' || n end;
  select count(*) into n from public.auditoria_firmas() a where a.tipo = 'enlace_sin_enviar' and a.severidad = 'critica' and a.desde is not null and a.detalle like '%NO ha salido%';
  total := total + 1; res := res || case when n >= 2 then '' else E'\nFALLA: la rama nueva debe ser crítica, con fecha y texto' end;
  reset role;
  -- un agente con alcance: ve la rama nueva SOLO si la RLS le deja ver ese contrato (el invoker se conserva)
  perform set_config('request.jwt.claims', json_build_object('sub', u_agente, 'role', 'authenticated', 'email', 'x@ejemplo.invalid')::text, true);
  set local role authenticated;
  select count(*) into n0 from public.contratos c where c.id = v_c;
  select count(*) into n from public.auditoria_firmas() a where a.tipo = 'enlace_sin_enviar' and a.contrato_id = v_c;
  total := total + 1; res := res || case when n = case when n0 = 1 then 2 else 0 end then '' else E'\nFALLA: el agente ve ' || n || ' avisos de un contrato que ' || case when n0 = 1 then 'SÍ' else 'NO' end || ' ve' end;
  reset role;
  -- comprador: nada
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated', 'email', 'x@ejemplo.invalid')::text, true);
  set local role authenticated;
  select count(*) into n from public.auditoria_firmas();
  total := total + 1; res := res || case when n = 0 then '' else E'\nFALLA: un comprador recibió ' || n || ' filas de auditoria_firmas' end;
  reset role;

  -- ══ 5. las cinco ramas de antes siguen en la función (el create or replace no se comió ninguna) y sigue siendo INVOKER ═══
  select pg_get_functiondef('public.auditoria_firmas'::regproc) into v;
  total := total + 1; res := res || case when v like '%''cadena_parada''%' and v like '%''firmante_sin_email''%' and v like '%''enlace_caducado''%'
                                          and v like '%''cerrado_sin_documento''%' and v like '%''firma_atascada''%' and v like '%''enlace_sin_enviar''%'
                                    then '' else E'
FALLA: auditoria_firmas() perdió alguna de sus seis ramas' end;
  total := total + 1; res := res || case when not (select p.prosecdef from pg_proc p where p.oid = 'public.auditoria_firmas'::regproc)
                                    then '' else E'
FALLA: auditoria_firmas() dejó de ser INVOKER (rompe el alcance de 11-sep)' end;

  raise exception 'RESULTADO: % (% comprobaciones)%', case when res = '' then 'OK' else 'HAY FALLOS' end, total, res;
end
$t$;
