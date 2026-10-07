-- Descuento comercial: tope por rol. 7-oct-2026, owner: «el límite de 15 % de descuento comercial aumentalo para administradores hasta un 50 %».
-- Antes: 15 % para todos salvo super_admin (sin tope, 29-sep). Ahora: super_admin sin tope · admin 50 % · resto (sales_manager…) 15 %.
-- Sustituye SOLO dos funciones, sin tocar filas, grants ni triggers: descuento_comercial_construccion_valido (base: versión
-- de 20261007005103, LAW-494, conserva todo lo suyo) y descuento_comercial_suelo_valido (base: 20260929154600).
-- Quién puede poner un descuento sigue en descuento_comercial_rol. Sin sesión (service role) el tope es el 15 %, como antes.

create or replace function public.descuento_comercial_construccion_valido()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_descuento   numeric;
  v_base        numeric;
  v_esperado    numeric;
  v_cambia      boolean;
  v_dc_cambia   boolean;
  v_rol         text;
  v_pct         numeric;
  v_alta        boolean;
  v_contrastado boolean;
  v_tid         text;
  v_modelo      uuid;
  v_ok          numeric;
  v_nombre      text;
  v_x           jsonb;
  v_extras      jsonb;
begin
  if new.tipo <> 'construccion' then
    return new;
  end if;

  -- «Alta» no es solo el INSERT: también el contrato que acaba de volverse de Construcción. Mientras era de otro tipo
  -- la línea de arriba hizo que este trigger no mirara nada, así que sus cifras no se contrastaron nunca (LAW-494 #3).
  v_alta := tg_op = 'INSERT' or new.tipo is distinct from old.tipo;

  -- Techo y extras se comprueban CONTRA MODELOS, con sesión, en el alta o si cambian techo, extras o proyecto. Un
  -- contrato guardado que no toca nada de eso conserva su precio congelado aunque el techo se retire o cambie de
  -- precio. Sin sesión no se contrasta (mismo criterio que el resto de candados de rol).
  v_contrastado := (select auth.uid()) is not null and (
       v_alta
       or new.datos->'techo' is distinct from old.datos->'techo'
       or new.datos->'extras' is distinct from old.datos->'extras'
       or new.proyecto_id is distinct from old.proyecto_id);

  if v_contrastado then
    v_tid := nullif(btrim(coalesce(new.datos->'techo'->>'techo_id', '')), '');
    if v_tid is null then
      -- LAW-494 #2: en UPDATE, quitar el techo que el contrato YA traía tampoco vale (sin techo la base queda NULL y
      -- se saltan tope y cuadre). Un contrato antiguo que nunca tuvo techo se sigue pudiendo editar.
      if v_alta
         or nullif(btrim(coalesce(old.datos->'techo'->>'techo_id', '')), '') is not null then
        raise exception 'Un contrato de Construcción lleva siempre techo: elige la tipología y el techo.' using errcode = '22023';
      end if;
      if jsonb_array_length(coalesce(new.datos->'extras', '[]'::jsonb)) > 0 then
        raise exception 'Los extras necesitan un techo elegido.' using errcode = '22023';
      end if;
    else
      -- uuid con su forma exacta: '-'×36 cumplía el patrón viejo y reventaba con 22P02 en el cast
      if v_tid !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
        raise exception 'El techo elegido no es válido: vuelve a elegirlo.' using errcode = '22023';
      end if;
      select th.modelo_id into v_modelo from public.modelo_techos th where th.id = v_tid::uuid;
      if v_modelo is null then
        select m.id into v_modelo from public.modelos m where m.id = v_tid::uuid;   -- «Ulin» sintético: techo_id = modelo_id
      end if;
      if v_modelo is null then
        raise exception 'El techo elegido no existe en Modelos: vuelve a elegirlo.' using errcode = '22023';
      end if;
      select o.precio, o.nombre into v_ok, v_nombre
        from public._modelo_techos_opciones(v_modelo, new.proyecto_id) o where o.techo_id = v_tid::uuid;
      if v_ok is null then
        raise exception 'El techo «%» no se ofrece para este proyecto (retirado o fuera de su alcance): elige otro.',
          coalesce(new.datos->'techo'->>'nombre', '?') using errcode = '22023';
      end if;
      if abs(v_ok - coalesce(public.lw_importe(new.datos->'techo'->>'precio'), -1)) > 0.01 then
        raise exception 'El precio del techo «%» es % en Modelos, no %: vuelve a elegir el techo para refrescarlo.',
          v_nombre, v_ok, new.datos->'techo'->>'precio' using errcode = '22023';
      end if;
      -- LAW-494 #1: la base del cuadre es lo que Modelos acaba de dar, no la cadena del navegador, y eso mismo es lo
      -- que se guarda en el contrato (más abajo)
      v_base := v_ok;
      new.datos := jsonb_set(new.datos, '{techo,precio}', to_jsonb(v_ok));
      v_extras := '[]'::jsonb;
      for v_x in select * from jsonb_array_elements(coalesce(new.datos->'extras', '[]'::jsonb)) loop
        v_ok := null;
        if coalesce(v_x->>'extra_id', '') ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
          select me.precio into v_ok
            from public.modelo_extras me join public.extras e on e.id = me.extra_id
           where me.modelo_id = v_modelo and me.extra_id = (v_x->>'extra_id')::uuid
             and me.disponible and e.activo and me.precio is not null;
        end if;
        if v_ok is null then
          raise exception 'El extra «%» no se ofrece para este modelo: quítalo.', coalesce(v_x->>'nombre', '?') using errcode = '22023';
        end if;
        if abs(v_ok - coalesce(public.lw_importe(v_x->>'precio'), -1)) > 0.01 then
          raise exception 'El precio del extra «%» es % en Modelos, no %: desmárcalo y vuelve a marcarlo.',
            coalesce(v_x->>'nombre', '?'), v_ok, v_x->>'precio' using errcode = '22023';
        end if;
        v_base := v_base + v_ok;
        v_extras := v_extras || jsonb_build_array(jsonb_set(v_x, '{precio}', to_jsonb(v_ok)));
      end loop;
      if jsonb_typeof(new.datos->'extras') = 'array' then
        new.datos := jsonb_set(new.datos, '{extras}', v_extras);
      end if;
    end if;
  elsif nullif(btrim(coalesce(new.datos->'techo'->>'techo_id', '')), '') is not null then
    -- Contrato congelado (o escritura sin sesión): las cifras del propio contrato, con el MISMO parser del contraste.
    select coalesce(public.lw_importe(new.datos->'techo'->>'precio'), 0)
           + coalesce(sum(coalesce(public.lw_importe(x->>'precio'), 0)), 0)
      into v_base
      from jsonb_array_elements(coalesce(new.datos->'extras', '[]'::jsonb)) x;
  end if;

  v_descuento := coalesce(public.lw_importe(new.datos->'fields'->>'descuento_comercial'), 0);
  if v_descuento < 0 then
    raise exception 'El descuento comercial no puede ser negativo.';
  end if;
  if v_descuento > 0 then
    v_dc_cambia := v_alta or v_contrastado
      or (new.datos->'fields'->>'descuento_comercial') is distinct from (old.datos->'fields'->>'descuento_comercial')
      or new.datos->'techo' is distinct from old.datos->'techo'
      or new.datos->'extras' is distinct from old.datos->'extras';
    if v_dc_cambia and v_base > 0 then
      -- tope por rol (7-oct-2026, owner): super_admin sin tope (29-sep), admin 50 %, el resto 15 %. Sin sesión: 15 %.
      select u.rol into v_rol from public.usuarios u where u.user_id = (select auth.uid()) and u.activo;
      v_pct := case when v_rol = 'admin' then 50 else 15 end;
      if v_rol is distinct from 'super_admin' and v_descuento > round(v_base * v_pct / 100, 2) then
        raise exception 'El descuento comercial (%) supera el % %% del precio de techo+extras (%).',
          v_descuento, v_pct, v_base;
      end if;
    end if;
    if coalesce(new.precio_total, 0) <= 0 then
      raise exception 'precio_total no puede quedar en cero o negativo al aplicar un descuento comercial.';
    end if;
  end if;
  if v_base is not null and v_base > 0 then
    v_cambia := v_alta or v_contrastado
      or new.precio_total is distinct from old.precio_total
      or new.datos->'techo' is distinct from old.datos->'techo'
      or new.datos->'extras' is distinct from old.datos->'extras'
      or (new.datos->'fields'->>'descuento_comercial') is distinct from (old.datos->'fields'->>'descuento_comercial');
    if v_cambia then
      v_esperado := v_base - v_descuento;
      if new.precio_total is null or abs(new.precio_total - v_esperado) > 0.01 then
        raise exception 'precio_total (%) no cuadra con techo + extras − descuento comercial (% = % − %): el precio de Construcción con techo elegido lo calcula la intranet, no se teclea.',
          new.precio_total, v_esperado, v_base, v_descuento using errcode = '22023';
      end if;
    end if;
  end if;
  return new;
