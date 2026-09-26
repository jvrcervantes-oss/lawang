-- Factura de vencimiento atómica (26-sep-2026, owner: «bugs por funciones no atómicas» → opción 1).
-- Por qué: factura-vencimiento (cron diario) insertaba la factura y DESPUÉS marcaba el vencimiento con su
-- factura_id en otra llamada; si la marca fallaba solo lo apuntaba en el log y al día siguiente emitía OTRA
-- factura para el mismo hito. Y dos ejecuciones a la vez leían el mismo candidato sin cerrojo. Ninguna
-- restricción de la base lo impedía. Una RPC de PostgREST es UNA transacción: o factura + marca, o nada.
--
-- Revisión previa #111 (Datos), cada punto con su porqué:
--   1. `for update` sobre el vencimiento y la comprobación de factura_id ANTES del insert: una segunda ejecución
--      espera al cerrojo, ve la marca y sale con hint ya_facturado (el cron lo cuenta como «saltada»).
--   2. Comprobar antes de insertar también cuida la serie INV: `set_factura_numero` usa nextval, que no se
--      deshace; si la transacción revierte DESPUÉS del insert queda un hueco en la numeración fiscal.
--   3. SECURITY INVOKER: la llama la edge con service role; `fija_autor` sigue viendo auth.role()='service_role'
--      igual que con el insert suelto, y el resto de triggers de facturas corren exactamente como antes.
--   4. Lista blanca = las columnas que mandaba el insert suelto. contrato_id sale del VENCIMIENTO, no de p_fila:
--      la factura no puede colgar de un contrato distinto al del hito que marca.
--   5. Solo service_role: revoke de public, anon y authenticated (Supabase da EXECUTE explícito a anon).
-- Aviso anotado aparte (LAW-333): la FK factura_id → facturas es ON DELETE SET NULL; borrar la factura
-- devuelve el hito a candidato y el cron emitiría otra. Fuera del alcance de esta migración.
-- Solo añade: una función nueva; ninguna tabla ni dato se toca.

create function public.factura_vencimiento_emite(p_venc_id uuid, p_fila jsonb)
  returns table (id uuid, numero text, datos jsonb)
  language plpgsql security invoker set search_path to ''
  as $$
declare
  v_contrato uuid;
  v_factura  uuid;
  f          public.facturas;
  n          int;
begin
  select cv.contrato_id, cv.factura_id into v_contrato, v_factura
    from public.contrato_vencimientos cv where cv.id = p_venc_id for update;
  if not found then
    raise exception 'vencimiento % no existe', p_venc_id using hint = 'sin_fila';
  end if;
  if v_factura is not null then
    raise exception 'vencimiento % ya tiene factura', p_venc_id using hint = 'ya_facturado';
  end if;

  insert into public.facturas (tipo, sociedad, cliente_nombre, proyecto_nombre, contrato_numero, contrato_id,
                               total, moneda, fecha_emision, datos)
  values (p_fila->>'tipo', p_fila->>'sociedad', p_fila->>'cliente_nombre', p_fila->>'proyecto_nombre',
          p_fila->>'contrato_numero', v_contrato, (p_fila->>'total')::numeric, p_fila->>'moneda',
          (p_fila->>'fecha_emision')::date, p_fila->'datos')
  returning * into f;

  update public.contrato_vencimientos cv set factura_id = f.id where cv.id = p_venc_id;
  get diagnostics n = row_count;
  if n <> 1 then
    raise exception 'no se pudo marcar el vencimiento %', p_venc_id using hint = 'sin_fila';
  end if;

  return query select f.id, f.numero, f.datos;
end $$;

revoke all on function public.factura_vencimiento_emite(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.factura_vencimiento_emite(uuid, jsonb) to service_role;
