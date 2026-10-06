-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 3 · F4 (OK del owner 6-oct-2026): los modelos SIN publicar (y sus techos) solo los lee quien trabaja con ellos:
--   admin/super_admin o herramienta modelos, contratos, creatividades, creatividades_ver o dossier (creatividades_ver añadida
--   tras revisar panel-creatividades.js:234, que lo lee con solo esa herramienta). modelos_villa NO se toca: ya filtra por proyecto.
-- destructivo-ok: solo cambia dos policies de SELECT; no toca filas. Hoy ningun usuario activo queda fuera de la lista.
-- REVERTIR: drop policy "modelos: leer" on public.modelos; create policy "modelos: leer" on public.modelos for select to authenticated, lw_lector using (public.es_agente());
--           drop policy "techos: leer" on public.modelo_techos; create policy "techos: leer" on public.modelo_techos for select to authenticated, lw_lector using (public.es_agente());
drop policy "modelos: leer" on public.modelos;
create policy "modelos: leer" on public.modelos for select to authenticated, lw_lector
  using (public.es_agente() and (publicado or public.es_admin() or public.puede('modelos') or public.puede('contratos')
         or public.puede('creatividades') or public.puede('creatividades_ver') or public.puede('dossier')));
drop policy "techos: leer" on public.modelo_techos;
create policy "techos: leer" on public.modelo_techos for select to authenticated, lw_lector
  using (public.es_agente() and exists (select 1 from public.modelos m where m.id = modelo_techos.modelo_id));
