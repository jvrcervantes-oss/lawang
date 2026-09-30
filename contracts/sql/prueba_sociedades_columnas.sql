-- destructivo-ok: prueba que se deshace sola (raise exception final); no escribe nada permanente.
-- PRUEBA — AXW-116 (20260930220000_sociedades_select_por_columnas). 30-sep-2026.
-- Criterio: un comprador del portal NO lee creado_por/actualizado_por/creado_en/actualizado_en de `sociedades` (ni con select *);
-- todo lector legitimo sigue leyendo lo que necesita (agente, admin, super admin, generacion de documentos por la sesion del usuario,
-- edges con service_role); las RPC definer de la pantalla nueva siguen operando. Se ejecuta ENTERA como postgres (execute_sql), cambia de
-- rol con claims reales y termina en `raise exception 'FIN…'` (deshace todo). No escribe filas reales.
create or replace function public._zz_intenta(q text) returns text language plpgsql as $$
declare st text; m text;
begin
  execute q;
  return 'ok';
exception when others then
  get stacked diagnostics st = returned_sqlstate, m = message_text;
  return st || '|' || left(m, 120);
end $$;
grant execute on function public._zz_intenta(text) to public;

do $$
declare
  r text := '';
  u_sa uuid := gen_random_uuid(); m_sa text := 'super.col@pruebas.test';
  u_ad uuid := gen_random_uuid(); m_ad text := 'admin.col@pruebas.test';
  u_ag uuid := gen_random_uuid(); m_ag text := 'agente.col@pruebas.test';
  u_po uuid := gen_random_uuid(); m_po text := 'portal.col@pruebas.test';
  res text; who record; k text; ct uuid;
begin
  execute 'set local session_replication_role = replica';
  insert into auth.users (id, email, aud, role) values
    (u_sa, m_sa, 'authenticated', 'authenticated'), (u_ad, m_ad, 'authenticated', 'authenticated'),
    (u_ag, m_ag, 'authenticated', 'authenticated'), (u_po, m_po, 'authenticated', 'authenticated');
  insert into public.usuarios (user_id, email, nombre, rol, herramientas, activo, numero_usuario) values
    (u_sa, m_sa, 'Super Col', 'super_admin', '{}', true, 'USR-PRBCO-1'),
    (u_ad, m_ad, 'Admin Col', 'admin', array['ajustes'], true, 'USR-PRBCO-2'),
    (u_ag, m_ag, 'Agente Col', 'agente', array['ajustes'], true, 'USR-PRBCO-3');
  execute 'set local session_replication_role = origin';
  select id into ct from public.contratos limit 1;

  -- A. Los 4 perfiles con sesion: lo legitimo pasa, lo de auditoria no.
  for who in select * from (values ('comprador del portal', u_po, m_po), ('agente', u_ag, m_ag), ('admin', u_ad, m_ad), ('super admin', u_sa, m_sa)) x(q, uid, mail) loop
    perform set_config('request.jwt.claims', json_build_object('sub', who.uid, 'email', who.mail, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    res := public._zz_intenta($q$ select clave,label,razon,marca,npwp,npwp_label,nib,domicilio,rep,logo,logo_alto,emisor_debajo,folio,tinta,es_indonesia from public.sociedades where activa = true order by orden $q$);
    r := r || format(E'\nA1 %s: lectura de cargarSociedades (15 col + filtro activa + orden) → %s', who.q, case when res = 'ok' then 'ok' else 'FALLA ' || res end);
    res := public._zz_intenta($q$ select clave,razon,label,activa from public.sociedades order by orden $q$);
    r := r || format(E'\nA2 %s: lectura de datos.js/editores.js (clave,razon,label,activa) → %s', who.q, case when res = 'ok' then 'ok' else 'FALLA ' || res end);
    res := public._zz_intenta($q$ select s.clave, s.razon from public.sociedades s where s.clave = 'x' $q$);
    r := r || format(E'\nA3 %s: lectura de contrato_sociedad_existe / bot_pendientes (clave,razon) → %s', who.q, case when res = 'ok' then 'ok' else 'FALLA ' || res end);
    foreach k in array array['creado_por', 'actualizado_por', 'creado_en', 'actualizado_en', '*'] loop
      res := public._zz_intenta(format('select %s from public.sociedades limit 1', k));
      r := r || format(E'\nA4 %s: select %s → %s', who.q, k, case when res like '42501%' then 'cerrado (ok)' else 'FALLA ' || res end);
    end loop;
    execute 'reset role';
  end loop;

  -- B. La pantalla nueva y el instancia_marca siguen operando (RPC definer, no dependen del grant de columnas).
  perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'email', m_sa, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  res := public._zz_intenta($q$ select public.sociedades_ajustes_datos() $q$);
  r := r || format(E'\nB1 super admin: sociedades_ajustes_datos() → %s', case when res = 'ok' then 'ok' else 'FALLA ' || res end);
  res := public._zz_intenta($q$ select public.instancia_marca() $q$);
  r := r || format(E'\nB2 super admin: instancia_marca() → %s', case when res = 'ok' then 'ok' else 'FALLA ' || res end);
  res := public._zz_intenta($q$ select public.sociedad_guarda('prueba_col_a', '{"razon":"PT PRUEBA COL","domicilio":"Jl. Prueba 1","npwp":"99.999.999.9-999.999","npwp_label":"NPWP","rep":"Rep Prueba","marca":"PRUEBA","label":"PT Prueba Col","es_indonesia":true,"motivo":"prueba AXW-116"}'::jsonb, true) $q$);
  r := r || format(E'\nB3 super admin: sociedad_guarda (alta, se deshace) → %s', case when res = 'ok' then 'ok' else 'FALLA ' || res end);
  if ct is not null then
    res := public._zz_intenta(format('select * from public.bot_pendientes(%L::uuid)', ct));
    r := r || format(E'\nB4 super admin: bot_pendientes(un contrato) → %s', case when res = 'ok' then 'ok' else 'FALLA ' || res end);
  end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'email', m_ag, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  res := public._zz_intenta($q$ select public.sociedades_ajustes_datos() $q$);
  r := r || format(E'\nB5 agente: sociedades_ajustes_datos() → %s', case when res like '42501%' then 'rechazado (ok, solo super admin)' else 'REVISAR ' || res end);
  execute 'reset role';

  -- C. anon nunca leyo; service_role (edges de firma / factura / ficheros) sigue leyendo todo.
  execute 'set local role anon';
  res := public._zz_intenta($q$ select clave from public.sociedades limit 1 $q$);
  r := r || format(E'\nC1 anon: select clave → %s', case when res like '42501%' then 'cerrado (ok)' else 'FALLA ' || res end);
  execute 'reset role';
  execute 'set local role service_role';
  res := public._zz_intenta($q$ select clave,label,razon,marca,npwp,npwp_label,nib,domicilio,rep,logo,logo_alto,emisor_debajo,folio,tinta,creado_por,actualizado_por from public.sociedades where activa = true $q$);
  r := r || format(E'\nC2 service_role (edges): lectura completa → %s', case when res = 'ok' then 'ok' else 'FALLA ' || res end);
  execute 'reset role';

  raise exception E'FIN DE PRUEBAS (deshecho).%\n%', r, case when r like '%FALLA%' then '>>> HAY FALLOS' else '>>> TODO OK' end;
end $$;
