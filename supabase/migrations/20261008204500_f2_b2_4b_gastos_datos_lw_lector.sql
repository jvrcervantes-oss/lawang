-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 2 (DINERO) · migracion 4b (8-oct-2026): correccion cazada por el A/B de la foto (f2_foto_b2_ab.sql).
--   gasto_historial_datos y gastos_panel_datos (como todas las *_datos) son propiedad del rol lw_lector: corren con los permisos del lector y su RLS, y solo pueden llamar a funciones con EXECUTE
--   para lw_lector. La migracion 4 las dejo llamando a la puerta privada _gasto_puede(), y 4 admins con la casilla Gastos recibian «permission denied» (42501) donde antes recibian datos.
--   Aqui se cambia esa llamada por el envoltorio gastos_acceso() (mismo resultado, con EXECUTE para lw_lector). El fichero de la migracion 4 de este repo ya lleva el texto final.
--   panel_bancos_datos (tambien de lw_lector) se escribio ya bien en la migracion 5 (bancos_acceso, banco_comision_visible).
-- destructivo-ok: create or replace de dos funciones; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b2.sql
do $m$
declare f text; d text; viejo text := 'public._gasto_puede()'; nuevo text := 'public.gastos_acceso()'; n int;
begin
  foreach f in array array['public.gasto_historial_datos(uuid,integer)', 'public.gastos_panel_datos(integer,date,uuid)'] loop
    d := pg_get_functiondef(f::regprocedure);
    n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
    if n = 0 and position(nuevo in d) > 0 then continue; end if;   -- ya esta (el fichero de la migracion 4 lleva el texto final): nada que hacer
    if n <> 1 then raise exception '%: se esperaba 1 coincidencia y hay %', f, n; end if;
    execute replace(d, viejo, nuevo);
  end loop;
end $m$;
