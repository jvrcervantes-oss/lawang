-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68); el mismo arreglo va en erp/migraciones/20261013223000_traspaso_arrastra_todo.sql
-- Sin DROP: traspasar_cliente_con_documentos conserva su firma y sus columnas de salida (create or replace conserva tambien su ACL: postgres, service_role,
--   authenticated; nada para anon). El resto son create or replace y ediciones con asercion del texto vivo; no toca filas.
--
-- TRASPASO DE CLIENTE: SIEMPRE ARRASTRA TODO (13-oct-2026, orden del owner: «el traspaso SIEMPRE arrastra todo»; y «los administradores, administradores de
-- empresa, super administradores de empresa y super admins deben poder borrar, anular, traspasar y todas las funciones para gestionar su negocio sin mi»).
--
-- QUE PASO. El owner traspaso a Ariadna la ficha de IVAN REBOLLO MARCAS y ella seguia sin ver RP00261. Sin la casilla «con documentos» la pantalla llamaba a
--   cliente_traspasa (solo la ficha). Con la casilla, traspasar_cliente_con_documentos solo movia lo cuyo creado_por era el dueno ANTERIOR de la ficha; esa ficha
--   tenia dueno NULL, asi que no se movia nada. Y aunque hubiera movido algo, habria fallado: hacia `set local session_replication_role = replica` y en
--   Supabase el rol postgres NO tiene permiso para ese parametro (medido hoy: `select set_config('session_replication_role','replica',true)` →
--   42501 permission denied; has_parameter_privilege('postgres','session_replication_role','SET') = false).
--
-- QUE HACE AHORA traspasar_cliente_con_documentos(p_client_id, p_nuevo_propietario, p_motivo):
--   · Mueve la ficha y TODOS sus contratos (por contrato_compradores, con cualquier rol) y TODAS las facturas/recibis (por contrato_id de esos contratos o por
--     client_id): cualquier autor, NULL incluido, firmados (bloqueado) y anulados incluidos, y tambien los contratos con varios compradores (el traspaso es un
--     acto explicito). Medido hoy: 55 contratos tienen mas de un comprador; en 8 de ellos las fichas de los compradores son de duenos distintos (ninguno firmado).
--   · Puerta = la de cliente_traspasa: es_admin_en_alguna_empresa() + admin_de_cliente(p, true) (exclusivo: todo el cliente dentro de mis empresas) + el nuevo
--     dueno de mi empresa si no soy admin global. Antes era super_admin_de_cliente: ahora admin, admin_empresa, super_admin_empresa y super_admin (owner).
--   · Motivo obligatorio (3+ caracteres) y una fila en correcciones_datos POR FILA movida, con el autor REAL de antes (antes se apuntaba el dueno de la ficha).
--     Los firmados ademas dejan su evento 'editado_estando_firmado' en contrato_eventos (lo pone el trigger trg_registra_edicion_privilegiada, que sigue vivo).
--   · Si la ficha ya es de esa persona NO falla: arrastra lo que falte (las fichas traspasadas solas con la pantalla vieja recuperan asi sus documentos). Solo
--     falla (22023) si ficha y documentos ya eran todos suyos.
--   · Devuelve las MISMAS columnas que antes (cambiarlas exige DROP, y en Lawang un DROP solo lo abre el owner): contratos_movidos, facturas_movidas y
--     facturas_movidas_anuladas con lo movido; los «omitidos» (firmados, de otro autor, sin autor) son 0 porque ya no se omite nada. Una devolucion mas
--     rica (firmados movidos, compartidos, ya suyos) seria un DROP + CREATE que tiene que abrir el owner: opcional, nada lo necesita.
--   · Comprobacion que falla cerrada: si un trigger BEFORE cambiara algo mas que creado_por en una fila (la marca dejaria de valer y volverian los efectos
--     colaterales), el traspaso se para (55000) con el numero del documento y no se mueve nada.
--   · El email nuevo se guarda canonico (el de usuarios, en minusculas): puede_ver_contrato compara creado_por = auth.email() sin pasar a minusculas.
--   · NO toca contrato_closer: la comision sale de contrato_closer.closer_email, no de creado_por; un traspaso de gestion no cambia quien cobra.
--
-- POR QUE NO `replica` Y QUE LO SUSTITUYE. Sin replica corren todos los triggers, y un cambio SOLO de autor los dispara igual. Medido hoy en una transaccion
--   deshecha (todos los contratos con comprador y todas las facturas, autor cambiado): 289 updates en unidades (1 con contrato_id y estado de verdad cambiados),
--   1 comision devengada nueva + 1 cambiada, 2 lineas de comision de administracion, 1 solicitud de pago nueva y 5 notificaciones; y CG00004 fallaba (23505
--   «la parcela A5 ... ya esta asignada al contrato RP00012»). Ademas fija_autor() deshace en silencio el cambio de autor de una factura si quien lo hace no es
--   es_admin() global: un admin_empresa habria visto «movidas: N» sin mover nada.
--   Arreglo: una marca de transaccion `app.via_traspaso_autor` (mismo patron que app.via_libera_reserva / app.via_carta_cobrado_recalcula) que SOLO esta
--   funcion y reasigna_autor ponen, y solo alrededor de su UPDATE de creado_por. Los cuatro triggers con efectos la respetan unicamente si ademas la fila no
--   cambia en NADA salvo creado_por: fija_autor, sincroniza_unidad_contrato, _trg_comisiones_desde_facturas y _comision_admin_cambio_recibi. Medido con
--   los cuatro parcheados (misma transaccion deshecha, sesion de un agente sin rol admin): 0 fallos, 300 contratos y 541 facturas movidos, y solo se tocan
--   contratos, facturas y contrato_eventos (100 = los firmados, su rastro). Ni el navegador ni un agente pueden poner la marca: solo llaman RPC.
--   reasigna_autor (la otra via de cambiar el autor, solo super admin) tenia los mismos efectos colaterales: pone la marca igual.
--
-- cliente_traspasa: queda como ENVOLTORIO de esta (misma puerta, mismo arrastre). La pantalla nueva ya no la llama; la vieja (v4 publicada hasta que aterrice
--   el front, y los dist de AxisWorks/demo-erp) si, sin motivo obligatorio: se le pone uno por defecto. Retirarla (revoke a authenticated) es el paso siguiente
--   cuando no le quede llamador publicado: contracts/sql/retira_cliente_traspasa_tras_aterrizar.sql.
--
-- REVERTIR: reaplicar el cuerpo de traspasar_cliente_con_documentos de 20260917083601 + 20261008301000 (create or replace, misma firma),
--   cliente_traspasa y reasigna_autor de su ultima migracion, y quitar la primera linea `if tg_op = 'UPDATE' and coalesce(current_setting('app.via_traspaso_autor'...`
--   de los cuatro triggers (create or replace con pg_get_functiondef sin esa linea). No hay datos que deshacer.

