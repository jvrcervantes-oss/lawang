CREATE OR REPLACE FUNCTION public.valida_suma_tramos_comision()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_condicion_id uuid := coalesce(new.condicion_id, old.condicion_id);
  v_suma numeric;
begin
  -- La condición padre ya no existe (se borró ella misma, arrastrando estos
  -- tramos por el ON DELETE CASCADE): nada que validar, no queda condición
  -- viva con un % a medias.
  if not exists (select 1 from public.condiciones_comision c where c.id = v_condicion_id) then
    return coalesce(new, old);
  end if;

  select coalesce(sum(pct_tramo), 0) into v_suma
    from public.condicion_tramos
   where condicion_id = v_condicion_id;

  if abs(v_suma - 100) > 0.01 then
    raise exception 'los tramos de la condición % suman % (deben sumar exactamente 100)',
      v_condicion_id, v_suma using errcode = '23514';
  end if;

  return coalesce(new, old);
end;
$function$
