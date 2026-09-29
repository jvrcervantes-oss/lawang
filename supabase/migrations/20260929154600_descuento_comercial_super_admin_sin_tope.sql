-- Descuento comercial: el super_admin no tiene tope del 15% — 29-sep-2026.
-- Owner: "quita la limitación del % de descuento comercial en los contratos
-- de Lawang a superadmins".
-- ════════════════════════════════════════════════════════════════════════════
-- Toca los dos gemelos (Construcción y Bloqueo de Parcela). Para el resto de
-- roles (admin, sales_manager) el tope del 15% sigue igual.
--
-- QUIÉN ES SUPER ADMIN: mismo patrón que descuento_comercial_rol —
-- public.usuarios activo con user_id = auth.uid(). Sin sesión (auth.uid()
-- null: service_role, MCP) el tope SIGUE: la exención es opt-in, el candado
-- es el default. contrato_guarda es SECURITY DEFINER pero auth.uid() sale del
-- JWT, así que llega aquí con el usuario real.
--
-- TOPE SOLO CUANDO CAMBIA EL DESCUENTO (INSERT o descuento nuevo ≠ viejo).
-- Antes, en Construcción, corría en CUALQUIER update con descuento > 0: con un
-- 30% puesto por el super admin, un sales manager que arreglase un email del
-- contrato habría reventado con "supera el 15%". Misma familia que el fix del
-- 21-sep (un cinturón incondicional rompe ediciones que no tienen nada que
-- ver). El descuento que ya está guardado no se vuelve a medir.
--
-- NUEVO SUELO en el Bloqueo: sin techo, descuento > lista cuadraría con un
-- precio_total negativo. Se para para todos los roles (Construcción ya lo
-- para con precio_total <= 0).

create or replace function public.descuento_comercial_construccion_valido()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_descuento numeric;
  v_techo     numeric;
  v_base      numeric;
  v_esperado  numeric;
  v_cambia    boolean;
  v_dc_cambia boolean;
  v_super     boolean;
begin
  if new.tipo <> 'construccion' then
    return new;
  end if;
  v_descuento := coalesce(public.lw_importe(new.datos->'fields'->>'descuento_comercial'), 0);
  if v_descuento < 0 then
    raise exception 'El descuento comercial no puede ser negativo.';
  end if;
  v_techo := nullif(new.datos->'techo'->>'precio', '')::numeric;
  if v_techo is not null then
    select v_techo + coalesce(sum(nullif(x->>'precio','')::numeric), 0)
      into v_base
      from jsonb_array_elements(coalesce(new.datos->'extras', '[]'::jsonb)) x;
  end if;
  if v_descuento > 0 then
    v_dc_cambia := tg_op = 'INSERT'
      or (new.datos->'fields'->>'descuento_comercial') is distinct from (old.datos->'fields'->>'descuento_comercial');
    if v_dc_cambia and v_base > 0 and v_descuento > round(v_base * 0.15, 2) then
      select exists (select 1 from public.usuarios u
                      where u.user_id = (select auth.uid()) and u.activo and u.rol = 'super_admin')
        into v_super;
      if not coalesce(v_super, false) then
        raise exception 'El descuento comercial (%) supera el 15%% del precio de techo+extras (%).',
          v_descuento, v_base;
      end if;
    end if;
    if coalesce(new.precio_total, 0) <= 0 then
      raise exception 'precio_total no puede quedar en cero o negativo al aplicar un descuento comercial.';
    end if;
  end if;
  if v_base is not null and v_base > 0 then
    v_cambia := tg_op = 'INSERT'
      or new.precio_total is distinct from old.precio_total
      or new.datos->'techo' is distinct from old.datos->'techo'
      or new.datos->'extras' is distinct from old.datos->'extras'
      or (new.datos->'fields'->>'descuento_comercial') is distinct from (old.datos->'fields'->>'descuento_comercial');
    if v_cambia then
      v_esperado := v_base - v_descuento;
      if new.precio_total is null or abs(new.precio_total - v_esperado) > 0.01 then
        raise exception 'precio_total (%) no cuadra con techo + extras − descuento comercial (% = % + extras − %): el precio de Construcción con techo elegido lo calcula la intranet, no se teclea.',
          new.precio_total, v_esperado, v_techo, v_descuento;
      end if;
    end if;
  end if;
  return new;
