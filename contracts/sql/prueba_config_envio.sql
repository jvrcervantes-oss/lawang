-- destructivo-ok: prueba que se deshace sola (raise exception final); el delete/update de config_instancia y las copias de funciones _prueba_* viven solo dentro de la transacción y se revierten.
-- PRUEBA — Ajustes del ERP, S5.0 subtarea 2 (20260930230000_config_envio_siembra_y_url). 30-sep-2026.
-- Encargo: encargos/20260930_erp_ajustes_pantalla.md. Criterio: la siembra de config_instancia existe con la forma que lee la
-- edge (jsonb de texto); ninguna de sus claves es editable ni legible desde Ajustes (22023 / no aparecen); las dos funciones que
-- mandan correo siguen cerradas a anon/authenticated y resuelven la URL desde url_envio_correo, con caída al literal del PHP.
--
-- Se ejecuta ENTERA como postgres (MCP execute_sql / psql). NO ENVÍA NINGÚN CORREO: las funciones reales no se llaman; se prueban
-- COPIAS creadas dentro de la transacción (misma definición vigente, con net.http_post sustituida por una captura de la URL).
-- Termina en `raise exception 'FIN DE PRUEBAS…'`, que deshace todo. Maestro: la siembra y las funciones son de Lawang (el maestro
-- no tiene _avisar_equipo_soporte); este fichero solo corre en Lawang.
do $$
declare
  r text := '';
  claves constant text[] := array['dominio_web','url_intranet','url_envio_correo','email_avisos_soporte','email_avisos_sistema','asunto_por_defecto'];
  literal constant text := 'https://lawangproperties.com/contracts/api/send_email.php';
  u_sa uuid := gen_random_uuid();  m_sa text := 'super.envio@pruebas.test';
  k text; n int; def text; v jsonb; got text; ok boolean; sqlst text;
