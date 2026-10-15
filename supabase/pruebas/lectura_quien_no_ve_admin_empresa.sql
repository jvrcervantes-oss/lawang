-- SOLO LECTURA (lawang-ficha, 15-oct-2026; pendiente [quien-no-ve-noelia]). Desde la agencia: python erp/sql.py lawang -f proyectos/Lawang/supabase/pruebas/lectura_quien_no_ve_admin_empresa.sql
-- ¿Qué fichas de cliente NO ve entera cada admin de empresa, y por qué?
-- La cuenta de lectura no tiene EXECUTE sobre public.cliente_visible, así que la regla va EN LÍNEA, calcada de su texto vivo
-- (20261013161331, comprobado el 15-oct contra pg_get_functiondef). Para un rol de empresa es_admin() es falso, así que quedan
-- tres ramas: (1) el dueño de la ficha es él; (2) el dueño es un usuario activo de una de sus empresas y el cliente no tiene
-- contrato ni factura en una empresa NO NULA ajena; (3) el cliente tiene un contrato en un proyecto de su empresa.
-- La 4.ª rama (manager de equipo de venta / gestor) NO está aquí: solo AÑADE visibilidad; por eso se imprime si el usuario
-- es manager de algún equipo activo (si lo es, una ficha «no visible» de aquí podría verla por esa rama).
-- Sin nombres ni datos personales: nº de cliente, id y motivo.
with u as (
  select user_id, email, rol, ambito, empresas, activo,
         exists (select 1 from public.equipos_venta ev where ev.activo and lower(ev.manager_email) = lower(usuarios.email)) as manager_equipo
    from public.usuarios where rol in ('admin_empresa', 'super_admin_empresa')
), vis as (
  select u.email, c.id, c.numero_cliente, c.propietario, (
      coalesce(c.propietario = u.email, false)
      or (c.propietario is not null and u.activo and u.ambito = 'empresa'
          and exists (select 1 from public.usuarios pr where lower(pr.email) = lower(c.propietario) and pr.activo and pr.empresas && u.empresas)
          and not exists (select 1 from public.contrato_compradores cc join public.contratos k on k.id = cc.contrato_id
                            join public.proyectos p on p.id = k.proyecto_id
                           where cc.client_id = c.id and p.empresa is not null and not coalesce(p.empresa = any (u.empresas), false))
          and not exists (select 1 from public.facturas f left join public.proyectos p on p.id = f.proyecto_id
                            left join public.empresas e on e.sociedad_clave = f.sociedad
                           where f.client_id = c.id and coalesce(p.empresa, e.clave) is not null
                             and not coalesce(coalesce(p.empresa, e.clave) = any (u.empresas), false)))
      or (u.activo and u.ambito = 'empresa' and exists (
            select 1 from public.contrato_compradores cc join public.contratos k on k.id = cc.contrato_id
              join public.proyectos p on p.id = k.proyecto_id
             where cc.client_id = c.id and p.empresa = any (u.empresas)))
    ) as ve
    from u cross join public.clients c
)
select '1·usuario' as que, u.email, u.rol, u.ambito, u.empresas::text, u.activo::text, u.manager_equipo::text as manager,
       (select count(*) from vis where vis.email = u.email and vis.ve)::text as ve, (select count(*) from public.clients)::text as total
  from u
union all
select '2·no ve', v.email, coalesce(v.numero_cliente, 'sin nº'), v.id::text,
  case
    when exists (select 1 from public.contrato_compradores cc join public.contratos k on k.id = cc.contrato_id
                   join public.proyectos p on p.id = k.proyecto_id
                  where cc.client_id = v.id and p.empresa is not null and not (p.empresa = any (u.empresas)))
      then 'contrato en OTRA empresa y ninguno en la suya (correcto por diseño)'
    when exists (select 1 from public.contrato_compradores cc join public.contratos k on k.id = cc.contrato_id
                   left join public.proyectos p on p.id = k.proyecto_id
                  where cc.client_id = v.id and p.empresa is null)
      then 'contratos en proyecto SIN empresa o sin proyecto (solo direccion general)'
    when exists (select 1 from public.facturas f left join public.proyectos p on p.id = f.proyecto_id
                   left join public.empresas e on e.sociedad_clave = f.sociedad
                  where f.client_id = v.id and coalesce(p.empresa, e.clave) = any (u.empresas))
      then 'SOLO facturas/proformas en su empresa, sin contrato (HUECO de la regla)'
    when exists (select 1 from public.facturas f left join public.proyectos p on p.id = f.proyecto_id
                   left join public.empresas e on e.sociedad_clave = f.sociedad
                  where f.client_id = v.id and coalesce(p.empresa, e.clave) is not null)
      then 'facturas en OTRA empresa (correcto por diseño)'
    when v.propietario is null then 'ficha SIN dueño y sin negocio (LAW-180)'
    when not exists (select 1 from public.usuarios pr where lower(pr.email) = lower(v.propietario)) then 'el dueño no es usuario de la intranet'
    when not exists (select 1 from public.usuarios pr where lower(pr.email) = lower(v.propietario) and pr.activo) then 'el dueño esta DESACTIVADO'
    else 'el dueño no es de su empresa (p. ej. usuario global sin empresas) y el cliente no tiene contratos'
  end, null, null, null, null
  from vis v join u on u.email = v.email
 where not v.ve and v.email = 'hello@sandalwoods.id'   -- Noelia (usuarios.nombre)
order by 1, 2, 3;
