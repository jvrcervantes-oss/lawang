-- PRUEBA F5b · pantallas de «por su cuenta» (30-sep-2026) — migraciones 20260930131454_f5b_venta_pantallas,
-- 20260930132411_f5b_objecion_avisa_closer y supabase/pendientes/PENDIENTE_f5b_modo_admin_cierra.sql.
-- Se ejecuta ENTERA en una llamada con execute_sql (MCP) o psql como postgres. NO ESCRIBE NADA: el bloque entero acaba
-- en `raise exception 'RES: …'` y cada caso va en un sub-bloque que acaba en excepción. Cada caso debe decir «ok».
-- NO GASTA SERIES: no da de alta contratos (nada de contrato_guarda) y el motor (comisiones_evaluar_contrato) se
-- sustituye por un stub que devuelve 0 DENTRO de la transacción (se deshace con el resto). La venta de prueba es una
-- venta real del closer T en el equipo de S, marcada «por su cuenta» solo dentro de la transacción.
-- Perfiles (se buscan, no se inventan): closer T = dortegag (equipo de Gus), SM S = gusabellan, otro usuario M =
-- santidavidse (hace de «SM nuevo»), admin A = super_admin que no es ninguno de los anteriores.
-- Los casos de venta_modo_admin salen «SIN APLICAR» mientras PENDIENTE_f5b_modo_admin_cierra.sql no esté en la base:
-- se saltan a propósito, porque la versión vieja SÍ cambiaría el modo (y reevalúa comisiones).
do $$
declare
  r text := ''; v_t text; v_state text; v_obj uuid;
  T record; S record; M record; A record;
  v_eq uuid; v_raiz uuid; v_raiz2 uuid; v_num text;
  v_modo_nuevo boolean := position('Todavía no se declara' in pg_get_functiondef('public.venta_modo_admin(uuid,text,text)'::regprocedure)) > 0;
