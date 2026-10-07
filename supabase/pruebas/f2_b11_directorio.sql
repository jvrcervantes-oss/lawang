-- Prueba del BLOQUE 11 (7-oct-2026): directorio de clientes GLOBAL (ficha basica para todo el equipo; lo completo sigue por cliente_visible).
-- Se pega DESPUES de la migracion 20261008960000 (o detras de ella, para ensayarla sin rastro). Una sola peticion: setup + casos + A/B + raise final que lo revierte todo.
-- No crea usuarios: convierte dentro de la transaccion fichas existentes (ver f2_b3_empresas.sql):
--   ya = admin_empresa/lawang · cr = super_admin_empresa/sandal_woods · ad4 = admin_empresa con las dos · ctl = agente SIN empresas (control) · adm = admin global
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); sin drop de datos
create function pg_temp.t(p_uid uuid, p_email text, p_sql text, p_esp text, p_et text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare got text; r text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role',p_rol,'email',p_email)::text, true);
  execute format('set local role %I', p_rol);
  begin execute p_sql into r; got := coalesce(r,'null'); exception when others then got := sqlstate; end;
  reset role;
  return case when got = p_esp then 'OK   ' else 'FALLO' end || ' ' || p_et || ' [' || got || ' esp ' || p_esp || ']';
end $f$;
-- alta duplicada: captura SQLSTATE + DETAIL + MESSAGE y comprueba que no aparece NADA de la otra ficha (solo lo que tecleo quien da el alta)
create function pg_temp.dup(p_uid uuid, p_email text, p_datos text, p_otro_nombre text, p_otro_email text, p_otro_pas text, p_et text) returns text language plpgsql as $f$
declare got text := 'sin error'; m text := ''; d text := ''; n0 int; n1 int; fuga boolean;
begin
  select count(*) into n0 from public.clients;
  perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role','authenticated','email',p_email)::text, true);
  set local role authenticated;
  begin perform public.cliente_guarda(null, p_datos::jsonb);
  exception when others then get stacked diagnostics m = message_text, d = pg_exception_detail; got := sqlstate; end;
  reset role;
  select count(*) into n1 from public.clients;
  fuga := (p_otro_nombre is not null and position(upper(p_otro_nombre) in upper(m||' '||d)) > 0)
       or (p_otro_email is not null and position(lower(p_otro_email) in lower(m||' '||d)) > 0 and position(lower(p_otro_email) in lower(p_datos)) = 0)
       or (p_otro_pas is not null and position(upper(p_otro_pas) in upper(m||' '||d)) > 0 and position(upper(p_otro_pas) in upper(p_datos)) = 0);
  return case when got = '23505' and not fuga and n0 = n1 then 'OK   ' else 'FALLO' end || ' ' || p_et || ' [' || got || ' filas ' || n0 || '->' || n1 || ' fuga=' || fuga || ']';
end $f$;
-- ORIGINALES (texto de antes de la migracion, para el A/B)
create function pg_temp.o_lista() returns table(id uuid) language sql stable security definer set search_path to '' as $f$
  select c.id from public.clients c where public.es_agente() and (not (select public.alcance_restringido()) or public.cliente_visible(c.propietario, c.id)) $f$;
create function pg_temp.o_buscar(p_q text) returns table(id uuid) language plpgsql stable security definer set search_path to '' as $f$
begin
  if not public.es_agente() then return; end if;
  if length(btrim(coalesce(p_q,''))) < 3 then return; end if;
  return query select c.id from public.clients c
     where (not (select public.alcance_restringido()) or public.cliente_visible(c.propietario, c.id))
       and (c.full_name ilike '%'||btrim(p_q)||'%' or c.email ilike '%'||btrim(p_q)||'%' or lower(c.passport_number) = lower(btrim(p_q)))
     limit 8;
end $f$;
do $t$
declare
  jv uuid; ya uuid; cr uuid; ad4 uuid; ctl uuid; adm uuid; ina uuid;
  e_ya text; e_cr text; e_ad4 text; e_ctl text; e_adm text; e_ina text;
  cl uuid; cs uuid; cb uuid; total int; r text := ''; fallos int; u record; a text; b text; qs text;
  nom_cs text; em_cs text; pas_cs text; pas_cl text; path_cs text; cols text;
  hs text := '{comisiones,leads,ranking,reparto,comunicacion,compradores,usuarios}';
begin
  select user_id into jv from public.usuarios where email='jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email='yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email='cris.blueiestates@gmail.com';
  select user_id, email into ad4, e_ad4 from public.usuarios where email='adenovit.b@gmail.com';
  select user_id, email into ctl, e_ctl from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin') and user_id not in (ya,cr,ad4) order by email limit 1;
  select user_id, email into adm, e_adm from public.usuarios where activo and rol='admin' and ambito='global' order by email limit 1;
  if adm is null then select user_id, email into adm, e_adm from public.usuarios where activo and rol='super_admin' and ambito='global' order by email limit 1; end if;
  select user_id, email into ina, e_ina from public.usuarios where not activo order by email limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=ya;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=cr;
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang,sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=ad4;
  -- muestras (medidas como postgres): cl = cliente solo de Lawang, cs = solo de Sandal Woods, cb = en las dos
  select c.id into cl from public.clients c
   where exists (select 1 from public.contrato_compradores cc where cc.client_id=c.id)
     and not exists (select 1 from public.contrato_compradores cc join public.contratos k on k.id=cc.contrato_id left join public.proyectos pr on pr.id=k.proyecto_id where cc.client_id=c.id and pr.empresa is distinct from 'lawang')
     and c.passport_number is not null and c.email is not null
   order by c.id limit 1;
  select c.id into cs from public.clients c
   where exists (select 1 from public.contrato_compradores cc where cc.client_id=c.id)
     and not exists (select 1 from public.contrato_compradores cc join public.contratos k on k.id=cc.contrato_id left join public.proyectos pr on pr.id=k.proyecto_id where cc.client_id=c.id and pr.empresa is distinct from 'sandal_woods')
     and c.passport_number is not null and c.email is not null and length(split_part(c.email,'@',1)) >= 3
   order by (exists (select 1 from public.documents d where d.client_id=c.id and d.retirado_el is null)) desc, c.id limit 1;
  select cc.client_id into cb from public.contrato_compradores cc join public.contratos k on k.id=cc.contrato_id join public.proyectos p on p.id=k.proyecto_id
   group by cc.client_id having count(distinct p.empresa) filter (where p.empresa in ('lawang','sandal_woods'))=2 order by cc.client_id limit 1;
  select full_name, email, passport_number into nom_cs, em_cs, pas_cs from public.clients where id = cs;
  select passport_number into pas_cl from public.clients where id = cl;
  select d.storage_path into path_cs from public.documents d where d.client_id = cs and d.retirado_el is null and d.storage_path is not null limit 1;
  select count(*) into total from public.clients;

  -- 0. la ficha basica NO lleva nada sensible: columnas de lo que devuelven la lista y el buscador
  select string_agg(a2, ',') into cols from (select unnest(proargnames) a2 from pg_proc where proname='compradores_lista' and pronamespace='public'::regnamespace) z;
  r := r || case when cols !~ '(passport_number|date_of_birth|address|notes|registro_num|rep_nombre|kyc_verificado)' then 'OK   ' else 'FALLO' end || ' la lista no lleva pasaporte entero, nacimiento, direccion ni notas [' || cols || ']' || E'\n';
  select string_agg(a2, ',') into cols from (select unnest(proargnames) a2 from pg_proc where proname='comprador_buscar' and pronamespace='public'::regnamespace) z;
  r := r || case when cols !~ '(passport_number|date_of_birth|address|notes)' then 'OK   ' else 'FALLO' end || ' el buscador tampoco [' || cols || ']' || E'\n';
  -- 1. todos los del equipo ven todos en la lista y los numeros
  r := r || pg_temp.t(ya, e_ya, 'select count(*)::text from public.compradores_lista()', total::text, 'ya (admin Lawang) ve TODOS en la lista') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select count(*)::text from public.compradores_lista()', total::text, 'cr (super Sandal Woods) ve TODOS en la lista') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, 'select count(*)::text from public.compradores_lista()', total::text, 'ad4 (admin de las dos) ve TODOS') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, 'select count(*)::text from public.compradores_lista()', total::text, 'agente de control ve TODOS (ya los veia: sin alcance restringido)') || E'\n';
  r := r || pg_temp.t(adm, e_adm, 'select count(*)::text from public.compradores_lista()', total::text, 'admin global ve TODOS') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select count(*)::text from public.compradores_numeros()', total::text, 'ya ve TODOS los numeros de cliente') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select count(*)::text from public.compradores_numeros()', total::text, 'cr ve TODOS los numeros de cliente') || E'\n';
  -- 2. la ficha basica del cliente de la OTRA empresa: nombre y los 4 ultimos, sin el pasaporte entero
  r := r || pg_temp.t(ya, e_ya, format('select (passport_hint = ''…'' || right(%L, 4) and passport_hint <> %L)::text from public.compradores_lista() where id = %L', pas_cs, pas_cs, cs), 'true', 'ya ve al cliente de Sandal Woods con solo los 4 ultimos del pasaporte') || E'\n';
  -- 3. lo completo sigue cerrado: tabla, documentos, KYC, ficha entera, contratos
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.clients where id = %L', cs), '0', 'ya NO lee la fila entera del cliente de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select count(*)::text from public.clients where id = %L', cl), '0', 'cr NO lee la fila entera del cliente de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.documents where client_id = %L', cs), '0', 'ya NO ve documentos del cliente de Sandal Woods') || E'\n';
  if path_cs is not null then
    r := r || pg_temp.t(ya, e_ya, format('select public.agente_ve_kyc(%L)::text', path_cs), 'false', 'ya NO abre el fichero KYC del cliente de Sandal Woods (storage)') || E'\n';
    r := r || pg_temp.t(adm, e_adm, format('select public.agente_ve_kyc(%L)::text', path_cs), 'true', 'admin global sigue abriendo el KYC') || E'\n';
  end if;
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.comprador_ficha(%L)', cs), '0', 'ya NO abre la ficha entera (pasaporte, nacimiento, direccion) del cliente de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.comprador_ficha(%L)', cl), '1', 'ya abre la ficha entera de su cliente') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.comprador_contratos_resumen(%L)', cs), '0', 'ya NO ve ni los contratos del cliente de Sandal Woods') || E'\n';
  if cb is not null then
    r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.comprador_contratos_resumen(%L) where not visible', cb), '0', 'ya, del cliente compartido, solo ve los contratos que puede ver') || E'\n';
  end if;
  r := r || pg_temp.t(ctl, e_ctl, format('select count(*)::text from public.comprador_ficha(%L)', cs), '1', 'SIN CAMBIO: el agente sin restriccion sigue abriendo cualquier ficha entera (hueco previo, ver pendientes)') || E'\n';
  -- 4. el buscador: nombre y email de todos; el pasaporte ENTERO solo en el conjunto de antes
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.comprador_buscar(%L) where id = %L', split_part(em_cs,'@',1), cs), '1', 'ya encuentra al cliente de Sandal Woods por su correo') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.comprador_buscar(%L) where id = %L', em_cs, cs), '1', 'ya lo encuentra por su correo entero') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.comprador_buscar(%L) where id = %L', pas_cs, cs), '0', 'ya NO averigua a quien pertenece un pasaporte entero de la otra empresa') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.comprador_buscar(%L) where id = %L', pas_cl, cl), '1', 'ya si encuentra por pasaporte entero a su propio cliente') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select count(*)::text from public.comprador_buscar(%L) where id = %L', pas_cs, cs), '1', 'agente de control: el pasaporte entero sigue funcionando (sin cambio)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select count(*)::text from public.comprador_buscar(''ab'')', '0', 'busqueda de menos de 3 letras: nada') || E'\n';
  -- 5. escribir: quien no ve el cliente completo no lo edita, no lo traspasa y no lo borra
  r := r || pg_temp.t(ya, e_ya, format('select (public.cliente_guarda(%L, %L::jsonb) is not null)::text', cs, '{"notes":"prueba b11"}'), '42501', 'ya NO edita la ficha del cliente de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select (public.cliente_guarda(%L, %L::jsonb) is not null)::text', cl, '{"notes":"prueba b11"}'), '42501', 'cr NO edita la ficha del cliente de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.cliente_traspasa(%L, %L, ''prueba'') is not null)::text', cs, e_ad4), '42501', 'ya NO traspasa el cliente de la otra empresa') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.cliente_guarda(%L, %L::jsonb) is not null)::text', cs, '{"kyc_status":"verified"}'), '42501', 'ya NO aprueba el KYC del cliente de la otra empresa') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.borrar_comprador(%L)->>''borrado'')', cs), '42501', 'ya NO borra la ficha del cliente de la otra empresa', 'service_role') || E'\n';
  r := r || pg_temp.t(adm, e_adm, format('select (public.cliente_guarda(%L, %L::jsonb) is not null)::text', cs, '{"notes":"prueba b11"}'), 'true', 'admin global sigue editando cualquier ficha') || E'\n';
  -- 6. alta duplicada contra una ficha que no ves: el servidor la rechaza sin contar nada de la otra ficha, y no deja duplicados
  r := r || pg_temp.dup(ya, e_ya, jsonb_build_object('full_name','Prueba Duplicado B11','email',em_cs,'phone','+34600000001','nationality','ES','passport_number','B11XYZ99')::text, nom_cs, em_cs, pas_cs, 'ya: alta con el correo de un cliente invisible -> duplicado generico') || E'\n';
  r := r || pg_temp.dup(ya, e_ya, jsonb_build_object('full_name','Prueba Duplicado B11','email','prueba.b11.dup@example.com','phone','+34600000001','nationality','ES','passport_number',pas_cs)::text, nom_cs, em_cs, pas_cs, 'ya: alta con el pasaporte de un cliente invisible -> duplicado generico') || E'\n';
  r := r || pg_temp.dup(cr, e_cr, jsonb_build_object('full_name','Prueba Duplicado B11','email',(select email from public.clients where id = cl),'phone','+34600000001','nationality','ES','passport_number','B11XYZ98')::text,
                        (select full_name from public.clients where id = cl), (select email from public.clients where id = cl), pas_cl, 'cr: alta con el correo de un cliente de Lawang -> duplicado generico') || E'\n';
  -- 7. quien no es del equipo no recibe nada
  r := r || pg_temp.t(gen_random_uuid(), 'cuenta.portal.b11@example.com', 'select count(*)::text from public.compradores_lista()', '0', 'una cuenta del portal (sin ficha de equipo) NO recibe la lista') || E'\n';
  r := r || pg_temp.t(gen_random_uuid(), 'cuenta.portal.b11@example.com', 'select count(*)::text from public.comprador_buscar(''gmail'')', '0', 'ni el buscador') || E'\n';
  if ina is not null then
    r := r || pg_temp.t(ina, e_ina, 'select count(*)::text from public.compradores_lista()', '0', 'una ficha de equipo DESACTIVADA no recibe la lista') || E'\n';
  end if;
  r := r || pg_temp.t(gen_random_uuid(), 'anon@example.com', 'select count(*)::text from public.compradores_lista()', '42501', 'anon no tiene EXECUTE sobre la lista', 'anon') || E'\n';
  r := r || pg_temp.t(gen_random_uuid(), 'anon@example.com', 'select count(*)::text from public.comprador_buscar(''gmail'')', '42501', 'anon no tiene EXECUTE sobre el buscador', 'anon') || E'\n';
  -- 8. A/B por CADA persona activa, original frente a nuevo
  for u in select user_id, email, (ambito = 'empresa' or cardinality(coalesce(empresas,'{}')) > 0) restr from public.usuarios where activo order by email loop
    perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
    set local role authenticated;
    select md5(coalesce(string_agg(id::text, ',' order by id::text),'')) into a from pg_temp.o_lista();
    select md5(coalesce(string_agg(id::text, ',' order by id::text),'')) into b from public.compradores_lista();
    if not u.restr then
      r := r || case when a = b then 'OK   ' else 'FALLO' end || ' A/B lista, sin restriccion, ' || u.email || E'\n';
    else
      r := r || case when (select count(*) from public.compradores_lista()) = total
                      and not exists (select 1 from pg_temp.o_lista() o where o.id not in (select id from public.compradores_lista()))
                     then 'OK   ' else 'FALLO' end || ' A/B lista, con alcance, ' || u.email || ' [todos y contiene lo de antes]' || E'\n';
    end if;
    foreach qs in array array['mar','gmail',split_part(em_cs,'@',1),pas_cs,pas_cl] loop
      if qs is null then continue; end if;
      select md5(coalesce(string_agg(id::text, ',' order by id::text),'')) into a from pg_temp.o_buscar(qs);
      select md5(coalesce(string_agg(id::text, ',' order by id::text),'')) into b from public.comprador_buscar(qs);
      if not u.restr then
        r := r || case when a = b then 'OK   ' else 'FALLO' end || ' A/B buscar ' || case when qs in (pas_cs, pas_cl) then '<pasaporte>' else qs end || ', sin restriccion, ' || u.email || E'\n';
      elsif qs in (pas_cs, pas_cl) then
        r := r || case when not exists (select 1 from public.comprador_buscar(qs) n where n.id not in (select id from pg_temp.o_buscar(qs))) then 'OK   ' else 'FALLO' end
              || ' A/B buscar <pasaporte> entero, con alcance, ' || u.email || ' [no averigua mas que antes]' || E'\n';
      end if;
    end loop;
    reset role;
  end loop;
  fallos := (length(r) - length(replace(r, 'FALLO', ''))) / 5;
  raise exception E'\n%FALLOS=%', r, fallos;
end $t$;