-- p_segunda: segunda edicion de la misma funcion en esta migracion (la primera ya le puso la marca)
create or replace function pg_temp.inyecta(p_fn text, p_viejo text, p_nuevo text, p_segunda boolean default false) returns void language plpgsql as $f$
declare d text; n int;
begin
  d := pg_get_functiondef(p_fn::regprocedure);
  if not p_segunda and position('app.via_traspaso_autor' in d) > 0 then
    raise exception 'inyecta %: ya lleva la marca (se aplico dos veces?)', p_fn;
  end if;
  n := (length(d) - length(replace(d, p_viejo, ''))) / length(p_viejo);
  if n <> 1 then raise exception 'inyecta %: el fragmento aparece % veces (esperaba 1): %', p_fn, n, left(p_viejo, 70); end if;
  execute replace(d, p_viejo, p_nuevo);
end $f$;

-- ── 1. Los cuatro triggers con efectos ignoran un cambio SOLO de autor hecho bajo la marca ──────────────────────────────────────────────
select pg_temp.inyecta('public.fija_autor()',
  E'begin\n  if (select auth.role()) = ''service_role''',
  E'begin\n  if tg_op = ''UPDATE'' and coalesce(current_setting(''app.via_traspaso_autor'', true), '''') = ''on'' and (to_jsonb(new) - ''creado_por'') = (to_jsonb(old) - ''creado_por'') then return new; end if;\n  if (select auth.role()) = ''service_role''');
