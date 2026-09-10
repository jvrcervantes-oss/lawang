-- destructivo-ok: falso positivo del guardrail — aquí no hay ningún UPDATE de
-- datos; lo que casa con «UPDATE sin WHERE» es el `for update` de la policy de
-- RLS y el `before update on` del trigger. La migración solo CREA una tabla
-- nueva (solicitudes_pago), sus policies, triggers e índices. Cero filas tocadas.
-- ============================================================================
-- SOLICITUDES DE PAGO — 9-sep-2026 (encargo del owner: «un apartado donde los
-- comerciales nos puedan crear solicitudes de pago»)
-- Registro completo con porqués: supabase/migrations/20260909120000_solicitudes_pago.sql
-- ============================================================================

create table public.solicitudes_pago (
  id           uuid primary key default gen_random_uuid(),
  numero       bigint generated always as identity,
  client_id    uuid references public.clients(id),
  contrato_id  uuid references public.contratos(id),
  concepto     text not null,
  importe      numeric not null,
  moneda       text,
  vence_el     date,
  nota         text,
  estado       text not null default 'pendiente',
  motivo_rechazo text,
  factura_id   uuid references public.facturas(id),
  creado_por   uuid not null default auth.uid() references public.usuarios(user_id),
  creado_en    timestamptz not null default now(),
  resuelto_por uuid references public.usuarios(user_id),
  resuelto_en  timestamptz,

  constraint solicitud_concepto_no_vacio check (btrim(concepto) <> ''),
  constraint solicitud_importe_positivo  check (importe > 0),
  constraint solicitud_estado_valido
    check (estado in ('pendiente','aprobada','rechazada','anulada','cerrada')),
  constraint solicitud_con_destino check (client_id is not null or contrato_id is not null),
  constraint solicitud_moneda_un_dueno check (
    (contrato_id is not null and moneda is null) or
    (contrato_id is null and moneda in ('EUR','USD','IDR'))),
  constraint solicitud_rechazo_con_motivo
    check (estado <> 'rechazada' or btrim(coalesce(motivo_rechazo, '')) <> ''),
  constraint solicitud_cerrada_con_factura
    check (estado <> 'cerrada' or factura_id is not null)
);

comment on table public.solicitudes_pago is
  'Cola de peticiones de cobro de los comerciales hacia Administración. No emite ni cobra: para eso está Facturas. Máquina de estados en _trg_solicitud_pago_transicion.';
comment on column public.solicitudes_pago.moneda is
  'Solo cuando NO hay contrato enlazado: con contrato, la moneda se lee del contrato en vivo (el dato tiene un dueño).';

create index solicitudes_pago_estado_idx on public.solicitudes_pago(estado);
create index solicitudes_pago_creado_por_idx on public.solicitudes_pago(creado_por);

alter table public.solicitudes_pago enable row level security;

create policy "solicitudes: equipo lee lo suyo, admin todo"
  on public.solicitudes_pago for select
  using (public.es_admin() or creado_por = (select auth.uid()));

create policy "solicitudes: el equipo crea las suyas"
  on public.solicitudes_pago for insert
  with check (public.es_agente() and creado_por = (select auth.uid()));

create policy "solicitudes: admin resuelve, el creador toca la suya pendiente"
  on public.solicitudes_pago for update
  using (public.es_admin() or (creado_por = (select auth.uid()) and estado = 'pendiente'))
  with check (public.es_admin() or creado_por = (select auth.uid()));

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
  new.resuelto_por := null;
  new.resuelto_en := null;
  new.factura_id := null;
  new.motivo_rechazo := null;
  new.concepto := btrim(new.concepto);
  return new;
end
$$;

create trigger trg_solicitud_pago_alta
  before insert on public.solicitudes_pago
  for each row execute function public._trg_solicitud_pago_alta();

create or replace function public._trg_solicitud_pago_transicion()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare v_contrato_factura uuid;
begin
  new.numero := old.numero;
  new.creado_por := old.creado_por;
  new.creado_en := old.creado_en;

  if old.estado = 'pendiente' then
    if new.estado = 'pendiente' then
      new.resuelto_por := null; new.resuelto_en := null;
      new.factura_id := null; new.motivo_rechazo := null;
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
    new.client_id := old.client_id;   new.contrato_id := old.contrato_id;
    new.concepto := old.concepto;     new.importe := old.importe;
    new.moneda := old.moneda;         new.vence_el := old.vence_el;
    new.nota := old.nota;             new.factura_id := null;
    new.resuelto_por := auth.uid();
    new.resuelto_en := now();
    return new;

  elsif old.estado = 'aprobada' and new.estado = 'cerrada' then
    if not public.es_admin() then
      raise exception 'solo un administrador cierra una solicitud' using errcode = '42501';
    end if;
    if new.factura_id is null then
      raise exception 'cerrar exige la factura que la cierra' using errcode = '22023';
    end if;
    select f.contrato_id into v_contrato_factura from public.facturas f where f.id = new.factura_id;
    if old.contrato_id is not null and v_contrato_factura is distinct from old.contrato_id then
      raise exception 'esa factura es de otro contrato' using errcode = '22023';
    end if;
    new.client_id := old.client_id;   new.contrato_id := old.contrato_id;
    new.concepto := old.concepto;     new.importe := old.importe;
    new.moneda := old.moneda;         new.vence_el := old.vence_el;
    new.nota := old.nota;             new.motivo_rechazo := old.motivo_rechazo;
    new.resuelto_por := old.resuelto_por;
    new.resuelto_en := old.resuelto_en;
    return new;
  end if;

  raise exception 'una solicitud % no se puede editar', old.estado using errcode = '22023';
end
$$;

create trigger trg_solicitud_pago_transicion
  before update on public.solicitudes_pago
  for each row execute function public._trg_solicitud_pago_transicion();

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
            coalesce(v_nombre, 'Un comercial') || ' pide cobrar ' || new.concepto,
            null, new.contrato_id,
            '/intranet/solicitudes/?id=' || new.id::text);
  elsif tg_op = 'UPDATE' and new.estado is distinct from old.estado and new.estado <> 'pendiente' then
    select u.email into v_email from public.usuarios u where u.user_id = new.creado_por;
    if v_email is not null and new.estado <> 'anulada' then
      insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace)
      values ('solicitud_pago',
              'Tu solicitud SP-' || new.numero || ' — ' ||
                case new.estado when 'aprobada' then 'aprobada'
                                when 'rechazada' then 'rechazada'
                                when 'cerrada' then 'facturada y cerrada' end,
              case when new.estado = 'rechazada' then new.motivo_rechazo else new.concepto end,
              v_email, new.contrato_id,
              '/intranet/solicitudes/?id=' || new.id::text);
    end if;
  end if;
  return new;
exception when others then
  return new;
end
$$;

create trigger trg_solicitud_pago_aviso
  after insert or update on public.solicitudes_pago
  for each row execute function public._trg_solicitud_pago_aviso();;
