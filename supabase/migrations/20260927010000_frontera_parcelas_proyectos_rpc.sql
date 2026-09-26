-- destructivo-ok: solo crea funciones y la tabla unidades_log; no borra ni cambia ninguna fila al aplicarse.
-- Frontera frontend/backend — pieza 8: PARCELAS (unidades) y PROYECTOS por el servidor (27-sep-2026, LAW-336).
-- SOLO AÑADE funciones y una tabla de registro; el cierre (revoke) va aparte cuando las pantallas servidas
-- ya no escriban directo. Plan y revisión previa #123 (Seguridad + Administración):
-- encargos/20260927_lawang_frontera_f8_parcelas_proyectos.md
--
-- DECISIONES DEL OWNER (27-sep):
-- · Parcela CON contrato: un agente solo toca notas, modelo, tipo y fase/zona de masterplan. Precio de
--   suelo, de construcción, moneda, código y proyecto solo un admin, con motivo, y queda en unidades_log.
--   Esos datos alimentan en vivo las comisiones y la escalera vendida/cobrada (Administración).
-- · El vínculo parcela↔contrato lo pone SOLO el contrato (trigger sincroniza_unidad_contrato): desde la
--   parcela ya no se elige contrato. Estados manuales: disponible, no_disponible y bloqueada (litigio…);
--   vendida, cobrada y reservada nunca a mano (se puede conservar la que ya tiene una parcela sin tocarla).
-- Además (revisiones): el proyecto lo resuelve el servidor por su nombre (desconocido = error, antes quedaba
-- huérfana); `precio` nunca se escribe (lo pone el trigger suelo + construcción); la importación CSV va en
-- UNA transacción con tope de filas, y las filas de parcelas con contrato no cambian dinero ni código: se
-- devuelven como «rechazadas: tiene contrato», nunca se omiten en silencio.

create table if not exists public.unidades_log (
  id uuid primary key default gen_random_uuid(),
  unidad_id uuid not null,
  antes jsonb, despues jsonb,
  motivo text,
  via text,
  por text default auth.email(),
  en timestamptz not null default now()
);
alter table public.unidades_log enable row level security;
revoke all on public.unidades_log from anon, authenticated;
grant select on public.unidades_log to authenticated;
create policy "log de parcelas: lo ve un admin" on public.unidades_log for select to authenticated using (public.es_admin());

-- proyecto por NOMBRE → id, visible para quien guarda (raise si no existe o no lo ve)
create or replace function public._unidad_proyecto(p_nombre text) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare v uuid;
begin
  select p.id into v from public.proyectos p where p.nombre = btrim(coalesce(p_nombre, ''));
  if v is null or not public.unidad_visible(v) then
    raise exception 'Ese proyecto no existe o no trabajas en él' using errcode = '42501';
  end if;
  return v;
end $$;
revoke all on function public._unidad_proyecto(text) from public, anon, authenticated;

