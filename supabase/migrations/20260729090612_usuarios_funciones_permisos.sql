-- es_agente(): de "flag todo o nada" a "lo que diga su ficha".
-- COMPATIBILIDAD DELIBERADA: si el usuario NO tiene ficha en public.usuarios
-- (p.ej. creado a mano en el dashboard), se cae al flag legacy app_metadata.
-- Si SÍ la tiene, manda `activo` — si no, desactivar a alguien no serviría de
-- nada mientras conservara el flag.
-- SECURITY DEFINER es obligatorio: sin él, consultar `usuarios` desde dentro de
-- una policy dispararía la RLS de `usuarios`, que a su vez llama a estas
-- funciones (recursión).
create or replace function public.es_agente()
returns boolean language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from public.usuarios u where u.user_id = (select auth.uid()))
      then exists (select 1 from public.usuarios u where u.user_id = (select auth.uid()) and u.activo)
    else coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'agente')::boolean, false)
  end
$$;

create or replace function public.es_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo and u.rol in ('super_admin','admin')
  )
$$;

-- ¿puede usar esta herramienta? Un admin siempre. Con ficha, manda su lista.
-- Sin ficha, permiso completo si tiene el flag legacy (mismo criterio de
-- compatibilidad que es_agente).
create or replace function public.puede(herramienta text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case
    when public.es_admin() then true
    when exists (select 1 from public.usuarios u where u.user_id = (select auth.uid()))
      then exists (select 1 from public.usuarios u
                    where u.user_id = (select auth.uid()) and u.activo
                      and herramienta = any(u.herramientas))
    else coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'agente')::boolean, false)
  end
$$;

-- ¿puede editar esta fila? El autor o un admin. Las filas sin autor registrado
-- (anteriores al 27-jul, cuando se añadió `creado_por`) quedan editables por
-- cualquier agente: nadie las "creó" a efectos de la base, y bloquearlas
-- dejaría 15 contratos vivos sin nadie que pueda tocarlos.
create or replace function public.es_suyo(autor text)
returns boolean language sql stable security definer set search_path = '' as $$
  select autor is null or autor = (select auth.email()) or public.es_admin()
$$;

-- RLS de la propia tabla: cada uno ve su ficha (la app la necesita para saber
-- qué herramientas pintar); los admins ven y gestionan todas.
create policy "cada uno lee su ficha, el admin todas" on public.usuarios
  for select to authenticated using (user_id = (select auth.uid()) or public.es_admin());
create policy "solo admin crea usuarios" on public.usuarios
  for insert to authenticated with check (public.es_admin());
create policy "solo admin edita usuarios" on public.usuarios
  for update to authenticated using (public.es_admin()) with check (public.es_admin());;
