-- Revisión de código del 5-oct sobre 20261005210000 (dos hallazgos):
--  · contrato_saldo devuelve también el subtotal (sin impuesto) de cada factura: el aviso de la pantalla resta
--    el subtotal del documento que se está reescribiendo, no su total con impuesto (con PPN el «quedan X por
--    facturar» salía inflado y el aviso se callaba justo cuando el servidor iba a bloquear).
--  · _factura_tope_cadena: la no-regresión («en una edición solo bloquea si el subtotal sube») solo vale si la factura
--    sigue en la MISMA cadena. Si se mueve a un contrato de otra cadena, cuenta como alta en la cadena nueva.
create or replace function public._factura_tope_cadena(p_id uuid, p_contrato uuid, p_moneda text, p_subtotal numeric, p_tipo text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_raiz uuid; v_raiz_ant uuid; v_s record; v_ant numeric; v_tol numeric;
begin
  if p_tipo is distinct from 'factura' or p_contrato is null then return; end if;
  select coalesce(c.contrato_padre_id, c.id) into v_raiz from public.contratos c where c.id = p_contrato;
  if v_raiz is null then return; end if;
  perform pg_advisory_xact_lock(hashtextextended('factura_tope:' || v_raiz::text, 0));
  select * into v_s from public._cadena_saldo(p_contrato, p_id);
  if v_s.raiz is null or v_s.moneda is distinct from p_moneda or v_s.sin_precio or coalesce(v_s.precio, 0) <= 0 then return; end if;
  v_tol := power(10::numeric, -public.lw_decimales(p_moneda));
  if p_id is not null then
    select coalesce(nullif(f.datos->'totales'->>'subtotal', '')::numeric, f.total),
           (select coalesce(c.contrato_padre_id, c.id) from public.contratos c where c.id = f.contrato_id)
      into v_ant, v_raiz_ant
      from public.facturas f where f.id = p_id;
    if v_ant is not null and v_raiz_ant is not distinct from v_raiz and p_subtotal <= v_ant + v_tol then return; end if;
  end if;
  if v_s.facturado + p_subtotal <= v_s.precio + v_tol then return; end if;
  if public.es_super_admin() then
    perform public.registra_privilegio(p_contrato, 'factura_sobre_tope',
      jsonb_build_object('raiz', v_s.raiz_numero, 'precio', v_s.precio, 'facturado_antes', v_s.facturado, 'documento', p_subtotal));
    return;
  end if;
  raise exception 'Con este documento se facturarían % y el precio acordado de % es %. Quedan % por facturar. Corrige el importe, o el precio del contrato si cambió.',
    v_s.facturado + p_subtotal, v_s.raiz_numero, v_s.precio, greatest(v_s.precio - v_s.facturado, 0)
    using errcode = '23514';
end $$;
revoke all on function public._factura_tope_cadena(uuid, uuid, text, numeric, text) from public, anon, authenticated, service_role;

create or replace function public.contrato_saldo(p_contrato uuid)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_s record; v_f jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501';
  end if;
  if not (public.es_super_admin() or (public.es_agente() and public.puede_ver_contrato(p_contrato))) then
    raise exception 'No puedes ver este contrato' using errcode = '42501';
  end if;
  select * into v_s from public._cadena_saldo(p_contrato, null);
  if v_s.raiz is null then
    raise exception 'Ese contrato ya no existe' using errcode = 'P0002';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'numero', f.numero, 'total', f.total,
           'subtotal', coalesce(nullif(f.datos->'totales'->>'subtotal', '')::numeric, f.total),
           'cobrado', coalesce((select sum(ra.importe_aplicado) from public.recibi_aplicaciones ra
                                  join public.facturas rc on rc.id = ra.recibi_id
                                 where ra.factura_id = f.id and not coalesce(rc.anulada, false)), 0),
           'lineas', coalesce((select jsonb_agg(jsonb_build_object(
                         'descripcion', l->>'descripcion',
                         'importe', public.lw_parse_importe(l->>'importe')))
                       from jsonb_array_elements(case when jsonb_typeof(f.datos->'lineas') = 'array'
                                                      then f.datos->'lineas' else '[]'::jsonb end) l), '[]'::jsonb))
         order by f.numero), '[]'::jsonb)
    into v_f
    from public.facturas f
   where f.contrato_id = p_contrato and f.tipo = 'factura' and not coalesce(f.anulada, false);
  return jsonb_build_object(
    'cadena', v_s.raiz_numero, 'moneda', v_s.moneda, 'precio', v_s.precio, 'sin_precio', v_s.sin_precio,
    'facturado', v_s.facturado, 'cobrado', v_s.cobrado,
    'por_cobrar', v_s.total_facturas - v_s.cobrado,
    'por_facturar', case when v_s.sin_precio or coalesce(v_s.precio, 0) <= 0 then null
                         else greatest(v_s.precio - v_s.facturado, 0) end,
    'facturas', v_f);
end $$;
revoke all on function public.contrato_saldo(uuid) from public, anon;
grant execute on function public.contrato_saldo(uuid) to authenticated;
