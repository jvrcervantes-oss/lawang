-- 1. Clientes (compradores) — datos KYC básicos
create table clients (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text not null unique,
  phone text,
  nationality text,
  passport_number text,
  date_of_birth date,
  address text,
  kyc_status text not null default 'pending'
    check (kyc_status in ('pending','submitted','verified','rejected')),
  notes text,
  created_at timestamptz not null default now()
);

-- 2. Reservas/contratos — vincula cliente a una propiedad del catálogo (data.json)
create table reservations (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete restrict,
  property_slug text not null,       -- coincide con id en PROPERTIES de data.json
  property_title text,               -- snapshot al reservar (el catálogo puede cambiar)
  property_line text,                -- signature/land/villa/resorts
  price_eur numeric(12,2),
  contract_type text
    check (contract_type in ('reserva','parcela')),  -- ppjb_reserva.html vs ppjb_parcela.html
  status text not null default 'reserved'
    check (status in ('reserved','ppjb_signed','completed','cancelled')),
  reserved_at timestamptz not null default now(),
  notes text
);

-- 3. Pagos — plan de pagos + pagos recibidos (una fila = una cuota)
create table payments (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references reservations(id) on delete cascade,
  amount numeric(12,2) not null,
  currency text not null default 'EUR',
  due_date date,
  paid_at timestamptz,
  status text not null default 'pending'
    check (status in ('pending','paid','overdue','cancelled')),
  method text,        -- wire transfer, Stripe, etc.
  reference text,      -- referencia bancaria / id de Stripe
  created_at timestamptz not null default now()
);

-- 4. Documentos — KYC y contratos firmados (el archivo vive en Supabase Storage, esto solo indexa)
create table documents (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  reservation_id uuid references reservations(id) on delete set null,  -- null = doc de cliente (pasaporte), no de un deal concreto
  doc_type text not null
    check (doc_type in ('passport','proof_of_address','signed_contract','other')),
  storage_path text not null,
  status text not null default 'pending'
    check (status in ('pending','verified','rejected')),
  uploaded_at timestamptz not null default now()
);

-- RLS: contiene PII/KYC real → cerrado por defecto, sin políticas todavía.
alter table clients enable row level security;
alter table reservations enable row level security;
alter table payments enable row level security;
alter table documents enable row level security;
;
