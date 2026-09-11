-- La última hermana: `documentos_proyecto` — 11-sep-2026
--
-- Acaba de pasarle lo mismo a `unidades` hace media hora: se LEÍA filtrada por
-- proyecto y se ESCRIBÍA sin filtrar, bastaba tener la herramienta. Aquí igual:
-- con `documentacion` marcada, cualquiera podía subir o editar documentación de
-- un proyecto que ni siquiera ve. Leer y escribir con distinto alcance es un
-- permiso a medias, y la mitad que falta siempre es la que escribe.
--
-- Mismo `puede_proyecto(proyecto)` que la lectura, con la misma propiedad ya
-- razonada allí: un nombre que no está en `proyectos` pasa — que es como siguen
-- funcionando los tres documentos de «Lawang (general)», comunes al equipo.
-- Borrar sigue siendo solo de super_admin, sin cambios.

alter policy "documentacion: subir" on public.documentos_proyecto
  with check (public.es_agente() and public.puede('documentacion') and public.puede_proyecto(proyecto));

alter policy "documentacion: editar" on public.documentos_proyecto
  using      (public.es_agente() and public.puede('documentacion') and public.puede_proyecto(proyecto))
  with check (public.es_agente() and public.puede('documentacion') and public.puede_proyecto(proyecto));
