-- Tabla de contratos generados por la app contracts/ (Lawang), independiente
-- del CRM clients/reservations/payments existente (0 filas, sin integrar con
-- la app hoy). Numeración automática por tipo: RP00001... / CC00001...
-- Guarda todo el payload del formulario (comprador, hitos, cláusulas, diseño...)
-- en `datos` jsonb, más unas columnas planas para poder filtrar/listar rápido.

create sequence if not exists public.contratos_rp_seq start 1;
create sequence if not exists public.contratos_cc_seq start 1;

create table public.contratos (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('reserva_parcela','construccion')),
  numero text unique,
  comprador_nombre text,
  proyecto_nombre text,
  precio_total numeric,
  moneda text,
  fecha_firma date,
  datos jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index contratos_tipo_idx on public.contratos (tipo);
create index contratos_created_at_idx on public.contratos (created_at desc);

comment on table public.contratos is 'Contratos generados por proyectos/Lawang/contracts (app.html). Independiente del CRM clients/reservations.';
comment on column public.contratos.numero is 'Autogenerado por trigger si se deja NULL: RPXXXXX (reserva_parcela) / CCXXXXX (construccion). Se puede fijar a mano al insertar si hace falta.';
comment on column public.contratos.datos is 'Payload completo del formulario: collect() + HITOS[] + clausulas adicionales + estado de diseno/anexos.';

create or replace function public.set_contrato_numero()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  n bigint;
  prefix text;
begin
  if new.numero is not null then
    return new;
  end if;
  if new.tipo = 'reserva_parcela' then
    prefix := 'RP';
    n := nextval('public.contratos_rp_seq');
  elsif new.tipo = 'construccion' then
    prefix := 'CC';
    n := nextval('public.contratos_cc_seq');
  else
    raise exception 'Tipo de contrato sin numeracion definida: %', new.tipo;
  end if;
  new.numero := prefix || lpad(n::text, 5, '0');
  return new;
end;
$$;

create trigger trg_set_contrato_numero
before insert on public.contratos
for each row execute function public.set_contrato_numero();

-- RLS activado por consistencia con el resto del proyecto (clients/reservations/
-- payments/documents ya lo tienen); sin políticas todavía porque la app no está
-- conectada — se definen cuando se cablee el guardado real.
alter table public.contratos enable row level security;;
