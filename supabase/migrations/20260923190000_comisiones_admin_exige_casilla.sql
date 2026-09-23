-- Comisiones: el admin necesita la casilla (23-sep-2026, owner, opción A).
-- La casilla 'comisiones' (nacida hoy, concedida a nadie) solo escondía la
-- pantalla: la base seguía dejando leer solicitudes y devengos a cualquier
-- es_admin() (consulta de deploy, Seguridad). Ahora, donde decía «es_admin()»
-- en comisiones, dice «es_admin() y puede('comisiones')». puede() deja pasar
-- siempre al super_admin.
-- NO cambia (decisión del owner): cada comercial sigue viendo sus solicitudes
-- y sus comisiones, y el manager las de su equipo/proyecto, y puede cerrar el
-- cobro de su equipo. Los disparadores SECURITY DEFINER que generan devengos y
-- avisos no pasan por la RLS: siguen funcionando igual.
-- Se reescriben las policies por programa (sustituir es_admin() dentro de la
-- expresión viva) en vez de copiarlas a mano: son largas y copiarlas es como
-- se cuela una diferencia. Cada una exige encontrar es_admin() o aborta.

do $$
declare
  r record; q text; w text; sub constant text := '(es_admin() AND puede(''comisiones''::text))';
begin
  for r in select tablename, policyname, qual, with_check from pg_policies
            where schemaname = 'public' and tablename in ('solicitudes_pago', 'comisiones_devengadas', 'comisiones_ajustes_log')
              and coalesce(qual, '') || coalesce(with_check, '') ~ 'es_admin\(\)'
  loop
    q := replace(r.qual, 'es_admin()', sub);
    w := replace(r.with_check, 'es_admin()', sub);
    -- es_manager_de() devuelve TRUE a cualquier admin: sin esto el admin sin
    -- casilla seguía entrando por la rama «manager del proyecto» (ensayo en
    -- ROLLBACK, 23-sep: 5 de 5 solicitudes). Va DESPUÉS de sustituir es_admin(),
    -- para que el «NOT es_admin()» de aquí no se convierta.
    q := replace(q, 'es_manager_de(c.proyecto_id)', '(es_manager_de(c.proyecto_id) AND NOT es_admin())');
    execute format('alter policy %I on public.%I', r.policyname, r.tablename)
         || case when q is not null then ' using (' || q || ')' else '' end
         || case when w is not null then ' with check (' || w || ')' else '' end;
    raise notice 'policy % / %', r.tablename, r.policyname;
  end loop;
end $$;

-- Los avisos de la campana: el admin los leía todos. Los de solicitudes de
-- pago, solo con la casilla; el destinatario sigue viendo los suyos siempre.
alter policy "cada uno ve lo suyo, el admin todo" on public.notificaciones
  using ((es_admin() AND (tipo IS DISTINCT FROM 'solicitud_pago' OR puede('comisiones')))
         OR ((destinatario IS NOT NULL) AND (destinatario = (SELECT auth.email() AS email))));

-- Ajustar/anular un devengo (RPC de la sesión de comisiones de hoy): mismo
-- candado. Se parchea la definición VIVA con marca, no el .sql.
do $$
declare d text;
begin
  d := pg_get_functiondef('public._comision_devengo_admin_puede(uuid)'::regprocedure);
  if position('if not public.es_admin() then' in d) = 0 then
    raise exception '_comision_devengo_admin_puede: no encuentro el candado es_admin() a sustituir';
  end if;
  d := replace(d, 'if not public.es_admin() then',
               'if not (public.es_admin() and public.puede(''comisiones'')) then  -- casilla comisiones, 23-sep-2026');
  execute d;
end $$;
