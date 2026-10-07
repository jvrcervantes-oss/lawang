-- Prueba (se revierte sola: acaba en RAISE) de LAW-497 — 7-oct-2026.
-- Guarda «vendida/cobrada exige el cobro» (trg_unidad_vendida_exige_cobro) y el historial de
-- estado (trg_unidad_estado_al_historial y _alta). Lanzar como postgres (MCP o SQL Editor).
-- Crea una parcela de prueba ZZ-LAW497 en Bonian Village y toca C5 y REC00156 dentro de la
-- transaccion: todo se deshace con el RAISE final. Los avisos que disparan van por tablas,
-- tambien deshechos (sin http sincrono en esta base).
-- Esperado (cualquier «MAL» es fallo):
--   1:alta_vendida_rechazada 2:paso_a_vendida_rechazado 3:cambio_apuntado 4:excepcion_apuntada
--   5:alta_con_excepcion_apuntada 6:cambio_por_trigger_apuntado 7:C5_sube_con_duplicado_vivo
--   8:C5_no_baja_al_anular(la escalera no baja: decision del owner) 9:funciones_sin_permiso_anon

do $$
declare
  v_res text := ''; v_test uuid; v_alta uuid; v_c5 uuid; v_rec uuid; v_rp uuid; v_est text; v_n int;
begin
  -- 1: alta directa en vendida
  begin
    insert into public.unidades (codigo, proyecto, tipo, precio_suelo, estado)
    values ('ZZ-LAW497-1', 'Bonian Village', 'parcela', 1000, 'vendida');
    v_res := v_res || '1:MAL ';
  exception when sqlstate '23514' then v_res := v_res || '1:alta_vendida_rechazada ';
  end;

  -- 2: paso a vendida sin cobro
  insert into public.unidades (codigo, proyecto, tipo, precio_suelo, estado)
  values ('ZZ-LAW497-2', 'Bonian Village', 'parcela', 1000, 'disponible') returning id into v_test;
  begin
    update public.unidades set estado = 'vendida' where id = v_test;
    v_res := v_res || '2:MAL ';
  exception when sqlstate '23514' then v_res := v_res || '2:paso_a_vendida_rechazado ';
  end;

  -- 3: un cambio permitido deja fila
  update public.unidades set estado = 'bloqueada' where id = v_test;
  set constraints all immediate;
  select count(*) into v_n from public.unidades_log
   where unidad_id = v_test and antes->>'estado' = 'disponible' and despues->>'estado' = 'bloqueada';
  v_res := v_res || case when v_n = 1 then '3:cambio_apuntado ' else '3:MAL(' || v_n || ') ' end;
  set constraints all deferred;

  -- 4: excepcion del owner en un cambio
  perform set_config('app.unidad_estado_excepcion', 'on', true);
  update public.unidades set estado = 'vendida' where id = v_test;
  -- 5: excepcion del owner en un alta
  insert into public.unidades (codigo, proyecto, tipo, precio_suelo, estado)
  values ('ZZ-LAW497-5', 'Bonian Village', 'parcela', 1000, 'vendida') returning id into v_alta;
  set constraints all immediate;
  select count(*) into v_n from public.unidades_log where unidad_id = v_test and motivo = 'excepcion decidida por el owner';
  v_res := v_res || case when v_n = 1 then '4:excepcion_apuntada ' else '4:MAL(' || v_n || ') ' end;
  select count(*) into v_n from public.unidades_log where unidad_id = v_alta and antes is null and despues->>'estado' = 'vendida';
  v_res := v_res || case when v_n = 1 then '5:alta_con_excepcion_apuntada ' else '5:MAL(' || v_n || ') ' end;
  set constraints all deferred;
  perform set_config('app.unidad_estado_excepcion', '', true);

  -- 6: estado cambiado por un trigger BEFORE (libera_unidad_sin_contrato), sin nombrar estado
  select id into v_rp from public.contratos where numero = 'RP00140';
  update public.unidades set estado = 'reservada', contrato_id = v_rp where id = v_test;
  update public.unidades set contrato_id = null where id = v_test;
  set constraints all immediate;
  select count(*) into v_n from public.unidades_log
   where unidad_id = v_test and antes->>'estado' = 'reservada' and despues->>'estado' = 'disponible';
  v_res := v_res || case when v_n = 1 then '6:cambio_por_trigger_apuntado ' else '6:MAL(' || v_n || ') ' end;
  set constraints all deferred;

  -- 7 y 8: el camino real de C5 (6-oct): sube con REC00156 viva, no baja al anularla
  select id into v_c5 from public.unidades where proyecto = 'Bonian Village' and codigo = 'C5';
  select id into v_rec from public.facturas where numero = 'REC00156';
  update public.unidades set estado = 'bloqueada' where id = v_c5;
  update public.facturas set anulada = false where id = v_rec;
  select estado into v_est from public.unidades where id = v_c5;
  v_res := v_res || case when v_est = 'vendida' then '7:C5_sube_con_duplicado_vivo ' else '7:MAL(' || v_est || ') ' end;
  update public.facturas set anulada = true where id = v_rec;
  select estado into v_est from public.unidades where id = v_c5;
  v_res := v_res || case when v_est = 'vendida' then '8:C5_no_baja_al_anular ' else '8:CAMBIO(' || v_est || ') ' end;

  -- 9: ninguna de las funciones nuevas es ejecutable por anon/authenticated
  v_res := v_res || case when has_function_privilege('anon', 'public.unidad_cumple_estado(uuid,text,numeric,numeric)', 'execute')
                           or has_function_privilege('authenticated', 'public.unidad_cumple_estado(uuid,text,numeric,numeric)', 'execute')
                           or has_function_privilege('authenticated', 'public.trg_unidad_vendida_exige_cobro()', 'execute')
                           or has_function_privilege('authenticated', 'public.trg_unidad_estado_al_historial()', 'execute')
                         then '9:MAL ' else '9:funciones_sin_permiso_anon ' end;

  raise exception 'RESULTADO: %', v_res;
end $$;
