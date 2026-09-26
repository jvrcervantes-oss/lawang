-- destructivo-ok: crea la tabla modelos_precios_log y funciones; sustituye deck_foto_fijar_vista (INVOKER → DEFINER con permiso dentro); no borra ni cambia ninguna fila.
-- Frontera frontend/backend — bloque 3: MODELOS, PRECIOS y DECK (27-sep-2026, LAW-336 / LAW-331).
-- SOLO AÑADE; el cierre (revoke + quitar las policies de escritura de las 11 tablas y de los buckets `modelos`
-- y `deck`) va aparte cuando las pantallas servidas ya no escriban directo. Plan y revisión previa #126
-- (Seguridad + Administración), que manda sobre el plan: encargos/20260927_lawang_frontera_b3_modelos_deck.md
--
-- Qué cierra (con el cierre):
-- · El cambio de precio base era una CADENA de hasta 5 tipos de escritura desde el navegador con «deshacer» a
--   mano: si fallaba a mitad y el deshacer también, quedaba un modelo con base nueva y techos viejos. Ahora es
--   UNA transacción (`modelo_precios_guarda`) y la diferencia de techos la calcula el servidor.
-- · Los importes, la moneda y los ids los decidía la pantalla: ahora se validan aquí (importe > 0 y con techo
--   razonable POR MONEDA, moneda de lista cerrada, ids filtrados por modelo y contados).
-- · `contratos_diseno` lo escribía cualquier agente con cualquier cosa dentro, y ese jsonb se pega sin escapar
--   en el CSS del documento que ve el cliente (baliza/inyección). Ahora solo admin (medido: último cambio el
--   5-ago-2026, ningún agente lo usa) y lista blanca de la forma entera.
-- · Las fotos del deck (bucket PÚBLICO) y los documentos de modelo (planos = anexo del contrato) se suben por
--   la edge `ficheros`: ruta del servidor, permiso antes de subir, bytes mágicos, registro solo por la edge.
--
-- EL DATO TIENE UN DUEÑO:
-- · `modelos.precio_construccion` + `modelos.moneda` son de administración y mandan. `modelo_techos` NO tiene
--   moneda: hereda la del modelo. `modelos_villa.precio_construccion` NULL = hereda la base (resolución única
--   en contracts/assets/modelos_catalogo.js); con cifra, su `moneda` es SIEMPRE la del modelo (se reescribe
--   junta: el par número+moneda no se separa, lección LAW-331).
-- · Los contratos NO firmados guardan una COPIA congelada del precio elegido en pantalla (techo_extras.js): no
--   se recalculan solos (recalcular = cambiar un precio que el cliente vio, hard-stop del owner).
--   `modelo_precios_guarda` devuelve cuántos contratos no firmados cuelgan de una unidad de este modelo, como
--   MÍNIMO medible (los de construcción sin unidad enlazada no se pueden atribuir a un modelo).
-- · `modelos_precios_log` es historial (copia congelada con ids): qué, antes, después, moneda, quién (del
--   servidor) y cuándo. Lo escriben estas funciones en la misma transacción; nadie más.

-- ── historial de precios ────────────────────────────────────────────────────────────────────────────────
create table if not exists public.modelos_precios_log (
  id bigint generated always as identity primary key,
  modelo_id uuid,
  proyecto_id uuid,
  tabla text not null,
  fila_id uuid,
  campo text not null,
  antes numeric,
  despues numeric,
  moneda text,
  nota text,
  origen text not null,
  quien text,
  quien_uid uuid,
  cuando timestamptz not null default now()
);
create index if not exists modelos_precios_log_modelo_idx on public.modelos_precios_log (modelo_id, cuando desc);
create index if not exists modelos_precios_log_proyecto_idx on public.modelos_precios_log (proyecto_id, cuando desc);
alter table public.modelos_precios_log enable row level security;
revoke all on public.modelos_precios_log from public, anon, authenticated;
grant select on public.modelos_precios_log to authenticated;
drop policy if exists "admins leen el historial de precios" on public.modelos_precios_log;
create policy "admins leen el historial de precios" on public.modelos_precios_log for select to authenticated
  using (public.es_admin());

