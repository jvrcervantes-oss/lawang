-- Frontera frontend/backend — COBROS por el servidor (26-sep-2026, LAW-336 pieza 2).
-- Máxima del owner: «no te creas NADA del front-end». SOLO AÑADE; el revoke va después.
-- SECURITY DEFINER con el permiso comprobado dentro (= las policies de hoy), porque tras el
-- revoke `authenticated` no escribirá en estas tablas. Los triggers de siempre siguen mandando
-- (_trg_solicitud_pago_alta/_transicion leen auth.uid()/email() del JWT, que sigue ahí).
--
-- Lo que la pantalla decidía y la base se creía, y ya no:
-- · solicitudes_pago: el alta aceptaba `origen` del cliente; con origen 'comision_automatica'
--   el trigger respetaba el beneficiario que mandara el formulario. Ahora el alta manual es
--   SIEMPRE origen 'manual' y el importe se valida en el servidor. (`numero` es identity
--   ALWAYS: la base ya lo rechazaba; la nota de la primera versión de este comentario que decía
--   lo contrario era falsa.)
-- · contrato_vencimientos: «solo hitos de contratos firmados y aún sin facturar» y «la nota y
--   el no_facturar no se editan por pantalla» (decisión 15-sep) solo los aplicaba la PANTALLA.
-- Aplicada por MCP el 26-sep y probada (11 casos + hito facturado simulado) sin dejar rastro;
-- la secuencia de solicitudes se restauró a 57 tras la prueba.

create or replace function public._solicitud_puede_tocar(s public.solicitudes_pago)
returns boolean language sql stable security definer set search_path = '' as $$
  -- = policy «solicitudes: admin resuelve, el creador toca la suya pendiente» (USING)
  select (public.es_admin() and public.puede('comisiones'))
      or (s.creado_por = (select auth.uid()) and s.estado = 'pendiente')
$$;
revoke all on function public._solicitud_puede_tocar(public.solicitudes_pago) from public, anon, authenticated;

