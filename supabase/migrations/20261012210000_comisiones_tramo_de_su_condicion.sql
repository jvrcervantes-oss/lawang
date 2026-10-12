-- LAW-539 (12-oct-2026). Arreglo de datos de 20261012190000_comisiones_10pct_retroactivo.
--
-- Qué pasó: aquella migración cambió `condicion_id` de 6 devengos a las condiciones nuevas del 10 % pero
-- dejó su `tramo_id` en 3e84da5b, el tramo de la condición vieja 2ad6c563. comisiones_evaluar_contrato fija
-- la condición por el primer devengo, recorre los tramos de ESA condición y busca el devengo previo por
-- `tramo_id`; su `on conflict` es (contrato_raiz_id, tramo_id, beneficiario_email). Con el tramo de otra
-- condición no veía el devengo existente y habría insertado un segundo devengo con su solicitud de pago en
-- el siguiente cobro, firma o cambio de precio de esos contratos (RP00161, 162, 164, 181, 200, 211;
-- 33.220,40 EUR en total, todos «pendiente»).
--
-- Qué hace: pone en esas 6 filas el tramo de SU condición. No cambia importes, estados, beneficiarios ni
-- solicitudes. Deja un apunte por fila en comisiones_ajustes_log.
--
-- YA APLICADO EN PRODUCCIÓN el 12-oct-2026 (11:49 UTC) con este mismo cuerpo, por orden del owner
-- («Arreglarlo esta noche» / «Aplícalo tú esta noche»), tras la prueba de control (sin arreglo: 6 -> 12
-- devengos, 33.220,40 -> 66.440,80) y la prueba con arreglo (6 -> 6, mal enlazados 6 -> 0), las dos en
-- transacción deshecha; el revisor aprobó el bloque. Después: 0 devengos con el tramo de otra condición en
-- toda la tabla, huellas de devengo y de solicitud idénticas, apuntes 292-297 en comisiones_ajustes_log.
--
-- Este fichero es la constancia en el repositorio. Es IDEMPOTENTE: sobre una base ya arreglada salta las 6
-- filas sin escribir nada (ni cambio ni apunte doble) y la comprobación final pasa.
-- Pruebas, foto, detección y vuelta atrás: contracts/sql/comisiones_tramo_12oct/.
-- Pendiente aparte (owner + consulta a Datos): clave compuesta (tramo_id, condicion_id) ->
-- condicion_tramos(id, condicion_id) para que este fallo sea imposible.

do $$
declare
  c_tramo_viejo constant uuid := '3e84da5b-76cf-4320-8df2-0f54ceed9400';
  v_motivo      constant text := 'tramo de la condición vieja 2,5 % → tramo de su condición 10 % (arreglo de 20261012190000; owner 12-oct-2026)';
  v_raiz uuid;
  v_numero text;
  f record;
  d public.comisiones_devengadas;
begin
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
end $$;
