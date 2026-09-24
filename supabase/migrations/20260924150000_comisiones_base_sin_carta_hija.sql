-- Comisiones: la Carta de Reserva hija NO suma al precio de la venta (24-sep-2026, owner).
--
-- Síntoma: SP-53 (RP00122) «10% s/ precio total … 327065.00 EUR» y SP-54 (RP00046) «153000.00 EUR».
-- Causa: comisiones_evaluar_contrato sumaba precio_total de la raíz y de TODOS sus hijos. La Carta de
-- Reserva (carta_reserva, carta_reserva_pma…) cuelga de la RP y su precio_total ya es el total del
-- negocio (suelo + obra), que la RP y el CC vuelven a declarar → la venta contaba dos veces.
--   RP00046: CR 76.500 + RP 30.525 + CC 45.975 = 153.000  (bien: 76.500)
--   RP00122: CR 163.500 + RP 64.565 + CC 99.000 = 327.065 (bien: 163.565)
-- Misma familia que el /portal/ sumando la Carta de Reserva (memoria project_lawang_portal_carta_reserva_duplicada).
-- Hermana: crm_ranking_closers metía la carta hija en «firmado» y en el recuento de contratos.
--
-- Solo se excluye la carta HIJA: una carta raíz (reserva sin RP todavía) sigue siendo la venta.
-- Parche por marca sobre la definición viva (el .sql del repo no es la verdad de la función).

do $$
declare d text; m text; n text;
begin
  -- 1) motor
  d := pg_get_functiondef('public.comisiones_evaluar_contrato(uuid)'::regprocedure);
  if position('x.tipo like ''carta_reserva%''' in d) = 0 then
    m := '   where x.id = v_raiz_id or x.contrato_padre_id = v_raiz_id;';
    n := E'   where (x.id = v_raiz_id or x.contrato_padre_id = v_raiz_id)\n     and not (x.contrato_padre_id is not null and x.tipo like ''carta_reserva%'');';
    if position(m in d) = 0 then
      raise exception 'comisiones_evaluar_contrato: marca de la suma de precio_total no encontrada';
    end if;
    execute replace(d, m, n);
  end if;

  -- 2) ranking
  d := pg_get_functiondef('public.crm_ranking_closers(boolean)'::regprocedure);
  if position('c.tipo like ''carta_reserva%''' in d) = 0 then
    m := '       and (not coalesce(p_solo_raices, false) or c.contrato_padre_id is null)';
    n := m || E'\n       and not (c.contrato_padre_id is not null and c.tipo like ''carta_reserva%'')';
    if position(m in d) = 0 then
      raise exception 'crm_ranking_closers: marca del filtro de raíces no encontrada';
    end if;
    execute replace(d, m, n);
  end if;
end $$;

-- 3) Corregir lo ya devengado con la base doblada. Solo pendientes: si alguno ya está aprobado,
--    pagado o en disputa, se para (eso es complementaria/recuperación, decisión de Administración).
do $$
declare r record; v_base numeric; v_imp numeric; v_sp record; v_con text;
begin
  if exists (
    select 1 from public.comisiones_devengadas d
     where exists (select 1 from public.contratos h
                    where h.contrato_padre_id = d.contrato_raiz_id and h.tipo like 'carta_reserva%')
       and d.disparado_por_snapshot->>'base_calculo' = 'precio_total'
       and d.estado not in ('pendiente', 'anulada')
  ) then
    raise exception 'hay devengos con carta hija fuera de pendiente: corregir a mano con Administración';
  end if;

  -- la solicitud automática es inmutable por su trigger (concepto congelado, importe solo admin con
  -- sesión): la corrección del motor se hace sin triggers y deja su rastro en comisiones_ajustes_log
  set local session_replication_role = replica;

  for r in
    select d.* from public.comisiones_devengadas d
     where d.estado = 'pendiente'
       and d.disparado_por_snapshot->>'base_calculo' = 'precio_total'
       and exists (select 1 from public.contratos h
                    where h.contrato_padre_id = d.contrato_raiz_id and h.tipo like 'carta_reserva%')
  loop
    select coalesce(sum(x.precio_total), 0) into v_base
      from public.contratos x
     where (x.id = r.contrato_raiz_id or x.contrato_padre_id = r.contrato_raiz_id)
       and not (x.contrato_padre_id is not null and x.tipo like 'carta_reserva%');
    if v_base = (r.disparado_por_snapshot->>'base_valor')::numeric then
      continue;
    end if;
    v_imp := round(((r.disparado_por_snapshot->>'pct_comision')::numeric / 100) * v_base
             * ((r.disparado_por_snapshot->>'pct_tramo')::numeric / 100), 2);

    insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues,
                                               estado_antes, estado_despues, motivo, copia)
    values ('comisiones_devengadas', r.id, 'recalcular', r.importe, v_imp, r.estado, r.estado,
            'Base doblada: el motor sumaba la Carta de Reserva hija al precio de la venta (' ||
            round((r.disparado_por_snapshot->>'base_valor')::numeric, 2) || ' → ' || round(v_base, 2) || ')',
            to_jsonb(r));

    update public.comisiones_devengadas
       set importe = v_imp,
           disparado_por_snapshot = disparado_por_snapshot
             || jsonb_build_object('base_valor', v_base, 'precio_total', v_base,
                                   'corregido_24sep', 'carta de reserva hija excluida de la base')
     where id = r.id;

    if r.solicitud_id is not null then
      select * into v_sp from public.solicitudes_pago where id = r.solicitud_id;
      if v_sp.estado = 'pendiente' then
        v_con := replace(v_sp.concepto,
                         round((r.disparado_por_snapshot->>'base_valor')::numeric, 2)::text,
                         round(v_base, 2)::text);
        insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues,
                                                   estado_antes, estado_despues, motivo, copia)
        values ('solicitudes_pago', v_sp.id, 'recalcular', v_sp.importe, v_imp, v_sp.estado, v_sp.estado,
                'Base doblada por la Carta de Reserva hija (corrección del motor)', to_jsonb(v_sp));
        update public.solicitudes_pago set importe = v_imp, concepto = v_con where id = v_sp.id;
      end if;
    end if;
  end loop;
  -- los triggers vuelven a su sitio para lo que venga después en la misma transacción
  set local session_replication_role = origin;
end $$;
