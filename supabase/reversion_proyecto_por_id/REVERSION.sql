-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- REVERSION de 20261015214000_proyecto_por_id_intranet.sql (15-oct-2026, sesion proyecto-por-id, LAW-428 fase 2B).
-- ORDEN: 1) la intranet a su version anterior si ya llama a las *_por_id (fase 3), 2) ESTE fichero, en una transaccion.
-- Devuelve LITERALES las 5 recableadas a su cuerpo vivo del 15-oct (md5(prosrc) anotado) y borra las 5 nuevas (nadie mas las llama).
-- destructivo-ok: solo borra funciones que creo la migracion; no hay datos
set local lock_timeout = '5s';

-- carta_cobrado_al_bloquear(): md5(prosrc) vivo 15-oct = a37698f40a11073df89e56ac4656b783
CREATE OR REPLACE FUNCTION public.carta_cobrado_al_bloquear()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op <> 'INSERT' or new.tipo <> 'reserva_parcela' then
    return new;
  end if;
  new.datos := public.carta_cobrado_calcula(new.id, new.datos, new.proyecto_nombre);
  return new;
end $function$;

-- carta_cobrado_recalcula(uuid): md5(prosrc) vivo 15-oct = 3887e7ad9bb80e82a6be7fe7debf024c
CREATE OR REPLACE FUNCTION public.carta_cobrado_recalcula(p_contrato_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  c public.contratos%rowtype;
  v_datos jsonb;
begin
  if not public.es_admin_de(public.empresa_de_contrato(p_contrato_id)) then
    raise exception 'Recalcular el abono de la Carta exige admin.' using errcode = '42501';
  end if;
  select * into c from public.contratos where id = p_contrato_id;
  if c.id is null then raise exception 'Contrato no encontrado.' using errcode = 'P0002'; end if;
  if c.tipo <> 'reserva_parcela' then
    raise exception 'Solo se recalcula en un Bloqueo de Parcela.' using errcode = '22023';
  end if;
  if coalesce(c.bloqueado, false) or public.contrato_firma_viva(c.id) then
    raise exception 'El contrato está firmado o en firma: el abono impreso no se toca.' using errcode = '23514';
  end if;
  -- lo reclamado por este Bloqueo se suelta y se vuelve a calcular desde cero
  delete from public.carta_cobrado_aplicado where contrato_id = p_contrato_id;
  v_datos := public.carta_cobrado_calcula(c.id, c.datos, c.proyecto_nombre);
  perform set_config('app.via_carta_cobrado_recalcula', 'on', true);
  update public.contratos set datos = v_datos where id = p_contrato_id;
  insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
  values (p_contrato_id, 'editado',
          jsonb_build_object('accion', 'carta_cobrado_recalculado',
                             'importe', v_datos->'fields'->>'carta_cobrado_importe',
                             'numeros', v_datos->'fields'->>'carta_cobrado_numeros'),
          coalesce(public._quien_actua(), (select auth.uid())::text));
  return jsonb_build_object('carta_cobrado_importe', v_datos->'fields'->>'carta_cobrado_importe',
                            'carta_cobrado_numeros', v_datos->'fields'->>'carta_cobrado_numeros',
                            'carta_cobrado_sobrante', v_datos->'fields'->>'carta_cobrado_sobrante');
end $function$;

-- obra_contratos_afectados(uuid,text,text,text): md5(prosrc) vivo 15-oct = 75eb30f62103f376c02aa03a73e0f091
CREATE OR REPLACE FUNCTION public.obra_contratos_afectados(p_proyecto_id uuid, p_fase_masterplan text, p_zona_masterplan text, p_fase_nueva text)
 RETURNS TABLE(contrato_id uuid, numero text, elegible boolean, motivo text, orden_pago integer, vencimiento_id uuid, fecha_actual date)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_proyecto_nombre text;
  v_orden int;
begin
  select nombre into v_proyecto_nombre from public.proyectos where id = p_proyecto_id;
  if v_proyecto_nombre is null then
    raise exception 'Proyecto no encontrado';
  end if;
  if not (public._puede_herr_o_super_empresa('obra') and public.puede_proyecto(v_proyecto_nombre)) then
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
      when k.n_hitos > 0 and not coalesce(k.algun_fijo,false) then 'anterior_al_mecanismo'
      else 'calendario_manual'
    end) as motivo,
    v_orden,
    k.venc_id,
    k.fecha
  from clase k;
