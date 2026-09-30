-- PRUEBA — F6 «Mi equipo» y condiciones (30-sep-2026): migraciones 20260930070138, 071319, 075711, 082130, 085658 y 091729.
-- Se ejecuta ENTERA en una llamada con execute_sql (MCP) o psql como postgres. NO ESCRIBE NADA: cada caso va en un
-- sub-bloque que acaba en excepción (Postgres deshace lo que hizo, claims incluidos) y el bloque entero termina en
-- `raise exception 'RES: …'`. Cada caso debe decir «ok»; un «FALLO» es una regla de equipo o de dinero que no se cumple.
-- La identidad se pone con request.jwt.claims (las RPC son SECURITY DEFINER y deciden por auth.uid()/auth.email()).
-- No llama a contrato_guarda ni a nada que numere (series): solo equipo_miembros, plantilla, interruptor y condiciones.
-- Las condiciones se prueban en un alcance SINTÉTICO (equipo real + nivel team_lead + closer x@prueba.invalid), sin
-- ventas ni devengos; solo el caso del recuento retroactivo usa un alcance real (condición de manager de un equipo).
-- La base se busca, no se inventa: si falta un perfil, la prueba lo dice en vez de dar un falso «ok».
-- Los booleanos que pasan por format() salen como t/f; los que se concatenan con ||, como true/false.
do $$
declare
  r text := ''; v_t text; v_h text; v_n int; v_id uuid; v_a uuid; v_b uuid; v_c uuid; v_x record;
  v_hoy date := (now() at time zone 'Asia/Makassar')::date;
  v_eq uuid; v_sm record; v_sm2 record; v_adm record; v_pm record; v_otro record; v_libre record; v_closer record;
  v_tr jsonb := '[{"disparador_tipo":"contrato_firmado","pct_tramo":100}]';
  v_sin jsonb; v_sin2 jsonb; v_ret record; v_d date; v_esperado int;
  v_dev0 text := (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(d)::text, '|' order by d.id), '')) from public.comisiones_devengadas d);
  v_sp0 text := (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(s)::text, '|' order by s.id), '')) from public.solicitudes_pago s);
