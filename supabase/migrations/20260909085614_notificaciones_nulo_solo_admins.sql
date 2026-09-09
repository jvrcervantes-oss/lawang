-- destructivo-ok: el unico drop es un `drop policy` que este mismo fichero
-- vuelve a crear tres lineas mas abajo (mismo patron que notificaciones.sql).
-- No toca tablas, columnas ni datos.
-- ============================================================================
-- CAMPANA: destinatario NULO = SOLO ADMINISTRADORES, de verdad — 9-sep-2026
-- ----------------------------------------------------------------------------
-- El diseño de notificaciones.sql (4-ago) lo dice por escrito: «destinatario
-- nulo = solo lo ven los administradores». Pero la policy de SELECT era
-- `es_admin() OR es_suyo(destinatario)`, y es_suyo(null) devuelve TRUE — una
-- regla de compatibilidad pensada para CONTRATOS sin autor («sin autor = de
-- todos»), correcta alli y al reves de lo documentado aqui. Resultado: todos
-- los avisos con destinatario nulo los veia el equipo entero desde el 4-ago.
--
-- Cazado el 9-sep con la prueba de aislamiento de Solicitudes de pago (un
-- agente B veia en su campana el aviso de alta de la solicitud de A, que va
-- con destinatario nulo hacia los admins). Se corrige EN LA POLICY de esta
-- tabla, no en es_suyo(): contratos depende de es_suyo(null)=true a proposito
-- y cambiar la funcion romperia aquello para arreglar esto.
drop policy if exists "cada uno ve lo suyo, el admin todo" on public.notificaciones;
create policy "cada uno ve lo suyo, el admin todo"
  on public.notificaciones for select
  using (public.es_admin()
         or (destinatario is not null and destinatario = (select auth.email())));
