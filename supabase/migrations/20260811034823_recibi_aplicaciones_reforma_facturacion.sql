alter table public.facturas
  add constraint facturas_contrato_obligatorio
  check (tipo not in ('factura','recibi') or contrato_id is not null)
  not valid;

alter table public.facturas add column if not exists justificante_path text;

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
;
