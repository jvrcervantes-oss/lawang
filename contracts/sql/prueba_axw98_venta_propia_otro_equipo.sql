-- PRUEBA — AXW-98/B3c en Lawang, caso que la batería de 25 de agencia-0b (prueba_axw98_subida_mismo_equipo.sql)
-- NO ejercía: una reclamación de VENTA PROPIA aprobada por un equipo DISTINTO del equipo congelado
-- de la venta. Es el único camino de Lawang donde el equipo del SNAPSHOT de un devengo
-- (`disparado_por_snapshot->>'equipo_id'`, el que escribe el motor — supabase/migrations/20260924160000_comisiones_roles_venta_propia_ajuste_sm.sql:488,
-- `v_equipo_id := v_propia.equipo_id` cuando hay reclamación aprobada) puede diferir del equipo que
-- devuelve `_equipo_de_venta(raiz)` (el congelado del closer/manager en `contrato_closer`).
--
-- Por qué hace falta este fichero aparte: revisor-codigo (segunda pasada, sobre el commit 6511beb6)
-- señaló que la fila «A3» de la batería de 25 casos no ejecuta ningún escenario — es un
-- `position('...' in pg_get_functiondef(...))`, una comprobación de que el TEXTO de la función
-- contiene ciertas cadenas, no de que la lógica por-devengo produzca el resultado correcto. Y ningún
-- otro caso de esa batería crea un devengo `nivel = 'propia'` ni una fila en
-- `reclamaciones_venta_propia`, así que el único camino donde 20260930170000 (equipo UNA vez por
-- llamada) y 20260930171500 (equipo por CADA devengo, con el snapshot) dan resultados distintos
-- nunca se ejecutó. Hallazgo correcto: hacía falta este caso, con datos, no solo con grep sobre el
-- código.
--
-- Se ejecuta ENTERA con execute_sql (MCP) o psql como postgres. NO ESCRIBE NADA: termina en
-- `raise exception 'FIN PRUEBA…'`, así que se deshace sola.
--
-- Montaje:
--   EQUIPO A (eqA): closer c_mail, manager m_mail — es el equipo CONGELADO de la venta en `contrato_closer`.
--   EQUIPO B (eqB): manager m2_mail, miembro x_mail — NADA que ver con la venta salvo la reclamación.
--   Una reclamación de venta propia de m2_mail (equipo B) queda APROBADA sobre esta venta.
--   El devengo `nivel = 'propia'`, beneficiario m2_mail, lleva en su snapshot `equipo_id = eqB`
--   (así lo construye el motor real, no una invención de la prueba).
--
-- Caso: x_mail (miembro de equipo B — NI beneficiario de esta comisión, NI del equipo congelado A)
-- provoca una subida del precio del contrato. La colusión que AXW-98 cierra es exactamente esta:
-- alguien de fuera de la venta, pero del MISMO equipo que el beneficiario, se beneficia sin que nadie
-- lo revise. Con el equipo sacado UNA vez de `_equipo_de_venta` (=A), x_mail no coincide con nada de
-- A y la subida se aplicaría sola. Con el equipo por-devengo (snapshot=B), x_mail SÍ es del equipo B
-- (miembro) y la subida tiene que ir a «revisar» con el motivo `subida_mismo_equipo`.
do $$
declare
  r text := '';
  vx uuid; v_mon text;
  u_m uuid := gen_random_uuid();  m_mail text := 'mgrA2.axw98c@pruebas.test';
  u_c uuid := gen_random_uuid();  c_mail text := 'closerA2.axw98c@pruebas.test';
  u_m2 uuid := gen_random_uuid(); m2_mail text := 'mgrB2.axw98c@pruebas.test';
  u_x uuid := gen_random_uuid();  x_mail text := 'miembroB2.axw98c@pruebas.test';
  eqA uuid := gen_random_uuid(); eqB uuid := gen_random_uuid();
  kA uuid := gen_random_uuid(); tA uuid := gen_random_uuid();
  kB uuid := gen_random_uuid(); tB uuid := gen_random_uuid();
  d_propia uuid := gen_random_uuid();
  sp_id uuid := gen_random_uuid();
  rp_id uuid;
  v_base numeric; v_mot text; v_estado text; v_eq_venta uuid; v_eq_snapshot uuid;
