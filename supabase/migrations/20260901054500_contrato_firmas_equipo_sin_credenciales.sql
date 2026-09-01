-- Fix-forward de la consulta de deploy (1-sep-2026, hallazgo de Seguridad):
-- contrato_firmas_equipo() hacía `select *` sobre contrato_firmas y la
-- migración anterior de esta misma sesión le añadió `enlace_firma` (el
-- token de firma EN CLARO) sin darse cuenta de que esta función YA exponía
-- esa fila entera a CUALQUIER agente (es_agente() a secas, sin es_suyo(),
-- y sin filtrar por estado) — no solo al dueño del contrato, y no solo
-- mientras está pendiente. El propio token_hash ya se exponía así antes de
-- hoy (riesgo menor, es un hash) pero enlace_firma es un secreto usable
-- directamente: cualquier agente podía abrir la firma de un contrato ajeno.
--
-- Arreglo: la función pasa de `RETURNS SETOF contrato_firmas` (select *) a
-- `RETURNS TABLE(...)` con la lista EXACTA de columnas que se leen de aquí
-- en todo el repo (grep verificado): contracts/app.html usa estado,
-- firmante_nombre, firmante_email, firmante_rol, id, creado_en, firmado_en,
-- expira_en; contracts/assets/operaciones-cuentas.js además necesita
-- snapshot_path (limpieza de storage al borrar una operación,
-- borrarOperacion() — es una RUTA, no una credencial, el bucket tiene su
-- propia policy aparte). token_hash, enlace_firma, pdf_path, pdf_hash,
-- firmante_ip, firmante_user_agent y orden se quedan fuera. No es un cambio
-- de alcance (quién ve qué contrato sigue igual, es_agente() a secas sigue
-- siendo la política), es dejar de servir credenciales dentro de un listado
-- de estado.
--
-- destructivo-ok: Postgres no permite cambiar el tipo de retorno de una
-- función con CREATE OR REPLACE (RETURNS SETOF contrato_firmas ->
-- RETURNS TABLE(...) cuenta como cambio de tipo) — hace falta DROP antes.
-- No se pierde ningún dato: es la misma función, mismo nombre, mismos
-- argumentos (ninguno), solo cambia qué columnas devuelve.
drop function if exists public.contrato_firmas_equipo();

create or replace function public.contrato_firmas_equipo()
 returns table(
   id uuid, contrato_id uuid, estado text,
   firmante_nombre text, firmante_email text, firmante_rol text,
   creado_en timestamptz, firmado_en timestamptz, expira_en timestamptz,
   snapshot_path text
 )
 language sql
 security definer
 set search_path to ''
as $function$
  select cf.id, cf.contrato_id, cf.estado,
         cf.firmante_nombre, cf.firmante_email, cf.firmante_rol,
         cf.creado_en, cf.firmado_en, cf.expira_en, cf.snapshot_path
    from public.contrato_firmas cf
   where public.es_agente();
$function$;

revoke execute on function public.contrato_firmas_equipo() from public;
revoke execute on function public.contrato_firmas_equipo() from anon;
grant execute on function public.contrato_firmas_equipo() to authenticated;