end $function$;

-- obra_datos_cobro(uuid,text,text,text): md5(prosrc) vivo 15-oct = 20a2809e046563c238b50f7dd243e56a
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
    -- Lo cobrado de esta Construcción contando su venta: primero la parcela, luego la obra (owner, 14-oct-2026).
    -- La puerta de arriba es por proyecto y ninguna venta tiene contratos en dos proyectos (Seguridad, 14-oct).
    public._contrato_cobrado_venta(c.id),
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

-- proyecto_guarda(uuid,jsonb): md5(prosrc) vivo 15-oct = d901439ef78cc51efed47fb7c4160d66
CREATE OR REPLACE FUNCTION public.proyecto_guarda(p_id uuid, p_cambios jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old public.proyectos%rowtype; v_fecha date; v_pct numeric; v_slug text;
begin
  if not public.es_admin_de(public.empresa_de_proyecto(p_id)) then raise exception 'La ficha del proyecto la edita un administrador' using errcode = '42501'; end if;
  select * into v_old from public.proyectos p where p.id = p_id for update;
  if not found then raise exception 'Ese proyecto no existe' using errcode = 'P0002'; end if;
  begin
    v_fecha := case when p_cambios ? 'fecha_entrega_estimada_proyecto' then nullif(p_cambios->>'fecha_entrega_estimada_proyecto', '')::date end;
    v_pct := case when p_cambios ? 'pct_minimo_inicio' then (p_cambios->>'pct_minimo_inicio')::numeric end;
  exception when others then raise exception 'Revisa la fecha y el porcentaje' using errcode = '22023';
  end;
  if p_cambios ? 'pct_minimo_inicio' and (v_pct is null or v_pct < 0 or v_pct > 100) then
    raise exception 'El porcentaje mínimo va de 0 a 100' using errcode = '22023';
  end if;
  if p_cambios ? 'slug' then
    v_slug := lower(btrim(coalesce(p_cambios->>'slug', '')));
    if v_slug !~ '^[a-z0-9-]{3,60}$' then raise exception 'El slug va en minúsculas, números y guiones (3 a 60)' using errcode = '22023'; end if;
    if exists (select 1 from public.proyectos p where p.slug = v_slug and p.id <> p_id) then
      raise exception 'Ese slug ya lo usa otro proyecto' using errcode = '23505';
    end if;
  end if;
  update public.proyectos p
     set resort = case when p_cambios ? 'resort' then nullif(btrim(coalesce(p_cambios->>'resort', '')), '') else p.resort end,
         parcela_master = case when p_cambios ? 'parcela_master' then nullif(btrim(coalesce(p_cambios->>'parcela_master', '')), '') else p.parcela_master end,
         ubicacion_maps = case when p_cambios ? 'ubicacion_maps' then nullif(btrim(coalesce(p_cambios->>'ubicacion_maps', '')), '') else p.ubicacion_maps end,
         fecha_entrega_estimada_proyecto = case when p_cambios ? 'fecha_entrega_estimada_proyecto' then v_fecha else p.fecha_entrega_estimada_proyecto end,
         fecha_entrega_estimada_fijada_en = case
             when p_cambios ? 'fecha_entrega_estimada_proyecto' and v_fecha is distinct from p.fecha_entrega_estimada_proyecto
             then case when v_fecha is null then null else current_date end
             else p.fecha_entrega_estimada_fijada_en end,
         pct_minimo_inicio = case when p_cambios ? 'pct_minimo_inicio' then v_pct else p.pct_minimo_inicio end,
         slug = case when p_cambios ? 'slug' then v_slug else p.slug end
   where p.id = p_id;
end $function$;

drop function public.borrar_proyecto_por_id(uuid);
drop function public.proyecto_vinculos_datos_por_id(uuid);
drop function public.renombrar_proyecto_por_id(uuid, text);
drop function public.parcela_traspaso_estado_por_unidad(uuid, text[]);
drop function privado.carta_cobrado_calcula_por_id(uuid, jsonb, uuid);
