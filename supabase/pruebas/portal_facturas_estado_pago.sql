-- Prueba (se revierte sola: acaba en RAISE) del estado de pago de Facturas en el portal — 8-oct-2026.
-- Migración: 20261009050000_portal_facturas_estado_pago.sql. Hace de comprador del portal, de cuenta del equipo
-- y de cuenta mixta (equipo + portal) con claims simulados, y llama a las funciones REALES. No escribe nada.
-- Esperado (cualquier «MAL» es fallo):
--   1:propia_con_importe 2:ajena_null_para_comprador 3:equipo_ve_ajena 4:mixta_ve_ajena 5:sin_sesion_ve_ajena
--   6:salda_solo_mis_facturas 7:lista_sin_anuladas_ni_proformas_sin_enviar 8:aplicado_solo_en_facturas
--   9:sesion_sin_marca_ni_equipo_null

do $$
declare
  v_email text; v_agente uuid;
  v_propia uuid; v_ajena uuid; v_real_propia numeric; v_real_ajena numeric; v_n numeric;
  v_lista jsonb; v_res text := ''; v_malos int;
begin
  -- un comprador del portal con un recibí aplicado a una de sus facturas
  select pa.email, ra.factura_id into v_email, v_propia
    from public.portal_accesos pa
    join public.contrato_compradores cc on cc.client_id = pa.client_id
    join public.facturas f on f.contrato_id = cc.contrato_id and f.tipo = 'factura' and not coalesce(f.anulada, false)
    join public.recibi_aplicaciones ra on ra.factura_id = f.id
   where pa.activo
   limit 1;
  if v_email is null then raise exception 'RESULTADO: sin datos de prueba (ningún comprador con un recibí aplicado)'; end if;

  -- una factura AJENA con algo aplicado (para distinguir «null» de «0»)
  select f.id into v_ajena
    from public.facturas f
    join public.recibi_aplicaciones ra on ra.factura_id = f.id
   where f.tipo = 'factura'
     and not exists (select 1 from public.contrato_compradores cc join public.portal_accesos pa on pa.client_id = cc.client_id
                      where cc.contrato_id = f.contrato_id and pa.activo and pa.email = v_email)
   limit 1;
  select u.user_id into v_agente from public.usuarios u where u.activo and u.user_id is not null limit 1;
  if v_ajena is null or v_agente is null then raise exception 'RESULTADO: sin datos de prueba (factura ajena aplicada o usuario del equipo)'; end if;

  -- lo real, sin sesión (como el cron)
  v_real_propia := public.factura_aplicado(v_propia);
  v_real_ajena  := public.factura_aplicado(v_ajena);

  -- comprador del portal, que NO es del equipo
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated', 'email', v_email,
                     'app_metadata', json_build_object('portal', true))::text, true);
  v_n := public.factura_aplicado(v_propia);
  v_res := v_res || case when v_n = v_real_propia and v_n > 0 then '1:propia_con_importe ' else '1:MAL(' || coalesce(v_n::text, 'null') || ') ' end;
  v_n := public.factura_aplicado(v_ajena);
  v_res := v_res || case when v_n is null then '2:ajena_null_para_comprador ' else '2:MAL(' || v_n || ') ' end;

  v_lista := public.portal_situacion() -> 'facturas';
  -- 6: «salda» solo nombra facturas que están en la propia lista del comprador
  select count(*) into v_malos
    from jsonb_array_elements(v_lista) r, jsonb_array_elements(case when jsonb_typeof(r -> 'salda') = 'array' then r -> 'salda' else '[]'::jsonb end) s
   where not exists (select 1 from jsonb_array_elements(v_lista) f where f ->> 'numero' = s ->> 'numero' and f ->> 'tipo' = 'factura');
  v_res := v_res || case when v_malos = 0 then '6:salda_solo_mis_facturas ' else '6:MAL(' || v_malos || ') ' end;
  -- 7: la lista no trae anuladas ni proformas sin enviar
  select count(*) into v_malos
    from jsonb_array_elements(v_lista) x join public.facturas f on f.id = (x ->> 'id')::uuid
   where coalesce(f.anulada, false) or (f.tipo = 'proforma' and not coalesce(f.enviada, false))
      or (x ->> 'contrato_id')::uuid is distinct from f.contrato_id;   -- y cada una con SU contrato (la clave del reparto)
  v_res := v_res || case when v_malos = 0 then '7:lista_sin_anuladas_ni_proformas_sin_enviar ' else '7:MAL(' || v_malos || ') ' end;
  -- 8: `aplicado` en las facturas y en nada más; `salda` en los recibís y en nada más
  select count(*) into v_malos
    from jsonb_array_elements(v_lista) x
   where (x ->> 'tipo' = 'factura') <> coalesce(jsonb_typeof(x -> 'aplicado') = 'number', false)
      or (x ->> 'tipo' = 'recibi') <> coalesce(jsonb_typeof(x -> 'salda') = 'array', false);
  v_res := v_res || case when v_malos = 0 then '8:aplicado_solo_en_facturas ' else '8:MAL(' || v_malos || ') ' end;

  -- 3: cuenta solo del equipo
  perform set_config('request.jwt.claims', json_build_object('sub', v_agente, 'role', 'authenticated')::text, true);
  v_n := public.factura_aplicado(v_ajena);
  v_res := v_res || case when v_n = v_real_ajena then '3:equipo_ve_ajena ' else '3:MAL(' || coalesce(v_n::text, 'null') || ') ' end;

  -- 4: cuenta mixta (del equipo y con la marca del portal)
  perform set_config('request.jwt.claims', json_build_object('sub', v_agente, 'role', 'authenticated', 'email', v_email,
                     'app_metadata', json_build_object('portal', true))::text, true);
  v_n := public.factura_aplicado(v_ajena);
  v_res := v_res || case when v_n = v_real_ajena then '4:mixta_ve_ajena ' else '4:MAL(' || coalesce(v_n::text, 'null') || ') ' end;

  -- 9: con sesión, sin marca de portal y sin ser del equipo (p. ej. un usuario del equipo desactivado): cierra
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  v_n := public.factura_aplicado(v_ajena);
  v_res := v_res || case when v_n is null then '9:sesion_sin_marca_ni_equipo_null ' else '9:MAL(' || v_n || ') ' end;

  -- 5: sin sesión (cron, finanzas_resumen_semanal)
  perform set_config('request.jwt.claims', '', true);
  v_n := public.factura_aplicado(v_ajena);
  v_res := v_res || case when v_n = v_real_ajena then '5:sin_sesion_ve_ajena ' else '5:MAL(' || coalesce(v_n::text, 'null') || ') ' end;

  raise exception 'RESULTADO: %', v_res;
end $$;
