-- destructivo-ok: prueba que se deshace sola (raise exception final); los delete/truncate solo intentan tocar ajustes_log o una clave de prueba y todo se revierte.
-- PRUEBA — Ajustes del ERP, S1 (20260930190000_ajustes_config_log). 30-sep-2026.
-- Encargo: encargos/20260930_erp_ajustes_pantalla.md. Criterio de S1: un no-super-admin no escribe (42501); una clave fuera de la
-- lista blanca se rechaza en servidor (22023); el log registra quién, cuándo, antes y después; el log no admite UPDATE, DELETE ni
-- TRUNCATE ni con super admin; las lecturas respetan el rol.
--
-- Se ejecuta ENTERA como postgres (MCP execute_sql / psql), y CAMBIA de rol dentro (`set local role authenticated|anon`) para
-- que se prueben los GRANT y las policies de verdad, no solo el cuerpo de las funciones. NO ESCRIBE NADA: termina en
-- `raise exception 'FIN DE PRUEBAS…'`, que deshace la transacción entera. No usa session_replication_role = replica salvo para
-- montar los usuarios de prueba (nunca durante los casos: se saltaría los triggers que se están probando).
--   Lawang:  se pega este fichero en execute_sql (contracts/sql/prueba_ajustes_config.sql).
--   Maestro: python erp/pruebas/corre.py <instancia> ajustes_config.sql   (mismo cuerpo).
do $$
declare
  r text := '';
  u_sa uuid := gen_random_uuid();  m_sa  text := 'super.ajustes@pruebas.test';
  u_ad uuid := gen_random_uuid();  m_ad  text := 'admin.ajustes@pruebas.test';
  u_ag uuid := gen_random_uuid();  m_ag  text := 'agente.ajustes@pruebas.test';
  u_of uuid := gen_random_uuid();  m_of  text := 'super.baja.ajustes@pruebas.test';
  u_po uuid := gen_random_uuid();  m_po  text := 'portal.ajustes@pruebas.test';
  st text; h text; v jsonb; n int; n2 int; f record; c record; pv jsonb; ok boolean;
  pk text; pval jsonb; pmax numeric; pmin numeric; pnuevo numeric;
