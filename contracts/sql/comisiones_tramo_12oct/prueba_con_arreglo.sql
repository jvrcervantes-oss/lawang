-- PRUEBA (con arreglo) — 12-oct-2026. Un solo bloque DO que TERMINA en raise exception: todo se deshace,
-- también el arreglo. Aplica DENTRO de la transacción el mismo cambio que
-- 20261012210000_comisiones_tramo_de_su_condicion (bloque «el arreglo» = cuerpo de la migración, con su
-- candado por raíz, comprobaciones y apunte en comisiones_ajustes_log) y después recorre el camino real de una firma (comisiones_reconciliar +
-- comisiones_evaluar_contrato, lo que hace _trg_comisiones_reconcilia_contrato; facturas y recibí llaman
-- solo a evaluar) en los 6 contratos.
-- Resultado esperado: «devengos 6 -> 6, solicitudes 6 -> 6, importe 33220.40 -> 33220.40, mal enlazados 6 -> 0»
-- y por contrato «1 dev / 1 sp». La prueba solo vale si el detalle no trae ningún «ERROR» y si
-- prueba_sin_arreglo.sql dio 2 dev / 2 sp en ESE contrato (si no, el control no prueba nada para él).
--
-- Efectos fuera de la transacción: los mismos que en prueba_sin_arreglo.sql. Con el arreglo no se inserta
-- ninguna solicitud, así que no se espera gastar ningún número SP; los 6 apuntes del arreglo gastan 6 ids de
-- comisiones_ajustes_log (identity, hueco invisible).

do $$
declare
  c_tramo_viejo constant uuid := '3e84da5b-76cf-4320-8df2-0f54ceed9400';
  v_motivo      constant text := 'tramo de la condición vieja 2,5 % → tramo de su condición 10 % (arreglo de 20261012190000; owner 12-oct-2026)';
  v_raiz uuid;
  v_numero text;
  v_raices uuid[] := array[
    '6ac803d6-12fa-4e5d-adf1-cfd35910d34f',  -- RP00164
    'e73fa119-c48d-4470-8a52-1127a0727751',  -- RP00181
    '267ff2c0-1d90-4c97-84f7-4d306896be1b',  -- RP00211
    'e82e3db0-5cd5-4e60-b836-0a1dfb95868c',  -- RP00161
    'ae3b8523-76ab-4e4d-b348-ee1366c146ec',  -- RP00162
    'c1abc6f8-15ca-4e87-80e8-390f21cfc32d'   -- RP00200
  ]::uuid[];
  v_dev0 int; v_sp0 int; v_dev1 int; v_sp1 int; v_imp0 numeric; v_imp1 numeric; v_mal0 int; v_mal1 int;
  v_det text := '';
  f record;
  r record;
  d public.comisiones_devengadas;
