-- destructivo-ok: el drop de abajo tumba una tabla creada HOY MISMO (migración
-- 20260909071823_solicitudes_pago) con CERO filas — verificado con count(*)
-- justo antes de aplicar esto. No se pierde ni un dato: se corrige la
-- SEMÁNTICA antes de que la use nadie. (El resto de avisos del guardrail son
-- el mismo falso positivo de la v1: `for update` de policy y `before update
-- on` de trigger leídos como UPDATE sin WHERE.)
-- ============================================================================
-- SOLICITUDES DE PAGO v2 — 9-sep-2026, corrección del owner en la misma sesión
-- ----------------------------------------------------------------------------
-- Owner, textual: «Las solicitudes de pago las ponen los agentes para pedirle
-- a Lawang que les pague ciertos importes como pueden ser comisiones o pagos
-- acordados, no para cargarlas sobre los compradores.»
--
-- La v1 apuntaba el dinero al revés (cobros a compradores, cierre con la
-- factura emitida). Lo que se queda igual: cola agente→admin, RLS (cada uno
-- lo suyo, admin todo), máquina de estados en trigger, sellos de resolución,
-- avisos por la campana. Lo que cambia:
--   · fuera client_id y factura_id — el comprador no es la contraparte y a un
--     pago SALIENTE no lo cierra una factura de cliente;
--   · contrato_id se queda como REFERENCIA OPCIONAL (la venta de la que sale
--     la comisión), sin imponer nada;
--   · moneda propia siempre (el pago al agente no hereda la del contrato);
--   · el estado terminal es `pagada` (admin la marca al hacer el pago, con
--     referencia libre del pago) — mismo hallazgo de Administración que
--     motivó `cerrada` en la v1: aprobada ≠ pagada, que nada se quede en el
--     limbo sin verse.
-- ============================================================================

drop table public.solicitudes_pago;

create table public.solicitudes_pago (
  id           uuid primary key default gen_random_uuid(),
  -- solo para nombrarla en pantalla y en la campana: «SP-7»
  numero       bigint generated always as identity,
  -- la venta de la que sale este pago, si la hay (comisión de un contrato);
  -- pura referencia — el importe lo pacta el owner con el agente, no se deriva
  contrato_id  uuid references public.contratos(id),
  concepto     text not null,
  -- numeric, no text: dinero_no_es_texto.sql (19-ago). El cliente parsea lo
  -- tecleado con lwParseImporte ANTES de mandarlo.
  importe      numeric not null,
  moneda       text not null default 'EUR',
  vence_el     date,
  nota         text,
  estado       text not null default 'pendiente',
  motivo_rechazo text,
  -- cómo se pagó (transferencia, fecha, referencia) — lo escribe el admin al
  -- marcar pagada; texto libre a propósito: el pago real ocurre fuera
  pago_referencia text,
  creado_por   uuid not null default auth.uid() references public.usuarios(user_id),
  creado_en    timestamptz not null default now(),
  resuelto_por uuid references public.usuarios(user_id),
  resuelto_en  timestamptz,
  pagado_por   uuid references public.usuarios(user_id),
  pagado_en    timestamptz,

  constraint solicitud_concepto_no_vacio check (btrim(concepto) <> ''),
  constraint solicitud_importe_positivo  check (importe > 0),
  constraint solicitud_moneda_valida     check (moneda in ('EUR','USD','IDR')),
  constraint solicitud_estado_valido
    check (estado in ('pendiente','aprobada','rechazada','anulada','pagada')),
  constraint solicitud_rechazo_con_motivo
    check (estado <> 'rechazada' or btrim(coalesce(motivo_rechazo, '')) <> ''),
  constraint solicitud_pagada_con_sello
    check (estado <> 'pagada' or pagado_en is not null)
);

comment on table public.solicitudes_pago is
  'Pagos que los agentes le piden a Lawang (comisiones, pagos acordados). No mueve dinero: registra la petición y su resolución. Máquina de estados en _trg_solicitud_pago_transicion.';
comment on column public.solicitudes_pago.contrato_id is
  'Referencia opcional: la venta de la que sale este pago. No impone importe ni moneda.';

create index solicitudes_pago_estado_idx on public.solicitudes_pago(estado);
create index solicitudes_pago_creado_por_idx on public.solicitudes_pago(creado_por);

alter table public.solicitudes_pago enable row level security;

-- ── RLS: reparto de ACCESO por fila. Las transiciones viven en el trigger ───
create policy "solicitudes: cada agente lee las suyas, admin todas"
  on public.solicitudes_pago for select
  using (public.es_admin() or creado_por = (select auth.uid()));

create policy "solicitudes: el equipo crea las suyas"
  on public.solicitudes_pago for insert
  with check (public.es_agente() and creado_por = (select auth.uid()));

create policy "solicitudes: admin resuelve, el creador toca la suya pendiente"
  on public.solicitudes_pago for update
  using (public.es_admin() or (creado_por = (select auth.uid()) and estado = 'pendiente'))
  with check (public.es_admin() or creado_por = (select auth.uid()));

-- sin policy de DELETE: una solicitud no se borra, se anula o se rechaza.
-- anon y portal: sin policies = sin acceso.

