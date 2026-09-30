-- destructivo-ok: no borra filas. Renombra modelo_techos.precio_ahora/precio_2027 a *_antiguo (se conservan), pasa a
-- «hereda la base» (null) el precio por proyecto de 13 pares que lo tenían escrito a mano IGUAL a la base (decisión
-- del owner 30-sep, con log en modelos_precios_log), cambia la FK modelo_extras→extras de CASCADE a RESTRICT y
-- recrea el constraint trigger de invariantes. Aborta sola si alguna cifra cambia sin estar decidido.
--
-- TECHO = SUPLEMENTO SOBRE LA CASA + ALTA/RETIRADA DE EXTRAS — 30-sep-2026 (2ª parte del día).
-- Owner: «El modelo debe tener un precio base con un techo base; a partir de ahí la diferencia en los techos debe
-- sumarse (+4000 o lo que corresponda). Casi tratarlo como un extra. Y necesito poder añadir o retirar extras.»
-- Decisiones del owner (30-sep): suplemento con DOS cifras (ahora y 2027); extras: alta y retirada en el catálogo;
-- Alang-alang de la Dali = +4.000 ahora y +0 en 2027; los 13 pares con precio propio = base pasan a «hereda».
-- Revisión previa #166 (Administración + Datos), que manda sobre el plan.
--
-- MODELO NUEVO
--  · modelos.precio_construccion (base ahora) + modelos.precio_construccion_2027 (base 2027): la casa CON su techo base.
--  · modelo_techos.suplemento_ahora / suplemento_2027 (≥ 0) + es_base (uno por modelo, suplementos 0).
--  · Precio de un techo en un proyecto = (precio propio P del proyecto, o la base del tramo) + suplemento del tramo.
--    Con P no hay doble subida en 2027 (owner, mañana del 30-sep): P es el precio con el techo base en los dos años.
--  · Modelos SIN techos: rama «Ulin» igual que hasta hoy (mismo precio en los dos tramos).
--  · El precio COMPLETO sigue siendo lo que ven el contrato (datos.techo.precio, congelado) y la web (now/y2027).

-- ── 0. foto ANTES (tramo 2026 y 2027) ───────────────────────────────────────────────────────────────────
create temp table _antes (tramo_prueba text, modelo_id uuid, proyecto_id uuid, techo_id uuid, clave text, precio numeric) on commit drop;
do $$
declare t text;
begin
  foreach t in array array['2026', '2027'] loop
    execute format($f$create or replace function public.catalogo_tramo_activo() returns text language sql stable set search_path = '' as $b$ select %L::text $b$$f$, t);
    insert into _antes
      select t, x.modelo_id, x.proyecto_id, o.techo_id, o.clave, o.precio
        from (select mv.modelo_id, mv.proyecto_id from public.modelos_villa mv
              union select m.id, null::uuid from public.modelos m) x
        cross join lateral public._modelo_techos_opciones(x.modelo_id, x.proyecto_id) o;
  end loop;
end $$;
create or replace function public.catalogo_tramo_activo()
returns text language sql stable set search_path = '' as $$
  select case when (now() at time zone 'Asia/Makassar') < timestamp '2027-01-01 00:00:00' then '2026' else '2027' end
$$;
create temp table _catalogo_antes on commit drop as select public.catalogo_publico() as j;
-- contratos de Construcción cuyo techo congelado NO cuadra hoy con la fórmula (CC00117 es conocido, LAW-448)
create temp table _contratos_antes on commit drop as
  select c.numero from public.contratos c
    left join public.modelo_techos th on th.id::text = c.datos->'techo'->>'techo_id'
   where c.tipo = 'construccion' and c.datos->'techo'->>'techo_id' is not null
     and (select o.precio from public._modelo_techos_opciones(coalesce(th.modelo_id, (c.datos->'techo'->>'techo_id')::uuid), c.proyecto_id) o
           where o.techo_id::text = c.datos->'techo'->>'techo_id') is distinct from public.lw_importe(c.datos->'techo'->>'precio');

-- ── 1. esquema ───────────────────────────────────────────────────────────────────────────────────────────
alter table public.modelos add column if not exists precio_construccion_2027 numeric;
alter table public.modelo_techos add column if not exists suplemento_ahora numeric;
alter table public.modelo_techos add column if not exists suplemento_2027 numeric;
alter table public.modelo_techos add column if not exists es_base boolean not null default false;

-- base de cada modelo con techos = su techo ACTIVO más barato ahora (Datos #166: también es el más barato en 2027 y
-- no hay empates; se comprueba abajo).
create temp table _base on commit drop as
  select distinct on (t.modelo_id) t.modelo_id, t.id, t.precio_ahora, t.precio_2027
    from public.modelo_techos t where t.activo
   order by t.modelo_id, t.precio_ahora, t.orden nulls last, t.clave;
do $$ begin
  if exists (select 1 from _base b join public.modelo_techos t on t.modelo_id = b.modelo_id and t.activo
              where t.precio_2027 < b.precio_2027) then
    raise exception 'ABORTA: el techo base no es también el más barato en 2027 en algún modelo';
  end if;
  if exists (select 1 from _base b join public.modelos m on m.id = b.modelo_id
              where m.precio_construccion is distinct from b.precio_ahora) then
    raise exception 'ABORTA: la base de algún modelo no coincide con su techo más barato';
  end if;
