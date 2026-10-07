-- destructivo-ok: prueba en una transaccion que acaba en RAISE; se deshace entera
-- Prueba (se revierte sola: acaba en RAISE) de LAW-497c — 7-oct-2026.
-- Bajada automatica «vendida»/«cobrada» -> «bloqueada» cuando un cobro deja de cubrir el suelo, SOLO con el
-- Bloqueo de Parcela firmado. Lanzar como postgres (MCP o SQL Editor). Toca filas reales de
-- Bonian C5 (RP00140), Tamarind W3 (RP00069/RP00070), Mejan S7 A2 y Sumba Hills SH-189 (RP00200)
-- dentro de la transaccion: todo se deshace con el RAISE final.
-- Datos del 7-oct: C5 tiene 1.000 + REC00157 20.123 + REC00158 20.077 = 41.200 de suelo cobrado.
-- Esperado (cualquier «MAL» es fallo):
--   1:con_bloqueo_baja 2:bajada_apuntada_con_motivo 3:vuelve_a_subir_al_reactivar
--   4:cobro_que_no_rompe_el_suelo_no_toca 5:sin_bloqueo_no_baja(Tamarind x3) 6:sin_contrato_no_baja(Mejan A2)
--   7a:recibi_movido_baja_el_origen 7b:vuelve_y_sube 7c:recibi_borrado_baja 8:cobrada_sin_cobro_baja
--   9:funciones_sin_permiso_anon 10a/10b:precio_suelo 11/11b:factura_anulada_revisa 12:sin_ver_el_cobro_no_baja
-- (8 y 10-12 desde LAW-497d, migracion 20261007..._law497d)

do $$
declare
  v_res text := ''; v_c5 uuid; v_r158 uuid; v_r156 uuid; v_est text; v_n int; v_otro uuid; v_c record;
