CREATE OR REPLACE FUNCTION public._condicion_tramos_pone(p_condicion uuid, p_tramos jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_tramos is null or jsonb_typeof(p_tramos) <> 'array' or jsonb_array_length(p_tramos) = 0 then
    raise exception 'Hacen falta tramos de pago' using errcode = '23514';
  end if;
  delete from public.condicion_tramos where condicion_id = p_condicion;
  insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo)
  select p_condicion, ord, t->>'disparador_tipo',
         case when (t->>'disparador_tipo') like 'pct_cobrado_%' then (t->>'umbral')::numeric end,
         (t->>'pct_tramo')::numeric
    from jsonb_array_elements(p_tramos) with ordinality as x(t, ord);
end $function$
