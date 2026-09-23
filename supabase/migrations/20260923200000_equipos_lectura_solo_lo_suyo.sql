-- Equipos de venta: cada uno lee solo lo suyo (23-sep-2026, owner: «el Sales
-- Manager entra a su panel y puede configurar cuánto van a cobrar sus
-- closers… no todos ven lo de todos, sólo lo suyo»).
-- Hasta hoy equipos_venta y equipo_miembros se leían con using(true): cualquier
-- sesión del equipo veía todos los equipos y quién está en cada uno.
-- Ahora: admin todo; el manager, sus equipos y sus miembros; el closer, su
-- equipo y su propia fila. Los disparadores y el motor de comisiones son
-- SECURITY DEFINER y no pasan por aquí. es_manager_de_equipo() es DEFINER, así
-- que las dos policies no se llaman en bucle.
-- Ensayado en ROLLBACK con 15 usuarios reales: admin 2 equipos/7 miembros;
-- cada sales manager solo el suyo (1/3, 1/4) o nada si no dirige ninguno;
-- cada closer su equipo y su fila. Condiciones, tramos y devengos siguen
-- viéndose igual (sus policies consultan estas tablas con la sesión de quien
-- lee, y lo que necesitan sigue visible).
alter policy "equipos_venta: leer" on public.equipos_venta using (
  public.es_admin()
  or lower(manager_email) = lower(coalesce((select auth.email()), ''))
  or exists (select 1 from public.equipo_miembros em
              where em.equipo_id = equipos_venta.id
                and lower(em.closer_email) = lower(coalesce((select auth.email()), ''))));

alter policy "equipo_miembros: leer" on public.equipo_miembros using (
  public.es_admin()
  or lower(closer_email) = lower(coalesce((select auth.email()), ''))
  or public.es_manager_de_equipo(equipo_id));
