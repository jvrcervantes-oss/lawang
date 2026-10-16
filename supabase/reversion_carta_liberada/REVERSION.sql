-- VUELTA ATRÁS de 20261016083000_carta_liberada_mismo_comprador.sql (16-oct-2026, Backend).
-- Devuelve los TRES cuerpos vivos de antes de la migración, byte a byte (pg_get_functiondef de la viva del 16-oct, md5 al lado de cada uno),
-- NO devuelve el EXECUTE de public.carta_cobrado_calcula a service_role (0 llamadores, §1.ter; Seguridad, consulta de deploy del 16-oct)
-- y borra los 3 ayudantes de privado (después de que nada los llame).
-- OJO: revertir REABRE el agujero (la Carta liberada y la que ocupa la parcela vuelven a decidirse por el pasaporte/correo del navegador).
-- Solo si la regla nueva rompe un alta legítima que no se arregla eligiendo la ficha del comprador; y entonces se avisa a Seguridad.
-- No toca filas: carta_cobrado_aplicado y contrato_eventos quedan como estén (un evento carta_liberada_imputada es historia, no se borra).
-- Se aplica como migración nueva (apply_migration), con su .sql en supabase/migrations.
-- destructivo-ok: los drop function son de los 3 ayudantes que crea la migración que se revierte, sin datos dentro

set local lock_timeout = '5s';

