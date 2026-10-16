-- LAW-338 L5 (16-oct-2026): PARIDAD de las 8 lecturas nuevas contra la lectura directa de hoy, usuario a usuario, con el rol real.
-- Migración: 20261016090000_law338_l5_compradores_datos.sql. Revisión previa #396 (Seguridad 2 y 3, Backend 4 y 5).
--   python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261016090000_law338_l5_compradores_datos.sql --prueba law338_l5_paridad.sql
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada línea acaba en «→ ok» o «→ FALLA». Solo LEE (todo en una
-- transacción que acaba en raise = rollback); va en rama porque crea funciones temporales y las RPC aún no están en la viva.
-- Qué mide:
--  P1 por cada usuario ACTIVO de `usuarios` y por cada sesión de PORTAL (correos de portal_accesos activos y destinatarios de
--     notificaciones sin ficha en `usuarios`), como `authenticated` con las claims COMPLETAS (sub, role, email: 4 de las 7 tablas
--     filtran por auth.email(); sin él todo sale a cero y la paridad saldría verde sin comparar nada), el jsonb ENTERO de cada RPC
--     (contenido, no solo ids: un cruce conserva los ids y cambia el pasaporte) contra el mismo jsonb armado con la lectura directa.
--     Una línea por comprobación: «dif» = usuarios con respuesta distinta; «llenos» = usuarios con algo dentro (tiene que ser > 0:
--     una paridad sobre vacíos no prueba nada); «err» = errores.
--  P2 ve=false: algún agente pide una ficha que no ve y no recibe ninguna parte (Seguridad #396.2).
--  P3 sin sesión → 42501 en las 8 y en clientes_busca; anon y service_role sin EXECUTE en las 11 (proacl).
--  P4 clientes_busca: `%@%` no lista nada; el correo exacto de una ficha visible la encuentra; sin la herramienta del asistente, 42501.
--  P5 contratos_busca y bot_pendientes como authenticated (DEFINER-lw_lector) dan lo mismo que su cuerpo leído directo.
--  P6 tiempo de documentos_desactualizados_datos por cliente y por id: 7 llamadas seguidas (la 6.ª ya puede ir con plan genérico).
-- Los nombres de las tablas aparecen en SQL dinámico de pg_temp: no son funciones INVOKER de public.

create temp table _u (uid uuid, em text, rol text, portal boolean);
create temp table _r (chk text, uid uuid, ok boolean, lleno boolean, err text);
create temp table _s (k text, v uuid, vs uuid[]);

-- ejecuta como authenticated con las claims de la persona: el jsonb o {"__err": sqlstate}
create function pg_temp.q(p_uid uuid, p_em text, p_sql text) returns jsonb language plpgsql as $f$
declare r jsonb;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else
          json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_em)::text end, true);
  execute 'set local role authenticated';
  begin execute p_sql into r;
  exception when others then r := jsonb_build_object('__err', sqlstate || ' ' || left(sqlerrm, 160)); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return r;
end $f$;
create function pg_temp.lleno(j jsonb) returns boolean language sql as $f$
  select case when j is null or j = 'null'::jsonb then false
              when jsonb_typeof(j) = 'array' then jsonb_array_length(j) > 0
              when jsonb_typeof(j) = 'object' then exists (select 1 from jsonb_each(j) e where pg_temp.lleno(e.value))
              else true end
$f$;
-- compara directo vs RPC para un usuario
create function pg_temp.par(p_chk text, u _u, p_dir text, p_rpc text) returns void language plpgsql as $f$
declare d jsonb; r jsonb;
begin
  d := pg_temp.q(u.uid, u.em, p_dir);
  r := pg_temp.q(u.uid, u.em, p_rpc);
  insert into _r values (p_chk, u.uid, d is not distinct from r, pg_temp.lleno(r),
                         coalesce(d->>'__err', r->>'__err'));
end $f$;
create function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;

