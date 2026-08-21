create table if not exists public.modelos_villa (
  id                  uuid primary key default gen_random_uuid(),
  proyecto            text not null,
  modelo              text not null,
  precio_construccion numeric,
  moneda              text default 'EUR',
  notas               text,
  creado_en           timestamptz not null default now(),
  unique (proyecto, modelo)
);

alter table public.modelos_villa enable row level security;
drop policy if exists "modelos: leer"     on public.modelos_villa;
drop policy if exists "modelos: escribir" on public.modelos_villa;
create policy "modelos: leer" on public.modelos_villa
  for select to authenticated using (public.es_agente());
create policy "modelos: escribir" on public.modelos_villa
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

insert into public.modelos_villa (proyecto, modelo, precio_construccion, moneda)
select distinct u.proyecto, u.modelo, u.precio_construccion, coalesce(u.moneda,'EUR')
  from public.unidades u
 where u.modelo is not null and u.precio_construccion is not null
on conflict (proyecto, modelo) do nothing;;
