-- ============================================================================
-- SOCIEDADES EMISORAS — de `contracts/assets/entities.js` a la base
--
-- POR QUE. Hasta hoy la identidad de cada sociedad emisora (razon social, NPWP,
-- domicilio, logo, tinta del documento) vivia en un `const SOCIEDADES` dentro de
-- un fichero del repo que se sirve publico y sin login. Eso rompe la norma de la
-- suite «si el cliente lo puede dar de alta —o cambiar de opinion sobre el— no
-- puede vivir en un fichero» (contexto/suite_lawang.md), y con una segunda
-- empresa dentro de la intranet deja de aguantar: cada alta seria un commit.
--
-- QUE NO HACE ESTA MIGRACION, a proposito:
--   · NO toca ni un numero de documento. El owner decidio el 17-sep-2026 NO
--     separar todavia las series por sociedad (LAW-235): las tres secuencias
--     globales siguen exactamente como estan. Separarlas exige antes que un
--     contable indonesio diga si la normativa obliga a reinicio anual o a un
--     formato concreto de serie para una PT.
--   · NO escribe una sola fila de `facturas`. Esa tabla tiene cinco triggers de
--     fila y dos se tragan los errores (`exception when others then raise
--     warning`), asi que un UPDATE masivo devengaria o dejaria de devengar
--     comision del 0,5% sin que nadie se entere. Los 412 documentos ya emitidos
--     se quedan como historico documentado, decision del owner del 17-sep.
--
-- LA CLAVE NO SE EDITA NUNCA. `clave` va guardada dentro de cada contrato
-- (`datos->'fields'->>'sociedad_firmante'`) y de cada factura (`sociedad`), y
-- las plantillas la miran literalmente en `<!--if:sociedad_firmante=tepi_sungai-->`.
-- Por eso es la primary key y por eso el GRANT de UPDATE la deja fuera: no basta
-- con no ofrecerla en un formulario.
-- ============================================================================

create table if not exists public.sociedades (
  clave           text primary key,
  label           text not null,          -- lo que se lee en el desplegable
  razon           text not null,          -- razon social inscrita: lo que se IMPRIME
  marca           text not null default '',
  -- Identificacion fiscal. `npwp_label` existe porque no todas son indonesias:
  -- SANDAL WOODS Ltd es de Hong Kong y su identificador es un CRN. Sin este
  -- campo el documento imprimia «NPWP 79887714», una etiqueta falsa.
  npwp            text,
  npwp_label      text not null default 'NPWP',
  nib             text,
  domicilio       text not null,
  rep             text,                   -- solo el NOMBRE; ya consta en el registro mercantil
  -- Aspecto del documento cuando emite esta sociedad. Es cosmetico: se puede
  -- cambiar sin que cambie lo que el documento DICE.
  logo            text,
  logo_alto       text,
  emisor_debajo   boolean not null default false,
  folio           text,
  tinta           jsonb,
  activa          boolean not null default true,
  orden           integer not null default 0,
  creado_en       timestamptz not null default now(),
  actualizado_por text,
  actualizado_en  timestamptz
);

comment on table public.sociedades is
  'Identidad de cada sociedad emisora. Fuente unica; `entities.js` la lee, ya no la declara.';
comment on column public.sociedades.clave is
  'NO SE EDITA NUNCA: va dentro de cada contrato y cada factura ya emitidos.';
comment on column public.sociedades.npwp_label is
  'Etiqueta del identificador fiscal. NPWP en Indonesia, CRN en Hong Kong.';

-- ---------------------------------------------------------------------------
-- Semilla: las TRES que declara hoy `entities.js`, no dos.
-- `sandal_woods_ltd` tiene cero documentos emitidos pero SI es seleccionable en
-- el desplegable de sociedad firmante, asi que dejarla fuera rompe el primer
-- INSERT que la use en cuanto exista la clave ajena.
-- Valores copiados literalmente del fichero; no se corrige nada aqui.
-- ---------------------------------------------------------------------------
insert into public.sociedades
  (clave, label, razon, marca, npwp, npwp_label, nib, domicilio, rep,
   logo, logo_alto, emisor_debajo, folio, tinta, orden)
values
  ('tepi_sungai',
   'PT Tepi Sun Gai (marca «Lawang Tropical Properties»)',
   'PT TEPI SUN GAI', 'LAWANG TROPICAL PROPERTIES',
   '1000.0000.0619.8026', 'NPWP', '2410250046282',
   'Jalan Gunung Tangkuban Perahu, Gg. Dewi Sri Dusun Tegal Buah RT. 000 RW. 000, Padangsambian Kelod, Denpasar Barat, Kota Denpasar, Bali 80117 Indonesia',
   'I Wayan Eka Aryawan',
   '/contracts/assets/brand/lawang-logo-v3-dark.png', '14mm', true, '#E6EFE0',
   '{"primary":"#485B37","deep":"#104C4F"}'::jsonb, 1),
  ('san_dal_woods',
   'PT SAN DAL WOODS',
   'PT SAN DAL WOODS', '',
   '1000.0000.0012.5018', 'NPWP', null,
   'Jl. Sunset Road No. 89, Pertokoan Sunset Indah I, No. 3B RT. 000 RW. 000, Kuta, Kuta, Kab. Badung, Bali',
   'Pablo Cantero Gambín',
   '/contracts/assets/brand/sandalwoods-lockup.png', '24mm', false, '#E7E3D2',
   '{"primary":"#662906","deep":"#42210B"}'::jsonb, 2),
  ('sandal_woods_ltd',
   'SANDAL WOODS Ltd (Hong Kong)',
   'SANDAL WOODS Ltd', '',
   '79887714', 'CRN', '',
   'Suite D, 6/F Ho Lee Comm Bldg, 38-44 D''Aguilar St, Central, Hong Kong',
   'Pablo Cantero Gambín',
   '/contracts/assets/brand/sandalwoods-lockup.png', '24mm', false, '#E7E3D2',
   '{"primary":"#662906","deep":"#42210B"}'::jsonb, 3)
