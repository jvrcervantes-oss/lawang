-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Descuento comercial de Construcción: dos huecos de la base que encontró Seguridad (14-oct-2026) al abrir el descuento
-- al agente (20261014193000). Ya existían con sales_manager; ahora los alcanza cualquier agente.
--  (a) Motivo: solo lo exigía la pantalla; descuento_comercial_suelo_valido sí lo exige en la base, construccion_valido no.
--  (b) Sin techo: v_base queda NULL y `v_base > 0` dejaba pasar cualquier descuento sin tope (62 de 107 contratos de
--      Construcción no tienen techo). Ahora el tope se mide sobre precio_total + descuento (el precio antes de rebajar),
--      con el mismo % por rol y la misma exención del super. Limitación sabida: sin techo no hay precio de lista, y
--      precio_total lo manda la pantalla (en esos contratos ya se podía cambiar libremente antes de hoy); el tope
--      acota el descuento al 15 % de precio_total + descuento, no a un precio de referencia. Mejor que ninguno.
-- Medido el 14-oct: los 21 contratos de Construcción con descuento tienen motivo y techo; ninguno queda bloqueado.
-- destructivo-ok: create or replace de una funcion; sin borrar datos
-- REVERTIR: el mismo parche al reves (las dos frases nuevas por las viejas).

create or replace function pg_temp.parchea(f regprocedure, viejo text, nuevo text) returns void language plpgsql as $$
declare d text := pg_get_functiondef(f); n int;
begin
  n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
  if n <> 1 then raise exception 'parchea %: «%» aparece % veces (esperaba 1)', f, left(viejo, 60), n; end if;
  execute replace(d, viejo, nuevo);
end $$;

-- (a) motivo obligatorio cuando el descuento entra o cambia
select pg_temp.parchea('public.descuento_comercial_construccion_valido()'::regprocedure,
  $q$      or new.datos->'extras' is distinct from old.datos->'extras';
    if v_dc_cambia and v_base > 0$q$,
  $q$      or new.datos->'extras' is distinct from old.datos->'extras';
    -- también si solo se toca el motivo: vaciarlo en una segunda escritura no puede dejar un descuento sin él
    if (v_dc_cambia or (new.datos->'fields'->>'descuento_comercial_motivo') is distinct from (old.datos->'fields'->>'descuento_comercial_motivo'))
       and nullif(btrim(coalesce(new.datos->'fields'->>'descuento_comercial_motivo', '')), '') is null then
      raise exception 'Un descuento comercial necesita su motivo.' using errcode = '23514';
    end if;
    if v_dc_cambia and v_base > 0$q$);

-- (b) sin techo, el tope se mide sobre el precio antes del descuento
select pg_temp.parchea('public.descuento_comercial_construccion_valido()'::regprocedure,
  $q$    if v_dc_cambia and v_base > 0 and v_descuento > round(v_base *$q$,
  $q$    if v_dc_cambia and coalesce(v_base, coalesce(new.precio_total, 0) + v_descuento) > 0
       and v_descuento > round(coalesce(v_base, coalesce(new.precio_total, 0) + v_descuento) *$q$);
-- el mensaje enseña la base que se usó (sin techo, v_base era NULL)
select pg_temp.parchea('public.descuento_comercial_construccion_valido()'::regprocedure,
  $q$v_descuento, v_base;$q$,
  $q$v_descuento, coalesce(v_base, coalesce(new.precio_total, 0) + v_descuento);$q$);
