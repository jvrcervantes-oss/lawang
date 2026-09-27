-- LAW-338 L2 — CIERRE al navegador de las 7 tablas de pantallas de un solo lector. SIN APLICAR (por_aplicar/).
-- Se aplica SOLO con OK del owner y DESPUÉS de que producción sirva las pantallas que ya no las leen (lección B3-B5):
--   copia de sesión 0928-0708-law338-l2 (commits 949ecb83, 33824c59, 754f646f, de606aa7) aterrizada + Deploy confirma
--   el ?v= servido de mantenimiento.js, comunicacion.js, solicitudes.js, autoria.js, documento_diseno.js + verificador.
-- Al aplicarla: moverla a supabase/migrations/ con la versión que dé el MCP (mismo commit), añadir las 7 tablas a
-- _CERRADAS_LAW338 de tools/salud_lawang.py y hacer el ataque: GET /rest/v1/<tabla> con sesión de agente → 42501, no [].
--
-- Quién las lee hoy (medido el 28-sep-2026, `erp/contrato_front.py axisworks-demo --dir <copia> --grafo`):
--   · navegador: NINGÚN lector directo ni embebido en la copia (las 7 salen en «legibles sin lector»).
--   · RPC nuevas (mantenimiento_datos, comunicacion_datos, comunicado_datos, solicitudes_alta_datos, referidos_datos,
--     autoria_datos, contrato_diseno_datos): dueño lw_lector ⇒ leen con el SELECT de lw_lector y la policy TO lw_lector.
--   · servidor: edges comunicados-envio, avisos-manager, admin-usuarios y alta-colaborador usan service_role (no
--     dependen del GRANT de authenticated); RPC de escritura (comunicado_guarda/encolar/borra, mantenimiento_*,
--     reasigna_autor, contratos_diseno_guarda…) son DEFINER. 0 vistas, 0 INVOKER ejecutables por authenticated,
--     0 policies de otras tablas o de storage que las consulten.
--   · Orden: comunicado_envios (hija) antes que comunicados (padre), aunque ninguna policy cruza entre ellas.


-- Comprobación previa (#128 Datos 3 · #136 Seguridad 5): si algo, fuera de estas tablas, las lee por EXISTS/JOIN o
-- con el GRANT de authenticated, NO se aplica nada. Medido el 28-sep-2026 en la base: 0 en las tres patas.
do $$
declare v_n int; v_lista text;
begin
  select count(*), string_agg(schemaname || '.' || tablename || '.' || policyname, ', ') into v_n, v_lista
    from pg_policies
   where (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ~ '(from|join)\s+(public\.)?(comunicado_envios|comunicados|contratos_diseno|correcciones_datos|mantenimiento|referidos_contactos|solicitudes_colaborador)\M'
     and not (schemaname = 'public' and tablename in ('comunicado_envios', 'comunicados', 'contratos_diseno', 'correcciones_datos', 'mantenimiento', 'referidos_contactos', 'solicitudes_colaborador'));
  if v_n > 0 then raise exception 'L2 revoke: % policies de otras tablas o de storage consultan estas tablas: %', v_n, v_lista; end if;

  select count(*), string_agg(viewname, ', ') into v_n, v_lista
    from pg_views where schemaname = 'public' and definition ~ '\m(comunicado_envios|comunicados|contratos_diseno|correcciones_datos|mantenimiento|referidos_contactos|solicitudes_colaborador)\M';
  if v_n > 0 then raise exception 'L2 revoke: vistas que leen estas tablas: %', v_lista; end if;

  select count(*), string_agg(p.proname, ', ') into v_n, v_lista
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and not p.prosecdef
     and has_function_privilege('authenticated', p.oid, 'execute') and p.prosrc ~ '\m(comunicado_envios|comunicados|contratos_diseno|correcciones_datos|mantenimiento|referidos_contactos|solicitudes_colaborador)\M';
  if v_n > 0 then raise exception 'L2 revoke: funciones INVOKER que leen estas tablas (se romperían): %', v_lista; end if;
end $$;

revoke select on public.comunicado_envios, public.comunicados, public.contratos_diseno, public.correcciones_datos, public.mantenimiento, public.referidos_contactos, public.solicitudes_colaborador from authenticated;

alter policy "comunicado_envios_admin_select" on public.comunicado_envios to lw_lector;
alter policy "comunicados_admin_select" on public.comunicados to lw_lector;
alter policy "agentes autenticados leen diseno" on public.contratos_diseno to lw_lector;
alter policy "agentes leen correcciones" on public.correcciones_datos to lw_lector;
alter policy "mantenimiento_leer" on public.mantenimiento to lw_lector;
alter policy "admins con usuarios ven referidos" on public.referidos_contactos to lw_lector;
alter policy "admins con usuarios ven solicitudes" on public.solicitudes_colaborador to lw_lector;

do $$
declare t text;
begin
  foreach t in array array['comunicado_envios', 'comunicados', 'contratos_diseno', 'correcciones_datos', 'mantenimiento', 'referidos_contactos', 'solicitudes_colaborador'] loop
    if has_table_privilege('authenticated', 'public.' || t, 'select') then
      raise exception 'L2 revoke: authenticated sigue leyendo %', t;
    end if;
    if not has_table_privilege('lw_lector', 'public.' || t, 'select') then
      raise exception 'L2 revoke: lw_lector ha perdido la lectura de %, la RPC quedaría a cero', t;
    end if;
    if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = t and p.cmd in ('SELECT', 'ALL')
                                          and 'authenticated' = any(p.roles)) then
      raise exception 'L2 revoke: queda una policy de lectura TO authenticated en %', t;
    end if;
  end loop;
end $$;
