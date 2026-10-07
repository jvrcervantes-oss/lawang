-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · cierre · bloque 6 · migracion 5 (8-oct-2026): los FICHEROS de una creatividad (bucket «creatividades») tambien acotados por empresa.
--   privado.creatividad_ve_fichero es SECURITY DEFINER (se salta la RLS de creatividades que acaba de acotar la migracion 3): sin esto, quien tiene la casilla y alcance por empresa
--   leeria el PNG/estado de una creatividad de la OTRA empresa si conoce la ruta. Misma regla: sin proyecto o de otra empresa = no. Para los 34 de hoy (sin alcance por empresa) no cambia nada.
-- destructivo-ok: create or replace de una funcion; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b6.sql (PARTE 5)

create or replace function pg_temp.parchea(p_f regprocedure, p_old text, p_new text, p_n int default 1) returns void language plpgsql as $f$
declare v text; v_c int;
begin
  v := pg_get_functiondef(p_f);
  v_c := (length(v) - length(replace(v, p_old, ''))) / length(p_old);
  if v_c <> p_n then
    raise exception 'parche f2_b6: «%» aparece % veces en %, esperaba %', p_old, v_c, p_f, p_n;
  end if;
  execute replace(v, p_old, p_new);
end $f$;

select pg_temp.parchea('privado.creatividad_ve_fichero(text)'::regprocedure,
  $q$and public.creatividad_puede_ver(c.tipo, c.estado)$q$,
  $q$and public.creatividad_puede_ver(c.tipo, c.estado)
       and (not public.alcance_restringido() or (c.proyecto_id is not null and public.proyecto_en_alcance(c.proyecto_id)))$q$);