create or replace function public.unidad_guarda(p_id uuid, p_datos jsonb, p_motivo text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_old public.unidades%rowtype; v_new public.unidades%rowtype; v_id uuid;
  v_proy uuid; v_admin boolean := public.es_admin();
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_codigo text := nullif(btrim(coalesce(p_datos->>'codigo', '')), '');
  v_nproy text := btrim(coalesce(p_datos->>'proyecto', ''));
  v_mon text := upper(nullif(btrim(coalesce(p_datos->>'moneda', '')), ''));
  v_est text := nullif(btrim(coalesce(p_datos->>'estado', '')), '');
  v_sup numeric; v_suelo numeric; v_obra numeric;
  v_dinero boolean;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_agente() and public.puede('unidades')) then
    raise exception 'No tienes la herramienta Unidades' using errcode = '42501';
  end if;
  if v_codigo is null then raise exception 'El código no puede quedar vacío' using errcode = '22023'; end if;
  if v_mon is not null and v_mon not in ('EUR', 'USD', 'AUD', 'IDR') then raise exception 'Moneda no válida' using errcode = '22023'; end if;
  begin
    v_sup   := nullif(p_datos->>'superficie_m2', '')::numeric;
    v_suelo := nullif(p_datos->>'precio_suelo', '')::numeric;
    v_obra  := nullif(p_datos->>'precio_construccion', '')::numeric;
  exception when others then raise exception 'Revisa superficie y precios: no son números válidos' using errcode = '22023';
  end;
  v_proy := public._unidad_proyecto(v_nproy);

  if p_id is null then
    if v_est is not null and v_est not in ('disponible', 'no_disponible', 'bloqueada') then
      raise exception 'Ese estado no se pone a mano: lo decide el contrato' using errcode = '22023';
    end if;
    insert into public.unidades (codigo, proyecto, tipo, modelo, superficie_m2, precio_suelo, precio_construccion,
                                 moneda, notas, fase_masterplan, zona_masterplan, estado)
    values (v_codigo, v_nproy, coalesce(p_datos->>'tipo', 'parcela'), nullif(btrim(coalesce(p_datos->>'modelo', '')), ''), v_sup,
            case when p_datos ? 'precio_suelo' then v_suelo end, v_obra, coalesce(v_mon, 'EUR'),
            nullif(btrim(coalesce(p_datos->>'notas', '')), ''),
            nullif(btrim(coalesce(p_datos->>'fase_masterplan', '')), ''), nullif(btrim(coalesce(p_datos->>'zona_masterplan', '')), ''),
            coalesce(v_est, 'disponible'))
    returning id into v_id;
    insert into public.unidades_log (unidad_id, antes, despues, via)
    select v_id, null, to_jsonb(u), 'alta' from public.unidades u where u.id = v_id;
    return v_id;
  end if;

  select * into v_old from public.unidades u where u.id = p_id for update;
  if not found or not public.unidad_visible(v_old.proyecto_id) then
    raise exception 'No encuentro esa parcela entre las tuyas' using errcode = '42501';
  end if;
  -- ¿cambia algo de lo que cuenta como dinero o identidad?
  v_dinero := v_codigo is distinct from v_old.codigo or v_nproy is distinct from v_old.proyecto
           or v_sup is distinct from v_old.superficie_m2
           or (p_datos ? 'precio_suelo' and v_suelo is distinct from v_old.precio_suelo)
           or v_obra is distinct from v_old.precio_construccion
           or coalesce(v_mon, v_old.moneda) is distinct from v_old.moneda;
  if v_old.contrato_id is not null and v_dinero then
    if not v_admin then
      raise exception 'Esta parcela tiene contrato: su precio, moneda, superficie, código y proyecto solo los cambia un admin' using errcode = '42501';
    end if;
    if v_motivo is null or length(v_motivo) < 10 then
      raise exception 'Esta parcela tiene contrato: escribe por qué cambias sus datos (queda registrado)' using errcode = '22023';
    end if;
  end if;
  -- estado solo sin contrato, y a mano solo los manuales (conservar el que ya tiene no es cambiarlo)
  if v_old.contrato_id is not null then
    v_est := v_old.estado;
  elsif v_est is null then
    v_est := v_old.estado;
  elsif v_est is distinct from v_old.estado and v_est not in ('disponible', 'no_disponible', 'bloqueada') then
    raise exception 'Ese estado no se pone a mano: lo decide el contrato' using errcode = '22023';
  end if;

  update public.unidades u
     set codigo = v_codigo, proyecto = v_nproy, tipo = coalesce(p_datos->>'tipo', u.tipo),
         modelo = nullif(btrim(coalesce(p_datos->>'modelo', '')), ''),
         superficie_m2 = v_sup,
         precio_suelo = case when p_datos ? 'precio_suelo' then v_suelo else u.precio_suelo end,
         precio_construccion = v_obra,
         moneda = coalesce(v_mon, u.moneda),
         notas = nullif(btrim(coalesce(p_datos->>'notas', '')), ''),
         fase_masterplan = case when p_datos ? 'fase_masterplan' then nullif(btrim(coalesce(p_datos->>'fase_masterplan', '')), '') else u.fase_masterplan end,
         zona_masterplan = case when p_datos ? 'zona_masterplan' then nullif(btrim(coalesce(p_datos->>'zona_masterplan', '')), '') else u.zona_masterplan end,
         estado = v_est
   where u.id = p_id
  returning * into v_new;
  if not public.unidad_visible(v_new.proyecto_id) then
    raise exception 'No trabajas en ese proyecto' using errcode = '42501';
  end if;
  if v_dinero or v_est is distinct from v_old.estado then
    insert into public.unidades_log (unidad_id, antes, despues, motivo, via)
    values (p_id, to_jsonb(v_old), to_jsonb(v_new), v_motivo, 'ficha');
  end if;
  return p_id;
end $$;
revoke all on function public.unidad_guarda(uuid, jsonb, text) from public, anon;
grant execute on function public.unidad_guarda(uuid, jsonb, text) to authenticated;

