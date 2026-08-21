create policy "agentes borran aplicaciones de su propio recibi sin anular"
  on public.recibi_aplicaciones for delete
  using (
    exists (select 1 from public.facturas r where r.id = recibi_id
              and r.anulada = false and public.es_agente() and public.puede('facturas') and public.es_suyo(r.creado_por))
  );
;
