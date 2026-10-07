-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · paso 2A · migracion 5/6 (7-oct-2026): CLIENTES (cliente_visible) + KYC de storage (agente_ve_kyc -> cliente_visible) + documentos de cliente (policy de documents).
--   Rol de empresa = los clientes con algun contrato en un proyecto de SUS empresas. Un cliente con contratos en las dos empresas lo ven los dos (su ficha);
--   cada uno solo SUS contratos (migracion 3). Cliente sin contratos o con contratos sin proyecto: solo global (nace cerrado).
--   Lo que es del propio agente (propietario = el) no cambia. Rama de manager/equipo: ademas la empresa del contrato dentro del alcance (lista vacia = hoy).
-- destructivo-ok: create or replace de una funcion; sin DDL que destruya datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_2a.sql
create or replace function public.cliente_visible(p_propietario text, p_client_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_admin()
      or coalesce(p_propietario = (select auth.email()), false)
      or exists (
            select 1
              from public.usuarios u
              join public.contrato_compradores cc on cc.client_id = p_client_id
              join public.contratos c on c.id = cc.contrato_id
              join public.proyectos pr on pr.id = c.proyecto_id
             where u.user_id = (select auth.uid()) and u.activo
               and u.ambito = 'empresa' and u.rol in ('admin_empresa','super_admin_empresa')
               and pr.empresa = any (u.empresas))
      or ((public.es_gestor()
           or exists (select 1 from public.equipos_venta ev
                       where ev.activo and lower(ev.manager_email) = lower(coalesce((select auth.email()), ''))))
          and exists (
            select 1
              from public.contrato_compradores cc
              join public.contratos c on c.id = cc.contrato_id
              left join public.proyectos pr on pr.id = c.proyecto_id
             where cc.client_id = p_client_id
               and (public.es_manager_de(c.proyecto_id) or public._sm_ve_venta(c.id))
               and public._ve_empresa(pr.empresa)));
$$;
