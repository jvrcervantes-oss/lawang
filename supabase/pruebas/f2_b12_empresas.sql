-- Prueba del BLOQUE 12 (Fase 2 · comision de administracion solo super global; sociedades solo propietario; Ajustes), 7-oct-2026.
-- Se ejecuta DESPUES de las migraciones 20261008970000 y 970100 (o pegada tras ellas en la misma peticion para ensayarlas sin rastro). Todo dentro de una transaccion que acaba en raise (rollback).
-- No crea usuarios: convierte 4 fichas de agente existentes (como f2_b4_empresas.sql) a ae_L admin_empresa/lawang, se_L super_admin_empresa/lawang, ae_S admin_empresa/sandal_woods,
-- se_S super_admin_empresa/sandal_woods; un 5o agente (ctl) sin tocar; los tres super globales (propietario, Andrea y Pepito).
-- Cada linea OK/FALLO. Debe terminar con «FALLOS=0».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); sin drop
create temp table _b12_out (txt text, fallos int);
create or replace function pg_temp.como(p_uid uuid, p_email text, p_sql text) returns text language plpgsql as $f$
declare v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
  execute 'set local role authenticated';
  begin
    execute p_sql; v := 'ok';
    raise exception 'deshacer' using errcode = 'LWS03';
  exception when sqlstate 'LWS03' then null;
            when others then v := sqlstate; if v = 'P0001' then v := v || '|' || sqlerrm; end if;   -- las puertas antiguas sin errcode (P0001) se reconocen por su mensaje
  end;
  execute 'reset role';
  return v;
end $f$;
create or replace function pg_temp.cuenta(p_uid uuid, p_email text, p_sql text) returns bigint language plpgsql as $f$
declare n bigint;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
  execute 'set local role authenticated';
  begin execute p_sql into n; exception when others then n := -1; end;
  execute 'reset role';
  return n;
end $f$;
create or replace function pg_temp.texto(p_uid uuid, p_email text, p_sql text) returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
  execute 'set local role authenticated';
  begin execute p_sql into t; exception when others then t := 'ERR' || sqlstate; end;
  execute 'reset role';
  return t;
end $f$;

