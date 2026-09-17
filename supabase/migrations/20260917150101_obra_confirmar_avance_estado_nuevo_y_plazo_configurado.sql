-- Enlaza obra_confirmar_avance con las decisiones del owner del 17-sep:
--   · el candado pasa de 'construccion' a 'en_construccion' (estados nuevos).
--   · p_dias ahora puede venir NULL: entonces se usa el plazo configurado del proyecto para
--     ese pago (proyecto_plazo_pago). Si tampoco hay configurado, se rechaza con un mensaje
--     que dice exactamente que falta -- nunca se inventa un plazo por defecto, que seria
--     poner una fecha de cobro real a ojo.
--   La firma no cambia (p_dias sigue en su sitio), asi que no hay funcion duplicada.

create or replace function public.obra_confirmar_avance(
  p_proyecto_id uuid,
  p_fase_masterplan text,
  p_zona_masterplan text,
  p_fase_nueva text,
  p_dias int,
  p_nota text,
  p_contratos_esperados uuid[]
)
returns table (contrato_id uuid, numero text, fecha_vencimiento date)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_proyecto_nombre text;
  v_estado text;
  v_orden_pago int;
  v_dias int;
  v_fase_actual text;
  v_orden_actual int;
  v_orden_nuevo int;
  v_contratos uuid[];
  v_esperados uuid[];
  v_autor text;
  v_dia date;
  v_usadas int;
  r record;
begin
  select nombre, estado into v_proyecto_nombre, v_estado
    from public.proyectos where id = p_proyecto_id;
  if v_proyecto_nombre is null then
    raise exception 'Proyecto no encontrado';
  end if;
  if not (public.puede('obra') and public.puede_proyecto(v_proyecto_nombre)) then
    raise exception 'Sin permiso sobre este proyecto' using errcode = '42501';
  end if;
  if v_estado <> 'en_construccion' then
    raise exception 'El proyecto no esta en construccion todavia (estado actual: %)', v_estado;
  end if;
  if coalesce(p_fase_masterplan,'') = '' or coalesce(p_zona_masterplan,'') = '' then
    raise exception 'Fase y zona de masterplan son obligatorias';
  end if;
  select op.orden_pago into v_orden_pago
    from public.obra_fase_orden_pago op where op.obra_fase_clave = p_fase_nueva;
  if v_orden_pago is null then
    raise exception 'Fase de obra desconocida: %', p_fase_nueva;
  end if;

  -- El plazo: el que se pase explicitamente manda; si no, el configurado en la ficha
  -- del proyecto para ese pago. Si no hay ninguno, no se adivina.
  v_dias := p_dias;
  if v_dias is null then
    select dias into v_dias
      from public.proyecto_plazo_pago
     where proyecto_id = p_proyecto_id and orden_pago = v_orden_pago;
  end if;
  if v_dias is null then
    raise exception 'No hay plazo configurado para el pago % de este proyecto, y no se ha indicado ninguno al confirmar', v_orden_pago;
  end if;
  if v_dias < 0 then
    raise exception 'El desfase en dias no puede ser negativo';
  end if;
  if v_dias > 365 then
    raise exception 'El desfase en dias (%) supera el tope de 365 -- si de verdad hace falta ir mas lejos, confirmalo aparte', v_dias;
  end if;

  select obra_fase_actual into v_fase_actual
    from public.obra_progreso_fase_zona
   where proyecto_id = p_proyecto_id and fase_masterplan = p_fase_masterplan
     and zona_masterplan = p_zona_masterplan;

  if v_fase_actual is not distinct from p_fase_nueva then
    return; -- idempotente: ya esta en esa fase
  end if;

  if v_fase_actual is null then
    if p_fase_nueva <> 'preparacion' then
      raise exception 'Una fase-zona nueva solo puede arrancar en preparacion, no en %', p_fase_nueva;
    end if;
  else
    select orden into v_orden_actual from public.obra_fases where clave = v_fase_actual;
    select orden into v_orden_nuevo from public.obra_fases where clave = p_fase_nueva;
    if v_orden_nuevo is distinct from v_orden_actual + 1 then
      raise exception 'Solo se puede avanzar un paso de obra cada vez (actual: % [orden %]; pedido: % [orden %])',
        v_fase_actual, v_orden_actual, p_fase_nueva, v_orden_nuevo;
    end if;
  end if;

  select coalesce(array_agg(contrato_id order by contrato_id), '{}'::uuid[]) into v_contratos
    from public.obra_contratos_afectados(p_proyecto_id, p_fase_masterplan, p_zona_masterplan, p_fase_nueva)
   where elegible;

  select coalesce(array_agg(x order by x), '{}'::uuid[]) into v_esperados
    from unnest(coalesce(p_contratos_esperados, '{}'::uuid[])) x;

  if v_contratos <> v_esperados then
    raise exception 'La lista de contratos afectados cambio desde la vista previa -- vuelve a comprobarla antes de confirmar' using errcode = '40001';
  end if;

  v_autor := (select auth.email());

  insert into public.obra_partes_trabajo
    (proyecto_id, fase_masterplan, zona_masterplan, fase_anterior, fase_nueva, autor, nota, dias_offset)
  values (p_proyecto_id, p_fase_masterplan, p_zona_masterplan, v_fase_actual, p_fase_nueva, v_autor, p_nota, v_dias);

  insert into public.obra_progreso_fase_zona
    (proyecto_id, fase_masterplan, zona_masterplan, obra_fase_actual, actualizado_por)
  values (p_proyecto_id, p_fase_masterplan, p_zona_masterplan, p_fase_nueva, v_autor)
  on conflict (proyecto_id, fase_masterplan, zona_masterplan)
  do update set obra_fase_actual = excluded.obra_fase_actual,
                actualizado_en = now(),
                actualizado_por = excluded.actualizado_por;

  for r in
    select c.id as contrato_id, c.numero, a.vencimiento_id
    from public.obra_contratos_afectados(p_proyecto_id, p_fase_masterplan, p_zona_masterplan, p_fase_nueva) a
    join public.contratos c on c.id = a.contrato_id
    where a.elegible
    order by c.numero
  loop
    v_dia := current_date + v_dias;
    loop
      select count(*) into v_usadas
        from public.contrato_vencimientos cv2
       where cv2.fecha = v_dia and cv2.factura_id is null;
      exit when v_usadas < 8;
      v_dia := v_dia + 1;
    end loop;

    update public.contrato_vencimientos
       set fecha = v_dia,
           ajustado = true,
           origen = 'obra'
     where id = r.vencimiento_id;

    contrato_id := r.contrato_id;
    numero := r.numero;
    fecha_vencimiento := v_dia;
    return next;
  end loop;
end;
$$;

revoke all on function public.obra_confirmar_avance(uuid,text,text,text,int,text,uuid[]) from public, anon;
grant execute on function public.obra_confirmar_avance(uuid,text,text,text,int,text,uuid[]) to authenticated;
