-- Comisiones: el 10 % vale también hacia atrás (owner 12-oct-2026).
--
-- Regla del owner: Lawang paga el 10 % del precio total (parcela + construcción) al equipo
-- cuando se ha cobrado el 50 % de la parcela. Revisión del 12-oct, con sus tres decisiones:
--
-- 1) Venta sin equipo anterior al 30-sep: se devengaba al 2,5 % (el 10 % solo valía desde el
--    30-sep). Owner: subirlas al 10 %. Condición nueva 10 % vigente 1900-01-01..2026-09-29 por
--    empresa; empata en vigente_desde con la de 2,5 % y gana por created_at (orden del motor).
--    Las de 2,5 % NO se reescriben: RP00025 (Carmen, sales@, pagada el 8-oct) sigue en ella,
--    decisión del 30-sep («las ventas pasadas de Carmen sin comisión nueva, SP-47 intacta»).
-- 2) Las 6 comisiones pendientes de esas ventas (RP00161, RP00162, RP00164, RP00181, RP00200,
--    RP00211) se apuntan a la condición nueva de su empresa y comisiones_reconciliar las pone al
--    10 % con su solicitud de pago (estaban pendientes, nada aprobado ni pagado).
-- 3) Equipo de Victor: no tenía condición de manager antes del 30-sep fuera de Palm Field, así que
--    RP00202 (Bonian, 24-sep, 94,8 % de la parcela cobrado) no generaba nada. Condición nueva
--    10 % 1900-01-01..2026-09-29, como la de Gus («Victor como Gus», owner 30-sep).
-- 4) Palm Field W5 (equipo de Victor) pagaba 50 % al 50 % de la parcela y 50 % al 100 %. Owner:
--    igualar a la regla general. Sin comisiones generadas: se desactiva y manda la general.
--
-- Idempotente: ids fijos, cada paso comprueba antes de escribir.

do $$
declare
  c_std_lw   constant uuid := 'c0a10000-1012-4a10-8000-000000000001';
  c_std_sw   constant uuid := 'c0a10000-1012-4a10-8000-000000000002';
  c_victor   constant uuid := 'c0a10000-1012-4a10-8000-000000000003';
  c_viejo    constant uuid := '2ad6c563-e82c-4826-8758-55a5441e334a';  -- estándar 2,5 % lawang hasta 29-sep
  c_palm     constant uuid := '0864530b-0d6b-4a03-b6de-538029c66454';  -- Palm Field 50/50 equipo Victor
  e_victor   constant uuid := '7124be6e-a9bf-45d3-a775-5cc29f9d8259';
  v_motivo   constant text := 'owner 12-oct-2026: el 10 % del precio total al cobrar el 50 % de la parcela vale también hacia atrás';
  d record;
  v_raiz uuid;
begin
  -- 1) condiciones nuevas
  insert into public.condiciones_comision
    (id, nivel, activo, empresa, equipo_id, proyecto_id, base_calculo, pct_comision, vigente_desde, vigente_hasta, created_by)
  values
    (c_std_lw, 'closer',  true, 'lawang',       null,     null, 'precio_total', 10, '1900-01-01', '2026-09-29', v_motivo),
    (c_std_sw, 'closer',  true, 'sandal_woods', null,     null, 'precio_total', 10, '1900-01-01', '2026-09-29', v_motivo),
    (c_victor, 'manager', true, 'lawang',       e_victor, null, 'precio_total', 10, '1900-01-01', '2026-09-29', v_motivo)
  on conflict (id) do nothing;

  insert into public.condicion_tramos (condicion_id, orden, umbral, pct_tramo, disparador_tipo)
  select x.id, 1, 50, 100, 'pct_cobrado_suelo'
    from (values (c_std_lw), (c_std_sw), (c_victor)) x(id)
   where not exists (select 1 from public.condicion_tramos t where t.condicion_id = x.id);

  insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
  select c.id, null, to_jsonb(c), 'creada: ' || v_motivo
    from public.condiciones_comision c
   where c.id in (c_std_lw, c_std_sw, c_victor)
     and not exists (select 1 from public.condiciones_comision_log l where l.condicion_id = c.id);

  -- 4) Palm Field 50/50 fuera
  if exists (select 1 from public.condiciones_comision where id = c_palm and activo) then
    if exists (select 1 from public.comisiones_devengadas where condicion_id = c_palm) then
      raise exception 'Palm Field ya ha generado comisiones: revisar a mano antes de desactivar';
    end if;
    insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
    values (c_palm, jsonb_build_object('activo', true), jsonb_build_object('activo', false),
            'desactivada: owner 12-oct-2026, Palm Field se paga como el resto (100 % al cobrar el 50 % de la parcela)');
    update public.condiciones_comision set activo = false where id = c_palm;
  end if;

  -- 2) las 6 pendientes al 2,5 % pasan a la condición del 10 % de su empresa y se recalculan
  for d in
    select cd.id, cd.contrato_raiz_id, cd.solicitud_id,
           case public._empresa_de_proyecto_int(c.proyecto_id) when 'sandal_woods' then c_std_sw else c_std_lw end as nueva
      from public.comisiones_devengadas cd
      join public.contratos c on c.id = cd.contrato_raiz_id
     where cd.condicion_id = c_viejo
       and cd.nivel = 'estandar'
       and cd.estado = 'pendiente'
       and c.numero in ('RP00161', 'RP00162', 'RP00164', 'RP00181', 'RP00200', 'RP00211')
  loop
    update public.comisiones_devengadas cd
       set condicion_id = d.nueva,
           disparado_por_snapshot = cd.disparado_por_snapshot
             || jsonb_build_object('pct_comision', 10, 'condicion_anterior', c_viejo,
                                   'pct_anterior', 2.5, 'reapuntada_en', now(), 'reapuntada_motivo', v_motivo)
     where cd.id = d.id;

    insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
    values ('comisiones_devengadas', d.id, 'recalcular', null, null, 'pendiente', 'pendiente',
            'condición 2,5 % → 10 %: ' || v_motivo,
            jsonb_build_object('condicion_antes', c_viejo, 'condicion_despues', d.nueva));

    perform public.comisiones_reconciliar(d.contrato_raiz_id, false, jsonb_build_object('origen', 'owner_12oct_10pct_retro'));

    -- el concepto de la solicitud decía «2.5% s/ precio total»
    if d.solicitud_id is not null then
      perform set_config('app.via_recalculo_comision', 'on', true);
      update public.solicitudes_pago
         set concepto = replace(concepto, ' — 2.5% s/ ', ' — 10% s/ ')
       where id = d.solicitud_id and estado = 'pendiente' and concepto like '% — 2.5\% s/ %';
      perform set_config('app.via_recalculo_comision', 'off', true);
    end if;
  end loop;

  -- 3) RP00202 genera su comisión con la condición nueva del equipo de Victor
  select id into v_raiz from public.contratos where numero = 'RP00202' and contrato_padre_id is null;
  if v_raiz is not null then
    perform public.comisiones_evaluar_contrato(v_raiz);
  end if;
end $$;
