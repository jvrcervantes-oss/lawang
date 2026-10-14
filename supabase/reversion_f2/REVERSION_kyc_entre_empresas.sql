-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- VUELTA ATRAS de la migracion «cliente_visible_propietario_sin_negocio_ajeno» (13-oct-2026, Backend).
-- Deja cliente_visible y _cliente_en_empresas como estaban (texto literal de pg_get_functiondef, 13-oct-2026 23:40).
-- OJO: volver a esto REABRE la fuga medida por Seguridad (KYC de clientes de Sandal Woods visible para admins solo de Lawang). Solo con OK del owner.
-- destructivo-ok: solo reemplaza 2 funciones (mismo tipo de retorno); no toca datos ni tablas

CREATE OR REPLACE FUNCTION public.cliente_visible(p_propietario text, p_client_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.es_admin()
      or coalesce(p_propietario = (select auth.email()), false)
      or (p_propietario is not null and exists (
            select 1 from public.usuarios me
             where me.user_id = (select auth.uid()) and me.activo and me.ambito = 'empresa'
               and me.rol in ('admin_empresa','super_admin_empresa')
               and exists (select 1 from public.usuarios pr
                            where lower(pr.email) = lower(p_propietario) and pr.activo and pr.empresas && me.empresas)))
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
$function$;

CREATE OR REPLACE FUNCTION public._cliente_en_empresas(p_client uuid, p_exclusivo boolean, p_roles text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
      from public.usuarios u
      join public.clients c on c.id = p_client
     where u.user_id = (select auth.uid()) and u.activo and u.ambito = 'empresa'
       and u.rol = any (p_roles) and cardinality(u.empresas) > 0
       and (case when p_exclusivo then
              (exists (select 1 from public.contrato_compradores cc where cc.client_id = c.id)
               or lower(coalesce(c.propietario, '')) = lower(u.email)
               or public._propietario_en_mis_empresas(c.propietario))
              and not exists (select 1 from public.contrato_compradores cc
                                join public.contratos k on k.id = cc.contrato_id
                                left join public.proyectos pr on pr.id = k.proyecto_id
                               where cc.client_id = c.id and not coalesce(pr.empresa = any (u.empresas), false))
              and not exists (select 1 from public.facturas f
                               where f.client_id = c.id
                                 and not coalesce(public.empresa_de_factura(f.id) = any (u.empresas), false))
            else
              lower(coalesce(c.propietario, '')) = lower(u.email)
              or public._propietario_en_mis_empresas(c.propietario)
              or exists (select 1 from public.contrato_compradores cc
                           join public.contratos k on k.id = cc.contrato_id
                           join public.proyectos pr on pr.id = k.proyecto_id
                          where cc.client_id = c.id and pr.empresa = any (u.empresas))
            end))
$function$;