begin
  -- perfiles
  select ev.id, u.user_id, lower(u.email) e into v_x from public.equipos_venta ev
    join public.usuarios u on lower(u.email) = lower(ev.manager_email) and u.activo and u.rol = 'sales_manager'
   where ev.activo order by ev.created_at limit 1;
  v_eq := v_x.id;
  select u.user_id, lower(u.email) e into v_sm from public.usuarios u where u.user_id = v_x.user_id;
  select u.user_id, lower(u.email) e into v_sm2 from public.usuarios u where u.activo and u.rol = 'sales_manager' and u.user_id <> v_sm.user_id order by u.email limit 1;
  select u.user_id, lower(u.email) e into v_adm from public.usuarios u where u.activo and u.rol = 'super_admin' order by u.email limit 1;
  select u.user_id, lower(u.email) e into v_pm from public.usuarios u where u.activo and u.rol = 'project_manager' order by u.email limit 1;
  select u.user_id, lower(u.email) e into v_otro from public.equipo_miembros em join public.usuarios u on lower(u.email) = lower(em.closer_email) and u.activo
   where em.equipo_id <> v_eq and (em.hasta is null or em.hasta >= v_hoy) and u.rol = 'agente' order by u.email limit 1;
  select u.user_id, lower(u.email) e into v_libre from public.usuarios u
   where u.activo and u.rol = 'agente' and u.user_id is not null and public._equipo_candidato_valido(u.email) is null order by u.email limit 1;
  select u.user_id, lower(u.email) e into v_closer from public.equipo_miembros em join public.usuarios u on lower(u.email) = lower(em.closer_email) and u.activo
   where (em.hasta is null or em.hasta >= v_hoy) and u.rol = 'agente'
   order by (em.equipo_id = v_eq) desc, u.email limit 1;
  if v_eq is null or v_sm2.user_id is null or v_adm.user_id is null or v_pm.user_id is null or v_otro.user_id is null
     or v_libre.user_id is null or v_closer.user_id is null then
    raise exception 'RES: falta un perfil (equipo+SM %, otro SM %, admin %, PM %, de otro equipo %, libre %, closer %)',
      v_eq is not null, v_sm2.user_id is not null, v_adm.user_id is not null, v_pm.user_id is not null,
      v_otro.user_id is not null, v_libre.user_id is not null, v_closer.user_id is not null;
  end if;

  -- M1 · el SM entra solo por id (equipo_miembro_anade): a sí mismo, a otro SM, a admin, a un PM, a alguien de otro
  --      equipo o a un id que no es de nadie → todos rechazados con 42501 y el MISMO mensaje genérico (no revela
  --      rol ni estado de terceros)
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_sm.user_id, 'email', v_sm.e, 'role', 'authenticated')::text, true);
    v_t := '';
    for v_x in select u from unnest(array[v_sm.user_id, v_sm2.user_id, v_adm.user_id, v_pm.user_id, v_otro.user_id, gen_random_uuid()]) u loop
      begin perform public.equipo_miembro_anade(v_eq, v_x.u); v_t := v_t || 'pasa/';
      exception when others then
        v_t := v_t || case when sqlstate = '42501' and sqlerrm = 'Esa persona no se puede añadir a tu equipo' then 'gen/' else sqlstate || ':' || sqlerrm || '/' end;
      end;
    end loop;
    raise exception '%', v_t;
  exception when others then r := r || 'M1 rechazos genericos=' || sqlerrm || case when sqlerrm = 'gen/gen/gen/gen/gen/gen/' then ' ok; ' else ' FALLO; ' end; end;

  -- M2 · el SM ya no usa equipo_miembro_guarda (por email): rechazo 42501 que remite a administración
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_sm.user_id, 'email', v_sm.e, 'role', 'authenticated')::text, true);
    begin perform public.equipo_miembro_guarda(null, v_eq, v_libre.e, v_hoy, null); v_t := 'pasa';
    exception when others then v_t := case when sqlstate = '42501' and sqlerrm like '%es de administración%' then 'no' else sqlstate || ':' || sqlerrm end; end;
    raise exception '%', v_t;
  exception when others then r := r || 'M2 SM por email=' || sqlerrm || case when sqlerrm = 'no' then ' ok; ' else ' FALLO; ' end; end;

  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_sm.user_id, 'email', v_sm.e, 'role', 'authenticated')::text, true);
    select format('%s/%s/%s/%s',
      coalesce(bool_and(c.email like '_***@%'), true),
      not exists (select 1 from public.equipo_candidatos_sm(v_eq) c2 join public.usuarios u on u.user_id = c2.usuario
                   where u.rol in ('sales_manager', 'admin', 'super_admin', 'project_manager')
                      or exists (select 1 from public.equipo_miembros em where lower(em.closer_email) = lower(u.email) and (em.hasta is null or em.hasta >= v_hoy))),
      exists (select 1 from public.equipo_candidatos_sm(v_eq) c3 where c3.usuario = v_libre.user_id),
      coalesce(to_regprocedure('public.equipo_candidatos(uuid)') is null
               or not has_function_privilege('authenticated', to_regprocedure('public.equipo_candidatos(uuid)'), 'execute'), false))
      into v_t from public.equipo_candidatos_sm(v_eq) c;
    v_id := public.equipo_miembro_anade(v_eq, v_libre.user_id);
    select v_t || '/' || (m.desde = v_hoy and lower(m.closer_email) = v_libre.e) into v_t from public.equipo_miembros m where m.id = v_id;
    raise exception '%', v_t;
  exception when others then r := r || 'M3 candidatos y alta por id=' || sqlerrm || case when sqlerrm = 't/t/t/t/true' then ' ok; ' else ' FALLO; ' end; end;

  -- M4 · admin retroactiva: sin confirmar → rechazo; con recuento distinto → rechazo; con el de la vista previa → ok
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    v_n := (public.equipo_miembro_vista_previa(null, v_eq, v_libre.e, v_hoy - 30, null) ->> 'n')::int;
    v_t := '';
    begin perform public.equipo_miembro_guarda(null, v_eq, v_libre.e, v_hoy - 30, null); v_t := v_t || 'pasa/'; exception when others then v_t := v_t || 'no/'; end;
    begin perform public.equipo_miembro_guarda_confirmada(null, v_eq, v_libre.e, v_hoy - 30, null, v_n + 1); v_t := v_t || 'pasa/'; exception when others then v_t := v_t || 'no/'; end;
    begin perform public.equipo_miembro_guarda_confirmada(null, v_eq, v_libre.e, v_hoy - 30, null, v_n); v_t := v_t || 'pasa'; exception when others then v_t := v_t || 'no:' || sqlerrm; end;
    raise exception '%', v_t;
  exception when others then r := r || 'M4 retroactiva=' || sqlerrm || case when sqlerrm = 'no/no/pasa' then ' ok; ' else ' FALLO; ' end; end;

  -- P1 · plantilla: suma 100 → ok; 90 → rechazo; quitar un rol (queda uno al 100) → ok y se lee uno
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_sm.user_id, 'email', v_sm.e, 'role', 'authenticated')::text, true);
    v_t := '';
    begin perform public.plantilla_reparto_guarda(v_eq, '[{"rol_tipo":"closer","rol_nombre":"Closer","pct":60},{"rol_tipo":"setter","rol_nombre":"Setter","pct":40}]');
          v_t := v_t || (select count(*) from public.plantilla_reparto_lee(v_eq)) || '/'; exception when others then v_t := v_t || 'no:' || sqlerrm || '/'; end;
    begin perform public.plantilla_reparto_guarda(v_eq, '[{"rol_tipo":"closer","rol_nombre":"Closer","pct":60},{"rol_tipo":"setter","rol_nombre":"Setter","pct":30}]');
          v_t := v_t || 'pasa/'; exception when others then v_t := v_t || 'no/'; end;
    begin perform public.plantilla_reparto_guarda(v_eq, '[{"rol_tipo":"closer","rol_nombre":"Closer","pct":100}]');
          v_t := v_t || (select count(*) from public.plantilla_reparto_lee(v_eq)); exception when others then v_t := v_t || 'no:' || sqlerrm; end;
    raise exception '%', v_t;
  exception when others then r := r || 'P1 plantilla=' || sqlerrm || case when sqlerrm = '2/no/1' then ' ok; ' else ' FALLO; ' end; end;

  -- I1 · interruptor «mis closers ven su comisión»: el SM sí, un closer no
  begin
    v_t := '';
    perform set_config('request.jwt.claims', json_build_object('sub', v_sm.user_id, 'email', v_sm.e, 'role', 'authenticated')::text, true);
    begin perform public.equipo_closers_ven_comision(v_eq, not (select closers_ven_comision from public.equipos_venta where id = v_eq)); v_t := v_t || 'pasa/';
    exception when others then v_t := v_t || 'no:' || sqlerrm || '/'; end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_closer.user_id, 'email', v_closer.e, 'role', 'authenticated')::text, true);
    begin perform public.equipo_closers_ven_comision(v_eq, true); v_t := v_t || 'pasa'; exception when others then v_t := v_t || 'no'; end;
    raise exception '%', v_t;
  exception when others then r := r || 'I1 interruptor=' || sqlerrm || case when sqlerrm = 'pasa/no' then ' ok; ' else ' FALLO; ' end; end;

  -- condiciones en alcance sintético, como admin
  v_sin := jsonb_build_object('equipo_id', v_eq, 'nivel', 'team_lead', 'closer_email', 'x@prueba.invalid', 'pct_comision', 2, 'base_calculo', 'precio_total');

  -- C1 · cerrar = activo false + fin hoy; borrar una futura → desaparece; borrar una vigente → rechazo
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    v_a := public.condicion_comision_guarda(null, v_sin || jsonb_build_object('vigente_desde', v_hoy), v_tr);
    perform public.condicion_comision_activa(v_a, false);
    select format('%s', not c.activo and c.vigente_hasta = v_hoy) into v_t from public.condiciones_comision c where c.id = v_a;
    v_b := public.condicion_comision_guarda(null, v_sin || jsonb_build_object('vigente_desde', v_hoy + 10), v_tr);
    perform public.condicion_comision_borra(v_b);
    v_t := v_t || '/' || (not exists (select 1 from public.condiciones_comision where id = v_b));
    v_c := public.condicion_comision_guarda(null, v_sin || jsonb_build_object('vigente_desde', v_hoy + 1), v_tr);
    begin perform public.condicion_comision_borra(v_a); v_t := v_t || '/pasa'; exception when others then v_t := v_t || '/no'; end;
    raise exception '%', v_t;
  exception when others then r := r || 'C1 cerrar/borrar futura/borrar vigente=' || sqlerrm || case when sqlerrm = 't/true/no' then ' ok; ' else ' FALLO; ' end; end;

  -- C2 · caso a: se editan las cifras de la predecesora (log con motivo nulo) y luego se borra la sustituta:
  --      la predecesora vuelve a estar en vigor (antes se perdía la pista del log)
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    v_a := public.condicion_comision_guarda(null, v_sin || jsonb_build_object('vigente_desde', v_hoy - 5), v_tr);
    v_b := public.condicion_comision_guarda(null, v_sin || jsonb_build_object('vigente_desde', v_hoy + 10), v_tr);
    select format('%s/%s', (select vigente_hasta = v_hoy + 9 from public.condiciones_comision where id = v_a),
                           (select sustituye_a = v_a from public.condiciones_comision where id = v_b)) into v_t;
    perform public.condicion_comision_guarda(v_a, v_sin || jsonb_build_object('vigente_desde', v_hoy - 5, 'pct_comision', 3), v_tr);
    perform public.condicion_comision_borra(v_b);
    set constraints all immediate;
    select v_t || '/' || (c.activo and c.vigente_hasta is null and c.pct_comision = 3) into v_t from public.condiciones_comision c where c.id = v_a;
    raise exception '%', v_t;
  exception when others then r := r || 'C2 editar predecesora y borrar sustituta=' || sqlerrm || case when sqlerrm = 't/t/true' then ' ok; ' else ' FALLO; ' end; end;

  -- C3 · caso b: una sustituta que empezó HOY sin devengos se retrasa y luego se adelanta: nunca queda hueco
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    v_a := public.condicion_comision_guarda(null, v_sin || jsonb_build_object('vigente_desde', v_hoy - 5), v_tr);
    v_b := public.condicion_comision_guarda(null, v_sin || jsonb_build_object('vigente_desde', v_hoy), v_tr);
    perform public.condicion_comision_guarda(v_b, v_sin || jsonb_build_object('vigente_desde', v_hoy + 3), v_tr);
    select format('%s', (select vigente_hasta from public.condiciones_comision where id = v_a) = v_hoy + 2) into v_t;
    perform public.condicion_comision_guarda(v_b, v_sin || jsonb_build_object('vigente_desde', v_hoy - 2), v_tr);
    select v_t || '/' || ((select vigente_hasta from public.condiciones_comision where id = v_a) = v_hoy - 3) into v_t;
    raise exception '%', v_t;
  exception when others then r := r || 'C3 mover sustituta sin hueco=' || sqlerrm || case when sqlerrm = 't/true' then ' ok; ' else ' FALLO; ' end; end;

  -- C4 · cadena A→B→C: borrar B deja A cerrada el día antes de C y C sustituyendo a A; borrar C reabre A
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    v_a := public.condicion_comision_guarda(null, v_sin || jsonb_build_object('vigente_desde', v_hoy - 5), v_tr);
    v_b := public.condicion_comision_guarda(null, v_sin || jsonb_build_object('vigente_desde', v_hoy + 10), v_tr);
    v_c := public.condicion_comision_guarda(null, v_sin || jsonb_build_object('vigente_desde', v_hoy + 20), v_tr);
    select format('%s/%s', (select vigente_hasta = v_hoy + 9 from public.condiciones_comision where id = v_a)
                           and (select vigente_hasta = v_hoy + 19 and sustituye_a = v_a from public.condiciones_comision where id = v_b),
                           (select sustituye_a = v_b from public.condiciones_comision where id = v_c)) into v_t;
    perform public.condicion_comision_borra(v_b);
    set constraints all immediate;
    select v_t || '/' || ((select not activo and vigente_hasta = v_hoy + 19 from public.condiciones_comision where id = v_a)
                          and (select sustituye_a = v_a from public.condiciones_comision where id = v_c)) into v_t;
    perform public.condicion_comision_borra(v_c);
    set constraints all immediate;
    select v_t || '/' || (c.activo and c.vigente_hasta is null) into v_t from public.condiciones_comision c where c.id = v_a;
    raise exception '%', v_t;
  exception when others then r := r || 'C4 cadena A-B-C=' || sqlerrm || case when sqlerrm = 't/t/true/true' then ' ok; ' else ' FALLO; ' end; end;

  -- C5 · las cifras de una condición CERRADA no se editan (sintética cerrada a mano, y la estándar 2,5 % real)
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    v_a := public.condicion_comision_guarda(null, v_sin || jsonb_build_object('vigente_desde', v_hoy - 5), v_tr);
    perform public.condicion_comision_activa(v_a, false);
    v_t := '';
    begin perform public.condicion_comision_guarda(v_a, v_sin || jsonb_build_object('vigente_desde', v_hoy - 5, 'pct_comision', 4), v_tr);
          v_t := v_t || 'pasa/'; exception when others then v_t := v_t || 'no/'; end;
    begin perform public.condicion_comision_guarda(v_a, v_sin || jsonb_build_object('vigente_desde', v_hoy - 5),
                    '[{"disparador_tipo":"contrato_firmado","pct_tramo":50},{"disparador_tipo":"obra_firmada","pct_tramo":50}]');
          v_t := v_t || 'pasa/'; exception when others then v_t := v_t || 'no/'; end;
    select c.id into v_b from public.condiciones_comision c
     where c.equipo_id is null and c.proyecto_id is null and c.closer_email is null and c.vigente_hasta < v_hoy
     order by c.vigente_hasta desc limit 1;
    begin perform public.condicion_comision_guarda(v_b, jsonb_build_object('pct_comision', 7, 'base_calculo', 'precio_total',
                    'vigente_desde', (select vigente_desde from public.condiciones_comision where id = v_b)), null, 'prueba F6: no debe pasar');
          v_t := v_t || 'pasa'; exception when others then v_t := v_t || 'no'; end;
    raise exception '%', v_t;
  exception when others then r := r || 'C5 cifras de cerrada=' || sqlerrm || case when sqlerrm = 'no/no/no' then ' ok; ' else ' FALLO; ' end; end;

  -- C6 · nueva condición de admin con inicio pasado en un alcance REAL: exige confirmar el recuento exacto de
  --      ventas sin devengar que cambian de condición (sin él o distinto → rechazo con hint; igual → ok)
  begin
    select c.id, c.equipo_id, coalesce(public._condicion_ultima_venta_devengada(c.id) + 1, v_hoy - 365) d into v_ret
      from public.condiciones_comision c
     where c.nivel = 'manager' and c.equipo_id is not null and c.proyecto_id is null and c.activo and c.vigente_hasta is null
       and public._condicion_ventas_afectadas(c.equipo_id, null, 'manager', null,
             coalesce(public._condicion_ultima_venta_devengada(c.id) + 1, v_hoy - 365), v_hoy) > 0
       and coalesce(public._condicion_ultima_venta_devengada(c.id) + 1, v_hoy - 365) < v_hoy
     limit 1;
    if v_ret.id is null then raise exception 'sin alcance real con ventas sin devengar'; end if;
    v_esperado := public._condicion_ventas_afectadas(v_ret.equipo_id, null, 'manager', null, v_ret.d, v_hoy);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    v_sin := jsonb_build_object('equipo_id', v_ret.equipo_id, 'nivel', 'manager', 'pct_comision', 9, 'base_calculo', 'precio_total', 'vigente_desde', v_ret.d);
    v_t := '';
    begin perform public.condicion_comision_guarda(null, v_sin, v_tr); v_t := v_t || 'pasa/';
    exception when others then get stacked diagnostics v_h = pg_exception_hint; v_t := v_t || (v_h = 'lw-confirmar-ventas:' || v_esperado) || '/'; end;
    begin perform public.condicion_comision_guarda(null, v_sin || jsonb_build_object('confirmar_ventas', v_esperado + 1), v_tr); v_t := v_t || 'pasa/';
    exception when others then v_t := v_t || 'no/'; end;
    begin v_a := public.condicion_comision_guarda(null, v_sin || jsonb_build_object('confirmar_ventas', v_esperado), v_tr);
          v_t := v_t || (select sustituye_a = v_ret.id from public.condiciones_comision where id = v_a)
                     || ':' || (select vigente_hasta = v_ret.d - 1 from public.condiciones_comision where id = v_ret.id);
    exception when others then v_t := v_t || 'no:' || sqlerrm; end;
    raise exception '%', v_t;
  exception when others then r := r || 'C6 retroactiva con recuento=' || sqlerrm || case when sqlerrm = 'true/no/true:true' then ' ok; ' else ' FALLO; ' end; end;

  -- C7 · el SM cambia las cifras de una condición en vigor desde antes de hoy → 42501 «crea una condición nueva desde hoy»
  --      (sintética: la crea admin con inicio hace 5 días; el SM la reconoce como suya)
  begin
    v_sin := jsonb_build_object('equipo_id', v_eq, 'nivel', 'team_lead', 'closer_email', 'x@prueba.invalid', 'pct_comision', 2, 'base_calculo', 'precio_total');
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    v_a := public.condicion_comision_guarda(null, v_sin || jsonb_build_object('vigente_desde', v_hoy - 5), v_tr);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sm.user_id, 'email', v_sm.e, 'role', 'authenticated')::text, true);
    v_t := format('%s/', public._condicion_es_mia('team_lead', v_eq));
    begin perform public.condicion_comision_guarda(v_a, v_sin || jsonb_build_object('vigente_desde', v_hoy - 5, 'pct_comision', 3), v_tr);
          v_t := v_t || 'pasa';
    exception when others then
      v_t := v_t || case when sqlstate = '42501' and sqlerrm like '%crea una condición nueva desde hoy%' then 'no' else sqlstate || ':' || sqlerrm end;
    end;
    raise exception '%', v_t;
  exception when others then r := r || 'C7 SM cifras en vigor=' || sqlerrm || case when sqlerrm = 't/no' then ' ok; ' else ' FALLO; ' end; end;

  -- C8 · admin cambia el % de una condición REAL en vigor con ventas afectadas: sin confirmar → 22023 con el hint
  --      del recuento; con otro número → 22023; con el recuento → ok y el log guarda ventas_max. Control: re-guardar
  --      las MISMAS cifras y tramos (leídos de la tabla) no pide confirmación. Guardar una condición no dispara el motor.
  begin
    select c.* into v_ret from public.condiciones_comision c
     where c.vigente_desde < v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
       and not public._condicion_cerrada(c.id) and c.base_calculo <> 'importe_fijo' and c.pct_comision < 99
       and public._condicion_ventas_afectadas(c.equipo_id, c.proyecto_id, c.nivel, c.closer_email, c.vigente_desde, coalesce(c.vigente_hasta, v_hoy)) > 0
     order by (select count(*) from public.comisiones_devengadas d where d.condicion_id = c.id), c.vigente_desde
     limit 1;
    if v_ret.id is null then raise exception 'sin condición real en vigor con ventas afectadas'; end if;
    v_esperado := public._condicion_ventas_afectadas(v_ret.equipo_id, v_ret.proyecto_id, v_ret.nivel, v_ret.closer_email,
                    v_ret.vigente_desde, coalesce(v_ret.vigente_hasta, v_hoy));
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    v_sin := jsonb_build_object('closer_email', v_ret.closer_email, 'pct_comision', v_ret.pct_comision, 'base_calculo', v_ret.base_calculo,
                                'vigente_desde', v_ret.vigente_desde);
    select coalesce(jsonb_agg(jsonb_build_object('disparador_tipo', t.disparador_tipo, 'umbral', t.umbral, 'pct_tramo', t.pct_tramo) order by t.orden), '[]'::jsonb)
      into v_sin2 from public.condicion_tramos t where t.condicion_id = v_ret.id;
    v_t := '';
    begin perform public.condicion_comision_guarda(v_ret.id, v_sin, v_sin2, 'prueba F6: mismas cifras'); v_t := v_t || 'igual/';
    exception when others then v_t := v_t || 'igual-no:' || sqlerrm || '/'; end;
    v_sin := v_sin || jsonb_build_object('pct_comision', v_ret.pct_comision + 1);
    begin perform public.condicion_comision_guarda(v_ret.id, v_sin, v_sin2, 'prueba F6: no debe quedar'); v_t := v_t || 'pasa/';
    exception when others then get stacked diagnostics v_h = pg_exception_hint;
      v_t := v_t || (sqlstate = '22023' and v_h = 'lw-confirmar-ventas:' || v_esperado and sqlerrm like '%hasta a %') || '/'; end;
    begin perform public.condicion_comision_guarda(v_ret.id, v_sin || jsonb_build_object('confirmar_ventas', v_esperado + 1), v_sin2, 'prueba F6: no debe quedar');
          v_t := v_t || 'pasa/';
    exception when others then v_t := v_t || case when sqlstate = '22023' then 'no/' else sqlstate || '/' end; end;
    begin perform public.condicion_comision_guarda(v_ret.id, v_sin || jsonb_build_object('confirmar_ventas', v_esperado), v_sin2, 'prueba F6: no debe quedar');
          v_t := v_t || exists (select 1 from public.condiciones_comision_log l
                                 where l.condicion_id = v_ret.id and (l.despues ->> 'ventas_max')::int = v_esperado
                                   and (l.despues ->> 'pct_comision')::numeric = v_ret.pct_comision + 1);
    exception when others then v_t := v_t || 'no:' || sqlerrm; end;
    raise exception '%', v_t;
  exception when others then r := r || 'C8 admin cifras en vigor con recuento=' || sqlerrm || case when sqlerrm = 'igual/true/no/true' then ' ok; ' else ' FALLO; ' end; end;

  -- C9 · a quién se aplica (closer_email) es identidad: cambiarlo en una condición en vigor (SM y admin), cerrada o
  --      sustituta futura → 22023 «Para cambiar a quién se aplica…»; en una futura normal sin devengos → ok y cambia.
  --      Alcance sintético (team_lead de un equipo real), sin ventas.
  begin
    v_sin := jsonb_build_object('equipo_id', v_eq, 'nivel', 'team_lead', 'closer_email', 'x@prueba.invalid', 'pct_comision', 2, 'base_calculo', 'precio_total');
    v_t := '';
    -- en vigor desde hace 5 días: el SM la pasa a «todo el equipo», admin a otra persona
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    v_a := public.condicion_comision_guarda(null, v_sin || jsonb_build_object('vigente_desde', v_hoy - 5), v_tr);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sm.user_id, 'email', v_sm.e, 'role', 'authenticated')::text, true);
    begin perform public.condicion_comision_guarda(v_a, v_sin || jsonb_build_object('vigente_desde', v_hoy - 5, 'closer_email', null), v_tr);
          v_t := v_t || 'pasa/';
    exception when others then
      v_t := v_t || case when sqlstate = '22023' and sqlerrm = 'Para cambiar a quién se aplica, crea una condición nueva desde hoy' then 'no/' else sqlstate || ':' || sqlerrm || '/' end; end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    begin perform public.condicion_comision_guarda(v_a, v_sin || jsonb_build_object('vigente_desde', v_hoy - 5, 'closer_email', 'y@prueba.invalid'), v_tr);
          v_t := v_t || 'pasa/';
    exception when others then
      v_t := v_t || case when sqlstate = '22023' and sqlerrm = 'Para cambiar a quién se aplica, crea una condición nueva desde hoy' then 'no/' else sqlstate || ':' || sqlerrm || '/' end; end;
    -- cerrada (a mano, hoy) → rechazo
    perform public.condicion_comision_activa(v_a, false);
    begin perform public.condicion_comision_guarda(v_a, v_sin || jsonb_build_object('vigente_desde', v_hoy - 5, 'closer_email', null), v_tr);
          v_t := v_t || 'pasa/';
    exception when others then
      v_t := v_t || case when sqlstate = '22023' and sqlerrm = 'Para cambiar a quién se aplica, crea una condición nueva desde hoy' then 'no/' else sqlstate || ':' || sqlerrm || '/' end; end;
    -- sustituta futura: A en vigor (otra persona) y B desde dentro de 10 días que la sustituye → cambiar B, rechazo
    v_sin2 := v_sin || jsonb_build_object('closer_email', 'z@prueba.invalid');
    v_b := public.condicion_comision_guarda(null, v_sin2 || jsonb_build_object('vigente_desde', v_hoy - 5), v_tr);
    v_c := public.condicion_comision_guarda(null, v_sin2 || jsonb_build_object('vigente_desde', v_hoy + 10), v_tr);
    begin perform public.condicion_comision_guarda(v_c, v_sin2 || jsonb_build_object('vigente_desde', v_hoy + 10, 'closer_email', null), v_tr);
          v_t := v_t || 'pasa/';
    exception when others then
      v_t := v_t || case when sqlstate = '22023' and sqlerrm = 'Para cambiar a quién se aplica, crea una condición nueva desde hoy' then 'no/' else sqlstate || ':' || sqlerrm || '/' end; end;
    -- futura normal sin devengos ni sustitución → ok, y la persona cambia de verdad
    v_id := public.condicion_comision_guarda(null, v_sin || jsonb_build_object('closer_email', 'w@prueba.invalid', 'vigente_desde', v_hoy + 10), v_tr);
    begin perform public.condicion_comision_guarda(v_id, v_sin || jsonb_build_object('closer_email', 'v@prueba.invalid', 'vigente_desde', v_hoy + 10), v_tr);
          v_t := v_t || (select c.closer_email = 'v@prueba.invalid' and c.sustituye_a is null from public.condiciones_comision c where c.id = v_id);
    exception when others then v_t := v_t || 'no:' || sqlstate || ':' || sqlerrm; end;
    raise exception '%', v_t;
  exception when others then r := r || 'C9 a quien se aplica=' || sqlerrm || case when sqlerrm = 'no/no/no/no/true' then ' ok; ' else ' FALLO; ' end; end;

  -- dinero intacto: ninguna comisión ni solicitud nueva o cambiada al acabar (todo lo de arriba se deshizo)
  if (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(d)::text, '|' order by d.id), '')) from public.comisiones_devengadas d) <> v_dev0
     or (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(s)::text, '|' order by s.id), '')) from public.solicitudes_pago s) <> v_sp0 then
    r := r || 'DINERO cambió FALLO; ';
  else
    r := r || 'dinero intacto ok; ';
  end if;
  raise exception 'RES: %', r;
end $$;
