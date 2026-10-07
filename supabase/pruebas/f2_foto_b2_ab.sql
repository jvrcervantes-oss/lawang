-- A/B de la foto del bloque 2: en UNA transaccion calcula la foto con lo que hay aplicado, restaura las funciones/policies ORIGINALES del bloque que se quieran comparar
-- (desde public._f2_b2_originales, sin tocar nada de produccion: todo acaba en rollback) y vuelve a calcularla, y escribe QUE USUARIOS cambian entre las dos.
-- Sirve para separar «he cambiado el comportamiento» de «produccion cambio de datos entre dos fotos». Edita la lista `nombres` con lo que quieras comparar contra el original.
-- destructivo-ok: restaura definiciones desde la instantanea y termina en raise (rollback)
do $t$
declare
  nombres text[] := array[
    'f:_gasto_puede()','f:gasto_guarda(p_id uuid, p_datos jsonb)','f:gasto_anula(p_id uuid, p_motivo text)','f:gasto_marca_pagado(p_id uuid, p_pagado_el date, p_cuenta text)',
    'f:gasto_pph_ingresado(p_id uuid, p_fecha date)','f:gasto_anade_justificante(p_id uuid, p_ruta text, p_nombre text)','f:gasto_justificante_registra(p_uid uuid, p_gasto uuid, p_path text, p_nombre text)',
    'f:gasto_historial_datos(p_gasto uuid, p_limit integer)','f:proveedor_guarda(p_id uuid, p_datos jsonb)','f:gastos_panel_datos(p_limit integer, p_despues_fecha date, p_despues uuid)',
    'p:public.gastos:gastos: leer','p:public.gastos_log:gastos_log: leer','p:public.proveedores:proveedores: leer','p:public.gasto_categorias:categorias: leer',
    'p:storage.objects:gastos: leer justificantes'];
  fantasma constant uuid := '00000000-0000-4000-8000-00000000f2b2';
  tablas constant text[] := array['gastos','gastos_log','proveedores','gasto_categorias','bancos_movimientos','bancos_conciliacion','bancos_perfiles',
                                  'recibi_aplicaciones','solicitudes_pago_retencion','sociedades_log','ajustes_log','solicitudes_cambio','cuentas_bancarias',
                                  'solicitudes_pago','facturas','sociedades'];
  lecturas constant text[] := array[
    'public.gastos_panel_datos()', 'public.panel_bancos_datos()', 'public.bancos_resumen()', 'public.sociedades_ajustes_datos()',
    'public.cuentas_uso()', 'public.cuentas_cobro_visibles()', 'public.sociedades_visibles()',
    format('public.gasto_historial_datos(%L::uuid)', fantasma)];
  escrituras constant text[] := array[
    format('public.factura_borra(%L::uuid)', fantasma), format('public.factura_anula(%L::uuid)', fantasma), format('public.factura_reactiva(%L::uuid)', fantasma),
    format('public.factura_marca_enviada(%L::uuid)', fantasma),
    format('public.factura_guarda(%L::uuid, %L::jsonb)', fantasma, '{"tipo":"factura","moneda":"EUR","total":"1","sociedad":"tepi_sungai","datos":{"lineas":[{"d":"x","q":1,"p":1}]}}'),
    format('public.guardar_recibi(null::uuid, %L::jsonb, %L::jsonb)', '{"contrato_id":"00000000-0000-4000-8000-00000000f2b2","sociedad":"tepi_sungai"}', '[]'),
    format('public.gasto_guarda(%L::uuid, %L::jsonb)', fantasma, '{"base":"1","sociedad":"tepi_sungai"}'),
    format('public.gasto_anula(%L::uuid, %L)', fantasma, 'x'), format('public.gasto_marca_pagado(%L::uuid, current_date, %L)', fantasma, 'x'),
    format('public.gasto_pph_ingresado(%L::uuid, current_date)', fantasma),
    format('public.gasto_anade_justificante(%L::uuid, %L, %L)', fantasma, fantasma || '/x.pdf', 'n'),
    format('public.proveedor_guarda(%L::uuid, %L::jsonb)', fantasma, '{"nombre":"x"}'),
    format('public.solicitud_pago_guarda(%L::uuid, %L::jsonb)', fantasma, '{"importe":1,"concepto":"x"}'),
    format('public.solicitud_pago_resuelve(%L::uuid, %L)', fantasma, 'aprobada'),
    format('public.solicitud_pago_retencion_guarda(%L::uuid, %L::jsonb)', fantasma, '{}'),
    format('public.solicitud_pago_retencion_rectifica(%L::uuid, %L, %L)', fantasma, 'batal', 'x'),
    format('public.bancos_conciliar(%L::uuid, %L::jsonb)', fantasma, '[]'), 'public.bancos_desconciliar(-1)',
    format('public.bancos_designorar(%L::uuid)', fantasma), format('public.bancos_ignorar(%L::uuid, %L)', fantasma, 'x'),
    format('public.bancos_importar(%L, %L, %L::jsonb)', 'cuenta_fantasma', 'f.csv', '[{"fecha":"2026-01-01","importe":1,"moneda":"EUR","huella":"x"}]'),
    format('public.banco_perfil_guarda(%L, %L::jsonb)', 'cuenta_fantasma', '{}'),
    format('public.cuenta_bancaria_guarda(%L, %L::jsonb, false)', 'zzz_fantasma', '{}'),
    format('public.sociedad_guarda(%L, %L::jsonb, false)', 'zzz_fantasma', '{}')];
  u record; linea text; h text; t text; sql text; r record;
  foto1 text[] := '{}'; foto2 text[] := '{}'; i int; difs text := ''; n int := 0; cols1 text[]; cols2 text[]; j int; cuales text;
