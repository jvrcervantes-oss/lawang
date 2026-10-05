-- destructivo-ok: ataca a propósito el registro inmutable (update/delete/truncate sobre fichas_publicas_log, que el trigger rechaza) y todo acaba en rollback por `raise exception`.
-- PRUEBA — fichas_publicas /ficha_publica_guarda / fichas_publicas_log (The Collection v2 · F2, 2-oct-2026).
-- Cubre 20261002120000_thecollection_fichas_publicas.sql (adaptada a la firma v2 de ficha_publica_guarda, 5-oct-2026: devuelve jsonb {id,slug,version}). Se ejecuta con execute_sql (MCP) o psql como postgres, UN BLOQUE:
-- acaba en `raise exception 'RES: …'`, que revierte la transacción entera y enseña el resultado: NO ESCRIBE NADA.
-- Cada punto debe decir «ok»; «FALLO» es un agujero o una regresión. Un «debe fallar» solo vale con el SQLSTATE esperado.
-- Admin de prueba: 24257595… (rol admin, activo); cámbialo si ya no lo está. Cada execute_sql es su propia sesión: todo va en este bloque.
do $$
declare
  r text := '';
  ADM text := '{"sub":"24257595-aee2-4daa-8170-d268f46b9981","email":"admin-prueba@x.test","role":"authenticated"}';
  NOADM text := '{"sub":"00000000-0000-4000-8000-000000000001","email":"nadie@x.test","role":"authenticated"}';
  n0 int; n1 int; v_quien text; v_id uuid;
begin
  -- (a) no-admin: 42501
  perform set_config('request.jwt.claims', NOADM, true); set local role authenticated;
  begin perform public.ficha_publica_guarda('zz-prueba', '{"linea":"villa","region_key":"bali"}'::jsonb); r := r || 'a FALLO no-admin escribe; ';
  exception when others then r := r || case when sqlstate = '42501' then 'a ok; ' else 'a FALLO otro error (' || sqlstate || ' ' || sqlerrm || '); ' end; end;

  -- (b) admin real
  reset role; perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  begin perform public.ficha_publica_guarda('zz-prueba', '{"linea":"villa","region_key":"bali","foo":1}'::jsonb); r := r || 'b1 FALLO clave fuera de lista; ';
  exception when others then r := r || case when sqlstate = '22023' then 'b1 ok; ' else 'b1 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-prueba', '{"slug":"otro","linea":"villa","region_key":"bali"}'::jsonb); r := r || 'b1b FALLO slug en cambios; ';
  exception when others then r := r || case when sqlstate = '22023' then 'b1b ok; ' else 'b1b FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('Zz_Prueba!', '{"linea":"villa","region_key":"bali"}'::jsonb); r := r || 'b2 FALLO slug invalido; ';
  exception when others then r := r || case when sqlstate = '22023' then 'b2 ok; ' else 'b2 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-prueba', '{"linea":"villa"}'::jsonb); r := r || 'b3 FALLO alta sin region_key; ';
  exception when others then r := r || case when sqlstate = '22023' then 'b3 ok; ' else 'b3 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-prueba', '{"region_key":"bali"}'::jsonb); r := r || 'b3b FALLO alta sin linea; ';
  exception when others then r := r || case when sqlstate = '22023' then 'b3b ok; ' else 'b3b FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;

  -- alta válida (nace cerrada) y su fila de log
  reset role; select count(*) into n0 from public.fichas_publicas_log;
  perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  v_id := (public.ficha_publica_guarda('zz-prueba', '{"linea":"villa","region_key":"bali"}'::jsonb)->>'id')::uuid;
  reset role; select count(*) into n1 from public.fichas_publicas_log;
  r := r || case when v_id is not null and n1 = n0 + 1 then 'alta ok; ' else 'alta FALLO (log ' || n0 || '->' || n1 || '); ' end;

  perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  begin perform public.ficha_publica_guarda('zz-prueba', '{"publicada_web":true}'::jsonb); r := r || 'b4 FALLO publica sin textos.title.en; ';
  exception when others then r := r || case when sqlstate = '23514' then 'b4 ok; ' else 'b4 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  -- b5a (v1: «desde» sin importe no se publicaba) se RETIRÓ en F3a: ahora 'desde' no lleva importe (lo deriva coleccion_publica()); sin proyecto sigue sin publicarse (23514).
  begin perform public.ficha_publica_guarda('zz-prueba', '{"publicada_web":true,"precio_modo":"desde","textos":{"title":{"en":"X","es":"Y"}}}'::jsonb); r := r || 'b5a FALLO publica sin proyecto; ';
  exception when others then r := r || case when sqlstate = '23514' then 'b5a ok; ' else 'b5a FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-prueba', '{"linea":"signature","precio_modo":"fijo","publicada_web":true,"textos":{"title":{"en":"X"}}}'::jsonb); r := r || 'b5 FALLO publica fijo sin precio_eur; ';
  exception when others then r := r || case when sqlstate = '23514' then 'b5 ok; ' else 'b5 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-prueba', '{"precio_modo":"fijo","precio_eur":100000}'::jsonb); r := r || 'b6 FALLO fijo con linea villa; ';
  exception when others then r := r || case when sqlstate = '23514' then 'b6 ok; ' else 'b6 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;

  -- no-op: misma llamada otra vez = 0 filas nuevas en el log
  reset role; select count(*) into n0 from public.fichas_publicas_log;
  perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  perform public.ficha_publica_guarda('zz-prueba', '{"linea":"villa","region_key":"bali"}'::jsonb);
  reset role; select count(*) into n1 from public.fichas_publicas_log;
  r := r || case when n1 = n0 then 'c1 no-op ok; ' else 'c1 FALLO no-op deja ' || (n1 - n0) || ' filas; ' end;

  -- cambio real: 1 fila, con quien no vacío
  perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  perform public.ficha_publica_guarda('zz-prueba', '{"orden":5}'::jsonb);
  reset role; select count(*) into n1 from public.fichas_publicas_log;
  select quien into v_quien from public.fichas_publicas_log order by id desc limit 1;
  r := r || case when n1 = n0 + 1 and coalesce(v_quien, '') <> '' then 'c2 cambio ok (quien=' || v_quien || '); ' else 'c2 FALLO (log ' || n0 || '->' || n1 || ', quien=' || coalesce(v_quien, 'null') || '); ' end;

  -- log inmutable: update / delete / truncate → 42501 (como dueño: lo para el trigger)
  begin update public.fichas_publicas_log set slug = 'x'; r := r || 'd1 FALLO update; ';
  exception when others then r := r || case when sqlstate = '42501' then 'd1 ok; ' else 'd1 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin delete from public.fichas_publicas_log; r := r || 'd2 FALLO delete; ';
  exception when others then r := r || case when sqlstate = '42501' then 'd2 ok; ' else 'd2 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin truncate public.fichas_publicas_log; r := r || 'd3 FALLO truncate; ';
  exception when others then r := r || case when sqlstate = '42501' then 'd3 ok; ' else 'd3 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;

  raise exception 'RES: %', r;
end $$;
