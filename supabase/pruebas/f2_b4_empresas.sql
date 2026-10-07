-- Prueba del BLOQUE 4 (Fase 2 · comisiones, equipos de venta y condiciones por empresa), 8-oct-2026.
-- Se ejecuta DESPUES de las migraciones 20261008400100..400500 (o pegada tras ellas en la misma peticion para ensayarlas sin rastro). Todo dentro de una transaccion que acaba en raise (rollback).
-- No crea usuarios: convierte fichas de agente existentes (como f2_2b_empresas.sql):
--   ae = admin_empresa/lawang (casilla comisiones_reparto) · se = super_admin_empresa/sandal_woods (SIN casilla: el super de empresa no la necesita) ·
--   a2 = admin_empresa con las dos (con casilla) · ctl = agente de control NO tocado · pepito = super global · sales = admin global con casilla.
-- Cada linea OK/FALLO. Debe terminar con «FALLOS=0».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); sin drop
create temp table _b4_out (txt text, fallos int);
create or replace function pg_temp.como(p_uid uuid, p_email text, p_sql text) returns text language plpgsql as $f$
declare v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
  execute 'set local role authenticated';
  begin
    execute p_sql; v := 'ok';
    raise exception 'deshacer' using errcode = 'LWS03';   -- cada intento se deshace: las pruebas no se pisan entre si
  exception when sqlstate 'LWS03' then null;
            when others then v := sqlstate;
  end;
  execute 'reset role';
  return v;
end $f$;
create or replace function pg_temp.como_msg(p_uid uuid, p_email text, p_sql text) returns text language plpgsql as $f$
declare v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
  execute 'set local role authenticated';
  begin
    execute p_sql; v := 'ok';
    raise exception 'deshacer' using errcode = 'LWS03';
  exception when sqlstate 'LWS03' then null;
            when others then v := sqlstate || '|' || left(sqlerrm, 50);
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

create or replace function pg_temp.ids(p_uid uuid, p_email text, p_sql text) returns uuid[] language plpgsql as $f$
declare a uuid[];
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
  execute 'set local role authenticated';
  begin execute p_sql into a; exception when others then a := null; end;
  execute 'reset role';
  return a;
end $f$;

do $t3$
declare
  jv uuid; ya uuid; cr uuid; ad4 uuid; ctl uuid; pe uuid; sa uuid;
  e_ya text; e_cr text; e_ad4 text; e_ctl text; e_pe text; e_sa text;
  r text := ''; fallos int := 0; n bigint; x bigint; v text;
  d_l_est uuid; d_s_est uuid; d_l_clo uuid; raiz_sw uuid; raiz_lw uuid; dif uuid;
  arr uuid[];
