-- PRUEBA POR ROL — calendario de pagos del Contrato de Construcción (28-sep-2026, migraciones 20260928052131 + 052357 + 054712 + 055624 + 060334).
-- Se ejecuta con execute_sql (MCP) o psql como postgres, UN BLOQUE POR LLAMADA: cada uno acaba en
-- `raise exception 'RES: …'`, que revierte la transacción entera — NO ESCRIBE NADA. Cada punto debe decir «ok».
-- Para probar ANTES de aplicar: `begin;` + el texto de la migración + un bloque, en la misma llamada.
-- Usuarios: agente dortegag@gmail.com, admin p@pabloglobal.es. Contratos del agente: CC00106 (5 hitos de
-- fábrica, 67.000) y CC00094 (5 hitos de antes del 16-sep, sin marca). Obra: CC00092 (bloqueado, sin firmas,
-- proyecto 2f4fb2ad…, cubo I · Hotelera 2) y CC00093 (mismo cubo, 3 hitos sin marca).

-- 1. Agente
do $$
declare r text := ''; j jsonb; p jsonb; c record; l record; ff date;
  A text := '{"sub":"1cd031f2-c7da-455e-975f-c4e8708e36fb","email":"dortegag@gmail.com","role":"authenticated"}';
begin
  select * into c from contratos where numero = 'CC00106';
  select * into l from contratos where numero = 'CC00094';
  ff := coalesce(nullif(c.datos->'fields'->>'fecha_firma', '')::date, current_date);
  perform set_config('request.jwt.claims', A, true);
  set local role authenticated;

  -- 1: guardar tal cual (sin `calendario`, como una pestaña vieja) = estándar, importes del servidor (es-ES no agrupa 4 cifras: 3350)
  p := jsonb_build_object('tipo', 'construccion', 'datos', c.datos - 'calendario');
  j := contrato_guarda(c.id, p);
  r := r || case when j->>'calendario' = 'estandar' and jsonb_array_length(j->'hitos') = 5
                  and j->'hitos'->0->>'monto' = '16.750' and j->'hitos'->3->>'monto' = '13.400'
                  and j->'hitos'->4->>'monto' = '3350' and not (j->'hitos'->0 ? 'fecha')
             then '1 ok; ' else '1 FALLO ' || (j->'hitos')::text || '; ' end;
  -- 2: % manipulado desde el navegador → el servidor lo rehace
  p := jsonb_build_object('tipo', 'construccion', 'datos',
         jsonb_set(c.datos || '{"calendario":"estandar"}', '{hitos,0,pct}', '"50"'));
  j := contrato_guarda(c.id, p);
  r := r || case when j->'hitos'->0->>'pct' = '25' then '2 ok; ' else '2 FALLO pct ' || (j->'hitos'->0->>'pct') || '; ' end;
  -- 3: pago único a la firma a +30 días
  p := jsonb_build_object('tipo', 'construccion', 'datos', c.datos || jsonb_build_object('calendario', 'unico_firma',
         'hitos', jsonb_build_array(jsonb_build_object('pct', '1', 'monto', '1', 'fecha', to_char(ff + 30, 'YYYY-MM-DD')))));
  j := contrato_guarda(c.id, p);
  r := r || case when j->>'calendario' = 'unico_firma' and jsonb_array_length(j->'hitos') = 1
                  and j->'hitos'->0->>'pct' = '100' and j->'hitos'->0->>'monto' = '67.000'
                  and j->'hitos'->0->>'fecha' = to_char(ff + 30, 'YYYY-MM-DD')
                  and j->'fields'->>'clausula_pago' = 'unico_firma'
                  and (select count(*) from contrato_vencimientos v where v.contrato_id = c.id) = 1
             then '3 ok; ' else '3 FALLO ' || j::text || '; ' end;
  -- 4-6: fecha fuera del tope, sin fecha, antes de la firma
  begin
    perform contrato_guarda(c.id, jsonb_set(p, '{datos,hitos,0,fecha}', to_jsonb(to_char(ff + 91, 'YYYY-MM-DD'))));
    r := r || '4 FALLO agente pasa del tope; ';
  exception when others then r := r || '4 ok; '; end;
  begin
    perform contrato_guarda(c.id, jsonb_set(p, '{datos,hitos,0,fecha}', '""'));
    r := r || '5 FALLO sin fecha; ';
  exception when others then r := r || '5 ok; '; end;
  begin
    perform contrato_guarda(c.id, jsonb_set(p, '{datos,hitos,0,fecha}', to_jsonb(to_char(ff - 1, 'YYYY-MM-DD'))));
    r := r || '6 FALLO antes de la firma; ';
  exception when others then r := r || '6 ok; '; end;
  -- 7: pago único al inicio de obra: la estimada NO llega a `fecha` ni al vencimiento
  p := jsonb_build_object('tipo', 'construccion', 'datos', c.datos || jsonb_build_object('calendario', 'unico_obra',
         'hitos', jsonb_build_array(jsonb_build_object('fecha', to_char(ff + 10, 'YYYY-MM-DD'),
                                                       'fecha_estimada', to_char(ff + 200, 'YYYY-MM-DD')))));
  j := contrato_guarda(c.id, p);
  r := r || case when j->>'calendario' = 'unico_obra' and not (j->'hitos'->0 ? 'fecha')
                  and j->'hitos'->0->>'fecha_estimada' = to_char(ff + 200, 'YYYY-MM-DD')
                  and (select fecha from contrato_vencimientos v where v.contrato_id = c.id and v.orden = 1) is null
             then '7 ok; ' else '7 FALLO ' || (j->'hitos')::text || '; ' end;
  -- 8: a medida → no
  begin
    perform contrato_guarda(c.id, jsonb_set(p, '{datos,calendario}', '"manual"'));
    r := r || '8 FALLO agente monta calendario a medida; ';
  exception when others then r := r || '8 ok; '; end;
  -- 9: un contrato de antes del 16-sep se guarda como siempre
  j := contrato_guarda(l.id, jsonb_build_object('tipo', 'construccion', 'datos', l.datos));
  r := r || case when j->>'calendario' = 'libre' and j->'hitos' = l.datos->'hitos' then '9 ok; ' else '9 FALLO ' || (j->'hitos')::text || '; ' end;
  -- 10: …pero no se fabrica marcas de fábrica
  begin
    perform contrato_guarda(l.id, jsonb_build_object('tipo', 'construccion', 'datos',
      jsonb_set(l.datos, '{hitos,0,fijo}', 'true')));
    r := r || '10 FALLO agente marca fijo; ';
  exception when others then r := r || '10 ok; '; end;
  -- 11: …ni % que no suman 100
  begin
    perform contrato_guarda(l.id, jsonb_build_object('tipo', 'construccion', 'datos',
      jsonb_set(l.datos, '{hitos,0,pct}', '"1"')));
    r := r || '11 FALLO suma distinta de 100; ';
  exception when others then r := r || '11 ok; '; end;
  -- 12: y puede pasarlo a un calendario de fábrica
  j := contrato_guarda(l.id, jsonb_build_object('tipo', 'construccion', 'datos', l.datos || '{"calendario":"estandar"}'));
  r := r || case when j->>'calendario' = 'estandar' and jsonb_array_length(j->'hitos') = 5 then '12 ok; ' else '12 FALLO; ' end;
  -- 13: un alta nueva no puede ser «libre»
  begin
    perform contrato_guarda(null, jsonb_build_object('tipo', 'construccion', 'datos',
      jsonb_build_object('fields', c.datos->'fields', 'calendario', 'libre', 'hitos', '[{"pct":"100","es":"x"}]'::jsonb)));
    r := r || '13 FALLO alta libre; ';
  exception when others then r := r || '13 ok; '; end;
  -- 14: alta con calendario de fábrica. Por contrato_calendario_aplica y no por contrato_guarda: un alta de
  --     verdad gasta un número de la serie CC (nextval no se deshace con el rollback).
  reset role;
  j := contrato_calendario_aplica(jsonb_build_object('fields', c.datos->'fields', 'calendario', 'unico_firma',
         'hitos', jsonb_build_array(jsonb_build_object('fecha', to_char(ff + 5, 'YYYY-MM-DD')))), null, 67000, ff, null);
  r := r || case when j->>'calendario' = 'unico_firma' and j->'hitos'->0->>'monto' = '67.000' then '14 ok; ' else '14 FALLO; ' end;
  set local role authenticated;
  -- 15: con un pago ya movido, no se cambia de calendario
  reset role;
  update contrato_vencimientos set ajustado = true where contrato_id = c.id;
  set local role authenticated;
  begin
    perform contrato_guarda(c.id, jsonb_build_object('tipo', 'construccion', 'datos', c.datos || '{"calendario":"estandar"}'));
    r := r || '15 FALLO cambia calendario con pagos movidos; ';
  exception when others then r := r || '15 ok; '; end;
  -- 16: las funciones internas no se llaman desde el navegador
  begin
    perform contrato_calendario_monta('estandar', 1, '[]', current_date, true);
    r := r || '16 FALLO monta expuesta; ';
  exception when others then r := r || '16 ok; '; end;
  raise exception 'RES: %', r;
