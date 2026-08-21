-- 30-jul-2026: reenviar un enlace de firma devolvia 400 al subir el snapshot.
-- El bucket `contratos-firmados` tenia policies de INSERT y SELECT pero NINGUNA
-- de UPDATE, y `upload(..., {upsert:true})` sobre un objeto que ya existe hace
-- un UPDATE: el primer envio funcionaba y cualquier reenvio fallaba.
--
-- Acotada a `pendientes/%` a proposito: los PDF firmados viven en la RAIZ del
-- mismo bucket (RP00015.pdf, CC00008_manual.pdf...) y siguen SIN UPDATE, o sea
-- que un agente no puede sustituir un contrato ya firmado. Lo unico
-- sobreescribible es el borrador que se le ensena al firmante.
create policy "agentes reescriben el snapshot pendiente"
  on storage.objects for update to authenticated
  using  (bucket_id = 'contratos-firmados' and name like 'pendientes/%' and public.es_agente())
  with check (bucket_id = 'contratos-firmados' and name like 'pendientes/%' and public.es_agente());;
