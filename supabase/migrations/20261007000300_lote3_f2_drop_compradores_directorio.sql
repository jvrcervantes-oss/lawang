-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 3 · F2 paso (iii) (OK del owner 6-oct-2026): se retira el volcado de identidad. 0 llamadores (grep repo/edges/tools/panel, y 0 funciones de BD que la nombren);
--   el front nuevo (comprador_lista/buscar/ficha) esta publicado y verificado en produccion (curl de los 4 assets, 7-oct).
-- destructivo-ok: drop de una funcion de lectura sin llamadores; no toca filas. Definicion previa en supabase/reversion_lote3/REVERSION_lote3.sql.
drop function public.compradores_directorio();
