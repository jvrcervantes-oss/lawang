-- factura_guarda v3 (26-sep-2026): el total de pantalla se acepta si difiere en COMO MUCHO una
-- unidad mínima de la moneda (1 céntimo / 1 IDR), y se guarda SIEMPRE el del servidor.
-- Por qué (capa 1, Desarrollo): el JS viejo redondeaba en coma flotante y en 1.945 de 1,7 M
-- combinaciones con impuesto salía 1 céntimo por debajo; esas facturas no se podían guardar.
-- El JS ya está corregido (totales.js, BigInt, 0 diferencias en 1,2 M), pero `totales.js` se
-- carga sin sello de versión y el CDN puede servir el viejo días: esta tolerancia cubre esa
-- ventana. Una diferencia mayor sigue rechazándose (Administración: lo que se ve es lo que se guarda).
-- Parche con comprobación previa: si la función no tiene la línea esperada, no se toca.
do $$
declare def text;
begin
  def := pg_get_functiondef('public.factura_guarda(uuid, jsonb)'::regprocedure);
  if position('if v_pantalla <> v_total then' in def) = 0 then
    raise exception 'factura_guarda no tiene la comparación esperada: no se parchea a ciegas';
  end if;
  def := replace(def, 'if v_pantalla <> v_total then',
    'if abs(v_pantalla - v_total) > power(10::numeric, -public.lw_decimales(v_moneda)) then');
  execute def;
end $$;