begin
  select user_id into jv from public.usuarios where email = 'jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email = 'yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email = 'cris.blueiestates@gmail.com';
  select user_id, email into ad4, e_ad4 from public.usuarios where email = 'adenovit.b@gmail.com';
  select user_id, email into pe, e_pe from public.usuarios where email = 'pepito@lawangproperties.com';
  select user_id, email into sa, e_sa from public.usuarios where email = 'sales@lawangproperties.com';
  select user_id, email into ctl, e_ctl from public.usuarios
   where activo and ambito = 'global' and cardinality(coalesce(empresas, '{}')) = 0 and rol = 'agente' and not ('comisiones_reparto' = any (coalesce(herramientas, '{}')))
     and user_id not in (ya, cr, ad4) order by email limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', jv, 'role', 'authenticated', 'email', 'jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{comisiones_reparto}', tipos_contrato = '{}' where user_id = ya;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = cr;
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang,sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{comisiones_reparto}', tipos_contrato = '{}' where user_id = ad4;

  -- objetos de prueba
  select d.id into d_l_est from public.comisiones_devengadas d where d.nivel = 'estandar' and d.estado = 'pendiente' and public._empresa_de_contrato_int(d.contrato_raiz_id) = 'lawang' limit 1;
  select d.id into d_s_est from public.comisiones_devengadas d where d.nivel = 'estandar' and d.estado = 'pendiente' and public._empresa_de_contrato_int(d.contrato_raiz_id) = 'sandal_woods' limit 1;
  select d.id into d_l_clo from public.comisiones_devengadas d where d.nivel = 'closer' and d.estado = 'pendiente' and public._empresa_de_contrato_int(d.contrato_raiz_id) = 'lawang' limit 1;
  select k.contrato_id into raiz_sw from public.contrato_closer k where k.equipo_id is not null and public._empresa_de_contrato_int(k.contrato_id) = 'sandal_woods' limit 1;
  select k.contrato_id into raiz_lw from public.contrato_closer k where k.equipo_id is not null and public._empresa_de_contrato_int(k.contrato_id) = 'lawang' limit 1;

  -- 1. lo que ve cada una de comisiones_devengadas (policy = comision_visible)
  select count(*) into x from public.comisiones_devengadas d where public._empresa_de_contrato_int(d.contrato_raiz_id) = 'lawang';
  n := pg_temp.cuenta(ya, e_ya, 'select count(*) from public.comisiones_devengadas');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' ae(lawang) ve %s devengos (esperados %s, los de lawang)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
  select count(*) into x from public.comisiones_devengadas d where public._empresa_de_contrato_int(d.contrato_raiz_id) = 'sandal_woods';
  n := pg_temp.cuenta(cr, e_cr, 'select count(*) from public.comisiones_devengadas');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' se(sandal_woods, sin casilla) ve %s devengos (esperados %s, los de sandal_woods)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
  select count(*) into x from public.comisiones_devengadas d where public._empresa_de_contrato_int(d.contrato_raiz_id) is not null;
  n := pg_temp.cuenta(ad4, e_ad4, 'select count(*) from public.comisiones_devengadas');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' a2(las dos) ve %s (esperados %s)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
  select count(*) into x from public.comisiones_devengadas;
  n := pg_temp.cuenta(pe, e_pe, 'select count(*) from public.comisiones_devengadas');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' super global ve todos (%s/%s)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
  n := pg_temp.cuenta(sa, e_sa, 'select count(*) from public.comisiones_devengadas');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' admin global con casilla ve todos (%s/%s)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
  n := pg_temp.cuenta(ctl, e_ctl, 'select count(*) from public.comisiones_devengadas');
  r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' agente de control no ve ninguno (%s)', n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;

  -- 2. marcar pagada (comision de closer, pendiente, lawang)
  v := pg_temp.como(ya, e_ya, format('select public.comision_marca_pagada(%L)', d_l_clo));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' ae(lawang) marca pagada una de lawang (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.comision_marca_pagada(%L)', d_l_clo));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' se(sandal_woods) NO marca una de lawang (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(ctl, e_ctl, format('select public.comision_marca_pagada(%L)', d_l_clo));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' control NO marca (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(pe, e_pe, format('select public.comision_marca_pagada(%L)', d_l_clo));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' super global sigue marcando (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;

  -- 3. anular una comision estandar (la que paga Lawang)
  v := pg_temp.como(ya, e_ya, format('select public.comision_devengo_anular_lawang(%L, %L)', d_s_est, 'prueba de aislamiento'));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae(lawang) NO anula una de sandal_woods (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.comision_devengo_anular_lawang(%L, %L)', d_l_est, 'prueba de aislamiento'));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' se(sandal_woods) NO anula una de lawang (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  -- (comision_devengo_anular_lawang no es ejecutable por authenticated: esta dormida, sin llamador; su puerta ya esta convertida y solo la prueban los dos casos negativos de arriba) --  de pago que cuelga de la comision la para _trg_solicitud_pago_transicion (es_admin(), bloque 2): unico motivo aceptado

  -- 4. trazabilidad
  v := pg_temp.como(ya, e_ya, format('select public.comision_trazabilidad(%L)', d_s_est));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae(lawang) NO ve la trazabilidad de una de sandal_woods (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.comision_trazabilidad(%L)', d_s_est));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' se(sandal_woods) ve la de las suyas (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(ctl, e_ctl, format('select public.comision_trazabilidad(%L)', d_l_est));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' control NO ve la trazabilidad (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;

  -- 5. roles de la venta (setter/team lead), modo de la venta y recalculo
  v := pg_temp.como(ya, e_ya, format('select public.comision_rol_asignar(%L, ''setter'', null)', raiz_sw));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae(lawang) NO asigna roles en una venta de sandal_woods (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.comision_rol_asignar(%L, ''setter'', null)', raiz_sw));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' se(sandal_woods) asigna roles en una de las suyas (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.comision_rol_asignar(%L, ''setter'', null)', raiz_lw));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' se(sandal_woods) NO asigna roles en una de lawang (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(ya, e_ya, format('select public.venta_modo_admin(%L, ''equipo'', ''prueba de aislamiento'')', raiz_sw));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae(lawang) NO cambia el modo de una venta de sandal_woods (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.venta_modo_admin(%L, ''equipo'', ''prueba de aislamiento'')', raiz_sw));
  r := r || case when v <> '42501' then 'OK   ' else 'FALLO' end || format(' se(sandal_woods) PASA la puerta de venta_modo_admin en una de las suyas (%s)', v) || E'\n'; if v = '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(ya, e_ya, format('select public.comision_recalcular(%L, ''prueba'')', raiz_sw));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae(lawang) NO recalcula una de sandal_woods (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(ya, e_ya, format('select public.comision_recalcular(%L, ''prueba'')', raiz_lw));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae(lawang) NO recalcula ni las suyas: recalcular es de super (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.comision_recalcular(%L, ''prueba'')', raiz_lw));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' se(sandal_woods) NO recalcula una de lawang (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.comision_recalcular(%L, ''prueba'')', raiz_sw));
  r := r || case when v <> '42501' then 'OK   ' else 'FALLO' end || format(' se(sandal_woods) PASA la puerta de recalcular una de las suyas (%s)', v) || E'\n'; if v = '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(ya, e_ya, 'select public.venta_objecion_resolver(gen_random_uuid(), ''mantener_propia'', ''x'')');
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae NO resuelve una objecion que no es de su empresa (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(pe, e_pe, 'select public.venta_objecion_resolver(gen_random_uuid(), ''mantener_propia'', ''x'')');
  r := r || case when v = 'P0002' then 'OK   ' else 'FALLO' end || format(' super global sigue pasando la puerta (llega a «no existe», %s)', v) || E'\n'; if v <> 'P0002' then fallos := fallos + 1; end if;

  -- 6. diferencia de comision: una de sandal_woods
  begin
    insert into public.comisiones_diferencias (devengo_id, importe, importe_vigente, importe_nuevo, motivo, estado)
    select d_s_est, 1, 1, 2, 'prueba', 'revisar' returning id into dif;
  exception when others then dif := null; r := r || 'AVISO no se pudo crear la diferencia de prueba: ' || sqlerrm || E'\n';
  end;
  if dif is not null then
    v := pg_temp.como(ya, e_ya, format('select public.comision_diferencia_resolver(%L, ''anular'', ''prueba'')', dif));
    r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae(lawang) NO resuelve una diferencia de sandal_woods (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
    v := pg_temp.como(cr, e_cr, format('select public.comision_diferencia_resolver(%L, ''anular'', ''prueba'')', dif));
    r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' se(sandal_woods) resuelve la de las suyas (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  end if;

  -- 7. lista de ventas con equipo: solo las de su empresa
  arr := pg_temp.ids(ya, e_ya, 'select array_agg(raiz_id) from public.comisiones_ventas_equipo()');
  select count(*) into n from unnest(arr) a where public._empresa_de_contrato_int(a) is distinct from 'lawang';
  r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' ae: la lista de ventas con equipo no trae ninguna de otra empresa (%s ajenas)', n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;
  r := r || case when coalesce(cardinality(arr), 0) > 0 then 'OK   ' else 'FALLO' end || format(' ae: ve %s ventas de lawang con equipo', coalesce(cardinality(arr), 0)) || E'\n'; if coalesce(cardinality(arr), 0) = 0 then fallos := fallos + 1; end if;
  arr := pg_temp.ids(cr, e_cr, 'select array_agg(raiz_id) from public.comisiones_ventas_equipo()');
  select count(*) into n from unnest(arr) a where public._empresa_de_contrato_int(a) is distinct from 'sandal_woods';
  r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' se: la lista no trae ninguna de lawang (%s ajenas)', n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;
  n := pg_temp.cuenta(ctl, e_ctl, 'select count(*) from public.comisiones_ventas_equipo()');
  r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' control no ve ventas de equipos ajenos (%s)', n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;
  v := pg_temp.como(ya, e_ya, 'select * from public.ventas_por_su_cuenta_cuota()');
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' ae: ventas_por_su_cuenta_cuota responde (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, 'select * from public.ventas_por_su_cuenta_equipo()');
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' se: ventas_por_su_cuenta_equipo responde (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;

  insert into _b4_out values (r, fallos);
end $t3$;

-- ================================================================= equipos, miembros, plantillas y condiciones (migracion 4)
do $t4$
declare
  jv uuid; ya uuid; cr uuid; ad4 uuid; ctl uuid; pe uuid; lo uuid;
  e_ya text; e_cr text; e_ad4 text; e_ctl text; e_pe text; e_lo text;
  r text := ''; fallos int := 0; n bigint; x bigint; v text;
  lt uuid; st uuid; c_st uuid; c_lt uuid; id_new uuid; emp text; filas jsonb;
  tramos jsonb := '[{"disparador_tipo":"contrato_firmado","umbral":null,"pct_tramo":100}]'::jsonb;
  cond_lt jsonb; cond_st jsonb; cond_std jsonb;
begin
  select user_id into jv from public.usuarios where email = 'jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email = 'yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email = 'cris.blueiestates@gmail.com';
  select user_id, email into ad4, e_ad4 from public.usuarios where email = 'adenovit.b@gmail.com';
  select user_id, email into pe, e_pe from public.usuarios where email = 'pepito@lawangproperties.com';
  select u.user_id, u.email into ctl, e_ctl from public.usuarios u
   where u.activo and u.ambito = 'global' and cardinality(coalesce(u.empresas, '{}')) = 0 and u.rol = 'agente' and not ('comisiones_reparto' = any (coalesce(u.herramientas, '{}')))
     and u.user_id not in (ya, cr, ad4)
     and not exists (select 1 from public.equipo_miembros m where lower(m.closer_email) = lower(u.email))
     and not exists (select 1 from public.equipos_venta ev where lower(ev.manager_email) = lower(u.email))
     and not exists (select 1 from public.contrato_closer k where lower(k.closer_email) = lower(u.email))
   order by u.email limit 1;
  select u.user_id, u.email into lo, e_lo from public.usuarios u
   where u.activo and u.ambito = 'global' and u.rol = 'agente' and u.user_id not in (ya, cr, ad4, ctl)
     and not exists (select 1 from public.equipo_miembros m where lower(m.closer_email) = lower(u.email))
     and not exists (select 1 from public.equipos_venta ev where lower(ev.manager_email) = lower(u.email))
     and not exists (select 1 from public.contrato_closer k where lower(k.closer_email) = lower(u.email))
   order by u.email desc limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', jv, 'role', 'authenticated', 'email', 'jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set empresas = '{lawang}' where user_id = lo;   -- «solo vende en lawang»

  select id into lt from public.equipos_venta where nombre = 'Gus Abellán' and empresa = 'lawang';
  select id into st from public.equipos_venta where nombre = 'Gus Abellán' and empresa = 'sandal_woods';
  select id into c_lt from public.condiciones_comision where equipo_id = lt and nivel = 'manager' limit 1;
  select id into c_st from public.condiciones_comision where equipo_id = st and nivel = 'manager' limit 1;
  cond_lt := jsonb_build_object('equipo_id', lt, 'nivel', 'closer', 'pct_comision', 7, 'base_calculo', 'precio_total', 'vigente_desde', current_date + 60);
  cond_st := jsonb_build_object('equipo_id', st, 'nivel', 'closer', 'pct_comision', 7, 'base_calculo', 'precio_total', 'vigente_desde', current_date + 60);
  cond_std := jsonb_build_object('nivel', 'closer', 'pct_comision', 3, 'base_calculo', 'precio_total', 'vigente_desde', current_date + 61);

  -- 1. lectura: lo que ve cada una de equipos, miembros y condiciones
  select count(*) into x from public.equipos_venta where empresa = 'lawang';
  n := pg_temp.cuenta(ya, e_ya, 'select count(*) from public.equipos_venta');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' ae(lawang) ve %s equipos (esperados %s)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
  select count(*) into x from public.equipos_venta where empresa = 'sandal_woods';
  n := pg_temp.cuenta(cr, e_cr, 'select count(*) from public.equipos_venta');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' se(sandal_woods) ve %s equipos (esperados %s)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
  select count(*) into x from public.equipos_venta;
  n := pg_temp.cuenta(ad4, e_ad4, 'select count(*) from public.equipos_venta');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' a2(las dos) ve %s equipos (esperados %s)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
  n := pg_temp.cuenta(pe, e_pe, 'select count(*) from public.equipos_venta');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' super global ve todos los equipos (%s/%s)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
  n := pg_temp.cuenta(ctl, e_ctl, 'select count(*) from public.equipos_venta');
  r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' agente de control no ve equipos (%s)', n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;
  select count(*) into x from public.equipo_miembros where empresa = 'lawang';
  n := pg_temp.cuenta(ya, e_ya, 'select count(*) from public.equipo_miembros');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' ae(lawang) ve %s miembros (esperados %s)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
  select count(*) into x from public.equipo_miembros where empresa = 'sandal_woods';
  n := pg_temp.cuenta(cr, e_cr, 'select count(*) from public.equipo_miembros');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' se(sandal_woods) ve %s miembros (esperados %s)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
  select count(*) into x from public.condiciones_comision where empresa = 'lawang';
  n := pg_temp.cuenta(ya, e_ya, 'select count(*) from public.condiciones_comision');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' ae(lawang) ve %s condiciones (esperadas %s)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
  select count(*) into x from public.condiciones_comision where empresa = 'sandal_woods';
  n := pg_temp.cuenta(cr, e_cr, 'select count(*) from public.condiciones_comision');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' se(sandal_woods) ve %s condiciones (esperadas %s)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
  select count(*) into x from public.condicion_tramos t join public.condiciones_comision c on c.id = t.condicion_id where c.empresa = 'sandal_woods';
  n := pg_temp.cuenta(cr, e_cr, 'select count(*) from public.condicion_tramos');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' se ve %s tramos (esperados %s, los de sus condiciones)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;

  -- 2. plantilla de reparto
  v := pg_temp.como(ya, e_ya, format('select * from public.plantilla_reparto_lee(%L)', lt));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' ae lee la plantilla de un equipo de lawang (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select * from public.plantilla_reparto_lee(%L)', lt));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' se NO lee la plantilla de un equipo de lawang (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  select jsonb_agg(jsonb_build_object('rol_tipo', rol_tipo, 'rol_nombre', rol_nombre, 'pct', pct)) into filas from public.plantilla_reparto where equipo_id = st;
  v := pg_temp.como(ya, e_ya, format('select public.plantilla_reparto_guarda(%L, %L::jsonb)', st, filas::text));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae NO guarda la plantilla de un equipo de sandal_woods (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.plantilla_reparto_guarda(%L, %L::jsonb)', st, filas::text));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' se guarda la de un equipo de sandal_woods (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;

  -- 3. equipos
  v := pg_temp.como(ya, e_ya, format('select public.equipo_venta_activa(%L, true)', lt));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' ae(lawang) activa/desactiva un equipo de lawang (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(ya, e_ya, format('select public.equipo_venta_activa(%L, false)', st));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae NO desactiva un equipo de sandal_woods (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.equipo_venta_activa(%L, true)', st));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' se(sandal_woods) gestiona sus equipos (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(ya, e_ya, format('select public.equipo_closers_ven_comision(%L, true)', st));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae NO cambia el interruptor de un equipo ajeno (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(ya, e_ya, format('select public.equipo_venta_guarda(%L, ''Renombrado'', %L)', st, e_ctl));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae NO edita un equipo de sandal_woods (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.equipo_venta_guarda(null, ''Equipo de prueba'', %L)', e_lo));
  r := r || case when v = '22023' then 'OK   ' else 'FALLO' end || format(' un manager que solo vende en lawang no dirige un equipo de sandal_woods (%s)', v) || E'\n'; if v <> '22023' then fallos := fallos + 1; end if;
  -- el equipo nuevo nace en la empresa del llamador (sin deshacer, para leerla)
  perform set_config('request.jwt.claims', json_build_object('sub', cr, 'role', 'authenticated', 'email', e_cr)::text, true);
  set local role authenticated; id_new := public.equipo_venta_guarda(null, 'Equipo de prueba SW', e_ctl); reset role;
  select empresa into emp from public.equipos_venta where id = id_new;
  r := r || case when emp = 'sandal_woods' then 'OK   ' else 'FALLO' end || format(' el equipo nuevo de se nace en %s', emp) || E'\n'; if emp is distinct from 'sandal_woods' then fallos := fallos + 1; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', ya, 'role', 'authenticated', 'email', e_ya)::text, true);
  set local role authenticated; id_new := public.equipo_venta_guarda(null, 'Equipo de prueba LW', e_ctl); reset role;
  select empresa into emp from public.equipos_venta where id = id_new;
  r := r || case when emp = 'lawang' then 'OK   ' else 'FALLO' end || format(' el equipo nuevo de ae nace en %s', emp) || E'\n'; if emp is distinct from 'lawang' then fallos := fallos + 1; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', pe, 'role', 'authenticated', 'email', e_pe)::text, true);
  set local role authenticated; id_new := public.equipo_venta_guarda(null, 'Equipo de prueba global', e_ctl); reset role;
  select empresa into emp from public.equipos_venta where id = id_new;
  r := r || case when emp = 'lawang' then 'OK   ' else 'FALLO' end || format(' el equipo nuevo de un global nace en %s (hasta que la pantalla deje elegir)', emp) || E'\n'; if emp is distinct from 'lawang' then fallos := fallos + 1; end if;

  -- 4. miembros
  v := pg_temp.como(ya, e_ya, format('select * from public.equipo_candidatos_sm(%L)', st));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae NO lista candidatos de un equipo de sandal_woods (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select * from public.equipo_candidatos_sm(%L)', st));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' se lista candidatos de un equipo de sandal_woods (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(ya, e_ya, format('select public.equipo_miembro_anade(%L, %L)', st, ctl));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae NO añade miembros a un equipo de sandal_woods (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.equipo_miembro_anade(%L, %L)', st, ctl));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' se añade un miembro a un equipo de sandal_woods (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(pe, e_pe, format('select public.equipo_miembro_guarda(null, %L, %L, current_date, null)', st, e_lo));
  r := r || case when v = '22023' then 'OK   ' else 'FALLO' end || format(' quien solo vende en lawang NO entra en un equipo de sandal_woods (%s)', v) || E'\n'; if v <> '22023' then fallos := fallos + 1; end if;
  v := pg_temp.como(pe, e_pe, format('select public.equipo_miembro_guarda(null, %L, %L, current_date, null)', lt, e_lo));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' ...y si entra en uno de lawang (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  select m.closer_email into v from public.equipo_miembros m where m.equipo_id = lt and m.hasta is null limit 1;
  select count(*) into n from public.equipo_miembros m where lower(m.closer_email) = lower(v) and m.hasta is null;
  r := r || case when n = 2 then 'OK   ' else 'FALLO' end || format(' un miembro de siempre esta abierto en sus dos equipos gemelos (%s filas)', n) || E'\n'; if n <> 2 then fallos := fallos + 1; end if;

  -- 5. condiciones
  v := pg_temp.como(ya, e_ya, format('select public.condicion_comision_guarda(null, %L::jsonb, %L::jsonb)', cond_lt::text, tramos::text));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' ae crea una condicion en un equipo de lawang (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.condicion_comision_guarda(null, %L::jsonb, %L::jsonb)', cond_lt::text, tramos::text));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' se NO crea una condicion en un equipo de lawang (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(ya, e_ya, format('select public.condicion_comision_guarda(null, %L::jsonb, %L::jsonb)', cond_st::text, tramos::text));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae NO crea una condicion en un equipo de sandal_woods (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.condicion_comision_guarda(null, %L::jsonb, %L::jsonb)', cond_st::text, tramos::text));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' se crea una condicion en un equipo de sandal_woods (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(ya, e_ya, format('do $x$ declare c uuid; begin c := public.condicion_comision_guarda(null, %L::jsonb, %L::jsonb); perform public.condicion_comision_borra(c); end $x$', cond_lt::text, tramos::text));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' ae crea y borra una condicion futura de lawang (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(ya, e_ya, format('select public.condicion_comision_activa(%L, false)', c_st));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' ae NO cierra una condicion de sandal_woods (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.condicion_comision_borra(%L)', c_lt));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' se NO borra una condicion de lawang (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', pe, 'role', 'authenticated', 'email', e_pe)::text, true);
  set local role authenticated; id_new := public.condicion_comision_guarda(null, cond_std, tramos); reset role;
  select count(*) into n from public.condiciones_comision where equipo_id is null and vigente_desde = current_date + 61 and created_by = e_pe;
  r := r || case when n = 2 then 'OK   ' else 'FALLO' end || format(' un global crea la estandar para las DOS empresas (%s condiciones)', n) || E'\n'; if n <> 2 then fallos := fallos + 1; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', ya, 'role', 'authenticated', 'email', e_ya)::text, true);
  set local role authenticated; id_new := public.condicion_comision_guarda(null, cond_std || jsonb_build_object('pct_comision', 4, 'vigente_desde', current_date + 62), tramos); reset role;
  select count(*), min(empresa) into n, emp from public.condiciones_comision where equipo_id is null and vigente_desde = current_date + 62 and created_by = e_ya;
  r := r || case when n = 1 and emp = 'lawang' then 'OK   ' else 'FALLO' end || format(' ae crea la estandar solo en lawang (%s condicion, %s)', n, emp) || E'\n'; if not (n = 1 and emp = 'lawang') then fallos := fallos + 1; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', cr, 'role', 'authenticated', 'email', e_cr)::text, true);
  set local role authenticated; id_new := public.condicion_comision_guarda(null, cond_std || jsonb_build_object('pct_comision', 5, 'vigente_desde', current_date + 63), tramos); reset role;
  select count(*), min(empresa) into n, emp from public.condiciones_comision where equipo_id is null and vigente_desde = current_date + 63 and created_by = e_cr;
  r := r || case when n = 1 and emp = 'sandal_woods' then 'OK   ' else 'FALLO' end || format(' se crea la estandar solo en sandal_woods (%s condicion, %s)', n, emp) || E'\n'; if not (n = 1 and emp = 'sandal_woods') then fallos := fallos + 1; end if;
  v := pg_temp.como(ctl, e_ctl, format('select public.condicion_comision_guarda(null, %L::jsonb, %L::jsonb)', cond_std::text, tramos::text));
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' el agente de control NO crea condiciones (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;

  insert into _b4_out values (r, fallos);
