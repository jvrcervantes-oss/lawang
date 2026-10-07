-- REVERSION de 20261008950000_f2_inv00157_a_tamarind_rise_tepi.sql: INV00157 vuelve a CC00084 / san_dal_woods (estado medido el 7-oct-2026).
-- destructivo-ok: restituye 3 columnas y 3 espejos jsonb de UNA factura sin enviar; el trigger re-congela datos.emisor.
-- (fields.proyecto_nombre volvia a ser «Sumba Hills»: era el valor antiguo del espejo.)
do $$
declare v_id uuid; v_c uuid;
begin
  select id into v_id from public.facturas where numero='INV00157' and tipo='factura';
  select id into v_c from public.contratos where numero='CC00084';
  if v_id is null or v_c is null or exists (select 1 from public.facturas where id=v_id and (coalesce(enviada,false) or anulada)) then
    raise exception 'REVERSION INV00157: no aplicable (enviada/anulada/inexistente)'; end if;
  update public.facturas f set sociedad='san_dal_woods', contrato_id=v_c, contrato_numero='CC00084',
         datos = jsonb_set(jsonb_set(jsonb_set(f.datos,'{fields,sociedad}','"san_dal_woods"',true),'{fields,contrato_numero}','"CC00084"',true),'{fields,proyecto_nombre}','"Sumba Hills"',true)
   where f.id=v_id;
end $$;
