-- Prueba de proyecto-por-id en la intranet (15-oct-2026, LAW-428 fase 2B, migración 20261015214000_proyecto_por_id_intranet.sql).
-- Cada gemela, con la SESIÓN del rol real (`set local role authenticated` + claims, como la pantalla), contra su vieja por nombre:
--   B1-B4  borrar_proyecto_por_id: el agente no borra (42501, la fila sigue); el super admin de la empresa borra uno vacío; uno con
--          parcelas no se borra (23503); un id que no existe da 42501 al super de empresa (no revela si existe).
--   V1-V4  proyecto_vinculos_por_id_datos: el admin recibe lo mismo que la vieja; el agente ya NO (42501; la vieja sí se lo daba,
--          Seguridad #381); anon no la ejecuta; dueño lw_lector.
--   R1-R4  renombrar_proyecto_por_id: el agente no renombra; el admin sí, por id (proyectos.nombre cambia y el espejo de unidades le
--          sigue); id inexistente = P0002; mismo nombre = sin_cambios.
--   T1-T4  parcela_traspaso_estado_por_unidad = la vieja (proyecto+código) para la parcela con Carta y para una sin Carta; un agente
--          sin el proyecto, 42501 por las dos.
--   C1-C6  el abono de la Carta en un Bloqueo: alta por contrato_guarda como el agente (sin proyecto_id: lo pone el espejo DESPUÉS del
--          disparador) → carta_cobrado_importe calculado y apunte en carta_cobrado_aplicado; la vieja y la gemela dan los mismos datos
--          para ese Bloqueo; alta directa sin proyecto_id y con el nombre (el camino del disparador antes del espejo) también; un
--          Bloqueo sin proyecto resoluble no entra; carta_cobrado_recalcula (admin) devuelve el mismo abono.
--   O1-O2  obra_contratos_afectados / obra_datos_cobro: el admin pasa el permiso (puede_proyecto_id), el agente de fuera no (42501).
--   G1-G3  proyecto_guarda: cambiar el slug se rechaza antes de tocar nada (22023); mandar el mismo slug con otro cambio guarda.
--   P1-P2  permisos: las 4 de la intranet, authenticated sí y anon/service_role no; privado.carta_cobrado_calcula_por_id, nadie.
-- MONTAJE: filas propias marcadas ZZ-PI. Lo cobrado de la Carta se fija sustituyendo, SOLO dentro de esta transacción de rama,
-- _contrato_cobrado_interno por una que da 5.000 a esa Carta y 0 al resto (el cálculo de lo cobrado no es lo que se prueba aquí).
-- En rama los números de serie no importan (la rama se borra); no corre en la viva (guardia erp.en_rama).
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada línea acaba en «→ ok» o «→ FALLA». Todo se deshace con el raise final.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
create or replace function pg_temp.x(p_sql text) returns text language plpgsql as $f$
declare t text;
begin
  execute p_sql into t;
  return coalesce(t, 'OK');
exception when others then
  return 'ERR' || sqlstate || ':' || left(sqlerrm, 200);
end $f$;
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then json_build_object('role', p_rol)::text else
          json_build_object('sub', p_uid, 'role', p_rol, 'email', p_email)::text end, true);
  execute 'set local role ' || p_rol;
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(t, '(null)');
end $f$;
create or replace function pg_temp.err(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then substr(t, 4, 5) end $f$;
-- el p_contrato que manda la pantalla a contrato_guarda (contracts/app.html, contractPayload) para un Bloqueo de Parcela
create or replace function pg_temp.bloqueo(p_proy_nombre text, p_codigo text) returns jsonb language sql as $f$
  select jsonb_build_object('tipo', 'reserva_parcela',
           'datos', jsonb_build_object('hitos', '[]'::jsonb,
                      'fields', jsonb_build_object('proyecto_nombre', p_proy_nombre, 'parcela_codigo', p_codigo, 'moneda', 'EUR',
                                                   'precio_total', '20000', 'sociedad_firmante', 'zz_pi1',
                                                   'adq1_nombre', 'ZZ-PI Comprador', 'adq1_pasaporte', 'ZZPI0001')))
$f$;

do $todo$
declare
  r text := ''; v text; v2 text; n bigint;
  p1 uuid; pv uuid; pr uuid; u1 uuid; u2 uuid; u3 uuid; k uuid; k2 uuid; b1 uuid;
  su uuid := gen_random_uuid(); c_su constant text := 'zz-pi-super@prueba.invalid';
  ad uuid := gen_random_uuid(); c_ad constant text := 'zz-pi-admin@prueba.invalid';
  ag uuid := gen_random_uuid(); c_ag constant text := 'zz-pi-agente@prueba.invalid';
  fx uuid := gen_random_uuid(); c_fx constant text := 'zz-pi-fuera@prueba.invalid';
  c_p1 constant text := 'ZZ-PI Proyecto 1';
  c_fin constant text := 'FIN DE PRUEBAS PROYECTO POR ID INTRANET (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS PROYECTO POR ID INTRANET:%', E'\nP0 esta prueba monta filas y sustituye _contrato_cobrado_interno: solo corre en rama → FALLA';
  end if;

  -- ============================================================ montaje (como postgres)
  insert into public.sociedades (clave, label, razon, domicilio) values ('zz_pi1', 'ZZ-PI 1', 'ZZ-PI PT 1', 'ZZ-domicilio') on conflict (clave) do nothing;
  insert into public.empresas (clave, nombre) values ('zz_pi_e1', 'ZZ-PI Empresa 1');
  update public.empresas set sociedad_clave = 'zz_pi1' where clave = 'zz_pi_e1';
  insert into public.proyectos (nombre, slug, empresa, activo) values (c_p1, 'zz-pi-proyecto-1', 'zz_pi_e1', true) returning id into p1;
  insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-PI Vacio', 'zz-pi-vacio', 'zz_pi_e1', true) returning id into pv;
  insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-PI Renombrar', 'zz-pi-renombrar', 'zz_pi_e1', true) returning id into pr;
  insert into public.unidades (codigo, proyecto, proyecto_id, tipo, superficie_m2, precio_suelo, precio, moneda, estado)
       values ('ZZPI-1', c_p1, p1, 'parcela', 300, 20000, 20000, 'EUR', 'disponible') returning id into u1;
  insert into public.unidades (codigo, proyecto, proyecto_id, tipo, superficie_m2, precio_suelo, precio, moneda, estado)
       values ('ZZPI-2', c_p1, p1, 'parcela', 300, 20000, 20000, 'EUR', 'disponible') returning id into u2;
  insert into public.unidades (codigo, proyecto, proyecto_id, tipo, superficie_m2, precio_suelo, precio, moneda, estado)
       values ('ZZPI-3', c_p1, p1, 'parcela', 300, 20000, 20000, 'EUR', 'disponible') returning id into u3;
  insert into public.unidades (codigo, proyecto, proyecto_id, tipo, superficie_m2, precio_suelo, precio, moneda, estado)
       values ('ZZPI-R', 'ZZ-PI Renombrar', pr, 'parcela', 300, 20000, 20000, 'EUR', 'disponible');
  insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, datos, creado_por)
       values ('ZZPI-CR1', 'carta_reserva', p1, c_p1, 'EUR', 5000,
               jsonb_build_object('hitos', '[]'::jsonb, 'fields', jsonb_build_object('proyecto_nombre', c_p1, 'parcela_codigo', 'ZZPI-1',
                 'moneda', 'EUR', 'sociedad_firmante', 'zz_pi1', 'adq1_nombre', 'ZZ-PI Comprador', 'adq1_pasaporte', 'ZZPI0001')),
               'zz-pi@prueba.invalid') returning id into k;
  insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, datos, creado_por)
       values ('ZZPI-CR2', 'carta_reserva', p1, c_p1, 'EUR', 5000,
               jsonb_build_object('hitos', '[]'::jsonb, 'fields', jsonb_build_object('proyecto_nombre', c_p1, 'parcela_codigo', 'ZZPI-3',
                 'moneda', 'EUR', 'sociedad_firmante', 'zz_pi1', 'adq1_nombre', 'ZZ-PI Comprador', 'adq1_pasaporte', 'ZZPI0001')),
               'zz-pi@prueba.invalid') returning id into k2;
  update public.unidades set contrato_id = k, estado = 'reservada' where id = u1;
  update public.unidades set contrato_id = k2, estado = 'reservada' where id = u3;
  execute format($s$create or replace function public._contrato_cobrado_interno(p_contrato_id uuid, p_moneda text default null)
                    returns numeric language sql stable as $b$select case when p_contrato_id in (%L::uuid, %L::uuid) then 5000::numeric else 0::numeric end$b$$s$, k, k2);
  insert into auth.users (id, instance_id, email, aud, role) values
    (su, '00000000-0000-0000-0000-000000000000', c_su, 'authenticated', 'authenticated'),
    (ad, '00000000-0000-0000-0000-000000000000', c_ad, 'authenticated', 'authenticated'),
    (ag, '00000000-0000-0000-0000-000000000000', c_ag, 'authenticated', 'authenticated'),
    (fx, '00000000-0000-0000-0000-000000000000', c_fx, 'authenticated', 'authenticated');
  insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
    (su, c_su, 'ZZ-PI Super', 'super_admin_empresa', 'empresa', '{zz_pi_e1}', '{}'::uuid[], '{}'::uuid[], '{contratos}', '{}', true),
    (ad, c_ad, 'ZZ-PI Admin', 'admin', 'global', '{}', '{}'::uuid[], '{}'::uuid[], '{contratos,obra}', '{}', true),
    (ag, c_ag, 'ZZ-PI Agente', 'agente', 'global', '{}', array[p1, pv, pr], '{}'::uuid[], '{contratos}', '{reserva_parcela,carta_reserva}', true),
    (fx, c_fx, 'ZZ-PI Fuera', 'agente', 'global', '{}', '{}'::uuid[], '{}'::uuid[], '{contratos,obra}', '{reserva_parcela,carta_reserva}', true);
  r := r || pg_temp.l(true, 'P montaje: empresa con sociedad, 3 proyectos, parcelas ZZPI-1 y ZZPI-3 con su Carta (5.000 cobrados cada una), 4 personas');

  -- ============================================================ B. borrar_proyecto_por_id
  v := pg_temp.val(ag, c_ag, format('select public.borrar_proyecto_por_id(%L)::text', pv));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and exists (select 1 from public.proyectos where id = pv), 'B1 el agente no borra y el proyecto sigue (' || left(v, 90) || ')');
  v := pg_temp.val(su, c_su, format('select public.borrar_proyecto_por_id(%L)::text', p1));
  r := r || pg_temp.l(pg_temp.err(v) = '23503' and v ~ 'unidad', 'B2 con parcelas no se borra (' || left(v, 110) || ')');
  v := pg_temp.val(su, c_su, format('select public.borrar_proyecto_por_id(%L)::text', gen_random_uuid()));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'B3 id inexistente: el super de empresa recibe 42501, no «no existe» (' || left(v, 90) || ')');
  v := pg_temp.val(su, c_su, format('select public.borrar_proyecto_por_id(%L)::text', pv));
  r := r || pg_temp.l(v !~ '^ERR' and not exists (select 1 from public.proyectos where id = pv)
                      and exists (select 1 from public.proyectos_borrados where nombre = 'ZZ-PI Vacio'),
                      'B4 el super admin de la empresa borra el vacío, con su apunte en proyectos_borrados (' || left(v, 90) || ')');

  -- ============================================================ V. proyecto_vinculos_por_id_datos
  v  := pg_temp.val(ad, c_ad, format('select public.proyecto_vinculos_por_id_datos(%L)::text', p1));
  v2 := pg_temp.val(ad, c_ad, format('select public.proyecto_vinculos_datos(%L)::text', c_p1));
  r := r || pg_temp.l(v = v2 and v !~ '^ERR' and (v::jsonb ->> 'unidades') = '3', 'V1 admin: gemela = vieja (' || left(v, 90) || ' / ' || left(v2, 60) || ')');
  v  := pg_temp.val(ag, c_ag, format('select public.proyecto_vinculos_por_id_datos(%L)::text', p1));
  v2 := pg_temp.val(ag, c_ag, format('select public.proyecto_vinculos_datos(%L)::text', c_p1));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v2 !~ '^ERR', 'V2 el agente ya no cuenta lo de un proyecto (la vieja sí se lo daba) (' || left(v, 90) || ')');
  v := pg_temp.val(null, null, format('select public.proyecto_vinculos_por_id_datos(%L)::text', p1), 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'V3 anon no la ejecuta (' || left(v, 90) || ')');
  r := r || pg_temp.l((select pg_get_userbyid(proowner) from pg_proc where oid = 'public.proyecto_vinculos_por_id_datos(uuid)'::regprocedure) = 'lw_lector',
                      'V4 dueño lw_lector, como la vieja');

  -- ============================================================ R. renombrar_proyecto_por_id
  v := pg_temp.val(ag, c_ag, format('select public.renombrar_proyecto_por_id(%L, %L)::text', pr, 'ZZ-PI Renombrado'));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and (select nombre from public.proyectos where id = pr) = 'ZZ-PI Renombrar', 'R1 el agente no renombra (' || left(v, 90) || ')');
  v := pg_temp.val(ad, c_ad, format('select public.renombrar_proyecto_por_id(%L, %L)::text', pr, 'ZZ-PI Renombrado'));
  r := r || pg_temp.l(v !~ '^ERR' and (select nombre from public.proyectos where id = pr) = 'ZZ-PI Renombrado'
                      and (select proyecto from public.unidades where codigo = 'ZZPI-R' and proyecto_id = pr) = 'ZZ-PI Renombrado',
                      'R2 el admin renombra por id y el espejo de unidades le sigue (' || left(v, 120) || ')');
  v := pg_temp.val(ad, c_ad, format('select public.renombrar_proyecto_por_id(%L, %L)::text', gen_random_uuid(), 'ZZ-PI X'));
  r := r || pg_temp.l(pg_temp.err(v) = 'P0002', 'R3 id inexistente: P0002 (' || left(v, 90) || ')');
  v := pg_temp.val(ad, c_ad, format('select public.renombrar_proyecto_por_id(%L, %L)::text', pr, 'ZZ-PI Renombrado'));
  r := r || pg_temp.l(v = '{"sin_cambios": true}', 'R4 el mismo nombre: sin cambios (' || left(v, 90) || ')');

  -- ============================================================ T. parcela_traspaso_estado_por_unidad
  v  := pg_temp.val(ag, c_ag, format('select public.parcela_traspaso_estado_por_unidad(%L, %L::text[])::text', u1, '{zzpi0001}'));
  v2 := pg_temp.val(ag, c_ag, format('select public.parcela_traspaso_estado(%L, %L, %L::text[])::text', c_p1, 'ZZPI-1', '{zzpi0001}'));
  r := r || pg_temp.l(v = v2 and v ~ 'ZZPI-CR1', 'T1 la parcela con Carta: gemela = vieja (' || left(v, 90) || ' / ' || left(v2, 60) || ')');
  v  := pg_temp.val(ag, c_ag, format('select public.parcela_traspaso_estado_por_unidad(%L, %L::text[])::text', u2, '{zzpi0001}'));
  v2 := pg_temp.val(ag, c_ag, format('select public.parcela_traspaso_estado(%L, %L, %L::text[])::text', c_p1, 'ZZPI-2', '{zzpi0001}'));
  r := r || pg_temp.l(v = v2 and v = '(null)', 'T2 sin Carta: null por las dos (' || left(v, 60) || ' / ' || left(v2, 60) || ')');
  v  := pg_temp.val(fx, c_fx, format('select public.parcela_traspaso_estado_por_unidad(%L, %L::text[])::text', u1, '{zzpi0001}'));
  v2 := pg_temp.val(fx, c_fx, format('select public.parcela_traspaso_estado(%L, %L, %L::text[])::text', c_p1, 'ZZPI-1', '{zzpi0001}'));
  r := r || pg_temp.l(v like 'ERR%' and v2 like 'ERR%', 'T3 el agente sin el proyecto, rechazado por las dos (' || left(v, 80) || ')');
  v := pg_temp.val(fx, c_fx, format('select public.parcela_traspaso_estado_por_unidad(%L, %L::text[])::text', gen_random_uuid(), '{zzpi0001}'));
  r := r || pg_temp.l(v like 'ERR%', 'T4 una unidad que no existe: el mismo rechazo, no revela nada (' || left(v, 80) || ')');

  -- ============================================================ C. el abono de la Carta en el Bloqueo (dinero)
  v := pg_temp.val(ag, c_ag, format('select (public.contrato_guarda(null, %L::jsonb))->>''id''', pg_temp.bloqueo(c_p1, 'ZZPI-1')));
  r := r || pg_temp.l(v !~ '^ERR', 'C1 el agente da de alta el Bloqueo por contrato_guarda, sin proyecto_id (' || left(v, 120) || ')');
  if v !~ '^ERR' then
    b1 := v::uuid;
    select c.datos->'fields'->>'carta_cobrado_importe' into v2 from public.contratos c where c.id = b1;
    r := r || pg_temp.l(public.lw_importe(v2) = 5000 and (select proyecto_id from public.contratos where id = b1) = p1
                        and exists (select 1 from public.carta_cobrado_aplicado a where a.contrato_id = b1 and a.carta_id = k and a.importe = 5000),
                        'C2 el disparador calculó el abono por id: 5.000 de ZZPI-CR1 y su apunte; el espejo dejó el proyecto (' || coalesce(v2, 'null') || ')');
    select md5(public.carta_cobrado_calcula(c.id, c.datos, c.proyecto_nombre)::text), md5(privado.carta_cobrado_calcula_por_id(c.id, c.datos, c.proyecto_id)::text)
      into v, v2 from public.contratos c where c.id = b1;
    r := r || pg_temp.l(v = v2, 'C3 para ese Bloqueo, vieja y gemela devuelven los mismos datos (' || v || ' / ' || v2 || ')');
    v := pg_temp.val(ad, c_ad, format('select public.carta_cobrado_recalcula(%L)::text', b1));
    r := r || pg_temp.l(v !~ '^ERR' and public.lw_importe(v::jsonb ->> 'carta_cobrado_importe') = 5000, 'C4 carta_cobrado_recalcula (admin) da el mismo abono (' || left(v, 120) || ')');
  end if;
  -- el camino del disparador ANTES del espejo, sin pantalla: proyecto_id null y el nombre en la columna
  v := pg_temp.x(format($q$insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, datos, creado_por)
                          values ('ZZPI-RP2', 'reserva_parcela', null, %L, 'EUR', 20000, %L::jsonb, 'zz-pi@prueba.invalid') returning id::text$q$,
                         c_p1, (pg_temp.bloqueo(c_p1, 'ZZPI-3'))->'datos'));
  r := r || pg_temp.l(v !~ '^ERR' and (select public.lw_importe(c.datos->'fields'->>'carta_cobrado_importe') = 5000 and c.proyecto_id = p1
                                         from public.contratos c where c.id::text = v),
                      'C5 alta directa sin proyecto_id: el disparador resuelve el proyecto por la columna y abona los 5.000 de ZZPI-CR2 (' || left(v, 100) || ')');
  v := pg_temp.x(format($q$insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, datos, creado_por)
                          values ('ZZPI-RP3', 'reserva_parcela', null, 'ZZ-PI No existe', 'EUR', 20000, %L::jsonb, 'zz-pi@prueba.invalid') returning id::text$q$,
                         (pg_temp.bloqueo('ZZ-PI No existe', 'ZZPI-1'))->'datos'));
  r := r || pg_temp.l(pg_temp.err(v) = '23502' and v ~ 'necesita su proyecto', 'C6 un Bloqueo sin proyecto resoluble no entra (antes: sin abono y en silencio) (' || left(v, 110) || ')');

  -- ============================================================ O. obra: permiso por id
  v := pg_temp.val(ad, c_ad, format('select count(*)::text from public.obra_contratos_afectados(%L, ''F1'', ''Z1'', ''cimentacion'')', p1));
  v2 := pg_temp.val(fx, c_fx, format('select count(*)::text from public.obra_contratos_afectados(%L, ''F1'', ''Z1'', ''cimentacion'')', p1));
  r := r || pg_temp.l(pg_temp.err(v) is distinct from '42501' and pg_temp.err(v2) = '42501', 'O1 obra_contratos_afectados: el admin pasa el permiso, el de fuera no (' || left(v, 70) || ' / ' || left(v2, 60) || ')');
  v := pg_temp.val(ad, c_ad, format('select count(*)::text from public.obra_datos_cobro(%L, ''F1'', ''Z1'', ''cimentacion'')', p1));
  v2 := pg_temp.val(fx, c_fx, format('select count(*)::text from public.obra_datos_cobro(%L, ''F1'', ''Z1'', ''cimentacion'')', p1));
  r := r || pg_temp.l(pg_temp.err(v) is distinct from '42501' and pg_temp.err(v2) = '42501', 'O2 obra_datos_cobro: igual (' || left(v, 70) || ' / ' || left(v2, 60) || ')');

  -- ============================================================ G. proyecto_guarda sin la rama del slug
  v := pg_temp.val(ad, c_ad, format('select public.proyecto_guarda(%L, %L::jsonb)::text', p1, '{"slug": "zz-pi-otro"}'));
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and (select slug from public.proyectos where id = p1) = 'zz-pi-proyecto-1', 'G1 cambiar el slug se rechaza y no cambia (' || left(v, 100) || ')');
  v := pg_temp.val(ad, c_ad, format('select public.proyecto_guarda(%L, %L::jsonb)::text', p1, '{"slug": "zz-pi-proyecto-1", "resort": "ZZ Resort"}'));
  r := r || pg_temp.l(v !~ '^ERR' and (select resort from public.proyectos where id = p1) = 'ZZ Resort', 'G2 el mismo slug con otro cambio guarda (' || left(v, 100) || ')');
  v := pg_temp.val(ad, c_ad, format('select public.proyecto_guarda(%L, %L::jsonb)::text', p1, '{"resort": "ZZ Resort 2"}'));
  r := r || pg_temp.l(v !~ '^ERR' and (select resort from public.proyectos where id = p1) = 'ZZ Resort 2', 'G3 sin slug guarda (' || left(v, 100) || ')');

  -- ============================================================ P. permisos
  select string_agg(f || ':' || has_function_privilege('authenticated', f, 'execute') || '/' || has_function_privilege('anon', f, 'execute')
                    || '/' || has_function_privilege('service_role', f, 'execute'), ' ') into v
    from unnest(array['public.borrar_proyecto_por_id(uuid)', 'public.proyecto_vinculos_por_id_datos(uuid)',
                      'public.renombrar_proyecto_por_id(uuid, text)', 'public.parcela_traspaso_estado_por_unidad(uuid, text[])']) f;
  r := r || pg_temp.l(v !~ 'true/true' and v !~ '/true' and v !~ ':false', 'P1 las 4 de la intranet: authenticated sí, anon y service_role no (' || v || ')');
  select string_agg(rl || '=' || has_function_privilege(rl, 'privado.carta_cobrado_calcula_por_id(uuid, jsonb, uuid)', 'execute'), ' ') into v
    from unnest(array['anon', 'authenticated', 'service_role', 'lw_lector']) rl;
  r := r || pg_temp.l(v !~ '=true', 'P2 privado.carta_cobrado_calcula_por_id no la ejecuta nadie del API (' || v || ')');

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
