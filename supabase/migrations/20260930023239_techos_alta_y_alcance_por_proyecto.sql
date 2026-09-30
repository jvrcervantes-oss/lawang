-- destructivo-ok: no borra ni cambia ninguna fila. Endurece dos columnas sin nulos (0 de 38, medido), cambia la FK
-- modelo_techos→modelos de CASCADE a RESTRICT (nadie borra modelos: 0 funciones lo hacen) y sustituye funciones.
--
-- Techos: alta desde la ficha del modelo y alcance por proyecto — 30-sep-2026.
-- Owner: «En v4/modelos necesito poder añadir nuevos techos, que se guarden en la base y salgan solos en el
-- contrato y en todo. Poder decidir qué casa + techo va en cada proyecto; si no digo nada, en todos.»
-- Revisión previa #163 (Datos + Seguridad + Administración), que manda sobre el plan.
--
-- DECISIONES DEL OWNER (30-sep-2026, no derivables del código):
--  · El precio del techo sigue siendo el precio COMPLETO de la villa, y NINGÚN techo activo puede quedar por
--    debajo de la base del modelo. Un techo más barato = primero se baja la base. Un modelo sin base no admite
--    techos (sin base no hay contra qué calcular el precio en los proyectos con precio propio).
--  · 2027 SIN doble subida: un proyecto con precio propio P mantiene P como precio de su techo más barato
--    también en 2027; los techos solo aportan la diferencia entre ellos. Antes: precio_2027 + (P − base 2026),
--    que en Dali/Sumba Hills daba 56.000 el 1-ene-2027 (52.000 ya era el precio 2027 del catálogo).
--
-- QUÉ HACE
--  1. modelos_villa: modelo_id/proyecto_id NOT NULL + UNIQUE por ids (hoy el único UNIQUE era por texto).
--  2. modelo_techos: `activo` (se retira, nunca se borra: la clave va en contratos congelados, en
--     modelo_documentos.techo_clave y en las fotos de la web), `alcance` 'todos'|'lista' (estado explícito: «sin
--     filas» NO significa «todos»), CHECK de forma de la clave (va en atributos HTML de la web), FK RESTRICT.
--  3. modelo_techo_proyectos: tabla puente del alcance 'lista' (regla del 26-sep: se vincula por tabla).
--  4. _modelo_techos_opciones: ÚNICA fórmula de precio de techo por proyecto y tramo. La usan el contrato
--     (modelo_techos_opciones), el trigger de Construcción y el «desde» del dossier.
--  5. Trigger de Construcción: el techo y los extras se comprueban contra Modelos (antes cuadraba precio_total
--     contra el precio que mandaba el NAVEGADOR). Solo en INSERT o si cambia techo, extras o proyecto: un
--     contrato guardado conserva su precio congelado aunque el techo se retire o cambie de precio.
--  6. RPC modelo_techo_crea / modelo_techo_edita (solo admin) + invariante en modelo_techos_guarda.
--  7. catalogo_publico: solo techos activos, con `orden` y, si el alcance es 'lista', los SLUG de sus proyectos
--     (nunca uuids: es anónima). dossier_datos: el «desde» del proyecto sale de la fórmula única.

-- ── 1. modelos_villa ─────────────────────────────────────────────────────────────────────────────────────
alter table public.modelos_villa alter column modelo_id set not null;
alter table public.modelos_villa alter column proyecto_id set not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'modelos_villa_modelo_proyecto_key') then
    alter table public.modelos_villa add constraint modelos_villa_modelo_proyecto_key unique (modelo_id, proyecto_id);
  end if;
end $$;

