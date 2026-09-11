-- Las dos tablas que aún nombraban proyectos ajenos — 11-sep-2026
--
-- Cerrada la lectura de `proyectos`, quedaban dos tablas que llevan el nombre del
-- proyecto DENTRO y se leían con `es_agente()` a secas, así que seguían nombrando la
-- cartera entera a quien solo trabaja en un proyecto:
--   · `modelos_villa` (32 filas): qué modelos de villa se ofrecen en cada proyecto y
--     a qué precio de construcción. Es el catálogo comercial, con dinero.
--   · `documentos_proyecto` (16): la documentación colgada de cada proyecto.
-- Se pintan dentro de la carpeta del proyecto —que ya no aparece—, así que el
-- síntoma visible estaba resuelto; esto cierra la puerta de al lado, no la misma.
--
-- `modelos` y `tipos_vivienda` NO se tocan: son catálogo del estudio, sin proyecto
-- dentro. Comunes a propósito.
--
-- Aquí el proyecto es TEXTO, no uuid, así que el filtro es `puede_proyecto(nombre)` y
-- no `proyecto_visible(id)`. Es la misma función que ya usan las policies de
-- contratos, con una propiedad que aquí viene bien y conviene dejar dicha: un nombre
-- que no existe en `proyectos` pasa siempre. Suena laxo y es deliberado — las tres
-- filas de `documentos_proyecto` que no casan son «Lawang (general)» (Akta, SK, NPWP
-- de la sociedad), documentación común del equipo que NO cuelga de ningún proyecto.
-- Comprobado fila a fila el 11-sep antes de aplicar esto: 0 de 32 en modelos_villa y
-- 3 de 16 en documentos_proyecto, y las tres son ésas.
--
-- VERIFICADO: admin 32 modelos / 16 docs · Victor 4/14 · Andrea 5/5 · Ismael 6/3 ·
-- Yesy 0/3 — los 3 de Yesy son justamente los generales, que es la prueba de que la
-- excepción de «Lawang (general)» funciona.

alter policy "modelos: leer" on public.modelos_villa
  using (public.es_agente() and public.puede_proyecto(proyecto));

alter policy "documentacion: leer" on public.documentos_proyecto
  using (public.es_agente() and public.puede_proyecto(proyecto));
