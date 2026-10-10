-- Reconstruida el 10-oct-2026 desde supabase_migrations.schema_migrations.statements (nombre exacto; version real del catalogo 20260929075341, el prefijo sigue al fichero padre para que el orden de replay sea el de aplicacion; ya APLICADA en produccion, no se vuelve a aplicar). Su cambio ya esta fundido en: 20260929154600_descuento_comercial_super_admin_sin_tope.sql (tope vigente: 20261008980000_descuento_comercial_tope_admin_50.sql)
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
      or (new.datos->'fields'->>'descuento_comercial') is distinct from (old.datos->'fields'->>'descuento_comercial')
      or new.datos->'techo' is distinct from old.datos->'techo'
      or new.datos->'extras' is distinct from old.datos->'extras';
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
  'BEFORE INSERT OR UPDATE en contratos, solo tipo=construccion: bloquea descuento_comercial negativo; tope 15% de techo+extras solo al poner/cambiar el descuento o techo/extras y nunca para super_admin (29-sep-2026, owner); con descuento, precio_total > 0; con techo, precio_total = techo+extras − descuento. El rol de quien pone descuento lo frena descuento_comercial_rol.';

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
    or (new.datos->'fields'->>'descuento_comercial') is distinct from (old.datos->'fields'->>'descuento_comercial')
    or (new.datos->'fields'->>'precio_lista_suelo') is distinct from (old.datos->'fields'->>'precio_lista_suelo');
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
  'BEFORE INSERT OR UPDATE en contratos, solo tipo=reserva_parcela: bloquea descuento_comercial negativo y, con descuento>0 (en INSERT o si cambia precio/descuento/motivo/lista), exige precio_lista_suelo, descuento < lista, motivo y precio_total = lista − descuento; tope 15% solo al poner/cambiar el descuento o la lista y nunca para super_admin (29-sep-2026, owner).';
