-- prueba_correos_cola.sql — AXW-202 C1: la cola de correos (migración 20261005011702) PROBADA POR PERFIL y por comportamiento.
-- Se lanza con el MCP supabase-lawang (execute_sql) o psql. El MCP corre como `postgres` y por eso NO prueba permisos por sí mismo:
-- aquí cada perfil se prueba con `set local role` (anon, authenticated con las claims de cada tipo de usuario, service_role).
-- TODO ocurre dentro de una transacción que SIEMPRE se deshace: el DO termina con un `raise exception 'RESULTADO: ...'`, así que no
-- queda ninguna fila (ni de la cola, ni de contrato_firmas, ni de correos_enviados) y las peticiones de pg_net del despertador también
-- se deshacen (nada sale a la red). Si el resultado empieza por «RESULTADO: OK» todo pasó; si no, cada línea «FALLA» dice qué.
-- Los datos de prueba son filas de contrato_firmas inventadas (correos @ejemplo.invalid) colgadas de un contrato vivo cualquiera, con los
-- triggers de la tabla apagados (session_replication_role) para no crear eventos ni avisos.
do $t$
declare
  res   text := '';
  total int  := 0;
  v_c   uuid;
  f1 uuid; f2 uuid; f3 uuid; f4 uuid; f5 uuid; f6 uuid;
  u_super uuid; u_admin uuid; u_agente uuid; u_pm uuid; u_sales uuid;
  perfil record;
  cmd    text;
  cmds   text[];
  v_sql  text;
  j      jsonb;
  q1 uuid; q2 uuid; q3 uuid; q4 uuid; q5 uuid;
  rec    record;
  n      int;
  e      text;
  st     text;
  v_prox timestamptz;
  s1     int;
