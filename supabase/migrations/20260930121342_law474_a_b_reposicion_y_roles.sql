-- LAW-474 (a) reposición tras cambio de modo y (b) sin roles en ventas «por su cuenta». APLICADO por la sesión
-- principal el 30-sep-2026 como migración 20260930121342_law474_a_b_reposicion_y_roles, con OK expreso del owner
-- («Sí, las dos»). Mismo SQL que supabase/pendientes/PENDIENTE_law474_a_b_reposicion_y_roles.sql (retirado de ahí).
-- destructivo-ok: OK del owner 30-sep-2026; no borra datos: ampliar un CHECK exige DROP CONSTRAINT + ADD, y el
-- cuerpo de comision_rol_asignar conserva su «delete from contrato_roles_equipo» de siempre.
-- Parte de los cuerpos vivos del 30-sep-2026 (evaluador ya con LAW-476, 20260930115040). Requiere
-- 20260930120030_law474_restos_f5 (columna anulado_por_modo). Pruebas: contracts/sql/prueba_f5_por_su_cuenta.sql
-- bloque 2 (P7-P9) y contracts/sql/prueba_law476_condicion_fija.sql.

alter table public.comisiones_ajustes_log drop constraint if exists comisiones_ajustes_log_accion_check;
alter table public.comisiones_ajustes_log add constraint comisiones_ajustes_log_accion_check
  check (accion = any (array['editar_importe', 'anular', 'recalcular', 'recalculo_auto', 'diferencia', 'resolver_diferencia', 'reponer']));

create or replace function public._comision_devengo_reponer(p_id uuid, p_importe numeric, p_snap jsonb, p_motivo text)
 returns boolean
 language plpgsql
 security definer
 set search_path to ''
as $function$
-- Devuelve true si la fila repuesta ya estaba pagada (no toca crear solicitud) y false si vuelve a pendiente sin pagar.
declare
  d      public.comisiones_devengadas;
  v_sp   public.solicitudes_pago;
  v_vig  numeric;
  v_obj  numeric;
  v_dif  uuid;
  v_yo   text := nullif(lower(coalesce(auth.email(), '')), '');
