-- Lawang · facturas — tabla, numeración y RLS
-- 27-jul-2026
--
-- Ejecutar UNA vez en Supabase → proyecto Lawang clientes/pagos → SQL Editor.
-- (El MCP de esta máquina está en modo solo lectura, por eso va a mano.)
--
-- Mismo patrón que public.contratos: el número lo pone un trigger desde una
-- secuencia (nunca el navegador, que no puede garantizar unicidad), y las
-- policies exigen el claim `agente` en app_metadata — estar autenticado no
-- basta, el registro de Supabase Auth está abierto (ver contracts/sql/rls_claim_agente.sql).

create table if not exists public.facturas (
  id uuid primary key default gen_random_uuid(),
  numero text unique,
  sociedad text,
  cliente_nombre text,
  proyecto_nombre text,
  contrato_numero text,
  total numeric,
  moneda text,
  fecha_emision date,
  datos jsonb not null default '{}'::jsonb,
  anulada boolean not null default false,
  created_at timestamptz not null default now(),
  creado_por text default auth.email()
);

comment on table public.facturas is
  'Facturas generadas por proyectos/Lawang/facturas (index.html). El numero lo asigna el trigger, formato INV00001.';
comment on column public.facturas.anulada is
  'Una factura emitida no se borra: se marca anulada y se emite otra. El numero gastado no se reutiliza.';

create sequence if not exists public.facturas_seq;

create or replace function public.set_factura_numero()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if new.numero is null then
    new.numero := 'INV' || lpad(nextval('public.facturas_seq')::text, 5, '0');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_factura_numero on public.facturas;
create trigger trg_set_factura_numero
  before insert on public.facturas
  for each row execute function public.set_factura_numero();

alter table public.facturas enable row level security;

create policy "agentes autenticados leen facturas"
  on public.facturas for select to authenticated
  using (public.es_agente());

create policy "agentes autenticados insertan facturas"
  on public.facturas for insert to authenticated
  with check (public.es_agente());

-- Una factura anulada queda congelada: se corrige emitiendo otra.
create policy "agentes autenticados actualizan facturas no anuladas"
  on public.facturas for update to authenticated
  using (anulada = false and public.es_agente())
  with check (public.es_agente());
