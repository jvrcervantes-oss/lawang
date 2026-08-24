-- Hallazgo de Seguridad (12-ago, ALTA): el NIK de un apoderado (identificador
-- nacional indonesio, dato personal sensible de un particular) vivía en
-- contracts/tokens.json — fichero público, servido sin login, igual que ya
-- pasaba con las cuentas bancarias antes del 6-ago-2026. Mismo patrón que
-- entonces (ver cuentas_bancarias): la identidad SOCIETARIA (SOCIEDADES en
-- entities.js: nombre+pasaporte de un representante legal, ya público por
-- registro mercantil) es distinta de la identidad de un PARTICULAR actuando
-- como apoderado — esta sí sale de lo público.

create table public.apoderados_hak_sewa (
  clave text primary key,        -- nombre en mayúsculas, igual que la clave del <select>
  edad text,
  ocupacion text,
  direccion text,
  nik text,
  ktp text,                      -- ruta dentro del bucket privado 'kyc', no una URL
  orden int not null default 0,
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

alter table public.apoderados_hak_sewa enable row level security;

create policy "apoderados hak sewa: solo con sesion"
  on public.apoderados_hak_sewa for select
  to authenticated
  using (true);

revoke all on public.apoderados_hak_sewa from public, anon;
grant select on public.apoderados_hak_sewa to authenticated;

-- ⚠️ LOS DATOS REALES NO VIVEN AQUI (24-ago-2026, contencion).
-- Esta migracion llevaba dentro el NIK / numero de pasaporte real de los
-- representantes, y este repo es PUBLICO por necesidad (el webhook de Hostinger
-- despliega desde el) — asi que el numero se podia leer en la URL cruda de GitHub
-- y, hasta el mismo dia, tambien en https://lawangproperties.com/... porque el
-- servidor servia los .sql. Es exactamente el dato que la propia tabla existe para
-- proteger: sirve para suplantar a la persona, y su nombre+cargo no.
-- Las filas se cargan FUERA del repo (MCP de Supabase o SQL Editor) y ya estan en
-- produccion. Aqui se queda la estructura, que es lo que hay que poder reconstruir.