begin
  for pasada in 1..2 loop
    if pasada = 2 then
      for r in select ddl from public._f2_b2_originales where nombre = any (nombres) order by tipo desc loop execute r.ddl; end loop;
    end if;
    for u in select user_id, email from public.usuarios order by email loop
      linea := u.email;
      perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
      set local role authenticated;
      foreach t in array tablas loop
        begin execute format('select md5(coalesce(string_agg(x::text, '','' order by x::text),'''')) from public.%I x', t) into h; linea := linea || '|' || left(h, 5);
        exception when others then linea := linea || '|E' || sqlstate; end;
      end loop;
      foreach sql in array lecturas loop
        begin execute format('select md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from (select * from (select %s) q) x)::text, ''-''))', sql) into h; linea := linea || '|' || left(h, 5);
        exception when others then linea := linea || '|E' || sqlstate; end;
      end loop;
      foreach sql in array escrituras loop
        begin execute format('select %s', sql); linea := linea || '|ok';
        exception when others then linea := linea || '|E' || sqlstate; end;
      end loop;
      reset role;
      if pasada = 1 then foto1 := foto1 || linea; else foto2 := foto2 || linea; end if;
    end loop;
  end loop;
  for i in 1..cardinality(foto1) loop
    if foto1[i] is distinct from foto2[i] then
      cols1 := string_to_array(foto1[i], '|'); cols2 := string_to_array(foto2[i], '|'); cuales := '';
      for j in 2..cardinality(cols1) loop
        if cols1[j] is distinct from cols2[j] then cuales := cuales || format(' #%s:%s->%s', j - 1, cols2[j], cols1[j]); end if;
      end loop;
      difs := difs || split_part(foto1[i], '|', 1) || cuales || E'\n'; n := n + 1;
    end if;
  end loop;
  raise exception E'FOTOB2_AB usuarios con diferencias = %\n(columnas: 1-16 tablas, 17-24 lecturas, 25+ escrituras; formato #col:ORIGINAL->NUEVO)\n%', n, difs;
end $t$;
