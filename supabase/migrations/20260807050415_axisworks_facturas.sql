-- Facturas de AxisWorks (el estudio, no Lawang). Tabla propia y NO la `facturas` que ya
-- existe: esa es de proyectos/Lawang/facturas (comprador↔contrato). El prefijo `axisworks_`
-- avisa a quien audite este esquema de que esta tabla no es de Lawang, igual que
-- `axisworks_cuentas`.
create table public.axisworks_facturas (
  id bigint generated always as identity primary key,
  numero text unique,
  fecha date not null,
  cliente jsonb not null,
  conceptos jsonb not null,
  moneda text not null,
  banco_id text,
  notas text not null default '',
  total bigint not null,
  anulada boolean not null default false,
  created_at timestamptz not null default now()
);
comment on table public.axisworks_facturas is
  'Facturas del propio estudio AxisWorks a sus clientes. Numero asignado por trigger '
  '(formato FAC00001), nunca por el navegador. Emitida = fila creada; una factura se '
  'anula, no se borra, para no dejar huecos en la numeracion.';

create sequence public.axisworks_facturas_seq start 1;

create or replace function public.axisworks_set_factura_numero()
returns trigger language plpgsql as $$
begin
  if new.numero is null then
    new.numero := 'FAC' || lpad(nextval('public.axisworks_facturas_seq')::text, 5, '0');
  end if;
  return new;
end;
$$;

create trigger trg_axisworks_factura_numero
before insert on public.axisworks_facturas
for each row execute function public.axisworks_set_factura_numero();

-- RLS encendida y SIN policies: igual que axisworks_cuentas, solo entra la service_role
-- que ya tiene panel-web. Ni anon ni authenticated ven una factura del estudio.
alter table public.axisworks_facturas enable row level security;
;
