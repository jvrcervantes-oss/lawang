-- destructivo-ok: prueba que se deshace sola (raise exception final); los delete solo vacían correo_smtp_intentos / una clave de prueba dentro de la transacción y todo se revierte.
-- PRUEBA — Correo desde Ajustes en LAWANG, parte 1: servidor de salida en Vault (F3.1; migración 20261010060000_correo_ajustes_servidor_y_codigo). Portada el 8-oct-2026
-- de erp/pruebas/f31_correo_smtp.sql del maestro SIN el instalador (correo_smtp_instala no se porta a Lawang: C2-C5 y su nombre en la lista A). Va con
-- prueba_correo_codigos.sql (parte 2: código de confirmación) y supabase-pruebas/ajustes_config (contracts/sql/prueba_ajustes_config.sql, 6 claves).
-- ESTADO (8-oct-2026): ESCRITA, NO EJECUTADA EN LAWANG (la migración no está aplicada en ninguna base). La del maestro, de la que sale, dio 105/105 en una rama efímera de bbm
-- con las dos migraciones. Antes de aplicar la migración a producción hay que correrla en una rama efímera de Lawang; el resultado «FALLA» manda sobre cualquier lectura de esto.
-- Criterio: el servidor de correo se guarda en Vault por una puerta que solo abre service_role y solo con un super admin ACTIVO; el candidato no se usa hasta promoverlo; el
-- estado y el registro no llevan nunca la contraseña; el límite de intentos vive en la base; las reglas de buzón propio de las claves de correo están en la parte 2.
--
-- Se ejecuta ENTERA como postgres y CAMBIA de rol dentro (`set local role service_role|authenticated|anon`) para probar los GRANT de verdad. Los grants se miden por
-- pg_proc.proacl (aclexplode), NO por has_function_privilege (que dice «sí» por herencia del dueño). NO ESCRIBE NADA: termina en `raise exception 'FIN DE PRUEBAS…'`, que
-- deshace la transacción (incluidos los secretos de Vault).
--   Lawang: se pega entera en execute_sql sobre una RAMA EFÍMERA o sobre la base ya migrada (nunca antes de aplicar la migración: las funciones no existen).
do $$
declare
  r text := '';
  u_sa uuid := gen_random_uuid();  m_sa  text := 'super.correo@pruebas.test';
  u_s2 uuid := gen_random_uuid();  m_s2  text := 'super2.correo@pruebas.test';
  u_ad uuid := gen_random_uuid();  m_ad  text := 'admin.correo@pruebas.test';
  u_of uuid := gen_random_uuid();  m_of  text := 'super.baja.correo@pruebas.test';
  st text; h text; v jsonb; v2 jsonb; n int; c record; tok text; dom text; ok boolean;
  tenia_activo boolean; activo_antes jsonb; sin_activo boolean; dom_from text := 'desde-from.test'; usr_dom text;