begin
  select c.id, c.moneda into vx, v_mon from public.contratos c
   where c.contrato_padre_id is null and c.liberado_en is null and coalesce(c.bloqueado, false) and c.precio_total > 0
     and c.moneda in ('EUR', 'USD', 'IDR')
   order by exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id = c.id),
            exists (select 1 from public.contrato_closer k where k.contrato_id = c.id), c.numero
   limit 1;
  if vx is null then raise exception 'sin raíz de prueba'; end if;

  execute 'set local session_replication_role = replica';
  insert into auth.users (id, email, aud, role)
  select x.id, x.mail, 'authenticated', 'authenticated'
    from (values (u_m, m_mail), (u_c, c_mail), (u_m2, m2_mail), (u_x, x_mail)) as x(id, mail);
  insert into public.usuarios (user_id, email, nombre, rol, herramientas, proyectos, activo, numero_usuario) values
    (u_m, m_mail, 'MgrA2', 'agente', array['comisiones'], '{}', true, 'USR-PRB98C-1'),
    (u_c, c_mail, 'CloserA2', 'agente', array['comisiones'], '{}', true, 'USR-PRB98C-2'),
    (u_m2, m2_mail, 'MgrB2', 'agente', array['comisiones'], '{}', true, 'USR-PRB98C-3'),
    (u_x, x_mail, 'MiembroB2', 'agente', array['comisiones'], '{}', true, 'USR-PRB98C-4');
  insert into public.equipos_venta (id, nombre, manager_email, activo) values
    (eqA, 'PRB98C EquipoA', m_mail, true), (eqB, 'PRB98C EquipoB', m2_mail, true);
  insert into public.equipo_miembros (equipo_id, closer_email, desde, hasta, added_by) values
    (eqA, c_mail, '2000-01-01', null, 'PRB98C'), (eqB, x_mail, '2000-01-01', null, 'PRB98C');
  insert into public.condiciones_comision (id, equipo_id, nivel, closer_email, pct_comision, base_calculo, activo, vigente_desde) values
    (kA, eqA, 'manager', null, 2.5, 'precio_total', true, '2000-01-01'),
    (kB, eqB, 'manager', null, 2.5, 'precio_total', true, '2000-01-01');
  insert into public.condicion_tramos (id, condicion_id, orden, disparador_tipo, pct_tramo) values
    (tA, kA, 1, 'contrato_firmado', 100), (tB, kB, 1, 'contrato_firmado', 100);

  -- la venta: closer/manager congelados en el equipo A
  insert into public.contrato_closer (contrato_id, closer_email, asignado_por, fecha_venta, equipo_id, manager_email, equipo_congelado_en)
  values (vx, c_mail, 'PRB98C', current_date, eqA, m_mail, now())
  on conflict (contrato_id) do update set closer_email = excluded.closer_email, asignado_por = excluded.asignado_por,
    fecha_venta = excluded.fecha_venta, equipo_id = excluded.equipo_id, manager_email = excluded.manager_email,
    equipo_congelado_en = excluded.equipo_congelado_en;

  -- reclamación de venta propia APROBADA por el manager del equipo B — equipo distinto del congelado
  insert into public.reclamaciones_venta_propia (id, contrato_raiz_id, solicitante_email, equipo_id, manager_email, motivo, estado, resuelto_por, resuelto_en)
  values (gen_random_uuid(), vx, m2_mail, eqB, m2_mail, 'prueba axw98c', 'aprobada', 'sistema', now())
  returning id into rp_id;

  v_base := public._comisiones_precio_total(vx);
  insert into public.solicitudes_pago (id, numero, contrato_id, concepto, importe, moneda, estado, origen, beneficiario_email, creado_por)
  overriding system value
  values (sp_id, 999000099, vx, 'Comisión propia PRB98C a fecha de disparo: ' || round(v_base, 2) || ' ' || v_mon,
          round(0.025 * v_base, 2), v_mon, 'pendiente', 'comision_automatica', m2_mail,
          (select u.user_id from public.usuarios u where u.email = m2_mail));
  -- devengo nivel 'propia', snapshot con equipo_id = eqB (el de la reclamación) — así lo construye el motor real
  insert into public.comisiones_devengadas (id, contrato_raiz_id, tramo_id, condicion_id, beneficiario_email, nivel, importe, moneda,
                                            disparado_en, disparado_por_snapshot, solicitud_id, estado)
  values (d_propia, vx, tB, kB, m2_mail, 'propia', round(0.025 * v_base, 2), v_mon, now(),
          jsonb_build_object('base_calculo', 'precio_total', 'base_valor', v_base, 'precio_total', v_base, 'equipo_id', eqB, 'reclamacion_id', rp_id),
          sp_id, 'pendiente');
  execute 'set local session_replication_role = origin';

  select equipo_id into v_eq_venta from public._equipo_de_venta(vx);
  select (disparado_por_snapshot->>'equipo_id')::uuid into v_eq_snapshot from public.comisiones_devengadas where id = d_propia;
  r := r || format(E'\nPRE: _equipo_de_venta = %s (congelado=A), snapshot del devengo propia = %s (equipo B) — distintos: %s',
        v_eq_venta, v_eq_snapshot, v_eq_venta <> v_eq_snapshot);
  if v_eq_venta = v_eq_snapshot then
    raise exception 'la prueba no monta lo que dice: los dos equipos salieron iguales';
  end if;

  -- x_mail: miembro de equipo B, NI beneficiario de este devengo NI del equipo congelado A
  perform set_config('request.jwt.claims', json_build_object('sub', u_x, 'email', x_mail, 'role', 'authenticated')::text, true);
  execute 'set local session_replication_role = replica';
  update public.contratos set precio_total = precio_total + 10000 where id = vx;
  execute 'set local session_replication_role = origin';
  perform public.comisiones_reconciliar(vx, false, jsonb_build_object('prueba', 'axw98c'));

  select estado, motivo into v_estado, v_mot from public.comisiones_diferencias where devengo_id = d_propia order by created_at desc limit 1;
  r := r || format(E'\nCASO: miembro del equipo B (no beneficiario, no del equipo congelado A) sube el precio → estado=%s motivo=%s → %s',
        v_estado, v_mot,
        case when v_estado = 'revisar' and v_mot like 'subida_mismo_equipo%' then 'ok'
             else 'FALLA — el equipo por-devengo no está funcionando, el hueco de colusión sigue abierto' end);

  perform set_config('request.jwt.claims', '', true);
  raise exception 'FIN PRUEBA VENTA PROPIA OTRO EQUIPO (se deshace):%', r;
end $$;
