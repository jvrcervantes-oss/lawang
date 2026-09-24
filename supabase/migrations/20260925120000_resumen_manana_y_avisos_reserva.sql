-- ============================================================================
-- RESUMEN DE LA MAÑANA + RESERVAS POR VENCER CON BOTONES — 25-sep-2026
-- Encargo 20260925_lawang_resumen_manana_y_reservas_telegram.md · revisión previa #76
-- (Seguridad, Datos, Legal). Owner: «necesito más Quality of Life de estos para mí».
--
-- Decisiones de la revisión (y por qué):
--   · «Hitos vencidos sin factura» tenía su regla SOLO en JS (Home, datos.js «Hoy toca»,
--     con el reparto de facturas vivas entre hitos porque muchas no se enlazaron a su hito).
--     Reescribirla aquí sería una segunda copia que acaba dando otra cifra: se saca a
--     `hitos_sin_factura()` — fuente única; el Home debe migrar a ella (pendiente anotado).
--   · `crm_leads_resumen()` filtra por puede('leads') y con service_role da 0 sin error:
--     se saca su núcleo a `_crm_leads_nucleo()` y la pública lo envuelve (un solo dueño).
--   · Moneda de un hito = la de su contrato, null = EUR (como el Home); hitos sin importe
--     se cuentan aparte, nunca como 0.
--   · «Hoy» es SIEMPRE el de Bali (Asia/Makassar): el resumen sale a las 08:00 de Bali,
--     que son las 00:00 UTC, justo en el cambio de fecha de current_date.
--   · El botón actúa como super_admin y `prorroga_reserva` no le aplica el tope de
--     prórrogas: TOPE PROPIO del canal Telegram (= reservas.prorrogas_max_manager) y los 7
--     días fijos AQUÍ, nunca en el botón. Por encima del tope, el aviso sale sin botón.
--   · Sin iniciales ni nombre del comprador en Telegram (Legal: contrato + iniciales
--     identifican a la persona y la aceptación de LAW-76 no cubre compradores).
--   · Doble toque / reintento de Telegram: `decision` ya puesta = no hace nada.
--   · Mismo advisory lock que `prorroga_reserva` ANTES de comprobar el vencimiento.
-- ============================================================================

-- ── Núcleo del recuento de leads (sin filtro de permisos) ───────────────────
create or replace function public._crm_leads_nucleo()
returns table (total bigint, nuevos bigint, parados bigint, nuevos_24h bigint)
language sql stable security definer set search_path to ''
as $$
  select count(*),
         count(*) filter (where coalesce(e.estado, 'nuevo') = 'nuevo'),
         count(*) filter (where coalesce(e.estado, 'nuevo') = 'nuevo'
                            and coalesce(e.estado_desde, l.created_at) < now() - interval '14 days'),
         count(*) filter (where l.created_at > now() - interval '24 hours')
    from public.leads l
    left join public.lead_estado e on e.lead_id = l.id
$$;
revoke execute on function public._crm_leads_nucleo() from public, anon, authenticated;

create or replace function public.crm_leads_resumen()
returns table (total bigint, nuevos bigint, parados bigint)
language sql stable security definer set search_path to ''
as $$
  select n.total, n.nuevos, n.parados from public._crm_leads_nucleo() n where public.puede('leads')
$$;

-- ── Hitos vencidos sin factura: la regla de «Hoy toca», una sola vez ────────
create or replace function public.hitos_sin_factura(p_hoy date)
returns table (contrato_id uuid, numero text, descripcion text, fecha date, monto numeric, moneda text)
language plpgsql stable security definer set search_path to ''
as $$
declare
  c_id   uuid := null;
  libres numeric[];
  h      record;
  i      int;
  cubierto boolean;
