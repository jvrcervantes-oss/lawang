-- VOLCADO DE PRODUCCION (Supabase Lawang) del 2026-09-30: pg_get_functiondef(public.comisiones_ventas_equipo).
-- NO es una migracion: no se aplica. Referencia para construir sobre el cuerpo VIVO (encargo 20260930_lawang_equipos_venta_asistente, F1).
-- Nota: el cuerpo vivo usa finales de linea CRLF; aqui van normalizados a LF (la huella se comprueba sin \r).
-- ---- fin cabecera ----
CREATE OR REPLACE FUNCTION public.comisiones_ventas_equipo()
 RETURNS TABLE(raiz_id uuid, numero text, proyecto_nombre text, creada date, fecha_venta date, equipo_id uuid, equipo_nombre text, manager_email text, closer_email text, setter_email text, team_lead_email text, reclamacion_id uuid, reclamacion_estado text, reclamacion_solicitante text, reclamacion_motivo text, reclamacion_resolucion text, reclamacion_en timestamp with time zone, soy_manager boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with yo as (select lower(coalesce(auth.email(), '')) as e,
                     (public.es_admin() and public.puede('comisiones_reparto')) as admin),
  ventas as (
    select c.id, c.numero, c.proyecto_nombre, c.created_at::date as creada, k.fecha_venta,
           lower(k.closer_email) as closer,
           (select em.equipo_id from public.equipo_miembros em
              join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo
             where lower(em.closer_email) = lower(k.closer_email)
               and em.desde <= coalesce(k.fecha_venta, current_date)
               and (em.hasta is null or em.hasta >= coalesce(k.fecha_venta, current_date))
             order by em.created_at desc limit 1) as equipo_id
      from public.contratos c
      join public.contrato_closer k on k.contrato_id = c.id
     where c.contrato_padre_id is null
  )
  select v.id, v.numero, v.proyecto_nombre, v.creada, v.fecha_venta,
         coalesce(r.equipo_id, v.equipo_id), ev.nombre, lower(ev.manager_email),
         v.closer, st.email, tl.email,
         r.id, r.estado, r.solicitante_email, r.motivo, r.motivo_resolucion, coalesce(r.resuelto_en, r.creado_en),
         lower(ev.manager_email) = yo.e
    from ventas v
    cross join yo
    left join lateral (select * from public.reclamaciones_venta_propia r0
                        where r0.contrato_raiz_id = v.id
                        order by (r0.estado in ('pendiente', 'aprobada')) desc, r0.creado_en desc limit 1) r on true
    join public.equipos_venta ev on ev.id = coalesce(r.equipo_id, v.equipo_id)
    left join public.contrato_roles_equipo st on st.contrato_raiz_id = v.id and st.rol = 'setter'
    left join public.contrato_roles_equipo tl on tl.contrato_raiz_id = v.id and tl.rol = 'team_lead'
   where yo.e <> ''
     and (yo.admin or lower(ev.manager_email) = yo.e or v.closer = yo.e
          or st.email = yo.e or tl.email = yo.e)
   order by v.creada desc
$function$
