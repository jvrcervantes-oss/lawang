-- Retira el modelo de tickets, ya sustituido por el hilo único de
-- mensajes_comprador + hilo_soporte (20260901140000_unificar_soporte_mensajes.sql).
--
-- A PROPÓSITO en su propia migración FINAL (hallazgo 7 de la revisión previa
-- de Datos, 1-sep-2026): la migración anterior es aditiva y deja un estado
-- intermedio funcionando; esta se aplica DESPUÉS de desplegar y verificar
-- el frontend nuevo (portal/index.html, intranet/soporte/, intranet/compradores/),
-- nunca antes ni en el mismo paso.
--
-- Re-comprobado justo antes de aplicar (no fiarse del recuento de la
-- migración anterior, que es de otro momento): tickets_comprador sigue
-- teniendo exactamente 1 fila ("TEST", del propio owner, jcervantes,
-- creada antes de desplegar el frontend nuevo) y tickets_comprador_mensajes
-- su único mensaje. Grep del repo entero (frontend + supabase/functions)
-- repetido: cero referencias a portal_crear_ticket / portal_enviar_ticket_mensaje
-- / tickets_comprador.
--
-- destructivo-ok: se retira el modelo de tickets a petición explícita del
-- owner ("se duplica, unifícalo"). Verificado: 1 sola fila de prueba,
-- cero clientes reales. El frontend que los llamaba ya está desplegado y
-- verificado en producción sin usarlos.

drop trigger if exists trg_aviso_ticket_nuevo on public.tickets_comprador;
drop trigger if exists trg_aviso_ticket_mensaje on public.tickets_comprador_mensajes;
drop function if exists public._trg_aviso_ticket_nuevo();
drop function if exists public._trg_aviso_ticket_mensaje();
drop function if exists public.portal_crear_ticket(uuid,text,text,text);
drop function if exists public.portal_enviar_ticket_mensaje(uuid,text);
drop table if exists public.tickets_comprador_mensajes;
drop table if exists public.tickets_comprador;
;
