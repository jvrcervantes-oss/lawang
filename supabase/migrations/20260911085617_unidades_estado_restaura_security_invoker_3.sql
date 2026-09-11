-- destructivo-ok: no destruye datos -- solo repone security_invoker en una
-- vista de solo lectura. 3a reincidencia del mismo fallo (10-ago, 2-sep,
-- 11-sep): CREATE OR REPLACE VIEW resetea reloptions si no se repite el
-- `alter view ... set (security_invoker = true)` en la MISMA tarea que toca
-- la vista. Esta vez fue al anadir cobrado_suelo/cobrado_obra/obra_firmada
-- (v4/proyectos, barra de recaudacion por parcela). Verificado antes de que
-- llegara a produccion: reloptions volvia a NULL tras el CREATE OR REPLACE.
alter view public.unidades_estado set (security_invoker = true);
