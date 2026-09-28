-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
--
-- Ficheros SUBIDOS en Documentación, descargables desde el investor deck (owner, 28-sep-2026: «en documentación
-- subo el dosier de un proyecto y no aparece en el investor deck»).
--
-- Por qué no salía: investor_deck_documentos solo servía filas con `url` (enlaces de Drive). Un fichero subido
-- vive en el bucket PRIVADO `documentacion` con `path` y url null, así que ninguna casilla lo hacía aparecer.
--
-- Qué hace esto, sin sacar el fichero del bucket privado:
--   · investor_deck_documento_visible(d): UN solo predicado de «esto lo puede ver el público». Lo usan la lista y
--     la ruta, para que no diverjan (la familia de fallo de los depósitos).
--   · investor_deck_documentos: misma firma y mismas columnas. A una fila subida le da como url la edge
--     `deck-documento?id=<uuid>`; las de Drive salen igual que antes.
--   · investor_deck_documento_ruta(id): path + título, SOLO service_role (la edge). La edge firma 60 s y redirige.
--     Despublicar, marcar confidencial o cerrar el deck corta el enlace al momento: se mira en cada clic.
--
-- Qué fichero subido puede salir (revisión previa de Seguridad, 28-sep): pdf, jpg/jpeg, png, webp, docx, xlsx,
-- pptx, con ruta del servidor (proyectos/<uuid>/<uuid>.<ext>), MIME de la fila Y del objeto de storage iguales al
-- que toca a su extensión (el Content-Type lo manda quien sube) y ≤ 50 MB (el tope del bucket). Fuera: doc/xls/ppt
-- (OLE, macros), zip (opaco), dwg/dxf/csv (sin sentido para un inversor; csv con inyección de fórmulas). Esos
-- siguen pudiendo salir como enlace de Drive, como hoy.
--
-- ⚠️ El ref del proyecto va escrito en la url (como otras 4 migraciones con functions/v1): no es portable a otra
-- instancia; ahí se reescribe con su ref.

create or replace function public.investor_deck_documento_mime(p_path text) returns text
language sql immutable set search_path = '' as $$
  select case lower(substring(p_path from '\.([a-z0-9]+)$'))
    when 'pdf'  then 'application/pdf'
    when 'jpg'  then 'image/jpeg'
    when 'jpeg' then 'image/jpeg'
    when 'png'  then 'image/png'
    when 'webp' then 'image/webp'
    when 'docx' then 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    when 'xlsx' then 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    when 'pptx' then 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
  end
$$;

create or replace function public.investor_deck_documento_visible(d public.documentos_proyecto) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(d.publicado_investor_deck, false)
     and d.confidencial = false             -- cinturon y tirantes: publicado nunca gana a confidencial
     and d.categoria <> 'faq'               -- 'faq' son notas INTERNAS; la publica vive en deck_faq
     and public.deck_proyecto_abierto(d.proyecto)
     and (
       coalesce(d.url, '') <> ''            -- enlace (Drive): igual que antes
       or (
         d.path ~ '^proyectos/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|jpe?g|png|webp|docx|xlsx|pptx)$'
         and d.mime = public.investor_deck_documento_mime(d.path)
         and coalesce(d.bytes, 0) between 1 and 52428800
         and exists (select 1 from storage.objects o
                      where o.bucket_id = 'documentacion' and o.name = d.path
                        and o.metadata->>'mimetype' = public.investor_deck_documento_mime(d.path))
       )
     )
$$;

create or replace function public.investor_deck_documentos(p_proyecto text)
returns table(titulo text, descripcion text, url text, categoria text)
language sql stable security definer set search_path = 'public' as $$
  select d.titulo, d.descripcion,
         case when coalesce(d.url, '') <> '' then d.url
              else 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/deck-documento?id=' || d.id::text end,
         d.categoria
    from public.documentos_proyecto d
   where d.proyecto = p_proyecto
     and public.investor_deck_documento_visible(d)
   order by d.creado_en desc;
$$;

create or replace function public.investor_deck_documento_ruta(p_id uuid)
returns table(path text, titulo text)
language sql stable security definer set search_path = '' as $$
  select d.path, d.titulo
    from public.documentos_proyecto d
   where d.id = p_id
     and coalesce(d.url, '') = ''           -- una fila con enlace sale por su enlace, nunca por aquí
     and public.investor_deck_documento_visible(d);
$$;

revoke all on function public.investor_deck_documento_mime(text) from public, anon, authenticated;
revoke all on function public.investor_deck_documento_visible(public.documentos_proyecto) from public, anon, authenticated;
revoke all on function public.investor_deck_documento_ruta(uuid) from public, anon, authenticated;
grant execute on function public.investor_deck_documento_ruta(uuid) to service_role;
-- la lista sigue como la dejó 20260927140000_superficie_funciones_sin_llamador: anon + service_role
revoke execute on function public.investor_deck_documentos(text) from public, authenticated;
grant execute on function public.investor_deck_documentos(text) to anon, service_role;
