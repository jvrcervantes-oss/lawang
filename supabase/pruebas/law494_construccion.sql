-- Prueba de LAW-494 (7-oct-2026): trigger de Construcción con un solo parser, techo exigido en UPDATE, volteo de tipo y
-- precio de Modelos guardado en el contrato. Se ejecuta por execute_sql y TERMINA CON UN RAISE a propósito: no deja
-- rastro. Cada caso va en su propio sub-bloque que también acaba en excepción, así que los casos no se pisan.
-- Cada línea dice `ok` o `FALLO` contra lo esperado; la última línea cuenta los fallos.
-- Para probar la migración ANTES de aplicarla: pegar su `create or replace` delante de este bloque en el MISMO
-- execute_sql (el raise final deshace también la función).
-- Casos (esperado con la versión nueva; entre corchetes lo que hacía la anterior, medido el 7-oct):
--   T1  guardado normal por contrato_guarda (congelado, con extra y descuento)  PASA     [PASA]
--   T1b re-elegir el mismo techo (corre el contraste)                         PASA     [PASA]
--   T2  contrato antiguo sin techo (CC00096)                                  PASA
--   T3  congelado con extra y descuento, UPDATE de otro campo (CC00122)       PASA
--   T4  techo "48.000" + total "48.000": guarda 48000 y techo.precio = número PASA     [RECHAZA: la base leía 48]
--   T5  techo "48.000" + total 48 (UPDATE directo)                            RECHAZA  [PASA: agujero 1]
--   T5b lo mismo por contrato_guarda                                          RECHAZA  [PASA: agujero 1]
--   T6  quitar el techo + total 1 (UPDATE directo)                            RECHAZA  [PASA: agujero 2]
--   T6b lo mismo por contrato_guarda                                          RECHAZA  [PASA: agujero 2]
--   T7  volteo contrato_general (techo 1) -> construccion, con sesión         RECHAZA  [PASA: agujero 3]
--   T7b el mismo volteo SIN sesión con total 1: cuadra contra sus cifras      PASA     (límite declarado: sin sesión
--       no se contrasta contra Modelos; no es camino de navegador)
--   T7c volteo SIN sesión con total que no cuadra                             RECHAZA
--   T8  descuento > 15 % como admin                                           RECHAZA  [RECHAZA]
--   T8b descuento > 15 % como super_admin                                     PASA     [PASA: exención del 29-sep]
--   T9  descuento 2.000 y total 46.000                                        PASA     [PASA]
-- CC00107 (LAW-267) no entra: tiene una firma en curso y lo para contrato_no_editable_en_firma antes que este trigger.
-- Datos de producción del 7-oct (CC00120 48.000 sin extras; CC00122 con extra y descuento; CC00096 sin techo).
do $t$
declare
  out text := ''; fallos int := 0; res text; esp text; extra text;
  u_ad uuid; u_sa uuid; e_ad text; e_sa text;
  c120 public.contratos%rowtype; c122 public.contratos%rowtype; c096 public.contratos%rowtype;
  d jsonb; r jsonb;
  claims_ad text; claims_sa text;
