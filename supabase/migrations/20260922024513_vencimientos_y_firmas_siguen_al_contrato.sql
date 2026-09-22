-- ============================================================================
-- VENCIMIENTOS Y FIRMAS SIGUEN AL CONTRATO (LAW-253, ampliada)
-- 22-sep-2026 · saneo de la intranet (revisión previa: Seguridad + Datos)
-- ----------------------------------------------------------------------------
-- contrato_vencimientos tenía SELECT = es_agente() y UPDATE = es_agente() and
-- puede('vencimientos'): cualquier agente con la herramienta leía y EDITABA
-- el calendario de pagos de contratos que no puede ver. Y contrato_firmas,
-- que ya acotaba el SELECT al contrato desde el 11-sep, seguía con UPDATE,
-- DELETE e INSERT = es_agente() a secas: un agente podía anular o borrar el
-- enlace de firma de un contrato ajeno, o crear uno.
--
-- Regla desde hoy, la MISMA que la policy de SELECT de `contratos`
-- («agentes leen sus contratos»): se ve/edita la fila si se ve el contrato —
-- es_suyo(creado_por) o es_manager_de(proyecto_id); super_admin pasa por
-- es_suyo. El gate puede('vencimientos') se CONSERVA en UPDATE (hallazgo de
-- Seguridad: copiar el patrón de firmas sin él era una regresión), y el
-- with check es idéntico al using para que nadie mueva contrato_id a un
-- contrato ajeno.
--
-- Efecto sobre datos reales (Datos lo midió): 10 contratos con creado_por
-- NULL (importados en julio + RP00140) tienen 28 vencimientos. Esos contratos
-- YA son invisibles para los agentes rasos por la policy de contratos
-- (es_suyo(null) = false: hace coalesce(…, false), verificado en vivo); sus vencimientos pasan a
-- comportarse igual — los ven admins y el manager del proyecto. No cambia
-- quién ve el contrato, solo alinea las filas hijas.
-- ============================================================================

-- destructivo-ok: se reemplazan policies por otras más estrechas, mismos nombres

-- ── contrato_vencimientos ───────────────────────────────────────────────────
drop policy if exists vencimientos_select on public.contrato_vencimientos;
create policy vencimientos_select on public.contrato_vencimientos
  for select to authenticated
  using (public.es_agente() and exists (
           select 1 from public.contratos c
            where c.id = contrato_vencimientos.contrato_id
              and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))));

drop policy if exists vencimientos_update on public.contrato_vencimientos;
create policy vencimientos_update on public.contrato_vencimientos
  for update to authenticated
  using (public.es_agente() and public.puede('vencimientos') and exists (
           select 1 from public.contratos c
            where c.id = contrato_vencimientos.contrato_id
              and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))))
  with check (public.es_agente() and public.puede('vencimientos') and exists (
           select 1 from public.contratos c
            where c.id = contrato_vencimientos.contrato_id
              and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))));

-- ── contrato_firmas ─────────────────────────────────────────────────────────
drop policy if exists "agentes actualizan firmas" on public.contrato_firmas;
create policy "agentes actualizan firmas" on public.contrato_firmas
  for update to authenticated
  using (public.es_agente() and exists (
           select 1 from public.contratos c
            where c.id = contrato_firmas.contrato_id
              and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))))
  with check (public.es_agente() and exists (
           select 1 from public.contratos c
            where c.id = contrato_firmas.contrato_id
              and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))));

drop policy if exists "agentes borran firmas" on public.contrato_firmas;
create policy "agentes borran firmas" on public.contrato_firmas
  for delete to authenticated
  using (public.es_agente() and exists (
           select 1 from public.contratos c
            where c.id = contrato_firmas.contrato_id
              and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))));

drop policy if exists "agentes gestionan firmas (escritura)" on public.contrato_firmas;
create policy "agentes gestionan firmas (escritura)" on public.contrato_firmas
  for insert to authenticated
  with check (public.es_agente() and exists (
           select 1 from public.contratos c
            where c.id = contrato_firmas.contrato_id
              and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))));
