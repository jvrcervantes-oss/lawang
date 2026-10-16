-- Prueba de privado.carta_imputable en el alta de un Bloqueo de Parcela (16-oct-2026, migración
-- 20261016083000_carta_liberada_mismo_comprador.sql). La regla nueva: una Carta (liberada, la que ocupa la parcela o la colgada)
-- solo aporta dinero o parcela al Bloqueo si comparten una FICHA (client_id que guardó el servidor) y son de la MISMA empresa; el
-- pasaporte o el correo que escribe el navegador ya no deciden. Revisión previa #397 (Seguridad). Con dinero REAL reclamable en cada Carta (si no, «0 abono» no probaría nada) y el alta por contrato_guarda
-- con la sesión del agente, como la pantalla (lección de Backend 11-oct: la prueba va por la RPC y el rol reales).
--   M1-M2  montaje: las tres Cartas liberadas tienen su ficha enlazada y dinero disponible (3.000 / 4.000 / 5.000).
--   T1     Bloqueo SIN ficha que escribe el pasaporte de V (comprador con Carta liberada en esta empresa y en otra): 0 abono, 0 apuntes.
--   T2     Bloqueo con la ficha A y un co-comprador sin ficha con el pasaporte de V: solo los 3.000 de la Carta de A; nada de V.
--   T3     Bloqueo con la ficha V: los 4.000 de su Carta de ESTA empresa; nada de su Carta de la OTRA empresa (5.000).
--   T4     carta_cobrado_recalcula dos veces sobre T3 (como postgres con los claims de un admin_empresa de la empresa 1: authenticated
--          no tiene EXECUTE desde 20260927140000): el mismo abono y un solo apunte, sin la Carta de la otra empresa.
--   T5     la vieja public.carta_cobrado_calcula (a la que vuelve el trigger si se revierte 2B) aplica la misma regla.
--   T6     un id de ficha AJENA (otra empresa, no visible) escrito a mano: contrato_guarda lo rechaza (42501) y no hay apunte.
--   E1     imputar una Carta LIBERADA deja su evento 'editado' {accion: carta_liberada_imputada} en la Carta.
--   TA     ATAQUE a la parcela OCUPADA por la Carta (no liberada, con saldo) de V: Bloqueo con la ficha A y un co-comprador sin ficha con
--          el pasaporte de V → el alta aborta («no cuadra»), 0 apuntes, la Carta sin padre y la parcela sigue en la Carta.
--   TC     la misma parcela, Bloqueo SIN ficha con el pasaporte de V (antes: traspaso 'ok' por texto) → aborta pidiendo la ficha.
--   TB     control positivo: la ficha V en esa parcela → abono = lo cobrado de la Carta, la Carta queda colgada y la parcela pasa.
--   D1     el disparador del alta llama a la gemela por id (LAW-428 2B): el verde no sale del cableado viejo.
--   P1-P2  los 3 ayudantes, la gemela y la vieja calcula no los ejecuta nadie del API (has_function_privilege y aclexplode).
-- MONTAJE: filas propias marcadas ZZ-CL. Lo cobrado se fija sustituyendo, SOLO dentro de esta transacción de rama,
-- _contrato_cobrado_interno (mismo truco que proyecto_por_id_intranet.sql). En rama los números de serie no importan (la rama se
-- borra); no corre en la viva (guardia erp.en_rama), así que no puede gastar números de serie de producción.
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada línea acaba en «→ ok» o «→ FALLA». Todo se deshace con el raise final.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
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
create or replace function pg_temp.bloqueo(p_codigo text, p_pasaporte text, p_client uuid, p_compradores jsonb) returns jsonb language sql as $f$
  select jsonb_build_object('tipo', 'reserva_parcela',
           'datos', jsonb_strip_nulls(jsonb_build_object('hitos', '[]'::jsonb,
                      'adq1_client_id', p_client::text,
                      'compradores', p_compradores,
                      'fields', jsonb_build_object('proyecto_nombre', 'ZZ-CL Proyecto 1', 'parcela_codigo', p_codigo, 'moneda', 'EUR',
                                                   'precio_total', '20000', 'sociedad_firmante', 'zz_cl1',
                                                   'adq1_nombre', 'ZZ-CL Comprador', 'adq1_pasaporte', p_pasaporte))))
