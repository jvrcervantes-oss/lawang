-- LAW-338 L3: prueba de paridad y prueba de ataque del cierre de las 8 tablas de comisiones, equipos y gastos.
-- Se guarda aquí (revisor, 10-oct-2026) para poder repetirla justo antes y justo después del revoke, lo lance quien lo lance.
-- Lo ejecuta postgres (MCP execute_sql), en UNA sola llamada: las tablas temporales mueren entre llamadas. Siempre
-- termina en `raise exception` = ROLLBACK, sin dejar rastro. El resumen sale en el mensaje del error.
--
-- Cómo se usa:
--   (a) ENSAYO del cierre: [este fichero hasta «-- FIN DEL ARNÉS»] + select pg_temp.firma('antes');
--       + [supabase/por_aplicar/law338_l3_revoke.sql, o su migración] + select pg_temp.firma('despues');
--       + select pg_temp.ataque(); + [bloque RESUMEN del final].
--   (b) TRAS APLICAR el cierre: [arnés] + select pg_temp.firma('despues'); + select pg_temp.ataque(); + [RESUMEN].
--       Las huellas `agg` de cada RPC tienen que ser las mismas que dio el ensayo (a) con los mismos datos.
-- Qué mide:
--   · firma: para cada usuario ACTIVO de `usuarios`, como `authenticated` con los claims que manda la sesión real
--     (sub, role y EMAIL: las policies de equipos y condiciones usan auth.email(); sin él todo sale a cero y la paridad
--     saldría verde sin comparar nada), el md5 de lo que devuelve cada una de las 8 RPC de L3. `dif` = usuarios cuya
--     respuesta cambió entre antes y después; `firmas` = respuestas distintas (si es 1 en todas, el arnés no distingue).
--   · ataque: cada usuario × cada tabla, `select count(*)` directo como authenticated. Tras el cierre: todo 42501.
-- Los nombres de las tablas NO aparecen en el cuerpo de las funciones temporales a propósito: la comprobación previa del
-- revoke busca funciones INVOKER que las nombren, y estas (pg_temp) la harían saltar.
-- Medido el 10-oct-2026 (ensayo, 33 usuarios activos): dif=0 y err=0 en las 9 llamadas; firmas distintas: equipos 14,
-- condiciones 7, finanzas 8, operación 8; ataque 264/264 → 42501.

create temp table _firma(uid uuid, rol text, rpc text, fase text, f text);
create temp table _ataque(uid uuid, tabla text, r text);
create temp table _tablas(t text);
insert into _tablas values ('comisiones_devengadas'), ('comisiones_diferencias'), ('equipos_venta'), ('equipo_miembros'),
  ('condiciones_comision'), ('condicion_tramos'), ('gastos'), ('gasto_categorias');
create temp table _par as select
  (select id from public.gastos order by creado_en desc limit 1) g,
  (select solicitud_id from public.comisiones_devengadas where solicitud_id is not null order by created_at desc limit 1) s,
  (select id from public.condiciones_comision order by created_at desc limit 1) c,
  (select array_agg(distinct contrato_raiz_id) from (select contrato_raiz_id from public.comisiones_devengadas order by created_at desc limit 40) x) cs;
create function pg_temp.llama(q text) returns text language plpgsql as $f$
declare r text;
begin
  perform set_config('role', 'authenticated', true);
  begin
    execute q into r;
  exception when others then r := 'ERR:' || sqlstate;
  end;
  perform set_config('role', 'postgres', true);
  return case when r like 'ERR:%' then r else md5(coalesce(r, '<null>')) end;
end $f$;
create function pg_temp.firma(fase text) returns void language plpgsql as $f$
declare u record; p record; q text; nombre text; qs text[];
begin
  select * into p from _par;
  qs := array['select public.equipos_datos()::text', 'select public.condiciones_comision_datos()::text',
    'select public.comisiones_reparto_datos()::text', 'select public.finanzas_panel_datos(true, true)::text',
    'select public.finanzas_panel_datos(false, false)::text', format('select public.gasto_estado_datos(%L)::text', p.g),
    format('select public.comision_de_solicitud_datos(%L)::text', p.s), format('select public.condicion_usos_datos(%L)::text', p.c),
    format('select public.operacion_comisiones_datos(%L::uuid[])::text', p.cs)];
  for u in select user_id, rol, email from public.usuarios where activo loop
    perform set_config('request.jwt.claims', json_build_object('sub', u.user_id, 'role', 'authenticated', 'email', u.email)::text, true);
    foreach q in array qs loop
      nombre := substring(q from 'public\.(\w+)\(') || case when q like '%(false, false)%' then '_ff' else '' end;
      insert into _firma values (u.user_id, u.rol, nombre, fase, pg_temp.llama(q));
    end loop;
  end loop;
end $f$;
create function pg_temp.ataque() returns void language plpgsql as $f$
declare u record; t text;
begin
  for u in select user_id, email from public.usuarios where activo loop
    perform set_config('request.jwt.claims', json_build_object('sub', u.user_id, 'role', 'authenticated', 'email', u.email)::text, true);
    for t in select x.t from _tablas x loop
      insert into _ataque values (u.user_id, t, pg_temp.llama(format('select count(*)::text from public.%I', t)));
    end loop;
  end loop;
end $f$;
-- FIN DEL ARNÉS

-- RESUMEN (último bloque de la llamada; con solo la fase «despues», `dif` sale 0 y vale `agg`):
do $$ declare m text; begin
  select string_agg(x, ' · ') into m from (
    select d.rpc || ': ' || count(*) || 'u dif=' || count(*) filter (where a.f is not null and a.f <> d.f)
           || ' err=' || count(*) filter (where d.f like 'ERR:%') || ' firmas=' || count(distinct d.f)
           || ' agg=' || left(md5(string_agg(d.uid::text || d.f, ',' order by d.uid)), 10) x
      from _firma d left join _firma a on a.uid = d.uid and a.rpc = d.rpc and a.fase = 'antes'
     where d.fase = 'despues' group by d.rpc order by d.rpc) s;
  m := coalesce(m, '(sin fase despues)') || ' ## ataque: ' || (select count(*) || ' intentos, ' || count(*) filter (where r = 'ERR:42501')
       || ' 42501, ' || count(*) filter (where r not like 'ERR:%') || ' leen' from _ataque);
  raise exception 'L3 PARIDAD (rollback) %', m;
end $$;
