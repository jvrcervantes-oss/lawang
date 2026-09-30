-- destructivo-ok: prueba que se deshace sola (raise exception final); los delete/update solo intentan tocar sociedades de prueba y filas reales que el candado rechaza, y todo se revierte.
-- PRUEBA — Ajustes del ERP, S2 + S3 (20260930200000_ajustes_sociedades_identidad). 30-sep-2026.
-- Encargo: encargos/20260930_erp_ajustes_pantalla.md. Criterio de S3: la identidad fiscal de una sociedad CON documentos no se puede
-- cambiar ni por la RPC ni con un UPDATE directo (service_role, ni con claims de otro rol); la clave no se cambia de NINGUNA forma;
-- desactivar con documentos abiertos se rechaza; el logo solo entra si es una imagen PNG/JPEG/WebP del bucket o una ruta heredada;
-- nadie que no sea super admin escribe; el registro guarda antes y después. Criterio de S2: cambiar el nombre del ERP queda en el
-- registro y lo lee `instancia_marca()` cualquier sesión.
--
-- Se ejecuta ENTERA como postgres (MCP execute_sql / psql), y CAMBIA de rol dentro (`set local role authenticated|anon|service_role`)
-- con claims reales, para que se prueben los GRANT, los triggers y las policies de verdad. NO ESCRIBE NADA: termina en
-- `raise exception 'FIN DE PRUEBAS…'`, que deshace la transacción entera (el helper _zz_* también se deshace). Los usuarios y el socio
-- de prueba se montan con session_replication_role = replica; NUNCA durante los casos (se saltaría los triggers que se prueban).
-- No emite ninguna factura ni gasta ningún número de serie.
--   Lawang:  se pega este fichero en execute_sql, DESPUÉS de la migración (o justo tras aplicarla).
--   Para probar la migración SIN aplicarla: pegar migración + este fichero en una sola llamada (todo se deshace).
create or replace function public._zz_intenta(q text) returns text language plpgsql as $$
declare st text; h text; m text;
begin
  execute q;
  return 'ok';
exception when others then
  get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint, m = message_text;
  return st || '|' || coalesce(h, '-') || '|' || left(m, 160);
end $$;
grant execute on function public._zz_intenta(text) to public;

do $$
declare
  r text := '';
  u_sa uuid := gen_random_uuid();  m_sa  text := 'super.soc@pruebas.test';
  u_ad uuid := gen_random_uuid();  m_ad  text := 'admin.soc@pruebas.test';
  u_ag uuid := gen_random_uuid();  m_ag  text := 'agente.soc@pruebas.test';
  u_of uuid := gen_random_uuid();  m_of  text := 'super.baja.soc@pruebas.test';
  u_po uuid := gen_random_uuid();  m_po  text := 'portal.soc@pruebas.test';
  soc  constant text := 'prueba_ajustes_a';
  res text; n int; n2 int; f record; c record; v jsonb; d jsonb; k text; nf int; nc int;
  hex64 constant text := repeat('ab', 32);
  base_pl constant jsonb := jsonb_build_object('razon', 'PT PRUEBA UNO', 'domicilio', 'Jl. Prueba 1, Bali', 'npwp', '99.999.999.9-999.999',
      'npwp_label', 'NPWP', 'nib', '1234567890123', 'rep', 'Rep Prueba', 'marca', 'PRUEBA', 'label', 'PT Prueba Uno', 'es_indonesia', true);