$f$;
-- una Carta de Reserva YA LIBERADA (dinero retenido), con su ficha en datos.adq1_client_id: el AFTER la enlaza en contrato_compradores
create or replace function pg_temp.carta(p_numero text, p_proy uuid, p_proy_nombre text, p_client uuid, p_pasaporte text) returns uuid language sql as $f$
  insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, datos, creado_por, liberado_en, liberado_motivo)
  values (p_numero, 'carta_reserva', p_proy, p_proy_nombre, 'EUR', 5000,
          jsonb_build_object('hitos', '[]'::jsonb, 'adq1_client_id', p_client::text,
            'fields', jsonb_build_object('proyecto_nombre', p_proy_nombre, 'moneda', 'EUR', 'sociedad_firmante', 'zz_cl1',
                                         'adq1_nombre', 'ZZ-CL Comprador', 'adq1_pasaporte', p_pasaporte)),
          'zz-cl@prueba.invalid', now(), 'ZZ-CL prueba')
  returning id
$f$;
-- los apuntes de un Bloqueo, legibles: «numero=importe» ordenados
create or replace function pg_temp.apuntes(p_bloqueo uuid) returns text language sql as $f$
  select coalesce(string_agg(k.numero || '=' || a.importe::numeric(12,0), ',' order by k.numero), '')
    from public.carta_cobrado_aplicado a join public.contratos k on k.id = a.carta_id where a.contrato_id = p_bloqueo
$f$;

