-- AXW-66 S1 (28-sep-2026, Datos; encargo encargos/20260928_lawang_deck_fotos_privadas.md, revisión previa #139).
-- Bucket PRIVADO hermano de `deck`: aquí viven las fotos de proyectos SIN deck abierto y los objetos sin fila en
-- deck_fotos. Mismos límites que `deck` (WebP, 8 MB) para que mover entre los dos nunca choque con un límite.
-- Sin políticas en storage.objects: solo el service role (edge `ficheros`) lee, mueve y firma. El navegador nunca
-- lee de aquí directamente; recibe una URL firmada que da el servidor.
-- Solo añade: `on conflict do nothing` (si ya existiera, no se toca).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('deck-privado', 'deck-privado', false, 8388608, array['image/webp'])
on conflict (id) do nothing;
