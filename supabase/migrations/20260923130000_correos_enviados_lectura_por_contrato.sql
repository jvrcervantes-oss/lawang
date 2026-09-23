-- ============================================================================
-- correos_enviados: cada agente lee solo los envíos de lo que puede ver
-- 23-sep-2026 — decisión de Legal del 19-sep (encargo de paridad v4):
-- «`correos_enviados` se lee entero con `es_agente()`: restringir el SELECT a
-- dueño-o-admin por contrato ANTES de que la ficha v4 lo enseñe».
-- ----------------------------------------------------------------------------
-- La policy vieja («agentes leen correos», USING es_agente()) dejaba a
-- cualquier agente activo leer los 229 envíos de toda la cartera — a quién se
-- escribió, con qué asunto y cuándo — también de compradores que no son suyos.
-- Rompía «el agente ve solo lo suyo» (project_lawang_roles_managers_11sep).
--
-- Regla nueva, la MISMA que ya gobierna los contratos (contrato_visible =
-- es_suyo(autor) OR es_manager_de(proyecto)):
--   · admin/super_admin: todo;
--   · quien lo envió: lo suyo;
--   · el resto: los envíos de un contrato que puede ver.
-- Todas las filas llevan contrato_id (229/229, comprobado el 23-sep), y los
-- cuatro lectores (contracts/app.html, intranet/compradores, intranet/facturas,
-- v4/editores.js) leen desde un contrato o factura que el usuario ya ve: no se
-- rompe ningún uso legítimo.
--
-- Probado con el rol REAL (SET ROLE authenticated + claims) en transacción con
-- ROLLBACK antes de aplicar: agente raso 229 → 13 (exactamente los de sus
-- contratos); super_admin 229 → 229. El INSERT no se toca.
-- ============================================================================

-- destructivo-ok: se sustituye una policy de LECTURA por otra más estricta, ningún dato se toca
drop policy if exists "agentes leen correos" on public.correos_enviados;

create policy "correos: leer lo propio o del contrato visible" on public.correos_enviados
  for select to authenticated
  using (
    public.es_agente() and (
      public.es_admin()
      or coalesce(enviado_por = (select auth.email()), false)
      or exists (
        select 1 from public.contratos c
         where c.id = correos_enviados.contrato_id
           and public.contrato_visible(c.creado_por, c.proyecto_id)
      )
    )
  );
