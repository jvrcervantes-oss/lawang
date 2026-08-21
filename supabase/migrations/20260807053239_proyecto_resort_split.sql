-- 7-ago-2026: "Bonian Village by Balian Hills" vuelve a ser dos datos
-- separados (petición del cliente, contratos punto 9). proyectos.nombre
-- pasa a ser solo la parte corta; el resort se guarda aparte. Las 3 tablas
-- que enlazan por texto contra el nombre del proyecto (unidades,
-- documentos_proyecto, modelos_villa) se acortan igual para seguir
-- enlazando con el mismo proyecto. destructivo-ok: son UPDATE de texto con
-- WHERE explícito, ningún DROP ni borrado de filas.

alter table proyectos add column resort text;

update proyectos
  set resort = split_part(nombre, ' by ', 2), nombre = split_part(nombre, ' by ', 1)
  where nombre like '% by %';

update unidades set proyecto = split_part(proyecto, ' by ', 1) where proyecto like '% by %';
update documentos_proyecto set proyecto = split_part(proyecto, ' by ', 1) where proyecto like '% by %';
update modelos_villa set proyecto = split_part(proyecto, ' by ', 1) where proyecto like '% by %';;
