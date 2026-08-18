-- ════════════════════════════════════════════════════════════════════════════
-- PERMISOS POR PROYECTO — 18-ago-2026, encargo del owner
-- ════════════════════════════════════════════════════════════════════════════
-- Hasta hoy el permiso tenía UNA sola dimensión: qué HERRAMIENTAS ve cada uno
-- (`usuarios.herramientas` + `puede()`). Eso reparte el acceso a Contratos,
-- Facturas, Obra… pero dentro de Contratos todo el mundo podía crear en
-- cualquiera de los 29 proyectos, vendiera el que vendiera. Esta es la segunda
-- dimensión: SOBRE QUÉ PROYECTOS puede trabajar cada agente.
--
-- LAS TRES DECISIONES DEL OWNER (18-ago), para que nadie las reabra a ciegas:
--   1. Alcance: se filtra donde se trabaja (el selector de proyecto y, con él,
--      el inventario de parcelas) Y se frena en la BASE al crear/editar. Los
--      paneles de dirección (Operaciones, Vencimientos) NO se filtran: ya están
--      limitados por herramienta y filtrar sus totales es otra obra.
--   2. A quién: solo al rol `agente`. `admin` y `super_admin` siguen sin límite
--      — es el corte que ya existe en todo el sistema (`es_admin()`).
--   3. Por defecto: sin proyectos asignados NO se crea nada. Para que nadie
--      pierda acceso hoy, la migración de abajo asigna TODOS los proyectos
--      activos a los agentes que ya existen; a partir de ahí se quita lo que
--      sobre. Un permiso se concede, no se hereda.
--
-- POR QUÉ SE GUARDAN IDs Y NO NOMBRES. `usuarios.proyectos` es `uuid[]` contra
-- `proyectos.id`. Guardar el nombre habría creado otra lista a mano que
-- `renombrar_proyecto()` tendría que ir a actualizar — que es exactamente el
-- fallo abierto en LAW-36. Con el id, renombrar un proyecto no toca ni un
-- permiso.

alter table public.usuarios
  add column if not exists proyectos uuid[] not null default '{}';

comment on column public.usuarios.proyectos is
  'Proyectos (proyectos.id) sobre los que este usuario puede crear/editar contratos. Solo aplica al rol agente: admin y super_admin no tienen límite. Vacío = ninguno.';

-- ── El permiso, por nombre de proyecto ──────────────────────────────────────
-- Devuelve el nombre porque es lo que guarda el contrato (`proyecto_nombre` y
-- `datos->fields->>proyecto_nombre`); el id solo vive en la asignación.
-- `p_nombre` y no `nombre`: dentro del cuerpo se compara contra
-- `proyectos.nombre`, y Postgres no adivina cuál es cuál — «column reference
-- nombre is ambiguous» al crearla.
create or replace function public.puede_proyecto(p_nombre text)
returns boolean
language sql stable security definer
set search_path to ''
as $$
  select case
    -- admin y super_admin, sin límite (decisión 2)
    when public.es_admin() then true

    -- Cuenta de auth SIN ficha en `usuarios` (hay 5 el 18-ago): mismo camino
    -- que `puede()`, no uno propio. Si algún día ese fallback cambia, cambia
    -- en los dos sitios o un usuario tendrá herramienta y no proyecto, o al
    -- revés, sin que nadie entienda por qué.
    when not exists (select 1 from public.usuarios u where u.user_id = (select auth.uid()))
      then coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'agente')::boolean, false)

    -- Documento SIN proyecto: no hay proyecto que restringir. Es un caso real,
    -- no un hueco — el Poder Notarial no lleva proyecto, y hay 12 contratos
    -- históricos sin él. Bloquearlos dejaría al agente sin poder trabajar.
    when coalesce(btrim(p_nombre), '') = '' then true

    -- Nombre que NO está en el catálogo: contratos viejos con el nombre
    -- comercial de entonces («Horizon by Balian Hills» cuando el catálogo dice
    -- «Horizon S1»); son ~13 el 18-ago. No puede coincidir con ninguno de los
    -- asignados, así que bloquearlo solo conseguiría que su propio autor no
    -- pueda tocar su histórico. El selector solo ofrece nombres del catálogo,
    -- así que un contrato NUEVO nunca cae por aquí.
    when not exists (select 1 from public.proyectos p where p.nombre = btrim(p_nombre)) then true

    else exists (
      select 1
        from public.usuarios u
        join public.proyectos p on p.id = any (u.proyectos)
       where u.user_id = (select auth.uid()) and u.activo
         and p.nombre = btrim(p_nombre))
  end
