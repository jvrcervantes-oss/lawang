-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- KYC ENTRE EMPRESAS, 2a pasada (14-oct-2026, Backend; hallazgos del revisor sobre 20261013154339).
--   1) Lo que NO tiene empresa no cuenta como «de fuera» para VER la ficha (decision del CEO por defecto, reversible: REVERTIR abajo).
--      En la rama propietario de cliente_visible y en la rama NO exclusiva de _cliente_en_empresas, la condicion pasa a ser «ningun contrato
--      ni factura en una empresa NO NULA fuera de me.empresas». La rama EXCLUSIVA de _cliente_en_empresas (traspasar, borrar, retirar KYC)
--      NO se toca: ahi lo que no tiene empresa sigue bloqueando.
--      Medido el 14-oct en transaccion (conjuntos de fichas que ve cada admin_empresa/super_admin_empresa, original pre-13-oct = A,
--      20261013154339 = B, esta = C): B = C para los 4 (balianhills y fran.mg 128, hello@sandalwoods y p@pabloglobal 182) y C esta dentro
--      de A (137 / 137 / 182 / 182): no expone nada que no se viera antes del 13-oct. Lo que deja de ver cada uno frente a A: balianhills 9 y
--      fran.mg 9, todas «de otra empresa»; «sin empresa» 0 para los 4. Hoy el cambio no mueve ninguna ficha real: los 2 contratos sin empresa
--      con comprador (CR00058, CH00001, sin proyecto) son de clientes que ademas tienen contratos en Lawang Y en Sandal Woods, asi que los
--      admins solo de Lawang los siguen sin ver por la parte de Sandal Woods y los de las dos los ven por la rama de contratos; facturas
--      sin empresa: 0. Cubre el caso futuro (cliente con solo un contrato o factura sin empresa) y lo fija la prueba «cse» de f2_b3 seccion 1.
--   2) Rendimiento: la condicion va con joins a proyectos y empresas (empresa_de_contrato es inner join a proyectos; empresa_de_factura es
--      coalesce(empresa del proyecto, empresa de la sociedad), misma semantica aqui), no con empresa_de_contrato/empresa_de_factura por fila.
--      select count(*) from clients como balianhills@ (mejor de 7, transaccion con rollback): 20261013154339 224-239 ms; con una funcion
--      auxiliar (_cliente_sin_negocio_fuera, sql con search_path vacio: no se puede alinear, una llamada por fila) 202-206 ms; en linea 95-98 ms.
--      Por eso NO hay funcion auxiliar: la condicion va EN LINEA en las dos funciones con el MISMO texto (solo cambian los nombres: p_client_id
--      / me.empresas en cliente_visible, c.id / u.empresas en _cliente_en_empresas). Si se toca una, se toca la otra; la prueba «cse» de
--      f2_b3 seccion 1 compara las dos para el mismo cliente y el mismo usuario.
-- ORDEN DE ATERRIZAJE: esta copia (1013-2332-kyc-entre-empresas) fija en f2_b3 expectativas de traspaso que dependen de las migraciones
--   20261013150447 (traspaso_receptor_ve_lo_que_recibe) y 20261013150901 (traspaso_solo_lo_del_cliente), cuyos ficheros viven en la copia
--   1013-2205-traspaso-arrastra: esa copia aterriza ANTES o a la vez que esta (las dos migraciones ya estan aplicadas en Lawang).
-- destructivo-ok: solo reemplaza 2 funciones (mismo tipo de retorno); no toca datos ni tablas
-- REVERTIR: supabase/reversion_f2/REVERSION_kyc_sin_empresa.sql (vuelve al texto de 20261013154339)
-- Prueba: supabase/pruebas/f2_b3_empresas.sql seccion 1 (casos «cs2», «csf» y «cse»)
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
               -- 14-oct: y el cliente no tiene NADA (contrato ni factura) en una empresa NO NULA que no es mia (mismo texto en _cliente_en_empresas)
               and not exists (select 1 from public.contrato_compradores cc
                                 join public.contratos k on k.id = cc.contrato_id
                                 join public.proyectos pr on pr.id = k.proyecto_id
                                where cc.client_id = p_client_id and pr.empresa is not null
                                  and not coalesce(pr.empresa = any (me.empresas), false))
               and not exists (select 1 from public.facturas f
                                 left join public.proyectos pr on pr.id = f.proyecto_id
                                 left join public.empresas e on e.sociedad_clave = f.sociedad
                                where f.client_id = p_client_id and coalesce(pr.empresa, e.clave) is not null
                                  and not coalesce(coalesce(pr.empresa, e.clave) = any (me.empresas), false))))
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
              -- 14-oct: la rama del dueno compartido, solo si el cliente no tiene nada en una empresa NO NULA que no es mia (mismo texto en cliente_visible)
              or (public._propietario_en_mis_empresas(c.propietario)
                  and not exists (select 1 from public.contrato_compradores cc
                                    join public.contratos k on k.id = cc.contrato_id
                                    join public.proyectos pr on pr.id = k.proyecto_id
                                   where cc.client_id = c.id and pr.empresa is not null
                                     and not coalesce(pr.empresa = any (u.empresas), false))
                  and not exists (select 1 from public.facturas f
                                    left join public.proyectos pr on pr.id = f.proyecto_id
                                    left join public.empresas e on e.sociedad_clave = f.sociedad
                                   where f.client_id = c.id and coalesce(pr.empresa, e.clave) is not null
                                     and not coalesce(coalesce(pr.empresa, e.clave) = any (u.empresas), false)))
              or exists (select 1 from public.contrato_compradores cc
                           join public.contratos k on k.id = cc.contrato_id
                           join public.proyectos pr on pr.id = k.proyecto_id
                          where cc.client_id = c.id and pr.empresa = any (u.empresas))
            end))
$function$;
