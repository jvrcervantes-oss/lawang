-- destructivo-ok: DROP CONSTRAINT de un CHECK, no toca filas ni borra datos —
-- se sustituye por una versión que añade 'faq' a la lista permitida (12-ago,
-- petición del owner: sección de preguntas frecuentes por proyecto en
-- Documentación, para entrenar al equipo comercial).
alter table public.documentos_proyecto
  drop constraint documentos_proyecto_categoria_check;

alter table public.documentos_proyecto
  add constraint documentos_proyecto_categoria_check
  check (categoria = any (array['precios','planos','legal','comercial','tecnico','fotos','faq','otros']));;
