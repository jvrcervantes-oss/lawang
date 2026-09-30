-- PRUEBA — AXW-98 en Lawang (opción (a) del owner, 30-sep-2026): toda SUBIDA de una comisión a favor de alguien del MISMO EQUIPO
-- DE LA VENTA que quien provoca el cambio va SIEMPRE a «revisar». Arreglo compartido con el maestro: son los 24 casos de
-- erp/pruebas/b3c_comisiones_subida_mismo_equipo.sql (agencia) adaptados a Lawang, más I1 (devengo sin equipo en el snapshot, que
-- es como están 8 de los 10 devengos vivos de Lawang: la regla cae al equipo congelado de contrato_closer).
-- Se ejecuta ENTERA con execute_sql (MCP) o psql como postgres. NO ESCRIBE NADA: cada caso va en un sub-bloque que se deshace
-- (error PRB01) y el bloque entero termina en `raise exception 'FIN DE PRUEBAS…'`. Cada línea debe decir «ok».
--
-- Portada a esta rama (era de sesion/0930-1502-axw98-mismo-equipo, commit be318d4f, autoría de agencia-0b, sin push a origin)
-- por pedido de revisor-codigo: no se sube sola. AVISO sobre el caso «A3» de este fichero: es un `position(... in
-- pg_get_functiondef(...))`, una comprobación de que el TEXTO de la función contiene ciertas cadenas — NO ejecuta ningún
-- escenario. Ningún caso de ESTE fichero crea un devengo `nivel = 'propia'` ni una fila en `reclamaciones_venta_propia`, así
-- que no prueba por sí solo que el equipo se lea del snapshot de CADA devengo (en vez de una vez por llamada). Ese caso
-- concreto —el único de Lawang donde las dos fórmulas pueden dar equipos distintos— está en
-- `prueba_axw98_venta_propia_otro_equipo.sql`, en este mismo directorio.
--
-- Adaptación a Lawang (el maestro tiene fixture PRB de corre.py y helpers equipo_venta_guarda/condicion_comision_guarda; aquí no):
--   · el fixture se monta a mano con session_replication_role = replica (usuarios, equipos, condiciones, devengos y la solicitud del
--     manager), y se vuelve a origin ANTES de llamar al reconciliador: las diferencias y sus disparadores corren como en producción;
--   · «el closer sube el precio» = subir en replica el precio_total de la raíz (firmada, cuenta en _comisiones_precio_total) y llamar
--     a comisiones_reconciliar(raiz, false) con la sesión de quien provoca — es lo que hace el disparador zz_comisiones_reconcilia_cambio
--     (contrato_guarda no deja editar un contrato firmado desde SQL, y esta prueba no la toca);
--   · la raíz es una real (la primera firmada sin devengos ni closer); todo lo que se le hace se deshace.
--
--   A  la función sigue igual de cerrada (definer, search_path vacío, EXECUTE solo service_role) y lleva la regla
--   B  el closer sube: setter/team lead/manager a «revisar», sin aplicar nada ni crear solicitud; la suya con el motivo de siempre;
--      con el setter ya pagado, UNA fila «revisar»; el closer no la resuelve, un admin con Reparto sí
--   C  team lead pagado y manager con solicitud APROBADA: «revisar», sin solicitud nueva ni tocar la aprobada
--   D  quien provoca es el MANAGER: closer/setter/team lead a «revisar»; la suya, motivo de siempre; no resuelve la del setter
--   E  otro equipo, admin ajeno, sin sesión: flujo normal (diferencias pendientes)
--   F  una BAJADA sigue el flujo normal
--   G  cambios de equipo posteriores a la venta no liberan (closer que se va, miembro que se va, miembro que entra después)
--   H  una segunda subida no duplica la fila «revisar»
--   I  devengo sin equipo en el snapshot: cae al equipo congelado de contrato_closer
do $$
declare
  r text := ''; e text; n bigint; n0 bigint; n1 bigint; b boolean;
  vx uuid; v_mon text;
  u_a uuid := gen_random_uuid();  a_mail text := 'admin.axw98@pruebas.test';
  u_a2 uuid := gen_random_uuid(); a2_mail text := 'admin2.axw98@pruebas.test';
  u_m uuid := gen_random_uuid();  m_mail text := 'manager.axw98@pruebas.test';
  u_c uuid := gen_random_uuid();  c_mail text := 'closer.axw98@pruebas.test';
  u_t uuid := gen_random_uuid();  t_mail text := 'setter.axw98@pruebas.test';
  u_tl uuid := gen_random_uuid(); tl_mail text := 'teamlead.axw98@pruebas.test';
  u_w uuid := gen_random_uuid();  w_mail text := 'miembro.axw98@pruebas.test';
  u_m2 uuid := gen_random_uuid(); m2_mail text := 'manager2.axw98@pruebas.test';
  u_x uuid := gen_random_uuid();  x_mail text := 'otroequipo.axw98@pruebas.test';
  eq uuid := gen_random_uuid(); eq2 uuid := gen_random_uuid();
  k_m uuid := gen_random_uuid(); k_c uuid := gen_random_uuid(); k_s uuid := gen_random_uuid(); k_tl uuid := gen_random_uuid();
  t_m uuid := gen_random_uuid(); t_c uuid := gen_random_uuid(); t_s uuid := gen_random_uuid(); t_tl uuid := gen_random_uuid();
  d_m uuid := gen_random_uuid(); d_c uuid := gen_random_uuid(); d_s uuid := gen_random_uuid(); d_tl uuid := gen_random_uuid();
  sm uuid := gen_random_uuid(); ids uuid[]; todos uuid[];
  dw uuid; imp_s numeric; imp_m numeric; imp_tl numeric; nsp0 bigint; nsp1 bigint; base0 numeric;