end;
$$;

comment on function public.descuento_comercial_construccion_valido() is
  'BEFORE INSERT OR UPDATE en contratos, tipo=construccion (LAW-494 + tope por rol 7-oct-2026): descuento no negativo; tope sobre techo+extras solo al poner/cambiar el descuento o techo/extras: 15 %, 50 % admin, sin tope super_admin; con descuento precio_total > 0; con techo, precio_total = techo+extras − descuento y techo/extras contrastados contra Modelos. El rol de quien pone el descuento lo frena descuento_comercial_rol.';


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
  v_rol       text;
  v_pct       numeric;
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
  if v_dc_cambia then
    -- tope por rol (7-oct-2026, owner): super_admin sin tope (29-sep), admin 50 %, el resto 15 %. Sin sesión: 15 %.
    select u.rol into v_rol from public.usuarios u where u.user_id = (select auth.uid()) and u.activo;
    v_pct := case when v_rol = 'admin' then 50 else 15 end;
    if v_rol is distinct from 'super_admin' and v_descuento > round(v_lista * v_pct / 100, 2) then
      raise exception 'El descuento comercial (%) supera el % %% del precio del suelo (%).', v_descuento, v_pct, v_lista;
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
  'BEFORE INSERT OR UPDATE en contratos, tipo=reserva_parcela: no negativo, con descuento exige precio_lista_suelo, descuento < lista, motivo y precio_total = lista − descuento; tope sobre el suelo solo al poner/cambiar descuento o lista: 15 %, 50 % admin, sin tope super_admin (7-oct-2026, owner).';
