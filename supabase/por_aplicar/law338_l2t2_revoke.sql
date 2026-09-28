-- LAW-338 L2, tanda 2 — CIERRE al navegador de 9 tablas que ya no lee ninguna pantalla.
-- Pareja del maestro: erp/por_aplicar/b10a_l2t2_revoke.sql (solo las 4 que existen allí; espera a republicar el ERP del
--   estudio, AXW-67). Lawang es independiente del maestro desde el 28-sep: esto se aplica por su lado.
-- SIN APLICAR. Orden seguro (lección B3-B5): la migración aditiva 20260928045443_law338_l2_tanda2 → aterriza el front →
--   curl a lawangproperties.com: entities.js, creatividades.js, panel-gastos.js y panel-creatividades.js servidos con
--   lwDatos y 0 .from() de estas tablas → esto.
-- Con ella: las 9 tablas a _CERRADAS_LAW338 de tools/salud_lawang.py y ataque 42501 por usuario × tabla.
--
-- Quién las lee hoy (medido el 28-sep-2026, grep del repo entero: servido + contracts/edge + supabase/functions):
--   · navegador: NINGÚN lector directo ni embebido tras la tanda 2 (entities.js → apoderados_datos/firmantes_datos;
--     panel-gastos.js → gastos_panel_datos/gasto_historial_datos; creatividades.js → creatividades_datos/
--     creatividad_datos/bloque_legal_datos). creatividad_fotos, creatividad_modelos y modelos_precios_log no tenían lector.
--   · edges: `ficheros` lee creatividades con service_role (`admin`); las compartidos.generated.ts de firma-submit y
--     factura-vencimiento llevan entities.js dentro pero NO llaman a los cargadores. Ninguna edge las lee con el JWT del
--     usuario (a diferencia de bot_bloqueos/bot_fuentes/contrato_documentos, que bot-agentes sí lee así: no entran aquí).
--   · RPC de lectura: dossier_datos y las 7 de la tanda 2, dueño lw_lector ⇒ leen con el SELECT del lector y la policy
--     TO lw_lector. Storage «creatividades: leer ficheros» va por privado.creatividad_ve_fichero (DEFINER de postgres).
--   · Las policies de creatividad_fotos/creatividad_modelos consultan creatividades: se cierran JUNTAS (hijas antes).
--   · `_creatividad_sin_permiso` (INVOKER) nombra «creatividades» solo en un texto de error: no lee ninguna tabla.
-- Funciones: se miran en TODOS los esquemas (no solo public; revisor 28-sep: existe `privado`). Medido: fuera de public
--   solo privado.creatividad_ve_fichero las nombra, y es DEFINER de postgres.
-- Riesgo que la comprobación textual NO ve: SQL dinámico (`execute format('… %I …', tabla)`). Medido el 28-sep (tanda 1):
--   todas las de public con execute + format(%I) son DEFINER de postgres. Volver a mirarlo al aplicar.

do $$
declare v_n int; v_lista text;
  re text := '(apoderados_hak_sewa|firmantes_cred|creatividad_fotos|creatividad_modelos|creatividades|bloques_legales|modelos_precios_log|gastos_log|proveedores)';
  tablas text[] := array['apoderados_hak_sewa', 'firmantes_cred', 'creatividad_fotos', 'creatividad_modelos', 'creatividades',
                         'bloques_legales', 'modelos_precios_log', 'gastos_log', 'proveedores'];
begin
  select count(*), string_agg(schemaname || '.' || tablename || '.' || policyname, ', ') into v_n, v_lista
    from pg_policies
   where (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ~ ('(from|join)\s+(public\.)?' || re || '\M')
     and not (schemaname = 'public' and tablename = any(tablas));
  if v_n > 0 then raise exception 'L2t2 revoke: % policies de otras tablas o de storage consultan estas tablas: %', v_n, v_lista; end if;

  select count(*), string_agg(viewname, ', ') into v_n, v_lista
    from pg_views where schemaname = 'public' and definition ~ ('\m' || re || '\M');
  if v_n > 0 then raise exception 'L2t2 revoke: vistas que leen estas tablas: %', v_lista; end if;

  select count(*), string_agg(p.proname, ', ') into v_n, v_lista
    from pg_proc p
   where p.pronamespace not in ('pg_catalog'::regnamespace, 'information_schema'::regnamespace) and not p.prosecdef and p.prosrc ~ ('\m' || re || '\M')
     and p.proname <> '_creatividad_sin_permiso';
  if v_n > 0 then raise exception 'L2t2 revoke: funciones INVOKER que leen estas tablas (se romperían): %', v_lista; end if;

  select count(*), string_agg(p.proname || ' (' || pg_get_userbyid(p.proowner) || ')', ', ') into v_n, v_lista
    from pg_proc p
   where p.pronamespace not in ('pg_catalog'::regnamespace, 'information_schema'::regnamespace) and p.prosecdef
     and pg_get_userbyid(p.proowner) not in ('postgres', 'supabase_admin', 'lw_lector')
     and p.prosrc ~ ('\m' || re || '\M');
  if v_n > 0 then raise exception 'L2t2 revoke: funciones DEFINER de otro dueño que leen estas tablas: %', v_lista; end if;
end $$;

revoke select on public.creatividad_fotos, public.creatividad_modelos, public.creatividades, public.bloques_legales,
  public.apoderados_hak_sewa, public.firmantes_cred, public.modelos_precios_log, public.gastos_log, public.proveedores
  from authenticated;

alter policy "creatividad_fotos: leer" on public.creatividad_fotos to lw_lector;
alter policy "creatividad_modelos: leer" on public.creatividad_modelos to lw_lector;
alter policy "creatividades: leer" on public.creatividades to lw_lector;
alter policy "bloques_legales: leer" on public.bloques_legales to lw_lector;
alter policy "apoderados hak sewa: solo con sesion" on public.apoderados_hak_sewa to lw_lector;
alter policy "firmantes cred: solo con sesion" on public.firmantes_cred to lw_lector;
alter policy "admins leen el historial de precios" on public.modelos_precios_log to lw_lector;
alter policy "gastos_log: leer" on public.gastos_log to lw_lector;
alter policy "proveedores: leer" on public.proveedores to lw_lector;

do $$
declare t text;
begin
  foreach t in array array['apoderados_hak_sewa', 'firmantes_cred', 'creatividad_fotos', 'creatividad_modelos', 'creatividades',
                           'bloques_legales', 'modelos_precios_log', 'gastos_log', 'proveedores'] loop
    if has_table_privilege('authenticated', 'public.' || t, 'select') then
      raise exception 'L2t2 revoke: authenticated sigue leyendo %', t;
    end if;
    if not has_table_privilege('lw_lector', 'public.' || t, 'select') then
      raise exception 'L2t2 revoke: lw_lector ha perdido la lectura de %, la RPC quedaría a cero', t;
    end if;
    if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = t and p.cmd in ('SELECT', 'ALL')
                                          and 'authenticated' = any(p.roles)) then
      raise exception 'L2t2 revoke: queda una policy de lectura TO authenticated en %', t;
    end if;
  end loop;
end $$;
