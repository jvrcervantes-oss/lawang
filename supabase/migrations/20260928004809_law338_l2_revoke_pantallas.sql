-- LAW-338 L2 — CIERRE al navegador de las 7 tablas de pantallas de un solo lector.
-- erp-ok: B10 a la par (pareja: erp/por_aplicar/b10a_l2_revoke_pantallas.sql, que espera a republicar el ERP del estudio)
-- APLICADA el 28-sep-2026 con OK del owner («Sí, cerrar ya»), después de comprobar que producción sirve las pantallas
--   que ya no las leen (lección B3-B5): lawangproperties.com sirve comunicacion.js?v=8e653067, mantenimiento.js?v=a40d074a
--   (comunicación, ajustes, reservas), solicitudes.js?v=87501e14, autoria.js?v=3b88aaeb (app, v4/facturas, v4/recibos) y
--   documento_diseno.js?v=a6230c91, los cinco con lwDatos y 0 .from() de estas tablas (curl, 28-sep).
-- Con ella: las 7 tablas en _CERRADAS_LAW338 de tools/salud_lawang.py; ataque medido (ver Bitácora del encargo).
--
-- Quién las lee hoy (medido el 28-sep-2026):
--   · navegador: NINGÚN lector directo ni embebido en la copia (`erp/contrato_front.py axisworks-demo --dir <copia>
--     --grafo`: las 7 salen en «legibles sin lector»).
--   · RPC de lectura: mantenimiento_datos, comunicacion_datos, comunicado_datos, solicitudes_alta_datos,
--     referidos_datos, autoria_datos, contrato_diseno_datos, dueño lw_lector ⇒ leen con el SELECT de lw_lector y la
--     policy TO lw_lector.
--   · edges del repo que las tocan (contracts/edge + supabase/functions): comunicados-envio, avisos-manager,
--     admin-usuarios, alta-colaborador — las cuatro con cliente service_role (no dependen del GRANT de authenticated).
--   · RPC de escritura (comunicado_guarda/encolar/borra, mantenimiento_*, reasigna_autor, contratos_diseno_guarda…):
--     DEFINER de postgres. 0 vistas, 0 funciones INVOKER (triggers incluidos), 0 DEFINER de otro dueño, 0 policies de
--     otras tablas o de storage que las consulten.
--   · Orden: comunicado_envios (hija) antes que comunicados (padre), aunque ninguna policy cruza entre ellas.
-- Riesgo que la comprobación textual NO ve: SQL dinámico (`execute format('… %I …', tabla)`) no nombra la tabla en el
--   cuerpo. Medido el 28-sep: las funciones de public con execute + format(%I) son todas DEFINER de postgres, así que no
--   dependen del GRANT de authenticated. Lawang: _sc_referencias_cliente, resolver_solicitud_cambio. Maestro:
--   _erp_restaura_acl, erp_aplica_modulos, impuesto_guarda, producto_guarda. Volver a mirarlo al aplicar.

-- Comprobación previa (#128 Datos 3 · #136 Seguridad 5 · consulta Seguridad+Datos 28-sep): si algo, fuera de estas
-- tablas, las lee por EXISTS/JOIN, o depende del GRANT de authenticated, NO se aplica nada. Medido el 28-sep: 0 en las
-- cuatro patas, en las dos bases.
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

  -- INVOKER de cualquier tipo, triggers incluidos, sin mirar quién la ejecuta: una de trigger corre como quien
  -- escribe, y quien escribe puede ser authenticated
  select count(*), string_agg(p.proname, ', ') into v_n, v_lista
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and not p.prosecdef and p.prosrc ~ '\m(comunicado_envios|comunicados|contratos_diseno|correcciones_datos|mantenimiento|referidos_contactos|solicitudes_colaborador)\M';
  if v_n > 0 then raise exception 'L2 revoke: funciones INVOKER que leen estas tablas (se romperían): %', v_lista; end if;

  -- DEFINER de un dueño que no es postgres ni el lector: si su dueño leía por el GRANT de authenticated, lo pierde
  select count(*), string_agg(p.proname || ' (' || pg_get_userbyid(p.proowner) || ')', ', ') into v_n, v_lista
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prosecdef
     and pg_get_userbyid(p.proowner) not in ('postgres', 'supabase_admin', 'lw_lector')
     and p.prosrc ~ '\m(comunicado_envios|comunicados|contratos_diseno|correcciones_datos|mantenimiento|referidos_contactos|solicitudes_colaborador)\M';
  if v_n > 0 then raise exception 'L2 revoke: funciones DEFINER de otro dueño que leen estas tablas: %', v_lista; end if;
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
