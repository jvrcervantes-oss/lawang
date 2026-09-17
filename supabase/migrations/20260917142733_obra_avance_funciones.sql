-- Funciones de avance de fase-zona para el mecanismo de vencimientos por obra.
-- encargos/20260917_lawang_vencimientos_obra.md
-- No recalculan importes (esa regla vive en intranet/vencimientos/logica.js y su copia
-- empaquetada en la edge factura-vencimiento; no se triplica). Solo autorizan, calculan
-- la fecha y escriben -- el importe real que se factura lo sigue decidiendo esa misma pieza.

alter table public.obra_partes_trabajo
  add column dias_offset int;

comment on column public.obra_partes_trabajo.dias_offset is
  'Desfase en dias usado para este avance (hoy + dias_offset, repartido en lotes de 8). La UI propone por defecto el ultimo valor usado para este proyecto+orden_pago, sin tabla de configuracion aparte.';

-- ---------------------------------------------------------------------------
-- obra_contratos_afectados: solo lectura. Lista TODOS los contratos de Construccion
-- firmados de esa fase-zona, elegibles o no, con el motivo de exclusion visible --
-- nunca se descarta un contrato en silencio (mismo principio que la vista de huerfanos).
-- ---------------------------------------------------------------------------
create or replace function public.obra_contratos_afectados(
  p_proyecto_id uuid,
  p_fase_masterplan text,
  p_zona_masterplan text,
  p_fase_nueva text
)
returns table (
  contrato_id uuid,
  numero text,
  elegible boolean,
  motivo text,
  orden_pago int,
  vencimiento_id uuid,
  fecha_actual date
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_proyecto_nombre text;
  v_orden int;
begin
  select nombre into v_proyecto_nombre from public.proyectos where id = p_proyecto_id;
  if v_proyecto_nombre is null then
    raise exception 'Proyecto no encontrado';
  end if;
  if not (public.puede('obra') and public.puede_proyecto(v_proyecto_nombre)) then
    raise exception 'Sin permiso sobre este proyecto' using errcode = '42501';
  end if;
  if coalesce(p_fase_masterplan,'') = '' or coalesce(p_zona_masterplan,'') = '' then
    raise exception 'Fase y zona de masterplan son obligatorias';
  end if;

  select op.orden_pago into v_orden
    from public.obra_fase_orden_pago op where op.obra_fase_clave = p_fase_nueva;
  if v_orden is null then
    raise exception 'Fase de obra desconocida: %', p_fase_nueva;
  end if;

  return query
  select
    c.id,
    c.numero,
    (cv.id is not null
      and jsonb_array_length(coalesce(c.datos->'hitos','[]'::jsonb)) = 5
      and (select bool_and(coalesce((h->>'fijo')::boolean,false))
           from jsonb_array_elements(c.datos->'hitos') h)
      and not cv.ajustado
      and cv.factura_id is null
    ) as elegible,
    (case
      when not (jsonb_array_length(coalesce(c.datos->'hitos','[]'::jsonb)) = 5
                and (select bool_and(coalesce((h->>'fijo')::boolean,false))
                     from jsonb_array_elements(c.datos->'hitos') h))
        then 'calendario_manual'
      when cv.id is null then 'sin_vencimiento_en_ese_orden'
      when cv.ajustado then 'ajustado_a_mano'
      when cv.factura_id is not null then 'ya_facturado'
      else null
    end) as motivo,
    v_orden,
    cv.id,
    cv.fecha
  from public.contratos c
  join public.unidades u on u.id = c.unidad_id
   and u.proyecto_id = p_proyecto_id
   and u.fase_masterplan = p_fase_masterplan
   and u.zona_masterplan = p_zona_masterplan
  left join public.contrato_vencimientos cv on cv.contrato_id = c.id and cv.orden = v_orden
  where c.tipo = 'construccion' and c.bloqueado = true;
end;
$$;

revoke all on function public.obra_contratos_afectados(uuid,text,text,text) from public, anon;
grant execute on function public.obra_contratos_afectados(uuid,text,text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- obra_confirmar_avance: escribe. Revalida la lista de contratos elegibles contra
-- lo que el llamador vio en la vista previa (p_contratos_esperados) y rechaza si
-- ha cambiado -- nunca confia en lo que pinto el UI hace un rato.
-- ---------------------------------------------------------------------------
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
  v_fase_actual text;
  v_orden_actual int;
  v_orden_nuevo int;
  v_contratos uuid[];
  v_esperados uuid[];
  v_autor text;
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
  if v_estado <> 'construccion' then
    raise exception 'El proyecto no esta en construccion todavia (estado actual: %)', v_estado;
  end if;
  if coalesce(p_fase_masterplan,'') = '' or coalesce(p_zona_masterplan,'') = '' then
    raise exception 'Fase y zona de masterplan son obligatorias';
  end if;
  if p_dias is null or p_dias < 0 then
    raise exception 'El desfase en dias es obligatorio y no puede ser negativo';
  end if;

  select op.orden_pago into v_orden_pago
    from public.obra_fase_orden_pago op where op.obra_fase_clave = p_fase_nueva;
  if v_orden_pago is null then
    raise exception 'Fase de obra desconocida: %', p_fase_nueva;
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
  values (p_proyecto_id, p_fase_masterplan, p_zona_masterplan, v_fase_actual, p_fase_nueva, v_autor, p_nota, p_dias);

  insert into public.obra_progreso_fase_zona
    (proyecto_id, fase_masterplan, zona_masterplan, obra_fase_actual, actualizado_por)
  values (p_proyecto_id, p_fase_masterplan, p_zona_masterplan, p_fase_nueva, v_autor)
  on conflict (proyecto_id, fase_masterplan, zona_masterplan)
  do update set obra_fase_actual = excluded.obra_fase_actual,
                actualizado_en = now(),
                actualizado_por = excluded.actualizado_por;

  for r in
    select c.id as contrato_id, c.numero, a.vencimiento_id,
           (row_number() over (order by c.numero) - 1) as rn
    from public.obra_contratos_afectados(p_proyecto_id, p_fase_masterplan, p_zona_masterplan, p_fase_nueva) a
    join public.contratos c on c.id = a.contrato_id
    where a.elegible
  loop
    update public.contrato_vencimientos
       set fecha = current_date + p_dias + (r.rn / 8),
           ajustado = true,
           origen = 'obra'
     where id = r.vencimiento_id;

    contrato_id := r.contrato_id;
    numero := r.numero;
    fecha_vencimiento := current_date + p_dias + (r.rn / 8);
    return next;
  end loop;
end;
$$;

revoke all on function public.obra_confirmar_avance(uuid,text,text,text,int,text,uuid[]) from public, anon;
grant execute on function public.obra_confirmar_avance(uuid,text,text,text,int,text,uuid[]) to authenticated;
