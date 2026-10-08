-- destructivo-ok: prueba que se deshace sola (raise exception final); los delete solo vacían correo_codigos / correo_smtp_intentos / una clave de prueba dentro de la transacción y todo se revierte.
-- PRUEBA — Correo desde Ajustes en LAWANG, parte 2: código de confirmación (F3.1b; migración 20261010060000_correo_ajustes_servidor_y_codigo). Portada el 8-oct-2026
-- de erp/pruebas/f31b_correo_codigos.sql del maestro SIN el caso G7 (el instalador no existe en Lawang). Criterio: el servidor de correo y las cuatro claves de correo
-- (email_from, email_reply_to, email_avisos_sistema, email_avisos_soporte) solo se cambian con un código de un solo uso, atado al cambio exacto, que se consume en la misma
-- transacción que el cambio; 5 fallos lo anulan; emisión limitada; nada de esto lo ejecuta nadie salvo service_role (y la vuelta atrás, nadie salvo el dueño de la base);
-- `quien` del registro = el actor; la vuelta atrás deja a `correo_smtp_lee()` en NULL con rastro.
-- ESTADO (8-oct-2026): ESCRITA, NO EJECUTADA EN LAWANG. La del maestro dio 131/131 en una rama efímera de bbm. Va DESPUÉS de correo_smtp_servidor.sql.
--
-- Se ejecuta ENTERA como postgres y CAMBIA de rol dentro (`set local role service_role|authenticated|anon`) para probar los GRANT de verdad. Los grants se miden por
-- pg_proc.proacl (aclexplode), NO por has_function_privilege. NO ESCRIBE NADA: termina en `raise exception 'FIN DE PRUEBAS…'`, que deshace la transacción entera
-- (incluidos los secretos de Vault y todo lo que escribe la prueba en config_instancia / ajustes_log).
--   Lawang: se pega entera en execute_sql sobre una RAMA EFÍMERA o sobre la base ya migrada. NUNCA antes de aplicar la migración.
do $$
declare
  r text := '';
  u_sa uuid := gen_random_uuid();  m_sa  text := 'super.codigo@pruebas.test';
  u_s2 uuid := gen_random_uuid();  m_s2  text := 'super2.codigo@pruebas.test';
  u_ad uuid := gen_random_uuid();  m_ad  text := 'admin.codigo@pruebas.test';
  u_of uuid := gen_random_uuid();  m_of  text := 'super.baja.codigo@pruebas.test';
  hu  bytea := decode(repeat('11', 32), 'hex');   -- huella buena
  hu2 bytea := decode(repeat('12', 32), 'hex');   -- huella de otro cambio
  ha  bytea := decode(repeat('22', 32), 'hex');   -- hash bueno
  ha2 bytea := decode(repeat('23', 32), 'hex');   -- hash malo
  st text; h text; v jsonb; v2 jsonb; n int; c record; tok text; e text; f int; dom text; ok boolean;
  claims_antes text; id1 bigint; id2 bigint; id3 bigint; activo_antes jsonb; sin_activo boolean; usr_dom text; dom_from text := 'desde-from.test';