begin
  -- ── A. Siembra presente y con la forma que lee la edge ────────────────────────────────────────────────────
  select count(*) into n from public.config_instancia where clave = any (claves) and jsonb_typeof(valor) = 'string' and btrim(valor #>> '{}') <> '';
  r := r || format(E'\nA1 las 6 claves existen, son texto y no están vacías: %s de 6 → %s', n, case when n = 6 then 'ok' else 'FALLA' end);
  select valor #>> '{}' into got from public.config_instancia where clave = 'url_envio_correo';
  r := r || format(E'\nA2 url_envio_correo es el PHP de hoy → %s', case when got = literal then 'ok' else 'FALLA' end);
  select count(*) into n from public.config_instancia where clave in ('dominio_web','url_intranet') and (valor #>> '{}') in ('lawangproperties.com','https://lawangproperties.com');
  r := r || format(E'\nA3 dominio_web y url_intranet (la edge exige https en url_intranet): %s de 2 → %s', n, case when n = 2 then 'ok' else 'FALLA' end);
  select count(*) into n from public.config_instancia where clave in ('email_avisos_soporte','email_avisos_sistema')
     and (valor #>> '{}') ~ '^[^@ ]+@lawangproperties\.com$';
  r := r || format(E'\nA4 los dos buzones de aviso son del dominio propio (la edge descarta el resto): %s de 2 → %s', n, case when n = 2 then 'ok' else 'FALLA' end);
  select count(*) into n from public.config_instancia where clave in ('marca','logo_correo_url') and false;  -- no se siembran; solo se documenta
  select count(*) into n from public.ajustes_log where tabla = 'config_instancia' and clave = any (claves) and quien like 'sistema:%';
  r := r || format(E'\nA5 el trigger de ajustes_log recogió la siembra con quien=sistema:*: %s filas (≥6) → %s', n, case when n >= 6 then 'ok' else 'FALLA' end);

  -- ── B. Ninguna es editable ni legible desde Ajustes ───────────────────────────────────────────────────────
  foreach k in array claves loop
    if k = any (public._ajustes_claves_editables()) then r := r || format(E'\nB1 «%s» está en _ajustes_claves_editables() → FALLA', k); end if;
  end loop;
  r := r || format(E'\nB1 ninguna de las 6 está en _ajustes_claves_editables() (%s editables) → %s', cardinality(public._ajustes_claves_editables()),
        case when not (claves && public._ajustes_claves_editables()) then 'ok' else 'FALLA' end);

  execute 'set local session_replication_role = replica';
  insert into auth.users (id, email, aud, role) values (u_sa, m_sa, 'authenticated', 'authenticated');
  insert into public.usuarios (user_id, email, nombre, rol, herramientas, activo, numero_usuario)
    values (u_sa, m_sa, 'Super Envio', 'super_admin', '{}', true, 'USR-PRBEV-1');
  execute 'set local session_replication_role = origin';
  perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);

  n := 0;
  foreach k in array claves loop
    execute 'set local role authenticated';
    begin
      perform public.ajustes_config_guardar(k, to_jsonb('https://otro.example/x'::text), 'prueba');
    exception when sqlstate '22023' then n := n + 1;
              when others then null;
    end;
    execute 'reset role';
  end loop;
  r := r || format(E'\nB2 super admin intenta escribir cada una por la RPC de Ajustes: %s de 6 rechazadas con 22023 → %s', n, case when n = 6 then 'ok' else 'FALLA' end);

  execute 'set local role authenticated';
  v := public.ajustes_config_datos();
  execute 'reset role';
  select count(*) into n from jsonb_object_keys(v->'valores') x where x = any (claves);
  r := r || format(E'\nB3 ajustes_config_datos() (super admin) no devuelve ninguna de las 6 (valores=%s claves): %s → %s',
        (select count(*) from jsonb_object_keys(v->'valores')), n, case when n = 0 then 'ok' else 'FALLA' end);

  ok := false;
  execute 'set local role authenticated';
  begin perform 1 from public.config_instancia limit 1;
  exception when insufficient_privilege then ok := true; end;
  execute 'reset role';
  r := r || format(E'\nB4 authenticated no lee config_instancia directamente (42501) → %s', case when ok then 'ok' else 'FALLA' end);

  -- ── C. Las dos funciones siguen cerradas ───────────────────────────────────────────────────────────────────
  n := 0;
  foreach k in array array['public._avisar_equipo_soporte(uuid,text,text)', 'public.revisar_almacenamiento()'] loop
    if not has_function_privilege('anon', k, 'execute') and not has_function_privilege('authenticated', k, 'execute')
       and has_function_privilege('service_role', k, 'execute')
       and (select prosecdef and proconfig = array['search_path=""'] from pg_proc where oid = k::regprocedure) then n := n + 1; end if;
  end loop;
  r := r || format(E'\nC1 _avisar_equipo_soporte y revisar_almacenamiento: anon y authenticated sin execute, service_role con execute, SECURITY DEFINER y search_path vacío: %s de 2 → %s',
        n, case when n = 2 then 'ok' else 'FALLA' end);

  -- ── D. La URL se lee de url_envio_correo y cae al literal ──────────────────────────────────────────────────
  create function public._prueba_captura(url text, headers jsonb, body jsonb) returns void language plpgsql as
    $f$ begin perform set_config('prueba.url', coalesce(url, '<null>'), true); end $f$;
  create function public._prueba_uso() returns jsonb language sql as
    $f$ select '{"dias_de_margen":5,"ritmo_mb_dia":1,"buckets":"x","ficheros":{"pct":90,"bytes":9437184,"limite":10485760},"base":{"pct":10,"bytes":1048576,"limite":10485760}}'::jsonb $f$;

  select pg_get_functiondef('public._avisar_equipo_soporte(uuid,text,text)'::regprocedure) into def;
  r := r || format(E'\nD0a _avisar_equipo_soporte real: lee url_envio_correo=%s, ya sin URL literal en la llamada=%s → %s',
        position('url_envio_correo' in def) > 0, position('url := ''https' in def) = 0,
        case when position('url_envio_correo' in def) > 0 and position('url := ''https' in def) = 0 then 'ok' else 'FALLA' end);
  sqlst := replace(replace(def, 'public._avisar_equipo_soporte', 'public._prueba_avisar_copia'), 'net.http_post', 'public._prueba_captura');
  -- el INSERT del cooldown se quita de la copia: con un client_id inventado violaría la FK y el `exception when others` de la función
  -- deshace la captura de la URL (subtransacción). Lo que se prueba aquí es la resolución de la URL, no el cooldown.
  sqlst := regexp_replace(sqlst, 'insert into public\.avisos_soporte_equipo.*?do update set enviado_en = now\(\);', 'null;', 's');
  if position('avisos_soporte_equipo (client_id' in sqlst) > 0 then raise exception 'la copia de prueba conserva el INSERT del cooldown'; end if;
  execute sqlst;
  select pg_get_functiondef('public.revisar_almacenamiento()'::regprocedure) into def;
  r := r || format(E'\nD0b revisar_almacenamiento real: lee url_envio_correo=%s, ya sin URL literal en la llamada=%s → %s',
        position('url_envio_correo' in def) > 0, position('url := ''https' in def) = 0,
        case when position('url_envio_correo' in def) > 0 and position('url := ''https' in def) = 0 then 'ok' else 'FALLA' end);
  sqlst := replace(replace(replace(replace(def, 'public.revisar_almacenamiento', 'public._prueba_revisar_copia'),
             'net.http_post', 'public._prueba_captura'), 'public._uso_almacenamiento()', 'public._prueba_uso()'),
             'interval ''7 days''', 'interval ''0 seconds''');
  execute sqlst;

  -- D1: con la clave presente y un valor distinto, la copia usa ese valor
  update public.config_instancia set valor = to_jsonb('https://ejemplo.invalid/envia'::text) where clave = 'url_envio_correo';
  perform set_config('prueba.url', '', true);
  perform public._prueba_avisar_copia(gen_random_uuid(), 'asunto', 'cuerpo');
  got := current_setting('prueba.url', true);
  r := r || format(E'\nD1 _avisar_equipo_soporte con la clave cambiada a otro valor usa ese valor → %s', case when got = 'https://ejemplo.invalid/envia' then 'ok' else 'FALLA (' || coalesce(got, 'null') || ')' end);
  perform set_config('prueba.url', '', true);
  got := public._prueba_revisar_copia();
  r := r || format(E'\nD2 revisar_almacenamiento (copia con uso simulado al 90%%) usa ese valor; devolvió «%s» → %s', got,
        case when current_setting('prueba.url', true) = 'https://ejemplo.invalid/envia' then 'ok' else 'FALLA (' || coalesce(current_setting('prueba.url', true), 'null') || ')' end);

  -- D3: sin la clave -> literal del PHP
  delete from public.config_instancia where clave = 'url_envio_correo';
  perform set_config('prueba.url', '', true);
  perform public._prueba_avisar_copia(gen_random_uuid(), 'asunto', 'cuerpo');
  ok := current_setting('prueba.url', true) = literal;
  perform set_config('prueba.url', '', true);
  perform public._prueba_revisar_copia();
  r := r || format(E'\nD3 con la clave borrada, las dos caen al literal del PHP → %s',
        case when ok and current_setting('prueba.url', true) = literal then 'ok' else 'FALLA' end);

  -- D4: valor vacío o no-texto -> literal
  n := 0;
  foreach v in array array['""'::jsonb, '"   "'::jsonb, '42'::jsonb, '{"a":1}'::jsonb, '["x"]'::jsonb] loop
    delete from public.config_instancia where clave = 'url_envio_correo';
    insert into public.config_instancia (clave, valor) values ('url_envio_correo', v);
    perform set_config('prueba.url', '', true);
    perform public._prueba_avisar_copia(gen_random_uuid(), 'asunto', 'cuerpo');
    if current_setting('prueba.url', true) = literal then n := n + 1; end if;
  end loop;
  r := r || format(E'\nD4 valor vacío, en blanco, número, objeto o lista → literal del PHP: %s de 5 → %s', n, case when n = 5 then 'ok' else 'FALLA' end);

  raise exception E'FIN DE PRUEBAS (transacción deshecha)%\nCasos con FALLA: %', r,
    (select count(*) from regexp_matches(r, 'FALLA', 'g'));
end $$;
