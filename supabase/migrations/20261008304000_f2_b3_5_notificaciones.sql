-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · BLOQUE 3 · migracion 5 (7-oct-2026): NOTIFICACIONES por empresa.
--   Un administrador de empresa ve, ademas de las dirigidas a el, las notificaciones ligadas a un contrato de SUS empresas (las de solicitud_pago, solo con la herramienta «comisiones», como el admin global).
--   Las que no tienen contrato (avisos generales) siguen siendo solo del administrador global. mis_contratos_admin_empresa() se evalua una vez por consulta (initPlan), no por fila.
--   correos_enviados NO se toca: sus 357 filas tienen contrato y ya pasan por mis_contratos_visibles (empresa-aware desde 2A); se comprueba en la prueba.
--   portal_accesos: su policy mira clients (con la RLS de cliente_visible): ya queda por empresa.
-- destructivo-ok: alter policy (solo anade una rama); sin tocar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b3.sql
alter policy "cada uno ve lo suyo, el admin todo" on public.notificaciones
  using (
    (public.es_admin() and (tipo is distinct from 'solicitud_pago' or public.puede('comisiones')))
    or (destinatario is not null and destinatario = (select auth.email()))
    or (contrato_id is not null
        and contrato_id = any ((select public.mis_contratos_admin_empresa()))
        and (tipo is distinct from 'solicitud_pago' or public.puede('comisiones')))
  );
