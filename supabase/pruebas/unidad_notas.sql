-- Prueba de las notas de la ficha de la parcela del 15-oct-2026 (migracion 20261016001810_unidad_notas).
-- Cada llamada va con el rol REAL (`set local role authenticated` + las claims de la persona, armazon de cliente_notas.sql)
-- por la RPC que usa la pantalla (lecciones de Backend 11 y 13-oct), y cada NO lleva al lado un SI que solo cambia en lo que se prueba.
-- U1 el PM del proyecto añade (autor y fecha del servidor). U2 leer: PM, admin global y admin de la empresa leen, con
-- autor_nombre y puede_retirar bien puestos. U3 NO leen (42501, no lista vacia): agente que VE la parcela, PM de otro proyecto
-- que tambien la ve, sales_manager, PM sin la herramienta «unidades», admin de otra empresa, cuenta desactivada, anonimo y sin
-- sesion. U4 los mismos NO añaden y nada cambia. U5 texto: vacia, 4001, parcela nula o inexistente. U6 la tabla no se toca
-- directo (authenticated ni la edicion a mano como postgres; traza de solo añadir). U7 retirar: quien no ve la parcela recibe
-- «no existe», motivo fuera de lista, el agente que la ve pero no es autor ni admin no retira, el autor retira y el texto
-- DESAPARECE, el admin de la empresa retira la de otro, una nota sin autor solo la retira un admin; puede_retirar coincide
-- con lo que hace la llamada real. U7c autor_nombre de un admin global visto por un admin de empresa (RLS de usuarios).
-- U8-U10 la columna vieja: unidad_guarda (edicion y alta) y unidades_importa (actualizacion y alta) con «notas» dejan una
-- nota «campo_notas» firmada y la columna vacia; sin «notas» no crean nada; U9c-e un texto que la parcela YA tiene (pestaña
-- vieja, CSV exportado antes) no se duplica y uno distinto si entra. U11 check (notas is null) aunque se salten los
-- disparadores. U12 borrar_unidad (como postgres: está cerrada a authenticated) borra las notas y deja traza «ficha_borrada». U13 (Legal, #376) las filas NUEVAS de
-- unidades_log (alta, ficha, csv, y U13d las diferidas que se escriben al confirmar) llevan notas null. U14 tope: 30 en 10 minutos por agrega, por unidad_guarda, y una
-- importacion de 31 filas con notas aborta ENTERA (0 notas y 0 parcelas). U15/U16 cliente_notas_datos: conserva sus claves
-- de antes (autor_email) y añade autor_nombre y puede_retirar, que coincide con cliente_nota_retira real (autor si, agente no
-- autor no, admin de empresa si, admin global si).
-- XSS: el texto se guarda tal cual (la pantalla lo pinta escapado); aqui se comprueba que llega intacto.
-- !! CREA EMPRESAS, PROYECTOS, PARCELAS, USUARIOS, FICHAS Y NOTAS: SOLO EN RAMA, NUNCA EN LA BASE VIVA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261016001810_unidad_notas.sql --prueba unidad_notas.sql
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada linea acaba en «→ ok» o «→ FALLA». Todo va marcado ZZ-UN.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama (usa session_replication_role para U11)
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

insert into _tp values ('PM',  gen_random_uuid(), 'zz-un-pm@prueba.invalid'),
                       ('PM2', gen_random_uuid(), 'zz-un-pm-otro@prueba.invalid'),
                       ('PMH', gen_random_uuid(), 'zz-un-pm-sin-herr@prueba.invalid'),
                       ('AG',  gen_random_uuid(), 'zz-un-agente@prueba.invalid'),
                       ('SM',  gen_random_uuid(), 'zz-un-sales@prueba.invalid'),
                       ('AE',  gen_random_uuid(), 'zz-un-admin-empresa@prueba.invalid'),
                       ('AO',  gen_random_uuid(), 'zz-un-admin-otra@prueba.invalid'),
                       ('AD',  gen_random_uuid(), 'zz-un-admin@prueba.invalid'),
                       ('SA',  gen_random_uuid(), 'zz-un-super@prueba.invalid'),
                       ('X',   gen_random_uuid(), 'zz-un-baja@prueba.invalid');

do $todo$
declare
  r text := ''; v text; v2 text; n bigint; j jsonb;
  pm _tp; pm2 _tp; pmh _tp; ag _tp; sm _tp; ae _tp; ao _tp; ad _tp; sa _tp; x _tp;
  c_emp  constant text := 'zz_un';
  c_otra constant text := 'zz_un_otra';
  pP uuid; pQ uuid; pO uuid; pPn text := 'ZZ-UN Proyecto'; pOn text := 'ZZ-UN Proyecto otra';
  u1 uuid; u2 uuid; u3 uuid; uo uuid; c1 uuid; ualta uuid;
  n1 bigint; n2 bigint; nad bigint; nant bigint; cn_ag bigint; cn_ad bigint; cn_ad2 bigint;
  c_xss constant text := '<img src=x onerror=alert(1)> "><svg onload=alert(2)>';
  c_fin constant text := 'FIN DE PRUEBAS NOTAS DE LA PARCELA (se deshace todo):%';
  -- las 3 lecturas que se repiten: cuantas notas, y la nota n de quien llama
  q_cuenta constant text := 'select jsonb_array_length((public.unidad_notas_datos(%L))->''notas'')::text';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS NOTAS DE LA PARCELA:%', E'\nP0 esta prueba crea usuarios y parcelas: solo corre en rama → FALLA';
  end if;
  select * into pm from _tp where et = 'PM';   select * into pm2 from _tp where et = 'PM2'; select * into pmh from _tp where et = 'PMH';
  select * into ag from _tp where et = 'AG';   select * into sm from _tp where et = 'SM';   select * into ae from _tp where et = 'AE';
  select * into ao from _tp where et = 'AO';   select * into ad from _tp where et = 'AD';   select * into sa from _tp where et = 'SA';
  select * into x from _tp where et = 'X';

  -- ============================================================ P. montaje (como postgres, SIN sesion)
  perform set_config('request.jwt.claims', '', true);
  begin
    insert into public.empresas (clave, nombre) values (c_emp, 'ZZ-UN Empresa'), (c_otra, 'ZZ-UN Otra empresa');
    insert into public.proyectos (nombre, slug, empresa, activo) values (pPn, 'zz-un-proyecto', c_emp, true) returning id into pP;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-UN Proyecto Q', 'zz-un-proyecto-q', c_emp, true) returning id into pQ;
    insert into public.proyectos (nombre, slug, empresa, activo) values (pOn, 'zz-un-proyecto-otra', c_otra, true) returning id into pO;
    insert into auth.users (id, instance_id, email, aud, role)
      select t.uid, '00000000-0000-0000-0000-000000000000', t.em, 'authenticated', 'authenticated' from _tp t;
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (pm.uid,  pm.em,  'ZZ-UN PM',               'project_manager',     'global',  array[c_emp],  array[pP],     array[pP],     '{unidades,compradores}'::text[], '{}'::text[], true),
      (pm2.uid, pm2.em, 'ZZ-UN PM de otro',       'project_manager',     'global',  array[c_emp],  array[pP, pQ], array[pQ],     '{unidades}'::text[],             '{}'::text[], true),
      (pmh.uid, pmh.em, 'ZZ-UN PM sin unidades',  'project_manager',     'global',  array[c_emp],  array[pP],     array[pP],     '{}'::text[],                     '{}'::text[], true),
      (ag.uid,  ag.em,  'ZZ-UN Agente',           'agente',              'global',  array[c_emp],  array[pP],     '{}'::uuid[],  '{unidades,compradores}'::text[], '{}'::text[], true),
      (sm.uid,  sm.em,  'ZZ-UN Sales manager',    'sales_manager',       'global',  array[c_emp],  array[pP],     '{}'::uuid[],  '{unidades}'::text[],             '{}'::text[], true),
      (ae.uid,  ae.em,  'ZZ-UN Admin empresa',    'admin_empresa',       'empresa', array[c_emp],  '{}'::uuid[],  '{}'::uuid[],  '{unidades,compradores}'::text[], '{}'::text[], true),
      (ao.uid,  ao.em,  'ZZ-UN Admin otra',       'admin_empresa',       'empresa', array[c_otra], '{}'::uuid[],  '{}'::uuid[],  '{unidades}'::text[],             '{}'::text[], true),
      (ad.uid,  ad.em,  'ZZ-UN Admin',            'admin',               'global',  '{}'::text[],  '{}'::uuid[],  '{}'::uuid[],  '{unidades,compradores}'::text[], '{}'::text[], true),
      (sa.uid,  sa.em,  'ZZ-UN Super admin',      'super_admin',         'global',  '{}'::text[],  '{}'::uuid[],  '{}'::uuid[],  '{}'::text[],                     '{}'::text[], true),
      (x.uid,   x.em,   'ZZ-UN PM de baja',       'project_manager',     'global',  array[c_emp],  array[pP],     array[pP],     '{unidades}'::text[],             '{}'::text[], false);
    -- la rama nace de la ESTRUCTURA del volcado (catálogos vacíos): sin esta fila, unidades_tipo_fkey da 23503 (ensayo 16-oct,
    -- lawang-202610160618-47b9a37a). Misma fila que la viva, como invitacion_portal.sql y precio_cadena_vigente.sql
    insert into public.tipos_vivienda (clave, etiqueta) values ('parcela', 'Parcela') on conflict (clave) do nothing;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, estado) values ('ZZ-UN-1', pPn, pP, 'parcela', 'disponible') returning id into u1;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, estado) values ('ZZ-UN-2', pPn, pP, 'parcela', 'disponible') returning id into u2;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, estado) values ('ZZ-UN-3', pPn, pP, 'parcela', 'disponible') returning id into u3;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, estado) values ('ZZ-UN-O', pOn, pO, 'parcela', 'disponible') returning id into uo;
    insert into public.clients (full_name, email) values ('ZZ-UN CLIENTE', 'zz-un-c1@prueba.invalid') returning id into c1;
    update public.clients set propietario = ag.em where id = c1;
    r := r || pg_temp.l(true, 'P montaje: 10 usuarios, 2 empresas, 3 proyectos, 4 parcelas y la ficha C1 del agente');
  exception when others then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'P montaje: ' || sqlstate || ' ' || left(sqlerrm, 300)));
  end;

  -- ============================================================ U1 añadir
  v := pg_temp.val(pm.uid, pm.em, format('select (public.unidad_nota_agrega(%L, %L))->>''id''', u1, '  Primera nota del PM  '));
  r := r || pg_temp.l(v ~ '^\d+$' and (select count(*) from public.unidad_notas where unidad_id = u1 and autor_id = pm.uid
                                         and origen = 'nota' and texto = 'Primera nota del PM' and creado_en is not null) = 1,
                      'U1 el PM del proyecto añade: autor = su id y texto recortado, por el servidor (' || left(v, 60) || ')');
  if v ~ '^\d+$' then n1 := v::bigint; end if;
  v := pg_temp.val(pm.uid, pm.em, format('select (public.unidad_nota_agrega(%L, %L))->>''id''', u1, c_xss));
  r := r || pg_temp.l(v ~ '^\d+$' and exists (select 1 from public.unidad_notas where id = v::bigint and texto = c_xss),
                      'U1b un texto con HTML se guarda intacto (la pantalla lo escapa) (' || left(v, 40) || ')');
  if v ~ '^\d+$' then n2 := v::bigint; end if;
  v := pg_temp.val(ad.uid, ad.em, format('select (public.unidad_nota_agrega(%L, %L))->>''id''', u1, 'Nota del admin global'));
  r := r || pg_temp.l(v ~ '^\d+$', 'U1c el admin global añade (' || left(v, 40) || ')');
  if v ~ '^\d+$' then nad := v::bigint; end if;
  v := pg_temp.val(ae.uid, ae.em, format('select (public.unidad_nota_agrega(%L, %L))->>''id''', u3, 'Nota del admin de empresa'));
  r := r || pg_temp.l(v ~ '^\d+$', 'U1d el admin de la empresa añade (' || left(v, 40) || ')');

  -- ============================================================ U2 leer: PM, admin global, admin de empresa
  v := pg_temp.val(pm.uid, pm.em, format('select (public.unidad_notas_datos(%L))::text', u1));
  j := case when v like '{%' then v::jsonb end;
  r := r || pg_temp.l(jsonb_array_length(j->'notas') = 3 and (j->>'recortado') = 'false'
                      and (select string_agg(e->>'id' || ':' || (e->>'puede_retirar') || ':' || coalesce(e->>'autor_nombre', 'null'), ',' order by (e->>'id')::bigint)
                             from jsonb_array_elements(j->'notas') e)
                          = n1 || ':true:ZZ-UN PM,' || n2 || ':true:ZZ-UN PM,' || nad || ':false:ZZ-UN Admin',
                      'U2 el PM lee sus 2 notas (puede_retirar true) y la del admin (false), con autor_nombre (' || left(coalesce(v, ''), 120) || ')');
  r := r || pg_temp.l((select bool_and(e ?& array['id', 'texto', 'origen', 'creado_en', 'autor_id', 'autor_nombre', 'puede_retirar'])
                         from jsonb_array_elements(j->'notas') e)
                      and (select (array_agg(e->>'id'))[1] from jsonb_array_elements(j->'notas') e) = nad::text,
                      'U2b cada nota trae las 7 claves del contrato y la mas reciente va primero');
  v := pg_temp.val(ad.uid, ad.em, format('select (public.unidad_notas_datos(%L))::text', u1));
  j := case when v like '{%' then v::jsonb end;
  r := r || pg_temp.l(jsonb_array_length(j->'notas') = 3
                      and (select bool_and((e->>'puede_retirar')::boolean) from jsonb_array_elements(j->'notas') e),
                      'U2c el admin global lee las 3 y puede retirar todas (' || left(coalesce(v, ''), 60) || ')');
  v := pg_temp.val(ae.uid, ae.em, format('select (public.unidad_notas_datos(%L))::text', u1));
  j := case when v like '{%' then v::jsonb end;
  r := r || pg_temp.l(jsonb_array_length(j->'notas') = 3
                      and (select bool_and((e->>'puede_retirar')::boolean) from jsonb_array_elements(j->'notas') e),
                      'U2d el admin de la empresa lee las 3 y puede retirar todas (' || left(coalesce(v, ''), 60) || ')');
  -- U7c (adelantada): el admin de empresa tiene alcance restringido y aun asi ve el nombre de un admin global (empresas vacias)
  r := r || pg_temp.l((select e->>'autor_nombre' from jsonb_array_elements(j->'notas') e where (e->>'id')::bigint = nad) = 'ZZ-UN Admin'
                      and (select e->>'autor_nombre' from jsonb_array_elements(j->'notas') e where (e->>'id')::bigint = n1) = 'ZZ-UN PM',
                      'U7c el admin de empresa ve el nombre del autor (admin global y PM de su empresa), no «sin autor»');

  -- ============================================================ U3 NO leen (42501, no lista vacia)
  -- el agente y el PM de otro proyecto SI ven la parcela: la negativa es por no poder editarla, no por no verla
  v := pg_temp.val(ag.uid, ag.em, format('select (select count(*) from public.unidades where id = %L)::text', u1));
  v2 := pg_temp.val(ag.uid, ag.em, format(q_cuenta, u1));
  r := r || pg_temp.l(v = '1' and v2 like 'ERR42501:%', 'U3 el agente VE la parcela pero no lee sus notas (' || v || ' / ' || left(v2, 60) || ')');
  v := pg_temp.val(pm2.uid, pm2.em, format('select (select count(*) from public.unidades where id = %L)::text', u1));
  v2 := pg_temp.val(pm2.uid, pm2.em, format(q_cuenta, u1));
  r := r || pg_temp.l(v = '1' and v2 like 'ERR42501:%', 'U3b el PM de OTRO proyecto ve la parcela pero no lee sus notas (' || v || ' / ' || left(v2, 60) || ')');
  v := pg_temp.val(sm.uid, sm.em, format(q_cuenta, u1));
  r := r || pg_temp.l(v like 'ERR42501:%', 'U3c el sales_manager no lee (' || left(v, 60) || ')');
  v := pg_temp.val(pmh.uid, pmh.em, format(q_cuenta, u1));
  r := r || pg_temp.l(v like 'ERR42501:%', 'U3d un PM sin la herramienta «unidades» no lee (la misma puerta que unidad_guarda) (' || left(v, 60) || ')');
  v := pg_temp.val(ao.uid, ao.em, format(q_cuenta, u1));
  r := r || pg_temp.l(v like 'ERR42501:%', 'U3e el admin de OTRA empresa no lee (' || left(v, 60) || ')');
  v := pg_temp.val(x.uid, x.em, format(q_cuenta, u1));
  r := r || pg_temp.l(v like 'ERR42501:%', 'U3f una cuenta desactivada no lee (' || left(v, 60) || ')');
  v := pg_temp.val(null, null, format(q_cuenta, u1), 'anon');
  r := r || pg_temp.l(v like 'ERR42501:%', 'U3g anonimo no lee (' || left(v, 60) || ')');
  v := pg_temp.val(null, null, format(q_cuenta, u1));
  r := r || pg_temp.l(v like 'ERR42501:%', 'U3h authenticated sin sesion no lee (' || left(v, 60) || ')');
  v := pg_temp.val(pm.uid, pm.em, format(q_cuenta, uo));
  r := r || pg_temp.l(v like 'ERR42501:%', 'U3i el PM no lee las notas de una parcela de otra empresa (' || left(v, 60) || ')');

  -- ============================================================ U4 NO añaden y nada cambia
  n := (select count(*) from public.unidad_notas where unidad_id = u1);
  v := pg_temp.val(ag.uid, ag.em, format('select (public.unidad_nota_agrega(%L, %L))::text', u1, 'del agente'));
  r := r || pg_temp.l(v like 'ERR42501:%', 'U4 el agente que ve la parcela no añade (' || left(v, 60) || ')');
  v := pg_temp.val(pm2.uid, pm2.em, format('select (public.unidad_nota_agrega(%L, %L))::text', u1, 'del PM de otro'));
  r := r || pg_temp.l(v like 'ERR42501:%', 'U4b el PM de otro proyecto no añade (' || left(v, 60) || ')');
  v := pg_temp.val(sm.uid, sm.em, format('select (public.unidad_nota_agrega(%L, %L))::text', u1, 'del sales'));
  r := r || pg_temp.l(v like 'ERR42501:%', 'U4c el sales_manager no añade (' || left(v, 60) || ')');
  v := pg_temp.val(pmh.uid, pmh.em, format('select (public.unidad_nota_agrega(%L, %L))::text', u1, 'sin herramienta'));
  r := r || pg_temp.l(v like 'ERR42501:%', 'U4d el PM sin «unidades» no añade (' || left(v, 60) || ')');
  v := pg_temp.val(ao.uid, ao.em, format('select (public.unidad_nota_agrega(%L, %L))::text', u1, 'de otra empresa'));
  r := r || pg_temp.l(v like 'ERR42501:%', 'U4e el admin de otra empresa no añade (' || left(v, 60) || ')');
  v := pg_temp.val(x.uid, x.em, format('select (public.unidad_nota_agrega(%L, %L))::text', u1, 'de baja'));
  r := r || pg_temp.l(v like 'ERR42501:%', 'U4f una cuenta desactivada no añade (' || left(v, 60) || ')');
  v := pg_temp.val(null, null, format('select (public.unidad_nota_agrega(%L, %L))::text', u1, 'anon'), 'anon');
  r := r || pg_temp.l(v like 'ERR42501:%', 'U4g anonimo no añade (' || left(v, 60) || ')');
  v := pg_temp.val(null, null, format('select (public.unidad_nota_agrega(%L, %L))::text', u1, 'sin sesion'));
  r := r || pg_temp.l(v like 'ERR42501:%' and (select count(*) from public.unidad_notas where unidad_id = u1) = n,
                      'U4h sin sesion no añade, y ninguna de las 8 negativas cambio nada (' || left(v, 60) || ')');

  -- ============================================================ U5 texto y parcela
  v := pg_temp.val(pm.uid, pm.em, format('select (public.unidad_nota_agrega(%L, %L))::text', u1, '   '));
  r := r || pg_temp.l(v like 'ERR22023:%vac%', 'U5 una nota vacia se rechaza (' || left(v, 60) || ')');
  v := pg_temp.val(pm.uid, pm.em, format('select (public.unidad_nota_agrega(%L, %L))::text', u1, repeat('x', 4001)));
  r := r || pg_temp.l(v like 'ERR22023:%4000%', 'U5b una nota de 4001 caracteres se rechaza (' || left(v, 60) || ')');
  v := pg_temp.val(ad.uid, ad.em, 'select (public.unidad_nota_agrega(null, ''x''))::text');
  r := r || pg_temp.l(v like 'ERR42501:%', 'U5c parcela nula: 42501 (' || left(v, 60) || ')');
  v := pg_temp.val(ad.uid, ad.em, format('select (public.unidad_nota_agrega(%L, %L))::text', gen_random_uuid(), 'x'));
  v2 := pg_temp.val(ad.uid, ad.em, format(q_cuenta, gen_random_uuid()));
  r := r || pg_temp.l(v like 'ERR42501:%' and v2 like 'ERR42501:%',
                      'U5d una parcela que no existe: 42501 al añadir y al leer, también para un admin (' || left(v, 40) || ' / ' || left(v2, 40) || ')');

  -- ============================================================ U6 la tabla no se toca directo
  v := pg_temp.val(pm.uid, pm.em, 'select count(*)::text from public.unidad_notas');
  r := r || pg_temp.l(v like 'ERR42501:%', 'U6 authenticated no lee la tabla directamente (' || left(v, 60) || ')');
  v := pg_temp.val(pm.uid, pm.em, format('insert into public.unidad_notas (unidad_id, texto, autor_id) values (%L, ''x'', %L) returning id::text', u1, ag.uid));
  r := r || pg_temp.l(v like 'ERR42501:%', 'U6b authenticated no inserta directamente (ni con otro autor) (' || left(v, 60) || ')');
  v := pg_temp.val(pm.uid, pm.em, 'select count(*)::text from public.unidad_notas_retiradas');
  r := r || pg_temp.l(v like 'ERR42501:%', 'U6c authenticated no lee la traza de retiradas (' || left(v, 60) || ')');
  begin
    update public.unidad_notas set texto = 'cambiada' where id = n1;
    r := r || pg_temp.l(false, 'U6d editar una nota a mano como postgres deberia rechazarse');
  exception when others then
    r := r || pg_temp.l(sqlstate = '42501' and (select texto from public.unidad_notas where id = n1) = 'Primera nota del PM',
                        'U6d una nota no se edita ni como postgres (' || sqlstate || ')');
  end;
  begin
    delete from public.unidad_notas where id = n1;
    r := r || pg_temp.l(false, 'U6e borrar una nota a mano como postgres deberia rechazarse');
  exception when others then
    r := r || pg_temp.l(sqlstate = '42501' and exists (select 1 from public.unidad_notas where id = n1),
                        'U6e una nota no se borra a mano ni como postgres (' || sqlstate || ')');
  end;

  -- ============================================================ U7 retirar
  v := pg_temp.val(ao.uid, ao.em, format('select (public.unidad_nota_retira(%s, %L))::text', n1, 'otro'));
  r := r || pg_temp.l(v like 'ERRP0002:Esa nota no existe%' and exists (select 1 from public.unidad_notas where id = n1),
                      'U7 quien no ve la parcela recibe «no existe» y la nota sigue (' || left(v, 60) || ')');
  v := pg_temp.val(ad.uid, ad.em, format('select (public.unidad_nota_retira(%s, %L))::text', 999999999999, 'otro'));
  r := r || pg_temp.l(v like 'ERRP0002:Esa nota no existe%', 'U7a un id que no existe da el mismo «no existe» (' || left(v, 60) || ')');
  v := pg_temp.val(pm.uid, pm.em, format('select (public.unidad_nota_retira(%s, %L))::text', n1, 'porque si'));
  r := r || pg_temp.l(v like 'ERR22023:%', 'U7b un motivo fuera de la lista se rechaza (' || left(v, 60) || ')');
  v := pg_temp.val(ag.uid, ag.em, format('select (public.unidad_nota_retira(%s, %L))::text', n1, 'otro'));
  r := r || pg_temp.l(v like 'ERR42501:%' and exists (select 1 from public.unidad_notas where id = n1),
                      'U7d el agente que VE la parcela pero no es autor ni admin no la retira (' || left(v, 60) || ')');
  -- puede_retirar del PM sobre la nota del admin era false (U2): la llamada real tambien lo niega
  v := pg_temp.val(pm.uid, pm.em, format('select (public.unidad_nota_retira(%s, %L))::text', nad, 'otro'));
  r := r || pg_temp.l(v like 'ERR42501:%' and exists (select 1 from public.unidad_notas where id = nad),
                      'U7e el PM no retira la nota del admin: coincide con su puede_retirar false (' || left(v, 60) || ')');
  v := pg_temp.val(pm.uid, pm.em, format('select (public.unidad_nota_retira(%s, %L))::text', n1, 'rectificacion'));
  r := r || pg_temp.l(v like '%"ok": true%' and not exists (select 1 from public.unidad_notas where id = n1)
                      and exists (select 1 from public.unidad_notas_retiradas where nota_id = n1 and unidad_id = u1 and autor_id = pm.uid
                                    and retirada_por_id = pm.uid and motivo = 'rectificacion')
                      and not exists (select 1 from information_schema.columns where table_schema = 'public'
                                        and table_name = 'unidad_notas_retiradas' and column_name = 'texto'),
                      'U7f el autor la retira (su puede_retirar era true): el texto desaparece y queda la traza sin texto (' || left(v, 40) || ')');
  v := pg_temp.val(pm.uid, pm.em, format('select (public.unidad_nota_retira(%s, %L))::text', n1, 'otro'));
  r := r || pg_temp.l(v like 'ERRP0002:%', 'U7g retirarla otra vez: «no existe» (' || left(v, 60) || ')');
  v := pg_temp.val(ae.uid, ae.em, format('select (public.unidad_nota_retira(%s, %L))::text', nad, 'dato_sensible'));
  r := r || pg_temp.l(v like '%"ok": true%' and not exists (select 1 from public.unidad_notas where id = nad),
                      'U7h el admin de la empresa retira la nota de otro (su puede_retirar era true) (' || left(v, 40) || ')');
  begin
    delete from public.unidad_notas_retiradas where nota_id = n1;
    r := r || pg_temp.l(false, 'U7i la traza deberia ser de solo añadir');
  exception when others then
    r := r || pg_temp.l(sqlstate = '42501', 'U7i la traza es de solo añadir (' || sqlstate || ')');
  end;
  -- nota SIN autor (como las 19 'antigua' o lo que entra sin sesion): ni el PM que la lee la retira; un admin si
  update public.unidades set notas = 'ZZ-UN entra sin sesion' where id = u1;
  select max(un.id) into nant from public.unidad_notas un where un.unidad_id = u1 and un.autor_id is null;
  v := pg_temp.val(pm.uid, pm.em, format('select (public.unidad_notas_datos(%L))::text', u1));
  j := case when v like '{%' then v::jsonb end;
  v2 := pg_temp.val(pm.uid, pm.em, format('select (public.unidad_nota_retira(%s, %L))::text', nant, 'otro'));
  r := r || pg_temp.l(nant is not null
                      and (select (e->>'puede_retirar') || '|' || coalesce(e->>'autor_nombre', 'null') || '|' || (e->>'origen')
                             from jsonb_array_elements(j->'notas') e where (e->>'id')::bigint = nant) = 'false|null|campo_notas'
                      and v2 like 'ERR42501:%' and exists (select 1 from public.unidad_notas where id = nant),
                      'U7j una nota sin autor: el PM la ve con puede_retirar false y autor_nombre null, y la llamada real se lo niega (' || left(v2, 60) || ')');
  v := pg_temp.val(ad.uid, ad.em, format('select (public.unidad_nota_retira(%s, %L))::text', nant, 'otro'));
  r := r || pg_temp.l(v like '%"ok": true%' and not exists (select 1 from public.unidad_notas where id = nant),
                      'U7k un admin global si la retira (' || left(v, 40) || ')');

  -- ============================================================ U8 unidad_guarda con y sin notas (rol real, de una en una)
  n := (select count(*) from public.unidad_notas where unidad_id = u1);
  v := pg_temp.val(pm.uid, pm.em, format('select public.unidad_guarda(%L, %L::jsonb, null)::text', u1,
                                         jsonb_build_object('codigo', 'ZZ-UN-1', 'proyecto', pPn)));
  r := r || pg_temp.l(v = u1::text and (select count(*) from public.unidad_notas where unidad_id = u1) = n
                      and (select notas from public.unidades where id = u1) is null,
                      'U8 unidad_guarda sin notas no crea nota ni deja texto en la columna (' || left(v, 80) || ')');
  v := pg_temp.val(pm.uid, pm.em, format('select public.unidad_guarda(%L, %L::jsonb, null)::text', u1,
                                         jsonb_build_object('codigo', 'ZZ-UN-1', 'proyecto', pPn, 'notas', '  ZZ-UN por el editor  ')));
  r := r || pg_temp.l(v = u1::text and (select notas from public.unidades where id = u1) is null
                      and (select count(*) from public.unidad_notas where unidad_id = u1) = n + 1
                      and exists (select 1 from public.unidad_notas where unidad_id = u1 and origen = 'campo_notas'
                                    and texto = 'ZZ-UN por el editor' and autor_id = pm.uid),
                      'U8b unidad_guarda con notas (pestaña vieja) crea UNA nota «campo_notas» firmada por quien guarda (' || left(v, 80) || ')');
  v := pg_temp.val(pm.uid, pm.em, format('select public.unidad_guarda(null, %L::jsonb, null)::text',
                                         jsonb_build_object('codigo', 'ZZ-UN-ALTA', 'proyecto', pPn, 'notas', 'ZZ-UN nota del alta')));
  if v ~ '^[0-9a-f-]{36}$' then ualta := v::uuid; end if;
  r := r || pg_temp.l(ualta is not null and (select notas from public.unidades where id = ualta) is null
                      and exists (select 1 from public.unidad_notas where unidad_id = ualta and origen = 'campo_notas'
                                    and texto = 'ZZ-UN nota del alta' and autor_id = pm.uid),
                      'U8c un alta por unidad_guarda con notas crea la nota de la parcela nueva y la columna queda vacia (' || left(v, 40) || ')');
  -- U13 (Legal, #376): la fila 'alta' de unidades_log de esa parcela lleva notas null
  r := r || pg_temp.l(ualta is not null
                      and exists (select 1 from public.unidades_log l where l.unidad_id = ualta and l.via = 'alta')
                      and not exists (select 1 from public.unidades_log l where l.unidad_id = ualta
                                        and (coalesce(l.despues->'notas', 'null'::jsonb) <> 'null'::jsonb
                                             or coalesce(l.antes->'notas', 'null'::jsonb) <> 'null'::jsonb)),
                      'U13 la fila «alta» de unidades_log lleva notas null');
  -- una edicion que SI deja fila en el log (cambia el estado) y manda notas: la fila tampoco lleva el texto
  v := pg_temp.val(pm.uid, pm.em, format('select public.unidad_guarda(%L, %L::jsonb, null)::text', u2,
                                         jsonb_build_object('codigo', 'ZZ-UN-2', 'proyecto', pPn, 'estado', 'bloqueada', 'notas', 'ZZ-UN con el log')));
  r := r || pg_temp.l(v = u2::text
                      and exists (select 1 from public.unidad_notas where unidad_id = u2 and texto = 'ZZ-UN con el log')
                      and exists (select 1 from public.unidades_log l where l.unidad_id = u2 and l.via = 'ficha')
                      and not exists (select 1 from public.unidades_log l where l.unidad_id = u2
                                        and (coalesce(l.despues->'notas', 'null'::jsonb) <> 'null'::jsonb
                                             or coalesce(l.antes->'notas', 'null'::jsonb) <> 'null'::jsonb)),
                      'U13b unidad_guarda que cambia el estado y manda notas: nota creada y la fila «ficha» del log con notas null (' || left(v, 60) || ')');

  -- ============================================================ U9 unidades_importa (actualizacion y alta) con el rol real
  v := pg_temp.val(pm.uid, pm.em, format('select public.unidades_importa(%L::jsonb)::text', jsonb_build_array(
         jsonb_build_object('fila', 1, 'codigo', 'ZZ-UN-3', 'proyecto', pPn, 'notas', 'ZZ-UN por csv'),
         jsonb_build_object('fila', 2, 'codigo', 'ZZ-UN-CSV', 'proyecto', pPn, 'notas', 'ZZ-UN alta por csv'))));
  r := r || pg_temp.l(v like '%"creadas": 1%' and v like '%"actualizadas": 1%'
                      and (select notas from public.unidades where id = u3) is null
                      and exists (select 1 from public.unidad_notas where unidad_id = u3 and origen = 'campo_notas'
                                    and texto = 'ZZ-UN por csv' and autor_id = pm.uid)
                      and exists (select 1 from public.unidad_notas un join public.unidades u on u.id = un.unidad_id
                                   where u.codigo = 'ZZ-UN-CSV' and u.notas is null and un.texto = 'ZZ-UN alta por csv' and un.autor_id = pm.uid),
                      'U9 importar con notas (actualizacion y alta) crea notas firmadas y deja la columna vacia (' || left(v, 80) || ')');
  r := r || pg_temp.l(exists (select 1 from public.unidades_log l where l.unidad_id = u3 and l.via = 'csv')
                      and not exists (select 1 from public.unidades_log l where l.unidad_id = u3
                                        and (coalesce(l.despues->'notas', 'null'::jsonb) <> 'null'::jsonb
                                             or coalesce(l.antes->'notas', 'null'::jsonb) <> 'null'::jsonb)),
                      'U13c la fila «csv» de unidades_log lleva notas null');
  n := (select count(*) from public.unidad_notas where unidad_id = u3);
  v := pg_temp.val(pm.uid, pm.em, format('select public.unidades_importa(%L::jsonb)::text', jsonb_build_array(
         jsonb_build_object('fila', 1, 'codigo', 'ZZ-UN-3', 'proyecto', pPn, 'zona_masterplan', 'Z1'))));
  r := r || pg_temp.l(v like '%"actualizadas": 1%' and (select count(*) from public.unidad_notas where unidad_id = u3) = n,
                      'U9b importar sin la columna notas no crea notas (' || left(v, 80) || ')');
  -- U9c pestaña vieja / CSV exportado antes de aplicar: reenvían el texto que la parcela ya tiene en su historial
  n := (select count(*) from public.unidad_notas where unidad_id = u3);
  v := pg_temp.val(pm.uid, pm.em, format('select public.unidades_importa(%L::jsonb)::text', jsonb_build_array(
         jsonb_build_object('fila', 1, 'codigo', 'ZZ-UN-3', 'proyecto', pPn, 'notas', '  ZZ-UN por csv '))));
  r := r || pg_temp.l(v like '%"actualizadas": 1%' and (select count(*) from public.unidad_notas where unidad_id = u3) = n,
                      'U9c reimportar una nota que la parcela ya tiene no la duplica (' || left(v, 80) || ')');
  v := pg_temp.val(pm.uid, pm.em, format('select public.unidades_importa(%L::jsonb)::text', jsonb_build_array(
         jsonb_build_object('fila', 1, 'codigo', 'ZZ-UN-3', 'proyecto', pPn, 'notas', 'ZZ-UN por csv, corregida'))));
  r := r || pg_temp.l(v like '%"actualizadas": 1%' and (select count(*) from public.unidad_notas where unidad_id = u3) = n + 1,
                      'U9d un texto distinto si entra como nota nueva (' || left(v, 80) || ')');
  n := (select count(*) from public.unidad_notas where unidad_id = u1);
  v := pg_temp.val(pm.uid, pm.em, format('select public.unidad_guarda(%L, %L::jsonb, null)::text', u1,
                                         jsonb_build_object('codigo', 'ZZ-UN-1', 'proyecto', pPn, 'notas', 'ZZ-UN por el editor')));
  r := r || pg_temp.l(v = u1::text and (select count(*) from public.unidad_notas where unidad_id = u1) = n
                      and (select notas from public.unidades where id = u1) is null,
                      'U9e guardar la parcela desde una pestaña vieja con la misma nota no la duplica y deja la columna vacia (' || left(v, 60) || ')');

  -- ============================================================ U10 la columna vieja por un UPDATE directo (service_role, procesos)
  perform set_config('request.jwt.claims', json_build_object('sub', ae.uid, 'role', 'authenticated', 'email', ae.em)::text, true);
  update public.unidades set notas = '  ZZ-UN directo  ' where id = u3;
  perform set_config('request.jwt.claims', '', true);
  r := r || pg_temp.l((select notas from public.unidades where id = u3) is null
                      and exists (select 1 from public.unidad_notas where unidad_id = u3 and origen = 'campo_notas'
                                    and texto = 'ZZ-UN directo' and autor_id = ae.uid),
                      'U10 cualquier UPDATE de unidades.notas pasa al historial (autor = quien llama) y deja la columna vacia');
  begin
    update public.unidades set notas = repeat('x', 4001) where id = u3;
    r := r || pg_temp.l(false, 'U10b una nota de 4001 caracteres por unidades.notas deberia rechazarse');
  exception when others then
    r := r || pg_temp.l(sqlstate = '22023', 'U10b una nota de 4001 caracteres por la columna vieja se rechaza, no se recorta (' || sqlstate || ')');
  end;

  -- ============================================================ U11 el check aguanta aunque se salten los disparadores
  begin
    set local session_replication_role = replica;
    update public.unidades set notas = 'ZZ-UN sin disparadores' where id = u3;
    set local session_replication_role = origin;
    r := r || pg_temp.l(false, 'U11 con los disparadores apagados, escribir en unidades.notas deberia chocar con el check');
  exception when others then
    set local session_replication_role = origin;
    r := r || pg_temp.l(sqlstate = '23514' and (select notas from public.unidades where id = u3) is null,
                        'U11 check (notas is null): ni saltándose los disparadores entra texto en la columna (' || sqlstate || ')');
  end;

  -- ============================================================ U12 borrar la parcela (borrar_unidad, su llamador real)
  -- borrar_unidad está cerrada a authenticated desde 20260930100100 y dentro exige super_admin: su llamador real
  -- (tools/flujos_lawang.py, C5) es postgres CON las claims del super admin puestas. Ensayos 16-oct: con rol authenticated
  -- 42501 de permiso (09e9ffb4); sin claims, «solo un super_admin puede borrar una parcela» (d1555280).
  n := (select count(*) from public.unidad_notas where unidad_id = u2);
  perform set_config('request.jwt.claims', json_build_object('sub', sa.uid, 'role', 'authenticated', 'email', sa.em)::text, true);
  begin
    perform public.borrar_unidad(u2);
    v := 'ok';
  exception when others then
    v := 'ERR' || sqlstate || ':' || sqlerrm;
  end;
  perform set_config('request.jwt.claims', '', true);
  r := r || pg_temp.l(n > 0 and v not like 'ERR%' and not exists (select 1 from public.unidades where id = u2)
                      and not exists (select 1 from public.unidad_notas where unidad_id = u2)
                      and (select count(*) from public.unidad_notas_retiradas where unidad_id = u2 and motivo = 'ficha_borrada'
                             and retirada_por_id = sa.uid) = n,
                      'U12 borrar_unidad (postgres con claims de super_admin) borra sus ' || n || ' nota(s) y deja traza «ficha_borrada» con quien la borró (' || left(v, 60) || ')');

  -- ============================================================ U15/U16 cliente_notas_datos: claves de antes + autor_nombre + puede_retirar
  v := pg_temp.val(ag.uid, ag.em, format('select (public.cliente_nota_agrega(%L, %L))->>''id''', c1, 'ZZ-UN nota del agente'));
  if v ~ '^\d+$' then cn_ag := v::bigint; end if;
  v := pg_temp.val(ad.uid, ad.em, format('select (public.cliente_nota_agrega(%L, %L))->>''id''', c1, 'ZZ-UN nota del admin'));
  if v ~ '^\d+$' then cn_ad := v::bigint; end if;
  v := pg_temp.val(ad.uid, ad.em, format('select (public.cliente_nota_agrega(%L, %L))->>''id''', c1, 'ZZ-UN otra del admin'));
  if v ~ '^\d+$' then cn_ad2 := v::bigint; end if;
  v := pg_temp.val(ag.uid, ag.em, format('select (public.cliente_notas_datos(%L))::text', c1));
  j := case when v like '{%' then v::jsonb end;
  r := r || pg_temp.l(cn_ag is not null and cn_ad is not null and cn_ad2 is not null
                      and (select bool_and(e ?& array['id', 'texto', 'origen', 'creado_en', 'autor_id', 'autor_email', 'autor_nombre', 'puede_retirar'])
                             from jsonb_array_elements(j->'notas') e)
                      and (select e->>'autor_email' from jsonb_array_elements(j->'notas') e where (e->>'id')::bigint = cn_ag) = ag.em,
                      'U15 cliente_notas_datos conserva sus claves (autor_email incluida: la pantalla vieja sigue) y añade autor_nombre y puede_retirar');
  r := r || pg_temp.l((select string_agg(e->>'id' || ':' || (e->>'puede_retirar') || ':' || coalesce(e->>'autor_nombre', 'null'), ',' order by (e->>'id')::bigint)
                         from jsonb_array_elements(j->'notas') e)
                      = cn_ag || ':true:ZZ-UN Agente,' || cn_ad || ':false:ZZ-UN Admin,' || cn_ad2 || ':false:ZZ-UN Admin',
                      'U16 el agente dueño de la ficha: su nota true, las del admin false, con nombre (' || left(coalesce(v, ''), 120) || ')');
  v := pg_temp.val(ag.uid, ag.em, format('select (public.cliente_nota_retira(%s, %L))::text', cn_ad, 'otro'));
  r := r || pg_temp.l(v like 'ERR42501:%' and exists (select 1 from public.cliente_notas where id = cn_ad),
                      'U16b la llamada real coincide: el agente NO retira la nota del admin (' || left(v, 60) || ')');
  v := pg_temp.val(ae.uid, ae.em, format('select (public.cliente_notas_datos(%L))::text', c1));
  j := case when v like '{%' then v::jsonb end;
  v2 := (select string_agg(e->>'puede_retirar', ',') from jsonb_array_elements(j->'notas') e);
  r := r || pg_temp.l(jsonb_array_length(j->'notas') = 3 and v2 = 'true,true,true',
                      'U16c el admin de la empresa del dueño lee las 3 y puede retirar todas (' || coalesce(v2, left(coalesce(v, ''), 80)) || ')');
  v := pg_temp.val(ae.uid, ae.em, format('select (public.cliente_nota_retira(%s, %L))::text', cn_ad, 'otro'));
  r := r || pg_temp.l(v like '%"ok": true%' and not exists (select 1 from public.cliente_notas where id = cn_ad),
                      'U16d la llamada real coincide: el admin de empresa SI retira la nota del admin global (' || left(v, 40) || ')');
  v := pg_temp.val(ad.uid, ad.em, format('select (public.cliente_notas_datos(%L))::text', c1));
  j := case when v like '{%' then v::jsonb end;
  r := r || pg_temp.l(jsonb_array_length(j->'notas') = 2
                      and (select bool_and((e->>'puede_retirar')::boolean) from jsonb_array_elements(j->'notas') e),
                      'U16e el admin global puede retirar todas (' || left(coalesce(v, ''), 60) || ')');
  v := pg_temp.val(ag.uid, ag.em, format('select (public.cliente_nota_retira(%s, %L))::text', cn_ag, 'rectificacion'));
  r := r || pg_temp.l(v like '%"ok": true%', 'U16f la llamada real coincide: el autor retira la suya (' || left(v, 40) || ')');

  -- ============================================================ U17 lo nuevo nace cerrado (llamador con nombre)
  r := r || pg_temp.l(not exists (
         select 1 from (values ('public._unidad_ficha_ve(uuid)'), ('public._unidad_notas_editor(uuid)'), ('public._unidad_notas_admin(uuid)'),
                               ('public._cliente_notas_admin(uuid)'), ('public._unidades_notas_a_historial()'), ('public._unidades_notas_al_borrar()'))
                         f(f)
         cross join pg_roles ro where ro.rolname in ('anon', 'authenticated', 'service_role')
           and has_function_privilege(ro.oid, f.f::regprocedure, 'execute'))
      and not exists (
         select 1 from (values ('public.unidad_notas_datos(uuid)'), ('public.unidad_nota_agrega(uuid,text)'), ('public.unidad_nota_retira(bigint,text)')) f(f)
         cross join pg_roles ro where ro.rolname in ('anon', 'service_role')
           and has_function_privilege(ro.oid, f.f::regprocedure, 'execute'))
      and not exists (select 1 from pg_roles ro where ro.rolname in ('anon', 'authenticated', 'service_role')
                        and (has_table_privilege(ro.oid, 'public.unidad_notas', 'select, insert, update, delete')
                             or has_table_privilege(ro.oid, 'public.unidad_notas_retiradas', 'select, insert, update, delete'))),
      'U17 helpers y disparadores sin execute para anon/authenticated/service_role; las 3 RPC solo authenticated; tablas cerradas');
  r := r || pg_temp.l((select pg_get_userbyid(p.proowner) from pg_proc p where p.oid = 'public.unidad_notas_datos(uuid)'::regprocedure) = 'lw_lector'
                      and (select pg_get_userbyid(p.proowner) from pg_proc p where p.oid = 'public.cliente_notas_datos(uuid)'::regprocedure) = 'lw_lector'
                      and (select pg_get_userbyid(p.proowner) from pg_proc p where p.oid = 'public._unidad_notas_editor(uuid)'::regprocedure) = 'postgres',
                      'U17b las lecturas siguen con dueño lw_lector y el permiso de editor con dueño postgres');
  -- secuencias: el ACL por defecto de postgres da rwU a authenticated sobre las nuevas; y lw_lector sin CREATE en public
  -- tras los alter owner (Seguridad, consulta de deploy 15-oct)
  r := r || pg_temp.l(not exists (
         select 1 from (values ('public.unidad_notas_id_seq'), ('public.unidad_notas_retiradas_id_seq')) s(s)
         cross join pg_roles ro where ro.rolname in ('anon', 'authenticated', 'service_role')
           and has_sequence_privilege(ro.oid, s.s, 'usage, select, update'))
      and not has_schema_privilege('lw_lector', 'public', 'create'),
      'U17c secuencias cerradas para anon/authenticated/service_role y lw_lector sin CREATE en public');

  -- ============================================================ U14 tope (al final: deja a los autores sin cupo)
  n := (select count(*) from public.unidades where codigo like 'ZZ-UN-T%');
  v := pg_temp.val(ae.uid, ae.em, format('select public.unidades_importa(%L::jsonb)::text',
         (select jsonb_agg(jsonb_build_object('fila', g, 'codigo', 'ZZ-UN-T' || lpad(g::text, 2, '0'), 'proyecto', pPn, 'notas', 'ZZ-UN tope csv ' || g))
            from generate_series(1, 31) g)));
  r := r || pg_temp.l(v like 'ERR54000:%' and n = 0
                      and not exists (select 1 from public.unidades where codigo like 'ZZ-UN-T%')
                      and not exists (select 1 from public.unidad_notas where texto like 'ZZ-UN tope csv %'),
                      'U14 una importacion (pestaña vieja) de 31 filas con notas aborta ENTERA: 0 parcelas y 0 notas (' || left(v, 60) || ')');
  insert into public.unidad_notas (unidad_id, texto, autor_id, origen)
    select u1, 'ZZ-UN tope ' || g, ad.uid, 'nota' from generate_series(1, 30) g;
  v := pg_temp.val(ad.uid, ad.em, format('select (public.unidad_nota_agrega(%L, %L))::text', u1, 'ZZ-UN la 31'));
  v2 := pg_temp.val(ad.uid, ad.em, format('select public.unidad_guarda(%L, %L::jsonb, null)::text', u1,
                                          jsonb_build_object('codigo', 'ZZ-UN-1', 'proyecto', pPn, 'notas', 'ZZ-UN la 31 por el editor')));
  r := r || pg_temp.l(v like 'ERR54000:%' and v2 like 'ERR54000:%' and not exists (select 1 from public.unidad_notas where texto like 'ZZ-UN la 31%'),
                      'U14b pasado el tope de 30 en 10 minutos, ni unidad_nota_agrega ni unidad_guarda con notas escriben (' || left(v, 40) || ' / ' || left(v2, 40) || ')');

  -- ============================================================ U13d (Legal, #376) tambien lo que se escribe al confirmar
  -- trg_unidad_estado_al_historial es diferido: escribe su fila de unidades_log al confirmar, y las U13 de arriba no la ven.
  -- Se dispara ahora (AL FINAL: en modo inmediato un alta con notas no podria crear su nota antes de existir la parcela).
  begin
    set constraints all immediate;
    r := r || pg_temp.l(exists (select 1 from public.unidades_log l where l.unidad_id = u1 and l.via = 'sql directo')
                        and not exists (select 1 from public.unidades_log l
                                         where (l.unidad_id in (select u.id from public.unidades u where u.codigo like 'ZZ-UN-%') or l.unidad_id = u2)
                                           and (coalesce(l.despues->'notas', 'null'::jsonb) <> 'null'::jsonb
                                                or coalesce(l.antes->'notas', 'null'::jsonb) <> 'null'::jsonb)),
                        'U13d disparados los diferidos, ninguna fila de unidades_log de las parcelas de la prueba lleva notas');
  exception when others then
    r := r || pg_temp.l(false, 'U13d al disparar los diferidos: ' || sqlstate || ' ' || left(sqlerrm, 200));
  end;

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
