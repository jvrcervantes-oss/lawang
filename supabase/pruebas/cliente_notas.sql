-- Prueba de las notas de la ficha del cliente del 15-oct-2026 (migracion 20261015170000_cliente_notas).
-- Cada llamada va con el rol REAL (`set local role authenticated` + las claims de la persona, armazon de recibi_total_suma_y_exento.sql)
-- y cada NO lleva al lado un SI que solo cambia en lo que se prueba.
-- N1 el dueño de la ficha añade: autor y fecha los pone el servidor. N2 otro agente (no ve la ficha) no añade y nada cambia.
-- N3 leer = ver la ficha: por perfil, «ve notas» coincide con «ve la fila de clients» (dueño si, ajeno no, admin si).
-- N4 anonimo sin permiso. N5 vacia y >4000 se rechazan. N6 la tabla no se lee ni se escribe directo (ni authenticated ni la
-- edicion a mano como postgres). N7 retirar: el ajeno recibe «no existe» (no sondea ids), motivo fuera de lista se rechaza, el
-- autor la retira y su texto DESAPARECE (la traza no tiene columna de texto), un admin retira la de otro. N8 cuenta desactivada
-- no añade. N9 todo lo que escriba en clients.notes pasa al historial (alta y edicion) y la columna queda vacia. N10 borrar la
-- ficha borra sus notas y deja traza «ficha_borrada». N11 una nota NO bloquea la retencion KYC: cuenta como actividad.
-- XSS: el texto se guarda tal cual (la pantalla lo pinta con esc); aqui se comprueba que llega intacto, no que se ejecute.
-- !! CREA FICHAS, USUARIOS Y NOTAS: SOLO EN RAMA, NUNCA EN LA BASE VIVA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261015170000_cliente_notas.sql --prueba cliente_notas.sql
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada linea acaba en «→ ok» o «→ FALLA». Todo va marcado ZZ-CN.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create temp table _tp (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
-- ejecuta p_sql con la sesion de quien se dice (rol authenticated o anon): el resultado en texto, o el error
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else
          json_build_object('sub', p_uid, 'role', p_rol, 'email', p_email)::text end, true);
  execute 'set local role ' || p_rol;
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(t, '(null)');
end $f$;

insert into _tp values ('A',  gen_random_uuid(), 'zz-cn-agente@prueba.invalid'),
                       ('B',  gen_random_uuid(), 'zz-cn-ajeno@prueba.invalid'),
                       ('AD', gen_random_uuid(), 'zz-cn-admin@prueba.invalid'),
                       ('X',  gen_random_uuid(), 'zz-cn-baja@prueba.invalid');