-- ── 2. modelo_techos ─────────────────────────────────────────────────────────────────────────────────────
alter table public.modelo_techos add column if not exists activo boolean not null default true;
alter table public.modelo_techos add column if not exists alcance text not null default 'todos';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'modelo_techos_alcance_check') then
    alter table public.modelo_techos add constraint modelo_techos_alcance_check check (alcance in ('todos', 'lista'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'modelo_techos_clave_forma') then
    alter table public.modelo_techos add constraint modelo_techos_clave_forma check (clave ~ '^[a-z0-9_]{1,40}$');
  end if;
  if exists (select 1 from pg_constraint where conname = 'modelo_techos_modelo_id_fkey' and confdeltype = 'c') then
    alter table public.modelo_techos drop constraint modelo_techos_modelo_id_fkey;
    alter table public.modelo_techos add constraint modelo_techos_modelo_id_fkey
      foreign key (modelo_id) references public.modelos(id) on delete restrict;
  end if;
end $$;
comment on column public.modelo_techos.activo is
  'false = retirado: no se ofrece en contratos nuevos ni en la web. Nunca se borra la fila (su clave vive en contratos congelados, en modelo_documentos.techo_clave y en las fotos de la web). 30-sep-2026.';
comment on column public.modelo_techos.alcance is
  '''todos'' = se ofrece en cualquier proyecto donde se venda el modelo (por defecto, decisión del owner). ''lista'' = solo en los proyectos de modelo_techo_proyectos; una lista vacía = en ninguno. 30-sep-2026.';

-- ── 3. alcance por proyecto ──────────────────────────────────────────────────────────────────────────────
create table if not exists public.modelo_techo_proyectos (
  techo_id    uuid not null references public.modelo_techos(id) on delete cascade,
  proyecto_id uuid not null references public.proyectos(id) on delete cascade,
  creado_en   timestamptz not null default now(),
  primary key (techo_id, proyecto_id)
);
create index if not exists modelo_techo_proyectos_proyecto_idx on public.modelo_techo_proyectos (proyecto_id);
alter table public.modelo_techo_proyectos enable row level security;
revoke all on public.modelo_techo_proyectos from public, anon, authenticated;
grant select on public.modelo_techo_proyectos to authenticated, lw_lector;
drop policy if exists "techo_proyectos: leer" on public.modelo_techo_proyectos;
create policy "techo_proyectos: leer" on public.modelo_techo_proyectos for select to authenticated, lw_lector
  using (public.es_agente());
comment on table public.modelo_techo_proyectos is
  'Proyectos donde se ofrece un techo con alcance=''lista''. Solo la escriben modelo_techo_crea/modelo_techo_edita. 30-sep-2026.';

-- ── 4. fórmula única ─────────────────────────────────────────────────────────────────────────────────────
-- Precio del techo T en el proyecto con precio propio P:
--   2026: P + (T.ahora − base)          (base = modelos.precio_construccion = el techo más barato)
--   2027: P + (T.2027 − mín 2027)       (mín de los techos activos del modelo; sin doble subida — owner)
-- Sin precio propio: el precio del techo en el tramo, tal cual. Un techo sin precio del tramo activo no se ofrece.
-- «Ulin» sintético: solo si el modelo NO TIENE NINGUNA fila de techo (sin filtrar por activo ni alcance —
-- «no tiene variantes» no es «tiene variantes y ninguna va aquí», Datos #163).
create or replace function public._modelo_techos_opciones(p_modelo_id uuid, p_proyecto_id uuid)
returns table(techo_id uuid, clave text, nombre text, precio numeric, moneda text, tramo text)
language sql
stable
security definer
set search_path = ''
as $$
  with base as (
    select m.precio_construccion as catalogo, m.moneda as m_moneda,
           mv.precio_construccion as propio,
           coalesce(mv.precio_construccion, m.precio_construccion) as efectivo,
           case when mv.precio_construccion is not null then coalesce(mv.moneda, m.moneda) else m.moneda end as moneda
      from public.modelos m
      left join public.modelos_villa mv
        on mv.modelo_id = m.id and mv.proyecto_id = p_proyecto_id and mv.precio_construccion is not null
     where m.id = p_modelo_id
  ), tramo as (select public.catalogo_tramo_activo() as t),
  min27 as (
    select min(th.precio_2027) as b from public.modelo_techos th where th.modelo_id = p_modelo_id and th.activo
  ), vivos as (
    select th.* from public.modelo_techos th
     where th.modelo_id = p_modelo_id and th.activo
       and (th.alcance = 'todos'
            or exists (select 1 from public.modelo_techo_proyectos tp
                        where tp.techo_id = th.id and tp.proyecto_id = p_proyecto_id))
  )
  (
    select v.id, v.clave, v.nombre,
           case when tramo.t = '2026' then v.precio_ahora + coalesce(base.propio - base.catalogo, 0)
                else v.precio_2027 + coalesce(base.propio - min27.b, 0) end,
           base.m_moneda, tramo.t
      from vivos v, base, tramo, min27
     where case when tramo.t = '2026' then v.precio_ahora else v.precio_2027 end is not null
     order by v.orden nulls last, v.nombre
  )
  union all
  (
    select p_modelo_id, 'ulin'::text, 'Ulin'::text, base.efectivo, base.moneda, tramo.t
      from base, tramo
     where base.efectivo is not null
       and not exists (select 1 from public.modelo_techos th where th.modelo_id = p_modelo_id)
  )
$$;
revoke all on function public._modelo_techos_opciones(uuid, uuid) from public, anon, authenticated;
grant execute on function public._modelo_techos_opciones(uuid, uuid) to lw_lector;   -- dossier_datos corre como lw_lector

-- La que llama la pantalla: la misma fórmula, solo para agentes (Seguridad #163: los 29 compradores del portal
-- son `authenticated` y sacaban precios que la policy de lectura de modelo_techos les niega).
create or replace function public.modelo_techos_opciones(p_modelo_id uuid, p_proyecto_id uuid default null)
returns table(techo_id uuid, clave text, nombre text, precio numeric, moneda text, tramo text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is not null and not public.es_agente() then
    raise exception 'Sin permiso para ver precios de construcción' using errcode = '42501';
  end if;
  return query select * from public._modelo_techos_opciones(p_modelo_id, p_proyecto_id);
end $$;
comment on function public.modelo_techos_opciones(uuid, uuid) is
  'Techos ofrecibles de un modelo en un proyecto, con precio YA resuelto (tramo + precio propio del proyecto) y filtrados por activo y alcance. Fórmula única en _modelo_techos_opciones. 30-sep-2026.';
revoke all on function public.modelo_techos_opciones(uuid, uuid) from public, anon;
grant execute on function public.modelo_techos_opciones(uuid, uuid) to authenticated;

create or replace function public.modelo_extras_opciones(p_modelo_id uuid)
returns table(extra_id uuid, clave text, nombre text, precio numeric, moneda text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is not null and not public.es_agente() then
    raise exception 'Sin permiso para ver precios de construcción' using errcode = '42501';
  end if;
  return query
    select e.id, e.clave, e.nombre, me.precio, me.moneda
      from public.modelo_extras me
      join public.extras e on e.id = me.extra_id
     where me.modelo_id = p_modelo_id and me.disponible and e.activo and me.precio is not null
     order by e.orden nulls last, e.nombre;
end $$;
revoke all on function public.modelo_extras_opciones(uuid) from public, anon;
grant execute on function public.modelo_extras_opciones(uuid) to authenticated;

-- ── 5. trigger de Construcción ───────────────────────────────────────────────────────────────────────────
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
  -- 30-sep-2026
  v_tid       text;
  v_modelo    uuid;
  v_ok        numeric;
  v_nombre    text;
  v_x         jsonb;
begin
  if new.tipo <> 'construccion' then
    return new;
  end if;

  -- 30-sep-2026 (revisión previa #163): el techo y los extras los pone Modelos, no la pantalla. Con sesión, en
  -- INSERT o si cambia techo, extras o proyecto. Sin sesión (service_role, MCP) no: mismo criterio que el resto
  -- de candados de rol. Un contrato guardado que no cambia nada de eso conserva su precio congelado.
  if (select auth.uid()) is not null and (
       tg_op = 'INSERT'
       or new.datos->'techo' is distinct from old.datos->'techo'
       or new.datos->'extras' is distinct from old.datos->'extras'
       or new.proyecto_id is distinct from old.proyecto_id) then
    v_tid := nullif(btrim(coalesce(new.datos->'techo'->>'techo_id', '')), '');
    if v_tid is null then
      if tg_op = 'INSERT' then
        raise exception 'Un contrato de Construcción lleva siempre techo: elige la tipología y el techo.' using errcode = '22023';
      end if;
      if jsonb_array_length(coalesce(new.datos->'extras', '[]'::jsonb)) > 0 then
        raise exception 'Los extras necesitan un techo elegido.' using errcode = '22023';
      end if;
    else
      if v_tid !~ '^[0-9a-fA-F-]{36}$' then
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
      for v_x in select * from jsonb_array_elements(coalesce(new.datos->'extras', '[]'::jsonb)) loop
        v_ok := null;
        if coalesce(v_x->>'extra_id', '') ~ '^[0-9a-fA-F-]{36}$' then
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
      end loop;
    end if;
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

-- ── 6. escritura (solo admin) ────────────────────────────────────────────────────────────────────────────
-- Alcance: 'todos' borra la lista; 'lista' la sustituye. Cada proyecto tiene que vender ese modelo.
create or replace function public._modelo_techo_alcance(p_techo uuid, p_modelo uuid, p_alcance text, p_proyectos jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_ids uuid[]; v_n int;
begin
  if p_alcance not in ('todos', 'lista') then
    raise exception 'Alcance no válido' using errcode = '22023';
  end if;
  update public.modelo_techos set alcance = p_alcance where id = p_techo;
  delete from public.modelo_techo_proyectos where techo_id = p_techo;
  if p_alcance = 'todos' then return; end if;
  if p_proyectos is null or jsonb_typeof(p_proyectos) <> 'array' or jsonb_array_length(p_proyectos) = 0 then
    raise exception 'Marca al menos un proyecto, o deja «Todos los proyectos».' using errcode = '22023';
  end if;
  begin
    select array_agg(distinct (x #>> '{}')::uuid) into v_ids from jsonb_array_elements(p_proyectos) x;
  exception when others then
    raise exception 'Proyectos no válidos' using errcode = '22023';
  end;
  if cardinality(v_ids) <> jsonb_array_length(p_proyectos) then
    raise exception 'Hay un proyecto repetido' using errcode = '22023';
  end if;
  select count(*) into v_n from public.modelos_villa mv where mv.modelo_id = p_modelo and mv.proyecto_id = any (v_ids);
  if v_n <> cardinality(v_ids) then
    raise exception 'Algún proyecto marcado no vende esta casa: añádela antes al proyecto (bloque «Precio por proyecto»).' using errcode = '22023';
  end if;
  insert into public.modelo_techo_proyectos (techo_id, proyecto_id) select p_techo, unnest(v_ids);
end $$;
revoke all on function public._modelo_techo_alcance(uuid, uuid, text, jsonb) from public, anon, authenticated;

-- Contratos de Construcción SIN firmar que llevan ese techo (y, si se pasa la lista nueva, los que quedarían
-- fuera de ella). No se tocan: su techo está congelado. Se cuentan para que administración lo sepa ANTES.
create or replace function public._modelo_techo_uso(p_techo uuid, p_quedan uuid[] default null)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int from public.contratos c
   where c.tipo = 'construccion' and not coalesce(c.bloqueado, false)   -- firmado = bloqueado, nunca fecha_firma (suite_lawang.md)
     and c.datos->'techo'->>'techo_id' = p_techo::text
     and (p_quedan is null or c.proyecto_id is null or not (c.proyecto_id = any (p_quedan)))
$$;
revoke all on function public._modelo_techo_uso(uuid, uuid[]) from public, anon, authenticated;

create or replace function public._slug_techo(p text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(left(btrim(regexp_replace(
           translate(lower(coalesce(p, '')), 'áàäâãéèëêíìïîóòöôõúùüûñç', 'aaaaaeeeeiiiiooooouuuunc'),
           '[^a-z0-9]+', '_', 'g'), '_'), 40), '')
$$;
revoke all on function public._slug_techo(text) from public, anon, authenticated;

-- p_datos: {nombre, descripcion?, precio_ahora, precio_2027, alcance: 'todos'|'lista', proyectos?: [uuid]}
create or replace function public.modelo_techo_crea(p_modelo_id uuid, p_datos jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m public.modelos%rowtype; k text; v_nombre text; v_desc text; v_a numeric; v_z numeric;
  v_clave text; v_base text; v_i int := 1; v_id uuid; v_orden int; v_mon text;
begin
  if not public.es_admin() then raise exception 'Los techos los da de alta administración' using errcode = '42501'; end if;
  if jsonb_typeof(p_datos) is distinct from 'object' then raise exception 'Datos no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_datos) loop
    if k not in ('nombre', 'descripcion', 'precio_ahora', 'precio_2027', 'alcance', 'proyectos') then
      raise exception 'Ese dato del techo no se da de alta desde aquí: %', k using errcode = '22023';
    end if;
  end loop;
  select * into v_m from public.modelos m where m.id = p_modelo_id for update;
  if not found then raise exception 'Ese modelo ya no existe: recarga la página' using errcode = '22023'; end if;
  v_mon := coalesce(v_m.moneda, 'EUR');
  if v_m.precio_construccion is null then
    raise exception 'Pon antes el precio base del modelo: sin base no se puede calcular el techo en los proyectos con precio propio.' using errcode = '22023';
  end if;
  v_nombre := btrim(coalesce(p_datos->>'nombre', ''));
  if v_nombre = '' or length(v_nombre) > 60 then
    raise exception 'El nombre del techo es obligatorio (máximo 60 caracteres)' using errcode = '22023';
  end if;
  if exists (select 1 from public.modelo_techos t where t.modelo_id = p_modelo_id and lower(t.nombre) = lower(v_nombre)) then
    raise exception 'Este modelo ya tiene un techo «%» (activo o retirado)', v_nombre using errcode = '22023';
  end if;
  v_desc := nullif(btrim(coalesce(p_datos->>'descripcion', '')), '');
  if length(v_desc) > 500 then raise exception 'La descripción es demasiado larga (máximo 500)' using errcode = '22023'; end if;
  v_a := public._lw_num(p_datos->'precio_ahora', 'El precio ahora');
  v_z := public._lw_num(p_datos->'precio_2027', 'El precio 2027');
  if not public._lw_importe_ok(v_a, v_mon) then raise exception 'El techo necesita un precio ahora mayor que cero (y razonable en %)', v_mon using errcode = '22023'; end if;
  if not public._lw_importe_ok(v_z, v_mon) then raise exception 'El techo necesita también su precio 2027: el 1-ene-2027 se cobra ese' using errcode = '22023'; end if;
  if v_a < v_m.precio_construccion then
    raise exception 'El techo (%) no puede ser más barato que el precio base del modelo (%): si quieres uno más barato, baja antes la base.',
      v_a, v_m.precio_construccion using errcode = '22023';
  end if;
  v_base := coalesce(public._slug_techo(v_nombre), 'techo');
  v_clave := v_base;
  while v_clave = 'ulin' or exists (select 1 from public.modelo_techos t where t.modelo_id = p_modelo_id and t.clave = v_clave) loop
    v_i := v_i + 1;
    v_clave := left(v_base, 36) || '_' || v_i;
  end loop;
  select coalesce(max(t.orden), 0) + 1 into v_orden from public.modelo_techos t where t.modelo_id = p_modelo_id;
  insert into public.modelo_techos (modelo_id, clave, nombre, descripcion, precio_ahora, precio_2027, orden, activo, alcance)
  values (p_modelo_id, v_clave, v_nombre, v_desc, v_a, v_z, v_orden, true, 'todos')
  returning id into v_id;
  perform public._modelo_techo_alcance(v_id, p_modelo_id, coalesce(p_datos->>'alcance', 'todos'), p_datos->'proyectos');
  perform public._precio_log(p_modelo_id, null, 'modelo_techos', v_id, 'precio_ahora', null, v_a, v_mon, 'modelo_techo_crea', 'alta del techo «' || v_nombre || '»');
  perform public._precio_log(p_modelo_id, null, 'modelo_techos', v_id, 'precio_2027', null, v_z, v_mon, 'modelo_techo_crea');
  return v_id;
end $$;
revoke all on function public.modelo_techo_crea(uuid, jsonb) from public, anon;
grant execute on function public.modelo_techo_crea(uuid, jsonb) to authenticated;

-- p_cambios: {nombre?, descripcion?, orden?, activo?, alcance?, proyectos?}. Nunca clave ni modelo ni precios
-- (los precios van por modelo_techos_guarda). Si retirar o recortar el alcance deja fuera contratos sin firmar,
-- falla con errcode LW409 y el número, salvo p_confirmado = true: la pantalla pregunta y reintenta.
create or replace function public.modelo_techo_edita(p_id uuid, p_cambios jsonb, p_confirmado boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.modelo_techos%rowtype; k text; v_nombre text; v_desc text; v_orden int; v_activo boolean;
  v_alcance text; v_ids uuid[]; v_uso int := 0;
begin
  if not public.es_admin() then raise exception 'Los techos los cambia administración' using errcode = '42501'; end if;
  if jsonb_typeof(p_cambios) is distinct from 'object' then raise exception 'Cambios no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_cambios) loop
    if k not in ('nombre', 'descripcion', 'orden', 'activo', 'alcance', 'proyectos') then
      raise exception 'Ese dato del techo no se edita desde aquí: %', k using errcode = '22023';
    end if;
  end loop;
  select * into t from public.modelo_techos x where x.id = p_id for update;
  if not found then raise exception 'Ese techo ya no existe: recarga la página' using errcode = '22023'; end if;
  perform 1 from public.modelos m where m.id = t.modelo_id for update;

  if p_cambios ? 'nombre' then
    v_nombre := btrim(coalesce(p_cambios->>'nombre', ''));
    if v_nombre = '' or length(v_nombre) > 60 then raise exception 'El nombre del techo es obligatorio (máximo 60 caracteres)' using errcode = '22023'; end if;
    if exists (select 1 from public.modelo_techos x where x.modelo_id = t.modelo_id and x.id <> t.id and lower(x.nombre) = lower(v_nombre)) then
      raise exception 'Este modelo ya tiene un techo «%»', v_nombre using errcode = '22023';
    end if;
    update public.modelo_techos set nombre = v_nombre where id = t.id;
  end if;
  if p_cambios ? 'descripcion' then
    v_desc := nullif(btrim(coalesce(p_cambios->>'descripcion', '')), '');
    if length(v_desc) > 500 then raise exception 'La descripción es demasiado larga (máximo 500)' using errcode = '22023'; end if;
    update public.modelo_techos set descripcion = v_desc where id = t.id;
  end if;
  if p_cambios ? 'orden' then
    v_orden := public._lw_num(p_cambios->'orden', 'El orden')::int;
    update public.modelo_techos set orden = v_orden where id = t.id;
  end if;
  if p_cambios ? 'activo' then
    v_activo := public._lw_bool(p_cambios->'activo', 'Activo');
    if v_activo is null then raise exception 'Activo tiene que ser sí o no' using errcode = '22023'; end if;
    if not v_activo and t.activo then
      if not exists (select 1 from public.modelo_techos x where x.modelo_id = t.modelo_id and x.id <> t.id and x.activo) then
        raise exception 'Es el único techo activo del modelo: un modelo con techos necesita al menos uno.' using errcode = '22023';
      end if;
      v_uso := public._modelo_techo_uso(t.id);
    end if;
    if v_activo and not t.activo then
      if t.precio_ahora < (select m.precio_construccion from public.modelos m where m.id = t.modelo_id) then
        raise exception 'Este techo está por debajo del precio base actual: sube antes su precio.' using errcode = '22023';
      end if;
    end if;
    update public.modelo_techos set activo = v_activo where id = t.id;
  end if;
  if p_cambios ? 'alcance' or p_cambios ? 'proyectos' then
    v_alcance := coalesce(p_cambios->>'alcance', t.alcance);
    if v_alcance = 'lista' and coalesce(jsonb_typeof(p_cambios->'proyectos'), '') = 'array' then
      begin
        select array_agg((x #>> '{}')::uuid) into v_ids from jsonb_array_elements(p_cambios->'proyectos') x;
      exception when others then raise exception 'Proyectos no válidos' using errcode = '22023';
      end;
      v_uso := greatest(v_uso, public._modelo_techo_uso(t.id, coalesce(v_ids, '{}')));
    end if;
    perform public._modelo_techo_alcance(t.id, t.modelo_id, v_alcance,
      case when v_alcance = 'lista' then p_cambios->'proyectos' else null end);
  end if;
  if v_uso > 0 and not coalesce(p_confirmado, false) then
    raise exception '% contrato(s) de Construcción sin firmar llevan este techo y dejarían de poder cambiarlo a él. Conservan su precio congelado.', v_uso
      using errcode = 'LW409', hint = v_uso::text;
  end if;
  return jsonb_build_object('ok', true, 'contratos_sin_firmar', v_uso);
end $$;
revoke all on function public.modelo_techo_edita(uuid, jsonb, boolean) from public, anon;
grant execute on function public.modelo_techo_edita(uuid, jsonb, boolean) to authenticated;

-- modelo_techos_guarda: igual que antes + ningún techo ACTIVO por debajo de la base (decisión del owner).
create or replace function public.modelo_techos_guarda(p_id uuid, p_techos jsonb)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
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
    if t.activo and v_m.precio_construccion is not null and v_a < v_m.precio_construccion then
      raise exception '«%» (%) no puede quedar por debajo del precio base (%): si quieres un techo más barato, baja antes la base.',
        t.nombre, v_a, v_m.precio_construccion using errcode = '22023';
    end if;
    update public.modelo_techos set precio_ahora = v_a, precio_2027 = v_z where id = t.id;
    perform public._precio_log(p_id, null, 'modelo_techos', t.id, 'precio_ahora', t.precio_ahora, v_a, v_m.moneda, 'modelo_techos_guarda');
    perform public._precio_log(p_id, null, 'modelo_techos', t.id, 'precio_2027', t.precio_2027, v_z, v_m.moneda, 'modelo_techos_guarda');
  end loop;
  return cardinality(v_ids);
end $function$;

-- ── 7. lectores de la web y del dossier ──────────────────────────────────────────────────────────────────
create or replace function public.catalogo_publico()
returns jsonb
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(jsonb_object_agg(x.slug, x.ficha), '{}'::jsonb)
    from (
      select m.slug,
             jsonb_strip_nulls(jsonb_build_object(
               'nombre',             m.nombre,
               'dormitorios',        m.dormitorios,
               'banos',              m.banos,
               'villa_m2',           m.villa_m2,
               'terraza_m2',         m.terraza_m2,
               'sub',                m.descripcion,
               'moneda',             m.moneda,
               'desde',              m.precio_construccion,
               'renders_pendientes', nullif(m.renders_pendientes, false),
               'alcance',            m.alcance,
               'acabados',           m.acabados,
               -- 30-sep-2026: solo activos; `orden` porque un objeto jsonb no conserva el orden; `proyectos`
               -- (slugs, nunca uuids: esta función es anónima) solo si el techo se limita a unos proyectos.
               'techos', (select jsonb_object_agg(t.clave, jsonb_strip_nulls(jsonb_build_object(
                                   'nombre', t.nombre, 'desc', t.descripcion,
                                   'now',    t.precio_ahora, 'y2027', t.precio_2027, 'orden', t.orden,
                                   'proyectos', case when t.alcance = 'lista' then coalesce(
                                       (select jsonb_agg(p.slug order by p.slug)
                                          from public.modelo_techo_proyectos tp
                                          join public.proyectos p on p.id = tp.proyecto_id
                                         where tp.techo_id = t.id and p.slug is not null), '[]'::jsonb) end)))
                            from public.modelo_techos t where t.modelo_id = m.id and t.activo),
               'extras', (select jsonb_object_agg(e.clave, jsonb_build_object(
                                   'nombre', e.nombre, 'desc', e.descripcion,
                                   'precio', me.precio, 'orden', e.orden))
                            from public.modelo_extras me
                            join public.extras e on e.id = me.extra_id
                           where me.modelo_id = m.id and me.disponible and e.activo)
             )) as ficha
        from public.modelos m
       where m.publicado and m.activo
    ) x
$function$;

create or replace function public.dossier_datos(p_proyecto uuid, p_modelos uuid[])
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
begin
  if not (public.puede('dossier') or public.puede('creatividades')) then
    raise exception 'Sin permiso para montar dossiers.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'proyecto', (select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'slug', p.slug)
                   from public.proyectos p where p.id = p_proyecto),
    'parcelas', coalesce((select jsonb_agg(jsonb_build_object('codigo', u.codigo, 'superficie_m2', u.superficie_m2)
                                  order by coalesce(u.codigo_orden, u.codigo))
                            from public.unidades u
                           where u.proyecto_id = p_proyecto and u.estado = 'disponible'
                             and coalesce(u.publicado_investor_deck, false)), '[]'::jsonb),
    -- 30-sep-2026: el «desde» es el techo más barato que el CONTRATO ofrecería en este proyecto hoy (tramo,
    -- precio propio, alcance) — antes era min(precio_ahora) de catálogo y en Sumba Hills decía 48.000 con el
    -- contrato cobrando 52.000 (Administración #163).
    'modelos', coalesce((select jsonb_agg(jsonb_build_object(
                   'id', m.id, 'nombre', m.nombre, 'dormitorios', m.dormitorios, 'banos', m.banos,
                   'villa_m2', m.villa_m2, 'terraza_m2', m.terraza_m2, 'moneda', m.moneda,
                   'desde', (select min(o.precio) from public._modelo_techos_opciones(m.id, p_proyecto) o))
                   order by m.orden nulls last, m.nombre)
                  from public.modelos m where m.id = any(coalesce(p_modelos, '{}')) and m.activo), '[]'::jsonb),
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'ambito', f.ambito, 'modelo_id', f.modelo_id,
                   'tipo', f.tipo, 'uso', f.uso, 'path', f.path, 'pie', f.pie) order by f.ambito, f.orden)
                  from public.deck_fotos f
                 where (f.ambito = 'proyecto' and f.proyecto_id = p_proyecto)
                    or (f.ambito = 'modelo' and f.modelo_id = any(coalesce(p_modelos, '{}')))), '[]'::jsonb),
    'precios_a', to_char(current_date, 'YYYY-MM-DD')
  );
end $function$;
