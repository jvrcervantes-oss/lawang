-- 10-oct-2026 (Deploy, a raiz de `check_seguridad.py --live`: [BOT-S1] _bot_humano_regla debe ser SECURITY DEFINER).
-- La funcion pura de la regla de /humano (migracion 20261010190000) se creo sin SECURITY DEFINER. No era explotable (sin EXECUTE para nadie salvo su dueno; solo la llama
-- `bot_humano_verificar`, que es definer), pero el gate BOT-S1 exige que toda funcion del bot sea definer con search_path fijo y sin grants: se alinea, sin aflojar el gate.
-- Mismo cuerpo, mismos revokes. No toca datos. Reversion: create or replace de la version anterior (sin `security definer`).
create or replace function public._bot_humano_regla(p_rol text, p_activo boolean, p_ambito text, p_empresas text[], p_herramientas text[], p_permiso text)
returns boolean language sql immutable security definer set search_path = '' as $f$
  select coalesce(p_activo, false)
     and p_ambito is distinct from 'empresa'
     and coalesce(cardinality(p_empresas), 0) = 0
     and (p_rol is not distinct from 'super_admin' or coalesce(p_permiso = any (p_herramientas), false));
$f$;

revoke all on function public._bot_humano_regla(text, boolean, text, text[], text[], text) from public, anon, authenticated, service_role;
