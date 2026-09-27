-- LAW-338 · bloque L1 — higiene de las dos auxiliares que nacieron en L0 (BAJAS del revisor de L0).
-- encargos/20260927_lawang_law338_lecturas_bloques.md → fila L0, «L1 debe además».
--
-- 1. public.uid_sesion() y creatividad_ve_fichero(text) quitan EXECUTE a service_role. Llamadores con
--    nombre (reducir la exposición, seguridad_2026 §1.ter): uid_sesion → solo las RPC `_datos` con dueño
--    lw_lector; creatividad_ve_fichero → solo la policy de Storage «creatividades: leer ficheros», que
--    evalúa authenticated (service_role tiene BYPASSRLS: esa policy nunca se le evalúa). Buscado por
--    nombre el 27-sep-2026 en edges, JS/PHP/py del repo, pg_proc, pg_policies y cron.job: ningún otro.
--
-- 2. creatividad_ve_fichero sale de la API: PostgREST de Lawang expone SOLO `public` y `graphql_public`
--    (medido por REST el 27-sep-2026: PGRST106 «Only the following schemas are exposed: public,
--    graphql_public»). En `public` cualquiera con sesión podía llamarla por /rest/v1/rpc/ y preguntar,
--    ruta a ruta, qué ficheros del bucket existen y ve. Se mueve a `privado`, esquema nuevo sin USAGE para
--    nadie más que postgres: la policy guarda el OID de la función, no su nombre, así que sigue apuntando
--    a ella. Medido antes/después como en L0: count + md5 de los nombres de storage.objects del bucket
--    `creatividades` que ve cada uno de los 65 usuarios como authenticated.

-- ── 1 ─────────────────────────────────────────────────────────────────────────────────────────────────
revoke execute on function public.uid_sesion() from service_role;
revoke execute on function public.creatividad_ve_fichero(text) from service_role;

-- ── 2 ─────────────────────────────────────────────────────────────────────────────────────────────────
create schema if not exists privado;
revoke all on schema privado from public, anon, authenticated, service_role;
alter function public.creatividad_ve_fichero(text) set schema privado;

do $$
declare v_acl text; v_q text;
begin
  select p.proacl::text into v_acl from pg_proc p where p.oid = 'privado.creatividad_ve_fichero(text)'::regprocedure;
  if v_acl is distinct from '{postgres=X/postgres,authenticated=X/postgres}' then
    raise exception 'creatividad_ve_fichero: proacl % (esperado postgres + authenticated)', v_acl;
  end if;
  if (select p.proacl::text from pg_proc p where p.oid = 'public.uid_sesion()'::regprocedure)
     is distinct from '{postgres=X/postgres,lw_lector=X/postgres}' then
    raise exception 'uid_sesion: proacl inesperado';
  end if;
  select qual into v_q from pg_policies where schemaname = 'storage' and policyname = 'creatividades: leer ficheros';
  if v_q is null or v_q !~ 'privado\.creatividad_ve_fichero' then
    raise exception 'la policy de Storage no apunta a privado.creatividad_ve_fichero: %', v_q;
  end if;
end $$;
