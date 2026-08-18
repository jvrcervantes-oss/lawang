-- ════════════════════════════════════════════════════════════════════════════
-- VENCIMIENTOS PASA A TENER PERMISO PROPIO — 18-ago-2026 (2ª vuelta)
-- ════════════════════════════════════════════════════════════════════════════
-- El owner: «hay una nueva herramienta y no sale en la lista». Tenía razón, y la
-- causa está escrita en el propio catálogo: Vencimientos nació compartiendo la
-- clave `operaciones` porque una clave NUEVA hay que darla de alta en la edge
-- `admin-usuarios` y redesplegarla, y aquel día la edge estaba bloqueada. Al no
-- tener clave propia, no había nada que listar en el panel de permisos.
-- La edge se desplegó esa misma noche, así que el motivo ya no existe.
--
-- LO QUE HAY QUE MIGRAR, y por qué no es opcional: 10 de los 18 usuarios activos
-- tienen `operaciones` y NINGUNO tiene `vencimientos`. Crear la clave sin más
-- les quitaría de golpe una herramienta que ya usaban — y eso no sería una
-- decisión, sería una regresión metida por la puerta de atrás. Se les concede.

update public.usuarios
   set herramientas = array_append(herramientas, 'vencimientos')
 where 'operaciones' = any(herramientas)
   and not ('vencimientos' = any(herramientas));

-- La regla de escritura del calendario operativo pasa a pedir la herramienta
-- que le corresponde. Con la migración de arriba ya aplicada esto no le quita
-- el permiso a nadie: quien podía escribir aquí tenía `operaciones`, y acaba de
-- recibir `vencimientos`. El orden importa — primero conceder, luego exigir.
drop policy if exists vencimientos_update on public.contrato_vencimientos;
create policy vencimientos_update on public.contrato_vencimientos
  for update to authenticated
  using (public.es_agente() and public.puede('vencimientos'))
  with check (public.es_agente() and public.puede('vencimientos'));

-- ── Comprobación (la del catálogo, nunca el «ya lo mandé») ──────────────────
--   select count(*) filter (where 'vencimientos' = any(herramientas))
--     from public.usuarios where activo;                    → 10 o más
--   select pg_get_expr(polqual, polrelid) from pg_policy
--    where polrelid='public.contrato_vencimientos'::regclass
--      and polname='vencimientos_update';                   → puede('vencimientos')
-- Y fuera de la base: `node contracts/listas.test.js` compara el catálogo del
-- navegador con la lista de la edge — las dos tienen que decir 11.
