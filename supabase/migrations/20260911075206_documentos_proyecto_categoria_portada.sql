-- destructivo-ok: DROP CONSTRAINT de un CHECK, no toca filas ni borra datos —
-- se sustituye por una versión que añade 'portada' a la lista permitida
-- (11-sep-2026, v4/proyectos: foto de portada del proyecto, editable desde
-- "Editar proyecto"). Categoría aparte de 'fotos' a propósito: 'fotos' es la
-- galería general del proyecto (hoy vacía) y 'portada' es LA imagen que la
-- tarjeta usa como fondo — la más reciente por proyecto (datos.js). Mezclar
-- las dos habría hecho que subir una foto de galería cambiara la portada sin
-- avisar el día que 'fotos' se empiece a usar de verdad.
alter table public.documentos_proyecto
  drop constraint documentos_proyecto_categoria_check;

alter table public.documentos_proyecto
  add constraint documentos_proyecto_categoria_check
  check (categoria = any (array['precios','planos','legal','comercial','tecnico','fotos','faq','portada','otros']));
