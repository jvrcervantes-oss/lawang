-- Prueba de S5 «plantillas de contrato por empresa · generador» (7-oct-2026). Se pega DESPUES de las migraciones 20261009000000 y 20261009000100 en la MISMA peticion
-- (ensayo sin rastro: el bloque acaba en raise y todo se deshace). Mismas personas por JWT simulado que f2_plantillas_s2.sql.
-- NO inserta contratos (nextval no hace rollback). Debe terminar con «FALLOS=0».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); los vinculos de prueba se deshacen
create temp table _s5p (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select case when coalesce(c, false) then 'OK    ' else 'FALLO ' end || t || E'\n'
$f$;
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text, p_role text default 'authenticated') returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', case when p_role = 'anon' then json_build_object('role', 'anon')::text
                      else json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text end, true);
  execute format('set local role %I', p_role);
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 90); end;
  execute 'reset role';
  return t;
end $f$;
create or replace function pg_temp.err(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then substr(t, 4, 5) end $f$;

insert into _s5p select 'jv', user_id, email from public.usuarios where email = 'jvr.cervantes@gmail.com';
insert into _s5p
  select (array['ae_L', 'se_L', 'ae_S', 'se_S', 'ctl_L', 'ctl_G'])[rn], user_id, email
    from (select user_id, email, row_number() over (order by email) rn
            from (select user_id, email from public.usuarios where activo and ambito = 'global' and rol = 'agente' order by email limit 6) q) z;

do $todo$
declare
  r text := ''; v text; n bigint; u text; k int;
  ae_L _s5p; se_L _s5p; ae_S _s5p; se_S _s5p; ctl_L _s5p; ctl_G _s5p; jv _s5p;
  pL uuid; pS uuid; cL uuid; cS uuid; cLnb uuid; vL uuid; vS uuid; vLother uuid; j jsonb; fallos int;
  n_vinc int; n_cand int; src text;
begin
  select * into jv from _s5p where et = 'jv';
  select * into ae_L from _s5p where et = 'ae_L'; select * into se_L from _s5p where et = 'se_L'; select * into ae_S from _s5p where et = 'ae_S';
  select * into se_S from _s5p where et = 'se_S'; select * into ctl_L from _s5p where et = 'ctl_L'; select * into ctl_G from _s5p where et = 'ctl_G';
  select id into pL from public.proyectos where empresa = 'lawang' order by id limit 1;
  select id into pS from public.proyectos where empresa = 'sandal_woods' order by id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{ajustes,facturas,gastos,usuarios}', tipos_contrato = '{}' where user_id = ae_L.uid;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{contratos}', tipos_contrato = '{}' where user_id = se_L.uid;
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{ajustes,facturas,gastos,usuarios}', tipos_contrato = '{}' where user_id = ae_S.uid;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{contratos}', tipos_contrato = '{}' where user_id = se_S.uid;
  update public.usuarios set rol = 'agente', ambito = 'global', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ctl_L.uid;
  update public.usuarios set rol = 'agente', ambito = 'global', empresas = '{}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ctl_G.uid;

  -- ============================================================ A. exposicion: solo tres RPC con llamador
  select count(*) into n from unnest(array['plantilla_contrato_cuerpo(text,uuid,text)', 'plantilla_contrato_cuerpo_de_contrato(uuid,text)', 'plantilla_contrato_fija(uuid,uuid)']) x
   where has_function_privilege('authenticated', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 3, 'A1 authenticated ejecuta las 3 RPC del generador (' || n || ')');
  select count(*) into n from unnest(array['plantilla_contrato_guarda_borrador(text,text,text,text)', 'plantilla_contrato_activa(uuid,text,boolean)', 'plantilla_contrato_descarta_borrador(uuid)',
        'plantilla_contrato_cuerpo_version(uuid,text)', 'plantilla_contrato_version_de_contrato(uuid)', 'plantilla_contrato_versiones_lista(text,text)']) x
   where has_function_privilege('authenticated', 'public.' || x, 'execute') or has_function_privilege('anon', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 0, 'A2 las otras 6 siguen SIN EXECUTE para authenticated ni anon (' || n || ')');
  r := r || pg_temp.l(has_function_privilege('lw_lector', 'public.plantilla_contrato_cuerpo_version(uuid,text)', 'execute')
                      and not has_function_privilege('authenticated', 'public.plantilla_contrato_cuerpo_version(uuid,text)', 'execute'),
                      'A3 plantilla_contrato_cuerpo_version: EXECUTE solo para su duenno lw_lector');
  select count(*) into n from unnest(array['plantilla_contrato_cuerpo(text,uuid,text)', 'plantilla_contrato_cuerpo_de_contrato(uuid,text)', 'plantilla_contrato_fija(uuid,uuid)']) x
   where has_function_privilege('anon', 'public.' || x, 'execute') or has_function_privilege('service_role', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 0, 'A4 anon y service_role no ejecutan ninguna de las 3');
  select count(*) into n from pg_proc where pronamespace = 'public'::regnamespace and proname in ('plantilla_contrato_cuerpo_de_contrato', '_plantilla_slug_de_tipo', 'plantilla_contrato_fija', 'plantilla_contrato_activa', 'plantilla_contrato_descarta_borrador', 'plantilla_contrato_cuerpo')
     and not (prosecdef and proconfig @> array['search_path=""']);
  r := r || pg_temp.l(n = 0, 'A5 las 6 funciones tocadas: SECURITY DEFINER con search_path vacio');
  r := r || pg_temp.l((select pg_get_userbyid(proowner) from pg_proc where proname = 'plantilla_contrato_cuerpo_de_contrato') = 'lw_lector', 'A6 la lectura nueva es de lw_lector (la RLS filtra como el que llama)');

  -- ============================================================ B. interbloqueo: en activa y descarta el candado asesor va ANTES del for update
  select count(*) into n from pg_proc where proname in ('plantilla_contrato_activa', 'plantilla_contrato_descarta_borrador', 'plantilla_contrato_guarda_borrador')
     and position('pg_advisory_xact_lock' in prosrc) > 0 and position('pg_advisory_xact_lock' in prosrc) < position('for update' in prosrc);
  r := r || pg_temp.l(n = 3, 'B1 las 3 escrituras toman el candado asesor antes del for update (mismo orden, sin interbloqueo posible) (' || n || ')');
  r := r || pg_temp.l((select position('_plantilla_motivo_bloqueo' in prosrc) > 0 from pg_proc where proname = 'plantilla_contrato_activa'), 'B2 activa conserva el recheck F1 de 20261008990100');

  -- ============================================================ C. vinculacion de los borradores
  select count(*) into n_vinc from public.contrato_plantilla_version where fijado_por = 'S5 carga inicial';
  select count(*) into n_cand from public.contratos c join public.proyectos p on p.id = c.proyecto_id
   where p.empresa is not null and not c.bloqueado and not exists (select 1 from public.contrato_firmas f where f.contrato_id = c.id);
  r := r || pg_temp.l(n_vinc = n_cand and n_vinc > 0, format('C1 vinculados = candidatos (editables, con empresa, sin firmas): %s = %s', n_vinc, n_cand));
  select count(*) into n from public.contrato_plantilla_version l join public.contratos c on c.id = l.contrato_id where c.bloqueado or exists (select 1 from public.contrato_firmas f where f.contrato_id = c.id);
  r := r || pg_temp.l(n = 0, 'C2 ningun bloqueado ni con filas de firma esta vinculado (' || n || ')');
  select count(*) into n from public.contrato_plantilla_version l join public.contratos c on c.id = l.contrato_id join public.proyectos p on p.id = c.proyecto_id join public.plantilla_contrato_versiones v on v.id = l.version_id
   where v.empresa is distinct from p.empresa or v.slug is distinct from public._plantilla_slug_de_tipo(c.tipo) or v.origen <> 'semilla' or v.version <> 1;
  r := r || pg_temp.l(n = 0, 'C3 cada vinculo es la semilla v1 de SU empresa y de SU plantilla (' || n || ' mal)');
  select count(*) into n from public.contratos c where c.proyecto_id is null or not exists (select 1 from public.proyectos p where p.id = c.proyecto_id and p.empresa is not null);
  select count(*) into k from public.contrato_plantilla_version l join public.contratos c on c.id = l.contrato_id where c.proyecto_id is null;
  r := r || pg_temp.l(k = 0, format('C4 los %s sin proyecto/empresa no se vinculan (%s vinculados)', n, k));
  select count(*) into n from public.contratos where tipo is not null and public._plantilla_slug_de_tipo(tipo) is null;
  r := r || pg_temp.l(n = 0, 'C5 los 17 tipos de contrato existentes tienen plantilla en _plantilla_slug_de_tipo (' || n || ' sin)');

  select c.id into cL from public.contrato_plantilla_version l join public.contratos c on c.id = l.contrato_id join public.proyectos p on p.id = c.proyecto_id where p.empresa = 'lawang' and c.tipo = 'carta_reserva' order by c.id limit 1;
  select c.id into cS from public.contrato_plantilla_version l join public.contratos c on c.id = l.contrato_id join public.proyectos p on p.id = c.proyecto_id where p.empresa = 'sandal_woods' and c.tipo = 'carta_reserva' order by c.id limit 1;
  select c.id into cLnb from public.contratos c join public.proyectos p on p.id = c.proyecto_id where p.empresa = 'lawang' and c.bloqueado order by c.id limit 1;
  r := r || pg_temp.l(cL is not null and cS is not null and cLnb is not null, 'C6 datos de partida: contrato vinculado de cada empresa y un bloqueado');
  select v.id into vL from public.plantilla_contrato_versiones v where v.empresa = 'lawang' and v.slug = 'carta_reserva' and v.version = 1;
  select v.id into vS from public.plantilla_contrato_versiones v where v.empresa = 'sandal_woods' and v.slug = 'carta_reserva' and v.version = 1;
  select v.id into vLother from public.plantilla_contrato_versiones v where v.empresa = 'lawang' and v.slug = 'adenda' and v.version = 1;

  -- ============================================================ D. lectura para reabrir (cuerpo_de_contrato)
  v := pg_temp.val(se_L.uid, se_L.em, format('select (public.plantilla_contrato_cuerpo_de_contrato(%L)->>''version_id'')', cL));
  r := r || pg_temp.l(v = vL::text, 'D1 el super de Lawang lee el texto fijado de su contrato (version = semilla de Lawang)');
  v := pg_temp.val(se_L.uid, se_L.em, format('select length(public.plantilla_contrato_cuerpo_de_contrato(%L)->>''cuerpo_html'')', cL));
  r := r || pg_temp.l(v::int = (select bytes from public.plantilla_contrato_versiones where id = vL) or v::int > 1000, 'D2 devuelve el cuerpo (' || v || ' caracteres)');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_cuerpo_de_contrato(%L, %L)::text', cL, (select hash from public.plantilla_contrato_versiones where id = vL)));
  r := r || pg_temp.l(v like '%sin_cambios%' and v not like '%cuerpo_html%', 'D3 con el etag al dia no reenvia el cuerpo');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_cuerpo_de_contrato(%L)::text', cS));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'D4 un admin de Lawang NO lee el texto de un contrato de Sandal Woods (' || v || ')');
  v := pg_temp.val(se_S.uid, se_S.em, format('select public.plantilla_contrato_cuerpo_de_contrato(%L)::text', cL));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'D5 y el de Sandal Woods no lee el de Lawang (' || v || ')');
  v := pg_temp.val(null, null, format('select public.plantilla_contrato_cuerpo_de_contrato(%L)::text', cL), 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'D6 anon no ejecuta (' || v || ')');
  v := pg_temp.val(gen_random_uuid(), 'portal.ajeno@example.com', format('select public.plantilla_contrato_cuerpo_de_contrato(%L)::text', cL));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'D7 un cliente del portal (sin ficha de agente) no lee (' || v || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select coalesce(public.plantilla_contrato_cuerpo_de_contrato(%L)::text, ''nulo'')', cLnb));
  r := r || pg_temp.l(v = 'nulo', 'D8 un contrato bloqueado sin vinculo devuelve null: sigue con fichero/PDF (' || left(v, 40) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select public.plantilla_contrato_cuerpo_de_contrato(%L)::text', cL));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' or v like '%version_id%', 'D9 un agente sin permiso sobre el contrato: o lo ve (RLS) o 42501 — nunca otro error (' || left(v, 40) || ')');

  -- ============================================================ E. lectura para redactar (cuerpo): activa, y si no hay, la semilla v1
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_cuerpo(''carta_reserva'', %L)->>''origen''', pL));
  r := r || pg_temp.l(v = 'semilla', 'E1 sin version activa, el super de Lawang recibe la semilla v1 (' || v || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select public.plantilla_contrato_cuerpo(''carta_reserva'', %L)->>''origen''', pL));
  r := r || pg_temp.l(v = 'semilla', 'E2 un agente que no es admin recibe lo mismo (las semillas son los ficheros publicos) (' || v || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_cuerpo(''carta_reserva'', %L)->>''empresa''', pL));
  r := r || pg_temp.l(v = 'lawang', 'E3 es el texto de SU empresa');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_cuerpo(''carta_reserva'', %L)::text', pS));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'E4 un super de Lawang pidiendo el texto con un proyecto de Sandal Woods: 42501 (' || v || ')');
  v := pg_temp.val(se_S.uid, se_S.em, 'select public.plantilla_contrato_cuerpo(''carta_reserva'')->>''empresa''');
  r := r || pg_temp.l(v = 'sandal_woods', 'E5 sin proyecto, la empresa se deduce de la unica del que llama (' || v || ')');
  v := pg_temp.val(jv.uid, jv.em, 'select coalesce(public.plantilla_contrato_cuerpo(''carta_reserva'')::text, ''nulo'')');
  r := r || pg_temp.l(v = 'nulo' or v like '%empresa%', 'E6 un global con las dos empresas y sin proyecto: no adivina (' || left(v, 30) || ')');
  v := pg_temp.val(se_L.uid, se_L.em, 'select coalesce(public.plantilla_contrato_cuerpo(''no_existe'', null)::text, ''nulo'')');
  r := r || pg_temp.l(v = 'nulo', 'E7 un slug que no existe devuelve null (el cliente cae al fichero)');
  v := pg_temp.val(null, null, 'select public.plantilla_contrato_cuerpo(''carta_reserva'')::text', 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'E8 anon no ejecuta (' || v || ')');
  select count(*) into n from public.plantilla_contrato_versiones where estado <> 'borrador';
  r := r || pg_temp.l(n = 0, 'E9 ninguna version activada ni retirada en produccion (' || n || '): nada cambia hasta que S7 + owner activen');

  -- ============================================================ F. fijar
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cL, vL));
  r := r || pg_temp.l(v is null or v = '', 'F1 volver a fijar la misma semilla es idempotente (' || coalesce(v, 'ok') || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cL, vLother));
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and v like '%otra plantilla%', 'F2 la version de OTRA plantilla (adenda) no se fija a una carta de reserva (' || v || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cL, vS));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'F3 la version de OTRA empresa se rechaza (' || v || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cLnb, vL));
  r := r || pg_temp.l(pg_temp.err(v) in ('55000', '22023', '42501'), 'F4 un contrato bloqueado no cambia de version (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cL, vL));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'F5 un admin sin la herramienta contratos no fija (' || v || ')');
  v := pg_temp.val(se_S.uid, se_S.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cL, vL));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'F6 el super de Sandal Woods no fija sobre un contrato de Lawang (' || v || ')');
  v := pg_temp.val(null, null, format('select public.plantilla_contrato_fija(%L, %L)::text', cL, vL), 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'F7 anon no ejecuta (' || v || ')');
  -- con una version activa de la empresa, la semilla deja de poder fijarse
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);
  begin
    -- activa fabricada solo para el ensayo (como postgres: el trigger exige hash=cuerpo; confirmacion y activable van en el INSERT directo, que el trigger ins rechaza, asi que se pasa por borrador->activa)
    insert into public.plantilla_contrato_versiones (empresa, slug, version, origen, idioma_set, hash, bytes, activable, autor, motivo)
      select 'lawang', 'carta_reserva', 2, 'empresa', '{es}', public._plantilla_hash('<p>v2 de prueba</p>'), octet_length('<p>v2 de prueba</p>'), true, 'prueba', 'ensayo' returning id into vLother;
    insert into public.plantilla_contrato_cuerpos values (vLother, '<p>v2 de prueba</p>');
    update public.plantilla_contrato_versiones set estado = 'activa', activado_por = 'prueba', activado_en = now(), confirmacion_nombre = 'prueba', confirmacion_texto = 'prueba' where id = vLother;
    v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cL, vL));
    r := r || pg_temp.l(pg_temp.err(v) = '22023', 'F8 con una version activa en la empresa, la semilla v1 ya no se fija (' || v || ')');
    v := pg_temp.val(se_L.uid, se_L.em, 'select public.plantilla_contrato_cuerpo(''carta_reserva'', ' || quote_literal(pL) || ')->>''origen''');
    r := r || pg_temp.l(v = 'empresa', 'F9 y cuerpo() sirve la activa en vez de la semilla (' || v || ')');
    v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_cuerpo_de_contrato(%L)->>''origen''', cL));
    r := r || pg_temp.l(v = 'semilla', 'F10 pero el contrato ya fijado sigue leyendo SU semilla (cambiar de version es un acto explicito) (' || v || ')');
    v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cL, vLother));
    r := r || pg_temp.l(v is null or v = '', 'F11 y fijarle la activa es el acto explicito (' || coalesce(v, 'ok') || ')');
    v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_cuerpo_de_contrato(%L)->>''origen''', cL));
    r := r || pg_temp.l(v = 'empresa', 'F12 tras fijarla, el contrato lee la nueva (' || v || ')');
  end;

  -- ============================================================ G. contratos intactos
  select count(*) into n from pg_trigger where tgrelid = 'public.contratos'::regclass and not tgisinternal and tgname ilike '%plantilla%';
  r := r || pg_temp.l(n = 0, 'G1 ningun trigger de plantillas en contratos (' || n || ')');
  select count(*) into n from information_schema.columns where table_name = 'contratos' and column_name ilike '%plantilla%';
  r := r || pg_temp.l(n = 0, 'G2 ninguna columna de plantillas en contratos (' || n || ')');

  fallos := (select count(*) from regexp_matches(r, 'FALLO', 'g'));
  raise exception E'INFORME S5\n%FALLOS=%', r, fallos;
end $todo$;