begin
  select * into d from public.comisiones_devengadas where id = p_id for update;
  if d.id is null or d.estado <> 'anulada' or not d.anulado_por_modo then
    raise exception 'Solo se repone una comisión anulada por un cambio de modo de la venta' using errcode = '22023';
  end if;
  if d.solicitud_id is not null then
    select * into v_sp from public.solicitudes_pago sp where sp.id = d.solicitud_id;
  end if;

  if d.pagado_en is null and v_sp.estado is distinct from 'pagada' then
    -- no se había pagado: vuelve a devengar con el importe de hoy; la solicitud vieja queda anulada con su rastro
    insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
    values ('comisiones_devengadas', d.id, 'reponer', coalesce(d.importe_ajustado, d.importe), p_importe, 'anulada', 'pendiente',
            p_motivo || ' — no se había pagado: vuelve a devengar',
            jsonb_build_object('solicitud_anterior', d.solicitud_id, 'anulado_motivo', d.anulado_motivo, 'anulado_en', d.anulado_en));
    update public.comisiones_devengadas
       set estado = 'pendiente', importe = p_importe,
           importe_ajustado = null, ajuste_motivo = null, ajustado_por = null, ajustado_en = null,
           anulado_motivo = null, anulado_por = null, anulado_en = null, anulado_por_modo = false,
           solicitud_id = null, disparado_en = now(),
           disparado_por_snapshot = coalesce(p_snap, '{}'::jsonb)
             || jsonb_build_object('repuesta_en', now(), 'importe_anterior', d.importe, 'solicitud_anterior', d.solicitud_id)
     where id = d.id;
    return false;
  end if;

  -- ya pagada: lo pagado no se reescribe ni se vuelve a pagar
  perform set_config('app.via_recalculo_comision', 'on', true);
  -- lo que valía justo antes del cambio de modo (lo guardó su diferencia negativa en importe_vigente)
  select x.importe_vigente into v_obj
    from public.comisiones_diferencias x
   where x.devengo_id = d.id and x.importe < 0 and x.origen->>'op' = 'cambio_modo'
   order by x.created_at desc limit 1;
  update public.comisiones_diferencias
     set estado = 'anulada', resuelto_por = 'sistema', resuelto_en = now(),
         resolucion_motivo = p_motivo || ': se repone la comisión ya pagada, no se descuenta'
   where devengo_id = d.id and estado = 'pendiente' and importe < 0 and origen->>'op' = 'cambio_modo';
  v_vig := coalesce(v_sp.importe, coalesce(d.importe_ajustado, d.importe))
         + coalesce((select sum(x.importe) from public.comisiones_diferencias x
                      where x.devengo_id = d.id and x.estado in ('pendiente', 'pagada', 'compensada')), 0);
  v_obj := coalesce(v_obj, v_vig);
  if round(v_obj - v_vig, 2) >= 0.01 then
    -- la diferencia negativa ya se había descontado de otro pago: se devuelve al mismo perceptor
    insert into public.comisiones_diferencias (devengo_id, importe, importe_vigente, importe_nuevo, base_antes, base_despues,
                                               motivo, estado, origen, provocado_por)
    values (d.id, round(v_obj - v_vig, 2), v_vig, v_obj,
            nullif(d.disparado_por_snapshot->>'base_valor', '')::numeric, nullif(d.disparado_por_snapshot->>'base_valor', '')::numeric,
            p_motivo || ' — ya estaba pagada y se había descontado: se devuelve lo descontado', 'pendiente',
            jsonb_build_object('tabla', 'contrato_closer', 'op', 'vuelta_modo', 'contrato_id', d.contrato_raiz_id, 'en', now(), 'quien', v_yo),
            v_yo)
    returning id into v_dif;
    insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
    values ('comisiones_diferencias', v_dif, 'diferencia', v_vig, v_obj, null, 'pendiente', p_motivo, jsonb_build_object('devengo_id', d.id));
    perform public._comision_diferencia_solicitud(v_dif);
  end if;
  insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
  values ('comisiones_devengadas', d.id, 'reponer', coalesce(d.importe_ajustado, d.importe), coalesce(d.importe_ajustado, d.importe),
          'anulada', case when d.pagado_en is not null then 'pagada' else 'pendiente' end,
          p_motivo || ' — ya estaba pagada: se repone sin volver a pagarla',
          jsonb_build_object('anulado_motivo', d.anulado_motivo, 'anulado_en', d.anulado_en, 'diferencia_devuelta', v_dif));
  update public.comisiones_devengadas
     set estado = case when d.pagado_en is not null then 'pagada' else 'pendiente' end,
         anulado_motivo = null, anulado_por = null, anulado_en = null, anulado_por_modo = false
   where id = d.id;
  perform set_config('app.via_recalculo_comision', 'off', true);
  return true;
end $function$;

revoke all on function public._comision_devengo_reponer(uuid, numeric, jsonb, text) from public, anon, authenticated;

-- ── motor: LAW-476 (condición fijada) + LAW-474 (a) (reposición) ────────────────────────────────────────────────
create or replace function public.comisiones_evaluar_contrato(p_contrato_id uuid)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_raiz_id              uuid;
  v_raiz_creada          date;
  v_fecha_equipo         date;
  v_moneda               text;
  v_proyecto_id          uuid;
  v_contrato_firmado     boolean := false;
  v_obra_firmada         boolean := false;
  v_precio_total         numeric := 0;
  v_precio_suelo         numeric := 0;
  v_precio_construccion  numeric := 0;
  v_cobrado_suelo        numeric := 0;
  v_cobrado_obra         numeric := 0;
  v_cobrado_total        numeric := 0;
  v_closer_email         text;
  v_fecha_venta          date;
  v_equipo_id            uuid;
  v_manager_email        text;
  v_propia               public.reclamaciones_venta_propia;
  v_niveles              text[];
  v_ultimo_recibi_id     uuid;
  v_ultimo_recibi_en     timestamptz;
  v_nivel                text;
  v_beneficiario         text;
  v_condicion            record;
  v_cond_fija            uuid;          -- LAW-476: condición del primer devengo de (venta, nivel, perceptor)
  v_prev                 public.comisiones_devengadas;   -- LAW-474 (a): fila previa de (venta, tramo, perceptor)
  v_snap                 jsonb;
  v_tramo                record;
  v_base                 numeric;
  v_importe              numeric;
  v_devengo_id           uuid;
  v_sp_id                uuid;
  v_creado_por           uuid;
  v_concepto             text;
  v_creados              integer := 0;
  v_eq_cong              uuid;
  v_man_cong             text;
  v_congelado            boolean := false;
  v_modo                 text;          -- F5: equipo | propia | NULL (sin declarar: como hasta hoy)
  v_espera               timestamptz;   -- F5: fin de la ventana de objeción
  v_propia_modo          boolean := false;
