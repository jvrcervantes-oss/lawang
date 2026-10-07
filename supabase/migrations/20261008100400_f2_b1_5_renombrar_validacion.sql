-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · cierre · bloque 1 · migracion 5 (8-oct-2026): renombrar_proyecto, ahora alcanzable por un admin de empresa, valida el nombre como proyecto_alta (largo y no empezar por = + - @, anti-formula de Excel).
-- destructivo-ok: create or replace de una funcion; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b1.sql (PARTE 5)
create or replace function pg_temp.parchea(p_f regprocedure, p_old text, p_new text, p_n int default 1) returns void language plpgsql as $f$
declare v text; v_c int;
begin
  v := pg_get_functiondef(p_f);
  v_c := (length(v) - length(replace(v, p_old, ''))) / length(p_old);
  if v_c <> p_n then
    raise exception 'parche f2_b1: «%» aparece % veces en %, esperaba %', p_old, v_c, p_f, p_n;
  end if;
  execute replace(v, p_old, p_new);
end $f$;
select pg_temp.parchea('public.renombrar_proyecto(text,text)'::regprocedure,
  $q$if exists (select 1 from public.proyectos where nombre = p_nuevo) then$q$,
  $q$if length(btrim(p_nuevo)) > 120 then raise exception 'El nombre no puede pasar de 120 caracteres' using errcode = '22023'; end if;
  if btrim(p_nuevo) ~ '^[=+\-@]' then raise exception 'El nombre no puede empezar por = + - @' using errcode = '22023'; end if;
  if exists (select 1 from public.proyectos where nombre = p_nuevo) then$q$);