$$;
revoke execute on function public.puede_proyecto(text) from public, anon;

-- El proyecto de un contrato vive en DOS sitios y manda el del JSON (mismo
-- coalesce que `sincroniza_unidad_contrato`). Envuelto en una función para que
-- las cuatro policies no repitan la expresión: una lista a mano en cuatro
-- sitios es la forma larga de que un día solo se arreglen tres.
create or replace function public.puede_proyecto_de(datos jsonb, col text)
returns boolean
language sql stable security definer
set search_path to ''
as $$
  select public.puede_proyecto(
    coalesce(nullif(btrim(datos -> 'fields' ->> 'proyecto_nombre'), ''), col))
$$;
revoke execute on function public.puede_proyecto_de(jsonb, text) from public, anon;

-- ── Las policies de `contratos`, con la condición nueva añadida ─────────────
-- Se reescriben ENTERAS a propósito (no hay ALTER POLICY que añada un AND):
-- cada una conserva palabra por palabra lo que ya tenía, y suma el proyecto.
-- LEER no cambia: un agente ya solo veía sus propios contratos (`es_suyo`).

drop policy if exists "agentes con la herramienta insertan contratos" on public.contratos;
create policy "agentes con la herramienta insertan contratos" on public.contratos
  for insert to authenticated
  with check (public.es_agente() and public.puede('contratos')
              and public.puede_proyecto_de(datos, proyecto_nombre));

-- USING mira la fila VIEJA y WITH CHECK la NUEVA: así no se puede editar un
-- contrato de un proyecto ajeno, ni MOVER uno propio a un proyecto ajeno.
drop policy if exists "el autor o un admin editan contratos no bloqueados" on public.contratos;
create policy "el autor o un admin editan contratos no bloqueados" on public.contratos
  for update to authenticated
  using (bloqueado = false and public.es_agente() and public.puede('contratos')
         and public.es_suyo(creado_por)
         and public.puede_proyecto_de(datos, proyecto_nombre))
  with check (public.es_agente() and public.puede('contratos')
              and public.puede_proyecto_de(datos, proyecto_nombre));

drop policy if exists "borrar contratos" on public.contratos;
create policy "borrar contratos" on public.contratos
  for delete to authenticated
  using (public.es_super_admin()
         or (coalesce(bloqueado, false) = false and public.es_agente()
             and public.puede('contratos')
             and creado_por is not null and creado_por = (select auth.email())
             and public.puede_proyecto_de(datos, proyecto_nombre)));

-- ── Migración: nadie pierde acceso HOY ──────────────────────────────────────
-- Solo a los agentes, y solo a los que no tienen ninguno todavía (idempotente:
-- si se vuelve a ejecutar, no pisa lo que el owner ya haya afinado a mano).
-- A los admin se les deja vacío A PROPÓSITO: no les aplica, y rellenarlo daría
-- a entender que sí. Si un día uno baja a agente, se le asignan entonces.
update public.usuarios u
   set proyectos = (select coalesce(array_agg(p.id), '{}')
                      from public.proyectos p where coalesce(p.activo, true))
 where u.rol = 'agente'
   and coalesce(array_length(u.proyectos, 1), 0) = 0;

-- ── Comprobación (la del catálogo, nunca el «ya lo mandé») ──────────────────
--   select column_name from information_schema.columns
--    where table_name='usuarios' and column_name='proyectos';        → 1 fila
--   select polname, pg_get_expr(polwithcheck, polrelid) from pg_policy
--    where polrelid='public.contratos'::regclass;   → las 3 con puede_proyecto_de
--   select rol, count(*), min(coalesce(array_length(proyectos,1),0))
--     from public.usuarios group by rol;            → agente ≥ 29, admin 0
-- Y la de comportamiento: DO con rollback suplantando a un agente — crear en un
-- proyecto asignado pasa, en uno no asignado revienta, y sin proyecto pasa.
