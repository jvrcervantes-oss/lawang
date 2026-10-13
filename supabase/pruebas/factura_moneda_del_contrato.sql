-- Prueba de LAW-553 (13-oct-2026): la moneda de un documento la decide su contrato, el tope de una venta se mide por
-- cadena Y moneda, y la moneda de un contrato con documentos no cambia por debajo. Migración:
-- supabase/migrations/20261013074408_factura_moneda_del_contrato.sql, con 20261013081849_factura_tope_proforma_y_reactiva
-- (a12, a13, h1, h2, c3) y 20261013105140_factura_reactiva_moneda (h3, h4: reactivar vuelve a comprobar la moneda).
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
-- Cada línea dice OK, MAL o PENDIENTE (solo g3-g5 y h1, ver allí); ninguna debe decir MAL. El canario C0 tiene que salir OK o lo demás no vale.
do $t$
declare
  out text := ''; v_p uuid; v_e uuid; v_i uuid; v_i2 uuid; v_n uuid; v_hs uuid; v_e2 uuid; v_f uuid; v_pro uuid;
  v_rec uuid; v_venc uuid; v_soc text; v_ag_sub text; v_ag_mail text; v_ag_emp text; v_ad_sub text; v_ad_mail text;
  v_sa_sub text; v_sa_mail text; v_ev int; acl_ok boolean;
  v_venc2 uuid; v_c3 uuid; v_c3i uuid; v_h1 uuid; v_h2 uuid; v_n0 int; v_n1 int; v_n2 int; v_e0 int; v_e1 int;
  v_ok boolean; v_m uuid; v_h3 uuid; v_h4 uuid;
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
  insert into public.contrato_vencimientos (contrato_id, orden, descripcion, monto, fecha)
    values (v_e, 2, 'ZZ L553 b', 100, current_date + 2) returning id into v_venc2;
  -- h1/h2 (reactivar): en E2 (precio 1.000) una factura viva de 500 y dos anuladas sin enviar, de 600 y de 400.
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por)
    values ('ZZ-L553-H0', v_soc, 'factura', v_e2, '{}'::jsonb, 500, 'EUR', v_ag_mail);
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por, anulada)
    values ('ZZ-L553-H1', v_soc, 'factura', v_e2, '{}'::jsonb, 600, 'EUR', v_ag_mail, true) returning id into v_h1;
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por, anulada)
    values ('ZZ-L553-H2', v_soc, 'factura', v_e2, '{}'::jsonb, 400, 'EUR', v_ag_mail, true) returning id into v_h2;
  -- h3/h4 (revisión de código sobre b40a8a2f8, 13-oct; migración 20261013105140_factura_reactiva_moneda): M, venta EUR con una factura y una
  -- proforma en EUR. Se anulan, M pasa a IDR (con todo anulado, trg_zz_00 lo deja) y se intenta reactivarlas.
  -- Alta firmada (bloqueado) para que trg_contrato_moneda_desde_unidad no recalcule la moneda.
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por, bloqueado)
    values ('ZZ-L553-M', 'contrato_general', v_p, 'EUR', 1000, '{"hitos":[]}', v_ag_mail, true) returning id into v_m;
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por)
    values ('ZZ-L553-H3', v_soc, 'factura', v_m, '{}'::jsonb, 100, 'EUR', v_ag_mail) returning id into v_h3;
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por)
    values ('ZZ-L553-H4', v_soc, 'proforma', v_m, '{}'::jsonb, 10, 'EUR', v_ag_mail) returning id into v_h4;
  update public.facturas set anulada = true where id in (v_h3, v_h4);
  begin update public.contratos set moneda = 'IDR' where id = v_m;
    out := out || case when (select moneda from public.contratos where id = v_m) = 'IDR' then 'OK ' else 'MAL ' end
               || E'h0 montaje: con sus documentos anulados, M pasa de EUR a IDR\n';
  exception when others then out := out || 'MAL h0 montaje (M a IDR): ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;
  -- c3: copia INVOKER, sin tope, de factura_vencimiento_emite tal como la dejó 20260926160000 (la de antes de LAW-553),
  -- para comparar lo que deja el robot en su versión DEFINER con lo que dejaba antes.
  create function public.zz_l553_venc_invoker(p_venc_id uuid, p_fila jsonb)
    returns table (id uuid, numero text, datos jsonb) language plpgsql security invoker set search_path to '' as $f$
  declare v_contrato uuid; v_factura uuid; f public.facturas; n int;
  begin
    select cv.contrato_id, cv.factura_id into v_contrato, v_factura
      from public.contrato_vencimientos cv where cv.id = p_venc_id for update;
    if not found then raise exception 'vencimiento % no existe', p_venc_id using hint = 'sin_fila'; end if;
    if v_factura is not null then raise exception 'vencimiento % ya tiene factura', p_venc_id using hint = 'ya_facturado'; end if;
    insert into public.facturas (tipo, sociedad, cliente_nombre, proyecto_nombre, contrato_numero, contrato_id,
                                 total, moneda, fecha_emision, datos)
    values (p_fila->>'tipo', p_fila->>'sociedad', p_fila->>'cliente_nombre', p_fila->>'proyecto_nombre',
            p_fila->>'contrato_numero', v_contrato, (p_fila->>'total')::numeric, p_fila->>'moneda',
            (p_fila->>'fecha_emision')::date, p_fila->'datos')
    returning * into f;
    update public.contrato_vencimientos cv set factura_id = f.id where cv.id = p_venc_id;
    get diagnostics n = row_count;
    if n <> 1 then raise exception 'no se pudo marcar el vencimiento %', p_venc_id using hint = 'sin_fila'; end if;
    return query select f.id, f.numero, f.datos;
  end $f$;
  revoke all on function public.zz_l553_venc_invoker(uuid, jsonb) from public, anon, authenticated;
  grant execute on function public.zz_l553_venc_invoker(uuid, jsonb) to service_role;
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

  -- a12/a13 (revisión de código, 13-oct): una proforma convertida en factura cuenta entera en el tope; el atajo de
  -- «editar sin subir el importe» solo vale para una factura que ya contaba. a3 ya factura 500 de los 1.000 de E.
  begin
    select id into v_pro from public.factura_guarda(null, jsonb_build_object('tipo', 'proforma', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'EUR', 'total', '600',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '600')), 'fields', '{}'::jsonb)));
    begin perform public.factura_guarda(v_pro, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'EUR', 'total', '600',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '600')), 'fields', '{}'::jsonb)));
      out := out || E'MAL a12 proforma de 600 pasada a factura con 500 de 1.000 facturados: PASA\n';
    exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%precio acordado%' then 'OK ' else 'MAL ' end
                                         || 'a12 proforma de 600 pasada a factura con 500 de 1.000 facturados: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  exception when others then out := out || 'MAL a12 montaje (proforma): ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;
  -- a13: la MISMA proforma de a12 (solo puede haber una proforma viva por contrato: facturas_proforma_activa_por_contrato)
  -- pasada a factura por 300: 500+300 de 1.000, pasa. La conversión no gasta número (set_factura_numero solo en INSERT).
  begin
    if v_pro is null then raise exception 'sin la proforma de a12'; end if;
    perform public.factura_guarda(v_pro, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'EUR', 'total', '300',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '300')), 'fields', '{}'::jsonb)));
    out := out || case when (select tipo from public.facturas where id = v_pro) = 'factura' then 'OK ' else 'MAL ' end
               || E'a13 proforma de 300 pasada a factura dentro del tope (500+300 de 1.000): pasa\n';
  exception when others then out := out || 'MAL a13 proforma pasada a factura por 300: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;

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
  -- h1/h2 (revisión de código, 13-oct): reactivar una factura anulada la devuelve al tope. E2: 500 vivos de 1.000.
  -- h1, 600 → 1.100: el super_admin solo pasa con rastro 'factura_sobre_tope' (PENDIENTE mientras LAW-560 no amplíe
  -- contrato_eventos_evento_check); pasar SIN rastro es MAL (era lo de antes). h2, 400 → 900: pasa.
  select count(*) into v_e0 from public.contrato_eventos where contrato_id = v_e2 and evento = 'factura_sobre_tope';
  begin perform public.factura_reactiva(v_h1);
    select count(*) into v_e1 from public.contrato_eventos where contrato_id = v_e2 and evento = 'factura_sobre_tope';
    out := out || case when v_e1 > v_e0 then 'OK ' else 'MAL ' end || 'h1 reactivar 600 sobre 500 de 1.000: pasa con rastro=' || (v_e1 > v_e0) || E'\n';
  -- 23514 por sí solo no basta (la constraint de contrato_eventos también lo da): tiene que ser el mensaje del tope
  exception when others then out := out || case when sqlerrm like '%contrato_eventos_evento_check%' then 'PENDIENTE '
                                                  when sqlstate = '23514' and sqlerrm like '%precio acordado%' then 'OK ' else 'MAL ' end
                                       || 'h1 reactivar 600 sobre 500 de 1.000: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  begin perform public.factura_reactiva(v_h2);
    out := out || case when not (select anulada from public.facturas where id = v_h2) then 'OK ' else 'MAL ' end
               || E'h2 reactivar 400 dentro del tope: pasa\n';
  exception when others then out := out || 'MAL h2 reactivar 400 dentro del tope: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;
  -- h3: la factura EUR anulada de M, ahora en IDR → no se reactiva (ni el super_admin: integridad, no tope)
  begin perform public.factura_reactiva(v_h3);
    out := out || E'MAL h3 reactivar factura EUR sobre contrato que pasó a IDR: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en IDR%' then 'OK ' else 'MAL ' end
                                       || 'h3 reactivar factura EUR sobre contrato que pasó a IDR: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
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
    out := out || E'MAL c2 robot sobre el tope (800+900 sobre 1.000): PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%precio acordado%' then 'OK ' else 'MAL ' end
                                       || 'c2 robot sobre el tope: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  -- c3: caso POSITIVO del robot (DEFINER desde 20261013074408). Dentro del tope (500+300 de a3/a13, +50 y +50: sin
  -- llegar a 1.000, porque saldar la venta dispara un aviso 'operacion_saldada' más y la comparación saldría falsa) y con la
  -- moneda buena: inserta y marca el vencimiento. Y deja lo mismo que la versión INVOKER de antes (copia de arriba,
  -- otro vencimiento del mismo contrato): creado_por (fija_autor devuelve la fila sin tocar con auth.role() =
  -- 'service_role'; el default auth.email() es null), created_at = now(), y los mismos avisos de los triggers AFTER.
  select count(*) into v_n0 from public.notificaciones where contrato_id = v_e;
  begin
    select id into v_c3 from public.factura_vencimiento_emite(v_venc, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_numero', 'ZZ-L553-E',
                 'total', 50, 'moneda', 'EUR', 'fecha_emision', current_date, 'datos', jsonb_build_object('totales', jsonb_build_object('subtotal', 50))));
    select count(*) into v_n1 from public.notificaciones where contrato_id = v_e;
    select id into v_c3i from public.zz_l553_venc_invoker(v_venc2, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_numero', 'ZZ-L553-E',
                 'total', 50, 'moneda', 'EUR', 'fecha_emision', current_date, 'datos', jsonb_build_object('totales', jsonb_build_object('subtotal', 50))));
    select count(*) into v_n2 from public.notificaciones where contrato_id = v_e;
  exception when others then out := out || 'MAL c3 robot dentro del tope: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;
  -- h4: el camino del TRIGGER. service_role (las edges) revive por UPDATE directo la proforma EUR anulada de M (ahora
  -- IDR): factura_anulada_solo_cambia_autor no mira nada sin auth.uid(), así que solo la para trg_01_moneda_del_contrato.
  out := out || case when current_user = 'service_role' then 'OK ' else 'MAL ' end || E'C0 canario service_role\n';
  begin update public.facturas set anulada = false where id = v_h4;
    out := out || E'MAL h4 service_role revive proforma EUR sobre contrato que pasó a IDR: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en IDR%' then 'OK ' else 'MAL ' end
                                       || 'h4 service_role revive proforma EUR sobre contrato IDR: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  execute 'reset role';
  if v_c3 is not null and v_c3i is not null then
    select a.creado_por is null and a.created_at = now()
           and (a.creado_por, a.created_at, a.tipo, a.moneda, a.total, a.anulada, a.enviada, a.sociedad, a.contrato_id, a.proyecto_id)
               is not distinct from (b.creado_por, b.created_at, b.tipo, b.moneda, b.total, b.anulada, b.enviada, b.sociedad, b.contrato_id, b.proyecto_id)
           and (select cv.factura_id from public.contrato_vencimientos cv where cv.id = v_venc) = v_c3
           and (select cv.factura_id from public.contrato_vencimientos cv where cv.id = v_venc2) = v_c3i
           and v_n1 - v_n0 = v_n2 - v_n1
      into v_ok
      from public.facturas a, public.facturas b where a.id = v_c3 and b.id = v_c3i;
    out := out || case when v_ok then 'OK ' else 'MAL ' end
               || 'c3 robot dentro del tope: inserta, marca el vencimiento y deja lo mismo que la versión INVOKER (avisos '
               || (v_n1 - v_n0) || '/' || (v_n2 - v_n1) || E')\n';
  end if;

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
  -- factura_reactiva: la ACL de siempre (authenticated, que dentro exige super_admin, y service_role), nunca anon
  out := out || case when has_function_privilege('authenticated', 'public.factura_reactiva(uuid)', 'execute')
                      and not has_function_privilege('anon', 'public.factura_reactiva(uuid)', 'execute')
                     then 'OK ' else 'MAL ' end || E'privilegios: factura_reactiva para authenticated, no anon\n';

  raise exception E'RESULTADOS\n%', out;
end $t$;
