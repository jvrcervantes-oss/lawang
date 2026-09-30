-- PRUEBA F5 «por su cuenta» (30-sep-2026) — migración supabase/migrations/20260930074916_f5_por_su_cuenta.sql.
-- Se ejecuta ENTERA en una llamada con execute_sql (MCP) o psql como postgres. NO ESCRIBE NADA: cada caso va en un
-- sub-bloque que acaba en excepción (Postgres deshace lo que hizo, rol, claims e interruptor incluidos) y el bloque
-- entero termina en `raise exception 'RES: …'`. Cada caso debe decir «ok».
-- OJO: el ROLLBACK no devuelve las secuencias. Cada pasada gasta números reales: ~6 de contrato RP, 1 de solicitud de
-- pago (SP), 1 de diferencia y 1 de cliente (CLI). No pasarla en bucle; el hueco de numeración lo decide el owner.
-- Los triggers de recálculo (zz_comisiones_reconcilia_*) son DEFERRED y no llegan a disparar dentro de la prueba: el
-- motor se llama a mano (comisiones_evaluar_contrato) donde el caso lo necesita.
-- Perfiles (se buscan, no se inventan): closer T = dortegag (equipo de Gus desde 1-abr), SM S = gusabellan, otro miembro
-- M = santidavidse, admin A = super_admin que no cobra comisiones. Venta que paga: RP00017 (firmada, 100 % del suelo
-- cobrado, 0 devengos hoy); en la prueba se le pone de closer a T (se congela solo al equipo de Gus) y fecha de venta hoy
-- (session_replication_role=replica solo para esa fila: el trigger no deja cambiar fecha_venta) para que rija el 10 %.
do $$
declare
  r text := ''; v_t text; v_state text;
  T record; S record; M record; A record;
  v_datos jsonb; v_res jsonb; v_root uuid; v_hijo uuid; v_obj uuid; v_lead uuid; v_cli uuid;
  k public.contrato_closer; v_n int; v_num text; v_tipo_hijo text;
  v_rp uuid := (select c.id from public.contratos c where c.numero = 'RP00017');
  v_cond record; v_pt numeric; v_dev public.comisiones_devengadas; v_sp public.solicitudes_pago; v_dif public.comisiones_diferencias;
