-- destructivo-ok: se retiran adenda_firmada_en (1 fila, fecha de relleno 2020-01-01) y el nombre escrito a mano (duplicaba usuarios.nombre); el manager queda enlazado por usuario antes de soltar el texto.
-- Trazabilidad GHL — 23-sep-2026, owner:
--  · «El sales manager debería ser un desplegable de los ya creados»: la cuenta apunta a
--    public.usuarios (rol sales_manager). El nombre ya NO se guarda aquí: lo manda la ficha
--    del usuario (una sola fuente — si se renombra, la trazabilidad lo sigue sola).
--  · «Lo de la adenda quítalo, no hace falta»: decisión del owner contra la recomendación de
--    Legal (revisión previa #49), tomada a sabiendas. Se retira el CHECK, la columna y el
--    parámetro. Queda anotado en contexto/pendientes.md (LAW-287).

alter table public.traza_cuentas add column if not exists manager_id uuid references public.usuarios(user_id);
update public.traza_cuentas c set manager_id = u.user_id
  from public.usuarios u
 where c.manager_id is null and u.rol = 'sales_manager' and lower(trim(u.nombre)) = lower(trim(c.nombre));
do $$ begin
  if exists (select 1 from public.traza_cuentas where manager_id is null) then
    raise exception 'Hay cuentas de trazabilidad sin sales manager enlazable por nombre';
  end if;
end $$;
alter table public.traza_cuentas alter column manager_id set not null;
alter table public.traza_cuentas drop constraint if exists traza_activo_exige_adenda;
alter table public.traza_cuentas drop column if exists adenda_firmada_en;
alter table public.traza_cuentas drop column if exists nombre;

drop function if exists public.traza_cuenta_alta(text,text,text,text,uuid);
drop function if exists public.traza_cuenta_estado(uuid,boolean,date);
drop function if exists public.traza_cuentas_listar();
drop function if exists public.traza_cuentas_para_sync(uuid);

-- El desplegable: sales managers activos de la intranet.
create or replace function public.traza_managers()
returns table(user_id uuid, nombre text, email text)
language plpgsql stable security definer set search_path to '' as $$
begin
  if not public.es_super_admin() then raise exception 'sin permiso'; end if;
  return query select u.user_id, u.nombre, u.email from public.usuarios u
                where u.rol = 'sales_manager' and u.activo order by u.nombre;
end $$;

create or replace function public.traza_cuenta_alta(
  p_manager uuid, p_location_id text, p_etiqueta text, p_token text, p_creado_por uuid)
returns uuid language plpgsql security definer set search_path to '' as $$
declare v_id uuid := gen_random_uuid(); v_sec uuid;
begin
  if not exists (select 1 from public.usuarios where user_id = p_manager and rol = 'sales_manager' and activo) then
    raise exception 'Elige un sales manager de la lista';
  end if;
  if coalesce(trim(p_location_id),'') = '' or coalesce(trim(p_etiqueta),'') = ''
     or coalesce(p_token,'') !~ '^pit-' then
    raise exception 'datos incompletos';
  end if;
  v_sec := vault.create_secret(p_token, 'ghl_traza_' || v_id::text, 'Token GHL (solo lectura) de trazabilidad');
  insert into public.traza_cuentas(id, manager_id, location_id, etiqueta, secreto_id, creado_por)
  values (v_id, p_manager, trim(p_location_id), trim(p_etiqueta), v_sec, p_creado_por);
  return v_id;
end $$;

create or replace function public.traza_cuentas_para_sync(p_solo uuid default null)
returns table(id uuid, nombre text, location_id text, etiqueta text, token text)
language sql security definer set search_path to '' as $$
  select c.id, u.nombre, c.location_id, c.etiqueta, s.decrypted_secret
    from public.traza_cuentas c
    join public.usuarios u on u.user_id = c.manager_id
    join vault.decrypted_secrets s on s.id = c.secreto_id
   where (p_solo is null and c.activo) or c.id = p_solo;
$$;

create or replace function public.traza_cuentas_listar()
returns table(id uuid, manager_id uuid, nombre text, email text, location_id text, etiqueta text,
              activo boolean, ultima_sync timestamptz, ultimo_resultado jsonb)
language plpgsql stable security definer set search_path to '' as $$
begin
  if not public.es_super_admin() then raise exception 'sin permiso'; end if;
  return query select c.id, c.manager_id, u.nombre, u.email, c.location_id, c.etiqueta, c.activo,
                      c.ultima_sync, c.ultimo_resultado
                 from public.traza_cuentas c join public.usuarios u on u.user_id = c.manager_id
                order by c.creado_en;
end $$;

create or replace function public.traza_cuenta_estado(p_id uuid, p_activo boolean)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not public.es_super_admin() then raise exception 'sin permiso'; end if;
  update public.traza_cuentas set activo = p_activo where id = p_id;
  if not found then raise exception 'cuenta no existe'; end if;
  if not p_activo then delete from public.traza_coincidencias where cuenta_id = p_id; end if;
end $$;

create or replace function public.traza_coincidencias_listar()
returns table(huella text, tipos text[], n_funnels integer, primera_alta timestamptz, apariciones jsonb)
language plpgsql stable security definer set search_path to '' as $$
begin
  if not public.es_super_admin() then raise exception 'sin permiso'; end if;
  return query
  with ap as (
    select distinct on (t.huella, t.origen, t.cuenta_id, t.ref_id)
           t.huella, t.tipo, t.origen, t.cuenta_id, t.ref_id, t.fuente, t.alta,
           case t.origen when 'lawang' then 'Lawang · lead' when 'comprador' then 'Lawang · comprador'
                else u.nombre end as funnel,
           coalesce(l.name, k.full_name) as nombre, l.project as proyecto
      from public.traza_coincidencias t
      left join public.traza_cuentas c on c.id = t.cuenta_id
      left join public.usuarios u on u.user_id = c.manager_id
      left join public.leads   l on t.origen = 'lawang'    and l.id::text = t.ref_id
      left join public.clients k on t.origen = 'comprador' and k.id::text = t.ref_id
     order by t.huella, t.origen, t.cuenta_id, t.ref_id, t.alta
  )
  select ap.huella,
         array_agg(distinct ap.tipo),
         count(distinct coalesce(ap.cuenta_id::text, 'lawang'))::int,
         min(ap.alta),
         jsonb_agg(jsonb_build_object(
           'funnel', ap.funnel, 'origen', ap.origen, 'ref_id', ap.ref_id,
           'fuente', ap.fuente, 'alta', ap.alta,
           'nombre', ap.nombre, 'proyecto', ap.proyecto) order by ap.alta nulls last)
    from ap
   group by ap.huella
  having count(distinct coalesce(ap.cuenta_id::text, 'lawang')) >= 2
   order by min(ap.alta) desc nulls last;
end $$;

revoke execute on function public.traza_cuenta_alta(uuid,text,text,text,uuid),
                           public.traza_cuentas_para_sync(uuid)
  from public, anon, authenticated;
grant execute on function public.traza_cuenta_alta(uuid,text,text,text,uuid),
                          public.traza_cuentas_para_sync(uuid)
  to service_role;
revoke execute on function public.traza_managers(), public.traza_cuentas_listar(),
                           public.traza_cuenta_estado(uuid,boolean), public.traza_coincidencias_listar()
  from public, anon;
grant execute on function public.traza_managers(), public.traza_cuentas_listar(),
                          public.traza_cuenta_estado(uuid,boolean), public.traza_coincidencias_listar()
  to authenticated;