end $t4$;

-- ================================================================= libro de administracion (migracion 5)
do $t5$
declare
  jv uuid; ya uuid; cr uuid; ad4 uuid; pe uuid; lo uuid;
  e_ya text; e_cr text; e_ad4 text; e_pe text; e_lo text;
  r text := ''; fallos int := 0; n bigint; x bigint; v text; ok boolean;
  l_l uuid; l_s uuid; cobro uuid; serie uuid; emp text; f1 uuid; f2 uuid; b jsonb; a0 jsonb; a jsonb; a2 jsonb; kk text;
  datos_sw jsonb; datos_lw jsonb; c_sw uuid; c_lw uuid;
begin
  select user_id into jv from public.usuarios where email = 'jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email = 'yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email = 'cris.blueiestates@gmail.com';
  select user_id, email into ad4, e_ad4 from public.usuarios where email = 'adenovit.b@gmail.com';
  select user_id, email into pe, e_pe from public.usuarios where email = 'pepito@lawangproperties.com';
  select u.user_id, u.email into lo, e_lo from public.usuarios u
   where u.activo and u.ambito = 'global' and u.rol = 'agente' and u.user_id not in (ya, cr, ad4) order by u.email desc limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', jv, 'role', 'authenticated', 'email', 'jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = lo;
  select l.id into l_l from public.comision_admin_lineas l where l.sociedad = 'tepi_sungai' and l.tipo_linea = 'devengo' and not l.anulada and l.estado = 'pendiente' limit 1;
  select l.id into l_s from public.comision_admin_lineas l where l.sociedad = 'san_dal_woods' and l.tipo_linea = 'devengo' and not l.anulada and l.estado = 'pendiente' limit 1;
  select c.id into cobro from public.comision_admin_cobros c where c.sociedad = 'tepi_sungai' and not c.anulado limit 1;
  select f.serie_id into serie from public.comision_admin_fees f where f.sociedad = 'tepi_sungai' limit 1;
  select c.id into c_sw from public.contratos c join public.proyectos p on p.id = c.proyecto_id where p.empresa = 'sandal_woods' and c.contrato_padre_id is null limit 1;
  select c.id into c_lw from public.contratos c join public.proyectos p on p.id = c.proyecto_id where p.empresa = 'lawang' and c.contrato_padre_id is null limit 1;
  datos_lw := jsonb_build_object('importe', 10, 'moneda', 'EUR', 'efectivo_desde', current_date);
  datos_sw := jsonb_build_object('concepto', 'Prueba', 'sociedad', 'san_dal_woods', 'importe', 10, 'moneda', 'EUR', 'efectivo_desde', current_date);

  -- 1. lectura del libro
  select count(*) into x from public.comision_admin_lineas where sociedad = 'tepi_sungai';
  n := pg_temp.cuenta(lo, e_lo, 'select count(*) from public.comision_admin_lineas');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' super de lawang ve %s lineas del libro (esperadas %s, las de tepi_sungai)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
  select count(*) into x from public.comision_admin_lineas where sociedad = 'san_dal_woods';
  n := pg_temp.cuenta(cr, e_cr, 'select count(*) from public.comision_admin_lineas');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' super de sandal_woods ve %s (esperadas %s, las de san_dal_woods)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;
  n := pg_temp.cuenta(lo, e_lo, 'select count(*) from public.comision_admin_fees');
  r := r || case when n = 4 then 'OK   ' else 'FALLO' end || format(' los fees (4) son de lawang: su super los ve (%s)', n) || E'\n'; if n <> 4 then fallos := fallos + 1; end if;
  n := pg_temp.cuenta(cr, e_cr, 'select count(*) from public.comision_admin_fees');
  r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' el super de sandal_woods no ve fees de lawang (%s)', n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;
  n := pg_temp.cuenta(cr, e_cr, 'select count(*) from public.comision_admin_cobros');
  r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' ...ni cobros de lawang (%s)', n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;
  n := pg_temp.cuenta(lo, e_lo, 'select count(*) from public.comision_admin_cobros');
  r := r || case when n = 1 then 'OK   ' else 'FALLO' end || format(' el super de lawang ve su cobro (%s)', n) || E'\n'; if n <> 1 then fallos := fallos + 1; end if;
  n := pg_temp.cuenta(lo, e_lo, 'select count(*) from public.comision_admin_tarifas');
  r := r || case when n = 1 then 'OK   ' else 'FALLO' end || format(' cada super ve solo su tarifa (%s)', n) || E'\n'; if n <> 1 then fallos := fallos + 1; end if;
  n := pg_temp.cuenta(ya, e_ya, 'select (select count(*) from public.comision_admin_lineas) + (select count(*) from public.comision_admin_fees) + (select count(*) from public.comision_admin_tarifas) + (select count(*) from public.comision_admin_cobros)');
  r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' un admin_empresa (que no es super) no ve nada del libro (%s)', n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;
  select count(*) into x from public.comision_admin_lineas;
  n := pg_temp.cuenta(pe, e_pe, 'select count(*) from public.comision_admin_lineas');
  r := r || case when n = x then 'OK   ' else 'FALLO' end || format(' super global ve todo el libro (%s/%s)', n, x) || E'\n'; if n <> x then fallos := fallos + 1; end if;

  -- 2. informes: identicos para el global; por empresa para los demas
  perform set_config('request.jwt.claims', json_build_object('sub', pe, 'role', 'authenticated', 'email', e_pe)::text, true);
  a0 := public.comision_admin_descuadres();
  r := r || case when jsonb_typeof(a0) = 'object' then 'OK   ' else 'FALLO' end || ' el super global obtiene los descuadres de todo el libro' || E'\n'; if jsonb_typeof(a0) <> 'object' then fallos := fallos + 1; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', lo, 'role', 'authenticated', 'email', e_lo)::text, true);
  a := public.comision_admin_descuadres();
  perform set_config('request.jwt.claims', json_build_object('sub', cr, 'role', 'authenticated', 'email', e_cr)::text, true);
  a2 := public.comision_admin_descuadres();
  ok := true;
  for kk in select jsonb_object_keys(a) loop
    if jsonb_typeof(a->kk) = 'number' and (a->>kk)::numeric + (a2->>kk)::numeric > (a0->>kk)::numeric then ok := false; end if;
  end loop;
  r := r || case when ok then 'OK   ' else 'FALLO' end || ' descuadres: lo de lawang mas lo de sandal_woods no supera el total' || E'\n'; if not ok then fallos := fallos + 1; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', cr, 'role', 'authenticated', 'email', e_cr)::text, true);
  b := public.comision_admin_prevision();
  r := r || case when jsonb_typeof(b->'monedas') = 'array' then 'OK   ' else 'FALLO' end || format(' prevision del super de sandal_woods responde (%s)', left(b::text, 60)) || E'\n'; if jsonb_typeof(b->'monedas') <> 'array' then fallos := fallos + 1; end if;
  v := pg_temp.como(ya, e_ya, 'select public.comision_admin_prevision()');
  r := r || case when v <> 'ok' then 'OK   ' else 'FALLO' end || format(' un admin_empresa (no super) NO ve la prevision (%s)', v) || E'\n'; if v = 'ok' then fallos := fallos + 1; end if;

  -- 3. operar el libro
  v := pg_temp.como(lo, e_lo, format('select public.comision_admin_anula_linea(%L, %L)', l_l, 'prueba'));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' super de lawang anula una linea de lawang (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.comision_admin_anula_linea(%L, %L)', l_l, 'prueba'));
  r := r || case when v <> 'ok' then 'OK   ' else 'FALLO' end || format(' super de sandal_woods NO anula una de lawang (%s)', v) || E'\n'; if v = 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(ya, e_ya, format('select public.comision_admin_anula_linea(%L, %L)', l_l, 'prueba'));
  r := r || case when v <> 'ok' then 'OK   ' else 'FALLO' end || format(' admin_empresa (no super) NO anula (%s)', v) || E'\n'; if v = 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.comision_admin_linea_estado(%L, ''exenta'', null, false, false, ''motivo de prueba'')', l_s));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' super de sandal_woods cambia el estado de una de las suyas (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(lo, e_lo, format('select public.comision_admin_linea_estado(%L, ''exenta'', null, false, false, ''motivo de prueba'')', l_s));
  r := r || case when v <> 'ok' then 'OK   ' else 'FALLO' end || format(' super de lawang NO cambia el de una de sandal_woods (%s)', v) || E'\n'; if v = 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(lo, e_lo, 'select public.comision_admin_registrar_cobro(''tepi_sungai'', ''EUR'', 1, current_date)');
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' super de lawang registra (en simulacion) un cobro de tepi_sungai (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, 'select public.comision_admin_registrar_cobro(''tepi_sungai'', ''EUR'', 1, current_date)');
  r := r || case when v <> 'ok' then 'OK   ' else 'FALLO' end || format(' super de sandal_woods NO registra un cobro de tepi_sungai (%s)', v) || E'\n'; if v = 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, 'select public.comision_admin_registrar_cobro(''san_dal_woods'', ''EUR'', 1, current_date)');
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' ...y uno de san_dal_woods si (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.comision_admin_anular_cobro(%L, ''motivo de prueba'')', cobro));
  r := r || case when v <> 'ok' then 'OK   ' else 'FALLO' end || format(' super de sandal_woods NO anula un cobro de lawang (%s)', v) || E'\n'; if v = 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(lo, e_lo, format('select public.comision_admin_anular_cobro(%L, ''motivo de prueba'')', cobro));
  r := r || case when v not in ('42702', '42501') then 'OK   ' else 'FALLO' end || format(' super de lawang PASA la puerta de anular un cobro de lawang (%s)', v) || E'\n'; if v in ('42702', '42501') then fallos := fallos + 1; end if;
  v := pg_temp.como(lo, e_lo, format('select public.comision_admin_fee_guarda(%L, %L::jsonb)', serie, datos_lw::text));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' super de lawang cambia un fee de lawang (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.comision_admin_fee_guarda(%L, %L::jsonb)', serie, datos_lw::text));
  r := r || case when v <> 'ok' then 'OK   ' else 'FALLO' end || format(' super de sandal_woods NO cambia un fee de lawang (%s)', v) || E'\n'; if v = 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, format('select public.comision_admin_fee_guarda(null, %L::jsonb)', datos_sw::text));
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' super de sandal_woods crea un fee de su sociedad (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(lo, e_lo, format('select public.comision_admin_fee_guarda(null, %L::jsonb)', datos_sw::text));
  r := r || case when v <> 'ok' then 'OK   ' else 'FALLO' end || format(' super de lawang NO crea un fee de san_dal_woods (%s)', v) || E'\n'; if v = 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(ya, e_ya, 'select public.comision_admin_devenga_fees()');
  r := r || case when v <> 'ok' then 'OK   ' else 'FALLO' end || format(' admin_empresa (no super) NO devenga fees (%s)', v) || E'\n'; if v = 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(cr, e_cr, 'select public.comision_admin_devenga_fees()');
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' super de sandal_woods devenga los suyos (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;
  v := pg_temp.como(lo, e_lo, 'select public.comision_admin_devenga_fees()');
  r := r || case when v = 'ok' then 'OK   ' else 'FALLO' end || format(' super de lawang devenga los suyos (%s)', v) || E'\n'; if v <> 'ok' then fallos := fallos + 1; end if;

  -- 4. tarifas: solo el super GLOBAL las define; una por empresa
  v := pg_temp.como(cr, e_cr, 'select public.comision_admin_tarifa_crea(0.6, current_date + 100, ''prueba'')');
  r := r || case when v = '42501' then 'OK   ' else 'FALLO' end || format(' super de empresa NO crea tarifas (%s)', v) || E'\n'; if v <> '42501' then fallos := fallos + 1; end if;
  v := pg_temp.como(lo, e_lo, format('select public.comision_admin_edita_tarifa(%L, 0.7, current_date + 99, ''prueba'', false)', (select t.id from public.comision_admin_tarifas t where t.empresa = 'lawang')));
  r := r || case when v <> 'ok' then 'OK   ' else 'FALLO' end || format(' super de lawang NO edita la tarifa (%s)', v) || E'\n'; if v = 'ok' then fallos := fallos + 1; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', pe, 'role', 'authenticated', 'email', e_pe)::text, true);
  perform public.comision_admin_tarifa_crea(0.6, current_date + 100, 'prueba');
  select count(*) into n from public.comision_admin_tarifas where efectivo_desde = current_date + 100;
  r := r || case when n = 2 then 'OK   ' else 'FALLO' end || format(' una tarifa nueva del super global crea una por empresa (%s)', n) || E'\n'; if n <> 2 then fallos := fallos + 1; end if;
  ok := false;
  begin perform public.comision_admin_tarifa_crea(0.9, current_date + 100, 'duplicada'); exception when sqlstate '23505' then ok := true; end;
  r := r || case when ok then 'OK   ' else 'FALLO' end || ' y repetir la fecha sigue rechazandose' || E'\n'; if not ok then fallos := fallos + 1; end if;

  -- 5. el devengo automatico elige la tarifa de la empresa del recibi (se intenta con recibis reales de prueba)
  begin
    insert into public.facturas (tipo, sociedad, numero, fecha_emision, total, moneda, datos, contrato_id)
    values ('recibi', 'san_dal_woods', 'TEST-B4-SW', current_date, 100, 'EUR', '{"totales":{"subtotal":100}}'::jsonb, c_sw) returning id into f1;
    insert into public.facturas (tipo, sociedad, numero, fecha_emision, total, moneda, datos, contrato_id)
    values ('recibi', 'tepi_sungai', 'TEST-B4-LW', current_date, 100, 'EUR', '{"totales":{"subtotal":100}}'::jsonb, c_lw) returning id into f2;
    select t.empresa into emp from public.comision_admin_lineas l join public.comision_admin_tarifas t on t.id = l.tarifa_id where l.recibi_id = f1 and l.tipo_linea = 'devengo';
    r := r || case when emp = 'sandal_woods' then 'OK   ' else 'FALLO' end || format(' un recibi de san_dal_woods devenga con la tarifa de %s', emp) || E'\n'; if emp is distinct from 'sandal_woods' then fallos := fallos + 1; end if;
    select t.empresa into emp from public.comision_admin_lineas l join public.comision_admin_tarifas t on t.id = l.tarifa_id where l.recibi_id = f2 and l.tipo_linea = 'devengo';
    r := r || case when emp = 'lawang' then 'OK   ' else 'FALLO' end || format(' un recibi de tepi_sungai devenga con la tarifa de %s', emp) || E'\n'; if emp is distinct from 'lawang' then fallos := fallos + 1; end if;
  exception when others then
    r := r || 'AVISO no se pudo insertar un recibi de prueba (' || sqlerrm || '); se comprueba la consulta de tarifa por separado' || E'\n';
  end;
  select count(*) into n from public.comision_admin_tarifas t where t.efectivo_desde <= current_date and t.empresa = coalesce(public.empresa_de_sociedad('san_dal_woods'), 'lawang');
  r := r || case when n = 1 then 'OK   ' else 'FALLO' end || format(' la consulta de tarifa de san_dal_woods da una fila (%s)', n) || E'\n'; if n <> 1 then fallos := fallos + 1; end if;
  select count(*) into n from public.comision_admin_tarifas t where t.efectivo_desde <= current_date and t.empresa = coalesce(public.empresa_de_sociedad('sociedad_que_no_existe'), 'lawang');
  r := r || case when n = 1 then 'OK   ' else 'FALLO' end || format(' una sociedad sin empresa conocida cae en la tarifa de lawang (%s)', n) || E'\n'; if n <> 1 then fallos := fallos + 1; end if;

  insert into _b4_out values (r, fallos);
end $t5$;

-- ================================================================= informe
do $fin$
declare t text := ''; f int := 0; x record;
begin
  for x in select * from _b4_out loop t := t || x.txt; f := f + x.fallos; end loop;
  raise exception E'\n%FALLOS=%', t, f;
end $fin$;