begin
  -- ── Preparación (como postgres) ───────────────────────────────────────────────────────────────────────────
  execute 'set local session_replication_role = replica';
  insert into auth.users (id, email, aud, role) values
    (u_sa, m_sa, 'authenticated', 'authenticated'), (u_s2, m_s2, 'authenticated', 'authenticated'),
    (u_ad, m_ad, 'authenticated', 'authenticated'), (u_of, m_of, 'authenticated', 'authenticated');
  insert into public.usuarios (user_id, email, nombre, rol, herramientas, activo, numero_usuario) values
    (u_sa, m_sa, 'Super Correo', 'super_admin', '{}', true, 'USR-PRBCO-1'),
    (u_s2, m_s2, 'Super Dos', 'super_admin', '{}', true, 'USR-PRBCO-2'),
    (u_ad, m_ad, 'Admin Correo', 'admin', array['ajustes'], true, 'USR-PRBCO-3'),
    (u_of, m_of, 'Super de baja', 'super_admin', '{}', false, 'USR-PRBCO-4');
  execute 'set local session_replication_role = origin';
  delete from public.correo_smtp_intentos;
  tenia_activo := public._correo_smtp_existe('smtp_activo');
  sin_activo := not tenia_activo;
  activo_antes := public.correo_smtp_lee();   -- como lo ve envia-correo (NULL si no hay servidor o está vacío tras una vuelta atrás)
  select valor #>> '{}' into dom from public.config_instancia where clave = 'dominio_web' and jsonb_typeof(valor) = 'string';
  if dom is null or dom = '' then
    insert into public.config_instancia (clave, valor) values ('dominio_web', '"pruebas.test"'::jsonb) on conflict (clave) do update set valor = excluded.valor;
    dom := 'pruebas.test';
  end if;

  -- ── A. Nace cerrada: solo service_role ejecuta las 4 públicas; las auxiliares, nadie; la tabla, nadie ───────────
  for c in select p.proname, p.oid, p.prosecdef, p.proconfig, p.proowner from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('correo_smtp_guarda_candidato', 'correo_smtp_promueve', 'correo_smtp_lee', 'correo_smtp_estado', 'correo_smtp_reauth_intento',
                                '_correo_smtp_secreto', '_correo_smtp_pon', '_correo_smtp_actor', '_correo_smtp_existe',
                                '_correo_smtp_valida', '_correo_smtp_activa') loop
    select count(*) filter (where a.grantee <> c.proowner and a.grantee <> 'service_role'::regrole),
           count(*) filter (where a.grantee = 'service_role'::regrole)
      into n, st
      from aclexplode(coalesce((select proacl from pg_proc where oid = c.oid), acldefault('f', c.proowner))) a where a.privilege_type = 'EXECUTE';
    r := r || format(E'\nA %s: ejecutan de más=%s (anon/authenticated/PUBLIC/otros), service_role=%s, DEFINER=%s, search_path vacío=%s → %s', c.proname, n, st, c.prosecdef,
          c.proconfig = array['search_path=""'],
          case when n = 0 and c.prosecdef and c.proconfig = array['search_path=""']
                    and ((c.proname in ('correo_smtp_guarda_candidato', 'correo_smtp_promueve', 'correo_smtp_lee', 'correo_smtp_estado', 'correo_smtp_reauth_intento') and st::int = 1)
                         or (c.proname not in ('correo_smtp_guarda_candidato', 'correo_smtp_promueve', 'correo_smtp_lee', 'correo_smtp_estado', 'correo_smtp_reauth_intento') and st::int = 0)) then 'ok' else 'FALLA' end);
  end loop;
  select count(*) into n from pg_class k where k.oid = 'public.correo_smtp_intentos'::regclass and k.relrowsecurity
     and not exists (select 1 from aclexplode(coalesce(k.relacl, acldefault('r', k.relowner))) a where a.grantee <> k.relowner);
  r := r || format(E'\nA9 correo_smtp_intentos: RLS puesta y sin permisos para nadie más que el dueño → %s', case when n = 1 then 'ok' else 'FALLA' end);
  select count(*) into n from pg_class k, aclexplode(coalesce(k.relacl, acldefault('r', k.relowner))) a
   where k.oid = 'public.correo_smtp_intentos'::regclass and a.grantee = 'service_role'::regrole;
  r := r || format(E'\nA9b service_role NO tiene privilegios directos sobre correo_smtp_intentos (solo llega por las funciones DEFINER): %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);

  -- authenticated y anon no ejecutan nada de esto (42501)
  for c in select * from (values ('authenticated'), ('anon')) x(rol) loop
    execute format('set local role %I', c.rol);
    begin
      perform public.correo_smtp_estado();
      r := r || format(E'\nA10 %s ejecuta correo_smtp_estado → FALLA (entró)', c.rol);
    exception when others then
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nA10 %s no ejecuta correo_smtp_estado (sqlstate %s) → %s', c.rol, st, case when st = '42501' then 'ok' else 'FALLA' end);
    end;
    begin
      perform public.correo_smtp_lee();
      r := r || format(E'\nA11 %s ejecuta correo_smtp_lee → FALLA (entró)', c.rol);
    exception when others then
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nA11 %s no ejecuta correo_smtp_lee (sqlstate %s) → %s', c.rol, st, case when st = '42501' then 'ok' else 'FALLA' end);
    end;
    execute 'reset role';
  end loop;

  -- ── B. Quién: solo un super admin ACTIVO (la función lo vuelve a comprobar aunque la edge ya lo hizo) ──────────
  execute 'set local role service_role';
  for c in select * from (values ('admin', u_ad), ('super de baja', u_of), ('uuid desconocido', gen_random_uuid()), ('null', null::uuid)) x(quien, uid) loop
    begin
      perform public.correo_smtp_guarda_candidato(c.uid, 'smtp.proveedor.com', 465, 'buzon@proveedor.com', 'clave-x', null);
      r := r || format(E'\nB %s guarda candidato → FALLA (entró)', c.quien);
    exception when others then
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nB %s no guarda candidato (sqlstate %s) → %s', c.quien, st, case when st = '42501' then 'ok' else 'FALLA' end);
    end;
    begin
      perform public.correo_smtp_promueve(c.uid, 'x', decode(repeat('cd', 32), 'hex'), decode(repeat('ab', 32), 'hex'));
      r := r || format(E'\nB %s promueve → FALLA (entró)', c.quien);
    exception when others then
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nB %s no promueve (sqlstate %s) → %s', c.quien, st, case when st = '42501' then 'ok' else 'FALLA' end);
    end;
  end loop;
  execute 'reset role';
  select count(*) into n from public.correo_smtp_intentos;
  r := r || format(E'\nB0 los rechazos por «quién» no dejaron intentos anotados: %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);

  -- ── C. Validación del servidor, el puerto, el usuario, la clave y el nombre (22023, sin tocar Vault ni contar intentos) ──
  execute 'set local role service_role';
  for c in select e->>'h' as host, (e->>'p')::int as puerto, e->>'u' as usuario, e->>'k' as clave, e->>'n' as nombre, e->>'hint' as hint
             from jsonb_array_elements($j$[
      {"h":"127.0.0.1","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"}, {"h":"10.0.0.5","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"},
      {"h":"localhost","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"}, {"h":"smtp.internal","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"},
      {"h":"mail.local","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"}, {"h":"smtp","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"},
      {"h":"2130706433","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"}, {"h":"[::1]","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"},
      {"h":"smtp.example","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"}, {"h":"smtp.proveedor.com:25","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"},
      {"h":"smtp..proveedor.com","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"}, {"h":"-a.proveedor.com","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"},
      {"h":"a_b.proveedor.com","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"}, {"h":"smtp.proveedor.com/x","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"},
      {"h":"1.2.3.4","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"}, {"h":"","p":465,"u":"b@x.com","k":"k","hint":"host_no_valido"},
      {"h":"smtp.proveedor.com","p":25,"u":"b@x.com","k":"k","hint":"puerto_no_valido"}, {"h":"smtp.proveedor.com","p":587,"u":"b@x.com","k":"k","hint":"puerto_no_valido"},
      {"h":"smtp.proveedor.com","p":null,"u":"b@x.com","k":"k","hint":"puerto_no_valido"},
      {"h":"smtp.proveedor.com","p":465,"u":"","k":"k","hint":"usuario_no_valido"}, {"h":"smtp.proveedor.com","p":465,"u":"b@x.com\nBcc: y@z.com","k":"k","hint":"usuario_no_valido"},
      {"h":"smtp.proveedor.com","p":465,"u":"b@x.com","k":"","hint":"clave_no_valida"}, {"h":"smtp.proveedor.com","p":465,"u":"b@x.com","k":"a\nb","hint":"clave_no_valida"},
      {"h":"smtp.proveedor.com","p":465,"u":"b@x.com","k":null,"hint":"clave_no_valida"},
      {"h":"smtp.proveedor.com","p":465,"u":"b@x.com","k":"k","n":"Acme <b>","hint":"nombre_no_valido"},
      {"h":"smtp.proveedor.com","p":465,"u":"b@x.com","k":"k","n":"Acme\nBcc: x","hint":"nombre_no_valido"}]$j$::jsonb) e loop
    begin
      perform public.correo_smtp_guarda_candidato(u_sa, c.host, c.puerto, c.usuario, c.clave, c.nombre);
      r := r || format(E'\nC host=%s puerto=%s usuario=%s clave=%s → FALLA (entró)', left(coalesce(c.host, '∅'), 30), c.puerto, translate(left(coalesce(c.usuario, '∅'), 20), chr(10), '~'), translate(left(coalesce(c.clave, '∅'), 10), chr(10), '~'));
    exception when others then
      get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint;
      r := r || format(E'\nC «%s»/%s/«%s»/«%s» se rechaza (%s, %s) → %s', left(coalesce(c.host, '∅'), 30), c.puerto, translate(left(coalesce(c.usuario, '∅'), 20), chr(10), '~'), translate(left(coalesce(c.clave, '∅'), 10), chr(10), '~'), st, coalesce(h, '-'),
            case when st = '22023' and h = c.hint then 'ok' else 'FALLA' end);
    end;
  end loop;
  execute 'reset role';
  select count(*) into n from public.correo_smtp_intentos;
  r := r || format(E'\nC0 ninguna validación fallida dejó un intento anotado: %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);

  delete from public.correo_smtp_intentos;

  -- ── D. Flujo: candidato → (no se usa) → promover → activo; el previo se guarda; el rastro no lleva la contraseña ──
  -- estado conocido: si no había activo, lee() devuelve null (Vault intacto); si lo había, se anota que NO se pudo probar «sin fila»
  execute 'set local role service_role';
  v := public.correo_smtp_lee();
  r := r || format(E'\nD0 lee() sin cambios hasta ahora = el activo de antes: %s → %s', case when v is null then 'sin fila (null)' else 'con fila' end,
        case when v is not distinct from activo_antes then 'ok' else 'FALLA' end);
  if not sin_activo then r := r || E'\nD0b la instancia YA tenía un servidor activo: el caso «sin fila → null» NO SE PROBÓ aquí (se deshace igualmente)'; end if;

  v := public.correo_smtp_guarda_candidato(u_sa, '  SMTP.Proveedor.com ', 465, ' buzon@proveedor.com ', 'secreto-uno', 'Acme');
  tok := v ->> 'token';
  r := r || format(E'\nD1 guarda candidato: token=%s hay_activo=%s cambia_servidor=%s → %s', tok is not null, v ->> 'hay_activo', v ->> 'cambia_servidor',
        case when tok is not null and (v ->> 'hay_activo')::boolean = tenia_activo then 'ok' else 'FALLA' end);
  v2 := public.correo_smtp_lee();
  r := r || format(E'\nD2 el candidato NO se usa: lee() sigue igual → %s', case when v2 is not distinct from activo_antes then 'ok' else 'FALLA' end);
  execute 'reset role';  -- service_role no lee la tabla de intentos (A9): el contador se lee como dueño
  select count(*) into n from public.correo_smtp_intentos;
  execute 'set local role service_role';
  r := r || format(E'\nD3 el intento quedó anotado: %s → %s', n, case when n = 1 then 'ok' else 'FALLA' end);

  -- el token tiene que ser el del candidato, y el actor el mismo
  begin
    perform public.correo_smtp_promueve(u_sa, 'otro-token', decode(repeat('cd', 32), 'hex'), decode(repeat('ab', 32), 'hex'));
    r := r || E'\nD4 promover con otro token → FALLA (entró)';
  exception when others then
    get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint;
    r := r || format(E'\nD4 promover con otro token (sqlstate %s, %s) → %s', st, coalesce(h, '-'), case when st = '22023' and h = 'candidato_no_vigente' then 'ok' else 'FALLA' end);
  end;
  begin
    perform public.correo_smtp_promueve(u_s2, tok, decode(repeat('cd', 32), 'hex'), decode(repeat('ab', 32), 'hex'));
    r := r || E'\nD5 promover el candidato de OTRO super admin → FALLA (entró)';
  exception when others then
    get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint;
    r := r || format(E'\nD5 promover el candidato de otro (sqlstate %s, %s) → %s', st, coalesce(h, '-'), case when st = '42501' and h = 'candidato_de_otro' then 'ok' else 'FALLA' end);
  end;

  execute 'reset role'; delete from public.correo_codigos where actor = u_sa; insert into public.correo_codigos (actor, alcance, huella, hash) values (u_sa, 'servidor', decode(repeat('cd', 32), 'hex'), decode(repeat('ab', 32), 'hex')); execute 'set local role service_role';
  v := public.correo_smtp_promueve(u_sa, tok, decode(repeat('cd', 32), 'hex'), decode(repeat('ab', 32), 'hex'));
  r := r || format(E'\nD6 promueve: host=%s usuario=%s hay_previo=%s → %s', v ->> 'host', v ->> 'usuario', v ->> 'hay_previo',
        case when v ->> 'host' = 'smtp.proveedor.com' and v ->> 'usuario' = 'buzon@proveedor.com' and (v ->> 'hay_previo')::boolean = tenia_activo then 'ok' else 'FALLA' end);
  v2 := public.correo_smtp_lee();
  r := r || format(E'\nD7 lee() devuelve el nuevo activo (host, puerto 465, usuario, clave, nombre) → %s',
        case when v2 ->> 'host' = 'smtp.proveedor.com' and (v2 ->> 'port')::int = 465 and v2 ->> 'user' = 'buzon@proveedor.com'
                  and v2 ->> 'pass' = 'secreto-uno' and v2 ->> 'nombre' = 'Acme' then 'ok' else 'FALLA' end);
  begin
    perform public.correo_smtp_promueve(u_sa, tok, decode(repeat('cd', 32), 'hex'), decode(repeat('ab', 32), 'hex'));
    r := r || E'\nD8 promover dos veces el mismo token → FALLA (entró)';
  exception when others then
    get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint;
    r := r || format(E'\nD8 el token ya gastado no vale (sqlstate %s, %s) → %s', st, coalesce(h, '-'), case when st = '22023' and h = 'candidato_no_vigente' then 'ok' else 'FALLA' end);
  end;
  execute 'reset role';
  select count(*) into n from (select public._correo_smtp_secreto('smtp_candidato') as sec) s where s.sec ? 'pass' or s.sec ? 'host';
  r := r || format(E'\nD9 tras promover, el candidato no conserva la contraseña: %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);

  -- estado: sin contraseña, con quién y cuándo
  execute 'set local role service_role';
  v := public.correo_smtp_estado();
  r := r || format(E'\nE1 estado: configurado=%s host=%s usuario=%s puesto_por=%s, sin contraseña=%s, intentos=%s → %s', v ->> 'configurado', v ->> 'host', v ->> 'usuario', v ->> 'puesto_por',
        v::text not like '%secreto-uno%', v ->> 'intentos_recientes',
        case when (v ->> 'configurado')::boolean and v ->> 'host' = 'smtp.proveedor.com' and v ->> 'usuario' = 'buzon@proveedor.com' and v ->> 'puesto_por' = m_sa
                  and v::text not like '%secreto-uno%' and (v ->> 'puesto_en') ~ '^\d{4}-\d\d-\d\dT' and (v ->> 'intentos_recientes')::int = 1 and (v ->> 'intentos_max')::int = 5 then 'ok' else 'FALLA' end);
  execute 'reset role';

  -- el registro de cambios: host y usuario legibles (la clave NO casa con /smtp|pass|…/), la contraseña, en ninguna parte
  select count(*) into n from public.ajustes_log where clave = 'correo_salida' and despues ->> 'host' = 'smtp.proveedor.com' and despues ->> 'usuario' = 'buzon@proveedor.com' and despues ->> 'puesto_por' = m_sa;
  r := r || format(E'\nE2 ajustes_log dice host, usuario y quién: %s fila(s) → %s', n, case when n = 1 then 'ok' else 'FALLA' end);
  select count(*) into n from public.ajustes_log where antes::text like '%secreto%' or despues::text like '%secreto%' or motivo like '%secreto%';
  r := r || format(E'\nE3 la contraseña no está en ajustes_log: %s filas con ella → %s', n, case when n = 0 then 'ok' else 'FALLA' end);
  r := r || format(E'\nE4 la clave de estado no se redacta: _ajustes_es_sensible(correo_salida)=%s → %s', public._ajustes_es_sensible('correo_salida'),
        case when not public._ajustes_es_sensible('correo_salida') then 'ok' else 'FALLA' end);

  -- ── F. Rotación: el activo pasa a previo; cambiar solo la clave no cuenta como «cambiar de servidor» ──────────
  execute 'set local role service_role';
  v := public.correo_smtp_guarda_candidato(u_sa, 'smtp.proveedor.com', 465, 'buzon@proveedor.com', 'secreto-dos', 'Acme');
  r := r || format(E'\nF1 misma máquina y mismo usuario, otra clave: cambia_servidor=%s → %s', v ->> 'cambia_servidor', case when (v ->> 'cambia_servidor')::boolean is false then 'ok' else 'FALLA' end);
  execute 'reset role'; delete from public.correo_codigos where actor = u_sa; insert into public.correo_codigos (actor, alcance, huella, hash) values (u_sa, 'servidor', decode(repeat('cd', 32), 'hex'), decode(repeat('ab', 32), 'hex')); execute 'set local role service_role';
  perform public.correo_smtp_promueve(u_sa, v ->> 'token', decode(repeat('cd', 32), 'hex'), decode(repeat('ab', 32), 'hex'));
  v := public.correo_smtp_guarda_candidato(u_sa, 'otro.proveedor.net', 465, 'buzon@proveedor.com', 'secreto-tres', null);
  r := r || format(E'\nF2 otro host: cambia_servidor=%s → %s', v ->> 'cambia_servidor', case when (v ->> 'cambia_servidor')::boolean then 'ok' else 'FALLA' end);
  v := public.correo_smtp_guarda_candidato(u_sa, 'otro.proveedor.net', 465, 'otro.buzon@proveedor.net', 'secreto-tres', null);
  r := r || format(E'\nF3 otro usuario: cambia_servidor=%s → %s', v ->> 'cambia_servidor', case when (v ->> 'cambia_servidor')::boolean then 'ok' else 'FALLA' end);
  execute 'reset role'; delete from public.correo_codigos where actor = u_sa; insert into public.correo_codigos (actor, alcance, huella, hash) values (u_sa, 'servidor', decode(repeat('cd', 32), 'hex'), decode(repeat('ab', 32), 'hex')); execute 'set local role service_role';
  perform public.correo_smtp_promueve(u_sa, v ->> 'token', decode(repeat('cd', 32), 'hex'), decode(repeat('ab', 32), 'hex'));
  v2 := public.correo_smtp_lee();
  r := r || format(E'\nF4 el activo es el último (host=%s, clave=%s, nombre null=%s) → %s', v2 ->> 'host', v2 ->> 'pass' = 'secreto-tres', v2 ->> 'nombre' is null,
        case when v2 ->> 'host' = 'otro.proveedor.net' and v2 ->> 'pass' = 'secreto-tres' and v2 ->> 'nombre' is null then 'ok' else 'FALLA' end);
  execute 'reset role';
  r := r || format(E'\nF5 el previo es el activo anterior (smtp.proveedor.com / secreto-dos) → %s',
        case when public._correo_smtp_secreto('smtp_previo') ->> 'pass' = 'secreto-dos' and public._correo_smtp_secreto('smtp_previo') ->> 'host' = 'smtp.proveedor.com' then 'ok' else 'FALLA' end);
  select count(*) into n from public.ajustes_log where clave = 'correo_salida' and antes ->> 'host' = 'smtp.proveedor.com' and despues ->> 'host' = 'otro.proveedor.net';
  r := r || format(E'\nF6 el registro guarda host viejo y nuevo: %s → %s', n, case when n = 1 then 'ok' else 'FALLA' end);

  -- una prueba caducada (15 min) no se promueve
  execute 'set local role service_role';
  v := public.correo_smtp_guarda_candidato(u_sa, 'caduca.proveedor.net', 465, 'c@proveedor.net', 'secreto-caduco', null);
  execute 'reset role';
  perform public._correo_smtp_pon('smtp_candidato', jsonb_set(public._correo_smtp_secreto('smtp_candidato'), '{creado}', to_jsonb(now() - interval '20 minutes')), 'prueba: caducada');
  execute 'set local role service_role';
  begin
    perform public.correo_smtp_promueve(u_sa, v ->> 'token', decode(repeat('cd', 32), 'hex'), decode(repeat('ab', 32), 'hex'));
    r := r || E'\nF7 promover una prueba de hace 20 minutos → FALLA (entró)';
  exception when others then
    get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint;
    r := r || format(E'\nF7 la prueba caducada no se promueve (sqlstate %s, %s) → %s', st, coalesce(h, '-'), case when st = '22023' and h = 'candidato_no_vigente' then 'ok' else 'FALLA' end);
  end;
  execute 'reset role';

  -- ── G. Límite de intentos persistido: 5 cada 10 minutos por instancia, cuente quien cuente ────────────────────
  delete from public.correo_smtp_intentos;
  execute 'set local role service_role';
  for c in select g from generate_series(1, 5) g loop
    perform public.correo_smtp_guarda_candidato(case when c.g % 2 = 0 then u_s2 else u_sa end, 'limite.proveedor.net', 465, 'l@proveedor.net', 'k' || c.g, null);
  end loop;
  begin
    perform public.correo_smtp_guarda_candidato(u_sa, 'limite.proveedor.net', 465, 'l@proveedor.net', 'k6', null);
    r := r || E'\nG1 el sexto intento en 10 minutos → FALLA (entró)';
  exception when others then
    get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint;
    r := r || format(E'\nG1 el sexto intento se frena (sqlstate %s, %s) → %s', st, coalesce(h, '-'), case when h = 'demasiados_intentos' then 'ok' else 'FALLA' end);
  end;
  v := public.correo_smtp_estado();
  r := r || format(E'\nG2 estado cuenta %s intentos recientes de %s → %s', v ->> 'intentos_recientes', v ->> 'intentos_max', case when (v ->> 'intentos_recientes')::int = 5 then 'ok' else 'FALLA' end);
  execute 'reset role';
  update public.correo_smtp_intentos set cuando = now() - interval '11 minutes';
  execute 'set local role service_role';
  begin
    perform public.correo_smtp_guarda_candidato(u_sa, 'limite.proveedor.net', 465, 'l@proveedor.net', 'k7', null);
    r := r || E'\nG3 pasados 10 minutos el límite se libera → ok';
  exception when others then
    r := r || E'\nG3 pasados 10 minutos el límite sigue → FALLA';
  end;
  execute 'reset role';

  -- G4. La reautenticación con contraseña cuenta en el MISMO límite: se reserva ANTES de preguntar a Auth, acertar libera la reserva
  delete from public.correo_smtp_intentos;
  execute 'set local role service_role';
  declare ids bigint[] := '{}';
  begin
    for c in select g from generate_series(1, 5) g loop
      ids := ids || public.correo_smtp_reauth_intento(u_sa);
    end loop;
    execute 'reset role';
    select count(*) into n from public.correo_smtp_intentos;
    r := r || format(E'\nG4a cinco reservas de reautenticación quedan contadas: %s → %s', n, case when n = 5 then 'ok' else 'FALLA' end);
    execute 'set local role service_role';
    begin
      perform public.correo_smtp_reauth_intento(u_sa);
      r := r || E'\nG4b la sexta reautenticación en 10 minutos → FALLA (entró)';
    exception when others then
      get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint;
      r := r || format(E'\nG4b la sexta reautenticación se frena (sqlstate %s, %s) → %s', st, coalesce(h, '-'), case when h = 'demasiados_intentos' then 'ok' else 'FALLA' end);
    end;
    begin
      perform public.correo_smtp_guarda_candidato(u_sa, 'limite.proveedor.net', 465, 'l@proveedor.net', 'k8', null);
      r := r || E'\nG4c las reautenticaciones agotan también la prueba del servidor → FALLA (entró)';
    exception when others then
      get stacked diagnostics h = pg_exception_hint;
      r := r || format(E'\nG4c las reautenticaciones agotan también la prueba del servidor (%s) → %s', coalesce(h, '-'), case when h = 'demasiados_intentos' then 'ok' else 'FALLA' end);
    end;
    perform public.correo_smtp_reauth_intento(u_sa, ids[1]);
    execute 'reset role';
    select count(*) into n from public.correo_smtp_intentos;
    r := r || format(E'\nG4d acertar la contraseña libera su reserva: quedan %s → %s', n, case when n = 4 then 'ok' else 'FALLA' end);
    execute 'set local role service_role';
    perform public.correo_smtp_reauth_intento(u_sa, ids[2] + 100000);   -- un id que no existe no borra nada
    execute 'reset role';
    select count(*) into n from public.correo_smtp_intentos;
    r := r || format(E'\nG4e liberar un id que no existe no borra nada: quedan %s → %s', n, case when n = 4 then 'ok' else 'FALLA' end);
    execute 'set local role service_role';
    begin
      perform public.correo_smtp_reauth_intento(gen_random_uuid());
      r := r || E'\nG4f un uuid que no es super admin → FALLA (entró)';
    exception when others then
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nG4f un uuid que no es super admin se rechaza (sqlstate %s) → %s', st, case when st = '42501' then 'ok' else 'FALLA' end);
    end;
    execute 'reset role';
  end;

  -- ── H. Ajustes: asunto_por_defecto se valida EN SERVIDOR; las 4 claves de correo ya no se escriben por ajustes_config_guardar ─────
  -- F3.1b (8-oct-2026, 20261008135000): email_from, email_reply_to, email_avisos_sistema y email_avisos_soporte salieron de la lista blanca de authenticated y solo
  -- se cambian con código de confirmación por correo_ajuste_guarda (service_role). Sus reglas de dominio (antes aquí, H/H3) se prueban en correo_codigos.sql.
  perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  for c in select e->>'c' as clave, e->'v' as valor, e->>'hint' as hint from jsonb_array_elements(jsonb_build_array(
      jsonb_build_object('c', 'asunto_por_defecto', 'v', 'null'::jsonb, 'hint', null),
      jsonb_build_object('c', 'asunto_por_defecto', 'v', E'Hola\nBcc: x@y.com', 'hint', null),
      jsonb_build_object('c', 'asunto_por_defecto', 'v', repeat('a', 201), 'hint', null),
      jsonb_build_object('c', 'asunto_por_defecto', 'v', 123, 'hint', null),
      jsonb_build_object('c', 'email_from', 'v', 'ventas@' || dom, 'hint', 'clave_no_editable'),
      jsonb_build_object('c', 'email_reply_to', 'v', 'r@' || dom, 'hint', 'clave_no_editable'),
      jsonb_build_object('c', 'email_avisos_soporte', 'v', 'soporte@' || dom, 'hint', 'clave_no_editable'),
      jsonb_build_object('c', 'email_avisos_sistema', 'v', 'sistema@' || dom, 'hint', 'clave_no_editable'))) e loop
    begin
      perform public.ajustes_config_guardar(c.clave, c.valor);
      r := r || format(E'\nH «%s» = %s → FALLA (entró)', c.clave, left(c.valor::text, 40));
    exception when others then
      get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint;
      r := r || format(E'\nH «%s» = %s se rechaza (%s, %s) → %s', c.clave, left(c.valor::text, 40), st, coalesce(h, '-'),
            case when st = '22023' and (c.hint is null or h = c.hint) then 'ok' else 'FALLA' end);
    end;
  end loop;
  for c in select e->>'c' as clave, e->'v' as valor, e->'esperado' as esperado from jsonb_array_elements(jsonb_build_array(
      jsonb_build_object('c', 'asunto_por_defecto', 'v', 'Documento de la empresa', 'esperado', 'Documento de la empresa'),
      jsonb_build_object('c', 'asunto_por_defecto', 'v', '', 'esperado', ''),
      jsonb_build_object('c', 'asunto_por_defecto', 'v', repeat('é', 200), 'esperado', repeat('é', 200)))) e loop
    begin
      v := public.ajustes_config_guardar(c.clave, c.valor);
      r := r || format(E'\nH+ «%s» = %s entra como %s → %s', c.clave, left(c.valor::text, 30), left(v ->> 'valor', 30), case when v -> 'valor' = c.esperado then 'ok' else 'FALLA' end);
    exception when others then
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nH+ «%s» = %s se rechaza (%s) → FALLA', c.clave, left(c.valor::text, 30), st);
    end;
  end loop;
  v := public.ajustes_config_datos();
  r := r || format(E'\nH1 la lectura ofrece 6 claves editables, con asunto_por_defecto y SIN las 4 de correo → %s',
        case when jsonb_array_length(v -> 'editables') = 6 and v -> 'editables' ? 'asunto_por_defecto' and not (v -> 'editables' ? 'email_from') and not (v -> 'editables' ? 'email_reply_to')
                  and not (v -> 'editables' ? 'email_avisos_soporte') and not (v -> 'editables' ? 'email_avisos_sistema') then 'ok' else 'FALLA' end);
  -- un admin (no super) sigue sin escribir
  perform set_config('request.jwt.claims', json_build_object('sub', u_ad, 'email', m_ad, 'role', 'authenticated')::text, true);
  begin
    perform public.ajustes_config_guardar('asunto_por_defecto', to_jsonb('x'::text));
    r := r || E'\nH2 un admin escribe asunto_por_defecto → FALLA (entró)';
  exception when others then
    get stacked diagnostics st = returned_sqlstate;
    r := r || format(E'\nH2 un admin no escribe asunto_por_defecto (sqlstate %s) → %s', st, case when st = '42501' then 'ok' else 'FALLA' end);
  end;
  execute 'reset role';

  perform set_config('request.jwt.claims', '', true);
  raise exception 'FIN DE PRUEBAS F3.1 CORREO (se deshace):%', r;
end $$;
