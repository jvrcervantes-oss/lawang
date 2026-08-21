-- destructivo-ok: DROP CONSTRAINT de un CHECK, no toca filas ni borra datos —
-- se sustituye por una versión que exime a las FAQ (12-ago): una pregunta
-- frecuente no vive "en algún sitio" (ni archivo ni enlace), así que exigirle
-- uno de los dos no tenía sentido para esta categoría nueva.
alter table public.documentos_proyecto
  drop constraint documentos_proyecto_fichero_o_enlace;

alter table public.documentos_proyecto
  add constraint documentos_proyecto_fichero_o_enlace
  check (categoria = 'faq' or ((path is not null) <> (url is not null)));;
