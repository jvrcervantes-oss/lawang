-- destructivo-ok: solo retira permisos y policies de ESCRITURA sin llamador; no borra ni cambia ninguna fila.
-- Cierre GLOBAL de escrituras de authenticated/anon (LAW-336/337/338, 27-sep-2026, noche). Análisis tabla por tabla
-- de Seguridad (solo lectura) en encargos/20260927_lawang_cierre_global_escrituras.md. Quedan abiertas SOLO dos
-- puertas con llamador: bot_faq (edge bot-agentes con el JWT del usuario) y leads (INSERT anon desde
-- SumbaHills/api/lead.php); cada una tiene su pieza siguiente. Las secuencias (parte C del análisis) van aparte.
-- LAW-338 (cierre global). Revisión de Seguridad 27-sep-2026: encargos/20260927_lawang_cierre_global_escrituras.md
-- Quedan abiertas SOLO: bot_faq (INSERT/UPDATE authenticated, edge bot-agentes con JWT) y leads (INSERT anon, SumbaHills/api/lead.php).


-- ── A.1  Revoke de escritura en las 42 relaciones sin llamador ─────────────────────────────
revoke insert, update, delete, truncate, maintain on
  public._respaldo_resort_sandalwoods, public.avisos_almacenamiento, public.avisos_soporte_equipo,
  public.axisworks_cuentas, public.axisworks_facturas, public.axisworks_meta_campanas,
  public.axisworks_meta_campanas_conjuntos, public.axisworks_meta_exclusiones_segmento,
  public.axisworks_meta_insights_dia, public.axisworks_meta_targeting_historial, public.axisworks_meta_vigilancia,
  public.borrados, public.bot_bloqueos, public.bot_consultas, public.bot_fuentes,
  public.contrato_compradores, public.contrato_documentos, public.contrato_eventos, public.contrato_tipo_etapa,
  public.documentos_desactualizados, public.extras, public.fathom_call_insights,
  public.investor_deck_config, public.investor_deck_verificaciones,
  public.lead_acceso_log, public.lead_closer, public.lead_estado, public.lead_estado_log, public.lead_estados,
  public.lead_notas, public.lead_sugerencia, public.lead_tablero,
  public.mensajes_comprador, public.notificaciones, public.obra_fases, public.payments, public.portal_accesos,
  public.preferencias_comprador, public.privilegios_ejercidos, public.proyectos_huerfanos,
  public.recibi_aplicaciones, public.reservations,
  public.bloques_legales, public.gasto_categorias          -- grants de columna: el revoke de tabla los arrastra
from authenticated, anon;

-- leads: fuera todo lo de authenticated; anon conserva SOLO insert (SumbaHills/api/lead.php)
revoke insert, update, delete, truncate, maintain on public.leads from authenticated;
revoke update, delete, truncate, maintain on public.leads from anon;

-- bot_faq: authenticated conserva insert/update (edge bot-agentes con JWT); fuera lo demás
revoke delete, truncate, maintain on public.bot_faq from authenticated, anon;
revoke insert, update on public.bot_faq from anon;

-- Por si acaso los grants de columna no cayeron con el revoke de tabla (explícito, idempotente)
revoke insert (clave, estado, idioma, texto, version) on public.bloques_legales from authenticated;
revoke insert (clave, nombre, grupo, orden, activa), update (nombre, grupo, orden, activa) on public.gasto_categorias from authenticated;

-- ── A.2  MAINTAIN fuera de todo el esquema ────────────────────────────────────────────────
revoke maintain on all tables in schema public from authenticated, anon;   -- "all tables" incluye vistas y matviews

-- ── A.3  Drop de policies de escritura sin llamador (tablas de A.1) ──────────────────────
drop policy if exists "bot_bloqueos: solo super_admin escribe"                       on public.bot_bloqueos;
drop policy if exists "bot_consultas: cada uno inserta como si mismo"                on public.bot_consultas;
drop policy if exists "bot_fuentes: solo super_admin escribe"                        on public.bot_fuentes;
drop policy if exists "se enlaza un comprador a un contrato que se ve"               on public.contrato_compradores;
drop policy if exists "se cambia el enlace de un contrato que se ve"                 on public.contrato_compradores;
drop policy if exists "se desenlaza un comprador de un contrato que se ve"           on public.contrato_compradores;
drop policy if exists "extras: escribir"                                             on public.extras;
drop policy if exists "obra_fases: escribir"                                         on public.obra_fases;
drop policy if exists "admins gestionan accesos del portal"                          on public.portal_accesos;
drop policy if exists "admin borra aplicaciones"                                     on public.recibi_aplicaciones;
drop policy if exists "agentes borran aplicaciones de su propio recibi sin anular"   on public.recibi_aplicaciones;
drop policy if exists "agentes o su manager crean aplicaciones al crear su recibi"   on public.recibi_aplicaciones;
drop policy if exists "bloques_legales: escribir"                                    on public.bloques_legales;
drop policy if exists "categorias: crear"                                            on public.gasto_categorias;
drop policy if exists "categorias: editar"                                           on public.gasto_categorias;
-- Las policies ALL también daban SELECT: comprobado el 27-sep que cada tabla tiene su policy SELECT propia.

