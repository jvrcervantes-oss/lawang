-- PRUEBA POR ROL — F4 «comisión oculta» (30-sep-2026): migraciones 20260930041708, 042130, 043522, 044643, 044759,
-- 050714 (recorte de comision_trazabilidad), 050821, 050946 y 052657 (bote no tocable por el closer; equipo borrado = oculta).
-- Se ejecuta ENTERA en una llamada con execute_sql (MCP) o psql como postgres. NO ESCRIBE NADA: cada caso va en un
-- sub-bloque que acaba en excepción (Postgres deshace lo que hizo, rol y claims incluidos) y el bloque entero termina en
-- `raise exception 'RES: …'`. Los booleanos salen como t/f (format) y los de jsonb como true/false. Cada caso debe decir «ok»; un «FALLO» es una cifra de comisión a la vista de quien no debe.
-- Perfiles: closer del equipo de Gus (interruptor encendido y apagado), SM Gus, agente SIN equipo (ismael: blueiestates ya
-- tiene equipo propio), admin (super_admin que no cobra de esa venta) y lw_lector (rol de lectura del estudio, sin sesión).
-- La base se busca, no se inventa: el closer es el beneficiario de una comisión de nivel closer del equipo; el SM, el
-- manager de ese equipo. Si falta alguno, la prueba lo dice en vez de dar un falso «ok».
do $$
declare
  r text := ''; v_t text; v_n int; v_j jsonb;
  v_eq uuid; v_dev_closer uuid; v_dev_sm uuid; v_dev_ag uuid; v_sp_bote uuid; v_dif uuid;
  v_closer record; v_sm record; v_ag record; v_adm record;
  v_total int := (select count(*) from public.comisiones_devengadas); v_mias int;
  v_s public.solicitudes_pago; v_vis boolean;