begin
  -- ── Preparación (como postgres) ───────────────────────────────────────────────────────────────────────────
  execute 'set local session_replication_role = replica';
  insert into auth.users (id, email, aud, role) values
    (u_sa, m_sa, 'authenticated', 'authenticated'), (u_ad, m_ad, 'authenticated', 'authenticated'),
    (u_ag, m_ag, 'authenticated', 'authenticated'), (u_of, m_of, 'authenticated', 'authenticated'),
    (u_po, m_po, 'authenticated', 'authenticated');
  insert into public.usuarios (user_id, email, nombre, rol, herramientas, activo, numero_usuario) values
    (u_sa, m_sa, 'Super Ajustes', 'super_admin', '{}', true, 'USR-PRBAJ-1'),
    (u_ad, m_ad, 'Admin Ajustes', 'admin', array['ajustes'], true, 'USR-PRBAJ-2'),
    (u_ag, m_ag, 'Agente Ajustes', 'agente', array['ajustes'], true, 'USR-PRBAJ-3'),
    (u_of, m_of, 'Super de baja', 'super_admin', '{}', false, 'USR-PRBAJ-4');
  execute 'set local session_replication_role = origin';
  select valor into pv from public.config_instancia where clave = 'marca';

  -- ── A. El super admin escribe y el log dice quién, cuándo, antes y después ────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v := public.ajustes_config_guardar('marca', to_jsonb('Marca Prueba Uno'::text), 'prueba S1');
  execute 'reset role';
  select * into f from public.ajustes_log where tabla = 'config_instancia' and clave = 'marca' order by id desc limit 1;
  r := r || format(E'\nA1 super admin cambia «marca»: cambiado=%s, log(quien=%s, antes=%s, despues=%s, motivo=%s, cuando≈ahora=%s) → %s',
        v->>'cambiado', f.quien, coalesce(f.antes::text, 'null'), f.despues, f.motivo, abs(extract(epoch from now() - f.cuando)) < 5,
        case when v->>'cambiado' = 'true' and f.quien = m_sa and f.antes is not distinct from pv
                  and f.despues = '"Marca Prueba Uno"'::jsonb and f.motivo = 'prueba S1' and abs(extract(epoch from now() - f.cuando)) < 5
             then 'ok' else 'FALLA' end);
  select count(*) into n from public.ajustes_log where clave = 'marca';
  execute 'set local role authenticated';
  v := public.ajustes_config_guardar('marca', to_jsonb('Marca Prueba Uno'::text), 'igual');
  execute 'reset role';
  select count(*) into n2 from public.ajustes_log where clave = 'marca';
  r := r || format(E'\nA2 guardar el mismo valor: cambiado=%s y el log no crece (%s → %s) → %s', v->>'cambiado', n, n2,
        case when v->>'cambiado' = 'false' and n = n2 then 'ok' else 'FALLA' end);
  execute 'set local role authenticated';
  v := public.ajustes_config_guardar('marca', to_jsonb('Marca Prueba Dos'::text));
  execute 'reset role';
  select * into f from public.ajustes_log where tabla = 'config_instancia' and clave = 'marca' order by id desc limit 1;
  r := r || format(E'\nA3 segundo cambio: antes=%s despues=%s motivo=%s → %s', f.antes, f.despues, coalesce(f.motivo, 'null'),
        case when f.antes = '"Marca Prueba Uno"'::jsonb and f.despues = '"Marca Prueba Dos"'::jsonb and f.motivo is null then 'ok' else 'FALLA' end);

  -- ── B. Quien no es super admin no escribe: 42501 (admin, agente, super desactivado, comprador del portal, anon) ──
  for c in select * from (values ('admin', u_ad, m_ad, 'authenticated'), ('agente', u_ag, m_ag, 'authenticated'),
                                 ('super desactivado', u_of, m_of, 'authenticated'), ('comprador del portal', u_po, m_po, 'authenticated'),
                                 ('anon', null::uuid, null::text, 'anon')) x(quien, uid, mail, rol) loop
    perform set_config('request.jwt.claims', case when c.uid is null then '' else json_build_object('sub', c.uid, 'email', c.mail, 'role', c.rol,
                       'app_metadata', json_build_object('portal', c.quien = 'comprador del portal'))::text end, true);
    execute format('set local role %I', c.rol);
    begin
      perform public.ajustes_config_guardar('marca', to_jsonb('Marca Intrusa'::text));
      execute 'reset role';
      r := r || format(E'\nB %s escribe → FALLA (entró)', c.quien);
    exception when others then
      execute 'reset role';
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nB %s no escribe (sqlstate %s) → %s', c.quien, st, case when st = '42501' then 'ok' else 'FALLA' end);
    end;
  end loop;
  select count(*) into n from public.config_instancia where clave = 'marca' and valor = '"Marca Intrusa"'::jsonb;
  r := r || format(E'\nB0 ninguna escritura intrusa quedó en config_instancia: %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);

  -- ── C. Una clave fuera de la lista se rechaza EN SERVIDOR, también para el super admin ────────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  for c in select k from unnest(array['modulos_activos', 'url_supabase', 'smtp_pass', 'clave_inventada', '', 'marca ']) k loop
    begin
      perform public.ajustes_config_guardar(c.k, '"x"'::jsonb);
      r := r || format(E'\nC «%s» fuera de la lista → FALLA (entró)', c.k);
    exception when others then
      get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint;
      r := r || format(E'\nC «%s» fuera de la lista (sqlstate %s, hint %s) → %s', c.k, st, coalesce(h, '-'),
            case when st = '22023' and h = 'clave_no_editable' then 'ok' else 'FALLA' end);
    end;
  end loop;
  begin
    perform public.ajustes_config_guardar(null, '"x"'::jsonb);
    r := r || E'\nC clave null → FALLA (entró)';
  exception when others then
    get stacked diagnostics st = returned_sqlstate;
    r := r || format(E'\nC clave null (sqlstate %s) → %s', st, case when st = '22023' then 'ok' else 'FALLA' end);
  end;
  execute 'reset role';
  select count(*) into n from public.config_instancia where clave in ('smtp_pass', 'clave_inventada', '');
  r := r || format(E'\nC0 ninguna clave fuera de la lista se creó: %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);

  -- ── D. Cada valor se valida: lo malo se rechaza (22023) y lo bueno entra normalizado ───────────────────────
  execute 'set local role authenticated';
  for c in select e->>'c' as clave, e->'v' as valor from jsonb_array_elements($j$[
      {"c":"marca","v":"<b>x</b>"}, {"c":"marca","v":""}, {"c":"marca","v":123}, {"c":"marca","v":"a\nb"},
      {"c":"email_from","v":"no-es-un-correo"}, {"c":"email_from","v":""}, {"c":"email_from","v":"a@b.com\nBcc: x@y.com"},
      {"c":"email_from","v":".a@x.com"}, {"c":"email_from","v":"a.@x.com"}, {"c":"email_from","v":"a..b@x.com"},
      {"c":"email_from","v":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@x.com"},
      {"c":"email_reply_to","v":"x"}, {"c":"email_avisos_reservas","v":["a@b.com"]}, {"c":"email_avisos_reservas","v":""},
      {"c":"email_avisos_crm","v":"x@"}, {"c":"logo_correo_url","v":"http://x.com/a.png"},
      {"c":"logo_correo_url","v":"https://x.com/a b.png"}, {"c":"logo_correo_url","v":"https://x.com/a.png\"onerror=\"x"},
      {"c":"zona_horaria","v":"Mars/Base"}, {"c":"zona_horaria","v":"PST"}]$j$::jsonb) e loop
    begin
      perform public.ajustes_config_guardar(c.clave, c.valor);
      r := r || format(E'\nD «%s» = %s → FALLA (entró)', c.clave, left(c.valor::text, 40));
    exception when others then
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nD «%s» = %s se rechaza (%s) → %s', c.clave, left(c.valor::text, 40), st, case when st = '22023' then 'ok' else 'FALLA' end);
    end;
  end loop;
  for c in select e->>'c' as clave, e->'v' as valor, e->'esperado' as esperado from jsonb_array_elements($j$[
      {"c":"email_reply_to","v":"","esperado":""}, {"c":"email_avisos_crm","v":"","esperado":""}, {"c":"logo_correo_url","v":"","esperado":""},
      {"c":"logo_correo_url","v":"https://cdn.ejemplo.com/logo.png?v=2","esperado":"https://cdn.ejemplo.com/logo.png?v=2"},
      {"c":"zona_horaria","v":"Asia/Makassar","esperado":"Asia/Makassar"}, {"c":"email_from","v":"  Hola@Pruebas.Test ","esperado":"Hola@Pruebas.Test"},
      {"c":"email_avisos_reservas","v":"reservas@pruebas.test","esperado":"reservas@pruebas.test"},
      {"c":"email_reply_to","v":"a.b+c_d%e@x.co.id","esperado":"a.b+c_d%e@x.co.id"}]$j$::jsonb) e loop
    begin
      v := public.ajustes_config_guardar(c.clave, c.valor);
      r := r || format(E'\nD+ «%s» = %s entra como %s → %s', c.clave, left(c.valor::text, 40), v->>'valor', case when v->'valor' = c.esperado then 'ok' else 'FALLA' end);
    exception when others then
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nD+ «%s» = %s se rechaza (%s) → FALLA', c.clave, left(c.valor::text, 40), st);
    end;
  end loop;
  execute 'reset role';

  -- ── E. El log no admite UPDATE, DELETE ni TRUNCATE: ni el super admin (falta el grant) ni postgres (trigger) ──
  execute 'set local role authenticated';
  for c in select * from (values ('update', 'update public.ajustes_log set quien = ''otro'''), ('delete', 'delete from public.ajustes_log'),
                                 ('truncate', 'truncate public.ajustes_log'), ('insert', 'insert into public.ajustes_log (tabla, clave, quien) values (''x'', ''x'', ''x'')'),
                                 ('select', 'select count(*) from public.ajustes_log')) x(op, q) loop
    begin
      execute c.q;
      r := r || format(E'\nE1 super admin (sesión) %s del log → FALLA (entró)', c.op);
    exception when others then
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nE1 super admin (sesión) %s del log negado (sqlstate %s) → %s', c.op, st, case when st = '42501' then 'ok' else 'FALLA' end);
    end;
  end loop;
  execute 'reset role';
  for c in select * from (values ('update', 'update public.ajustes_log set quien = ''otro'''), ('delete', 'delete from public.ajustes_log'),
                                 ('truncate', 'truncate public.ajustes_log')) x(op, q) loop
    begin
      execute c.q;
      r := r || format(E'\nE2 postgres %s del log → FALLA (entró)', c.op);
    exception when others then
      get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint;
      r := r || format(E'\nE2 postgres %s del log lo impide el trigger (sqlstate %s, hint %s) → %s', c.op, st, coalesce(h, '-'),
            case when st = '42501' and h = 'ajustes_log_inmutable' then 'ok' else 'FALLA' end);
    end;
  end loop;
  select count(*) into n from public.ajustes_log where quien = 'otro';
  r := r || format(E'\nE3 nada del log se modificó: %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);

  -- ── F. Una clave sensible se registra REDACTADA (el log dice que cambió, no el secreto) ────────────────────
  perform set_config('request.jwt.claims', '', true);
  insert into public.config_instancia (clave, valor) values ('smtp_pass_prueba', '"secreto-de-prueba"'::jsonb);
  update public.config_instancia set valor = '"otro-secreto"'::jsonb where clave = 'smtp_pass_prueba';
  select count(*) filter (where despues = '"[redactado]"'::jsonb), count(*) filter (where despues::text like '%secreto%' or antes::text like '%secreto%'),
         min(quien) into n, n2, st from public.ajustes_log where clave = 'smtp_pass_prueba';
  r := r || format(E'\nF clave sensible: %s filas redactadas, %s filas con el secreto en claro, quien=%s → %s', n, n2, st,
        case when n = 2 and n2 = 0 and st = 'sistema:sql' then 'ok' else 'FALLA' end);
  delete from public.config_instancia where clave = 'smtp_pass_prueba';
  select count(*) into n from public.ajustes_log where clave = 'smtp_pass_prueba' and antes = '"[redactado]"'::jsonb and despues is null;
  r := r || format(E'\nF2 borrar una clave también deja rastro (despues null): %s → %s', n, case when n = 1 then 'ok' else 'FALLA' end);

  -- ── G. Reservas (`parametros`) deja el mismo rastro por parametro_set ───────────────────────────────────────
  select p.clave, p.valor, p.minimo, p.maximo into pk, pval, pmin, pmax from public.parametros p where jsonb_typeof(p.valor) = 'number' order by p.orden limit 1;
  if pk is null then
    r := r || E'\nG parametros sin filas numéricas: NO PROBADO';
  else
    pnuevo := case when (pval#>>'{}')::numeric + 1 <= coalesce(pmax, 1e9) then (pval#>>'{}')::numeric + 1 else (pval#>>'{}')::numeric - 1 end;
    perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.parametro_set(pk, to_jsonb(pnuevo));
    execute 'reset role';
    select * into f from public.ajustes_log where tabla = 'parametros' and clave = pk order by id desc limit 1;
    r := r || format(E'\nG parametro_set(%s): log(tabla=%s, quien=%s, antes=%s, despues=%s) → %s', pk, f.tabla, f.quien, f.antes, f.despues,
          case when f.quien = m_sa and f.antes = pval and f.despues = to_jsonb(pnuevo) then 'ok' else 'FALLA' end);
  end if;

  -- ── H. Las lecturas respetan el rol ───────────────────────────────────────────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v := public.ajustes_config_datos();
  r := r || format(E'\nH1 super admin lee la config: puede_escribir=%s, marca=%s, 7 editables=%s → %s', v->>'puede_escribir', v->'valores'->>'marca',
        jsonb_array_length(v->'editables') = 7,
        case when (v->>'puede_escribir')::boolean and v->'valores'->>'marca' = 'Marca Prueba Dos' and jsonb_array_length(v->'editables') = 7 then 'ok' else 'FALLA' end);
  v := public.ajustes_log_datos(500);
  select count(*) filter (where e->>'clave' = 'marca' and e->>'quien' = m_sa) into n from jsonb_array_elements(v->'filas') e;
  r := r || format(E'\nH2 super admin lee el registro: %s filas de «marca» suyas → %s', n, case when n >= 2 then 'ok' else 'FALLA' end);
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ad, 'email', m_ad, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v := public.ajustes_config_datos();
  r := r || format(E'\nH3 admin (no super) lee la config en solo lectura: puede_escribir=%s, marca=%s → %s', v->>'puede_escribir', v->'valores'->>'marca',
        case when not (v->>'puede_escribir')::boolean and v->'valores'->>'marca' = 'Marca Prueba Dos' then 'ok' else 'FALLA' end);
  begin
    perform public.ajustes_log_datos(10);
    r := r || E'\nH4 admin (no super) lee el registro → FALLA (entró)';
  exception when others then
    get stacked diagnostics st = returned_sqlstate;
    r := r || format(E'\nH4 admin (no super) no lee el registro (sqlstate %s) → %s', st, case when st = '42501' then 'ok' else 'FALLA' end);
  end;
  execute 'reset role';
  for c in select * from (values ('agente', u_ag, m_ag), ('super desactivado', u_of, m_of), ('comprador del portal', u_po, m_po)) x(quien, uid, mail) loop
    perform set_config('request.jwt.claims', json_build_object('sub', c.uid, 'email', c.mail, 'role', 'authenticated',
                       'app_metadata', json_build_object('portal', c.quien = 'comprador del portal'))::text, true);
    execute 'set local role authenticated';
    begin
      perform public.ajustes_config_datos();
      r := r || format(E'\nH5 %s lee la config → FALLA (entró)', c.quien);
    exception when others then
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nH5 %s no lee la config (sqlstate %s) → %s', c.quien, st, case when st = '42501' then 'ok' else 'FALLA' end);
    end;
    begin
      perform public.ajustes_log_datos(10);
      r := r || format(E'\nH6 %s lee el registro → FALLA (entró)', c.quien);
    exception when others then
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nH6 %s no lee el registro (sqlstate %s) → %s', c.quien, st, case when st = '42501' then 'ok' else 'FALLA' end);
    end;
    execute 'reset role';
  end loop;

  -- ── I. Lo que no es de la lista no sale por la lectura; la tabla sigue cerrada al navegador ─────────────────
  perform set_config('request.jwt.claims', '', true);
  insert into public.config_instancia (clave, valor) values ('url_supabase', '"https://no-debe-salir.example"'::jsonb)
    on conflict (clave) do update set valor = excluded.valor;
  perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v := public.ajustes_config_datos();
  r := r || format(E'\nI1 la lectura no devuelve claves fuera de la lista: %s → %s', v::text like '%no-debe-salir%',
        case when v::text not like '%no-debe-salir%' and not (v->'valores') ? 'url_supabase' then 'ok' else 'FALLA' end);
  begin
    execute 'select count(*) from public.config_instancia';
    r := r || E'\nI2 authenticated lee config_instancia directo → FALLA (entró)';
  exception when others then
    get stacked diagnostics st = returned_sqlstate;
    r := r || format(E'\nI2 authenticated no lee config_instancia directo (sqlstate %s) → %s', st, case when st = '42501' then 'ok' else 'FALLA' end);
  end;
  execute 'reset role';
  select count(*) into n from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('ajustes_config_guardar', 'ajustes_config_datos', 'ajustes_log_datos', '_ajustes_claves_editables', '_ajustes_es_sensible',
                       '_trg_ajustes_log', '_trg_ajustes_log_inmutable')
     and (has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('public', p.oid, 'EXECUTE'));
  r := r || format(E'\nI3 anon/PUBLIC ejecutan 0 funciones de Ajustes: %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);
  select count(*) into n from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('_ajustes_claves_editables', '_ajustes_es_sensible', '_trg_ajustes_log', '_trg_ajustes_log_inmutable')
     and has_function_privilege('authenticated', p.oid, 'EXECUTE');
  r := r || format(E'\nI4 authenticated ejecuta 0 auxiliares/triggers de Ajustes: %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);
  select count(*) into n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('ajustes_config_datos', 'ajustes_log_datos')
     and pg_get_userbyid(p.proowner) in ('lw_lector', 'erp_lector') and p.prosecdef and p.proconfig = array['search_path=""'];
  r := r || format(E'\nI5 las 2 lecturas son DEFINER con dueño lector y search_path vacío: %s → %s', n, case when n = 2 then 'ok' else 'FALLA' end);

  r := r || format(E'\nI6 service_role no puede vaciar config_instancia (rastro): %s → %s', has_table_privilege('service_role', 'public.config_instancia', 'TRUNCATE'),
        case when not has_table_privilege('service_role', 'public.config_instancia', 'TRUNCATE') then 'ok' else 'FALLA' end);

  perform set_config('request.jwt.claims', '', true);
  raise exception 'FIN DE PRUEBAS AJUSTES S1 (se deshace):%', r;
end $$;
