-- Fix del fix (1-sep-2026, mismo turno): contrato_firmas_equipo() se
-- restringio hace un momento a solo las columnas que contracts/app.html lee,
-- pero se paso por alto contracts/assets/operaciones-cuentas.js:215, que SI
-- necesita snapshot_path (limpieza de storage al borrar una operacion,
-- borrarOperacion()). snapshot_path es una RUTA de almacenamiento, no una
-- credencial (a diferencia de token_hash/enlace_firma, que siguen fuera):
-- conocer la ruta no da acceso, el bucket tiene su propia policy aparte.
--
-- destructivo-ok: mismo motivo que la migracion anterior -- cambia el tipo
-- de retorno, hace falta DROP; no se pierde ningun dato.
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
;