begin
  if p_contrato_id is null then
    return 0;
  end if;

  select coalesce(c.contrato_padre_id, c.id) into v_raiz_id
    from public.contratos c
   where c.id = p_contrato_id;

  if v_raiz_id is null then
    return 0;
  end if;

  -- mismo lock que comision_recalcular y venta_propia_resolver
  perform pg_advisory_xact_lock(hashtext('comisiones:' || v_raiz_id::text));

  select c.moneda, c.proyecto_id, c.bloqueado, (c.created_at at time zone 'Asia/Makassar')::date
    into v_moneda, v_proyecto_id, v_contrato_firmado, v_raiz_creada
    from public.contratos c
   where c.id = v_raiz_id;

  -- la Carta de Reserva hija ya vale suelo + obra: no se suma otra vez (24-sep-2026)
  v_precio_total := public._comisiones_precio_total(v_raiz_id);

  v_obra_firmada := exists (
    select 1 from public.contratos h
     where h.contrato_padre_id = v_raiz_id and h.bloqueado
  );

  select coalesce(sum(u.precio_suelo), 0),
         coalesce(sum(u.precio_construccion), 0),
         coalesce(sum(cp.cobrado_suelo), 0),
         coalesce(sum(cp.cobrado_obra), 0)
    into v_precio_suelo, v_precio_construccion, v_cobrado_suelo, v_cobrado_obra
    from public.unidades u
    left join lateral public.unidad_parte_cobrada_interno(u.id) cp on true
   where u.contrato_id = v_raiz_id;

  v_cobrado_total := v_cobrado_suelo + v_cobrado_obra;

  select k.closer_email, k.fecha_venta into v_closer_email, v_fecha_venta
    from public.contrato_closer k
   where k.contrato_id = v_raiz_id;

  if v_closer_email is null then
    return 0;
  end if;

  -- una sola fecha de la venta para equipo y condicion: fecha_venta o creacion de la raiz en hora de Bali, la misma
  -- con la que _venta_congela_equipo congela (F2, 30-sep-2026; antes el equipo de una venta no congelada se buscaba a hoy)
  v_raiz_creada := coalesce(v_fecha_venta, v_raiz_creada);
  v_fecha_equipo := v_raiz_creada;

  select k.equipo_id, k.manager_email, (k.equipo_congelado_en is not null), k.modo, k.modo_espera_hasta
    into v_eq_cong, v_man_cong, v_congelado, v_modo, v_espera
    from public.contrato_closer k where k.contrato_id = v_raiz_id;
  if coalesce(v_congelado, false) then
    v_equipo_id := v_eq_cong;   -- equipo congelado en la venta (owner, 26-sep-2026)
  else
  select em.equipo_id into v_equipo_id
    from public.equipo_miembros em
    join public.equipos_venta ev on ev.id = em.equipo_id
   where lower(em.closer_email) = lower(v_closer_email)
     and ev.activo
     and em.desde <= v_fecha_equipo
     and (em.hasta is null or em.hasta >= v_fecha_equipo)
   order by em.created_at desc
   limit 1;
  end if;

  if v_proyecto_id is null or v_moneda is null then
    return 0;
  end if;

  -- F5: la reclamación legada (24-sep) solo cuenta en ventas sin modo declarado y nunca una objeción del SM
  if v_modo is null then
    select * into v_propia
      from public.reclamaciones_venta_propia r
     where r.contrato_raiz_id = v_raiz_id and r.estado = 'aprobada' and r.tipo = 'reclamacion';
  end if;

  if v_modo = 'propia' and v_equipo_id is not null then
    -- F5: por su cuenta dentro de un equipo: en espera mientras dure la ventana de objeción o haya objeción viva;
    -- después cobra el closer la condición individual o la estándar vigente, y el equipo 0
    if (v_espera is not null and v_espera > now())
       or exists (select 1 from public.reclamaciones_venta_propia r
                   where r.contrato_raiz_id = v_raiz_id and r.tipo = 'objecion' and r.estado = 'pendiente') then
      return 0;
    end if;
    if not public.crm_usuario_activo(v_closer_email) then
      return 0;
    end if;
    v_propia_modo := true;
    v_niveles := array['propia'];
  elsif v_modo = 'propia' then
    -- F5: por su cuenta sin equipo = la estándar de siempre
    if not public.crm_usuario_activo(v_closer_email) then
      return 0;
    end if;
    v_niveles := array['estandar'];
  elsif v_propia.id is not null then
    -- venta propia aprobada: solo cobra quien la reclamó, con la condición de manager de SU equipo
    if lower(v_propia.solicitante_email) <> lower(v_closer_email) then
      return 0;
    end if;
    v_equipo_id := v_propia.equipo_id;
    v_niveles := array['propia'];
  elsif v_equipo_id is not null then
    if coalesce(v_congelado, false) then
      v_manager_email := v_man_cong;   -- manager congelado en la venta
    else
      select ev.manager_email into v_manager_email from public.equipos_venta ev where ev.id = v_equipo_id;
    end if;
    v_niveles := array['manager', 'closer', 'setter', 'team_lead'];
  else
    if not public.crm_usuario_activo(v_closer_email) then
      return 0;
    end if;
    v_niveles := array['estandar'];
  end if;

  select r.id, r.created_at
    into v_ultimo_recibi_id, v_ultimo_recibi_en
    from public.facturas r
   where r.tipo = 'recibi'
     and not coalesce(r.anulada, false)
     and (
       r.contrato_id = v_raiz_id
       or r.contrato_id in (select h.id from public.contratos h where h.contrato_padre_id = v_raiz_id)
       or exists (
            select 1
              from public.recibi_aplicaciones ra
              join public.facturas f on f.id = ra.factura_id
             where ra.recibi_id = r.id
               and not coalesce(f.anulada, false)
               and (f.contrato_id = v_raiz_id
                    or f.contrato_id in (select h.id from public.contratos h where h.contrato_padre_id = v_raiz_id))
          )
     )
   order by r.created_at desc
   limit 1;

  if v_ultimo_recibi_id is null then
    return 0;
  end if;

  foreach v_nivel in array v_niveles
  loop
    v_beneficiario := null;

    if v_nivel in ('closer', 'setter', 'team_lead') then
      if v_nivel = 'closer' then
        v_beneficiario := v_closer_email;
      else
        select re.email into v_beneficiario
          from public.contrato_roles_equipo re
         where re.contrato_raiz_id = v_raiz_id and re.rol = v_nivel and re.equipo_id = v_equipo_id;
      end if;
      if v_beneficiario is null then
        continue;
      end if;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id = v_equipo_id
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and c.nivel = v_nivel
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_raiz_creada
         and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
         and lower(c.closer_email) = lower(v_beneficiario)
       order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;

      if not found then
        select * into v_condicion
          from public.condiciones_comision c
         where c.equipo_id = v_equipo_id
           and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
           and c.nivel = v_nivel
           and (c.activo or c.vigente_hasta is not null)
           and c.vigente_desde <= v_raiz_creada
           and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
           and c.closer_email is null
         order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
         limit 1;
      end if;

    elsif v_nivel = 'estandar' or (v_nivel = 'propia' and v_propia_modo) then
      -- F5: la venta por su cuenta dentro de un equipo cobra lo mismo que quien vende sin equipo
      v_beneficiario := v_closer_email;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id is null
         and c.nivel = 'closer'
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_raiz_creada
         and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and (c.closer_email is null or lower(c.closer_email) = lower(v_closer_email))
       order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;

    else
      -- 'manager' cobra el manager; 'propia' (reclamación legada) cobra el closer con esa misma condición
      v_beneficiario := case when v_nivel = 'propia' then v_closer_email else v_manager_email end;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id = v_equipo_id
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and c.nivel = 'manager'
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_raiz_creada
         and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
         and c.closer_email is null
       order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;
    end if;

    -- LAW-476 (owner 30-sep: «se queda con la primera»): si la venta ya devengó en este nivel para este perceptor,
    -- manda la condición de ese PRIMER devengo (cualquier estado), aunque se haya cerrado, desactivado o sustituido.
    -- Sustituye a la regla vieja «la primera condición que devenga manda», que saltaba el nivel entero.
    v_cond_fija := null;
    if v_beneficiario is not null then
      select d.condicion_id into v_cond_fija
        from public.comisiones_devengadas d
       where d.contrato_raiz_id = v_raiz_id
         and d.beneficiario_email = v_beneficiario
         and d.nivel = v_nivel
       order by d.created_at, d.id
       limit 1;
      if v_cond_fija is not null then
        select * into v_condicion from public.condiciones_comision c where c.id = v_cond_fija;
      end if;
    end if;

    if v_condicion.id is null or v_beneficiario is null then
      continue;
    end if;

    if v_condicion.base_calculo <> 'importe_fijo' and v_condicion.pct_comision = 0 then
      continue;
    end if;

    v_base := case v_condicion.base_calculo
      when 'precio_total'        then v_precio_total
      when 'precio_suelo'        then v_precio_suelo
      when 'precio_construccion' then v_precio_construccion
      else null
    end;

    for v_tramo in
      select * from public.condicion_tramos
       where condicion_id = v_condicion.id
       order by orden
    loop
      -- LAW-474 (a): la fila de (venta, tramo, perceptor) solo deja volver a devengar si la anuló un cambio de modo
      v_prev := null;
      select * into v_prev
        from public.comisiones_devengadas d
       where d.contrato_raiz_id = v_raiz_id
         and d.tramo_id = v_tramo.id
         and d.beneficiario_email = v_beneficiario;
      if v_prev.id is not null and (v_prev.estado <> 'anulada' or not v_prev.anulado_por_modo) then
        continue;
      end if;

      -- como mucho un pago de Lawang vivo por tramo de la venta (manager | propia | estandar)
      if v_nivel in ('manager', 'estandar', 'propia') and exists (
        select 1 from public.comisiones_devengadas d
         where d.contrato_raiz_id = v_raiz_id
           and d.tramo_id = v_tramo.id
           and d.nivel in ('manager', 'estandar', 'propia')
           and d.estado <> 'anulada'
      ) then
        continue;
      end if;

      if not (case v_tramo.disparador_tipo
        when 'pct_cobrado_suelo' then
          v_precio_suelo > 0 and (v_cobrado_suelo / v_precio_suelo * 100) >= v_tramo.umbral
        when 'pct_cobrado_obra' then
          v_precio_construccion > 0 and (v_cobrado_obra / v_precio_construccion * 100) >= v_tramo.umbral
        when 'pct_cobrado_total' then public._comisiones_precio_total_todos(v_raiz_id) > 0 and (v_cobrado_total / public._comisiones_precio_total_todos(v_raiz_id) * 100) >= v_tramo.umbral
        when 'obra_firmada' then v_obra_firmada
        when 'contrato_firmado' then v_contrato_firmado
        else false
      end) then
        continue;
      end if;

      if v_condicion.base_calculo = 'importe_fijo' then
        v_importe := round(v_condicion.importe_fijo * v_tramo.pct_tramo / 100, 2);
      else
        if v_base is null then
          continue;
        end if;
        v_importe := round((v_condicion.pct_comision / 100) * v_base * (v_tramo.pct_tramo / 100), 2);
      end if;

      if coalesce(v_importe, 0) <= 0 then
        continue;
      end if;

      v_snap := jsonb_build_object(
          'recibi_id', v_ultimo_recibi_id,
          'recibi_registrado_en', v_ultimo_recibi_en,
          'disparador_tipo', v_tramo.disparador_tipo,
          'umbral', v_tramo.umbral,
          'pct_tramo', v_tramo.pct_tramo,
          'base_calculo', v_condicion.base_calculo,
          'base_valor', v_base,
          'pct_comision', v_condicion.pct_comision,
          'vigente_desde', v_condicion.vigente_desde,
          'precio_total', v_precio_total,
          'precio_suelo', v_precio_suelo,
          'precio_construccion', v_precio_construccion,
          'cobrado_suelo', v_cobrado_suelo,
          'cobrado_obra', v_cobrado_obra,
          'cobrado_total', v_cobrado_total,
          'obra_firmada', v_obra_firmada,
          'contrato_firmado', v_contrato_firmado,
          'fecha_venta', v_fecha_venta,
          'equipo_id', case when v_propia_modo then null else v_equipo_id end,
          'reclamacion_id', v_propia.id,
          'modo', v_modo,
          'condicion_fijada', v_cond_fija is not null
        );

      v_devengo_id := null;

      if v_prev.id is not null then
        -- LAW-474 (a): la venta vuelve a un modo que toca este tramo → se repone la misma fila (sin pago doble)
        v_creados := v_creados + 1;
        if public._comision_devengo_reponer(v_prev.id, v_importe, v_snap,
                                            'La venta vuelve a «' || coalesce(v_modo, 'equipo') || '»')
           or v_nivel not in ('manager', 'estandar', 'propia') then
          continue;                                   -- ya pagada (o la paga el SM): no hay solicitud nueva
        end if;
        v_devengo_id := v_prev.id;
      else
        insert into public.comisiones_devengadas (
          contrato_raiz_id, tramo_id, condicion_id, beneficiario_email, nivel,
          importe, moneda, tipo_cambio_aplicado, disparado_por_snapshot
        ) values (
          v_raiz_id, v_tramo.id, v_condicion.id, v_beneficiario, v_nivel,
          v_importe, v_moneda, null, v_snap
        )
        on conflict (contrato_raiz_id, tramo_id, beneficiario_email) do nothing
        returning id into v_devengo_id;

        if v_devengo_id is null then
          continue;
        end if;

        v_creados := v_creados + 1;
      end if;

      if v_nivel in ('manager', 'estandar', 'propia') then
        v_creado_por := coalesce(
          auth.uid(),
          (select u.user_id from public.usuarios u where lower(u.email) = lower(v_beneficiario) and u.activo limit 1),
          (select u.user_id from public.usuarios u where lower(u.email) = lower(v_closer_email) and u.activo limit 1),
          (select u.user_id from public.usuarios u where u.rol = 'super_admin' and u.activo order by u.email limit 1)
        );

        v_concepto := 'Comisión ' || case v_nivel when 'manager' then 'manager' when 'propia' then 'venta propia' else 'estándar' end
          || ' — tramo ' || v_tramo.orden || ' (' || v_tramo.disparador_tipo
          || case when v_tramo.umbral is not null then ' ' || v_tramo.umbral || '%' else '' end || ')'
          || case when v_condicion.base_calculo = 'importe_fijo'
               then ' — importe fijo ' || v_condicion.importe_fijo
               else ' — ' || v_condicion.pct_comision || '% s/ ' || replace(v_condicion.base_calculo, '_', ' ')
                    || ' a fecha de disparo: ' || round(v_base, 2) || ' ' || v_moneda
             end
          || ' × ' || v_tramo.pct_tramo || '% del tramo — importe BRUTO (retención al pagar)';

        if v_creado_por is null then
          raise warning 'comisiones_evaluar_contrato: sin creado_por resoluble para la solicitud de % (raiz %) -- devengo % sin solicitud',
            v_beneficiario, v_raiz_id, v_devengo_id;
        else
          v_sp_id := null;
          begin
            insert into public.solicitudes_pago (
              contrato_id, concepto, importe, moneda, origen, beneficiario_email, creado_por
            ) values (
              v_raiz_id, v_concepto, v_importe, v_moneda, 'comision_automatica', v_beneficiario, v_creado_por
            )
            returning id into v_sp_id;

            update public.comisiones_devengadas
               set solicitud_id = v_sp_id
             where id = v_devengo_id;
          exception when others then
            raise warning 'comisiones_evaluar_contrato: fallo creando la solicitud de pago de % (raiz %, tramo %): % -- devengo % sin solicitud',
              v_beneficiario, v_raiz_id, v_tramo.id, sqlerrm, v_devengo_id;
          end;
        end if;
      end if;
    end loop;
  end loop;

  return v_creados;
