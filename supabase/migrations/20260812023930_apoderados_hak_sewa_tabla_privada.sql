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

insert into public.apoderados_hak_sewa (clave, edad, ocupacion, direccion, nik, ktp, orden) values
  ('I WAYAN EKA ARYAWAN', '39', 'Private Employee', 'Banjar Dinas Payan, Antap Village, Selemadeg District, Tabanan Regency.', '5102010606870001', 'apoderados/i-wayan-eka-aryawan-ktp.jpg', 1),
  ('NI LUH GEDE DIAH SURASTRI', null, null, null, '5108014707010003', null, 2);;