begin
  -- ── Preparación (como postgres) ───────────────────────────────────────────────────────────────────────────
  execute 'set local session_replication_role = replica';
  insert into auth.users (id, email, aud, role) values
    (u_sa, m_sa, 'authenticated', 'authenticated'), (u_ad, m_ad, 'authenticated', 'authenticated'),
    (u_ag, m_ag, 'authenticated', 'authenticated'), (u_of, m_of, 'authenticated', 'authenticated'),
    (u_po, m_po, 'authenticated', 'authenticated');
  insert into public.usuarios (user_id, email, nombre, rol, herramientas, activo, numero_usuario) values
    (u_sa, m_sa, 'Super Soc', 'super_admin', '{}', true, 'USR-PRBSO-1'),
    (u_ad, m_ad, 'Admin Soc', 'admin', array['ajustes'], true, 'USR-PRBSO-2'),
    (u_ag, m_ag, 'Agente Soc', 'agente', array['ajustes'], true, 'USR-PRBSO-3'),
    (u_of, m_of, 'Super de baja', 'super_admin', '{}', false, 'USR-PRBSO-4');
  execute 'set local session_replication_role = origin';

  -- ── A. Alta y edición SIN documentos (el super admin) ─────────────────────────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  res := public._zz_intenta(format($q$ select public.sociedad_guarda(%L, %L::jsonb, true) $q$, soc, (base_pl || '{"motivo":"alta de prueba"}')::text));
  execute 'reset role';
  r := r || format(E'\nA1 el super admin da de alta una sociedad de prueba: %s → %s', res, case when res = 'ok' then 'ok' else 'FALLA' end);
  select * into f from public.sociedades where clave = soc;
  r := r || format(E'\nA1b nace activa y con lo enviado (activa=%s, razon=%s) → %s', f.activa, f.razon, case when f.activa and f.razon = 'PT PRUEBA UNO' then 'ok' else 'FALLA' end);
  select * into f from public.ajustes_log where tabla = 'sociedades' and clave = soc order by id desc limit 1;
  r := r || format(E'\nA1c registro del alta: quien=%s, antes=%s, motivo=%s, despues.razon=%s → %s', f.quien, coalesce(f.antes::text, 'null'), f.motivo, f.despues ->> 'razon',
        case when f.quien = m_sa and f.antes is null and f.motivo = 'alta de prueba' and f.despues ->> 'razon' = 'PT PRUEBA UNO' then 'ok' else 'FALLA' end);

  execute 'set local role authenticated';
  for c in select * from (values ('clave con mayúsculas y espacio', 'Mala Clave', true, '22023'), ('clave de 2 letras', 'ab', true, '22023'),
                                 ('clave de 41 caracteres', repeat('a', 41), true, '22023'), ('clave que ya existe', 'tepi_sungai', true, '23505'),
                                 ('editar una que no existe', 'prueba_no_existe', false, 'P0002')) x(que, clave, nueva, esperado) loop
    res := public._zz_intenta(format($q$ select public.sociedad_guarda(%L, %L::jsonb, %L) $q$, c.clave, base_pl::text, c.nueva));
    r := r || format(E'\nA2 %s → %s → %s', c.que, split_part(res, '|', 1), case when split_part(res, '|', 1) = c.esperado then 'ok' else 'FALLA' end);
  end loop;
  execute 'reset role';

  -- Sin documentos, la identidad SÍ se edita y el registro guarda antes y después de lo que cambió
  execute 'set local role authenticated';
  res := public._zz_intenta(format($q$ select public.sociedad_guarda(%L, %L::jsonb, false) $q$, soc,
          '{"razon":"PT PRUEBA UNO CAMBIADA","npwp":"11.111.111.1-111.111","domicilio":"Jl. Nueva 2","motivo":"cambio de prueba"}'));
  execute 'reset role';
  select * into f from public.ajustes_log where tabla = 'sociedades' and clave = soc order by id desc limit 1;
  r := r || format(E'\nA4 sin documentos se cambia razón, NPWP y domicilio: %s; registro antes=%s despues=%s motivo=%s → %s', res, f.antes, f.despues, f.motivo,
        case when res = 'ok' and f.antes = '{"razon":"PT PRUEBA UNO","npwp":"99.999.999.9-999.999","domicilio":"Jl. Prueba 1, Bali"}'::jsonb
                  and f.despues = '{"razon":"PT PRUEBA UNO CAMBIADA","npwp":"11.111.111.1-111.111","domicilio":"Jl. Nueva 2"}'::jsonb
                  and f.motivo = 'cambio de prueba' then 'ok' else 'FALLA' end);
  select * into f from public.sociedades where clave = soc;
  r := r || format(E'\nA4b lo que NO venía se conserva (marca=%s, nib=%s, rep=%s, label=%s) → %s', f.marca, f.nib, f.rep, f.label,
        case when f.marca = 'PRUEBA' and f.nib = '1234567890123' and f.rep = 'Rep Prueba' and f.label = 'PT Prueba Uno' then 'ok' else 'FALLA' end);
  select count(*) into n from public.ajustes_log where tabla = 'sociedades' and clave = soc;
  execute 'set local role authenticated';
  res := public._zz_intenta(format($q$ select public.sociedad_guarda(%L, %L::jsonb, false) $q$, soc, '{"razon":"PT PRUEBA UNO CAMBIADA"}'));
  execute 'reset role';
  select count(*) into n2 from public.ajustes_log where tabla = 'sociedades' and clave = soc;
  r := r || format(E'\nA5 guardar lo mismo no añade fila al registro (%s → %s) → %s', n, n2, case when res = 'ok' and n = n2 then 'ok' else 'FALLA' end);

  -- ── B. Quien no es super admin no escribe: ni por la RPC ni con UPDATE directo ────────────────────────────
  for c in select * from (values ('admin', u_ad, m_ad, 'authenticated'), ('agente', u_ag, m_ag, 'authenticated'),
                                 ('super desactivado', u_of, m_of, 'authenticated'), ('comprador del portal', u_po, m_po, 'authenticated'),
                                 ('anon', null::uuid, null::text, 'anon')) x(quien, uid, mail, rol) loop
    perform set_config('request.jwt.claims', case when c.uid is null then '' else json_build_object('sub', c.uid, 'email', c.mail, 'role', c.rol,
                       'app_metadata', json_build_object('portal', c.quien = 'comprador del portal'))::text end, true);
    execute format('set local role %I', c.rol);
    res := public._zz_intenta(format($q$ select public.sociedad_guarda(%L, %L::jsonb, false) $q$, soc, '{"label":"Intruso"}'));
    r := r || format(E'\nB1 %s por la RPC: %s → %s', c.quien, split_part(res, '|', 1), case when split_part(res, '|', 1) = '42501' then 'ok' else 'FALLA' end);
    res := public._zz_intenta(format($q$ update public.sociedades set label = 'Intruso' where clave = %L $q$, soc));
    r := r || format(E'\nB2 %s con UPDATE directo: %s → %s', c.quien, split_part(res, '|', 1), case when split_part(res, '|', 1) = '42501' then 'ok' else 'FALLA' end);
    execute 'reset role';
  end loop;
  select count(*) into n from public.sociedades where label = 'Intruso';
  r := r || format(E'\nB0 nada intruso quedó escrito: %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);

  -- ── C. La clave no se cambia de NINGUNA forma (trigger de la tabla, sin excepción, ni siquiera para el estudio) ──
  for c in select * from (values ('service_role con claims', 'service_role', json_build_object('role', 'service_role')::text),
                                 ('postgres con claims de super admin (como una RPC definer)', 'postgres',
                                    json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text),
                                 ('postgres SIN claims (la vía del estudio)', 'postgres', '')) x(quien, rol, claims) loop
    perform set_config('request.jwt.claims', c.claims, true);
    execute format('set local role %I', c.rol);
    res := public._zz_intenta(format($q$ update public.sociedades set clave = 'prueba_ajustes_zz' where clave = %L $q$, soc));
    execute 'reset role';
    r := r || format(E'\nC %s intenta cambiar la clave: %s → %s', c.quien, res, case when split_part(res, '|', 1) = 'P0001' and res like '%no se cambia%' then 'ok' else 'FALLA' end);
  end loop;
  select count(*) into n from public.sociedades where clave = soc;
  r := r || format(E'\nC0 la clave sigue siendo la misma: %s → %s', n, case when n = 1 then 'ok' else 'FALLA' end);

  -- ── D. Con documentos, la identidad queda BLOQUEADA ─────────────────────────────────────────────────────────
  execute 'set local session_replication_role = replica';
  insert into public.socios (numero, sociedad, nombre, tipo, activo) values ('PRB-SOC-1', soc, 'Socio de Prueba', 'socio', true);
  execute 'set local session_replication_role = origin';
  d := public._sociedad_docs(soc);
  r := r || format(E'\nD1 la sociedad de prueba ya «tiene documentos»: %s → %s', d, case when (d ->> 'total')::int = 1 and (d ->> 'abiertos')::int = 1 then 'ok' else 'FALLA' end);

  perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  for c in select * from (values ('razon', '"PT OTRA"'), ('marca', '"OTRA MARCA"'), ('npwp', '"1.1.1"'), ('npwp_label', '"NIF"'), ('nib', '"999"'),
                                 ('domicilio', '"Otro sitio 3"'), ('rep', '"Otro Rep"'), ('es_indonesia', 'false'), ('npwp', 'null')) x(campo, valor) loop
    res := public._zz_intenta(format($q$ select public.sociedad_guarda(%L, jsonb_build_object(%L, %L::jsonb), false) $q$, soc, c.campo, c.valor));
    r := r || format(E'\nD2 por la RPC, cambiar «%s» con documentos: %s → %s', c.campo, res,
          case when split_part(res, '|', 1) = 'P0001' and split_part(res, '|', 2) = 'identidad_bloqueada' and res like '%pídeselo al estudio%' then 'ok' else 'FALLA' end);
  end loop;
  execute 'reset role';
  select * into f from public.sociedades where clave = soc;
  r := r || format(E'\nD2b la identidad no se movió (razon=%s, npwp=%s, nib=%s) → %s', f.razon, f.npwp, f.nib,
        case when f.razon = 'PT PRUEBA UNO CAMBIADA' and f.npwp = '11.111.111.1-111.111' and f.nib = '1234567890123' then 'ok' else 'FALLA' end);

  for c in select * from (values ('service_role', 'service_role', json_build_object('role', 'service_role')::text),
                                 ('postgres con claims (definer)', 'postgres', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text)) x(quien, rol, claims) loop
    perform set_config('request.jwt.claims', c.claims, true);
    execute format('set local role %I', c.rol);
    res := public._zz_intenta(format($q$ update public.sociedades set razon = 'PT DIRECTA' where clave = %L $q$, soc));
    execute 'reset role';
    r := r || format(E'\nD3 UPDATE directo de %s sobre la razón: %s → %s', c.quien, res, case when split_part(res, '|', 1) = 'P0001' and split_part(res, '|', 2) = 'identidad_bloqueada' then 'ok' else 'FALLA' end);
  end loop;
  select razon into k from public.sociedades where clave = soc;
  r := r || format(E'\nD3b la razón sigue igual (%s) → %s', k, case when k = 'PT PRUEBA UNO CAMBIADA' then 'ok' else 'FALLA' end);

  -- Lo que SÍ se edita siempre, con documentos
  perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  res := public._zz_intenta(format($q$ select public.sociedad_guarda(%L, %L::jsonb, false) $q$, soc,
          '{"logo":"/contracts/assets/brand/lawang-logo-v3-dark.png","logo_alto":"18mm","folio":"#E6EFE0","tinta":{"primary":"#485B37","deep":"#104C4F"},"emisor_debajo":true,"label":"Etiqueta nueva","orden":42}'));
  execute 'reset role';
  select * into f from public.sociedades where clave = soc;
  r := r || format(E'\nD4 con documentos se editan logo, tinta, folio, emisor_debajo, etiqueta y orden: %s → %s', res,
        case when res = 'ok' and f.logo = '/contracts/assets/brand/lawang-logo-v3-dark.png' and f.tinta = '{"primary":"#485B37","deep":"#104C4F"}'::jsonb
                  and f.folio = '#E6EFE0' and f.emisor_debajo and f.label = 'Etiqueta nueva' and f.orden = 42 and f.logo_alto = '18mm' then 'ok' else 'FALLA' end);

  -- La pantalla vieja manda la fila ENTERA: el mismo contenido (con '' y null equivalentes) no cuenta como cambio de identidad
  execute 'set local role authenticated';
  res := public._zz_intenta(format($q$ select public.sociedad_guarda(%L, %L::jsonb, false) $q$, soc,
          jsonb_build_object('label', 'Etiqueta nueva', 'razon', ' PT PRUEBA UNO CAMBIADA ', 'marca', 'PRUEBA', 'npwp', '11.111.111.1-111.111', 'npwp_label', 'NPWP', 'nib', '1234567890123',
                             'domicilio', 'Jl. Nueva 2', 'rep', 'Rep Prueba', 'logo', '/contracts/assets/brand/lawang-logo-v3-dark.png', 'logo_alto', '18mm', 'folio', '#E6EFE0',
                             'tinta', '{"primary":"#485B37","deep":"#104C4F"}'::jsonb, 'emisor_debajo', true, 'es_indonesia', true, 'activa', true, 'orden', 42)::text));
  r := r || format(E'\nD5 fila entera de la pantalla vieja con lo mismo: %s → %s', res, case when res = 'ok' then 'ok' else 'FALLA' end);
  -- y con una sociedad REAL con documentos (tepi_sungai) y su propia fila: nada cambia
  select jsonb_build_object('label', s.label, 'razon', s.razon, 'marca', s.marca, 'npwp', s.npwp, 'npwp_label', s.npwp_label, 'nib', s.nib, 'domicilio', s.domicilio,
         'rep', s.rep, 'logo', s.logo, 'logo_alto', s.logo_alto, 'folio', s.folio, 'tinta', s.tinta, 'emisor_debajo', s.emisor_debajo, 'es_indonesia', s.es_indonesia,
         'activa', s.activa, 'orden', s.orden) into v from public.sociedades s where s.clave = 'tepi_sungai';
  res := public._zz_intenta(format($q$ select public.sociedad_guarda('tepi_sungai', %L::jsonb, false) $q$, v::text));
  execute 'reset role';
  r := r || format(E'\nD5b tepi_sungai (con cientos de documentos) reguardada con su propia fila: %s → %s', res, case when res = 'ok' then 'ok' else 'FALLA' end);

  -- La vía del estudio: SQL directo sin claims SÍ puede hacer un cambio real (y deja rastro con quien = sistema:sql)
  perform set_config('request.jwt.claims', '', true);
  res := public._zz_intenta(format($q$ update public.sociedades set razon = 'PT CAMBIO DEL ESTUDIO' where clave = %L $q$, soc));
  select * into f from public.ajustes_log where tabla = 'sociedades' and clave = soc order by id desc limit 1;
  r := r || format(E'\nD6 el estudio (SQL sin claims) cambia la razón: %s; registro quien=%s despues=%s → %s', res, f.quien, f.despues,
        case when res = 'ok' and f.quien = 'sistema:sql' and f.despues ->> 'razon' = 'PT CAMBIO DEL ESTUDIO' then 'ok' else 'FALLA' end);
  update public.sociedades set razon = 'PT PRUEBA UNO CAMBIADA' where clave = soc;

  -- ── E. Desactivar y borrar ────────────────────────────────────────────────────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  res := public._zz_intenta(format($q$ select public.sociedad_guarda(%L, '{"activa":false}'::jsonb, false) $q$, soc));
  r := r || format(E'\nE1 desactivar la de prueba con un socio activo (documento abierto): %s → %s', res,
        case when split_part(res, '|', 1) = 'P0001' and split_part(res, '|', 2) = 'desactivar_bloqueado' then 'ok' else 'FALLA' end);
  res := public._zz_intenta($q$ select public.sociedad_guarda('tepi_sungai', '{"activa":false}'::jsonb, false) $q$);
  r := r || format(E'\nE2 desactivar tepi_sungai (documentos abiertos): %s → %s', res,
        case when split_part(res, '|', 1) = 'P0001' and split_part(res, '|', 2) = 'desactivar_bloqueado' then 'ok' else 'FALLA' end);
  res := public._zz_intenta($q$ select public.sociedad_guarda('san_dal_woods', '{"activa":false}'::jsonb, false) $q$);
  r := r || format(E'\nE2b desactivar san_dal_woods: %s → %s', split_part(res, '|', 1) || '|' || split_part(res, '|', 2),
        case when split_part(res, '|', 1) = 'P0001' and split_part(res, '|', 2) = 'desactivar_bloqueado' then 'ok' else 'FALLA' end);
  res := public._zz_intenta($q$ select public.sociedad_guarda('sandal_woods_ltd', '{"activa":false}'::jsonb, false) $q$);
  r := r || format(E'\nE3 desactivar sandal_woods_ltd (sin documentos): %s → %s', res, case when res = 'ok' then 'ok' else 'FALLA' end);
  execute 'reset role';
  update public.socios set activo = false where numero = 'PRB-SOC-1';
  d := public._sociedad_docs(soc);
  perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  res := public._zz_intenta(format($q$ select public.sociedad_guarda(%L, '{"activa":false}'::jsonb, false) $q$, soc));
  r := r || format(E'\nE4 sin documentos ABIERTOS (el socio ya no está activo; abiertos=%s, total=%s) se desactiva: %s → %s', d ->> 'abiertos', d ->> 'total', res, case when res = 'ok' then 'ok' else 'FALLA' end);
  res := public._zz_intenta(format($q$ select public.sociedad_guarda(%L, '{"razon":"PT OTRA VEZ"}'::jsonb, false) $q$, soc));
  r := r || format(E'\nE5 desactivada pero con documentos cerrados, la identidad sigue bloqueada: %s → %s', split_part(res, '|', 1) || '|' || split_part(res, '|', 2),
        case when split_part(res, '|', 1) = 'P0001' and split_part(res, '|', 2) = 'identidad_bloqueada' then 'ok' else 'FALLA' end);
  res := public._zz_intenta(format($q$ select public.sociedad_guarda(%L, '{"activa":true}'::jsonb, false) $q$, soc));
  r := r || format(E'\nE6 reactivar siempre se puede: %s → %s', res, case when res = 'ok' then 'ok' else 'FALLA' end);
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  execute 'set local role service_role';
  res := public._zz_intenta(format($q$ delete from public.sociedades where clave = %L $q$, 'sandal_woods_ltd'));
  execute 'reset role';
  r := r || format(E'\nE7 service_role no borra ni una sociedad SIN documentos: %s → %s', split_part(res, '|', 1) || '|' || split_part(res, '|', 2),
        case when split_part(res, '|', 1) = 'P0001' and split_part(res, '|', 2) = 'sociedad_no_se_borra' then 'ok' else 'FALLA' end);
  perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  res := public._zz_intenta(format($q$ delete from public.sociedades where clave = %L $q$, soc));
  execute 'reset role';
  r := r || format(E'\nE8 un super admin con sesión tampoco borra (sin grant): %s → %s', split_part(res, '|', 1), case when split_part(res, '|', 1) = '42501' then 'ok' else 'FALLA' end);

  -- ── G. Logo: solo imágenes PNG/JPEG/WebP; la ruta heredada o la URL del bucket para ESA clave ─────────────
  execute 'set local role authenticated';
  for c in select * from (values
      ('ruta heredada .png', '/contracts/assets/brand/sandalwoods-lockup.png', true),
      ('ruta heredada .webp en mayúsculas', '/contracts/assets/brand/Logo-1.WEBP', true),
      ('URL del bucket para esta clave', 'https://vtulllundrfennhjddhc.supabase.co/storage/v1/object/public/sociedades/' || soc || '/' || hex64 || '.png', true),
      ('URL del bucket .jpg', 'https://vtulllundrfennhjddhc.supabase.co/storage/v1/object/public/sociedades/' || soc || '/' || hex64 || '.jpg', true),
      ('un SVG heredado', '/contracts/assets/brand/logo.svg', false),
      ('una ruta con subcarpeta y ..', '/contracts/assets/brand/../../../etc/x.png', false),
      ('una dirección ajena', 'https://evil.example/logo.png', false),
      ('javascript:', 'javascript:alert(1)', false),
      ('data:', 'data:image/png;base64,AAAA', false),
      ('URL del bucket de OTRA clave', 'https://vtulllundrfennhjddhc.supabase.co/storage/v1/object/public/sociedades/tepi_sungai/' || hex64 || '.png', false),
      ('URL del bucket con .svg', 'https://vtulllundrfennhjddhc.supabase.co/storage/v1/object/public/sociedades/' || soc || '/' || hex64 || '.svg', false),
      ('URL del bucket con hash corto', 'https://vtulllundrfennhjddhc.supabase.co/storage/v1/object/public/sociedades/' || soc || '/abc.png', false),
      ('URL http (sin s)', 'http://vtulllundrfennhjddhc.supabase.co/storage/v1/object/public/sociedades/' || soc || '/' || hex64 || '.png', false),
      ('URL de OTRO proyecto Supabase (ref ajeno, 20 caracteres)', 'https://abcdefghijklmnopqrst.supabase.co/storage/v1/object/public/sociedades/' || soc || '/' || hex64 || '.png', false),
      ('ref propio como subdominio de otro dominio', 'https://vtulllundrfennhjddhc.supabase.co.evil.example/storage/v1/object/public/sociedades/' || soc || '/' || hex64 || '.png', false),
      ('ref propio precedido de otro prefijo', 'https://xvtulllundrfennhjddhc.supabase.co/storage/v1/object/public/sociedades/' || soc || '/' || hex64 || '.png', false),
      ('URL de otro bucket', 'https://vtulllundrfennhjddhc.supabase.co/storage/v1/object/public/deck/' || soc || '/' || hex64 || '.png', false)
    ) x(que, logo, debe) loop
    res := public._zz_intenta(format($q$ select public.sociedad_guarda(%L, jsonb_build_object('logo', %L::text), false) $q$, soc, c.logo));
    r := r || format(E'\nG %s: %s → %s', c.que, split_part(res, '|', 1) || '|' || split_part(res, '|', 2),
          case when c.debe and res = 'ok' then 'ok' when not c.debe and split_part(res, '|', 1) = '22023' and split_part(res, '|', 2) = 'logo_no_admitido' then 'ok' else 'FALLA' end);
  end loop;
  res := public._zz_intenta(format($q$ select public.sociedad_guarda(%L, '{"logo":null}'::jsonb, false) $q$, soc));
  r := r || format(E'\nG quitar el logo (null): %s → %s', res, case when res = 'ok' then 'ok' else 'FALLA' end);

  -- ── H. Tinta, folio y alto se validan ───────────────────────────────────────────────────────────────────
  for c in select * from (values
      ('tinta con color válido', '{"tinta":{"primary":"#112233","deep":"#445566"}}', true),
      ('tinta con un solo color', '{"tinta":{"primary":"#112233"}}', true),
      ('tinta vacía = hereda', '{"tinta":{"primary":"","deep":""}}', true),
      ('tinta con un color mal escrito', '{"tinta":{"primary":"rojo","deep":"#445566"}}', false),
      ('tinta con url()', '{"tinta":{"primary":"#112233;background:url(x)","deep":"#445566"}}', false),
      ('tinta con una clave inventada', '{"tinta":{"primary":"#112233","x":"#445566"}}', false),
      ('tinta que no es objeto', '{"tinta":"#112233"}', false),
      ('folio válido', '{"folio":"#E7E3D2"}', true), ('folio mal', '{"folio":"beige"}', false),
      ('alto 24mm', '{"logo_alto":"24mm"}', true), ('alto 999px', '{"logo_alto":"999px"}', false), ('alto con calc()', '{"logo_alto":"calc(1mm)"}', false),
      ('orden numérico', '{"orden":7}', true), ('orden texto', '{"orden":"abc"}', false),
      ('activa no booleano', '{"activa":"si"}', false), ('razón vacía', '{"razon":"  "}', false), ('razón con salto de línea', E'{"razon":"a\\nb"}', false)
    ) x(que, pl, debe) loop
    res := public._zz_intenta(format($q$ select public.sociedad_guarda(%L, %L::jsonb, false) $q$, soc, c.pl));
    r := r || format(E'\nH %s: %s → %s', c.que, split_part(res, '|', 1), case when c.debe and res = 'ok' then 'ok' when not c.debe and split_part(res, '|', 1) in ('22023', 'P0001') then 'ok' else 'FALLA' end);
  end loop;
  execute 'reset role';

  -- ── I. Lectura: el lector de Ajustes es de administración ──────────────────────────────────────────────
  for c in select * from (values ('super admin', u_sa, m_sa, 'authenticated', true), ('admin', u_ad, m_ad, 'authenticated', true),
                                 ('agente', u_ag, m_ag, 'authenticated', false), ('super desactivado', u_of, m_of, 'authenticated', false),
                                 ('comprador del portal', u_po, m_po, 'authenticated', false), ('anon', null::uuid, null::text, 'anon', false)) x(quien, uid, mail, rol, debe) loop
    perform set_config('request.jwt.claims', case when c.uid is null then '' else json_build_object('sub', c.uid, 'email', c.mail, 'role', c.rol,
                       'app_metadata', json_build_object('portal', c.quien = 'comprador del portal'))::text end, true);
    execute format('set local role %I', c.rol);
    res := public._zz_intenta($q$ select public.sociedades_ajustes_datos() $q$);
    r := r || format(E'\nI1 %s lee sociedades_ajustes_datos: %s → %s', c.quien, split_part(res, '|', 1),
          case when c.debe and res = 'ok' then 'ok' when not c.debe and split_part(res, '|', 1) = '42501' then 'ok' else 'FALLA' end);
    execute 'reset role';
  end loop;
  perform set_config('request.jwt.claims', json_build_object('sub', u_ad, 'email', m_ad, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v := public.sociedades_ajustes_datos();
  execute 'reset role';
  select count(*) into nf from public.facturas where sociedad = 'tepi_sungai';
  select (e.value ->> 'total')::int into nc from jsonb_array_elements(v -> 'sociedades') s, jsonb_each(s -> 'documentos' -> 'detalle') e
   where s ->> 'clave' = 'tepi_sungai' and e.key = 'facturas';
  r := r || format(E'\nI2 el admin ve 4 sociedades (3 reales + la de prueba), sin poder escribir, y tepi_sungai con %s facturas (real: %s) → %s',
        jsonb_array_length(v -> 'sociedades'), nc, nf, case when jsonb_array_length(v -> 'sociedades') = 4 and (v ->> 'puede_escribir') = 'false' and nc = nf then 'ok' else 'FALLA' end);
  select coalesce(sum(1), 0) into n from public.contratos k
   where coalesce(nullif(btrim(k.datos -> 'fields' ->> 'sociedad_firmante'), ''), case k.tipo when 'ppjb_reserva' then 'san_dal_woods' else 'tepi_sungai' end) = 'tepi_sungai';
  d := public._sociedad_docs('tepi_sungai');
  r := r || format(E'\nI3 contratos de tepi_sungai: la función dice %s, el recuento independiente sobre `datos->fields` dice %s → %s', d -> 'detalle' -> 'contratos' ->> 'total', n,
        case when (d -> 'detalle' -> 'contratos' ->> 'total')::int = n then 'ok' else 'FALLA' end);

  -- canon: cada FK hacia sociedades tiene su fuente en la función (una tabla nueva no se escapa sin aviso)
  for c in select conrelid::regclass::text as t, a.attname as col
             from pg_constraint x join pg_attribute a on a.attrelid = x.conrelid and a.attnum = any (x.conkey)
            where x.contype = 'f' and x.confrelid = 'public.sociedades'::regclass loop
    r := r || format(E'\nJ canon: la FK %s.%s está cubierta por _sociedad_docs_filas → %s', c.t, c.col,
          case when pg_get_functiondef('public._sociedad_docs_filas(text)'::regprocedure) ~ ('public\.' || c.t || '\M') and
                    pg_get_functiondef('public._sociedad_docs_filas(text)'::regprocedure) like '%' || c.col || '%' then 'ok' else 'FALLA' end);
  end loop;

  -- lo que un COMPRADOR puede leer de sociedades (informativo: la propuesta de recorte está sin aplicar)
  perform set_config('request.jwt.claims', json_build_object('sub', u_po, 'email', m_po, 'role', 'authenticated', 'app_metadata', json_build_object('portal', true))::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.sociedades;
  res := public._zz_intenta($q$ select creado_por, actualizado_por from public.sociedades limit 1 $q$);
  execute 'reset role';
  r := r || format(E'\nJ2 INFORMATIVO: un comprador lee %s sociedades; creado_por/actualizado_por (correos del equipo) legibles: %s → %s', n, res,
        case when res = 'ok' then 'EXPUESTO (deuda anterior: contracts/sql/propuesta_sociedades_columnas_comprador.sql)' else 'cerrado' end);

  -- ── M. S2: el nombre del ERP se guarda, queda en el registro y lo lee cualquier sesión ─────────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v := public.ajustes_config_guardar('marca', to_jsonb('Marca Prueba S2'::text), 'prueba S2');
  execute 'reset role';
  select * into f from public.ajustes_log where tabla = 'config_instancia' and clave = 'marca' order by id desc limit 1;
  r := r || format(E'\nM1 «marca» cambia y queda en el registro (quien=%s, despues=%s, motivo=%s) → %s', f.quien, f.despues, f.motivo,
        case when f.quien = m_sa and f.despues = '"Marca Prueba S2"'::jsonb and f.motivo = 'prueba S2' then 'ok' else 'FALLA' end);
  for c in select * from (values ('super admin', u_sa, m_sa), ('agente', u_ag, m_ag), ('comprador del portal', u_po, m_po)) x(quien, uid, mail) loop
    perform set_config('request.jwt.claims', json_build_object('sub', c.uid, 'email', c.mail, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    res := coalesce(public.instancia_marca(), '(null)');
    execute 'reset role';
    r := r || format(E'\nM2 %s lee instancia_marca(): %s → %s', c.quien, res, case when res = 'Marca Prueba S2' then 'ok' else 'FALLA' end);
  end loop;
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  res := public._zz_intenta($q$ select public.instancia_marca() $q$);
  execute 'reset role';
  r := r || format(E'\nM3 anon no llama a instancia_marca(): %s → %s', split_part(res, '|', 1), case when split_part(res, '|', 1) = '42501' then 'ok' else 'FALLA' end);

  raise exception E'FIN DE PRUEBAS (todo se deshace)\n%\n\nFALLAS: %', r, (length(r) - length(replace(r, 'FALLA', ''))) / 5;
end $$;
