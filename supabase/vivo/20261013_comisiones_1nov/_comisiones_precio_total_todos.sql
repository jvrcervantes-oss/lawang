CREATE OR REPLACE FUNCTION public._comisiones_precio_total_todos(p_raiz uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$

  select coalesce(sum(x.precio_total), 0)

    from public.contratos x

   where (x.id = p_raiz or x.contrato_padre_id = p_raiz)

     and not (x.contrato_padre_id is not null and x.tipo like 'carta_reserva%');

$function$
