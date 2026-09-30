-- LAW-474 (30-sep-2026) · restos de F5 («por su cuenta») antes de encender comisiones_interruptor.modo_obligatorio.
-- Parte de los cuerpos VIVOS (pg_get_functiondef) de comisiones_evaluar_contrato (ya con LAW-476, 20260930115040),
-- _venta_modo_aplica (md5 1c126b73…), comision_rol_asignar (f31a5a37…) y _ventas_propia_fin_espera (08225fec…).
--
-- (a) Una venta que pasa de «propia» a «equipo» y vuelve (o al revés) no volvía a devengar el mismo tramo: la fila
--     anulada por el cambio de modo seguía ocupando (venta, tramo, perceptor) y el motor la saltaba → al closer se le
--     pagaba de menos y nadie se enteraba. Ahora el cambio de modo marca sus anulaciones (anulado_por_modo) y, si la
--     venta vuelve a un modo que toca ese tramo, el motor REPONE la misma fila (_comision_devengo_reponer):
--       · no se había pagado → vuelve a pendiente con el importe de hoy y, si paga Lawang, solicitud nueva;
--       · ya pagada → nunca se reescribe lo pagado ni se paga dos veces: la diferencia negativa del cambio de modo, si
--         sigue pendiente, se anula; si ya se descontó, diferencia positiva al MISMO perceptor por lo descontado.
--     Una anulación hecha por un administrador (comision_devengo_anular) no se repone nunca.
-- (b) comision_rol_asignar rechaza setter/team lead en ventas «por su cuenta» (no cobran; solo confundía).
-- (c) El cron de fin de espera recorre TODA la cola vencida (ventas «propia» con la ventana acabada, sin objeción viva y
--     sin devengo vivo de «propia»/«estandar»), no solo las que vencieron en los últimos 3 días.
-- (d) venta_modo_admin a «propia» (dentro de un equipo) abre la ventana de 7 días, anota los cruces y avisa al SM, igual
--     que cuando lo declara el closer. Va dentro de _venta_modo_aplica para que el motor, que corre al final, ya vea la
--     ventana (si se abriera después, devengaría antes de que el SM pudiera objetar). «pasar_equipo» no abre nada.
-- (e) _venta_propia_cruces: índices de expresión en leads por email normalizado y teléfono E.164 (la consulta ya usaba
--     esas mismas expresiones). Con 133 leads el planificador sigue leyendo la tabla entera (más barato); los índices
--     están para cuando crezca. Medido en la cabecera de la prueba.
-- (f) Cambiar el closer de una venta con devengos vivos queda BLOQUEADO para cualquiera (trigger, cubre todos los
--     caminos): antes un super admin podía hacerlo y el motor calculaba para el nuevo closer lo ya devengado al anterior
--     (pago doble). Para cambiarlo, un administrador anula antes esos devengos con motivo (anulación explícita) y el
--     motor devenga al nuevo desde cero; lo ya pagado se regulariza por comision_devengo_anular / diferencias.
--
-- APLICADO AQUÍ: columna anulado_por_modo + marca en _venta_modo_aplica, (c), (d), (e) y (f).
-- NO APLICADO (lo frena tools/no_destruir.py, espera decisión del owner): la reposición de (a) — necesita ampliar el
-- CHECK de comisiones_ajustes_log.accion con «reponer» (DROP + ADD CONSTRAINT) — y (b) — re-crear comision_rol_asignar
-- lleva su «delete from contrato_roles_equipo» de siempre dentro del cuerpo. Listo en
-- supabase/pendientes/PENDIENTE_law474_a_b_reposicion_y_roles.sql. Mientras tanto la marca anulado_por_modo ya se
-- rellena en cada cambio de modo, así que la reposición, cuando se aplique, servirá también para esos casos.

-- ── (a) marca de anulación por cambio de modo ────────────────────────────────────────────────────────────────────
alter table public.comisiones_devengadas add column if not exists anulado_por_modo boolean not null default false;
comment on column public.comisiones_devengadas.anulado_por_modo is
  'LAW-474 (a): true si la anuló _venta_modo_aplica al cambiar el modo de la venta; el motor la repone si la venta vuelve '
  'a un modo que toca ese tramo. Una anulación de un administrador queda en false y no se repone nunca.';

-- ── (a) + (d): _venta_modo_aplica marca sus anulaciones y, a «propia» dentro de un equipo, abre ventana y avisa ─────
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
      -- LAW-474 (a): la anuló el cambio de modo (también si la arrastró su solicitud): el motor la repone si vuelve
      update public.comisiones_devengadas set anulado_por_modo = true where id = d.id and estado = 'anulada';

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

-- ── (c) cola completa del fin de espera ─────────────────────────────────────────────────────────────────────────
create or replace function public._ventas_propia_fin_espera_cola()
 returns setof uuid
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- toda venta «propia» con la ventana vencida (sin límite de días), sin objeción viva y aún sin devengo vivo de
  -- «propia»/«estandar»: los tramos siguientes ya los dispara el cobro (triggers de facturas), no hace falta el cron
  select k.contrato_id from public.contrato_closer k
   where k.modo = 'propia' and k.modo_espera_hasta <= now()
     and not exists (select 1 from public.reclamaciones_venta_propia x
                      where x.contrato_raiz_id = k.contrato_id and x.tipo = 'objecion' and x.estado = 'pendiente')
     and not exists (select 1 from public.comisiones_devengadas d
                      where d.contrato_raiz_id = k.contrato_id and d.nivel in ('propia', 'estandar') and d.estado <> 'anulada')
   order by k.contrato_id
$function$;

revoke all on function public._ventas_propia_fin_espera_cola() from public, anon, authenticated;

create or replace function public._ventas_propia_fin_espera()
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare r record; n integer := 0;
begin
  for r in select x.id as contrato_id from public._ventas_propia_fin_espera_cola() x(id) loop
    begin
      n := n + coalesce(public.comisiones_evaluar_contrato(r.contrato_id), 0);
    exception when others then
      update public.comisiones_interruptor
         set ultimo_error = 'fin de espera por su cuenta: ' || sqlerrm || ' (contrato ' || r.contrato_id || ')', ultimo_error_en = now()
       where id;
    end;
  end loop;
  return n;
end $function$;

-- ── (e) índices de identidad normalizada para _venta_propia_cruces ──────────────────────────────────────────────
create index if not exists leads_email_norm_idx on public.leads (public._lw_email_norm(email));
create index if not exists leads_whatsapp_e164_idx on public.leads (public._lw_tel_e164(whatsapp));

-- ── (f) cambio de closer con devengos vivos: bloqueado en todos los caminos ─────────────────────────────────────
create or replace function public._trg_contrato_closer_devengos_vivos()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if exists (select 1 from public.comisiones_devengadas d
              where d.contrato_raiz_id = old.contrato_id and d.estado <> 'anulada') then
    raise exception 'Esta venta ya tiene comisiones vivas: para cambiar el closer, un administrador las anula antes con motivo (así el nuevo closer no cobra lo que ya devengó el anterior)'
      using errcode = '22023';
  end if;
  return new;
end $function$;

revoke all on function public._trg_contrato_closer_devengos_vivos() from public, anon, authenticated;

create trigger trg_contrato_closer_a_devengos_vivos
  before update of closer_email on public.contrato_closer
  for each row
  when (lower(coalesce(old.closer_email, '')) is distinct from lower(coalesce(new.closer_email, '')))
  execute function public._trg_contrato_closer_devengos_vivos();