begin
  -- base
  select d.id, coalesce(k.equipo_id, c.equipo_id) into v_dev_closer, v_eq
    from public.comisiones_devengadas d
    left join public.condiciones_comision c on c.id = d.condicion_id
    left join public.contrato_closer k on k.contrato_id = d.contrato_raiz_id
   where d.nivel = 'closer' and coalesce(k.equipo_id, c.equipo_id) is not null
   order by d.created_at limit 1;
  if v_dev_closer is null then raise exception 'RES: sin comisión de nivel closer con equipo: la prueba no tiene base'; end if;
  select u.user_id, lower(u.email) e into v_closer from public.usuarios u
   where lower(u.email) = (select lower(beneficiario_email) from public.comisiones_devengadas where id = v_dev_closer);
  select count(*) into v_mias from public.comisiones_devengadas where lower(beneficiario_email) = v_closer.e;
  select u.user_id, lower(u.email) e into v_sm from public.usuarios u
   where lower(u.email) = (select lower(ev.manager_email) from public.equipos_venta ev where ev.id = v_eq);
  select d.id into v_dev_sm from public.comisiones_devengadas d
   where lower(d.beneficiario_email) = v_sm.e and d.nivel = 'manager' and d.solicitud_id is not null order by d.created_at limit 1;
  select u.user_id, lower(u.email) e into v_ag from public.usuarios u
   where lower(u.email) = 'ismaelsumbahills@gmail.com' and u.activo
     and not exists (select 1 from public.equipo_miembros em where lower(em.closer_email) = lower(u.email))
     and not exists (select 1 from public.equipos_venta ev where lower(ev.manager_email) = lower(u.email));
  select d.id into v_dev_ag from public.comisiones_devengadas d where lower(d.beneficiario_email) = v_ag.e order by d.created_at limit 1;
  select u.user_id, lower(u.email) e into v_adm from public.usuarios u
   where u.rol = 'super_admin' and u.activo
     and lower(u.email) not in (select lower(beneficiario_email) from public.comisiones_devengadas)
   order by u.email limit 1;
  if v_closer.user_id is null or v_sm.user_id is null or v_dev_sm is null or v_ag.user_id is null or v_dev_ag is null or v_adm.user_id is null then
    raise exception 'RES: falta un perfil (closer %, SM %, bote %, agente sin equipo %, su comisión %, admin %)',
      v_closer.user_id is not null, v_sm.user_id is not null, v_dev_sm is not null, v_ag.user_id is not null, v_dev_ag is not null, v_adm.user_id is not null;
  end if;

  -- 1 · closer, interruptor ENCENDIDO: ve solo lo suyo; trazabilidad RECORTADA (sin contratos, parcelas, correos ni precios del origen)
  begin
    update public.equipos_venta set closers_ven_comision = true where id = v_eq;
    insert into public.comisiones_diferencias (devengo_id, importe, importe_vigente, importe_nuevo, base_antes, base_despues, motivo, estado, origen, provocado_por, resuelto_por)
    values (v_dev_closer, 10, 100, 110, 1000, 1100, 'prueba F4', 'pendiente',
            jsonb_build_object('numero', 'CCPRUEBA', 'en', now(), 'quien', 'editor@prueba.invalid',
                               'precio_total', jsonb_build_object('antes', 1000, 'despues', 1100),
                               'firmado', jsonb_build_object('antes', true, 'despues', true)),
            'editor@prueba.invalid', 'admin@prueba.invalid')
    returning id into v_dif;
    insert into public.comisiones_ajustes_log (tabla, fila_id, accion, actor_email, importe_antes, importe_despues, motivo)
    values ('comisiones_diferencias', v_dif, 'diferencia', 'editor@prueba.invalid', 100, 110, 'prueba F4');
    perform set_config('request.jwt.claims', json_build_object('sub', v_closer.user_id, 'email', v_closer.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_j := public.comision_trazabilidad(v_dev_closer);
    select format('%s/%s/%s/%s/%s/%s/%s/%s/%s',
      (select count(*) from public.comisiones_devengadas where lower(beneficiario_email) <> v_closer.e) = 0,
      (select count(*) from public.comisiones_devengadas) = v_mias,
      exists (select 1 from public.mi_condicion_comision() m where not m.oculta),
      v_j->>'completa', v_j->'operacion' = '[]'::jsonb and v_j->'parcelas' = '[]'::jsonb,
      (select bool_and(((x->'origen') - 'en' - 'cambio') = '{}'::jsonb and x->'origen'->'cambio' = '["precio_total"]'::jsonb
                       and x->>'provocado_por' is null and x->>'resuelto_por' is null) from jsonb_array_elements(v_j->'diferencias') x),
      (select bool_and(h->>'quien' is null) from jsonb_array_elements(v_j->'historial') h),
      jsonb_array_length(v_j->'diferencias') = 1,
      position('prueba.invalid' in v_j::text) = 0) into v_t;
    raise exception '%', v_t;
  exception when others then r := r || '1 closer encendido=' || sqlerrm || case when sqlerrm = 't/t/t/false/t/t/t/t/t' then ' ok; ' else ' FALLO; ' end; end;

  -- 2 · closer, interruptor APAGADO: ninguna comisión de equipo, «oculta», trazabilidad cerrada
  begin
    update public.equipos_venta set closers_ven_comision = false where id = v_eq;
    perform set_config('request.jwt.claims', json_build_object('sub', v_closer.user_id, 'email', v_closer.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select format('%s/%s', (select count(*) from public.comisiones_devengadas where nivel in ('closer', 'setter', 'team_lead')),
                  exists (select 1 from public.mi_condicion_comision() m where m.oculta and m.pct_comision is null)) into v_t;
    begin
      perform public.comision_trazabilidad(v_dev_closer);
      v_t := v_t || '/abierta';
    exception when insufficient_privilege then v_t := v_t || '/cerrada'; end;
    raise exception '%', v_t;
  exception when others then r := r || '2 closer apagado=' || sqlerrm || case when sqlerrm = '0/t/cerrada' then ' ok; ' else ' FALLO; ' end; end;

  -- 3 · bote: solicitud AUTOMÁTICA del SM con creado_por = el closer (así la deja el disparador en su sesión) → el closer ve 0
  begin
    insert into public.solicitudes_pago (concepto, importe, moneda, estado, creado_por, beneficiario_email, origen)
    values ('prueba F4 bote', 123, 'EUR', 'pendiente', v_closer.user_id, v_sm.e, 'comision_automatica')
    returning id into v_sp_bote;
    perform set_config('request.jwt.claims', json_build_object('sub', v_closer.user_id, 'email', v_closer.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select format('%s/%s', (select count(*) from public.solicitudes_pago where id = v_sp_bote),
                  (select count(*) from public.solicitudes_pago where origen = 'comision_automatica' and lower(beneficiario_email) <> v_closer.e)) into v_t;
    raise exception '%', v_t;
  exception when others then r := r || '3 bote creado por el closer=' || sqlerrm || case when sqlerrm = '0/0' then ' ok; ' else ' FALLO; ' end; end;

  -- 4 · SM Gus: ve las comisiones de closer de su equipo y la trazabilidad COMPLETA
  begin
    update public.equipos_venta set closers_ven_comision = false where id = v_eq;   -- apagar no le quita nada al SM
    perform set_config('request.jwt.claims', json_build_object('sub', v_sm.user_id, 'email', v_sm.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_j := public.comision_trazabilidad(v_dev_closer);
    select format('%s/%s/%s', exists (select 1 from public.comisiones_devengadas where id = v_dev_closer),
                  v_j->>'completa', jsonb_array_length(v_j->'operacion') > 0) into v_t;
    raise exception '%', v_t;
  exception when others then r := r || '4 SM=' || sqlerrm || case when sqlerrm = 't/true/t' then ' ok; ' else ' FALLO; ' end; end;

  -- 5 · agente sin equipo: solo lo suyo, condición estándar, trazabilidad recortada; la del closer, cerrada
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_ag.user_id, 'email', v_ag.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_j := public.comision_trazabilidad(v_dev_ag);
    select format('%s/%s/%s', (select count(*) from public.comisiones_devengadas where lower(beneficiario_email) <> v_ag.e),
                  coalesce((select bool_and(m.ambito = 'estandar') from public.mi_condicion_comision() m), true),
                  v_j->>'completa') into v_t;
    begin
      perform public.comision_trazabilidad(v_dev_closer);
      v_t := v_t || '/abierta';
    exception when insufficient_privilege then v_t := v_t || '/cerrada'; end;
    raise exception '%', v_t;
  exception when others then r := r || '5 agente sin equipo=' || sqlerrm || case when sqlerrm = '0/t/false/cerrada' then ' ok; ' else ' FALLO; ' end; end;

  -- 6 · admin: todo, trazabilidad completa
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_j := public.comision_trazabilidad(v_dev_closer);
    select format('%s/%s', (select count(*) from public.comisiones_devengadas) = v_total, v_j->>'completa') into v_t;
    raise exception '%', v_t;
  exception when others then r := r || '6 admin=' || sqlerrm || case when sqlerrm = 't/true' then ' ok; ' else ' FALLO; ' end; end;

  -- 7 · lw_lector (sin sesión de usuario): ni comisiones ni solicitudes
  begin
    perform set_config('request.jwt.claims', '{}', true);
    set local role lw_lector;
    select format('%s/%s', (select count(*) from public.comisiones_devengadas), (select count(*) from public.solicitudes_pago)) into v_t;
    raise exception '%', v_t;
  exception when others then r := r || '7 lw_lector=' || sqlerrm || case when sqlerrm = '0/0' then ' ok; ' else ' FALLO; ' end; end;

  -- 8 · las 3 columnas denegadas de comisiones_diferencias (authenticated y lw_lector): origen, provocado_por, resuelto_por
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_closer.user_id, 'email', v_closer.e, 'role', 'authenticated')::text, true);
    v_t := '';
    for v_n in 1..6 loop
      begin
        execute format('set local role %s', case when v_n <= 3 then 'authenticated' else 'lw_lector' end);
        execute format('select count(%I) from public.comisiones_diferencias', (array['origen', 'provocado_por', 'resuelto_por'])[1 + (v_n - 1) % 3]);
        v_t := v_t || 'x';
      exception when insufficient_privilege then v_t := v_t || 'n'; end;
    end loop;
    execute 'set local role authenticated';
    perform count(id) from public.comisiones_diferencias;   -- la lista del navegador sigue leyendo
    raise exception '%', v_t;
  exception when others then r := r || '8 columnas denegadas=' || sqlerrm || case when sqlerrm = 'nnnnnn' then ' ok; ' else ' FALLO; ' end; end;

  -- 9 · bote: _solicitud_puede_tocar de una AUTOMÁTICA con creado_por = el closer → false; una manual suya pendiente → true
  begin
    insert into public.solicitudes_pago (concepto, importe, moneda, estado, creado_por, beneficiario_email, origen)
    values ('prueba F4 bote tocar', 123, 'EUR', 'pendiente', v_closer.user_id, v_sm.e, 'comision_automatica')
    returning id into v_sp_bote;
    perform set_config('request.jwt.claims', json_build_object('sub', v_closer.user_id, 'email', v_closer.e, 'role', 'authenticated')::text, true);
    select * into v_s from public.solicitudes_pago where id = v_sp_bote;
    v_t := format('%s', public._solicitud_puede_tocar(v_s));
    v_s.origen := null;   -- la misma fila como manual: el creador sí la toca (no se ha cerrado de más)
    v_t := v_t || format('/%s', public._solicitud_puede_tocar(v_s));
    raise exception '%', v_t;
  exception when others then r := r || '9 bote no tocable=' || sqlerrm || case when sqlerrm = 'f/t' then ' ok; ' else ' FALLO; ' end; end;

  -- 10 · equipo_id congelado que ya no existe (contrato_closer.equipo_id no tiene FK) → la comisión del closer NO se ve
  begin
    update public.equipos_venta set closers_ven_comision = true where id = v_eq;   -- encendido: solo el equipo borrado la oculta
    update public.contrato_closer set equipo_id = gen_random_uuid()
     where contrato_id = (select contrato_raiz_id from public.comisiones_devengadas where id = v_dev_closer);
    if not found then raise exception 'sin contrato_closer para la base'; end if;
    perform set_config('request.jwt.claims', json_build_object('sub', v_closer.user_id, 'email', v_closer.e, 'role', 'authenticated')::text, true);
    -- la función se evalúa con la fila leída como postgres (si no, la RLS la escondería y el «no visible» sería gratis)
    select public.comision_visible(d.nivel, d.beneficiario_email, d.condicion_id, d.contrato_raiz_id) into v_vis
      from public.comisiones_devengadas d where d.id = v_dev_closer;
    set local role authenticated;
    select format('%s/%s', v_vis, (select count(*) from public.comisiones_devengadas where id = v_dev_closer)) into v_t;
    raise exception '%', v_t;
  exception when others then r := r || '10 equipo inexistente=' || sqlerrm || case when sqlerrm = 'f/0' then ' ok; ' else ' FALLO; ' end; end;

  raise exception 'RES: %', r;
end $$;
