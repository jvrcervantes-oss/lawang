-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Descuento comercial: el agente tambien lo pone (14-oct-2026, owner: «abrirlo como sales manager»).
-- Hasta hoy descuento_comercial_rol solo dejaba cambiar descuento_comercial y su motivo a super_admin, admin,
-- sales_manager y al admin de la empresa de la fila. Se anade 'agente' a la lista. El tope NO cambia: lo ponen
-- descuento_comercial_suelo_valido / _construccion_valido (15 % para quien no es admin de la empresa, 50 % admin,
-- super sin tope) y siguen exigiendo motivo. project_manager sigue fuera (no crea ni edita contratos).
-- Pantalla: ROLES_DESCUENTO en contracts/app.html, misma lista.
-- Se PARCHA el texto vivo (conserva la exencion por empresa de f2_b1_2); cada cambio debe aparecer exactamente una vez.
-- destructivo-ok: create or replace de una funcion; sin borrar datos
-- REVERTIR: el mismo parche al reves (quitar 'agente' de la lista y devolver el mensaje anterior).

create or replace function pg_temp.parchea(f regprocedure, viejo text, nuevo text) returns void language plpgsql as $$
declare d text := pg_get_functiondef(f); n int;
begin
  n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
  if n <> 1 then raise exception 'parchea %: «%» aparece % veces (esperaba 1)', f, left(viejo, 60), n; end if;
  execute replace(d, viejo, nuevo);
end $$;

select pg_temp.parchea('public.descuento_comercial_rol()'::regprocedure,
  $q$if v_rol in ('super_admin', 'admin', 'sales_manager') or$q$,
  $q$if v_rol in ('super_admin', 'admin', 'sales_manager', 'agente') or$q$);
select pg_temp.parchea('public.descuento_comercial_rol()'::regprocedure,
  $q$solo los ponen dirección y los sales managers.$q$,
  $q$solo los ponen dirección, los sales managers y los agentes.$q$);

comment on function public.descuento_comercial_rol() is
  'BEFORE INSERT OR UPDATE en contratos: solo super_admin/admin/sales_manager/agente (y el admin de la empresa de la fila) cambian descuento_comercial y su motivo. Sin sesión no aplica. 25-sep-2026; agente desde 14-oct-2026, owner.';
