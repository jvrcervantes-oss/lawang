CREATE OR REPLACE FUNCTION public.condicion_tramos_reemplaza(p_condicion uuid, p_tramos jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_n integer;
begin
  if exists (select 1 from public.comisiones_devengadas d where d.condicion_id = p_condicion) then
    raise exception 'Esta condición ya ha devengado comisiones: sus tramos no se cambian. Desactívala y crea otra.'
      using errcode = '23514';
  end if;
  if jsonb_typeof(p_tramos) <> 'array' or jsonb_array_length(p_tramos) = 0 then
    raise exception 'Hacen falta tramos' using errcode = '23514';
  end if;

  delete from public.condicion_tramos where condicion_id = p_condicion;

  insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo)
  select p_condicion, ord,
         t->>'disparador_tipo',
         case when (t->>'disparador_tipo') like 'pct_cobrado_%' then (t->>'umbral')::numeric end,
         (t->>'pct_tramo')::numeric
    from jsonb_array_elements(p_tramos) with ordinality as x(t, ord);

  get diagnostics v_n = row_count;
  return v_n;
end;
$function$
