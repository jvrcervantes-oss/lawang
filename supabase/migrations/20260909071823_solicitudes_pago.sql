-- destructivo-ok: falso positivo del guardrail — aquí no hay ningún UPDATE de
-- datos; lo que casa con «UPDATE sin WHERE» es el `for update` de la policy de
-- RLS y el `before update on` del trigger. Solo CREA objetos. Cero filas tocadas.
-- ============================================================================
-- SOLICITUDES DE PAGO — 9-sep-2026 (encargo del owner: «un apartado donde los
-- comerciales nos puedan crear solicitudes de pago»)
-- ----------------------------------------------------------------------------
-- La cola de entrada de Administración: el comercial (rol agente) pide que se
-- cobre/emita algo — comprador y/o contrato, concepto e importe — y el admin
-- resuelve. La solicitud NO emite ni cobra nada sola: el dinero real sigue
-- pasando únicamente por Facturas con sus guardarraíles. Herramienta:
-- /intranet/solicitudes/.
--
-- Diseño pasado por revisión previa (Seguridad + Datos + Administración,
-- 9-sep-2026) y esto es lo que cambió respecto al primer plan:
--   · La máquina de estados vive AQUÍ, no en la app: un trigger BEFORE UPDATE
--     compara old/new (cosa que una policy WITH CHECK no puede) y las policies
--     de RLS solo reparten el acceso por fila. Sin esto, una llamada REST con
--     la publishable key podía reabrir una solicitud resuelta.
--   · resuelto_por / resuelto_en los SELLA el trigger con auth.uid()/now();
--     lo que mande el cliente en esas columnas se ignora.
--   · La moneda tiene UN dueño: con contrato enlazado se lee del contrato en
--     vivo (no se persiste aquí); solo una solicitud sin contrato lleva moneda
--     propia. El CHECK de abajo hace las dos cosas obligatorias y excluyentes.
--   · aprobada ≠ facturada: existe el estado terminal 'cerrada', que exige
--     factura_id y solo se alcanza desde 'aprobada' (hallazgo de
--     Administración: sin él se acumulan aprobadas que nadie factura nunca).
--
-- DESCARTES, por escrito (norma de la revisión previa):
--   · Sin serie de numeración tipo contratos (set_contrato_numero): esto no es
--     un documento que salga hacia un tercero, es una cola interna. Un identity
--     basta para nombrarla (SP-n) y no toca los cuatro sitios de LAW-48.
--   · El importe no se ata por FK a un hito de contrato_vencimientos: la
--     solicitud es una PETICIÓN (señales, reservas, conceptos sueltos), no un
--     apunte contable, y esta tabla no se agrega en ninguna vista de cartera o
--     caja — no crea segunda fuente de dinero. La fuente del dinero contractual
--     sigue siendo Vencimientos.
-- ============================================================================

create table public.solicitudes_pago (
  id           uuid primary key default gen_random_uuid(),
  -- solo para nombrarla en pantalla y en la campana: «SP-7»
  numero       bigint generated always as identity,
  client_id    uuid references public.clients(id),
  contrato_id  uuid references public.contratos(id),
  concepto     text not null,
  -- numeric, no text: dinero_no_es_texto.sql (19-ago). El cliente parsea lo
  -- tecleado con lwParseImporte ANTES de mandarlo.
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
  -- a quién se le cobra: comprador, contrato, o los dos — pero nunca ninguno
  constraint solicitud_con_destino check (client_id is not null or contrato_id is not null),
  -- la moneda tiene UN dueño: la del contrato manda cuando lo hay
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

-- ── RLS: reparto de ACCESO por fila. Las transiciones NO viven aquí (una
--    policy no ve old y new a la vez): viven en el trigger de abajo. ─────────
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

-- sin policy de DELETE: una solicitud no se borra, se anula o se rechaza
-- (el rastro es el punto). anon y portal: sin policies = sin acceso.

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

-- ── La máquina de estados, entera y en un solo sitio ────────────────────────
--    pendiente → aprobada | rechazada   (solo admin; el trigger sella quién y cuándo)
--    pendiente → anulada                (solo el creador; también deja sello)
--    pendiente → pendiente              (el creador corrige su petición)
--    aprobada  → cerrada                (solo admin, exige factura_id; congela el resto)
--    todo lo demás → error con el motivo dicho con todas las letras
create or replace function public._trg_solicitud_pago_transicion()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare v_contrato_factura uuid;
begin
  -- columnas de identidad y autoría: inmutables siempre
  new.numero := old.numero;
  new.creado_por := old.creado_por;
  new.creado_en := old.creado_en;

  if old.estado = 'pendiente' then
    if new.estado = 'pendiente' then
      -- corrección del creador: los sellos de resolución no se tocan
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
    -- al resolver, lo pedido queda congelado tal cual se pidió
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
    -- si los dos tienen contrato, tiene que ser el mismo: enlazar la factura
    -- de otro contrato es exactamente el cruce que esta columna viene a evitar
    select f.contrato_id into v_contrato_factura from public.facturas f where f.id = new.factura_id;
    if old.contrato_id is not null and v_contrato_factura is distinct from old.contrato_id then
      raise exception 'esa factura es de otro contrato' using errcode = '22023';
    end if;
    -- todo lo demás, congelado como quedó al aprobar
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

-- ── Campana: HECHOS al canal existente (notificaciones.sql, 4-ago) ──────────
--    Al crear → destinatario null (= solo administradores). Al resolver → el
--    email del creador, el MISMO criterio de reparto que ya usa el canal.
--    El fallo del aviso nunca deshace la escritura que lo disparó (patrón de
--    _trg_hilo_soporte_actividad). El texto lo pinta topbar.js con esc().
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
    -- al creador no se le avisa de lo que hizo él mismo (anular la suya)
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
  return new;   -- la solicitud ya se guardó; un fallo del aviso no la deshace
end
$$;

create trigger trg_solicitud_pago_aviso
  after insert or update on public.solicitudes_pago
  for each row execute function public._trg_solicitud_pago_aviso();
