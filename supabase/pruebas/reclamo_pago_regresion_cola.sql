-- Regresion de la COLA DE CORREOS tras la migracion 20261010070000_reclamo_pago_parcela.sql (8-oct-2026).
-- La migracion reescribe public.correo_cola_reclamar y public.correo_cola_ok (rama aditiva para filas con reclamo_id). Esto fija que las
-- filas de firma/aviso se comportan EXACTAMENTE igual que antes. Se ejecuta en el MISMO envio que la migracion (migracion + este bloque):
-- una transaccion que acaba en `raise exception` (rollback, sin rastro). El veredicto sale en el mensaje: «FALLOS=0 de N casos | ...».
-- Sin la migracion aplicada tambien corre (linea base): salta R5 y la parte de B4 que usa reclamos_pago, y dice cuantos casos no probo.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback). El unico «drop» no existe; las filas ajenas de la cola solo se
-- marcan «cancelado» DENTRO de la transaccion para aislar la tanda (se deshace con el rollback).
-- Todo sintetico: cliente, parcelas, contratos y firmas se crean aqui dentro (correo @example.test); ningun dato real sale en el mensaje.
-- Cubre: R1 firma (enlace_firma_cadena) · R2 aviso de anulacion · R3 hecho ya no vigente · R4 sin destinatario · R5 reclamo real y
-- prueba conviven en la misma tanda · B4 contrato sin firmar (destinatarios y encolar).
do $t$
declare
  fallos int := 0; total int := 0; resumen text := '';
  v_mig boolean := to_regclass('public.reclamos_pago') is not null;
  v_prop uuid; v_prop_em text;
  p record; v_soc text;
  v_cl uuid; v_us uuid; v_ub uuid; v_cs uuid; v_cu uuid;
  f_ok uuid; f_an uuid; f_sd uuid;
  q1 uuid; q2 uuid; q3 uuid; q4 uuid; q_real uuid; q_pru uuid;
  j jsonb; el jsonb; n int; n_ajenas int; r text; v_ok boolean; v_est text; v_err text;
  c_ini int; c_fin int; c_res int; v_para text;
  v_sint constant text := 'sintetico.r@example.test';
