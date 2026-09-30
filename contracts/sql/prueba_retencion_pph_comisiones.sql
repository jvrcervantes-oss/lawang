-- PRUEBA — retención PPh de los pagos de comisión (20260930022612_pph_retencion_solicitudes_pago, 30-sep-2026).
-- Se ejecuta entera con execute_sql (MCP) o psql como postgres. NO ESCRIBE NADA: el bloque entero termina en
-- `raise exception 'RES: …'`, que deshace la preparación; cada caso va en un sub-bloque que acaba en excepción.
-- El MCP corre como postgres con BYPASSRLS: cada caso «por rol» fija request.jwt.claims y `set local role
-- authenticated`, o la prueba pasaría con la policy abierta. Cada caso debe decir «ok»; un «FALLO» es una
-- puerta abierta o un dato fiscal mal guardado.
-- Base: una solicitud `comision_automatica` pendiente, que aquí se aprueba y se paga como admin (se deshace).
do $$
declare
  r text := ''; v_sp uuid; v_otra uuid; v_imp numeric; v_benef record; v_admin record; v_ajeno record;
  v_n int; v_t text;
  c_admin text; c_benef text; c_ajeno text; c_admin_perceptor text;
begin
  select sp.id, sp.importe into v_sp, v_imp from public.solicitudes_pago sp
   where sp.origen = 'comision_automatica' and sp.estado = 'pendiente' and sp.importe_editado_por is null
   order by sp.numero limit 1;
  if v_sp is null then raise exception 'RES: sin solicitud automática pendiente: la prueba no tiene base'; end if;
  select sp.id into v_otra from public.solicitudes_pago sp where sp.estado = 'pendiente' and sp.id <> v_sp limit 1;
  select u.user_id, u.email into v_benef from public.usuarios u
   where lower(u.email) = (select lower(beneficiario_email) from public.solicitudes_pago where id = v_sp);
  select u.user_id, u.email into v_admin from public.usuarios u
   where u.rol = 'super_admin' and u.activo and lower(u.email) <> lower(v_benef.email) order by u.email limit 1;
  select u.user_id, u.email into v_ajeno from public.usuarios u
   where u.activo and u.rol not in ('super_admin','admin') and lower(u.email) <> lower(v_benef.email)
   order by u.email limit 1;
  if v_benef.user_id is null or v_admin.user_id is null or v_ajeno.user_id is null then
    raise exception 'RES: faltan usuarios (beneficiario/admin/ajeno) para la prueba';
  end if;
  c_admin := json_build_object('sub', v_admin.user_id, 'email', v_admin.email, 'role', 'authenticated')::text;
  c_benef := json_build_object('sub', v_benef.user_id, 'email', v_benef.email, 'role', 'authenticated')::text;
  c_ajeno := json_build_object('sub', v_ajeno.user_id, 'email', v_ajeno.email, 'role', 'authenticated')::text;
  -- admin que a la vez es el perceptor: uid de admin (es_admin), email del beneficiario
  c_admin_perceptor := json_build_object('sub', v_admin.user_id, 'email', v_benef.email, 'role', 'authenticated')::text;

  -- preparación: aprobar y pagar como admin (lo deshace el raise final)
  perform set_config('request.jwt.claims', c_admin, true);
  update public.solicitudes_pago set estado = 'aprobada' where id = v_sp;
  update public.solicitudes_pago set estado = 'pagada', pago_referencia = 'PRUEBA-F0' where id = v_sp;

  -- 0 · sobre una solicitud no pagada, la RPC se niega
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    execute 'set local role authenticated';
    perform public.solicitud_pago_retencion_guarda(v_otra, '{"perceptor_tipo":"persona","perceptor_nombre_fiscal":"X","perceptor_residente":false,"base":"1","pph_tipo":"pph26"}');
    raise exception 'escribio';
  exception when others then r := r || '0 no pagada=' || (case when sqlstate = '22023' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;

  -- 1 · admin con casilla escribe; perceptor, bruto y moneda los pone el servidor
  perform set_config('request.jwt.claims', c_admin, true);
  execute 'set local role authenticated';
  perform public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object(
    'perceptor_tipo', 'persona', 'perceptor_nombre_fiscal', 'PERCEPTOR DE PRUEBA',
    'perceptor_nik', '12.3456.7890.1234-56', 'perceptor_residente', true,
    'base', (v_imp / 2)::text, 'pph_tipo', 'PPH21', 'pph_retenido', '1'));
  execute 'reset role';
  select format('%s/%s/%s/%s', bruto = v_imp, lower(perceptor_email) = lower(v_benef.email),
                perceptor_nik = '1234567890123456', pph_tipo = 'pph21')
    into v_t from public.solicitudes_pago_retencion where solicitud_id = v_sp;
  r := r || '1 admin escribe=' || coalesce(v_t, 'sin fila') || (case when v_t = 't/t/t/t' then ' ok; ' else ' FALLO; ' end);

  -- 2 · el beneficiario lee la suya
  begin
    perform set_config('request.jwt.claims', c_benef, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.solicitudes_pago_retencion where solicitud_id = v_sp;
    raise exception '%', v_n;
  exception when others then r := r || '2 perceptor lee=' || sqlerrm || (case when sqlerrm = '1' then ' ok; ' else ' FALLO; ' end); end;

  -- 3 · el beneficiario no escribe por la RPC
  begin
    perform set_config('request.jwt.claims', c_benef, true);
    execute 'set local role authenticated';
    perform public.solicitud_pago_retencion_guarda(v_sp, '{"pph_retenido":"0"}');
    raise exception 'escribio';
  exception when others then r := r || '3 perceptor RPC=' || (case when sqlstate = '42501' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;

  -- 4 · ni directo (UPDATE / INSERT)
  begin
    perform set_config('request.jwt.claims', c_benef, true);
    execute 'set local role authenticated';
    update public.solicitudes_pago_retencion set pph_retenido = 0 where solicitud_id = v_sp;
    raise exception 'escribio';
  exception when others then r := r || '4a perceptor UPDATE=' || (case when sqlstate = '42501' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_benef, true);
    execute 'set local role authenticated';
    insert into public.solicitudes_pago_retencion (solicitud_id, perceptor_email, perceptor_tipo, perceptor_nombre_fiscal,
      perceptor_residente, moneda, bruto, base, pph_tipo) values (v_otra, v_benef.email, 'persona', 'X', false, 'EUR', 1, 1, 'pph26');
    raise exception 'escribio';
  exception when others then r := r || '4b perceptor INSERT=' || (case when sqlstate = '42501' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;

  -- 5 · un agente ajeno no la ve ni la escribe
  begin
    perform set_config('request.jwt.claims', c_ajeno, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.solicitudes_pago_retencion;
    raise exception '%', v_n;
  exception when others then r := r || '5a ajeno lee=' || sqlerrm || (case when sqlerrm = '0' then ' ok; ' else ' FALLO; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_ajeno, true);
    execute 'set local role authenticated';
    perform public.solicitud_pago_retencion_guarda(v_sp, '{"pph_retenido":"0"}');
    raise exception 'escribio';
  exception when others then r := r || '5b ajeno RPC=' || (case when sqlstate = '42501' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;

  -- 6 · un admin que es el perceptor no registra la suya
  begin
    perform set_config('request.jwt.claims', c_admin_perceptor, true);
    execute 'set local role authenticated';
    perform public.solicitud_pago_retencion_guarda(v_sp, '{"pph_retenido":"0"}');
    raise exception 'escribio';
  exception when others then r := r || '6 admin perceptor=' || (case when sqlstate = '42501' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;

  -- 7 · la base no supera el bruto
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    execute 'set local role authenticated';
    perform public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object('base', (v_imp + 1)::text));
    raise exception 'escribio';
  exception when others then r := r || '7 base>bruto=' || (case when sqlstate = '22023' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;

  -- 8 · el bukti potong congela: después no cambia la base; el ingreso en la DJP se pone una vez
  perform set_config('request.jwt.claims', c_admin, true);
  execute 'set local role authenticated';
  perform public.solicitud_pago_retencion_guarda(v_sp, '{"bukti_potong_numero":"BP-PRUEBA-F0"}');
  execute 'reset role';
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    execute 'set local role authenticated';
    perform public.solicitud_pago_retencion_guarda(v_sp, '{"base":"1"}');
    raise exception 'escribio';
  exception when others then r := r || '8a congelado=' || (case when sqlstate = '23514' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  perform set_config('request.jwt.claims', c_admin, true);
  execute 'set local role authenticated';
  perform public.solicitud_pago_retencion_guarda(v_sp, '{"djp_ingresado_el":"2026-09-30","djp_justificante_ref":"NTPN-PRUEBA"}');
  execute 'reset role';
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    execute 'set local role authenticated';
    perform public.solicitud_pago_retencion_guarda(v_sp, '{"djp_ingresado_el":"2026-10-01"}');
    raise exception 'escribio';
  exception when others then r := r || '8b ingreso una vez=' || (case when sqlstate = '23514' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;

  -- 9 · el log guardó cada escritura (insert + 2 updates)
  select count(*) into v_n from public.solicitudes_pago_retencion_log where solicitud_id = v_sp;
  r := r || '9 log=' || v_n || (case when v_n = 3 then ' ok; ' else ' FALLO; ' end);

  raise exception 'RES: %', r;
end $$;