begin
  select u.user_id, lower(u.email) e into T from public.usuarios u where lower(u.email) = 'dortegag@gmail.com' and u.activo;
  select u.user_id, lower(u.email) e into S from public.usuarios u where lower(u.email) = 'gusabellan@gmail.com' and u.activo and u.rol not in ('admin', 'super_admin');
  select u.user_id, lower(u.email) e into M from public.usuarios u where lower(u.email) = 'santidavidse@gmail.com' and u.activo and u.rol not in ('admin', 'super_admin');
  select u.user_id, lower(u.email) e into A from public.usuarios u
   where u.rol = 'super_admin' and u.activo and lower(u.email) not in (T.e, S.e, M.e) order by u.email limit 1;
  select ev.id into v_eq from public.equipos_venta ev where lower(ev.manager_email) = S.e and ev.activo limit 1;
  select k.contrato_id into v_raiz from public.contrato_closer k join public.contratos c on c.id = k.contrato_id and c.contrato_padre_id is null
   where lower(k.closer_email) = T.e and k.equipo_id = v_eq and k.equipo_congelado_en is not null and k.modo is null
   order by c.created_at desc limit 1;
  select k.contrato_id into v_raiz2 from public.contrato_closer k join public.contratos c on c.id = k.contrato_id and c.contrato_padre_id is null
   where lower(k.closer_email) = T.e and k.modo is null and k.contrato_id <> v_raiz order by c.created_at desc limit 1;
  if T.user_id is null or S.user_id is null or M.user_id is null or A.user_id is null or v_raiz is null or v_raiz2 is null then
    raise exception 'RES: falta base (T %, S %, M %, A %, venta %, venta2 %)', T.user_id is not null, S.user_id is not null,
      M.user_id is not null, A.user_id is not null, v_raiz is not null, v_raiz2 is not null;
  end if;
  if coalesce((select i.modo_obligatorio from public.comisiones_interruptor i where i.id), false) then
    raise exception 'RES: el interruptor ya está encendido: esta prueba asume el estado de 30-sep (apagado)';
  end if;
  select c.numero into v_num from public.contratos c where c.id = v_raiz;

  -- montaje (se deshace al final): motor → stub; la venta de T pasa a «por su cuenta» con 7 días para objetar
  execute format('create or replace function public.comisiones_evaluar_contrato(%s) returns integer language sql as $s$ select 0 $s$',
                 pg_get_function_arguments('public.comisiones_evaluar_contrato(uuid)'::regprocedure));
  perform set_config('app.via_modo_admin', 'on', true);
  update public.contrato_closer set modo = 'propia', modo_origen = 'contacto_personal', modo_declarado_en = now(),
         modo_declarado_por = T.e, modo_espera_hasta = now() + interval '7 days'
   where contrato_id = v_raiz;
  perform set_config('app.via_modo_admin', '', true);

  -- 1 · el SM de hoy ve la venta en la bandeja y la cuenta en la cuota
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', S.user_id, 'email', S.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_t := format('%s/%s', (select count(*) from public.ventas_por_su_cuenta_equipo() f where f.raiz_id = v_raiz and f.equipo_id = v_eq),
                  (select count(*) from public.ventas_por_su_cuenta_cuota() q where q.closer_email = T.e and q.equipo_id = v_eq and q.por_su_cuenta >= 1));
    raise exception '%', v_t;
  exception when others then r := r || '1 SM ve=' || sqlerrm || case when sqlerrm = '1/1' then ' ok; ' else ' FALLO; ' end; end;

  -- 2 · el closer no ve la bandeja ni la cuota, y no objeta (42501)
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', T.user_id, 'email', T.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_t := format('%s/%s', (select count(*) from public.ventas_por_su_cuenta_equipo()), (select count(*) from public.ventas_por_su_cuenta_cuota()));
    begin
      perform public.venta_objecion_crear(v_raiz, 'prueba F5b');
      v_t := v_t || '/sin error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_t || '/' || v_state; end;
    raise exception '%', v_t;
  exception when others then r := r || '2 closer=' || sqlerrm || case when sqlerrm = '0/0/42501' then ' ok; ' else ' FALLO; ' end; end;

  -- 3 · cambia el SM del equipo: el anterior deja de ver y no objeta; el nuevo ve
  begin
    update public.equipos_venta set manager_email = M.e where id = v_eq;
    perform set_config('request.jwt.claims', json_build_object('sub', S.user_id, 'email', S.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_t := format('%s/%s', (select count(*) from public.ventas_por_su_cuenta_equipo() f where f.raiz_id = v_raiz),
                  (select count(*) from public.ventas_por_su_cuenta_cuota() q where q.equipo_id = v_eq));
    begin
      perform public.venta_objecion_crear(v_raiz, 'prueba F5b');
      v_t := v_t || '/sin error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_t || '/' || v_state; end;
    perform set_config('request.jwt.claims', json_build_object('sub', M.user_id, 'email', M.e, 'role', 'authenticated')::text, true);
    v_t := v_t || '/' || (select count(*) from public.ventas_por_su_cuenta_equipo() f where f.raiz_id = v_raiz);
    raise exception '%', v_t;
  exception when others then r := r || '3 SM anterior=' || sqlerrm || case when sqlerrm = '0/0/42501/1' then ' ok; ' else ' FALLO; ' end; end;

  -- 4 · equipo desactivado: su SM deja de verlo y no objeta
  begin
    update public.equipos_venta set activo = false where id = v_eq;
    perform set_config('request.jwt.claims', json_build_object('sub', S.user_id, 'email', S.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_t := (select count(*) from public.ventas_por_su_cuenta_equipo() f where f.raiz_id = v_raiz)::text;
    begin
      perform public.venta_objecion_crear(v_raiz, 'prueba F5b');
      v_t := v_t || '/sin error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_t || '/' || v_state; end;
    raise exception '%', v_t;
  exception when others then r := r || '4 equipo inactivo=' || sqlerrm || case when sqlerrm = '0/42501' then ' ok; ' else ' FALLO; ' end; end;

  -- 5 · el SM objeta: avisa al closer (texto propio) y a administración; el SM no resuelve ni cambia el modo (42501);
  --     el admin resuelve «mantener por su cuenta»
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', S.user_id, 'email', S.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_obj := public.venta_objecion_crear(v_raiz, 'prueba F5b: el cliente vino por la campaña');
    begin perform public.venta_objecion_resolver(v_obj, 'mantener_propia', 'prueba'); v_t := 'sin error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_state; end;
    begin perform public.venta_modo_admin(v_raiz, 'equipo', 'prueba'); v_t := v_t || '/sin error';
    exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_t || '/' || v_state; end;
    perform set_config('request.jwt.claims', json_build_object('sub', A.user_id, 'email', A.e, 'role', 'authenticated')::text, true);
    perform public.venta_objecion_resolver(v_obj, 'mantener_propia', 'prueba F5b');
    reset role;
    v_t := v_t || format('/%s/%s/%s/%s',
      (select count(*) from public.notificaciones n where n.contrato_id = v_raiz and n.tipo = 'venta_objecion' and lower(n.destinatario) = T.e
          and n.detalle = 'Tu Sales Manager ha objetado que la venta ' || v_num || ' sea por tu cuenta; la comisión queda en espera hasta que la resuelva administración.'),
      (select count(*) > 0 from public.notificaciones n join public.usuarios u on lower(u.email) = lower(n.destinatario) and u.rol in ('admin', 'super_admin')
          where n.contrato_id = v_raiz and n.tipo = 'venta_objecion'),
      (select r2.estado || ':' || r2.resolucion from public.reclamaciones_venta_propia r2 where r2.id = v_obj),
      (select k.modo_fijado_admin from public.contrato_closer k where k.contrato_id = v_raiz));
    raise exception '%', v_t;
  exception when others then r := r || '5 objeta/resuelve=' || sqlerrm || case when sqlerrm = '42501/42501/1/t/rechazada:mantener_propia/t' then ' ok; ' else ' FALLO; ' end; end;

  -- 6 · venta_modo_admin (admin): interruptor apagado + venta sin modo → 22023; p_modo 'propia' → 22023
  if not v_modo_nuevo then
    r := r || '6 modo_admin=SIN APLICAR (PENDIENTE_f5b_modo_admin_cierra.sql) FALLO; ';
  else
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', A.user_id, 'email', A.e, 'role', 'authenticated')::text, true);
      set local role authenticated;
      begin perform public.venta_modo_admin(v_raiz2, 'equipo', 'prueba F5b'); v_t := 'sin error';
      exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_state || case when sqlerrm like 'Todavía no se declara%' then '' else '(' || sqlerrm || ')' end; end;
      begin perform public.venta_modo_admin(v_raiz, 'propia', 'prueba F5b'); v_t := v_t || '/sin error';
      exception when others then get stacked diagnostics v_state = returned_sqlstate; v_t := v_t || '/' || v_state; end;
      raise exception '%', v_t;
    exception when others then r := r || '6 modo_admin=' || sqlerrm || case when sqlerrm = '22023/22023' then ' ok; ' else ' FALLO; ' end; end;
  end if;

  -- 7 · modo_obligatorio_activo(): false con sesión (interruptor apagado) y false sin sesión
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', S.user_id, 'email', S.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_t := public.modo_obligatorio_activo()::text;
    perform set_config('request.jwt.claims', '{}', true);
    v_t := v_t || '/' || public.modo_obligatorio_activo()::text;
    raise exception '%', v_t;
  exception when others then r := r || '7 interruptor=' || sqlerrm || case when sqlerrm = 'false/false' then ' ok; ' else ' FALLO; ' end; end;

  raise exception 'RES: %', r;
end $$;
