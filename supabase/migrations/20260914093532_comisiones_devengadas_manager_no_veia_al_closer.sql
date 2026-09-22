-- CORRECCIÓN sobre 20260914120000_comisiones_devengadas.sql, misma sesión:
-- verificando con una sesión simulada de manager, la policy "leer" (y la de
-- "actualizar") no le enseñaban NINGUNA fila nivel='closer' de su propio
-- equipo -- ni siquiera la del miembro vigente que debían mostrarle.
--
-- CAUSA: las dos policies llegan al equipo_id de una fila haciendo JOIN a
-- public.condiciones_comision (condicion_id -> equipo_id). Pero
-- condiciones_comision tiene SU PROPIA RLS (de
-- 20260914100000_condiciones_comision_tramos.sql), y esa RLS es la del punto
-- de vista de un CLOSER/manager sobre CONDICIONES, no la de este caso: un
-- manager no puede leer una condición nivel='closer' salvo que él MISMO sea
-- closer_email de un override, o miembro vigente del equipo -- y un manager
-- normalmente no es miembro de su propio equipo. Postgres aplica RLS también
-- dentro de un EXISTS/JOIN referenciado desde OTRA policy (no es un bypass
-- automático): el resultado con una sesión de manager real era
-- `select count(*) from condiciones_comision where id = <la condición de su
-- equipo>` = 0 filas -- confirmado en vivo antes de este fix, no supuesto.
--
-- FIX: un helper SECURITY DEFINER que resuelve condicion_id -> equipo_id sin
-- pasar por la RLS de condiciones_comision (mismo patrón que es_admin() /
-- es_agente(): función definer, dueña de la tabla, bypass legítimo). No
-- expone nada sensible nuevo -- equipo_id ya es público para cualquier
-- authenticated a través de equipos_venta (policy "equipos_venta: leer" ...
-- using (true)); esta función solo evita el salto por la tabla intermedia
-- restringida. Por eso SÍ lleva EXECUTE a authenticated (a diferencia de
-- valida_suma_tramos_comision, que es un trigger y no necesita que nadie la
-- llame por RPC): aquí la llama la propia policy con el rol del usuario.
--
-- destructivo-ok: DROP POLICY solo sobre las dos policies creadas en la
-- migración anterior de esta misma sesión (no hay filas ni dependientes que
-- perder); no hay DELETE ni UPDATE sin WHERE en este fichero.

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
-- anon no la necesita: sin acceso a comisiones_devengadas, no hay policy que la invoque para anon.

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
