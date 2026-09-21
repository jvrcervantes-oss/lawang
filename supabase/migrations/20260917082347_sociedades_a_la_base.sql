create table if not exists public.sociedades (
  clave           text primary key,
  label           text not null,
  razon           text not null,
  marca           text not null default '',
  npwp            text,
  npwp_label      text not null default 'NPWP',
  nib             text,
  domicilio       text not null,
  rep             text,
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
  'Identidad de cada sociedad emisora. Fuente unica; entities.js la lee, ya no la declara.';
comment on column public.sociedades.clave is
  'NO SE EDITA NUNCA: va dentro de cada contrato y cada factura ya emitidos.';
comment on column public.sociedades.npwp_label is
  'Etiqueta del identificador fiscal. NPWP en Indonesia, CRN en Hong Kong.';

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

create or replace function public._sociedades_autoria() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
  new.clave := old.clave;
  new.actualizado_por := auth.email();
  new.actualizado_en := now();
  return new;
end; $$;

create trigger trg_sociedades_autoria
  before update on public.sociedades
  for each row execute function public._sociedades_autoria();

alter table public.sociedades enable row level security;
alter table public.sociedades_log enable row level security;

revoke all on public.sociedades from anon, authenticated;
revoke all on public.sociedades_log from anon, authenticated;
revoke all on sequence public.sociedades_log_id_seq from anon, authenticated;

grant select on public.sociedades to authenticated;
grant select on public.sociedades_log to authenticated;

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

create policy "sociedades_log: leer solo super" on public.sociedades_log
  for select to authenticated using (public.es_super_admin());

revoke execute on function public._sociedades_log() from anon, authenticated;
revoke execute on function public._sociedades_autoria() from anon, authenticated;;
