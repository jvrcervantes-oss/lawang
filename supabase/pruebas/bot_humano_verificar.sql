-- supabase/pruebas/bot_humano_verificar.sql — la regla de `bot_humano_verificar` contra la base real, SOLO LECTURA (no toca ninguna fila).
-- Los mismos casos que bot_humano_verificar.test.js pasa por la regla del proxy (`reglaBot`): si una cambia, cambia la otra.
-- Devuelve filas SOLO cuando algo está mal.
with casos(n, rol, activo, ambito, empresas, herramientas, permiso, esperado) as (values
  --CASOS-INICIO
  ('casilla',                   'agente',      true,  'global',  '{}'::text[],            '{bot_escribir}'::text[], 'bot_escribir',   true),
  ('sin casilla',               'agente',      true,  'global',  '{}'::text[],            '{leads}'::text[],        'bot_escribir',   false),
  ('super_admin sin casilla',   'super_admin', true,  'global',  '{}'::text[],            '{}'::text[],             'bot_escribir',   true),
  ('inactivo',                  'agente',      false, 'global',  '{}'::text[],            '{bot_escribir}'::text[], 'bot_escribir',   false),
  ('super_admin inactivo',      'super_admin', false, 'global',  '{}'::text[],            '{}'::text[],             'bot_escribir',   false),
  ('activo nulo',               'agente',      null,  'global',  '{}'::text[],            '{bot_escribir}'::text[], 'bot_escribir',   false),
  ('ambito empresa',            'agente',      true,  'empresa', '{}'::text[],            '{bot_escribir}'::text[], 'bot_escribir',   false),
  ('super_admin ambito empresa','super_admin', true,  'empresa', '{}'::text[],            '{}'::text[],             'bot_escribir',   false),
  ('empresas marcadas',         'agente',      true,  'global',  '{sandalwoods}'::text[], '{bot_escribir}'::text[], 'bot_escribir',   false),
  ('super_admin empresas',      'super_admin', true,  'global',  '{sandalwoods}'::text[], '{}'::text[],             'bot_escribir',   false),
  ('herramientas nulas',        'agente',      true,  'global',  '{}'::text[],            null::text[],             'bot_escribir',   false),
  ('empresas nulas',            'agente',      true,  'global',  null::text[],            '{bot_escribir}'::text[], 'bot_escribir',   true),
  ('ambito nulo',               'agente',      true,  null,      '{}'::text[],            '{bot_escribir}'::text[], 'bot_escribir',   true),
  ('rol nulo con casilla',      null,          true,  'global',  '{}'::text[],            '{bot_escribir}'::text[], 'bot_escribir',   true),
  ('rol nulo sin casilla',      null,          true,  'global',  '{}'::text[],            '{}'::text[],             'bot_escribir',   false),
  ('otra casilla pedida',       'agente',      true,  'global',  '{}'::text[],            '{bot_escribir}'::text[], 'bot_configurar', false)
  --CASOS-FIN
)
select 'regla: ' || n as fallo, esperado, public._bot_humano_regla(rol, activo, ambito, empresas, herramientas, permiso) as obtenido
  from casos where public._bot_humano_regla(rol, activo, ambito, empresas, herramientas, permiso) is distinct from esperado
union all
-- permisos: nadie fuera de postgres y bot_lawang ejecuta nada de esto (ni PUBLIC, grantee 0)
select 'acl: ' || p.proname, null, null from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('bot_humano_verificar', '_bot_humano_regla')
   and (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 or a.grantee in (select oid from pg_roles where rolname in ('anon', 'authenticated', 'service_role'))))
union all
select 'bot_lawang no ejecuta bot_humano_verificar', null, null where not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace, aclexplode(p.proacl) a, pg_roles r
   where n.nspname = 'public' and p.proname = 'bot_humano_verificar' and a.privilege_type = 'EXECUTE' and a.grantee = r.oid and r.rolname = 'bot_lawang')
union all
select 'bot_lawang ejecuta la regla pura (no debe)', null, null where exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace, aclexplode(p.proacl) a, pg_roles r
   where n.nspname = 'public' and p.proname = '_bot_humano_regla' and a.privilege_type = 'EXECUTE' and a.grantee = r.oid and r.rolname = 'bot_lawang')
union all
select 'search_path: ' || p.proname, null, null from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('bot_humano_verificar', '_bot_humano_regla') and (p.proconfig is null or not p.proconfig::text like '%search_path=%')
union all
select 'bot_humano_verificar debe ser SECURITY DEFINER', null, null from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'bot_humano_verificar' and not p.prosecdef
union all
-- la función real: un usuario que no existe, un permiso fuera de lista y un texto que no es uuid
select 'verificar usuario inexistente', null, null
 where public.bot_humano_verificar('00000000-0000-0000-0000-000000000000', 'bot_escribir') is distinct from '{"permitido": false, "email": null}'::jsonb
union all
select 'verificar permiso fuera de lista', null, null
 where public.bot_humano_verificar('00000000-0000-0000-0000-000000000000', 'leads') is distinct from '{"error": "permiso_invalido"}'::jsonb
union all
select 'verificar texto no uuid', null, null
 where public.bot_humano_verificar('ana@lawang.com', 'bot_escribir') is distinct from '{"permitido": false, "email": null}'::jsonb;
