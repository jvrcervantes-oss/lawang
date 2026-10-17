-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68). La pareja del maestro NO va en esta vuelta: espera a la gemela
-- de notificaciones_datos (20261016090000 b10_l5, fila AXW-357 [b10-l5-cierre-maestro]) y entonces lleva el disparador
-- _cuenta_pruebas_corta en la tabla nueva (canon 7.zb) y el doble de demo_datos.js:856 con `id` y `leida`.
-- H7 de Experiencia (17-oct-2026, sesión lawang-mejoras-ux, tren 6): un aviso de la campana se da por leído AL PULSARLO, no al
-- abrir la campana (hoy cabecera.js llama a marcar_notificaciones_leidas() al abrir y lo da todo por visto aunque no se lea).
-- Revisión previa #429 (Seguridad y Backend, ADELANTE CON CAMBIOS); lo que pidieron está aquí punto por punto.
--
-- SOLO CONSTRUYE. Nada se borra y nada se le abre a `anon`. Lo ÚNICO nuevo expuesto: EXECUTE de `authenticated` sobre
-- notificaciones_marca_leidas(uuid[]), y su llamador con nombre es intranet/v4/assets/cabecera.js (clic en un aviso). La tabla
-- no tiene ningún permiso de API: la lee solo lw_lector, dentro de notificaciones_datos (avisos.js), y la escribe solo esa RPC.
-- ORDEN con el front: da igual. El front de antes no mira `id` ni `leida` (sigue marcando al abrir); el nuevo, si la respuesta
-- no trae `id`, se porta como el de antes.
--
-- · notificaciones_leidas: una fila por (persona, aviso) leído. Clave ajena en las dos columnas (no_destruir: ningún *_id suelto),
--   las dos en cascada: si se borra el aviso o la persona, su marca no tiene sentido. Sin UPDATE ni DELETE por la API.
-- · notificaciones_marca_leidas(p_ids): DEFINER de postgres (escribe), search_path '' y nombres cualificados. NO copia la regla de
--   visibilidad (la policy de notificaciones tiene tres ramas y ya cambió dos veces: 9-sep y 7-oct): pregunta a la policy REAL por
--   _notificaciones_visibles, DEFINER de lw_lector, que la evalúa con las claims de quien llama, como las *_datos de L5.
--   Un id que no existe y uno que no se ve hacen exactamente lo mismo (nada, sin error): la RPC no sirve para sondear ids.
--   La persona sale de uid_sesion(), nunca del navegador. Como mucho 50 ids por llamada (22023): la campana funde las copias de un
--   suceso (un admin recibe una por manager, 7-8) y manda todas las del grupo. Sin fila en usuarios (no es del equipo): nada.
--   Abuso acotado: una fila por aviso visible (la clave primaria), no mueve dinero ni permisos; sin registro aparte.
-- · notificaciones_datos: misma función de L5 (20261016063536 §6) con dos campos más por fila, `id` y `leida`. El `create or
--   replace` vuelve a INVOKER si no se repite: por eso lleva `security definer` y `search_path ''`, y el bloque final lo comprueba
--   (con authenticated sin SELECT sobre notificaciones desde L5, una INVOKER dejaría la campana a cero sin error).
--
-- PRUEBA (rol real, en rama): python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261017200000_notificaciones_leidas.sql --prueba notificaciones_leidas.sql
-- VUELTA ATRÁS: supabase/reversion_notificaciones_leidas/REVERSION.sql (devuelve el cuerpo exacto de L5 y retira la RPC; la tabla
-- con marcas dentro NO se borra ahí: eso destruye datos y para con el owner).

set local lock_timeout = '5s';

-- ── 1. La tabla ──────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.notificaciones_leidas (
  user_id         uuid not null references public.usuarios(user_id) on delete cascade,
  notificacion_id uuid not null references public.notificaciones(id) on delete cascade,
  leida_en        timestamptz not null default now(),
  primary key (user_id, notificacion_id)
);
-- la cascada desde notificaciones busca por notificacion_id (la clave primaria empieza por user_id)
create index if not exists notificaciones_leidas_aviso_idx on public.notificaciones_leidas (notificacion_id);
comment on table public.notificaciones_leidas is
  'Avisos de la campana que cada persona ha abierto (H7, 17-oct-2026). Sin permisos de API: la escribe notificaciones_marca_leidas y la lee lw_lector dentro de notificaciones_datos.';

