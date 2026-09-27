-- LAW-338 · bloque L1 — CIERRE de las tres tablas bancarias al navegador.
-- APLICADA el 27-sep-2026 (MCP, nombre law338_l1_revoke_bancos) con OK del owner, tras comprobar /v4/bancos/ con su sesion. Se aplica cuando PRODUCCIÓN sirva la /v4/bancos/ que lee por
--   panel_bancos_datos (lección de B3-B5: revoke después de servir la pantalla nueva, en migración aparte).
--   Hasta entonces el invariante 8 de tools/salud_lawang.py («cada migración del repo está aplicada») la
--   marca: es el recordatorio, no un fallo.
--
-- Qué hace:
--   · revoke select on bancos_movimientos, bancos_conciliacion, bancos_perfiles from authenticated
--     ⇒ PostgREST deja de servirlas (GET /rest/v1/bancos_movimientos con sesión → 42501, no []).
--   · sus policies SELECT pasan a `TO lw_lector` (la RPC las sigue leyendo con la misma regla).
--
-- Quién las lee hoy (comprobado el 27-sep-2026 antes de escribir esto):
--   · navegador: solo intranet/v4/assets/panel-bancos.js, que ya no las lee (commit a7eabe78).
--     panel-finanzas.js llama a bancos_resumen (DEFINER-postgres): no depende del GRANT de authenticated.
--   · RPC de escritura (bancos_importar, bancos_conciliar, bancos_desconciliar, bancos_ignorar,
--     bancos_designorar, banco_perfil_guarda, _bancos_recalcula) y bancos_resumen: todas SECURITY DEFINER
--     con dueño postgres ⇒ no les afecta el revoke.
--   · 0 vistas, 0 edges, 0 pg_cron, 0 intranet clásica, 0 herramientas de la agencia.
--   · 0 policies de otras tablas o de storage que consulten estas tres (chequeo #128 Datos punto 3):
--     lo vuelve a comprobar el bloque de abajo y NO aplica nada si aparece alguna.

do $$
declare v_n int; v_lista text;
begin
  select count(*), string_agg(schemaname || '.' || tablename || '.' || policyname, ', ')
    into v_n, v_lista
    from pg_policies
   where (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ~ 'bancos_(movimientos|conciliacion|perfiles)'
     and not (schemaname = 'public' and tablename in ('bancos_movimientos', 'bancos_conciliacion', 'bancos_perfiles'));
  if v_n > 0 then raise exception 'L1 revoke: % policies de otras tablas consultan las bancarias: %', v_n, v_lista; end if;

  select count(*), string_agg(viewname, ', ') into v_n, v_lista
    from pg_views where definition ~ 'bancos_(movimientos|conciliacion|perfiles)';
  if v_n > 0 then raise exception 'L1 revoke: vistas que leen las bancarias: %', v_lista; end if;

  select count(*), string_agg(p.proname, ', ') into v_n, v_lista
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and not p.prosecdef
     and p.prosrc ~ 'bancos_(movimientos|conciliacion|perfiles)';
  if v_n > 0 then raise exception 'L1 revoke: funciones INVOKER que leen las bancarias (se romperían): %', v_lista; end if;
end $$;

revoke select on public.bancos_movimientos, public.bancos_conciliacion, public.bancos_perfiles from authenticated;

alter policy "bancos_movimientos: leer"  on public.bancos_movimientos  to lw_lector;
alter policy "bancos_conciliacion: leer" on public.bancos_conciliacion to lw_lector;
alter policy "bancos_perfiles: leer"     on public.bancos_perfiles     to lw_lector;

do $$
begin
  if has_table_privilege('authenticated', 'public.bancos_movimientos', 'select')
     or has_table_privilege('authenticated', 'public.bancos_conciliacion', 'select')
     or has_table_privilege('authenticated', 'public.bancos_perfiles', 'select') then
    raise exception 'L1 revoke: authenticated sigue leyendo alguna tabla bancaria';
  end if;
  if not (has_table_privilege('lw_lector', 'public.bancos_movimientos', 'select')
      and has_table_privilege('lw_lector', 'public.bancos_conciliacion', 'select')
      and has_table_privilege('lw_lector', 'public.bancos_perfiles', 'select')) then
    raise exception 'L1 revoke: lw_lector ha perdido la lectura (la RPC quedaría a cero)';
  end if;
end $$;
