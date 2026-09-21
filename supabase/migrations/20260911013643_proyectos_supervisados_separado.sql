-- destructivo-ok: ALTER TABLE ADD COLUMN, DROP+CREATE FUNCTION son adiciones y
-- sustituciones. El UPDATE lleva WHERE (email = ANY de 5 personas concretas,
-- pedido explicito del owner), no es masivo. Cero DELETE/TRUNCATE.

alter table public.usuarios
  add column if not exists proyectos_supervisados uuid[] not null default '{}';

comment on column public.usuarios.proyectos_supervisados is
  'Proyectos (proyectos.id) de los que este usuario es MANAGER (sales_manager/project_manager): ve y corrige todo lo que hagan sus agentes ahi. Se asigna desde la ficha de CADA proyecto en /proyectos/, nunca desde /usuarios/. Distinto de proyectos, que es en que proyectos puede CREAR contratos como agente. Vacio = no supervisa ninguno.';

create or replace function public.es_manager_de(p_proyecto_id uuid)
returns boolean
language sql stable security definer
set search_path to ''
as $$
  select case
    when public.es_admin() then true
    when p_proyecto_id is null then false
    else exists (
      select 1 from public.usuarios u
       where u.user_id = (select auth.uid()) and u.activo
         and u.rol in ('sales_manager','project_manager')
         and p_proyecto_id = any (u.proyectos_supervisados))
  end
$$;

drop function if exists public.usuario_asigna_proyecto(uuid, uuid, boolean);
create or replace function public.usuario_supervisa_proyecto(
  p_user_id uuid, p_proyecto_id uuid, p_asignar boolean
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare v_rol text;
begin
  if not (public.es_admin() and public.puede('usuarios')) then
    raise exception 'no autorizado' using errcode = '42501';
  end if;
  select rol into v_rol from public.usuarios where user_id = p_user_id;
  if v_rol is null then
    raise exception 'usuario no encontrado' using errcode = '22023';
  end if;
  if v_rol = 'super_admin' and not public.es_super_admin() then
    raise exception 'no autorizado' using errcode = '42501';
  end if;

  if p_asignar then
    update public.usuarios
       set proyectos_supervisados = (
         select array(select distinct unnest(coalesce(proyectos_supervisados, '{}'::uuid[]) || array[p_proyecto_id]))
       )
     where user_id = p_user_id;
  else
    update public.usuarios
       set proyectos_supervisados = array_remove(coalesce(proyectos_supervisados, '{}'::uuid[]), p_proyecto_id)
     where user_id = p_user_id;
  end if;
end;
$$;
revoke execute on function public.usuario_supervisa_proyecto(uuid, uuid, boolean) from public, anon;
grant execute on function public.usuario_supervisa_proyecto(uuid, uuid, boolean) to authenticated;

update public.usuarios
   set proyectos = '{}'
 where email in (
   'balianhills@gmail.com', 'gusabellan@gmail.com', 'hello@lawangproperties.com',
   'fernando.margoz@gmail.com', 'martaruiz@lawangproperties.com'
 );
;