begin
  set local session_replication_role = replica;

  select c.id into v_c from public.contratos c where c.liberado_en is null limit 1;
  select u.user_id into u_super  from public.usuarios u where u.activo and u.rol = 'super_admin' limit 1;
  select u.user_id into u_admin  from public.usuarios u where u.activo and u.rol = 'admin' limit 1;
  select u.user_id into u_agente from public.usuarios u where u.activo and u.rol = 'agente' limit 1;
  select u.user_id into u_pm     from public.usuarios u where u.activo and u.rol = 'project_manager' limit 1;
  select u.user_id into u_sales  from public.usuarios u where u.activo and u.rol = 'sales_manager' limit 1;

  -- fixtures (el contrato es real; las firmas, no): f1 enlace vivo · f2 enlace vivo · f3 enlace vivo · f4 anulada (aviso)
  --   f5 NO anulada (el aviso no procede) · f6 con un «email» que no lo es
  insert into public.contrato_firmas (contrato_id, token_hash, firmante_nombre, firmante_email, estado, expira_en, orden, enlace_firma, anulado_en)
  select v_c, 'hash-' || g, 'Prueba ' || g, case when g = 6 then 'no-es-un-email' else 'Prueba' || g || '@ejemplo.invalid' end,
         'pendiente', now() + interval '10 days', g, 'https://ejemplo.invalid/contracts/firmar.html?t=prueba' || g,
         case when g = 4 then now() else null end
    from generate_series(1, 6) g;
  select f.id into f1 from public.contrato_firmas f where f.token_hash = 'hash-1';
  select f.id into f2 from public.contrato_firmas f where f.token_hash = 'hash-2';
  select f.id into f3 from public.contrato_firmas f where f.token_hash = 'hash-3';
  select f.id into f4 from public.contrato_firmas f where f.token_hash = 'hash-4';
  select f.id into f5 from public.contrato_firmas f where f.token_hash = 'hash-5';
  select f.id into f6 from public.contrato_firmas f where f.token_hash = 'hash-6';

  -- ══ 1. PERFILES: nadie salvo service_role toca nada ═══════════════════════════════════════════════════════
  cmds := array[
    'select public.correo_encolar(''enlace_firma_cadena'', ''' || f1 || '''::uuid)',
    'select * from public.correo_cola_reclamar(5)',
    'select public.correo_cola_ok(''' || f1 || '''::uuid, ''x@ejemplo.invalid'', ''v1'')',
    'select public.correo_cola_fallo(''' || f1 || '''::uuid, ''x'')',
    'select public.correos_cola_purga()',
    'select * from public.correo_cola_salud()',
    'select public.cron_correos_cola_secret()',
    'select * from public._correo_cola_regla(''enlace_firma_cadena'')',
    'select public._correo_cola_vigente(''aviso_anulacion'', ''' || f4 || '''::uuid, null, null)',
    'select public._correo_cola_destino(''enlace_firma_cadena'', ''' || f1 || '''::uuid, null, null)',
    'select public._correos_cola_despierta()',
    'select count(*) from public.correos_cola',
    'insert into public.correos_cola (clave, firma_id) values (''enlace_firma_cadena'', ''' || f1 || '''::uuid)',
    'update public.correos_cola set estado = ''ok''',
    'delete from public.correos_cola'];
  for perfil in
    select * from (values
      ('anon',                         'anon',          null::uuid),
      ('authenticated sin claims',     'authenticated', null::uuid),
      ('comprador (portal, sin ficha)','authenticated', gen_random_uuid()),
      ('agente',                       'authenticated', u_agente),
      ('admin',                        'authenticated', u_admin),
      ('super_admin',                  'authenticated', u_super),
      ('project_manager',              'authenticated', u_pm),
      ('sales_manager',                'authenticated', u_sales)) p(nombre, rol, uid) loop
    execute format('set local role %I', perfil.rol);
    perform set_config('request.jwt.claims',
      case when perfil.uid is null then '{}' else json_build_object('sub', perfil.uid, 'role', 'authenticated', 'email', 'x@ejemplo.invalid')::text end, true);
    foreach cmd in array cmds loop
      total := total + 1;
      begin
        execute cmd;
        res := res || E'\nFALLA: ' || perfil.nombre || ' PUDO ejecutar: ' || left(cmd, 60);
      exception when insufficient_privilege then null;
                when others then res := res || E'\nFALLA: ' || perfil.nombre || ' recibió otro error (' || sqlstate || ') en: ' || left(cmd, 60);
      end;
    end loop;
    reset role;
  end loop;

  -- ══ 2. service_role: encola, lee, y NADA más sobre la tabla ═══════════════════════════════════════════════
  set local role service_role;
  j := public.correo_encolar('enlace_firma_cadena', f1);
  q1 := (j->>'id')::uuid;
  total := total + 1; res := res || case when (j->>'nuevo')::boolean and j->>'estado' = 'pendiente' then '' else E'\nFALLA: encolar no devolvió nuevo/pendiente: ' || j::text end;
  j := public.correo_encolar('enlace_firma_cadena', f1);
  total := total + 1; res := res || case when not (j->>'nuevo')::boolean and (j->>'id')::uuid = q1 then '' else E'\nFALLA: reencolar el mismo documento creó otra fila: ' || j::text end;
  select count(*) into n from public.correos_cola;
  total := total + 1; res := res || case when n = 1 then '' else E'\nFALLA: service_role lee la tabla y debería ver 1 fila, ve ' || n end;
  foreach cmd in array array[
    'insert into public.correos_cola (clave, firma_id) values (''enlace_firma_cadena'', ''' || f2 || '''::uuid)',
    'update public.correos_cola set estado = ''ok''', 'delete from public.correos_cola'] loop
    total := total + 1;
    begin execute cmd; res := res || E'\nFALLA: service_role escribió directo en la tabla: ' || left(cmd, 50);
    exception when insufficient_privilege then null; end;
  end loop;
  -- rechazos de forma (no se ajusta, se rechaza)
  foreach cmd in array array[
    'select public.correo_encolar(''no_existe'', ''' || f2 || '''::uuid)',
    'select public.correo_encolar(''factura_vencimiento'', null, null, ''' || gen_random_uuid() || '''::uuid)',
    'select public.correo_encolar(''enlace_firma_cadena'', ''' || f2 || '''::uuid, ''' || v_c || '''::uuid)',
    'select public.correo_encolar(''enlace_firma_cadena'', null, ''' || v_c || '''::uuid)',
    'select public.correo_encolar(''enlace_firma_cadena'')',
    'select public.correo_encolar(''enlace_firma_cadena'', ''' || f2 || '''::uuid, null, null, ''{"nombre":"Ana"}''::jsonb)',
    'select public.correo_encolar(''enlace_firma_cadena'', ''' || f2 || '''::uuid, null, null, ''{"enlace":"https://x"}''::jsonb)',
    'select public.correo_encolar(''enlace_firma_cadena'', ''' || f2 || '''::uuid, null, null, ''[]''::jsonb)'] loop
    total := total + 1;
    begin execute cmd; res := res || E'\nFALLA: encolar aceptó algo que debía rechazar: ' || left(cmd, 70);
    exception when invalid_parameter_value then null;
              when others then res := res || E'\nFALLA: encolar rechazó con otro error (' || sqlstate || '): ' || left(cmd, 70); end;
  end loop;

  -- ══ 3. reclamar: fila, destinatario del DUEÑO, lease, y ni una dirección en la cola ═══════════════════════
  select * into rec from public.correo_cola_reclamar(5);
  total := total + 1; res := res || case when rec.id = q1 and rec.para = 'prueba1@ejemplo.invalid' and rec.contrato_id = v_c and rec.firma_id = f1
                                          and rec.intentos = 1 and rec.prioridad = 1 and rec.factura_id is null
                                    then '' else E'\nFALLA: reclamar devolvió algo distinto de lo esperado: ' || to_jsonb(rec)::text end;
  select count(*) into n from public.correo_cola_reclamar(5);
  total := total + 1; res := res || case when n = 0 then '' else E'\nFALLA: con el lease vivo, una segunda pasada la volvió a coger' end;
  reset role;
  total := total + 1;
  res := res || case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'correos_cola'
                                    and (column_name ~* '(email|correo|destin|para|token|url|asunto|mensaje|cuerpo|texto)')) then E'\nFALLA: la tabla guarda destinatario/token/URL/texto' else '' end;

  -- ══ 4. cerrar ok: registro en correos_enviados en la MISMA transacción; idempotente ═══════════════════════
  set local role service_role;
  total := total + 1; res := res || case when public.correo_cola_ok(q1, 'Prueba1@Ejemplo.invalid', 'f:ab12cd34') then '' else E'\nFALLA: ok no cerró' end;
  total := total + 1; res := res || case when not public.correo_cola_ok(q1, 'prueba1@ejemplo.invalid', 'f:ab12cd34') then '' else E'\nFALLA: un segundo ok volvió a cerrar (duplicaría el registro)' end;
  reset role;
  select * into rec from public.correos_enviados ce where ce.contrato_id = v_c and ce.para = 'prueba1@ejemplo.invalid';
  total := total + 1; res := res || case when rec.plantilla = 'enlace_firma_cadena' and rec.plantilla_version = 'f:ab12cd34' and rec.via = 'enlace_firma'
                                          and rec.mensaje is null and rec.enviado_por is null
                                    then '' else E'\nFALLA: registro en correos_enviados incorrecto: ' || coalesce(to_jsonb(rec)::text, 'no existe') end;
  select count(*) into n from public.correos_enviados ce where ce.contrato_id = v_c and ce.para = 'prueba1@ejemplo.invalid';
  total := total + 1; res := res || case when n = 1 then '' else E'\nFALLA: debería haber 1 registro, hay ' || n end;
  set local role service_role;
  j := public.correo_encolar('enlace_firma_cadena', f1);
  total := total + 1; res := res || case when not (j->>'nuevo')::boolean and j->>'estado' = 'ok' then '' else E'\nFALLA: reencolar tras ok debería devolver la fila ok, no una nueva: ' || j::text end;
  -- versión rara: se registra igualmente, sin versión (no se pierde el registro)
  j := public.correo_encolar('enlace_firma_cadena', f2); q2 := (j->>'id')::uuid;
  perform public.correo_cola_reclamar(5);
  total := total + 1; res := res || case when public.correo_cola_ok(q2, 'prueba2@ejemplo.invalid', 'basura') then '' else E'\nFALLA: ok con versión rara no cerró' end;
  reset role;
  select * into rec from public.correos_enviados ce where ce.contrato_id = v_c and ce.para = 'prueba2@ejemplo.invalid';
  total := total + 1; res := res || case when rec.plantilla is null and rec.plantilla_version is null then '' else E'\nFALLA: versión no válida debía registrarse sin plantilla' end;

  -- ══ 5. vigencia: el hecho ya no vale → cancelado sin enviar ═══════════════════════════════════════════════
  set local role service_role;
  j := public.correo_encolar('aviso_anulacion', f5); q3 := (j->>'id')::uuid;      -- f5 NO está anulada
  select count(*) into n from public.correo_cola_reclamar(5);
  reset role;
  select c.estado, c.error into st, e from public.correos_cola c where c.id = q3;
  total := total + 1; res := res || case when n = 0 and st = 'cancelado' and e = 'hecho_no_vigente' then '' else E'\nFALLA: aviso sobre firma no anulada: estado ' || st || ' / ' || coalesce(e, '-') end;
  set local role service_role;
  j := public.correo_encolar('aviso_anulacion', f5);
  total := total + 1; res := res || case when (j->>'nuevo')::boolean then '' else E'\nFALLA: tras cancelado se puede encolar de nuevo y no se pudo' end;
  j := public.correo_encolar('aviso_anulacion', f4); q4 := (j->>'id')::uuid;      -- f4 SÍ anulada
  select * into rec from public.correo_cola_reclamar(5);
  total := total + 1; res := res || case when rec.id = q4 and rec.para = 'prueba4@ejemplo.invalid' and rec.contrato_id = v_c and rec.prioridad = 5 then '' else E'\nFALLA: aviso_anulacion vigente no se reclamó bien: ' || coalesce(to_jsonb(rec)::text, 'nada') end;
  reset role;
  update public.contrato_firmas set estado = 'firmado' where id = f3;               -- enlace que se firmó antes de salir
  set local role service_role;
  j := public.correo_encolar('enlace_firma_cadena', f3); q5 := (j->>'id')::uuid;
  select count(*) into n from public.correo_cola_reclamar(5);
  reset role;
  select c.estado, c.error into st, e from public.correos_cola c where c.id = q5;
  total := total + 1; res := res || case when n = 0 and st = 'cancelado' then '' else E'\nFALLA: enlace de una firma ya firmada no se canceló: ' || st end;

  -- ══ 6. sin destinatario, tope de antigüedad ═══════════════════════════════════════════════════════════════
  set local role service_role;
  j := public.correo_encolar('enlace_firma_cadena', f6); q1 := (j->>'id')::uuid;
  perform public.correo_cola_reclamar(5);
  reset role;
  select c.estado, c.error into st, e from public.correos_cola c where c.id = q1;
  total := total + 1; res := res || case when st = 'error' and e = 'sin_destinatario' then '' else E'\nFALLA: firmante sin email válido: ' || st || '/' || coalesce(e, '-') end;

  -- f2: ya cerrada ok arriba. Una fila nueva sobre f3 revivida
  update public.contrato_firmas set estado = 'pendiente' where id = f3;
  set local role service_role;
  j := public.correo_encolar('enlace_firma_cadena', f3); q2 := (j->>'id')::uuid;
  reset role;
  update public.correos_cola set encolado_en = now() - interval '25 hours' where id = q2;
  set local role service_role;
  select count(*) into n from public.correo_cola_reclamar(5);
  reset role;
  select c.estado, c.error into st, e from public.correos_cola c where c.id = q2;
  total := total + 1; res := res || case when n = 0 and st = 'error' and e = 'tope_antiguedad' then '' else E'\nFALLA: enlace de 25 h no pasó a error por antigüedad: ' || st || '/' || coalesce(e, '-') end;

  -- ══ 7. lease vencido, reintentos, backoff, tope de intentos ═══════════════════════════════════════════════
  -- fila nueva sobre f2 (cerrada ok): se usa un aviso sobre f4 ya reclamado arriba (q4 está `enviando`)
  reset role;
  update public.correos_cola set reclamado_hasta = now() - interval '1 second' where id = q4;
  set local role service_role;
  select * into rec from public.correo_cola_reclamar(5);
  total := total + 1; res := res || case when rec.id = q4 and rec.intentos = 2 then '' else E'\nFALLA: lease vencido no se volvió a reclamar con intentos 2: ' || coalesce(to_jsonb(rec)::text, 'nada') end;
  -- fallo normal: vuelve a pendiente con backoff y no se reclama enseguida
  st := public.correo_cola_fallo(q4, 'fallo smtp de prueba a@b.com');
  reset role;
  select c.error, c.proximo_intento_en, c.intentos into e, v_prox, n from public.correos_cola c where c.id = q4;
  total := total + 1; res := res || case when st = 'pendiente' and v_prox > now() + interval '90 seconds' and n = 2 and e not like '%@%' and e like '%<correo>%'
                                    then '' else E'\nFALLA: fallo normal: estado ' || coalesce(st, '-') || ', error «' || coalesce(e, '-') || '», proximo ' || coalesce(v_prox::text, '-') end;
  set local role service_role;
  select count(*) into n from public.correo_cola_reclamar(5);
  total := total + 1; res := res || case when n = 0 then '' else E'\nFALLA: una fila en backoff se reclamó antes de su hora' end;
  reset role;
  update public.correos_cola set proximo_intento_en = now() where id = q4;
  set local role service_role;
  perform public.correo_cola_reclamar(5);                                              -- intentos 3
  st := public.correo_cola_fallo(q4, 'bloqueo del proveedor', false, true, 0);          -- devolver: no gasta intento
  reset role;
  select c.intentos into n from public.correos_cola c where c.id = q4;
  total := total + 1; res := res || case when st = 'pendiente' and n = 2 then '' else E'\nFALLA: devolver debía dejar los intentos en 2: ' || st || '/' || n end;
  -- tope de reintentos: con 10 intentos gastados, el fallo siguiente es `error`
  update public.correos_cola set intentos = 9, proximo_intento_en = now() where id = q4;
  set local role service_role;
  perform public.correo_cola_reclamar(5);                                              -- intentos 10
  st := public.correo_cola_fallo(q4, 'otra vez');
  total := total + 1; res := res || case when st = 'error' then '' else E'\nFALLA: tras 10 intentos el fallo debía ser error, fue ' || coalesce(st, '-') end;
  -- terminal
  reset role;
  update public.correos_cola set estado = 'enviando', reclamado_hasta = now() + interval '4 minutes', intentos = 1 where id = q3;
  set local role service_role;
  st := public.correo_cola_fallo(q3, 'terminal', true);
  total := total + 1; res := res || case when st = 'error' then '' else E'\nFALLA: fallo terminal debía ser error' end;
  -- agotado: lease vencido con los intentos gastados
  reset role;
  update public.correos_cola set estado = 'enviando', intentos = 10, reclamado_hasta = now() - interval '1 minute', error = null where id = q4;
  set local role service_role;
  perform public.correo_cola_reclamar(5);
  reset role;
  select c.estado, c.error into st, e from public.correos_cola c where c.id = q4;
  total := total + 1; res := res || case when st = 'error' and e = 'agotado' then '' else E'\nFALLA: lease vencido con 10 intentos debía ser error/agotado: ' || st || '/' || coalesce(e, '-') end;

  -- ══ 8. salud y purga ══════════════════════════════════════════════════════════════════════════════════════
  set local role service_role;
  select * into rec from public.correo_cola_salud();
  s1 := rec.en_error;
  total := total + 1; res := res || case when s1 >= 3 then '' else E'\nFALLA: salud no cuenta los errores: ' || to_jsonb(rec)::text end;
  -- encolar de nuevo un documento en `error` lo REABRE (si no, quien encola cree que salió y no sale)
  j := public.correo_encolar('enlace_firma_cadena', f6);
  total := total + 1; res := res || case when (j->>'reabierto')::boolean and j->>'estado' = 'pendiente' and not (j->>'nuevo')::boolean
                                    then '' else E'\nFALLA: reencolar tras error no lo reabrió: ' || j::text end;
  reset role;
  select c.intentos, c.error into n, e from public.correos_cola c where c.id = (j->>'id')::uuid;
  total := total + 1; res := res || case when n = 0 and e is null and (j->>'id')::uuid = q1 then '' else E'\nFALLA: la fila reabierta no quedó limpia (misma fila, intentos 0): ' || n || '/' || coalesce(e, '-') end;
  set local role service_role;
  select * into rec from public.correo_cola_salud();
  total := total + 1; res := res || case when rec.en_error = s1 - 1 then '' else E'\nFALLA: salud debía bajar un error al reabrir: ' || s1 || ' -> ' || rec.en_error end;
  -- una fila `pendiente` no se reabre ni se duplica
  j := public.correo_encolar('enlace_firma_cadena', f6);
  total := total + 1; res := res || case when not (j->>'nuevo')::boolean and not (j->>'reabierto')::boolean and j->>'estado' = 'pendiente' then '' else E'\nFALLA: reencolar una pendiente: ' || j::text end;
  reset role;
  -- un error de hace 91 días: se conserva (la purga no lo toca) y deja de dar la alarma (>30 días)
  update public.correos_cola set encolado_en = now() - interval '91 days' where id = q2;
  set local role service_role;
  select * into rec from public.correo_cola_salud();
  total := total + 1; res := res || case when rec.en_error = s1 - 2 then '' else E'\nFALLA: un error de 91 días no debía dar alarma: ' || to_jsonb(rec)::text end;
  reset role;
  update public.correos_cola set enviado_en = now() - interval '91 days' where estado = 'ok';
  set local role service_role;
  n := public.correos_cola_purga();
  total := total + 1; res := res || case when n >= 1 then '' else E'\nFALLA: la purga de 90 días no borró nada' end;
  reset role;
  total := total + 1; res := res || case when exists (select 1 from public.correos_cola c where c.id = q2 and c.estado = 'error') then '' else E'\nFALLA: la purga se llevó una fila en error' end;
  total := total + 1; res := res || case when not exists (select 1 from public.correos_cola c where c.estado = 'ok') then '' else E'\nFALLA: la purga dejó filas ok de hace 91 días' end;

  raise exception 'RESULTADO: % (% comprobaciones)%', case when res = '' then 'OK' else 'HAY FALLOS' end, total, res;
end
$t$;
