-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68). Permisos e indices propios de las tablas de Lawang.
-- PERMISOS TECNICOS E INDICES DE CONTRATOS Y FACTURAS (14-oct-2026, Backend). Bloque E1 + E3 del plan «arreglos seguros y
--   reversibles de Contratos y Facturas» (revision previa de Backend #337 y de Seguridad #338, plan cerrado). E2 queda FUERA (LAW-616).
-- E1 · Dos funciones de TRIGGER se podian llamar desde fuera (aviso de Supabase): authenticated tenia EXECUTE. Un trigger no necesita
--   ese permiso para dispararse (PostgreSQL no lo mira al disparar), asi que se revoca a public, anon y authenticated; service_role y el
--   dueno lo conservan. Medido el 14-oct (solo lectura): antes anon=no, authenticated=si, service_role=si; cada una con 1 trigger.
--     _documents_kyc_firmado()                 _trg_contrato_bloqueado_aviso_manager()
-- E3 · Indices en las claves foraneas sin indice (aviso de Supabase). Tablas pequenas medidas el 14-oct: facturas 541 filas,
--   notificaciones 2.910, solicitudes_pago 18, correos_cola 8, reclamos_pago casi vacia. CREATE INDEX normal (dentro de la transaccion
--   de la migracion no cabe CONCURRENTLY) con lock_timeout: si una tabla esta ocupada, falla limpio a los 5 s y no se aplica nada.
-- LO QUE NO HACE: no toca datos ni cuerpos de funciones.
-- REVERTIR: supabase/reversion_permisos_e_indices_cf/REVERSION.sql (grant de vuelta y drop de los indices nuevos).
-- Prueba: el bloque $cierre$ comprueba los permisos despues; la rama de 20261015055003 la aplica con --aplica a la vez.

set local lock_timeout = '5s';

-- ============================================================ E1
revoke execute on function public._documents_kyc_firmado() from public, anon, authenticated;
revoke execute on function public._trg_contrato_bloqueado_aviso_manager() from public, anon, authenticated;

-- ============================================================ E3
create index if not exists facturas_sociedad_idx               on public.facturas (sociedad);
create index if not exists notificaciones_contrato_id_idx      on public.notificaciones (contrato_id);
create index if not exists solicitudes_pago_contrato_id_idx    on public.solicitudes_pago (contrato_id);
create index if not exists correos_cola_contrato_id_idx        on public.correos_cola (contrato_id);
create index if not exists correos_cola_factura_id_idx         on public.correos_cola (factura_id);
create index if not exists correos_cola_firma_id_idx           on public.correos_cola (firma_id);
create index if not exists reclamos_pago_contrato_id_idx       on public.reclamos_pago (contrato_id);
create index if not exists reclamos_pago_cola_id_idx           on public.reclamos_pago (cola_id);

-- ============================================================ cierre: permisos como se quieren
do $cierre$
declare f text;
begin
  foreach f in array array['public._documents_kyc_firmado()', 'public._trg_contrato_bloqueado_aviso_manager()'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      raise exception 'permisos_e_indices_cf: % no quedo con EXECUTE solo para service_role', f;
    end if;
  end loop;
end $cierre$;
