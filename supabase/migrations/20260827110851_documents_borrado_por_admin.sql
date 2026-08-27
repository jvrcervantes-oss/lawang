-- La tabla `documents` tenía INSERT, SELECT y UPDATE, pero NINGUNA política de
-- DELETE. Con RLS activa eso significa que nadie podía borrar una fila… y sin
-- error: PostgREST devuelve éxito con cero filas afectadas cuando la RLS lo
-- bloquea. El bucket `kyc` SÍ deja borrar el fichero a cualquier agente.
--
-- O sea que un botón de «borrar documento» cableado sin esto habría borrado el
-- ARCHIVO y dejado la FILA apuntando a un fichero que ya no existe, enseñando
-- un «Abrir» que falla, y sin que nada lo avisara.
--
-- Owner, 27-ago-2026: «poder borrar documentación como pasaportes o algo si hay
-- algo mal». Se abre al mismo rol que ya puede EDITAR una ficha existente
-- —admin y super_admin, que es lo que la pantalla llama ES_ADMIN—, no a
-- cualquier agente: retirar un documento KYC no es corregir un campo.
create policy "admins borran documentos"
  on public.documents for delete
  to authenticated
  using (public.es_admin());