begin
  select count(*), sum(coalesce(importe_ajustado, importe)) into v_dev0, v_imp0
    from public.comisiones_devengadas where contrato_raiz_id = any(v_raices) and estado <> 'anulada';
  select count(*) into v_sp0
    from public.solicitudes_pago where contrato_id = any(v_raices) and origen = 'comision_automatica' and estado <> 'anulada';
  select count(*) into v_mal0
    from public.comisiones_devengadas cd join public.condicion_tramos t on t.id = cd.tramo_id where t.condicion_id <> cd.condicion_id;

  -- ===== el arreglo: MISMO cuerpo que llevará la migración 20261012210000 (revisor 12-oct: la prueba lo envuelve
  -- entero, con candado por raíz, comprobaciones y apunte en comisiones_ajustes_log; no se exige «pendiente»:
  -- una comisión pagada con el tramo viejo es justo el caso más caro, se arregla igual y el log guarda su estado)
  for f in
    select * from (values
      ('a23fb382-0771-40d6-8661-7e068cdfffb8'::uuid, 'RP00164', 'c0a10000-1012-4a10-8000-000000000001'::uuid, 'fb47da81-95e8-4340-b517-774b40b6a812'::uuid),
      ('99103540-0741-45f2-91f3-59e1fb3fe9f4'::uuid, 'RP00181', 'c0a10000-1012-4a10-8000-000000000001'::uuid, 'fb47da81-95e8-4340-b517-774b40b6a812'::uuid),
      ('95230454-a5b6-4a19-a926-8f429fa67f1c'::uuid, 'RP00211', 'c0a10000-1012-4a10-8000-000000000001'::uuid, 'fb47da81-95e8-4340-b517-774b40b6a812'::uuid),
      ('d347bd12-13f5-419f-9341-1b500437b2d8'::uuid, 'RP00161', 'c0a10000-1012-4a10-8000-000000000002'::uuid, '6d09d8bf-f5a5-485b-95a9-e7603d57ccb3'::uuid),
      ('0338276a-5312-49bc-b282-61fbcd72cf3e'::uuid, 'RP00162', 'c0a10000-1012-4a10-8000-000000000002'::uuid, '6d09d8bf-f5a5-485b-95a9-e7603d57ccb3'::uuid),
      ('1c493584-88ba-4fe1-b8f3-3affa186dcc9'::uuid, 'RP00200', 'c0a10000-1012-4a10-8000-000000000002'::uuid, '6d09d8bf-f5a5-485b-95a9-e7603d57ccb3'::uuid)
    ) x(devengo_id, numero, condicion_id, tramo_nuevo)
  loop
    select cd.contrato_raiz_id into v_raiz from public.comisiones_devengadas cd where cd.id = f.devengo_id;
    if v_raiz is null then
      raise exception 'tramo 12-oct: no existe el devengo % (%)', f.devengo_id, f.numero;
    end if;
    -- el mismo candado que toman comisiones_evaluar_contrato y comisiones_reconciliar
    perform pg_advisory_xact_lock(hashtext('comisiones:' || v_raiz::text));

    select cd.* into d from public.comisiones_devengadas cd where cd.id = f.devengo_id for update;
    select c.numero into v_numero from public.contratos c where c.id = d.contrato_raiz_id;

    if d.tramo_id = f.tramo_nuevo and d.condicion_id = f.condicion_id then
      continue;  -- ya arreglada: sin cambio, sin apunte doble
    end if;

    if v_numero is distinct from f.numero or d.condicion_id <> f.condicion_id or d.tramo_id <> c_tramo_viejo
       or d.nivel <> 'estandar' then
      raise exception 'tramo 12-oct: % (%) no está como se midió (contrato %, condición %, tramo %, nivel %)',
        f.numero, f.devengo_id, v_numero, d.condicion_id, d.tramo_id, d.nivel;
    end if;

    if not exists (select 1 from public.condicion_tramos t where t.id = f.tramo_nuevo and t.condicion_id = f.condicion_id) then
      raise exception 'tramo 12-oct: el tramo % no es de la condición %', f.tramo_nuevo, f.condicion_id;
    end if;

    if exists (select 1 from public.comisiones_devengadas x
                where x.contrato_raiz_id = d.contrato_raiz_id and x.tramo_id = f.tramo_nuevo and x.id <> d.id) then
      raise exception 'tramo 12-oct: % ya tiene otro devengo en el tramo %: revisar a mano (posible duplicado)', f.numero, f.tramo_nuevo;
    end if;

    update public.comisiones_devengadas set tramo_id = f.tramo_nuevo where id = d.id;

    insert into public.comisiones_ajustes_log
      (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
    values
      ('comisiones_devengadas', d.id, 'recalcular',
       coalesce(d.importe_ajustado, d.importe), coalesce(d.importe_ajustado, d.importe), d.estado, d.estado,
       v_motivo || ' — ' || f.numero,
       jsonb_build_object('tramo_antes', d.tramo_id, 'tramo_despues', f.tramo_nuevo,
                          'condicion', d.condicion_id, 'arreglo', '20261012210000_comisiones_tramo_de_su_condicion'));
  end loop;

  if exists (select 1 from public.comisiones_devengadas cd
               join public.condicion_tramos t on t.id = cd.tramo_id
              where t.condicion_id <> cd.condicion_id) then
    raise exception 'tramo 12-oct: tras el arreglo sigue habiendo devengos con el tramo de otra condición';
  end if;
  -- ===== fin del arreglo

  for r in select c.id, c.numero from public.contratos c where c.id = any(v_raices) order by c.numero loop
    begin
      perform public.comisiones_reconciliar(r.id, false, jsonb_build_object('origen', 'prueba_tramo_12oct'));
      perform public.comisiones_evaluar_contrato(r.id);
    exception when others then
      v_det := v_det || r.numero || ' ERROR ' || sqlerrm || '; ';
    end;
    v_det := v_det || r.numero || ' '
      || (select count(*) from public.comisiones_devengadas d2 where d2.contrato_raiz_id = r.id and d2.estado <> 'anulada') || ' dev / '
      || (select count(*) from public.solicitudes_pago s where s.contrato_id = r.id and s.origen = 'comision_automatica' and s.estado <> 'anulada') || ' sp; ';
  end loop;

  select count(*), sum(coalesce(importe_ajustado, importe)) into v_dev1, v_imp1
    from public.comisiones_devengadas where contrato_raiz_id = any(v_raices) and estado <> 'anulada';
  select count(*) into v_sp1
    from public.solicitudes_pago where contrato_id = any(v_raices) and origen = 'comision_automatica' and estado <> 'anulada';
  select count(*) into v_mal1
    from public.comisiones_devengadas cd join public.condicion_tramos t on t.id = cd.tramo_id where t.condicion_id <> cd.condicion_id;

  raise exception 'PRUEBA CON ARREGLO (se deshace todo): devengos % -> %, solicitudes % -> %, importe % -> %, mal enlazados % -> % | %',
    v_dev0, v_dev1, v_sp0, v_sp1, v_imp0, v_imp1, v_mal0, v_mal1, v_det;
end $$;
