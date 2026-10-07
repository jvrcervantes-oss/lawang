-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 3 · F3 fase B, trozo 2 de 3: plantilla_cuentas y proyecto_cuentas, solo el equipo (es_agente()). No las lee el portal. Ver el trozo 1 sobre el nombre (LAW-496).
-- destructivo-ok: sustituye dos policies de SELECT (drop+create en la misma transaccion); no toca filas.
-- REVERTIR:
--   drop policy "mapeo cuentas: agentes" on public.plantilla_cuentas; create policy "mapeo cuentas: solo con sesion" on public.plantilla_cuentas for select to authenticated, lw_lector using (true);
--   drop policy "cuentas por proyecto: agentes" on public.proyecto_cuentas; create policy "cuentas por proyecto: solo con sesion" on public.proyecto_cuentas for select to authenticated, lw_lector using (true);
drop policy "mapeo cuentas: solo con sesion" on public.plantilla_cuentas;
create policy "mapeo cuentas: agentes" on public.plantilla_cuentas for select to authenticated, lw_lector using (public.es_agente());
drop policy "cuentas por proyecto: solo con sesion" on public.proyecto_cuentas;
create policy "cuentas por proyecto: agentes" on public.proyecto_cuentas for select to authenticated, lw_lector using (public.es_agente());