-- ── B (opcional, recomendado)  Policies de escritura residuales sobre tablas sin grant ─────
-- Sin grant son letra muerta; se quitan para que un GRANT futuro no las reactive.
-- DEFINER = postgres con bypassrls: no rompe ninguna RPC.
do $b$
declare r record;
begin
  for r in
    select p.tablename, p.policyname
    from pg_policies p
    where p.schemaname = 'public' and p.cmd in ('INSERT','UPDATE','DELETE','ALL')
      and (p.roles && array['anon','authenticated','public']::name[])
      and not (p.tablename = 'bot_faq' and p.policyname in ('bot_faq: solo super_admin aprueba','bot_faq: solo super_admin retira'))
      and not (p.tablename = 'leads'   and p.policyname = 'anon can insert leads')
      and not exists (   -- solo si NINGUNO de los dos roles conserva grant de escritura en la tabla
        select 1 from pg_class c cross join lateral aclexplode(c.relacl) a
        where c.relnamespace = 'public'::regnamespace and c.relname = p.tablename
          and a.grantee in ('authenticated'::regrole,'anon'::regrole)
          and a.privilege_type in ('INSERT','UPDATE','DELETE'))
      and not exists (
        select 1 from information_schema.column_privileges cp
        where cp.table_schema = 'public' and cp.table_name = p.tablename
          and cp.grantee in ('authenticated','anon') and cp.privilege_type in ('INSERT','UPDATE'))
  loop
    -- ALL también cubre SELECT: se avisa para revisar la lectura de esa tabla
    raise notice 'drop policy residual %.%', r.tablename, r.policyname;
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $b$;
-- B incluye policies ALL (condicion_tramos, condiciones_comision, equipo_miembros, equipos_venta,
-- plantilla_cuentas, plantillas_contrato, proyecto_cuentas, bot_temas): todas tienen policy SELECT propia (27-sep).

-- ── C (opcional, pieza aparte)  Secuencias ──────────────────────────────────────────────
-- authenticated tiene USAGE/UPDATE en 35 secuencias (contratos_*_seq numeran contratos).
-- Tras A, ninguna tabla con INSERT para authenticated usa secuencia (bot_faq y leads son uuid), y los
-- únicos INVOKER con nextval (set_contrato_numero, axisworks_set_factura_numero) solo se disparan
-- desde escrituras DEFINER/service. Seguro, pero cambia otro eje: aplicarlo en su propia migración.
-- revoke usage, update on all sequences in schema public from authenticated, anon;
-- alter default privileges for role postgres in schema public revoke usage, update on sequences from authenticated, anon;

-- ── D  Comprobación: falla la migración si queda algo fuera de la lista blanca ────────────
do $chk$
declare malos text;
begin
  -- D.1 privilegios de tabla (INSERT/UPDATE/DELETE/TRUNCATE/MAINTAIN)
  select string_agg(format('%s:%s:%s', c.relname, pg_get_userbyid(a.grantee), a.privilege_type), ', ')
    into malos
  from pg_class c cross join lateral aclexplode(c.relacl) a
  where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p','v','m','f')
    and a.grantee in ('authenticated'::regrole,'anon'::regrole)
    and a.privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','MAINTAIN')
    and not (c.relname = 'bot_faq' and a.grantee = 'authenticated'::regrole and a.privilege_type in ('INSERT','UPDATE'))
    and not (c.relname = 'leads'   and a.grantee = 'anon'::regrole          and a.privilege_type = 'INSERT');
  if malos is not null then
    raise exception 'cierre global: quedan privilegios de escritura de tabla: %', malos;
  end if;

  -- D.2 privilegios de columna (el hueco que aclexplode sobre relacl no ve)
  select string_agg(format('%s.%s:%s:%s', cp.table_name, cp.column_name, cp.grantee, cp.privilege_type), ', ')
    into malos
  from information_schema.column_privileges cp
  where cp.table_schema = 'public' and cp.grantee in ('authenticated','anon')
    and cp.privilege_type in ('INSERT','UPDATE')
    and not (cp.table_name = 'bot_faq' and cp.grantee = 'authenticated')
    and not (cp.table_name = 'leads'   and cp.grantee = 'anon' and cp.privilege_type = 'INSERT');
  if malos is not null then
    raise exception 'cierre global: quedan privilegios de escritura de columna: %', malos;
  end if;

  -- D.3 policies de escritura para anon/authenticated/public que AÚN tienen grant detrás (puerta viva)
  select string_agg(format('%s."%s"(%s)', p.tablename, p.policyname, p.cmd), ', ')
    into malos
  from pg_policies p
  where p.schemaname = 'public' and p.cmd in ('INSERT','UPDATE','DELETE','ALL')
    and (p.roles && array['anon','authenticated','public']::name[])
    and not (p.tablename = 'bot_faq' and p.policyname in ('bot_faq: solo super_admin aprueba','bot_faq: solo super_admin retira'))
    and not (p.tablename = 'leads'   and p.policyname = 'anon can insert leads')
    and exists (
      select 1 from pg_class c cross join lateral aclexplode(c.relacl) a
      where c.relnamespace = 'public'::regnamespace and c.relname = p.tablename
        and a.grantee in ('authenticated'::regrole,'anon'::regrole)
        and a.privilege_type in ('INSERT','UPDATE','DELETE'));
  if malos is not null then
    raise exception 'cierre global: policies de escritura con grant vivo: %', malos;
  end if;

  -- D.4 (estricto, solo si se aplicó B) ninguna policy de escritura fuera de la lista blanca, con o sin grant
  -- select string_agg(...) into malos from pg_policies p where ... (misma lista blanca, sin el exists);
  -- if malos is not null then raise exception ...; end if;

  -- D.5 las dos puertas que quedan siguen existiendo (si no, se ha roto un llamador)
  if not has_table_privilege('authenticated', 'public.bot_faq', 'INSERT')
     or not has_table_privilege('authenticated', 'public.bot_faq', 'UPDATE') then
    raise exception 'cierre global: bot_faq perdió INSERT/UPDATE y la edge bot-agentes lo necesita';
  end if;
  if not has_table_privilege('anon', 'public.leads', 'INSERT') then
    raise exception 'cierre global: leads perdió INSERT de anon y SumbaHills/api/lead.php lo necesita';
  end if;
end $chk$;