alter table public.notificaciones_leidas enable row level security;
-- «sin grant» no basta: Supabase da ALL por defecto (pg_default_acl de supabase_admin, seguridad_2026 §7)
revoke all on table public.notificaciones_leidas from public, anon, authenticated, service_role;
grant select on table public.notificaciones_leidas to lw_lector;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'notificaciones_leidas'
                                             and policyname = 'cada uno lee sus marcas') then
    create policy "cada uno lee sus marcas" on public.notificaciones_leidas
      for select to lw_lector using (user_id = public.uid_sesion());
  end if;
end $$;

-- ── 2. ¿Puede esta sesión ver estos avisos? La responde la policy real de notificaciones ───────────────────────────────────
-- Nace INVOKER; pasa a DEFINER de lw_lector al final (si el fichero se cortara antes, lo peor es una INVOKER sin EXECUTE de nadie).
create or replace function public._notificaciones_visibles(p_ids uuid[])
returns setof uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select n.id from public.notificaciones n where n.id = any (p_ids)
$$;

-- ── 3. La RPC que marca ──────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.notificaciones_marca_leidas(p_ids uuid[])
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v_uid uuid := public.uid_sesion();
begin
  if v_uid is null then
    raise exception 'notificaciones_marca_leidas: sin sesión' using errcode = '42501';
  end if;
  if p_ids is null or cardinality(p_ids) = 0 then return; end if;
  if cardinality(p_ids) > 50 then
    raise exception 'notificaciones_marca_leidas: como mucho 50 avisos por llamada' using errcode = '22023';
  end if;
  if not exists (select 1 from public.usuarios u where u.user_id = v_uid) then return; end if;
  insert into public.notificaciones_leidas (user_id, notificacion_id)
  select distinct v_uid, v.id from public._notificaciones_visibles(p_ids) v(id)
  on conflict do nothing;
end $$;
comment on function public.notificaciones_marca_leidas(uuid[]) is
  'H7 (17-oct-2026): marca como leidos los avisos de la campana que se pulsan (todas las copias del grupo, como mucho 50). Solo los que la policy de notificaciones deja ver a quien llama; un id ajeno o inexistente no hace nada. Llamador: intranet/v4/assets/cabecera.js.';

-- ── 4. La lectura de la campana gana `id` y `leida` (cuerpo de L5 + dos campos) ───────────────────────────────────────────
create or replace function public.notificaciones_datos(p_limite int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v jsonb; n int; lim int := least(greatest(coalesce(p_limite, 30), 1), 400);
begin
  if public.uid_sesion() is null then
    raise exception 'notificaciones_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'tipo', x.tipo, 'titulo', x.titulo, 'detalle', x.detalle, 'enlace', x.enlace,
                                               'creado_en', x.creado_en, 'destinatario', x.destinatario, 'leida', x.leida) order by x.rn)
                  filter (where x.rn <= lim), '[]'::jsonb), count(*)::int
    into v, n
    from (select t.id, t.tipo, t.titulo, t.detalle, t.enlace, t.creado_en, t.destinatario,
                 exists (select 1 from public.notificaciones_leidas l
                          where l.user_id = public.uid_sesion() and l.notificacion_id = t.id) as leida,
                 row_number() over (order by t.creado_en desc, t.id desc) as rn
            from public.notificaciones t order by t.creado_en desc, t.id desc limit lim + 1) x;
  return jsonb_build_object('notificaciones', v, 'hay_mas', n > lim);
end $$;

-- ── 5. Dueños y permisos ─────────────────────────────────────────────────────────────────────────────────────────────────
-- cambiar el dueño a lw_lector exige CREATE en el esquema (lo mismo que L5: se da y se quita en el acto)
grant create on schema public to lw_lector;
alter function public._notificaciones_visibles(uuid[]) owner to lw_lector;
revoke create on schema public from lw_lector;
alter function public.notificaciones_marca_leidas(uuid[]) owner to postgres;

