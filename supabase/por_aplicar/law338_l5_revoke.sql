-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- LAW-338 L5 — CIERRE al navegador de clients, documents, hilo_soporte, mensajes_comprador, portal_accesos, notificaciones,
-- correos_enviados y la vista documentos_desactualizados. SIN APLICAR (escrito el 16-oct-2026, sesión lecturas-servidor-2).
-- QUITA ACCESO: se aplica SOLO con la válvula del owner (la gestiona agencia-c0), como L1-L3.
-- ORDEN (lección B3-B5; condición del revisor del 16-oct en el encargo):
--   1. migración aditiva 20261016063536_law338_l5_compradores_datos APLICADA en la viva (las 8 *_datos + las 3 búsquedas DEFINER)
--      y supabase_fetch_seguro.py → 2. front y edges aterrizados (`aterriza.py --edge ficheros-kyc,portal-invitar,asistente-peticiones`)
--   → 3. get_edge_function de las 3 edges con el código nuevo (sha de contracts/edge/*/index.ts y supabase/functions/ficheros-kyc) y curl
--      de datos.js, editores.js, emitir.js, avisos.js, operaciones-cuentas.js, ficha_divergencia.js, contracts/app.html e
--      intranet/facturas con su ?v= nuevo y 0 .from() de estas tablas → 4. pg_stat_statements: 0 formas NUEVAS de `authenticated`
--      sobre estas tablas desde el aterrizaje → 5. ensayo de esto en transacción revertida: paridad (supabase/pruebas/law338_l5_paridad.sql)
--      y ATAQUE usuario × tabla → 42501, incluida la edge bot-agentes (llama a bot_pendientes con el JWT) → 6. OK del owner →
--   7. apply_migration(name='law338_l5_revoke', query=este fichero); git mv a supabase/migrations/<versión real>_law338_l5_revoke.sql;
--      las 8 a _CERRADAS_LAW338 de tools/salud_lawang.py (agencia) en el mismo aterrizaje; supabase_fetch_seguro.py.
--   8. GET /rest/v1/<tabla> con sesión de agente → 42501, verificador de las pantallas (Compradores, Soporte, campana, editor de
--      documentos, emitir, cajón de la operación, Operaciones, «Ficha ≠», registro de envíos, portal) y salud_lawang.py.
-- Quién las lee tras L5 (medido el 16-oct en la viva y en el repo):
--   · navegador: ninguna lectura directa ni embebida (8 *_datos de dueño lw_lector).
--   · edges: avisos-manager, libera-reservas-vencidas, portal-invitar y ficheros-kyc (`admin`) leen con service_role: no se tocan.
--   · policies de OTRAS tablas que consultan estas: solo «notas: las de las fichas que ves» de cliente_notas (→ clients), que evalúa
--     únicamente lw_lector (cliente_notas no tiene GRANT a authenticated). Ninguna de storage. Ninguna vista ajena.
--   · INVOKER que las nombran: bot_pendientes, clientes_busca y contratos_busca (DEFINER-lw_lector desde 20261016063536; la guarda
--     de abajo lo exige) y _portal_rechazo (sin EXECUTE para authenticated ni anon: se exceptúa y se comprueba su ACL).
--   · escrituras: authenticated no escribe en ninguna de las 7 (medido): todas van por DEFINER de postgres.
-- VUELTA ATRÁS (exacta):
--   grant select on public.clients, public.documents, public.hilo_soporte, public.mensajes_comprador, public.portal_accesos,
--     public.notificaciones, public.correos_enviados, public.documentos_desactualizados to authenticated;
--   alter policy "cada uno lo suyo, el manager lo de su proyecto, admin todo" on public.clients to authenticated, lw_lector;
--   alter policy "correos: leer lo propio o del contrato visible" on public.correos_enviados to authenticated, lw_lector;
--   alter policy "agentes leen documentos de sus compradores" on public.documents to authenticated, lw_lector;
--   alter policy "comprador lee su estado" on public.hilo_soporte to authenticated, lw_lector;
--   alter policy "equipo lee los tickets" on public.hilo_soporte to authenticated, lw_lector;
--   alter policy "comprador ve su hilo de mensajes" on public.mensajes_comprador to authenticated, lw_lector;
--   alter policy "equipo ve hilos de mensajes" on public.mensajes_comprador to authenticated, lw_lector;
--   alter policy "cada uno ve lo suyo, el admin todo" on public.notificaciones to public;
--   alter policy "agentes ven accesos del portal" on public.portal_accesos to authenticated, lw_lector;
-- Pareja del maestro: fila AXW-357 [b10-l5-cierre-maestro] (cuando bbm y la demo sirvan la v4 que llama a las gemelas).

do $$
declare v_n int; v_lista text;
  re text := '(clients|documents|hilo_soporte|mensajes_comprador|portal_accesos|notificaciones|correos_enviados|documentos_desactualizados)';
  tablas text[] := array['clients', 'documents', 'hilo_soporte', 'mensajes_comprador', 'portal_accesos', 'notificaciones',
                         'correos_enviados', 'documentos_desactualizados'];
begin
  -- la aditiva tiene que estar: sin ella las pantallas se quedan a cero
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prosecdef and pg_get_userbyid(p.proowner) = 'lw_lector'
     and p.proname in ('clientes_lista_datos', 'comprador_ficha_datos', 'operacion_compradores_datos', 'operaciones_compradores_datos',
                       'soporte_datos', 'notificaciones_datos', 'correos_registro_datos', 'documentos_desactualizados_datos',
                       'clientes_busca', 'contratos_busca', 'bot_pendientes');
  if v_n <> 11 then raise exception 'L5 revoke: faltan las RPC de 20261016063536 (DEFINER-lw_lector: % de 11)', v_n; end if;

  select count(*), string_agg(schemaname || '.' || tablename || '.' || policyname, ', ') into v_n, v_lista
    from pg_policies
   where (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ~ ('(from|join)\s+(public\.)?' || re || '\M')
     and not (schemaname = 'public' and tablename = any(tablas))
     and not (schemaname = 'public' and tablename = 'cliente_notas' and policyname = 'notas: las de las fichas que ves');
  if v_n > 0 then raise exception 'L5 revoke: % policies de otras tablas o de storage consultan estas tablas: %', v_n, v_lista; end if;
  if has_table_privilege('authenticated', 'public.cliente_notas', 'select')
     or has_any_column_privilege('authenticated', 'public.cliente_notas', 'select') then
    raise exception 'L5 revoke: authenticated lee cliente_notas (su policy consulta clients)';
  end if;

  select count(*), string_agg(schemaname || '.' || viewname, ', ') into v_n, v_lista
    from pg_views where schemaname not in ('pg_catalog', 'information_schema') and viewname <> 'documentos_desactualizados'
     and definition ~ ('\m' || re || '\M');
  if v_n > 0 then raise exception 'L5 revoke: vistas que leen estas tablas: %', v_lista; end if;

  select count(*), string_agg(p.proname, ', ') into v_n, v_lista
    from pg_proc p
   where p.pronamespace not in ('pg_catalog'::regnamespace, 'information_schema'::regnamespace) and not p.prosecdef
     and p.prosrc ~ ('\m' || re || '\M') and p.proname <> '_portal_rechazo';
  if v_n > 0 then raise exception 'L5 revoke: funciones INVOKER que leen estas tablas (se romperían): %', v_lista; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_portal_rechazo'
              and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))) then
    raise exception 'L5 revoke: _portal_rechazo (INVOKER) es ejecutable por authenticated/anon';
  end if;

  select count(*), string_agg(p.proname || ' (' || pg_get_userbyid(p.proowner) || ')', ', ') into v_n, v_lista
    from pg_proc p
   where p.pronamespace not in ('pg_catalog'::regnamespace, 'information_schema'::regnamespace) and p.prosecdef
     and pg_get_userbyid(p.proowner) not in ('postgres', 'supabase_admin', 'lw_lector')
     and p.prosrc ~ ('\m' || re || '\M');
  if v_n > 0 then raise exception 'L5 revoke: funciones DEFINER de otro dueño que leen estas tablas: %', v_lista; end if;

  select count(*), string_agg(c.relname, ', ') into v_n, v_lista
    from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname = any(tablas) and c.relkind = 'r'
     and (has_table_privilege('authenticated', c.oid, 'insert,update,delete')
          or has_any_column_privilege('authenticated', c.oid, 'insert') or has_any_column_privilege('authenticated', c.oid, 'update'));
  if v_n > 0 then raise exception 'L5 revoke: authenticated escribe en % (un RETURNING o un disparador leería como él)', v_lista; end if;

  select count(*), string_agg(p.proname, ', ') into v_n, v_lista
    from pg_proc p
   where p.pronamespace::regnamespace::text in ('public', 'privado')
     and (not p.prosecdef or pg_get_userbyid(p.proowner) not in ('postgres', 'supabase_admin'))
     and p.prosrc ~* 'execute\s+format' and p.prosrc ~* '%I';
  if v_n > 0 then raise exception 'L5 revoke: SQL dinámico fuera de DEFINER de postgres (no se puede descartar que lea estas tablas): %', v_lista; end if;
end $$;

revoke select on public.clients, public.documents, public.hilo_soporte, public.mensajes_comprador, public.portal_accesos,
  public.notificaciones, public.correos_enviados, public.documentos_desactualizados
  from authenticated, anon;

alter policy "cada uno lo suyo, el manager lo de su proyecto, admin todo" on public.clients to lw_lector;
alter policy "correos: leer lo propio o del contrato visible" on public.correos_enviados to lw_lector;
alter policy "agentes leen documentos de sus compradores" on public.documents to lw_lector;
alter policy "comprador lee su estado" on public.hilo_soporte to lw_lector;
alter policy "equipo lee los tickets" on public.hilo_soporte to lw_lector;
alter policy "comprador ve su hilo de mensajes" on public.mensajes_comprador to lw_lector;
alter policy "equipo ve hilos de mensajes" on public.mensajes_comprador to lw_lector;
alter policy "cada uno ve lo suyo, el admin todo" on public.notificaciones to lw_lector;
alter policy "agentes ven accesos del portal" on public.portal_accesos to lw_lector;

-- los comentarios de 20261015062313 decían «INVOKER: la RLS de quien pide»; desde 20261016063536 son DEFINER-lw_lector
comment on function public.contratos_busca(text) is
  'Busqueda sin tildes (15-oct-2026): ventas para el asistente de contrato (asistente-contrato.js). DEFINER de lw_lector desde LAW-338 L5 (16-oct-2026): decide la RLS de lw_lector con uid_sesion() de quien pide. Menos de 2 letras = las 10 ultimas.';
comment on function public.clientes_busca(text) is
  'Busqueda sin tildes (15-oct-2026): clientes por nombre, pasaporte, correo o telefono para la edge asistente-peticiones. DEFINER de lw_lector desde LAW-338 L5 (16-oct-2026): decide la RLS de lw_lector con uid_sesion() de quien pide.';

do $$
declare t text;
begin
  foreach t in array array['clients', 'documents', 'hilo_soporte', 'mensajes_comprador', 'portal_accesos', 'notificaciones',
                           'correos_enviados', 'documentos_desactualizados'] loop
    if has_table_privilege('authenticated', 'public.' || t, 'select')
       or has_any_column_privilege('authenticated', 'public.' || t, 'select')
       or has_any_column_privilege('anon', 'public.' || t, 'select') then
      raise exception 'L5 revoke: authenticated o anon siguen leyendo %', t;
    end if;
    if not has_any_column_privilege('lw_lector', 'public.' || t, 'select') then
      raise exception 'L5 revoke: lw_lector ha perdido la lectura de %, la RPC quedaría a cero', t;
    end if;
    if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = t and p.cmd in ('SELECT', 'ALL')
                                          and ('authenticated' = any(p.roles) or 'public' = any(p.roles))) then
      raise exception 'L5 revoke: queda una policy de lectura TO authenticated/public en %', t;
    end if;
  end loop;
end $$;