end $$;
update public.modelo_techos t
   set es_base = (t.id = b.id),
       suplemento_ahora = t.precio_ahora - b.precio_ahora,
       suplemento_2027 = t.precio_2027 - b.precio_2027
  from _base b where b.modelo_id = t.modelo_id;
update public.modelos m set precio_construccion_2027 = b.precio_2027 from _base b where b.modelo_id = m.id;
alter table public.modelo_techos alter column suplemento_ahora set not null;
alter table public.modelo_techos alter column suplemento_2027 set not null;
alter table public.modelo_techos alter column suplemento_ahora set default 0;
alter table public.modelo_techos alter column suplemento_2027 set default 0;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'modelo_techos_suplemento_no_negativo') then
    alter table public.modelo_techos add constraint modelo_techos_suplemento_no_negativo check (suplemento_ahora >= 0 and suplemento_2027 >= 0);
  end if;
end $$;
create unique index if not exists modelo_techos_un_base on public.modelo_techos (modelo_id) where es_base;
alter table public.modelo_techos rename column precio_ahora to precio_ahora_antiguo;
alter table public.modelo_techos rename column precio_2027 to precio_2027_antiguo;
comment on column public.modelo_techos.precio_ahora_antiguo is 'SIN USO desde el 30-sep-2026: el techo es un suplemento (suplemento_ahora). Se conserva hasta que el owner autorice borrarla.';
comment on column public.modelo_techos.precio_2027_antiguo is 'SIN USO desde el 30-sep-2026: el techo es un suplemento (suplemento_2027). Se conserva hasta que el owner autorice borrarla.';
comment on column public.modelo_techos.suplemento_ahora is 'Lo que suma este techo sobre la casa con su techo base (precio base del modelo o precio propio del proyecto), tramo 2026. El techo base lleva 0. 30-sep-2026.';
comment on column public.modelos.precio_construccion_2027 is 'Precio de la casa con su techo base desde el 1-ene-2027 (catálogo y proyectos que heredan). 30-sep-2026.';

-- extras: forma de la clave y nunca se borran (los contratos congelan extra_id/clave/nombre)
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'extras_clave_forma') then
    alter table public.extras add constraint extras_clave_forma check (clave ~ '^[a-z0-9_]{1,40}$');
  end if;
  if exists (select 1 from pg_constraint where conname = 'modelo_extras_extra_id_fkey' and confdeltype = 'c') then
    alter table public.modelo_extras drop constraint modelo_extras_extra_id_fkey;
    alter table public.modelo_extras add constraint modelo_extras_extra_id_fkey
      foreign key (extra_id) references public.extras(id) on delete restrict;
  end if;
end $$;

-- 13 pares con precio propio escrito a mano IGUAL a la base, en modelos con techos → «hereda» (owner 30-sep):
-- ahora no cambian; en 2027 suben con el catálogo.
do $$
declare v record; n int := 0;
begin
  for v in select mv.* , m.moneda m_moneda from public.modelos_villa mv join public.modelos m on m.id = mv.modelo_id
            where mv.precio_construccion is not null and mv.precio_construccion = m.precio_construccion
              and exists (select 1 from public.modelo_techos t where t.modelo_id = mv.modelo_id) loop
    update public.modelos_villa set precio_construccion = null where id = v.id;
    perform public._precio_log(v.modelo_id, v.proyecto_id, 'modelos_villa', v.id, 'precio_construccion', v.precio_construccion, null, v.m_moneda,
      'migracion_techos_suplemento', 'pasa a heredar la base (owner 30-sep: que suba con el catálogo en 2027)');
    n := n + 1;
  end loop;
  if n <> 13 then raise exception 'ABORTA: se esperaban 13 pares fijados a mano = base y hay %', n; end if;
end $$;

-- ── 2. fórmula única (con el tramo como parámetro interno: así se prueban los dos) ──────────────────────
create or replace function public._modelo_techos_opciones_tramo(p_modelo_id uuid, p_proyecto_id uuid, p_tramo text)
returns table(techo_id uuid, clave text, nombre text, precio numeric, moneda text, tramo text)
language sql
stable
security definer
set search_path = ''
as $$
  with base as (
    select m.moneda as m_moneda,
           mv.precio_construccion as propio,
           case when p_tramo = '2026' then m.precio_construccion else m.precio_construccion_2027 end as catalogo,
           coalesce(mv.precio_construccion, m.precio_construccion) as efectivo_ulin,
           case when mv.precio_construccion is not null then coalesce(mv.moneda, m.moneda) else m.moneda end as moneda
      from public.modelos m
      left join public.modelos_villa mv
        on mv.modelo_id = m.id and mv.proyecto_id = p_proyecto_id and mv.precio_construccion is not null
     where m.id = p_modelo_id
  ), vivos as (
    select th.* from public.modelo_techos th
     where th.modelo_id = p_modelo_id and th.activo
       and (th.alcance = 'todos'
            or exists (select 1 from public.modelo_techo_proyectos tp
                        where tp.techo_id = th.id and tp.proyecto_id = p_proyecto_id))
  )
  (
    select v.id, v.clave, v.nombre,
           coalesce(base.propio, base.catalogo)
             + case when p_tramo = '2026' then v.suplemento_ahora else v.suplemento_2027 end,
           base.m_moneda, p_tramo
      from vivos v, base
     where coalesce(base.propio, base.catalogo) is not null
     order by v.es_base desc, v.orden nulls last, v.nombre
  )
  union all
  (
    select p_modelo_id, 'ulin'::text, 'Ulin'::text, base.efectivo_ulin, base.moneda, p_tramo
      from base
     where base.efectivo_ulin is not null
       and not exists (select 1 from public.modelo_techos th where th.modelo_id = p_modelo_id)
  )
