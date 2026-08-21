-- Para poder ENSEÑAR "creado por: Javier Cervantes" en vez del email hace falta
-- que un agente pueda leer el nombre de sus compañeros. Hasta ahora cada uno
-- solo veía su propia ficha (y los admin, todas).
-- Las policies de SELECT se combinan con OR, así que basta añadir esta: no se
-- toca ni se debilita la que ya había.
-- Qué se expone: nombre, email, rol y herramientas del EQUIPO INTERNO. No es
-- dato de cliente ni PII de comprador; es el equivalente a la lista de
-- compañeros. Escribir sigue exigiendo es_admin().
create policy "el equipo se ve entre si" on public.usuarios
  for select to authenticated using (public.es_agente());;
