-- Creatividades, rediseño A (24-sep-2026): la biblioteca enseña la PORTADA de cada
-- dossier en vez de una caja gris con un icono. Un dossier no tiene PNG final (sale en
-- PDF al exportar), así que se guarda una miniatura aparte: `<id>/portada-<ts>.png`.
--
-- Mismas reglas que el resto de ficheros del bucket: ruta dentro de la carpeta de la
-- fila, congelada fuera de borrador (el trigger la vigila con las demás columnas), y un
-- comercial solo lee la de una fila aprobada o publicada, por igualdad EXACTA de ruta.
-- destructivo-ok: se reemplazan dos policies de storage por otras que añaden la portada; no se borra ningún dato
alter table public.creatividades add column portada_path text
  check (portada_path ~ '^[0-9a-f-]{36}/portada-[0-9]+\.png$');
alter table public.creatividades add constraint creatividades_portada_carpeta
  check (portada_path is null or split_part(portada_path, '/', 1) = id::text);
grant insert (portada_path), update (portada_path) on public.creatividades to authenticated;

drop policy "creatividades: leer ficheros" on storage.objects;
create policy "creatividades: leer ficheros" on storage.objects for select to authenticated
  using (bucket_id = 'creatividades' and exists (
    select 1 from public.creatividades c
     where c.id::text = (storage.foldername(name))[1]
       and (public.creatividad_puede_hacer(c.tipo)
            or (public.puede('creatividades_ver') and c.estado in ('aprobada','publicada')
                and (c.path = name or c.estado_path = name or c.portada_path = name)))));
drop policy "creatividades: subir ficheros" on storage.objects;
create policy "creatividades: subir ficheros" on storage.objects for insert to authenticated
  with check (bucket_id = 'creatividades' and exists (
    select 1 from public.creatividades c
     where c.id::text = (storage.foldername(name))[1]
       and c.estado = 'borrador' and public.creatividad_puede_hacer(c.tipo)
       and ((storage.extension(name) = 'json' and name ~ '/estado-[0-9]+\.json$')
         or (storage.extension(name) = 'png' and c.tipo = 'pieza' and name ~ '/pieza-[0-9]+\.png$')
         or (storage.extension(name) = 'png' and c.tipo = 'dossier' and name ~ '/portada-[0-9]+\.png$'))));

-- El trigger congela el contenido fuera de borrador: la portada entra en la lista.
create or replace function public._creatividades_antes()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    if old.estado <> 'borrador' and (
         new.path is distinct from old.path or new.estado_path is distinct from old.estado_path
      or new.portada_path is distinct from old.portada_path
      or new.titulo is distinct from old.titulo or new.proyecto_id is distinct from old.proyecto_id
      or new.formato is distinct from old.formato or new.arquetipo is distinct from old.arquetipo
      or new.precios_a is distinct from old.precios_a or new.tipo is distinct from old.tipo) then
      raise exception 'Solo se edita un borrador. Para cambiar esta creatividad, haz una copia.' using errcode = '23514';
    end if;
    new.tipo := old.tipo;
    new.origen := old.origen;
    new.creado_por := old.creado_por;
    new.creado_en  := old.creado_en;
    new.actualizado_por := (select auth.uid());
    new.actualizado_en  := now();
  else
    new.creado_por := coalesce((select auth.uid()), new.creado_por);
    new.creado_en  := now();
    new.actualizado_por := null; new.actualizado_en := null;
    new.aprobada_por := null; new.aprobada_en := null;
    new.enviada_por := null; new.enviada_en := null;
    new.publicada_en := null; new.archivada_en := null;
    new.lleva_render := false;
    if (select auth.uid()) is not null then new.estado := 'borrador'; new.origen := null; end if;
  end if;
  return new;
end $$;
revoke all on function public._creatividades_antes() from public, anon, authenticated;
