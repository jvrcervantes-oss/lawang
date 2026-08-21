-- Gestión de usuarios y permisos de la suite interna.
-- Hasta ahora el único control era el flag `app_metadata.agente` (todo o nada,
-- editable solo desde el dashboard de Supabase). Esta tabla lo sustituye por
-- rol + herramientas visibles, gestionable desde /usuarios/.
create table public.usuarios (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  nombre text,
  rol text not null default 'agente' check (rol in ('super_admin','admin','agente')),
  herramientas text[] not null default '{}',
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  creado_por text default auth.email()
);
comment on table public.usuarios is
  'Usuarios de la suite interna: rol y herramientas visibles. Sin ficha aquí, el acceso cae al flag legacy app_metadata.agente (permiso completo).';

alter table public.usuarios enable row level security;

-- Alta de los usuarios que YA existen en auth.users, preservando el statu quo:
-- quien hoy tiene app_metadata.agente entra activo; quien NO lo tiene (y por
-- tanto hoy no ve nada) entra DESACTIVADO — activar a alguien es una decisión
-- del owner, no un efecto colateral de esta migración.
insert into public.usuarios (user_id, email, rol, herramientas, activo, creado_por)
select u.id, u.email,
       case when u.email = 'jvr.cervantes@gmail.com' then 'super_admin' else 'agente' end,
       array['contratos','facturas','operaciones','unidades','compradores','dossier'],
       coalesce((u.raw_app_meta_data ->> 'agente')::boolean, false),
       'migracion 29-jul-2026'
from auth.users u;

-- el super_admin ve además el panel de usuarios
update public.usuarios
   set herramientas = herramientas || array['usuarios']
 where rol = 'super_admin';;