begin
  -- ── Preparación (como postgres) ───────────────────────────────────────────────────────────────────────────
  execute 'set local session_replication_role = replica';
  insert into auth.users (id, email, aud, role) values
    (u_sa, m_sa, 'authenticated', 'authenticated'), (u_s2, m_s2, 'authenticated', 'authenticated'),
    (u_ad, m_ad, 'authenticated', 'authenticated'), (u_of, m_of, 'authenticated', 'authenticated');
  insert into public.usuarios (user_id, email, nombre, rol, herramientas, activo, numero_usuario) values
    (u_sa, m_sa, 'Super Codigo', 'super_admin', '{}', true, 'USR-PRBCD-1'),
    (u_s2, m_s2, 'Super Dos', 'super_admin', '{}', true, 'USR-PRBCD-2'),
    (u_ad, m_ad, 'Admin Codigo', 'admin', array['ajustes'], true, 'USR-PRBCD-3'),
    (u_of, m_of, 'Super de baja', 'super_admin', '{}', false, 'USR-PRBCD-4');
  execute 'set local session_replication_role = origin';
  delete from public.correo_codigos;
  delete from public.correo_smtp_intentos;
  activo_antes := public.correo_smtp_lee();   -- como lo ve envia-correo (NULL si no hay servidor o está vacío)
  sin_activo := not public._correo_smtp_existe('smtp_activo');
  select valor #>> '{}' into dom from public.config_instancia where clave = 'dominio_web' and jsonb_typeof(valor) = 'string';
  if dom is null or dom = '' then
    insert into public.config_instancia (clave, valor) values ('dominio_web', '"pruebas.test"'::jsonb) on conflict (clave) do update set valor = excluded.valor;
    dom := 'pruebas.test';
  end if;

  -- ── A. Nace cerrado: solo service_role ejecuta las públicas; las internas y la vuelta atrás, nadie ──────────
  for c in select p.proname, p.oid, p.prosecdef, p.proconfig, p.proowner from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('correo_codigo_emite', 'correo_codigo_verifica', 'correo_codigo_retira', 'correo_smtp_promueve', 'correo_smtp_descarta', 'correo_ajuste_guarda',
                                'correo_smtp_revierte', '_correo_codigo_comprueba', '_correo_ct_igual', '_correo_smtp_como', '_correo_smtp_vuelve', '_correo_smtp_activa', '_correo_smtp_existe',
                                '_correo_mail_valido', '_correo_dominio_usuario_smtp', '_correo_buzon_propio') loop
    select count(*) filter (where a.grantee <> c.proowner and a.grantee <> 'service_role'::regrole),
           count(*) filter (where a.grantee = 'service_role'::regrole)
      into n, f
      from aclexplode(coalesce((select proacl from pg_proc where oid = c.oid), acldefault('f', c.proowner))) a where a.privilege_type = 'EXECUTE';
    r := r || format(E'\nA %s: ejecutan de más=%s (anon/authenticated/PUBLIC/otros), service_role=%s, DEFINER=%s → %s', c.proname, n, f, c.prosecdef,
          case when n = 0
                    and ((c.proname in ('correo_codigo_emite', 'correo_codigo_verifica', 'correo_codigo_retira', 'correo_smtp_promueve', 'correo_smtp_descarta', 'correo_ajuste_guarda') and f = 1 and c.prosecdef and c.proconfig = array['search_path=""'])
                         or (c.proname not in ('correo_codigo_emite', 'correo_codigo_verifica', 'correo_codigo_retira', 'correo_smtp_promueve', 'correo_smtp_descarta', 'correo_ajuste_guarda') and f = 0)) then 'ok' else 'FALLA' end);
  end loop;
  select count(*) into n from pg_class k where k.oid = 'public.correo_codigos'::regclass and k.relrowsecurity
     and not exists (select 1 from aclexplode(coalesce(k.relacl, acldefault('r', k.relowner))) a where a.grantee <> k.relowner);
  r := r || format(E'\nA9 correo_codigos: RLS puesta y NINGÚN permiso para nadie más que el dueño (ni service_role) → %s', case when n = 1 then 'ok' else 'FALLA' end);
  r := r || format(E'\nA10 las firmas viejas ya no existen (promueve de 2 argumentos y _correo_smtp_activa de 2) → %s',
        case when to_regprocedure('public.correo_smtp_promueve(uuid,text)') is null and to_regprocedure('public._correo_smtp_activa(jsonb,text)') is null then 'ok' else 'FALLA' end);
  r := r || format(E'\nA11 la lista blanca de authenticated son 6 claves SIN las 4 de correo → %s',
        case when public._ajustes_claves_editables() = array['marca', 'logo_correo_url', 'email_avisos_reservas', 'email_avisos_crm', 'zona_horaria', 'asunto_por_defecto'] then 'ok' else 'FALLA' end);
  for c in select * from (values ('authenticated'), ('anon')) x(rol) loop
    execute format('set local role %I', c.rol);
    begin
      perform public.correo_codigo_emite(u_sa, 'servidor', hu, ha);
      r := r || format(E'\nA12 %s ejecuta correo_codigo_emite → FALLA (entró)', c.rol);
    exception when others then
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nA12 %s no ejecuta correo_codigo_emite (sqlstate %s) → %s', c.rol, st, case when st = '42501' then 'ok' else 'FALLA' end);
    end;
    begin
      perform public.correo_ajuste_guarda(u_sa, 'email_from', to_jsonb('a@' || dom), hu, ha);
      r := r || format(E'\nA13 %s ejecuta correo_ajuste_guarda → FALLA (entró)', c.rol);
    exception when others then
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nA13 %s no ejecuta correo_ajuste_guarda (sqlstate %s) → %s', c.rol, st, case when st = '42501' then 'ok' else 'FALLA' end);
    end;
    begin
      perform public.correo_smtp_revierte('x');
      r := r || format(E'\nA14 %s ejecuta correo_smtp_revierte → FALLA (entró)', c.rol);
    exception when others then
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nA14 %s no ejecuta correo_smtp_revierte (sqlstate %s) → %s', c.rol, st, case when st = '42501' then 'ok' else 'FALLA' end);
    end;
    execute 'reset role';
  end loop;
  execute 'set local role service_role';
  begin
    perform public.correo_smtp_revierte('x');
    r := r || E'\nA15 service_role ejecuta correo_smtp_revierte → FALLA (entró)';
  exception when others then
    get stacked diagnostics st = returned_sqlstate;
    r := r || format(E'\nA15 ni service_role ejecuta correo_smtp_revierte (sqlstate %s) → %s', st, case when st = '42501' then 'ok' else 'FALLA' end);
  end;
  execute 'reset role';

  -- ── B. Quién: solo un super admin ACTIVO, en TODAS las funciones nuevas ──────────────────────────────────────────
  execute 'set local role service_role';
  for c in select * from (values ('admin', u_ad), ('super de baja', u_of), ('uuid desconocido', gen_random_uuid()), ('null', null::uuid)) x(quien, uid) loop
    for e in select * from unnest(array['emite', 'verifica', 'retira', 'descarta', 'ajuste', 'promueve']) loop
      begin
        if e = 'emite' then perform public.correo_codigo_emite(c.uid, 'servidor', hu, ha);
        elsif e = 'verifica' then perform public.correo_codigo_verifica(c.uid, 'servidor', hu, ha);
        elsif e = 'retira' then perform public.correo_codigo_retira(c.uid, 1);
        elsif e = 'descarta' then perform public.correo_smtp_descarta(c.uid, 'x');
        elsif e = 'ajuste' then perform public.correo_ajuste_guarda(c.uid, 'email_reply_to', to_jsonb(''::text), hu, ha);
        else perform public.correo_smtp_promueve(c.uid, 'x', hu, ha); end if;
        r := r || format(E'\nB %s %s → FALLA (entró)', c.quien, e);
      exception when others then
        get stacked diagnostics st = returned_sqlstate;
        r := r || format(E'\nB %s no hace «%s» (sqlstate %s) → %s', c.quien, e, st, case when st = '42501' then 'ok' else 'FALLA' end);
      end;
    end loop;
  end loop;
  execute 'reset role';
  select count(*) into n from public.correo_codigos;
  r := r || format(E'\nB0 los rechazos por «quién» no dejaron códigos: %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);

  -- ── C. Comparación en tiempo constante (tabla de verdad) ──────────────────────────────────────────────────────────
  r := r || format(E'\nC1 _correo_ct_igual: iguales=%s, difiere el primer byte=%s, difiere el último=%s, longitud distinta=%s, null=%s → %s',
        public._correo_ct_igual(ha, ha), public._correo_ct_igual(ha, decode('23' || repeat('22', 31), 'hex')), public._correo_ct_igual(ha, decode(repeat('22', 31) || '23', 'hex')),
        public._correo_ct_igual(ha, decode(repeat('22', 31), 'hex')), public._correo_ct_igual(ha, null),
        case when public._correo_ct_igual(ha, ha) and not public._correo_ct_igual(ha, decode('23' || repeat('22', 31), 'hex')) and not public._correo_ct_igual(ha, decode(repeat('22', 31) || '23', 'hex'))
                  and not public._correo_ct_igual(ha, decode(repeat('22', 31), 'hex')) and not public._correo_ct_igual(ha, null) then 'ok' else 'FALLA' end);

  -- ── D. Emitir, verificar sin consumir, fallos que NO se deshacen, anular a los 5 ────────────────────────────────────
  execute 'set local role service_role';
  v := public.correo_codigo_emite(u_sa, 'servidor', hu, ha);
  id1 := (v ->> 'id')::bigint;
  r := r || format(E'\nD1 emite devuelve id y caducidad (10 min): %s → %s', v::text, case when id1 is not null and (v ->> 'caduca')::timestamptz between now() + interval '9 minutes' and now() + interval '11 minutes' then 'ok' else 'FALLA' end);
  begin
    perform public.correo_codigo_emite(u_sa, 'otro', hu, ha);
    r := r || E'\nD1b alcance inventado → FALLA (entró)';
  exception when others then
    get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint;
    r := r || format(E'\nD1b alcance inventado se rechaza (%s, %s) → %s', st, coalesce(h, '-'), case when st = '22023' and h = 'codigo_mal_formado' then 'ok' else 'FALLA' end);
  end;
  begin
    perform public.correo_codigo_emite(u_sa, 'servidor', decode('11', 'hex'), ha);
    r := r || E'\nD1c huella de 1 byte → FALLA (entró)';
  exception when others then
    get stacked diagnostics st = returned_sqlstate;
    r := r || format(E'\nD1c huella que no mide 32 bytes se rechaza (%s) → %s', st, case when st = '22023' then 'ok' else 'FALLA' end);
  end;
  v := public.correo_codigo_verifica(u_sa, 'servidor', hu, ha);
  r := r || format(E'\nD2 verifica el bueno: valido=%s → %s', v ->> 'valido', case when (v ->> 'valido')::boolean then 'ok' else 'FALLA' end);
  v := public.correo_codigo_verifica(u_sa, 'servidor', hu, ha);
  r := r || format(E'\nD3 verificar NO consume: lo repite y sigue valiendo (%s) → %s', v ->> 'valido', case when (v ->> 'valido')::boolean then 'ok' else 'FALLA' end);
  for c in select * from (values ('hash malo', 'servidor', hu, ha2), ('huella de otro cambio', 'servidor', hu2, ha), ('otro alcance', 'ajuste', hu, ha), ('hash nulo', 'servidor', hu, null::bytea)) x(que, alc, hh, aa) loop
    v := public.correo_codigo_verifica(u_sa, c.alc, c.hh, c.aa);
    r := r || format(E'\nD4 %s no vale (valido=%s) → %s', c.que, v ->> 'valido', case when (v ->> 'valido')::boolean is false then 'ok' else 'FALLA' end);
  end loop;
  execute 'reset role';
  select estado, fallos into e, f from public.correo_codigos where id = id1;
  r := r || format(E'\nD5 los 4 fallos QUEDARON contados (no se deshicieron con la respuesta): fallos=%s estado=%s → %s', f, e, case when f = 4 and e = 'pendiente' then 'ok' else 'FALLA' end);
  execute 'set local role service_role';
  v := public.correo_codigo_verifica(u_sa, 'servidor', hu, ha2);
  execute 'reset role';
  select estado, fallos into e, f from public.correo_codigos where id = id1;
  r := r || format(E'\nD6 el 5º fallo anula el código: estado=%s fallos=%s → %s', e, f, case when e = 'anulado' and f = 5 then 'ok' else 'FALLA' end);
  execute 'set local role service_role';
  v := public.correo_codigo_verifica(u_sa, 'servidor', hu, ha);
  r := r || format(E'\nD7 anulado, el código BUENO ya no vale (valido=%s) → %s', v ->> 'valido', case when (v ->> 'valido')::boolean is false then 'ok' else 'FALLA' end);
  begin
    perform public.correo_codigo_emite(u_sa, 'servidor', hu, ha);
    r := r || E'\nD8 emitir justo tras anular → FALLA (entró)';
  exception when others then
    get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint;
    r := r || format(E'\nD8 60 s de enfriamiento tras un código anulado (%s, %s) → %s', st, coalesce(h, '-'), case when h = 'codigo_enfriamiento' then 'ok' else 'FALLA' end);
  end;
  execute 'reset role';
  update public.correo_codigos set cambiado = now() - interval '2 minutes' where id = id1;
  execute 'set local role service_role';
  v := public.correo_codigo_emite(u_sa, 'servidor', hu, ha);
  id2 := (v ->> 'id')::bigint;
  r := r || format(E'\nD9 pasado el minuto se puede emitir otro → %s', case when id2 is not null and id2 <> id1 then 'ok' else 'FALLA' end);
  -- límite: 3 emisiones por hora y actor (cuentan las sustituidas y las anuladas): ya van 2 (id1, id2); la 3ª entra y la 4ª no
  v := public.correo_codigo_emite(u_sa, 'servidor', hu, ha);
  id3 := (v ->> 'id')::bigint;
  begin
    perform public.correo_codigo_emite(u_sa, 'servidor', hu, ha);
    r := r || E'\nD10 la 4ª emisión de la hora → FALLA (entró)';
  exception when others then
    get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint;
    r := r || format(E'\nD10 la 4ª emisión en una hora se frena (%s, %s) → %s', st, coalesce(h, '-'), case when h = 'demasiados_codigos' then 'ok' else 'FALLA' end);
  end;
  -- el límite es por actor: otro super admin puede pedir el suyo
  v := public.correo_codigo_emite(u_s2, 'servidor', hu, ha);
  r := r || format(E'\nD11 el cupo es por actor: el otro super admin emite → %s', case when (v ->> 'id') is not null then 'ok' else 'FALLA' end);
  execute 'reset role';
  select count(*) into n from public.correo_codigos where actor = u_sa and estado = 'pendiente';
  select estado into e from public.correo_codigos where id = id2;
  r := r || format(E'\nD12 un solo pendiente por actor (%s) y el anterior quedó «sustituido» (%s) → %s', n, e, case when n = 1 and e = 'sustituido' then 'ok' else 'FALLA' end);
  -- caducidad
  update public.correo_codigos set caduca = now() - interval '1 second' where id = id3;
  execute 'set local role service_role';
  v := public.correo_codigo_verifica(u_sa, 'servidor', hu, ha);
  execute 'reset role';
  select estado into e from public.correo_codigos where id = id3;
  r := r || format(E'\nD13 un código caducado no vale (valido=%s) y queda «caducado» (%s) → %s', v ->> 'valido', e, case when (v ->> 'valido')::boolean is false and e = 'caducado' then 'ok' else 'FALLA' end);
  -- retirar una emisión que no llegó no gasta cupo; con fallos no se retira
  delete from public.correo_codigos;
  execute 'set local role service_role';
  v := public.correo_codigo_emite(u_sa, 'servidor', hu, ha); id1 := (v ->> 'id')::bigint;
  perform public.correo_codigo_retira(u_sa, id1);
  execute 'reset role';
  select count(*) into n from public.correo_codigos where id = id1;
  r := r || format(E'\nD14 retira borra la emisión que no llegó: quedan %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);
  execute 'set local role service_role';
  v := public.correo_codigo_emite(u_sa, 'servidor', hu, ha); id1 := (v ->> 'id')::bigint;
  perform public.correo_codigo_verifica(u_sa, 'servidor', hu, ha2);   -- un fallo
  perform public.correo_codigo_retira(u_sa, id1);
  perform public.correo_codigo_retira(u_s2, id1);                      -- ni otro actor
  execute 'reset role';
  select count(*) into n from public.correo_codigos where id = id1;
  r := r || format(E'\nD15 con un fallo (o de otro actor) NO se retira: quedan %s → %s', n, case when n = 1 then 'ok' else 'FALLA' end);
  delete from public.correo_codigos;

  -- ── E. Promover el servidor SOLO con el código: se consume aquí, quien = el actor, el activo no cambia si el código falla ──
  claims_antes := coalesce(current_setting('request.jwt.claims', true), '');
  execute 'set local role service_role';
  perform public.correo_codigo_emite(u_sa, 'servidor', hu, ha);
  v := public.correo_smtp_guarda_candidato(u_sa, 'smtp.proveedor.com', 465, 'buzon@proveedor.com', 'secreto-uno', 'Acme');
  tok := v ->> 'token';
  v := public.correo_smtp_promueve(u_sa, tok, hu, ha2);
  r := r || format(E'\nE1 promover con un código MALO: %s → %s', v::text, case when (v ->> 'codigo_no_valido')::boolean then 'ok' else 'FALLA' end);
  v2 := public.correo_smtp_lee();
  execute 'reset role';   -- las auxiliares _correo_smtp_* no las ejecuta service_role: se leen como dueño
  r := r || format(E'\nE2 el activo no cambió (lee() igual que antes) y, sin código válido, el candidato se DESCARTÓ (su contraseña no espera en Vault) → %s',
        case when v2 is not distinct from activo_antes and (public._correo_smtp_secreto('smtp_candidato') ? 'host') is false
                  and public._correo_smtp_secreto('smtp_candidato')::text not like '%secreto-uno%' then 'ok' else 'FALLA' end);
  delete from public.correo_smtp_intentos;   -- el límite de pruebas (5 por 10 min) no es lo que se mide aquí: cada tramo vuelve a probar el servidor
  execute 'set local role service_role';
  v := public.correo_smtp_guarda_candidato(u_sa, 'smtp.proveedor.com', 465, 'buzon@proveedor.com', 'secreto-uno', 'Acme'); tok := v ->> 'token';
  v := public.correo_smtp_promueve(u_sa, tok, hu2, ha);
  r := r || format(E'\nE3 promover con la huella de OTRO cambio: %s → %s', v::text, case when (v ->> 'codigo_no_valido')::boolean then 'ok' else 'FALLA' end);
  execute 'reset role'; delete from public.correo_smtp_intentos; execute 'set local role service_role';
  v := public.correo_smtp_guarda_candidato(u_sa, 'smtp.proveedor.com', 465, 'buzon@proveedor.com', 'secreto-uno', 'Acme'); tok := v ->> 'token';
  v := public.correo_smtp_promueve(u_sa, tok, hu, ha, 'sin otro destinatario de aviso');
  r := r || format(E'\nE4 promover con el código bueno: host=%s usuario=%s → %s', v ->> 'host', v ->> 'usuario', case when v ->> 'host' = 'smtp.proveedor.com' and (v ->> 'codigo_no_valido') is null then 'ok' else 'FALLA' end);
  v2 := public.correo_smtp_lee();
  r := r || format(E'\nE5 lee() devuelve el nuevo activo → %s', case when v2 ->> 'host' = 'smtp.proveedor.com' and v2 ->> 'pass' = 'secreto-uno' then 'ok' else 'FALLA' end);
  execute 'reset role';
  select estado into e from (select estado from public.correo_codigos where actor = u_sa order by id desc limit 1) x;
  r := r || format(E'\nE6 el código quedó «usado» (se consumió en la misma transacción): %s → %s', e, case when e = 'usado' then 'ok' else 'FALLA' end);
  r := r || format(E'\nE7 las claims de la sesión se restituyeron (no quedó el correo del actor puesto): %s → %s', coalesce(current_setting('request.jwt.claims', true), '') = claims_antes,
        case when coalesce(current_setting('request.jwt.claims', true), '') = claims_antes then 'ok' else 'FALLA' end);
  select quien, motivo into e, st from public.ajustes_log where clave = 'correo_salida' and despues ->> 'host' = 'smtp.proveedor.com' order by id desc limit 1;
  r := r || format(E'\nE8 el registro dice QUIÉN (el actor, no sistema:service_role): %s; motivo: %s → %s', e, st,
        case when e = m_sa and st like '%sin otro destinatario de aviso%' then 'ok' else 'FALLA' end);
  select count(*) into n from public.ajustes_log where antes::text like '%secreto%' or despues::text like '%secreto%' or motivo like '%secreto%';
  r := r || format(E'\nE9 la contraseña no está en ajustes_log: %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);
  -- el mismo código no sirve dos veces: otro candidato con el código ya usado
  execute 'set local role service_role';
  execute 'reset role'; delete from public.correo_smtp_intentos; execute 'set local role service_role';
  v := public.correo_smtp_guarda_candidato(u_sa, 'otro.proveedor.net', 465, 'otro@proveedor.net', 'secreto-dos', null);
  v2 := public.correo_smtp_promueve(u_sa, v ->> 'token', hu, ha);
  r := r || format(E'\nE10 un código ya usado no promueve otro cambio: %s → %s', v2::text, case when (v2 ->> 'codigo_no_valido')::boolean then 'ok' else 'FALLA' end);
  execute 'reset role';
  r := r || format(E'\nE10b y el candidato (con su contraseña) se descartó → %s',
        case when (public._correo_smtp_secreto('smtp_candidato') ? 'host') is false and public._correo_smtp_secreto('smtp_candidato')::text not like '%secreto-dos%' then 'ok' else 'FALLA' end);
  -- un código caducado entre la prueba y la promoción: tampoco
  delete from public.correo_smtp_intentos;
  update public.correo_codigos set estado = 'pendiente', caduca = now() - interval '1 second' where actor = u_sa and estado = 'usado';
  execute 'set local role service_role';
  v := public.correo_smtp_guarda_candidato(u_sa, 'otro.proveedor.net', 465, 'otro@proveedor.net', 'secreto-dos', null);
  v2 := public.correo_smtp_promueve(u_sa, v ->> 'token', hu, ha);
  r := r || format(E'\nE11 un código caducado durante la prueba tampoco promueve: %s → %s', v2::text, case when (v2 ->> 'codigo_no_valido')::boolean then 'ok' else 'FALLA' end);
  -- descartar: solo el candidato con SU token y del MISMO actor; no toca el activo
  execute 'reset role'; delete from public.correo_smtp_intentos; execute 'set local role service_role';
  v := public.correo_smtp_guarda_candidato(u_sa, 'otro.proveedor.net', 465, 'otro@proveedor.net', 'secreto-dos', null);
  perform public.correo_smtp_descarta(u_sa, 'otro-token');
  perform public.correo_smtp_descarta(u_s2, v ->> 'token');
  execute 'reset role';
  r := r || format(E'\nE12 descartar con otro token o desde otro super admin no quita el candidato → %s', case when public._correo_smtp_secreto('smtp_candidato') ->> 'token' = v ->> 'token' then 'ok' else 'FALLA' end);
  execute 'set local role service_role';
  perform public.correo_smtp_descarta(u_sa, v ->> 'token');
  execute 'reset role';
  r := r || format(E'\nE13 descartar con su token vacía el candidato (la contraseña que no funcionó no se queda) → %s',
        case when ((public._correo_smtp_secreto('smtp_candidato') ? 'host') is false) and public._correo_smtp_secreto('smtp_candidato')::text not like '%secreto-dos%' then 'ok' else 'FALLA' end);
  r := r || format(E'\nE14 y el activo sigue siendo el de antes de descartar → %s', case when public.correo_smtp_lee() ->> 'host' = 'smtp.proveedor.com' then 'ok' else 'FALLA' end);
  delete from public.correo_codigos;

  -- ── F. correo_ajuste_guarda: las cuatro claves, validadas ANTES de gastar el código, y con quien = el actor ──────────────────
  usr_dom := lower(split_part(public.correo_smtp_lee() ->> 'user', '@', 2));   -- 'proveedor.com' (del servidor que acaba de quedar activo)
  insert into public.config_instancia (clave, valor) values ('email_avisos_sistema', to_jsonb('sistema@' || dom)) on conflict (clave) do update set valor = excluded.valor;
  execute 'set local role service_role';
  perform public.correo_codigo_emite(u_sa, 'ajuste', hu, ha);
  for c in select je->>'c' as clave, je->'v' as valor, je->>'hint' as hint from jsonb_array_elements(jsonb_build_array(
      jsonb_build_object('c', 'marca', 'v', 'x@' || dom, 'hint', 'clave_no_editable'),
      jsonb_build_object('c', 'zona_horaria', 'v', 'UTC', 'hint', 'clave_no_editable'),
      jsonb_build_object('c', 'email_from', 'v', 'ventas@otro-dominio.com', 'hint', 'from_ajeno'),                    -- el remitente es del dominio del buzón del servidor
      jsonb_build_object('c', 'email_from', 'v', 'ventas@sub.' || usr_dom, 'hint', 'from_ajeno'),
      jsonb_build_object('c', 'email_from', 'v', 'no-es-correo', 'hint', 'valor_no_valido'),
      jsonb_build_object('c', 'email_from', 'v', '', 'hint', 'valor_no_valido'),
      jsonb_build_object('c', 'email_from', 'v', 'a@' || usr_dom || E'\nBcc: x@y.com', 'hint', 'valor_no_valido'),
      jsonb_build_object('c', 'email_reply_to', 'v', 'x', 'hint', 'valor_no_valido'),
      jsonb_build_object('c', 'email_reply_to', 'v', 'a@x.com, b@x.com', 'hint', 'valor_no_valido'),
      jsonb_build_object('c', 'email_avisos_soporte', 'v', 'x@gmail.com', 'hint', 'buzon_ajeno'),
      jsonb_build_object('c', 'email_avisos_sistema', 'v', 'sistema@' || dom || '.fraude.ru', 'hint', 'buzon_ajeno'),
      jsonb_build_object('c', 'email_avisos_sistema', 'v', 'sistema@fraude' || dom, 'hint', 'buzon_ajeno'),
      jsonb_build_object('c', 'email_avisos_sistema', 'v', 'sistema@sub.' || usr_dom, 'hint', 'buzon_ajeno'),            -- del servidor solo el dominio EXACTO
      jsonb_build_object('c', 'email_avisos_soporte', 'v', '', 'hint', 'valor_no_valido'),
      jsonb_build_object('c', 'email_avisos_soporte', 'v', jsonb_build_array('a@' || dom), 'hint', 'valor_no_valido'),
      jsonb_build_object('c', 'email_avisos_soporte', 'v', 'null'::jsonb, 'hint', 'valor_no_valido'))) je loop
    begin
      perform public.correo_ajuste_guarda(u_sa, c.clave, c.valor, hu, ha);
      r := r || format(E'\nF «%s» = %s → FALLA (entró)', c.clave, left(c.valor::text, 40));
    exception when others then
      get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint;
      r := r || format(E'\nF «%s» = %s se rechaza (%s, %s) → %s', c.clave, left(c.valor::text, 40), st, coalesce(h, '-'), case when st = '22023' and h = c.hint then 'ok' else 'FALLA' end);
    end;
  end loop;
  begin
    perform public.correo_ajuste_guarda(u_sa, 'email_reply_to', null::jsonb, hu, ha);
    r := r || E'\nF0 valor null de SQL → FALLA (entró)';
  exception when others then
    get stacked diagnostics st = returned_sqlstate;
    r := r || format(E'\nF0 valor null de SQL se rechaza (%s) → %s', st, case when st = '22023' then 'ok' else 'FALLA' end);
  end;
  execute 'reset role';
  select fallos, estado into f, e from public.correo_codigos where actor = u_sa and alcance = 'ajuste' order by id desc limit 1;
  r := r || format(E'\nF1 todo lo inválido se rechazó SIN gastar ni contar el código: fallos=%s estado=%s → %s', f, e, case when f = 0 and e = 'pendiente' then 'ok' else 'FALLA' end);
  -- código malo: no escribe
  execute 'set local role service_role';
  v := public.correo_ajuste_guarda(u_sa, 'email_reply_to', to_jsonb('r@' || dom), hu, ha2);
  execute 'reset role';
  select count(*) into n from public.config_instancia where clave = 'email_reply_to' and valor = to_jsonb('r@' || dom);
  r := r || format(E'\nF2 con un código malo no se escribe nada: %s; respuesta %s → %s', n, v::text, case when n = 0 and (v ->> 'codigo_no_valido')::boolean then 'ok' else 'FALLA' end);
  -- código de OTRO alcance (el de «servidor» no vale para un ajuste)
  delete from public.correo_codigos;
  execute 'set local role service_role';
  perform public.correo_codigo_emite(u_sa, 'servidor', hu, ha);
  v := public.correo_ajuste_guarda(u_sa, 'email_reply_to', to_jsonb('r@' || dom), hu, ha);
  execute 'reset role';
  select count(*) into n from public.config_instancia where clave = 'email_reply_to' and valor = to_jsonb('r@' || dom);
  r := r || format(E'\nF3 un código de «servidor» no vale para un ajuste: %s, escrito=%s → %s', v::text, n, case when n = 0 and (v ->> 'codigo_no_valido')::boolean then 'ok' else 'FALLA' end);
  -- código bueno: escribe, registra quién y con qué motivo, consume
  delete from public.correo_codigos;
  claims_antes := coalesce(current_setting('request.jwt.claims', true), '');
  execute 'set local role service_role';
  perform public.correo_codigo_emite(u_sa, 'ajuste', hu, ha);
  v := public.correo_ajuste_guarda(u_sa, 'email_reply_to', to_jsonb(' R@' || dom || ' '), hu, ha, 'sin otro destinatario de aviso');
  execute 'reset role';
  select quien, motivo into e, st from public.ajustes_log where clave = 'email_reply_to' order by id desc limit 1;
  r := r || format(E'\nF4 código bueno: cambiado=%s valor=%s; ajustes_log quien=%s motivo=%s → %s', v ->> 'cambiado', v ->> 'valor', e, st,
        case when (v ->> 'cambiado')::boolean and v ->> 'valor' = 'R@' || dom and e = m_sa and st like 'Confirmado con código%' and st like '%sin otro destinatario de aviso%' then 'ok' else 'FALLA' end);
  r := r || format(E'\nF5 las claims se restituyeron → %s', case when coalesce(current_setting('request.jwt.claims', true), '') = claims_antes then 'ok' else 'FALLA' end);
  select estado into e from public.correo_codigos where actor = u_sa order by id desc limit 1;
  r := r || format(E'\nF6 el código quedó «usado»: %s → %s', e, case when e = 'usado' then 'ok' else 'FALLA' end);
  execute 'set local role service_role';
  v := public.correo_ajuste_guarda(u_sa, 'email_reply_to', to_jsonb('otro@' || dom), hu, ha);
  r := r || format(E'\nF7 el mismo código no sirve dos veces: %s → %s', v::text, case when (v ->> 'codigo_no_valido')::boolean then 'ok' else 'FALLA' end);
  -- las otras tres claves (buzón de aviso: dominio de la instancia, del email_from o del servidor; reply_to vacío vale)
  for c in select je->>'c' as clave, je->'v' as valor, je->'esperado' as esperado from jsonb_array_elements(jsonb_build_array(
      jsonb_build_object('c', 'email_avisos_soporte', 'v', ' Soporte@' || dom || ' ', 'esperado', 'Soporte@' || dom),
      jsonb_build_object('c', 'email_avisos_sistema', 'v', 'sistema@correo.' || dom, 'esperado', 'sistema@correo.' || dom),
      jsonb_build_object('c', 'email_avisos_sistema', 'v', 'Avisos@' || upper(usr_dom), 'esperado', 'Avisos@' || upper(usr_dom)),   -- dominio del servidor, sin importar mayúsculas
      jsonb_build_object('c', 'email_reply_to', 'v', '', 'esperado', ''),
      jsonb_build_object('c', 'email_from', 'v', 'ventas@' || usr_dom, 'esperado', 'ventas@' || usr_dom),
      jsonb_build_object('c', 'email_from', 'v', 'a.b+c_d%e@' || usr_dom, 'esperado', 'a.b+c_d%e@' || usr_dom))) je loop
    execute 'reset role';
    delete from public.correo_codigos where actor = u_sa;
    insert into public.correo_codigos (actor, alcance, huella, hash) values (u_sa, 'ajuste', hu, ha);
    execute 'set local role service_role';
    begin
      v := public.correo_ajuste_guarda(u_sa, c.clave, c.valor, hu, ha);
      r := r || format(E'\nF8 «%s» = %s entra como %s → %s', c.clave, left(c.valor::text, 30), left(v ->> 'valor', 30), case when v -> 'valor' = c.esperado then 'ok' else 'FALLA' end);
    exception when others then
      get stacked diagnostics st = returned_sqlstate;
      r := r || format(E'\nF8 «%s» = %s se rechaza (%s) → FALLA', c.clave, left(c.valor::text, 30), st);
    end;
  end loop;
  execute 'reset role';
  -- las dos reglas compartidas, directas (la edge repite el formato en MAIL_BASE: sus casos están también en ajustes_correo.test.js)
  r := r || format(E'\nF10 _correo_mail_valido: %s → %s',
        array[public._correo_mail_valido('a@b.com'), public._correo_mail_valido('a.b+c_d%e@sub.b.co'), public._correo_mail_valido(repeat('a', 64) || '@b.com'), public._correo_mail_valido(repeat('a', 65) || '@b.com'),
              public._correo_mail_valido('.a@b.com'), public._correo_mail_valido('a..b@b.com'), public._correo_mail_valido('a@b'), public._correo_mail_valido('a@b.c'),
              public._correo_mail_valido('a b@b.com'), public._correo_mail_valido('a!b@b.com'), public._correo_mail_valido(''), public._correo_mail_valido(null)]::text,
        case when array[public._correo_mail_valido('a@b.com'), public._correo_mail_valido('a.b+c_d%e@sub.b.co'), public._correo_mail_valido(repeat('a', 64) || '@b.com'), public._correo_mail_valido(repeat('a', 65) || '@b.com'),
                        public._correo_mail_valido('.a@b.com'), public._correo_mail_valido('a..b@b.com'), public._correo_mail_valido('a@b'), public._correo_mail_valido('a@b.c'),
                        public._correo_mail_valido('a b@b.com'), public._correo_mail_valido('a!b@b.com'), public._correo_mail_valido(''), public._correo_mail_valido(null)]::boolean[]
                  = array[true, true, true, false, false, false, false, false, false, false, false, false]::boolean[] then 'ok' else 'FALLA' end);
  r := r || format(E'\nF11 _correo_buzon_propio: de la instancia=%s, subdominio=%s, del servidor=%s, ajeno=%s, sufijo falso=%s → %s',
        public._correo_buzon_propio('x@' || dom), public._correo_buzon_propio('x@sub.' || dom), public._correo_buzon_propio('x@' || usr_dom), public._correo_buzon_propio('x@fraude.ru'), public._correo_buzon_propio('x@fraude' || dom),
        case when public._correo_buzon_propio('x@' || dom) = '' and public._correo_buzon_propio('x@sub.' || dom) = '' and public._correo_buzon_propio('x@' || usr_dom) = ''
                  and public._correo_buzon_propio('x@fraude.ru') = 'buzon_ajeno' and public._correo_buzon_propio('x@fraude' || dom) = 'buzon_ajeno' then 'ok' else 'FALLA' end);
  -- F12: el correo gratuito (gmail…) del email_from o del usuario del servidor NO vale como «propio» (Seguridad, 8-oct-2026); el de dominio_web siempre vale
  declare
    f_from jsonb; f_act jsonb; f_dom jsonb; f_r text;
  begin
    select valor into f_from from public.config_instancia where clave = 'email_from';
    select valor into f_dom from public.config_instancia where clave = 'dominio_web';
    f_act := public._correo_smtp_secreto('smtp_activo');
    -- (a) email_from de un Gmail: su buzón NO cuenta
    insert into public.config_instancia (clave, valor) values ('email_from', to_jsonb('empresa@gmail.com'::text)) on conflict (clave) do update set valor = excluded.valor;
    f_r := public._correo_buzon_propio('empresa@gmail.com');
    r := r || format(E'\nF12a email_from de Gmail: el buzón gmail.com NO es propio (%s) → %s', f_r, case when f_r <> '' then 'ok' else 'FALLA' end);
    -- (b) usuario SMTP de un hotmail
    insert into public.config_instancia (clave, valor) values ('email_from', to_jsonb('ventas@' || dom_from)) on conflict (clave) do update set valor = excluded.valor;
    perform public._correo_smtp_pon('smtp_activo', f_act || jsonb_build_object('user', 'alguien@hotmail.com'), 'prueba F12');
    f_r := public._correo_buzon_propio('alguien@hotmail.com');
    r := r || format(E'\nF12b usuario SMTP de Hotmail: hotmail.com NO es propio (%s) → %s', f_r, case when f_r <> '' then 'ok' else 'FALLA' end);
    -- (c) el dominio de la empresa (dominio_web) vale aunque lo sea de un correo gratuito: es SU dominio
    insert into public.config_instancia (clave, valor) values ('dominio_web', to_jsonb('gmail.com'::text)) on conflict (clave) do update set valor = excluded.valor;
    f_r := public._correo_buzon_propio('x@gmail.com');
    r := r || format(E'\nF12c dominio_web=gmail.com SIEMPRE cuenta (%s) → %s', f_r, case when f_r = '' then 'ok' else 'FALLA' end);
    -- (d) un dominio de empresa de verdad sigue valiendo por email_from y por usuario SMTP
    if f_dom is null then delete from public.config_instancia where clave = 'dominio_web';
    else update public.config_instancia set valor = f_dom where clave = 'dominio_web'; end if;
    perform public._correo_smtp_pon('smtp_activo', f_act, 'prueba F12 (restaurado)');
    r := r || format(E'\nF12d dominios de empresa siguen valiendo (email_from=%s, servidor=%s) → %s', public._correo_buzon_propio('x@' || dom_from), public._correo_buzon_propio('x@' || usr_dom),
          case when public._correo_buzon_propio('x@' || dom_from) = '' and public._correo_buzon_propio('x@' || usr_dom) = '' then 'ok' else 'FALLA' end);
    if f_from is null then delete from public.config_instancia where clave = 'email_from';
    else update public.config_instancia set valor = f_from where clave = 'email_from'; end if;
  end;
  -- el camino viejo está cerrado: ajustes_config_guardar ya no escribe las 4 claves, ni siquiera un super admin
  perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  for c in select * from (values ('email_from'), ('email_reply_to'), ('email_avisos_sistema'), ('email_avisos_soporte')) x(clave) loop
    begin
      perform public.ajustes_config_guardar(c.clave, to_jsonb('a@' || dom));
      r := r || format(E'\nF9 ajustes_config_guardar escribe %s sin código → FALLA (entró)', c.clave);
    exception when others then
      get stacked diagnostics st = returned_sqlstate, h = pg_exception_hint;
      r := r || format(E'\nF9 ajustes_config_guardar ya no escribe %s (%s, %s) → %s', c.clave, st, coalesce(h, '-'), case when st = '22023' and h = 'clave_no_editable' then 'ok' else 'FALLA' end);
    end;
  end loop;
  execute 'reset role';
  perform set_config('request.jwt.claims', claims_antes, true);

  -- ── G. Vuelta atrás: una transacción, rastro y correo_smtp_lee() = NULL ───────────────────
  r := r || format(E'\nG0 antes de revertir hay servidor activo (existe=%s) y copia correo_salida → %s', public._correo_smtp_existe('smtp_activo'),
        case when public._correo_smtp_existe('smtp_activo') and exists (select 1 from public.config_instancia where clave = 'correo_salida') then 'ok' else 'FALLA' end);
  v := public.correo_smtp_revierte('prueba de vuelta atrás');
  r := r || format(E'\nG1 revierte: %s → %s', v::text, case when (v ->> 'revertido')::boolean and (v ->> 'habia_servidor')::boolean then 'ok' else 'FALLA' end);
  r := r || format(E'\nG2 lee() devuelve NULL (envia-correo cae a los SMTP_* del entorno) y «existe» dice que no → %s',
        case when public.correo_smtp_lee() is null and not public._correo_smtp_existe('smtp_activo') then 'ok' else 'FALLA' end);
  r := r || format(E'\nG2b smtp_previo (la contraseña del servidor anterior) también quedó vacío: hay_previo=%s existe=%s → %s', public.correo_smtp_estado() ->> 'hay_previo', public._correo_smtp_existe('smtp_previo'),
        case when (public.correo_smtp_estado() ->> 'hay_previo')::boolean is false and not public._correo_smtp_existe('smtp_previo') then 'ok' else 'FALLA' end);
  r := r || format(E'\nG3 la copia correo_salida se borró → %s', case when not exists (select 1 from public.config_instancia where clave = 'correo_salida') then 'ok' else 'FALLA' end);
  select quien, motivo, (despues is null) into e, st, ok from public.ajustes_log where clave = 'correo_salida' order by id desc limit 1;
  r := r || format(E'\nG4 rastro: borrado de correo_salida, motivo=%s, quien=%s → %s', st, e, case when ok and st like 'Vuelta atrás del servidor de correo: prueba de vuelta atrás%' then 'ok' else 'FALLA' end);
  v := public.correo_smtp_revierte('otra vez');
  r := r || format(E'\nG5 revertir dos veces no falla (habia_servidor=%s) → %s', v ->> 'habia_servidor', case when (v ->> 'habia_servidor')::boolean is false then 'ok' else 'FALLA' end);
  r := r || format(E'\nG6 el estado dice «no configurado» → %s', case when (public.correo_smtp_estado() ->> 'configurado')::boolean is false then 'ok' else 'FALLA' end);
  if not sin_activo then r := r || E'\nG8 la instancia YA tenía un servidor al empezar: se perdió dentro de la prueba, pero la transacción se deshace entera (nada que restaurar)'; end if;

  perform set_config('request.jwt.claims', '', true);
  raise exception 'FIN DE PRUEBAS F3.1b CÓDIGOS (se deshace):%', r;
end $$;
