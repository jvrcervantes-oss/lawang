-- Foto de no-regresion del BLOQUE 3 (clientes, KYC, comunicacion, CRM/leads, notificaciones) del encargo de empresas (7-oct-2026).
-- Por cada usuario (JWT con email + set local role authenticated) saca un md5 de LOS IDS que ve en cada tabla y de lo que devuelven las funciones del bloque.
-- Las tablas que crecen solas (notificaciones, correos, envios, leads) se cortan en una fecha fija (v_corte) para que el antes y el despues sean comparables.
-- Termina en raise (sin rastro). Debe dar el MISMO md5 antes y despues de cada migracion del bloque 3 (los 34 usuarios no cambian).
-- Detalle: poniendo v_detalle = 'email@...' imprime los hashes campo a campo de ese usuario, para localizar la diferencia.
-- destructivo-ok: solo lectura (comprador_ficha inserta un registro de acceso, que el raise final revierte)
do $t$
declare
  u record; pr text[]; q text; h text; o text; todo text := ''; n int := 0;
  v_corte text := '2026-10-07 02:00:00+00';
  v_detalle text := '';
  cl1 uuid; cl2 uuid; cl3 uuid; cm uuid;
begin
  select id into cl1 from public.clients order by id limit 1 offset 3;
  select id into cl2 from public.clients order by id limit 1 offset 100;
  select id into cl3 from public.clients order by id limit 1 offset 150;
  select id into cm from public.comunicados order by id limit 1;
  pr := array[
    'select id from public.clients',
    'select id from public.documents',
    format('select id from public.notificaciones where creado_en <= %L', v_corte),
    'select id from public.comunicados',
    format('select id from public.comunicado_envios where encolado_en <= %L', v_corte),
    format('select id from public.correos_enviados where enviado_en <= %L', v_corte),
    'select id from public.portal_accesos',
    'select id from public.referidos_contactos',
    'select id from public.solicitudes_colaborador',
    'select clave from public.lead_estados',
    'select id from public.compradores_lista()',
    'select id from public.comprador_buscar(''mar'')',
    'select id from public.comprador_buscar(''gmail'')',
    format('select concat_ws(''|'',id,full_name,passport_number,propietario) from public.comprador_ficha(%L)', cl1),
    format('select concat_ws(''|'',id,full_name,passport_number,propietario) from public.comprador_ficha(%L)', cl2),
    format('select concat_ws(''|'',id,full_name,passport_number,propietario) from public.comprador_ficha(%L)', cl3),
    format('select id from public.crm_leads() where created_at <= %L', v_corte),
    'select concat_ws(''|'',es_gestor,campanas::text) from public.crm_mi_alcance()',
    'select campaign_id from public.crm_campanas()',
    'select adset_id from public.crm_campanas_conjuntos()',
    format('select concat_ws(''|'',cuando,campana,accion) from public.crm_automatismos(500) where cuando <= %L', v_corte),
    'select concat_ws(''|'',source,closers::text) from public.crm_reparto_config()',
    'select concat_ws(''|'',closer_email,puesto,contratos,firmado) from public.crm_ranking_closers(false)',
    'select contrato_id from public.crm_contratos_para_atribuir(false)',
    'select semana::text from public.crm_serie_semanal(8)',
    'select md5(public.comunicacion_datos(100, null)::text)',
    format('select md5(public.comunicado_datos(%L)::text)', cm),
    'select md5(public.referidos_datos(100, null)::text)',
    'select md5(public.solicitudes_alta_datos(60, null)::text)'
  ];
  for u in select user_id, email from public.usuarios order by email loop
    perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
    set local role authenticated;
    o := '';
    foreach q in array pr loop
      begin
        execute 'select md5(coalesce(string_agg(x::text, '','' order by x::text),'''')) from (' || q || ') t(x)' into h;
        o := o || left(h, 5) || ' ';
      exception when others then o := o || 'E' || sqlstate || ' ';
      end;
    end loop;
    reset role;
    if v_detalle = '' then todo := todo || left(md5(o), 8) || ' ' || u.email || E'\n';
    elsif u.email = v_detalle then todo := o; end if;
    n := n + 1;
  end loop;
  raise exception E'FOTOB3 usuarios=%\nMD5=%\n%', n, md5(todo), todo;
end $t$;
