-- La cuarta y última de las que nacieron `TO PUBLIC` (misma razón y mismo día
-- que `policies_de_law71_a_authenticated_no_a_public`). Va aparte porque es una
-- policy de BORRADO y su condición se copia entera desde la que está viva en
-- producción, no de memoria ni del .sql del repo — que es donde se pierden los
-- matices.
--
-- Condición, sin cambiar una coma: el super admin puede borrar cualquiera
-- (LAW-71); un admin solo una NO anulada y que no tenga ningún cobro aplicado
-- ni como factura ni como recibí.
drop policy if exists "borrar facturas" on public.facturas;
create policy "borrar facturas" on public.facturas
  for delete to authenticated
  using (
    public.es_super_admin()
    or (public.es_admin()
        and coalesce(anulada, false) = false
        and not exists (
          select 1 from public.recibi_aplicaciones ra
           where ra.factura_id = facturas.id or ra.recibi_id = facturas.id))
  );;
