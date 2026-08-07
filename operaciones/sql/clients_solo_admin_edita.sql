-- Lawang · Compradores — editar la ficha de un comprador ya existente pasa a
-- ser solo de administradores/super admin
-- 7-ago-2026
--
-- Petición del owner: los agentes pueden CONSULTAR la ficha (nombre, KYC,
-- documentos) pero no MODIFICAR sus datos de identidad. Crear un comprador
-- nuevo ("+ Nuevo comprador") se queda abierto a cualquier agente — es la
-- entrada de datos del día a día, no lo que se pidió restringir.
--
-- Por qué solo se toca UPDATE, y no INSERT ni SELECT:
--   · SELECT: sigue en es_agente() — consultar la ficha no cambia.
--   · INSERT: sigue en es_agente() — dar de alta a un comprador nuevo sigue
--     siendo tarea de cualquier agente, ver `compradores/index.html` (botón
--     "+ Nuevo comprador") y el disparador `sincronizar_compradores()`
--     (contracts/sql/compradores_desde_contrato.sql) que da de alta fichas
--     automáticamente al guardar un contrato — ese disparador SOLO hace
--     INSERT en `clients`, nunca UPDATE (comprobado antes de escribir esto:
--     `grep -n clients contracts/sql/compradores_desde_contrato.sql`), así
--     que estrechar UPDATE no le afecta.
--   · UPDATE: pasa de es_agente() a es_admin(). Único escritor real de un
--     UPDATE sobre `clients` en todo el repo: `compradores/index.html`
--     (`SB.from('clients').update(...)`, censo hecho por grep en .html/.ts/.js
--     y en los .sql de triggers/RPC antes de tocar esto).
--
-- `documents` (subida de KYC) NO se toca: seguir aceptando pasaportes/NPWP
-- de un comprador es trabajo operativo de cualquier agente, no la
-- "información" que se pidió proteger (los datos de identidad de `clients`).
--
-- destructivo-ok: el DROP POLICY es un reemplazo idempotente (mismo patrón que
-- usa cada .sql de este repo, ver tipo_y_contrato.sql), no borra filas ni
-- tabla; y el "UPDATE sin WHERE" que marca el guardrail es un falso positivo
-- de su propia heurística sobre `FOR UPDATE` de la sintaxis de policy, no una
-- sentencia UPDATE de datos. CLAUDE.md clasifica las policies como DDL que
-- CONSTRUYE (autónomo), no que destruye. Censo de escritores hecho antes de
-- escribir esto (ver arriba): un solo INSERT/UPDATE real sobre `clients` en
-- todo el repo, y no se ve afectado por este cambio.

drop policy if exists "agentes actualizan clientes" on public.clients;

create policy "admins actualizan clientes"
  on public.clients for update to authenticated
  using (public.es_admin())
  with check (public.es_admin());

comment on table public.clients is
  'Fichas de comprador. Cualquier agente lee y da de alta; solo admin/super_admin edita una ya existente (7-ago-2026).';

-- Comprobación:
-- select polname, polcmd from pg_policy where polrelid = 'public.clients'::regclass;
