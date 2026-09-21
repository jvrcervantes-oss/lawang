-- EL GRANT MANDA ANTES QUE LA POLICY, y por poco se queda el panel sin escribir.
--
-- `cuentas_bancarias` tenía `GRANT SELECT` a `authenticated` y nada más (correcto
-- mientras solo se leía: se editaba por SQL). Las policies de INSERT/UPDATE que
-- se añadieron hoy para el super admin **no habrían servido de nada**: sin el
-- GRANT, Postgres corta antes de mirar la RLS y el panel habría dado «permission
-- denied for table cuentas_bancarias» al guardar. Cazado al auditar los grants
-- después del `revoke ... from anon`, no al escribir el código.
--
-- Quien decide sigue siendo la RLS (`es_super_admin()`): el GRANT solo abre la
-- puerta para que la policy pueda opinar. Sin DELETE a propósito — una cuenta
-- referenciada por contratos emitidos no se borra, se desactiva, y no hay policy
-- de DELETE que lo permitiera.
grant insert, update on table public.cuentas_bancarias to authenticated;

-- Y en las dos tablas nuevas, al revés: nacieron con TODO (el `grant all` que
-- Supabase da por defecto a `authenticated`), incluido TRUNCATE. La RLS lo
-- contiene, pero un privilegio que nadie necesita es superficie de ataque si
-- mañana una policy se relaja por error. Se dejan los cuatro que el panel usa de
-- verdad: leer, marcar, cambiar la precarga y desmarcar.
revoke all on table public.plantillas_pago   from authenticated;
revoke all on table public.plantilla_cuentas from authenticated;
grant select, insert, update, delete on table public.plantillas_pago   to authenticated;
grant select, insert, update, delete on table public.plantilla_cuentas to authenticated;;
