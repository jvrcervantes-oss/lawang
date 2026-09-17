-- Funciones para gobernar el estado del proyecto y sus plazos.
-- encargos/20260917_lawang_vencimientos_obra.md

-- ---------------------------------------------------------------------------
-- proyecto_pct_vendido: version inicial (solo vendida/cobrada). Corregida en
-- 20260917150920 para contar tambien las bloqueadas -- ver alli el motivo.
-- ---------------------------------------------------------------------------
create or replace function public.proyecto_pct_vendido(p_proyecto_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select case when count(*) = 0 then 0
              else round(100.0 * count(*) filter (where u.estado in ('vendida','cobrada')) / count(*), 2)
         end
    from public.unidades u
   where u.proyecto_id = p_proyecto_id;
$$;

revoke all on function public.proyecto_pct_vendido(uuid) from public, anon;
grant execute on function public.proyecto_pct_vendido(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- proyecto_cambiar_estado: la palanca manual. Editar proyectos ya era cosa de
-- admin (policy "admin desactiva proyectos"), asi que se mantiene ese mismo
-- liston en vez de abrir uno nuevo.
-- Pasar a `en_construccion` exige llegar al umbral de venta del proyecto; por
-- debajo se puede forzar, pero solo a proposito (p_forzar) y con motivo, y
-- queda escrito en proyecto_eventos.
-- ---------------------------------------------------------------------------
create or replace function public.proyecto_cambiar_estado(
  p_proyecto_id uuid,
  p_estado text,
  p_forzar boolean default false,
  p_motivo text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nombre text;
  v_estado_actual text;
  v_umbral numeric;
  v_pct numeric;
  v_quien text;
begin
  select nombre, estado, pct_minimo_inicio
    into v_nombre, v_estado_actual, v_umbral
    from public.proyectos where id = p_proyecto_id;

  if v_nombre is null then
    raise exception 'Proyecto no encontrado';
  end if;

  if not public.es_admin() then
    raise exception 'Solo un admin cambia el estado de un proyecto' using errcode = '42501';
  end if;

  if p_estado not in ('en_venta','no_disponible','en_construccion','construido',
                      'finalizado','gestionado','stand_by','cedido') then
    raise exception 'Estado desconocido: %', p_estado;
  end if;

  if p_estado = v_estado_actual then
    return v_estado_actual; -- idempotente
  end if;

  v_quien := (select auth.email());
  v_pct := public.proyecto_pct_vendido(p_proyecto_id);

  if p_estado = 'en_construccion' and v_pct < v_umbral then
    if not coalesce(p_forzar, false) then
      raise exception
        'El proyecto lleva vendido un %%% y hace falta un %%% para iniciar la construccion. Si aun asi hay que iniciarlo, hazlo explicitamente indicando el motivo.',
        v_pct, v_umbral;
    end if;
    if coalesce(btrim(p_motivo), '') = '' then
      raise exception 'Forzar el inicio por debajo del umbral exige un motivo escrito';
    end if;
    insert into public.proyecto_eventos (proyecto_id, evento, detalle, quien)
    values (p_proyecto_id, 'inicio_forzado_bajo_umbral',
            jsonb_build_object('pct_vendido', v_pct, 'umbral', v_umbral, 'motivo', p_motivo),
            v_quien);
  end if;

  update public.proyectos set estado = p_estado where id = p_proyecto_id;

  insert into public.proyecto_eventos (proyecto_id, evento, detalle, quien)
  values (p_proyecto_id, 'estado_cambiado',
          jsonb_strip_nulls(jsonb_build_object(
            'de', v_estado_actual, 'a', p_estado,
            'pct_vendido', v_pct, 'motivo', p_motivo)),
          v_quien);

  return p_estado;
end;
$$;

revoke all on function public.proyecto_cambiar_estado(uuid,text,boolean,text) from public, anon;
grant execute on function public.proyecto_cambiar_estado(uuid,text,boolean,text) to authenticated;

-- ---------------------------------------------------------------------------
-- proyecto_fijar_plazo: configura los dias de uno de los 5 pagos del proyecto.
-- ---------------------------------------------------------------------------
create or replace function public.proyecto_fijar_plazo(
  p_proyecto_id uuid,
  p_orden_pago int,
  p_dias int
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nombre text;
begin
  select nombre into v_nombre from public.proyectos where id = p_proyecto_id;
  if v_nombre is null then
    raise exception 'Proyecto no encontrado';
  end if;
  if not public.es_admin() then
    raise exception 'Solo un admin configura los plazos de un proyecto' using errcode = '42501';
  end if;
  if p_orden_pago is null or p_orden_pago < 1 or p_orden_pago > 5 then
    raise exception 'El pago debe ser del 1 al 5 (recibido: %)', p_orden_pago;
  end if;
  if p_dias is null or p_dias < 0 or p_dias > 365 then
    raise exception 'Los dias deben estar entre 0 y 365 (recibido: %)', p_dias;
  end if;

  insert into public.proyecto_plazo_pago (proyecto_id, orden_pago, dias, actualizado_por)
  values (p_proyecto_id, p_orden_pago, p_dias, (select auth.email()))
  on conflict (proyecto_id, orden_pago)
  do update set dias = excluded.dias,
                actualizado_en = now(),
                actualizado_por = excluded.actualizado_por;
end;
$$;

revoke all on function public.proyecto_fijar_plazo(uuid,int,int) from public, anon;
grant execute on function public.proyecto_fijar_plazo(uuid,int,int) to authenticated;
