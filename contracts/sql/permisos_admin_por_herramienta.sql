-- ════════════════════════════════════════════════════════════════════════════
-- LOS ADMIN TAMBIÉN SE LIMITAN POR HERRAMIENTA — 18-ago-2026, encargo del owner
-- ════════════════════════════════════════════════════════════════════════════
-- «Son gente del equipo interno pero no todos deben tener acceso a todo.»
--
-- Hasta hoy `puede(herramienta)` devolvía true para cualquier `admin`: la lista
-- de `usuarios.herramientas` existía para ellos —y estaba rellenada, entre 1 y
-- 10 herramientas cada uno— pero NO GOBERNABA NADA. Ocho de los dieciocho
-- usuarios eran admin, así que en la práctica el reparto por herramienta solo
-- se aplicaba a la mitad del equipo.
--
-- Ahora el único sin límite es `super_admin` (hay exactamente uno). Un admin
-- pasa por su lista igual que un agente.
--
-- LAS DOS DECISIONES DEL OWNER (18-ago):
--   1. Aterrizaje DIRECTO: se activa con lo que cada admin tiene marcado hoy,
--      sin rellenar nada antes. Se le enseñó el impacto exacto y lo aceptó —
--      p.ej. admin@lawangproperties.com se queda solo con Contratos.
--   2. La gestión de usuarios se limita TAMBIÉN en la base, no solo en el menú:
--      es el permiso más delicado que hay (quien lo tiene puede concederse
--      cualquier otro), así que esconder la pantalla no bastaba.
--
-- LO QUE ESTE CAMBIO NO TOCA, a propósito:
--   · `es_admin()` sigue significando lo mismo en `es_suyo()`: un admin sigue
--     viendo y editando documentos de otros. Eso es autoría, no herramientas.
--   · `puede_proyecto()` sigue exento para admin: el límite por proyecto es
--     solo para agentes (decisión del 18-ago, permisos_por_proyecto.sql).
--   · LEER no cambia para nadie. Verificado antes de aplicar: las 16 policies
--     que usan `puede()` son de escritura; ninguna de SELECT. La única lectura
--     afectada es la de las fotos de obra, cuya policy es FOR ALL — y a quien
--     no tenga «Obra» tampoco se le abre la herramienta, así que es coherente.

create or replace function public.puede(herramienta text)
returns boolean
language sql stable security definer
set search_path to ''
as $$
  select case
    -- ÚNICO sin límite. Antes era es_admin() y ese era justo el agujero.
    when public.es_super_admin() then true
    when exists (select 1 from public.usuarios u where u.user_id = (select auth.uid()))
      then exists (select 1 from public.usuarios u
                    where u.user_id = (select auth.uid()) and u.activo
                      and herramienta = any(u.herramientas))
    -- cuenta de auth sin ficha: se conserva el fallback que ya tenía
    else coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'agente')::boolean, false)
  end
$$;

-- ── La gestión de usuarios, con su propia herramienta ───────────────────────
-- Se reescriben enteras conservando lo que ya decían y sumando `puede`.
-- Ojo al orden de la comprobación: `es_admin() AND puede('usuarios')` — el rol
-- sigue haciendo falta, la herramienta ya no basta por sí sola. Un agente con
-- «usuarios» marcado NO gestiona usuarios.
drop policy if exists "solo admin crea usuarios" on public.usuarios;
create policy "solo admin crea usuarios" on public.usuarios
  for insert to authenticated
  with check (public.es_admin() and public.puede('usuarios'));

drop policy if exists "admin edita, pero no toca una fila super_admin sin serlo" on public.usuarios;
create policy "admin edita, pero no toca una fila super_admin sin serlo" on public.usuarios
  for update to authenticated
  using (public.es_admin() and public.puede('usuarios')
         and (rol <> 'super_admin' or public.es_super_admin()))
  with check (public.es_admin() and public.puede('usuarios')
              and (rol <> 'super_admin' or public.es_super_admin()));

-- ── Comprobación (la del catálogo, nunca el «ya lo mandé») ──────────────────
--   select prosrc from pg_proc where proname='puede';   → es_super_admin(), no es_admin()
--   select polname, pg_get_expr(polwithcheck, polrelid) from pg_policy
--    where polrelid='public.usuarios'::regclass;        → las dos con puede('usuarios')
-- Y la de comportamiento: DO con rollback suplantando a un admin con lista
-- corta — escribir en su herramienta pasa, en una que no tiene revienta, y
-- tocar `usuarios` sin la herramienta «usuarios» revienta.
