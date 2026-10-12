-- VUELTA ATRÁS de 20261012210000_comisiones_tramo_de_su_condicion (12-oct-2026).
-- OJO: restaura el FALLO (tramo de la condición vieja en 6 devengos de la nueva → riesgo de segundo devengo
-- y segunda solicitud en el próximo cobro/firma). Solo si el arreglo resultara equivocado, y con el owner.
-- Devuelve tramo_id = 3e84da5b SOLO en las filas que siguen exactamente como las dejó el arreglo, y aborta
-- si entre medias el motor ha creado otro devengo en el tramo viejo (chocaría con la UNIQUE).
-- Queda en comisiones_ajustes_log. No toca importes, estados, solicitudes ni triggers.

do $$
declare
  c_tramo_viejo constant uuid := '3e84da5b-76cf-4320-8df2-0f54ceed9400';
  f record;
  d public.comisiones_devengadas;
  v_raiz uuid;
begin
  for f in
    select * from (values
      ('a23fb382-0771-40d6-8661-7e068cdfffb8'::uuid, 'c0a10000-1012-4a10-8000-000000000001'::uuid, 'fb47da81-95e8-4340-b517-774b40b6a812'::uuid),
      ('99103540-0741-45f2-91f3-59e1fb3fe9f4'::uuid, 'c0a10000-1012-4a10-8000-000000000001'::uuid, 'fb47da81-95e8-4340-b517-774b40b6a812'::uuid),
      ('95230454-a5b6-4a19-a926-8f429fa67f1c'::uuid, 'c0a10000-1012-4a10-8000-000000000001'::uuid, 'fb47da81-95e8-4340-b517-774b40b6a812'::uuid),
      ('d347bd12-13f5-419f-9341-1b500437b2d8'::uuid, 'c0a10000-1012-4a10-8000-000000000002'::uuid, '6d09d8bf-f5a5-485b-95a9-e7603d57ccb3'::uuid),
      ('0338276a-5312-49bc-b282-61fbcd72cf3e'::uuid, 'c0a10000-1012-4a10-8000-000000000002'::uuid, '6d09d8bf-f5a5-485b-95a9-e7603d57ccb3'::uuid),
      ('1c493584-88ba-4fe1-b8f3-3affa186dcc9'::uuid, 'c0a10000-1012-4a10-8000-000000000002'::uuid, '6d09d8bf-f5a5-485b-95a9-e7603d57ccb3'::uuid)
    ) x(devengo_id, condicion_id, tramo_nuevo)
  loop
    select cd.contrato_raiz_id into v_raiz from public.comisiones_devengadas cd where cd.id = f.devengo_id;
    if v_raiz is null then
      raise exception 'vuelta atrás: no existe el devengo %', f.devengo_id;
    end if;
    -- el mismo candado que toman comisiones_evaluar_contrato y comisiones_reconciliar
    perform pg_advisory_xact_lock(hashtext('comisiones:' || v_raiz::text));
    select cd.* into d from public.comisiones_devengadas cd where cd.id = f.devengo_id for update;
    if d.tramo_id = c_tramo_viejo then
      continue;  -- ya revertida
    end if;
    if d.condicion_id <> f.condicion_id then
      raise exception 'vuelta atrás: el devengo % ya no está en la condición % (tiene %): revisar a mano', d.id, f.condicion_id, d.condicion_id;
    end if;
    if d.tramo_id <> f.tramo_nuevo then
      raise exception 'vuelta atrás: el devengo % tiene el tramo % (ni el viejo ni el del arreglo): revisar a mano', d.id, d.tramo_id;
    end if;
    if exists (select 1 from public.comisiones_devengadas x
                where x.contrato_raiz_id = d.contrato_raiz_id and x.tramo_id = c_tramo_viejo and x.id <> d.id) then
      raise exception 'vuelta atrás: el contrato del devengo % ya tiene otro devengo en el tramo viejo', d.id;
    end if;

    update public.comisiones_devengadas set tramo_id = c_tramo_viejo where id = d.id;

    insert into public.comisiones_ajustes_log
      (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
    values
      ('comisiones_devengadas', d.id, 'recalcular',
       coalesce(d.importe_ajustado, d.importe), coalesce(d.importe_ajustado, d.importe), d.estado, d.estado,
       'vuelta atrás de 20261012210000: tramo de su condición → tramo viejo 3e84da5b',
       jsonb_build_object('tramo_antes', d.tramo_id, 'tramo_despues', c_tramo_viejo, 'vuelta_atras_de', '20261012210000'));
  end loop;
end $$;
