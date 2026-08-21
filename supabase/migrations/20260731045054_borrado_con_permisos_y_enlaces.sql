create or replace function public.es_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios u
                  where u.user_id = (select auth.uid()) and u.activo
                    and u.rol = 'super_admin')
$$;

alter table public.contrato_documentos
  drop constraint if exists contrato_documentos_contrato_id_fkey;
alter table public.contrato_documentos
  add constraint contrato_documentos_contrato_id_fkey
  foreign key (contrato_id) references public.contratos(id) on delete cascade;

alter table public.contratos
  drop constraint if exists contratos_contrato_padre_id_fkey;
alter table public.contratos
  add constraint contratos_contrato_padre_id_fkey
  foreign key (contrato_padre_id) references public.contratos(id) on delete set null;

drop policy if exists "borrar contratos" on public.contratos;
create policy "borrar contratos" on public.contratos
  for delete to authenticated
  using (
    public.es_super_admin()
    or (coalesce(bloqueado, false) = false
        and public.es_agente() and public.puede('contratos')
        and creado_por is not null
        and creado_por = (select auth.email()))
  );

drop policy if exists "borrar facturas" on public.facturas;
create policy "borrar facturas" on public.facturas
  for delete to authenticated
  using (public.es_admin());

drop policy if exists "agentes gestionan documentacion" on public.documentos_proyecto;
create policy "documentacion: leer" on public.documentos_proyecto
  for select to authenticated using (public.es_agente());
create policy "documentacion: subir" on public.documentos_proyecto
  for insert to authenticated with check (public.es_agente() and public.puede('documentacion'));
create policy "documentacion: editar" on public.documentos_proyecto
  for update to authenticated
  using (public.es_agente() and public.puede('documentacion'))
  with check (public.es_agente() and public.puede('documentacion'));
create policy "documentacion: borrar" on public.documentos_proyecto
  for delete to authenticated using (public.es_super_admin());

drop policy if exists "documentacion: agentes borran" on storage.objects;
create policy "documentacion: super admin borra" on storage.objects
  for delete to authenticated
  using (bucket_id = 'documentacion' and public.es_super_admin());

alter table public.documentos_proyecto add column if not exists url text;
alter table public.documentos_proyecto alter column path drop not null;
alter table public.documentos_proyecto
  drop constraint if exists documentos_proyecto_fichero_o_enlace;
alter table public.documentos_proyecto
  add constraint documentos_proyecto_fichero_o_enlace
  check ((path is not null) <> (url is not null));

alter table public.unidades add column if not exists precio_suelo numeric;
alter table public.unidades add column if not exists precio_construccion numeric;
comment on column public.unidades.precio is
  'Precio total. Si hay desglose, debe cuadrar con precio_suelo + precio_construccion.';;
