-- ════════════════════════════════════════════════════════════════════════════
-- AGENTE VE SOLO LO SUYO + ROLES sales_manager / project_manager — 10-sep-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Encargo del owner. Revisión previa: Seguridad + Datos + Legal sobre el plan
-- (CEO/flujos/revision_previa.md), 15 hallazgos plegados aquí antes de escribir
-- una línea. Verificado contra la base REAL antes de diseñar (el repo estuvo 33
-- migraciones desincronizado hasta el 9-sep — no basta con leer el .sql viejo):
--   - contratos/facturas YA estaban bien scoped en lectura (es_agente() AND
--     es_suyo(creado_por)); NO existía ninguna política "el equipo se ve entre
--     sí" ahí — esa solo vive en `usuarios`. Solo hacía falta AÑADIR la rama de
--     manager, no tocar nada de lo que ya funcionaba.
--   - `clients` y `unidades` SÍ eran de lectura abierta a cualquier agente
--     (`es_agente()` a secas) — ahí es donde de verdad se cierra algo.
--
-- LAS DECISIONES QUE HAY QUE CONOCER ANTES DE TOCAR ESTO:
--
--   1. `puede_proyecto()` es fail-open a propósito (pensado para no bloquear
--      una ESCRITURA por un dato mal etiquetado) y compara por NOMBRE. Para
--      LECTURA eso es lo contrario de lo que se pide: una fila con proyecto
--      huérfano o mal escrito quedaría visible a todo el equipo, en silencio.
--      Por eso `es_manager_de()` de abajo es una función NUEVA, fail-CLOSED,
--      y compara por `proyecto_id` (uuid, ya indexado), nunca por nombre — un
--      proyecto renombrado no le afecta.
--   2. `es_suyo(autor)` devuelve TRUE cuando `autor` es NULL — correcto para
--      contratos/facturas (documento sin autor = de todos, decisión del
--      27-jul) pero JAMÁS se reutiliza tal cual para una fila nueva: para
--      `clients.propietario` el default es el CONTRARIO (sin propietario
--      reconstruible → NO visible a un agente, solo admin/manager), porque
--      esto es KYC (pasaporte, nacionalidad, domicilio) y el mismo patrón ya
--      mordió una vez con `notificaciones` (`es_suyo(null)=TRUE` enseñó avisos
--      solo-admin a todo el equipo del 4-ago al 9-sep).
--   3. `es_agente()` devuelve TRUE para CUALQUIER usuario activo, mire o no su
--      rol — así que un `sales_manager`/`project_manager` también la pasa.
--      Cada policy tocada añade su propia rama `es_manager_de(...)` explícita;
--      no se asume que el rol nuevo hereda nada de las funciones existentes.
--   4. Los roles nuevos son SOLO LECTURA. No se les da INSERT/UPDATE/DELETE en
--      ninguna tabla — el encargo pide que "reciban información" y "tengan
--      acceso a toda la información", nunca que editen. Si algún día hace
--      falta que editen, es una decisión aparte, no una consecuencia de esto.
--   5. La asignación de QUÉ proyectos ve cada manager reutiliza `usuarios.
--      proyectos` (uuid[], ya existe desde el 18-ago) — el owner sigue
--      asignándolo a mano, persona por persona, como ya hace con los agentes.
--      No hay tabla nueva de asignación ni regla automática por rol.

-- ── 1. Los dos roles nuevos ──────────────────────────────────────────────────
-- destructivo-ok: DROP+ADD CONSTRAINT solo amplía el CHECK de rol (5 valores en
-- vez de 3), no borra filas ni relaja nada de lo que ya había. Mismo patrón que
-- toda reescritura de policy de este fichero: se sustituye, no se retira.
alter table public.usuarios drop constraint if exists usuarios_rol_check;
alter table public.usuarios add constraint usuarios_rol_check
  check (rol = any (array['super_admin','admin','agente','sales_manager','project_manager']));

comment on column public.usuarios.proyectos is
  'Proyectos (proyectos.id) sobre los que este usuario trabaja. Agente: crea/edita contratos y LEE obra/clientes de estos proyectos (desde el 10-sep, antes solo gobernaba escritura). sales_manager/project_manager: LEE (nunca edita) todo lo que pase en estos proyectos, de cualquier agente. admin y super_admin no tienen límite. Vacío = ninguno.';