begin
  -- ── Preparación (como postgres) ────────────────────────────────────────────────────────────────────────────
  select c.id, c.moneda into vx, v_mon from public.contratos c
   where c.contrato_padre_id is null and c.liberado_en is null and coalesce(c.bloqueado, false) and c.precio_total > 0
     and c.moneda in ('EUR', 'USD', 'IDR')
   order by exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id = c.id),
            exists (select 1 from public.contrato_closer k where k.contrato_id = c.id), c.numero
   limit 1;
  if vx is null then raise exception 'RES: sin raíz firmada con precio: la prueba no tiene base'; end if;
  ids := array[d_m, d_c, d_s, d_tl, sm, k_m, k_c, k_s, k_tl, t_m, t_c, t_s, t_tl];
  todos := array[d_m, d_c, d_s, d_tl];

  execute 'set local session_replication_role = replica';
  insert into auth.users (id, email, aud, role)
  select x.id, x.mail, 'authenticated', 'authenticated'
    from (values (u_a, a_mail), (u_a2, a2_mail), (u_m, m_mail), (u_c, c_mail), (u_t, t_mail), (u_tl, tl_mail), (u_w, w_mail),
                 (u_m2, m2_mail), (u_x, x_mail)) as x(id, mail);
  insert into public.usuarios (user_id, email, nombre, rol, herramientas, proyectos, activo, numero_usuario) values
    (u_a, a_mail, 'Admin AXW98', 'admin', array['usuarios', 'comisiones_reparto'], '{}', true, 'USR-PRB98-1'),
    (u_a2, a2_mail, 'Admin2 AXW98', 'admin', array['usuarios', 'comisiones_reparto'], '{}', true, 'USR-PRB98-2'),
    (u_m, m_mail, 'Manager AXW98', 'agente', array['comisiones'], '{}', true, 'USR-PRB98-3'),
    (u_c, c_mail, 'Closer AXW98', 'agente', array['comisiones'], '{}', true, 'USR-PRB98-4'),
    (u_t, t_mail, 'Setter AXW98', 'agente', array['comisiones'], '{}', true, 'USR-PRB98-5'),
    (u_tl, tl_mail, 'TeamLead AXW98', 'agente', array['comisiones'], '{}', true, 'USR-PRB98-6'),
    (u_w, w_mail, 'Miembro AXW98', 'agente', array['comisiones'], '{}', true, 'USR-PRB98-7'),
    (u_m2, m2_mail, 'Manager2 AXW98', 'agente', array['comisiones'], '{}', true, 'USR-PRB98-8'),
    (u_x, x_mail, 'OtroEquipo AXW98', 'agente', array['comisiones'], '{}', true, 'USR-PRB98-9');
  insert into public.equipos_venta (id, nombre, manager_email, activo) values
    (eq, 'PRB AXW98 Equipo', m_mail, true), (eq2, 'PRB AXW98 Otro equipo', m2_mail, true);
  insert into public.equipo_miembros (equipo_id, closer_email, desde, hasta, added_by) values
    (eq, c_mail, '2000-01-01', null, 'PRB-AXW98'), (eq, t_mail, '2000-01-01', null, 'PRB-AXW98'),
    (eq, tl_mail, '2000-01-01', null, 'PRB-AXW98'), (eq, w_mail, '2000-01-01', null, 'PRB-AXW98'),
    (eq2, x_mail, '2000-01-01', null, 'PRB-AXW98');
  insert into public.condiciones_comision (id, equipo_id, nivel, closer_email, pct_comision, base_calculo, activo, vigente_desde) values
    (k_m, eq, 'manager', null, 2.5, 'precio_total', true, '2000-01-01'),
    (k_c, eq, 'closer', c_mail, 1.5, 'precio_total', true, '2000-01-01'),
    (k_s, eq, 'setter', t_mail, 0.5, 'precio_total', true, '2000-01-01'),
    (k_tl, eq, 'team_lead', tl_mail, 0.4, 'precio_total', true, '2000-01-01');
  insert into public.condicion_tramos (id, condicion_id, orden, disparador_tipo, pct_tramo) values
    (t_m, k_m, 1, 'contrato_firmado', 100), (t_c, k_c, 1, 'contrato_firmado', 100),
    (t_s, k_s, 1, 'contrato_firmado', 100), (t_tl, k_tl, 1, 'contrato_firmado', 100);
  execute 'set local session_replication_role = origin';
  perform set_config('request.jwt.claims', '', true);

  -- La venta: closer atribuido con equipo y manager CONGELADOS, setter y team lead de la venta, y los cuatro devengos cuadrando con
  -- la base de hoy (el del manager con su solicitud pendiente, como la deja el motor). p_dias retrasa la fecha de la venta.
  execute $f$create function pg_temp.axw98_arma(p_x uuid, p_mon text, p_eq uuid, p_m text, p_c text, p_t text, p_tl text,
                                                 p_dias int, p_snap boolean, p uuid[]) returns void language plpgsql as $b$
    declare v_base numeric := public._comisiones_precio_total(p_x); v_snap jsonb;
    begin
      v_snap := jsonb_build_object('base_calculo', 'precio_total', 'base_valor', v_base, 'precio_total', v_base)
                || case when p_snap then jsonb_build_object('equipo_id', p_eq) else '{}'::jsonb end;
      set local session_replication_role = replica;
      insert into public.contrato_closer (contrato_id, closer_email, asignado_por, fecha_venta, equipo_id, manager_email, equipo_congelado_en)
      values (p_x, p_c, 'PRB-AXW98', current_date - p_dias, p_eq, p_m, now())
      on conflict (contrato_id) do update set closer_email = excluded.closer_email, asignado_por = excluded.asignado_por,
        fecha_venta = excluded.fecha_venta, equipo_id = excluded.equipo_id, manager_email = excluded.manager_email,
        equipo_congelado_en = excluded.equipo_congelado_en;
      insert into public.contrato_roles_equipo (contrato_raiz_id, rol, email, equipo_id, asignado_por) values
        (p_x, 'setter', p_t, p_eq, 'PRB-AXW98'), (p_x, 'team_lead', p_tl, p_eq, 'PRB-AXW98');
      insert into public.solicitudes_pago (id, numero, contrato_id, concepto, importe, moneda, estado, origen, beneficiario_email, creado_por)
      overriding system value
      values (p[5], 999000098, p_x, 'Comisión manager PRB-AXW98 a fecha de disparo: ' || round(v_base, 2) || ' ' || p_mon,
              round(0.025 * v_base, 2), p_mon, 'pendiente', 'comision_automatica', p_m,
              (select u.user_id from public.usuarios u where u.email = p_m));
      insert into public.comisiones_devengadas (id, contrato_raiz_id, tramo_id, condicion_id, beneficiario_email, nivel, importe, moneda,
                                                disparado_en, disparado_por_snapshot, solicitud_id, estado) values
        (p[1], p_x, p[10], p[6], p_m, 'manager', round(0.025 * v_base, 2), p_mon, now(), v_snap, p[5], 'pendiente'),
        (p[2], p_x, p[11], p[7], p_c, 'closer', round(0.015 * v_base, 2), p_mon, now(), v_snap, null, 'pendiente'),
        (p[3], p_x, p[12], p[8], p_t, 'setter', round(0.005 * v_base, 2), p_mon, now(), v_snap, null, 'pendiente'),
        (p[4], p_x, p[13], p[9], p_tl, 'team_lead', round(0.004 * v_base, 2), p_mon, now(), v_snap, null, 'pendiente');
      set local session_replication_role = origin;
    end $b$ $f$;
  -- pagar devengos / aprobar una solicitud (como en prueba_comisiones_recalculo.sql: en replica, sin pasar por las guardas)
  execute $f$create function pg_temp.axw98_paga(p_ids uuid[]) returns void language plpgsql as $b$
    begin
      set local session_replication_role = replica;
      update public.comisiones_devengadas set estado = 'pagada', pagado_en = now() where id = any(p_ids);
      set local session_replication_role = origin;
    end $b$ $f$;
  -- el cambio de contrato: sube (o baja) el precio de la raíz y reconcilia con la sesión que haya puesta
  execute $f$create function pg_temp.axw98_cambia(p_x uuid, p_delta numeric) returns void language plpgsql as $b$
    begin
      set local session_replication_role = replica;
      update public.contratos set precio_total = precio_total + p_delta where id = p_x;
      set local session_replication_role = origin;
      perform public.comisiones_reconciliar(p_x, false, jsonb_build_object('prueba', 'axw98', 'delta', p_delta));
    end $b$ $f$;

  -- ── A. La función: mismas puertas, con la regla dentro ─────────────────────────────────────────────────────
  r := r || format(E'\nA1 comisiones_reconciliar existe, es definer con search_path vacío → %s',
        case when (select p.prosecdef and coalesce(p.proconfig, '{}') @> array['search_path=""']
                     from pg_proc p where p.oid = 'public.comisiones_reconciliar(uuid,boolean,jsonb)'::regprocedure) then 'ok' else 'FALLA' end);
  r := r || format(E'\nA2 EXECUTE: solo service_role (ni anon, ni authenticated) → %s',
        case when has_function_privilege('service_role', 'public.comisiones_reconciliar(uuid,boolean,jsonb)', 'execute')
               and not has_function_privilege('anon', 'public.comisiones_reconciliar(uuid,boolean,jsonb)', 'execute')
               and not has_function_privilege('authenticated', 'public.comisiones_reconciliar(uuid,boolean,jsonb)', 'execute') then 'ok' else 'FALLA' end);
  r := r || format(E'\nA3 el cuerpo lleva subida_mismo_equipo, el equipo del snapshot y los tres caminos de pertenencia → %s',
        case when position('subida_mismo_equipo' in pg_get_functiondef('public.comisiones_reconciliar(uuid,boolean,jsonb)'::regprocedure)) > 0
               and position($m$disparado_por_snapshot->>'equipo_id'$m$ in pg_get_functiondef('public.comisiones_reconciliar(uuid,boolean,jsonb)'::regprocedure)) > 0
               and position('contrato_roles_equipo' in pg_get_functiondef('public.comisiones_reconciliar(uuid,boolean,jsonb)'::regprocedure)) > 0
               and position('reclamaciones_venta_propia' in pg_get_functiondef('public.comisiones_reconciliar(uuid,boolean,jsonb)'::regprocedure)) > 0
               and position('equipo_miembros' in pg_get_functiondef('public.comisiones_reconciliar(uuid,boolean,jsonb)'::regprocedure)) > 0
               and position('equipos_venta' in pg_get_functiondef('public.comisiones_reconciliar(uuid,boolean,jsonb)'::regprocedure)) > 0 then 'ok' else 'FALLA' end);

  -- ── B. el closer sube el precio de la venta ────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.axw98_arma(vx, v_mon, eq, m_mail, c_mail, t_mail, tl_mail, 0, true, ids);
    base0 := public._comisiones_precio_total(vx);
    select importe into imp_s from public.comisiones_devengadas where id = d_s;
    select count(*) into nsp0 from public.solicitudes_pago;
    select count(*) into n from public.comisiones_reconciliar(vx, true, '{}');
    r := r || format(E'\nB0 fixture: 4 devengos con el equipo congelado en el snapshot, cuadrando (0 filas a simular) y _equipo_de_venta = el equipo → %s',
          case when (select count(*) from public.comisiones_devengadas where id = any(todos) and disparado_por_snapshot->>'equipo_id' = eq::text) = 4
                and n = 0 and (select equipo_id = eq from public._equipo_de_venta(vx)) then 'ok' else 'FALLA' end);
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'email', c_mail, 'role', 'authenticated')::text, true);
    perform pg_temp.axw98_cambia(vx, 10000);
    select count(*), coalesce(bool_and(x.estado = 'revisar' and x.motivo like 'subida_mismo_equipo%' and x.provocado_por = c_mail
                                      and x.importe > 0 and x.solicitud_id is null), false)
      into n, b from public.comisiones_diferencias x where x.devengo_id in (d_m, d_s, d_tl);
    r := r || format(E'\nB1 el closer sube con todo pendiente (base %s → %s): setter, team lead y manager en «revisar» con subida_mismo_equipo: %s de 3 → %s',
          base0, public._comisiones_precio_total(vx), n,
          case when n = 3 and b and public._comisiones_precio_total(vx) > base0 then 'ok' else 'FALLA' end);
    select count(*) into nsp1 from public.solicitudes_pago;
    r := r || format(E'\nB2 no se aplicó nada solo: setter sigue en %s, manager y su solicitud intactos, solicitudes %s → %s → %s',
          imp_s, nsp0, nsp1,
          case when (select importe from public.comisiones_devengadas where id = d_s) = imp_s and nsp0 = nsp1
                and (select importe from public.solicitudes_pago where id = sm) = (select importe from public.comisiones_devengadas where id = d_m)
                and (select disparado_por_snapshot ? 'recalculado_en' from public.comisiones_devengadas where id = d_m) is false then 'ok' else 'FALLA' end);
    select count(*), coalesce(bool_and(x.estado = 'revisar' and x.motivo like '%la provoca quien cobra%'), false)
      into n, b from public.comisiones_diferencias x where x.devengo_id = d_c;
    r := r || format(E'\nB3 su propia subida de closer sigue en «revisar» con el motivo de siempre → %s', case when n = 1 and b then 'ok' else 'FALLA' end);
    perform pg_temp.axw98_cambia(vx, 500);
    select count(*) into n from public.comisiones_diferencias where devengo_id = any(todos) and estado = 'revisar';
    r := r || format(E'\nH1 una segunda subida no duplica: una fila «revisar» por devengo (%s de 4) → %s', n, case when n = 4 then 'ok' else 'FALLA' end);
    raise exception using errcode = 'PRB01', message = 'fin del caso B1';
  exception when sqlstate 'PRB01' then null;
  end;
  perform set_config('request.jwt.claims', '', true);

  begin
    perform pg_temp.axw98_arma(vx, v_mon, eq, m_mail, c_mail, t_mail, tl_mail, 0, true, ids);
    perform pg_temp.axw98_paga(array[d_s]);
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'email', c_mail, 'role', 'authenticated')::text, true);
    perform pg_temp.axw98_cambia(vx, 10000);
    select x.id into dw from public.comisiones_diferencias x where x.devengo_id = d_s;
    select count(*), coalesce(bool_and(x.estado = 'revisar' and x.motivo like 'subida_mismo_equipo%' and x.solicitud_id is null), false)
      into n, b from public.comisiones_diferencias x where x.devengo_id = d_s;
    r := r || format(E'\nB4 el setter ya cobró: la subida es UNA fila «revisar» (no una diferencia pendiente): %s → %s', n, case when n = 1 and b then 'ok' else 'FALLA' end);
    execute 'set local role authenticated';
    begin perform public.comision_diferencia_resolver(dw, 'aplicar', 'prueba axw98'); e := 'entró'; exception when others then e := sqlstate; end;
    execute 'reset role';
    r := r || format(E'\nB5 el closer que la provocó no la resuelve (%s) → %s', e, case when e = '42501' then 'ok' else 'FALLA' end);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a2, 'email', a2_mail, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin perform public.comision_diferencia_resolver(dw, 'aplicar', 'prueba axw98: la subida es correcta'); e := 'ok'; exception when others then e := sqlstate || ' ' || sqlerrm; end;
    execute 'reset role';
    r := r || format(E'\nB6 un admin con Reparto la resuelve como cualquier «revisar» (%s): pendiente y resuelta por él → %s', e,
          case when e = 'ok' and (select estado = 'pendiente' and resuelto_por = a2_mail from public.comisiones_diferencias where id = dw) then 'ok' else 'FALLA' end);
    raise exception using errcode = 'PRB01', message = 'fin del caso B4';
  exception when sqlstate 'PRB01' then null;
  end;
  perform set_config('request.jwt.claims', '', true);

  -- ── C. team lead pagado y manager con la solicitud YA aprobada ───────────────────────────────────────────────
  begin
    perform pg_temp.axw98_arma(vx, v_mon, eq, m_mail, c_mail, t_mail, tl_mail, 0, true, ids);
    select importe into imp_m from public.comisiones_devengadas where id = d_m;
    select importe into imp_tl from public.comisiones_devengadas where id = d_tl;
    perform pg_temp.axw98_paga(array[d_tl]);
    execute 'set local session_replication_role = replica';
    update public.solicitudes_pago set estado = 'aprobada' where id = sm;
    execute 'set local session_replication_role = origin';
    select count(*) into nsp0 from public.solicitudes_pago;
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'email', c_mail, 'role', 'authenticated')::text, true);
    perform pg_temp.axw98_cambia(vx, 10000);
    select count(*) into n from public.comisiones_diferencias x
     where x.devengo_id in (d_m, d_tl) and x.estado = 'revisar' and x.motivo like 'subida_mismo_equipo%' and x.importe > 0 and x.solicitud_id is null;
    select count(*) into nsp1 from public.solicitudes_pago;
    r := r || format(E'\nC1 el closer sube: team lead (pagado) y manager (solicitud APROBADA) en «revisar» (%s de 2), solicitudes %s → %s, importes intactos → %s',
          n, nsp0, nsp1,
          case when n = 2 and nsp0 = nsp1 and (select importe from public.solicitudes_pago where id = sm) = imp_m
                and (select importe from public.comisiones_devengadas where id = d_m) = imp_m
                and (select importe from public.comisiones_devengadas where id = d_tl) = imp_tl then 'ok' else 'FALLA' end);
    raise exception using errcode = 'PRB01', message = 'fin del caso C1';
  exception when sqlstate 'PRB01' then null;
  end;
  perform set_config('request.jwt.claims', '', true);

  -- ── D. quien provoca es el MANAGER del equipo ───────────────────────────────────────────────────────────────
  begin
    perform pg_temp.axw98_arma(vx, v_mon, eq, m_mail, c_mail, t_mail, tl_mail, 0, true, ids);
    perform pg_temp.axw98_paga(array[d_c, d_s, d_tl]);
    perform set_config('request.jwt.claims', json_build_object('sub', u_m, 'email', m_mail, 'role', 'authenticated')::text, true);
    perform pg_temp.axw98_cambia(vx, 10000);
    select count(*) into n from public.comisiones_diferencias x
     where x.devengo_id in (d_c, d_s, d_tl) and x.estado = 'revisar' and x.motivo like 'subida_mismo_equipo%' and x.provocado_por = m_mail;
    r := r || format(E'\nD1 el manager sube: closer, setter y team lead (pagados) en «revisar» (%s de 3) → %s', n, case when n = 3 then 'ok' else 'FALLA' end);
    select count(*), coalesce(bool_and(x.estado = 'revisar' and x.motivo like '%la provoca quien cobra%'), false) into n, b
      from public.comisiones_diferencias x where x.devengo_id = d_m;
    r := r || format(E'\nD2 y su propia comisión de manager, con el motivo de siempre → %s', case when n = 1 and b then 'ok' else 'FALLA' end);
    select x.id into dw from public.comisiones_diferencias x where x.devengo_id = d_s;
    execute 'set local role authenticated';
    begin perform public.comision_diferencia_resolver(dw, 'aplicar', 'prueba axw98'); e := 'entró'; exception when others then e := sqlstate; end;
    execute 'reset role';
    r := r || format(E'\nD3 el manager que provocó no resuelve la del setter aunque la paga él (%s) → %s', e, case when e = '42501' then 'ok' else 'FALLA' end);
    raise exception using errcode = 'PRB01', message = 'fin del caso D';
  exception when sqlstate 'PRB01' then null;
  end;
  perform set_config('request.jwt.claims', '', true);

  -- ── E. otro equipo, un admin ajeno y sin sesión: el flujo de siempre ────────────────────────────────────────
  begin
    perform pg_temp.axw98_arma(vx, v_mon, eq, m_mail, c_mail, t_mail, tl_mail, 0, true, ids);
    perform pg_temp.axw98_paga(array[d_c, d_s, d_tl]);
    perform set_config('request.jwt.claims', json_build_object('sub', u_x, 'email', x_mail, 'role', 'authenticated')::text, true);
    perform pg_temp.axw98_cambia(vx, 10000);
    select count(*) filter (where estado = 'pendiente' and importe > 0), count(*) filter (where estado = 'revisar'),
           count(*) filter (where motivo like 'subida_mismo_equipo%')
      into n, n0, n1 from public.comisiones_diferencias where devengo_id in (d_c, d_s, d_tl);
    r := r || format(E'\nE1 alguien de OTRO equipo sube: 3 pendientes (%s), ninguna en «revisar» (%s) ni con el motivo nuevo (%s) → %s',
          n, n0, n1, case when n = 3 and n0 = 0 and n1 = 0 then 'ok' else 'FALLA' end);
    raise exception using errcode = 'PRB01', message = 'fin del caso E1';
  exception when sqlstate 'PRB01' then null;
  end;
  perform set_config('request.jwt.claims', '', true);
  begin
    perform pg_temp.axw98_arma(vx, v_mon, eq, m_mail, c_mail, t_mail, tl_mail, 0, true, ids);
    perform pg_temp.axw98_paga(array[d_c, d_s, d_tl]);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'email', a_mail, 'role', 'authenticated')::text, true);
    perform pg_temp.axw98_cambia(vx, 10000);
    select count(*) filter (where estado = 'pendiente' and importe > 0), count(*) filter (where estado = 'revisar')
      into n, n0 from public.comisiones_diferencias where devengo_id in (d_c, d_s, d_tl);
    r := r || format(E'\nE2 un admin que no es del equipo sube: 3 pendientes y ninguna en «revisar» (%s / %s) → %s', n, n0, case when n = 3 and n0 = 0 then 'ok' else 'FALLA' end);
    raise exception using errcode = 'PRB01', message = 'fin del caso E2';
  exception when sqlstate 'PRB01' then null;
  end;
  perform set_config('request.jwt.claims', '', true);
  begin
    perform pg_temp.axw98_arma(vx, v_mon, eq, m_mail, c_mail, t_mail, tl_mail, 0, true, ids);
    perform pg_temp.axw98_paga(array[d_c, d_s, d_tl]);
    perform set_config('request.jwt.claims', '', true);
    perform pg_temp.axw98_cambia(vx, 10000);
    select count(*) filter (where estado = 'pendiente' and provocado_por is null), count(*) filter (where motivo like 'subida_mismo_equipo%')
      into n, n1 from public.comisiones_diferencias where devengo_id in (d_c, d_s, d_tl);
    r := r || format(E'\nE3 sin sesión (provocado_por nulo): la regla no aplica, flujo de siempre (%s pendientes sin provocador, %s con el motivo nuevo) → %s',
          n, n1, case when n = 3 and n1 = 0 then 'ok' else 'FALLA' end);
    raise exception using errcode = 'PRB01', message = 'fin del caso E3';
  exception when sqlstate 'PRB01' then null;
  end;

  -- ── F. una BAJADA a favor de un compañero de equipo sigue el flujo normal ─────────────────────────────────
  begin
    perform pg_temp.axw98_arma(vx, v_mon, eq, m_mail, c_mail, t_mail, tl_mail, 0, true, ids);
    perform pg_temp.axw98_paga(array[d_s, d_tl]);
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'email', c_mail, 'role', 'authenticated')::text, true);
    perform pg_temp.axw98_cambia(vx, -10000);
    select count(*) filter (where estado = 'pendiente' and importe < 0), count(*) filter (where estado = 'revisar')
      into n, n0 from public.comisiones_diferencias where devengo_id in (d_s, d_tl);
    r := r || format(E'\nF1 el closer BAJA: setter y team lead con diferencia negativa pendiente (%s de 2), ninguna en «revisar» (%s) → %s',
          n, n0, case when n = 2 and n0 = 0 then 'ok' else 'FALLA' end);
    raise exception using errcode = 'PRB01', message = 'fin del caso F1';
  exception when sqlstate 'PRB01' then null;
  end;
  perform set_config('request.jwt.claims', '', true);

  -- ── G. un cambio de equipo POSTERIOR a la venta no altera el resultado ────────────────────────────────────
  begin
    perform pg_temp.axw98_arma(vx, v_mon, eq, m_mail, c_mail, t_mail, tl_mail, 0, true, ids);
    perform pg_temp.axw98_paga(array[d_s]);
    execute 'set local session_replication_role = replica';
    update public.equipo_miembros set hasta = current_date - 1 where equipo_id = eq and closer_email = c_mail;
    insert into public.equipo_miembros (equipo_id, closer_email, desde, hasta, added_by) values (eq2, c_mail, current_date, null, 'PRB-AXW98');
    execute 'set local session_replication_role = origin';
    r := r || format(E'\nG0 el closer ya está en el otro equipo y el equipo de la venta sigue congelado en el original → %s',
          case when (select equipo_id = eq2 from public.equipo_miembros where closer_email = c_mail and hasta is null)
                and (select equipo_id = eq from public._equipo_de_venta(vx)) then 'ok' else 'FALLA' end);
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'email', c_mail, 'role', 'authenticated')::text, true);
    perform pg_temp.axw98_cambia(vx, 10000);
    select count(*) into n from public.comisiones_diferencias x where x.devengo_id = d_s and x.estado = 'revisar' and x.motivo like 'subida_mismo_equipo%';
    r := r || format(E'\nG1 el closer que se fue a otro equipo sube SU venta: la del setter sigue en «revisar» (%s) → %s', n, case when n = 1 then 'ok' else 'FALLA' end);
    raise exception using errcode = 'PRB01', message = 'fin del caso G1';
  exception when sqlstate 'PRB01' then null;
  end;
  perform set_config('request.jwt.claims', '', true);
  begin
    perform pg_temp.axw98_arma(vx, v_mon, eq, m_mail, c_mail, t_mail, tl_mail, 10, true, ids);
    perform pg_temp.axw98_paga(array[d_s, d_tl]);
    execute 'set local session_replication_role = replica';
    update public.equipo_miembros set hasta = current_date - 5 where equipo_id = eq and closer_email = w_mail;
    insert into public.equipo_miembros (equipo_id, closer_email, desde, hasta, added_by) values (eq2, w_mail, current_date - 4, null, 'PRB-AXW98');
    execute 'set local session_replication_role = origin';
    r := r || format(E'\nG2a venta de hace 10 días (%s); w se fue del equipo hace 5 y no es parte de la venta → %s',
          (select fecha_venta from public.contrato_closer where contrato_id = vx),
          case when (select fecha_venta from public.contrato_closer where contrato_id = vx) = current_date - 10
                and not exists (select 1 from public.equipo_miembros where closer_email = w_mail and equipo_id = eq and hasta is null)
                and not exists (select 1 from public.contrato_roles_equipo where contrato_raiz_id = vx and email = w_mail) then 'ok' else 'FALLA' end);
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'email', w_mail, 'role', 'authenticated')::text, true);
    perform pg_temp.axw98_cambia(vx, 10000);
    select count(*) into n from public.comisiones_diferencias x
     where x.devengo_id in (d_s, d_tl) and x.estado = 'revisar' and x.motivo like 'subida_mismo_equipo%' and x.provocado_por = w_mail;
    r := r || format(E'\nG2b w, del equipo el día de la venta, sube: setter y team lead en «revisar» (%s de 2) → %s', n, case when n = 2 then 'ok' else 'FALLA' end);
    raise exception using errcode = 'PRB01', message = 'fin del caso G2';
  exception when sqlstate 'PRB01' then null;
  end;
  perform set_config('request.jwt.claims', '', true);
  begin
    perform pg_temp.axw98_arma(vx, v_mon, eq, m_mail, c_mail, t_mail, tl_mail, 10, true, ids);
    perform pg_temp.axw98_paga(array[d_s]);
    execute 'set local session_replication_role = replica';
    update public.equipo_miembros set desde = current_date - 3 where equipo_id = eq and closer_email = w_mail;
    execute 'set local session_replication_role = origin';
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'email', w_mail, 'role', 'authenticated')::text, true);
    perform pg_temp.axw98_cambia(vx, 10000);
    select count(*) into n from public.comisiones_diferencias x where x.devengo_id = d_s and x.estado = 'revisar' and x.motivo like 'subida_mismo_equipo%';
    r := r || format(E'\nG3 quien entró en el equipo después de la venta y sigue hoy cuenta como del equipo (%s) → %s', n, case when n = 1 then 'ok' else 'FALLA' end);
    raise exception using errcode = 'PRB01', message = 'fin del caso G3';
  exception when sqlstate 'PRB01' then null;
  end;
  perform set_config('request.jwt.claims', '', true);

  -- ── I. (solo Lawang) devengo SIN equipo en el snapshot: cae al equipo congelado de contrato_closer ─────────
  begin
    perform pg_temp.axw98_arma(vx, v_mon, eq, m_mail, c_mail, t_mail, tl_mail, 0, false, ids);
    perform pg_temp.axw98_paga(array[d_s]);
    perform set_config('request.jwt.claims', json_build_object('sub', u_w, 'email', w_mail, 'role', 'authenticated')::text, true);
    perform pg_temp.axw98_cambia(vx, 10000);
    select count(*) into n from public.comisiones_diferencias x where x.devengo_id = d_s and x.estado = 'revisar' and x.motivo like 'subida_mismo_equipo%';
    r := r || format(E'\nI1 snapshot sin equipo_id (%s): w, miembro sin rol en la venta, sube y la del setter va a «revisar» (%s) → %s',
          (select disparado_por_snapshot ? 'equipo_id' from public.comisiones_devengadas where id = d_s), n,
          case when n = 1 and (select not (disparado_por_snapshot ? 'equipo_id') from public.comisiones_devengadas where id = d_s) then 'ok' else 'FALLA' end);
    raise exception using errcode = 'PRB01', message = 'fin del caso I1';
  exception when sqlstate 'PRB01' then null;
  end;

  perform set_config('request.jwt.claims', '', true);
  raise exception 'FIN DE PRUEBAS (se deshace todo):%', r;
end $$;
