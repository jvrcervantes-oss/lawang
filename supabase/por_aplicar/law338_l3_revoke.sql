-- LAW-338 L3 — CIERRE al navegador de las 8 tablas de comisiones, equipos de venta, condiciones y gastos.
-- SIN APLICAR (10-oct-2026). Orden seguro (lección B3-B5), y se aplica SOLO con OK del owner, como L1 y L2:
--   1. migración aditiva 20261010062215_law338_l3_comisiones_datos (APLICADA 10-oct; paridad 76 usuarios, 872
--      llamadas, 0 distintas) → 2. front aterrizado y edge `ficheros` redesplegada (gasto_estado_datos) → 3. curl a
--   lawangproperties.com: datos.js, editores.js, panel-finanzas.js, comisiones-equipo.js y asistente-contrato.js
--   servidos con lwDatos y 0 .from() de estas tablas → 4. esto, moviéndolo a supabase/migrations/ en el mismo commit.
-- ENSAYADO el 10-oct-2026 en transacción revertida (este fichero entero, como postgres, con el rol real después):
--   ataque 76 usuarios × 8 tablas → 608/608 dan 42501, 0 leen; firma (md5) de las 7 RPC de pantalla igual antes y
--   después en los 76. Comprobado tras el ensayo: authenticated conserva el SELECT (nada quedó aplicado).
-- Con ella: las 8 tablas a _CERRADAS_LAW338 de tools/salud_lawang.py y ataque 42501 por usuario × tabla.
-- Pareja del maestro: va en erp/por_aplicar/ cuando app.axisworks.studio sirva el front nuevo (no antes).
--
-- Quién las lee hoy (medido el 10-oct-2026, grep del repo entero: servido + contracts/edge + supabase/functions):
--   · navegador: NINGÚN lector directo ni embebido tras L3 (equipos_datos, condiciones_comision_datos,
--     comisiones_reparto_datos, comision_de_solicitud_datos, operacion_comisiones_datos, condicion_usos_datos,
--     finanzas_panel_datos).
--   · edges: `ficheros` leía `gastos` con el JWT del usuario para autorizar un justificante → pasa a gasto_estado_datos
--     (hay que redesplegarla ANTES de aplicar esto); su `filaDe` lee con service_role (`admin`), que no se toca.
--     Le queda UNA lectura directa con el JWT, solo si la RPC no existe (PGRST202): es para las instancias del ERP que
--     comparten el código y aún no tienen la RPC (bbm). En Lawang no corre; y si corriera tras esto, daría 42501 → 403
--     (falla cerrada). Se quita cuando bbm tenga 20261008139650 (fila en contexto/pendientes.md de la agencia).
-- Prueba de paridad y de ataque, repetible: supabase/pruebas/law338_l3_paridad.sql (antes y después de aplicar).
--   · escrituras: todas por funciones DEFINER de postgres (authenticated solo tenía SELECT): cerrar la lectura no
--     rompe ninguna escritura.
--   · Policies que consultan otra tabla del lote: condiciones_comision → equipos_venta, equipos_venta → equipo_miembros,
--     comisiones_diferencias → comisiones_devengadas, condicion_tramos → condiciones_comision. Se cierran JUNTAS: tras
--     esto solo las evalúa lw_lector, que conserva el SELECT de todas.
--   · Storage «gastos: leer justificantes» nombra 'gastos' como bucket (texto), no lee la tabla.
--   · INVOKER que las nombran: _trg_condicion_comision_manager (trigger: su proacl incluye authenticated=X, inocuo
--     porque una función de trigger no se puede llamar suelta; Seguridad 10-oct; solo
--     llega a mirar comisiones_devengadas con current_user authenticated/anon, y esos roles no escriben en
--     condiciones_comision: las escrituras van por DEFINER de postgres), condicion_tramos_reemplaza y
--     finanzas_resumen_semanal (EXECUTE solo postgres/service_role). Se exceptúan por nombre y se comprueba su ACL.
-- Riesgo que la comprobación textual NO ve: SQL dinámico. Se mira abajo (INVOKER/otro dueño con execute + format).

do $$
declare v_n int; v_lista text;
  re text := '(comisiones_devengadas|comisiones_diferencias|equipos_venta|equipo_miembros|condiciones_comision|condicion_tramos|gastos|gasto_categorias)';
  tablas text[] := array['comisiones_devengadas', 'comisiones_diferencias', 'equipos_venta', 'equipo_miembros',
                         'condiciones_comision', 'condicion_tramos', 'gastos', 'gasto_categorias'];
  invoker_ok text[] := array['_trg_condicion_comision_manager', 'condicion_tramos_reemplaza', 'finanzas_resumen_semanal'];
