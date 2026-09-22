-- ════════════════════════════════════════════════════════════════════════════
-- CIERRE DE HUECO — contrato_eventos exponía los "frenos saltados" a TODO
-- agente — 21-sep-2026, hallazgo de la revisión previa de Seguridad sobre el
-- plan de S7 (encargos/20260919_lawang_v4_paridad_lanzamiento.md)
-- ════════════════════════════════════════════════════════════════════════════
-- LA POLICY VIEJA (registro_eventos.sql, 18-ago): `for select to authenticated
-- using (es_agente())` — CUALQUIER usuario activo de `public.usuarios`, agente
-- raso incluido, leía CUALQUIER fila de `contrato_eventos` de CUALQUIER
-- contrato. Eso incluye los 6 eventos que LAW-71 (super_admin_poderes.sql)
-- creó a propósito para que SOLO el super_admin los viera —
-- 'editado_estando_firmado','desbloqueado','factura_sin_bloquear',
-- 'cobro_a_factura_huerfana','cobro_a_otro_comprador','comprador_sin_ficha' —
-- y que la vista `privilegios_ejercidos` (security_invoker=true) filtra pero
-- NO protege por sí sola: hereda la RLS de la tabla de debajo, y esa RLS
-- dejaba pasar a todo el mundo. Un agente con una llamada directa al SDK veía
-- la lista entera de "quién se saltó qué freno" de toda la empresa.
--
-- QUÉ SE PRESERVA (uso legítimo ya existente, verificado en contracts/app.html
-- líneas ~5938-5948, función abrirRegistro): el modal «Registro» de un
-- contrato abierto en la app lee `contrato_eventos` filtrado por ese
-- `contrato_id` para pintar su historial normal — exactamente los 10 eventos
-- que ya vivían en el CHECK original de registro_eventos.sql y que
-- `REG_EVT` (app.html ~5911) sabe pintar: creado, editado, tipo_cambiado,
-- enviado_a_firma, firma_abierta, firma_recogida, firma_anulada,
-- firmado_del_todo, desbloqueado, traspaso. Cualquier agente que hoy puede
-- ver un contrato (política "agentes leen sus contratos" de
-- permisos_agente_solo_lo_suyo_y_managers.sql: es_suyo(creado_por) o
-- es_manager_de(proyecto_id)) sigue viendo el registro normal de ESE
-- contrato — nada de eso se toca.
--
-- QUÉ SE CIERRA: los 6 eventos de privilegio de LAW-71 pasan a ser SOLO de
-- super_admin, sin excepción — es exactamente lo que su propio nombre
-- (`privilegios_ejercidos`) y su comentario en super_admin_poderes.sql ya
-- decían que debían ser. Y además, incluso para los 10 eventos normales, un
-- agente raso ya no puede leer los de un contrato que no es suyo ni de su
-- proyecto gestionado — antes de esta migración SÍ podía, por la misma
-- policy abierta; ahora queda alineado con la restricción que
-- permisos_agente_solo_lo_suyo_y_managers.sql (10-sep-2026) ya le puso a la
-- tabla `contratos` en sí. No hay regresión: si un agente no puede ver el
-- contrato, tampoco podía depender de ver su historial.

-- destructivo-ok: DROP POLICY de una policy de SELECT que se sustituye en la
-- misma sentencia por otra más estricta (mismo patrón que el resto del repo,
-- p.ej. registro_eventos.sql). No borra filas, no afecta a escritura (esta
-- tabla nunca tuvo policy de INSERT/UPDATE/DELETE — solo escriben triggers
-- definer) y no toca RLS ni el esquema auth.
drop policy if exists "agentes leen eventos" on public.contrato_eventos;
create policy "super_admin ve todo, el resto solo eventos normales de sus contratos"
  on public.contrato_eventos
  for select to authenticated
  using (
    public.es_super_admin()
    or (
      public.es_agente()
      and evento not in (
        'editado_estando_firmado','desbloqueado','factura_sin_bloquear',
        'cobro_a_factura_huerfana','cobro_a_otro_comprador','comprador_sin_ficha'
      )
      and exists (
        select 1 from public.contratos c
         where c.id = contrato_eventos.contrato_id
           and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))
      )
    )
  );

-- ── Comprobación (la del catálogo, nunca el «ya lo mandé») ──────────────────
--   select polname, pg_get_expr(polqual, polrelid) from pg_policy
--    where polrelid = 'public.contrato_eventos'::regclass;             → 1 fila, la de arriba
-- Y la de comportamiento (transacción con ROLLBACK, SET LOCAL ROLE
-- authenticated + request.jwt.claims simulando cada usuario):
--   - agente raso, cualquier evento de OTRO contrato (con o sin evento
--     privilegiado)                                         → 0 filas
--   - agente raso, evento normal (p.ej. 'editado') de SU PROPIO contrato → ve la fila
--   - agente raso, evento privilegiado (p.ej. 'desbloqueado') de SU PROPIO
--     contrato                                               → 0 filas (sigue vetado)
--   - super_admin, cualquier contrato, cualquier evento        → ve todo
--   - lo mismo repetido contra la vista `privilegios_ejercidos`: agente raso
--     → 0 filas · super_admin → todas