create or replace function public.solicitud_pago_guarda(p_id uuid, p_datos jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_old public.solicitudes_pago%rowtype;
  v_contrato uuid := nullif(p_datos->>'contrato_id', '')::uuid;
  v_importe numeric := public.lw_parse_importe(p_datos->>'importe');
  v_concepto text := nullif(btrim(coalesce(p_datos->>'concepto', '')), '');
  v_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_agente() then raise exception 'Solo el equipo pide pagos' using errcode = '42501'; end if;
  if v_importe is null or v_importe <= 0 then
    raise exception 'El importe no se entiende: tiene que ser un número mayor que cero' using errcode = '22023';
  end if;
  if v_contrato is not null and not exists (select 1 from public.contratos c
       where c.id = v_contrato and public.contrato_visible(c.creado_por, c.proyecto_id)) then
    raise exception 'No puedes pedir un pago sobre un contrato que no ves' using errcode = '42501';
  end if;

  if p_id is null then
    if v_concepto is null then raise exception 'El concepto no puede quedar vacío' using errcode = '22023'; end if;
    insert into public.solicitudes_pago as s (contrato_id, concepto, importe, moneda, vence_el, nota, origen, creado_por)
    values (v_contrato, v_concepto, v_importe, nullif(p_datos->>'moneda', ''),
            nullif(p_datos->>'vence_el', '')::date, nullif(btrim(coalesce(p_datos->>'nota', '')), ''),
            'manual', (select auth.uid()))
    returning s.id into v_id;
    return v_id;
  end if;

  select * into v_old from public.solicitudes_pago s where s.id = p_id for update;
  if not found then raise exception 'Esa solicitud ya no existe' using errcode = 'P0002'; end if;
  if not public._solicitud_puede_tocar(v_old) then
    raise exception 'No puedes editar esta solicitud (no es tuya, o ya no está pendiente)' using errcode = '42501';
  end if;
  -- Solo los campos editables; el trigger de transición decide el resto (automáticas,
  -- motivo obligatorio al cambiar el importe ajeno, registro de ajustes).
  update public.solicitudes_pago s set
    contrato_id = case when p_datos ? 'contrato_id' then v_contrato else s.contrato_id end,
    concepto = coalesce(v_concepto, s.concepto),
    importe = v_importe,
    moneda = coalesce(nullif(p_datos->>'moneda', ''), s.moneda),
    vence_el = case when p_datos ? 'vence_el' then nullif(p_datos->>'vence_el', '')::date else s.vence_el end,
    nota = case when p_datos ? 'nota' then nullif(btrim(coalesce(p_datos->>'nota', '')), '') else s.nota end,
    motivo_ajuste = nullif(btrim(coalesce(p_datos->>'motivo_ajuste', '')), '')
  where s.id = p_id
  returning s.id into v_id;
  return v_id;
end $$;

-- Aprobar / rechazar / anular / marcar pagada. Las reglas de quién puede cada paso viven en
-- _trg_solicitud_pago_transicion (servidor, desde antes): aquí solo se exige la policy y se
-- aceptan los datos propios de cada paso.
create or replace function public.solicitud_pago_resuelve(p_id uuid, p_estado text, p_motivo text default null, p_referencia text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_old public.solicitudes_pago%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if p_estado not in ('aprobada', 'rechazada', 'anulada', 'pagada') then
    raise exception 'Paso desconocido: %', p_estado using errcode = '22023';
  end if;
  select * into v_old from public.solicitudes_pago s where s.id = p_id for update;
  if not found then raise exception 'Esa solicitud ya no existe' using errcode = 'P0002'; end if;
  if not public._solicitud_puede_tocar(v_old) then
    raise exception 'No puedes cambiar esta solicitud' using errcode = '42501';
  end if;
  update public.solicitudes_pago s set
    estado = p_estado,
    motivo_rechazo = case when p_estado = 'rechazada' then nullif(btrim(coalesce(p_motivo, '')), '') else s.motivo_rechazo end,
    motivo_ajuste = case when p_estado = 'anulada' then nullif(btrim(coalesce(p_motivo, '')), '') else s.motivo_ajuste end,
    pago_referencia = case when p_estado = 'pagada' then nullif(btrim(coalesce(p_referencia, '')), '') else s.pago_referencia end
  where s.id = p_id;
end $$;

-- Ajustar la fecha de un hito. Lo que decía la pantalla, ahora en el servidor:
-- solo contratos FIRMADOS (bloqueado), solo hitos SIN FACTURAR, y solo la fecha.
create or replace function public.vencimiento_ajusta_fecha(p_id uuid, p_fecha date)
returns void language plpgsql security definer set search_path = '' as $$
declare v public.contrato_vencimientos%rowtype; c public.contratos%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  select * into v from public.contrato_vencimientos cv where cv.id = p_id for update;
  if not found then raise exception 'Ese hito ya no existe' using errcode = 'P0002'; end if;
  select * into c from public.contratos k where k.id = v.contrato_id;
  -- = policy vencimientos_update
  if not (public.es_agente() and public.puede('vencimientos')
          and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))) then
    raise exception 'No puedes ajustar hitos de este contrato' using errcode = '42501';
  end if;
  if not coalesce(c.bloqueado, false) then
    raise exception 'El contrato % no está firmado: sus hitos se regeneran solos, no se ajustan a mano', c.numero using errcode = '22023';
  end if;
  if v.factura_id is not null then
    raise exception 'Ese hito ya está facturado: su fecha viaja en la factura; se corrige anulando y reemitiendo' using errcode = '22023';
  end if;
  update public.contrato_vencimientos cv set fecha = p_fecha, ajustado = true where cv.id = p_id;
end $$;

revoke all on function public.solicitud_pago_guarda(uuid, jsonb), public.solicitud_pago_resuelve(uuid, text, text, text),
  public.vencimiento_ajusta_fecha(uuid, date) from public, anon;
grant execute on function public.solicitud_pago_guarda(uuid, jsonb), public.solicitud_pago_resuelve(uuid, text, text, text),
  public.vencimiento_ajusta_fecha(uuid, date) to authenticated;