end $$;

-- 2. Admin
do $$
declare r text := ''; j jsonb; p jsonb; c record; ff date;
  ADM text := '{"sub":"24257595-aee2-4daa-8170-d268f46b9981","email":"p@pabloglobal.es","role":"authenticated"}';
begin
  select * into c from contratos where numero = 'CC00106';
  ff := coalesce(nullif(c.datos->'fields'->>'fecha_firma', '')::date, current_date);
  perform set_config('request.jwt.claims', ADM, true);
  set local role authenticated;
  -- 1: pasa del tope de 90 días
  p := jsonb_build_object('tipo', 'construccion', 'datos', c.datos || jsonb_build_object('calendario', 'unico_firma',
         'hitos', jsonb_build_array(jsonb_build_object('fecha', to_char(ff + 200, 'YYYY-MM-DD')))));
  j := contrato_guarda(c.id, p);
  r := r || case when j->'hitos'->0->>'fecha' = to_char(ff + 200, 'YYYY-MM-DD') then '1 ok; ' else '1 FALLO; ' end;
  -- 2: calendario a medida
  j := contrato_guarda(c.id, jsonb_build_object('tipo', 'construccion', 'datos', c.datos || jsonb_build_object('calendario', 'manual',
         'hitos', '[{"pct":"60","monto":"","es":"A","fijo":true},{"pct":"40","monto":"","es":"B","fijo":true}]'::jsonb)));
  r := r || case when j->>'calendario' = 'manual' and jsonb_array_length(j->'hitos') = 2 then '2 ok; ' else '2 FALLO; ' end;
  -- 3: a medida que no suma 100
  begin
    perform contrato_guarda(c.id, jsonb_build_object('tipo', 'construccion', 'datos', c.datos || jsonb_build_object('calendario', 'manual',
         'hitos', '[{"pct":"60","es":"A"},{"pct":"30","es":"B"}]'::jsonb)));
    r := r || '3 FALLO admin guarda 90 %; ';
  exception when others then r := r || '3 ok; '; end;
  raise exception 'RES: %', r;
