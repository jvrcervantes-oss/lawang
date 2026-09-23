-- Solicitudes de pago: cada uno lee solo las suyas (23-sep-2026, owner, opción A:
-- «no todos ven lo de todos, sólo lo suyo», paso 2 del plan de Comisiones).
-- Hasta hoy un manager (sales o project) leía además las solicitudes de los
-- contratos de los proyectos que supervisa (rama es_manager_de, decisión del
-- 10-sep). La pantalla ya solo enseñaba las suyas; ahora la base tampoco se
-- las da. Quedan: admin con la casilla «Pagos de Lawang», quien la creó y el
-- beneficiario.
-- Ensayado en ROLLBACK: project manager 6 -> 2, sales managers 5 -> 1, 4 -> 3,
-- 1 -> 0 (x2), super admins 7 -> 7, admins sin casilla 0 -> 0.
-- Los avisos de la campana (notificaciones) no cambian: el manager sigue
-- recibiendo el aviso con el número de la solicitud y su estado.
alter policy "solicitudes: cada agente lee las suyas, admin todas, manager la" on public.solicitudes_pago
  using ((es_admin() AND puede('comisiones'::text))
         OR (creado_por = (SELECT auth.uid() AS uid))
         OR (beneficiario_email = (SELECT auth.email() AS email)));

alter policy "solicitudes: cada agente lee las suyas, admin todas, manager la" on public.solicitudes_pago
  rename to "solicitudes: cada uno lee las suyas, admin con casilla todas";
