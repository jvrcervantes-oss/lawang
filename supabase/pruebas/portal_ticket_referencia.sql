-- Prueba (se revierte sola: acaba en RAISE) de portal_abrir_ticket con referencia — 7-oct-2026.
-- Hace de comprador del portal (claim app_metadata.portal + su email) y llama a la RPC REAL.
-- No llega a insertar ningún mensaje (los casos que fallan paran antes) y el caso «propio» se
-- comprueba con el mismo predicado de propiedad que usa la RPC, sin ejecutar el alta: insertar
-- un mensaje de comprador dispara el aviso al equipo (_trg_aviso_mensaje_comprador).
-- Esperado (cualquier «MAL» es fallo):
--   1:contrato_propio_visible 2:factura_propia_visible 3:contrato_ajeno_rechazado 4:factura_ajena_rechazada
--   5:id_inexistente_mismo_error 6:dos_referencias_rechazadas 7:texto_largo_rechazado 8:tope_10_rechazado
--   9:anon_sin_permiso

do $$
declare
  v_email text; v_cli uuid; v_user uuid;
  v_con_propio uuid; v_fac_propia uuid; v_con_ajeno uuid; v_fac_ajena uuid;
  v_res text := ''; v_msg text; v_code text; v_n int;
begin
  -- un comprador del portal con contrato y factura propios
  select pa.email, pa.client_id into v_email, v_cli
    from public.portal_accesos pa
    join public.contrato_compradores cc on cc.client_id = pa.client_id
    join public.facturas f on f.contrato_id = cc.contrato_id and not coalesce(f.anulada,false) and (f.tipo <> 'proforma' or f.enviada)
   where pa.activo
   limit 1;
  if v_email is null then raise exception 'RESULTADO: sin datos de prueba (ningún comprador con contrato y factura)'; end if;

  select cc.contrato_id into v_con_propio
    from public.contrato_compradores cc join public.portal_accesos pa on pa.client_id = cc.client_id
   where pa.activo and pa.email = v_email limit 1;
  select f.id into v_fac_propia
    from public.facturas f
    join public.contrato_compradores cc on cc.contrato_id = f.contrato_id
    join public.portal_accesos pa on pa.client_id = cc.client_id
   where pa.activo and pa.email = v_email and not coalesce(f.anulada,false) and (f.tipo <> 'proforma' or f.enviada) limit 1;

  -- un contrato y una factura que NO son de este comprador
  select c.id into v_con_ajeno from public.contratos c
   where not exists (select 1 from public.contrato_compradores cc join public.portal_accesos pa on pa.client_id = cc.client_id
                      where cc.contrato_id = c.id and pa.activo and pa.email = v_email) limit 1;
  select f.id into v_fac_ajena from public.facturas f
   where not exists (select 1 from public.contrato_compradores cc join public.portal_accesos pa on pa.client_id = cc.client_id
                      where cc.contrato_id = f.contrato_id and pa.activo and pa.email = v_email) limit 1;

  v_user := gen_random_uuid();
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated', 'email', v_email,
                     'app_metadata', json_build_object('portal', true))::text, true);

  -- 1 y 2: el predicado de propiedad (el de la RPC) reconoce lo propio
  if exists (select 1 from public.contrato_compradores cc join public.portal_accesos pa on pa.client_id = cc.client_id
              where cc.contrato_id = v_con_propio and pa.activo and pa.email = v_email) then v_res := v_res || '1:contrato_propio_visible ';
  else v_res := v_res || '1:MAL '; end if;
  if exists (select 1 from public.facturas f join public.contrato_compradores cc on cc.contrato_id = f.contrato_id
               join public.portal_accesos pa on pa.client_id = cc.client_id
              where f.id = v_fac_propia and pa.activo and pa.email = v_email) then v_res := v_res || '2:factura_propia_visible ';
  else v_res := v_res || '2:MAL '; end if;

  -- 3: contrato ajeno
  begin perform public.portal_abrir_ticket(v_cli, 'Pagos', 'prueba', null, v_con_ajeno); v_res := v_res || '3:MAL ';
  exception when others then get stacked diagnostics v_code = returned_sqlstate; v_msg := sqlerrm;
    v_res := v_res || case when v_code = '42501' then '3:contrato_ajeno_rechazado ' else '3:MAL(' || v_code || ') ' end; end;
  -- 4: factura ajena
  begin perform public.portal_abrir_ticket(v_cli, 'Pagos', 'prueba', v_fac_ajena, null); v_res := v_res || '4:MAL ';
  exception when others then get stacked diagnostics v_code = returned_sqlstate;
    v_res := v_res || case when v_code = '42501' then '4:factura_ajena_rechazada ' else '4:MAL(' || v_code || ') ' end; end;
  -- 5: id inexistente: el MISMO error que uno ajeno (no revela si existe)
  begin perform public.portal_abrir_ticket(v_cli, 'Pagos', 'prueba', gen_random_uuid(), null); v_res := v_res || '5:MAL ';
  exception when others then get stacked diagnostics v_code = returned_sqlstate;
    v_res := v_res || case when v_code = '42501' and sqlerrm = 'esa ficha no es tuya' then '5:id_inexistente_mismo_error ' else '5:MAL(' || v_code || ') ' end; end;
  -- 6: las dos referencias a la vez
  begin perform public.portal_abrir_ticket(v_cli, 'Pagos', 'prueba', v_fac_propia, v_con_propio); v_res := v_res || '6:MAL ';
  exception when others then get stacked diagnostics v_code = returned_sqlstate;
    v_res := v_res || case when v_code = '22023' then '6:dos_referencias_rechazadas ' else '6:MAL(' || v_code || ') ' end; end;
  -- 7: texto de más de 4000 caracteres
  begin perform public.portal_abrir_ticket(v_cli, 'Pagos', repeat('x', 4001), null, null); v_res := v_res || '7:MAL ';
  exception when others then get stacked diagnostics v_code = returned_sqlstate;
    v_res := v_res || case when v_code = '22023' and sqlerrm = 'mensaje demasiado largo' then '7:texto_largo_rechazado ' else '7:MAL(' || v_code || ') ' end; end;
  -- 8: tope de 10 tickets abiertos (se rellenan hasta 10 y el siguiente debe rechazarse)
  select count(*) into v_n from public.hilo_soporte where client_id = v_cli and estado = 'abierto';
  while v_n < 10 loop
    insert into public.hilo_soporte (id, client_id, categoria, estado, actualizado_en) values (gen_random_uuid(), v_cli, 'Otro', 'abierto', now());
    v_n := v_n + 1;
  end loop;
  begin perform public.portal_abrir_ticket(v_cli, 'Pagos', 'prueba', null, null); v_res := v_res || '8:MAL ';
  exception when others then get stacked diagnostics v_code = returned_sqlstate;
    v_res := v_res || case when v_code = '22023' and sqlerrm = 'demasiados tickets abiertos' then '8:tope_10_rechazado ' else '8:MAL(' || v_code || ') ' end; end;
  -- 9: anon no puede ejecutarla
  v_res := v_res || case when has_function_privilege('anon', 'public.portal_abrir_ticket(uuid,text,text,uuid,uuid)', 'execute')
                         then '9:MAL ' else '9:anon_sin_permiso ' end;

  raise exception 'RESULTADO: %', v_res;
end $$;
