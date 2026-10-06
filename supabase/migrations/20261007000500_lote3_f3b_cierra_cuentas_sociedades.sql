-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 3 · F3 fase B (OK del owner 6-oct-2026): las 4 tablas dejan de ser legibles por cualquier sesion; solo el equipo (es_agente()).
--   El comprador del portal recibe lo suyo por cuentas_cobro_visibles()/sociedades_visibles() (fase A, publicada y verificada en produccion 7-oct;
--   38 compradores con acceso comprobados con contenido identico). plantilla_cuentas y proyecto_cuentas no las lee el portal.
-- destructivo-ok: sustituye 4 policies de SELECT (drop+create en la misma transaccion); no toca filas.
-- REVERTIR (policies previas, roles {authenticated,lw_lector}, using true):
--   drop policy "cuentas: agentes" on public.cuentas_bancarias; create policy "cuentas: solo con sesion" on public.cuentas_bancarias for select to authenticated, lw_lector using (true);
--   drop policy "mapeo cuentas: agentes" on public.plantilla_cuentas; create policy "mapeo cuentas: solo con sesion" on public.plantilla_cuentas for select to authenticated, lw_lector using (true);
--   drop policy "cuentas por proyecto: agentes" on public.proyecto_cuentas; create policy "cuentas por proyecto: solo con sesion" on public.proyecto_cuentas for select to authenticated, lw_lector using (true);
--   drop policy "sociedades: agentes" on public.sociedades; create policy "sociedades: leer" on public.sociedades for select to authenticated, lw_lector using (true);
drop policy "cuentas: solo con sesion" on public.cuentas_bancarias;
create policy "cuentas: agentes" on public.cuentas_bancarias for select to authenticated, lw_lector using (public.es_agente());
drop policy "mapeo cuentas: solo con sesion" on public.plantilla_cuentas;
create policy "mapeo cuentas: agentes" on public.plantilla_cuentas for select to authenticated, lw_lector using (public.es_agente());
drop policy "cuentas por proyecto: solo con sesion" on public.proyecto_cuentas;
create policy "cuentas por proyecto: agentes" on public.proyecto_cuentas for select to authenticated, lw_lector using (public.es_agente());
drop policy "sociedades: leer" on public.sociedades;
create policy "sociedades: agentes" on public.sociedades for select to authenticated, lw_lector using (public.es_agente());
