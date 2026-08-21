create table if not exists public.borrados (
  id          uuid primary key default gen_random_uuid(),
  tabla       text        not null,
  fila_id     uuid,
  numero      text,
  fila        jsonb       not null,
  quien       text,
  borrado_en  timestamptz not null default now()
);
create index if not exists borrados_tabla_fecha on public.borrados (tabla, borrado_en desc);

alter table public.borrados enable row level security;
drop policy if exists "super admin lee borrados" on public.borrados;
create policy "super admin lee borrados" on public.borrados
  for select using (public.es_super_admin());

create or replace function public.trg_guarda_antes_de_borrar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.borrados (tabla, fila_id, numero, fila, quien)
  values (tg_table_name, old.id,
          case when to_jsonb(old) ? 'numero' then to_jsonb(old)->>'numero' end,
          to_jsonb(old), (select auth.email()));
  return old;
end $$;

drop trigger if exists trg_guarda_antes_de_borrar on public.contratos;
create trigger trg_guarda_antes_de_borrar before delete on public.contratos
  for each row execute function public.trg_guarda_antes_de_borrar();

drop trigger if exists trg_guarda_antes_de_borrar on public.facturas;
create trigger trg_guarda_antes_de_borrar before delete on public.facturas
  for each row execute function public.trg_guarda_antes_de_borrar();

create or replace function public.registra_privilegio(p_contrato uuid, p_evento text, p_detalle jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
  select p_contrato, p_evento, p_detalle, (select auth.email())
   where p_contrato is not null;
$$;
revoke all on function public.registra_privilegio(uuid, text, jsonb) from public, anon, authenticated;;