create or replace function public._precio_log(p_modelo uuid, p_proyecto uuid, p_tabla text, p_fila uuid, p_campo text,
  p_antes numeric, p_despues numeric, p_moneda text, p_origen text, p_nota text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_antes is not distinct from p_despues and p_nota is null then return; end if;
  insert into public.modelos_precios_log (modelo_id, proyecto_id, tabla, fila_id, campo, antes, despues, moneda, nota,
                                          origen, quien, quien_uid)
  values (p_modelo, p_proyecto, p_tabla, p_fila, p_campo, p_antes, p_despues, p_moneda, p_nota,
          p_origen, (select auth.email()), (select auth.uid()));
end $$;
revoke all on function public._precio_log(uuid, uuid, text, uuid, text, numeric, numeric, text, text, text) from public, anon, authenticated;

-- ── lectores de jsonb (una sola forma de leer un número / un booleano que llega de la pantalla) ──────────
create or replace function public._lw_num(p_v jsonb, p_campo text) returns numeric
language plpgsql immutable set search_path = '' as $$
declare t text;
begin
  if p_v is null or jsonb_typeof(p_v) = 'null' then return null; end if;
  t := btrim(p_v #>> '{}');
  if jsonb_typeof(p_v) = 'string' and t = '' then return null; end if;
  if jsonb_typeof(p_v) in ('number', 'string') and t ~ '^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$' then
    return t::numeric;
  end if;
  raise exception '% no es un número válido', p_campo using errcode = '22023';
end $$;
revoke all on function public._lw_num(jsonb, text) from public, anon, authenticated;

create or replace function public._lw_bool(p_v jsonb, p_campo text) returns boolean
language plpgsql immutable set search_path = '' as $$
begin
  if p_v is null or jsonb_typeof(p_v) = 'null' then return null; end if;
  if jsonb_typeof(p_v) = 'boolean' then return (p_v #>> '{}')::boolean; end if;
  raise exception '% tiene que ser sí o no', p_campo using errcode = '22023';
end $$;
revoke all on function public._lw_bool(jsonb, text) from public, anon, authenticated;

-- Importe de construcción válido: > 0, finito y con techo razonable POR MONEDA (medido 27-sep: EUR hasta
-- 169.000, IDR hasta 1.726.000.000). El techo es un freno contra un cero de más, no un precio.
create or replace function public._lw_importe_ok(p numeric, p_moneda text) returns boolean
language sql immutable set search_path = '' as $$
  select p is not null and p > 0
     and p < case p_moneda when 'IDR' then 500000000000::numeric else 50000000::numeric end
$$;
revoke all on function public._lw_importe_ok(numeric, text) from public, anon, authenticated;

-- Texto de una lista blanca jsonb {es,en,id} → objeto limpio (recortado, sin vacíos, con tope).
create or replace function public._lw_idiomas(p jsonb, p_campo text, p_max int) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare k text; v jsonb := '{}'::jsonb; t text;
begin
  if p is null or jsonb_typeof(p) = 'null' then return '{}'::jsonb; end if;
  if jsonb_typeof(p) <> 'object' then raise exception '% no es válido', p_campo using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('es', 'en', 'id') then raise exception '%: idioma no admitido (%)', p_campo, k using errcode = '22023'; end if;
    if jsonb_typeof(p->k) not in ('string', 'null') then raise exception '% no es texto', p_campo using errcode = '22023'; end if;
    t := btrim(coalesce(p->>k, ''));
    if length(t) > p_max then raise exception '% es demasiado largo (máximo % caracteres)', p_campo, p_max using errcode = '22023'; end if;
    if t <> '' then v := v || jsonb_build_object(k, t); end if;
  end loop;
  return v;
end $$;
revoke all on function public._lw_idiomas(jsonb, text, int) from public, anon, authenticated;

-- ── ficha del modelo (todo menos el precio) ─────────────────────────────────────────────────────────────
-- Alta (p_id null: nombre y slug; precio y moneda solo aquí, sin nada que dependa aún) o edición con lista
-- blanca. Clave ausente = no se toca. `actualizado_en` y `orden` del servidor.
create or replace function public.modelo_guarda(p_id uuid, p_cambios jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_old public.modelos%rowtype; v_id uuid; k text; j jsonb; e jsonb; x text;
  v_ok text[] := array['nombre', 'slug', 'dormitorios', 'banos', 'villa_m2', 'terraza_m2', 'descripcion', 'publicado',
                       'activo', 'renders_pendientes', 'notas', 'alcance', 'acabados'];
  v_nombre text; v_slug text; v_dorm numeric; v_banos numeric; v_villa numeric; v_terraza numeric;
  v_desc text; v_notas text; v_alcance jsonb; v_acabados jsonb; v_inc jsonb; v_noinc jsonb;
  v_precio numeric; v_moneda text;
begin
  if not public.es_admin() then raise exception 'Los modelos los edita administración' using errcode = '42501'; end if;
  if jsonb_typeof(p_cambios) is distinct from 'object' then raise exception 'Datos del modelo no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_cambios) loop
    if k in ('precio_construccion', 'moneda') and p_id is not null then
      raise exception 'El precio base y la moneda se cambian en el bloque de precios (mueve también los techos)' using errcode = '22023';
    end if;
    if not (k = any (v_ok) or (p_id is null and k in ('precio_construccion', 'moneda'))) then
      raise exception 'Ese dato del modelo no se edita desde aquí: %', k using errcode = '22023';
    end if;
  end loop;

  if p_id is not null then
    select * into v_old from public.modelos m where m.id = p_id for update;
    if not found then raise exception 'Ese modelo ya no existe: recarga la página' using errcode = '22023'; end if;
  end if;

  -- nombre y dirección
  v_nombre := case when p_cambios ? 'nombre' then btrim(coalesce(p_cambios->>'nombre', '')) else v_old.nombre end;
  if v_nombre is null or v_nombre = '' then raise exception 'El nombre no puede quedar vacío' using errcode = '22023'; end if;
  if length(v_nombre) > 80 then raise exception 'El nombre es demasiado largo' using errcode = '22023'; end if;
  v_slug := case when p_cambios ? 'slug' then lower(btrim(coalesce(p_cambios->>'slug', ''))) else v_old.slug end;
  if v_slug is null or v_slug !~ '^[a-z0-9-]{2,60}$' then
    raise exception 'La dirección solo admite minúsculas, números y guiones (de 2 a 60)' using errcode = '22023';
  end if;
  if p_id is not null and v_slug <> v_old.slug and v_old.publicado then
    raise exception 'El modelo está publicado: cambiar su dirección rompe /modelo/% y los anuncios que apunten ahí. Despublícalo primero.', v_old.slug
      using errcode = '22023';
  end if;

  -- ficha técnica
  v_dorm := case when p_cambios ? 'dormitorios' then public._lw_num(p_cambios->'dormitorios', 'Dormitorios') else v_old.dormitorios end;
  v_banos := case when p_cambios ? 'banos' then public._lw_num(p_cambios->'banos', 'Baños') else v_old.banos end;
  v_villa := case when p_cambios ? 'villa_m2' then public._lw_num(p_cambios->'villa_m2', 'Villa (m²)') else v_old.villa_m2 end;
  v_terraza := case when p_cambios ? 'terraza_m2' then public._lw_num(p_cambios->'terraza_m2', 'Terraza (m²)') else v_old.terraza_m2 end;
  if v_dorm is not null and (v_dorm < 0 or v_dorm > 30 or v_dorm <> trunc(v_dorm)) then raise exception 'Dormitorios: un número entero entre 0 y 30' using errcode = '22023'; end if;
  if v_banos is not null and (v_banos < 0 or v_banos > 30 or v_banos <> trunc(v_banos)) then raise exception 'Baños: un número entero entre 0 y 30' using errcode = '22023'; end if;
  if v_villa is not null and (v_villa <= 0 or v_villa > 100000) then raise exception 'La superficie de la villa no es válida' using errcode = '22023'; end if;
  if v_terraza is not null and (v_terraza < 0 or v_terraza > 100000) then raise exception 'La superficie de la terraza no es válida' using errcode = '22023'; end if;

  v_desc := case when p_cambios ? 'descripcion' then nullif(btrim(coalesce(p_cambios->>'descripcion', '')), '') else v_old.descripcion end;
  v_notas := case when p_cambios ? 'notas' then nullif(btrim(coalesce(p_cambios->>'notas', '')), '') else v_old.notas end;
  if length(coalesce(v_desc, '')) > 6000 or length(coalesce(v_notas, '')) > 6000 then
    raise exception 'El texto es demasiado largo (máximo 6000 caracteres)' using errcode = '22023';
  end if;

  -- «la obra incluye»: {incluido:[texto], no_incluido:[texto]} o nada (vacío tiene que significar vacío: la
  -- ficha pública pregunta por !empty($m['alcance']))
  if p_cambios ? 'alcance' then
    j := p_cambios->'alcance';
    if j is null or jsonb_typeof(j) = 'null' then v_alcance := null;
    else
      if jsonb_typeof(j) <> 'object' then raise exception '«La obra incluye» no es válido' using errcode = '22023'; end if;
      for k in select jsonb_object_keys(j) loop
        if k not in ('incluido', 'no_incluido') then raise exception '«La obra incluye» no es válido' using errcode = '22023'; end if;
      end loop;
      v_inc := '[]'::jsonb; v_noinc := '[]'::jsonb;
      foreach k in array array['incluido', 'no_incluido'] loop
        if j ? k and jsonb_typeof(j->k) <> 'null' then
          if jsonb_typeof(j->k) <> 'array' or jsonb_array_length(j->k) > 80 then raise exception '«La obra incluye» no es válido' using errcode = '22023'; end if;
          for e in select * from jsonb_array_elements(j->k) loop
            if jsonb_typeof(e) <> 'string' then raise exception '«La obra incluye»: cada punto es un texto' using errcode = '22023'; end if;
            x := btrim(e #>> '{}');
            if length(x) > 600 then raise exception '«La obra incluye»: un punto es demasiado largo' using errcode = '22023'; end if;
            if x <> '' then
              if k = 'incluido' then v_inc := v_inc || to_jsonb(x); else v_noinc := v_noinc || to_jsonb(x); end if;
            end if;
          end loop;
        end if;
      end loop;
      v_alcance := case when jsonb_array_length(v_inc) + jsonb_array_length(v_noinc) = 0 then null
                        else jsonb_build_object('incluido', v_inc, 'no_incluido', v_noinc) end;
    end if;
  else
    v_alcance := v_old.alcance;
  end if;

  -- acabados de la web: [{n, d, n_en?, d_en?}] (modelo/catalogo.php deriva n_en/d_en si faltan)
  if p_cambios ? 'acabados' then
    j := p_cambios->'acabados';
    if j is null or jsonb_typeof(j) = 'null' then v_acabados := null;
    else
      if jsonb_typeof(j) <> 'array' or jsonb_array_length(j) > 40 then raise exception 'Los acabados no son válidos' using errcode = '22023'; end if;
      v_acabados := '[]'::jsonb;
      for e in select * from jsonb_array_elements(j) loop
        if jsonb_typeof(e) <> 'object' then raise exception 'Los acabados no son válidos' using errcode = '22023'; end if;
        for k in select jsonb_object_keys(e) loop
          if k not in ('n', 'd', 'n_en', 'd_en') or jsonb_typeof(e->k) not in ('string', 'null') or length(coalesce(e->>k, '')) > 600 then
            raise exception 'Los acabados no son válidos' using errcode = '22023';
          end if;
        end loop;
        if btrim(coalesce(e->>'n', '')) <> '' then
          v_acabados := v_acabados || jsonb_strip_nulls(jsonb_build_object(
            'n', btrim(e->>'n'), 'd', nullif(btrim(coalesce(e->>'d', '')), ''),
            'n_en', nullif(btrim(coalesce(e->>'n_en', '')), ''), 'd_en', nullif(btrim(coalesce(e->>'d_en', '')), '')));
        end if;
      end loop;
      if jsonb_array_length(v_acabados) = 0 then v_acabados := null; end if;
    end if;
  else
    v_acabados := v_old.acabados;
  end if;

  if p_id is null then
    v_moneda := upper(btrim(coalesce(p_cambios->>'moneda', 'EUR')));
    if v_moneda not in ('EUR', 'USD', 'AUD', 'IDR') then raise exception 'Moneda no admitida (EUR, USD, AUD o IDR)' using errcode = '22023'; end if;
    v_precio := public._lw_num(p_cambios->'precio_construccion', 'El precio de construcción');
    if v_precio is not null and not public._lw_importe_ok(v_precio, v_moneda) then
      raise exception 'El precio de construcción tiene que ser mayor que cero (y razonable en %)', v_moneda using errcode = '22023';
    end if;
    begin
      insert into public.modelos (nombre, slug, dormitorios, banos, villa_m2, terraza_m2, descripcion, notas, alcance, acabados,
                                  precio_construccion, moneda, publicado, activo, renders_pendientes, orden, actualizado_en)
      values (v_nombre, v_slug, v_dorm, v_banos, v_villa, v_terraza, v_desc, v_notas, v_alcance, v_acabados, v_precio, v_moneda,
              coalesce(public._lw_bool(p_cambios->'publicado', 'Publicado'), false),
              coalesce(public._lw_bool(p_cambios->'activo', 'Activo'), true),
              coalesce(public._lw_bool(p_cambios->'renders_pendientes', 'Renders pendientes'), false),
              (select coalesce(max(m.orden), 0) + 1 from public.modelos m), now())
      returning id into v_id;
    exception when unique_violation then
      raise exception 'Ya hay un modelo en esa dirección (%): elige otra', v_slug using errcode = '23505';
    end;
    if v_precio is not null then
      perform public._precio_log(v_id, null, 'modelos', v_id, 'precio_construccion', null, v_precio, v_moneda, 'modelo_guarda', 'alta');
    end if;
    return v_id;
  end if;

  begin
    update public.modelos m
       set nombre = v_nombre, slug = v_slug, dormitorios = v_dorm, banos = v_banos, villa_m2 = v_villa, terraza_m2 = v_terraza,
           descripcion = v_desc, notas = v_notas, alcance = v_alcance, acabados = v_acabados,
           publicado = case when p_cambios ? 'publicado' then coalesce(public._lw_bool(p_cambios->'publicado', 'Publicado'), m.publicado) else m.publicado end,
           activo = case when p_cambios ? 'activo' then coalesce(public._lw_bool(p_cambios->'activo', 'Activo'), m.activo) else m.activo end,
           renders_pendientes = case when p_cambios ? 'renders_pendientes'
                                     then coalesce(public._lw_bool(p_cambios->'renders_pendientes', 'Renders pendientes'), m.renders_pendientes)
                                     else m.renders_pendientes end,
           actualizado_en = now()
     where m.id = p_id;
  exception when unique_violation then
    raise exception 'Ya hay un modelo en esa dirección (%): elige otra', v_slug using errcode = '23505';
  end;
  return p_id;
end $$;
revoke all on function public.modelo_guarda(uuid, jsonb) from public, anon;
grant execute on function public.modelo_guarda(uuid, jsonb) to authenticated;

-- Contratos NO firmados que cuelgan de una unidad de este modelo: MÍNIMO medible (la construcción sin unidad
-- enlazada no se puede atribuir a un modelo; medido 27-sep: 23 de 77 no firmados).
create or replace function public._modelo_contratos_no_firmados(p_modelo uuid) returns int
language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.contratos c join public.unidades u on u.id = c.unidad_id
   where u.modelo_id = p_modelo and not coalesce(c.bloqueado, false)
$$;
revoke all on function public._modelo_contratos_no_firmados(uuid) from public, anon, authenticated;

-- ── precio de construcción: TODO en una transacción ─────────────────────────────────────────────────────
-- p_cambios: {base?, moneda?, desplaza_techos? (sí por defecto), villas?:[{id, precio}], altas?:[{proyecto_id, precio}]}
-- · base y techos van juntos (revisión #56): modelo_techos_opciones() resuelve el techo de un proyecto como
--   precio_techo + (precio_proyecto − base); subir la base sin mover los techos ABARATA el techo precargado.
--   La diferencia la calcula el servidor tras bloquear el modelo, en los dos tramos, sin redondeos.
-- · la moneda no se cambia si el modelo ya tiene techos, extras, precios por proyecto o previsión del deck
--   (cambiaría la unidad sin tocar la cifra: 48.000 EUR leídos como IDR).
-- · ids de villas filtrados por modelo y contados: si alguno no es de este modelo, se aborta todo.
create or replace function public.modelo_precios_guarda(p_id uuid, p_cambios jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_m public.modelos%rowtype; k text; e jsonb; t record; v record;
  v_base numeric; v_mon text; v_d numeric := 0; v_desplaza boolean; v_movidos int := 0;
  v_ids uuid[]; v_n int; v_precio numeric; v_nuevo_a numeric; v_nuevo_z numeric; v_py record; v_fila uuid;
begin
  if not public.es_admin() then raise exception 'Los precios de los modelos los cambia administración' using errcode = '42501'; end if;
  if jsonb_typeof(p_cambios) is distinct from 'object' then raise exception 'Datos de precio no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_cambios) loop
    if k not in ('base', 'moneda', 'desplaza_techos', 'villas', 'altas') then
      raise exception 'Ese dato de precio no se edita desde aquí: %', k using errcode = '22023';
    end if;
  end loop;
  select * into v_m from public.modelos m where m.id = p_id for update;
  if not found then raise exception 'Ese modelo ya no existe: recarga la página' using errcode = '22023'; end if;

  v_base := case when p_cambios ? 'base' then public._lw_num(p_cambios->'base', 'El precio base') else v_m.precio_construccion end;
  v_mon := case when p_cambios ? 'moneda' then upper(btrim(coalesce(p_cambios->>'moneda', ''))) else coalesce(v_m.moneda, 'EUR') end;
  if v_mon not in ('EUR', 'USD', 'AUD', 'IDR') then raise exception 'Moneda no admitida (EUR, USD, AUD o IDR)' using errcode = '22023'; end if;
  if v_base is not null and not public._lw_importe_ok(v_base, v_mon) then
    raise exception 'El precio base tiene que ser mayor que cero (y razonable en %)', v_mon using errcode = '22023';
  end if;

  if v_mon <> coalesce(v_m.moneda, 'EUR') and (
       exists (select 1 from public.modelo_techos x where x.modelo_id = p_id)
    or exists (select 1 from public.modelo_extras x where x.modelo_id = p_id)
    or exists (select 1 from public.modelos_villa x where x.modelo_id = p_id)
    or exists (select 1 from public.deck_forecast x where x.modelo_id = p_id)) then
    raise exception 'La moneda no se cambia: el modelo ya tiene techos, extras, precios por proyecto o previsión del deck en %, y cambiarla cambiaría la unidad sin tocar la cifra', coalesce(v_m.moneda, 'EUR')
      using errcode = '22023';
  end if;

  if v_base is distinct from v_m.precio_construccion or v_mon <> coalesce(v_m.moneda, 'EUR') then
    update public.modelos set precio_construccion = v_base, moneda = v_mon, actualizado_en = now() where id = p_id;
    perform public._precio_log(p_id, null, 'modelos', p_id, 'precio_construccion', v_m.precio_construccion, v_base, v_mon, 'modelo_precios_guarda');
    if v_mon <> coalesce(v_m.moneda, 'EUR') then
      perform public._precio_log(p_id, null, 'modelos', p_id, 'moneda', null, null, v_mon, 'modelo_precios_guarda',
                                 'moneda ' || coalesce(v_m.moneda, 'EUR') || ' → ' || v_mon);
    end if;
  end if;

  -- techos: se mueven la misma cantidad que la base (los dos tramos)
  v_desplaza := coalesce(public._lw_bool(p_cambios->'desplaza_techos', 'Mover los techos'), true);
  if v_base is not null and v_m.precio_construccion is not null then v_d := v_base - v_m.precio_construccion; end if;
  if v_d <> 0 and v_desplaza then
    for t in select * from public.modelo_techos x where x.modelo_id = p_id order by x.orden nulls last, x.clave for update loop
      v_nuevo_a := case when t.precio_ahora is null then null else t.precio_ahora + v_d end;
      v_nuevo_z := case when t.precio_2027 is null then null else t.precio_2027 + v_d end;
      if (v_nuevo_a is not null and not public._lw_importe_ok(v_nuevo_a, v_mon))
         or (v_nuevo_z is not null and not public._lw_importe_ok(v_nuevo_z, v_mon)) then
        raise exception 'Mover los techos % dejaría «%» sin un precio válido: revisa el bloque de techos', v_d, t.nombre using errcode = '22023';
      end if;
      update public.modelo_techos set precio_ahora = v_nuevo_a, precio_2027 = v_nuevo_z where id = t.id;
      perform public._precio_log(p_id, null, 'modelo_techos', t.id, 'precio_ahora', t.precio_ahora, v_nuevo_a, v_mon, 'modelo_precios_guarda', 'se mueve con la base');
      perform public._precio_log(p_id, null, 'modelo_techos', t.id, 'precio_2027', t.precio_2027, v_nuevo_z, v_mon, 'modelo_precios_guarda', case when t.precio_2027 is null then null else 'se mueve con la base' end);
      v_movidos := v_movidos + 1;
    end loop;
  end if;

  -- precio por proyecto (NULL = hereda la base)
  if p_cambios ? 'villas' and jsonb_typeof(p_cambios->'villas') <> 'null' then
    if jsonb_typeof(p_cambios->'villas') <> 'array' then raise exception 'Precios por proyecto no válidos' using errcode = '22023'; end if;
    begin
      select array_agg((x->>'id')::uuid) into v_ids from jsonb_array_elements(p_cambios->'villas') x;
    exception when others then raise exception 'Precios por proyecto no válidos' using errcode = '22023';
    end;
    if v_ids is not null then
      if cardinality(v_ids) <> (select count(distinct u) from unnest(v_ids) u) then raise exception 'Hay un proyecto repetido en los precios' using errcode = '22023'; end if;
      select count(*) into v_n from public.modelos_villa x where x.id = any (v_ids) and x.modelo_id = p_id;
      if v_n <> cardinality(v_ids) then
        raise exception 'Alguno de los precios por proyecto no es de este modelo (o ya no existe): recarga la página' using errcode = '22023';
      end if;
      for e in select * from jsonb_array_elements(p_cambios->'villas') loop
        v_precio := public._lw_num(e->'precio', 'El precio por proyecto');
        select * into v from public.modelos_villa x where x.id = (e->>'id')::uuid and x.modelo_id = p_id for update;
        if v_precio is not null and not public._lw_importe_ok(v_precio, v_mon) then
          raise exception 'El precio de «%» tiene que ser mayor que cero (y razonable en %)', v.proyecto, v_mon using errcode = '22023';
        end if;
        update public.modelos_villa set precio_construccion = v_precio, moneda = v_mon where id = v.id;
        perform public._precio_log(p_id, v.proyecto_id, 'modelos_villa', v.id, 'precio_construccion', v.precio_construccion, v_precio, v_mon, 'modelo_precios_guarda',
                                   case when v_precio is null and v.precio_construccion is not null then 'pasa a heredar la base' end);
      end loop;
    end if;
  end if;

  -- declarar el modelo en proyectos nuevos
  if p_cambios ? 'altas' and jsonb_typeof(p_cambios->'altas') <> 'null' then
    if jsonb_typeof(p_cambios->'altas') <> 'array' then raise exception 'Altas por proyecto no válidas' using errcode = '22023'; end if;
    for e in select * from jsonb_array_elements(p_cambios->'altas') loop
      begin
        select p.id, p.nombre into v_py from public.proyectos p where p.id = (e->>'proyecto_id')::uuid;
      exception when others then raise exception 'Proyecto no válido' using errcode = '22023';
      end;
      if v_py.id is null then raise exception 'Ese proyecto no existe: recarga la página' using errcode = '22023'; end if;
      v_precio := public._lw_num(e->'precio', 'El precio por proyecto');
      if v_precio is not null and not public._lw_importe_ok(v_precio, v_mon) then
        raise exception 'El precio de «%» tiene que ser mayor que cero (y razonable en %)', v_py.nombre, v_mon using errcode = '22023';
      end if;
      begin
        insert into public.modelos_villa (proyecto, proyecto_id, modelo, modelo_id, precio_construccion, moneda, notas)
        values (v_py.nombre, v_py.id, v_m.nombre, p_id, v_precio, v_mon,
                'Declarado desde la ficha del modelo el ' || to_char(now() at time zone 'Asia/Makassar', 'YYYY-MM-DD')
                || case when v_precio is null then '. Hereda el precio de catálogo.' else '.' end)
        returning id into v_fila;
      exception when unique_violation then
        raise exception 'El modelo ya está declarado en «%» (quizá desde otra pestaña): recarga la página', v_py.nombre using errcode = '23505';
      end;
      perform public._precio_log(p_id, v_py.id, 'modelos_villa', v_fila, 'precio_construccion', null, v_precio, v_mon, 'modelo_precios_guarda',
                                 'declarado en el proyecto' || case when v_precio is null then ', hereda la base' else '' end);
    end loop;
  end if;

  -- nadie se queda heredando una base vacía
  if v_base is null and exists (select 1 from public.modelos_villa x where x.modelo_id = p_id and x.precio_construccion is null) then
    raise exception 'Hay proyectos que heredan el precio base: ponles precio propio antes de dejar la base vacía' using errcode = '22023';
  end if;

  return jsonb_build_object('ok', true, 'base', v_base, 'moneda', v_mon, 'techos_movidos', v_movidos,
                            'contratos_no_firmados_min', public._modelo_contratos_no_firmados(p_id));
end $$;
revoke all on function public.modelo_precios_guarda(uuid, jsonb) from public, anon;
grant execute on function public.modelo_precios_guarda(uuid, jsonb) to authenticated;

-- ── techos (precio completo de la villa con ese acabado) ─────────────────────────────────────────────────
-- p_techos: [{id, precio_ahora?, precio_2027?}] — clave ausente = no se toca; ids de ESTE modelo y contados.
create or replace function public.modelo_techos_guarda(p_id uuid, p_techos jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare v_m public.modelos%rowtype; e jsonb; t record; v_ids uuid[]; v_n int; v_a numeric; v_z numeric; k text;
begin
  if not public.es_admin() then raise exception 'Los precios de los techos los cambia administración' using errcode = '42501'; end if;
  if jsonb_typeof(p_techos) is distinct from 'array' then raise exception 'Techos no válidos' using errcode = '22023'; end if;
  select * into v_m from public.modelos m where m.id = p_id for update;
  if not found then raise exception 'Ese modelo ya no existe: recarga la página' using errcode = '22023'; end if;
  begin
    select array_agg((x->>'id')::uuid) into v_ids from jsonb_array_elements(p_techos) x;
  exception when others then raise exception 'Techos no válidos' using errcode = '22023';
  end;
  if v_ids is null then return 0; end if;
  if cardinality(v_ids) <> (select count(distinct u) from unnest(v_ids) u) then raise exception 'Hay un techo repetido' using errcode = '22023'; end if;
  select count(*) into v_n from public.modelo_techos x where x.id = any (v_ids) and x.modelo_id = p_id;
  if v_n <> cardinality(v_ids) then raise exception 'Alguno de los techos no es de este modelo (o ya no existe): recarga la página' using errcode = '22023'; end if;
  for e in select * from jsonb_array_elements(p_techos) loop
    for k in select jsonb_object_keys(e) loop
      if k not in ('id', 'precio_ahora', 'precio_2027') then raise exception 'Ese dato del techo no se edita desde aquí: %', k using errcode = '22023'; end if;
    end loop;
    select * into t from public.modelo_techos x where x.id = (e->>'id')::uuid for update;
    v_a := case when e ? 'precio_ahora' then public._lw_num(e->'precio_ahora', 'El precio ahora') else t.precio_ahora end;
    v_z := case when e ? 'precio_2027' then public._lw_num(e->'precio_2027', 'El precio 2027') else t.precio_2027 end;
    if not public._lw_importe_ok(v_a, coalesce(v_m.moneda, 'EUR')) then
      raise exception '«%» necesita un precio ahora mayor que cero (y razonable en %)', t.nombre, coalesce(v_m.moneda, 'EUR') using errcode = '22023';
    end if;
    if v_z is not null and not public._lw_importe_ok(v_z, coalesce(v_m.moneda, 'EUR')) then
      raise exception 'El precio 2027 de «%» tiene que ser mayor que cero', t.nombre using errcode = '22023';
    end if;
    update public.modelo_techos set precio_ahora = v_a, precio_2027 = v_z where id = t.id;
    perform public._precio_log(p_id, null, 'modelo_techos', t.id, 'precio_ahora', t.precio_ahora, v_a, v_m.moneda, 'modelo_techos_guarda');
    perform public._precio_log(p_id, null, 'modelo_techos', t.id, 'precio_2027', t.precio_2027, v_z, v_m.moneda, 'modelo_techos_guarda');
  end loop;
  return cardinality(v_ids);
end $$;
revoke all on function public.modelo_techos_guarda(uuid, jsonb) from public, anon;
grant execute on function public.modelo_techos_guarda(uuid, jsonb) to authenticated;

-- ── extras del modelo ───────────────────────────────────────────────────────────────────────────────────
-- p_extras: [{extra_id, precio?, disponible?}] — upsert por (modelo, extra); sin fila = «se ofrece, sin precio
-- propio». La moneda es SIEMPRE la del modelo.
create or replace function public.modelo_extras_guarda(p_id uuid, p_extras jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare v_m public.modelos%rowtype; e jsonb; k text; v_ex uuid; v_old public.modelo_extras%rowtype; v_p numeric; v_d boolean; v_n int := 0; v_fila uuid;
begin
  if not public.es_admin() then raise exception 'Los extras de los modelos los cambia administración' using errcode = '42501'; end if;
  if jsonb_typeof(p_extras) is distinct from 'array' then raise exception 'Extras no válidos' using errcode = '22023'; end if;
  select * into v_m from public.modelos m where m.id = p_id for update;
  if not found then raise exception 'Ese modelo ya no existe: recarga la página' using errcode = '22023'; end if;
  for e in select * from jsonb_array_elements(p_extras) loop
    for k in select jsonb_object_keys(e) loop
      if k not in ('extra_id', 'precio', 'disponible') then raise exception 'Ese dato del extra no se edita desde aquí: %', k using errcode = '22023'; end if;
    end loop;
    begin v_ex := (e->>'extra_id')::uuid;
    exception when others then raise exception 'Extra no válido' using errcode = '22023';
    end;
    if v_ex is null or not exists (select 1 from public.extras x where x.id = v_ex) then
      raise exception 'Ese extra no existe en el catálogo: recarga la página' using errcode = '22023';
    end if;
    v_old := null;
    select * into v_old from public.modelo_extras x where x.modelo_id = p_id and x.extra_id = v_ex for update;
    v_p := case when e ? 'precio' then public._lw_num(e->'precio', 'El precio del extra') else v_old.precio end;
    v_d := case when e ? 'disponible' then coalesce(public._lw_bool(e->'disponible', 'Se ofrece'), true) else coalesce(v_old.disponible, true) end;
    if v_p is not null and not public._lw_importe_ok(v_p, coalesce(v_m.moneda, 'EUR')) then
      raise exception 'El precio de un extra tiene que ser mayor que cero (y razonable en %)', coalesce(v_m.moneda, 'EUR') using errcode = '22023';
    end if;
    insert into public.modelo_extras (modelo_id, extra_id, precio, moneda, disponible)
    values (p_id, v_ex, v_p, coalesce(v_m.moneda, 'EUR'), v_d)
    on conflict (modelo_id, extra_id) do update set precio = excluded.precio, moneda = excluded.moneda, disponible = excluded.disponible
    returning id into v_fila;
    perform public._precio_log(p_id, null, 'modelo_extras', v_fila, 'precio', v_old.precio, v_p, v_m.moneda, 'modelo_extras_guarda');
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
revoke all on function public.modelo_extras_guarda(uuid, jsonb) from public, anon;
grant execute on function public.modelo_extras_guarda(uuid, jsonb) to authenticated;

-- ── la ficha entera de la herramienta clásica, en UNA transacción ───────────────────────────────────────
-- La clásica guarda ficha, precio, techos y extras con un solo botón. Orden: ficha → precio (mueve los techos
-- con la base) → techos que el usuario tocó a mano (mandan sobre el desplazamiento) → extras. Si algo falla,
-- no queda nada.
create or replace function public.modelo_ficha_guarda(p_id uuid, p_cambios jsonb, p_precios jsonb, p_techos jsonb, p_extras jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb := '{}'::jsonb;
begin
  if not public.es_admin() then raise exception 'Los modelos los edita administración' using errcode = '42501'; end if;
  if p_cambios is not null and p_cambios <> '{}'::jsonb then perform public.modelo_guarda(p_id, p_cambios); end if;
  if p_precios is not null and p_precios <> '{}'::jsonb then r := public.modelo_precios_guarda(p_id, p_precios); end if;
  if p_techos is not null and jsonb_typeof(p_techos) = 'array' and jsonb_array_length(p_techos) > 0 then perform public.modelo_techos_guarda(p_id, p_techos); end if;
  if p_extras is not null and jsonb_typeof(p_extras) = 'array' and jsonb_array_length(p_extras) > 0 then perform public.modelo_extras_guarda(p_id, p_extras); end if;
  return r || jsonb_build_object('ok', true, 'contratos_no_firmados_min', public._modelo_contratos_no_firmados(p_id));
end $$;
revoke all on function public.modelo_ficha_guarda(uuid, jsonb, jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.modelo_ficha_guarda(uuid, jsonb, jsonb, jsonb, jsonb) to authenticated;

-- ── qué modelos se construyen en un proyecto (declarar / retirar) ───────────────────────────────────────
-- Sustituye al upsert+delete de contracts/assets/modelos_catalogo.js. «En uso» lo decide el servidor: una
-- unidad del proyecto que lo nombra (por id, o por nombre si no está enlazada). Esos no se retiran y se
-- devuelven en `rechazadas` para que la pantalla diga por qué.
create or replace function public.modelos_proyecto_fija(p_proyecto_id uuid, p_modelos uuid[]) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_py record; v_altas int := 0; v_bajas int := 0; v_rech jsonb := '[]'::jsonb; m record; v record; v_quiere uuid[] := coalesce(p_modelos, '{}');
begin
  if not public.es_admin() then raise exception 'Qué modelos se construyen en un proyecto lo decide administración' using errcode = '42501'; end if;
  select p.id, p.nombre into v_py from public.proyectos p where p.id = p_proyecto_id for update;
  if v_py.id is null then raise exception 'Ese proyecto no existe: recarga la página' using errcode = '22023'; end if;
  if exists (select 1 from unnest(v_quiere) q where not exists (select 1 from public.modelos mm where mm.id = q)) then
    raise exception 'Alguno de los modelos no existe: recarga la página' using errcode = '22023';
  end if;

  for m in select mm.id, mm.nombre, mm.moneda from public.modelos mm
            where mm.id = any (v_quiere)
              and not exists (select 1 from public.modelos_villa x
                               where x.modelo_id = mm.id and (x.proyecto_id = v_py.id or (x.proyecto_id is null and x.proyecto = v_py.nombre)))
  loop
    begin
      insert into public.modelos_villa (proyecto, proyecto_id, modelo, modelo_id, precio_construccion, moneda, notas)
      values (v_py.nombre, v_py.id, m.nombre, m.id, null, coalesce(m.moneda, 'EUR'),
              'Declarado desde la ficha del proyecto el ' || to_char(now() at time zone 'Asia/Makassar', 'YYYY-MM-DD') || '. Hereda el precio de catálogo.');
    exception when unique_violation then null;   /* MUDO A PROPOSITO: ya estaba declarado (otra pestaña); el resultado es el mismo */
    end;
    v_altas := v_altas + 1;
  end loop;

  for v in select x.* from public.modelos_villa x
            where (x.proyecto_id = v_py.id or (x.proyecto_id is null and x.proyecto = v_py.nombre))
              and x.modelo_id is not null and not (x.modelo_id = any (v_quiere))
            for update
  loop
    if exists (select 1 from public.unidades u
                where (u.proyecto_id = v_py.id or u.proyecto = v_py.nombre)
                  and (u.modelo_id = v.modelo_id or (u.modelo_id is null and public.modelo_norm(u.modelo) = public.modelo_norm(v.modelo)))) then
      v_rech := v_rech || jsonb_build_object('id', v.id, 'modelo', v.modelo, 'modelo_id', v.modelo_id);
    else
      delete from public.modelos_villa where id = v.id;
      perform public._precio_log(v.modelo_id, v_py.id, 'modelos_villa', v.id, 'precio_construccion', v.precio_construccion, null, v.moneda,
                                 'modelos_proyecto_fija', 'retirado del proyecto');
      v_bajas := v_bajas + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'altas', v_altas, 'bajas', v_bajas, 'rechazadas', v_rech);
end $$;
revoke all on function public.modelos_proyecto_fija(uuid, uuid[]) from public, anon;
grant execute on function public.modelos_proyecto_fija(uuid, uuid[]) to authenticated;

-- ── documentos de modelo (bucket privado `modelos`) ─────────────────────────────────────────────────────
-- Cualquiera del equipo sube y retipa documentos, SALVO el plano (Anexo Maestro del contrato de
-- Construcción), que es de administración (25-sep-2026). Registrar y borrar: solo la edge `ficheros`.
create or replace function public.modelo_documento_cambia(p_id uuid, p_cambios jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_d public.modelo_documentos%rowtype; k text; v_tipo text; v_techo text;
begin
  if not public.es_agente() then raise exception 'Solo el equipo cambia documentos' using errcode = '42501'; end if;
  if jsonb_typeof(p_cambios) is distinct from 'object' then raise exception 'Datos del documento no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_cambios) loop
    if k not in ('tipo', 'techo_clave') then raise exception 'Ese dato del documento no se edita desde aquí: %', k using errcode = '22023'; end if;
  end loop;
  select * into v_d from public.modelo_documentos d where d.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe: recarga la página' using errcode = '22023'; end if;
  v_tipo := case when p_cambios ? 'tipo' then btrim(coalesce(p_cambios->>'tipo', '')) else v_d.tipo end;
  if v_tipo not in ('plano', 'calidades', 'ficha', 'render', 'otro') then raise exception 'Tipo de documento no válido' using errcode = '22023'; end if;
  v_techo := case when p_cambios ? 'techo_clave' then nullif(btrim(coalesce(p_cambios->>'techo_clave', '')), '') else v_d.techo_clave end;
  if (v_d.tipo = 'plano' or v_tipo = 'plano') and not public.es_admin() then
    raise exception 'El plano (Anexo Maestro del contrato) solo lo cambia administración' using errcode = '42501';
  end if;
  if v_techo is not null and not exists (select 1 from public.modelo_techos t where t.modelo_id = v_d.modelo_id and t.clave = v_techo) then
    raise exception 'Ese techo no es de este modelo' using errcode = '22023';
  end if;
  update public.modelo_documentos set tipo = v_tipo, techo_clave = v_techo where id = p_id;
  return p_id;
end $$;
revoke all on function public.modelo_documento_cambia(uuid, jsonb) from public, anon;
grant execute on function public.modelo_documento_cambia(uuid, jsonb) to authenticated;

create or replace function public.modelo_documento_registra(p_uid uuid, p_modelo uuid, p_path text, p_nombre text, p_tipo text,
  p_techo_clave text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_tam bigint; v_nombre text; v_techo text := nullif(btrim(coalesce(p_techo_clave, '')), '');
begin
  perform public._actua_como(p_uid);
  if not public.es_agente() then raise exception 'Solo el equipo sube documentos' using errcode = '42501'; end if;
  if p_tipo is null or p_tipo not in ('plano', 'calidades', 'ficha', 'render', 'otro') then raise exception 'Tipo de documento no válido' using errcode = '22023'; end if;
  if p_tipo = 'plano' and not public.es_admin() then raise exception 'El plano (Anexo Maestro del contrato) solo lo sube administración' using errcode = '42501'; end if;
  if not exists (select 1 from public.modelos m where m.id = p_modelo) then raise exception 'Ese modelo ya no existe' using errcode = '22023'; end if;
  if p_path is null or p_path !~ ('^' || p_modelo::text || '/[0-9a-f-]{36}\.(pdf|jpg|jpeg|png|webp)$') then
    raise exception 'Ruta de documento no válida' using errcode = '22023';
  end if;
  if v_techo is not null and not exists (select 1 from public.modelo_techos t where t.modelo_id = p_modelo and t.clave = v_techo) then
    raise exception 'Ese techo no es de este modelo' using errcode = '22023';
  end if;
  select (o.metadata->>'size')::bigint into v_tam from storage.objects o where o.bucket_id = 'modelos' and o.name = p_path;
  if not found then raise exception 'El fichero no ha llegado al archivo: vuelve a subirlo' using errcode = '22023'; end if;
  -- el nombre real va en la COLUMNA (la ruta es un uuid): sin caracteres de control, con tope
  v_nombre := left(btrim(regexp_replace(coalesce(p_nombre, ''), '[[:cntrl:]]', '', 'g')), 200);
  if v_nombre = '' then v_nombre := 'Documento'; end if;
  begin
    insert into public.modelo_documentos (modelo_id, nombre, path, tipo, tamano_bytes, subido_por, techo_clave)
    values (p_modelo, v_nombre, p_path, p_tipo, v_tam, p_uid, v_techo)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Ese fichero ya está registrado' using errcode = '23505';
  end;
  return v_id;
end $$;
revoke all on function public.modelo_documento_registra(uuid, uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function public.modelo_documento_registra(uuid, uuid, text, text, text, text) to service_role;

-- Borrar: admin (el borrado del objeto en el bucket era solo de admin; así nunca queda la fila borrada y el
-- fichero huérfano). p_solo_comprobar = true: comprueba y devuelve la ruta sin borrar nada.
create or replace function public.modelo_documento_borra(p_uid uuid, p_id uuid, p_solo_comprobar boolean default false) returns text
language plpgsql security definer set search_path = '' as $$
declare v_d public.modelo_documentos%rowtype;
begin
  perform public._actua_como(p_uid);
  if not public.es_admin() then raise exception 'Borrar documentos de un modelo lo hace administración' using errcode = '42501'; end if;
  select * into v_d from public.modelo_documentos d where d.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe: recarga la página' using errcode = '22023'; end if;
  if not coalesce(p_solo_comprobar, false) then delete from public.modelo_documentos where id = p_id; end if;
  return v_d.path;
end $$;
revoke all on function public.modelo_documento_borra(uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function public.modelo_documento_borra(uuid, uuid, boolean) to service_role;

-- ── fotos del Investor Deck (bucket PÚBLICO `deck`: subir es publicar) ───────────────────────────────────
create or replace function public.deck_foto_registra(p_uid uuid, p_ambito text, p_ref uuid, p_path text, p_nombre text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_pie text; v_orden int;
begin
  perform public._actua_como(p_uid);
  if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;
  if p_ambito not in ('proyecto', 'modelo') then raise exception 'Ámbito de foto no válido' using errcode = '22023'; end if;
  if p_ambito = 'proyecto' and not exists (select 1 from public.proyectos p where p.id = p_ref) then raise exception 'Ese proyecto no existe' using errcode = '22023'; end if;
  if p_ambito = 'modelo' and not exists (select 1 from public.modelos m where m.id = p_ref) then raise exception 'Ese modelo no existe' using errcode = '22023'; end if;
  if p_path is null or p_path !~ ('^' || p_ambito || '/' || p_ref::text || '/[0-9a-f-]{36}\.webp$') then
    raise exception 'Ruta de foto no válida' using errcode = '22023';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'deck' and o.name = p_path) then
    raise exception 'La foto no ha llegado al archivo: vuelve a subirla' using errcode = '22023';
  end if;
  -- Nace con el nombre del fichero como pie en inglés (el CHECK exige `en`): punto de partida para corregir,
  -- sale del nombre que la persona le puso a su propio fichero.
  v_pie := left(btrim(regexp_replace(regexp_replace(regexp_replace(coalesce(p_nombre, ''), '\.[A-Za-z0-9]+$', ''), '[_-]+', ' ', 'g'), '[[:cntrl:]<>]', '', 'g')), 200);
  if v_pie = '' then v_pie := 'Photo'; end if;
  select coalesce(max(f.orden), -1) + 1 into v_orden from public.deck_fotos f
   where (p_ambito = 'proyecto' and f.proyecto_id = p_ref) or (p_ambito = 'modelo' and f.modelo_id = p_ref);
  begin
    insert into public.deck_fotos (ambito, proyecto_id, modelo_id, uso, tipo, path, pie, orden, creado_por)
    values (p_ambito, case when p_ambito = 'proyecto' then p_ref end, case when p_ambito = 'modelo' then p_ref end,
            'galeria', 'foto', p_path, jsonb_build_object('en', v_pie), v_orden, (select auth.email()))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Esa foto ya está registrada' using errcode = '23505';
  end;
  return v_id;
end $$;
revoke all on function public.deck_foto_registra(uuid, text, uuid, text, text) from public, anon, authenticated;
grant execute on function public.deck_foto_registra(uuid, text, uuid, text, text) to service_role;

create or replace function public.deck_foto_borra(p_uid uuid, p_id uuid, p_solo_comprobar boolean default false) returns text
language plpgsql security definer set search_path = '' as $$
declare v_f public.deck_fotos%rowtype;
begin
  perform public._actua_como(p_uid);
  if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;
  select * into v_f from public.deck_fotos f where f.id = p_id for update;
  if not found then raise exception 'Esa foto ya no existe: recarga' using errcode = '22023'; end if;
  if not coalesce(p_solo_comprobar, false) then delete from public.deck_fotos where id = p_id; end if;
  return v_f.path;
end $$;
revoke all on function public.deck_foto_borra(uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function public.deck_foto_borra(uuid, uuid, boolean) to service_role;

-- uso (portada/galería), tipo (foto/render/IA) y pie (en obligatorio)
create or replace function public.deck_foto_cambia(p_id uuid, p_cambios jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_f public.deck_fotos%rowtype; k text; v_uso text; v_tipo text; v_pie jsonb;
begin
  if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;
  if jsonb_typeof(p_cambios) is distinct from 'object' then raise exception 'Datos de la foto no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_cambios) loop
    if k not in ('uso', 'tipo', 'pie') then raise exception 'Ese dato de la foto no se edita desde aquí: %', k using errcode = '22023'; end if;
  end loop;
  select * into v_f from public.deck_fotos f where f.id = p_id for update;
  if not found then raise exception 'Esa foto ya no existe: recarga' using errcode = '22023'; end if;
  v_uso := case when p_cambios ? 'uso' then p_cambios->>'uso' else v_f.uso end;
  v_tipo := case when p_cambios ? 'tipo' then p_cambios->>'tipo' else v_f.tipo end;
  if v_uso not in ('hero', 'galeria') then raise exception 'Uso de la foto no válido' using errcode = '22023'; end if;
  if v_tipo not in ('foto', 'render', 'ia') then raise exception 'Tipo de la foto no válido' using errcode = '22023'; end if;
  if p_cambios ? 'pie' then
    v_pie := public._lw_idiomas(p_cambios->'pie', 'El pie', 300);
    if not v_pie ? 'en' then raise exception 'El pie en inglés no puede quedarse vacío' using errcode = '22023'; end if;
  else
    v_pie := v_f.pie;
  end if;
  update public.deck_fotos set uso = v_uso, tipo = v_tipo, pie = v_pie where id = p_id;
  return p_id;
end $$;
revoke all on function public.deck_foto_cambia(uuid, jsonb) from public, anon;
grant execute on function public.deck_foto_cambia(uuid, jsonb) to authenticated;

-- Reordenar: una posición arriba (-1) o abajo (+1) DENTRO de su mismo uso y dueño; renumera la lista entera
-- en la misma transacción (antes eran dos updates sueltos que podían dejar dos fotos con el mismo orden).
create or replace function public.deck_foto_mueve(p_id uuid, p_delta int) returns void
language plpgsql security definer set search_path = '' as $$
declare v_f public.deck_fotos%rowtype; v_ids uuid[]; v_i int; v_tmp uuid;
begin
  if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;
  if p_delta not in (-1, 1) then raise exception 'Movimiento no válido' using errcode = '22023'; end if;
  select * into v_f from public.deck_fotos f where f.id = p_id for update;
  if not found then raise exception 'Esa foto ya no existe: recarga' using errcode = '22023'; end if;
  select array_agg(f.id order by f.orden, f.id) into v_ids from public.deck_fotos f
   where f.ambito = v_f.ambito and f.uso = v_f.uso
     and f.proyecto_id is not distinct from v_f.proyecto_id and f.modelo_id is not distinct from v_f.modelo_id;
  v_i := array_position(v_ids, p_id);
  if v_i + p_delta < 1 or v_i + p_delta > cardinality(v_ids) then return; end if;
  v_tmp := v_ids[v_i + p_delta]; v_ids[v_i + p_delta] := p_id; v_ids[v_i] := v_tmp;
  update public.deck_fotos f set orden = s.pos - 1
    from unnest(v_ids) with ordinality as s(id, pos) where f.id = s.id and f.orden is distinct from s.pos - 1;
end $$;
revoke all on function public.deck_foto_mueve(uuid, int) from public, anon;
grant execute on function public.deck_foto_mueve(uuid, int) to authenticated;

-- Vista de la foto en la ficha pública del modelo. Era INVOKER y su único candado era la RLS (el `not found`
-- del update): ahora DEFINER con el permiso dentro, como el resto.
create or replace function public.deck_foto_fijar_vista(p_foto uuid, p_vista text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_modelo uuid;
begin
  if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;
  if p_vista is not null and p_vista not in ('planta', 'techo_bambu', 'techo_sirap', 'interior', 'cocina', 'bano', 'aerea') then
    raise exception 'Vista no válida' using errcode = '22023';
  end if;
  select modelo_id into v_modelo from public.deck_fotos where id = p_foto and ambito = 'modelo' for update;
  if v_modelo is null then raise exception 'La foto no existe o no es de un modelo' using errcode = '22023'; end if;
  if p_vista is not null then
    update public.deck_fotos set vista = null where modelo_id = v_modelo and vista = p_vista and id <> p_foto;
  end if;
  update public.deck_fotos set vista = p_vista where id = p_foto;
end $$;
revoke all on function public.deck_foto_fijar_vista(uuid, text) from public, anon;
grant execute on function public.deck_foto_fijar_vista(uuid, text) to authenticated;

-- ── previsión de rentabilidad del deck (par proyecto+modelo) y gastos del proyecto, en UNA transacción ──
-- p_forecast: {adr_medio, adr_optimo, ocupacion_media, ocupacion_optima, inversion_base, destacado, publicado,
-- unidad_referencia_id} · p_gastos: {pct_gestion, pct_mantenimiento, pct_impuesto, contrato_vigente, publicado}.
-- Porcentajes en tanto por uno; ocupación media <= óptima; moneda = la del modelo (y el deck solo publica EUR).
-- La fila con ocupación media 0,05 frente a óptima 0,55 es del owner (LAW pendiente): no se corrige aquí.
create or replace function public.deck_prevision_guarda(p_proyecto_id uuid, p_modelo_id uuid, p_forecast jsonb, p_gastos jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_m public.modelos%rowtype; v_f public.deck_forecast%rowtype; v_g public.deck_forecast_proyecto%rowtype; k text;
  v_adrm numeric; v_adro numeric; v_ocm numeric; v_oco numeric; v_inv numeric; v_dest boolean; v_pub boolean; v_ref uuid;
  v_pg numeric; v_pm numeric; v_pi numeric; v_contr text; v_pubp boolean; v_fid uuid;
begin
  if not public.es_admin() then raise exception 'La previsión del deck la cambia administración' using errcode = '42501'; end if;
  if not exists (select 1 from public.proyectos p where p.id = p_proyecto_id) then raise exception 'Ese proyecto no existe' using errcode = '22023'; end if;

  if p_forecast is not null and jsonb_typeof(p_forecast) <> 'null' then
    if jsonb_typeof(p_forecast) <> 'object' then raise exception 'Previsión no válida' using errcode = '22023'; end if;
    for k in select jsonb_object_keys(p_forecast) loop
      if k not in ('adr_medio', 'adr_optimo', 'ocupacion_media', 'ocupacion_optima', 'inversion_base', 'destacado', 'publicado', 'unidad_referencia_id') then
        raise exception 'Ese dato de la previsión no se edita desde aquí: %', k using errcode = '22023';
      end if;
    end loop;
    select * into v_m from public.modelos m where m.id = p_modelo_id;
    if not found then raise exception 'Ese modelo no existe' using errcode = '22023'; end if;
    if coalesce(v_m.moneda, 'EUR') <> 'EUR' then
      raise exception 'La previsión del deck se publica en EUR y este modelo está en %', v_m.moneda using errcode = '22023';
    end if;
    select * into v_f from public.deck_forecast f where f.proyecto_id = p_proyecto_id and f.modelo_id = p_modelo_id for update;
    v_adrm := case when p_forecast ? 'adr_medio' then public._lw_num(p_forecast->'adr_medio', 'El precio medio/noche') else v_f.adr_medio end;
    v_adro := case when p_forecast ? 'adr_optimo' then public._lw_num(p_forecast->'adr_optimo', 'El precio óptimo') else v_f.adr_optimo end;
    v_ocm := case when p_forecast ? 'ocupacion_media' then public._lw_num(p_forecast->'ocupacion_media', 'La ocupación media') else v_f.ocupacion_media end;
    v_oco := case when p_forecast ? 'ocupacion_optima' then public._lw_num(p_forecast->'ocupacion_optima', 'La ocupación óptima') else v_f.ocupacion_optima end;
    v_inv := case when p_forecast ? 'inversion_base' then public._lw_num(p_forecast->'inversion_base', 'La inversión base') else v_f.inversion_base end;
    if not public._lw_importe_ok(v_adrm, 'EUR') then raise exception 'Falta o no es válido: el precio medio/noche' using errcode = '22023'; end if;
    if not public._lw_importe_ok(v_adro, 'EUR') then raise exception 'Falta o no es válido: el precio óptimo' using errcode = '22023'; end if;
    if not public._lw_importe_ok(v_inv, 'EUR') then raise exception 'Falta o no es válido: la inversión base' using errcode = '22023'; end if;
    if v_ocm is null or not (v_ocm > 0 and v_ocm <= 1) then raise exception 'La ocupación media es un porcentaje entre 0 y 100' using errcode = '22023'; end if;
    if v_oco is null or not (v_oco > 0 and v_oco <= 1) then raise exception 'La ocupación óptima es un porcentaje entre 0 y 100' using errcode = '22023'; end if;
    if v_ocm > v_oco then raise exception 'La ocupación media no puede ser mayor que la óptima' using errcode = '22023'; end if;
    v_dest := case when p_forecast ? 'destacado' then coalesce(public._lw_bool(p_forecast->'destacado', 'Destacado'), false) else coalesce(v_f.destacado, false) end;
    v_pub := case when p_forecast ? 'publicado' then coalesce(public._lw_bool(p_forecast->'publicado', 'Publicado'), false) else coalesce(v_f.publicado, false) end;
    if p_forecast ? 'unidad_referencia_id' then
      begin v_ref := nullif(p_forecast->>'unidad_referencia_id', '')::uuid;
      exception when others then raise exception 'Unidad de referencia no válida' using errcode = '22023';
      end;
      if v_ref is not null and not exists (select 1 from public.unidades u where u.id = v_ref and u.proyecto_id = p_proyecto_id) then
        raise exception 'La unidad de referencia no es de este proyecto' using errcode = '22023';
      end if;
    else
      v_ref := v_f.unidad_referencia_id;
    end if;
    insert into public.deck_forecast (proyecto_id, modelo_id, adr_medio, adr_optimo, ocupacion_media, ocupacion_optima, inversion_base,
                                      unidad_referencia_id, moneda, destacado, publicado, actualizado_en, actualizado_por)
    values (p_proyecto_id, p_modelo_id, v_adrm, v_adro, v_ocm, v_oco, v_inv, v_ref, 'EUR', v_dest, v_pub, now(), (select auth.email()))
    on conflict (proyecto_id, modelo_id) do update
      set adr_medio = excluded.adr_medio, adr_optimo = excluded.adr_optimo, ocupacion_media = excluded.ocupacion_media,
          ocupacion_optima = excluded.ocupacion_optima, inversion_base = excluded.inversion_base,
          unidad_referencia_id = excluded.unidad_referencia_id, moneda = excluded.moneda, destacado = excluded.destacado,
          publicado = excluded.publicado, actualizado_en = excluded.actualizado_en, actualizado_por = excluded.actualizado_por
    returning id into v_fid;
    perform public._precio_log(p_modelo_id, p_proyecto_id, 'deck_forecast', v_fid, 'adr_medio', v_f.adr_medio, v_adrm, 'EUR', 'deck_prevision_guarda');
    perform public._precio_log(p_modelo_id, p_proyecto_id, 'deck_forecast', v_fid, 'adr_optimo', v_f.adr_optimo, v_adro, 'EUR', 'deck_prevision_guarda');
    perform public._precio_log(p_modelo_id, p_proyecto_id, 'deck_forecast', v_fid, 'ocupacion_media', v_f.ocupacion_media, v_ocm, null, 'deck_prevision_guarda');
    perform public._precio_log(p_modelo_id, p_proyecto_id, 'deck_forecast', v_fid, 'ocupacion_optima', v_f.ocupacion_optima, v_oco, null, 'deck_prevision_guarda');
    perform public._precio_log(p_modelo_id, p_proyecto_id, 'deck_forecast', v_fid, 'inversion_base', v_f.inversion_base, v_inv, 'EUR', 'deck_prevision_guarda');
  end if;

  if p_gastos is not null and jsonb_typeof(p_gastos) <> 'null' then
    if jsonb_typeof(p_gastos) <> 'object' then raise exception 'Gastos no válidos' using errcode = '22023'; end if;
    for k in select jsonb_object_keys(p_gastos) loop
      if k not in ('pct_gestion', 'pct_mantenimiento', 'pct_impuesto', 'contrato_vigente', 'publicado') then
        raise exception 'Ese dato de los gastos no se edita desde aquí: %', k using errcode = '22023';
      end if;
    end loop;
    select * into v_g from public.deck_forecast_proyecto g where g.proyecto_id = p_proyecto_id for update;
    v_pg := case when p_gastos ? 'pct_gestion' then public._lw_num(p_gastos->'pct_gestion', 'Gestión') else v_g.pct_gestion end;
    v_pm := case when p_gastos ? 'pct_mantenimiento' then public._lw_num(p_gastos->'pct_mantenimiento', 'Mantenimiento') else v_g.pct_mantenimiento end;
    v_pi := case when p_gastos ? 'pct_impuesto' then public._lw_num(p_gastos->'pct_impuesto', 'Impuesto') else v_g.pct_impuesto end;
    if v_pg is null or v_pm is null or v_pi is null or v_pg < 0 or v_pg > 1 or v_pm < 0 or v_pm > 1 or v_pi < 0 or v_pi > 1 then
      raise exception 'Los porcentajes van entre 0 y 100' using errcode = '22023';
    end if;
    if v_pg + v_pm + v_pi >= 1 then
      raise exception 'Los tres porcentajes juntos se comen el ingreso entero: el neto saldría negativo' using errcode = '22023';
    end if;
    v_contr := case when p_gastos ? 'contrato_vigente' then nullif(btrim(coalesce(p_gastos->>'contrato_vigente', '')), '') else v_g.contrato_vigente end;
    if length(coalesce(v_contr, '')) > 80 then raise exception 'La referencia del contrato de gestión es demasiado larga' using errcode = '22023'; end if;
    v_pubp := case when p_gastos ? 'publicado' then coalesce(public._lw_bool(p_gastos->'publicado', 'Publicado'), false) else coalesce(v_g.publicado, false) end;
    insert into public.deck_forecast_proyecto (proyecto_id, pct_gestion, pct_mantenimiento, pct_impuesto, contrato_vigente, publicado,
                                               actualizado_en, actualizado_por)
    values (p_proyecto_id, v_pg, v_pm, v_pi, v_contr, v_pubp, now(), (select auth.email()))
    on conflict (proyecto_id) do update
      set pct_gestion = excluded.pct_gestion, pct_mantenimiento = excluded.pct_mantenimiento, pct_impuesto = excluded.pct_impuesto,
          contrato_vigente = excluded.contrato_vigente, publicado = excluded.publicado,
          actualizado_en = excluded.actualizado_en, actualizado_por = excluded.actualizado_por;
    perform public._precio_log(null, p_proyecto_id, 'deck_forecast_proyecto', p_proyecto_id, 'pct_gestion', v_g.pct_gestion, v_pg, null, 'deck_prevision_guarda');
    perform public._precio_log(null, p_proyecto_id, 'deck_forecast_proyecto', p_proyecto_id, 'pct_mantenimiento', v_g.pct_mantenimiento, v_pm, null, 'deck_prevision_guarda');
    perform public._precio_log(null, p_proyecto_id, 'deck_forecast_proyecto', p_proyecto_id, 'pct_impuesto', v_g.pct_impuesto, v_pi, null, 'deck_prevision_guarda');
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.deck_prevision_guarda(uuid, uuid, jsonb, jsonb) from public, anon;
grant execute on function public.deck_prevision_guarda(uuid, uuid, jsonb, jsonb) to authenticated;

-- ── configuración del deck de un proyecto (título, meta description, modelo destacado) ──────────────────
-- titulo/meta_desc se MEZCLAN por idioma: las dos pantallas mandan solo `en`, y el upsert de antes pisaba el
-- español y el indonesio. Lista blanca: solo lo que se edita desde una pantalla (kpis, masterplan y tipo de
-- venta no se tocan desde el navegador).
create or replace function public.deck_config_guarda(p_proyecto_id uuid, p_cambios jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_c public.deck_config_proyecto%rowtype; v_hay boolean; k text; v_tit jsonb; v_meta jsonb; v_dest uuid; v_nombre text;
begin
  if not public.es_admin() then raise exception 'Solo un administrador puede editar el Investor Deck' using errcode = '42501'; end if;
  if jsonb_typeof(p_cambios) is distinct from 'object' then raise exception 'Datos del deck no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_cambios) loop
    if k not in ('titulo', 'meta_desc', 'modelo_destacado_id') then raise exception 'Ese dato del deck no se edita desde aquí: %', k using errcode = '22023'; end if;
  end loop;
  select p.nombre into v_nombre from public.proyectos p where p.id = p_proyecto_id;
  if v_nombre is null then raise exception 'Ese proyecto no existe' using errcode = '22023'; end if;
  select * into v_c from public.deck_config_proyecto c where c.proyecto_id = p_proyecto_id for update;
  v_hay := found;
  v_tit := coalesce(v_c.titulo, '{}'::jsonb) || public._lw_idiomas(p_cambios->'titulo', 'El título', 200);
  v_meta := coalesce(v_c.meta_desc, '{}'::jsonb) || public._lw_idiomas(p_cambios->'meta_desc', 'La meta description', 400);
  if not v_tit ? 'en' or not v_meta ? 'en' then raise exception 'Título y meta description (en inglés) son obligatorios' using errcode = '22023'; end if;
  if p_cambios ? 'modelo_destacado_id' then
    begin v_dest := nullif(p_cambios->>'modelo_destacado_id', '')::uuid;
    exception when others then raise exception 'Modelo destacado no válido' using errcode = '22023';
    end;
    if v_dest is not null and not exists (select 1 from public.modelos_villa x where x.modelo_id = v_dest
                                           and (x.proyecto_id = p_proyecto_id or x.proyecto = v_nombre)) then
      raise exception 'El modelo destacado no se construye en este proyecto' using errcode = '22023';
    end if;
  else
    v_dest := v_c.modelo_destacado_id;
  end if;
  insert into public.deck_config_proyecto (proyecto_id, titulo, meta_desc, modelo_destacado_id, actualizado_en, actualizado_por)
  values (p_proyecto_id, v_tit, v_meta, v_dest, now(), (select auth.email()))
  on conflict (proyecto_id) do update
    set titulo = excluded.titulo, meta_desc = excluded.meta_desc, modelo_destacado_id = excluded.modelo_destacado_id,
        actualizado_en = excluded.actualizado_en, actualizado_por = excluded.actualizado_por;
  return p_proyecto_id;
end $$;
revoke all on function public.deck_config_guarda(uuid, jsonb) from public, anon;
grant execute on function public.deck_config_guarda(uuid, jsonb) to authenticated;

-- ── preguntas frecuentes del deck ───────────────────────────────────────────────────────────────────────
-- El freno duro de Legal vivía solo en la pantalla: publicar un texto que INTRODUCE «nominee», «Hak Milik»
-- (Lawang no lo ofrece) o una rentabilidad garantizada, idioma a idioma. Aquí también. Las confirmaciones
-- blandas (afirmación jurídica, idiomas desalineados) se quedan en la pantalla.
create or replace function public._deck_texto_prohibido(p text) returns text
language sql immutable set search_path = '' as $$
  select case
    when p ~* 'nominee' then '«nominee»'
    when p ~* 'hak\s*milik' then '«Hak Milik» (Lawang no ofrece Hak Milik)'
    when p ~* '(garantizad|guaranteed?|dijamin).{0,40}(rentab|retorno|return|yield|imbal|beneficio|profit)'
      or p ~* '(rentab|retorno|return|yield|imbal|beneficio|profit).{0,40}(garantizad|guaranteed?|dijamin)' then 'una rentabilidad garantizada'
  end
$$;
revoke all on function public._deck_texto_prohibido(text) from public, anon, authenticated;

create or replace function public.deck_faq_guarda(p_id uuid, p_proyecto_id uuid, p_datos jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_old public.deck_faq%rowtype; k text; v_p jsonb; v_r jsonb; v_orden numeric; v_pub boolean; v_id uuid; l text; v_antes text; v_ahora text; v_mal text;
begin
  if not public.es_admin() then raise exception 'Editar las FAQ del deck exige ser administrador' using errcode = '42501'; end if;
  if jsonb_typeof(p_datos) is distinct from 'object' then raise exception 'Datos de la pregunta no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_datos) loop
    if k not in ('pregunta', 'respuesta', 'orden', 'publicado') then raise exception 'Ese dato de la pregunta no se edita desde aquí: %', k using errcode = '22023'; end if;
  end loop;
  if p_id is not null then
    select * into v_old from public.deck_faq f where f.id = p_id for update;
    if not found then raise exception 'Esa pregunta ya no existe: recarga' using errcode = '22023'; end if;
  elsif not exists (select 1 from public.proyectos p where p.id = p_proyecto_id) then
    raise exception 'Ese proyecto no existe' using errcode = '22023';
  end if;
  v_p := case when p_datos ? 'pregunta' then public._lw_idiomas(p_datos->'pregunta', 'La pregunta', 1000) else v_old.pregunta end;
  v_r := case when p_datos ? 'respuesta' then public._lw_idiomas(p_datos->'respuesta', 'La respuesta', 6000) else v_old.respuesta end;
  if not (coalesce(v_p, '{}') ? 'es') or not (coalesce(v_r, '{}') ? 'es') then
    raise exception 'La pregunta y la respuesta en español son obligatorias: es el texto de referencia' using errcode = '22023';
  end if;
  -- la tabla exige `en` (CHECK): si falta, el deck enseña el español en ese idioma — se copia como hasta hoy
  if not v_p ? 'en' then v_p := v_p || jsonb_build_object('en', v_p->>'es'); end if;
  if not v_r ? 'en' then v_r := v_r || jsonb_build_object('en', v_r->>'es'); end if;
  v_orden := case when p_datos ? 'orden' then public._lw_num(p_datos->'orden', 'El orden') else v_old.orden end;
  if v_orden is null then select coalesce(max(f.orden), -1) + 1 into v_orden from public.deck_faq f where f.proyecto_id = coalesce(v_old.proyecto_id, p_proyecto_id); end if;
  if v_orden < 0 or v_orden > 10000 or v_orden <> trunc(v_orden) then raise exception 'El orden no es válido' using errcode = '22023'; end if;
  v_pub := case when p_datos ? 'publicado' then coalesce(public._lw_bool(p_datos->'publicado', 'Publicada'), false) else coalesce(v_old.publicado, false) end;

  if v_pub then
    foreach l in array array['es', 'en', 'id'] loop
      v_antes := coalesce(v_old.pregunta->>l, '') || E'\n' || coalesce(v_old.respuesta->>l, '');
      v_ahora := coalesce(v_p->>l, '') || E'\n' || coalesce(v_r->>l, '');
      v_mal := public._deck_texto_prohibido(v_ahora);
      if v_mal is not null and public._deck_texto_prohibido(v_antes) is distinct from v_mal then
        raise exception 'No se puede publicar: el texto introduce % (%). Revisadlo con Legal; si hay que decirlo, guárdala sin publicar.', v_mal, l
          using errcode = '22023';
      end if;
    end loop;
  end if;

  if p_id is null then
    insert into public.deck_faq (proyecto_id, pregunta, respuesta, orden, publicado, creado_por, actualizado_en)
    values (p_proyecto_id, v_p, v_r, v_orden::int, v_pub, (select auth.email()), now())
    returning id into v_id;
    return v_id;
  end if;
  update public.deck_faq set pregunta = v_p, respuesta = v_r, orden = v_orden::int, publicado = v_pub, actualizado_en = now() where id = p_id;
  return p_id;
end $$;
revoke all on function public.deck_faq_guarda(uuid, uuid, jsonb) from public, anon;
grant execute on function public.deck_faq_guarda(uuid, uuid, jsonb) to authenticated;

create or replace function public.deck_faq_borra(p_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_admin() then raise exception 'Editar las FAQ del deck exige ser administrador' using errcode = '42501'; end if;
  delete from public.deck_faq where id = p_id;
  if not found then raise exception 'Esa pregunta ya no existe: recarga' using errcode = '22023'; end if;
  return p_id;
end $$;
revoke all on function public.deck_faq_borra(uuid) from public, anon;
grant execute on function public.deck_faq_borra(uuid) to authenticated;

-- ── diseño visual de un tipo de contrato (portada, marca de agua) ──────────────────────────────────────
-- Forma exacta de DESIGN_DEFAULT (contracts/app.html) y de los controles de contracts/assets/documento_diseno.js.
-- Cada valor acaba pegado sin escapar dentro de un CSS del documento del cliente: por eso lista blanca de la
-- forma ENTERA (clave desconocida = rechazo), color hex, posiciones de su propia lista por hueco, números con
-- rango y `src` solo imagen incrustada png/webp/jpeg o ruta propia.
create or replace function public._contratos_diseno_valida(p jsonb) returns void
language plpgsql immutable set search_path = '' as $$
declare k text; s jsonb; kk text; v_pos text[]; v_min numeric; v_max numeric; n numeric; src text;
begin
  if jsonb_typeof(p) is distinct from 'object' then raise exception 'El diseño no es válido' using errcode = '22023'; end if;
  if length(p::text) > 4000000 then raise exception 'El diseño pesa demasiado (imágenes de más de ~3 MB)' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p) loop
    s := p->k;
    if k = 'coverColor' then
      if jsonb_typeof(s) <> 'string' or (s #>> '{}' <> '' and s #>> '{}' !~ '^#[0-9a-fA-F]{6}$') then
        raise exception 'El color de portada tiene que ser un color #RRGGBB' using errcode = '22023';
      end if;
    elsif k in ('coverGrad', 'coverGrain') then
      if jsonb_typeof(s) <> 'number' or (s #>> '{}')::numeric < 0 or (s #>> '{}')::numeric > 1 then
        raise exception 'Opacidad no válida (%)', k using errcode = '22023';
      end if;
    elsif k in ('coverBg', 'docBg', 'coverLogo', 'coverEmblem', 'coverMark', 'docLogo', 'docMark') then
      if jsonb_typeof(s) <> 'object' then raise exception 'Hueco de diseño no válido (%)', k using errcode = '22023'; end if;
      v_pos := case k
        when 'coverBg' then array['cover', 'contain', 'repeat']
        when 'docBg' then array['cover', 'contain', 'repeat']
        when 'coverMark' then array['top-left', 'top-center', 'top-right', 'center', 'bottom-left', 'bottom-center', 'bottom-right', 'fullbleed']
        when 'docLogo' then array['left', 'center', 'right']
        when 'docMark' then array['center', 'top', 'bottom']
        else array['top-left', 'top-center', 'top-right', 'center', 'bottom-left', 'bottom-center', 'bottom-right', 'fullbleed'] end;
      select x.mn, x.mx into v_min, v_max from (values ('coverLogo', 10, 90), ('coverEmblem', 8, 60), ('coverMark', 20, 120),
        ('docLogo', 10, 60), ('docMark', 60, 220)) as x(hueco, mn, mx) where x.hueco = k;
      for kk in select jsonb_object_keys(s) loop
        if kk = 'src' then
          if jsonb_typeof(s->kk) <> 'string' then raise exception 'Imagen no válida (%)', k using errcode = '22023'; end if;
          src := s->>kk;
          if src <> '' and src !~ '^data:image/(png|webp|jpeg);base64,[A-Za-z0-9+/]+={0,2}$'
                       and src !~ '^(/|assets/)[A-Za-z0-9/_.-]+\.(png|webp|jpe?g|svg)$' then
            raise exception 'La imagen de % tiene que ser PNG, WEBP o JPEG subida desde el editor', k using errcode = '22023';
          end if;
        elsif kk = 'pos' then
          if jsonb_typeof(s->kk) <> 'string' or not ((s->>kk) = any (v_pos)) then
            raise exception 'Posición no válida (%)', k using errcode = '22023';
          end if;
        elsif kk = 'op' then
          if jsonb_typeof(s->kk) <> 'number' or (s->>kk)::numeric < 0 or (s->>kk)::numeric > 1 then
            raise exception 'Opacidad no válida (%)', k using errcode = '22023';
          end if;
        elsif kk = 'size' and v_min is not null then
          if jsonb_typeof(s->kk) <> 'number' then raise exception 'Tamaño no válido (%)', k using errcode = '22023'; end if;
          n := (s->>kk)::numeric;
          if n < v_min or n > v_max then raise exception 'Tamaño fuera de rango (%: de % a %)', k, v_min, v_max using errcode = '22023'; end if;
        else
          raise exception 'Dato de diseño no admitido (%.%)', k, kk using errcode = '22023';
        end if;
      end loop;
    else
      raise exception 'Dato de diseño no admitido (%)', k using errcode = '22023';
    end if;
  end loop;
end $$;
revoke all on function public._contratos_diseno_valida(jsonb) from public, anon, authenticated;

create or replace function public.contratos_diseno_guarda(p_slug text, p_design jsonb) returns text
language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_admin() then
    raise exception 'El diseño compartido de un tipo de contrato lo guarda administración (lo ven todos los agentes y el cliente)' using errcode = '42501';
  end if;
  if p_slug is null or p_slug !~ '^[a-z0-9_-]{2,60}$' then raise exception 'Tipo de contrato no válido' using errcode = '22023'; end if;
  perform public._contratos_diseno_valida(p_design);
  insert into public.contratos_diseno (slug, design, updated_at) values (p_slug, p_design, now())
  on conflict (slug) do update set design = excluded.design, updated_at = excluded.updated_at;
  return p_slug;
end $$;
revoke all on function public.contratos_diseno_guarda(text, jsonb) from public, anon;
grant execute on function public.contratos_diseno_guarda(text, jsonb) to authenticated;
