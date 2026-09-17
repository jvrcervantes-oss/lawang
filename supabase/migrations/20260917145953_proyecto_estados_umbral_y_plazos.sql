-- destructivo-ok: el unico DROP es proyectos_estado_check, sustituido por otro CHECK en la misma
-- migracion para ampliar de 3 estados a 8 (mismo patron que estado_unidad_por_tipo_y_cobro el
-- 12-ago). El UPDATE lleva WHERE explicito y es un remapeo 1:1 de nombres: verificado antes de
-- aplicarlo que los 29 proyectos estan TODOS en 'proceso_venta', el valor por defecto creado hoy
-- mismo (20260917091621), asi que ninguna fila pierde informacion ni hay dato que respaldar --
-- nadie ha elegido un estado todavia. Decisiones del owner del 17-sep.
--
--   · 8 estados: en_venta, no_disponible, en_construccion, construido, finalizado,
--     gestionado, stand_by, cedido. "gestionado" y "management" eran el mismo concepto en dos
--     idiomas -- se queda uno. "construido" = obra terminada sin entregar; "finalizado" =
--     entregado y cerrado.
--   · solo `en_construccion` dispara vencimientos (el candado de obra_confirmar_avance).
--   · umbral de venta para poder iniciar: bloquea, pero un admin puede forzarlo dejando
--     constancia de quien y por que. Configurable por proyecto, 33% por defecto.
--   · los plazos en dias son por proyecto Y por pago (5), no uno global.

-- 1) Estados nuevos.
alter table public.proyectos drop constraint proyectos_estado_check;

update public.proyectos set estado = case estado
    when 'proceso_venta' then 'en_venta'
    when 'construccion'  then 'en_construccion'
    when 'entregado'     then 'finalizado'
    else estado end
 where estado in ('proceso_venta', 'construccion', 'entregado');

alter table public.proyectos alter column estado set default 'en_venta';

alter table public.proyectos add constraint proyectos_estado_check
  check (estado = any (array[
    'en_venta', 'no_disponible', 'en_construccion', 'construido',
    'finalizado', 'gestionado', 'stand_by', 'cedido'
  ]));

comment on column public.proyectos.estado is
  'Estado comercial/de obra del proyecto. Solo `en_construccion` habilita el disparo de vencimientos por avance de obra (obra_confirmar_avance). Se cambia por proyecto_cambiar_estado(), nunca por UPDATE directo.';

-- 2) Umbral de venta para poder iniciar la construccion, configurable por proyecto.
alter table public.proyectos
  add column pct_minimo_inicio numeric not null default 33
    check (pct_minimo_inicio >= 0 and pct_minimo_inicio <= 100);

comment on column public.proyectos.pct_minimo_inicio is
  'Porcentaje de unidades vendidas necesario para pasar a en_construccion. Un admin puede forzar por debajo, y queda registrado en proyecto_eventos.';

-- 3) Plazos en dias por proyecto y por pago (los 5 de Construccion).
create table public.proyecto_plazo_pago (
  proyecto_id uuid not null references public.proyectos(id) on delete cascade,
  orden_pago int not null check (orden_pago between 1 and 5),
  dias int not null check (dias >= 0 and dias <= 365),
  actualizado_en timestamptz not null default now(),
  actualizado_por text,
  primary key (proyecto_id, orden_pago)
);

alter table public.proyecto_plazo_pago enable row level security;
revoke all on public.proyecto_plazo_pago from public, anon, authenticated;
grant select on public.proyecto_plazo_pago to authenticated;
create policy proyecto_plazo_pago_select on public.proyecto_plazo_pago
  for select using (es_agente());

comment on table public.proyecto_plazo_pago is
  'Dias entre avanzar una fase de obra y la fecha de vencimiento de su pago, por proyecto y por pago (1-5). Solo lo escribe proyecto_fijar_plazo().';

-- 4) Registro de eventos de proyecto -- hoy no existia ninguno (contrato_eventos es por contrato).
--    Hace falta para dejar constancia de quien fuerza un inicio por debajo del umbral.
create table public.proyecto_eventos (
  id uuid primary key default gen_random_uuid(),
  proyecto_id uuid not null references public.proyectos(id) on delete cascade,
  evento text not null,
  detalle jsonb,
  quien text,
  creado_en timestamptz not null default now()
);

create index proyecto_eventos_proyecto_idx on public.proyecto_eventos (proyecto_id, creado_en desc);

alter table public.proyecto_eventos enable row level security;
revoke all on public.proyecto_eventos from public, anon, authenticated;
grant select on public.proyecto_eventos to authenticated;
create policy proyecto_eventos_select on public.proyecto_eventos
  for select using (es_agente());

comment on table public.proyecto_eventos is
  'Bitacora de cambios de estado de un proyecto y de saltos del umbral de venta. Solo la escriben las funciones SECURITY DEFINER del propio proyecto.';
