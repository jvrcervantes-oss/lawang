-- LAW-474, arreglos del revisor sobre 20260930120030 / 20260930120750 / 20260930121342 (30-sep-2026). Parte de los
-- cuerpos VIVOS de ese día (md5 de prosrc comprobado contra el repo antes de tocar). Pruebas: contracts/sql/
-- prueba_f5_por_su_cuenta.sql bloque 2, P15-P19 (y P9/P10 con el mensaje nuevo).
--
-- 1 [ALTA] Una solicitud RECHAZADA renacía con dos cambios de modo: _venta_modo_aplica trataba su devengo como «sin
--   pagar», lo anulaba con anulado_por_modo = true y a la vuelta _comision_devengo_reponer lo dejaba sin solicitud y el
--   motor pedía otra. Ahora: si la solicitud del devengo está 'rechazada' no se marca anulado_por_modo (queda anulada
--   normal y el motor no la vuelve a devengar), y _comision_devengo_reponer se niega (22023) a reponer una fila cuya
--   solicitud esté rechazada. Datos vivos a 30-sep 13:18 UTC: 0 devengos anulado_por_modo, 0 con solicitud rechazada.
-- 2 [ALTA] La regla (f) miraba TODOS los devengos vivos de la venta: con la fee del manager, un setter/team lead o algo
--   pagado, cambiar el closer quedaba bloqueado sin salida, y las filas que se anulaban para desbloquear dejaban sin
--   cobrar al manager para siempre (la unicidad es venta+tramo+perceptor). Ahora solo cuentan los devengos vivos cuyo
--   perceptor es el closer ANTERIOR en niveles closer, estandar y propia, y el mensaje dice qué hacer:
--   · pagados, en disputa o con su solicitud aprobada/pagada → no se permite; lo regulariza Administración.
--   · pendientes → un administrador los anula antes con motivo: nivel closer con comision_devengo_anular (ya existía);
--     estandar/propia con comision_devengo_anular_lawang (NUEVA, solo admin con comisiones_reparto, motivo obligatorio,
--     log en comisiones_ajustes_log). Antes no había vía para una estandar/propia pendiente cuya solicitud estuviera
--     rechazada, anulada o sin crear (hoy 0 casos vivos); con solicitud pendiente la vía era anular la solicitud, y la
--     función nueva hace eso mismo (el trigger de solicitudes arrastra el devengo y deja su rastro).
-- 3 [BAJA] Comentario de anulado_por_modo al día (la reposición ya está aplicada). El drop/create de los triggers va
--   aparte y NO está aplicado: no_destruir.py frenó el DROP TRIGGER → supabase/pendientes/PENDIENTE_law474_triggers_closer.sql.
-- 4 [MEDIA] SIN EJECUTAR NUNCA: la rama de _comision_devengo_reponer que crea una diferencia POSITIVA (comisión pagada,
--   anulada por cambio de modo, y su diferencia negativa ya descontada de otro pago). No se ha pasado ni en prueba: el
--   insert toma numero = nextval de comisiones_diferencias_seq (gasta la serie DIF real aunque haya ROLLBACK) y su
--   _comision_diferencia_solicitud crea una solicitud de pago con nextval de la serie SP. Solo está comprobada por
--   lógica (P12b: las entradas que lee dan esa rama y el importe). Queda pendiente de probar en una rama de Supabase o
--   con número escrito a mano; no ejecutarla en producción hasta entonces.

