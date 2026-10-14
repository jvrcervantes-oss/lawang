-- VUELTA ATRÁS de f2_lectores.sql (F2 de «primero la parcela», 14-oct-2026). Copiado de producción
-- (pg_get_functiondef) justo antes de aplicar. Deja obra_datos_cobro y comision_admin_prevision como estaban y retira
-- las tres funciones nuevas. Antes de lanzarla, las pantallas tienen que haber vuelto a contratos_cobrado_equipo (si
-- no, Vencimientos y Finanzas caen solas a ella: el fallo de la RPC nueva ya está previsto en datos.js).
-- Retirar funciones es «destruir» para el guardia del estudio: necesita la marca del owner.
-- La otra migración de F2, 20261014104259_cobro_primero_parcela_carta_por_etapa (la cascada con «Carta» por etapa), se
-- deshace volviendo a aplicar _unidad_cobro_cascada tal como la deja supabase/migrations/20261014042207_cobro_primero_parcela_obra_firmada.sql
-- (la última definición anterior, comprobado el 14-oct). Ese día no cambiaba ninguna cifra (0 de 565 unidades).

CREATE OR REPLACE FUNCTION public.comision_admin_prevision()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pct numeric;
  v_out jsonb;
begin
  if not public.es_super_admin() then
    raise exception 'comision_admin_prevision: solo super_admin';
  end if;

  select t.pct into v_pct
    from public.comision_admin_tarifas t join public.empresas e on e.clave = t.empresa
   where t.efectivo_desde <= current_date
   order by e.orden, t.efectivo_desde desc
   limit 1;

  with vivos as (
    select coalesce(c.moneda, 'EUR') as moneda,
           c.bloqueado as firmado,
           coalesce(public._empresa_de_contrato_int(c.id), 'lawang') as emp,
           greatest(coalesce(c.precio_total, 0)
                    - public.contrato_cobrado(c.id)
                    - coalesce(public.lw_importe(c.datos->'fields'->>'carta_cobrado_importe'), 0), 0) as pendiente
      from public.contratos c
     where c.liberado_en is null
       and c.tipo not like 'carta_reserva%'
       and coalesce(c.precio_total, 0) > 0
       and (c.bloqueado or public.contrato_firma_viva(c.id))
  ), con_pct as (
    select v.*, (select t.pct from public.comision_admin_tarifas t
                  where t.empresa = v.emp and t.efectivo_desde <= current_date
                  order by t.efectivo_desde desc limit 1) as pct
      from vivos v
  ), por_moneda as (
    select moneda,
           count(*) filter (where firmado)                          as n_firmados,
           coalesce(sum(pendiente) filter (where firmado), 0)       as pend_firmados,
           count(*) filter (where not firmado)                      as n_en_firma,
           coalesce(sum(pendiente) filter (where not firmado), 0)   as pend_en_firma,
           bool_or(pct is null)                                     as falta_tarifa,
           coalesce(sum(pendiente * pct / 100), 0)                  as com_total,
           coalesce(sum(pendiente * pct / 100) filter (where firmado), 0) as com_firmados
      from con_pct group by moneda
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'moneda', moneda,
           'n_firmados', n_firmados, 'pendiente_firmados', pend_firmados,
           'n_en_firma', n_en_firma, 'pendiente_en_firma', pend_en_firma,
           'pendiente', pend_firmados + pend_en_firma,
           'comision', case when falta_tarifa then null else round(com_total, 2) end,
           'comision_firmados', case when falta_tarifa then null else round(com_firmados, 2) end
         ) order by moneda), '[]'::jsonb)
    into v_out
    from por_moneda;

  return jsonb_build_object('pct', v_pct, 'monedas', v_out);
end;
$function$;

CREATE OR REPLACE FUNCTION public.obra_datos_cobro(p_proyecto_id uuid, p_fase_masterplan text, p_zona_masterplan text, p_fase_nueva text)
 RETURNS TABLE(contrato_id uuid, numero text, moneda text, precio_total numeric, cobrado numeric, vencimientos jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_proyecto_nombre text;
begin
  select nombre into v_proyecto_nombre from public.proyectos where id = p_proyecto_id;
  if v_proyecto_nombre is null then
    raise exception 'Proyecto no encontrado';
  end if;
  -- Mismo gate, palabra por palabra, que obra_contratos_afectados().
  if not (public._puede_herr_o_super_empresa('obra') and public.puede_proyecto(v_proyecto_nombre)) then
    raise exception 'Sin permiso sobre este proyecto' using errcode = '42501';
  end if;

  return query
  select
    c.id,
    c.numero,
    c.moneda,
    c.precio_total,
    -- cobrado efectivo: lo del propio contrato mas lo de sus hijos PRELIMINARES
    -- (una Carta de Reserva que cuelga de el ya entrego dinero a cuenta de esta
    -- misma operacion). Mismos tipos que lwEsPreliminar en vocabulario.js.
    coalesce(public.contrato_cobrado(c.id), 0) + coalesce((
      select sum(coalesce(public.contrato_cobrado(h.id), 0))
        from public.contratos h
       where h.contrato_padre_id = c.id
         and h.tipo in ('carta_reserva','carta_reserva_ampliada','carta_reserva_hak_sewa',
                        'carta_reserva_pma','carta_reserva_investor_deck')
    ), 0),
    coalesce((
      select jsonb_agg(jsonb_build_object('orden', cv.orden, 'pct', cv.pct,
                                          'monto', cv.monto, 'fecha', cv.fecha)
                       order by cv.orden)
        from public.contrato_vencimientos cv where cv.contrato_id = c.id
    ), '[]'::jsonb)
  from public.contratos c
  join public.unidades u on u.id = c.unidad_id
   and u.proyecto_id = p_proyecto_id
   and u.fase_masterplan = p_fase_masterplan
   and u.zona_masterplan = p_zona_masterplan
  where c.tipo = 'construccion' and c.bloqueado = true;
end;
$function$;

drop function if exists public.contratos_cobrado_regla_equipo();
drop function if exists public._contrato_cobrado_venta(uuid);
drop function if exists public._venta_cobro_atribuido(uuid);
