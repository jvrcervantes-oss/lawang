-- destructivo-ok: DROP+CREATE de investor_deck_parcelas es mecanico, no data-destructivo.
-- Postgres no permite CREATE OR REPLACE cuando cambia el tipo de fila devuelta (OUT params);
-- se añaden 2 columnas (precio_suelo, precio_construccion) al mismo SELECT de siempre,
-- sin tocar ninguna fila de la tabla base, y se re-otorga el GRANT a continuacion.
DROP FUNCTION public.investor_deck_parcelas(text);

CREATE FUNCTION public.investor_deck_parcelas(p_proyecto text)
 RETURNS TABLE(codigo text, estado text, superficie_m2 numeric, precio numeric, precio_suelo numeric, precio_construccion numeric, cuota_reserva numeric, moneda text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select codigo, estado, superficie_m2,
         coalesce(precio, precio_suelo) as precio,
         precio_suelo,
         precio_construccion,
         cuota_reserva_investor_deck as cuota_reserva,
         moneda
    from public.unidades
   where proyecto = p_proyecto
     and publicado_investor_deck = true
   order by codigo;
$function$;

GRANT EXECUTE ON FUNCTION public.investor_deck_parcelas(text) TO anon, authenticated, service_role;
