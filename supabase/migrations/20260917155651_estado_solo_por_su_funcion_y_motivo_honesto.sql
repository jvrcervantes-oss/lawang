-- Dos hallazgos de la consulta de deploy (Desarrollo, 17-sep) sobre la UI nueva.
--
-- 1) `proyectos.estado` podia cambiarse por UPDATE directo. La migracion que lo
--    creo dice "se cambia por proyecto_cambiar_estado(), nunca por UPDATE
--    directo" y nada lo impedia: verificado en produccion que authenticated Y
--    anon tenian GRANT UPDATE sobre esa columna, y la unica policy de UPDATE
--    (es_admin(), sin restriccion de columna) la deja pasar. O sea, un PATCH
--    desde la consola del navegador de cualquier admin se saltaba el umbral de
--    venta Y el rastro en proyecto_eventos, que existe justo para eso.
--    proyecto_cambiar_estado() no se ve afectada: es SECURITY DEFINER y su dueño
--    es postgres.
revoke update (estado) on public.proyectos from authenticated, anon;

-- 2) El motivo `calendario_manual` decia lo mismo de dos cosas distintas. Los 12
--    contratos de Construccion firmados hoy no tienen "un calendario a medida":
--    son ANTERIORES al calendario de fabrica del 16-sep, que es de donde salen
--    los flags `fijo`. Meterlos en el mismo saco que un calendario realmente
--    personalizado es como se cierra un aviso sin entenderlo. Se separan.
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
  with base as (
    select
      c.id, c.numero, cv.id as venc_id, cv.ajustado, cv.factura_id, cv.fecha,
      jsonb_array_length(coalesce(c.datos->'hitos','[]'::jsonb)) as n_hitos,
      (select bool_and(coalesce((h->>'fijo')::boolean,false))
         from jsonb_array_elements(coalesce(c.datos->'hitos','[]'::jsonb)) h) as todos_fijos
    from public.contratos c
    join public.unidades u on u.id = c.unidad_id
     and u.proyecto_id = p_proyecto_id
     and u.fase_masterplan = p_fase_masterplan
     and u.zona_masterplan = p_zona_masterplan
    left join public.contrato_vencimientos cv on cv.contrato_id = c.id and cv.orden = v_orden
    where c.tipo = 'construccion' and c.bloqueado = true
  )
  select
    b.id,
    b.numero,
    (b.venc_id is not null and b.n_hitos = 5 and coalesce(b.todos_fijos,false)
      and not b.ajustado and b.factura_id is null) as elegible,
    (case
      -- Sin ningun hito `fijo`: contrato anterior al calendario de fabrica del
      -- 16-sep. No es un calendario "a medida", es que se firmo antes.
      when coalesce(b.todos_fijos,false) = false and coalesce(b.n_hitos,0) > 0
           and not exists (
             select 1 from jsonb_array_elements(coalesce((select c2.datos->'hitos' from public.contratos c2 where c2.id = b.id),'[]'::jsonb)) h2
              where coalesce((h2->>'fijo')::boolean,false)
           )
        then 'anterior_al_mecanismo'
      when b.n_hitos <> 5 or coalesce(b.todos_fijos,false) = false then 'calendario_manual'
      when b.venc_id is null then 'sin_vencimiento_en_ese_orden'
      when b.ajustado then 'ajustado_a_mano'
      when b.factura_id is not null then 'ya_facturado'
      else null
    end) as motivo,
    v_orden,
    b.venc_id,
    b.fecha
  from base b;
end;
$$;

revoke all on function public.obra_contratos_afectados(uuid,text,text,text) from public, anon;
grant execute on function public.obra_contratos_afectados(uuid,text,text,text) to authenticated;;
