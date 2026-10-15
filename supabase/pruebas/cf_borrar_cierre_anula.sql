-- Prueba «borrar una operacion con cobros, cerrar firmado a mano y anular lo enviado o cobrado: solo admin de la empresa»
-- (14-oct-2026, migracion 20261015065220_cf_borrar_cierre_anula_solo_admin, bloque B). Rol REAL: cada llamada va con
-- `set local role authenticated` y los claims (sub + email) de la persona, puestos FUERA del bloque con `exception` (pg_temp.val,
-- el mismo armazon que espejo_cliente_visible.sql). Cada NO lleva al lado un SI que solo cambia en la condicion que se prueba.
-- Los 42501 nuevos se distinguen por su texto de los de siempre («No puedes anular», autoria, GRANT).
--
-- !! CREA CONTRATOS por contrato_guarda (gasta numeracion, que un rollback no devuelve): SOLO EN RAMA, NUNCA EN LA BASE VIVA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261015065220_cf_borrar_cierre_anula_solo_admin.sql
--           --prueba cf_borrar_cierre_anula.sql,cf_vuelta.py
--    Fuera de una rama (sin `erp.en_rama = si`, que pone rama_prueba) se niega a empezar, antes de tocar nada.
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada linea acaba en «→ ok» o «→ FALLA». No imprime lo que
-- devuelven las llamadas que entran (solo contadores, codigos de error y booleanos). Todo lo de prueba va marcado ZZ-CF.
-- FIXTURE PROPIO (la rama recibe SOLO la estructura): como postgres y SIN sesion,
--   · empresas zz_cf y zz_cf_otra, un proyecto activo de cada una, una sociedad activa para zz_cf;
--   · 8 personas (auth.users + usuarios): SA super_admin global; A y B agentes acotados a zz_cf (Contratos + Facturas); N agente sin
--     Contratos (solo Facturas); AE admin_empresa de zz_cf; SE super_admin_empresa de zz_cf; AO admin_empresa de zz_cf_otra
--     (los tres admins de empresa con Contratos + Facturas: puede() solo se salta para super_admin);
--   · los contratos los da de alta su autor por contrato_guarda (A y B), o SA y despues, como postgres, se les pone el autor (AE, N)
--     y, en K5, el padre: contrato_guarda no deja colgar una hija de un contrato de otro proyecto;
--   · los documentos (facturas, proformas, recibis) se insertan como postgres, con su autor y su estado (enviada / anulada).
--   Cada SI gasta su operacion o su documento: cada caso tiene el suyo.
-- MEDIDO: (pendiente; la rama la lanza quien encarga, con turno)
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create temp table _tp (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text) returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
  execute 'set local role authenticated';
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return t;
end $f$;
create or replace function pg_temp.err(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then substr(t, 4, 5) end $f$;
create or replace function pg_temp.e(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then left(t, 140) else 'sin error' end $f$;
-- el alta minima de un contrato_general (no lleva parcela ni cliente; la moneda va en fields para que las facturas la hereden)
create or replace function pg_temp.pago(p_proy text) returns jsonb language sql immutable as $f$
  select jsonb_build_object('tipo', 'contrato_general', 'datos', jsonb_build_object('fields',
           jsonb_build_object('proyecto_nombre', p_proy, 'adq1_nombre', 'ZZ-CF comprador', 'moneda', 'EUR')))
$f$;
-- alta por contrato_guarda con la sesion de quien se dice: el id, o null si falla (el montaje lo cuenta despues)
create or replace function pg_temp.alta(p_uid uuid, p_email text, p_proy text) returns uuid language plpgsql as $f$
declare v text;
begin
  v := pg_temp.val(p_uid, p_email, format('select (public.contrato_guarda(null, %L::jsonb))->>''id''', pg_temp.pago(p_proy)));
  return case when v is null or v ~ '^ERR' then null else v::uuid end;
end $f$;
-- borrar_operacion por el camino real: devuelve contratos_borrados, o el error
create or replace function pg_temp.borra(p_uid uuid, p_email text, p_id uuid) returns text language sql as $f$
  select pg_temp.val(p_uid, p_email, format('select (public.borrar_operacion(%L::uuid))->>''contratos_borrados''', p_id))
$f$;

-- Personas SINTETICAS (id y correo aqui; las filas se crean dentro del bloque, tras la guardia de rama). Correos en minusculas.
insert into _tp values ('SA', gen_random_uuid(), 'zz-cf-super@prueba.invalid'),
                       ('A',  gen_random_uuid(), 'zz-cf-agente-a@prueba.invalid'),
                       ('B',  gen_random_uuid(), 'zz-cf-agente-b@prueba.invalid'),
                       ('N',  gen_random_uuid(), 'zz-cf-agente-sin-contratos@prueba.invalid'),
                       ('AE', gen_random_uuid(), 'zz-cf-admin-empresa@prueba.invalid'),
                       ('SE', gen_random_uuid(), 'zz-cf-super-empresa@prueba.invalid'),
                       ('AO', gen_random_uuid(), 'zz-cf-admin-otra@prueba.invalid');

do $todo$
declare
  r text := ''; v text; v2 text; v3 text; n bigint; g boolean;
  sa _tp; a _tp; b _tp; nn _tp; ae _tp; se _tp; ao _tp;
  pL uuid; pLn text; pO uuid; pOn text;
  k1 uuid; k1b uuid; k2 uuid; k3 uuid; k3b uuid; k4 uuid; k5 uuid; k5h uuid; kB uuid; kN uuid; kM uuid; kM2 uuid;
  fBorr uuid; fEnv uuid; fRec uuid; fProf uuid; fAnu uuid; num_m text;
  c_emp  constant text := 'zz_cf';
  c_otra constant text := 'zz_cf_otra';
  c_tg   constant text := 'SC-0001 - pedido por zz - aprobado por zz via Telegram';   -- el correo FALSO de resolver_solicitud_cambio
  c_herr constant text := 'No tienes la herramienta de Contratos';
  c_nove constant text := 'ERRP0002:Esa operación no existe o no tienes acceso a ella.';
  c_cobr constant text := 'solo la puede borrar un administrador de su empresa';
  c_anu  constant text := 'solo lo puede anular un administrador de su empresa';
  c_fin  constant text := 'FIN DE PRUEBAS CF BORRAR CIERRE ANULA (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS CF BORRAR CIERRE ANULA:%', E'\nP0 esta prueba crea contratos (gasta numeracion): solo corre en rama → FALLA';
  end if;
  select * into sa from _tp where et = 'SA'; select * into a from _tp where et = 'A'; select * into b from _tp where et = 'B';
  select * into nn from _tp where et = 'N'; select * into ae from _tp where et = 'AE'; select * into se from _tp where et = 'SE';
  select * into ao from _tp where et = 'AO';

  -- ============================================================ P. montaje (como postgres, SIN sesion)
  perform set_config('request.jwt.claims', '', true);
  begin
    insert into public.empresas (clave, nombre) values (c_emp, 'ZZ-CF Empresa'), (c_otra, 'ZZ-CF Otra empresa');
    insert into public.sociedades (clave, label, razon, domicilio) values ('zz_cf', 'ZZ-CF', 'ZZ-CF PT', 'ZZ-domicilio')
      on conflict (clave) do nothing;
    update public.empresas set sociedad_clave = 'zz_cf' where clave = c_emp;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-CF Proyecto', 'zz-cf-proyecto', c_emp, true)
      returning id, nombre into pL, pLn;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-CF Proyecto otra', 'zz-cf-proyecto-otra', c_otra, true)
      returning id, nombre into pO, pOn;
    insert into auth.users (id, instance_id, email, aud, role)
      select t.uid, '00000000-0000-0000-0000-000000000000', t.em, 'authenticated', 'authenticated' from _tp t;
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (sa.uid, sa.em, 'ZZ-CF Super admin',      'super_admin',         'global',  '{}'::text[],  '{}'::uuid[], '{}'::uuid[], '{}'::text[],                    '{}'::text[], true),
      (a.uid,  a.em,  'ZZ-CF Agente A',         'agente',              'global',  array[c_emp],  array[pL],    '{}'::uuid[], '{contratos,facturas}'::text[], '{contrato_general}'::text[], true),
      (b.uid,  b.em,  'ZZ-CF Agente B',         'agente',              'global',  array[c_emp],  array[pL],    '{}'::uuid[], '{contratos,facturas}'::text[], '{contrato_general}'::text[], true),
      (nn.uid, nn.em, 'ZZ-CF Agente sin Contratos', 'agente',          'global',  array[c_emp],  array[pL],    '{}'::uuid[], '{facturas}'::text[],           '{contrato_general}'::text[], true),
      (ae.uid, ae.em, 'ZZ-CF Admin empresa',    'admin_empresa',       'empresa', array[c_emp],  '{}'::uuid[], '{}'::uuid[], '{contratos,facturas}'::text[], '{}'::text[], true),
      (se.uid, se.em, 'ZZ-CF Super admin empresa', 'super_admin_empresa', 'empresa', array[c_emp], '{}'::uuid[], '{}'::uuid[], '{contratos,facturas}'::text[], '{}'::text[], true),
      (ao.uid, ao.em, 'ZZ-CF Admin otra empresa', 'admin_empresa',     'empresa', array[c_otra], '{}'::uuid[], '{}'::uuid[], '{contratos,facturas}'::text[], '{}'::text[], true);
  exception when others then
    raise exception using message = replace(c_fin, '%', pg_temp.l(false, 'P0 montaje de empresas, proyectos y personas: ' || sqlstate || ' ' || left(sqlerrm, 300)
                                                               || ' [session_user=' || session_user || ']'));
  end;

  -- contratos: A los suyos por contrato_guarda; SA los de otros autores (luego, como postgres, el autor y el padre)
  v := pg_temp.val(a.uid, a.em, format('select (public.contrato_guarda(null, %L::jsonb))->>''id''', pg_temp.pago(pLn)));
  r := r || pg_temp.l(v !~ '^ERR', 'P1 A da de alta un contrato por contrato_guarda (' || pg_temp.e(v) || ')');
  if v !~ '^ERR' then
    k1 := v::uuid;
    k1b := pg_temp.alta(a.uid, a.em, pLn);   k2  := pg_temp.alta(a.uid, a.em, pLn);   k3  := pg_temp.alta(a.uid, a.em, pLn);
    k3b := pg_temp.alta(a.uid, a.em, pLn);   kM  := pg_temp.alta(a.uid, a.em, pLn);   kM2 := pg_temp.alta(a.uid, a.em, pLn);
    kB  := pg_temp.alta(b.uid, b.em, pLn);
    k4  := pg_temp.alta(sa.uid, sa.em, pLn); k5  := pg_temp.alta(sa.uid, sa.em, pLn); k5h := pg_temp.alta(sa.uid, sa.em, pOn);
    kN  := pg_temp.alta(sa.uid, sa.em, pLn);
  end if;
  begin
    update public.contratos set creado_por = ae.em where id in (k4, k5, k5h);
    update public.contratos set contrato_padre_id = k5 where id = k5h;
    update public.contratos set creado_por = nn.em where id = kN;
    update public.contratos set moneda = 'EUR' where id in (k1, k1b, k2, k3, k3b, k4, k5, k5h, kB, kN, kM, kM2) and moneda is null;
    -- documentos (como postgres: su autor y su estado se fijan aqui; recibi con justificante, por el CHECK)
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos, enviada, anulada, justificante_path) values
      ('factura', 'ZZ-CF-K1B-BORR', 'zz_cf', k1b, 10, 'EUR', a.em,  'ZZ-CF', '{"fields": {}}'::jsonb, false, false, null),
      ('recibi',  'ZZ-CF-K2-REC',   'zz_cf', k2,  10, 'EUR', a.em,  'ZZ-CF', '{"fields": {}}'::jsonb, false, false, 'zz/zz-cf-k2.pdf'),
      ('factura', 'ZZ-CF-K3-ENVANU','zz_cf', k3,  10, 'EUR', a.em,  'ZZ-CF', '{"fields": {}}'::jsonb, true,  true,  null),
      ('recibi',  'ZZ-CF-K3B-RECANU','zz_cf', k3b, 10, 'EUR', a.em, 'ZZ-CF', '{"fields": {}}'::jsonb, false, true,  'zz/zz-cf-k3b.pdf'),
      ('recibi',  'ZZ-CF-K4-REC',   'zz_cf', k4,  10, 'EUR', ae.em, 'ZZ-CF', '{"fields": {}}'::jsonb, false, false, 'zz/zz-cf-k4.pdf'),
      ('recibi',  'ZZ-CF-K5-REC',   'zz_cf', k5,  10, 'EUR', ae.em, 'ZZ-CF', '{"fields": {}}'::jsonb, false, false, 'zz/zz-cf-k5.pdf');
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos, enviada, anulada)
      values ('factura', 'ZZ-CF-KM-BORR', 'zz_cf', kM, 10, 'EUR', a.em, 'ZZ-CF', '{"fields": {}}'::jsonb, false, false) returning id into fBorr;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos, enviada, anulada)
      values ('factura', 'ZZ-CF-KM-ENV', 'zz_cf', kM, 10, 'EUR', a.em, 'ZZ-CF', '{"fields": {}}'::jsonb, true, false) returning id into fEnv;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos, enviada, anulada, justificante_path)
      values ('recibi', 'ZZ-CF-KM-REC', 'zz_cf', kM, 10, 'EUR', a.em, 'ZZ-CF', '{"fields": {}}'::jsonb, false, false, 'zz/zz-cf-km.pdf') returning id into fRec;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos, enviada, anulada)
      values ('proforma', 'ZZ-CF-KM-PROENV', 'zz_cf', kM, 10, 'EUR', a.em, 'ZZ-CF', '{"fields": {}}'::jsonb, true, false) returning id into fProf;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos, enviada, anulada)
      values ('factura', 'ZZ-CF-KM-ANU', 'zz_cf', kM, 10, 'EUR', a.em, 'ZZ-CF', '{"fields": {}}'::jsonb, false, true) returning id into fAnu;
  exception when others then
    r := r || pg_temp.l(false, 'P2 montaje de autores, padre y documentos: ' || sqlstate || ' ' || left(sqlerrm, 300));
  end;
  select numero into num_m from public.contratos where id = kM;
  select count(*) into n from public.contratos where id in (k1, k1b, k2, k3, k3b, k4, k5, k5h, kB, kN, kM, kM2);
  r := r || pg_temp.l(n = 12 and num_m is not null, 'P3 los 12 contratos del montaje existen, con numero (' || n || ')');
  select count(*) into n from public.contratos
   where (id in (k1, k1b, k2, k3, k3b, kM, kM2) and creado_por = a.em) or (id = kB and creado_por = b.em)
      or (id in (k4, k5, k5h) and creado_por = ae.em) or (id = kN and creado_por = nn.em);
  r := r || pg_temp.l(n = 12, 'P4 cada contrato tiene el autor del caso (' || n || ')');
  select count(*) into n from public.contratos c join public.proyectos p on p.id = c.proyecto_id
   where c.id = k5h and c.contrato_padre_id = k5 and p.empresa = c_otra;
  r := r || pg_temp.l(n = 1, 'P5 K5 tiene una hija en un proyecto de la OTRA empresa');
  select count(*) into n from public.facturas where numero like 'ZZ-CF-%'
     and creado_por in (a.em, ae.em);
  r := r || pg_temp.l(n = 11, 'P6 los 11 documentos del montaje existen con su autor (' || n || ')');
  select count(*) into n from public.facturas where numero like 'ZZ-CF-%' and (enviada, anulada) is distinct from
     (case when numero in ('ZZ-CF-K3-ENVANU', 'ZZ-CF-KM-ENV', 'ZZ-CF-KM-PROENV') then true else false end,
      case when numero in ('ZZ-CF-K3-ENVANU', 'ZZ-CF-K3B-RECANU', 'ZZ-CF-KM-ANU') then true else false end);
  r := r || pg_temp.l(n = 0, 'P7 ... con su estado (enviada / anulada) tal cual se inserto (' || n || ' distintos)');
  -- las puertas de las que dependen los casos, con los claims de cada uno (como postgres: son DEFINER y solo leen auth.uid())
  perform set_config('request.jwt.claims', json_build_object('sub', a.uid, 'role', 'authenticated', 'email', a.em)::text, true);
  g := public._puede_herr('contratos') and public.puede('facturas') and public.puede_ver_contrato(k2) and not public.puede_ver_contrato(kB)
       and not public.es_admin_de(c_emp);
  r := r || pg_temp.l(g, 'P8 A: tiene Contratos y Facturas, ve su operacion y no la de B, y no es admin de su empresa');
  perform set_config('request.jwt.claims', json_build_object('sub', nn.uid, 'role', 'authenticated', 'email', nn.em)::text, true);
  g := not public._puede_herr('contratos') and public.es_agente() and public.puede_ver_contrato(kN);
  r := r || pg_temp.l(g, 'P9 N: agente activo que ve su contrato, sin la herramienta Contratos');
  perform set_config('request.jwt.claims', json_build_object('sub', ae.uid, 'role', 'authenticated', 'email', ae.em)::text, true);
  g := public._puede_herr('contratos') and public.puede('facturas') and public.es_admin_de(c_emp) and not public.es_admin_de(c_otra)
       and not public.es_super_admin_de(c_emp) and public.puede_ver_contrato(k2) and public.puede_ver_contrato(k5);
  r := r || pg_temp.l(g, 'P10 AE: admin de zz_cf (no super), no de la otra; ve la operacion de A y la suya');
  perform set_config('request.jwt.claims', json_build_object('sub', se.uid, 'role', 'authenticated', 'email', se.em)::text, true);
  g := public._puede_herr('contratos') and public.es_super_admin_de(c_emp) and public.puede_ver_contrato(k2);
  r := r || pg_temp.l(g, 'P11 SE: super admin de zz_cf y ve la operacion de A');
  perform set_config('request.jwt.claims', json_build_object('sub', ao.uid, 'role', 'authenticated', 'email', ao.em)::text, true);
  g := public._puede_herr('contratos') and not public.puede_ver_contrato(k2) and not public.es_admin_de(c_emp);
  r := r || pg_temp.l(g, 'P12 AO: admin de la otra empresa, no ve la operacion de A');
  perform set_config('request.jwt.claims', json_build_object('sub', sa.uid, 'role', 'authenticated', 'email', c_tg)::text, true);
  g := public._puede_herr('contratos') and public.es_admin() and coalesce((select auth.email()), '') = c_tg;
  r := r || pg_temp.l(g, 'P13 la identidad de Telegram: uid del super admin con un correo que no es el suyo');
  perform set_config('request.jwt.claims', '', true);
  v := pg_temp.val(a.uid, a.em, 'select (select auth.uid())::text || ''|'' || (select auth.email()) || ''|'' || current_user');
  r := r || pg_temp.l(v = a.uid::text || '|' || a.em || '|authenticated', 'S0 la sesion simulada se reconoce: auth.uid(), auth.email() y el rol authenticated de A (' || pg_temp.e(v) || ')');

  if r ~ 'FALLA' then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'PARADA: el montaje o la sesion no valen; los casos B/C/F no se corren'));
  end if;

  -- ============================================================ B. borrar_operacion
  v := pg_temp.borra(a.uid, a.em, k1);
  r := r || pg_temp.l(v = '1', 'B1 ENTRA: A borra su operacion sin documentos (' || pg_temp.e(v) || ')');
  v := pg_temp.borra(a.uid, a.em, k1b);
  r := r || pg_temp.l(v = '1' and exists (select 1 from public.facturas where numero = 'ZZ-CF-K1B-BORR' and anulada and contrato_id is null),
       'B1b ENTRA: A borra su operacion con una factura en borrador (sin enviar): como hoy, la factura queda anulada (' || pg_temp.e(v) || ')');
  v := pg_temp.borra(a.uid, a.em, k3b);
  r := r || pg_temp.l(v = '1', 'B1c ENTRA: ... y con un recibi ANULADO sin enviar (no es un recibi vivo) (' || pg_temp.e(v) || ')');
  v := pg_temp.borra(a.uid, a.em, k2);
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ c_cobr, 'B2 NIEGA: A no borra su operacion con un recibi vivo: 42501 con el mensaje nuevo (' || pg_temp.e(v) || ')');
  v := pg_temp.borra(a.uid, a.em, k3);
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ c_cobr, 'B3 NIEGA: ... ni la que tiene una factura ENVIADA aunque este anulada (' || pg_temp.e(v) || ')');
  select count(*) into n from public.contratos where id in (k2, k3);
  r := r || pg_temp.l(n = 2, 'B3b ... y las dos operaciones siguen ahi (' || n || ')');
  v := pg_temp.borra(ae.uid, ae.em, k2);
  r := r || pg_temp.l(pg_temp.err(v) = 'P0001' and v ~ 'es de otra persona', 'B4c NIEGA, COMO HOY: un admin de empresa (no super) que no es el autor se para en la autoria (' || pg_temp.e(v) || ')');
  v := pg_temp.borra(ao.uid, ao.em, k2);
  r := r || pg_temp.l(v = c_nove, 'B5 NIEGA: el admin de OTRA empresa recibe el mismo «no existe o no tienes acceso» (' || pg_temp.e(v) || ')');
  v := pg_temp.borra(ae.uid, ae.em, k5);
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ c_cobr, 'B5b NIEGA (TODAS las empresas): AE, autor de toda la cadena con recibi, no la borra porque una hija es de otra empresa (' || pg_temp.e(v) || ')');
  v := pg_temp.borra(ae.uid, ae.em, k4);
  r := r || pg_temp.l(v = '1', 'B4 ENTRA: el admin de la empresa borra SU operacion con un recibi vivo (' || pg_temp.e(v) || ')');
  v := pg_temp.borra(se.uid, se.em, k2);
  r := r || pg_temp.l(v = '1' and exists (select 1 from public.facturas where numero = 'ZZ-CF-K2-REC' and anulada),
       'B4b ENTRA: el super admin de la empresa borra la operacion de A con el recibi vivo (el recibi queda anulado) (' || pg_temp.e(v) || ')');
  v := pg_temp.borra(sa.uid, c_tg, k3);
  r := r || pg_temp.l(v = '1', 'B8 ENTRA (Telegram): uid del super admin con el correo falso de resolver_solicitud_cambio borra la de la factura enviada (' || pg_temp.e(v) || ')');
  v := pg_temp.borra(nn.uid, nn.em, kN);
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ c_herr, 'B6 NIEGA: el agente sin la herramienta Contratos no borra ni su propia operacion (' || pg_temp.e(v) || ')');
  v  := pg_temp.borra(a.uid, a.em, gen_random_uuid());
  v2 := pg_temp.borra(a.uid, a.em, kB);
  r := r || pg_temp.l(v = c_nove and v2 = v, 'B7 el MISMO error, letra por letra, para un id que no existe y para la operacion de otro agente (' || pg_temp.e(v) || ' | ' || pg_temp.e(v2) || ')');
  v3 := pg_temp.borra(sa.uid, sa.em, gen_random_uuid());
  r := r || pg_temp.l(v3 = c_nove, 'B7b ... y para un admin con un id que no existe (puede_ver_contrato le da true a cualquier id) (' || pg_temp.e(v3) || ')');
  r := r || pg_temp.l(substr(v, 10) !~ '[0-9]' and position(coalesce((select numero from public.contratos where id = kB), '?') in v) = 0,
       'B7c ... sin ningun numero (ni el de la operacion de B) en el mensaje');
  select count(*) into n from public.contratos where id in (k5, k5h, kB, kN);
  r := r || pg_temp.l(n = 4, 'B9 lo que se nego sigue entero (K5 y su hija, la de B, la de N) (' || n || ')');

  -- ============================================================ C. cierre manual «firmado a mano» (agente_escribe_fichero_contrato)
  v := pg_temp.val(a.uid, a.em, format('select public.agente_escribe_fichero_contrato(%L)::text', num_m || '_manual.pdf'));
  r := r || pg_temp.l(v = 'false', 'C1 NIEGA: el agente autor no puede cerrar su contrato como firmado a mano (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select public.agente_escribe_fichero_contrato(%L)::text', 'pendientes/' || kM::text || '.html'));
  r := r || pg_temp.l(v = 'true', 'C2 ENTRA: ... pero si sigue pudiendo enviarlo a firmar (rama pendientes/, sin cambios) (' || pg_temp.e(v) || ')');
  v := pg_temp.val(ae.uid, ae.em, format('select public.agente_escribe_fichero_contrato(%L)::text', num_m || '_manual.pdf'));
  r := r || pg_temp.l(v = 'true', 'C3 ENTRA: el admin de la empresa si lo cierra (' || pg_temp.e(v) || ')');
  v := pg_temp.val(se.uid, se.em, format('select public.agente_escribe_fichero_contrato(%L)::text', num_m || '_manual.pdf'));
  r := r || pg_temp.l(v = 'true', 'C4 ENTRA: ... y el super admin de la empresa (' || pg_temp.e(v) || ')');
  v := pg_temp.val(sa.uid, sa.em, format('select public.agente_escribe_fichero_contrato(%L)::text', num_m || '_manual.pdf'));
  r := r || pg_temp.l(v = 'true', 'C5 ENTRA: ... y el super admin global (' || pg_temp.e(v) || ')');
  v := pg_temp.val(ao.uid, ao.em, format('select public.agente_escribe_fichero_contrato(%L)::text', num_m || '_manual.pdf'));
  r := r || pg_temp.l(v = 'false', 'C6 NIEGA: el admin de OTRA empresa no (' || pg_temp.e(v) || ')');
  v := pg_temp.val(b.uid, b.em, format('select public.agente_escribe_fichero_contrato(%L)::text', 'pendientes/' || kM::text || '.html'));
  r := r || pg_temp.l(v = 'false', 'C7 NIEGA, COMO HOY: otro agente no envia a firmar un contrato que no ve (' || pg_temp.e(v) || ')');
  begin
    update public.contratos set bloqueado = true where id = kM2;
    v := pg_temp.val(ae.uid, ae.em, format('select public.agente_escribe_fichero_contrato(%L)::text',
           (select numero from public.contratos where id = kM2) || '_manual.pdf'));
    r := r || pg_temp.l(v = 'false', 'C8 NIEGA, COMO HOY: ni el admin sobre un contrato ya cerrado (' || pg_temp.e(v) || ')');
  exception when others then
    r := r || pg_temp.l(false, 'C8 montaje: cerrar kM2 como postgres: ' || sqlstate || ' ' || left(sqlerrm, 200));
  end;

  -- ============================================================ F. factura_anula
  v := pg_temp.val(b.uid, b.em, format('select public.factura_anula(%L)::text', fAnu));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ 'No puedes anular este documento',
       'F5 NIEGA (oraculo): un agente sin permiso sobre un documento YA anulado recibe «No puedes anular», no «ya está anulado» con su numero (' || pg_temp.e(v) || ')');
  r := r || pg_temp.l(v !~ 'ZZ-CF', 'F5b ... y el mensaje no lleva el numero');
  v := pg_temp.val(ao.uid, ao.em, format('select public.factura_anula(%L)::text', fAnu));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ 'No puedes anular este documento', 'F5c ... ni el admin de otra empresa (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select public.factura_anula(%L)::text', fAnu));
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and v ~ 'ya está anulado', 'F5d ENTRA AL MENSAJE: su autor, que si podria anularla, si lee «ya está anulado» (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select public.factura_anula(%L)::text', fEnv));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ c_anu, 'F2 NIEGA: el agente no anula su factura ENVIADA: 42501 con el mensaje nuevo (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select public.factura_anula(%L)::text', fRec));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ c_anu, 'F3 NIEGA: ... ni su RECIBI (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select public.factura_anula(%L)::text', fProf));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ c_anu, 'F3b NIEGA: ... ni su proforma ENVIADA (enviado = cualquier tipo) (' || pg_temp.e(v) || ')');
  select count(*) into n from public.facturas where id in (fEnv, fRec, fProf) and not anulada;
  r := r || pg_temp.l(n = 3, 'F3c ... y las tres siguen vivas (' || n || ')');
  v := pg_temp.val(a.uid, a.em, format('select public.factura_anula(%L)::text', fBorr));
  r := r || pg_temp.l(v !~ '^ERR' and exists (select 1 from public.facturas where id = fBorr and anulada),
       'F1 ENTRA: el agente anula su factura en BORRADOR, como hoy (' || pg_temp.e(v) || ')');
  v := pg_temp.val(ae.uid, ae.em, format('select public.factura_anula(%L)::text', fEnv));
  r := r || pg_temp.l(v !~ '^ERR' and exists (select 1 from public.facturas where id = fEnv and anulada),
       'F4 ENTRA: el admin de la empresa anula la factura enviada (' || pg_temp.e(v) || ')');
  v := pg_temp.val(ae.uid, ae.em, format('select public.factura_anula(%L)::text', fRec));
  r := r || pg_temp.l(v !~ '^ERR' and exists (select 1 from public.facturas where id = fRec and anulada),
       'F4b ENTRA: ... y el recibi (' || pg_temp.e(v) || ')');
  v := pg_temp.val(ao.uid, ao.em, format('select public.factura_anula(%L)::text', fProf));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ 'No puedes anular este documento', 'F6 NIEGA: el admin de otra empresa no anula la proforma enviada (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select public.factura_anula(%L)::text', gen_random_uuid()));
  r := r || pg_temp.l(pg_temp.err(v) = 'P0002', 'F7 COMO HOY: un id que no existe da P0002 «ya no existe» (' || pg_temp.e(v) || ')');

  -- ============================================================ X. exposicion y forma
  select count(*) into n from pg_proc p
   where p.oid in ('public.borrar_operacion(uuid)'::regprocedure, 'public.agente_escribe_fichero_contrato(text)'::regprocedure,
                   'public.factura_anula(uuid)'::regprocedure)
     and p.prosecdef and 'search_path=""' = any (p.proconfig)
     and not has_function_privilege('anon', p.oid, 'execute') and has_function_privilege('authenticated', p.oid, 'execute')
     and not has_function_privilege('public', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute');
  r := r || pg_temp.l(n = 3, 'X1 las tres: DEFINER, search_path vacio, anon NO, authenticated SI, public NO, service_role SI, como antes (' || n || ')');
  select count(*) into n from pg_proc p where p.oid = 'public.contrato_cierra_manual(uuid,text,text,text)'::regprocedure
     and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
     and has_function_privilege('service_role', p.oid, 'execute');
  r := r || pg_temp.l(n = 1, 'X2 contrato_cierra_manual sigue solo para service_role (no se toca)');
  select count(*) into n from pg_proc p where p.oid = 'public.borrar_operacion(uuid)'::regprocedure
     and (length(p.prosrc) - length(replace(p.prosrc, 'auth.email()', ''))) / length('auth.email()') = 1
     and position('auth.email()' in p.prosrc) > position('3. Autoria' in p.prosrc)
     and position('auth.email()' in p.prosrc) < position('4. Con cobros' in p.prosrc)
     and position('3. Autoria' in p.prosrc) > 0;
  r := r || pg_temp.l(n = 1, 'X3 en borrar_operacion auth.email() solo sale en la autoria de siempre: ni la herramienta, ni la visibilidad, ni la regla nueva lo usan');

  raise exception 'FIN DE PRUEBAS CF BORRAR CIERRE ANULA (se deshace todo):%', r;
end $todo$;