-- ── privado.carta_cobrado_calcula_por_id: viva del 16-oct, md5 41be932a47f00beb4b4264df69b36d31 ──
CREATE OR REPLACE FUNCTION privado.carta_cobrado_calcula_por_id(p_id uuid, p_datos jsonb, p_proyecto_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  datos jsonb := p_datos;
  cods text[] := (
    select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
      from unnest(string_to_array(coalesce(p_datos->'fields'->>'parcela_codigo',''), ',')) x);
  moneda_bloqueo text := coalesce(nullif(btrim(p_datos->'fields'->>'moneda'), ''), 'EUR');
  ids_yo text[] := public.contrato_identificadores(p_datos);
  cartas_ids        uuid[];
  cartas_nums        text[];
  v_disponibles      numeric[] := '{}';
  v_nums_aportantes  text[] := '{}';
  v_cobrado          numeric := 0;
  v_precio_total     numeric;
  v_descuento        numeric;
  v_sobrante         numeric;
  v_restante         numeric;
  v_detalle          jsonb := '[]'::jsonb;
  v_disp             numeric;
  v_ya               numeric;
  v_claim            numeric;
  i                  int;
begin
  datos := datos #- '{fields,carta_cobrado_importe}'
                 #- '{fields,carta_cobrado_numeros}'
                 #- '{fields,carta_cobrado_sobrante}'
                 #- '{fields,carta_cobrado_detalle}';
  datos := public.carta_cobrado_aplica_hitos(datos, 'insert');

  if p_proyecto_id is null then
    return datos;
  end if;

  select array_agg(x.id order by x.misma desc, x.numero), array_agg(x.numero order by x.misma desc, x.numero)
    into cartas_ids, cartas_nums
    from (select y.id, y.numero, bool_or(y.misma) as misma from (
      -- la Carta que ocupa hoy la parcela (traspaso Carta -> Bloqueo, 17-sep)
      select distinct c.id, c.numero, true as misma
        from public.unidades u
        join public.contratos c on c.id = u.contrato_id
       where u.proyecto_id = p_proyecto_id and u.codigo = any(cods)
         and c.tipo like 'carta_reserva%'
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
      union
      -- la Carta ya colgada de este Bloqueo (traspaso posterior al alta, 23-sep)
      select c.id, c.numero, true
        from public.contratos c
       where c.contrato_padre_id = p_id
         and c.tipo like 'carta_reserva%'
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
      union
      -- la Carta LIBERADA del mismo comprador (22-sep): retenida e imputable
      select c.id, c.numero, false
        from public.contratos c
       where c.tipo like 'carta_reserva%'
         and c.liberado_en is not null
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
         and coalesce(array_length(ids_yo, 1), 0) > 0
         and public.contrato_identificadores(c.datos) && ids_yo
    ) y group by y.id, y.numero) x;

  if coalesce(array_length(cartas_ids, 1), 0) = 0 then
    return datos;
  end if;

  for i in 1 .. array_length(cartas_ids, 1) loop
    perform pg_advisory_xact_lock(hashtext(cartas_ids[i]::text));
    v_ya := coalesce((
      select sum(importe) from public.carta_cobrado_aplicado
       where carta_id = cartas_ids[i] and contrato_id <> p_id
    ), 0);
    v_disp := greatest(coalesce(public.contrato_cobrado(cartas_ids[i]), 0) - v_ya, 0);
    v_disponibles := v_disponibles || v_disp;
    v_cobrado := v_cobrado + v_disp;
  end loop;

  if v_cobrado <= 0 then
    return datos;
  end if;

  v_precio_total := greatest(coalesce(public.lw_importe(datos->'fields'->>'precio_total'), 0), 0);
  v_descuento := least(v_cobrado, v_precio_total);
  v_sobrante  := greatest(v_cobrado - v_precio_total, 0);

  if v_descuento > 0 then
    v_restante := v_descuento;
    for i in 1 .. array_length(cartas_ids, 1) loop
      exit when v_restante <= 0;
      v_disp := v_disponibles[i];
      if v_disp > 0 then
        v_claim := least(v_disp, v_restante);
        v_detalle := v_detalle || jsonb_build_object(
          'carta_id', cartas_ids[i],
          'numero', cartas_nums[i],
          'importe', public.lw_importe_texto(v_claim));
        v_nums_aportantes := v_nums_aportantes || cartas_nums[i];
        v_restante := v_restante - v_claim;
      end if;
    end loop;

    datos := jsonb_set(datos, '{fields,carta_cobrado_importe}', to_jsonb(public.lw_importe_texto(v_descuento)), true);
    datos := jsonb_set(datos, '{fields,carta_cobrado_numeros}', to_jsonb(array_to_string(v_nums_aportantes, ', ')), true);
    datos := jsonb_set(datos, '{fields,carta_cobrado_detalle}', v_detalle, true);

    insert into public.carta_cobrado_aplicado (contrato_id, carta_id, importe)
    select p_id, (elem->>'carta_id')::uuid, public.lw_importe(elem->>'importe')
      from jsonb_array_elements(v_detalle) elem
    on conflict (contrato_id, carta_id) do nothing;
  end if;

  if v_sobrante > 0 then
    datos := jsonb_set(datos, '{fields,carta_cobrado_sobrante}', to_jsonb(public.lw_importe_texto(v_sobrante)), true);
  end if;

  datos := public.carta_cobrado_aplica_hitos(datos, 'insert');
  return datos;
end;
$function$
;

-- ── public.carta_cobrado_calcula: viva del 16-oct, md5 ddf75635712cbec45b1d55d6cb630cc8 ──
CREATE OR REPLACE FUNCTION public.carta_cobrado_calcula(p_id uuid, p_datos jsonb, p_proyecto_nombre text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  datos jsonb := p_datos;
  cods text[] := (
    select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
      from unnest(string_to_array(coalesce(p_datos->'fields'->>'parcela_codigo',''), ',')) x);
  proy text := coalesce(nullif(btrim(p_datos->'fields'->>'proyecto_nombre'), ''), p_proyecto_nombre);
  moneda_bloqueo text := coalesce(nullif(btrim(p_datos->'fields'->>'moneda'), ''), 'EUR');
  ids_yo text[] := public.contrato_identificadores(p_datos);
  cartas_ids        uuid[];
  cartas_nums        text[];
  v_disponibles      numeric[] := '{}';
  v_nums_aportantes  text[] := '{}';
  v_cobrado          numeric := 0;
  v_precio_total     numeric;
  v_descuento        numeric;
  v_sobrante         numeric;
  v_restante         numeric;
  v_detalle          jsonb := '[]'::jsonb;
  v_disp             numeric;
  v_ya               numeric;
  v_claim            numeric;
  i                  int;
begin
  datos := datos #- '{fields,carta_cobrado_importe}'
                 #- '{fields,carta_cobrado_numeros}'
                 #- '{fields,carta_cobrado_sobrante}'
                 #- '{fields,carta_cobrado_detalle}';
  datos := public.carta_cobrado_aplica_hitos(datos, 'insert');

  if proy is null then
    return datos;
  end if;

  select array_agg(x.id order by x.misma desc, x.numero), array_agg(x.numero order by x.misma desc, x.numero)
    into cartas_ids, cartas_nums
    from (select y.id, y.numero, bool_or(y.misma) as misma from (
      -- la Carta que ocupa hoy la parcela (traspaso Carta -> Bloqueo, 17-sep)
      select distinct c.id, c.numero, true as misma
        from public.unidades u
        join public.contratos c on c.id = u.contrato_id
       where u.proyecto = proy and u.codigo = any(cods)
         and c.tipo like 'carta_reserva%'
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
      union
      -- la Carta ya colgada de este Bloqueo (traspaso posterior al alta, 23-sep)
      select c.id, c.numero, true
        from public.contratos c
       where c.contrato_padre_id = p_id
         and c.tipo like 'carta_reserva%'
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
      union
      -- la Carta LIBERADA del mismo comprador (22-sep): retenida e imputable
      select c.id, c.numero, false
        from public.contratos c
       where c.tipo like 'carta_reserva%'
         and c.liberado_en is not null
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
         and coalesce(array_length(ids_yo, 1), 0) > 0
         and public.contrato_identificadores(c.datos) && ids_yo
    ) y group by y.id, y.numero) x;

  if coalesce(array_length(cartas_ids, 1), 0) = 0 then
    return datos;
  end if;

  for i in 1 .. array_length(cartas_ids, 1) loop
    perform pg_advisory_xact_lock(hashtext(cartas_ids[i]::text));
    v_ya := coalesce((
      select sum(importe) from public.carta_cobrado_aplicado
       where carta_id = cartas_ids[i] and contrato_id <> p_id
    ), 0);
    v_disp := greatest(coalesce(public.contrato_cobrado(cartas_ids[i]), 0) - v_ya, 0);
    v_disponibles := v_disponibles || v_disp;
    v_cobrado := v_cobrado + v_disp;
  end loop;

  if v_cobrado <= 0 then
    return datos;
  end if;

  v_precio_total := greatest(coalesce(public.lw_importe(datos->'fields'->>'precio_total'), 0), 0);
  v_descuento := least(v_cobrado, v_precio_total);
  v_sobrante  := greatest(v_cobrado - v_precio_total, 0);

  if v_descuento > 0 then
    v_restante := v_descuento;
    for i in 1 .. array_length(cartas_ids, 1) loop
      exit when v_restante <= 0;
      v_disp := v_disponibles[i];
      if v_disp > 0 then
        v_claim := least(v_disp, v_restante);
        v_detalle := v_detalle || jsonb_build_object(
          'carta_id', cartas_ids[i],
          'numero', cartas_nums[i],
          'importe', public.lw_importe_texto(v_claim));
        v_nums_aportantes := v_nums_aportantes || cartas_nums[i];
        v_restante := v_restante - v_claim;
      end if;
    end loop;

    datos := jsonb_set(datos, '{fields,carta_cobrado_importe}', to_jsonb(public.lw_importe_texto(v_descuento)), true);
    datos := jsonb_set(datos, '{fields,carta_cobrado_numeros}', to_jsonb(array_to_string(v_nums_aportantes, ', ')), true);
    datos := jsonb_set(datos, '{fields,carta_cobrado_detalle}', v_detalle, true);

    insert into public.carta_cobrado_aplicado (contrato_id, carta_id, importe)
    select p_id, (elem->>'carta_id')::uuid, public.lw_importe(elem->>'importe')
      from jsonb_array_elements(v_detalle) elem
    on conflict (contrato_id, carta_id) do nothing;
  end if;

  if v_sobrante > 0 then
    datos := jsonb_set(datos, '{fields,carta_cobrado_sobrante}', to_jsonb(public.lw_importe_texto(v_sobrante)), true);
  end if;

  datos := public.carta_cobrado_aplica_hitos(datos, 'insert');
  return datos;
end;
$function$
;

-- ── public.sincroniza_unidad_contrato: viva del 16-oct, md5 524feef3b661037e3b444615c8eeb6af ──
CREATE OR REPLACE FUNCTION public.sincroniza_unidad_contrato()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cods text[] := (
    select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
      from unnest(string_to_array(coalesce(new.datos->'fields'->>'parcela_codigo',''), ',')) x);
  cods_ant text[];
  proy text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  proy_ant     text;
  cod          text;
  ocupada      text;
  ocupada_id   uuid;
  ocupada_tipo text;
  ids_nuevo    text[];
  ids_ocupa    text[];
  traspaso_ok  boolean;
  estado_tr    text;
  exige        boolean;
  master       text;
  falta        text;
  existe          boolean;
  hay_inventario  boolean;
  cod_nuevo       boolean;
begin
  if tg_op = 'UPDATE' and coalesce(current_setting('app.via_traspaso_autor', true), '') = 'on' and (to_jsonb(new) - 'creado_por') = (to_jsonb(old) - 'creado_por') then return new; end if;
  if new.liberado_en is not null then
    return new;
  end if;

  if tg_op = 'UPDATE' and pg_trigger_depth() > 1
     and new.datos     is not distinct from old.datos
     and new.tipo      is not distinct from old.tipo
     and new.bloqueado is not distinct from old.bloqueado then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    cods_ant := (
      select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
        from unnest(string_to_array(coalesce(old.datos->'fields'->>'parcela_codigo',''), ',')) x);
    proy_ant := coalesce(nullif(btrim(old.datos->'fields'->>'proyecto_nombre'), ''), old.proyecto_nombre);
    if cods_ant is distinct from cods
       or (old.datos->'fields'->>'proyecto_nombre') is distinct from (new.datos->'fields'->>'proyecto_nombre') then
      if coalesce(current_setting('app.via_traspaso_estudio', true), '') <> 'on' then
        select u.codigo, cr.numero, u.estado into cod, ocupada, estado_tr
          from public.unidades u
          left join public.contratos cr
            on cr.contrato_padre_id = new.id and cr.id <> new.id
           and cr.liberado_en is null and coalesce(cr.bloqueado, false)
           and u.codigo = any (select btrim(x) from unnest(string_to_array(coalesce(cr.datos->'fields'->>'parcela_codigo', ''), ',')) x)
         where u.contrato_id = new.id
           and (u.proyecto is distinct from proy or not (u.codigo = any (cods)))
           and (u.estado in ('vendida', 'cobrada') or cr.id is not null)
         limit 1;
        if cod is not null then
          if ocupada is not null then
            raise exception 'La parcela % de % no se puede quitar de %: la nombra la Carta de Reserva firmada %. Moverla es un traspaso: pídeselo a administración.',
              cod, proy_ant, new.numero, ocupada using errcode = '23514';
          end if;
          raise exception 'La parcela % de % no se puede quitar de %: está %. Pídeselo a administración.',
            cod, proy_ant, new.numero, estado_tr using errcode = '23514';
        end if;
        cod := null; ocupada := null; estado_tr := null;
      end if;
      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id
         and (u.proyecto is distinct from proy or not (u.codigo = any (cods)));
    end if;
  end if;

  if coalesce(array_length(cods, 1), 0) = 0 or proy is null then

    select true into exige
      from public.contrato_tipo_etapa e
     where e.tipo = new.tipo and e.etapa = 'reserva';

    if coalesce(exige, false) then
      proy_ant := case when tg_op = 'UPDATE'
                  then coalesce(nullif(btrim(old.datos->'fields'->>'proyecto_nombre'), ''), old.proyecto_nombre)
                  end;
      if tg_op = 'UPDATE'
         and cods_ant is not distinct from cods
         and proy_ant is not distinct from proy then
        return new;
      end if;

      falta := case
                 when proy is null and coalesce(array_length(cods, 1), 0) = 0
                   then 'el proyecto y la parcela'
                 when proy is null then 'el proyecto'
                 else 'la parcela'
               end;

      master := nullif(btrim(coalesce(new.datos->'fields'->>'parcela_master','')), '');

      if master is not null and coalesce(array_length(cods, 1), 0) = 0 then
        raise exception
          'Rellena: %. El código «%» está en «Parcela máster» por error — va en el campo «Parcela».',
          falta, master using errcode = '23514';
      end if;

      raise exception
        'Rellena: %.',
        falta using errcode = '23514';
    end if;

    return new;
  end if;

  ids_nuevo := public.contrato_identificadores(new.datos);

  foreach cod in array cods loop
    select c.id, c.numero, c.tipo, public.contrato_identificadores(c.datos)
      into ocupada_id, ocupada, ocupada_tipo, ids_ocupa
      from public.unidades u join public.contratos c on c.id = u.contrato_id
     where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id
       and c.liberado_en is null;

    cod_nuevo := (tg_op = 'INSERT')
              or (proy_ant is distinct from proy)
              or not (cod = any (coalesce(cods_ant, '{}')));

    if ocupada_id is null and cod_nuevo then
      select exists(select 1 from public.unidades u where u.proyecto = proy and u.codigo = cod)
        into existe;
      if not existe then
        select exists(select 1 from public.unidades u where u.proyecto = proy)
          into hay_inventario;
        if hay_inventario then
          raise exception
            'La parcela «%» no está en el inventario de «%». Revisa el código (puede faltar o sobrar un espacio, un punto o una tilde) — este proyecto ya tiene parcelas cargadas.',
            cod, proy using errcode = '23514';
        end if;
      end if;
    end if;

    if ocupada_id is not null then
      if new.tipo like 'carta_reserva%'
         and ocupada_tipo = 'reserva_parcela'
         and (ids_nuevo && ids_ocupa or new.contrato_padre_id = ocupada_id) then
        continue;
      end if;

      estado_tr := public.traspaso_carta_estado(new.tipo, ids_nuevo, ocupada_tipo, ids_ocupa);
      traspaso_ok := estado_tr <> 'no';

      if not traspaso_ok then
        raise exception 'La parcela % de % ya esta asignada al contrato %', cod, proy, ocupada
          using errcode = '23505';
      end if;

      if estado_tr = 'sin_datos' then
        raise exception 'El traspaso de la parcela % de % no se puede comprobar: falta el pasaporte o el email del comprador en % o en el contrato que estás guardando. Complétalo y vuelve a guardar.',
          cod, proy, ocupada using errcode = '23514';
      end if;
      if estado_tr = 'otro' then
        raise exception 'El traspaso de la parcela % de % no cuadra: % está a nombre de otro comprador. La parcela solo pasa de una Carta de Reserva a su Bloqueo si coincide el pasaporte o el email.',
          cod, proy, ocupada using errcode = '23514';
      end if;
    end if;

    update public.unidades u
       set contrato_id = new.id,
           estado = case
             when u.estado in ('vendida','cobrada') then u.estado
             when u.estado = 'no_disponible' then u.estado
             when u.estado = 'bloqueada' and not exists (
                    select 1 from public.contratos c2
                     where c2.id = u.contrato_id
                       and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                  ) then u.estado
             when new.tipo = 'reserva_parcela' and coalesce(new.bloqueado, false) then 'bloqueada'
             when new.tipo = 'construccion' then u.estado
             else 'reservada'
           end
     where u.proyecto = proy and u.codigo = cod;

    if ocupada_id is not null and traspaso_ok then
      update public.contratos c
         set contrato_padre_id = new.id
       where c.id = ocupada_id and c.contrato_padre_id is null;
    end if;

    ocupada_id := null; ocupada := null; ocupada_tipo := null; ids_ocupa := null;
  end loop;

  update public.unidades u
     set estado = case
           when u.estado in ('vendida','cobrada') then u.estado
           when u.estado = 'no_disponible' then u.estado
           when u.estado = 'bloqueada' and not exists (
                  select 1 from public.contratos c2
                   where c2.id = u.contrato_id
                     and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                ) then u.estado
           when new.tipo = 'reserva_parcela' and coalesce(new.bloqueado, false) then 'bloqueada'
           when new.tipo = 'construccion' then u.estado
           else 'reservada'
         end
   where u.contrato_id = new.id;

  return new;
end;
$function$
;

drop function privado.carta_imputable(uuid, uuid[], text);
drop function privado.contrato_fichas(uuid);
drop function privado.carta_cobrado_clientes_de(jsonb);