begin
  select user_id, email into u_ad, e_ad from public.usuarios where activo and rol = 'admin' and email like 'p@p%' limit 1;
  select user_id, email into u_sa, e_sa from public.usuarios where activo and rol = 'super_admin' order by email limit 1;
  claims_ad := json_build_object('sub', u_ad, 'role', 'authenticated', 'email', e_ad)::text;
  claims_sa := json_build_object('sub', u_sa, 'role', 'authenticated', 'email', e_sa)::text;
  select * into c120 from public.contratos where numero = 'CC00120';
  select * into c122 from public.contratos where numero = 'CC00122';
  select * into c096 from public.contratos where numero = 'CC00096';

  -- T1
  esp := 'PASA';
  begin
    perform set_config('request.jwt.claims', claims_ad, true);
    r := public.contrato_guarda(c122.id, jsonb_build_object('tipo', 'construccion', 'datos', c122.datos));
    raise exception '__PASO__ total=%', r->>'precio_total';
  exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' else 'RECHAZA' end; extra := left(sqlerrm, 140); end;
  out := out || 'T1  ' || case when res = esp then 'ok   ' else 'FALLO' end || ' ' || res || ' · ' || extra || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T1b
  esp := 'PASA';
  begin
    perform set_config('request.jwt.claims', claims_ad, true);
    d := jsonb_set(c122.datos, '{techo,fecha_resuelta}', to_jsonb('2026-10-07T00:00:00Z'::text));
    r := public.contrato_guarda(c122.id, jsonb_build_object('tipo', 'construccion', 'datos', d));
    raise exception '__PASO__ total=%', r->>'precio_total';
  exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' else 'RECHAZA' end; extra := left(sqlerrm, 140); end;
  out := out || 'T1b ' || case when res = esp then 'ok   ' else 'FALLO' end || ' ' || res || ' · ' || extra || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T2
  esp := 'PASA';
  begin
    perform set_config('request.jwt.claims', claims_ad, true);
    r := public.contrato_guarda(c096.id, jsonb_build_object('tipo', 'construccion', 'datos', c096.datos));
    raise exception '__PASO__';
  exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' else 'RECHAZA' end; extra := left(sqlerrm, 140); end;
  out := out || 'T2  ' || case when res = esp then 'ok   ' else 'FALLO' end || ' ' || res || ' · ' || extra || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T3
  esp := 'PASA';
  begin
    perform set_config('request.jwt.claims', claims_ad, true);
    update public.contratos set datos = jsonb_set(datos, '{fields,_prueba_law494}', '"x"') where id = c122.id;
    raise exception '__PASO__';
  exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' else 'RECHAZA' end; extra := left(sqlerrm, 140); end;
  out := out || 'T3  ' || case when res = esp then 'ok   ' else 'FALLO' end || ' ' || res || ' · ' || extra || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T4: además del PASA, lo guardado tiene que ser 48000 y techo.precio un NÚMERO 48000
  esp := 'PASA';
  begin
    perform set_config('request.jwt.claims', claims_ad, true);
    d := jsonb_set(jsonb_set(c120.datos, '{techo,precio}', to_jsonb('48.000'::text)), '{fields,precio_total}', to_jsonb('48.000'::text));
    r := public.contrato_guarda(c120.id, jsonb_build_object('tipo', 'construccion', 'datos', d));
    if (select precio_total from public.contratos where id = c120.id) <> 48000
       or (select jsonb_typeof(datos->'techo'->'precio') || ':' || (datos->'techo'->>'precio') from public.contratos where id = c120.id)
          is distinct from 'number:48000' then
      raise exception 'guardado mal: total=% techo=%', (select precio_total from public.contratos where id = c120.id),
        (select datos->'techo'->'precio' from public.contratos where id = c120.id);
    end if;
    raise exception '__PASO__ total=48000 techo.precio=48000 (número)';
  exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' else 'RECHAZA' end; extra := left(sqlerrm, 140); end;
  out := out || 'T4  ' || case when res = esp then 'ok   ' else 'FALLO' end || ' ' || res || ' · ' || extra || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T5
  esp := 'RECHAZA';
  begin
    perform set_config('request.jwt.claims', claims_ad, true);
    update public.contratos set datos = jsonb_set(datos, '{techo,precio}', to_jsonb('48.000'::text)), precio_total = 48 where id = c120.id;
    raise exception '__PASO__';
  exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' else 'RECHAZA' end; extra := left(sqlerrm, 140); end;
  out := out || 'T5  ' || case when res = esp then 'ok   ' else 'FALLO' end || ' ' || res || ' · ' || extra || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T5b
  esp := 'RECHAZA';
  begin
    perform set_config('request.jwt.claims', claims_ad, true);
    d := jsonb_set(jsonb_set(c120.datos, '{techo,precio}', to_jsonb('48.000'::text)), '{fields,precio_total}', to_jsonb('48'::text));
    r := public.contrato_guarda(c120.id, jsonb_build_object('tipo', 'construccion', 'datos', d));
    raise exception '__PASO__';
  exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' else 'RECHAZA' end; extra := left(sqlerrm, 140); end;
  out := out || 'T5b ' || case when res = esp then 'ok   ' else 'FALLO' end || ' ' || res || ' · ' || extra || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T6
  esp := 'RECHAZA';
  begin
    perform set_config('request.jwt.claims', claims_ad, true);
    update public.contratos set datos = datos - 'techo', precio_total = 1 where id = c120.id;
    raise exception '__PASO__';
  exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' else 'RECHAZA' end; extra := left(sqlerrm, 140); end;
  out := out || 'T6  ' || case when res = esp then 'ok   ' else 'FALLO' end || ' ' || res || ' · ' || extra || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T6b
  esp := 'RECHAZA';
  begin
    perform set_config('request.jwt.claims', claims_ad, true);
    d := jsonb_set(c120.datos - 'techo', '{fields,precio_total}', to_jsonb('1'::text));
    r := public.contrato_guarda(c120.id, jsonb_build_object('tipo', 'construccion', 'datos', d));
    raise exception '__PASO__';
  exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' else 'RECHAZA' end; extra := left(sqlerrm, 140); end;
  out := out || 'T6b ' || case when res = esp then 'ok   ' else 'FALLO' end || ' ' || res || ' · ' || extra || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T7: paso 1 como otro tipo con techo a 1 (el trigger no mira), paso 2 solo voltea el tipo, con sesión
  esp := 'RECHAZA';
  begin
    perform set_config('request.jwt.claims', claims_ad, true);
    begin
      update public.contratos set tipo = 'contrato_general', datos = jsonb_set(datos, '{techo,precio}', '1'::jsonb), precio_total = 1 where id = c120.id;
    exception when others then raise exception '__PASO1_FALLA__ %', left(sqlerrm, 120);
    end;
    update public.contratos set tipo = 'construccion' where id = c120.id;
    raise exception '__PASO__';
  exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' when sqlerrm like '\_\_PASO1%' then 'PREPARACION' else 'RECHAZA' end; extra := left(sqlerrm, 140); end;
  out := out || 'T7  ' || case when res = esp then 'ok   ' else 'FALLO' end || ' ' || res || ' · ' || extra || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T7b: el mismo volteo sin sesión, cuadrando contra sus propias cifras (límite declarado)
  esp := 'PASA';
  begin
    perform set_config('request.jwt.claims', '', true);
    update public.contratos set tipo = 'contrato_general', datos = jsonb_set(datos, '{techo,precio}', '1'::jsonb), precio_total = 1 where id = c120.id;
    update public.contratos set tipo = 'construccion' where id = c120.id;
    raise exception '__PASO__';
  exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' else 'RECHAZA' end; extra := left(sqlerrm, 140); end;
  out := out || 'T7b ' || case when res = esp then 'ok   ' else 'FALLO' end || ' ' || res || ' · ' || extra || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T7c: volteo sin sesión con un total que no cuadra con sus cifras
  esp := 'RECHAZA';
  begin
    perform set_config('request.jwt.claims', '', true);
    begin
      update public.contratos set tipo = 'contrato_general', precio_total = 1 where id = c120.id;
    exception when others then raise exception '__PASO1_FALLA__ %', left(sqlerrm, 120);
    end;
    update public.contratos set tipo = 'construccion' where id = c120.id;
    raise exception '__PASO__';
  exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' when sqlerrm like '\_\_PASO1%' then 'PREPARACION' else 'RECHAZA' end; extra := left(sqlerrm, 140); end;
  out := out || 'T7c ' || case when res = esp then 'ok   ' else 'FALLO' end || ' ' || res || ' · ' || extra || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T8
  esp := 'RECHAZA';
  begin
    perform set_config('request.jwt.claims', claims_ad, true);
    update public.contratos set datos = jsonb_set(datos, '{fields,descuento_comercial}', to_jsonb('9000'::text)), precio_total = 39000 where id = c120.id;
    raise exception '__PASO__';
  exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' else 'RECHAZA' end; extra := left(sqlerrm, 140); end;
  out := out || 'T8  ' || case when res = esp then 'ok   ' else 'FALLO' end || ' ' || res || ' · ' || extra || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T8b
  esp := 'PASA';
  begin
    perform set_config('request.jwt.claims', claims_sa, true);
    update public.contratos set datos = jsonb_set(datos, '{fields,descuento_comercial}', to_jsonb('9000'::text)), precio_total = 39000 where id = c120.id;
    raise exception '__PASO__';
  exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' else 'RECHAZA' end; extra := left(sqlerrm, 140); end;
  out := out || 'T8b ' || case when res = esp then 'ok   ' else 'FALLO' end || ' ' || res || ' · ' || extra || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T9
  esp := 'PASA';
  begin
    perform set_config('request.jwt.claims', claims_ad, true);
    update public.contratos set datos = jsonb_set(datos, '{fields,descuento_comercial}', to_jsonb('2000'::text)), precio_total = 46000 where id = c120.id;
    raise exception '__PASO__';
  exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' else 'RECHAZA' end; extra := left(sqlerrm, 140); end;
  out := out || 'T9  ' || case when res = esp then 'ok   ' else 'FALLO' end || ' ' || res || ' · ' || extra || E'\n'; fallos := fallos + (res <> esp)::int;

  raise exception E'RESULTADOS (fallos: %)\n%', fallos, out;
end $t$;