-- ================================================================= personas (4 agentes convertidos + control) y objetos de prueba
create temp table _b12_p (et text primary key, uid uuid, em text);
do $p$
declare ids uuid[]; ems text[]; jv uuid;
begin
  select user_id into jv from public.usuarios where email = 'jvr.cervantes@gmail.com';
  select array_agg(user_id order by email), array_agg(email order by email) into ids, ems
    from (select user_id, email from public.usuarios where activo and ambito = 'global' and rol = 'agente' order by email limit 5) q;
  insert into _b12_p values ('ae_L', ids[1], ems[1]), ('se_L', ids[2], ems[2]), ('ae_S', ids[3], ems[3]), ('se_S', ids[4], ems[4]), ('ctl', ids[5], ems[5]);
  insert into _b12_p select 'jv', user_id, email from public.usuarios where email = 'jvr.cervantes@gmail.com';
  insert into _b12_p select 'andrea', user_id, email from public.usuarios where email = 'andreabenimeli@gmail.com';
  insert into _b12_p select 'pepito', user_id, email from public.usuarios where email = 'pepito@lawangproperties.com';
  perform set_config('request.jwt.claims', json_build_object('sub', jv, 'role', 'authenticated', 'email', 'jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{ajustes,comisiones_reparto,facturas,gastos,usuarios}', tipos_contrato = '{}' where user_id = ids[1];
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ids[2];
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{ajustes,comisiones_reparto,facturas,gastos,usuarios}', tipos_contrato = '{}' where user_id = ids[3];
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ids[4];
end $p$;

-- ================================================================= A y B: comision de administracion + devengo
do $t1$
declare
  e record; n bigint; x bigint; v text; t text; r text := ''; fallos int := 0;
  l_l uuid; l_s uuid; cobro uuid; serie uuid; datos_lw jsonb; datos_sw jsonb;
  c_sw uuid; c_lw uuid; f1 uuid; f2 uuid; emp text; tarifa_l uuid;
begin
  select l.id into l_l from public.comision_admin_lineas l where l.sociedad = 'tepi_sungai' and l.tipo_linea = 'devengo' and not l.anulada and l.estado = 'pendiente' limit 1;
  select l.id into l_s from public.comision_admin_lineas l where l.sociedad = 'san_dal_woods' and l.tipo_linea = 'devengo' and not l.anulada and l.estado = 'pendiente' limit 1;
  select c.id into cobro from public.comision_admin_cobros c where c.sociedad = 'tepi_sungai' and not c.anulado limit 1;
  select f.serie_id into serie from public.comision_admin_fees f where f.sociedad = 'tepi_sungai' limit 1;
  select t2.id into tarifa_l from public.comision_admin_tarifas t2 where t2.empresa = 'lawang' limit 1;
  datos_lw := jsonb_build_object('importe', 10, 'moneda', 'EUR', 'efectivo_desde', current_date);
  datos_sw := jsonb_build_object('concepto', 'Prueba', 'sociedad', 'san_dal_woods', 'importe', 10, 'moneda', 'EUR', 'efectivo_desde', current_date);

  -- A. un rol de empresa no ve ni opera nada (42501 en todo), ni el admin ni el super
  for e in select * from _b12_p where et in ('ae_L', 'se_L', 'ae_S', 'se_S', 'ctl') order by et loop
    n := pg_temp.cuenta(e.uid, e.em, 'select (select count(*) from public.comision_admin_lineas) + (select count(*) from public.comision_admin_fees) + (select count(*) from public.comision_admin_cobros) + (select count(*) from public.comision_admin_tarifas)');
    r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' A1 %s no ve nada del libro (lineas+fees+cobros+tarifas = %s)', e.et, n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;
    foreach t in array array[
      'select public.comision_admin_descuadres()',
      'select public.comision_admin_prevision()',
      'select public.comision_admin_devenga_fees()',
      format('select public.comision_admin_anula_linea(%L, %L)', l_l, 'prueba'),
      format('select public.comision_admin_anula_linea(%L, %L)', l_s, 'prueba'),
      format('select public.comision_admin_repone_devengo(%L)', l_l),
      format('select public.comision_admin_linea_estado(%L, ''exenta'', null, false, false, ''motivo de prueba'')', l_l),
      format('select public.comision_admin_linea_estado(%L, ''exenta'', null, false, false, ''motivo de prueba'')', l_s),
      'select public.comision_admin_registrar_cobro(''tepi_sungai'', ''EUR'', 1, current_date)',
      'select public.comision_admin_registrar_cobro(''san_dal_woods'', ''EUR'', 1, current_date)',
      format('select public.comision_admin_anular_cobro(%L, ''motivo de prueba'')', cobro),
      format('select public.comision_admin_fee_guarda(%L, %L::jsonb)', serie, datos_lw::text),
      format('select public.comision_admin_fee_guarda(null, %L::jsonb)', datos_sw::text),
      'select public.comision_admin_tarifa_crea(0.6, current_date + 100, ''prueba'')',
      format('select public.comision_admin_edita_tarifa(%L, 0.7, current_date + 99, ''prueba'', false)', tarifa_l)] loop
      v := pg_temp.como(e.uid, e.em, t);
      r := r || case when v = '42501' or v ~* '^P0001[|].*super' then 'OK   ' else 'FALLO' end || format(' A2 %s: %s -> %s', e.et, left(replace(t, 'select public.', ''), 44), left(v, 44)) || E'
'; if not (v = '42501' or v ~* '^P0001[|].*super') then fallos := fallos + 1; end if;
    end loop;
  end loop;
  -- los tres super globales ven y operan todo (cualquier cosa menos 42501)
  for e in select * from _b12_p where et in ('jv', 'andrea', 'pepito') order by et loop
    select count(*) into x from public.comision_admin_lineas;
    n := pg_temp.cuenta(e.uid, e.em, 'select count(*) from public.comision_admin_lineas');
    r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' A3 %s ve las %s lineas del libro (%s)', e.et, x, n) || E'\n'; if n <> x then fallos := fallos + 1; end if;
    select (select count(*) from public.comision_admin_fees) + (select count(*) from public.comision_admin_cobros) + (select count(*) from public.comision_admin_tarifas) into x;
    n := pg_temp.cuenta(e.uid, e.em, 'select (select count(*) from public.comision_admin_fees) + (select count(*) from public.comision_admin_cobros) + (select count(*) from public.comision_admin_tarifas)');
    r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' A3 %s ve fees, cobros y tarifas (%s/%s)', e.et, n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
    foreach t in array array[
      'select public.comision_admin_descuadres()',
      'select public.comision_admin_prevision()',
      'select public.comision_admin_devenga_fees()',
      format('select public.comision_admin_anula_linea(%L, %L)', l_l, 'prueba'),
      format('select public.comision_admin_anula_linea(%L, %L)', l_s, 'prueba'),
      format('select public.comision_admin_linea_estado(%L, ''exenta'', null, false, false, ''motivo de prueba'')', l_s),
      'select public.comision_admin_registrar_cobro(''san_dal_woods'', ''EUR'', 1, current_date)',
      format('select public.comision_admin_fee_guarda(null, %L::jsonb)', datos_sw::text),
      'select public.comision_admin_tarifa_crea(0.6, current_date + 100, ''prueba'')'] loop
      v := pg_temp.como(e.uid, e.em, t);
      r := r || case when v <> '42501' then 'OK   ' else 'FALLO' end || format(' A4 %s: %s -> %s (todo menos 42501)', e.et, left(replace(t, 'select public.', ''), 40), v) || E'\n'; if v = '42501' then fallos := fallos + 1; end if;
    end loop;
  end loop;
  -- puede_reparto_de NO es de esta pantalla (reparto de comisiones de los agentes): el super de empresa conserva el de SU empresa
  select * into e from _b12_p where et = 'se_L';
  perform set_config('request.jwt.claims', json_build_object('sub', e.uid, 'role', 'authenticated', 'email', e.em)::text, true);
  v := (public.puede_reparto_de('lawang'))::text || '/' || (public.puede_reparto_de('sandal_woods'))::text;
  r := r || case when v = 'true/false' then 'OK   ' else 'FALLO' end || format(' A6 puede_reparto_de (reparto de comisiones de los agentes) no cambia: se_L = %s', v) || E'\n'; if v <> 'true/false' then fallos := fallos + 1; end if;

  -- B. el devengo automatico no se toca (recibis de prueba DENTRO del rollback + consulta de tarifa por separado)
  select c.id into c_sw from public.contratos c join public.proyectos p on p.id = c.proyecto_id where p.empresa = 'sandal_woods' and c.contrato_padre_id is null limit 1;
  select c.id into c_lw from public.contratos c join public.proyectos p on p.id = c.proyecto_id where p.empresa = 'lawang' and c.contrato_padre_id is null limit 1;
  select * into e from _b12_p where et = 'pepito';
  perform set_config('request.jwt.claims', json_build_object('sub', e.uid, 'role', 'authenticated', 'email', e.em)::text, true);
  begin
    insert into public.facturas (tipo, sociedad, numero, fecha_emision, total, moneda, datos, contrato_id, justificante_path)
    values ('recibi', 'san_dal_woods', 'TEST-B12-SW', current_date, 100, 'EUR', '{"totales":{"subtotal":100}}'::jsonb, c_sw, 'prueba/b12-sw.pdf') returning id into f1;
    insert into public.facturas (tipo, sociedad, numero, fecha_emision, total, moneda, datos, contrato_id, justificante_path)
    values ('recibi', 'tepi_sungai', 'TEST-B12-LW', current_date, 100, 'EUR', '{"totales":{"subtotal":100}}'::jsonb, c_lw, 'prueba/b12-lw.pdf') returning id into f2;
    select t2.empresa into emp from public.comision_admin_lineas l join public.comision_admin_tarifas t2 on t2.id = l.tarifa_id where l.recibi_id = f1 and l.tipo_linea = 'devengo';
    r := r || case when emp = 'sandal_woods' then 'OK   ' else 'FALLO' end || format(' B1 un recibi de san_dal_woods sigue devengando con la tarifa de %s', emp) || E'\n'; if emp is distinct from 'sandal_woods' then fallos := fallos + 1; end if;
    select t2.empresa into emp from public.comision_admin_lineas l join public.comision_admin_tarifas t2 on t2.id = l.tarifa_id where l.recibi_id = f2 and l.tipo_linea = 'devengo';
    r := r || case when emp = 'lawang' then 'OK   ' else 'FALLO' end || format(' B1 un recibi de tepi_sungai sigue devengando con la tarifa de %s', emp) || E'\n'; if emp is distinct from 'lawang' then fallos := fallos + 1; end if;
  exception when others then
    r := r || 'AVISO no se pudo insertar un recibi de prueba (' || sqlerrm || '); se comprueba la consulta de tarifa por separado' || E'\n';
  end;
  select count(*) into n from public.comision_admin_tarifas t2 where t2.efectivo_desde <= current_date and t2.empresa = coalesce(public.empresa_de_sociedad('san_dal_woods'), 'lawang');
  r := r || case when n = 1 then 'OK   ' else 'FALLO' end || format(' B2 la consulta de tarifa de san_dal_woods da una fila (%s)', n) || E'\n'; if n <> 1 then fallos := fallos + 1; end if;
  select count(*) into n from public.comision_admin_tarifas t2 where t2.efectivo_desde <= current_date and t2.empresa = coalesce(public.empresa_de_sociedad('tepi_sungai'), 'lawang');
  r := r || case when n = 1 then 'OK   ' else 'FALLO' end || format(' B2 la consulta de tarifa de tepi_sungai da una fila (%s)', n) || E'\n'; if n <> 1 then fallos := fallos + 1; end if;
  select count(*) into n from pg_trigger where tgrelid = 'public.facturas'::regclass and not tgisinternal and tgname ilike '%comision_admin%';
  r := r || case when n >= 1 then 'OK   ' else 'FALLO' end || format(' B3 los disparadores del devengo siguen en facturas (%s)', n) || E'\n'; if n < 1 then fallos := fallos + 1; end if;
  insert into _b12_out values (r, fallos);
end $t1$;

-- ================================================================= C: sociedades solo propietario
do $t2$
declare
  e record; n bigint; x bigint; v text; r text := ''; fallos int := 0; j jsonb; razon text;
begin
  -- C1 la lista (con el recuento de documentos): solo el propietario
  for e in select * from _b12_p where et in ('ae_L', 'se_L', 'ae_S', 'se_S', 'ctl', 'andrea', 'pepito') order by et loop
    v := pg_temp.como(e.uid, e.em, 'select public.sociedades_ajustes_datos()');
    r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' C1 %s: sociedades_ajustes_datos -> %s', e.et, v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  end loop;
  select * into e from _b12_p where et = 'jv';
  v := pg_temp.como(e.uid, e.em, 'select public.sociedades_ajustes_datos()');
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' C1 el propietario: sociedades_ajustes_datos -> %s', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', e.uid, 'role', 'authenticated', 'email', e.em)::text, true);
  set local role authenticated;
  j := public.sociedades_ajustes_datos();
  reset role;
  select count(*) into x from public.sociedades;
  r := r || case when (j->>'puede_escribir') = 'true' and jsonb_array_length(j->'sociedades') = x then 'OK   ' else 'FALLO' end || format(' C1 el propietario recibe las %s sociedades con puede_escribir=%s', x, j->>'puede_escribir') || E'\n';
  if not ((j->>'puede_escribir') = 'true' and jsonb_array_length(j->'sociedades') = x) then fallos := fallos + 1; end if;
  r := r || case when (j->'sociedades'->0) ? 'documentos' and not ((j->'sociedades'->0) ? 'puede_escribir_esta') then 'OK   ' else 'FALLO' end || ' C1 cada sociedad lleva el recuento de documentos' || E'\n';
  if not ((j->'sociedades'->0) ? 'documentos' and not ((j->'sociedades'->0) ? 'puede_escribir_esta')) then fallos := fallos + 1; end if;

  -- C2 editar y dar de alta: solo el propietario (con los mismos datos de la sociedad, sin cambiar nada)
  select s.razon into razon from public.sociedades s where s.clave = 'tepi_sungai';
  for e in select * from _b12_p where et in ('ae_L', 'se_L', 'ae_S', 'se_S', 'ctl', 'andrea', 'pepito') order by et loop
    v := pg_temp.como(e.uid, e.em, format('select public.sociedad_guarda(''tepi_sungai'', jsonb_build_object(''razon'', %L), false)', razon));
    r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' C2 %s NO edita tepi_sungai (%s)', e.et, v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
    v := pg_temp.como(e.uid, e.em, 'select public.sociedad_guarda(''san_dal_woods'', jsonb_build_object(''razon'', (select s.razon from public.sociedades s where s.clave = ''san_dal_woods'')), false)');
    r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' C2 %s NO edita san_dal_woods (%s)', e.et, v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
    v := pg_temp.como(e.uid, e.em, 'select public.sociedad_guarda(''sociedad_nueva_x'', ''{"razon":"X","domicilio":"Y"}''::jsonb, true)');
    r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' C2 %s NO da de alta una sociedad (%s)', e.et, v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  end loop;
  select * into e from _b12_p where et = 'jv';
  v := pg_temp.como(e.uid, e.em, format('select public.sociedad_guarda(''tepi_sungai'', jsonb_build_object(''razon'', %L), false)', razon));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' C2 el propietario edita tepi_sungai (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(e.uid, e.em, 'select public.sociedad_guarda(''sociedad_nueva_x'', ''{"razon":"X","domicilio":"Y"}''::jsonb, true)');
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' C2 el propietario da de alta una sociedad (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;

  -- C3 el historial: solo el propietario
  select count(*) into x from public.sociedades_log;
  for e in select * from _b12_p where et in ('ae_L', 'se_L', 'ae_S', 'se_S', 'ctl', 'andrea', 'pepito', 'jv') order by et loop
    n := pg_temp.cuenta(e.uid, e.em, 'select count(*) from public.sociedades_log');
    r := r || case when (e.et = 'jv' and n = x) or (e.et <> 'jv' and n = 0) then 'OK   ' else 'FALLO' end || format(' C3 %s ve %s filas del historial de sociedades (propietario: %s)', e.et, n, x) || E'\n';
    if not ((e.et = 'jv' and n = x) or (e.et <> 'jv' and n = 0)) then fallos := fallos + 1; end if;
  end loop;
  r := r || case when to_regprocedure('public.sociedad_super_de(text)') is null then 'OK   ' else 'FALLO' end || ' C4 sociedad_super_de retirada (sin llamador)' || E'\n';
  if to_regprocedure('public.sociedad_super_de(text)') is not null then fallos := fallos + 1; end if;

  -- C5 lo que necesitan los documentos y la emision NO cambia: se_L sigue leyendo la sociedad de su empresa
  select * into e from _b12_p where et = 'se_L';
  n := pg_temp.cuenta(e.uid, e.em, 'select count(*) from public.sociedades');
  r := r || case when n >= 1 then 'OK   ' else 'FALLO' end || format(' C5 se_L sigue leyendo la sociedad de su empresa en sociedades para sus documentos (%s)', n) || E'\n'; if n < 1 then fallos := fallos + 1; end if;
  n := pg_temp.cuenta(e.uid, e.em, 'select count(*) from public.sociedades_visibles()');
  r := r || case when n >= 1 then 'OK   ' else 'FALLO' end || format(' C5 se_L sigue viendo su sociedad en sociedades_visibles() (%s)', n) || E'\n'; if n < 1 then fallos := fallos + 1; end if;
  insert into _b12_out values (r, fallos);
end $t2$;

-- ================================================================= D: Ajustes - un rol de empresa no entra; los super globales si
do $t3$
declare
  e record; v text; r text := ''; fallos int := 0; t text; a text;
begin
  for e in select * from _b12_p where et in ('ae_L', 'se_L', 'ae_S', 'se_S', 'ctl') order by et loop
    foreach t in array array[
      'select public.ajustes_config_datos()',
      'select public.ajustes_log_datos(10)',
      'select public.ajustes_config_guardar(''clave_que_no_existe'', ''"x"''::jsonb, ''prueba'')',
      'select public.mantenimiento_intranet(false, ''prueba'')',
      'select public.mantenimiento_envios(false, ''prueba'')'] loop
      v := pg_temp.como(e.uid, e.em, t);
      r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' D1 %s: %s -> %s', e.et, left(replace(t, 'select public.', ''), 40), v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
    end loop;
    a := pg_temp.texto(e.uid, e.em, 'select public.mantenimiento_datos()::text');
    r := r || case when a not like '%"ajustes": true%' and a not like '%"ajustes":true%' then 'OK   ' else 'FALLO' end || format(' D2 %s: mantenimiento_datos no le da la llave de Ajustes (%s)', e.et, left(a, 70)) || E'\n';
    if a like '%"ajustes": true%' or a like '%"ajustes":true%' then fallos := fallos + 1; end if;
  end loop;
  for e in select * from _b12_p where et in ('jv', 'andrea', 'pepito') order by et loop
    foreach t in array array['select public.ajustes_config_datos()', 'select public.ajustes_log_datos(10)'] loop
      v := pg_temp.como(e.uid, e.em, t);
      r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' D3 %s (super global): %s -> %s', e.et, left(replace(t, 'select public.', ''), 40), v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
    end loop;
  end loop;
  insert into _b12_out values (r, fallos);
end $t3$;

-- ================================================================= informe
do $fin$
declare t text := ''; f int := 0; x record;
begin
  for x in select * from _b12_out loop t := t || x.txt; f := f + x.fallos; end loop;
  raise exception E'\n%FALLOS=%', t, f;
end $fin$;
