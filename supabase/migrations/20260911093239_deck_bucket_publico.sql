/* Bucket `deck` — el PRIMER bucket publico de los seis de Lawang, y es una
   decision del owner tomada a sabiendas (11-sep-2026): en un bucket publico
   SUBIR ES PUBLICAR. El objeto es alcanzable por URL desde ese segundo, salga o
   no listado por el RPC. Por eso `deck_fotos` no tiene columna `publicado`
   (seria decorativa) y la pantalla de la intranet lo dice con esas palabras.

   Los otros cinco (contratos-firmados, kyc, documentacion, obra, justificantes,
   modelos) siguen privados y NO se tocan: ahi viven pasaportes y contratos.

   `allowed_mime_types` solo admite WebP, y no es cosmetica:
   - WebP es obligatorio en toda web del estudio (patrones_tecnicos.md).
   - La intranet recodifica la imagen en el NAVEGADOR antes de subirla. Eso mata
     el EXIF de paso -- las coordenadas GPS de una foto de obra son la casa de un
     comprador real (Seguridad) -- y de regalo valida que los bytes son una imagen
     de verdad: lo que no decodifica no se puede recodificar. `allowed_mime_types`
     por si solo NO basta, porque valida el content-type DECLARADO por el cliente,
     no los bytes.
   Tope de 8 MB, el mismo que `obra`, que es el otro bucket de fotografia. */
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('deck', 'deck', true, 8388608, array['image/webp'])
on conflict (id) do nothing;

do $$
begin
  -- Escribir: solo admin, igual que la policy de escritura de `deck_fotos`.
  -- Leer no lleva policy: un bucket publico se sirve por el endpoint publico.
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='deck: sube admin') then
    create policy "deck: sube admin" on storage.objects
      for insert to authenticated with check (bucket_id = 'deck' and es_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='deck: borra admin') then
    create policy "deck: borra admin" on storage.objects
      for delete to authenticated using (bucket_id = 'deck' and es_admin());
  end if;
end $$;;
