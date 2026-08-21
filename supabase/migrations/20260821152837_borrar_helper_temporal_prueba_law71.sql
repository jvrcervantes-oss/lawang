-- Fuera el helper de verificación. Existía solo para poder probar la RLS
-- asumiendo el rol real: la conexión del MCP es dueña de las tablas y la
-- bypasea, así que sin esto un «no salta ningún error» no distingue entre
-- policy correcta y policy ausente.
--
-- Se borra el mismo día que se crea, como los dos del 29-jul: dejarlo sería
-- dejar en producción una función que hace SET ROLE, que es justo lo que no
-- puede quedarse suelto.
drop function if exists public._prueba_law71(text, text, uuid);;
