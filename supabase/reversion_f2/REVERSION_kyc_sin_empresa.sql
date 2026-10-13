-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- VUELTA ATRAS de la migracion 20261013161331 «cliente_visible_sin_empresa_no_es_de_fuera» (14-oct-2026, Backend).
-- Deja cliente_visible y _cliente_en_empresas con el texto de 20261013154339 (lo que no tiene empresa vuelve a contar como «de fuera» para VER,
-- y la condicion vuelve a empresa_de_contrato/empresa_de_factura por fila: ~225 ms en vez de ~97 ms en clients para un admin de empresa).
-- NO reabre la fuga KYC entre empresas (esa vuelta atras es REVERSION_kyc_entre_empresas.sql, solo con OK del owner).
-- destructivo-ok: solo reemplaza 2 funciones (mismo tipo de retorno); no toca datos ni tablas

create or replace function public.cliente_visible(p_propietario text, p_client_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select public.es_admin()
      or coalesce(p_propietario = (select auth.email()), false)
      or (p_propietario is not null and exists (
            select 1 from public.usuarios me
             where me.user_id = (select auth.uid()) and me.activo and me.ambito = 'empresa'
               and me.rol in ('admin_empresa','super_admin_empresa')
               and exists (select 1 from public.usuarios pr
                            where lower(pr.email) = lower(p_propietario) and pr.activo and pr.empresas && me.empresas)
               -- 13-oct: y el cliente no tiene NADA (contrato ni factura) en una empresa que no es mia
               and not exists (select 1 from public.contrato_compradores cc
                                where cc.client_id = p_client_id
                                  and not coalesce(public.empresa_de_contrato(cc.contrato_id) = any (me.empresas), false))
               and not exists (select 1 from public.facturas f
                                where f.client_id = p_client_id
                                  and not coalesce(public.empresa_de_factura(f.id) = any (me.empresas), false))))
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

create or replace function public._cliente_en_empresas(p_client uuid, p_exclusivo boolean, p_roles text[])
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
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
              -- 13-oct: la rama del dueno compartido, solo si el cliente no tiene nada en una empresa que no es mia
              or (public._propietario_en_mis_empresas(c.propietario)
                  and not exists (select 1 from public.contrato_compradores cc
                                   where cc.client_id = c.id
                                     and not coalesce(public.empresa_de_contrato(cc.contrato_id) = any (u.empresas), false))
                  and not exists (select 1 from public.facturas f
                                   where f.client_id = c.id
                                     and not coalesce(public.empresa_de_factura(f.id) = any (u.empresas), false)))
              or exists (select 1 from public.contrato_compradores cc
                           join public.contratos k on k.id = cc.contrato_id
                           join public.proyectos pr on pr.id = k.proyecto_id
                          where cc.client_id = c.id and pr.empresa = any (u.empresas))
            end))
$function$;