-- ── Alta: lo que mande el cliente en las columnas selladas se pisa ──────────
create or replace function public._trg_solicitud_pago_alta()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  new.estado := 'pendiente';
  new.creado_por := auth.uid();
  new.creado_en := now();
  new.resuelto_por := null; new.resuelto_en := null;
  new.pagado_por := null;   new.pagado_en := null;
  new.pago_referencia := null;
  new.motivo_rechazo := null;
  new.concepto := btrim(new.concepto);
  return new;
end
$$;

create trigger trg_solicitud_pago_alta
  before insert on public.solicitudes_pago
  for each row execute function public._trg_solicitud_pago_alta();

-- ── La máquina de estados, entera y en un solo sitio ────────────────────────
--    pendiente → aprobada | rechazada   (solo admin; sella resuelto_por/en)
--    pendiente → anulada                (solo el creador; también sella)
--    pendiente → pendiente              (el creador corrige su petición)
--    aprobada  → pagada                 (solo admin; sella pagado_por/en y
--                                        admite pago_referencia; congela el resto)
--    todo lo demás → error con el motivo dicho con todas las letras
create or replace function public._trg_solicitud_pago_transicion()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  new.numero := old.numero;
  new.creado_por := old.creado_por;
  new.creado_en := old.creado_en;

  if old.estado = 'pendiente' then
    if new.estado = 'pendiente' then
      new.resuelto_por := null; new.resuelto_en := null;
      new.pagado_por := null;   new.pagado_en := null;
      new.pago_referencia := null; new.motivo_rechazo := null;
      new.concepto := btrim(new.concepto);
      return new;
    elsif new.estado in ('aprobada','rechazada') then
      if not public.es_admin() then
        raise exception 'solo un administrador resuelve una solicitud' using errcode = '42501';
      end if;
    elsif new.estado = 'anulada' then
      if old.creado_por is distinct from auth.uid() then
        raise exception 'solo quien creó la solicitud puede anularla' using errcode = '42501';
      end if;
    else
      raise exception 'desde pendiente solo se puede aprobar, rechazar o anular' using errcode = '22023';
    end if;
    -- al resolver, lo pedido queda congelado tal cual se pidió
    new.contrato_id := old.contrato_id; new.concepto := old.concepto;
    new.importe := old.importe;         new.moneda := old.moneda;
    new.vence_el := old.vence_el;       new.nota := old.nota;
    new.pagado_por := null; new.pagado_en := null; new.pago_referencia := null;
    new.resuelto_por := auth.uid();
    new.resuelto_en := now();
    return new;

  elsif old.estado = 'aprobada' and new.estado = 'pagada' then
    if not public.es_admin() then
      raise exception 'solo un administrador marca una solicitud como pagada' using errcode = '42501';
    end if;
    -- todo lo demás, congelado como quedó al aprobar; pago_referencia es lo
    -- único que entra nuevo en esta transición
    new.contrato_id := old.contrato_id; new.concepto := old.concepto;
    new.importe := old.importe;         new.moneda := old.moneda;
    new.vence_el := old.vence_el;       new.nota := old.nota;
    new.motivo_rechazo := old.motivo_rechazo;
    new.resuelto_por := old.resuelto_por; new.resuelto_en := old.resuelto_en;
    new.pagado_por := auth.uid();
    new.pagado_en := now();
    return new;
  end if;

  raise exception 'una solicitud % no se puede editar', old.estado using errcode = '22023';
end
$$;

create trigger trg_solicitud_pago_transicion
  before update on public.solicitudes_pago
  for each row execute function public._trg_solicitud_pago_transicion();

-- ── Campana: HECHOS al canal existente (notificaciones.sql, 4-ago) ──────────
--    Al crear → destinatario null (= solo administradores). Al resolver o
--    pagar → el email del creador. El fallo del aviso nunca deshace la
--    escritura que lo disparó. El texto lo pinta topbar.js con esc().
create or replace function public._trg_solicitud_pago_aviso()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare v_email text; v_nombre text;
begin
  if tg_op = 'INSERT' then
    select u.nombre into v_nombre from public.usuarios u where u.user_id = new.creado_por;
    insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace)
    values ('solicitud_pago',
            'Solicitud de pago SP-' || new.numero,
            coalesce(v_nombre, 'Un comercial') || ' pide un pago: ' || new.concepto,
            null, new.contrato_id,
            '/intranet/solicitudes/?id=' || new.id::text);
  elsif tg_op = 'UPDATE' and new.estado is distinct from old.estado and new.estado <> 'pendiente' then
    select u.email into v_email from public.usuarios u where u.user_id = new.creado_por;
    -- al creador no se le avisa de lo que hizo él mismo (anular la suya)
    if v_email is not null and new.estado <> 'anulada' then
      insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace)
      values ('solicitud_pago',
              'Tu solicitud SP-' || new.numero || ' — ' ||
                case new.estado when 'aprobada' then 'aprobada'
                                when 'rechazada' then 'rechazada'
                                when 'pagada' then 'pagada' end,
              case when new.estado = 'rechazada' then new.motivo_rechazo
                   when new.estado = 'pagada' then coalesce(new.pago_referencia, new.concepto)
                   else new.concepto end,
              v_email, new.contrato_id,
              '/intranet/solicitudes/?id=' || new.id::text);
    end if;
  end if;
  return new;
exception when others then
  return new;   -- la solicitud ya se guardó; un fallo del aviso no la deshace
end
$$;

create trigger trg_solicitud_pago_aviso
  after insert or update on public.solicitudes_pago
  for each row execute function public._trg_solicitud_pago_aviso();