create or replace function public._venta_modo_aplica(p_raiz uuid, p_modo text, p_motivo text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  k        public.contrato_closer;
  d        record;
  v_sp     public.solicitudes_pago;
  v_yo     text := lower(coalesce(auth.email(), ''));
  v_viejos text[];
  v_vig    numeric;
  v_dif    uuid;
  v_mot    text := 'Cambio de modo de la venta a «' || p_modo || '»: ' || coalesce(p_motivo, '');
  v_espera timestamptz;   -- LAW-474 (d)
  v_cruces jsonb;
  v_num    text;
  v_avisos text;
begin
  if p_modo not in ('equipo', 'propia') then raise exception 'La venta es «equipo» o «propia»' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));
  select * into k from public.contrato_closer where contrato_id = p_raiz for update;
  if not found then raise exception 'Esa venta no tiene closer atribuido' using errcode = 'P0002'; end if;
  if p_modo = 'equipo' and k.equipo_id is null then
    raise exception 'Esta venta no es de ningún equipo: no puede pasar a «equipo»' using errcode = '22023';
  end if;
  -- (3) el manager del equipo de la venta (congelado o actual) no cobra «por su cuenta»
  if p_modo = 'propia' and k.equipo_id is not null
     and (lower(coalesce(k.manager_email, '')) = lower(k.closer_email)
          or exists (select 1 from public.equipos_venta ev
                      where ev.id = k.equipo_id and lower(coalesce(ev.manager_email, '')) = lower(k.closer_email))) then
    raise exception 'El closer es el manager de este equipo: su venta cobra la fee de manager, no puede ser «por su cuenta»' using errcode = '22023';
  end if;

  -- lo que ya no toca con el modo nuevo
  v_viejos := case p_modo when 'equipo' then array['propia', 'estandar'] else array['manager', 'closer', 'setter', 'team_lead'] end;
  for d in select * from public.comisiones_devengadas cd
            where cd.contrato_raiz_id = p_raiz and cd.estado <> 'anulada' and cd.nivel = any(v_viejos)
            order by cd.created_at, cd.id loop
    if exists (select 1 from public.comisiones_diferencias x where x.devengo_id = d.id and x.estado in ('revisar', 'pendiente')) then
      raise exception 'Una comisión de esta venta tiene diferencias abiertas: resuélvelas antes de cambiar el modo' using errcode = '22023';
    end if;
    v_sp := null;
    if d.solicitud_id is not null then select * into v_sp from public.solicitudes_pago sp where sp.id = d.solicitud_id; end if;

    if d.estado = 'pendiente' and (v_sp.id is null or v_sp.estado in ('pendiente', 'rechazada', 'anulada')) then
      -- sin pagar: se anula (la solicitud pendiente arrastra su devengo, con rastro)
      if v_sp.estado = 'pendiente' then
        perform set_config('app.via_venta_propia', 'on', true);
        update public.solicitudes_pago set estado = 'anulada', motivo_ajuste = v_mot where id = v_sp.id;
        perform set_config('app.via_venta_propia', 'off', true);
      end if;
      if (select cd.estado from public.comisiones_devengadas cd where cd.id = d.id) <> 'anulada' then
        insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo)
        values ('comisiones_devengadas', d.id, 'anular', coalesce(d.importe_ajustado, d.importe), coalesce(d.importe_ajustado, d.importe),
                d.estado, 'anulada', v_mot);
        update public.comisiones_devengadas
           set estado = 'anulada', anulado_motivo = v_mot, anulado_por = auth.uid(), anulado_en = now()
         where id = d.id;
      end if;
      -- LAW-474 (a): la anuló el cambio de modo (también si la arrastró su solicitud): el motor la repone si vuelve.
      -- Salvo si su solicitud estaba RECHAZADA: esa ya la había denegado un administrador, queda anulada normal y no
      -- renace al volver de modo (arreglo del revisor, 30-sep-2026).
      update public.comisiones_devengadas set anulado_por_modo = true
       where id = d.id and estado = 'anulada' and v_sp.estado is distinct from 'rechazada';

    elsif d.estado = 'pagada' or v_sp.estado = 'pagada' then
      if d.nivel not in ('manager', 'estandar', 'propia') then
        raise exception 'Una comisión de equipo de esta venta ya la pagó el Sales Manager: ajústala a mano antes de cambiar el modo' using errcode = '22023';
      end if;
      -- ya pagado por Lawang: diferencia negativa al MISMO perceptor, nunca se reescribe lo pagado
      v_vig := coalesce(v_sp.importe, coalesce(d.importe_ajustado, d.importe))
             + coalesce((select sum(x.importe) from public.comisiones_diferencias x
                          where x.devengo_id = d.id and x.estado in ('pagada', 'compensada')), 0);
      if v_vig > 0 then
        perform set_config('app.via_recalculo_comision', 'on', true);
        insert into public.comisiones_diferencias (devengo_id, importe, importe_vigente, importe_nuevo, base_antes, base_despues,
                                                   motivo, estado, origen, provocado_por)
        values (d.id, -v_vig, v_vig, 0, nullif(d.disparado_por_snapshot->>'base_valor', '')::numeric,
                nullif(d.disparado_por_snapshot->>'base_valor', '')::numeric,
                v_mot || ' — ya estaba pagada: la diferencia se descuenta de un pago siguiente', 'pendiente',
                jsonb_build_object('tabla', 'contrato_closer', 'op', 'cambio_modo', 'contrato_id', p_raiz, 'modo', p_modo,
                                   'en', now(), 'quien', nullif(v_yo, '')),
                nullif(v_yo, ''))
        returning id into v_dif;
        insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
        values ('comisiones_diferencias', v_dif, 'diferencia', v_vig, 0, null, 'pendiente', v_mot, jsonb_build_object('devengo_id', d.id));
        perform set_config('app.via_recalculo_comision', 'off', true);
      end if;
      insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo)
      values ('comisiones_devengadas', d.id, 'anular', coalesce(d.importe_ajustado, d.importe), coalesce(d.importe_ajustado, d.importe),
              d.estado, 'anulada', v_mot || ' — pagada: se descuenta con una diferencia negativa');
      update public.comisiones_devengadas
         set estado = 'anulada', anulado_motivo = v_mot || ' — pagada: se descuenta con una diferencia negativa',
             anulado_por = auth.uid(), anulado_en = now(), anulado_por_modo = true
       where id = d.id;

    else
      raise exception 'Una comisión de esta venta está aprobada sin pagar o en disputa: resuélvela en Solicitudes de pago antes de cambiar el modo' using errcode = '22023';
    end if;
  end loop;

  -- LAW-474 (d): a «propia» dentro de un equipo se abre la misma ventana de 7 días que cuando lo declara el closer, con
  -- sus cruces, y se avisa al SM. Antes de llamar al motor: si se abriera después, devengaría sin dejar objetar.
  if p_modo = 'propia' and k.equipo_id is not null then
    v_espera := now() + interval '7 days';
    v_cruces := public._venta_propia_cruces(p_raiz, k.closer_email, k.equipo_id, k.manager_email);
  end if;

  perform set_config('app.via_modo_admin', 'on', true);
  update public.contrato_closer
     set modo = p_modo,
         modo_origen = case when p_modo = 'propia' then k.modo_origen end,
         modo_origen_texto = case when p_modo = 'propia' then k.modo_origen_texto end,
         modo_espera_hasta = v_espera,
         modo_cruces = case when v_espera is not null then v_cruces else modo_cruces end,
         modo_declarado_por = nullif(v_yo, ''), modo_declarado_en = now(),
         modo_fijado_admin = true                  -- (2) el closer ya no lo cambia al re-guardar
   where contrato_id = p_raiz;
  perform set_config('app.via_modo_admin', 'off', true);

  -- aviso al SM: sin cifras ni datos del cliente (se envía también por correo)
  if v_espera is not null and nullif(btrim(coalesce(k.manager_email, '')), '') is not null
     and lower(k.manager_email) <> lower(k.closer_email) then
    select c.numero into v_num from public.contratos c where c.id = p_raiz;
    select string_agg(distinct case a->>'tipo'
             when 'campana' then 'el cliente ya estaba en los leads de campañas de Lawang'
             when 'lead_otro_miembro' then 'el lead lo llevaba otra persona de tu equipo'
             when 'ficha_otro_miembro' then 'la ficha del cliente la creó otra persona de tu equipo' end, '; ')
      into v_avisos from jsonb_array_elements(coalesce(v_cruces->'avisos', '[]'::jsonb)) a;
    insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace, email_pendiente)
    values ('venta_por_su_cuenta',
            'Venta por su cuenta · ' || coalesce(v_num, '?'),
            'Un administrador marca la venta ' || coalesce(v_num, '?') || ' de ' || lower(k.closer_email)
              || ' como suya, sin el equipo. '
              || case when v_avisos is not null then 'Atención: ' || v_avisos || '. ' else 'Sin coincidencias en leads ni fichas del equipo. ' end
              || 'Puedes objetar hasta el ' || to_char(v_espera at time zone 'Asia/Makassar', 'DD-MM-YYYY HH24:MI') || ' (hora de Bali).',
            lower(k.manager_email), p_raiz, '/intranet/v4/equipos-venta/', true);
  end if;

  return coalesce(public.comisiones_evaluar_contrato(p_raiz), 0);