begin
  -- desde el 18-ago-2026, día en que se activó la factura automática (igual que el Home)
  for h in
    select v.contrato_id, c.numero, v.descripcion, v.fecha, v.monto, coalesce(c.moneda, 'EUR') as moneda
      from public.contrato_vencimientos v
      join public.contratos c on c.id = v.contrato_id
     where coalesce(c.bloqueado, false) and c.liberado_en is null
       and v.factura_id is null and not coalesce(v.no_facturar, false)
       and v.fecha < p_hoy and v.fecha >= date '2026-08-18'
     order by v.contrato_id, v.fecha
  loop
    if h.contrato_id is distinct from c_id then
      c_id := h.contrato_id;
      -- facturas vivas del contrato, de menor a mayor (cada una cubre un solo hito)
      select coalesce(array_agg(coalesce(f.total, 0) order by coalesce(f.total, 0)), '{}')
        into libres
        from public.facturas f
       where f.contrato_id = c_id and f.tipo = 'factura' and not coalesce(f.anulada, false);
    end if;
    cubierto := false;
    for i in 1 .. coalesce(array_length(libres, 1), 0) loop
      if libres[i] >= coalesce(h.monto, 0) * 0.99 then
        libres := libres[1:i-1] || libres[i+1:];
        cubierto := true;
        exit;
      end if;
    end loop;
    if not cubierto then
      contrato_id := h.contrato_id; numero := h.numero; descripcion := h.descripcion;
      fecha := h.fecha; monto := h.monto; moneda := h.moneda;
      return next;
    end if;
  end loop;
end
$$;
revoke execute on function public.hitos_sin_factura(date) from public, anon, authenticated;
grant execute on function public.hitos_sin_factura(date) to service_role;

-- ── Resumen de la mañana: solo recuentos, importes y números de documento ───
create or replace function public.resumen_manana(p_hoy date)
returns jsonb
language plpgsql stable security definer set search_path to ''
as $$
declare
  v_gracia int := coalesce((public.parametro('reservas.dias_gracia'))::int, 3);
  r jsonb := '{}'::jsonb;
begin
  if p_hoy is distinct from (now() at time zone 'Asia/Makassar')::date then
    raise exception 'p_hoy tiene que ser hoy en Bali' using errcode = '22023';
  end if;

  r := r || jsonb_build_object('hoy', p_hoy, 'leads',
    (select to_jsonb(n) from public._crm_leads_nucleo() n));

  -- reservas vivas, una fila por CONTRATO (la función da una por parcela)
  r := r || jsonb_build_object('reservas', (
    select coalesce(jsonb_agg(x order by x->>'vence_el'), '[]'::jsonb) from (
      select jsonb_build_object('numero', min(rv.numero), 'proyecto', min(rv.proyecto_nombre),
               'parcelas', string_agg(distinct rv.codigo, ', '), 'vence_el', min(rv.vence_el),
               'dias', min(rv.vence_el) - p_hoy, 'prorrogas', max(rv.n_prorrogas)) as x
        from public.reservas_vencimiento() rv
       where rv.vence_el is not null and rv.vence_el <= p_hoy + 7 and rv.vence_el > p_hoy - v_gracia
       group by rv.contrato_id) t));
  r := r || jsonb_build_object('dias_gracia', v_gracia);

  -- hitos vencidos sin factura (regla del Home) y por facturar en 7 días, POR MONEDA
  r := r || jsonb_build_object('hitos_vencidos', (
    select coalesce(jsonb_object_agg(moneda, jsonb_build_object('n', n, 'importe', importe, 'sin_importe', sin_importe)), '{}'::jsonb)
      from (select h.moneda, count(*) n, coalesce(sum(h.monto), 0) importe, count(*) filter (where h.monto is null) sin_importe
              from public.hitos_sin_factura(p_hoy) h group by h.moneda) t),
    'hitos_mas_antiguo', (select jsonb_build_object('numero', h.numero, 'descripcion', h.descripcion, 'fecha', h.fecha)
                            from public.hitos_sin_factura(p_hoy) h order by h.fecha limit 1));
  r := r || jsonb_build_object('hitos_7d', (
    select coalesce(jsonb_object_agg(moneda, jsonb_build_object('n', n, 'importe', importe, 'sin_importe', sin_importe)), '{}'::jsonb)
      from (select coalesce(c.moneda, 'EUR') moneda, count(*) n, coalesce(sum(v.monto), 0) importe,
                   count(*) filter (where v.monto is null) sin_importe
              from public.contrato_vencimientos v join public.contratos c on c.id = v.contrato_id
             where coalesce(c.bloqueado, false) and c.liberado_en is null
               and v.factura_id is null and not coalesce(v.no_facturar, false)
               and v.fecha between p_hoy and p_hoy + 7
             group by 1) t));

  -- lo que espera una decisión del owner
  r := r || jsonb_build_object('esperando', jsonb_build_object(
    'peticiones', (select count(*) from public.solicitudes_cambio where estado = 'pendiente'),
    'pagos_pendientes', (select count(*) from public.solicitudes_pago where estado = 'pendiente'),
    'pagos_por_pagar', (select count(*) from public.solicitudes_pago where estado = 'aprobada')));
  return r;
