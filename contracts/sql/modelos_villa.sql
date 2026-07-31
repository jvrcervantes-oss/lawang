-- ============================================================================
-- Catálogo de modelos de villa por proyecto — 31-jul-2026
-- ----------------------------------------------------------------------------
-- Petición del cliente: en Palm Field se puede construir CUALQUIERA de las dos
-- viviendas (Dream o Dune) en CUALQUIER parcela. Hasta ahora el modelo venía
-- pegado a la parcela porque así llegó la tabla de precios, y eso convertía una
-- decisión comercial —qué casa quiere el comprador— en un dato del inventario.
--
-- Lo que de verdad es de la PARCELA: su superficie y su precio de suelo
-- (125 €/m² en Palm Field, verificado sobre las 32).
-- Lo que es del MODELO: lo que cuesta construirlo (Dune 64.000, Dream 94.000).
-- El total es la suma, y cambia si el comprador cambia de casa.
--
-- El catálogo va en su tabla y no derivado de `unidades` porque, si un día todas
-- las parcelas quedaran asignadas a Dream, el precio de Dune desaparecería del
-- sistema sin que nadie lo hubiera dado de baja.
-- ============================================================================

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
drop policy if exists "modelos: leer"    on public.modelos_villa;
drop policy if exists "modelos: escribir" on public.modelos_villa;
create policy "modelos: leer" on public.modelos_villa
  for select to authenticated using (public.es_agente());
-- Cambiar lo que cuesta construir es una decisión de precio: administradores.
create policy "modelos: escribir" on public.modelos_villa
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

-- Semilla desde lo que ya está en el inventario: es el dato real del cliente,
-- no una cifra inventada.
insert into public.modelos_villa (proyecto, modelo, precio_construccion, moneda)
select distinct u.proyecto, u.modelo, u.precio_construccion, coalesce(u.moneda,'EUR')
  from public.unidades u
 where u.modelo is not null and u.precio_construccion is not null
on conflict (proyecto, modelo) do nothing;
