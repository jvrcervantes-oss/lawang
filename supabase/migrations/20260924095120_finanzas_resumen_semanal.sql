-- AVISO SEMANAL DE FINANZAS (24-sep-2026, owner: Telegram, solo al owner).
-- La lee SOLO el servicio del estudio (panel-web, clave service_role) para el
-- mensaje de los lunes. Nada de lógica nueva del dinero: lo pendiente de una
-- factura es total − factura_aplicado(), la MISMA función que usa
-- facturas_pendiente_equipo(); los gastos, total − PPh retenido, como en
-- finanzas.js. Los HITOS del calendario (que necesitan la cascada de cobros de
-- vencimientos/logica.js) NO se recalculan aquí: el mensaje enlaza a Vencimientos.
-- Sin nombres de comprador: el texto sale hacia Telegram.
create or replace function public.finanzas_resumen_semanal(p_hoy date default current_date)
returns jsonb
language sql stable security invoker set search_path = ''
as $$
  with fac as (
    select f.numero, coalesce(f.moneda, 'EUR') moneda, f.proyecto_nombre,
           nullif(f.datos->'fields'->>'fecha_vencimiento', '')::date vence,
           f.total - public.factura_aplicado(f.id) pendiente
      from public.facturas f
     where f.tipo = 'factura' and not coalesce(f.anulada, false)
       and (f.datos->'fields'->>'fecha_vencimiento') ~ '^\d{4}-\d{2}-\d{2}'
  ), fac_viva as (
    select * from fac where pendiente > 0 and vence <= p_hoy + 7
  ), gas as (
    select coalesce(moneda, 'EUR') moneda, vence_el, total - pph_retenido al_proveedor
      from public.gastos where estado = 'pendiente' and vence_el is not null and vence_el <= p_hoy + 7
  ), rec as (
    select coalesce(moneda, 'EUR') moneda, sum(total) cobrado
      from public.facturas
     where tipo = 'recibi' and not coalesce(anulada, false)
       and coalesce(fecha_emision, created_at::date) between p_hoy - 7 and p_hoy - 1
     group by 1
  ), pph as (
    select coalesce(moneda, 'EUR') moneda, sum(pph_retenido) pendiente
      from public.gastos where estado <> 'anulado' and pph_retenido > 0 and pph_ingresado_el is null
     group by 1
  ), monedas as (
    select moneda from fac_viva union select moneda from gas union select moneda from rec union select moneda from pph
  )
  select jsonb_build_object(
    'hoy', p_hoy,
    'monedas', coalesce(jsonb_object_agg(m.moneda, jsonb_build_object(
      'cobrado_7d', coalesce((select cobrado from rec where rec.moneda = m.moneda), 0),
      'facturas_vencidas', coalesce((select jsonb_agg(jsonb_build_object('numero', numero, 'proyecto', proyecto_nombre, 'pendiente', round(pendiente), 'vence', vence) order by vence)
                                       from fac_viva where fac_viva.moneda = m.moneda and vence < p_hoy), '[]'::jsonb),
      'facturas_7d', coalesce((select jsonb_agg(jsonb_build_object('numero', numero, 'proyecto', proyecto_nombre, 'pendiente', round(pendiente), 'vence', vence) order by vence)
                                 from fac_viva where fac_viva.moneda = m.moneda and vence >= p_hoy), '[]'::jsonb),
      'gastos_vencidos', jsonb_build_object('n', (select count(*) from gas where gas.moneda = m.moneda and vence_el < p_hoy),
                                            'importe', coalesce((select round(sum(al_proveedor)) from gas where gas.moneda = m.moneda and vence_el < p_hoy), 0)),
      'gastos_7d', jsonb_build_object('n', (select count(*) from gas where gas.moneda = m.moneda and vence_el >= p_hoy),
                                      'importe', coalesce((select round(sum(al_proveedor)) from gas where gas.moneda = m.moneda and vence_el >= p_hoy), 0)),
      'pph_por_ingresar', coalesce((select round(pendiente) from pph where pph.moneda = m.moneda), 0)
    )), '{}'::jsonb)
  )
  from monedas m;
$$;
revoke execute on function public.finanzas_resumen_semanal(date) from public, anon, authenticated;
grant execute on function public.finanzas_resumen_semanal(date) to service_role;