end
$$;
revoke execute on function public.resumen_manana(date) from public, anon, authenticated;
grant execute on function public.resumen_manana(date) to service_role;

-- ── Avisos de reserva por vencer (un aviso por contrato y vencimiento) ──────
create table public.avisos_reserva (
  id              uuid primary key default gen_random_uuid(),
  contrato_id     uuid not null references public.contratos(id) on delete cascade,
  vence_el        date not null,
  telegram_msg_id bigint,
  avisado_en      timestamptz,
  decision        text check (decision in ('prorrogada','dejar_vencer','fallida')),
  decidido_en     timestamptz,
  decidido_via    text,
  resultado       jsonb,
  creado_en       timestamptz not null default now(),
  unique (contrato_id, vence_el)
);
alter table public.avisos_reserva enable row level security;
revoke all on public.avisos_reserva from public, anon, authenticated;
grant all on public.avisos_reserva to service_role;
comment on table public.avisos_reserva is
  'Avisos al owner por Telegram de reservas que vencen en N días, con botones Prorrogar/Dejar vencer. resolver_aviso_reserva() decide. Encargo 20260925_lawang_resumen_manana_y_reservas_telegram.md.';

create or replace function public.reservas_para_avisar(p_hoy date)
returns table (id uuid, numero text, proyecto text, parcelas text, vence_el date, dias int,
               prorrogas int, puede_prorrogar boolean, nuevo_vencimiento date, libera_el date)
language plpgsql security definer set search_path to ''
as $$
declare
  v_antes  int := coalesce((public.parametro('reservas.aviso_owner_dias_antes'))::int, 3);
  v_gracia int := coalesce((public.parametro('reservas.dias_gracia'))::int, 3);
  v_tope   int := coalesce((public.parametro('reservas.prorrogas_max_manager'))::int, 2);
begin
  if p_hoy is distinct from (now() at time zone 'Asia/Makassar')::date then
    raise exception 'p_hoy tiene que ser hoy en Bali' using errcode = '22023';
  end if;
  insert into public.avisos_reserva (contrato_id, vence_el)
  select distinct rv.contrato_id, rv.vence_el
    from public.reservas_vencimiento() rv
   where rv.vence_el = p_hoy + v_antes
  on conflict on constraint avisos_reserva_contrato_id_vence_el_key do nothing;

  return query
  select a.id, c.numero, c.proyecto_nombre,
         (select string_agg(distinct u.codigo, ', ') from public.unidades u where u.contrato_id = c.id),
         a.vence_el, (a.vence_el - p_hoy)::int,
         (select count(*)::int from public.contrato_prorrogas p where p.contrato_id = c.id),
         (select count(*) from public.contrato_prorrogas p where p.contrato_id = c.id) < v_tope,
         a.vence_el + 7, a.vence_el + v_gracia
    from public.avisos_reserva a join public.contratos c on c.id = a.contrato_id
   where a.telegram_msg_id is null and a.decision is null and a.vence_el >= p_hoy
   order by a.vence_el
   limit 10;
end
$$;
revoke execute on function public.reservas_para_avisar(date) from public, anon, authenticated;
grant execute on function public.reservas_para_avisar(date) to service_role;

create or replace function public.marcar_aviso_reserva(p_id uuid, p_msg_id bigint)
returns void
language sql security definer set search_path to ''
as $$
  update public.avisos_reserva set telegram_msg_id = p_msg_id, avisado_en = now()
   where id = p_id and telegram_msg_id is null
$$;
revoke execute on function public.marcar_aviso_reserva(uuid, bigint) from public, anon, authenticated;
grant execute on function public.marcar_aviso_reserva(uuid, bigint) to service_role;

-- ── Resolver el botón: una transacción, idempotente, candados AQUÍ ──────────
create or replace function public.resolver_aviso_reserva(p_id uuid, p_msg_id bigint,
                                                         p_decision text, p_via text)