-- Importación CSV entera en UNA transacción. Cada fila: {fila, codigo, proyecto, [tipo, modelo, superficie_m2,
-- precio_suelo, precio_construccion, moneda, notas, fase_masterplan, zona_masterplan]} — solo se aplican las
-- claves que vienen (ausente ≠ vacío, 8-sep). `precio` no se acepta: lo calcula el trigger.
create or replace function public.unidades_importa(p_filas jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  f jsonb; v_old public.unidades%rowtype; v_proy uuid; v_nproy text; v_cod text;
  v_alta int := 0; v_act int := 0; v_rech jsonb := '[]'::jsonb; v_dinero text[];
  k text; v_mon text;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_agente() and public.puede('unidades')) then
    raise exception 'No tienes la herramienta Unidades' using errcode = '42501';
  end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then raise exception 'Nada que importar' using errcode = '22023'; end if;
  if jsonb_array_length(p_filas) > 5000 then raise exception 'Como mucho 5000 filas por importación' using errcode = '22023'; end if;

  for f in select * from jsonb_array_elements(p_filas) loop
    v_cod := nullif(btrim(coalesce(f->>'codigo', '')), '');
    v_nproy := btrim(coalesce(f->>'proyecto', ''));
    if v_cod is null then raise exception 'Fila %: falta el código', coalesce(f->>'fila', '?') using errcode = '22023'; end if;
    v_proy := public._unidad_proyecto(v_nproy);   -- proyecto que no existe o no ves: falla la importación entera
    v_mon := upper(nullif(btrim(coalesce(f->>'moneda', '')), ''));
    if f ? 'moneda' and v_mon not in ('EUR', 'USD', 'AUD', 'IDR') then
      raise exception 'Fila %: moneda no válida', coalesce(f->>'fila', '?') using errcode = '22023';
    end if;

    select * into v_old from public.unidades u where u.proyecto = v_nproy and u.codigo = v_cod for update;
    if not found then
      insert into public.unidades (codigo, proyecto, tipo, modelo, superficie_m2, precio_suelo, precio_construccion,
                                   moneda, notas, fase_masterplan, zona_masterplan)
      -- 'parcela' = el DEFAULT de la columna tipo
      values (v_cod, v_nproy, coalesce(f->>'tipo', 'parcela'), nullif(btrim(coalesce(f->>'modelo', '')), ''),
              nullif(f->>'superficie_m2', '')::numeric, nullif(f->>'precio_suelo', '')::numeric,
              nullif(f->>'precio_construccion', '')::numeric, coalesce(v_mon, 'EUR'),
              nullif(btrim(coalesce(f->>'notas', '')), ''),
              nullif(btrim(coalesce(f->>'fase_masterplan', '')), ''), nullif(btrim(coalesce(f->>'zona_masterplan', '')), ''));
      v_alta := v_alta + 1;
      continue;
    end if;
    if not public.unidad_visible(v_old.proyecto_id) then
      raise exception 'Fila %: no trabajas en el proyecto de esa parcela', coalesce(f->>'fila', '?') using errcode = '42501';
    end if;
    -- parcela con contrato: por CSV nunca se cambia dinero ni identidad (Administración); se informa
    v_dinero := '{}';
    if v_old.contrato_id is not null then
      foreach k in array array['superficie_m2', 'precio_suelo', 'precio_construccion', 'moneda'] loop
        if f ? k then v_dinero := v_dinero || k; end if;
      end loop;
      if array_length(v_dinero, 1) > 0 then
        v_rech := v_rech || jsonb_build_object('fila', f->'fila', 'codigo', v_cod, 'proyecto', v_nproy,
                    'motivo', 'tiene contrato: no se cambia ' || array_to_string(v_dinero, ', '));
      end if;
    end if;
    update public.unidades u
       set tipo = case when f ? 'tipo' then f->>'tipo' else u.tipo end,
           modelo = case when f ? 'modelo' then nullif(btrim(coalesce(f->>'modelo', '')), '') else u.modelo end,
           notas = case when f ? 'notas' then nullif(btrim(coalesce(f->>'notas', '')), '') else u.notas end,
           fase_masterplan = case when f ? 'fase_masterplan' then nullif(btrim(coalesce(f->>'fase_masterplan', '')), '') else u.fase_masterplan end,
           zona_masterplan = case when f ? 'zona_masterplan' then nullif(btrim(coalesce(f->>'zona_masterplan', '')), '') else u.zona_masterplan end,
           superficie_m2 = case when v_old.contrato_id is null and f ? 'superficie_m2' then nullif(f->>'superficie_m2', '')::numeric else u.superficie_m2 end,
           precio_suelo = case when v_old.contrato_id is null and f ? 'precio_suelo' then nullif(f->>'precio_suelo', '')::numeric else u.precio_suelo end,
           precio_construccion = case when v_old.contrato_id is null and f ? 'precio_construccion' then nullif(f->>'precio_construccion', '')::numeric else u.precio_construccion end,
           moneda = case when v_old.contrato_id is null and f ? 'moneda' then v_mon else u.moneda end
     where u.id = v_old.id;
    insert into public.unidades_log (unidad_id, antes, despues, via)
    select v_old.id, to_jsonb(v_old), to_jsonb(u), 'csv' from public.unidades u where u.id = v_old.id;
    v_act := v_act + 1;
  end loop;
  return jsonb_build_object('creadas', v_alta, 'actualizadas', v_act, 'rechazadas', v_rech);
