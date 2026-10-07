-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 3 · F3 fase B, trozo 3 de 3: sociedades, solo el equipo (es_agente()); el comprador la recibe por sociedades_visibles() (fase A). Ver el trozo 1 sobre el nombre (LAW-496).
--   Luego la sustituye f2_b2_6 (por empresa) y 20260930220000 ya habia limitado las columnas de authenticated.
-- destructivo-ok: sustituye una policy de SELECT (drop+create en la misma transaccion); no toca filas.
-- REVERTIR: drop policy "sociedades: agentes" on public.sociedades; create policy "sociedades: leer" on public.sociedades for select to authenticated, lw_lector using (true);
drop policy "sociedades: leer" on public.sociedades;
create policy "sociedades: agentes" on public.sociedades for select to authenticated, lw_lector using (public.es_agente());
