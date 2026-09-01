-- Retira el modelo de tickets, ya sustituido por el hilo único de
-- mensajes_comprador + hilo_soporte (20260901140000_unificar_soporte_mensajes.sql).
--
-- A PROPÓSITO en su propia migración FINAL (hallazgo 7 de la revisión previa
-- de Datos, 1-sep-2026): la migración anterior es aditiva y deja un estado
-- intermedio funcionando; esta se aplica DESPUÉS de desplegar y verificar
-- el frontend nuevo (portal/index.html, intranet/soporte/, intranet/compradores/),
-- nunca antes ni en el mismo paso.
--
-- Antes de aplicar esta migración, repetir la comprobación (no fiarse del
-- recuento de la migración anterior, que es de otro momento):
--   select count(*) from public.tickets_comprador;
--   select count(*) from public.tickets_comprador_mensajes;
-- Y por grep en el repo, que ningún .html/.js/edge function llame ya a
-- portal_crear_ticket / portal_enviar_ticket_mensaje.
--
-- destructivo-ok: se retira el modelo de tickets a petición explícita del
-- owner ("se duplica, unifícalo"). Verificado el 1-sep-2026: 1 sola fila de
-- prueba ("TEST", del propio owner), cero clientes reales. El frontend que
-- los llamaba ya se ha reescrito para no usarlos (portal/index.html,
-- intranet/compradores/index.html) antes de aplicar esto.

drop trigger if exists trg_aviso_ticket_nuevo on public.tickets_comprador;
drop trigger if exists trg_aviso_ticket_mensaje on public.tickets_comprador_mensajes;
drop function if exists public._trg_aviso_ticket_nuevo();
drop function if exists public._trg_aviso_ticket_mensaje();
drop function if exists public.portal_crear_ticket(uuid,text,text,text);
drop function if exists public.portal_enviar_ticket_mensaje(uuid,text);
drop table if exists public.tickets_comprador_mensajes;
drop table if exists public.tickets_comprador;

-- Comprobación:
--   select tablename from pg_tables where schemaname='public' and tablename like 'tickets_comprador%';
--   -- debe devolver 0 filas.
