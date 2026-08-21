insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('justificantes', 'justificantes', false, 10485760, array['image/jpeg','image/png','image/webp','application/pdf']);

create policy "agentes suben justificantes"
  on storage.objects for insert
  with check (bucket_id = 'justificantes' and es_agente());

create policy "agentes leen justificantes"
  on storage.objects for select
  using (bucket_id = 'justificantes' and es_agente());

create policy "agentes borran justificantes"
  on storage.objects for delete
  using (bucket_id = 'justificantes' and es_agente());
;