begin
  select id into v_c5 from public.unidades where proyecto = 'Bonian Village' and codigo = 'C5';
  select id into v_r158 from public.facturas where numero = 'REC00158';
  select id into v_r156 from public.facturas where numero = 'REC00156';
  select estado into v_est from public.unidades where id = v_c5;
  if v_est <> 'vendida' or not public.unidad_cumple_estado(v_c5, 'vendida', null, 41200) then
    raise exception 'PRECONDICION: C5 no esta en vendida con el suelo cubierto (estado %)', v_est;
  end if;

  -- 1 y 2: anular el ultimo cobro (Bloqueo RP00140 firmado) la baja, con fila y motivo
  update public.facturas set anulada = true where id = v_r158;
  select estado into v_est from public.unidades where id = v_c5;
  v_res := v_res || case when v_est = 'bloqueada' then '1:con_bloqueo_baja ' else '1:MAL(' || v_est || ') ' end;
  set constraints all immediate;
  select count(*) into v_n from public.unidades_log
   where unidad_id = v_c5 and antes->>'estado' = 'vendida' and despues->>'estado' = 'bloqueada'
     and motivo like 'vuelve a bloqueada:%LAW-497%' and en = now();
  v_res := v_res || case when v_n = 1 then '2:bajada_apuntada_con_motivo ' else '2:MAL(' || v_n || ') ' end;
  set constraints all deferred;

  -- 3: reactivarlo la vuelve a subir (la regla de subida no cambia)
  update public.facturas set anulada = false where id = v_r158;
  select estado into v_est from public.unidades where id = v_c5;
  v_res := v_res || case when v_est = 'vendida' then '3:vuelve_a_subir_al_reactivar ' else '3:MAL(' || v_est || ') ' end;

  -- 4: un cobro que entra y se anula sin romper el suelo (el duplicado REC00156): ni cambio ni fila
  set constraints all immediate;
  select count(*) into v_n from public.unidades_log where unidad_id = v_c5;
  set constraints all deferred;
  update public.facturas set anulada = false where id = v_r156;
  update public.facturas set anulada = true where id = v_r156;
  set constraints all immediate;
  select estado into v_est from public.unidades where id = v_c5;
  v_res := v_res || case when v_est = 'vendida'
                          and (select count(*) from public.unidades_log where unidad_id = v_c5) = v_n
                         then '4:cobro_que_no_rompe_el_suelo_no_toca ' else '4:MAL(' || v_est || ') ' end;
  set constraints all deferred;

  -- 5: sin Bloqueo firmado no baja (datos reales: Tamarind W3-C1/C2/C3, vendida con 0 cobrado)
  perform public.avanza_unidad_por_cobro(c.id) from public.contratos c where c.numero in ('RP00069', 'RP00070');
  select count(*) into v_n from public.unidades
   where proyecto like 'Tamarind Rise%' and codigo in ('W3 - C1', 'W3 - C2', 'W3 - C3') and estado = 'vendida';
  v_res := v_res || case when v_n = 3 then '5:sin_bloqueo_no_baja ' else '5:MAL(' || v_n || ') ' end;

  -- 6: sin contrato no hay nada que la mueva (Mejan Village S7 A2)
  select estado into v_est from public.unidades where proyecto = 'Mejan Village S7' and codigo = 'A2';
  v_res := v_res || case when v_est = 'vendida' then '6:sin_contrato_no_baja ' else '6:MAL(' || coalesce(v_est, 'null') || ') ' end;

  -- 10 (LAW-497d): subir el precio del suelo por encima de lo cobrado la baja; devolverlo la sube
  update public.unidades set precio_suelo = 41201 where id = v_c5;
  select estado into v_est from public.unidades where id = v_c5;
  v_res := v_res || case when v_est = 'bloqueada' then '10a:precio_suelo_sube_y_baja ' else '10a:MAL(' || v_est || ') ' end;
  update public.unidades set precio_suelo = 41200 where id = v_c5;
  select estado into v_est from public.unidades where id = v_c5;
  v_res := v_res || case when v_est = 'vendida' then '10b:precio_devuelto_sube ' else '10b:MAL(' || v_est || ') ' end;

  -- 11 (LAW-497d): anular la FACTURA a la que esta aplicado REC00158 (INV00198) revisa la parcela:
  -- el estado tiene que quedar coherente con lo cobrado, sea cual sea
  update public.facturas set anulada = true where numero = 'INV00198';
  select estado into v_est from public.unidades where id = v_c5;
  v_res := v_res || case when v_est = case when public.unidad_cumple_estado(v_c5, 'vendida', null, 41200)
                                           then 'vendida' else 'bloqueada' end
                         then '11:factura_anulada_revisa(' || v_est || ') ' else '11:MAL(' || v_est || ') ' end;
  update public.facturas set anulada = false where numero = 'INV00198';
  select estado into v_est from public.unidades where id = v_c5;
  v_res := v_res || case when v_est = 'vendida' then '11b:reactivada_vendida ' else '11b:MAL(' || v_est || ') ' end;

  -- 12 (LAW-497d): si quien dispara la revision no ve el cobro (contrato_cobrado le da 0), no baja
  perform set_config('request.jwt.claims',
    json_build_object('role', 'authenticated', 'sub', gen_random_uuid())::text, true);
  update public.facturas set anulada = true where id = v_r158;
  select estado into v_est from public.unidades where id = v_c5;
  v_res := v_res || case when v_est = 'vendida' then '12:sin_ver_el_cobro_no_baja ' else '12:MAL(' || v_est || ') ' end;
  perform set_config('request.jwt.claims', '', true);
  update public.facturas set anulada = false where id = v_r158;

  -- 7: un recibi movido de contrato baja la parcela del contrato de ORIGEN, y uno borrado tambien.
  -- REC00158 esta aplicado a INV00198 (RP00140): con la aplicacion viva el cobro sigue contando
  -- para RP00140 aunque el recibi se mueva, asi que primero se quita la aplicacion.
  delete from public.recibi_aplicaciones where recibi_id = v_r158;
  select id into v_otro from public.contratos where numero = 'RP00069';
  update public.facturas set contrato_id = v_otro where id = v_r158;
  select estado into v_est from public.unidades where id = v_c5;
  v_res := v_res || case when v_est = 'bloqueada' then '7a:recibi_movido_baja_el_origen ' else '7a:MAL(' || v_est || ') ' end;
  update public.facturas set contrato_id = (select id from public.contratos where numero = 'RP00140') where id = v_r158;
  select estado into v_est from public.unidades where id = v_c5;
  v_res := v_res || case when v_est = 'vendida' then '7b:vuelve_y_sube ' else '7b:MAL(' || v_est || ') ' end;
  delete from public.facturas where id = v_r158;
  select estado into v_est from public.unidades where id = v_c5;
  v_res := v_res || case when v_est = 'bloqueada' then '7c:recibi_borrado_baja ' else '7c:MAL(' || v_est || ') ' end;

  -- 8: «cobrada» con Bloqueo firmado (SH-189, RP00200) que se queda sin ningun cobro vuelve a «bloqueada» (LAW-497d)
  update public.facturas f set anulada = true
   where f.tipo = 'recibi' and not f.anulada
     and f.contrato_id in (select c.id from public.contratos c
                            where c.numero = 'RP00200'
                               or c.contrato_padre_id = (select id from public.contratos where numero = 'RP00200'));
  select estado into v_est from public.unidades where proyecto = 'Sumba Hills' and codigo = 'SH-189';
  v_res := v_res || case when v_est = 'bloqueada' then '8:cobrada_sin_cobro_baja ' else '8:MAL(' || v_est || ') ' end;

  -- 9: las funciones de trigger no son ejecutables desde la API
  v_res := v_res || case when has_function_privilege('authenticated', 'public.trg_avanza_por_recibi()', 'execute')
                           or has_function_privilege('authenticated', 'public.trg_avanza_por_aplicacion()', 'execute')
                           or has_function_privilege('anon', 'public.avanza_unidad_por_cobro(uuid)', 'execute')
                           or has_function_privilege('authenticated', 'public.avanza_unidad_por_cobro(uuid)', 'execute')
                         then '9:MAL ' else '9:funciones_sin_permiso_anon ' end;

  raise exception 'RESULTADO: %', v_res;
end $$;