do $todo$
declare
  r text := ''; v text; v2 text; b uuid;
  p1 uuid; p2 uuid; fa uuid; fv uuid; fz uuid; ka uuid; kv1 uuid; kv2 uuid; kz uuid; ko uuid; u5 uuid;
  ad uuid := gen_random_uuid(); c_ad constant text := 'zz-cl-admin@prueba.invalid';
  ag uuid := gen_random_uuid(); c_ag constant text := 'zz-cl-agente@prueba.invalid';
  c_fin constant text := 'FIN DE PRUEBAS CARTA LIBERADA MISMO COMPRADOR (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS CARTA LIBERADA MISMO COMPRADOR:%', E'\nP0 esta prueba monta filas y sustituye _contrato_cobrado_interno: solo corre en rama → FALLA';
  end if;

  -- ============================================================ montaje (como postgres)
  insert into public.tipos_vivienda (clave, etiqueta) values ('parcela', 'Parcela') on conflict (clave) do nothing;
  insert into public.contrato_tipo_etapa (tipo, etapa, nota) values ('reserva_parcela', 'reserva', 'Reserva de parcela'),
    ('carta_reserva', 'reserva', 'Carta de Reserva (serie CR)') on conflict (tipo) do nothing;
  insert into public.sociedades (clave, label, razon, domicilio) values ('zz_cl1', 'ZZ-CL 1', 'ZZ-CL PT 1', 'ZZ-domicilio'),
    ('zz_cl2', 'ZZ-CL 2', 'ZZ-CL PT 2', 'ZZ-domicilio') on conflict (clave) do nothing;
  insert into public.empresas (clave, nombre) values ('zz_cl_e1', 'ZZ-CL Empresa 1'), ('zz_cl_e2', 'ZZ-CL Empresa 2');
  update public.empresas set sociedad_clave = 'zz_cl1' where clave = 'zz_cl_e1';
  update public.empresas set sociedad_clave = 'zz_cl2' where clave = 'zz_cl_e2';
  insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-CL Proyecto 1', 'zz-cl-proyecto-1', 'zz_cl_e1', true) returning id into p1;
  insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-CL Proyecto 2', 'zz-cl-proyecto-2', 'zz_cl_e2', true) returning id into p2;
  insert into public.unidades (codigo, proyecto, proyecto_id, tipo, superficie_m2, precio_suelo, precio, moneda, estado)
  select 'ZZCL-' || g, 'ZZ-CL Proyecto 1', p1, 'parcela', 300, 20000, 20000, 'EUR', 'disponible' from generate_series(1, 5) g;
  select id into u5 from public.unidades where proyecto_id = p1 and codigo = 'ZZCL-5';
  insert into auth.users (id, instance_id, email, aud, role) values
    (ad, '00000000-0000-0000-0000-000000000000', c_ad, 'authenticated', 'authenticated'),
    (ag, '00000000-0000-0000-0000-000000000000', c_ag, 'authenticated', 'authenticated');
  insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
    (ad, c_ad, 'ZZ-CL Admin', 'admin_empresa', 'empresa', '{zz_cl_e1}', '{}'::uuid[], '{}'::uuid[], '{contratos}', '{}', true),
    (ag, c_ag, 'ZZ-CL Agente', 'agente', 'global', '{}', array[p1], '{}'::uuid[], '{contratos}', '{reserva_parcela,carta_reserva}', true);
  -- fichas: A y V son del agente (las ve); Z es de otra persona y solo cuelga de una Carta de la OTRA empresa (no la ve)
  insert into public.clients (full_name, passport_number, numero_cliente, propietario) values ('ZZ-CL A', 'ZZCLA0001', 'ZZCL-A', c_ag) returning id into fa;
  insert into public.clients (full_name, passport_number, numero_cliente, propietario) values ('ZZ-CL V', 'ZZCLV0001', 'ZZCL-V', c_ag) returning id into fv;
  insert into public.clients (full_name, passport_number, numero_cliente, propietario) values ('ZZ-CL Z', 'ZZCLZ0001', 'ZZCL-Z', 'zz-cl-otra@prueba.invalid') returning id into fz;
  ka  := pg_temp.carta('ZZCL-CRA',  p1, 'ZZ-CL Proyecto 1', fa, 'ZZCLA0001');
  kv1 := pg_temp.carta('ZZCL-CRV1', p1, 'ZZ-CL Proyecto 1', fv, 'ZZCLV0001');
  kv2 := pg_temp.carta('ZZCL-CRV2', p2, 'ZZ-CL Proyecto 2', fv, 'ZZCLV0001');
  kz  := pg_temp.carta('ZZCL-CRZ',  p2, 'ZZ-CL Proyecto 2', fz, 'ZZCLZ0001');
  -- la Carta NO liberada de V que OCUPA la parcela ZZCL-5 (la hermana: el dinero expuesto el 16-oct estaba en esta forma)
  insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, datos, creado_por)
  values ('ZZCL-CRO', 'carta_reserva', p1, 'ZZ-CL Proyecto 1', 'EUR', 5000,
          jsonb_build_object('hitos', '[]'::jsonb, 'adq1_client_id', fv::text,
            'fields', jsonb_build_object('proyecto_nombre', 'ZZ-CL Proyecto 1', 'parcela_codigo', 'ZZCL-5', 'moneda', 'EUR',
                                         'sociedad_firmante', 'zz_cl1', 'adq1_nombre', 'ZZ-CL Comprador', 'adq1_pasaporte', 'ZZCLV0001')),
          'zz-cl@prueba.invalid') returning id into ko;
  update public.unidades set contrato_id = ko, estado = 'reservada' where id = u5;
  execute format($s$create or replace function public._contrato_cobrado_interno(p_contrato_id uuid, p_moneda text default null)
                    returns numeric language sql stable as $b$select case p_contrato_id when %L::uuid then 3000::numeric when %L::uuid then 4000::numeric
                                                                   when %L::uuid then 5000::numeric when %L::uuid then 6000::numeric
                                                                   when %L::uuid then 7000::numeric else 0::numeric end$b$$s$,
                 ka, kv1, kv2, kz, ko);
  r := r || pg_temp.l((select count(*) from public.contrato_compradores cc
                        where (cc.contrato_id, cc.client_id) in ((ka, fa), (kv1, fv), (kv2, fv), (kz, fz))) = 4
                      and (select count(*) from public.contratos where id in (ka, kv1, kv2, kz) and liberado_en is not null) = 4,
                      'M1 montaje: 4 Cartas liberadas, cada una enlazada a su ficha en contrato_compradores');
  r := r || pg_temp.l(public.contrato_cobrado(ka) = 3000 and public.contrato_cobrado(kv1) = 4000 and public.contrato_cobrado(kv2) = 5000
                      and public.contrato_cobrado(kz) = 6000 and public.contrato_cobrado(ko) = 7000
                      and (select contrato_id from public.unidades where id = u5) = ko,
                      'M2 hay dinero reclamable en cada Carta (3.000 / 4.000 / 5.000 / 6.000 / 7.000) y ZZCL-5 la ocupa ZZCL-CRO: un «0 abono» de abajo no es vacío');
  r := r || pg_temp.l(position('carta_cobrado_calcula_por_id' in pg_get_functiondef('public.carta_cobrado_al_bloquear()'::regprocedure)) > 0,
                      'D1 el disparador del alta llama a privado.carta_cobrado_calcula_por_id (2B aplicada en la rama)');

  -- ============================================================ T1 sin ficha, con el pasaporte de V escrito a mano
  v := pg_temp.val(ag, c_ag, format('select (public.contrato_guarda(null, %L::jsonb))->>''id''', pg_temp.bloqueo('ZZCL-1', 'ZZCLV0001', null, null)));
  r := r || pg_temp.l(v !~ '^ERR', 'T1a el agente da de alta el Bloqueo sin ficha por contrato_guarda (' || left(v, 100) || ')');
  if v !~ '^ERR' then
    b := v::uuid;
    select c.datos->'fields'->>'carta_cobrado_importe' into v2 from public.contratos c where c.id = b;
    r := r || pg_temp.l(v2 is null and pg_temp.apuntes(b) = '',
                        'T1b el pasaporte de V escrito por el navegador ya no se lleva sus Cartas liberadas: 0 abono, 0 apuntes (antes: 9.000) ('
                        || coalesce(v2, 'null') || ' / ' || pg_temp.apuntes(b) || ')');
  end if;

  -- ============================================================ T2 ficha A + co-comprador sin ficha con el pasaporte de V
  v := pg_temp.val(ag, c_ag, format('select (public.contrato_guarda(null, %L::jsonb))->>''id''',
                   pg_temp.bloqueo('ZZCL-2', 'ZZCLA0001', fa, jsonb_build_array(jsonb_build_object('nombre', 'ZZ-CL Otro', 'pasaporte', 'ZZCLV0001')))));
  r := r || pg_temp.l(v !~ '^ERR', 'T2a alta con la ficha A y un co-comprador sin ficha (' || left(v, 100) || ')');
  if v !~ '^ERR' then
    b := v::uuid;
    select c.datos->'fields'->>'carta_cobrado_importe' into v2 from public.contratos c where c.id = b;
    r := r || pg_temp.l(public.lw_importe(v2) = 3000 and pg_temp.apuntes(b) = 'ZZCL-CRA=3000',
                        'T2b solo la Carta de la ficha A (3.000); el pasaporte de V en un co-comprador no trae nada de V ('
                        || coalesce(v2, 'null') || ' / ' || pg_temp.apuntes(b) || ')');
    r := r || pg_temp.l((select count(*) from public.contrato_eventos e where e.contrato_id = ka and e.evento = 'editado'
                          and e.detalle->>'accion' = 'carta_liberada_imputada' and e.detalle->>'bloqueo_id' = b::text) = 1,
                        'E1 imputar la Carta LIBERADA de A deja su evento carta_liberada_imputada en la Carta, con el Bloqueo');
  end if;

  -- ============================================================ T3 ficha V: su Carta de ESTA empresa, no la de la otra
  v := pg_temp.val(ag, c_ag, format('select (public.contrato_guarda(null, %L::jsonb))->>''id''', pg_temp.bloqueo('ZZCL-3', 'ZZCLV0001', fv, null)));
  r := r || pg_temp.l(v !~ '^ERR', 'T3a alta con la ficha V (' || left(v, 100) || ')');
  if v !~ '^ERR' then
    b := v::uuid;
    select c.datos->'fields'->>'carta_cobrado_importe' into v2 from public.contratos c where c.id = b;
    r := r || pg_temp.l(public.lw_importe(v2) = 4000 and pg_temp.apuntes(b) = 'ZZCL-CRV1=4000',
                        'T3b control positivo: la misma ficha y la misma empresa SÍ se imputa (4.000); la Carta de V en la otra empresa (5.000) no ('
                        || coalesce(v2, 'null') || ' / ' || pg_temp.apuntes(b) || ')');

    -- ============================================================ T4 recalcula, dos veces
    v  := pg_temp.val(ad, c_ad, format('select public.carta_cobrado_recalcula(%L)::text', b), 'postgres');
    v2 := pg_temp.val(ad, c_ad, format('select public.carta_cobrado_recalcula(%L)::text', b), 'postgres');
    r := r || pg_temp.l(v !~ '^ERR' and v2 !~ '^ERR' and public.lw_importe(v2::jsonb ->> 'carta_cobrado_importe') = 4000
                        and pg_temp.apuntes(b) = 'ZZCL-CRV1=4000',
                        'T4 carta_cobrado_recalcula dos veces: el mismo abono y un solo apunte (' || left(v2, 90) || ' / ' || pg_temp.apuntes(b) || ')');

    -- ============================================================ T5 la vieja (vuelta atrás de 2B) aplica la misma regla
    select public.carta_cobrado_calcula(c.id, c.datos, c.proyecto_nombre)->'fields'->>'carta_cobrado_numeros' into v from public.contratos c where c.id = b;
    r := r || pg_temp.l(v = 'ZZCL-CRV1', 'T5a la vieja, sobre el Bloqueo de V: solo la Carta de esta empresa (' || coalesce(v, 'null') || ')');
  end if;
  select public.carta_cobrado_calcula(gen_random_uuid(), (pg_temp.bloqueo('ZZCL-4', 'ZZCLV0001', null, null))->'datos', 'ZZ-CL Proyecto 1')
         ->'fields'->>'carta_cobrado_importe' into v;
  r := r || pg_temp.l(v is null, 'T5b la vieja, con el pasaporte de V y sin ficha: 0 abono (' || coalesce(v, 'null') || ')');

  -- ============================================================ T6 un id de ficha ajena escrito a mano
  v := pg_temp.val(ag, c_ag, format('select (public.contrato_guarda(null, %L::jsonb))->>''id''', pg_temp.bloqueo('ZZCL-4', 'ZZCLZ0001', fz, null)));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and not exists (select 1 from public.carta_cobrado_aplicado where carta_id = kz),
                      'T6 la ficha de otra empresa que el agente no ve: contrato_guarda la rechaza y la Carta Z queda intacta (' || left(v, 110) || ')');

  -- ============================================================ TA ataque a la parcela ocupada (co-comprador sin ficha con el pasaporte de V)
  v := pg_temp.val(ag, c_ag, format('select (public.contrato_guarda(null, %L::jsonb))->>''id''',
                   pg_temp.bloqueo('ZZCL-5', 'ZZCLA0001', fa, jsonb_build_array(jsonb_build_object('nombre', 'ZZ-CL Otro', 'pasaporte', 'ZZCLV0001')))));
  r := r || pg_temp.l(pg_temp.err(v) = '23514' and v ~ 'no cuadra'
                      and not exists (select 1 from public.carta_cobrado_aplicado where carta_id = ko)
                      and (select contrato_padre_id from public.contratos where id = ko) is null
                      and (select contrato_id from public.unidades where id = u5) = ko
                      and not exists (select 1 from public.contratos where proyecto_id = p1 and tipo = 'reserva_parcela'
                                        and datos->'fields'->>'parcela_codigo' = 'ZZCL-5'),
                      'TA ataque (ficha A + pasaporte de V en un co-comprador) sobre la parcela de la Carta de V: aborta, 0 apuntes, la Carta sin padre, la parcela sigue en ZZCL-CRO y no queda Bloqueo ('
                      || left(v, 140) || ')');

  -- ============================================================ TC la misma parcela, sin ficha y con el pasaporte de V (antes: 'ok' por texto)
  v := pg_temp.val(ag, c_ag, format('select (public.contrato_guarda(null, %L::jsonb))->>''id''', pg_temp.bloqueo('ZZCL-5', 'ZZCLV0001', null, null)));
  r := r || pg_temp.l(pg_temp.err(v) = '23514' and v ~ 'falta la ficha del comprador'
                      and not exists (select 1 from public.carta_cobrado_aplicado where carta_id = ko)
                      and (select contrato_id from public.unidades where id = u5) = ko,
                      'TC sin ficha y con el pasaporte de V escrito a mano: aborta pidiendo la ficha; la Carta y la parcela intactas (' || left(v, 140) || ')');

  -- ============================================================ TB control positivo: la ficha V en esa parcela
  v := pg_temp.val(ag, c_ag, format('select (public.contrato_guarda(null, %L::jsonb))->>''id''', pg_temp.bloqueo('ZZCL-5', 'ZZCLV0001', fv, null)));
  r := r || pg_temp.l(v !~ '^ERR', 'TBa alta con la ficha V sobre la parcela de su Carta (' || left(v, 100) || ')');
  if v !~ '^ERR' then
    b := v::uuid;
    select c.datos->'fields'->>'carta_cobrado_importe' into v2 from public.contratos c where c.id = b;
    r := r || pg_temp.l(public.lw_importe(v2) = 7000 and pg_temp.apuntes(b) = 'ZZCL-CRO=7000'
                        and (select contrato_padre_id from public.contratos where id = ko) = b
                        and (select contrato_id from public.unidades where id = u5) = b,
                        'TBb misma ficha y misma empresa: abono = lo cobrado de la Carta (7.000), la Carta queda colgada y la parcela pasa al Bloqueo ('
                        || coalesce(v2, 'null') || ' / ' || pg_temp.apuntes(b) || ')');
  end if;

  -- ============================================================ P1-P2 permisos
  select string_agg(f || ':' || rl || '=' || has_function_privilege(rl, f, 'execute'), ' ') into v
    from unnest(array['privado.carta_cobrado_clientes_de(jsonb)', 'privado.contrato_fichas(uuid)', 'privado.carta_imputable(uuid, uuid[], text)',
                      'privado.carta_cobrado_calcula_por_id(uuid, jsonb, uuid)', 'public.carta_cobrado_calcula(uuid, jsonb, text)']) f,
         unnest(array['anon', 'authenticated', 'service_role', 'lw_lector']) rl;
  r := r || pg_temp.l(v !~ '=true', 'P1 los 3 ayudantes, la gemela y la vieja calcula no los ejecuta nadie del API (' || v || ')');
  select string_agg(distinct p.oid::regprocedure::text || ':' || case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end, ' ') into v
    from pg_proc p cross join lateral aclexplode(p.proacl) a
   where p.oid in ('privado.carta_cobrado_clientes_de(jsonb)'::regprocedure, 'privado.contrato_fichas(uuid)'::regprocedure,
                   'privado.carta_imputable(uuid, uuid[], text)'::regprocedure, 'public.carta_cobrado_calcula(uuid, jsonb, text)'::regprocedure)
     and a.privilege_type = 'EXECUTE' and (a.grantee = 0 or pg_get_userbyid(a.grantee) <> 'postgres');
  r := r || pg_temp.l(v is null, 'P2 aclexplode: EXECUTE solo para postgres en los 3 ayudantes y la vieja (' || coalesce(v, 'nadie más') || ')');

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
