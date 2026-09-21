-- Cierre del hallazgo de advisors (get_advisors --security) tras la migración
-- 20260921193000: toda función pública en Postgres queda invocable por RPC vía
-- PostgREST salvo que se revoque -- y esta es una función DE TRIGGER, nunca
-- pensada para llamarse directa (referencia NEW, que solo existe dentro de un
-- disparo real). Se revoca aquí, no en el archivo original, siguiendo el mismo
-- patrón de "sección de permisos" que ya usan crm_contrato_closer_set y sus
-- hermanas en 20260911020137_crm_atribucion_ventas_y_ranking_closers.sql.
-- No afecta al disparo del trigger: Postgres invoca la función de trigger con
-- los privilegios del dueño de la función, no con el EXECUTE del rol que hizo
-- el INSERT.
revoke execute on function public.crm_contrato_closer_semilla() from public, anon, authenticated;
;