on conflict (clave) do nothing;

-- Sin `drop ... if exists` en toda la migracion: la tabla NACE aqui, asi que no
-- hay nada previo que tirar y el guardrail `no_destruir.py` no tiene que mirar
-- para otro lado. Si algun dia hay que reaplicarla, se reaplica sobre limpio.
-- ---------------------------------------------------------------------------
-- Rastro de los cambios de identidad fiscal.
-- Mismo patron que `comision_admin_tarifas_log`: guarda la fila ANTERIOR antes
-- de pisarla. Hoy cambiar un NPWP exige commit y deploy, y queda en git; en
-- cuanto sea editable desde un panel, un UPDATE no dejaria ningun rastro.
-- ---------------------------------------------------------------------------
create table if not exists public.sociedades_log (
  id          bigserial primary key,
  clave       text not null,
  antes       jsonb not null,
  accion      text not null check (accion in ('update','delete')),
  quien       text default auth.email(),
  cuando      timestamptz not null default now()
);

create or replace function public._sociedades_log() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
  insert into public.sociedades_log (clave, antes, accion)
  values (old.clave, to_jsonb(old), lower(tg_op));
  return case when tg_op = 'DELETE' then old else new end;
end; $$;

create trigger trg_sociedades_log
  before update or delete on public.sociedades
  for each row execute function public._sociedades_log();

-- `actualizado_por`/`actualizado_en` los pone la base, no el navegador: si los
-- escribe el cliente, el rastro dice lo que el cliente quiera que diga.
create or replace function public._sociedades_autoria() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
  new.clave := old.clave;            -- blindaje extra: la clave no se mueve
  new.actualizado_por := auth.email();
  new.actualizado_en := now();
  return new;
end; $$;

create trigger trg_sociedades_autoria
  before update on public.sociedades
  for each row execute function public._sociedades_autoria();

-- ---------------------------------------------------------------------------
-- PERMISOS. El GRANT manda antes que la policy — regla ya pagada en este
-- proyecto. Una relacion nueva NACE con GRANT completo para `anon` por el
-- default ACL del owner (verificado en pg_default_acl el 17-sep-2026: `anon`
-- obtiene arwdDxtm), asi que revocar no es higiene: es la mitad del candado.
-- ---------------------------------------------------------------------------
alter table public.sociedades enable row level security;
alter table public.sociedades_log enable row level security;

revoke all on public.sociedades from anon, authenticated;
revoke all on public.sociedades_log from anon, authenticated;
revoke all on sequence public.sociedades_log_id_seq from anon, authenticated;

-- Lectura: todo el equipo. Es lo que ya va impreso en cada documento que el
-- comprador tiene en la mano, y la suite entera necesita pintarla.
-- ⚠️ `anon` NO. Hoy el argumento para dejarla publica era «ya va impresa»; en
-- cuanto entre un operador externo, esta tabla pasa a ser el censo de clientes
-- del estudio (quien opera que, con marca y estado) y no puede servirse sin
-- sesion. Se cierra ahora para no tener que acordarse despues.
grant select on public.sociedades to authenticated;
grant select on public.sociedades_log to authenticated;

-- Escritura: solo super admin, igual que `cuentas_bancarias`. Una cuenta decide
-- adonde va el dinero futuro; una sociedad decide quien emitio el documento.
-- `clave` queda FUERA del grant de UPDATE a proposito (ver cabecera).
grant insert on public.sociedades to authenticated;
grant update (label, razon, marca, npwp, npwp_label, nib, domicilio, rep,
              logo, logo_alto, emisor_debajo, folio, tinta, activa, orden)
  on public.sociedades to authenticated;

create policy "sociedades: leer" on public.sociedades
  for select to authenticated using (true);

create policy "sociedades: alta solo super" on public.sociedades
  for insert to authenticated with check (public.es_super_admin());

create policy "sociedades: edita solo super" on public.sociedades
  for update to authenticated
  using (public.es_super_admin()) with check (public.es_super_admin());

-- Sin policy de DELETE: una sociedad no se borra, se desactiva. Borrarla
-- dejaria a sus documentos emitidos apuntando a una clave que no existe.

create policy "sociedades_log: leer solo super" on public.sociedades_log
  for select to authenticated using (public.es_super_admin());

-- Una funcion DEFINER nace ejecutable por `anon`/`authenticated` pese al default
-- ACL corregido (deuda §7 de contexto/seguridad_2026.md, 16-sep-2026). Se revoca
-- explicitamente y se verifica despues en information_schema.routine_privileges.
revoke execute on function public._sociedades_log() from anon, authenticated;
revoke execute on function public._sociedades_autoria() from anon, authenticated;