returns jsonb
language plpgsql security definer set search_path to ''
as $$
declare
  a       public.avisos_reserva;
  v_tg    bigint;
  v_aprob public.usuarios;
  v_tope  int := coalesce((public.parametro('reservas.prorrogas_max_manager'))::int, 2);
  v_n     int;
  v_vence date;
  v_hasta date;
  v_res   jsonb;
  c_claims text := current_setting('request.jwt.claims', true);
  c_sub    text := current_setting('request.jwt.claim.sub', true);
  c_email  text := current_setting('request.jwt.claim.email', true);
  c_role   text := current_setting('request.jwt.claim.role', true);
begin
  if p_decision not in ('prorrogar','dejar') then
    raise exception 'decisión no válida' using errcode = '22023';
  end if;
  select * into a from public.avisos_reserva where id = p_id for update;
  if not found then return jsonb_build_object('estado', 'desconocido'); end if;
  if a.telegram_msg_id is distinct from p_msg_id then
    raise exception 'el mensaje no corresponde a este aviso' using errcode = '42501';
  end if;
  if a.decision is not null then
    return jsonb_build_object('estado', a.decision, 'ya_resuelta', true, 'resultado', a.resultado);
  end if;

  v_tg := nullif(substring(coalesce(p_via, '') from '^telegram:(\d{1,20})$'), '')::bigint;
  select u.* into v_aprob
    from public.aprobadores_telegram t join public.usuarios u on u.user_id = t.user_id
   where t.telegram_id = v_tg and u.activo and u.rol = 'super_admin';
  if v_aprob.user_id is null then
    raise exception 'ese usuario de Telegram no puede decidir' using errcode = '42501';
  end if;

  if p_decision = 'dejar' then
    update public.avisos_reserva
       set decision = 'dejar_vencer', decidido_en = now(), decidido_via = p_via
     where id = p_id;
    return jsonb_build_object('estado', 'dejar_vencer');
  end if;

  begin
    -- el MISMO candado que prorroga_reserva, antes de comprobar nada
    perform pg_advisory_xact_lock(hashtext('prorroga:' || a.contrato_id::text));
    if not exists (select 1 from public.reservas_vencimiento() rv where rv.contrato_id = a.contrato_id) then
      raise exception 'la reserva ya no está viva (liberada, pasada a Bloqueo o firmada)';
    end if;
    v_vence := public.reserva_vence_el(a.contrato_id);
    if v_vence is distinct from a.vence_el then
      raise exception 'el vencimiento ya cambió (ahora %): no se prorroga dos veces', v_vence;
    end if;
    select count(*) into v_n from public.contrato_prorrogas where contrato_id = a.contrato_id;
    if v_n >= v_tope then
      raise exception 'ya lleva % prórrogas: la siguiente se da desde la intranet', v_n;
    end if;

    perform set_config('request.jwt.claims',
      jsonb_build_object('sub', v_aprob.user_id, 'role', 'authenticated', 'email', v_aprob.email)::text, true);
    perform set_config('request.jwt.claim.sub', v_aprob.user_id::text, true);
    perform set_config('request.jwt.claim.email', v_aprob.email, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);

    v_hasta := public.prorroga_reserva(a.contrato_id, 7,
                 'Prórroga de 7 días desde Telegram (aviso 3 días antes del vencimiento)', false);
    v_res := jsonb_build_object('hasta', v_hasta, 'n', v_n + 1);
    update public.avisos_reserva
       set decision = 'prorrogada', decidido_en = now(), decidido_via = p_via, resultado = v_res
     where id = p_id;
  exception when others then
    v_res := jsonb_build_object('error', sqlerrm);
  end;

  perform set_config('request.jwt.claims', coalesce(c_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(c_sub, ''), true);
  perform set_config('request.jwt.claim.email', coalesce(c_email, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(c_role, ''), true);

  if v_res ? 'error' then
    update public.avisos_reserva
       set decision = 'fallida', decidido_en = now(), decidido_via = p_via, resultado = v_res
     where id = p_id;
    return jsonb_build_object('estado', 'fallida', 'error', v_res->>'error');
  end if;
  return jsonb_build_object('estado', 'prorrogada', 'hasta', v_hasta);
end
$$;
revoke execute on function public.resolver_aviso_reserva(uuid, bigint, text, text) from public, anon, authenticated;
grant execute on function public.resolver_aviso_reserva(uuid, bigint, text, text) to service_role;