$$;
revoke all on function public._modelo_techos_opciones_tramo(uuid, uuid, text) from public, anon, authenticated;

create or replace function public._modelo_techos_opciones(p_modelo_id uuid, p_proyecto_id uuid)
returns table(techo_id uuid, clave text, nombre text, precio numeric, moneda text, tramo text)
language sql
stable
security definer
set search_path = ''
as $$
  select * from public._modelo_techos_opciones_tramo(p_modelo_id, p_proyecto_id, public.catalogo_tramo_activo())
$$;

-- ── 3. invariantes (mismo constraint trigger diferido) ──────────────────────────────────────────────────
create or replace function public._techos_invariantes_modelo(p_modelo uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_m record; v_mal text; v_n int;
begin
  if p_modelo is null then return; end if;
  if not exists (select 1 from public.modelo_techos t where t.modelo_id = p_modelo) then return; end if;  -- sin variantes: «Ulin»
  select m.nombre, m.precio_construccion b26, m.precio_construccion_2027 b27 into v_m from public.modelos m where m.id = p_modelo;
  if not found then return; end if;
  if v_m.b26 is null or v_m.b27 is null then
    raise exception '«%» tiene techos: necesita el precio de la casa con su techo base, ahora y desde 2027.', v_m.nombre using errcode = '23514';
  end if;
  select count(*) into v_n from public.modelo_techos t where t.modelo_id = p_modelo and t.es_base;
  if v_n <> 1 then
    raise exception '«%» tiene que tener exactamente un techo base (tiene %).', v_m.nombre, v_n using errcode = '23514';
  end if;
  select t.nombre into v_mal from public.modelo_techos t
   where t.modelo_id = p_modelo and t.es_base and (not t.activo or t.suplemento_ahora <> 0 or t.suplemento_2027 <> 0);
  if v_mal is not null then
    raise exception 'El techo base de «%» («%») tiene que estar activo y sin suplemento: para cambiarlo, marca antes otro como base.', v_m.nombre, v_mal using errcode = '23514';
  end if;
  -- el techo base se ofrece en todos los proyectos que venden la casa (Datos #166: no «alcance = todos», que
  -- Tropical no cumple y no hace falta: su Alang-alang está en los dos proyectos que la venden)
  select string_agg(p.nombre, ', ' order by p.nombre) into v_mal
    from public.modelos_villa mv join public.proyectos p on p.id = mv.proyecto_id
    join public.modelo_techos t on t.modelo_id = mv.modelo_id and t.es_base
   where mv.modelo_id = p_modelo and t.alcance = 'lista'
     and not exists (select 1 from public.modelo_techo_proyectos tp where tp.techo_id = t.id and tp.proyecto_id = mv.proyecto_id);
  if v_mal is not null then
    raise exception 'El techo base de «%» no se ofrecería en: %. El techo base va en todos los proyectos que venden la casa.', v_m.nombre, v_mal using errcode = '23514';
  end if;
end $$;

-- el invariante también mira la base 2027
drop trigger if exists techos_invariantes on public.modelos;
create constraint trigger techos_invariantes after update of precio_construccion, precio_construccion_2027 on public.modelos
  deferrable initially deferred for each row execute function public._techos_invariantes_trg();

-- ── 4. escritura ────────────────────────────────────────────────────────────────────────────────────────
create or replace function public._lw_suplemento(p_v jsonb, p_campo text, p_moneda text)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare v numeric;
begin
  v := public._lw_num(p_v, p_campo);
  if v is null then raise exception '% es obligatorio (0 si no suma nada)', p_campo using errcode = '22023'; end if;
  if v < 0 or v >= case p_moneda when 'IDR' then 500000000000::numeric else 50000000::numeric end then
    raise exception '% tiene que ser 0 o más (y razonable en %)', p_campo, p_moneda using errcode = '22023';
  end if;
  return v;
end $$;
revoke all on function public._lw_suplemento(jsonb, text, text) from public, anon, authenticated;

-- p_datos: {nombre, descripcion?, suplemento_ahora, suplemento_2027, alcance, proyectos?}
create or replace function public.modelo_techo_crea(p_modelo_id uuid, p_datos jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m public.modelos%rowtype; k text; v_nombre text; v_desc text; v_a numeric; v_z numeric;
  v_clave text; v_base text; v_i int := 1; v_id uuid; v_orden int; v_mon text; v_primero boolean;
begin
  if not public.es_admin() then raise exception 'Los techos los da de alta administración' using errcode = '42501'; end if;
  if jsonb_typeof(p_datos) is distinct from 'object' then raise exception 'Datos no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_datos) loop
    if k not in ('nombre', 'descripcion', 'suplemento_ahora', 'suplemento_2027', 'alcance', 'proyectos') then
      raise exception 'Ese dato del techo no se da de alta desde aquí: %', k using errcode = '22023';
    end if;
  end loop;
  select * into v_m from public.modelos m where m.id = p_modelo_id for update;
  if not found then raise exception 'Ese modelo ya no existe: recarga la página' using errcode = '22023'; end if;
  v_mon := coalesce(v_m.moneda, 'EUR');
  if v_m.precio_construccion is null or v_m.precio_construccion_2027 is null then
    raise exception 'Pon antes el precio de la casa con su techo base (ahora y 2027) en «Precio de construcción».' using errcode = '22023';
  end if;
  v_nombre := btrim(coalesce(p_datos->>'nombre', ''));
  if v_nombre = '' or length(v_nombre) > 60 then raise exception 'El nombre del techo es obligatorio (máximo 60 caracteres)' using errcode = '22023'; end if;
  if exists (select 1 from public.modelo_techos t where t.modelo_id = p_modelo_id and lower(t.nombre) = lower(v_nombre)) then
    raise exception 'Este modelo ya tiene un techo «%» (activo o retirado)', v_nombre using errcode = '22023';
  end if;
  v_desc := nullif(btrim(coalesce(p_datos->>'descripcion', '')), '');
  if length(v_desc) > 500 then raise exception 'La descripción es demasiado larga (máximo 500)' using errcode = '22023'; end if;
  -- el primer techo de un modelo ES su techo base: suplemento 0 por definición
  v_primero := not exists (select 1 from public.modelo_techos t where t.modelo_id = p_modelo_id);
  if v_primero then
    v_a := 0; v_z := 0;
  else
    v_a := public._lw_suplemento(p_datos->'suplemento_ahora', 'El suplemento de ahora', v_mon);
    v_z := public._lw_suplemento(p_datos->'suplemento_2027', 'El suplemento de 2027', v_mon);
  end if;
  v_base := coalesce(public._slug_techo(v_nombre), 'techo');
  v_clave := v_base;
  while v_clave = 'ulin' or exists (select 1 from public.modelo_techos t where t.modelo_id = p_modelo_id and t.clave = v_clave) loop
    v_i := v_i + 1; v_clave := left(v_base, 36) || '_' || v_i;
  end loop;
  select coalesce(max(t.orden), 0) + 1 into v_orden from public.modelo_techos t where t.modelo_id = p_modelo_id;
  insert into public.modelo_techos (modelo_id, clave, nombre, descripcion, suplemento_ahora, suplemento_2027, es_base, orden, activo, alcance)
  values (p_modelo_id, v_clave, v_nombre, v_desc, v_a, v_z, v_primero, v_orden, true, 'todos')
  returning id into v_id;
  perform public._modelo_techo_alcance(v_id, p_modelo_id, coalesce(p_datos->>'alcance', 'todos'), p_datos->'proyectos');
  perform public._precio_log(p_modelo_id, null, 'modelo_techos', v_id, 'suplemento_ahora', null, v_a, v_mon, 'modelo_techo_crea', 'alta del techo «' || v_nombre || '»');
  perform public._precio_log(p_modelo_id, null, 'modelo_techos', v_id, 'suplemento_2027', null, v_z, v_mon, 'modelo_techo_crea');
  return v_id;
end $$;

-- p_techos: [{id, suplemento_ahora?, suplemento_2027?}] — solo la llama modelo_techos_guarda_lote
create or replace function public.modelo_techos_guarda(p_id uuid, p_techos jsonb)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare v_m public.modelos%rowtype; e jsonb; t record; v_ids uuid[]; v_n int; v_a numeric; v_z numeric; k text; v_mon text;
begin
  if not public.es_admin() then raise exception 'Los suplementos de los techos los cambia administración' using errcode = '42501'; end if;
  if jsonb_typeof(p_techos) is distinct from 'array' then raise exception 'Techos no válidos' using errcode = '22023'; end if;
  select * into v_m from public.modelos m where m.id = p_id for update;
  if not found then raise exception 'Ese modelo ya no existe: recarga la página' using errcode = '22023'; end if;
  v_mon := coalesce(v_m.moneda, 'EUR');
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
      if k not in ('id', 'suplemento_ahora', 'suplemento_2027') then raise exception 'Ese dato del techo no se edita desde aquí: %', k using errcode = '22023'; end if;
    end loop;
    select * into t from public.modelo_techos x where x.id = (e->>'id')::uuid for update;
    v_a := case when e ? 'suplemento_ahora' then public._lw_suplemento(e->'suplemento_ahora', 'El suplemento de «' || t.nombre || '»', v_mon) else t.suplemento_ahora end;
    v_z := case when e ? 'suplemento_2027' then public._lw_suplemento(e->'suplemento_2027', 'El suplemento 2027 de «' || t.nombre || '»', v_mon) else t.suplemento_2027 end;
    update public.modelo_techos set suplemento_ahora = v_a, suplemento_2027 = v_z where id = t.id;
    perform public._precio_log(p_id, null, 'modelo_techos', t.id, 'suplemento_ahora', t.suplemento_ahora, v_a, v_mon, 'modelo_techos_guarda');
    perform public._precio_log(p_id, null, 'modelo_techos', t.id, 'suplemento_2027', t.suplemento_2027, v_z, v_mon, 'modelo_techos_guarda');
  end loop;
  return cardinality(v_ids);
end $function$;
revoke execute on function public.modelo_techos_guarda(uuid, jsonb) from public, anon, authenticated;

-- p_cambios: {nombre?, descripcion?, orden?, activo?, alcance?, proyectos?, es_base?: true}
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
    if k not in ('nombre', 'descripcion', 'orden', 'activo', 'alcance', 'proyectos', 'es_base') then
      raise exception 'Ese dato del techo no se edita desde aquí: %', k using errcode = '22023';
    end if;
  end loop;
  select * into t from public.modelo_techos x where x.id = p_id for update;
  if not found then raise exception 'Ese techo ya no existe: recarga la página' using errcode = '22023'; end if;
  perform 1 from public.modelos m where m.id = t.modelo_id for update;

  if p_cambios ? 'es_base' then
    if public._lw_bool(p_cambios->'es_base', 'Techo base') is not true then
      raise exception 'Para dejar de ser base, marca otro techo como base' using errcode = '22023';
    end if;
    if not t.es_base then
      update public.modelo_techos set es_base = false where modelo_id = t.modelo_id and es_base;
      update public.modelo_techos set es_base = true where id = t.id;
    end if;
  end if;
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
    if not v_activo and t.activo then v_uso := public._modelo_techo_uso(t.id); end if;
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
    perform public._modelo_techo_alcance(t.id, t.modelo_id, v_alcance, case when v_alcance = 'lista' then p_cambios->'proyectos' else null end);
  end if;
  if v_uso > 0 and not coalesce(p_confirmado, false) then
    raise exception '% contrato(s) de Construcción sin firmar llevan este techo y dejarían de poder cambiarlo a él. Conservan su precio congelado.', v_uso
      using errcode = 'LW409', hint = v_uso::text;
  end if;
  return jsonb_build_object('ok', true, 'contratos_sin_firmar', v_uso);
end $$;
revoke execute on function public.modelo_techo_edita(uuid, jsonb, boolean) from public, anon, authenticated;

-- modelo_techos_guarda_lote: el cambio de techo base va PRIMERO (el suplemento del nuevo base se valida al commit)
create or replace function public.modelo_techos_guarda_lote(p_id uuid, p_precios jsonb, p_ediciones jsonb, p_confirmado boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare e jsonb; v_uso int := 0; r jsonb; v_tid uuid;
begin
  if not public.es_admin() then raise exception 'Los techos los cambia administración' using errcode = '42501'; end if;
  if jsonb_typeof(coalesce(p_precios, '[]'::jsonb)) <> 'array' or jsonb_typeof(coalesce(p_ediciones, '[]'::jsonb)) <> 'array' then
    raise exception 'Cambios de techos no válidos' using errcode = '22023';
  end if;
  for e in select * from jsonb_array_elements(coalesce(p_ediciones, '[]'::jsonb)) loop
    begin v_tid := (e->>'id')::uuid; exception when others then raise exception 'Techo no válido' using errcode = '22023'; end;
    if not exists (select 1 from public.modelo_techos t where t.id = v_tid and t.modelo_id = p_id) then
      raise exception 'Alguno de los techos no es de este modelo (o ya no existe): recarga la página' using errcode = '22023';
    end if;
  end loop;
  for e in select * from jsonb_array_elements(coalesce(p_ediciones, '[]'::jsonb)) where value->'cambios' ? 'es_base' loop
    perform public.modelo_techo_edita((e->>'id')::uuid, jsonb_build_object('es_base', e->'cambios'->'es_base'), true);
  end loop;
  if jsonb_array_length(coalesce(p_precios, '[]'::jsonb)) > 0 then
    perform public.modelo_techos_guarda(p_id, p_precios);
  end if;
  for e in select * from jsonb_array_elements(coalesce(p_ediciones, '[]'::jsonb)) loop
    if (e->'cambios') - 'es_base' = '{}'::jsonb then continue; end if;
    r := public.modelo_techo_edita((e->>'id')::uuid, (e->'cambios') - 'es_base', true);
    v_uso := v_uso + coalesce((r->>'contratos_sin_firmar')::int, 0);
  end loop;
  if v_uso > 0 and not coalesce(p_confirmado, false) then
    raise exception '% contrato(s) de Construcción sin firmar llevan techos que retiras o sacas de su proyecto: ya no podrán volver a elegirlos. Conservan su precio congelado.', v_uso
      using errcode = 'LW409', hint = v_uso::text;
  end if;
  return jsonb_build_object('ok', true, 'contratos_sin_firmar', v_uso);
end $$;

-- modelo_precios_guarda: + base 2027; ya NO mueve los techos (son suplementos). 'desplaza_techos' se acepta y se ignora
-- (pestañas abiertas con el JS anterior).
create or replace function public.modelo_precios_guarda(p_id uuid, p_cambios jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_m public.modelos%rowtype; k text; e jsonb; v record;
  v_base numeric; v_base27 numeric; v_mon text;
  v_ids uuid[]; v_n int; v_precio numeric; v_py record; v_fila uuid;
begin
  if not public.es_admin() then raise exception 'Los precios de los modelos los cambia administración' using errcode = '42501'; end if;
  if jsonb_typeof(p_cambios) is distinct from 'object' then raise exception 'Datos de precio no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_cambios) loop
    if k not in ('base', 'base_2027', 'moneda', 'desplaza_techos', 'villas', 'altas') then
      raise exception 'Ese dato de precio no se edita desde aquí: %', k using errcode = '22023';
    end if;
  end loop;
  select * into v_m from public.modelos m where m.id = p_id for update;
  if not found then raise exception 'Ese modelo ya no existe: recarga la página' using errcode = '22023'; end if;

  v_base := case when p_cambios ? 'base' then public._lw_num(p_cambios->'base', 'El precio base') else v_m.precio_construccion end;
  v_base27 := case when p_cambios ? 'base_2027' then public._lw_num(p_cambios->'base_2027', 'El precio base 2027') else v_m.precio_construccion_2027 end;
  v_mon := case when p_cambios ? 'moneda' then upper(btrim(coalesce(p_cambios->>'moneda', ''))) else coalesce(v_m.moneda, 'EUR') end;
  if v_mon not in ('EUR', 'USD', 'AUD', 'IDR') then raise exception 'Moneda no admitida (EUR, USD, AUD o IDR)' using errcode = '22023'; end if;
  if v_base is not null and not public._lw_importe_ok(v_base, v_mon) then
    raise exception 'El precio base tiene que ser mayor que cero (y razonable en %)', v_mon using errcode = '22023';
  end if;
  if v_base27 is not null and not public._lw_importe_ok(v_base27, v_mon) then
    raise exception 'El precio base 2027 tiene que ser mayor que cero (y razonable en %)', v_mon using errcode = '22023';
  end if;

  if v_mon <> coalesce(v_m.moneda, 'EUR') and (
       exists (select 1 from public.modelo_techos x where x.modelo_id = p_id)
    or exists (select 1 from public.modelo_extras x where x.modelo_id = p_id)
    or exists (select 1 from public.modelos_villa x where x.modelo_id = p_id)
    or exists (select 1 from public.deck_forecast x where x.modelo_id = p_id)) then
    raise exception 'La moneda no se cambia: el modelo ya tiene techos, extras, precios por proyecto o previsión del deck en %, y cambiarla cambiaría la unidad sin tocar la cifra', coalesce(v_m.moneda, 'EUR')
      using errcode = '22023';
  end if;

  if v_base is distinct from v_m.precio_construccion or v_base27 is distinct from v_m.precio_construccion_2027
     or v_mon <> coalesce(v_m.moneda, 'EUR') then
    update public.modelos set precio_construccion = v_base, precio_construccion_2027 = v_base27, moneda = v_mon, actualizado_en = now() where id = p_id;
    perform public._precio_log(p_id, null, 'modelos', p_id, 'precio_construccion', v_m.precio_construccion, v_base, v_mon, 'modelo_precios_guarda');
    perform public._precio_log(p_id, null, 'modelos', p_id, 'precio_construccion_2027', v_m.precio_construccion_2027, v_base27, v_mon, 'modelo_precios_guarda');
    if v_mon <> coalesce(v_m.moneda, 'EUR') then
      perform public._precio_log(p_id, null, 'modelos', p_id, 'moneda', null, null, v_mon, 'modelo_precios_guarda',
                                 'moneda ' || coalesce(v_m.moneda, 'EUR') || ' → ' || v_mon);
    end if;
  end if;

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

  if v_base is null and exists (select 1 from public.modelos_villa x where x.modelo_id = p_id and x.precio_construccion is null) then
    raise exception 'Hay proyectos que heredan el precio base: ponles precio propio antes de dejar la base vacía' using errcode = '22023';
  end if;

  return jsonb_build_object('ok', true, 'base', v_base, 'base_2027', v_base27, 'moneda', v_mon, 'techos_movidos', 0,
                            'contratos_no_firmados_min', public._modelo_contratos_no_firmados(p_id));
end $function$;

-- ── 5. extras: alta y retirada del catálogo ─────────────────────────────────────────────────────────────
-- p_datos: {nombre, descripcion?, precio} — se ofrece en ESTE modelo; en los demás queda «no se ofrece» hasta
-- que se le ponga precio allí (Administración #166: sin fila «disponible sin precio»).
create or replace function public.extra_crea(p_modelo_id uuid, p_datos jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m public.modelos%rowtype; k text; v_nombre text; v_desc text; v_p numeric; v_mon text;
  v_clave text; v_base text; v_i int := 1; v_id uuid; v_orden int;
begin
  if not public.es_admin() then raise exception 'Los extras los da de alta administración' using errcode = '42501'; end if;
  if jsonb_typeof(p_datos) is distinct from 'object' then raise exception 'Datos no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_datos) loop
    if k not in ('nombre', 'descripcion', 'precio') then raise exception 'Ese dato del extra no se da de alta desde aquí: %', k using errcode = '22023'; end if;
  end loop;
  select * into v_m from public.modelos m where m.id = p_modelo_id for update;
  if not found then raise exception 'Ese modelo ya no existe: recarga la página' using errcode = '22023'; end if;
  v_mon := coalesce(v_m.moneda, 'EUR');
  v_nombre := btrim(coalesce(p_datos->>'nombre', ''));
  if v_nombre = '' or length(v_nombre) > 60 then raise exception 'El nombre del extra es obligatorio (máximo 60 caracteres)' using errcode = '22023'; end if;
  if exists (select 1 from public.extras e where lower(e.nombre) = lower(v_nombre)) then
    raise exception 'Ya hay un extra «%» en el catálogo (activo o retirado): si está retirado, reactívalo', v_nombre using errcode = '22023';
  end if;
  v_desc := nullif(btrim(coalesce(p_datos->>'descripcion', '')), '');
  if length(v_desc) > 500 then raise exception 'La descripción es demasiado larga (máximo 500)' using errcode = '22023'; end if;
  v_p := public._lw_num(p_datos->'precio', 'El precio del extra');
  if not public._lw_importe_ok(v_p, v_mon) then raise exception 'El extra necesita un precio mayor que cero en este modelo (y razonable en %)', v_mon using errcode = '22023'; end if;
  perform 1 from public.extras for update;   -- serializa altas: la clave y el orden no se pisan entre pestañas
  v_base := coalesce(public._slug_techo(v_nombre), 'extra');
  v_clave := v_base;
  while exists (select 1 from public.extras e where e.clave = v_clave) loop
    v_i := v_i + 1; v_clave := left(v_base, 36) || '_' || v_i;
  end loop;
  select coalesce(max(e.orden), 0) + 1 into v_orden from public.extras e;
  insert into public.extras (clave, nombre, descripcion, activo, orden) values (v_clave, v_nombre, v_desc, true, v_orden) returning id into v_id;
  insert into public.modelo_extras (modelo_id, extra_id, precio, moneda, disponible)
    select m.id, v_id, case when m.id = p_modelo_id then v_p end, coalesce(m.moneda, 'EUR'), m.id = p_modelo_id
      from public.modelos m;
  perform public._precio_log(p_modelo_id, null, 'modelo_extras', v_id, 'precio', null, v_p, v_mon, 'extra_crea', 'alta del extra «' || v_nombre || '»');
  return v_id;
end $$;
revoke all on function public.extra_crea(uuid, jsonb) from public, anon;
grant execute on function public.extra_crea(uuid, jsonb) to authenticated;

-- p_cambios: {nombre?, descripcion?, orden?, activo?}. Retirar = activo false (nunca se borra). Si hay contratos de
-- Construcción sin firmar con ese extra: LW409 salvo p_confirmado — al editarlos habrá que quitarlo (Datos #166).
create or replace function public.extra_edita(p_id uuid, p_cambios jsonb, p_confirmado boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare x public.extras%rowtype; k text; v_nombre text; v_desc text; v_act boolean; v_uso int := 0;
begin
  if not public.es_admin() then raise exception 'Los extras los cambia administración' using errcode = '42501'; end if;
  if jsonb_typeof(p_cambios) is distinct from 'object' then raise exception 'Cambios no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_cambios) loop
    if k not in ('nombre', 'descripcion', 'orden', 'activo') then raise exception 'Ese dato del extra no se edita desde aquí: %', k using errcode = '22023'; end if;
  end loop;
  select * into x from public.extras e where e.id = p_id for update;
  if not found then raise exception 'Ese extra ya no existe: recarga la página' using errcode = '22023'; end if;
  if p_cambios ? 'nombre' then
    v_nombre := btrim(coalesce(p_cambios->>'nombre', ''));
    if v_nombre = '' or length(v_nombre) > 60 then raise exception 'El nombre del extra es obligatorio (máximo 60 caracteres)' using errcode = '22023'; end if;
    if exists (select 1 from public.extras e where e.id <> p_id and lower(e.nombre) = lower(v_nombre)) then
      raise exception 'Ya hay otro extra «%»', v_nombre using errcode = '22023';
    end if;
    update public.extras set nombre = v_nombre where id = p_id;
  end if;
  if p_cambios ? 'descripcion' then
    v_desc := nullif(btrim(coalesce(p_cambios->>'descripcion', '')), '');
    if length(v_desc) > 500 then raise exception 'La descripción es demasiado larga (máximo 500)' using errcode = '22023'; end if;
    update public.extras set descripcion = v_desc where id = p_id;
  end if;
  if p_cambios ? 'orden' then
    update public.extras set orden = public._lw_num(p_cambios->'orden', 'El orden')::int where id = p_id;
  end if;
  if p_cambios ? 'activo' then
    v_act := public._lw_bool(p_cambios->'activo', 'Activo');
    if v_act is null then raise exception 'Activo tiene que ser sí o no' using errcode = '22023'; end if;
    if not v_act and x.activo then
      select count(*) into v_uso from public.contratos c
       where c.tipo = 'construccion' and not coalesce(c.bloqueado, false)
         and exists (select 1 from jsonb_array_elements(coalesce(c.datos->'extras', '[]'::jsonb)) z where z->>'extra_id' = p_id::text);
    end if;
    update public.extras set activo = v_act where id = p_id;
  end if;
  if v_uso > 0 and not coalesce(p_confirmado, false) then
    raise exception '% contrato(s) de Construcción sin firmar llevan este extra: se quedan con él, pero para volver a guardarlos habrá que quitarlo.', v_uso
      using errcode = 'LW409', hint = v_uso::text;
  end if;
  return jsonb_build_object('ok', true, 'contratos_sin_firmar', v_uso);
end $$;
revoke all on function public.extra_edita(uuid, jsonb, boolean) from public, anon, authenticated;

-- La pantalla retira/reactiva varios extras de una vez: UNA transacción (misma lección que el lote de techos:
-- una cadena de llamadas deja el catálogo a medias). p_cambios: [{id, cambios: {activo}}]. LW409 al final.
create or replace function public.extras_catalogo_guarda(p_cambios jsonb, p_confirmado boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare e jsonb; r jsonb; v_uso int := 0;
begin
  if not public.es_admin() then raise exception 'Los extras los cambia administración' using errcode = '42501'; end if;
  if jsonb_typeof(p_cambios) is distinct from 'array' then raise exception 'Cambios no válidos' using errcode = '22023'; end if;
  for e in select * from jsonb_array_elements(p_cambios) loop
    begin
      r := public.extra_edita((e->>'id')::uuid, e->'cambios', true);
    exception when invalid_text_representation then raise exception 'Extra no válido' using errcode = '22023';
    end;
    v_uso := v_uso + coalesce((r->>'contratos_sin_firmar')::int, 0);
  end loop;
  if v_uso > 0 and not coalesce(p_confirmado, false) then
    raise exception '% contrato(s) de Construcción sin firmar llevan extras que retiras: se quedan con ellos, pero para volver a guardarlos habrá que quitarlos.', v_uso
      using errcode = 'LW409', hint = v_uso::text;
  end if;
  return jsonb_build_object('ok', true, 'contratos_sin_firmar', v_uso);
end $$;
revoke all on function public.extras_catalogo_guarda(jsonb, boolean) from public, anon;
grant execute on function public.extras_catalogo_guarda(jsonb, boolean) to authenticated;

-- ── 6. lectores ─────────────────────────────────────────────────────────────────────────────────────────
-- La web sigue recibiendo el precio COMPLETO (now / y2027 = base del tramo + suplemento) y el «desde» del tramo
-- activo (Administración #166: antes era siempre el de 2026).
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
               'desde',              case when public.catalogo_tramo_activo() = '2026' then m.precio_construccion
                                          else coalesce(m.precio_construccion_2027, m.precio_construccion) end,
               'renders_pendientes', nullif(m.renders_pendientes, false),
               'alcance',            m.alcance,
               'acabados',           m.acabados,
               'techos', (select jsonb_object_agg(t.clave, jsonb_strip_nulls(jsonb_build_object(
                                   'nombre', t.nombre, 'desc', t.descripcion,
                                   'now',    m.precio_construccion + t.suplemento_ahora,
                                   'y2027',  m.precio_construccion_2027 + t.suplemento_2027,
                                   'orden',  t.orden,
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

-- ── 7. comprobaciones: si algo no cuadra, la migración entera se deshace ────────────────────────────────
set constraints all immediate;
do $$
declare n int; v_mal text;
begin
  -- ningún cuerpo de función sigue leyendo las columnas viejas
  select string_agg(p.proname, ', ') into v_mal from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.prosrc ~ '\mprecio_(ahora|2027)\M';
  if v_mal is not null then raise exception 'ABORTA: funciones que siguen leyendo precio_ahora/precio_2027: %', v_mal; end if;

  -- cifras: iguales que antes en los dos tramos, salvo los 13 pares que pasan a heredar (solo 2027, decidido)
  create temp table _despues on commit drop as
    select t.tramo_prueba, x.modelo_id, x.proyecto_id, o.techo_id, o.clave, o.precio
      from (select mv.modelo_id, mv.proyecto_id from public.modelos_villa mv
            union select m.id, null::uuid from public.modelos m) x
      cross join (values ('2026'), ('2027')) t(tramo_prueba)
      cross join lateral public._modelo_techos_opciones_tramo(x.modelo_id, x.proyecto_id, t.tramo_prueba) o;
  create temp table _heredan on commit drop as
    select l.modelo_id, l.proyecto_id from public.modelos_precios_log l where l.origen = 'migracion_techos_suplemento';
  select count(*) into n from (
    (select * from _antes except select * from _despues)
    union all
    (select * from _despues except select * from _antes)) d
   where d.tramo_prueba <> '2027'
      or not exists (select 1 from _heredan h where h.modelo_id = d.modelo_id and h.proyecto_id = d.proyecto_id);
  if n > 0 then raise exception 'ABORTA: % cifras de techo cambian sin estar decidido', n; end if;
  -- los 13 que heredan: en 2027 = base 2027 + suplemento
  select count(*) into n from _despues d join _heredan h on h.modelo_id = d.modelo_id and h.proyecto_id = d.proyecto_id
    join public.modelo_techos t on t.id = d.techo_id join public.modelos m on m.id = d.modelo_id
   where d.tramo_prueba = '2027' and d.precio <> m.precio_construccion_2027 + t.suplemento_2027;
  if n > 0 then raise exception 'ABORTA: % precios 2027 de los pares que heredan no son base 2027 + suplemento', n; end if;
  -- Alang-alang de la Dali: +4.000 ahora y +0 en 2027 (decisión del owner, coincide con lo tecleado)
  select count(*) into n from public.modelo_techos t join public.modelos m on m.id = t.modelo_id
   where m.nombre = 'Dali' and t.clave = 'alang_alang' and t.suplemento_ahora = 4000 and t.suplemento_2027 = 0;
  if n <> 1 then raise exception 'ABORTA: el suplemento del Alang-alang de la Dali no es +4.000 / +0'; end if;
  -- web: el catálogo público sale idéntico (tramo 2026)
  if (select j from _catalogo_antes) is distinct from public.catalogo_publico() then
    raise exception 'ABORTA: catalogo_publico cambia';
  end if;
  -- contratos: los mismos descuadres que antes (ni uno más)
  select count(*) into n from (
    select c.numero from public.contratos c
      left join public.modelo_techos th on th.id::text = c.datos->'techo'->>'techo_id'
     where c.tipo = 'construccion' and c.datos->'techo'->>'techo_id' is not null
       and (select o.precio from public._modelo_techos_opciones(coalesce(th.modelo_id, (c.datos->'techo'->>'techo_id')::uuid), c.proyecto_id) o
             where o.techo_id::text = c.datos->'techo'->>'techo_id') is distinct from public.lw_importe(c.datos->'techo'->>'precio')
    except select numero from _contratos_antes) z;
  if n > 0 then raise exception 'ABORTA: % contratos de Construcción dejarían de cuadrar con la fórmula', n; end if;
  -- invariantes de todos los modelos
  perform public._techos_invariantes_modelo(m.id) from public.modelos m;
end $$;
set constraints all deferred;