end $$;

-- 3. Agente sobre un contrato a medida (lo montó el admin): conserva la tabla, solo mueve fechas
do $$
declare r text := ''; j jsonb; c record;
  A text := '{"sub":"1cd031f2-c7da-455e-975f-c4e8708e36fb","email":"dortegag@gmail.com","role":"authenticated"}';
begin
  select * into c from contratos where numero = 'CC00106';
  update contratos set datos = datos || '{"calendario":"manual","hitos":[{"pct":"60","monto":"40.200","es":"A","fijo":true},{"pct":"40","monto":"26.800","es":"B","fijo":true}]}'
   where id = c.id;
  select * into c from contratos where id = c.id;
  perform set_config('request.jwt.claims', A, true);
  set local role authenticated;
  j := contrato_guarda(c.id, jsonb_build_object('tipo', 'construccion', 'datos',
         jsonb_set(jsonb_set(c.datos, '{hitos,0,pct}', '"99"'), '{hitos,1,fecha}', '"2027-01-15"')));
  r := r || case when j->'hitos'->0->>'pct' = '60' and j->'hitos'->1->>'fecha' = '2027-01-15' and j->>'calendario' = 'manual'
             then '1 ok; ' else '1 FALLO ' || (j->'hitos')::text || '; ' end;
  begin
    perform contrato_guarda(c.id, jsonb_build_object('tipo', 'construccion', 'datos',
      c.datos || '{"hitos":[{"pct":"100","es":"A","fijo":true}]}'));
    r := r || '2 FALLO agente quita hitos de un calendario a medida; ';
  exception when others then r := r || '2 ok; '; end;
  raise exception 'RES: %', r;
end $$;

-- 4. Obra: pago único al inicio de obra entra en el pago 1; a la firma y fases posteriores, fuera con motivo
do $$
declare r text := ''; c record; x record; py uuid;
  ADM text := '{"sub":"24257595-aee2-4daa-8170-d268f46b9981","email":"p@pabloglobal.es","role":"authenticated"}';
