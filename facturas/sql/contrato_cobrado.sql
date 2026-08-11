-- Fuente única de "cuánto se ha cobrado de verdad" por contrato (11-ago-2026,
-- misma reforma que recibi_aplicaciones.sql). La usan Operaciones, el portal
-- del cliente y la ficha de Unidades — antes cada uno sumaba factura+recibí a
-- su manera y podían divergir; ahora los tres llaman a esta única función.
--
-- Regla: solo el recibí es dinero cobrado. Una factura es lo que se debe.
--   · recibís CON aplicación (recibi_aplicaciones, desde el 11-ago-2026):
--     cuentan por el importe_aplicado a CADA factura, atribuido al contrato
--     de ESA factura — así un recibí que reparte pago entre dos contratos
--     (el caso real que originó esta reforma) se cuenta partido, no entero
--     contra uno solo.
--   · recibís SIN aplicación (documentos de antes de esta reforma, la
--     mayoría del histórico): siguen contando por su propio contrato_id,
--     comportamiento igual que tenían — si no, todo el histórico pasaría a
--     mostrar 0€ cobrado de golpe.
-- SECURITY DEFINER a propósito: "cobrado" es dato operativo del equipo, no
-- solo de quien creó la factura — mismo criterio que contratos_equipo() en
-- Operaciones (7-ago). No expone nada nuevo: ya se podía ver vía esa RPC.
create or replace function public.contrato_cobrado(p_contrato_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce((
      select sum(ra.importe_aplicado)
        from public.recibi_aplicaciones ra
        join public.facturas r on r.id = ra.recibi_id
        join public.facturas f on f.id = ra.factura_id
       where f.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
         and not coalesce(f.anulada, false)
    ), 0)
    +
    coalesce((
      select sum(r.total)
        from public.facturas r
       where r.tipo = 'recibi' and r.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
         and not exists (select 1 from public.recibi_aplicaciones ra where ra.recibi_id = r.id)
    ), 0)
$$;

revoke all on function public.contrato_cobrado(uuid) from public, anon;
grant execute on function public.contrato_cobrado(uuid) to authenticated;
