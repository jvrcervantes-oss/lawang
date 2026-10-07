-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «plantillas de contrato por empresa» · S10 · cierre (8-oct-2026) · reducir la exposicion (contexto/seguridad_2026.md §1.ter).
-- Tres funciones de TRIGGER conservaban EXECUTE sin llamador: un trigger no necesita que nadie tenga EXECUTE para dispararse (Postgres solo lo comprueba al
-- CREAR el trigger) y una funcion RETURNS trigger no se puede llamar a mano. Es higiene, no un hueco: se cierran para que la lista de lo expuesto sea la de lo que tiene llamador.
--   un_solo_default_por_plantilla()           trigger trg_un_solo_default            sobre plantilla_cuentas (authenticated y service_role)
--   _trg_equipos_venta_plantilla_defecto()    trigger trg_equipos_venta_plantilla_defecto sobre equipos_venta (service_role)
--   _trg_plantilla_reparto_suma_100()         trigger trg_plantilla_reparto_suma_100  sobre plantilla_reparto (service_role)
-- NO se borra plantilla_contrato_version_de_contrato (sin llamador y sin EXECUTE para nadie salvo su dueno lw_lector): sigue nombrada en contracts/plantilla_tipo_slug.test.js y en
-- las pruebas f2_plantillas_s5/s7 como «debe seguir sin EXECUTE»; quitarla obliga a reescribir esas pruebas y no cambia la exposicion, que ya es cero.
-- destructivo-ok: solo revoca EXECUTE de funciones de trigger; no toca filas, tablas ni triggers
-- REVERTIR:
--   grant execute on function public.un_solo_default_por_plantilla() to authenticated, service_role;
--   grant execute on function public._trg_equipos_venta_plantilla_defecto() to service_role;
--   grant execute on function public._trg_plantilla_reparto_suma_100() to service_role;
revoke execute on function public.un_solo_default_por_plantilla() from authenticated, service_role;
revoke execute on function public._trg_equipos_venta_plantilla_defecto() from service_role;
revoke execute on function public._trg_plantilla_reparto_suma_100() from service_role;
