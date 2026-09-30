-- destructivo-ok: sin DROP; solo `create or replace function` sobre `comisiones_reconciliar`.
-- Corrige 20260930170000 (misma sesión, ya aplicada): agencia-0b adaptó la batería de 24 casos de
-- erp/pruebas/b3c_comisiones_subida_mismo_equipo.sql (maestro) a Lawang y encontró que el caso A3
-- (venta propia reclamada por OTRO equipo) fallaba contra 20260930170000.
--
-- Causa: 20260930170000 sacaba el equipo de la venta UNA sola vez por llamada con
-- `_equipo_de_venta(p_raiz)` (el del closer/manager congelados en `contrato_closer`). El maestro
-- (canon, B3c) lo saca del SNAPSHOT DE CADA DEVENGO (`disparado_por_snapshot->>'equipo_id'`), y
-- solo cae a `_equipo_de_venta` si el devengo no lo trae. Para un devengo normal los dos coinciden,
-- pero para un devengo 'propia' (reclamación de venta propia aprobada) el snapshot lleva el equipo
-- DE QUIEN RECLAMÓ (`v_propia.equipo_id` en el motor, `comisiones_evaluar_contrato`), que puede ser
-- distinto del equipo del closer original — y ES la fila 'equipo_id' que el motor de Lawang YA
-- guarda en el snapshot de TODO devengo desde siempre (supabase/migrations/20260924160000_comisiones_roles_venta_propia_ajuste_sm.sql:488),
-- así que Lawang no necesita el fallback casi nunca — usarlo bien es lo correcto, no una aproximación.
--
-- Arreglo: el equipo (y v_mismo_equipo) se calcula DENTRO del bucle, por devengo, con la misma
-- prioridad snapshot→`_equipo_de_venta` del maestro. El resto de la regla (los 5 caminos de
-- pertenencia: parte de la venta, roles de la venta, venta propia, manager de hoy, miembro el día
-- de la venta o miembro hoy) no cambia — solo de dónde sale el equipo.
--
-- Verificado ANTES de aplicar con la batería de agencia-0b (24 casos + I1 propio de Lawang: devengo
-- sin equipo en el snapshot cae al congelado), corrida en un `do $$ … raise exception 'FIN DE
-- PRUEBAS' $$` que se deshace solo: los 25 salen «ok». Aplicada en producción vía MCP y reverificada
-- con la misma batería DESPUÉS de aplicar.

create or replace function public.comisiones_reconciliar(p_raiz uuid, p_simular boolean default true, p_origen jsonb default '{}'::jsonb)
returns table (devengo_id uuid, venta text, beneficiario text, nivel text, estado_devengo text,
               base_antes numeric, base_despues numeric, vigente numeric, nuevo numeric, delta numeric,
               accion text, motivo text)
language plpgsql security definer set search_path = '' as $$
declare
  r record; v_sp public.solicitudes_pago;
  v_es_raiz boolean; v_moneda text; v_num text; v_base numeric;
  v_vig numeric; v_nuevo numeric; v_delta numeric; v_base_antes numeric;
  v_lawang boolean; v_manual boolean; v_accion text; v_motivo text;
  v_yo text := lower(coalesce(auth.email(), ''));
  v_dif public.comisiones_diferencias; v_dif_id uuid;
  v_hoy text := to_char(now() at time zone 'Asia/Makassar', 'DD-MM-YYYY');
  v_eq_id uuid; v_fecha_venta date; v_mismo_equipo boolean;   -- AXW-98 / B3c, por devengo
