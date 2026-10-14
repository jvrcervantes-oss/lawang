-- Aplicada en Supabase Lawang como 20261014130410_retira_unidad_parte_cobrada (14-oct-2026, con la marca del owner y su
-- permiso en la sesión). Mismo SQL que supabase/vivo/20261014_cobro_primero_parcela/f6_retira_parte_cobrada.sql;
-- vuelta atrás en vuelta_f6.sql de esa carpeta. Verificado tras aplicar: 0 funciones con esos nombres en public.
-- destructivo-ok: F6/LAW-590: borrar 2 funciones sin llamador, decisión del owner 14-oct ~21:10
-- F6 (LAW-590), owner 14-oct-2026: borrar las dos funciones sin llamador (detalle y vuelta atrás en
-- supabase/vivo/20261014_cobro_primero_parcela/f6_retira_parte_cobrada.sql y vuelta_f6.sql).
drop function public.unidad_parte_cobrada(uuid);
drop function public.unidad_parte_cobrada_split(uuid);