create or replace function public.es_gestor()
returns boolean
language sql stable security definer
set search_path to ''
as $$
  select exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo
       and u.rol in ('sales_manager','project_manager')
  )
$$;
revoke execute on function public.es_gestor() from public, anon;
grant execute on function public.es_gestor() to authenticated;

-- Fail-CLOSED por proyecto_id (uuid). A diferencia de `puede_proyecto()`
-- (fail-open, por nombre, pensada para no bloquear una escritura), aquí un
-- proyecto NULL o sin match NO concede nada — es lectura, no escritura, y el
-- default seguro es "no se ve" (decisión 1 de arriba).
create or replace function public.es_manager_de(p_proyecto_id uuid)
returns boolean
language sql stable security definer
set search_path to ''
as $$
  select case
    when public.es_admin() then true
    when p_proyecto_id is null then false
    else exists (
      select 1 from public.usuarios u
       where u.user_id = (select auth.uid()) and u.activo
         and u.rol in ('sales_manager','project_manager')
         and p_proyecto_id = any (u.proyectos))
  end
$$;
revoke execute on function public.es_manager_de(uuid) from public, anon;
grant execute on function public.es_manager_de(uuid) to authenticated;

-- ── 2. `clients` — de "abierto a todo el equipo" a "lo suyo + su manager" ───
alter table public.clients add column if not exists propietario text;
comment on column public.clients.propietario is
  'Email de quien dio de alta la ficha (auth.email() de creado_por en contratos, NUNCA el nombre — mismo motivo que contratos.creado_por: es la identidad con la que decide la RLS). NULL = sin autor reconstruible: NO visible a un agente, solo admin/manager (decisión 2 de arriba — al revés que contratos).';
create index if not exists clients_propietario_idx on public.clients (propietario);

create or replace function public.cliente_visible(p_propietario text, p_client_id uuid)
returns boolean
language sql stable security definer
set search_path to ''
as $$
  select case
    when public.es_admin() then true
    when public.es_gestor() then exists (
      select 1
        from public.contrato_compradores cc
        join public.contratos c on c.id = cc.contrato_id
       where cc.client_id = p_client_id
         and public.es_manager_de(c.proyecto_id))
    else coalesce(p_propietario = (select auth.email()), false)
  end
$$;
revoke execute on function public.cliente_visible(text, uuid) from public, anon;
grant execute on function public.cliente_visible(text, uuid) to authenticated;

drop policy if exists "agentes leen clientes" on public.clients;
create policy "cada uno lo suyo, el manager lo de su proyecto, admin todo" on public.clients
  for select to authenticated
  using (es_agente() and public.cliente_visible(propietario, id));

-- ── 3. `unidades` (obra) — de "abierto a todo el equipo" a "sus proyectos" ──
-- "Sus obras" es por PROYECTO ASIGNADO (`usuarios.proyectos`), no por autoría:
-- una unidad no la "crea" un agente concreto, es del proyecto entero. Mismo
-- concepto que ya gobierna la ESCRITURA de contratos desde el 18-ago, ahora
-- también para la LECTURA de obra. Fail-closed: los 462 registros tienen
-- proyecto_id hoy (comprobado en vivo), cero regresión por NULL.
create or replace function public.unidad_visible(p_proyecto_id uuid)
returns boolean
language sql stable security definer
set search_path to ''
as $$
  select case
    when public.es_admin() then true
    when public.es_manager_de(p_proyecto_id) then true
    when p_proyecto_id is null then false
    else exists (
      select 1 from public.usuarios u
       where u.user_id = (select auth.uid()) and u.activo
         and p_proyecto_id = any (u.proyectos))
  end
$$;
revoke execute on function public.unidad_visible(uuid) from public, anon;
grant execute on function public.unidad_visible(uuid) to authenticated;

drop policy if exists "agentes leen unidades" on public.unidades;
create policy "agentes leen unidades de sus proyectos, manager de los suyos" on public.unidades
  for select to authenticated
  using (es_agente() and public.unidad_visible(proyecto_id));

-- ── 4. `contratos`/`facturas` — YA scoped a su autor; se AÑADE el manager ───
-- No existía policy "el equipo se ve entre sí" aquí (verificado en pg_policies
-- el 10-sep) — solo se añade la rama nueva, el resto queda intacto.
drop policy if exists "agentes leen sus contratos" on public.contratos;
create policy "agentes leen sus contratos" on public.contratos
  for select to authenticated
  using (es_agente() and (es_suyo(creado_por) or public.es_manager_de(proyecto_id)));

