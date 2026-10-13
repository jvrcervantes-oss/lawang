-- Prueba de LAW-553 (13-oct-2026): la moneda de un documento la decide su contrato, el tope de una venta se mide por
-- cadena Y moneda, y la moneda de un contrato con documentos no cambia por debajo. Migración:
-- supabase/migrations/20261013074408_factura_moneda_del_contrato.sql.
--
-- Se ejecuta por execute_sql DESPUÉS de aplicar (o pegada detrás de la migración, antes de aplicarla): todo va en un
-- único bloque que termina con un raise a propósito, así que no deja rastro (contratos ZZ-L553-*, proyecto, facturas,
-- eventos y el trigger auxiliar de numeración se deshacen; la cola de pg_net también).
-- NO gasta números de la serie fiscal: los documentos de prueba llevan número explícito, y los que da de alta una RPC
-- (factura_guarda, guardar_recibi) lo reciben del trigger auxiliar trg_00a_zz_l553_num, que corre antes de
-- trg_set_factura_numero (mismo truco que tools/flujos_lawang.py).
-- Perfiles con el ROL REAL (`set local role authenticated` + claims JWT, como tools/flujos_lawang.py): el MCP corre
-- como postgres con bypassrls y sin cambiar de rol ninguna policy se evalúa. Identidades resueltas desde la base:
-- un agente con la herramienta Facturas y empresa, un admin y un super_admin; ningún uid ni email en el fichero.
-- Cada línea dice OK, MAL o PENDIENTE (solo g3-g5, ver allí); ninguna debe decir MAL. El canario C0 tiene que salir OK o lo demás no vale.
do $t$
declare
  out text := ''; v_p uuid; v_e uuid; v_i uuid; v_i2 uuid; v_n uuid; v_hs uuid; v_e2 uuid; v_f uuid; v_pro uuid;
  v_rec uuid; v_venc uuid; v_soc text; v_ag_sub text; v_ag_mail text; v_ag_emp text; v_ad_sub text; v_ad_mail text;
  v_sa_sub text; v_sa_mail text; v_ev int; acl_ok boolean;