-- el ayudante no tiene llamador por la API: solo la RPC de arriba (postgres es miembro de lw_lector, su dueño)
revoke all on function public._notificaciones_visibles(uuid[]) from public, anon, authenticated, service_role;
revoke all on function public.notificaciones_marca_leidas(uuid[]) from public, anon, service_role;
grant execute on function public.notificaciones_marca_leidas(uuid[]) to authenticated;
-- notificaciones_datos conserva dueño (lw_lector) y permisos de L5 con el create or replace; se repiten por si acaso
revoke all on function public.notificaciones_datos(int) from public, anon, service_role;
grant execute on function public.notificaciones_datos(int) to authenticated;

alter function public._notificaciones_visibles(uuid[]) security definer;

-- ── 6. Comprobación: así tiene que quedar, o no se aplica nada ───────────────────────────────────────────────────────────
do $$
declare x record; v_mal text := '';
begin
  for x in select p.proname, p.prosecdef, p.proconfig, pg_get_userbyid(p.proowner) dueno,
                  exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0) pub,
                  exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                           where a.grantee = (select oid from pg_roles where rolname = 'anon')) anon,
                  exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                           where a.grantee = (select oid from pg_roles where rolname = 'authenticated')) auth,
                  exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                           where a.grantee = (select oid from pg_roles where rolname = 'service_role')) srv
             from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('notificaciones_datos', 'notificaciones_marca_leidas', '_notificaciones_visibles') loop
    if not x.prosecdef or not coalesce(x.proconfig @> array['search_path=""'], false) or x.pub or x.anon or x.srv then
      v_mal := v_mal || x.proname || ' (definer=' || x.prosecdef || ', config=' || coalesce(array_to_string(x.proconfig, ','), '-')
               || ', public=' || x.pub || ', anon=' || x.anon || ', service_role=' || x.srv || ') ';
    end if;
    if x.proname = '_notificaciones_visibles' and (x.dueno <> 'lw_lector' or x.auth) then
      v_mal := v_mal || '_notificaciones_visibles (dueño ' || x.dueno || ', authenticated=' || x.auth || ') ';
    elsif x.proname = 'notificaciones_datos' and (x.dueno <> 'lw_lector' or not x.auth) then
      v_mal := v_mal || 'notificaciones_datos (dueño ' || x.dueno || ', authenticated=' || x.auth || ') ';
    elsif x.proname = 'notificaciones_marca_leidas' and (x.dueno <> 'postgres' or not x.auth) then
      v_mal := v_mal || 'notificaciones_marca_leidas (dueño ' || x.dueno || ', authenticated=' || x.auth || ') ';
    end if;
  end loop;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
         and proname in ('notificaciones_datos', 'notificaciones_marca_leidas', '_notificaciones_visibles')) <> 3 then
    v_mal := v_mal || 'faltan funciones (o hay sobrecargas) ';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.notificaciones_leidas'::regclass) then
    v_mal := v_mal || 'notificaciones_leidas sin RLS ';
  end if;
  if exists (select 1 from aclexplode(coalesce((select relacl from pg_class where oid = 'public.notificaciones_leidas'::regclass),
                                               acldefault('r', (select relowner from pg_class where oid = 'public.notificaciones_leidas'::regclass)))) a
              where a.grantee = 0 or a.grantee in (select oid from pg_roles where rolname in ('anon', 'authenticated', 'service_role'))) then
    v_mal := v_mal || 'notificaciones_leidas tiene permisos de API ';
  end if;
  if not has_table_privilege('lw_lector', 'public.notificaciones_leidas', 'select') then
    v_mal := v_mal || 'lw_lector no lee notificaciones_leidas (la campana no sabría qué está leído) ';
  end if;
  if v_mal <> '' then raise exception 'notificaciones_leidas: %', v_mal; end if;
end $$;