begin
  if p_raiz is null then return; end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));

  select (c.contrato_padre_id is null and c.liberado_en is null), c.moneda, c.numero
    into v_es_raiz, v_moneda, v_num
    from public.contratos c where c.id = p_raiz;
  v_base := public._comisiones_precio_total(p_raiz);

  for r in
    select d.*, c.base_calculo, c.pct_comision, c.importe_fijo, t.pct_tramo
      from public.comisiones_devengadas d
      join public.condiciones_comision c on c.id = d.condicion_id
      join public.condicion_tramos t on t.id = d.tramo_id
     where d.contrato_raiz_id = p_raiz and d.estado <> 'anulada'
     order by d.created_at, d.id
  loop
    -- solo la base precio_total se reconcilia: importe fijo no depende del contrato, y las
    -- bases de parcela salen de la lista viva de unidades
    continue when r.base_calculo <> 'precio_total';

    v_lawang := r.nivel in ('manager', 'estandar', 'propia');
    v_sp := null;
    if r.solicitud_id is not null then
      select * into v_sp from public.solicitudes_pago sp where sp.id = r.solicitud_id;
    end if;
    select * into v_dif from public.comisiones_diferencias x where x.devengo_id = r.id and x.estado = 'revisar';

    v_base_antes := coalesce(
      (select x.base_despues from public.comisiones_diferencias x
        where x.devengo_id = r.id and x.estado in ('pendiente', 'pagada', 'compensada')
        order by x.created_at desc limit 1),
      nullif(r.disparado_por_snapshot->>'base_valor', '')::numeric);
    v_vig := (case when v_lawang and v_sp.id is not null then v_sp.importe
                   else coalesce(r.importe_ajustado, r.importe) end)
           + coalesce((select sum(x.importe) from public.comisiones_diferencias x
                        where x.devengo_id = r.id and x.estado in ('pendiente', 'pagada', 'compensada')), 0);
    v_nuevo := round((r.pct_comision / 100) * v_base * (r.pct_tramo / 100), 2);
    v_delta := round(v_nuevo - v_vig, 2);
    v_manual := r.importe_ajustado is not null or (v_sp.id is not null and v_sp.importe_editado_por is not null);

    -- AXW-98/B3c (regla canónica, ver erp/migraciones/20260930180000_b3c_comisiones_subida_mismo_equipo.sql
    -- del maestro): ¿v_yo (quien provoca) es del mismo equipo de ESTE devengo? Por devengo, no por
    -- llamada: el equipo sale del snapshot (lo que el motor congeló al devengar) y solo cae al
    -- congelado de la venta si el devengo no lo trae.
    v_mismo_equipo := false;
    if v_delta > 0 and nullif(v_yo, '') is not null and r.nivel <> 'estandar' then
      v_eq_id := coalesce(nullif(r.disparado_por_snapshot->>'equipo_id', '')::uuid,
                          (select x.equipo_id from public._equipo_de_venta(p_raiz) x limit 1));
      if v_eq_id is not null then
        v_fecha_venta := coalesce((select x.fecha from public._equipo_de_venta(p_raiz) x limit 1), current_date);
        v_mismo_equipo :=
             -- (1) v_yo es parte de esta venta: su closer/manager congelado, su setter o team lead, o quien la reclamó como propia
             exists (select 1 from public._equipo_de_venta(p_raiz) x
                      where x.equipo_id = v_eq_id and v_yo in (lower(x.manager_email), lower(x.closer_email)))
          or exists (select 1 from public.contrato_roles_equipo re
                      where re.contrato_raiz_id = p_raiz and re.equipo_id = v_eq_id and lower(re.email) = v_yo)
          or exists (select 1 from public.reclamaciones_venta_propia rp
                      where rp.contrato_raiz_id = p_raiz and rp.equipo_id = v_eq_id and rp.estado = 'aprobada'
                        and lower(rp.solicitante_email) = v_yo)
             -- (2) es el manager de HOY de ese equipo
          or exists (select 1 from public.equipos_venta ev where ev.id = v_eq_id and lower(ev.manager_email) = v_yo)
             -- (3) era miembro de ese equipo el día de la venta, o lo es hoy (irse después no libera; entrar después no deja fuera)
          or exists (select 1 from public.equipo_miembros em
                      where em.equipo_id = v_eq_id and lower(em.closer_email) = v_yo
                        and ((em.desde <= v_fecha_venta and (em.hasta is null or em.hasta >= v_fecha_venta))
                          or (em.desde <= current_date and (em.hasta is null or em.hasta >= current_date))));
      end if;
    end if;

    v_accion := null; v_motivo := null;
    if not coalesce(v_es_raiz, false) then
      v_accion := 'revisar'; v_motivo := 'la venta ' || coalesce(v_num, '?') || ' ya no es una venta viva (traspasada a otro contrato o liberada)';
      v_delta := null;
    elsif v_moneda is distinct from r.moneda then
      v_accion := 'revisar'; v_motivo := 'la venta está ahora en ' || coalesce(v_moneda, '?') || ' y la comisión en ' || r.moneda;
      v_delta := null;
    elsif abs(v_delta) < 0.01 then
      v_accion := 'nada';
    elsif v_nuevo <= 0 then
      v_accion := 'revisar'; v_motivo := 'sin contratos firmados en la venta la comisión bajaría a 0';
    elsif v_manual then
      v_accion := 'revisar'; v_motivo := 'el importe se había ajustado a mano';
    elsif r.estado = 'en_disputa' then
      v_accion := 'revisar'; v_motivo := 'la comisión está en disputa';
    elsif v_lawang and (v_sp.id is null or v_sp.estado in ('rechazada', 'anulada')) then
      v_accion := 'revisar'; v_motivo := 'su solicitud de pago está ' || coalesce(v_sp.estado, 'sin crear');
    elsif v_delta > 0 and lower(r.beneficiario_email) = v_yo then
      v_accion := 'revisar'; v_motivo := 'la subida la provoca quien cobra la comisión';
    elsif v_delta > 0 and v_mismo_equipo then
      -- va ANTES de 'actualizar' y de 'diferencia': una subida a favor del equipo de quien la
      -- provoca no se aplica sola, ni en sitio ni como diferencia pendiente; la decide una persona
      -- (comision_diferencia_resolver, sin tocar quién resuelve)
      v_accion := 'revisar';
      v_motivo := 'subida_mismo_equipo: la subida beneficia a alguien del mismo equipo de la venta que quien provocó el cambio; la decide otra persona';
    elsif r.estado = 'pendiente' and (not v_lawang or v_sp.estado = 'pendiente')
          and not exists (select 1 from public.comisiones_diferencias x
                           where x.devengo_id = r.id and x.estado in ('pendiente', 'pagada', 'compensada')) then
      v_accion := 'actualizar';
    else
      v_accion := 'diferencia';
      v_motivo := 'la comisión ya estaba '
                  || case when r.estado = 'pagada' or v_sp.estado = 'pagada' then 'pagada' else 'aprobada' end
                  || case when v_delta > 0 then ': se paga la diferencia' else ': la diferencia se descuenta de un pago siguiente' end;
    end if;

    -- un «revisar» ya descartado por un admin para este mismo importe no se vuelve a abrir
    if v_accion = 'revisar' and exists (
         select 1 from public.comisiones_diferencias x
          where x.devengo_id = r.id and x.estado = 'anulada' and x.importe_nuevo is not distinct from v_nuevo
            and x.resuelto_por is not null and x.resuelto_por <> 'sistema') then
      v_accion := 'descartada';
    end if;

    if v_accion <> 'nada' or v_dif.id is not null then
      devengo_id := r.id; venta := v_num; beneficiario := r.beneficiario_email; nivel := r.nivel;
      estado_devengo := r.estado; base_antes := v_base_antes; base_despues := v_base;
      vigente := v_vig; nuevo := v_nuevo; delta := v_delta;
      accion := case when v_accion = 'nada' then 'cierra_revisar' else v_accion end;
      motivo := v_motivo;
      return next;
    end if;
    continue when p_simular;

    perform set_config('app.via_recalculo_comision', 'on', true);

    if v_accion = 'nada' then
      if v_dif.id is not null then
        update public.comisiones_diferencias
           set estado = 'anulada', resuelto_por = 'sistema', resuelto_en = now(),
               resolucion_motivo = 'la comisión vuelve a cuadrar sola con la base de hoy'
         where id = v_dif.id;
      end if;

    elsif v_accion = 'actualizar' then
      update public.comisiones_devengadas d
         set importe = v_nuevo,
             disparado_por_snapshot = d.disparado_por_snapshot
               || jsonb_build_object('base_valor', v_base, 'precio_total', v_base,
                                     'recalculado_en', now(), 'recalculo_origen', p_origen,
                                     'importe_motor_original', coalesce(d.disparado_por_snapshot->'importe_motor_original', to_jsonb(r.importe)),
                                     'base_original', coalesce(d.disparado_por_snapshot->'base_original', d.disparado_por_snapshot->'base_valor'))
       where d.id = r.id;
      if v_sp.id is not null then
        update public.solicitudes_pago sp
           set importe = v_nuevo,
               concepto = case
                 when sp.concepto ~ '(a fecha de disparo|recalculada el [0-9-]+): [0-9.]+ [A-Z]{3}'
                   then regexp_replace(sp.concepto, '(a fecha de disparo|recalculada el [0-9-]+): [0-9.]+ [A-Z]{3}',
                                       'recalculada el ' || v_hoy || ': ' || round(v_base, 2) || ' ' || sp.moneda)
                 else sp.concepto || ' — recalculada el ' || v_hoy || ' sobre ' || round(v_base, 2) || ' ' || sp.moneda
               end
         where sp.id = v_sp.id;
      end if;
      insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
      values ('comisiones_devengadas', r.id, 'recalculo_auto', v_vig, v_nuevo, r.estado, r.estado,
              'cambio en el contrato: base ' || coalesce(round(v_base_antes, 2)::text, '?') || ' → ' || round(v_base, 2) || ' ' || r.moneda,
              jsonb_build_object('origen', p_origen, 'solicitud_id', v_sp.id));

    elsif v_accion = 'descartada' then
      if v_dif.id is not null then
        update public.comisiones_diferencias
           set estado = 'anulada', resuelto_por = 'sistema', resuelto_en = now(),
               resolucion_motivo = 'un administrador ya descartó este mismo importe'
         where id = v_dif.id;
      end if;

    elsif v_accion = 'revisar' then
      if v_dif.id is not null then
        update public.comisiones_diferencias
           set importe = v_delta, importe_vigente = v_vig, importe_nuevo = v_nuevo,
               base_despues = v_base, motivo = v_motivo, origen = p_origen
         where id = v_dif.id;
      else
        insert into public.comisiones_diferencias (devengo_id, importe, importe_vigente, importe_nuevo, base_antes, base_despues,
                                                   motivo, estado, origen, provocado_por)
        values (r.id, v_delta, v_vig, v_nuevo, v_base_antes, v_base, v_motivo, 'revisar', p_origen, nullif(v_yo, ''))
        returning id into v_dif_id;
        insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
        values ('comisiones_diferencias', v_dif_id, 'diferencia', v_vig, v_nuevo, null, 'revisar', v_motivo, jsonb_build_object('origen', p_origen));
      end if;

    elsif v_accion = 'diferencia' then
      if v_dif.id is not null then
        update public.comisiones_diferencias
           set estado = 'anulada', resuelto_por = 'sistema', resuelto_en = now(),
               resolucion_motivo = 'sustituida por una diferencia automática'
         where id = v_dif.id;
      end if;
      insert into public.comisiones_diferencias (devengo_id, importe, importe_vigente, importe_nuevo, base_antes, base_despues,
                                                 motivo, estado, origen, provocado_por)
      values (r.id, v_delta, v_vig, v_nuevo, v_base_antes, v_base, v_motivo, 'pendiente', p_origen, nullif(v_yo, ''))
      returning id into v_dif_id;
      insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
      values ('comisiones_diferencias', v_dif_id, 'diferencia', v_vig, v_nuevo, null, 'pendiente', v_motivo, jsonb_build_object('origen', p_origen));
      perform public._comision_diferencia_solicitud(v_dif_id);
    end if;

    perform set_config('app.via_recalculo_comision', 'off', true);
  end loop;
end $$;
revoke execute on function public.comisiones_reconciliar(uuid, boolean, jsonb) from public, anon, authenticated;