begin
  select * into c from contratos where numero = 'CC00092';
  py := c.proyecto_id;
  update contratos set datos = datos || jsonb_build_object('calendario', 'unico_obra',
         'hitos', contrato_calendario_monta('unico_obra', 100000, '[]', current_date, true)) where id = c.id;
  perform set_config('request.jwt.claims', ADM, true);
  set local role authenticated;
  select * into x from obra_contratos_afectados(py, 'I', 'Hotelera 2', 'preparacion') a where a.contrato_id = c.id;
  r := r || case when x.elegible and x.motivo is null then '1 ok; ' else '1 FALLO ' || coalesce(x.motivo, 'null') || '; ' end;
  select * into x from obra_contratos_afectados(py, 'I', 'Hotelera 2', 'estructura') a where a.contrato_id = c.id;
  r := r || case when not x.elegible and x.motivo = 'pago_unico_ya_al_inicio' then '2 ok; ' else '2 FALLO ' || coalesce(x.motivo, 'null') || '; ' end;
  select * into x from obra_contratos_afectados(py, 'I', 'Hotelera 2', 'preparacion') a where a.numero = 'CC00093';
  r := r || case when not x.elegible and x.motivo = 'anterior_al_mecanismo' then '3 ok; ' else '3 FALLO ' || coalesce(x.motivo, 'null') || '; ' end;
  reset role;
  update contratos set datos = datos || jsonb_build_object('calendario', 'unico_firma') where id = c.id;
  set local role authenticated;
  select * into x from obra_contratos_afectados(py, 'I', 'Hotelera 2', 'preparacion') a where a.contrato_id = c.id;
  r := r || case when not x.elegible and x.motivo = 'pago_unico_firma' then '4 ok; ' else '4 FALLO ' || coalesce(x.motivo, 'null') || '; ' end;
  raise exception 'RES: %', r;
end $$;

-- 5. Tras 20260928054712: los importes de un calendario a medida siguen al precio, y un agente no le cambia la forma de
--    pago. El precio de la prueba 1 entra por contrato_calendario_aplica: por contrato_guarda, el trigger
--    descuento_comercial_construccion_valido no deja un precio que no cuadre con techo + extras − descuento.
do $$
declare r text := ''; j jsonb; c record; ant jsonb;
  A text := '{"sub":"1cd031f2-c7da-455e-975f-c4e8708e36fb","email":"dortegag@gmail.com","role":"authenticated"}';
begin
  select * into c from contratos where numero = 'CC00106';
  ant := c.datos || '{"calendario":"manual","hitos":[{"pct":"60","monto":"40.200","es":"A","fijo":true,"calculado":true},{"pct":"40","monto":"26.800","es":"B","fijo":true,"calculado":true,"resto":true}]}';
  update contratos set datos = ant where id = c.id;
  perform set_config('request.jwt.claims', A, true);
  j := contrato_calendario_aplica(ant, ant, 70000, current_date, c.id);
  r := r || case when j->'hitos'->0->>'monto' = '42.000' and j->'hitos'->1->>'monto' = '28.000' then '1 ok; ' else '1 FALLO ' || (j->'hitos')::text || '; ' end;
  set local role authenticated;
  begin
    perform contrato_guarda(c.id, jsonb_build_object('tipo', 'construccion', 'datos', ant || '{"calendario":"estandar"}'));
    r := r || '2 FALLO agente pisa el calendario del admin; ';
  exception when others then r := r || '2 ok; '; end;
  reset role;
  j := contrato_calendario_monta('estandar', 67000, '[]', current_date, false);
  r := r || case when j->0->>'monto' = '16.750' and j->4->>'monto' = '3350' then '3 ok; ' else '3 FALLO ' || j::text || '; ' end;
  j := contrato_calendario_monta('estandar', 100000.01, '[]', current_date, false);
  r := r || case when (select sum(public.lw_importe(h->>'monto')) from jsonb_array_elements(j) h) = 100000.01 then '4 ok; ' else '4 FALLO ' || j::text || '; ' end;
  raise exception 'RES: %', r;
end $$;

