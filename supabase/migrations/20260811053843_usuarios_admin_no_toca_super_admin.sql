-- destructivo-ok: reemplaza una policy de UPDATE por otra más estricta (mismo patrón que
-- el resto de este fichero: drop policy if exists + create policy). No borra filas ni tablas.
-- Aprobado por el owner (11-ago-2026, tras la auditoría de suite): un admin normal podía
-- ascenderse a super_admin o degradar a uno vía API directa, saltándose el disabled del panel.
create or replace function public.es_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios u
                  where u.user_id = (select auth.uid()) and u.activo
                    and u.rol = 'super_admin')
$$;

revoke execute on function public.es_super_admin() from public;
grant  execute on function public.es_super_admin() to authenticated, service_role;

drop policy if exists "solo admin edita usuarios" on public.usuarios;
create policy "admin edita, pero no toca una fila super_admin sin serlo" on public.usuarios
  for update to authenticated
  using   (public.es_admin() and (rol <> 'super_admin' or public.es_super_admin()))
  with check (public.es_admin() and (rol <> 'super_admin' or public.es_super_admin()));;
