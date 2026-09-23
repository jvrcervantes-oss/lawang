-- Comisiones: una entrada con cuatro pestañas, una casilla por pestaña
-- (23-sep-2026, plan aprobado por el owner: «Necesitamos agrupar y controlar lo
-- que se ve por permisos»; opción B: los equipos y sus closers los asigna
-- administración, el Sales Manager solo consulta su equipo).
--   comisiones             -> «Pagos de Lawang» (solicitudes_pago, avisos): sin cambios
--   comisiones_reparto     -> «Reparto a closers» (comisiones_devengadas)
--   comisiones_condiciones -> «Condiciones»
--   comisiones_equipos     -> «Equipos»
-- La casilla decide si la pestaña aparece. Lo que se ve dentro lo sigue
-- decidiendo el rol: el closer lo suyo, el manager su equipo, el admin todo si
-- tiene la casilla.
--
-- 1) El admin lee y ajusta devengos con la casilla de REPARTO, ya no con la de
--    Pagos. Se reescriben las policies vivas sustituyendo la llamada, y el
--    candado de ajustar/anular (_comision_devengo_admin_puede) igual.
-- 2) Cada usuario recibe las casillas de su rol, sin quitar ninguna:
--    agente / project_manager -> reparto; sales_manager -> reparto, condiciones,
--    equipos; admin -> condiciones, equipos. «Pagos» no se da a nadie: los dos
--    Sales Managers que ya la tienen la conservan.
--    Se ejecuta como el super_admin owner (el trigger solo deja tocar
--    herramientas a un super_admin, y el cambio es suyo).
-- Ensayado en ROLLBACK: SM 7/7 las tres, agentes 19 reparto, PM 1 reparto,
-- admins 4 condiciones+equipos, Pagos sigue en 2.
do $$
declare r record; q text; w text;
begin
  for r in select tablename, policyname, qual, with_check from pg_policies
            where schemaname = 'public' and tablename in ('comisiones_devengadas', 'comisiones_ajustes_log')
              and coalesce(qual, '') || coalesce(with_check, '') ~ 'puede\(''comisiones''::text\)'
  loop
    q := replace(r.qual, 'puede(''comisiones''::text)', 'puede(''comisiones_reparto''::text)');
    w := replace(r.with_check, 'puede(''comisiones''::text)', 'puede(''comisiones_reparto''::text)');
    execute format('alter policy %I on public.%I', r.policyname, r.tablename)
      || case when q is not null then ' using (' || q || ')' else '' end
      || case when w is not null then ' with check (' || w || ')' else '' end;
  end loop;
end $$;

do $$
declare d text;
begin
  d := pg_get_functiondef('public._comision_devengo_admin_puede(uuid)'::regprocedure);
  if position('public.puede(''comisiones'')' in d) = 0 then
    raise exception '_comision_devengo_admin_puede: no encuentro el candado puede(''comisiones'')';
  end if;
  d := replace(d, 'public.puede(''comisiones'')', 'public.puede(''comisiones_reparto'')');
  execute d;
end $$;

select set_config('request.jwt.claims', json_build_object('sub',
  (select user_id from public.usuarios where email = 'jvr.cervantes@gmail.com' and rol = 'super_admin'),
  'role', 'authenticated')::text, true);

update public.usuarios u set herramientas = coalesce((
  select array_agg(distinct h order by h) from unnest(u.herramientas
    || case when u.rol in ('agente', 'project_manager', 'sales_manager') then array['comisiones_reparto'] else '{}'::text[] end
    || case when u.rol in ('sales_manager', 'admin') then array['comisiones_condiciones', 'comisiones_equipos'] else '{}'::text[] end) h),
  '{}'::text[])
where u.rol in ('agente', 'project_manager', 'sales_manager', 'admin');
