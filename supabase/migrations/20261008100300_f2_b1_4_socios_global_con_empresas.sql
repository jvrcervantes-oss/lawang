-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · cierre · bloque 1 · migracion 4 (8-oct-2026): un admin/super GLOBAL con lista de empresas no queda restringido en socios (hallazgo de la consulta de Datos).
-- destructivo-ok: create or replace de funciones; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b1.sql (PARTE 4)
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
select pg_temp.parchea('public.socios_parcelas(uuid)'::regprocedure,
  $q$and (not public.alcance_restringido()$q$, $q$and (public.es_admin() or not public.alcance_restringido()$q$);
select pg_temp.parchea('public.unidad_socio_asigna(uuid,uuid,text)'::regprocedure,
  $q$if p_socio is not null and public.alcance_restringido() and not exists ($q$,
  $q$if p_socio is not null and not public.es_admin() and public.alcance_restringido() and not exists ($q$);
