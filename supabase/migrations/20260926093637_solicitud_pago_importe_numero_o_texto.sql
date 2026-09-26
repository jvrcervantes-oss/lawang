-- solicitud_pago_guarda: un importe que llega como NÚMERO JSON se toma tal cual; solo el TEXTO
-- se interpreta con lw_parse_importe (que lee «1234.567» como miles, a propósito, para lo tecleado).
-- La v4 manda Number(...): con tres decimales habría salido ×1000. Parche con comprobación previa.
do $$
declare def text;
  viejo text := $v$v_importe numeric := public.lw_parse_importe(p_datos->>'importe');$v$;
  nuevo text := $n$v_importe numeric := case when jsonb_typeof(p_datos->'importe') = 'number'
                                     then (p_datos->>'importe')::numeric
                                     else public.lw_parse_importe(p_datos->>'importe') end;$n$;
begin
  def := pg_get_functiondef('public.solicitud_pago_guarda(uuid, jsonb)'::regprocedure);
  if position(viejo in def) = 0 then raise exception 'solicitud_pago_guarda no tiene la línea esperada'; end if;
  execute replace(def, viejo, nuevo);
end $$;
