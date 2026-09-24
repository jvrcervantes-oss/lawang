-- Ubicación del proyecto en Google Maps (24-sep-2026, owner: «poner la ubicación del
-- proyecto en proyectos, tenemos las coordenadas de google maps»).
--
-- Un solo campo de texto con lo que el equipo pegue: un enlace de Google Maps
-- (largo o corto maps.app.goo.gl) o «lat, lng». Se guarda tal cual, sin partir en
-- dos columnas numéricas: la fuente es Google Maps y el enlace es lo que se copia de
-- allí; convertirlo a coordenadas lo hace la pantalla al pintar (y el corto se
-- resuelve con /api/resolve-map.php, que ya existía para la web pública).
-- Vacío = sin ubicación: nunca se rellena con algo aproximado.
alter table public.proyectos add column if not exists ubicacion_maps text;

comment on column public.proyectos.ubicacion_maps is
  'Enlace de Google Maps o «lat, lng» del proyecto. Lo edita admin desde «Editar proyecto» en /v4/proyectos/. NULL = sin ubicación.';

-- UPDATE de `proyectos` está concedido POR COLUMNAS: sin esta línea la columna se
-- lee pero no se guarda (el GRANT manda antes que la policy). Quién puede editar
-- sigue decidiéndolo la policy de UPDATE de siempre.
grant update (ubicacion_maps) on public.proyectos to authenticated;
