-- PRUEBA POR ROL, COMO ATAQUE — frontera bloque 2: compradores, documentos y bucket kyc (27-sep-2026, LAW-336).
-- Se ejecuta entera con execute_sql (MCP) o psql como postgres. NO ESCRIBE NADA: cada bloque termina en
-- `raise exception 'RES: …'`, que revierte la transacción y enseña el resultado. Cada línea debe decir «ok»;
-- una línea «FALLO» es un agujero abierto. (Ojo: un alta de prueba gasta un número de cliente de la
-- secuencia aunque se revierta.) Usuarios de prueba: el agente con más fichas y un admin; cámbialos si ya no
-- están activos. Tras el cierre (20260927103000) añade el bloque 4.

-- 1. Agente y admin por las RPC
do $$
declare r text := ''; v_new uuid; fd record; sd record; v_n int; v_tot int; v_j jsonb; v_t text;
  A text := '{"sub":"1cd031f2-c7da-455e-975f-c4e8708e36fb","email":"dortegag@gmail.com","role":"authenticated"}';
  ADM text := '{"sub":"24257595-aee2-4daa-8170-d268f46b9981","email":"p@pabloglobal.es","role":"authenticated"}';
begin
  select d.id, d.storage_path, d.client_id into fd from documents d join clients c on c.id=d.client_id
   where c.propietario <> 'dortegag@gmail.com' and not public.cliente_con_contrato_firmado(c.id) and d.storage_path like d.client_id::text||'/%' limit 1;
  select d.id, d.client_id into sd from documents d where public.cliente_con_contrato_firmado(d.client_id) limit 1;
  select count(*) into v_tot from documents;
  perform set_config('request.jwt.claims', A, true);
  set local role authenticated;
  begin perform public.cliente_guarda(null, '{"full_name":"Prueba Uno","phone":"+34 600000000","nationality":"ES","passport_number":"zz1"}'); r := r || '1 FALLO alta sin email; ';
  exception when others then r := r || '1 ok(' || left(sqlerrm,50) || '); '; end;
  begin perform public.cliente_guarda(null, '{"full_name":"prueba frontera b2","email":"prueba.b2@example.invalid","phone":"+34 600000001","nationality":"ES","passport_number":"zzb2test","kyc_status":"verified"}'); r := r || '2 FALLO agente aprueba KYC; ';
  exception when others then r := r || '2 ok; '; end;
  v_new := public.cliente_guarda(null, '{"full_name":"prueba frontera b2","email":"prueba.b2@example.invalid","phone":"+34 600000001","nationality":"ES","passport_number":"zzb2test","propietario":"otro@x.com"}');
  select '3 dueño=' || propietario || (case when propietario='dortegag@gmail.com' then ' ok; ' else ' FALLO; ' end) into v_t from clients where id=v_new; r := r || v_t;
  begin perform public.cliente_guarda(fd.client_id, '{"notes":"ataque"}'); r := r || '4 FALLO edita ficha ajena; ';
  exception when others then r := r || '4 ok; '; end;
  begin perform public.documento_kyc_retira('1cd031f2-c7da-455e-975f-c4e8708e36fb', fd.id); r := r || '5 FALLO el navegador llama a retirar; ';
  exception when others then r := r || '5 ok; '; end;
  begin perform public.cliente_traspasa(v_new, 'p@pabloglobal.es'); r := r || '6 FALLO agente traspasa; ';
  exception when others then r := r || '6 ok; '; end;
  select count(*) into v_n from documents d where d.client_id = fd.client_id; r := r || '7 ve documento ajeno=' || v_n || (case when v_n=0 then ' ok; ' else ' FALLO; ' end);
  r := r || '8 lee fichero ajeno=' || public.agente_ve_kyc(fd.storage_path) || '; ';
  perform set_config('request.jwt.claims', ADM, true);
  perform public.cliente_guarda(v_new, '{"kyc_status":"verified"}');
  select '9 admin aprueba, sello=' || coalesce(kyc_verificado_por,'FALLO') || '; ' into v_t from clients where id=v_new; r := r || v_t;
  reset role;
  set local role service_role;   -- retirar solo lo llama la edge, como el usuario de la sesión
  if sd.id is not null then
    begin perform public.documento_kyc_retira('24257595-aee2-4daa-8170-d268f46b9981', sd.id, 'motivo largo de prueba'); r := r || '10 FALLO admin retira con contrato; ';
    exception when others then r := r || '10 ok; '; end;
  end if;
  begin perform public.documento_kyc_retira('1cd031f2-c7da-455e-975f-c4e8708e36fb', fd.id); r := r || '11 FALLO agente retira; ';
  exception when others then r := r || '11 ok; '; end;
  raise exception 'RES: %', r;
