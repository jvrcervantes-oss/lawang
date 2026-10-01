-- Prueba LAW-482 / LAW-483 (solo lee y deja todo como estaba: termina en rollback). Correr con la migración 20261001090500/090600 YA aplicada.
-- Sale con error en el primer fallo; si llega al final imprime 'OK'.
begin;

-- 1. Estructura: las tres RPC llevan la guarda y el reconciliador la marca del informativo.
do $t$
declare f text;
begin
  foreach f in array array['public.condicion_comision_guarda(uuid,jsonb,jsonb,text)','public.condicion_comision_activa(uuid,boolean)','public.condicion_comision_borra(uuid)'] loop
    if position('_condicion_a_su_favor' in pg_get_functiondef(f::regprocedure)) = 0 then raise exception 'FALLA: % sin guarda', f; end if;
  end loop;
  if position('F9M5-informativo' in pg_get_functiondef('public.comisiones_reconciliar(uuid,boolean,jsonb)'::regprocedure)) = 0 then
    raise exception 'FALLA: reconciliador sin la rama del informativo';
  end if;
  -- la rama de edicion de guarda comprueba el closer NUEVO y el viejo
  if position('array[v_closer_nuevo, v_old.closer_email]' in pg_get_functiondef('public.condicion_comision_guarda(uuid,jsonb,jsonb,text)'::regprocedure)) = 0 then
    raise exception 'FALLA: la edicion no comprueba v_closer_nuevo';
  end if;
  -- la casilla comisiones_reparto (LAW-483, decisión del owner 1-oct): la exige _condicion_es_mia y el v_admin de guarda
  if position('comisiones_reparto' in pg_get_functiondef('public._condicion_es_mia(text,uuid)'::regprocedure)) = 0 then
    raise exception 'FALLA: _condicion_es_mia no exige la casilla';
  end if;
  if position('v_admin  boolean := public.es_admin() and public.puede' in pg_get_functiondef('public.condicion_comision_guarda(uuid,jsonb,jsonb,text)'::regprocedure)) = 0 then
    raise exception 'FALLA: v_admin de guarda no esta ligado a la casilla';
  end if;
  -- el helper no es llamable desde fuera
  if has_function_privilege('authenticated', 'public._condicion_a_su_favor(text[],text,uuid)', 'execute') then raise exception 'FALLA: helper expuesto a authenticated'; end if;
  if has_function_privilege('anon', 'public._condicion_a_su_favor(text[],text,uuid)', 'execute') then raise exception 'FALLA: helper expuesto a anon'; end if;
end $t$;

-- 2. Comportamiento del helper con un email simulado en el JWT.
select set_config('request.jwt.claims', '{"email":"yo@prueba.test","role":"authenticated"}', true);
do $t$
begin
  -- su email como closer de la condicion -> a su favor
  if not public._condicion_a_su_favor(array['yo@prueba.test'], 'closer', null) then raise exception 'FALLA: su email no cuenta'; end if;
  -- el de otra persona -> no
  if public._condicion_a_su_favor(array['otro@prueba.test'], 'closer', null) then raise exception 'FALLA: el de otro cuenta'; end if;
  -- sin equipo ni closer (nivel estandar) -> no
  if public._condicion_a_su_favor(array[null::text], 'estandar', null) then raise exception 'FALLA: estandar sin equipo cuenta'; end if;
  -- reasignar de otro a uno mismo en edicion: el closer NUEVO va en el array -> a su favor
  if not public._condicion_a_su_favor(array['yo@prueba.test', 'otro@prueba.test'], 'closer', null) then raise exception 'FALLA: reasignarse una condicion ajena pasa'; end if;
end $t$;
-- sin sesion (sin email) nunca es «a su favor» (service_role/cron no pasan por estas RPC)
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $t$
begin
  if public._condicion_a_su_favor(array['yo@prueba.test'], 'closer', null) then raise exception 'FALLA: sin email devuelve true'; end if;
end $t$;

-- 3. PENDIENTE de correr con datos reales (no se puede montar sin escribir en tablas de produccion): SM miembro de su propio equipo (bloquea),
--    SM no miembro (pasa), super admin (pasa), manager congelado de venta viva (bloquea), y el caso LAW-482: devengo closer 'pagada' con cambio
--    de base +/- -> sin fila nueva en comisiones_diferencias, importe actualizado, apunte en comisiones_ajustes_log.

select 'OK' as resultado;
rollback;
