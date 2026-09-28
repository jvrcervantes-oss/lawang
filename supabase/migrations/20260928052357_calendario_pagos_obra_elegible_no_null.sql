-- destructivo-ok: reemplaza obra_contratos_afectados con la misma firma.
-- Arreglo de 20260928052131 (calendario de pagos de Construcción), cazado por contracts/sql/prueba_calendario_pagos.sql
-- (bloque 4) nada más aplicarla: para un contrato sin calendario deducible (los de antes del 16-sep) `elegible` salía
-- NULL en vez de false — la comparación con un calendario NULL da NULL. La previa del parte de obra lo trataba como
-- falso, pero una lista de «¿se cobra?» tiene que decir «no», no «no sé».
create or replace function public.obra_contratos_afectados(p_proyecto_id uuid, p_fase_masterplan text,
                                                           p_zona_masterplan text, p_fase_nueva text)
returns table (contrato_id uuid, numero text, elegible boolean, motivo text, orden_pago integer,
               vencimiento_id uuid, fecha_actual date)
language plpgsql stable security definer set search_path = '' as $$
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
         from jsonb_array_elements(coalesce(c.datos->'hitos','[]'::jsonb)) h) as todos_fijos,
      (select bool_or(coalesce((h->>'fijo')::boolean,false))
         from jsonb_array_elements(coalesce(c.datos->'hitos','[]'::jsonb)) h) as algun_fijo,
      nullif(c.datos->>'calendario', '') as cal
    from public.contratos c
    join public.unidades u on u.id = c.unidad_id
     and u.proyecto_id = p_proyecto_id
     and u.fase_masterplan = p_fase_masterplan
     and u.zona_masterplan = p_zona_masterplan
    left join public.contrato_vencimientos cv on cv.contrato_id = c.id and cv.orden = v_orden
    where c.tipo = 'construccion' and c.bloqueado = true
  ), clase as (
    select b.*,
      coalesce(b.cal, case when b.n_hitos = 5 and coalesce(b.todos_fijos,false) then 'estandar' end) as calendario,
      (b.venc_id is not null and not b.ajustado and b.factura_id is null) as libre_para_fijar
    from base b
  )
  select
    k.id,
    k.numero,
    coalesce(k.libre_para_fijar
      and ((k.calendario = 'estandar' and k.n_hitos = 5 and coalesce(k.todos_fijos,false))
           or (k.calendario = 'unico_obra' and v_orden = 1)), false) as elegible,
    (case
      when k.calendario = 'unico_firma' then 'pago_unico_firma'
      when k.calendario = 'unico_obra' and v_orden <> 1 then 'pago_unico_ya_al_inicio'
      when k.calendario = 'unico_obra' or (k.calendario = 'estandar' and k.n_hitos = 5 and coalesce(k.todos_fijos,false)) then
        case
          when k.venc_id is null then 'sin_vencimiento_en_ese_orden'
          when k.ajustado then 'ajustado_a_mano'
          when k.factura_id is not null then 'ya_facturado'
          else null
        end
      -- Sin ningún hito `fijo`: contrato anterior al calendario de fábrica del 16-sep. No es un calendario
      -- «a medida», es que se firmó antes.
      when k.n_hitos > 0 and not coalesce(k.algun_fijo,false) then 'anterior_al_mecanismo'
      else 'calendario_manual'
    end) as motivo,
    v_orden,
    k.venc_id,
    k.fecha
  from clase k;
end $$;
revoke all on function public.obra_contratos_afectados(uuid,text,text,text) from public, anon;
grant execute on function public.obra_contratos_afectados(uuid,text,text,text) to authenticated;
