-- Vencimientos de Construccion por avance de obra: esquema base.
-- encargos/20260917_lawang_vencimientos_obra.md

-- 1) Estado del proyecto (Proceso de venta -> En construccion -> Entregado).
--    El cambio de estado real se hace via una funcion aparte (con confirmacion),
--    esta columna solo declara el valor.
alter table public.proyectos
  add column estado text not null default 'proceso_venta'
    check (estado in ('proceso_venta', 'construccion', 'entregado'));

-- 2) Mapeo de los 7 pasos reales de obra a los 5 pagos de Construccion
--    (decision del owner 17-sep: "los pasos de obra quedan en los 5 pagos, son los mismos").
--    Por orden numerico, nunca por texto (hitosDefaults.ppjb_construccion no tiene clave estable).
create table public.obra_fase_orden_pago (
  obra_fase_clave text primary key references public.obra_fases(clave),
  orden_pago int not null check (orden_pago between 1 and 5)
);

insert into public.obra_fase_orden_pago (obra_fase_clave, orden_pago) values
  ('preparacion', 1),
  ('cimentacion', 1),
  ('estructura', 2),
  ('cubierta', 2),
  ('instalaciones', 3),
  ('acabados', 4),
  ('entregada', 5);

alter table public.obra_fase_orden_pago enable row level security;
revoke all on public.obra_fase_orden_pago from public, anon;
grant select on public.obra_fase_orden_pago to authenticated;
create policy obra_fase_orden_pago_select on public.obra_fase_orden_pago
  for select using (es_agente());

-- 3) Progreso de obra por fase-zona del masterplan (decision owner: granularidad = fase-zona,
--    no parcela ni proyecto entero). Una fila por cubo (proyecto, fase_masterplan, zona_masterplan).
create table public.obra_progreso_fase_zona (
  id uuid primary key default gen_random_uuid(),
  proyecto_id uuid not null references public.proyectos(id),
  fase_masterplan text not null,
  zona_masterplan text not null,
  obra_fase_actual text not null references public.obra_fases(clave),
  actualizado_en timestamptz not null default now(),
  actualizado_por text,
  unique (proyecto_id, fase_masterplan, zona_masterplan)
);

alter table public.obra_progreso_fase_zona enable row level security;
revoke all on public.obra_progreso_fase_zona from public, anon;
grant select on public.obra_progreso_fase_zona to authenticated;
create policy obra_progreso_fase_zona_select on public.obra_progreso_fase_zona
  for select using (es_agente() and puede('obra'));
-- Sin policy de insert/update para "authenticated": solo escribe la funcion
-- SECURITY DEFINER de avance (dueña postgres, bypassa RLS como ya hace sincroniza_vencimientos()).

-- 4) Partes de trabajo: bitacora de cada avance (quien, cuando, de que fase a que fase).
--    Es el disparador del vencimiento, el historico y la base del futuro aviso al comprador.
create table public.obra_partes_trabajo (
  id uuid primary key default gen_random_uuid(),
  proyecto_id uuid not null references public.proyectos(id),
  fase_masterplan text not null,
  zona_masterplan text not null,
  fase_anterior text references public.obra_fases(clave),
  fase_nueva text not null references public.obra_fases(clave),
  fecha date not null default current_date,
  autor text,
  nota text,
  creado_en timestamptz not null default now()
);

alter table public.obra_partes_trabajo enable row level security;
revoke all on public.obra_partes_trabajo from public, anon;
grant select on public.obra_partes_trabajo to authenticated;
create policy obra_partes_trabajo_select on public.obra_partes_trabajo
  for select using (es_agente() and puede('obra'));

-- 5) Procedencia del vencimiento: distingue una fecha fijada por el mecanismo de obra
--    de una tocada a mano (independiente de `ajustado`, que protege de sincroniza_vencimientos()).
alter table public.contrato_vencimientos
  add column origen text not null default 'manual'
    check (origen in ('manual', 'obra'));

comment on column public.contrato_vencimientos.origen is
  'manual = tecleado o calculado al firmar; obra = fijado por el avance de obra (obra_partes_trabajo). No confundir con `ajustado` (protege de sincroniza_vencimientos()).';
comment on table public.obra_progreso_fase_zona is
  'Fase de obra actual por cubo (proyecto, fase_masterplan, zona_masterplan). Solo la escribe la funcion SECURITY DEFINER de avance, nunca INSERT/UPDATE directo.';
comment on table public.obra_partes_trabajo is
  'Bitacora de cada avance de fase-zona: quien, cuando, de que fase a que fase. Encargo: encargos/20260917_lawang_vencimientos_obra.md';
