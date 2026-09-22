-- ============================================================================
-- ANON SIN GRANTS — la RLS deja de ser la única barrera
-- 22-sep-2026 · saneo de la intranet (revisión previa: Seguridad + Datos)
-- ----------------------------------------------------------------------------
-- Estado antes de esta migración (verificado en vivo):
--   · `anon` tenía SELECT en ~55 tablas de public (clients, contratos,
--     usuarios, leads, contrato_firmas, documents…), INSERT/UPDATE/DELETE en
--     ~50, SELECT en 6 vistas y USAGE en 28 secuencias.
--   · La única policy para anon era `leads: anon can insert leads`.
--   · 45 funciones eran ejecutables por anon (34 SECURITY DEFINER), casi
--     todas por herencia de PUBLIC: triggers, agente_ve_*, puede_proyecto*…
-- Todo eso vivía detrás de la RLS, que hasta hoy no ha fallado. Pero la regla
-- de contexto/seguridad_2026.md es «grant a anon = la RLS es la ÚNICA
-- barrera»: el día que una policy nueva se abra por error (ya pasó con
-- privilegios_ejercidos el 21-sep), la tabla sale entera. Sin grant, la RLS
-- ni se evalúa: PostgREST responde `permission denied` antes.
--
-- Lo que un anónimo puede hacer DESPUÉS de esto, y por qué:
--   · INSERT en `leads`: proyectos/SumbaHills/api/lead.php escribe el lead
--     del formulario QR con la clave pública (return=minimal, sin SELECT).
--     leads.id es gen_random_uuid(): no necesita secuencia.
--   · EXECUTE en las funciones que las páginas públicas llaman por
--     /rest/v1/rpc/ (verificado con grep en investor-deck, modelo, palmfield,
--     index.html, SumbaHills): catálogo, investor deck, masterplan público.
--     Todas devuelven solo lo publicado; van declaradas en
--     departamentos/seguridad/rls_publico.txt.
--   · Nada más. Ni tablas, ni vistas, ni secuencias.
--
-- El resto de funciones pierde el grant a PUBLIC/anon pero CONSERVA exactamente
-- lo que authenticated y service_role tenían: el bucle mira privilegio a
-- privilegio antes de tocar y vuelve a concederlo. Así una función que hoy
-- solo ejecutaba el owner (triggers, cron_*_secret) sigue igual, y una que
-- authenticated ejecutaba por PUBLIC sigue ejecutándola por grant directo.
--
-- Default privileges: la fila de `postgres` para TABLAS y FUNCIONES ya no
-- incluía a anon (17-sep). La de SECUENCIAS sí (anon=rwU): se corrige. Las
-- filas de `supabase_admin` no las puede tocar `postgres` (deuda §7 de
-- seguridad_2026.md), así que una tabla creada desde el dashboard PUEDE nacer
-- con grants otra vez: el invariante «anon sin grants» de
-- tools/salud_lawang.py es la red para eso.
--
-- El gate tools/check_seguridad.py --live leía un HTTP 401/403 como «NO
-- VERIFICADO»; desde hoy `permission denied` es el aprobado FUERTE (cambio
-- en el mismo commit, con su caso en tools/test_check_seguridad.py).
-- ============================================================================

-- ── Tablas, vistas y secuencias ─────────────────────────────────────────────
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
grant insert on public.leads to anon;

alter default privileges for role postgres in schema public revoke all on sequences from anon;

-- ── Funciones: lista blanca explícita para anon, el resto sin PUBLIC ────────
do $$
declare
  r record;
  v_auth boolean;
  v_srv  boolean;
  publicas text[] := array[
    'catalogo_publico', 'modelo_fotos_publico', 'unidades_estado_publico',
    'parcelas_tamanos_disponibles',
    'deck_config_publico', 'deck_forecast_ejemplo_publico',
    'investor_deck_documentos', 'investor_deck_faq', 'investor_deck_forecast',
    'investor_deck_fotos', 'investor_deck_modelos', 'investor_deck_parcelas'];
begin
  for r in
    select p.oid, p.oid::regprocedure as firma, p.proname
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and has_function_privilege('anon', p.oid, 'execute')
       and not (p.proname = any(publicas))
  loop
    v_auth := has_function_privilege('authenticated', r.oid, 'execute');
    v_srv  := has_function_privilege('service_role',  r.oid, 'execute');
    execute format('revoke all on routine %s from public, anon', r.firma);
    if v_auth then execute format('grant execute on routine %s to authenticated', r.firma); end if;
    if v_srv  then execute format('grant execute on routine %s to service_role',  r.firma); end if;
  end loop;
end $$;

-- ── deck_publicaciones: INSERT con check(true) para PUBLIC → es_agente() ────
-- Es el registro de quién publicó qué en el investor deck (trigger deck_audita
-- lo escribe). anon no tenía grant de tabla, así que en la práctica solo
-- entraba authenticated; ahora la policy lo dice en vez de suponerlo.
-- destructivo-ok: se reemplaza la policy por una más estrecha, mismo nombre
drop policy if exists "deck_publicaciones: escribir" on public.deck_publicaciones;
create policy "deck_publicaciones: escribir" on public.deck_publicaciones
  for insert to authenticated with check (public.es_agente());

-- ── Dos funciones muertas del CRM ───────────────────────────────────────────
-- crm_lead_asignar_closer y crm_repartir_lead: 0 referencias en pg_depend,
-- 0 en el repo (html/js/ts/py) — sustituidas por crm_lead_asignar y
-- crm_reparto_* el 10-sep. Una función DEFINER sin uso es superficie sin dueño.
-- destructivo-ok: funciones sin ningún llamador, verificado en vivo y en repo
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('crm_lead_asignar_closer', 'crm_repartir_lead')
  loop
    execute format('drop function %s', r.firma);
  end loop;
end $$;