end $$;

-- 2. Registro: solo la edge (service_role) y como el usuario de la sesión
do $$
declare r text := ''; own uuid; fc uuid; p text; v uuid;
begin
  select id into own from clients where propietario='dortegag@gmail.com' limit 1;
  select c.id into fc from clients c where c.propietario<>'dortegag@gmail.com' limit 1;
  p := own::text || '/' || gen_random_uuid()::text || '.pdf';
  insert into storage.objects (bucket_id, name) values ('kyc', p);
  set local role service_role;
  begin perform public.documento_kyc_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', fc, fc::text||'/'||gen_random_uuid()||'.pdf', 'passport'); r := r||'1 FALLO comprador ajeno; ';
  exception when others then r := r||'1 ok; '; end;
  begin perform public.documento_kyc_registra(gen_random_uuid(), own, p, 'passport'); r := r||'2 FALLO usuario falso; ';
  exception when others then r := r||'2 ok; '; end;
  v := public.documento_kyc_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', own, p, 'passport');
  r := r || '3 registrado ok; ';
  begin perform public.documento_kyc_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', own, p, 'passport'); r := r||'4 FALLO duplicado; ';
  exception when others then r := r||'4 ok; '; end;
  reset role;
  perform set_config('request.jwt.claims', '{"sub":"1cd031f2-c7da-455e-975f-c4e8708e36fb","email":"dortegag@gmail.com","role":"authenticated"}', true);
  set local role authenticated;
  begin perform public.documento_kyc_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', own, p, 'passport'); r := r||'5 FALLO el navegador registra; ';
  exception when others then r := r||'5 ok; '; end;
  raise exception 'RES: %', r;
end $$;

-- 3. Super admin: lo de un comprador con contrato o pagos se conserva
do $$
declare r text := ''; sd record; v_j jsonb; su record;
begin
  select user_id, email into su from usuarios where rol='super_admin' and activo and user_id is not null limit 1;
  select d.id into sd from documents d where exists (select 1 from contrato_compradores cc where cc.client_id = d.client_id) and d.retirado_el is null limit 1;
  set local role service_role;
  begin perform public.documento_kyc_retira(su.user_id, sd.id, 'corto'); r := r || '1 FALLO sin motivo; ';
  exception when others then r := r || '1 ok; '; end;
  v_j := public.documento_kyc_retira(su.user_id, sd.id, 'pasaporte caducado, se sustituye por el nuevo');
  r := r || '2 conservado=' || (v_j->>'conservado');
  reset role;
  r := r || ' fila_sigue=' || (select count(*) from public.documents where id=sd.id and retirado_el is not null);
  raise exception 'RES: %', r;
end $$;

-- 4. (tras el cierre) el navegador ya no escribe directo
do $$
declare r text := ''; own uuid; fd record;
begin
  select id into own from clients where propietario='dortegag@gmail.com' limit 1;
  select d.storage_path into fd from documents d join clients c on c.id=d.client_id where c.propietario<>'dortegag@gmail.com' limit 1;
  perform set_config('request.jwt.claims', '{"sub":"1cd031f2-c7da-455e-975f-c4e8708e36fb","email":"dortegag@gmail.com","role":"authenticated"}', true);
  set local role authenticated;
  begin insert into public.documents (client_id, doc_type, storage_path) values (own, 'passport', fd.storage_path); r := r||'1 FALLO insert ruta ajena; ';
  exception when others then r := r||'1 ok; '; end;
  begin update public.documents set status='verified' where client_id=own; r := r||'2 FALLO update documento; ';
  exception when others then r := r||'2 ok; '; end;
  begin insert into public.clients (full_name) values ('X'); r := r||'3 FALLO insert cliente; ';
  exception when others then r := r||'3 ok; '; end;
  begin update public.clients set kyc_status='verified' where id=own; r := r||'4 FALLO update cliente; ';
  exception when others then r := r||'4 ok; '; end;
  begin delete from storage.objects where bucket_id='kyc' and name=fd.storage_path; r := r||'5 borrados='||(select count(*) from storage.objects where bucket_id='kyc' and name=fd.storage_path)||' (1 = ok); ';
  exception when others then r := r||'5 ok; '; end;
  raise exception 'RES: %', r;
end $$;
