-- Foto del bloque 2 (DINERO) de la Fase 2 (8-oct-2026): para CADA usuario (los 34 de hoy), con su JWT (email) y `set local role authenticated`,
--   (a) md5 de lo que ve de cada tabla del bloque (gastos, proveedores, bancos_*, categorias, aplicaciones, retenciones, logs, cuentas...),
--   (b) md5 del resultado de cada RPC de lectura del bloque, o el sqlstate si falla,
--   (c) sqlstate de cada RPC de ESCRITURA llamada con ids que no existen (nada se toca; ademas todo acaba en rollback).
-- Por defecto solo imprime el md5; con `set local f2b2.v = '1';` delante imprime tambien la linea de cada usuario (para ver QUIEN cambio).
-- No incluye lo del 2A/2B (eso es f2_foto_ids.sql). El md5 final debe ser IDENTICO antes y despues de cada migracion del bloque.
-- Produccion esta viva: si cambia una fila entre foto y foto, aparece en la linea de ese usuario; se regenera la previa justo antes de aplicar.
-- destructivo-ok: solo lectura y llamadas a ids inexistentes; termina en raise (rollback)
do $t$
declare
  u record; out text := ''; linea text; h text; t text; sql text; i int;
  fantasma constant uuid := '00000000-0000-4000-8000-00000000f2b2';
  tablas constant text[] := array['gastos','gastos_log','proveedores','gasto_categorias','bancos_movimientos','bancos_conciliacion','bancos_perfiles',
                                  'recibi_aplicaciones','solicitudes_pago_retencion','sociedades_log','ajustes_log','solicitudes_cambio','cuentas_bancarias',
                                  'solicitudes_pago','facturas','sociedades'];
  lecturas constant text[] := array[
    'public.gastos_panel_datos()', 'public.panel_bancos_datos()', 'public.bancos_resumen()', 'public.sociedades_ajustes_datos()',
    'public.cuentas_uso()', 'public.cuentas_cobro_visibles()', 'public.sociedades_visibles()',
    format('public.gasto_historial_datos(%L::uuid)', fantasma)];
  escrituras constant text[] := array[
    format('public.factura_borra(%L::uuid)', fantasma),
    format('public.factura_anula(%L::uuid)', fantasma),
    format('public.factura_reactiva(%L::uuid)', fantasma),
    format('public.factura_marca_enviada(%L::uuid)', fantasma),
    format('public.factura_guarda(%L::uuid, %L::jsonb)', fantasma, '{"tipo":"factura","moneda":"EUR","total":"1","sociedad":"tepi_sungai","datos":{"lineas":[{"d":"x","q":1,"p":1}]}}'),
    format('public.guardar_recibi(null::uuid, %L::jsonb, %L::jsonb)', '{"contrato_id":"00000000-0000-4000-8000-00000000f2b2","sociedad":"tepi_sungai"}', '[]'),
    format('public.gasto_guarda(%L::uuid, %L::jsonb)', fantasma, '{"base":"1","sociedad":"tepi_sungai"}'),
    format('public.gasto_anula(%L::uuid, %L)', fantasma, 'x'),
    format('public.gasto_marca_pagado(%L::uuid, current_date, %L)', fantasma, 'x'),
    format('public.gasto_pph_ingresado(%L::uuid, current_date)', fantasma),
    format('public.gasto_anade_justificante(%L::uuid, %L, %L)', fantasma, fantasma || '/x.pdf', 'n'),
    format('public.proveedor_guarda(%L::uuid, %L::jsonb)', fantasma, '{"nombre":"x"}'),
    format('public.solicitud_pago_guarda(%L::uuid, %L::jsonb)', fantasma, '{"importe":1,"concepto":"x"}'),
    format('public.solicitud_pago_resuelve(%L::uuid, %L)', fantasma, 'aprobada'),
    format('public.solicitud_pago_retencion_guarda(%L::uuid, %L::jsonb)', fantasma, '{}'),
    format('public.solicitud_pago_retencion_rectifica(%L::uuid, %L, %L)', fantasma, 'batal', 'x'),
    format('public.bancos_conciliar(%L::uuid, %L::jsonb)', fantasma, '[]'),
    'public.bancos_desconciliar(-1)',
    format('public.bancos_designorar(%L::uuid)', fantasma),
    format('public.bancos_ignorar(%L::uuid, %L)', fantasma, 'x'),
    format('public.bancos_importar(%L, %L, %L::jsonb)', 'cuenta_fantasma', 'f.csv', '[{"fecha":"2026-01-01","importe":1,"moneda":"EUR","huella":"x"}]'),
    format('public.banco_perfil_guarda(%L, %L::jsonb)', 'cuenta_fantasma', '{}'),
    format('public.cuenta_bancaria_guarda(%L, %L::jsonb, false)', 'zzz_fantasma', '{}'),
    format('public.sociedad_guarda(%L, %L::jsonb, false)', 'zzz_fantasma', '{}')];
begin
  for u in select user_id, email from public.usuarios order by email loop
    linea := u.email;
    perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
    set local role authenticated;
    foreach t in array tablas loop
      begin
        execute format('select md5(coalesce(string_agg(x::text, '','' order by x::text),'''')) from public.%I x', t) into h;
        linea := linea || '|' || left(h, 5);
      exception when others then linea := linea || '|E' || sqlstate; end;
    end loop;
    foreach sql in array lecturas loop
      begin
        execute format('select md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from (select * from (select %s) q) x)::text, ''-''))', sql) into h;
        linea := linea || '|' || left(h, 5);
      exception when others then
        begin
          execute format('select md5(%s::text)', sql) into h;
          linea := linea || '|' || left(h, 5);
        exception when others then linea := linea || '|E' || sqlstate; end;
      end;
    end loop;
    foreach sql in array escrituras loop
      begin
        execute format('select %s', sql);
        linea := linea || '|ok';
      exception when others then linea := linea || '|E' || sqlstate; end;
    end loop;
    reset role;
    out := out || linea || E'\n';
  end loop;
  raise exception E'FOTOB2\nMD5=%\n%', md5(out), case when current_setting('f2b2.v', true) = '1' then out else '(lineas por usuario: ejecutar con set local f2b2.v = ''1'' delante)' end;
end $t$;