begin
  select u.user_id, lower(u.email) e into T from public.usuarios u where lower(u.email) = 'dortegag@gmail.com' and u.activo;
  select u.user_id, lower(u.email) e into S from public.usuarios u where lower(u.email) = 'gusabellan@gmail.com' and u.activo;
  select u.user_id, lower(u.email) e into M from public.usuarios u where lower(u.email) = 'santidavidse@gmail.com' and u.activo;
  select u.user_id, lower(u.email) e into A from public.usuarios u
   where u.rol = 'super_admin' and u.activo
     and lower(u.email) not in (select lower(beneficiario_email) from public.comisiones_devengadas)
   order by u.email limit 1;
  if T.user_id is null or S.user_id is null or M.user_id is null or A.user_id is null or v_rp is null then
    raise exception 'RES: falta un perfil o la venta base (T %, S %, M %, A %, RP00017 %)',
      T.user_id is not null, S.user_id is not null, M.user_id is not null, A.user_id is not null, v_rp is not null;
  end if;
  if not exists (select 1 from public.equipo_miembros em join public.equipos_venta ev on ev.id = em.equipo_id
                  where lower(em.closer_email) = T.e and lower(ev.manager_email) = S.e and ev.activo and em.hasta is null) then
    raise exception 'RES: T ya no está en el equipo de S: la prueba no tiene base';
  end if;
  select tipo into v_tipo_hijo from public.contratos where contrato_padre_id is not null and tipo = 'carta_reserva' limit 1;
  -- datos de una Reserva de Parcela real de T (los triggers de alta necesitan un contrato completo), con otro comprador
  select c.datos into v_datos from public.contratos c
   where c.contrato_padre_id is null and c.tipo = 'reserva_parcela' and lower(c.creado_por) = T.e order by c.created_at desc limit 1;
  v_datos := jsonb_set(v_datos, '{fields}', (v_datos->'fields') - 'contrato_num' - 'num_reserva_vinculada' - 'poa_hs_vinculado'
    || jsonb_build_object('adq1_nombre', 'Prueba F5', 'adq1_email', 'prueba.f5.cliente@prueba.invalid',
                          'adq1_telefono', '+62 811-0000-5555', 'adq1_pasaporte', 'PF 5000 111',
                          'parcela_codigo', (select u.codigo from public.unidades u
                                              where u.proyecto_id = (select c.proyecto_id from public.contratos c
                                                                      where c.contrato_padre_id is null and c.tipo = 'reserva_parcela'
                                                                        and lower(c.creado_por) = T.e order by c.created_at desc limit 1)
                                                and u.estado = 'disponible' and u.contrato_id is null
                                              order by u.codigo_orden nulls last, u.codigo limit 1)));
  if v_datos->'fields'->>'parcela_codigo' is null then raise exception 'RES: no hay parcela libre para la prueba'; end if;
  -- sin enlace a fichas reales: espeja_comprador rellenaría el comprador desde adqN_client_id
  select jsonb_object_agg(e.key, e.value) into v_datos from jsonb_each(v_datos) e where e.key !~ '(client_id|^compradores$)';

  -- 1 · interruptor ENCENDIDO: alta de raíz sin modo (RPC llamada directamente) → 22023
  begin
    update public.comisiones_interruptor set modo_obligatorio = true where id;
    perform set_config('request.jwt.claims', json_build_object('sub', T.user_id, 'email', T.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    perform public.contrato_guarda(null, jsonb_build_object('tipo', 'reserva_parcela', 'datos', v_datos));
    raise exception 'sin error';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    r := r || '1 raiz sin modo=' || v_state || case when v_state = '22023' and sqlerrm like 'Indica si la venta%' then ' ok; ' else ' FALLO(' || sqlerrm || '); ' end;
  end;

  -- 2 · interruptor APAGADO (el de hoy): alta sin modo se guarda como hoy, modo NULL
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', T.user_id, 'email', T.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_res := public.contrato_guarda(null, jsonb_build_object('tipo', 'reserva_parcela', 'datos', v_datos));
    reset role;
    select * into k from public.contrato_closer where contrato_id = (v_res->>'id')::uuid;
    raise exception '%', format('%s/%s/%s', k.contrato_id is not null, k.modo is null, v_res->'venta'->>'modo' is null);
  exception when others then r := r || '2 apagado sin modo=' || sqlerrm || case when sqlerrm = 't/t/t' then ' ok; ' else ' FALLO; ' end; end;

  -- Desde 20260930080806 la clave `venta` solo existe con el interruptor ENCENDIDO: los casos 3-11 lo encienden aqui
  -- (se deshace con el resto al final). El caso 2 ya probo el apagado.
  update public.comisiones_interruptor set modo_obligatorio = true where id;
  -- 3 · BLOQUEO: el cliente es un lead que su SM le asignó (email en mayúsculas, teléfono en formato local)
  begin
    insert into public.leads (email, whatsapp, source, name) values ('prueba.f5.cliente@prueba.invalid', '0811 0000 5555', 'meta-lawang-bali', 'Prueba F5')
    returning id into v_lead;
    insert into public.lead_estado (lead_id, estado, responsable, asignado_por, asignado_en)
    values (v_lead, (select le.clave from public.lead_estados le order by le.orden limit 1), T.e, S.e, now())
    on conflict (lead_id) do update set responsable = excluded.responsable, asignado_por = excluded.asignado_por, asignado_en = excluded.asignado_en;
    perform set_config('request.jwt.claims', json_build_object('sub', T.user_id, 'email', T.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    perform public.contrato_guarda(null, jsonb_build_object('tipo', 'reserva_parcela',
      'datos', jsonb_set(v_datos, '{fields,adq1_email}', '"PRUEBA.F5.Cliente@Prueba.Invalid"'),
      'venta', jsonb_build_object('modo', 'propia', 'origen', 'contacto_personal')));
    raise exception 'sin error';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    r := r || '3 bloqueo=' || v_state || case when v_state = '23514' and sqlerrm like '%te asignó tu Sales Manager%' then ' ok; ' else ' FALLO(' || sqlerrm || '); ' end;
  end;

  -- 4 · AVISO de campaña (lead con el teléfono en otro formato, no asignado): se guarda, cruce anotado, ventana = now()+7 d
  --     aunque el navegador mande otra fecha, aviso al SM sin cifras; el closer no puede objetar su venta
  begin
    insert into public.leads (email, whatsapp, source, name) values (null, '0811 0000 5555', 'meta-lawang-bali', 'Prueba F5')
    returning id into v_lead;
    perform set_config('request.jwt.claims', json_build_object('sub', T.user_id, 'email', T.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_res := public.contrato_guarda(null, jsonb_build_object('tipo', 'reserva_parcela', 'datos', v_datos,
      'venta', jsonb_build_object('modo', 'propia', 'origen', 'redes_propias', 'espera_hasta', '2020-01-01', 'modo_espera_hasta', '2020-01-01')));
    reset role;
    v_root := (v_res->>'id')::uuid;
    select * into k from public.contrato_closer where contrato_id = v_root;
    select format('%s/%s/%s/%s/%s/%s/%s',
      k.modo = 'propia' and k.modo_origen = 'redes_propias',
      not (k.modo_cruces->>'bloqueo')::boolean,
      exists (select 1 from jsonb_array_elements(k.modo_cruces->'avisos') av where av->>'tipo' = 'campana' and av->>'lead_id' = v_lead::text),
      k.modo_espera_hasta between now() + interval '7 days' - interval '1 minute' and now() + interval '7 days' + interval '1 minute',
      k.modo_declarado_por = T.e and v_res->'venta'->>'modo' = 'propia',
      exists (select 1 from public.notificaciones n where n.contrato_id = v_root and n.tipo = 'venta_por_su_cuenta'
                 and lower(n.destinatario) = S.e and n.detalle like '%campañas de Lawang%' and n.detalle !~ '[0-9]{4,}\.[0-9]{2}'),
      (select count(*) from public.notificaciones n where n.contrato_id = v_root and n.tipo = 'venta_por_su_cuenta') = 1) into v_t;
    -- el closer no objeta su propia venta
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', T.user_id, 'email', T.e, 'role', 'authenticated')::text, true);
      -- sin «set local role authenticated»: RPC revocada a authenticated (20260930080806), se llama con claims
      perform public.venta_objecion_crear(v_root, 'prueba');
      v_t := v_t || '/objeta-closer-sin-error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_t || '/' || v_state; end;
    raise exception '%', v_t;
  exception when others then r := r || '4 aviso campaña=' || sqlerrm || case when sqlerrm = 't/t/t/t/t/t/t/42501' then ' ok; ' else ' FALLO; ' end; end;

  -- 5 · ficha de OTRO miembro del equipo (email con mayúsculas, pasaporte con espacios) → aviso; «otro» sin texto → 22023
  begin
    insert into public.clients (full_name, email, passport_number) values ('Prueba F5 ficha', 'prueba.f5.ficha@prueba.invalid', 'PF5000222')
    returning id into v_cli;
    update public.clients set propietario = M.e where id = v_cli;
    perform set_config('request.jwt.claims', json_build_object('sub', T.user_id, 'email', T.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    begin
      perform public.contrato_guarda(null, jsonb_build_object('tipo', 'reserva_parcela', 'datos', v_datos,
        'venta', jsonb_build_object('modo', 'propia', 'origen', 'otro')));
      v_t := 'otro-sin-texto-sin-error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_state; end;
    v_res := public.contrato_guarda(null, jsonb_build_object('tipo', 'reserva_parcela',
      'datos', jsonb_set(jsonb_set(jsonb_set(v_datos, '{fields,adq1_email}', '"PRUEBA.F5.Ficha@Prueba.INVALID"'),
                                   '{fields,adq1_telefono}', '"+62 899 0000 1234"'), '{fields,adq1_pasaporte}', '"pf 5000 222"'),
      'venta', jsonb_build_object('modo', 'propia', 'origen', 'otro', 'origen_texto', 'feria inmobiliaria')));
    reset role;
    select * into k from public.contrato_closer where contrato_id = (v_res->>'id')::uuid;
    select v_t || format('/%s/%s',
      exists (select 1 from jsonb_array_elements(k.modo_cruces->'avisos') av
               where av->>'tipo' = 'ficha_otro_miembro' and av->>'client_id' = v_cli::text and av->>'de' = M.e),
      not (k.modo_cruces->>'bloqueo')::boolean) into v_t;
    raise exception '%', v_t;
  exception when others then r := r || '5 ficha otro miembro=' || sqlerrm || case when sqlerrm = '22023/t/t' then ' ok; ' else ' FALLO; ' end; end;

  -- 6 · HIJO: ignora el modo que le manden y hereda el de la raíz; no tiene fila propia en contrato_closer
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', T.user_id, 'email', T.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_res := public.contrato_guarda(null, jsonb_build_object('tipo', 'reserva_parcela', 'datos', v_datos,
      'venta', jsonb_build_object('modo', 'propia', 'origen', 'referido_cliente')));
    v_root := (v_res->>'id')::uuid; v_num := v_res->>'numero';
    v_res := public.contrato_guarda(null, jsonb_build_object('tipo', v_tipo_hijo,
      'datos', jsonb_set(v_datos, '{fields,num_reserva_vinculada}', to_jsonb(v_num)),
      'venta', jsonb_build_object('modo', 'equipo')));
    reset role;
    v_hijo := (v_res->>'id')::uuid;
    raise exception '%', format('%s/%s/%s/%s',
      (select c.contrato_padre_id from public.contratos c where c.id = v_hijo) = v_root,
      v_res->'venta'->>'modo' = 'propia',
      not exists (select 1 from public.contrato_closer x where x.contrato_id = v_hijo),
      (select x.modo from public.contrato_closer x where x.contrato_id = v_root) = 'propia');
  exception when others then r := r || '6 hijo hereda=' || sqlerrm || case when sqlerrm = 't/t/t/t' then ' ok; ' else ' FALLO; ' end; end;

  -- 7 · MOTOR con RP00017 de T por su cuenta: (a) ventana abierta → 0; (b) objeción viva del SM aunque la ventana acabe → 0;
  --     el SM no objeta fuera de plazo; (c) admin mantiene «propia» → paga el 10 % estándar al closer, 0 al equipo;
  --     (d) cambio de modo tras PAGAR → diferencia negativa al mismo perceptor, devengo anulado, el recálculo no lo repaga
  begin
    update public.contrato_closer set closer_email = T.e where contrato_id = v_rp;   -- el trigger re-congela al equipo de Gus
    set local session_replication_role = replica;
    update public.contrato_closer set fecha_venta = current_date where contrato_id = v_rp;
    set local session_replication_role = origin;
    select * into k from public.contrato_closer where contrato_id = v_rp;
    if lower(k.manager_email) is distinct from S.e or k.fecha_venta <> current_date then
      raise exception 'base: RP00017 no quedó en el equipo de S con fecha de hoy (%, %)', k.manager_email, k.fecha_venta;
    end if;
    perform set_config('app.via_modo_admin', 'on', true);
    update public.contrato_closer set modo = 'propia', modo_origen = 'contacto_personal',
           modo_espera_hasta = now() + interval '7 days' where contrato_id = v_rp;
    perform set_config('app.via_modo_admin', 'off', true);
    v_t := public.comisiones_evaluar_contrato(v_rp)::text;                                   -- (a)
    perform set_config('request.jwt.claims', json_build_object('sub', S.user_id, 'email', S.e, 'role', 'authenticated')::text, true);
    -- sin «set local role authenticated»: RPC revocada a authenticated (20260930080806), se llama con claims
    v_obj := public.venta_objecion_crear(v_rp, 'El cliente vino por una campaña del equipo');
    reset role;
    update public.contrato_closer set modo_espera_hasta = now() - interval '1 minute' where contrato_id = v_rp;
    v_t := v_t || '/' || public.comisiones_evaluar_contrato(v_rp)::text;                    -- (b)
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', S.user_id, 'email', S.e, 'role', 'authenticated')::text, true);
      -- sin «set local role authenticated»: RPC revocada a authenticated (20260930080806), se llama con claims
      perform public.venta_objecion_crear(v_rp, 'otra');
      v_t := v_t || '/fuera-de-plazo-sin-error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_t || '/' || v_state; end;
    -- (c)
    perform set_config('request.jwt.claims', json_build_object('sub', A.user_id, 'email', A.e, 'role', 'authenticated')::text, true);
    -- sin «set local role authenticated»: RPC revocada a authenticated (20260930080806), se llama con claims
    v_n := public.venta_objecion_resolver(v_obj, 'mantener_propia', 'prueba F5: el cliente es del closer');
    reset role;
    select c.* into v_cond from public.condiciones_comision c
     where c.equipo_id is null and c.nivel = 'closer' and c.closer_email is null and c.proyecto_id is null
       and c.vigente_desde <= current_date and (c.vigente_hasta is null or c.vigente_hasta >= current_date)
     order by c.vigente_desde desc limit 1;
    v_pt := public._comisiones_precio_total(v_rp);
    select * into v_dev from public.comisiones_devengadas d where d.contrato_raiz_id = v_rp and d.estado <> 'anulada' order by d.created_at limit 1;
    select * into v_sp from public.solicitudes_pago sp where sp.id = v_dev.solicitud_id;
    v_t := v_t || format('/%s/%s/%s/%s/%s/%s/%s', v_n >= 1, v_cond.pct_comision = 10,
      (select bool_and(d.nivel = 'propia' and d.condicion_id = v_cond.id and lower(d.beneficiario_email) = T.e
                       and d.importe = round(v_cond.pct_comision / 100 * v_pt * tr.pct_tramo / 100, 2))
         from public.comisiones_devengadas d join public.condicion_tramos tr on tr.id = d.tramo_id
        where d.contrato_raiz_id = v_rp and d.estado <> 'anulada'),
      not exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id = v_rp
                   and d.nivel in ('manager', 'closer', 'setter', 'team_lead') and d.estado <> 'anulada'),
      v_sp.id is not null and lower(v_sp.beneficiario_email) = T.e and v_sp.importe = v_dev.importe,
      (select r2.estado || '/' || r2.resolucion from public.reclamaciones_venta_propia r2 where r2.id = v_obj) = 'rechazada/mantener_propia',
      exists (select 1 from public.notificaciones n where n.contrato_id = v_rp and n.tipo = 'venta_objecion' and n.destinatario is not null));
    -- (d) se paga la solicitud y un admin pasa la venta a «equipo»
    perform set_config('request.jwt.claims', json_build_object('sub', A.user_id, 'email', A.e, 'role', 'authenticated')::text, true);
    update public.solicitudes_pago set estado = 'aprobada' where id = v_sp.id;
    update public.solicitudes_pago set estado = 'pagada' where id = v_sp.id;
    -- sin «set local role authenticated»: RPC revocada a authenticated (20260930080806), se llama con claims
    perform public.venta_modo_admin(v_rp, 'equipo', 'prueba F5: la venta era del equipo');
    reset role;
    select * into v_dif from public.comisiones_diferencias x where x.devengo_id = v_dev.id;
    v_t := v_t || format('/%s/%s/%s/%s/%s',
      (select d.estado from public.comisiones_devengadas d where d.id = v_dev.id) = 'anulada',
      v_dif.importe = -v_sp.importe and v_dif.estado = 'pendiente' and v_dif.solicitud_id is null,
      (select sp.estado from public.solicitudes_pago sp where sp.id = v_sp.id) = 'pagada',
      (select k2.modo from public.contrato_closer k2 where k2.contrato_id = v_rp) = 'equipo',
      not exists (select 1 from public.comisiones_reconciliar(v_rp, true, '{}'::jsonb)));
    raise exception '%', v_t;
  exception when others then r := r || '7 motor/objecion/cambio tras pago=' || sqlerrm
    || case when sqlerrm = '0/0/22023/t/t/t/t/t/t/t/t/t/t/t/t' then ' ok; ' else ' FALLO; ' end; end;

  -- 8 · objeción ACEPTADA: admin pasa la venta a «equipo»; una objeción nunca paga; el resolver viejo no la toca
  begin
    update public.contrato_closer set closer_email = T.e where contrato_id = v_rp;
    perform set_config('app.via_modo_admin', 'on', true);
    update public.contrato_closer set modo = 'propia', modo_origen = 'contacto_personal',
           modo_espera_hasta = now() + interval '7 days' where contrato_id = v_rp;
    perform set_config('app.via_modo_admin', 'off', true);
    perform set_config('request.jwt.claims', json_build_object('sub', S.user_id, 'email', S.e, 'role', 'authenticated')::text, true);
    -- sin «set local role authenticated»: RPC revocada a authenticated (20260930080806), se llama con claims
    v_obj := public.venta_objecion_crear(v_rp, 'Lead del equipo');
    begin
      perform public.venta_propia_resolver(v_obj, true, 'x');
      v_t := 'resolver-viejo-sin-error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_state; end;
    begin
      perform public.venta_objecion_resolver(v_obj, 'pasar_equipo', 'el SM no resuelve');
      v_t := v_t || '/sm-resuelve-sin-error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_t || '/' || v_state; end;
    perform set_config('request.jwt.claims', json_build_object('sub', A.user_id, 'email', A.e, 'role', 'authenticated')::text, true);
    v_n := public.venta_objecion_resolver(v_obj, 'pasar_equipo', 'prueba F5: lead del equipo');
    reset role;
    select * into k from public.contrato_closer where contrato_id = v_rp;
    raise exception '%', v_t || format('/%s/%s/%s/%s', k.modo = 'equipo' and k.modo_origen is null and k.modo_espera_hasta is null,
      (select r2.estado || '/' || r2.resolucion from public.reclamaciones_venta_propia r2 where r2.id = v_obj) = 'retirada/pasar_equipo',
      not exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id = v_rp and d.nivel = 'propia' and d.estado <> 'anulada'),
      (select count(*) from public.reclamaciones_venta_propia r2 where r2.estado = 'aprobada' and r2.tipo = 'objecion') = 0);
  exception when others then r := r || '8 objecion aceptada=' || sqlerrm || case when sqlerrm = '22023/42501/t/t/t/t' then ' ok; ' else ' FALLO; ' end; end;

  -- 9 · CANDADO tras firma: nadie cambia el modo de RP00017 (firmada) sin pasar por el admin
  begin
    update public.contrato_closer set modo = 'propia', modo_origen = 'otro', modo_origen_texto = 'saltarse el candado' where contrato_id = v_rp;
    raise exception 'sin error';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    r := r || '9 candado=' || v_state || case when v_state = '42501' then ' ok; ' else ' FALLO(' || sqlerrm || '); ' end;
  end;

  -- 10 · EXPOSICIÓN: los ayudantes internos no se pueden llamar con sesión de usuario
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', T.user_id, 'email', T.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    perform public._venta_modo_aplica(v_rp, 'propia', 'saltarse');
    raise exception 'sin error';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    r := r || '10 ayudante interno=' || v_state || case when v_state = '42501' then ' ok; ' else ' FALLO(' || sqlerrm || '); ' end;
  end;

  -- 11 · PARIDAD: el motor nuevo no crea nada en ninguna raíz existente (todas con modo NULL)
  begin
    select coalesce(sum(public.comisiones_evaluar_contrato(c.id)), 0), count(*) into v_n, v_t
      from public.contratos c where c.contrato_padre_id is null;
    raise exception '%', format('%s/%s', v_n, (select count(*) from public.contrato_closer where modo is not null));
  exception when others then r := r || '11 paridad (creados/raices con modo)=' || sqlerrm || case when sqlerrm = '0/0' then ' ok; ' else ' FALLO; ' end; end;

  raise exception 'RES: %', r;
end $$;

-- HUELLAS (antes y después de aplicar, y otra vez a los 2-3 min): deben ser idénticas.
-- select
--  (select count(*)||':'||md5(string_agg(id::text||estado||importe::text||coalesce(importe_ajustado::text,'')||coalesce(solicitud_id::text,'')||nivel||beneficiario_email, ',' order by id)) from comisiones_devengadas) devengos,
--  (select count(*)||':'||md5(string_agg(id::text||estado||importe::text||coalesce(beneficiario_email,''), ',' order by id)) from solicitudes_pago) sps,
--  (select count(*)||':'||md5(string_agg(id::text||estado||coalesce(importe::text,''), ',' order by id)) from comisiones_diferencias) difs,
--  (select count(*) from (select r.* from (select distinct contrato_raiz_id from comisiones_devengadas) d,
--          lateral comisiones_reconciliar(d.contrato_raiz_id, true, '{}'::jsonb) r) x) reconciliar_filas;
-- Antes (30-sep 07:18 UTC): devengos 10:873cb219e4cd746a8144573b763fc2fd · sps 9:e7a0153471ad74d2a6afbe7ebedb455d · difs 0 · reconciliar 0.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- BLOQUE 2 · arreglos del revisor (20260930080806 + 20260930082215). Independiente del bloque de arriba y SIN
-- secuencias: no da de alta contratos (contrato_guarda solo sobre una raíz existente), la solicitud de pago lleva un
-- número de prueba escrito a mano, 999999005, lejos de la serie (numero es identity: OVERRIDING SYSTEM VALUE no gasta la serie) y la raíz no tiene cobros,
-- así que el motor no crea solicitudes nuevas. Se puede pasar cuantas veces haga falta. Todo acaba en excepción.
-- Raíz: la raíz más reciente de T sin firmar, sin devengos y congelada al equipo de S.
do $$
declare
  r text := ''; v_t text; v_state text;
  T record; S record; M record; A record;
  v_root uuid; c public.contratos; k public.contrato_closer; v_obj uuid; v_sp uuid; v_dev uuid; v_cond uuid; v_tramo uuid; v_n int;
begin
  select u.user_id, lower(u.email) e into T from public.usuarios u where lower(u.email) = 'dortegag@gmail.com' and u.activo;
  select u.user_id, lower(u.email) e into S from public.usuarios u where lower(u.email) = 'gusabellan@gmail.com' and u.activo;
  select u.user_id, lower(u.email) e into M from public.usuarios u where lower(u.email) = 'santidavidse@gmail.com' and u.activo;
  select u.user_id, lower(u.email) e into A from public.usuarios u
   where u.rol = 'super_admin' and u.activo
     and lower(u.email) not in (select lower(beneficiario_email) from public.comisiones_devengadas)
   order by u.email limit 1;
  select kk.contrato_id into v_root from public.contrato_closer kk join public.contratos cc on cc.id = kk.contrato_id
   where lower(kk.closer_email) = T.e and lower(kk.manager_email) = S.e and kk.equipo_congelado_en is not null
     and cc.contrato_padre_id is null and not coalesce(cc.bloqueado, false)
     and not exists (select 1 from public.contrato_firmas f where f.contrato_id = cc.id)
     and not exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id = cc.id)
   order by cc.created_at desc limit 1;
  if T.user_id is null or S.user_id is null or M.user_id is null or A.user_id is null or v_root is null then
    raise exception 'RES2: falta un perfil o la raíz de prueba';
  end if;
  select * into c from public.contratos where id = v_root;
  select cc.id, tr.id into v_cond, v_tramo from public.condiciones_comision cc join public.condicion_tramos tr on tr.condicion_id = cc.id
   where cc.nivel = 'manager' order by cc.vigente_desde desc limit 1;

  -- P1 · PUERTA: interruptor APAGADO → «propia» por contrato_guarda y por el camino del alta no escribe nada
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', T.user_id, 'email', T.e, 'role', 'authenticated')::text, true);
    perform public._venta_modo_declara(v_root, '{"modo":"propia","origen":"contacto_personal"}'::jsonb, true);
    v_t := coalesce((select modo from public.contrato_closer where contrato_id = v_root), 'NULL');
    perform set_config('app.via_modo_admin', 'on', true);
    update public.contrato_closer set modo = 'equipo' where contrato_id = v_root;
    perform set_config('app.via_modo_admin', 'off', true);
    set local role authenticated;
    perform public.contrato_guarda(v_root, jsonb_build_object('tipo', c.tipo, 'datos', c.datos,
      'venta', '{"modo":"propia","origen":"contacto_personal"}'::jsonb));
    reset role;
    select * into k from public.contrato_closer where contrato_id = v_root;
    raise exception '%', format('%s/%s/%s/%s', v_t, k.modo, k.modo_cruces is null,
      (select count(*) from public.notificaciones n where n.contrato_id = v_root and n.tipo = 'venta_por_su_cuenta'));
  exception when others then r := r || 'P1 puerta apagada=' || sqlerrm || case when sqlerrm = 'NULL/equipo/t/0' then ' ok; ' else ' FALLO; ' end; end;

  -- P2 · RPC sin pantalla revocadas a authenticated
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', S.user_id, 'email', S.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    begin perform public.venta_objecion_crear(v_root, 'x'); v_t := 'crear-sin-error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_state; end;
    begin perform public.venta_objecion_resolver(gen_random_uuid(), 'pasar_equipo', 'x'); v_t := v_t || '/resolver-sin-error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_t || '/' || v_state; end;
    begin perform public.venta_modo_admin(v_root, 'equipo', 'x'); v_t := v_t || '/admin-sin-error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_t || '/' || v_state; end;
    begin perform public.ventas_por_su_cuenta_equipo(); v_t := v_t || '/lista-sin-error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_t || '/' || v_state; end;
    reset role;
    raise exception '%', v_t;
  exception when others then r := r || 'P2 revocadas=' || sqlerrm || case when sqlerrm = '42501/42501/42501/42501' then ' ok; ' else ' FALLO; ' end; end;

  -- P3 · (2) modo FIJADO por un admin: el closer no lo cambia al re-guardar; re-guardar lo mismo sí pasa
  begin
    update public.comisiones_interruptor set modo_obligatorio = true where id;
    perform set_config('app.via_modo_admin', 'on', true);
    update public.contrato_closer set modo = 'equipo', modo_fijado_admin = true where contrato_id = v_root;
    perform set_config('app.via_modo_admin', 'off', true);
    perform set_config('request.jwt.claims', json_build_object('sub', T.user_id, 'email', T.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    perform public.contrato_guarda(v_root, jsonb_build_object('tipo', c.tipo, 'datos', c.datos, 'venta', '{"modo":"equipo"}'::jsonb));
    begin
      perform public.contrato_guarda(v_root, jsonb_build_object('tipo', c.tipo, 'datos', c.datos,
        'venta', '{"modo":"propia","origen":"contacto_personal"}'::jsonb));
      v_t := 'sin-error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate;
      v_t := v_state || case when sqlerrm like '%lo fijó un administrador%' then '' else '(' || sqlerrm || ')' end; end;
    reset role;
    raise exception '%', v_t || '/' || (select modo from public.contrato_closer where contrato_id = v_root);
  exception when others then r := r || 'P3 fijado admin=' || sqlerrm || case when sqlerrm = '42501/equipo' then ' ok; ' else ' FALLO; ' end; end;

  -- P4 · (3) el manager del equipo no declara «propia»: congelado (contrato_guarda) y actual (venta_modo_admin)
  begin
    update public.comisiones_interruptor set modo_obligatorio = true where id;
    perform set_config('app.via_modo_admin', 'on', true);
    update public.contrato_closer set modo = 'equipo', manager_email = T.e where contrato_id = v_root;
    perform set_config('app.via_modo_admin', 'off', true);
    perform set_config('request.jwt.claims', json_build_object('sub', T.user_id, 'email', T.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    begin
      perform public.contrato_guarda(v_root, jsonb_build_object('tipo', c.tipo, 'datos', c.datos,
        'venta', '{"modo":"propia","origen":"contacto_personal"}'::jsonb));
      v_t := 'congelado-sin-error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate;
      v_t := v_state || case when sqlerrm like 'Eres el manager%' then '' else '(' || sqlerrm || ')' end; end;
    reset role;
    update public.contrato_closer set manager_email = S.e where contrato_id = v_root;
    select * into k from public.contrato_closer where contrato_id = v_root;
    update public.equipos_venta set manager_email = T.e where id = k.equipo_id;
    perform set_config('request.jwt.claims', json_build_object('sub', A.user_id, 'email', A.e, 'role', 'authenticated')::text, true);
    begin
      perform public.venta_modo_admin(v_root, 'propia', 'prueba: manager actual');
      v_t := v_t || '/actual-sin-error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate;
      v_t := v_t || '/' || v_state || case when sqlerrm like '%es el manager de este equipo%' then '' else '(' || sqlerrm || ')' end; end;
    raise exception '%', v_t;
  exception when others then r := r || 'P4 manager propia=' || sqlerrm || case when sqlerrm = '22023/22023' then ' ok; ' else ' FALLO; ' end; end;

  -- P5 · (6) cambio de closer: modo, origen, cruces, ventana y marca de admin a NULL; objeción retirada; se declara de nuevo
  begin
    update public.comisiones_interruptor set modo_obligatorio = true where id;
    perform set_config('app.via_modo_admin', 'on', true);
    update public.contrato_closer set modo = 'propia', modo_origen = 'contacto_personal', modo_cruces = '{"bloqueo":false}',
           modo_espera_hasta = now() + interval '7 days', modo_fijado_admin = true, modo_declarado_por = T.e
     where contrato_id = v_root;
    perform set_config('app.via_modo_admin', 'off', true);
    insert into public.reclamaciones_venta_propia (contrato_raiz_id, solicitante_email, equipo_id, manager_email, motivo, tipo)
    select v_root, S.e, kk.equipo_id, S.e, 'prueba objeción', 'objecion' from public.contrato_closer kk where kk.contrato_id = v_root
    returning id into v_obj;
    update public.contrato_closer set closer_email = M.e where contrato_id = v_root;
    select * into k from public.contrato_closer where contrato_id = v_root;
    v_t := format('%s/%s/%s/%s', k.modo is null and k.modo_origen is null and k.modo_cruces is null and k.modo_espera_hasta is null,
      not k.modo_fijado_admin and k.modo_declarado_por = 'sistema:cambio_closer',
      (select estado from public.reclamaciones_venta_propia where id = v_obj),
      lower(k.closer_email) = M.e);
    perform set_config('request.jwt.claims', json_build_object('sub', M.user_id, 'email', M.e, 'role', 'authenticated')::text, true);
    perform public._venta_modo_declara(v_root, '{"modo":"equipo"}'::jsonb, false);
    raise exception '%', v_t || '/' || coalesce((select modo from public.contrato_closer where contrato_id = v_root), 'NULL');
  exception when others then r := r || 'P5 cambio closer=' || sqlerrm || case when sqlerrm = 't/t/retirada/t/equipo' then ' ok; ' else ' FALLO; ' end; end;

  -- P6 · (4) rama «sin pagar» de _venta_modo_aplica: fee de manager pendiente con su solicitud pendiente; el admin pasa la
  --      venta de equipo a propia → la solicitud se anula por app.via_venta_propia, el devengo con ella, un solo rastro de
  --      anulación, nada activo en la raíz y el reconciliar en seco no ve nada que pagar (sin pago doble)
  begin
    perform set_config('app.via_modo_admin', 'on', true);
    update public.contrato_closer set modo = 'equipo' where contrato_id = v_root;
    perform set_config('app.via_modo_admin', 'off', true);
    insert into public.solicitudes_pago (numero, concepto, importe, moneda, origen, beneficiario_email, creado_por, contrato_id)
    overriding system value
    values (999999005, 'Prueba F5 fee de manager', 100, 'EUR', 'comision_automatica', S.e, A.user_id, v_root)
    returning id into v_sp;
    insert into public.comisiones_devengadas (contrato_raiz_id, tramo_id, condicion_id, beneficiario_email, nivel, importe, moneda, solicitud_id)
    values (v_root, v_tramo, v_cond, S.e, 'manager', 100, 'EUR', v_sp)
    returning id into v_dev;
    perform set_config('request.jwt.claims', json_build_object('sub', A.user_id, 'email', A.e, 'role', 'authenticated')::text, true);
    v_n := public.venta_modo_admin(v_root, 'propia', 'prueba F5: rama sin pagar');
    select * into k from public.contrato_closer where contrato_id = v_root;
    raise exception '%', format('%s/%s/%s/%s/%s/%s/%s',
      (select estado from public.solicitudes_pago where id = v_sp),
      (select estado from public.comisiones_devengadas where id = v_dev),
      (select count(*) from public.comisiones_ajustes_log l where l.fila_id in (v_sp, v_dev) and l.accion = 'anular'),
      (select count(*) from public.comisiones_devengadas d where d.contrato_raiz_id = v_root and d.estado <> 'anulada')
        + (select count(*) from public.solicitudes_pago sp where sp.contrato_id = v_root and sp.estado not in ('anulada', 'rechazada')),
      not exists (select 1 from public.comisiones_reconciliar(v_root, true, '{}'::jsonb)),
      k.modo = 'propia' and k.modo_fijado_admin,
      v_n);
  exception when others then r := r || 'P6 sin pagar=' || sqlerrm || case when sqlerrm = 'anulada/anulada/1/0/t/t/0' then ' ok; ' else ' FALLO; ' end; end;

  -- ── LAW-474 (migración 20260930120030_law474_restos_f5). Base con cobros: RP00141 (closer T en el equipo de S, firmada,
  --    cobrada en parte, 0 devengos). Sin secuencias: el devengo se crea en el nivel `closer` (lo paga el SM, sin solicitud)
  --    con una condición de prueba, y las de manager del equipo se apagan dentro de la prueba.
  declare
    v_rp uuid := (select cc.id from public.contratos cc where cc.numero = 'RP00141' and cc.contrato_padre_id is null);
    kk public.contrato_closer; v_f date; v_c uuid; v_d public.comisiones_devengadas;
  begin
    select * into kk from public.contrato_closer where contrato_id = v_rp;
    if v_rp is null or lower(kk.closer_email) <> T.e or lower(kk.manager_email) <> S.e or kk.modo is not null
       or exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id = v_rp) then
      raise exception 'RES2: RP00141 ya no sirve de base para LAW-474 (%)', r;
    end if;
    v_f := coalesce(kk.fecha_venta, (select (cc.created_at at time zone 'Asia/Makassar')::date from public.contratos cc where cc.id = v_rp));

    -- P7 · (d) + marca de (a): admin pasa a «propia» una venta con devengo de closer vivo → devengo anulado Y marcado
    --      anulado_por_modo; ventana de 7 días, cruces anotados, aviso al SM sin cifras, y el motor no devenga en la ventana
    begin
      update public.condiciones_comision set activo = false, vigente_hasta = null
       where equipo_id = kk.equipo_id and nivel in ('manager', 'closer', 'setter', 'team_lead');
      insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo, activo, vigente_desde)
      select kk.equipo_id, cc.proyecto_id, 'closer', T.e, 5, 'precio_total', true, v_f - 30 from public.contratos cc where cc.id = v_rp
      returning id into v_c;
      insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo) values (v_c, 1, 'pct_cobrado_total', 0, 100);
      v_n := public.comisiones_evaluar_contrato(v_rp);
      select * into v_d from public.comisiones_devengadas d where d.contrato_raiz_id = v_rp;
      perform set_config('request.jwt.claims', json_build_object('sub', A.user_id, 'email', A.e, 'role', 'authenticated')::text, true);
      v_t := v_n || '/' || public.venta_modo_admin(v_rp, 'propia', 'prueba LAW-474 (d)');
      select * into k from public.contrato_closer where contrato_id = v_rp;
      raise exception '%', v_t || format('/%s/%s/%s/%s/%s',
        (select d.estado || ':' || d.anulado_por_modo from public.comisiones_devengadas d where d.id = v_d.id),
        k.modo = 'propia' and k.modo_fijado_admin
          and k.modo_espera_hasta between now() + interval '7 days' - interval '1 minute' and now() + interval '7 days' + interval '1 minute',
        k.modo_cruces ? 'bloqueo',
        (select count(*) from public.notificaciones n where n.contrato_id = v_rp and n.tipo = 'venta_por_su_cuenta'
            and lower(n.destinatario) = S.e and n.detalle like 'Un administrador marca%' and n.detalle !~ '[0-9]{4,}\.[0-9]{2}'),
        (select count(*) from public.comisiones_devengadas d where d.contrato_raiz_id = v_rp and d.estado <> 'anulada'));
    exception when others then r := r || 'P7 admin a propia=' || sqlerrm || case when sqlerrm = '1/0/anulada:true/t/t/1/0' then ' ok; ' else ' FALLO; ' end; end;

    -- P8 · (c) cola del fin de espera: una ventana vencida hace 10 días entra (antes solo miraba 3 días); con objeción
    --      viva o con devengo vivo de «propia» no entra. Se mira la cola, no se corre el cron (crearía una solicitud real).
    begin
      perform set_config('app.via_modo_admin', 'on', true);
      update public.contrato_closer set modo = 'propia', modo_espera_hasta = now() - interval '10 days' where contrato_id = v_rp;
      perform set_config('app.via_modo_admin', 'off', true);
      v_t := (v_rp in (select x from public._ventas_propia_fin_espera_cola() x))::text;
      insert into public.reclamaciones_venta_propia (contrato_raiz_id, solicitante_email, equipo_id, manager_email, motivo, tipo)
      values (v_rp, S.e, kk.equipo_id, S.e, 'prueba LAW-474 (c)', 'objecion') returning id into v_obj;
      v_t := v_t || '/' || (v_rp in (select x from public._ventas_propia_fin_espera_cola() x))::text;
      raise exception '%', v_t;
    exception when others then r := r || 'P8 cola fin espera=' || sqlerrm || case when sqlerrm = 'true/false' then ' ok; ' else ' FALLO; ' end; end;

    -- P9 · (f) cambio de closer con devengo vivo → 22023 (también por update directo); tras anularlo un admin con motivo,
    --      el cambio pasa y el motor no le genera al nuevo closer lo del anterior (el tramo del anterior queda anulado)
    begin
      update public.condiciones_comision set activo = false, vigente_hasta = null
       where equipo_id = kk.equipo_id and nivel in ('manager', 'closer', 'setter', 'team_lead');
      insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo, activo, vigente_desde)
      select kk.equipo_id, cc.proyecto_id, 'closer', null, 5, 'precio_total', true, v_f - 30 from public.contratos cc where cc.id = v_rp
      returning id into v_c;
      insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo) values (v_c, 1, 'pct_cobrado_total', 0, 100);
      v_n := public.comisiones_evaluar_contrato(v_rp);
      select * into v_d from public.comisiones_devengadas d where d.contrato_raiz_id = v_rp;
      begin
        update public.contrato_closer set closer_email = M.e where contrato_id = v_rp;
        v_t := 'cambio-sin-error';
      exception when others then get stacked diagnostics v_state = returned_sqlstate;
        v_t := v_state || case when sqlerrm like 'Esta venta ya tiene comisiones vivas%' then '' else '(' || sqlerrm || ')' end; end;
      perform set_config('request.jwt.claims', json_build_object('sub', A.user_id, 'email', A.e, 'role', 'authenticated')::text, true);
      perform public.comision_devengo_anular(v_d.id, 'prueba LAW-474 (f): cambia el closer');
      update public.contrato_closer set closer_email = M.e where contrato_id = v_rp;
      raise exception '%', v_n || '/' || v_t || format('/%s/%s', lower((select closer_email from public.contrato_closer where contrato_id = v_rp)) = M.e,
        (select d.anulado_por_modo from public.comisiones_devengadas d where d.id = v_d.id));
    exception when others then r := r || 'P9 cambio closer con devengos=' || sqlerrm || case when sqlerrm = '1/22023/t/f' then ' ok; ' else ' FALLO; ' end; end;

    -- P10 · (f) hueco del borrado (20260930120750): quitar el closer con crm_contrato_closer_set(raíz, NULL) —borra la
    --       fila y luego se podría asignar otro por INSERT— con devengo vivo → 22023; en una venta sin devengos sí se quita
    declare v_otro uuid;
    begin
      select k2.contrato_id into v_otro from public.contrato_closer k2 join public.contratos c2 on c2.id = k2.contrato_id
       where c2.contrato_padre_id is null and not exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id = c2.id)
         and lower(k2.closer_email) = T.e and k2.contrato_id <> v_rp limit 1;
      update public.condiciones_comision set activo = false, vigente_hasta = null
       where equipo_id = kk.equipo_id and nivel in ('manager', 'closer', 'setter', 'team_lead');
      insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo, activo, vigente_desde)
      select kk.equipo_id, cc.proyecto_id, 'closer', null, 5, 'precio_total', true, v_f - 30 from public.contratos cc where cc.id = v_rp
      returning id into v_c;
      insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo) values (v_c, 1, 'pct_cobrado_total', 0, 100);
      v_n := public.comisiones_evaluar_contrato(v_rp);
      perform set_config('request.jwt.claims', json_build_object('sub', A.user_id, 'email', A.e, 'role', 'authenticated')::text, true);
      begin
        perform public.crm_contrato_closer_set(v_rp, null, kk.closer_email);
        v_t := 'quitar-sin-error';
      exception when others then get stacked diagnostics v_state = returned_sqlstate;
        v_t := v_state || case when sqlerrm like 'Esta venta ya tiene comisiones vivas%' then '' else '(' || sqlerrm || ')' end; end;
      perform public.crm_contrato_closer_set(v_otro, null, kk.closer_email);
      raise exception '%', v_n || '/' || v_t || '/' || (select count(*) from public.contrato_closer where contrato_id = v_rp)
        || '/' || (select count(*) from public.contrato_closer where contrato_id = v_otro);
    exception when others then r := r || 'P10 quitar closer con devengos=' || sqlerrm || case when sqlerrm = '1/22023/1/0' then ' ok; ' else ' FALLO; ' end; end;
  end;

  raise exception 'RES2: %', r;
end $$;
-- 30-sep 12:0x UTC tras 20260930120030: P1-P9 ok (9/9); P10 ok tras 20260930120750 (pasado aparte). Secuencias SP 84, DIF 110, RP 253 sin cambios por la prueba.
-- La reposición de LAW-474 (a) y (b) no están aplicadas (supabase/pendientes/PENDIENTE_law474_a_b_reposicion_y_roles.sql):
-- sus casos se escriben y se pasan al aplicarla.