begin
  -- ── identidades ────────────────────────────────────────────────────────────────────────────────────────────────
  select u.user_id::text, u.email, coalesce(u.empresas[1], '') into v_ag_sub, v_ag_mail, v_ag_emp
    from public.usuarios u where u.activo and u.rol = 'agente' and 'facturas' = any(u.herramientas)
     and coalesce(array_length(u.empresas, 1), 0) > 0 and coalesce(array_length(u.proyectos_supervisados, 1), 0) = 0
   order by u.creado_en limit 1;
  select u.user_id::text, u.email into v_ad_sub, v_ad_mail
    from public.usuarios u where u.activo and u.rol = 'admin' order by u.creado_en limit 1;
  select u.user_id::text, u.email into v_sa_sub, v_sa_mail
    from public.usuarios u where u.activo and u.rol = 'super_admin' order by u.creado_en limit 1;
  select coalesce((select e.sociedad_clave from public.empresas e where e.clave = v_ag_emp),
                  (select clave from public.sociedades order by clave limit 1)) into v_soc;
  out := out || 'identidades: agente=' || (v_ag_sub is not null) || ' admin=' || (v_ad_sub is not null)
             || ' super_admin=' || (v_sa_sub is not null) || E'\n';

  -- ── datos (como postgres, con las claims del super_admin: hay triggers que miran auth.uid()) ───────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', v_sa_sub, 'email', v_sa_mail, 'role', 'authenticated')::text, true);
  create function public.zz_l553_num() returns trigger language plpgsql as $f$ begin
    if new.numero is null then new.numero := 'ZZ-L553-N' || left(gen_random_uuid()::text, 8); end if; return new; end $f$;
  create trigger trg_00a_zz_l553_num before insert on public.facturas for each row execute function public.zz_l553_num();
  insert into storage.objects (bucket_id, name) values ('justificantes', 'zz-l553/justificante.pdf');

  insert into public.proyectos (nombre, slug, empresa) values ('ZZ L553 PROYECTO', 'zz-l553-proyecto', nullif(v_ag_emp, '')) returning id into v_p;
  -- E: venta en EUR con precio 1.000, del agente
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por)
    values ('ZZ-L553-E', 'contrato_general', v_p, 'EUR', 1000, '{"hitos":[]}', v_ag_mail) returning id into v_e;
  -- E2: otra venta en EUR. I: hija de E en IDR con precio 5.000.000; I2: hija de E2 en IDR sin precio. Van en ventas
  -- distintas a propósito: un miembro en IDR sin precio deja «sin precio» TODA la parte en IDR de su venta, y entonces
  -- la factura en IDR se rechaza (es la regla: en otra moneda, sin precio no hay tope y se para).
  -- contrato_general y no construccion: una Construcción exige tipología y techo. Alta firmada y luego la moneda: el
  -- trigger de moneda no toca un contrato firmado y, sin documentos, el guarda nuevo deja cambiarla.
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por)
    values ('ZZ-L553-E2', 'contrato_general', v_p, 'EUR', 1000, '{"hitos":[]}', v_ag_mail) returning id into v_e2;
  insert into public.contratos (numero, tipo, proyecto_id, precio_total, contrato_padre_id, datos, creado_por, bloqueado)
    values ('ZZ-L553-I', 'contrato_general', v_p, 5000000, v_e, '{"hitos":[]}', v_ag_mail, true) returning id into v_i;
  insert into public.contratos (numero, tipo, proyecto_id, precio_total, contrato_padre_id, datos, creado_por, bloqueado)
    values ('ZZ-L553-I2', 'contrato_general', v_p, null, v_e2, '{"hitos":[]}', v_ag_mail, true) returning id into v_i2;
  update public.contratos set moneda = 'IDR' where id in (v_i, v_i2);
  -- N: contrato sin moneda (ni unidad ni padre); HS: Hak Sewa hijo de E (hereda EUR)
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por)
    values ('ZZ-L553-N', 'contrato_general', v_p, null, 1000, '{"hitos":[]}', v_ag_mail) returning id into v_n;
  insert into public.contratos (numero, tipo, proyecto_id, precio_total, contrato_padre_id, datos, creado_por)
    values ('ZZ-L553-HS', 'hak_sewa_notario', v_p, null, v_e, '{"hitos":[]}', v_ag_mail) returning id into v_hs;
  insert into public.contrato_vencimientos (contrato_id, orden, descripcion, monto, fecha)
    values (v_e, 1, 'ZZ L553', 100, current_date + 1) returning id into v_venc;
  out := out || 'datos: E=' || (select moneda from public.contratos where id = v_e) || ' I=' || (select moneda from public.contratos where id = v_i)
             || ' N=' || coalesce((select moneda from public.contratos where id = v_n), 'null')
             || ' HS=' || coalesce((select moneda from public.contratos where id = v_hs), 'null') || E'\n';

  -- ── como AGENTE ─────────────────────────────────────────────────────────────────────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', v_ag_sub, 'email', v_ag_mail, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  out := out || case when current_user = 'authenticated' and auth.uid()::text = v_ag_sub and not public.es_super_admin()
                     then 'OK ' else 'MAL ' end || E'C0 canario agente: rol y claims\n';

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'IDR', 'total', '500',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '500')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a1 factura IDR sobre venta EUR: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en EUR%' then 'OK ' else 'MAL ' end
                                       || 'a1 factura IDR sobre venta EUR: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_e, 'total', '500',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '500')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a2 factura sin moneda: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' then 'OK ' else 'MAL ' end
                                       || 'a2 factura sin moneda: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  begin
    select id into v_f from public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'EUR', 'total', '500',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '500')), 'fields', '{}'::jsonb)));
    out := out || E'OK a3 factura EUR 500 sobre venta EUR 1.000: pasa\n';
  exception when others then out := out || 'MAL a3 factura EUR 500: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'EUR', 'total', '600',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '600')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a4 tope EUR 500+600 sobre 1.000: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%precio acordado%' then 'OK ' else 'MAL ' end
                                       || 'a4 tope EUR 500+600 sobre 1.000: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_i, 'moneda', 'IDR', 'total', '4000000',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '4000000')), 'fields', '{}'::jsonb)));
    out := out || E'OK a5 hija IDR 4.000.000 sobre su precio 5.000.000: pasa\n';
  exception when others then out := out || 'MAL a5 hija IDR 4.000.000: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_i, 'moneda', 'IDR', 'total', '2000000',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '2000000')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a6 tope IDR 4M+2M sobre 5M: PASA (antes de LAW-553 pasaba sin tope)\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%precio acordado%IDR%' then 'OK ' else 'MAL ' end
                                       || 'a6 tope IDR 4M+2M sobre 5M: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_i2, 'moneda', 'IDR', 'total', '100',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '100')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a7 hija IDR sin precio: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%con precio en IDR%' then 'OK ' else 'MAL ' end
                                       || 'a7 hija IDR sin precio: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_n, 'moneda', 'EUR', 'total', '10',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '10')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a8 contrato sin moneda: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%no tiene moneda%' then 'OK ' else 'MAL ' end
                                       || 'a8 contrato sin moneda: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_hs, 'moneda', 'EUR', 'total', '10',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '10')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a9 Hak Sewa (agente): PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%Hak Sewa%' then 'OK ' else 'MAL ' end
                                       || 'a9 Hak Sewa (agente): ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'proforma', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'IDR', 'total', '10',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '10')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a10 proforma IDR sobre venta EUR: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en EUR%' then 'OK ' else 'MAL ' end
                                       || 'a10 proforma IDR sobre venta EUR: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  -- a11: editar la factura de a3 llevándola a la hija en IDR sin cambiar la moneda → para por moneda
  begin perform public.factura_guarda(v_f, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_i, 'moneda', 'EUR', 'total', '500',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '500')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a11 edición a contrato en otra moneda: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en IDR%' then 'OK ' else 'MAL ' end
                                       || 'a11 edición a contrato en otra moneda: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  -- b1: recibí del agente sobre su venta EUR mandando IDR → para (trigger, camino de guardar_recibi; la RPC exige al
  -- menos una factura que saldar, así que se aplica a la de a3)
  begin perform public.guardar_recibi(null, jsonb_build_object('contrato_id', v_e, 'sociedad', v_soc, 'total', '1', 'moneda', 'IDR',
                 'justificantes', jsonb_build_array(jsonb_build_object('path', 'zz-l553/justificante.pdf')), 'datos', '{}'::jsonb),
                 jsonb_build_array(jsonb_build_object('factura_id', v_f, 'importe', '1')));
    out := out || E'MAL b1 recibí IDR sobre venta EUR: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en EUR%' then 'OK ' else 'MAL ' end
                                       || 'b1 recibí IDR sobre venta EUR: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  execute 'reset role';

  -- ── como ADMIN (no super): el Hak Sewa sigue parado ─────────────────────────────────────────────────────────────
  if v_ad_sub is not null then
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad_sub, 'email', v_ad_mail, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_hs, 'moneda', 'EUR', 'total', '10',
                   'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '10')), 'fields', '{}'::jsonb)));
      out := out || E'MAL g1 Hak Sewa (admin): PASA\n';
    exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%Hak Sewa%' then 'OK ' else 'MAL ' end
                                         || 'g1 Hak Sewa (admin): ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
    execute 'reset role';
  else
    out := out || E'MAL g1 sin admin activo para probar\n';
  end if;

  -- ── como SUPER_ADMIN: la moneda no tiene salida; Hak Sewa y tope sin precio pasan CON rastro ───────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', v_sa_sub, 'email', v_sa_mail, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  out := out || case when current_user = 'authenticated' and public.es_super_admin() then 'OK ' else 'MAL ' end || E'C0 canario super_admin\n';
  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'IDR', 'total', '500',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '500')), 'fields', '{}'::jsonb)));
    out := out || E'MAL g2 super_admin factura IDR sobre venta EUR: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en EUR%' then 'OK ' else 'MAL ' end
                                       || 'g2 super_admin moneda ajena: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_hs, 'moneda', 'EUR', 'total', '10',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '10')), 'fields', '{}'::jsonb)));
    out := out || E'OK g3 super_admin Hak Sewa: pasa\n';
  -- PENDIENTE (no MAL) mientras contrato_eventos_evento_check no admita el evento del rastro: la salida falla cerrada
  -- (contracts/sql/contrato_eventos_privilegios.sql, la aplica el owner). Cualquier otro error sí es MAL.
  exception when others then out := out || case when sqlerrm like '%contrato_eventos_evento_check%' then 'PENDIENTE ' else 'MAL ' end
                                       || 'g3 super_admin Hak Sewa: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;
  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_i2, 'moneda', 'IDR', 'total', '100',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '100')), 'fields', '{}'::jsonb)));
    out := out || E'OK g4 super_admin hija IDR sin precio: pasa\n';
  exception when others then out := out || case when sqlerrm like '%contrato_eventos_evento_check%' then 'PENDIENTE ' else 'MAL ' end
                                       || 'g4 super_admin hija IDR sin precio: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;
  execute 'reset role';
  select count(*) into v_ev from public.contrato_eventos
   where (contrato_id = v_hs and evento = 'documento_sobre_hak_sewa') or (contrato_id = v_i2 and evento = 'factura_sobre_tope');
  out := out || case when v_ev = 2 then 'OK '
                     when v_ev = 0 and not exists (select 1 from pg_constraint where conname = 'contrato_eventos_evento_check'
                                                     and pg_get_constraintdef(oid) like '%factura_sobre_tope%') then 'PENDIENTE '
                     else 'MAL ' end || 'g5 rastro de los dos pases del super_admin: ' || v_ev || E' (deben ser 2)\n';

  -- ── robot (service_role): factura_vencimiento_emite con moneda ajena ───────────────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  execute 'set local role service_role';
  begin perform public.factura_vencimiento_emite(v_venc, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_numero', 'ZZ-L553-E',
                 'total', 100, 'moneda', 'IDR', 'fecha_emision', current_date, 'datos', '{}'::jsonb));
    out := out || E'MAL c1 robot con moneda ajena: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en EUR%' then 'OK ' else 'MAL ' end
                                       || 'c1 robot con moneda ajena: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  begin perform public.factura_vencimiento_emite(v_venc, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_numero', 'ZZ-L553-E',
                 'total', 900, 'moneda', 'EUR', 'fecha_emision', current_date, 'datos', jsonb_build_object('totales', jsonb_build_object('subtotal', 900))));
    out := out || E'MAL c2 robot sobre el tope (500+900 sobre 1.000): PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%precio acordado%' then 'OK ' else 'MAL ' end
                                       || 'c2 robot sobre el tope: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  execute 'reset role';

  -- ── contrato con documentos (como postgres —los cambios de contrato van por RPCs DEFINER—, con las claims del
  --    agente: no es super_admin, así que no hay salida con rastro) ──────────────────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', v_ag_sub, 'email', v_ag_mail, 'role', 'authenticated')::text, true);
  begin update public.contratos set moneda = 'IDR' where id = v_e;
    out := out || E'MAL d1 cambiar la moneda de una venta con documentos: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%moneda de un contrato con documentos%' then 'OK ' else 'MAL ' end
                                       || 'd1 cambiar la moneda de una venta con documentos: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  begin update public.contratos set datos = datos where id = v_e;
    out := out || E'OK d2 volver a guardar la venta sin cambiar moneda: pasa\n';
  exception when others then out := out || 'MAL d2 volver a guardar la venta: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;
  begin update public.contratos set contrato_padre_id = v_e2 where id = v_i;
    out := out || E'MAL e1 colgar de otra venta un contrato con facturas: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%otra venta%' then 'OK ' else 'MAL ' end
                                       || 'e1 colgar de otra venta un contrato con facturas: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  -- f1: un recibí aplicado a la factura de a3 no cambia de moneda, ni siquiera pasándolo a la vez a un contrato de la
  -- otra moneda (el único cambio que la regla de contrato dejaría pasar; facturas_contrato_obligatorio impide el
  -- documento sin contrato)
  begin
    insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por, justificante_path, justificantes)
      values ('ZZ-L553-REC', v_soc, 'recibi', v_e, '{}'::jsonb, 100, 'EUR', v_ag_mail, 'zz-l553/justificante.pdf',
              jsonb_build_array(jsonb_build_object('path', 'zz-l553/justificante.pdf'))) returning id into v_rec;
    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado) values (v_rec, v_f, 100);
    begin update public.facturas set contrato_id = v_i, moneda = 'IDR' where id = v_rec;
      out := out || E'MAL f1 cambiar la moneda de un recibí aplicado: PASA\n';
    exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%cobros aplicados%' then 'OK ' else 'MAL ' end
                                         || 'f1 cambiar la moneda de un recibí aplicado: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  exception when others then out := out || 'MAL f1 montaje (aplicación): ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;

  -- b2: moneda fuera de la lista cerrada. El contrato N (sin documentos) se pone en «XXX» para que la regla del
  -- contrato deje pasar y sea la constraint la que pare.
  update public.contratos set moneda = 'XXX' where id = v_n;
  begin insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por)
          values ('ZZ-L553-X', v_soc, 'proforma', v_n, '{}'::jsonb, 1, 'XXX', v_ag_mail);
    out := out || E'MAL b2 moneda XXX: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%facturas_moneda_admitida%' then 'OK ' else 'MAL ' end
                                       || 'b2 moneda XXX: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  -- ── privilegios: las piezas nuevas no son de nadie de fuera ────────────────────────────────────────────────────
  select bool_and(not has_function_privilege(r, f, 'execute')) into acl_ok
    from unnest(array['anon', 'authenticated', 'service_role']) r,
         unnest(array['public._factura_moneda_valida(uuid,text,boolean)', 'public.trg_factura_moneda_del_contrato()',
                      'public.trg_contrato_moneda_con_documentos()', 'public._cadena_saldo_en(uuid,text,uuid)',
                      'public._cadena_saldo(uuid,uuid)', 'public._factura_tope_cadena(uuid,uuid,text,numeric,text)']) f;
  out := out || case when acl_ok then 'OK ' else 'MAL ' end || E'privilegios: sin execute para anon/authenticated/service_role\n';
  out := out || case when has_function_privilege('service_role', 'public.factura_vencimiento_emite(uuid,jsonb)', 'execute')
                      and not has_function_privilege('authenticated', 'public.factura_vencimiento_emite(uuid,jsonb)', 'execute')
                      and not has_function_privilege('anon', 'public.factura_vencimiento_emite(uuid,jsonb)', 'execute')
                     then 'OK ' else 'MAL ' end || E'privilegios: factura_vencimiento_emite solo service_role\n';

  raise exception E'RESULTADOS\n%', out;
end $t$;
