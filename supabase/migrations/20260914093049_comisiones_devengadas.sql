-- COMISIONES: DEVENGADAS — 14-sep-2026.
-- Subtarea del mismo encargo que equipos_venta/equipo_miembros
-- (20260914090000_comisiones_equipos_venta.sql) y condiciones_comision/
-- condicion_tramos (20260914100000_condiciones_comision_tramos.sql). Esta
-- pieza es la FILA que nace cuando un tramo se dispara de verdad para un
-- contrato concreto: cuánto le toca a QUIÉN (beneficiario_email, nivel) por
-- QUÉ tramo de QUÉ condición, en QUÉ contrato raíz -- y su ciclo de cobro
-- (pendiente -> pagada / en_disputa).
--
-- QUÉ NO CUBRE esta subtarea: quién/qué proceso INSERTA la fila cuando un
-- tramo se dispara de verdad (ese cálculo es de otra subtarea del mismo
-- encargo). Aquí solo se deja la tabla, su unicidad y su RLS listas.
--
-- FUNCIÓN DE ROL: public.es_admin() -- ya cubre super_admin.
--
-- destructivo-ok: no hay DROP ni DELETE ni UPDATE sin WHERE en este fichero.

create table public.comisiones_devengadas (
  id                       uuid primary key default gen_random_uuid(),
  contrato_raiz_id         uuid not null references public.contratos(id),
  tramo_id                 uuid not null references public.condicion_tramos(id),
  condicion_id             uuid not null references public.condiciones_comision(id),
  beneficiario_email       text not null,
  nivel                    text not null check (nivel in ('manager', 'closer')),
  importe                  numeric not null,
  moneda                   text not null,
  tipo_cambio_aplicado     numeric,
  disparado_en             timestamptz not null default now(),
  disparado_por_snapshot   jsonb,
  solicitud_id             uuid references public.solicitudes_pago(id),
  estado                   text not null default 'pendiente' check (estado in ('pendiente', 'pagada', 'en_disputa')),
  pagado_por               text,
  pagado_en                timestamptz,
  created_at               timestamptz not null default now(),

  constraint comisiones_devengadas_unicidad
    unique (contrato_raiz_id, tramo_id, beneficiario_email),
  constraint comisiones_devengadas_solicitud_solo_manager
    check (solicitud_id is null or nivel = 'manager')
);

comment on table public.comisiones_devengadas is
  'Fila que nace cuando un tramo de condicion_tramos se dispara de verdad para un contrato_raiz_id concreto: cuánto (importe/moneda) le toca a beneficiario_email por ese tramo, y su ciclo de cobro (estado). unique(contrato_raiz_id, tramo_id, beneficiario_email) impide devengar dos veces el mismo tramo para el mismo beneficiario en el mismo contrato. Quién/qué inserta la fila (el cálculo del disparo) es otra subtarea del mismo encargo.';
comment on column public.comisiones_devengadas.disparado_por_snapshot is
  'Copia congelada de los datos que dispararon el tramo -- el dato tiene un dueño: si condicion_tramos cambia después, este devengo no se recalcula solo.';
comment on column public.comisiones_devengadas.solicitud_id is
  'Solo nivel=manager la usa -- el cobro del manager pasa por la cola de solicitudes_pago. El cobro del closer se resuelve con estado/pagado_por/pagado_en de esta misma fila. Constraint comisiones_devengadas_solicitud_solo_manager impide que un closer llegue con esta columna rellena.';

create index comisiones_devengadas_contrato_raiz_idx on public.comisiones_devengadas (contrato_raiz_id);
create index comisiones_devengadas_beneficiario_idx  on public.comisiones_devengadas (beneficiario_email);
create index comisiones_devengadas_condicion_idx     on public.comisiones_devengadas (condicion_id);
create index comisiones_devengadas_solicitud_idx     on public.comisiones_devengadas (solicitud_id);
create index comisiones_devengadas_estado_idx        on public.comisiones_devengadas (estado);

alter table public.comisiones_devengadas enable row level security;

revoke all on public.comisiones_devengadas from anon, authenticated;

grant select, insert on public.comisiones_devengadas to authenticated;
grant update (estado, pagado_por, pagado_en) on public.comisiones_devengadas to authenticated;

-- anon: sin policies = sin acceso. DELETE: sin GRANT a nadie.

drop policy if exists "comisiones_devengadas: leer" on public.comisiones_devengadas;
create policy "comisiones_devengadas: leer" on public.comisiones_devengadas
  for select to authenticated using (
    public.es_admin()
    or beneficiario_email = (select auth.email())
    or (
      nivel = 'closer'
      and exists (
        select 1
          from public.condiciones_comision c
          join public.equipos_venta ev on ev.id = c.equipo_id
         where c.id = comisiones_devengadas.condicion_id
           and ev.manager_email = (select auth.email())
           and exists (
             select 1 from public.equipo_miembros em
              where em.equipo_id = ev.id
                and em.closer_email = comisiones_devengadas.beneficiario_email
                and em.desde <= current_date
                and (em.hasta is null or em.hasta >= current_date)
           )
      )
    )
  );

drop policy if exists "comisiones_devengadas: solo admin inserta" on public.comisiones_devengadas;
create policy "comisiones_devengadas: solo admin inserta" on public.comisiones_devengadas
  for insert to authenticated with check (public.es_admin());

drop policy if exists "comisiones_devengadas: el manager del equipo cierra el cobro del closer" on public.comisiones_devengadas;
create policy "comisiones_devengadas: el manager del equipo cierra el cobro del closer" on public.comisiones_devengadas
  for update to authenticated
  using (
    nivel = 'closer'
    and (
      public.es_admin()
      or exists (
        select 1
          from public.condiciones_comision c
          join public.equipos_venta ev on ev.id = c.equipo_id
         where c.id = comisiones_devengadas.condicion_id
           and ev.manager_email = (select auth.email())
           and exists (
             select 1 from public.equipo_miembros em
              where em.equipo_id = ev.id
                and em.closer_email = comisiones_devengadas.beneficiario_email
                and em.desde <= current_date
                and (em.hasta is null or em.hasta >= current_date)
           )
      )
    )
  )
  with check (
    nivel = 'closer'
    and (
      public.es_admin()
      or exists (
        select 1
          from public.condiciones_comision c
          join public.equipos_venta ev on ev.id = c.equipo_id
         where c.id = comisiones_devengadas.condicion_id
           and ev.manager_email = (select auth.email())
           and exists (
             select 1 from public.equipo_miembros em
              where em.equipo_id = ev.id
                and em.closer_email = comisiones_devengadas.beneficiario_email
                and em.desde <= current_date
                and (em.hasta is null or em.hasta >= current_date)
           )
      )
    )
  );
;