end $function$;

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
  -- su solicitud la rechazó un administrador: no renace (arreglo del revisor, 30-sep-2026)
  if v_sp.estado = 'rechazada' then
    raise exception 'La solicitud de pago de esta comisión se rechazó: no se repone, queda anulada' using errcode = '22023';
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

revoke all on function public._venta_modo_aplica(uuid, text, text) from public, anon, authenticated;
revoke all on function public._comision_devengo_reponer(uuid, numeric, jsonb, text) from public, anon, authenticated;

-- ── 2 · (f) solo el closer ANTERIOR, niveles closer/estandar/propia, con el mensaje de qué hacer ─────────────────────
create or replace function public._trg_contrato_closer_devengos_vivos()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_ant text := lower(btrim(coalesce(old.closer_email, '')));
begin
  if v_ant <> '' then
    if exists (select 1 from public.comisiones_devengadas d
                 left join public.solicitudes_pago sp on sp.id = d.solicitud_id
                where d.contrato_raiz_id = old.contrato_id and d.estado <> 'anulada'
                  and lower(d.beneficiario_email) = v_ant and d.nivel in ('closer', 'estandar', 'propia')
                  and (d.estado <> 'pendiente' or sp.estado in ('aprobada', 'pagada'))) then
      raise exception 'El closer anterior ya tiene comisiones de esta venta pagadas, aprobadas o en disputa: el cambio de closer no se permite. Lo regulariza Administración'
        using errcode = '22023';
    end if;
    if exists (select 1 from public.comisiones_devengadas d
                where d.contrato_raiz_id = old.contrato_id and d.estado <> 'anulada'
                  and lower(d.beneficiario_email) = v_ant and d.nivel in ('closer', 'estandar', 'propia')) then
      raise exception 'El closer anterior tiene comisiones pendientes en esta venta: para cambiar o quitar el closer, un administrador las anula antes con motivo (la de closer con comision_devengo_anular; la estándar o «por su cuenta» con comision_devengo_anular_lawang). Así el nuevo closer no cobra lo que devengó el anterior'
        using errcode = '22023';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end $function$;

