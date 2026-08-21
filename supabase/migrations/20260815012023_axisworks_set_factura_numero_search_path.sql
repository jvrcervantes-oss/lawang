-- `search_path` fijo: sin el, quien pueda crear objetos en un esquema que este
-- antes en el search_path del llamante podria colar su propia `nextval` o su
-- propia secuencia. No es SECURITY DEFINER, asi que el riesgo es menor, pero es
-- la unica funcion del proyecto que se quedaba sin fijarlo. Se usan rutas
-- absolutas dentro, asi que search_path='' no cambia el comportamiento.
create or replace function public.axisworks_set_factura_numero()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.numero is null then
    new.numero := 'FAC' || lpad(nextval('public.axisworks_facturas_seq')::text, 5, '0');
  end if;
  return new;
end;
$function$;;
