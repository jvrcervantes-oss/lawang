-- destructivo-ok: los DROP POLICY son solo sobre las dos policies creadas en
-- la migración anterior de esta misma sesión (20260914120000), para
-- recrearlas usando un helper que evita el bug de RLS encontrado en vivo
-- (el manager no veía las filas closer de su equipo). No hay DELETE ni
-- UPDATE sin WHERE en este fichero.

create or replace function public._equipo_de_condicion_comision(p_condicion_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select equipo_id from public.condiciones_comision where id = p_condicion_id
$$;

comment on function public._equipo_de_condicion_comision(uuid) is
  'Bypass legítimo de la RLS de condiciones_comision para resolver condicion_id -> equipo_id desde las policies de comisiones_devengadas. No filtra nada sensible: equipo_id ya es público vía equipos_venta.';

revoke all on function public._equipo_de_condicion_comision(uuid) from public;
grant execute on function public._equipo_de_condicion_comision(uuid) to authenticated;

drop policy if exists "comisiones_devengadas: leer" on public.comisiones_devengadas;
create policy "comisiones_devengadas: leer" on public.comisiones_devengadas
  for select to authenticated using (
    public.es_admin()
    or beneficiario_email = (select auth.email())
    or (
      nivel = 'closer'
      and exists (
        select 1 from public.equipos_venta ev
         where ev.id = public._equipo_de_condicion_comision(comisiones_devengadas.condicion_id)
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

drop policy if exists "comisiones_devengadas: el manager del equipo cierra el cobro del closer" on public.comisiones_devengadas;
create policy "comisiones_devengadas: el manager del equipo cierra el cobro del closer" on public.comisiones_devengadas
  for update to authenticated
  using (
    nivel = 'closer'
    and (
      public.es_admin()
      or exists (
        select 1 from public.equipos_venta ev
         where ev.id = public._equipo_de_condicion_comision(comisiones_devengadas.condicion_id)
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
        select 1 from public.equipos_venta ev
         where ev.id = public._equipo_de_condicion_comision(comisiones_devengadas.condicion_id)
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