end $$;
revoke all on function public.unidades_importa(jsonb) from public, anon;
grant execute on function public.unidades_importa(jsonb) to authenticated;

-- ── proyectos ─────────────────────────────────────────────────────────────────
create or replace function public.proyecto_alta(p_nombre text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v uuid; v_nom text := btrim(coalesce(p_nombre, ''));
begin
  if not public.es_admin() then raise exception 'Dar de alta un proyecto es cosa de un administrador. Pídeselo a dirección.' using errcode = '42501'; end if;
  if v_nom = '' or length(v_nom) > 120 then raise exception 'El nombre no puede quedar vacío' using errcode = '22023'; end if;
  if v_nom ~ '^[=+\-@]' then raise exception 'El nombre no puede empezar por = + - @' using errcode = '22023'; end if;
  if exists (select 1 from public.proyectos p where lower(p.nombre) = lower(v_nom)) then
    raise exception 'Ya existe un proyecto con ese nombre.' using errcode = '23505';
  end if;
  insert into public.proyectos (nombre, creado_por) values (v_nom, (select auth.email())) returning id into v;
  return v;
end $$;
revoke all on function public.proyecto_alta(text) from public, anon;
grant execute on function public.proyecto_alta(text) to authenticated;

-- Ficha del proyecto. Nombre, estado y activo tienen su propia función: aquí no.
create or replace function public.proyecto_guarda(p_id uuid, p_cambios jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare v_old public.proyectos%rowtype; v_fecha date; v_pct numeric; v_slug text;
begin
  if not public.es_admin() then raise exception 'La ficha del proyecto la edita un administrador' using errcode = '42501'; end if;
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
         -- «cuándo se fijó» lo pone el servidor, solo si la fecha cambia de verdad
         fecha_entrega_estimada_fijada_en = case
             when p_cambios ? 'fecha_entrega_estimada_proyecto' and v_fecha is distinct from p.fecha_entrega_estimada_proyecto
             then case when v_fecha is null then null else current_date end
             else p.fecha_entrega_estimada_fijada_en end,
         pct_minimo_inicio = case when p_cambios ? 'pct_minimo_inicio' then v_pct else p.pct_minimo_inicio end,
         slug = case when p_cambios ? 'slug' then v_slug else p.slug end
   where p.id = p_id;
end $$;
revoke all on function public.proyecto_guarda(uuid, jsonb) from public, anon;
grant execute on function public.proyecto_guarda(uuid, jsonb) to authenticated;

create or replace function public.tipo_vivienda_alta(p_clave text, p_etiqueta text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_cl text := btrim(coalesce(p_clave, '')); v_et text := btrim(coalesce(p_etiqueta, ''));
begin
  if not (public.es_agente() and public.puede('unidades')) then raise exception 'No tienes la herramienta Unidades' using errcode = '42501'; end if;
  if v_cl !~ '^[a-z0-9_]{1,40}$' then raise exception 'Ese nombre no da una clave válida' using errcode = '22023'; end if;
  if v_et = '' or length(v_et) > 60 or v_et ~ '^[=+\-@]' then raise exception 'El nombre del tipo no es válido' using errcode = '22023'; end if;
  if exists (select 1 from public.tipos_vivienda t where t.clave = v_cl) then
    raise exception 'Ya existe un tipo con esa clave.' using errcode = '23505';
  end if;
  insert into public.tipos_vivienda (clave, etiqueta) values (v_cl, v_et);
end $$;
revoke all on function public.tipo_vivienda_alta(text, text) from public, anon;
grant execute on function public.tipo_vivienda_alta(text, text) to authenticated;
