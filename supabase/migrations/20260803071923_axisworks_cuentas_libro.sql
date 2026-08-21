-- Libro de cuentas del PROPIO estudio (que debe cada cliente a AxisWorks).
-- Vive en este proyecto Supabase, que es del estudio, porque el panel ya tiene aqui
-- su clave y su respaldo automatico: montar otro sitio solo para esto habria sido
-- una credencial mas y una copia de seguridad menos. El prefijo `axisworks_` es para
-- que quien audite este esquema vea de un vistazo que esta fila no es de Lawang.
--
-- Una sola fila con el documento entero en jsonb: lo escribe y lo lee un unico
-- usuario desde una unica pagina, y con tablas normalizadas cada campo nuevo del
-- formulario pediria migracion. Si algun dia hay que consultar por cliente o por
-- trimestre desde SQL, entonces si toca normalizar.
create table if not exists public.axisworks_cuentas (
  id smallint primary key default 1 check (id = 1),
  doc jsonb not null default '{"empresas":[],"conceptos":[],"cargos":[]}'::jsonb,
  updated_at timestamptz not null default now()
);

-- RLS encendida y SIN policies a proposito: esto son las finanzas del estudio.
-- Sin policy, ni anon ni authenticated ven nada; solo entra la service_role que usa
-- el servidor del panel, detras de PANEL_PASSWORD.
alter table public.axisworks_cuentas enable row level security;

insert into public.axisworks_cuentas (id) values (1) on conflict (id) do nothing;;
