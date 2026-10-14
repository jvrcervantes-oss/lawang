-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Calendario de pagos: un % de hito con EXACTAMENTE 3 decimales se rechaza (14-oct-2026).
-- Porque: public.lw_importe('12.123') = 12123 (lo lee como miles) y la pantalla, con parseFloat, 12.123. Mismo dato,
-- dos lecturas (reference_dos_parsers_para_el_mismo_importe). Hasta hoy nadie lo tecleaba (medido el 14-oct: ningun
-- hito guardado tiene mas de 2 decimales), pero desde hoy el % puede salir de una cantidad tecleada (hasta 8 decimales)
-- y la pantalla ya lo guarda con 4 (pctSeguro, contracts/assets/hitos_fechas.js). Esto cierra la puerta a quien no pase
-- por la pantalla. Solo la rama 'libre'/no-calendario de contrato_calendario_aplica: las otras rehacen los hitos.
-- destructivo-ok: create or replace de una funcion; sin borrar datos
-- REVERTIR: quitar el bloque «if exists ... 3 decimales» con el mismo parche al reves.

create or replace function pg_temp.parchea(f regprocedure, viejo text, nuevo text) returns void language plpgsql as $$
declare d text := pg_get_functiondef(f); n int;
begin
  n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
  if n <> 1 then raise exception 'parchea %: «%» aparece % veces (esperaba 1)', f, left(viejo, 60), n; end if;
  execute replace(d, viejo, nuevo);
end $$;

select pg_temp.parchea('public.contrato_calendario_aplica(jsonb,jsonb,numeric,date,uuid)'::regprocedure,
  $q$    select sum(public.lw_importe(h->>'pct')) into v_suma$q$,
  $q$    if exists (select 1 from jsonb_array_elements(v_hitos) h where coalesce(h->>'pct', '') ~ '^\s*\d*[.,]\d{3}\s*$') then
      raise exception 'Un %% de hito con exactamente 3 decimales se leería como miles: usa 2 o 4 decimales.' using errcode = '22023';
    end if;
    select sum(public.lw_importe(h->>'pct')) into v_suma$q$);
