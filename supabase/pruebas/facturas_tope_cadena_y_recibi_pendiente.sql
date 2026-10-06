-- Prueba de facturas_tope_cadena_y_recibi_pendiente (5-oct-2026). Se ejecuta DESPUÉS de aplicar la migración, por
-- execute_sql: termina con un raise a propósito, así que no deja rastro (las altas, los recibís y el fichero de
-- prueba en storage se deshacen). Resultado del 5-oct: alta de 30.000 sobre CC00118 bloqueada, alta de 100 pasa,
-- RP00106 (ya excedida) edita sin subir y bloquea al subir, otra moneda y proforma no se tocan, recibí con pendiente
-- + 1 bloqueado, importe 0 bloqueado, privilegios: helpers sin execute para anon/authenticated, contrato_saldo solo
-- para authenticated. Datos de producción de ese día: ajustar los números si cambiaron.
do $t$
declare out text := ''; u record; c1 uuid; c2 uuid; f1 uuid; f2 uuid; soc text; j jsonb; pend numeric; r jsonb;
begin
  select user_id, email into u from public.usuarios where activo and rol='admin' and email like 'p@p%' limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
  out := out || 'es_admin='||public.es_admin()||' es_agente='||public.es_agente()||' puede_fact='||public.puede('facturas')||E'\n';
  select id into c1 from public.contratos where numero='CC00118';
  begin out := out || 'SALDO CC00118: '||left(public.contrato_saldo(c1)::text,420)||E'\n'; exception when others then out := out||'SALDO ERR '||sqlerrm||E'\n'; end;
  select sociedad into soc from public.facturas where numero='INV00184';
  begin
    perform public.factura_guarda(null, jsonb_build_object('tipo','factura','contrato_id',c1,'sociedad',soc,'moneda','EUR','total','30000','fecha_emision','2026-10-05','datos',jsonb_build_object('lineas',jsonb_build_array(jsonb_build_object('descripcion','x','importe','30000')),'fields','{}'::jsonb)));
    out := out||'ALTA 30000: PASO (MAL)'||E'\n';
  exception when others then out := out||'ALTA 30000 bloqueada: '||sqlerrm||E'\n'; end;
  begin
    perform public.factura_guarda(null, jsonb_build_object('tipo','factura','contrato_id',c1,'sociedad',soc,'moneda','EUR','total','100','fecha_emision','2026-10-05','datos',jsonb_build_object('lineas',jsonb_build_array(jsonb_build_object('descripcion','x','importe','100')),'fields','{}'::jsonb)));
    out := out||'ALTA 100: ok'||E'\n';
  exception when others then out := out||'ALTA 100 ERR '||sqlerrm||E'\n'; end;
  select f.id, f.contrato_id into f1, c2 from public.facturas f where f.numero='INV00159';
  begin perform public._factura_tope_cadena(f1, c2, 'EUR', 25000, 'factura'); out := out||'RP00106 sin subir: ok'||E'\n'; exception when others then out := out||'RP00106 sin subir ERR '||sqlerrm||E'\n'; end;
  begin perform public._factura_tope_cadena(f1, c2, 'EUR', 26000, 'factura'); out := out||'RP00106 subiendo: PASO (MAL)'||E'\n'; exception when others then out := out||'RP00106 subiendo bloqueada: '||left(sqlerrm,160)||E'\n'; end;
  begin perform public._factura_tope_cadena(null, c2, 'IDR', 99999999, 'factura'); out := out||'otra moneda: ok'||E'\n'; exception when others then out := out||'otra moneda ERR '||sqlerrm||E'\n'; end;
  begin perform public._factura_tope_cadena(null, c2, 'EUR', 99999999, 'proforma'); out := out||'proforma: ok'||E'\n'; exception when others then out := out||'proforma ERR '||sqlerrm||E'\n'; end;
  insert into storage.objects (bucket_id, name) values ('justificantes','test-5oct/x.pdf');
  select id into f2 from public.facturas where numero='INV00184';
  select total - coalesce((select sum(importe_aplicado) from public.recibi_aplicaciones ra join public.facturas rc on rc.id=ra.recibi_id and not coalesce(rc.anulada,false) where ra.factura_id=f2),0) into pend from public.facturas where id=f2;
  out := out||'pendiente INV00184='||pend||E'\n';
  j := jsonb_build_object('contrato_id',c1,'sociedad',soc,'cliente_nombre','t','proyecto_nombre','t','contrato_numero','CC00118','total',(pend+500)::text,'moneda','EUR','fecha_emision','2026-10-05','justificantes',jsonb_build_array(jsonb_build_object('path','test-5oct/x.pdf')),'datos','{}'::jsonb);
  begin r := public.guardar_recibi(null, j, jsonb_build_array(jsonb_build_object('factura_id',f2,'importe',pend+500))); out := out||'RECIBI pend+500: PASO (MAL)'||E'\n'; exception when others then out := out||'RECIBI pend+500 bloqueado: '||sqlerrm||E'\n'; end;
  begin r := public.guardar_recibi(null, j, jsonb_build_array(jsonb_build_object('factura_id',f2,'importe',0))); out := out||'RECIBI 0: PASO (MAL)'||E'\n'; exception when others then out := out||'RECIBI 0 bloqueado: '||sqlerrm||E'\n'; end;
  begin r := public.guardar_recibi(null, j, jsonb_build_array(jsonb_build_object('factura_id',f2,'importe',pend))); out := out||'RECIBI pend: ok '||r::text||E'\n'; exception when others then out := out||'RECIBI pend ERR '||sqlerrm||E'\n'; end;
  begin r := public.guardar_recibi(null, j, jsonb_build_array(jsonb_build_object('factura_id',f2,'importe',1))); out := out||'RECIBI 1 sobre cobrada: PASO (MAL)'||E'\n'; exception when others then out := out||'RECIBI 1 sobre cobrada bloqueado: '||sqlerrm||E'\n'; end;
  out := out||'privilegios: tope anon='||has_function_privilege('anon','public._factura_tope_cadena(uuid,uuid,text,numeric,text)','execute')||' auth='||has_function_privilege('authenticated','public._factura_tope_cadena(uuid,uuid,text,numeric,text)','execute')||' cadena auth='||has_function_privilege('authenticated','public._cadena_saldo(uuid,uuid)','execute')||' saldo anon='||has_function_privilege('anon','public.contrato_saldo(uuid)','execute')||' saldo auth='||has_function_privilege('authenticated','public.contrato_saldo(uuid)','execute');
  raise exception E'RESULTADOS\n%', out;
end $t$;