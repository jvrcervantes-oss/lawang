-- Borrar en `contratos-firmados` no estaba permitido para NADIE: no habia
-- politica de DELETE, asi que un `remove()` desde la app no borraba y tampoco
-- daba error (Storage devuelve una lista vacia cuando RLS deniega). Eso protege
-- los PDF firmados y asi se queda.
--
-- Lo que si hace falta poder limpiar son los SNAPSHOTS de trabajo: el HTML
-- previo a la firma que vive en `pendientes/`. Una vez existe el PDF firmado ya
-- no sirve para nada, y el 17-ago-2026 habia 38 MB de ellos muertos — 28 MB de
-- contratos ya firmados y 10 MB de contratos que ya ni existen.
--
-- La politica es DELIBERADAMENTE estrecha: solo `pendientes/%`. Un PDF firmado
-- sigue sin poder borrarlo nadie desde la aplicacion, que es como debe ser: es
-- la prueba de la operacion. Misma forma que la politica de UPDATE que ya existe
-- para reescribir ese mismo snapshot al firmar en cadena.
create policy "agentes borran el snapshot pendiente"
on storage.objects for delete to authenticated
using (
  bucket_id = 'contratos-firmados'
  and name like 'pendientes/%'
  and public.es_agente()
);;