end;
$function$;

-- ── (b) sin roles de equipo en ventas «por su cuenta» ────────────────────────────────────────────────────────────
create or replace function public.comision_rol_asignar(p_raiz uuid, p_rol text, p_email text)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_yo    text := lower(coalesce(auth.email(), ''));
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_eq    record;
  v_prev  text;
begin
  if v_yo = '' then raise exception 'sesión sin identidad' using errcode = '42501'; end if;
  if p_rol not in ('setter', 'team_lead') then raise exception 'rol desconocido' using errcode = '22023'; end if;
  if not exists (select 1 from public.contratos c where c.id = p_raiz and c.contrato_padre_id is null) then
    raise exception 'esa venta no existe (o no es la raíz)' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));

  select * into v_eq from public._equipo_de_venta(p_raiz);
  if v_eq.equipo_id is null then
    raise exception 'esta venta no es de ningún equipo: no lleva setter ni team lead' using errcode = '22023';
  end if;
  if not (public.es_manager_de_equipo(v_eq.equipo_id) or (public.es_admin() and public.puede('comisiones_reparto'))) then
    raise exception 'solo el manager del equipo o un administrador asigna los roles de una venta' using errcode = '42501';
  end if;
  if v_email is not null and v_email = v_yo and not public.es_super_admin() then
    raise exception 'un rol de la venta no se lo asigna uno mismo' using errcode = '42501';
  end if;
  if v_email is not null and not exists (
       select 1 from public.equipo_miembros em
        where em.equipo_id = v_eq.equipo_id and lower(em.closer_email) = v_email
          and em.desde <= v_eq.fecha and (em.hasta is null or em.hasta >= v_eq.fecha)) then
    raise exception 'esa persona no estaba en el equipo en la fecha de la venta' using errcode = '22023';
  end if;
  if exists (select 1 from public.reclamaciones_venta_propia r
              where r.contrato_raiz_id = p_raiz and r.estado = 'aprobada') then
    raise exception 'esta venta es venta propia aprobada: no lleva roles de equipo' using errcode = '22023';
  end if;
  -- LAW-474 (b): la venta «por su cuenta» no cobra roles de equipo (quitar uno sí se deja, para limpiar)
  if v_email is not null and exists (select 1 from public.contrato_closer k where k.contrato_id = p_raiz and k.modo = 'propia') then
    raise exception 'esta venta es «por su cuenta»: no lleva setter ni team lead' using errcode = '22023';
  end if;

  select re.email into v_prev from public.contrato_roles_equipo re where re.contrato_raiz_id = p_raiz and re.rol = p_rol;
  if v_prev is not distinct from v_email then return; end if;
  if v_prev is not null and exists (
       select 1 from public.comisiones_devengadas d
        where d.contrato_raiz_id = p_raiz and d.nivel = p_rol and lower(d.beneficiario_email) = v_prev
          and d.estado <> 'anulada') then
    raise exception 'ese rol ya ha generado comisión a su nombre: anúlala primero (con motivo) y vuelve a asignarlo' using errcode = '22023';
  end if;

  if v_email is null then
    delete from public.contrato_roles_equipo where contrato_raiz_id = p_raiz and rol = p_rol;
  else
    insert into public.contrato_roles_equipo (contrato_raiz_id, rol, email, equipo_id, asignado_por)
    values (p_raiz, p_rol, v_email, v_eq.equipo_id, v_yo)
    on conflict (contrato_raiz_id, rol) do update
      set email = excluded.email, equipo_id = excluded.equipo_id,
          asignado_por = excluded.asignado_por, asignado_en = now();
  end if;

  -- si la venta ya cumple el tramo, el rol devenga ya
  perform public.comisiones_evaluar_contrato(p_raiz);
end $function$;

