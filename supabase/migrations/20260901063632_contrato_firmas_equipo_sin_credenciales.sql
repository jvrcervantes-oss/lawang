-- Fix-forward de la consulta de deploy (1-sep-2026, hallazgo de Seguridad):
-- contrato_firmas_equipo() hacia `select *` sobre contrato_firmas y la
-- migracion anterior de esta misma sesion le anadio `enlace_firma` (el
-- token de firma EN CLARO) sin darse cuenta de que esta funcion YA exponia
-- esa fila entera a CUALQUIER agente (es_agente() a secas, sin es_suyo(),
-- y sin filtrar por estado) -- no solo al dueno del contrato, y no solo
-- mientras esta pendiente. El propio token_hash ya se exponia asi antes de
-- hoy (riesgo menor, es un hash) pero enlace_firma es un secreto usable
-- directamente: cualquier agente podia abrir la firma de un contrato ajeno.
--
-- Arreglo: la funcion pasa de `RETURNS SETOF contrato_firmas` (select *) a
-- `RETURNS TABLE(...)` con la lista EXACTA de columnas que
-- contracts/app.html de verdad lee de aqui (grep verificado: estado,
-- firmante_nombre, firmante_email, firmante_rol, id, creado_en, firmado_en,
-- expira_en) -- token_hash, enlace_firma, snapshot_path, pdf_path, pdf_hash,
-- firmante_ip, firmante_user_agent y orden se quedan fuera. No es un cambio
-- de alcance (quien ve que contrato sigue igual, es_agente() a secas sigue
-- siendo la politica), es dejar de servir credenciales dentro de un listado
-- de estado.
--
-- destructivo-ok: Postgres no permite cambiar el tipo de retorno de una
-- funcion con CREATE OR REPLACE (RETURNS SETOF contrato_firmas ->
-- RETURNS TABLE(...) cuenta como cambio de tipo) -- hace falta DROP antes.
-- No se pierde ningun dato: es la misma funcion, mismo nombre, mismos
-- argumentos (ninguno), solo cambia que columnas devuelve.
drop function if exists public.contrato_firmas_equipo();

create or replace function public.contrato_firmas_equipo()
 returns table(
   id uuid, contrato_id uuid, estado text,
   firmante_nombre text, firmante_email text, firmante_rol text,
   creado_en timestamptz, firmado_en timestamptz, expira_en timestamptz
 )
 language sql
 security definer
 set search_path to ''
as $function$
  select cf.id, cf.contrato_id, cf.estado,
         cf.firmante_nombre, cf.firmante_email, cf.firmante_rol,
         cf.creado_en, cf.firmado_en, cf.expira_en
    from public.contrato_firmas cf
   where public.es_agente();
$function$;

revoke execute on function public.contrato_firmas_equipo() from public;
revoke execute on function public.contrato_firmas_equipo() from anon;
grant execute on function public.contrato_firmas_equipo() to authenticated;
;
