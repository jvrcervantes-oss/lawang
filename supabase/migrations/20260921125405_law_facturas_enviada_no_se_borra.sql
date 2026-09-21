-- destructivo-ok: drop+create de policy es el patron estandar del estudio para reemplazar una
-- policy (departamentos/datos/prompt.md permite crear/drop policy sin preguntar); no borra datos.
drop policy if exists "borrar facturas" on public.facturas;
create policy "borrar facturas" on public.facturas
  for delete using (
    coalesce(enviada, false) = false
    and (
      public.es_super_admin()
      or (public.es_admin()
          and coalesce(anulada, false) = false
          and not exists (select 1 from public.recibi_aplicaciones ra
                           where ra.factura_id = facturas.id or ra.recibi_id = facturas.id))
    )
  );;