select pg_temp.inyecta('public.sincroniza_unidad_contrato()',
  E'begin\n  if new.liberado_en is not null then',
  E'begin\n  if tg_op = ''UPDATE'' and coalesce(current_setting(''app.via_traspaso_autor'', true), '''') = ''on'' and (to_jsonb(new) - ''creado_por'') = (to_jsonb(old) - ''creado_por'') then return new; end if;\n  if new.liberado_en is not null then');
select pg_temp.inyecta('public._trg_comisiones_desde_facturas()',
  E'begin\n  if tg_op = ''DELETE'' then',
  E'begin\n  if tg_op = ''UPDATE'' and coalesce(current_setting(''app.via_traspaso_autor'', true), '''') = ''on'' and (to_jsonb(new) - ''creado_por'') = (to_jsonb(old) - ''creado_por'') then return new; end if;\n  if tg_op = ''DELETE'' then');
select pg_temp.inyecta('public._comision_admin_cambio_recibi()',
  E'begin\n  if coalesce(new.tipo, '''') <> ''recibi''',
  E'begin\n  if tg_op = ''UPDATE'' and coalesce(current_setting(''app.via_traspaso_autor'', true), '''') = ''on'' and (to_jsonb(new) - ''creado_por'') = (to_jsonb(old) - ''creado_por'') then return new; end if;\n  if coalesce(new.tipo, '''') <> ''recibi''');

-- ── 2. reasigna_autor: la misma marca alrededor de su UPDATE (sin ella, mismos efectos colaterales que arriba) ─────────────────────────────
select pg_temp.inyecta('public.reasigna_autor(text,uuid,text,text)',
  E'  if p_tabla = ''contratos'' then\n    update public.contratos set creado_por = v_nuevo where id = p_fila;',
  E'  perform set_config(''app.via_traspaso_autor'', ''on'', true);\n  if p_tabla = ''contratos'' then\n    update public.contratos set creado_por = v_nuevo where id = p_fila;');
select pg_temp.inyecta('public.reasigna_autor(text,uuid,text,text)',
  E'  return jsonb_build_object(''anterior'', v_actual, ''nuevo'', v_nuevo);',
  E'  perform set_config(''app.via_traspaso_autor'', ''off'', true);\n  return jsonb_build_object(''anterior'', v_actual, ''nuevo'', v_nuevo);', true);

