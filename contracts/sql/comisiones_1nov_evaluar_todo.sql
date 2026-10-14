-- Las ventas de hoy no cambian con el motor nuevo (migración comisiones_regla_1nov, 13-oct-2026).
-- Se ejecuta DOS veces en la ventana de la válvula: ANTES de aplicar la migración (motor viejo) y DESPUÉS (motor nuevo).
-- Correcto = mismo «creados» y mismo md5 las dos veces. NO ESCRIBE NADA: termina en excepción.
-- ⚠ Necesita la válvula del owner (session_replication_role para desactivar usuarios dentro de la transacción: así el
--   motor no resuelve creado_por y no crea solicitudes de pago, que consumirían la serie SP; LAW-217).
-- Límite: con los usuarios desactivados el motor sale antes en las ventas sin equipo («estándar»/«propia» miran
-- crm_usuario_activo); esas se cubren con las dos pasadas de comisiones_reconciliar (0 diferencias) y la foto.
do $$
declare v_sp0 bigint; v_n int := 0; v_r uuid; v_h text; v_c int; v_det text;
begin
  select last_value into v_sp0 from public.solicitudes_pago_numero_seq;
  execute 'set local session_replication_role = replica';
  -- 14-oct-2026: el propietario no puede quedar inactivo (usuarios_propietario_check); se le quita la marca en la
  -- misma transacción, que se deshace entera. Si quedara activo, el motor lo usaría de creado_por y gastaría la serie SP.
  update public.usuarios set activo = false, es_propietario = false where activo = true;
  execute 'set local session_replication_role = origin';
  create temp table _antes_ev on commit drop as select id from public.comisiones_devengadas;
  for v_r in select c.id from public.contratos c join public.contrato_closer k on k.contrato_id = c.id
              where c.contrato_padre_id is null and k.closer_email is not null order by c.id loop
    v_n := v_n + public.comisiones_evaluar_contrato(v_r);
  end loop;
  select count(*), md5(coalesce(string_agg(d.contrato_raiz_id || ':' || d.tramo_id || ':' || d.beneficiario_email || ':' || d.nivel
                                          || ':' || d.importe, '|' order by d.contrato_raiz_id, d.tramo_id, d.beneficiario_email), '')),
         coalesce(string_agg((select x.numero from public.contratos x where x.id = d.contrato_raiz_id) || '/' || d.nivel || '/' || d.importe, ', '), '-')
    into v_c, v_h, v_det
    from public.comisiones_devengadas d where d.id not in (select a.id from _antes_ev a);
  raise exception 'EVAL: creados=% filas_nuevas=% md5=% [%] serie SP %/%', v_n, v_c, v_h, v_det,
    v_sp0, (select last_value from public.solicitudes_pago_numero_seq);
end $$;