end;
$$;

comment on function public.descuento_comercial_construccion_valido() is
  'BEFORE INSERT OR UPDATE en contratos, solo tipo=construccion: bloquea descuento_comercial negativo; tope 15% de techo+extras solo al poner/cambiar el descuento y nunca para super_admin (29-sep-2026, owner); con descuento, precio_total > 0; con techo, precio_total = techo+extras − descuento. El rol de quien pone descuento lo frena descuento_comercial_rol.';

create or replace function public.descuento_comercial_suelo_valido()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_descuento numeric;
  v_lista     numeric;
  v_motivo    text;
  v_cambia    boolean;
  v_dc_cambia boolean;
  v_super     boolean;
begin
  if new.tipo <> 'reserva_parcela' then
    return new;
  end if;
  v_descuento := coalesce(public.lw_importe(new.datos->'fields'->>'descuento_comercial'), 0);
  if v_descuento < 0 then
    raise exception 'El descuento comercial no puede ser negativo.';
  end if;
  if v_descuento = 0 then
    return new;
  end if;
  v_cambia := tg_op = 'INSERT'
    or new.precio_total is distinct from old.precio_total
    or (new.datos->'fields'->>'descuento_comercial') is distinct from (old.datos->'fields'->>'descuento_comercial')
    or (new.datos->'fields'->>'descuento_comercial_motivo') is distinct from (old.datos->'fields'->>'descuento_comercial_motivo')
    or (new.datos->'fields'->>'precio_lista_suelo') is distinct from (old.datos->'fields'->>'precio_lista_suelo');
  if not v_cambia then
    return new;
  end if;
  v_dc_cambia := tg_op = 'INSERT'
    or (new.datos->'fields'->>'descuento_comercial') is distinct from (old.datos->'fields'->>'descuento_comercial');
  v_lista := public.lw_importe(new.datos->'fields'->>'precio_lista_suelo');
  if v_lista is null or v_lista <= 0 then
    raise exception 'Un descuento comercial en el Bloqueo de Parcela necesita el precio de lista del suelo (precio_lista_suelo).';
  end if;
  if v_descuento >= v_lista then
    raise exception 'El descuento comercial (%) no puede igualar ni superar el precio del suelo (%).', v_descuento, v_lista;
  end if;
  if v_dc_cambia and v_descuento > round(v_lista * 0.15, 2) then
    select exists (select 1 from public.usuarios u
                    where u.user_id = (select auth.uid()) and u.activo and u.rol = 'super_admin')
      into v_super;
    if not coalesce(v_super, false) then
      raise exception 'El descuento comercial (%) supera el 15%% del precio del suelo (%).', v_descuento, v_lista;
    end if;
  end if;
  v_motivo := nullif(btrim(coalesce(new.datos->'fields'->>'descuento_comercial_motivo', '')), '');
  if v_motivo is null then
    raise exception 'Un descuento comercial necesita su motivo.';
  end if;
  if new.precio_total is null or abs(new.precio_total - (v_lista - v_descuento)) > 0.01 then
    raise exception 'precio_total (%) no cuadra con el precio del suelo menos el descuento comercial (% − % = %).',
      new.precio_total, v_lista, v_descuento, v_lista - v_descuento;
  end if;
  return new;
end;
$$;

comment on function public.descuento_comercial_suelo_valido() is
  'BEFORE INSERT OR UPDATE en contratos, solo tipo=reserva_parcela: bloquea descuento_comercial negativo y, con descuento>0 (en INSERT o si cambia precio/descuento/motivo/lista), exige precio_lista_suelo, descuento < lista, motivo y precio_total = lista − descuento; tope 15% solo al poner/cambiar el descuento y nunca para super_admin (29-sep-2026, owner).';
