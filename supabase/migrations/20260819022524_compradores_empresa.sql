alter table public.clients
  add column if not exists tipo            text not null default 'persona',
  add column if not exists forma_juridica  text,
  add column if not exists registro_num    text,
  add column if not exists rep_nombre      text,
  add column if not exists rep_cargo       text;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.clients'::regclass and conname = 'clients_tipo_check') then
    alter table public.clients
      add constraint clients_tipo_check check (tipo in ('persona','empresa'));
  end if;
end $$;

comment on column public.clients.tipo is
  'persona | empresa. En una empresa: full_name = razon social, passport_number = identificacion fiscal (NIF/CIF/NPWP/EIN), nationality = pais de constitucion, address = domicilio social.';
comment on column public.clients.forma_juridica is 'S.L., LLC, PT PMA, GmbH... texto libre: el comprador puede ser de cualquier pais';
comment on column public.clients.registro_num  is 'No de registro mercantil, NIB/OSS en Indonesia, state file number en EE.UU.';

alter table public.clients drop constraint if exists clients_email_key;
create unique index if not exists clients_email_tipo_key
  on public.clients (lower(email), tipo) where email is not null;;