begin
  -- ── función temporal: ejecuta SQL como un perfil y devuelve 'OK:<filas>' o 'E<sqlstate>/<hint>' ──
  execute $f$
    create or replace function pg_temp.intenta(p_rol text, p_sub uuid, p_email text, p_sql text) returns text
    language plpgsql as $g$
    declare n bigint; v_h text;
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', p_rol, 'email', p_email)::text, true);
      execute format('set local role %I', p_rol);
      begin
        execute 'select count(*) from (' || p_sql || ') t' into n;
        reset role;
        return 'OK:' || n;
      exception when others then
        get stacked diagnostics v_h = pg_exception_hint;
        reset role;
        return 'E' || sqlstate || '/' || coalesce(v_h, '');
      end;
    end $g$;
  $f$;

  select user_id, email into v_prop, v_prop_em from public.usuarios where es_propietario and activo limit 1;
  select pr.id, pr.nombre, e.sociedad_clave into p from public.proyectos pr join public.empresas e on e.clave = pr.empresa
   where e.sociedad_clave is not null order by pr.id limit 1;
  v_soc := p.sociedad_clave;
  if v_prop is null or p.id is null then
    raise exception 'FALLOS=1 | sin propietario o sin proyecto con sociedad (propietario %, proyecto %)', v_prop is not null, p.id is not null;
  end if;

  -- ── datos SINTETICOS: persona, dos parcelas, contrato firmado y contrato sin firmar ──
  insert into public.clients (full_name, email) values ('Sintetico Regresion', v_sint) returning id into v_cl;
  insert into public.unidades (codigo, proyecto, proyecto_id) values ('ZZ-SINT-R1', p.nombre, p.id) returning id into v_us;
  insert into public.unidades (codigo, proyecto, proyecto_id) values ('ZZ-SINT-B4', p.nombre, p.id) returning id into v_ub;
  insert into public.contratos (tipo, proyecto_id, fecha_firma, datos)
  values ('contrato_general', p.id, now(), jsonb_build_object('adq1_client_id', v_cl, 'fields', jsonb_build_object('sociedad_firmante', v_soc)))
  returning id into v_cs;
  insert into public.contratos (tipo, proyecto_id, datos)
  values ('contrato_general', p.id, jsonb_build_object('adq1_client_id', v_cl, 'fields', jsonb_build_object('sociedad_firmante', v_soc)))
  returning id into v_cu;
  -- la parcela apunta a su contrato (unidades.contrato_id es el vinculo que el candado de contratos exige; la otra via, contratos.unidad_id, la cubre la union)
  update public.unidades set contrato_id = v_cs where id = v_us;
  update public.unidades set contrato_id = v_cu where id = v_ub;
  -- tres firmas sinteticas: vigente con correo y anulada (contrato firmado), vigente sin correo (contrato sin firmar: solo hay una pendiente por rol y contrato)
  insert into public.contrato_firmas (contrato_id, token_hash, firmante_nombre, firmante_email, firmante_rol, orden, enlace_firma)
  values (v_cs, 'sint_hash_r1', 'Sintetico', v_sint, 'comprador', 1, 'https://example.test/firma') returning id into f_ok;
  insert into public.contrato_firmas (contrato_id, token_hash, firmante_nombre, firmante_email, firmante_rol, orden, enlace_firma, estado, anulado_en, anulado_por, anulado_motivo)
  values (v_cs, 'sint_hash_r2', 'Sintetico', v_sint, 'comprador', 2, 'https://example.test/firma', 'anulado', now(), 'regresion@example.test', 'prueba') returning id into f_an;
  insert into public.contrato_firmas (contrato_id, token_hash, firmante_nombre, firmante_rol, orden, enlace_firma)
  values (v_cu, 'sint_hash_r4', 'Sintetico', 'comprador', 1, 'https://example.test/firma') returning id into f_sd;

  -- ── aislar la tanda: lo que ya hubiera en la cola (real) se aparta DENTRO de la transaccion; el rollback lo devuelve ──
  update public.correos_cola set estado = 'cancelado', error = 'aislado_prueba' where estado in ('pendiente', 'enviando');
  get diagnostics n_ajenas = row_count;

  -- ── filas sinteticas de la cola, con la forma que usa correo_encolar (clave + ancla + prioridad de la regla) ──
  insert into public.correos_cola (clave, firma_id, prioridad) values ('enlace_firma_cadena', f_ok, (select r2.prioridad from public._correo_cola_regla('enlace_firma_cadena') r2)) returning id into q1;
  insert into public.correos_cola (clave, firma_id, prioridad) values ('aviso_anulacion', f_an, (select r2.prioridad from public._correo_cola_regla('aviso_anulacion') r2)) returning id into q2;
  insert into public.correos_cola (clave, firma_id, prioridad) values ('enlace_firma_cadena', f_an, (select r2.prioridad from public._correo_cola_regla('enlace_firma_cadena') r2)) returning id into q3;
  insert into public.correos_cola (clave, firma_id, prioridad) values ('enlace_firma_cadena', f_sd, (select r2.prioridad from public._correo_cola_regla('enlace_firma_cadena') r2)) returning id into q4;

  -- R5 (necesita la migracion): un reclamo real y una prueba, por el camino real (RPC con la sesion del propietario)
  if v_mig then
    r := pg_temp.intenta('authenticated', v_prop, v_prop_em, format('select public.reclamo_pago_encolar(%L, array[%L]::uuid[], null)', v_us, v_cl));
    total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [R5a encolar reclamo real sintetico: ' || r || ']'; end if;
    r := pg_temp.intenta('authenticated', v_prop, v_prop_em, format('select public.reclamo_pago_prueba(%L, null)', v_us));
    total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [R5b encolar prueba sintetica: ' || r || ']'; end if;
    execute format('select q.id from public.correos_cola q join public.reclamos_pago x on x.id = q.reclamo_id where x.unidad_id = %L and not x.prueba', v_us) into q_real;
    execute format('select q.id from public.correos_cola q join public.reclamos_pago x on x.id = q.reclamo_id where x.unidad_id = %L and x.prueba', v_us) into q_pru;
  end if;

  -- ── UNA tanda: la edge reclama hasta 10 filas; deben salir las dos de firma (+ las dos de reclamo) y ninguna mas ──
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  set local role service_role;
  select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) into j from public.correo_cola_reclamar(10) c;
  reset role;

  -- R1 firma: sale en la tanda con el MISMO destinatario y contrato que antes
  select x into el from jsonb_array_elements(j) x where x->>'id' = q1::text;
  total := total + 1; if el is null then fallos := fallos + 1; resumen := resumen || ' [R1 la fila de firma no salio en la tanda]';
  else
    total := total + 1; if el->>'para' is distinct from v_sint then fallos := fallos + 1; resumen := resumen || ' [R1b destinatario de la firma cambiado]'; end if;
    total := total + 1; if el->>'contrato_id' is distinct from v_cs::text then fallos := fallos + 1; resumen := resumen || ' [R1c contrato_id de la firma cambiado]'; end if;
    total := total + 1; if el->>'clave' <> 'enlace_firma_cadena' or (el->>'intentos')::int <> 1 or (el->>'prioridad')::int <> 1 then fallos := fallos + 1; resumen := resumen || ' [R1d clave/intentos/prioridad de la firma cambiados]'; end if;
  end if;
  select q.estado into v_est from public.correos_cola q where q.id = q1;
  total := total + 1; if v_est <> 'enviando' then fallos := fallos + 1; resumen := resumen || ' [R1e la firma no quedo enviando: ' || coalesce(v_est, 'null') || ']'; end if;

  -- R2 aviso de anulacion
  select x into el from jsonb_array_elements(j) x where x->>'id' = q2::text;
  total := total + 1; if el is null then fallos := fallos + 1; resumen := resumen || ' [R2 la fila de aviso no salio en la tanda]';
  else
    total := total + 1; if el->>'para' is distinct from v_sint or el->>'contrato_id' is distinct from v_cs::text or el->>'clave' <> 'aviso_anulacion' or (el->>'prioridad')::int <> 5 then
      fallos := fallos + 1; resumen := resumen || ' [R2b aviso: destinatario/contrato/clave/prioridad cambiados]'; end if;
  end if;

  -- R3 hecho ya no vigente (enlace de una firma anulada): cancelada, no sale
  select q.estado, q.error into v_est, v_err from public.correos_cola q where q.id = q3;
  total := total + 1; if v_est <> 'cancelado' or v_err is distinct from 'hecho_no_vigente' then fallos := fallos + 1; resumen := resumen || ' [R3 no vigente: ' || coalesce(v_est, 'null') || '/' || coalesce(v_err, 'null') || ']'; end if;
  total := total + 1; if exists (select 1 from jsonb_array_elements(j) x where x->>'id' = q3::text) then fallos := fallos + 1; resumen := resumen || ' [R3b la fila no vigente salio en la tanda]'; end if;

  -- R4 sin destinatario: error, no sale
  select q.estado, q.error into v_est, v_err from public.correos_cola q where q.id = q4;
  total := total + 1; if v_est <> 'error' or v_err is distinct from 'sin_destinatario' then fallos := fallos + 1; resumen := resumen || ' [R4 sin destinatario: ' || coalesce(v_est, 'null') || '/' || coalesce(v_err, 'null') || ']'; end if;
  total := total + 1; if exists (select 1 from jsonb_array_elements(j) x where x->>'id' = q4::text) then fallos := fallos + 1; resumen := resumen || ' [R4b la fila sin destinatario salio en la tanda]'; end if;

  -- R5 reclamo real y prueba conviven: salen los dos, cada uno con SU destinatario y el contrato del libro; las filas de firma no se alteran
  if v_mig then
    select x into el from jsonb_array_elements(j) x where x->>'id' = q_real::text;
    total := total + 1; if el is null or el->>'para' is distinct from v_sint or el->>'contrato_id' is distinct from v_cs::text or el->>'clave' <> 'reclamo_pago' or (el->>'prioridad')::int <> 7 then
      fallos := fallos + 1; resumen := resumen || ' [R5c reclamo real en la tanda: destinatario/contrato/clave/prioridad]'; end if;
    select x into el from jsonb_array_elements(j) x where x->>'id' = q_pru::text;
    total := total + 1; if el is null or el->>'para' is distinct from lower(v_prop_em) or el->>'para' = v_sint or el->>'contrato_id' is distinct from v_cs::text then
      fallos := fallos + 1; resumen := resumen || ' [R5d la prueba no va a quien la pidio]'; end if;
    total := total + 1; if jsonb_array_length(j) <> 4 then fallos := fallos + 1; resumen := resumen || ' [R5e la tanda trae ' || jsonb_array_length(j) || ' filas (esperadas 4)]'; end if;
  else
    total := total + 1; if jsonb_array_length(j) <> 2 then fallos := fallos + 1; resumen := resumen || ' [R5e la tanda trae ' || jsonb_array_length(j) || ' filas (esperadas 2)]'; end if;
  end if;

  -- ── cerrar ok: UNA fila en correos_enviados por correo real, con via/asunto de la regla; la prueba no deja registro ──
  select count(*) into c_ini from public.correos_enviados where contrato_id = v_cs;
  set local role service_role;
  v_ok := public.correo_cola_ok(q1, v_sint, 'v1');
  reset role;
  total := total + 1; if not coalesce(v_ok, false) then fallos := fallos + 1; resumen := resumen || ' [R1f correo_cola_ok de la firma devolvio false]'; end if;
  select count(*) into n from public.correos_enviados e2 where e2.contrato_id = v_cs and e2.via = 'enlace_firma' and e2.asunto = 'Documento para firmar'
     and e2.para = v_sint and e2.plantilla = 'enlace_firma_cadena' and e2.plantilla_version = 'v1';
  total := total + 1; if n <> 1 then fallos := fallos + 1; resumen := resumen || ' [R1g registro de la firma: filas=' || n || ' (esperada 1)]'; end if;

  set local role service_role;
  v_ok := public.correo_cola_ok(q2, v_sint, 'v1');
  reset role;
  total := total + 1; if not coalesce(v_ok, false) then fallos := fallos + 1; resumen := resumen || ' [R2c correo_cola_ok del aviso devolvio false]'; end if;
  select count(*) into n from public.correos_enviados e2 where e2.contrato_id = v_cs and e2.via = 'aviso_anulacion' and e2.asunto = 'Actualización del documento'
     and e2.para = v_sint and e2.plantilla = 'aviso_anulacion';
  total := total + 1; if n <> 1 then fallos := fallos + 1; resumen := resumen || ' [R2d registro del aviso: filas=' || n || ' (esperada 1)]'; end if;

  -- cerrar una fila ya cerrada no escribe otra vez (igual que antes)
  set local role service_role;
  v_ok := public.correo_cola_ok(q1, v_sint, 'v1');
  reset role;
  select count(*) into n from public.correos_enviados e2 where e2.contrato_id = v_cs and e2.via = 'enlace_firma';
  total := total + 1; if coalesce(v_ok, true) or n <> 1 then fallos := fallos + 1; resumen := resumen || ' [R1h cerrar dos veces escribio de mas o devolvio true]'; end if;

  if v_mig then
    set local role service_role;
    v_ok := public.correo_cola_ok(q_real, v_sint, 'v1');
    reset role;
    total := total + 1; if not coalesce(v_ok, false) then fallos := fallos + 1; resumen := resumen || ' [R5f cerrar el reclamo real devolvio false]'; end if;
    select count(*) into n from public.correos_enviados e2 where e2.contrato_id = v_cs and e2.via = 'reclamo_pago' and e2.asunto = 'Recordatorio de pago' and e2.para = v_sint;
    total := total + 1; if n <> 1 then fallos := fallos + 1; resumen := resumen || ' [R5g registro del reclamo real: filas=' || n || ' (esperada 1)]'; end if;
    select count(*) into c_res from public.correos_enviados where contrato_id = v_cs;
    set local role service_role;
    v_ok := public.correo_cola_ok(q_pru, v_prop_em, 'v1');
    reset role;
    select count(*) into c_fin from public.correos_enviados where contrato_id = v_cs;
    total := total + 1; if not coalesce(v_ok, false) or c_fin <> c_res then fallos := fallos + 1; resumen := resumen || ' [R5h la prueba escribio en correos_enviados o devolvio false]'; end if;
  end if;
  select count(*) into c_fin from public.correos_enviados where contrato_id = v_cs;
  total := total + 1; if c_fin - c_ini <> (case when v_mig then 3 else 2 end) then fallos := fallos + 1; resumen := resumen || ' [R6 registros nuevos del contrato: ' || (c_fin - c_ini) || ']'; end if;

  -- ── B4: contrato SIN firmar (sintetico). destinatarios lo devuelve no seleccionable con motivo sin_firmar y encolar lo rechaza ──
  if v_mig then
    r := pg_temp.intenta('authenticated', v_prop, v_prop_em, format('select * from public.reclamo_pago_destinatarios(%L) d where not d.seleccionable and d.motivo = ''sin_firmar'' and d.contrato_id = %L', v_ub, v_cu));
    total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [B4 destinatarios no marca sin_firmar: ' || r || ']'; end if;
    r := pg_temp.intenta('authenticated', v_prop, v_prop_em, format('select * from public.reclamo_pago_destinatarios(%L) d where d.seleccionable', v_ub));
    total := total + 1; if r <> 'OK:0' then fallos := fallos + 1; resumen := resumen || ' [B4b el contrato sin firmar figura seleccionable: ' || r || ']'; end if;
    select count(*) into n from public.reclamos_pago;
    r := pg_temp.intenta('authenticated', v_prop, v_prop_em, format('select public.reclamo_pago_encolar(%L, array[%L]::uuid[], null)', v_ub, v_cl));
    total := total + 1; if r not like 'E22023/sin_firmar' then fallos := fallos + 1; resumen := resumen || ' [B4c encolar sin firmar: ' || r || ']'; end if;
    total := total + 1; if (select count(*) from public.reclamos_pago) <> n then fallos := fallos + 1; resumen := resumen || ' [B4d el rechazo dejo filas en el libro]'; end if;
  else
    resumen := resumen || ' [B4: sin migracion aplicada, no probado]';
  end if;

  raise exception 'FALLOS=% de % casos | migracion=% ajenas_apartadas=% |%', fallos, total, v_mig, n_ajenas, case when resumen = '' then ' todo en verde' else resumen end;
end $t$;
