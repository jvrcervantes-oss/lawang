-- destructivo-ok: sin DROP; solo `create or replace function` sobre `comisiones_reconciliar`
-- (base: 20260928213000_comisiones_recalculo_arreglos_revisor.sql, su última versión — mismo
-- cuerpo salvo lo señalado «AXW-98» abajo) para cerrar AXW-98 (contexto/pendientes.md, decidido
-- por el owner 30-sep-2026, opción (a)). NO toca `comisiones_diferencias` ni ninguna fila existente.
--
-- AXW-98 — colusión residual en el recálculo automático de comisiones «diferencia ±»:
-- el freno ya existente («la subida la provoca quien cobra la comisión», línea `v_delta > 0 and
-- lower(r.beneficiario_email) = v_yo`) solo mira si quien EDITA el contrato (v_yo, quien llama a
-- `comisiones_reconciliar`) es el propio BENEFICIARIO del devengo que sube. No mira si v_yo es
-- un compañero del MISMO EQUIPO DE VENTA que el beneficiario (manager, team lead, setter o closer):
-- un team lead o manager que edita el contrato podía subir la comisión de un compañero de su
-- equipo sin que nada lo parase — la subida se aplicaba sola (acción `diferencia`/`actualizar`)
-- en vez de ir a `revisar`.
--
-- DECISIÓN DEL OWNER (30-sep-2026, AXW-98): opción (a) — toda subida a favor de alguien del mismo
-- equipo de venta que quien edita el contrato va SIEMPRE a «revisar» (igual que ya pasa cuando el
-- beneficiario es el propio editor). La resuelve un admin con el mismo mecanismo de
-- `comision_diferencia_resolver` que ya existe (el freno «quien provocó no resuelve la suya» no
-- cambia aquí: sigue mirando solo al provocador — límites conocidos de AXW-99, aceptados como no
-- bloqueantes por el owner el mismo día).
--
-- «Mismo equipo» usa el equipo de LA VENTA (congelado si lo hay; si no, el equipo de hoy del
-- closer — mismo criterio que ya usa `_equipo_de_venta`, LAW-336 F7, 26-sep): v_yo es del mismo
-- equipo si es el manager_email de ese equipo o un miembro ACTIVO hoy en `equipo_miembros`. Se
-- calcula UNA vez por llamada (p_raiz es fijo en toda la función), no por cada devengo del bucle.
--
-- Vive en Lawang, donde `recalculo_auto` está ENCENDIDO desde el 28-sep con este hueco abierto en
-- producción con dinero real (prioridad sobre el maestro, que hoy nace con `recalculo_auto = false`
-- y no se enciende hasta portar este mismo arreglo — AXW-90/AXW-98).

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
  v_eq_id uuid; v_mismo_equipo boolean;   -- AXW-98
begin
  if p_raiz is null then return; end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));

  select (c.contrato_padre_id is null and c.liberado_en is null), c.moneda, c.numero
    into v_es_raiz, v_moneda, v_num
    from public.contratos c where c.id = p_raiz;
  v_base := public._comisiones_precio_total(p_raiz);

  -- AXW-98: ¿v_yo (quien edita/llama) es del mismo equipo de venta que esta venta? Una vez por llamada,
  -- no por cada devengo: p_raiz (y por tanto el equipo) es el mismo en todo el bucle.
  select eq.equipo_id into v_eq_id from public._equipo_de_venta(p_raiz) eq;
  v_mismo_equipo := v_eq_id is not null and nullif(v_yo, '') is not null and (
    exists (select 1 from public.equipos_venta ev where ev.id = v_eq_id and lower(ev.manager_email) = v_yo)
    or exists (select 1 from public.equipo_miembros em
                where em.equipo_id = v_eq_id and lower(em.closer_email) = v_yo
                  and em.desde <= current_date and (em.hasta is null or em.hasta >= current_date))
  );

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
      v_accion := 'revisar'; v_motivo := 'la subida la provoca alguien del mismo equipo de venta que el beneficiario';   -- AXW-98
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
