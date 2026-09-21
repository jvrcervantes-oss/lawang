-- destructivo-ok: DROP+ADD CONSTRAINT solo amplia el CHECK de rol (5 valores en
-- vez de 3, no borra filas); los DROP POLICY son reescritura completa de la
-- misma policy (patron ya usado en permisos_por_proyecto.sql), sustituida en
-- la misma sentencia, no retirada sin reemplazo. Cero DELETE/TRUNCATE/RLS off.
-- Revision previa Seguridad+Datos+Legal ya hecha (CEO/flujos/revision_previa.md).
-- Razonamiento completo en proyectos/Lawang/contracts/sql/permisos_agente_solo_lo_suyo_y_managers.sql

alter table public.usuarios drop constraint if exists usuarios_rol_check;
alter table public.usuarios add constraint usuarios_rol_check
  check (rol = any (array['super_admin','admin','agente','sales_manager','project_manager']));

comment on column public.usuarios.proyectos is
  'Proyectos (proyectos.id) sobre los que este usuario trabaja. Agente: crea/edita contratos y LEE obra/clientes de estos proyectos (desde el 10-sep, antes solo gobernaba escritura). sales_manager/project_manager: LEE (nunca edita) todo lo que pase en estos proyectos, de cualquier agente. admin y super_admin no tienen límite. Vacío = ninguno.';

create or replace function public.es_gestor()
returns boolean
language sql stable security definer
set search_path to ''
as $$
  select exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo
       and u.rol in ('sales_manager','project_manager')
  )
$$;
revoke execute on function public.es_gestor() from public, anon;
grant execute on function public.es_gestor() to authenticated;

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
         and p_proyecto_id = any (u.proyectos))
  end
$$;
revoke execute on function public.es_manager_de(uuid) from public, anon;
grant execute on function public.es_manager_de(uuid) to authenticated;

alter table public.clients add column if not exists propietario text;
comment on column public.clients.propietario is
  'Email de quien dio de alta la ficha (auth.email() de creado_por en contratos, NUNCA el nombre). NULL = sin autor reconstruible: NO visible a un agente, solo admin/manager.';
create index if not exists clients_propietario_idx on public.clients (propietario);

create or replace function public.cliente_visible(p_propietario text, p_client_id uuid)
returns boolean
language sql stable security definer
set search_path to ''
as $$
  select case
    when public.es_admin() then true
    when public.es_gestor() then exists (
      select 1
        from public.contrato_compradores cc
        join public.contratos c on c.id = cc.contrato_id
       where cc.client_id = p_client_id
         and public.es_manager_de(c.proyecto_id))
    else coalesce(p_propietario = (select auth.email()), false)
  end
$$;
revoke execute on function public.cliente_visible(text, uuid) from public, anon;
grant execute on function public.cliente_visible(text, uuid) to authenticated;

drop policy if exists "agentes leen clientes" on public.clients;
create policy "cada uno lo suyo, el manager lo de su proyecto, admin todo" on public.clients
  for select to authenticated
  using (es_agente() and public.cliente_visible(propietario, id));

create or replace function public.unidad_visible(p_proyecto_id uuid)
returns boolean
language sql stable security definer
set search_path to ''
as $$
  select case
    when public.es_admin() then true
    when public.es_manager_de(p_proyecto_id) then true
    when p_proyecto_id is null then false
    else exists (
      select 1 from public.usuarios u
       where u.user_id = (select auth.uid()) and u.activo
         and p_proyecto_id = any (u.proyectos))
  end
$$;
revoke execute on function public.unidad_visible(uuid) from public, anon;
grant execute on function public.unidad_visible(uuid) to authenticated;

drop policy if exists "agentes leen unidades" on public.unidades;
create policy "agentes leen unidades de sus proyectos, manager de los suyos" on public.unidades
  for select to authenticated
  using (es_agente() and public.unidad_visible(proyecto_id));

drop policy if exists "agentes leen sus contratos" on public.contratos;
create policy "agentes leen sus contratos" on public.contratos
  for select to authenticated
  using (es_agente() and (es_suyo(creado_por) or public.es_manager_de(proyecto_id)));

drop policy if exists "agentes leen sus facturas" on public.facturas;
create policy "agentes leen sus facturas" on public.facturas
  for select to authenticated
  using (es_agente() and (es_suyo(creado_por) or public.es_manager_de(proyecto_id)));

drop policy if exists "agentes leen aplicaciones de sus documentos" on public.recibi_aplicaciones;
create policy "agentes leen aplicaciones de sus documentos" on public.recibi_aplicaciones
  for select to authenticated
  using (
    (exists (select 1 from public.facturas r
              where r.id = recibi_aplicaciones.recibi_id and es_agente()
                and (es_suyo(r.creado_por) or public.es_manager_de(r.proyecto_id))))
    or
    (exists (select 1 from public.facturas f
              where f.id = recibi_aplicaciones.factura_id and es_agente()
                and (es_suyo(f.creado_por) or public.es_manager_de(f.proyecto_id))))
  );

drop policy if exists "solicitudes: cada agente lee las suyas, admin todas" on public.solicitudes_pago;
create policy "solicitudes: cada agente lee las suyas, admin todas, manager las de su proyecto" on public.solicitudes_pago
  for select to authenticated
  using (
    es_admin()
    or (creado_por = (select auth.uid()))
    or exists (select 1 from public.contratos c
                where c.id = solicitudes_pago.contrato_id
                  and public.es_manager_de(c.proyecto_id))
  );

update public.clients c
   set propietario = sub.creado_por
  from (
    select distinct on (cc.client_id) cc.client_id, ct.creado_por
      from public.contrato_compradores cc
      join public.contratos ct on ct.id = cc.contrato_id
     where ct.creado_por is not null
     order by cc.client_id, ct.created_at asc
  ) sub
 where c.id = sub.client_id
   and c.propietario is null;
;
