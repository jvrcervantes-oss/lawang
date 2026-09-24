-- Ajuste del mismo día (24-sep-2026) a bancos_conciliar: el tipo de cambio se
-- guarda SOLO si las monedas difieren. Con la misma moneda, importe_doc distinto
-- de importe_mov es la comisión del banco (SWIFT recortada) y se lee como
-- diferencia, no como un cambio de divisa. El fichero 20260924101052 ya trae la
-- versión corregida; este deja constancia del paso aplicado en la base.
create or replace function public.bancos_conciliar(p_mov uuid, p_lineas jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare m record; l record; v_ya numeric; v_tope numeric; v_doc_ya numeric; v_mon text; v_estado text; v_otro record;
begin
  perform public._bancos_puerta();
  select * into m from public.bancos_movimientos where id = p_mov for update;
  if m.id is null then raise exception 'Movimiento no encontrado.' using errcode = 'P0002'; end if;
  if m.ignorado_en is not null then raise exception 'Este movimiento está marcado como ignorado: quítale la marca antes de conciliarlo.' using errcode = '23514'; end if;
  for l in select * from jsonb_to_recordset(p_lineas) as x(tipo text, ref_id uuid, importe_mov numeric, importe_doc numeric, naturaleza text, nota text) loop
    if l.importe_mov is null or l.importe_mov = 0 or sign(l.importe_mov) <> sign(m.importe) then
      raise exception 'Cada línea lleva el mismo signo que el movimiento (entrada + / salida −).' using errcode = '23514';
    end if;
    select coalesce(sum(importe_mov), 0) into v_ya from public.bancos_conciliacion where movimiento_id = p_mov and anulado_en is null;
    if abs(v_ya + l.importe_mov) > abs(m.importe) + 0.005 then
      raise exception 'Las líneas suman más que el movimiento.' using errcode = '23514';
    end if;
    v_tope := null; v_mon := null;
    if l.tipo = 'recibi' then
      if m.importe < 0 then raise exception 'Un recibí solo explica una ENTRADA.' using errcode = '23514'; end if;
      select total, coalesce(moneda, 'EUR') into v_tope, v_mon from public.facturas where id = l.ref_id and tipo = 'recibi' and not coalesce(anulada, false);
    elsif l.tipo = 'gasto' then
      if m.importe > 0 then raise exception 'Un gasto solo explica una SALIDA.' using errcode = '23514'; end if;
      select total - pph_retenido, moneda into v_tope, v_mon from public.gastos where id = l.ref_id and estado = 'pagado';
    elsif l.tipo = 'pph' then
      if m.importe > 0 then raise exception 'Una retención ingresada solo explica una SALIDA.' using errcode = '23514'; end if;
      select pph_retenido, moneda into v_tope, v_mon from public.gastos where id = l.ref_id and pph_retenido > 0 and pph_ingresado_el is not null and estado <> 'anulado';
    elsif l.tipo = 'comision' then
      if m.importe > 0 then raise exception 'Una comisión pagada solo explica una SALIDA.' using errcode = '23514'; end if;
      select coalesce(importe_ajustado, importe), moneda into v_tope, v_mon from public.comisiones_devengadas where id = l.ref_id and estado = 'pagada';
    elsif l.tipo = 'traspaso' then
      select * into v_otro from public.bancos_movimientos where id = l.ref_id;
      if v_otro.id is null or v_otro.cuenta_clave = m.cuenta_clave or sign(v_otro.importe) = sign(m.importe) then
        raise exception 'Un traspaso enlaza con un movimiento de SIGNO CONTRARIO en OTRA cuenta propia.' using errcode = '23514';
      end if;
      v_tope := abs(v_otro.importe); v_mon := v_otro.moneda;
    end if;
    if l.tipo in ('recibi','gasto','pph','comision','traspaso') then
      if v_tope is null then raise exception 'El documento % no existe o no está en el estado que se puede conciliar.', l.ref_id using errcode = '23514'; end if;
      select coalesce(sum(abs(coalesce(importe_doc, importe_mov))), 0) into v_doc_ya from public.bancos_conciliacion
       where tipo = l.tipo and ref_id = l.ref_id and anulado_en is null;
      -- por el lado del documento: nunca más de lo que vale (misma moneda que el documento)
      if v_doc_ya + abs(coalesce(l.importe_doc, case when v_mon = m.moneda then l.importe_mov end, 0)) > v_tope + 0.005 then
        raise exception 'Ese documento ya está conciliado del todo (o esta línea lo supera).' using errcode = '23514';
      end if;
      if v_mon <> m.moneda and l.importe_doc is null then
        raise exception 'Moneda distinta (% en el banco, % en el documento): indica el importe en la moneda del documento.', m.moneda, v_mon using errcode = '23514';
      end if;
    end if;
    insert into public.bancos_conciliacion (movimiento_id, tipo, ref_id, importe_mov, importe_doc, moneda_doc, tipo_cambio, naturaleza, nota, creado_por)
    values (p_mov, l.tipo, l.ref_id, l.importe_mov,
            coalesce(l.importe_doc, case when v_mon = m.moneda then abs(l.importe_mov) end),
            coalesce(v_mon, m.moneda),
            -- tipo de cambio SOLO si las monedas difieren; con la misma moneda, importe_doc ≠ importe_mov
            -- es la comisión del banco (SWIFT recortada) y se lee como diferencia, no como cambio
            case when v_mon is not null and v_mon <> m.moneda and l.importe_doc is not null and l.importe_doc <> 0 then round(abs(l.importe_mov) / abs(l.importe_doc), 8) end,
            case when l.tipo = 'traspaso' then coalesce(l.naturaleza, 'interno') end,
            left(l.nota, 500), (select auth.uid()));
  end loop;
  perform public._bancos_recalcula(p_mov);
  select estado into v_estado from public.bancos_movimientos where id = p_mov;
  return jsonb_build_object('estado', v_estado);
end $$;
revoke all on function public.bancos_conciliar(uuid, jsonb) from public, anon;
grant execute on function public.bancos_conciliar(uuid, jsonb) to authenticated;
