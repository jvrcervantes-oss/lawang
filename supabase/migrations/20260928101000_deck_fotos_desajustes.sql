-- destructivo-ok: solo añade (tabla nueva vacía y funciones nuevas cerradas); el único delete es el CUERPO de deck_transicion_termina, que quita la marca de transición de un proyecto (no son datos de cliente).
-- AXW-66 S2 (28-sep-2026, Datos; encargo encargos/20260928_lawang_deck_fotos_privadas.md, revisión previa #139).
-- Las fotos de proyectos SIN deck abierto viven en el bucket privado `deck-privado`; las de decks abiertos y las de
-- modelo, en el público `deck`. Aquí va la parte de base de datos; mover los ficheros es de la edge `ficheros`
-- (Storage API, nunca `update storage.objects`, que no mueve el fichero real).
--
-- Solo AÑADE: una tabla y funciones nuevas, todas cerradas (solo service_role). No cambia ninguna función existente:
--   · la vieja investor_deck_activar(text, boolean) sigue viva y con su grant: la llama el front hasta S4; su drop
--     va con el REVOKE después de S4 (orden de la revisión #139: edge+front aterrizados → hash servido → REVOKE).
--   · deck_foto_registra / borra y la clase deck_foto de la edge no cambian en esta tanda (cambiarlas antes del front
--     rompería «Fotos del deck», que hoy pinta con URL pública).
--
-- Bucket DEBIDO de cada objeto (derivado, sin columna: la ubicación real ya tiene dueño, storage.objects):
--   · solo los prefijos `proyecto/` y `modelo/` (lista CERRADA aquí; `formacion/` y cualquier otro quedan fuera);
--   · sin fila en deck_fotos → `deck-privado`, salvo que tenga < 1 h (puede ser una subida en curso: se salta);
--   · ámbito modelo → `deck`;
--   · proyecto en transición (marca < 15 min) → lo que diga la marca (`abrir`);
--   · si no, deck_proyecto_abierto(nombre) → `deck`, y si no → `deck-privado`.
--   El mismo `name` en los DOS buckets es desajuste (motivo en_ambos): no se arregla solo, se informa.

-- ── marca de transición: serializa abrir/cerrar por proyecto ─────────────────────────────────────────────────────
create table if not exists public.deck_transiciones (
  proyecto_id uuid primary key references public.proyectos(id) on delete cascade,
  abrir       boolean     not null,
  desde       timestamptz not null default now(),
  quien       text        not null default coalesce(auth.email(), '(sistema)')
);
alter table public.deck_transiciones enable row level security;
revoke all on table public.deck_transiciones from public, anon, authenticated;
grant all on table public.deck_transiciones to service_role;

-- ── dónde DEBE estar cada objeto, y lo que no está ahí ───────────────────────────────────────────────────────────
-- p_proyecto_id null  → todos, SALTANDO los proyectos en transición (lo usa el barrido `sincroniza`).
-- p_proyecto_id dado  → solo ese proyecto, esté o no en transición (lo usa `deck_activa` para acabar el suyo).
create or replace function public.deck_fotos_desajustes(p_proyecto_id uuid default null)
returns table (name text, bucket_real text, bucket_debido text, proyecto_id uuid, motivo text)
language sql stable security definer set search_path to ''
as $function$
  with objs as (
    select o.name, o.bucket_id, o.created_at
      from storage.objects o
     where o.bucket_id in ('deck', 'deck-privado')
       and (o.name like 'proyecto/%' or o.name like 'modelo/%')
  ), nombres as (
    select n.name, array_agg(n.bucket_id order by n.bucket_id) as buckets, min(n.created_at) as creado
      from objs n group by n.name
  ), est as (
    select n.name, n.buckets, n.creado, f.ambito, f.proyecto_id, p.nombre, t.abrir as t_abrir, t.desde as t_desde
      from nombres n
      left join public.deck_fotos f on f.path = n.name
      left join public.proyectos p on p.id = f.proyecto_id
      left join public.deck_transiciones t on t.proyecto_id = f.proyecto_id and t.desde > now() - interval '15 minutes'
  ), deb as (
    select e.*,
           case
             when e.ambito is null then case when e.creado > now() - interval '1 hour' then null else 'deck-privado' end
             when e.ambito = 'modelo' then 'deck'
             when e.t_abrir is not null then case when e.t_abrir then 'deck' else 'deck-privado' end
             when public.deck_proyecto_abierto(e.nombre) then 'deck'
             else 'deck-privado'
           end as debido
      from est e
  )
  select d.name,
         case when cardinality(d.buckets) > 1 then 'ambos' else d.buckets[1] end,
         d.debido,
         d.proyecto_id,
         case when cardinality(d.buckets) > 1 then 'en_ambos' when d.ambito is null then 'huerfano' else 'bucket' end
    from deb d
   where d.debido is not null
     and (cardinality(d.buckets) > 1 or d.buckets[1] <> d.debido)
     and (case when p_proyecto_id is null then d.t_desde is null else d.proyecto_id = p_proyecto_id end)
   order by d.name;
$function$;
revoke all on function public.deck_fotos_desajustes(uuid) from public, anon, authenticated;
grant execute on function public.deck_fotos_desajustes(uuid) to service_role;

-- ── abrir/cerrar un deck: marca → (mover) → flag → (mover) → quita marca. Lo orquesta la edge `deck_activa`. ──
create or replace function public.deck_transicion_empieza(p_uid uuid, p_proyecto_id uuid, p_abrir boolean)
returns text
language plpgsql security definer set search_path to ''
as $function$
declare v_nombre text; v_n int;
begin
  perform public._actua_como(p_uid);
  if not public.es_admin() then raise exception 'Solo administración abre o cierra un deck' using errcode = '42501'; end if;
  if p_abrir is null then raise exception 'Falta decir si se abre o se cierra' using errcode = '22023'; end if;
  select p.nombre into v_nombre from public.proyectos p where p.id = p_proyecto_id;
  if v_nombre is null then raise exception 'Ese proyecto no existe' using errcode = '22023'; end if;
  -- «abierto» = alguna unidad publicada: un proyecto sin unidades no se puede abrir (sus fotos saldrían al público
  -- y el flag no cambiaría nada; medido en la prueba del 28-sep con el proyecto con más fotos cerradas)
  if p_abrir and not exists (select 1 from public.unidades u where u.proyecto = v_nombre) then
    raise exception 'Este proyecto no tiene unidades: su deck no se puede abrir' using errcode = '22023';
  end if;
  -- una marca de más de 15 min es de un intento que murió a medias: se puede retomar (todo el camino es idempotente)
  insert into public.deck_transiciones as t (proyecto_id, abrir, desde, quien)
  values (p_proyecto_id, p_abrir, now(), coalesce((select auth.email()), '(sistema)'))
  on conflict (proyecto_id) do update set abrir = excluded.abrir, desde = excluded.desde, quien = excluded.quien
   where t.desde <= now() - interval '15 minutes';
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Ya hay un cambio en curso en el deck de %: espera a que termine', v_nombre using errcode = '55P03'; end if;
  return v_nombre;
end $function$;
revoke all on function public.deck_transicion_empieza(uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function public.deck_transicion_empieza(uuid, uuid, boolean) to service_role;

create or replace function public.deck_transicion_termina(p_proyecto_id uuid)
returns void
language sql security definer set search_path to ''
as $function$ delete from public.deck_transiciones where proyecto_id = p_proyecto_id; $function$;
revoke all on function public.deck_transicion_termina(uuid) from public, anon, authenticated;
grant execute on function public.deck_transicion_termina(uuid) to service_role;

-- Sucesora de investor_deck_activar(text, boolean): mismo efecto y misma auditoría, pero NACE CERRADA (solo
-- service_role), el usuario llega por p_uid (la edge lo saca de auth.getUser(jwt), nunca del body) y exige la marca
-- de transición con el mismo sentido: sin ella no se cambia el flag (así nadie abre un deck sin pasar antes sus fotos
-- al público). Nombre distinto a propósito: sin sobrecarga, el `.rpc('investor_deck_activar', …)` del front sigue
-- resolviendo a la vieja sin ambigüedad hasta que se retire.
create or replace function public.investor_deck_activa_como(p_uid uuid, p_proyecto_id uuid, p_activo boolean)
returns integer
language plpgsql security definer set search_path to ''
as $function$
declare v_nombre text; v_count integer;
begin
  perform public._actua_como(p_uid);
  if not public.es_admin() then raise exception 'solo un admin puede activar/desactivar el investor deck' using errcode = '42501'; end if;
  select p.nombre into v_nombre from public.proyectos p where p.id = p_proyecto_id;
  if v_nombre is null then raise exception 'proyecto no encontrado' using errcode = '22023'; end if;
  if not exists (select 1 from public.deck_transiciones t
                  where t.proyecto_id = p_proyecto_id and t.abrir = p_activo and t.desde > now() - interval '15 minutes') then
    raise exception 'El deck se abre o se cierra desde su botón (falta la marca de transición)' using errcode = '55000';
  end if;
  update public.unidades set publicado_investor_deck = p_activo where proyecto = v_nombre;
  get diagnostics v_count = row_count;
  insert into public.deck_publicaciones (tabla, fila_id, accion, antes, despues)
  values ('investor_deck_activacion', p_proyecto_id, case when p_activo then 'alta' else 'baja' end, null,
          jsonb_build_object('proyecto', v_nombre, 'unidades_afectadas', v_count, 'activo', p_activo));
  return v_count;
end $function$;
revoke all on function public.investor_deck_activa_como(uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function public.investor_deck_activa_como(uuid, uuid, boolean) to service_role;

-- ── ubicación real de las fotos pedidas, para firmar (acción `urls`) ────────────────────────────────────────────
-- Solo ids: el path sale de deck_fotos y el bucket de storage.objects, nunca del cliente. Mismo permiso que leer
-- deck_fotos (es_agente). Tope 200 por llamada. Si un objeto estuviera en los dos buckets, se firma el privado.
create or replace function public.deck_fotos_ubicacion(p_uid uuid, p_ids uuid[])
returns table (id uuid, path text, bucket text)
language plpgsql security definer set search_path to ''
as $function$
begin
  perform public._actua_como(p_uid);
  if not public.es_agente() then raise exception 'Solo el equipo' using errcode = '42501'; end if;
  if coalesce(cardinality(p_ids), 0) > 200 then raise exception 'Como mucho 200 fotos por llamada' using errcode = '22023'; end if;
  return query
    select f.id, f.path,
           (select o.bucket_id from storage.objects o
             where o.name = f.path and o.bucket_id in ('deck', 'deck-privado')
             order by (o.bucket_id = 'deck-privado') desc limit 1)::text
      from public.deck_fotos f
     where f.id = any(p_ids);
end $function$;
revoke all on function public.deck_fotos_ubicacion(uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.deck_fotos_ubicacion(uuid, uuid[]) to service_role;

-- ── bucket debido para una subida nueva (lo usará la clase deck_foto de la edge en S4) ──────────────────────────
create or replace function public.deck_bucket_debido(p_ambito text, p_ref uuid)
returns text
language sql stable security definer set search_path to ''
as $function$
  select case
           when p_ambito = 'modelo' then 'deck'
           when p_ambito = 'proyecto' then
             case coalesce((select t.abrir from public.deck_transiciones t
                             where t.proyecto_id = p_ref and t.desde > now() - interval '15 minutes'),
                           public.deck_proyecto_abierto((select p.nombre from public.proyectos p where p.id = p_ref)))
               when true then 'deck' else 'deck-privado' end
         end;
$function$;
revoke all on function public.deck_bucket_debido(text, uuid) from public, anon, authenticated;
grant execute on function public.deck_bucket_debido(text, uuid) to service_role;