do $todo$
declare
  u _u; x uuid; k uuid; ks uuid[]; cs uuid[]; f uuid; res text := ''; v jsonb; t0 timestamptz; ms int[] := '{}';
  v_chk text; n_u int; dif int; llenos int; errs int; agente _u; nove uuid; fichas uuid[];
  DOCF constant text := 'jsonb_build_object(''id'', d.id, ''doc_type'', d.doc_type, ''storage_path'', d.storage_path, ''uploaded_at'', d.uploaded_at, ''caduca_el'', d.caduca_el)';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS LAW-338 L5:%', E'\nP0 esta prueba crea funciones temporales: solo corre en rama → FALLA';
  end if;
  perform set_config('request.jwt.claims', '', true);

  -- ── quién: usuarios activos + sesiones de portal (sin ficha en usuarios) ─────────────────────────────────────────────
  insert into _u select u2.user_id, u2.email, u2.rol, false from public.usuarios u2 where u2.activo;
  insert into _u
    select coalesce((select au.id from auth.users au where lower(au.email) = e.em limit 1), gen_random_uuid()), e.em, 'portal', true
      from (select distinct lower(pa.email) em from public.portal_accesos pa where pa.activo
            union select distinct lower(n.destinatario) from public.notificaciones n
             where n.destinatario is not null and not exists (select 1 from public.usuarios u3 where lower(u3.email) = lower(n.destinatario))) e
     limit 8;

  -- ── muestras (como postgres): fichas con documentos, con portal, con soporte y una cualquiera; un contrato con compradores;
  --    contratos y una factura con correos ───────────────────────────────────────────────────────────────────────────────
  select array_agg(distinct z) into fichas from (
    (select d.client_id z from public.documents d where d.client_id is not null and d.retirado_el is null order by d.uploaded_at desc nulls last limit 3)
    union all (select pa.client_id from public.portal_accesos pa order by pa.creado_en desc limit 2)
    union all (select h.client_id from public.hilo_soporte h order by h.actualizado_en desc limit 1)
    union all (select c.id from public.clients c order by c.created_at limit 2)) s;
  select cc.contrato_id into k from public.contrato_compradores cc
   where exists (select 1 from public.documents d where d.client_id = cc.client_id) order by cc.contrato_id limit 1;
  select array_agg(cc.client_id order by cc.client_id) into cs from public.contrato_compradores cc where cc.contrato_id = k;
  select array_agg(z) into ks from (select distinct e.contrato_id z from public.correos_enviados e where e.contrato_id is not null limit 4) s;
  select e.factura_id into f from public.correos_enviados e where e.factura_id is not null order by e.enviado_en desc limit 1;
  res := res || pg_temp.l(cardinality(fichas) >= 4 and k is not null and cardinality(ks) >= 1 and f is not null,
    format('P0 muestras: %s fichas, contrato con compradores %s, %s contratos y 1 factura con correos, %s sesiones (%s de portal)',
           cardinality(fichas), k is not null, cardinality(ks), (select count(*) from _u), (select count(*) from _u where portal)));

  -- ── P1 paridad ────────────────────────────────────────────────────────────────────────────────────────────────────────
  for u in select * from _u loop
    perform pg_temp.par('clientes_lista', u,
      'select coalesce(jsonb_agg(jsonb_build_object(''id'', c.id, ''full_name'', c.full_name) order by c.full_name, c.id), ''[]'') from public.clients c',
      'select public.clientes_lista_datos()->''clientes''');
    perform pg_temp.par('clientes_lista(ids)', u,
      format('select coalesce(jsonb_agg(jsonb_build_object(''id'', c.id, ''full_name'', c.full_name) order by c.full_name, c.id), ''[]'') from public.clients c where c.id = any(%L::uuid[])', fichas),
      format('select public.clientes_lista_datos(%L::uuid[])->''clientes''', fichas));
    foreach x in array fichas loop
      perform pg_temp.par('ficha', u,
        format('select jsonb_build_object(''ve'', exists (select 1 from public.clients c where c.id = %1$L), ''ficha'', (select jsonb_build_object(''id'', c.id, ''numero_cliente'', c.numero_cliente, ''full_name'', c.full_name, ''email'', c.email, ''phone'', c.phone, ''nationality'', c.nationality, ''passport_number'', c.passport_number, ''tipo'', c.tipo, ''forma_juridica'', c.forma_juridica, ''registro_num'', c.registro_num, ''rep_nombre'', c.rep_nombre, ''rep_cargo'', c.rep_cargo, ''kyc_status'', c.kyc_status, ''idioma_comunicacion'', c.idioma_comunicacion, ''propietario'', c.propietario, ''created_at'', c.created_at) from public.clients c where c.id = %1$L))', x),
        format('select jsonb_build_object(''ve'', r->''ve'', ''ficha'', r->''ficha'') from (select public.comprador_ficha_datos(%L, array[''ficha'']) r) s', x));
      perform pg_temp.par('documento', u,
        format('select (select jsonb_build_object(''id'', c.id, ''full_name'', c.full_name, ''email'', c.email, ''passport_number'', c.passport_number, ''registro_num'', c.registro_num, ''address'', c.address) from public.clients c where c.id = %L)', x),
        format('select public.comprador_ficha_datos(%L, array[''documento''])->''documento''', x));
      perform pg_temp.par('documentos', u,
        format('select coalesce(jsonb_agg(%s order by d.uploaded_at desc nulls last, d.id desc), ''[]'') from public.documents d where d.client_id = %L', DOCF, x),
        format('select coalesce(public.comprador_ficha_datos(%L, array[''documentos''])->''documentos'', ''[]'')', x));
      perform pg_temp.par('portal', u,
        format('select coalesce(jsonb_agg(jsonb_build_object(''email'', p.email, ''activo'', p.activo, ''ultimo_acceso'', p.ultimo_acceso, ''accesos'', p.accesos) order by p.creado_en, p.id), ''[]'') from public.portal_accesos p where p.client_id = %L', x),
        format('select coalesce(public.comprador_ficha_datos(%L, array[''portal''])->''portal'', ''[]'')', x));
      -- soporte: solo cuando ve la ficha (con ve=false la RPC no da partes a propósito: P2)
      perform pg_temp.par('soporte', u,
        format('select case when exists (select 1 from public.clients c where c.id = %1$L) then jsonb_build_object(''ultimo'', (select jsonb_build_object(''de'', m.de, ''texto'', m.texto, ''creado_en'', m.creado_en) from public.mensajes_comprador m where m.client_id = %1$L order by m.creado_en desc, m.id desc limit 1), ''hilos'', (select coalesce(jsonb_agg(jsonb_build_object(''estado'', h.estado, ''actualizado_en'', h.actualizado_en) order by h.actualizado_en desc, h.id desc), ''[]'') from public.hilo_soporte h where h.client_id = %1$L)) end', x),
        format('select public.comprador_ficha_datos(%L, array[''soporte''])->''soporte''', x));
    end loop;
    perform pg_temp.par('operacion_compradores', u,
      format('select jsonb_build_object(''clientes'', (select coalesce(jsonb_agg(jsonb_build_object(''id'', c.id, ''full_name'', c.full_name, ''kyc_status'', c.kyc_status) order by c.full_name, c.id), ''[]'') from public.clients c where c.id = any(%2$L::uuid[])), ''documentos'', (select coalesce(jsonb_agg(jsonb_build_object(''doc_type'', d.doc_type, ''uploaded_at'', d.uploaded_at, ''caduca_el'', d.caduca_el, ''client_id'', d.client_id) order by d.uploaded_at desc nulls last, d.id desc), ''[]'') from public.documents d where d.contrato_id = %1$L or d.client_id = any(%2$L::uuid[])))', k, cs),
      format('select jsonb_build_object(''clientes'', r->''clientes'', ''documentos'', r->''documentos'') from (select public.operacion_compradores_datos(%L, %L::uuid[]) r) s', k, cs));
    perform pg_temp.par('operaciones_compradores', u,
      'select jsonb_build_object(''vinculos'', (select coalesce(jsonb_agg(jsonb_build_object(''contrato_id'', cc.contrato_id, ''rol'', cc.rol, ''cliente'', (select jsonb_build_object(''id'', c.id, ''full_name'', c.full_name, ''email'', c.email, ''phone'', c.phone, ''kyc_status'', c.kyc_status) from public.clients c where c.id = cc.client_id)) order by cc.contrato_id, cc.client_id), ''[]'') from public.contrato_compradores cc), ''documentos'', (select coalesce(jsonb_agg(jsonb_build_object(''id'', d.id, ''client_id'', d.client_id, ''contrato_id'', d.contrato_id, ''doc_type'', d.doc_type, ''storage_path'', d.storage_path, ''status'', d.status, ''uploaded_at'', d.uploaded_at, ''caduca_el'', d.caduca_el) order by d.uploaded_at desc nulls last, d.id desc), ''[]'') from public.documents d))',
      'select jsonb_build_object(''vinculos'', r->''vinculos'', ''documentos'', r->''documentos'') from (select public.operaciones_compradores_datos() r) s');
    perform pg_temp.par('soporte_datos', u,
      'select jsonb_build_object(''hilos'', (select coalesce(jsonb_agg(jsonb_build_object(''id'', h.id, ''client_id'', h.client_id, ''categoria'', h.categoria, ''estado'', h.estado, ''actualizado_en'', h.actualizado_en, ''factura_id'', h.factura_id, ''contrato_id'', h.contrato_id) order by h.actualizado_en desc, h.id desc), ''[]'') from public.hilo_soporte h), ''mensajes'', (select coalesce(jsonb_agg(jsonb_build_object(''hilo_id'', m.hilo_id, ''client_id'', m.client_id, ''de'', m.de, ''autor'', m.autor, ''texto'', m.texto, ''creado_en'', m.creado_en) order by m.creado_en desc, m.id desc), ''[]'') from (select * from public.mensajes_comprador mc order by mc.creado_en desc, mc.id desc limit 600) m), ''clientes'', (select coalesce(jsonb_agg(jsonb_build_object(''id'', c.id, ''full_name'', c.full_name, ''email'', c.email, ''phone'', c.phone, ''tipo'', c.tipo) order by c.full_name, c.id), ''[]'') from public.clients c where c.id in (select h.client_id from public.hilo_soporte h union select mc.client_id from public.mensajes_comprador mc)))',
      'select jsonb_build_object(''hilos'', r->''hilos'', ''mensajes'', r->''mensajes'', ''clientes'', r->''clientes'') from (select public.soporte_datos() r) s');
    perform pg_temp.par('notificaciones', u,
      'select coalesce(jsonb_agg(jsonb_build_object(''tipo'', t.tipo, ''titulo'', t.titulo, ''detalle'', t.detalle, ''enlace'', t.enlace, ''creado_en'', t.creado_en, ''destinatario'', t.destinatario) order by t.creado_en desc, t.id desc), ''[]'') from (select * from public.notificaciones n order by n.creado_en desc, n.id desc limit 400) t',
      'select public.notificaciones_datos(400)->''notificaciones''');
    perform pg_temp.par('correos(contratos)', u,
      format('select coalesce(jsonb_agg(jsonb_build_object(''para'', e.para, ''asunto'', e.asunto, ''via'', e.via, ''enviado_por'', e.enviado_por, ''enviado_en'', e.enviado_en, ''contrato_id'', e.contrato_id, ''factura_id'', e.factura_id) order by e.enviado_en desc, e.id desc), ''[]'') from (select * from public.correos_enviados x where x.contrato_id = any(%L::uuid[]) order by x.enviado_en desc, x.id desc limit 200) e', ks),
      format('select public.correos_registro_datos(%L::uuid[], null)->''correos''', ks));
    perform pg_temp.par('correos(factura)', u,
      format('select coalesce(jsonb_agg(jsonb_build_object(''para'', e.para, ''asunto'', e.asunto, ''via'', e.via, ''enviado_por'', e.enviado_por, ''enviado_en'', e.enviado_en, ''contrato_id'', e.contrato_id, ''factura_id'', e.factura_id) order by e.enviado_en desc, e.id desc), ''[]'') from (select * from public.correos_enviados x where x.factura_id = %L order by x.enviado_en desc, x.id desc limit 200) e', f),
      format('select public.correos_registro_datos(null, %L)->''correos''', f));
    perform pg_temp.par('ficha_distinta(cliente)', u,
      format('select coalesce(jsonb_agg(jsonb_build_object(''tipo'', d.tipo, ''id'', d.id, ''numero'', d.numero, ''congelado'', d.congelado, ''ficha'', d.ficha, ''diferencias'', d.diferencias) order by d.tipo, d.id), ''[]'') from public.documentos_desactualizados d where d.client_id = %L and jsonb_typeof(d.diferencias) = ''array'' and jsonb_array_length(d.diferencias) > 0', fichas[1]),
      format('select public.documentos_desactualizados_datos(null, %L, null)->''documentos''', fichas[1]));
  end loop;
  -- la vista por TIPO es cara (~12 s): un usuario por rol
  for u in select distinct on (rol) * from _u order by rol, uid loop
    perform pg_temp.par('ficha_distinta(tipo)', u,
      'select coalesce(jsonb_agg(jsonb_build_object(''tipo'', d.tipo, ''id'', d.id, ''numero'', d.numero, ''congelado'', d.congelado, ''ficha'', d.ficha, ''diferencias'', d.diferencias) order by d.tipo, d.id), ''[]'') from public.documentos_desactualizados d where d.tipo = ''contrato'' and jsonb_typeof(d.diferencias) = ''array'' and jsonb_array_length(d.diferencias) > 0',
      'select public.documentos_desactualizados_datos(''contrato'', null, null)->''documentos''');
  end loop;
  for v_chk in select distinct r.chk from _r r order by 1 loop
    select count(*), count(*) filter (where not r.ok), count(*) filter (where r.lleno), count(*) filter (where r.err is not null)
      into n_u, dif, llenos, errs from _r r where r.chk = v_chk;
    res := res || pg_temp.l(dif = 0 and errs = 0 and llenos > 0,
      format('P1 %s: %s sesiones, dif=%s, llenos=%s, err=%s%s', v_chk, n_u, dif, llenos, errs,
             coalesce(' (' || (select string_agg(distinct left(r.err, 60), '; ') from _r r where r.chk = v_chk and r.err is not null) || ')', '')));
  end loop;

  -- ── P2 ve=false: un agente con una ficha que no ve ───────────────────────────────────────────────────────────────────
  select * into agente from _u w where not w.portal and w.rol = 'agente'
     and exists (select 1 from unnest(fichas) z where (pg_temp.q(w.uid, w.em, format('select public.clientes_lista_datos(%L::uuid[])', array[z]))->'clientes') = '[]'::jsonb)
   limit 1;
  if agente.uid is null then
    res := res || pg_temp.l(false, 'P2 no hay agente que deje de ver alguna ficha de la muestra: caso sin medir');
  else
    select z into nove from unnest(fichas) z
     where (pg_temp.q(agente.uid, agente.em, format('select public.clientes_lista_datos(%L::uuid[])', array[z]))->'clientes') = '[]'::jsonb limit 1;
    v := pg_temp.q(agente.uid, agente.em, format('select public.comprador_ficha_datos(%L, array[''ficha'',''documento'',''documentos'',''portal'',''soporte''])', nove));
    res := res || pg_temp.l(v = '{"ve": false, "recortado": []}'::jsonb, 'P2 ficha que no ve: solo {ve:false}, ninguna parte (' || left(v::text, 80) || ')');
  end if;

  -- ── P3 sin sesión y ACL ────────────────────────────────────────────────────────────────────────────────────────────────
  res := res || pg_temp.l(
    (select bool_and(coalesce(pg_temp.q(null, null, s)->>'__err', '') like '42501%') from unnest(array[
      'select public.clientes_lista_datos()', format('select public.comprador_ficha_datos(%L, array[''ficha''])', fichas[1]),
      format('select public.operacion_compradores_datos(%L, %L::uuid[])', k, cs), 'select public.operaciones_compradores_datos()',
      'select public.soporte_datos()', 'select public.notificaciones_datos(5)', format('select public.correos_registro_datos(null, %L)', f),
      'select public.documentos_desactualizados_datos(''contrato'', null, null)',
      'select to_jsonb(array_agg(b)) from public.clientes_busca(''ana'') b']) s),
    'P3a sin sesión: 42501 en las 8 y en clientes_busca');
  res := res || pg_temp.l(
    (select bool_and(not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute')
                     and has_function_privilege('authenticated', p.oid, 'execute') and pg_get_userbyid(p.proowner) = 'lw_lector'
                     and p.prosecdef and p.proconfig @> array['search_path=""'])
       from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('clientes_lista_datos', 'comprador_ficha_datos', 'operacion_compradores_datos', 'operaciones_compradores_datos',
                          'soporte_datos', 'notificaciones_datos', 'correos_registro_datos', 'documentos_desactualizados_datos',
                          'clientes_busca', 'contratos_busca', 'bot_pendientes'))
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('clientes_lista_datos', 'comprador_ficha_datos', 'operacion_compradores_datos', 'operaciones_compradores_datos',
                            'soporte_datos', 'notificaciones_datos', 'correos_registro_datos', 'documentos_desactualizados_datos',
                            'clientes_busca', 'contratos_busca', 'bot_pendientes')) = 11,
    'P3b las 11: DEFINER, dueño lw_lector, search_path vacío, solo authenticated (sin anon ni service_role)');

  -- ── P4 clientes_busca ──────────────────────────────────────────────────────────────────────────────────────────────────
  select * into u from _u w where not w.portal and w.rol in ('super_admin', 'admin') order by w.rol desc, w.uid limit 1;
  v := pg_temp.q(u.uid, u.em, 'select coalesce(jsonb_agg(b), ''[]'') from public.clientes_busca(''%@%'') b');
  res := res || pg_temp.l(v = '[]'::jsonb, 'P4a clientes_busca(''%@%'') no lista nada (' || left(v::text, 60) || ')');
  select c.id into x from public.clients c where c.email like '%@%' order by c.created_at limit 1;
  v := pg_temp.q(u.uid, u.em, format('select coalesce(jsonb_agg(b.id), ''[]'') from public.clientes_busca((select upper(c.email) from public.clients c where c.id = %L)) b', x));
  res := res || pg_temp.l(v @> to_jsonb(array[x]), 'P4b el correo exacto (en mayúsculas) de una ficha visible la encuentra');
  select * into agente from _u w where not w.portal and w.rol = 'agente'
     and not exists (select 1 from public.usuarios u4 where u4.user_id = w.uid and 'asistente' = any(u4.herramientas)) limit 1;
  v := pg_temp.q(agente.uid, agente.em, 'select coalesce(jsonb_agg(b), ''[]'') from public.clientes_busca(''ana'') b');
  res := res || pg_temp.l(agente.uid is not null and coalesce(v->>'__err', '') like '42501%',
    'P4c sin la herramienta del asistente: 42501 (' || coalesce(left(v::text, 60), 'sin agente así') || ')');

  -- ── P5 contratos_busca y bot_pendientes por la RPC como authenticated ──────────────────────────────────────────────────
  for u in select * from _u w where not w.portal loop
    perform pg_temp.par('contratos_busca', u,
      'select coalesce(jsonb_agg(to_jsonb(b) order by b.created_at desc, b.id), ''[]'') from (select c.id, c.numero, c.created_at from public.contratos c where public.es_agente() and c.numero is not null order by c.created_at desc limit 10) b',
      'select coalesce(jsonb_agg(jsonb_build_object(''id'', b.id, ''numero'', b.numero, ''created_at'', b.created_at) order by b.created_at desc, b.id), ''[]'') from public.contratos_busca('''') b');
  end loop;
  select count(*), count(*) filter (where not r.ok), count(*) filter (where r.lleno), count(*) filter (where r.err is not null)
    into n_u, dif, llenos, errs from _r r where r.chk = 'contratos_busca';
  res := res || pg_temp.l(dif = 0 and errs = 0 and llenos > 0, format('P5a contratos_busca(''''): %s sesiones, dif=%s, llenos=%s, err=%s', n_u, dif, llenos, errs));
  select * into u from _u w where not w.portal and w.rol in ('super_admin', 'admin') order by w.rol desc, w.uid limit 1;
  select d.id into x from public.documentos_desactualizados d where d.tipo = 'contrato' and jsonb_typeof(d.diferencias) = 'array'
     and jsonb_array_length(d.diferencias) > 0 limit 1;
  v := pg_temp.q(u.uid, u.em, format('select coalesce(jsonb_agg(to_jsonb(b)), ''[]'') from public.bot_pendientes(%L) b', coalesce(x, k)));
  res := res || pg_temp.l(not coalesce(v ? '__err', true) and (x is null or jsonb_array_length(v) > 0),
    'P5b bot_pendientes como authenticated sin error' || case when x is null then ' (sin contrato que difiera: solo sin error)' else ' y con su motivo' end
    || ' (' || left(v::text, 60) || ')');

  -- ── P6 tiempo de documentos_desactualizados_datos (7 seguidas; la 6.ª y la 7.ª ya pueden ir con plan genérico) ──────────
  for i in 1..7 loop
    t0 := clock_timestamp();
    v := pg_temp.q(u.uid, u.em, format('select public.documentos_desactualizados_datos(null, %L, null)', fichas[1 + (i % cardinality(fichas))]));
    ms := ms || (extract(epoch from clock_timestamp() - t0) * 1000)::int;
  end loop;
  res := res || pg_temp.l((select max(z) from unnest(ms) z) < 4000, 'P6 por cliente, 7 llamadas (ms): ' || array_to_string(ms, ','));

  raise exception 'FIN DE PRUEBAS LAW-338 L5 (se deshace todo):%', res;
end $todo$;