do $todo$
declare
  r text := ''; v text; n bigint;
  a _tp; b _tp; ad _tp; x _tp;
  c1 uuid; c2 uuid; c3 uuid; n1 bigint; n2 bigint;
  c_xss constant text := '<img src=x onerror=alert(1)> "><svg onload=alert(2)>';
  c_fin constant text := 'FIN DE PRUEBAS NOTAS DEL CLIENTE (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS NOTAS DEL CLIENTE:%', E'\nP0 esta prueba crea fichas y usuarios: solo corre en rama → FALLA';
  end if;
  select * into a from _tp where et = 'A'; select * into b from _tp where et = 'B';
  select * into ad from _tp where et = 'AD'; select * into x from _tp where et = 'X';

  -- ============================================================ P. montaje (como postgres, SIN sesion)
  perform set_config('request.jwt.claims', '', true);
  begin
    insert into auth.users (id, instance_id, email, aud, role)
      select t.uid, '00000000-0000-0000-0000-000000000000', t.em, 'authenticated', 'authenticated' from _tp t;
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (a.uid,  a.em,  'ZZ-CN Agente',     'agente', 'global', '{}'::text[], '{}'::uuid[], '{}'::uuid[], '{compradores}'::text[], '{}'::text[], true),
      (b.uid,  b.em,  'ZZ-CN Ajeno',      'agente', 'global', '{}'::text[], '{}'::uuid[], '{}'::uuid[], '{compradores}'::text[], '{}'::text[], true),
      (ad.uid, ad.em, 'ZZ-CN Admin',      'admin',  'global', '{}'::text[], '{}'::uuid[], '{}'::uuid[], '{compradores}'::text[], '{}'::text[], true),
      (x.uid,  x.em,  'ZZ-CN Desactivado','agente', 'global', '{}'::text[], '{}'::uuid[], '{}'::uuid[], '{compradores}'::text[], '{}'::text[], false);
    insert into public.clients (full_name, email) values ('ZZ-CN CLIENTE UNO', 'zz-cn-c1@prueba.invalid') returning id into c1;
    update public.clients set propietario = a.em where id = c1;
    r := r || pg_temp.l(true, 'P montaje: 4 usuarios (agente dueño, agente ajeno, admin global, desactivado) y la ficha C1 de A');
  exception when others then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'P montaje: ' || sqlstate || ' ' || left(sqlerrm, 300)));
  end;

  -- ============================================================ N1 / N2 añadir
  v := pg_temp.val(a.uid, a.em, format('select (public.cliente_nota_agrega(%L, %L))->>''id''', c1, '  Primera nota de A  '));
  r := r || pg_temp.l(v ~ '^\d+$' and (select count(*) from public.cliente_notas where client_id = c1 and autor_id = a.uid
                                         and origen = 'nota' and texto = 'Primera nota de A' and creado_en is not null) = 1,
                      'N1 el dueño añade: autor = su id y texto recortado, por el servidor (' || left(v, 60) || ')');
  if v ~ '^\d+$' then n1 := v::bigint; end if;
  v := pg_temp.val(b.uid, b.em, format('select (public.cliente_nota_agrega(%L, %L))->>''id''', c1, 'Nota del ajeno'));
  r := r || pg_temp.l(v like 'ERR42501:%' and (select count(*) from public.cliente_notas where client_id = c1) = 1,
                      'N2 otro agente que no ve la ficha no añade y nada cambia (' || left(v, 80) || ')');
  v := pg_temp.val(a.uid, a.em, format('select (public.cliente_nota_agrega(%L, %L))->>''id''', c1, c_xss));
  r := r || pg_temp.l(v ~ '^\d+$' and exists (select 1 from public.cliente_notas where id = v::bigint and texto = c_xss),
                      'N1b un texto con HTML se guarda intacto (la pantalla lo escapa) (' || left(v, 40) || ')');
  if v ~ '^\d+$' then n2 := v::bigint; end if;

  -- ============================================================ N3 leer = ver la ficha
  v := pg_temp.val(a.uid, a.em, format('select jsonb_array_length((public.cliente_notas_datos(%L))->''notas'')::text || ''/'' || (select count(*) from public.clients where id = %L)', c1, c1));
  r := r || pg_temp.l(v = '2/1', 'N3 el dueño ve la ficha y sus 2 notas (' || v || ')');
  v := pg_temp.val(b.uid, b.em, format('select jsonb_array_length((public.cliente_notas_datos(%L))->''notas'')::text || ''/'' || (select count(*) from public.clients where id = %L)', c1, c1));
  r := r || pg_temp.l(v = '0/0', 'N3b el ajeno no ve la ficha ni sus notas (' || v || ')');
  v := pg_temp.val(ad.uid, ad.em, format('select jsonb_array_length((public.cliente_notas_datos(%L))->''notas'')::text || ''/'' || (select count(*) from public.clients where id = %L)', c1, c1));
  r := r || pg_temp.l(v = '2/1', 'N3c el admin global ve la ficha y sus notas (' || v || ')');
  v := pg_temp.val(a.uid, a.em, format('select (public.cliente_notas_datos(%L))->''notas''->0->>''autor_email''', c1));
  r := r || pg_temp.l(v = a.em, 'N3d la lectura trae el correo del autor para su nombre (' || v || ')');

  -- ============================================================ N4 anonimo
  v := pg_temp.val(null, null, format('select (public.cliente_notas_datos(%L))::text', c1), 'anon');
  r := r || pg_temp.l(v like 'ERR42501:%', 'N4 anonimo no puede leer (' || left(v, 70) || ')');
  v := pg_temp.val(null, null, format('select (public.cliente_nota_agrega(%L, %L))::text', c1, 'anon'), 'anon');
  r := r || pg_temp.l(v like 'ERR42501:%', 'N4b anonimo no puede añadir (' || left(v, 70) || ')');

  -- ============================================================ N5 texto
  v := pg_temp.val(a.uid, a.em, format('select (public.cliente_nota_agrega(%L, %L))::text', c1, '   '));
  r := r || pg_temp.l(v like 'ERR22023:%vac%', 'N5 una nota vacia se rechaza (' || left(v, 60) || ')');
  v := pg_temp.val(a.uid, a.em, format('select (public.cliente_nota_agrega(%L, %L))::text', c1, repeat('x', 4001)));
  r := r || pg_temp.l(v like 'ERR22023:%4000%', 'N5b una nota de 4001 caracteres se rechaza (' || left(v, 60) || ')');

  -- ============================================================ N6 la tabla no se toca directo
  v := pg_temp.val(a.uid, a.em, 'select count(*)::text from public.cliente_notas');
  r := r || pg_temp.l(v like 'ERR42501:%', 'N6 authenticated no lee la tabla directamente (' || left(v, 60) || ')');
  v := pg_temp.val(a.uid, a.em, format('insert into public.cliente_notas (client_id, texto, autor_id) values (%L, ''x'', %L) returning id::text', c1, b.uid));
  r := r || pg_temp.l(v like 'ERR42501:%', 'N6b authenticated no inserta directamente (ni con otro autor) (' || left(v, 60) || ')');
  begin
    update public.cliente_notas set texto = 'cambiada' where id = n1;
    r := r || pg_temp.l(false, 'N6c editar una nota a mano como postgres debería rechazarse');
  exception when others then
    r := r || pg_temp.l(sqlstate = '42501' and (select texto from public.cliente_notas where id = n1) = 'Primera nota de A',
                        'N6c una nota no se edita ni como postgres (' || sqlstate || ')');
  end;

  -- ============================================================ N7 retirar
  v := pg_temp.val(b.uid, b.em, format('select (public.cliente_nota_retira(%s, %L))::text', n1, 'otro'));
  r := r || pg_temp.l(v like 'ERRP0002:Esa nota no existe%' and exists (select 1 from public.cliente_notas where id = n1),
                      'N7 el ajeno recibe «no existe» y la nota sigue (' || left(v, 60) || ')');
  v := pg_temp.val(a.uid, a.em, format('select (public.cliente_nota_retira(%s, %L))::text', n1, 'porque si'));
  r := r || pg_temp.l(v like 'ERR22023:%', 'N7b un motivo fuera de la lista se rechaza (' || left(v, 60) || ')');
  v := pg_temp.val(a.uid, a.em, format('select (public.cliente_nota_retira(%s, %L))::text', n1, 'rectificacion'));
  r := r || pg_temp.l(v like '%"ok": true%' and not exists (select 1 from public.cliente_notas where id = n1)
                      and exists (select 1 from public.cliente_notas_retiradas where nota_id = n1 and client_id = c1 and autor_id = a.uid
                                    and retirada_por_id = a.uid and motivo = 'rectificacion')
                      and not exists (select 1 from information_schema.columns where table_schema = 'public'
                                        and table_name = 'cliente_notas_retiradas' and column_name = 'texto'),
                      'N7c el autor la retira: el texto desaparece y queda la traza sin texto (' || left(v, 40) || ')');
  v := pg_temp.val(a.uid, a.em, format('select (public.cliente_nota_retira(%s, %L))::text', n1, 'otro'));
  r := r || pg_temp.l(v like 'ERRP0002:%', 'N7d retirarla otra vez: «no existe» (' || left(v, 60) || ')');
  v := pg_temp.val(ad.uid, ad.em, format('select (public.cliente_nota_retira(%s, %L))::text', n2, 'dato_sensible'));
  r := r || pg_temp.l(v like '%"ok": true%' and not exists (select 1 from public.cliente_notas where id = n2),
                      'N7e un admin global retira la nota de otro (' || left(v, 40) || ')');
  begin
    delete from public.cliente_notas_retiradas where nota_id = n1;
    r := r || pg_temp.l(false, 'N7f la traza debería ser de solo añadir');
  exception when others then
    r := r || pg_temp.l(sqlstate = '42501', 'N7f la traza es de solo añadir (' || sqlstate || ')');
  end;

  -- ============================================================ N8 desactivado
  v := pg_temp.val(x.uid, x.em, format('select (public.cliente_nota_agrega(%L, %L))::text', c1, 'de baja'));
  r := r || pg_temp.l(v like 'ERR42501:%', 'N8 una cuenta desactivada no añade (' || left(v, 60) || ')');

  -- ============================================================ N9 la columna vieja pasa al historial
  perform set_config('request.jwt.claims', json_build_object('sub', a.uid, 'role', 'authenticated', 'email', a.em)::text, true);
  update public.clients set notes = '  Escrita en el campo viejo  ' where id = c1;
  perform set_config('request.jwt.claims', '', true);
  r := r || pg_temp.l((select notes from public.clients where id = c1) is null
                      and exists (select 1 from public.cliente_notas where client_id = c1 and origen = 'campo_notas'
                                    and texto = 'Escrita en el campo viejo' and autor_id = a.uid),
                      'N9 editar clients.notes crea una nota (autor = quien llama) y deja la columna vacía');
  insert into public.clients (full_name, email, notes) values ('ZZ-CN CLIENTE DOS', 'zz-cn-c2@prueba.invalid', 'Nota del alta') returning id into c2;
  r := r || pg_temp.l((select notes from public.clients where id = c2) is null
                      and exists (select 1 from public.cliente_notas where client_id = c2 and origen = 'campo_notas'
                                    and texto = 'Nota del alta' and autor_id is null),
                      'N9b un alta con notas crea la nota (sin sesión, sin autor) y la columna queda vacía');

  -- ============================================================ N10 borrar la ficha
  delete from public.clients where id = c2;
  r := r || pg_temp.l(not exists (select 1 from public.cliente_notas where client_id = c2)
                      and exists (select 1 from public.cliente_notas_retiradas where client_id = c2 and motivo = 'ficha_borrada'),
                      'N10 borrar una ficha borra sus notas y deja la traza «ficha_borrada»');

  -- ============================================================ N11 retencion KYC
  begin
    insert into public.clients (full_name, email) values ('ZZ-CN CLIENTE TRES', 'zz-cn-c3@prueba.invalid') returning id into c3;
    set local session_replication_role = replica;   -- fechas viejas sin disparadores (no es lo que se prueba)
    update public.clients set created_at = '2024-01-01' where id = c3;
    set local session_replication_role = origin;
    insert into public.documents (client_id, doc_type, storage_path, uploaded_at) values (c3, 'passport', 'zz-cn/pasaporte.pdf', '2024-01-01');
    v := public._kyc_retencion_candidato(c3, now() - interval '12 months')::text;
    insert into public.cliente_notas (client_id, texto, origen) values (c3, 'nota antigua', 'antigua');
    set local session_replication_role = replica;
    update public.cliente_notas set creado_en = '2024-02-01' where client_id = c3;
    set local session_replication_role = origin;
    v := v || '/' || public._kyc_retencion_candidato(c3, now() - interval '12 months')::text;
    insert into public.cliente_notas (client_id, texto, origen) values (c3, 'nota de hoy', 'antigua');
    v := v || '/' || public._kyc_retencion_candidato(c3, now() - interval '12 months')::text;
    r := r || pg_temp.l(v = 'true/true/false',
                        'N11 sin notas es candidata; con una nota vieja SIGUE siéndolo; una nota reciente la retrasa (' || v || ')');
  exception when others then
    r := r || pg_temp.l(false, 'N11 retencion KYC: ' || sqlstate || ' ' || left(sqlerrm, 200));
  end;

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
