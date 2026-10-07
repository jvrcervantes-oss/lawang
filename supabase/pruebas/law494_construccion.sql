-- Prueba de LAW-494 (7-oct-2026): trigger de Construcción con un solo parser, techo exigido en UPDATE y volteo de tipo.
-- Se ejecuta por execute_sql y TERMINA CON UN RAISE a propósito: no deja rastro. Cada caso va en su propio
-- sub-bloque que también acaba en excepción, así que los casos no se pisan entre sí.
-- Para probar la migración ANTES de aplicarla: pegar su `create or replace` delante de este bloque en el MISMO
-- execute_sql (el raise final deshace también la función). Sin pegarla, prueba la función viva.
-- Esperado con la versión nueva (resultado del 7-oct, columna derecha = versión anterior, que demostraba el agujero):
--   T1 guardado normal (contrato_guarda)                   PASA      | PASA
--   T1b re-elegir el mismo techo (corre el contraste)        PASA      | PASA
--   T2 contrato antiguo sin techo (CC00096)                  PASA      | (vivo: no medido con CC00096)
--   T3 CC00107 (LAW-267) por super_admin                     RECHAZA   | RECHAZA  (firma en curso: lo para
--      contrato_no_editable_en_firma, no este trigger; ni sin sesión se edita, así que el arreglo no le cambia nada)
--   T4 techo "48.000" y total "48.000" (guarda 48000)        PASA      | RECHAZA (la base leía 48)
--   T5 techo "48.000" y total 48 (UPDATE directo)            RECHAZA   | PASA  <- agujero 1
--   T5b lo mismo por contrato_guarda                         RECHAZA   | PASA  <- agujero 1
--   T6 quitar el techo y total 1                             RECHAZA   | PASA  <- agujero 2
--   T6b lo mismo por contrato_guarda                         RECHAZA   | PASA  <- agujero 2
--   T7 volteo contrato_general(techo 1) -> construccion      RECHAZA   | PASA  <- agujero 3
--   T8 descuento > 15 % como admin                           RECHAZA   | RECHAZA
--   T8b descuento > 15 % como super_admin                    PASA      | PASA (exención del 29-sep)
--   T9 descuento 2.000 y total 46.000                        PASA      | PASA
-- Datos de producción del 7-oct (CC00120 48.000 sin extras; CC00122 con extra y descuento; CC00096 sin techo;
-- CC00107 = LAW-267). Ajustar si cambian.
do $t$
declare
  out text := '';
  u_ad uuid; u_sa uuid; e_ad text; e_sa text;
  c120 public.contratos%rowtype; c122 public.contratos%rowtype; c107 public.contratos%rowtype; c097 public.contratos%rowtype;
  d jsonb; r jsonb;
