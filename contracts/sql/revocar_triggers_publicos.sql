-- ════════════════════════════════════════════════════════════════════════════
-- QUE LA ALARMA PUEDA SONAR — 17-ago-2026 (auditoría)
-- ════════════════════════════════════════════════════════════════════════════
-- SÍNTOMA: el linter de seguridad de Supabase daba 60 avisos, 53 de ellos WARN.
--
-- DIAGNÓSTICO, verificado función por función contra `pg_proc`: NINGUNO era un
-- problema real.
--   · De las 13 «ejecutables por anon», 12 devuelven `trigger`. Llamar a una
--     función de trigger por RPC da error del propio motor de Postgres, así que
--     no hacen nada; y la 13ª, `unidades_estado_publico`, es pública a propósito
--     —la web lee de ella la disponibilidad de las parcelas—.
--   · Las 38 de `authenticated` comprueban el permiso DENTRO (`es_agente()`,
--     `puede(...)`, `es_super_admin()`). Leídas una a una.
--
-- Y ESO ES EL PROBLEMA. Una lista que siempre está en rojo no distingue el día
-- que aparezca una función nueva que sí abra un agujero. Y ese día llega solo:
-- «un GRANT no restringe, añade — una función nueva nace pública». Con 51 avisos
-- permanentes, el 52º no se ve.
--
-- QUÉ HACE: quitar el EXECUTE que ninguna de las 18 funciones de trigger necesita
-- (16 de la suite + 2 de las tablas `axisworks_*`, que además deberían mudarse
-- fuera de esta base — hallazgo 12 de la auditoría).
--
-- POR QUÉ NO ROMPE NADA, y no es una deducción: Postgres comprueba el EXECUTE de
-- la función al CREAR el trigger, no al dispararlo. Probado en vivo antes de
-- escribir esto, con el patrón de bloque DO que termina en `raise exception`:
-- revocado el EXECUTE de `normaliza_carpeta` a public/anon/authenticated, un
-- INSERT hecho COMO `authenticated` y con los claims de un usuario real guardó
-- «//Planos//A//» como «Planos/A» — o sea que el trigger corrió. La excepción
-- deshizo el insert y el revoke, y se comprobó después que no quedó ni la fila ni
-- el cambio de permisos.
--
-- LO QUE NO SE TOCA, a propósito:
--   · `unidades_estado_publico` — anon la necesita, es la disponibilidad pública.
--   · Las 38 de `authenticated` que no son triggers — sus avisos son informativos
--     y quitarles el EXECUTE rompería la aplicación: son las que ELLA llama.
--     Su control está dentro de cada función, que es donde debe estar.
--
-- Es idempotente: revocar algo ya revocado no falla.
-- ════════════════════════════════════════════════════════════════════════════

do $$
declare
  f record;
  n int := 0;
begin
  for f in
    select p.oid::regprocedure as firma, p.proname
      from pg_proc p
      join pg_namespace nm on nm.oid = p.pronamespace
      join pg_type t on t.oid = p.prorettype
     where nm.nspname = 'public'
       and t.typname  = 'trigger'
       -- solo las que TIENEN un trigger de verdad colgado: una función que
       -- devuelve trigger y no la usa ninguno es otra conversación (código
       -- muerto), y este fichero no es el sitio para decidirlo.
       and exists (select 1 from pg_trigger g
                    where g.tgfoid = p.oid and not g.tgisinternal)
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.firma);
    n := n + 1;
    raise notice '  revocado: %', f.proname;
  end loop;
  raise notice 'revocar_triggers_publicos: % funciones de trigger ya no son ejecutables por la aplicacion', n;
end $$;

-- ── Comprobación (la del catálogo) ──────────────────────────────────────────
-- Ninguna función de trigger debe quedar alcanzable por PUBLIC, anon ni
-- authenticated. Esto tiene que devolver 0 filas:
--
--   select p.proname, array_to_string(p.proacl,' | ')
--     from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--     join pg_type t on t.oid=p.prorettype
--    where n.nspname='public' and t.typname='trigger'
--      and exists (select 1 from unnest(coalesce(p.proacl,'{}')) a
--                   where a::text like '=%'              -- PUBLIC
--                      or a::text like 'anon=%'
--                      or a::text like 'authenticated=%');
--
-- ⚠️ PUBLIC es el elemento de ACL que EMPIEZA por '=', sin rol delante. La primera
-- versión de esta comprobación buscaba `like '%=X/postgres%'` sobre el ACL entero
-- y daba 18 filas DESPUÉS de haber revocado bien: ese patrón casa también con
-- `postgres=X/postgres`, que es el dueño. Una comprobación que dice que algo
-- sigue mal cuando ya está bien acaba en que alguien "arregla" lo que no estaba
-- roto — o en que se desconfía del guardarraíl y se deja de mirar. Anotado aquí
-- porque el error es fácil de repetir con cualquier ACL de Postgres.
--
-- MEDIDO tras aplicarlo (17-ago-2026): el linter baja de 53 avisos WARN a 29, y
-- de 60 lints a 36. Los que quedan son todos deliberados o ya fichados:
--   · 26 funciones de `authenticated` que comprueban el permiso dentro — leídas
--     una a una, y quitarles el EXECUTE rompería la aplicación: son las que llama;
--   · `unidades_estado_publico` para anon — la disponibilidad pública de parcelas;
--   ·  7 INFO de tablas con RLS y sin policy: 4 son las `axisworks_*` que hay que
--      mudar fuera de esta base (hallazgo 12) y 3 son tablas muertas de un esquema
--      viejo (`payments`, `reservations`, `contrato_documentos`);
--   · `pg_net` en public y la protección de contraseñas filtradas: los dos son del
--     panel de Supabase, no del repo.
-- A partir de aquí, un aviso nuevo significa algo — que es el objetivo.
