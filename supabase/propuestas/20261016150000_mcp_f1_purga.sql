-- MCP de Lawang · F1 · purga diaria de lo operativo del puente (16-oct-2026, sesión mcp-lawang). Va DESPUÉS de 20261016110000.
-- Sale de la 110000 porque borra filas (tools/no_destruir.py: un DELETE no entra en una migración que construye). Se aplica con el
-- OK del owner a abrir el puente [mcp-abrir-puente], junto con 20261016140000: antes no hay conexiones, ni peticiones ni tokens
-- que caduquen, así que no hay nada que purgar.
-- destructivo-ok: borra SOLO filas operativas caducadas hace más de un día de public.ia_peticiones (peticiones de conexión de
-- 5 minutos) y public.ia_tokens (tokens ya inservibles). No toca ia_llamadas (el registro de quién consultó qué: su retención la
-- fijan Legal y el owner, [mcp-retencion-llamadas]) ni ia_conexiones. Necesita la marca del owner.
--
-- VUELTA ATRÁS (no destruye nada): `select cron.unschedule('ia-purga-diaria');` (la función sin cron no hace nada sola).

create or replace function privado.ia_purga()
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  delete from public.ia_peticiones where caduca_en < now() - interval '1 day';
  delete from public.ia_tokens where caduca_en < now() - interval '1 day';
$$;
-- dueño ia_puente_rol (dueño de las tablas ia_*), como el resto del puente; ALTER OWNER exige CREATE del nuevo dueño en el esquema
grant create on schema privado to ia_puente_rol;
alter function privado.ia_purga() owner to ia_puente_rol;
revoke create on schema privado from ia_puente_rol;
revoke all on function privado.ia_purga() from public, anon, authenticated, service_role;

-- Cada día a las 03:17 UTC. pg_cron corre como postgres, que es miembro de ia_puente_rol: la ejecuta sin grant aparte.
-- En una rama de ensayo sin pg_cron no se programa (la viva sí lo tiene: 13 trabajos, medido el 16-oct).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('ia-purga-diaria', '17 3 * * *', 'select privado.ia_purga()');
  end if;
end $$;
