-- Petición del owner (12-ago-2026): sección de "Preguntas frecuentes" por
-- proyecto en Documentación, para entrenar al equipo comercial con lo que
-- repiten los clientes en vez de responder lo mismo cada vez.
--
-- Se reusa la tabla documentos_proyecto (categoria='faq', carpeta fija
-- "Preguntas frecuentes") en vez de crear una tabla nueva: una FAQ es
-- título+respuesta, y esta tabla ya resuelve "agrupar por proyecto/carpeta"
-- con el árbol que ya existe. Dos constraints había que tocar porque
-- asumían que todo lo de aquí es un documento con archivo o enlace:

alter table public.documentos_proyecto
  drop constraint documentos_proyecto_categoria_check;
alter table public.documentos_proyecto
  add constraint documentos_proyecto_categoria_check
  check (categoria = any (array['precios','planos','legal','comercial','tecnico','fotos','faq','otros']));

-- Una FAQ no vive "en algún sitio" (ni archivo ni enlace) — se exime de la
-- exigencia de tener exactamente uno de los dos.
alter table public.documentos_proyecto
  drop constraint documentos_proyecto_fichero_o_enlace;
alter table public.documentos_proyecto
  add constraint documentos_proyecto_fichero_o_enlace
  check (categoria = 'faq' or ((path is not null) <> (url is not null)));
