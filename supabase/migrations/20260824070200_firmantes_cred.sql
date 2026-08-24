-- destructivo-ok: sin drop de datos ni objetos ajenos.
-- ════════════════════════════════════════════════════════════════════════════
-- CREDENCIALES DE FIRMANTES FUERA DEL FICHERO PUBLICO — 24-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Mismo motivo y mismo patron que apoderados_hak_sewa (12-ago) y cuentas_bancarias
-- (6-ago): entities.js se sirve publico sin login, y el numero de documento de
-- identidad (NIK indonesio o pasaporte) de un representante societario es un
-- dato de mas riesgo que su nombre+cargo -- permite suplantacion, no solo
-- identificacion. El nombre+cargo (SOCIEDADES.<x>.rep) SI se queda publico: es
-- la misma identidad que ya imprime cada contrato/factura que el comprador
-- tiene en la mano, y "quien representa a la sociedad" es informacion publica
-- por registro mercantil. El numero de documento no.
--
-- Revision previa 24-ago-2026 (Seguridad + Legal) antes de este fichero:
--   - Seguridad: el plan original solo nombraba `cred`; `rep_npwp` es el mismo
--     nivel de exposicion y se mueve junto. Verificado que solo
--     contracts/assets/entidades_pago.js (cargado unicamente por
--     contracts/app.html, siempre autenticado) lee estos campos -- portal/ y
--     facturas/ solo leen razon/marca/logo/domicilio/npwp, nunca cred/rep_npwp,
--     asi que RLS authenticated-only no rompe el portal del comprador sin
--     contrasena.
--   - Legal: "representante societario ya es publico por registro mercantil"
--     sostiene el nombre, no el numero de documento exacto. UU PDP (NIK
--     indonesio) y RGPD (responsable establecido en la UE) aplican de forma
--     acumulativa a las dos personas, no exclusiva por nacionalidad. Base legal
--     para conservar el dato: ejecucion de contrato -- se imprime en el
--     documento que esa persona firma.
--
-- `nombre` es la clave (coincide exacto con SOCIEDADES.<x>.rep y con la clave
-- que ya usaba FIRMANTES_CRED en entities.js): desacopla "quien puede aparecer
-- firmando" de "quien es HOY el representante por defecto" -- un representante
-- retirado se queda aqui para siempre, nunca se borra, porque puede haber un
-- contrato ya firmado o en vuelo con su nombre impreso.

create table if not exists public.firmantes_cred (
  nombre     text primary key,
  rep_npwp   text not null default '',
  cred_es    text not null,
  cred_en    text not null,
  cred_id    text not null,
  creado_en  timestamptz not null default now()
);

alter table public.firmantes_cred enable row level security;

drop policy if exists "firmantes cred: solo con sesion" on public.firmantes_cred;
create policy "firmantes cred: solo con sesion"
  on public.firmantes_cred for select
  to authenticated
  using (true);

insert into public.firmantes_cred (nombre, rep_npwp, cred_es, cred_en, cred_id) values
  ('I Wayan Eka Aryawan', '',
   'de nacionalidad Indonesia, con documento de identidad indonesio ID 5102010606870001',
   'Indonesian nationality, holder of Indonesian identity document ID 5102010606870001',
   'berkewarganegaraan Indonesia, dengan dokumen identitas Indonesia ID 5102010606870001'),
  ('Pablo Cantero Gambín', '',
   'de nacionalidad española, con pasaporte español nº PAL648254',
   'Spanish nationality, holder of Spanish passport no. PAL648254',
   'berkewarganegaraan Spanyol, dengan paspor Spanyol no. PAL648254'),
  ('I Made Monjong Adhi Nugruah', '',
   'de nacionalidad Indonesia, con documento de identidad indonesio ID 5171021704720002',
   'Indonesian nationality, holder of Indonesian identity document ID 5171021704720002',
   'berkewarganegaraan Indonesia, dengan dokumen identitas Indonesia ID 5171021704720002')
on conflict (nombre) do nothing;;