begin
  select count(*), string_agg(schemaname || '.' || tablename || '.' || policyname, ', ') into v_n, v_lista
    from pg_policies
   where (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ~ ('(from|join)\s+(public\.)?' || re || '\M')
     and not (schemaname = 'public' and tablename = any(tablas));
  if v_n > 0 then raise exception 'L3 revoke: % policies de otras tablas o de storage consultan estas tablas: %', v_n, v_lista; end if;

  select count(*), string_agg(schemaname || '.' || viewname, ', ') into v_n, v_lista
    from pg_views where schemaname not in ('pg_catalog', 'information_schema') and definition ~ ('\m' || re || '\M');
  if v_n > 0 then raise exception 'L3 revoke: vistas que leen estas tablas: %', v_lista; end if;

  select count(*), string_agg(p.proname, ', ') into v_n, v_lista
    from pg_proc p
   where p.pronamespace not in ('pg_catalog'::regnamespace, 'information_schema'::regnamespace) and not p.prosecdef
     and p.prosrc ~ ('\m' || re || '\M') and not (p.proname = any(invoker_ok));
  if v_n > 0 then raise exception 'L3 revoke: funciones INVOKER que leen estas tablas (se romperían): %', v_lista; end if;

  -- las exceptuadas: ni authenticated ni anon pueden ejecutarlas (el trigger no se ejecuta por EXECUTE: se comprueba
  -- que authenticated no puede escribir en su tabla, que es lo único que lo dispararía como authenticated)
  if has_function_privilege('authenticated', 'public.condicion_tramos_reemplaza(uuid,jsonb)', 'execute')
     or has_function_privilege('anon', 'public.condicion_tramos_reemplaza(uuid,jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.finanzas_resumen_semanal(date)', 'execute')
     or has_function_privilege('anon', 'public.finanzas_resumen_semanal(date)', 'execute') then
    raise exception 'L3 revoke: una INVOKER exceptuada es ejecutable por authenticated/anon';
  end if;
  -- también por columna (has_table_privilege no ve un INSERT/UPDATE concedido columna a columna; Seguridad 10-oct)
  if has_table_privilege('authenticated', 'public.condiciones_comision', 'insert,update,delete')
     or has_any_column_privilege('authenticated', 'public.condiciones_comision', 'insert')
     or has_any_column_privilege('authenticated', 'public.condiciones_comision', 'update') then
    raise exception 'L3 revoke: authenticated escribe en condiciones_comision (el trigger leería comisiones_devengadas)';
  end if;

  select count(*), string_agg(p.proname || ' (' || pg_get_userbyid(p.proowner) || ')', ', ') into v_n, v_lista
    from pg_proc p
   where p.pronamespace not in ('pg_catalog'::regnamespace, 'information_schema'::regnamespace) and p.prosecdef
     and pg_get_userbyid(p.proowner) not in ('postgres', 'supabase_admin', 'lw_lector')
     and p.prosrc ~ ('\m' || re || '\M');
  if v_n > 0 then raise exception 'L3 revoke: funciones DEFINER de otro dueño que leen estas tablas: %', v_lista; end if;

  -- solo los esquemas propios: los de Supabase (storage.search…) usan SQL dinámico sobre sus propias tablas
  select count(*), string_agg(p.proname, ', ') into v_n, v_lista
    from pg_proc p
   where p.pronamespace::regnamespace::text in ('public', 'privado')
     and (not p.prosecdef or pg_get_userbyid(p.proowner) not in ('postgres', 'supabase_admin'))
     and p.prosrc ~* 'execute\s+format' and p.prosrc ~* '%I';
  if v_n > 0 then raise exception 'L3 revoke: SQL dinámico fuera de DEFINER de postgres (no se puede descartar que lea estas tablas): %', v_lista; end if;
end $$;

-- comisiones_diferencias tiene SELECT por COLUMNAS (LAW-465): revocar el de tabla quita también el de cada columna.
revoke select on public.comisiones_devengadas, public.comisiones_diferencias, public.equipos_venta, public.equipo_miembros,
  public.condiciones_comision, public.condicion_tramos, public.gastos, public.gasto_categorias
  from authenticated;
revoke select (id, numero, devengo_id, importe, importe_vigente, importe_nuevo, base_antes, base_despues, motivo, estado,
               solicitud_id, resuelto_en, resolucion_motivo, created_at)
  on public.comisiones_diferencias from authenticated;

alter policy "comisiones_devengadas: leer" on public.comisiones_devengadas to lw_lector;
alter policy "comisiones_diferencias: leer" on public.comisiones_diferencias to lw_lector;
alter policy "equipos_venta: leer" on public.equipos_venta to lw_lector;
alter policy "equipo_miembros: leer" on public.equipo_miembros to lw_lector;
alter policy "condiciones_comision: leer" on public.condiciones_comision to lw_lector;
alter policy "condiciones: el manager lee las de su equipo" on public.condiciones_comision to lw_lector;
alter policy "condicion_tramos: leer" on public.condicion_tramos to lw_lector;
alter policy "tramos: el manager lee los de su equipo" on public.condicion_tramos to lw_lector;
alter policy "gastos: leer" on public.gastos to lw_lector;
alter policy "categorias: leer" on public.gasto_categorias to lw_lector;

do $$
declare t text;
begin
  foreach t in array array['comisiones_devengadas', 'comisiones_diferencias', 'equipos_venta', 'equipo_miembros',
                           'condiciones_comision', 'condicion_tramos', 'gastos', 'gasto_categorias'] loop
    if has_table_privilege('authenticated', 'public.' || t, 'select')
       or has_any_column_privilege('authenticated', 'public.' || t, 'select') then
      raise exception 'L3 revoke: authenticated sigue leyendo %', t;
    end if;
    if not has_any_column_privilege('lw_lector', 'public.' || t, 'select') then
      raise exception 'L3 revoke: lw_lector ha perdido la lectura de %, la RPC quedaría a cero', t;
    end if;
    if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = t and p.cmd in ('SELECT', 'ALL')
                                          and 'authenticated' = any(p.roles)) then
      raise exception 'L3 revoke: queda una policy de lectura TO authenticated en %', t;
    end if;
  end loop;
end $$;
