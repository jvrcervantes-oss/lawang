-- Prueba de los arreglos de la revision de codigo E7-E9 (10-oct-2026). Se pega DESPUES de la migracion 20261010050000 en la MISMA peticion
-- (ensayo sin rastro: el bloque acaba en raise y todo se deshace, migracion incluida si se pega junta). Debe terminar con «FALLOS=0».
-- Incluye la NEGATIVA: un agente de Lawang fija una revision activa de Sandal Woods (y su semilla v1) a un contrato de Lawang, para los 17 tipos de contrato.
-- NO activa nada en produccion; el contrato de partida vuelve a su tipo al deshacer.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback)
create temp table _t10 (et text primary key, uid uuid, em text);
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
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  return t;
end $f$;
create or replace function pg_temp.err(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then substr(t, 4, 5) end $f$;
create or replace function pg_temp.pg(p_sql text) returns text language plpgsql as $f$
declare t text;
begin
  begin execute p_sql into t; exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  return t;
end $f$;
create or replace function pg_temp.run(p_sql text) returns text language plpgsql as $f$
begin
  begin execute p_sql; exception when others then return 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  return 'OK';
end $f$;

create or replace function pg_temp.u(t text) returns uuid language sql immutable as $f$ select case when t is null or t like 'ERR%' or t = '' then null else t::uuid end $f$;

-- crea una version de prueba: nace borrador y pasa a activa/retirada/archivada como lo hacen las RPC (update directo como postgres)
create or replace function pg_temp.mk(p_emp text, p_slug text, p_ver int, p_var text, p_fin text, p_h text) returns text language plpgsql as $f$
declare v_id uuid; v_txt text := 'TEXTO-' || upper(p_fin) || '-' || p_ver;
begin
  begin
    insert into public.plantilla_contrato_versiones (empresa, slug, version, estado, origen, idioma_set, hash, bytes, activable, autor, variante, variante_nombre)
      values (p_emp, p_slug, p_ver, 'borrador', 'empresa', '{es}', public._plantilla_hash(v_txt), octet_length(v_txt), true, 'x', p_var, case when p_var = 'estandar' then null else 'zzz' end) returning id into v_id;
    insert into public.plantilla_contrato_cuerpos (version_id, cuerpo_html) values (v_id, v_txt);
    if p_fin in ('activa', 'retirada', 'archivada') then
      update public.plantilla_contrato_versiones set estado = 'activa', activado_por = 'x', activado_en = now(), confirmacion_nombre = 'x', confirmacion_texto = 'x' where id = v_id;
    end if;
    if p_fin = 'retirada' then update public.plantilla_contrato_versiones set estado = 'retirada', retirada_por = 'x', retirada_en = now() where id = v_id; end if;
    if p_fin = 'archivada' then update public.plantilla_contrato_versiones set estado = 'archivada', archivada_por = 'x', archivada_en = now() where id = v_id; end if;
    return v_id::text;
  exception when others then return 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
end $f$;

insert into _t10 select 'jv', user_id, email from public.usuarios where email = 'jvr.cervantes@gmail.com';
insert into _t10
  select (array['ae_L', 'ag_L'])[rn], user_id, email
    from (select user_id, email, row_number() over (order by email) rn
            from (select user_id, email from public.usuarios where activo and ambito = 'global' and rol = 'agente' order by email limit 2) q) z;

do $todo$
declare
  r text := ''; v text; n bigint; fallos int; tp text; sl text; ct uuid; idS uuid; idL uuid; idSem uuid; idR uuid; idA uuid; idN uuid; ctx uuid; n0 bigint; i int := 0; fns text[]; def text;
  jv _t10; ae_L _t10; ag_L _t10; neg int := 0; pos int := 0; sem int := 0; neg2 int := 0; bs text; bd text;
  tipos text[] := array['reserva_parcela', 'construccion', 'contrato_general', 'commercial_offer', 'carta_reserva', 'carta_reserva_ampliada', 'acuerdo_comercial', 'protocolo_operativo',
    'ppjb_bonian', 'ppjb_bonian_c2', 'hak_sewa_notario', 'carta_reserva_hak_sewa', 'poa', 'cc00014_timon', 'carta_reserva_pma', 'adenda', 'carta_reserva_investor_deck'];
begin
  select * into jv from _t10 where et = 'jv'; select * into ae_L from _t10 where et = 'ae_L'; select * into ag_L from _t10 where et = 'ag_L';
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ae_L.uid;
  update public.usuarios set rol = 'agente', ambito = 'global', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{contratos}', tipos_contrato = '{}' where user_id = ag_L.uid;
  select c.id into ct from public.contratos c join public.proyectos pr on pr.id = c.proyecto_id
   where pr.empresa = 'lawang' and public._plantilla_slug_de_tipo(c.tipo) = 'commercial_offer' and not coalesce(c.bloqueado, false)
     and not exists (select 1 from public.contrato_firmas f where f.contrato_id = c.id) limit 1;
  r := r || pg_temp.l(ct is not null, 'Z0 hay un contrato libre de Lawang para probar la fijacion');
  

  -- ================== 1. fijar una revision de OTRA empresa: los 17 tipos
  foreach tp in array tipos loop
    i := i + 1;
    sl := public._plantilla_slug_de_tipo(tp);
    ctx := ct;
    if tp = 'construccion' then
      select c.id into ctx from public.contratos c join public.proyectos pr on pr.id = c.proyecto_id where pr.empresa = 'lawang' and c.tipo = 'construccion' and not coalesce(c.bloqueado, false)
         and not exists (select 1 from public.contrato_firmas f where f.contrato_id = c.id) order by c.id limit 1;
      v := 'OK';
    else
      v := pg_temp.run(format('update public.contratos set tipo = %L where id = %L', tp, ct));
    end if;
    if v <> 'OK' then r := r || pg_temp.l(false, 'T' || i || ' no se pudo poner el tipo ' || tp || ' al contrato de prueba (' || v || ')'); continue; end if;
    select coalesce(max(x.version), 0) + 1 into n from public.plantilla_contrato_versiones x where x.empresa = 'sandal_woods' and x.slug = sl;
    v := pg_temp.mk('sandal_woods', sl, n::int, 'rev_9', 'activa', 'b'); idS := pg_temp.u(v);   -- rev_9: no choca con un borrador de la revision estandar que ya tenga esa empresa
    select coalesce(max(x.version), 0) + 1 into n from public.plantilla_contrato_versiones x where x.empresa = 'lawang' and x.slug = sl;
    select x.id into idL from public.plantilla_contrato_versiones x where x.empresa = 'lawang' and x.slug = sl and x.variante = 'estandar' and x.estado = 'activa' and x.borrada_en is null;
    if idL is null then v := pg_temp.mk('lawang', sl, n::int, 'estandar', 'activa', 'c'); idL := pg_temp.u(v); end if;
    if idS is null or idL is null then r := r || pg_temp.l(false, 'T' || i || ' no se pudieron crear las activas de prueba de ' || sl || ' (' || v || ')'); continue; end if;
    v := pg_temp.val(ag_L.uid, ag_L.em, format('select public.plantilla_contrato_fija(%L, %L)', ctx, idS));
    if pg_temp.err(v) = '42501' then neg := neg + 1; else r := r || pg_temp.l(false, 'N1 ' || tp || ': agente de Lawang fija la activa de Sandal Woods: debia ser 42501 (' || left(v, 110) || ')'); end if;
    v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, %L)', ctx, idS));
    if pg_temp.err(v) = '42501' and v like '%no es de la empresa%' then neg2 := neg2 + 1; else r := r || pg_temp.l(false, 'N2 ' || tp || ': global fija la activa de Sandal Woods: debia ser 42501 de empresa (' || left(v, 110) || ')'); end if;
    select x.id into idSem from public.plantilla_contrato_versiones x where x.empresa = 'sandal_woods' and x.slug = sl and x.origen = 'semilla' and x.version = 1;
    if idSem is not null then
      v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, %L)', ctx, idSem));
      if pg_temp.err(v) = '42501' then sem := sem + 1; else r := r || pg_temp.l(false, 'N3 ' || tp || ': semilla v1 de Sandal Woods: debia ser 42501 (' || left(v, 110) || ')'); end if;
    else sem := sem + 1; end if;
    v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, %L)', ctx, idL));
    if v not like 'ERR%' then pos := pos + 1; else r := r || pg_temp.l(false, 'P1 ' || tp || ': la de Lawang debia fijarse (' || left(v, 110) || ')'); end if;
    delete from public.contrato_plantilla_version where contrato_id = ctx;
  end loop;
  r := r || pg_temp.l(neg = 17, 'N1 el agente de Lawang NO puede fijar la activa de Sandal Woods en ninguno de los 17 tipos (' || neg || '/17)');
  r := r || pg_temp.l(neg2 = 17, 'N2 ni el administrador global (la regla es del contrato, no de quien lo pide) (' || neg2 || '/17)');
  r := r || pg_temp.l(sem = 17, 'N3 ni la semilla v1 de Sandal Woods (' || sem || '/17)');
  r := r || pg_temp.l(pos = 17, 'P1 la activa de la propia empresa SI se fija en los 17 tipos (' || pos || '/17)');
  r := r || pg_temp.l((select count(*) from public.contrato_plantilla_version l join public.plantilla_contrato_versiones vv on vv.id = l.version_id join public.contratos cc on cc.id = l.contrato_id join public.proyectos pp on pp.id = cc.proyecto_id where vv.empresa <> pp.empresa) = 0, 'N4 ningun contrato queda vinculado a una revision de otra empresa');
  select x.id into idS from public.plantilla_contrato_versiones x where x.empresa = 'sandal_woods' and x.slug = 'carta_reserva_investor_deck' and x.estado = 'activa' and x.variante = 'rev_9';
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_cuerpo(%L, %L, null, %L)', 'carta_reserva_investor_deck', (select proyecto_id from public.contratos where id = ct), idS));
  r := r || pg_temp.l(v is null or v like 'ERR%', 'N5 plantilla_contrato_cuerpo con una version de otra empresa no la sirve (' || left(coalesce(v, 'null'), 80) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_nuevo_crea(''lawang'', ''Prueba cruce'', ''copia'', ''carta_reserva_investor_deck'', %L)', idS));
  r := r || pg_temp.l(v like 'ERR%' and v not like '%Elige si partes%', 'N6 plantilla_contrato_nuevo_crea con una version de otra empresa tampoco (' || left(coalesce(v, 'null'), 80) || ')');

  -- ================== 2. volatilidad
  fns := array['_plantilla_texto(text,boolean)', '_plantilla_analiza(text,boolean)', '_plantilla_valida(text,text,boolean)', 'plantilla_cuerpo_valida(text,text)', 'plantilla_cuerpo_valida_semilla(text,text)',
               '_plantilla_exige_bloques(text,text,text,text)', 'plantilla_contrato_revisa(text,text,text,text)'];
  select count(*) into n from unnest(fns) x where (select provolatile from pg_proc where oid = ('public.' || x)::regprocedure) = 'v';
  r := r || pg_temp.l(n = 7, 'V1 las 7 funciones que llaman a set_config son VOLATILE (' || n || '/7)');
  select count(*) into n from unnest(array['_plantilla_valida(text,text,boolean)', 'plantilla_cuerpo_valida(text,text)', 'plantilla_cuerpo_valida_semilla(text,text)']) x where (select proparallel from pg_proc where oid = ('public.' || x)::regprocedure) = 'u';
  r := r || pg_temp.l(n = 3, 'V2 y las tres de validar siguen PARALLEL UNSAFE (' || n || '/3)');
  bd := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'')->>''cuerpo_html''');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select (public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L))->>''ok''', bd));
  r := r || pg_temp.l(v = 'true', 'V3 el ensayo (que llama al validador) sigue funcionando como administrador de empresa (' || left(coalesce(v, 'null'), 80) || ')');

  -- ================== 3. trigger de campos propios: FOR SHARE y sigue validando
  def := pg_get_functiondef('public._trg_contrato_campos_propios()'::regprocedure);
  r := r || pg_temp.l(def ilike '%for share%', 'C1 el trigger lee el campo del catalogo FOR SHARE');
  v := pg_temp.run(format($q$update public.contratos set datos = jsonb_set(coalesce(datos, '{}'::jsonb), '{fields,cx_no_existe_zz}', '"x"') where id = %L$q$, ct));
  r := r || pg_temp.l(v like 'ERR22023%' and v like '%catalogo%', 'C2 un campo cx_ que no esta en el catalogo sigue rechazandose (' || left(v, 90) || ')');

  -- ================== 4. base de comparacion: ignora retiradas y archivadas
  v := pg_temp.mk('lawang', 'commercial_offer', 901, 'rev_7', 'retirada', 'd');
  r := r || pg_temp.l(v not like 'ERR%', 'B0 retirada de prueba en rev_7 (' || left(coalesce(v, ''), 100) || ')');
  v := pg_temp.mk('lawang', 'commercial_offer', 902, 'rev_7', 'archivada', 'e');
  r := r || pg_temp.l(v not like 'ERR%', 'B0b archivada de prueba en rev_7 (' || left(coalesce(v, ''), 100) || ')');
  bs := public._plantilla_base_edicion('lawang', 'commercial_offer', 'rev_7');
  r := r || pg_temp.l(bs is null, 'B1 con solo una retirada y una archivada no hay base de comparacion: se compara con el esqueleto (' || coalesce(left(bs, 30), 'null') || ')');
  v := pg_temp.mk('lawang', 'commercial_offer', 903, 'rev_7', 'activa', 'f');
  bs := public._plantilla_base_edicion('lawang', 'commercial_offer', 'rev_7');
  r := r || pg_temp.l(bs = 'TEXTO-ACTIVA-903', 'B2 con una activa posterior, la base es la activa y no la retirada ni la archivada (' || coalesce(left(bs, 30), 'null') || ')');

  fallos := (select count(*) from regexp_matches(r, 'FALLO', 'g'));
  raise exception E'INFORME ARREGLOS REVISOR\n%FALLOS=%', r, fallos;
end $todo$;
