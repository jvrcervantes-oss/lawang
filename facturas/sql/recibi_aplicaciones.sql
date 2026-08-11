-- Reforma del modelo de facturación (11-ago-2026): una FACTURA es lo que se
-- debe (documento), un RECIBÍ es lo que se ha pagado de verdad. Hasta hoy
-- "cobrado" sumaba factura+recibí como si fueran lo mismo — un cliente real
-- (contratos vinculados RP00021+CC00010) acabó con balance negativo porque
-- una factura combinada de 69.000€ contaba como dinero cobrado ADEMÁS del
-- recibí real de 41.620€. Motivo del cambio, decisión del dueño:
--   · el recibí es la ÚNICA prueba de dinero recibido — la única cosa que
--     "cuenta" para el saldo.
--   · una factura exige un contrato (no se factura sin saber a qué contrato).
--   · un recibí exige referenciar la(s) factura(s) que salda, con el importe
--     exacto que aplica a cada una — un recibí puede pagar varias facturas o
--     solo parte de una (tabla puente, no una columna 1:1: el caso real que
--     originó esto era justo un recibí repartido entre dos contratos).
--   · un recibí exige adjuntar un justificante de pago (foto/PDF).

-- ---------- 1. factura/recibí exigen contrato ----------
-- NOT VALID: no revisa las filas ya existentes (hay 12 documentos de prueba,
-- sin contrato real, de antes de esta regla) — pero SÍ se aplica a cualquier
-- INSERT nuevo y a cualquier UPDATE futuro sobre esas 12 filas viejas. Quien
-- las toque tendrá que decidir su contrato en ese momento, no antes.
alter table public.facturas
  add constraint facturas_contrato_obligatorio
  check (tipo not in ('factura','recibi') or contrato_id is not null)
  not valid;

-- ---------- 2. justificante de pago (solo recibí) ----------
alter table public.facturas add column if not exists justificante_path text;

-- ---------- 3. tabla puente recibí ↔ factura ----------
create table if not exists public.recibi_aplicaciones (
  id uuid primary key default gen_random_uuid(),
  recibi_id uuid not null references public.facturas(id) on delete cascade,
  factura_id uuid not null references public.facturas(id) on delete restrict,
  importe_aplicado numeric not null check (importe_aplicado > 0),
  creado_en timestamptz not null default now(),
  creado_por text
);
create index if not exists recibi_aplicaciones_recibi_idx on public.recibi_aplicaciones(recibi_id);
create index if not exists recibi_aplicaciones_factura_idx on public.recibi_aplicaciones(factura_id);

alter table public.recibi_aplicaciones enable row level security;

create policy "agentes leen aplicaciones de sus documentos"
  on public.recibi_aplicaciones for select
  using (
    exists (select 1 from public.facturas r where r.id = recibi_id and public.es_agente() and public.es_suyo(r.creado_por))
    or exists (select 1 from public.facturas f where f.id = factura_id and public.es_agente() and public.es_suyo(f.creado_por))
  );

create policy "agentes crean aplicaciones al crear su recibi"
  on public.recibi_aplicaciones for insert
  with check (
    public.es_agente() and public.puede('facturas')
    and exists (select 1 from public.facturas r where r.id = recibi_id and r.tipo = 'recibi' and r.anulada = false and public.es_suyo(r.creado_por))
    and exists (select 1 from public.facturas f where f.id = factura_id and f.tipo = 'factura' and f.anulada = false)
  );

create policy "admin borra aplicaciones"
  on public.recibi_aplicaciones for delete
  using (public.es_admin());

revoke all on public.recibi_aplicaciones from anon;
grant select, insert on public.recibi_aplicaciones to authenticated;

comment on table public.recibi_aplicaciones is
  'Reparto de un recibí entre una o varias facturas: cuánto de este recibí salda cada factura. Un recibí sin filas aquí (documentos de antes del 11-ago-2026) sigue contando por su propio contrato_id — ver portal_situacion()/cuenta()/unidades_estado.';
