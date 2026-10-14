CREATE OR REPLACE FUNCTION public._condicion_solapa(p_cond uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select b.id from public.condiciones_comision a
    join public.condiciones_comision b
      on b.id <> a.id
     and b.equipo_id is not distinct from a.equipo_id
     and b.proyecto_id is not distinct from a.proyecto_id
     and b.nivel = a.nivel
     and b.empresa = a.empresa
     and lower(coalesce(b.closer_email, '')) = lower(coalesce(a.closer_email, ''))
     and (b.activo or b.vigente_hasta is not null)
     and b.vigente_desde <= coalesce(a.vigente_hasta, 'infinity'::date)
     and a.vigente_desde <= coalesce(b.vigente_hasta, 'infinity'::date)
   where a.id = p_cond and (a.activo or a.vigente_hasta is not null)
   limit 1
$function$
