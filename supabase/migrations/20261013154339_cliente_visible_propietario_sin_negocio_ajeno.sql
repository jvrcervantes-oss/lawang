-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- KYC ENTRE EMPRESAS (13-oct-2026, Backend; medido por Seguridad en vivo ese dia). UU PDP: gravedad alta.
--   El fallo: la «rama propietario» de cliente_visible (20261008300000, `pr.empresas && me.empresas`) daba la FICHA ENTERA de un comprador
--   (pasaporte, documentos y escaneos del bucket kyc) a cualquier admin de una empresa en la que tambien estuviera el DUENO de la ficha.
--   Falla cuando el dueno es de las dos empresas (lawang y sandal_woods) y el cliente solo tiene negocio en Sandal Woods: balianhills@
--   (admin_empresa solo de lawang) veia 9 fichas de ese tipo (8 con contratos + 1 solo con facturas), 5 documents, 5 de 5 escaneos,
--   comprador_ficha con el pasaporte y cliente_guarda le dejaba escribir notas. Igual fran.mg (super_admin_empresa solo de lawang).
--   La regla del owner (B11.1/B11.2, 7-oct): lo completo de la ficha sigue la regla de los contratos; la ficha basica del directorio global
--   (compradores_lista / comprador_buscar: nombre, email, ultimos 4 del pasaporte, dueno) es de todos y NO se toca aqui.
--   El arreglo: la rama propietario exige ademas que NINGUN contrato ni factura del cliente este en una empresa fuera de me.empresas
--   (empresa_de_contrato / empresa_de_factura, las funciones vivas; sin empresa = fuera, igual que la rama exclusiva de _cliente_en_empresas).
--   El cliente sin negocio sigue visible para los admins de las empresas de su dueno (para eso nacio la rama); el compartido sigue por la rama
--   de contratos. Lo que depende de cliente_visible queda cubierto sin tocarlo: policies de clients y documents, la policy de storage
--   «agentes leen kyc» (agente_ve_kyc -> cliente_visible), comprador_ficha, cliente_guarda, documento_kyc_registra, la edge ficheros-kyc
--   (lee clients con la sesion del usuario), solicitudes de cambio, factura_guarda, hilo_soporte_estado y crm_lead_*.
--   _cliente_en_empresas: su rama exclusiva (traspasos, retirar KYC, borrar, portal) ya lo exigia; la NO exclusiva (admin_de_cliente(p) por
--   defecto, hoy sin llamador) concedia solo con _propietario_en_mis_empresas: misma condicion, para que el primer llamador no reabra la fuga.
-- destructivo-ok: solo reemplaza 2 funciones (mismo tipo de retorno); no toca datos ni tablas; acota acceso
-- REVERTIR: supabase/reversion_f2/REVERSION_kyc_entre_empresas.sql (reabre la fuga: solo con OK del owner)
-- Prueba: supabase/pruebas/f2_b3_empresas.sql seccion 1 (caso «cs2») y supabase/pruebas/traspaso_arrastra_todo.sql
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