-- 6. Tras 20260928055624: un vencimiento facturado sobrevive a un guardado que reescribe los hitos; el tope del pago
--    único se aplica en un alta; la fecha ya guardada (puesta por un admin) no bloquea al agente, pero cambiarla sí.
--    Ejecutada el 28-sep contra producción: 4/4 ok.
do $$
declare r text := ''; j jsonb; c record; ant jsonb; fid uuid; ff date;
  A text := '{"sub":"1cd031f2-c7da-455e-975f-c4e8708e36fb","email":"dortegag@gmail.com","role":"authenticated"}';
begin
  select * into c from contratos where numero = 'CC00106';
  ff := coalesce(nullif(c.datos->'fields'->>'fecha_firma', '')::date, current_date);
  select id into fid from facturas limit 1;
  update contrato_vencimientos set factura_id = fid where contrato_id = c.id and orden = 2;
  perform set_config('request.jwt.claims', A, true);
  set local role authenticated;
  j := contrato_guarda(c.id, jsonb_build_object('tipo', 'construccion', 'datos', jsonb_set(c.datos, '{hitos,0,monto}', '"1"')));
  reset role;
  r := r || case when (select factura_id from contrato_vencimientos where contrato_id = c.id and orden = 2) = fid then '1 ok; ' else '1 FALLO se perdió la factura; ' end;
  begin
    perform contrato_calendario_aplica(jsonb_build_object('fields', c.datos->'fields', 'calendario', 'unico_firma',
      'hitos', jsonb_build_array(jsonb_build_object('fecha', to_char(ff + 120, 'YYYY-MM-DD')))), null, 67000, ff, null);
    r := r || '2 FALLO alta salta el tope; ';
  exception when others then r := r || '2 ok; '; end;
  ant := c.datos || jsonb_build_object('calendario', 'unico_firma', 'hitos',
           contrato_calendario_monta('unico_firma', 67000, jsonb_build_array(jsonb_build_object('fecha', to_char(ff + 200, 'YYYY-MM-DD'))), ff, true));
  j := contrato_calendario_aplica(ant, ant, 67000, ff, c.id);
  r := r || case when j->'hitos'->0->>'fecha' = to_char(ff + 200, 'YYYY-MM-DD') then '3 ok; ' else '3 FALLO; ' end;
  begin
    perform contrato_calendario_aplica(jsonb_set(ant, '{hitos,0,fecha}', to_jsonb(to_char(ff + 201, 'YYYY-MM-DD'))), ant, 67000, ff, c.id);
    r := r || '4 FALLO; ';
  exception when others then r := r || '4 ok; '; end;
  raise exception 'RES: %', r;
end $$;

-- 7. Tras 20260928060334 (consultas de Legal y Datos): un pago «no facturar» conserva su marca y su nota cuando se
--    reescriben los hitos, y bloquea el cambio de calendario; el pago único se llama «Pago único». 3/3 ok el 28-sep.
do $$
declare r text := ''; j jsonb; c record; ff date;
  A text := '{"sub":"1cd031f2-c7da-455e-975f-c4e8708e36fb","email":"dortegag@gmail.com","role":"authenticated"}';
begin
  select * into c from contratos where numero = 'CC00106';
  ff := coalesce(nullif(c.datos->'fields'->>'fecha_firma', '')::date, current_date);
  update contrato_vencimientos set no_facturar = true, nota = 'pactado aparte' where contrato_id = c.id and orden = 1;
  perform set_config('request.jwt.claims', A, true);
  set local role authenticated;
  j := contrato_guarda(c.id, jsonb_build_object('tipo', 'construccion', 'datos', jsonb_set(c.datos, '{hitos,0,monto}', '"1"')));
  reset role;
  r := r || case when (select no_facturar and nota = 'pactado aparte' and monto = 16750 from contrato_vencimientos where contrato_id = c.id and orden = 1) then '1 ok; ' else '1 FALLO; ' end;
  set local role authenticated;
  begin
    perform contrato_guarda(c.id, jsonb_build_object('tipo', 'construccion', 'datos', c.datos || jsonb_build_object('calendario', 'unico_firma',
         'hitos', jsonb_build_array(jsonb_build_object('fecha', to_char(ff + 30, 'YYYY-MM-DD'))))));
    r := r || '2 FALLO cambia calendario con un pago no facturar; ';
  exception when others then r := r || '2 ok; '; end;
  reset role;
  r := r || case when contrato_calendario_preset('unico_firma')->0->>'es' = 'Pago único' then '3 ok; ' else '3 FALLO; ' end;
  raise exception 'RES: %', r;
end $$;
