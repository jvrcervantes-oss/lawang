-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 3 · F3 fase B (OK del owner 6-oct-2026), trozo 1 de 3: cuentas_bancarias deja de ser legible por cualquier sesion; solo el equipo (es_agente()).
--   El comprador del portal recibe lo suyo por cuentas_cobro_visibles() (fase A). Se aplico en tres trozos con estos nombres; antes vivia en un solo fichero
--   (lote3_f3b_cierra_cuentas_sociedades) que nunca se registro con ese nombre (LAW-496, 7-oct-2026): partido para que cada fichero case con lo aplicado.
-- destructivo-ok: sustituye una policy de SELECT (drop+create en la misma transaccion); no toca filas.
-- REVERTIR: drop policy "cuentas: agentes" on public.cuentas_bancarias; create policy "cuentas: solo con sesion" on public.cuentas_bancarias for select to authenticated, lw_lector using (true);
drop policy "cuentas: solo con sesion" on public.cuentas_bancarias;
create policy "cuentas: agentes" on public.cuentas_bancarias for select to authenticated, lw_lector using (public.es_agente());