begin
  select user_id, email into u_ad, e_ad from public.usuarios where activo and rol = 'admin' and email like 'p@p%' limit 1;
  select user_id, email into u_sa, e_sa from public.usuarios where activo and rol = 'super_admin' order by email limit 1;
  select * into c120 from public.contratos where numero = 'CC00120';
  select * into c122 from public.contratos where numero = 'CC00122';
  select * into c107 from public.contratos where numero = 'CC00107';
  select * into c097 from public.contratos where numero = 'CC00096';

  -- T1
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', u_ad, 'role', 'authenticated', 'email', e_ad)::text, true);
    r := public.contrato_guarda(c122.id, jsonb_build_object('tipo', 'construccion', 'datos', c122.datos));
    raise exception '__PASO__ total=%', r->>'precio_total';
  exception when others then out := out || 'T1  ' || case when sqlerrm like '__PASO__%' then 'PASA ' || sqlerrm else 'RECHAZA ' || left(sqlerrm, 140) end || E'\n'; end;
  -- T1b
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', u_ad, 'role', 'authenticated', 'email', e_ad)::text, true);
    d := jsonb_set(c122.datos, '{techo,fecha_resuelta}', to_jsonb('2026-10-07T00:00:00Z'::text));
    r := public.contrato_guarda(c122.id, jsonb_build_object('tipo', 'construccion', 'datos', d));
    raise exception '__PASO__ total=%', r->>'precio_total';
  exception when others then out := out || 'T1b ' || case when sqlerrm like '__PASO__%' then 'PASA ' || sqlerrm else 'RECHAZA ' || left(sqlerrm, 140) end || E'\n'; end;
  -- T2
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', u_ad, 'role', 'authenticated', 'email', e_ad)::text, true);
    r := public.contrato_guarda(c097.id, jsonb_build_object('tipo', 'construccion', 'datos', c097.datos));
    raise exception '__PASO__ total=%', r->>'precio_total';
  exception when others then out := out || 'T2  ' || case when sqlerrm like '__PASO__%' then 'PASA ' || sqlerrm else 'RECHAZA ' || left(sqlerrm, 140) end || E'\n'; end;
  -- T3
  begin
    -- CC00107 tiene una firma en curso: solo un super_admin puede guardarlo (regla de contrato_guarda, no de este trigger)
    perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'role', 'authenticated', 'email', e_sa)::text, true);
    r := public.contrato_guarda(c107.id, jsonb_build_object('tipo', 'construccion', 'datos', c107.datos));
    raise exception '__PASO__ total=%', r->>'precio_total';
  exception when others then out := out || 'T3  ' || case when sqlerrm like '__PASO__%' then 'PASA ' || sqlerrm else 'RECHAZA ' || left(sqlerrm, 140) end || E'\n'; end;
  -- T4
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', u_ad, 'role', 'authenticated', 'email', e_ad)::text, true);
    d := jsonb_set(jsonb_set(c120.datos, '{techo,precio}', to_jsonb('48.000'::text)), '{fields,precio_total}', to_jsonb('48.000'::text));
    r := public.contrato_guarda(c120.id, jsonb_build_object('tipo', 'construccion', 'datos', d));
    raise exception '__PASO__ total=% guardado=%', r->>'precio_total', (select precio_total from public.contratos where id = c120.id);
  exception when others then out := out || 'T4  ' || case when sqlerrm like '__PASO__%' then 'PASA ' || sqlerrm else 'RECHAZA ' || left(sqlerrm, 140) end || E'\n'; end;
  -- T5
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', u_ad, 'role', 'authenticated', 'email', e_ad)::text, true);
    update public.contratos set datos = jsonb_set(datos, '{techo,precio}', to_jsonb('48.000'::text)), precio_total = 48 where id = c120.id;
    raise exception '__PASO__ guardado=%', (select precio_total from public.contratos where id = c120.id);
  exception when others then out := out || 'T5  ' || case when sqlerrm like '__PASO__%' then 'PASA ' || sqlerrm else 'RECHAZA ' || left(sqlerrm, 140) end || E'\n'; end;
  -- T5b
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', u_ad, 'role', 'authenticated', 'email', e_ad)::text, true);
    d := jsonb_set(jsonb_set(c120.datos, '{techo,precio}', to_jsonb('48.000'::text)), '{fields,precio_total}', to_jsonb('48'::text));
    r := public.contrato_guarda(c120.id, jsonb_build_object('tipo', 'construccion', 'datos', d));
    raise exception '__PASO__ total=%', r->>'precio_total';
  exception when others then out := out || 'T5b ' || case when sqlerrm like '__PASO__%' then 'PASA ' || sqlerrm else 'RECHAZA ' || left(sqlerrm, 140) end || E'\n'; end;
  -- T6
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', u_ad, 'role', 'authenticated', 'email', e_ad)::text, true);
    update public.contratos set datos = datos - 'techo', precio_total = 1 where id = c120.id;
    raise exception '__PASO__ guardado=%', (select precio_total from public.contratos where id = c120.id);
  exception when others then out := out || 'T6  ' || case when sqlerrm like '__PASO__%' then 'PASA ' || sqlerrm else 'RECHAZA ' || left(sqlerrm, 140) end || E'\n'; end;
  -- T6b
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', u_ad, 'role', 'authenticated', 'email', e_ad)::text, true);
    d := jsonb_set(c120.datos - 'techo', '{fields,precio_total}', to_jsonb('1'::text));
    r := public.contrato_guarda(c120.id, jsonb_build_object('tipo', 'construccion', 'datos', d));
    raise exception '__PASO__ total=%', r->>'precio_total';
  exception when others then out := out || 'T6b ' || case when sqlerrm like '__PASO__%' then 'PASA ' || sqlerrm else 'RECHAZA ' || left(sqlerrm, 140) end || E'\n'; end;
  -- T7: paso 1 (de otro tipo, techo a 1, total 1) y paso 2 (solo se voltea el tipo, con sesión)
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', u_ad, 'role', 'authenticated', 'email', e_ad)::text, true);
    begin
      update public.contratos set tipo = 'contrato_general', datos = jsonb_set(datos, '{techo,precio}', '1'::jsonb), precio_total = 1 where id = c120.id;
    exception when others then raise exception 'PASO1 falla: %', left(sqlerrm, 120);
    end;
    update public.contratos set tipo = 'construccion' where id = c120.id;
    raise exception '__PASO__ guardado=%', (select precio_total from public.contratos where id = c120.id);
  exception when others then out := out || 'T7  ' || case when sqlerrm like '__PASO__%' then 'PASA ' || sqlerrm else 'RECHAZA ' || left(sqlerrm, 140) end || E'\n'; end;
  -- T8
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', u_ad, 'role', 'authenticated', 'email', e_ad)::text, true);
    update public.contratos set datos = jsonb_set(datos, '{fields,descuento_comercial}', to_jsonb('9000'::text)), precio_total = 39000 where id = c120.id;
    raise exception '__PASO__';
  exception when others then out := out || 'T8  ' || case when sqlerrm like '__PASO__%' then 'PASA ' || sqlerrm else 'RECHAZA ' || left(sqlerrm, 140) end || E'\n'; end;
  -- T8b
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', u_sa, 'role', 'authenticated', 'email', e_sa)::text, true);
    update public.contratos set datos = jsonb_set(datos, '{fields,descuento_comercial}', to_jsonb('9000'::text)), precio_total = 39000 where id = c120.id;
    raise exception '__PASO__';
  exception when others then out := out || 'T8b ' || case when sqlerrm like '__PASO__%' then 'PASA ' || sqlerrm else 'RECHAZA ' || left(sqlerrm, 140) end || E'\n'; end;
  -- T9
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', u_ad, 'role', 'authenticated', 'email', e_ad)::text, true);
    update public.contratos set datos = jsonb_set(datos, '{fields,descuento_comercial}', to_jsonb('2000'::text)), precio_total = 46000 where id = c120.id;
    raise exception '__PASO__';
  exception when others then out := out || 'T9  ' || case when sqlerrm like '__PASO__%' then 'PASA ' || sqlerrm else 'RECHAZA ' || left(sqlerrm, 140) end || E'\n'; end;

  raise exception E'RESULTADOS\n%', out;
end $t$;
