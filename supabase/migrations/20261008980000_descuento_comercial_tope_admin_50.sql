-- Descuento comercial: tope por rol. 7-oct-2026, owner: «el límite de 15 % de descuento comercial aumentalo para
-- administradores hasta un 50 %». Antes: 15 % para todos salvo el super (sin tope, 29-sep; super de empresa, f2_b1_2).
-- Ahora: super sin tope · administrador 50 % · resto (sales_manager…) 15 %. «Administrador» = es_admin_de(empresa de la
-- fila): el admin global y el admin_empresa de esa empresa, el mismo criterio que ya usa descuento_comercial_rol.
-- Sin sesión (service role) el tope sigue en 15 %.
-- Se PARCHA el texto de las dos funciones vivas (no se reescriben): así conservan lo de LAW-494 y la exención por empresa
-- de 20261008100100. Cada cambio exige aparecer EXACTAMENTE una vez o la migración se para.

create or replace function pg_temp.parchea(f regprocedure, viejo text, nuevo text) returns void language plpgsql as $$
declare d text := pg_get_functiondef(f); n int;
begin
  n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
  if n <> 1 then raise exception 'parchea %: «%» aparece % veces (esperaba 1)', f, left(viejo, 60), n; end if;
  execute replace(d, viejo, nuevo);
end $$;

select pg_temp.parchea('public.descuento_comercial_construccion_valido()'::regprocedure,
  $q$round(v_base * 0.15, 2)$q$,
  $q$round(v_base * (case when public.es_admin_de(public._empresa_fila_contrato(new.proyecto_id, new.proyecto_nombre)) then 0.50 else 0.15 end), 2)$q$);
select pg_temp.parchea('public.descuento_comercial_construccion_valido()'::regprocedure,
  $q$supera el 15%% del precio de techo+extras$q$,
  $q$supera el tope de su rol (15%%, administración 50%%) del precio de techo+extras$q$);

select pg_temp.parchea('public.descuento_comercial_suelo_valido()'::regprocedure,
  $q$round(v_lista * 0.15, 2)$q$,
  $q$round(v_lista * (case when public.es_admin_de(public._empresa_fila_contrato(new.proyecto_id, new.proyecto_nombre)) then 0.50 else 0.15 end), 2)$q$);
select pg_temp.parchea('public.descuento_comercial_suelo_valido()'::regprocedure,
  $q$supera el 15%% del precio del suelo$q$,
  $q$supera el tope de su rol (15%%, administración 50%%) del precio del suelo$q$);
