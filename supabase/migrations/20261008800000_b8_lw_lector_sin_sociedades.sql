-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- LAW-496 · bloque 8 (7-oct-2026): lw_lector deja de leer la tabla `sociedades`. El invariante «lw_lector es un lector» lo marcaba (b): la leia aunque authenticated solo lee 17 columnas.
--   Sin llamador con nombre (comprobado en produccion 7-oct): ninguna funcion de lw_lector (22) ni vista ni policy ajena ni funcion INVOKER que ejecute lw_lector lee `sociedades`;
--   las RPC que la leen son DEFINER de postgres (sociedades_ajustes_datos, sociedades_visibles...). El SELECT de tabla venia de la creacion (AXW-116 lo dejo «por si»). Reducir la exposicion.
-- destructivo-ok: solo quita un privilegio de lectura; no toca filas
-- REVERTIR: grant select on public.sociedades to lw_lector;
revoke select on public.sociedades from lw_lector;
