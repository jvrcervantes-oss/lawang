-- Tras 20260925030855 un recibi anulado deja de contar en el tope de la factura.
-- Reactivarlo (super_admin, no enviado) le devolvia sus aplicaciones sin pasar por
-- valida_recibi_aplicacion: la factura podia quedar aplicada por encima de su total
-- (aviso de Seguridad en la consulta de deploy, 25-sep-2026).
-- Se revalida el tope de cada factura que salda antes de dejarlo reactivar.
-- Parche sobre la definicion viva (la del repo no coincide): marca de codigo puro,
-- idempotente, y raise si la marca no esta.
do $$
declare
  v_def text;
  v_marca text := E'      perform public.registra_privilegio(old.contrato_id, ''factura_reactivada'',';
  v_nuevo text := E'      if old.tipo = ''recibi'' then\n'
    || E'        perform 1 from (\n'
    || E'          select ra.factura_id, sum(ra.importe_aplicado) as mio\n'
    || E'            from public.recibi_aplicaciones ra\n'
    || E'           where ra.recibi_id = old.id\n'
    || E'           group by ra.factura_id) x\n'
    || E'          join public.facturas f on f.id = x.factura_id\n'
    || E'         where public.factura_aplicado(f.id) + x.mio > f.total + 0.01;\n'
    || E'        if found then\n'
    || E'          raise exception ''Reactivar % pasaria del total de alguna factura que salda: ya tiene otro recibi aplicado'', old.numero\n'
    || E'            using errcode = ''23514'';\n'
    || E'        end if;\n'
    || E'      end if;\n';
begin
  select pg_get_functiondef('public.factura_anulada_solo_cambia_autor()'::regprocedure) into v_def;
  if position('Reactivar % pasaria del total' in v_def) > 0 then
    return;
  end if;
  if position(v_marca in v_def) = 0 then
    raise exception 'marca no encontrada en factura_anulada_solo_cambia_autor';
  end if;
  execute replace(v_def, v_marca, v_nuevo || v_marca);
end $$;
