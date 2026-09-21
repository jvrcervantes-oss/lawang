-- destructivo-ok: el DROP es de obra_datos_cobro(), creada hace dos minutos en la
-- migracion inmediatamente anterior y que NO usa todavia ninguna pantalla ni
-- ningun dato -- se recrea entera en esta misma migracion. Hace falta DROP porque
-- cambia el tipo de dos columnas de salida (precio_total text -> numeric), y
-- Postgres no deja cambiar el tipo de retorno con CREATE OR REPLACE.
--
-- El porque del cambio: precio_total y moneda se leen ahora de las COLUMNAS de
-- `contratos` (numeric y text) y no de datos->fields. En el jsonb el precio es
-- texto ya formateado ("76.500") y Number() lo leeria como 76,5 -- tres ordenes
-- de magnitud de error en una pantalla que dispara cobros.
drop function if exists public.obra_datos_cobro(uuid,text,text,text);

create function public.obra_datos_cobro(
  p_proyecto_id uuid,
  p_fase_masterplan text,
  p_zona_masterplan text,
  p_fase_nueva text
)
returns table (
  contrato_id uuid,
  numero text,
  moneda text,
  precio_total numeric,
  cobrado numeric,
  vencimientos jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_proyecto_nombre text;
begin
  select nombre into v_proyecto_nombre from public.proyectos where id = p_proyecto_id;
  if v_proyecto_nombre is null then
    raise exception 'Proyecto no encontrado';
  end if;
  -- Mismo gate, palabra por palabra, que obra_contratos_afectados().
  if not (public.puede('obra') and public.puede_proyecto(v_proyecto_nombre)) then
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
$$;

revoke all on function public.obra_datos_cobro(uuid,text,text,text) from public, anon;
grant execute on function public.obra_datos_cobro(uuid,text,text,text) to authenticated;

comment on function public.obra_datos_cobro(uuid,text,text,text) is
  'Datos de dinero (precio, cobrado efectivo y vencimientos) de los contratos de un tramo de obra, con el MISMO gate que obra_contratos_afectados. Existe para que la vista previa de un parte de trabajo no mezcle dos alcances distintos y deje importes en blanco sin decirlo.';;