-- ── 3. El traspaso que arrastra todo (misma firma y mismas columnas: create or replace) ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.traspasar_cliente_con_documentos(p_client_id uuid, p_nuevo_propietario text, p_motivo text)
 RETURNS TABLE(propietario_anterior text, contratos_movidos integer, contratos_omitidos_firmados integer, contratos_omitidos_otro_autor integer,
               contratos_omitidos_sin_autor integer, facturas_movidas integer, facturas_movidas_anuladas integer, facturas_omitidas_otro_autor integer,
               facturas_omitidas_sin_autor integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_anterior  text;
  v_nuevo     text;
  v_motivo    text := left(btrim(coalesce(p_motivo, '')), 500);
  v_quien     text := (select auth.email());
  v_contratos uuid[];
  v_ficha     boolean;
  v_impuro    text;
begin
  -- Puerta: la misma que cliente_traspasa (admin global, admin_empresa o super_admin_empresa con el cliente entero en sus empresas)
  if not public.es_admin_en_alguna_empresa() then
    raise exception 'Traspasar una ficha lo hace un administrador' using errcode = '42501';
  end if;
  if char_length(v_motivo) < 3 then
    raise exception 'Escribe el motivo del traspaso: es lo que lo explica dentro de un año' using errcode = '22023';
  end if;
  select lower(u.email) into v_nuevo from public.usuarios u
   where lower(u.email) = lower(btrim(coalesce(p_nuevo_propietario, ''))) and u.activo limit 1;
  if v_nuevo is null then
    raise exception 'El nuevo propietario no es un usuario activo del equipo' using errcode = '22023';
  end if;
  select c.propietario into v_anterior from public.clients c where c.id = p_client_id for update;
  if not found then raise exception 'Esa ficha de comprador no existe' using errcode = '22023'; end if;
  if not public.admin_de_cliente(p_client_id, true) then
    raise exception 'Traspasar una ficha lo hace un administrador de las empresas de este comprador' using errcode = '42501';
  end if;
  if not public.es_admin() and not public.comparte_empresa_con(v_nuevo) then
    raise exception 'El nuevo propietario debe ser de tu empresa' using errcode = '22023';
  end if;

  -- Lo que se mueve: todos los contratos del cliente (cualquier rol) y todos sus documentos, cerrados para escritura mientras dura el traspaso
  select coalesce(array_agg(distinct cc.contrato_id), '{}') into v_contratos
    from public.contrato_compradores cc where cc.client_id = p_client_id;
  perform 1 from public.contratos k where k.id = any (v_contratos) for update;
  perform 1 from public.facturas f where f.contrato_id = any (v_contratos) or f.client_id = p_client_id for update;
  v_ficha := lower(coalesce(v_anterior, '')) is distinct from v_nuevo;

  -- Ya no se omite nada: las columnas de «omitidos» se quedan (la firma no cambia) y valen 0
  contratos_omitidos_firmados := 0; contratos_omitidos_otro_autor := 0; contratos_omitidos_sin_autor := 0;
  facturas_omitidas_otro_autor := 0; facturas_omitidas_sin_autor := 0;

  -- La marca solo alrededor de los dos UPDATE de autor (ver cabecera de la migracion 20261013223000 del maestro y 20261013143832 de Lawang)
  perform set_config('app.via_traspaso_autor', 'on', true);

  with mov as (
    update public.contratos k set creado_por = v_nuevo
      from (select x.id, x.numero, x.creado_por as antes, to_jsonb(x) - 'creado_por' as resto from public.contratos x
             where x.id = any (v_contratos) and lower(coalesce(x.creado_por, '')) <> v_nuevo) s
     where k.id = s.id
     returning k.id, s.numero, s.antes, (to_jsonb(k) - 'creado_por') = s.resto as puro
  ), rastro as (
    insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
    select 'contratos', m.id, 'creado_por', m.antes, v_nuevo, v_motivo, v_quien from mov m
    returning 1
  )
  select count(*)::int, min(m.numero) filter (where not m.puro)
    into contratos_movidos, v_impuro
    from mov m;
  if v_impuro is not null then
    raise exception 'Traspaso parado: al cambiar el autor de % cambiaria algo mas que el autor. No se ha movido nada; avisa al estudio.', v_impuro
      using errcode = '55000';
  end if;

  with mov as (
    update public.facturas f set creado_por = v_nuevo
      from (select x.id, x.numero, x.creado_por as antes, to_jsonb(x) - 'creado_por' as resto from public.facturas x
             where (x.contrato_id = any (v_contratos) or x.client_id = p_client_id)
               and lower(coalesce(x.creado_por, '')) <> v_nuevo) s
     where f.id = s.id
     returning f.id, s.numero, s.antes, coalesce(f.anulada, false) as anulada_ya, (to_jsonb(f) - 'creado_por') = s.resto as puro
  ), rastro as (
    insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
    select 'facturas', m.id, 'creado_por', m.antes, v_nuevo, v_motivo, v_quien from mov m
    returning 1
  )
  select count(*)::int, (count(*) filter (where m.anulada_ya))::int, min(m.numero) filter (where not m.puro)
    into facturas_movidas, facturas_movidas_anuladas, v_impuro
    from mov m;
  if v_impuro is not null then
    raise exception 'Traspaso parado: al cambiar el autor de % cambiaria algo mas que el autor. No se ha movido nada; avisa al estudio.', v_impuro
      using errcode = '55000';
  end if;

  perform set_config('app.via_traspaso_autor', 'off', true);

  -- La ficha (sus triggers corren normal: la marca ya esta apagada)
  if v_ficha then
    insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
    values ('clients', p_client_id, 'propietario', v_anterior, v_nuevo, v_motivo, v_quien);
    update public.clients set propietario = v_nuevo where id = p_client_id;
  elsif contratos_movidos = 0 and facturas_movidas = 0 then
    raise exception 'Esa ficha y todos sus contratos y facturas ya son de esa persona' using errcode = '22023';
  end if;

  propietario_anterior := v_anterior;
  return next;
end;
$function$;

-- ── 4. cliente_traspasa: envoltorio (create or replace conserva su ACL) ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cliente_traspasa(p_id uuid, p_nuevo text, p_motivo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- Desde el 13-oct-2026 el traspaso SIEMPRE arrastra contratos y facturas: esta solo envuelve a traspasar_cliente_con_documentos
  -- para la pantalla vieja (que no pedia motivo). Retirada prevista: contracts/sql/retira_cliente_traspasa_tras_aterrizar.sql
  perform 1 from public.traspasar_cliente_con_documentos(p_id, p_nuevo,
    case when char_length(btrim(coalesce(p_motivo, ''))) >= 3 then p_motivo else 'traspaso de la ficha (pantalla anterior, sin motivo)' end);
  return p_id;
end $function$;

-- ── 5. Comprobacion ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
do $$
declare fn text; p record; acl text[];
begin
  foreach fn in array array['public.traspasar_cliente_con_documentos(uuid,text,text)', 'public.cliente_traspasa(uuid,text,text)'] loop
    select pr.prosecdef, pr.proconfig into p from pg_proc pr where pr.oid = to_regprocedure(fn);
    if not p.prosecdef or not ('search_path=""' = any (coalesce(p.proconfig, '{}'))) then
      raise exception 'traspaso: % no es DEFINER con search_path vacio', fn;
    end if;
    select array_agg(split_part(a::text, '=', 1) order by split_part(a::text, '=', 1)) into acl from pg_proc pr, unnest(pr.proacl) a where pr.oid = to_regprocedure(fn);
    if acl is distinct from array['authenticated', 'postgres', 'service_role'] then
      raise exception 'traspaso: el ACL de % no es {authenticated, postgres, service_role}: %', fn, acl;
    end if;
    if has_function_privilege('anon', fn, 'execute') then raise exception 'traspaso: anon ejecuta %', fn; end if;
    if position('replication_role' in pg_get_functiondef(fn::regprocedure)) > 0 then raise exception 'traspaso: % apaga triggers', fn; end if;
  end loop;
  foreach fn in array array['public.fija_autor()', 'public.sincroniza_unidad_contrato()', 'public._trg_comisiones_desde_facturas()',
                            'public._comision_admin_cambio_recibi()', 'public.reasigna_autor(text,uuid,text,text)'] loop
    if position('app.via_traspaso_autor' in pg_get_functiondef(fn::regprocedure)) = 0 then
      raise exception 'traspaso: % no lleva la marca app.via_traspaso_autor', fn;
    end if;
  end loop;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'traspasar_cliente_con_documentos') <> 1 then
    raise exception 'traspaso: quedo una sobrecarga de traspasar_cliente_con_documentos';
  end if;
end $$;