revoke all on function public._trg_contrato_closer_devengos_vivos() from public, anon, authenticated;

-- ── 2 · vía de admin para anular una estandar/propia PENDIENTE (las paga Lawang, fuera de comision_devengo_anular) ──
-- Llamador: el administrador al que el trigger de arriba se lo indica al cambiar o quitar el closer.
create or replace function public.comision_devengo_anular_lawang(p_id uuid, p_motivo text)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  d     public.comisiones_devengadas;
  v_sp  public.solicitudes_pago;
  v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_yo  text := lower(coalesce(auth.email(), ''));
begin
  if v_mot is null then
    raise exception 'anular exige un motivo' using errcode = '22023';
  end if;
  if not (public.es_admin() and public.puede('comisiones_reparto')) then
    raise exception 'solo un administrador con el reparto de comisiones anula una comisión que paga Lawang' using errcode = '42501';
  end if;
  select * into d from public.comisiones_devengadas where id = p_id for update;
  if not found then raise exception 'no existe esa comisión' using errcode = 'P0002'; end if;
  if d.nivel not in ('estandar', 'propia') then
    raise exception 'esta vía es solo para la comisión estándar o «por su cuenta»; la de closer, setter o team lead se anula con comision_devengo_anular'
      using errcode = '22023';
  end if;
  if lower(d.beneficiario_email) = v_yo then
    raise exception 'no puedes anular una comisión a tu nombre' using errcode = '42501';
  end if;
  if d.estado <> 'pendiente' then
    raise exception 'solo se anula una comisión pendiente (esta está %): lo demás lo regulariza Administración', d.estado using errcode = '22023';
  end if;
  if d.solicitud_id is not null then
    select * into v_sp from public.solicitudes_pago sp where sp.id = d.solicitud_id for update;
  end if;
  if v_sp.estado in ('aprobada', 'pagada') then
    raise exception 'su solicitud de pago ya está %: no se anula desde aquí, lo regulariza Administración', v_sp.estado using errcode = '22023';
  end if;

  if v_sp.estado = 'pendiente' then
    -- misma vía que anular la solicitud a mano: su trigger deja el rastro y arrastra el devengo
    update public.solicitudes_pago set estado = 'anulada', motivo_ajuste = v_mot where id = v_sp.id;
  end if;
  if (select cd.estado from public.comisiones_devengadas cd where cd.id = d.id) <> 'anulada' then
    insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo)
    values ('comisiones_devengadas', d.id, 'anular', coalesce(d.importe_ajustado, d.importe), coalesce(d.importe_ajustado, d.importe),
            d.estado, 'anulada', v_mot);
    update public.comisiones_devengadas
       set estado = 'anulada', anulado_motivo = v_mot, anulado_por = auth.uid(), anulado_en = now()
     where id = d.id;
  end if;
end $function$;

revoke all on function public.comision_devengo_anular_lawang(uuid, text) from public, anon;
grant execute on function public.comision_devengo_anular_lawang(uuid, text) to authenticated;

-- ── 3 · comentario al día ───────────────────────────────────────────────────────────────────────────────────────
comment on column public.comisiones_devengadas.anulado_por_modo is
  'LAW-474 (a): true si la anuló _venta_modo_aplica al cambiar el modo de la venta; el motor la repone '
  '(_comision_devengo_reponer) si la venta vuelve a un modo que toca ese tramo. Queda en false, y no se repone nunca, '
  'si la anuló un administrador o si su solicitud de pago estaba rechazada.';