drop policy if exists "agentes leen sus facturas" on public.facturas;
create policy "agentes leen sus facturas" on public.facturas
  for select to authenticated
  using (es_agente() and (es_suyo(creado_por) or public.es_manager_de(proyecto_id)));

-- `recibi_aplicaciones` (recibís/justificantes) no tiene proyecto_id propio:
-- hereda el de la factura/recibí que referencia, en las dos direcciones.
drop policy if exists "agentes leen aplicaciones de sus documentos" on public.recibi_aplicaciones;
create policy "agentes leen aplicaciones de sus documentos" on public.recibi_aplicaciones
  for select to authenticated
  using (
    (exists (select 1 from public.facturas r
              where r.id = recibi_aplicaciones.recibi_id and es_agente()
                and (es_suyo(r.creado_por) or public.es_manager_de(r.proyecto_id))))
    or
    (exists (select 1 from public.facturas f
              where f.id = recibi_aplicaciones.factura_id and es_agente()
                and (es_suyo(f.creado_por) or public.es_manager_de(f.proyecto_id))))
  );

-- ── 5. `solicitudes_pago` — ya scoped a su creador; se AÑADE el manager ─────
-- `contrato_id` es referencia OPCIONAL (ver contracts/sql/solicitudes_pago):
-- una solicitud sin contrato no tiene proyecto derivable y un manager no la ve
-- (fail-closed, admin sigue viéndolas todas). Es el mismo criterio que el
-- resto de este fichero: sin dato para decidir, no se concede.
drop policy if exists "solicitudes: cada agente lee las suyas, admin todas" on public.solicitudes_pago;
create policy "solicitudes: cada agente lee las suyas, admin todas, manager las de su proyecto" on public.solicitudes_pago
  for select to authenticated
  using (
    es_admin()
    or (creado_por = (select auth.uid()))
    or exists (select 1 from public.contratos c
                where c.id = solicitudes_pago.contrato_id
                  and public.es_manager_de(c.proyecto_id))
  );

-- ── 6. Backfill de `clients.propietario` — SQL puro, sin PII embebida ───────
-- "El primer contrato que referencia cada ficha", vía `contrato_compradores`
-- (NO existe `contratos.client_id` — el vínculo real es la tabla puente).
-- Determinista por fecha (comprobado: cero empates de `created_at` entre las
-- 125 fichas con contrato). Las 46 fichas sin ningún contrato quedan con
-- propietario NULL — visibles solo a admin/manager desde ahora (decisión 2).
update public.clients c
   set propietario = sub.creado_por
  from (
    select distinct on (cc.client_id) cc.client_id, ct.creado_por
      from public.contrato_compradores cc
      join public.contratos ct on ct.id = cc.contrato_id
     where ct.creado_por is not null
     order by cc.client_id, ct.created_at asc
  ) sub
 where c.id = sub.client_id
   and c.propietario is null;

-- ── Comprobación (la del catálogo, nunca el «ya lo mandé») ──────────────────
--   select conname, pg_get_constraintdef(oid) from pg_constraint
--    where conrelid='public.usuarios'::regclass and contype='c';  → 5 roles
--   select count(*) from public.clients where propietario is not null;  → 125
--   select polname from pg_policy where polrelid in
--    ('public.clients'::regclass,'public.unidades'::regclass,
--     'public.contratos'::regclass,'public.facturas'::regclass,
--     'public.recibi_aplicaciones'::regclass,'public.solicitudes_pago'::regclass);
-- Y la de comportamiento: DO con `SET LOCAL ROLE authenticated` + JWT de un
-- agente real y de un manager de prueba — nunca con el MCP (bypasea RLS por
-- ser propietario de las tablas) ni con el SQL Editor.
--
-- ── Pendiente para el owner, no resuelto aquí a propósito ───────────────────
-- 6 fichas de `clients` tienen contratos de MÁS DE UN agente (traspaso de
-- cliente entre agentes, probablemente). El backfill asigna el PRIMERO por
-- fecha porque es lo que se pidió, pero queda anotado en
-- `contexto/pendientes.md` con owner para que se revise a mano quién debe
-- verla de verdad — no se adivina.
