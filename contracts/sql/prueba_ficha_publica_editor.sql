-- destructivo-ok: la prueba ataca a propósito las RPC de escritura (insert/update de fichas de prueba zz-ed*) y todo acaba en rollback por `raise exception 'RES: …'`; no escribe nada.
-- PRUEBA — ficha_publica_guarda v2 / ficha_publica_lee / _ficha_valida (The Collection v2 · F3a, 5-oct-2026).
-- Cubre 20261005120000_thecollection_ficha_publica_editor.sql: SE EJECUTA DESPUÉS de aplicar esa migración. Con execute_sql (MCP) o psql
-- como postgres, UN BLOQUE: acaba en `raise exception 'RES: …'`, que revierte la transacción entera y enseña el resultado.
-- Cada punto debe decir «ok»; «FALLO» es un agujero o una regresión. Un «debe fallar» solo vale con el SQLSTATE esperado.
-- Admin de prueba: 24257595… (rol admin, activo); no-admin: un usuario inventado sin fila en `usuarios`. Cada execute_sql es su propia sesión.
-- F3a-bis (5-oct-2026): se ejecuta tras 20261005130000_thecollection_ficha_guarda_exige_version.sql. Sobre una ficha EXISTENTE guarda exige la versión (aquí v_ver/v_ver2/v_ver3,
-- capturadas del retorno del alta): sin ella devolvería 22023 y los «debe fallar» fallarían por esa causa y no por la que prueban.
-- Nota: dentro de una transacción now() no avanza, así que «versión obsoleta» se prueba con una fecha antigua, no con dos guardados.
do $$
declare
  r text := '';
  ADM   text := '{"sub":"24257595-aee2-4daa-8170-d268f46b9981","email":"admin-prueba@x.test","role":"authenticated"}';
  NOADM text := '{"sub":"00000000-0000-4000-8000-000000000001","email":"nadie@x.test","role":"authenticated"}';
  v_rf2 uuid; v_u_rf2 uuid; v_u_otra uuid; v_m_otro uuid;
  j jsonb; v_ver timestamptz; v_ver2 timestamptz; v_ver3 timestamptz; v_otro uuid; v_snap jsonb; v_quien text; v_p text; n int; t text;
begin
  -- fixtures (como postgres)
  select id into v_rf2 from public.proyectos where slug = 'riverfront-ii';
  select id into v_otro from public.proyectos where id <> v_rf2 limit 1;
  select u.id into v_u_rf2 from public.unidades u where u.proyecto_id = v_rf2 limit 1;
  select u.id into v_u_otra from public.unidades u where u.proyecto_id is not null and u.proyecto_id <> v_rf2 limit 1;
  select mv.modelo_id into v_m_otro from public.modelos_villa mv
   where mv.modelo_id is not null and mv.modelo_id not in (select modelo_id from public.modelos_villa where proyecto_id = v_rf2 and modelo_id is not null) limit 1;
  if v_rf2 is null or v_u_rf2 is null or v_u_otra is null or v_m_otro is null or v_otro is null then
    raise exception 'RES: faltan fixtures (rf2=%, u_rf2=%, u_otra=%, m_otro=%, otro=%)', v_rf2, v_u_rf2, v_u_otra, v_m_otro, v_otro;
  end if;

  -- (a) permisos: no-admin 42501 en guarda y lee; anon sin execute en ambas; _ficha_valida sin grants
  perform set_config('request.jwt.claims', NOADM, true); set local role authenticated;
  begin perform public.ficha_publica_guarda('zz-ed', '{"linea":"villa","region_key":"bali"}'::jsonb); r := r || 'a1 FALLO no-admin escribe; ';
  exception when others then r := r || case when sqlstate = '42501' then 'a1 ok; ' else 'a1 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_lee(v_rf2); r := r || 'a2 FALLO no-admin lee; ';
  exception when others then r := r || case when sqlstate = '42501' then 'a2 ok; ' else 'a2 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  reset role; set local role anon;
  begin perform public.ficha_publica_guarda('zz-ed', '{"linea":"villa","region_key":"bali"}'::jsonb); r := r || 'a3 FALLO anon escribe; ';
  exception when others then r := r || case when sqlstate = '42501' then 'a3 ok; ' else 'a3 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_lee(v_rf2); r := r || 'a4 FALLO anon lee; ';
  exception when others then r := r || case when sqlstate = '42501' then 'a4 ok; ' else 'a4 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  reset role;
  r := r || case when not has_function_privilege('anon', 'public.ficha_publica_guarda(text,jsonb,timestamptz)', 'execute')
                  and not has_function_privilege('anon', 'public.ficha_publica_lee(uuid)', 'execute')
                  and has_function_privilege('authenticated', 'public.ficha_publica_guarda(text,jsonb,timestamptz)', 'execute')
                  and has_function_privilege('authenticated', 'public.ficha_publica_lee(uuid)', 'execute')
                  and not has_function_privilege('service_role', 'public.ficha_publica_guarda(text,jsonb,timestamptz)', 'execute')
                  and not has_function_privilege('service_role', 'public.ficha_publica_lee(uuid)', 'execute')
                  and not has_function_privilege('authenticated', 'public._ficha_valida(jsonb,jsonb)', 'execute')
                  and not has_function_privilege('authenticated', 'public._ficha_error(jsonb,jsonb)', 'execute')
                  and not exists (select 1 from pg_proc where proname = 'ficha_publica_guarda' and pronargs = 2)
                  and not exists (select 1 from pg_proc where proname = 'ficha_publica_lista')
             then 'a5 grants ok; ' else 'a5 FALLO grants/firmas; ' end;

  -- (l) lee, ANTES de crear fichas de prueba: las dos de riverfront-ii, y `publico` null para la oculta
  perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  j := public.ficha_publica_lee(v_rf2);
  reset role;
  select count(*) into n from jsonb_array_elements(j->'fichas') f where f->>'slug' in ('riverfront-ii-big', 'riverfront-ii-small');
  r := r || case when n = 2 and jsonb_array_length(j->'fichas') = 2 then 'l1 dos fichas ok; ' else 'l1 FALLO (' || n || ' de ' || jsonb_array_length(j->'fichas') || '); ' end;
  r := r || case when (select f->'publico' from jsonb_array_elements(j->'fichas') f where f->>'slug' = 'riverfront-ii-big') = 'null'::jsonb
                  or (select f->'publico' from jsonb_array_elements(j->'fichas') f where f->>'slug' = 'riverfront-ii-big') is null
                  then 'l2 oculta publico null ok; ' else 'l2 FALLO oculta con publico; ' end;
  r := r || case when (select f#>>'{publico,id}' from jsonb_array_elements(j->'fichas') f where f->>'slug' = 'riverfront-ii-small') = 'riverfront-ii-small'
                  then 'l3 publicada con publico ok; ' else 'l3 FALLO publicada sin publico; ' end;
  r := r || case when jsonb_typeof(j->'unidades') = 'array' and jsonb_typeof(j->'modelos') = 'array' and j#>>'{proyecto,slug}' = 'riverfront-ii'
                  and (select (f->>'version') ~ '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$' from jsonb_array_elements(j->'fichas') f limit 1)
                  then 'l4 forma ok; ' else 'l4 FALLO forma; ' end;
  perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  begin perform public.ficha_publica_lee('00000000-0000-4000-8000-0000000000ff'::uuid); r := r || 'l5 FALLO proyecto inexistente; ';
  exception when others then r := r || case when sqlstate = 'P0002' then 'l5 ok; ' else 'l5 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;

  -- (b) alta y mezcla por clave
  j := public.ficha_publica_guarda('zz-ed', jsonb_build_object('linea', 'villa', 'region_key', 'bali', 'proyecto_id', v_rf2));
  reset role;
  v_ver := (j->>'version')::timestamptz;
  select quien into v_quien from public.fichas_publicas_log where slug = 'zz-ed' order by id desc limit 1;
  select actualizado_por into v_p from public.fichas_publicas where slug = 'zz-ed';
  r := r || case when j ? 'id' and j->>'slug' = 'zz-ed' and v_ver is not null then 'b1 alta devuelve {id,slug,version} ok; ' else 'b1 FALLO retorno; ' end;
  r := r || case when v_quien = 'admin-prueba@x.test' and v_p = 'admin-prueba@x.test' then 'b2 quien real ok; ' else 'b2 FALLO quien=' || coalesce(v_quien, 'null') || ' por=' || coalesce(v_p, 'null') || '; ' end;
  r := r || case when (select publicada_web from public.fichas_publicas where slug = 'zz-ed') = false then 'b3 nace cerrada ok; ' else 'b3 FALLO nace abierta; ' end;

  perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  perform public.ficha_publica_guarda('zz-ed', '{"ficha":{"imagenes":["/a.png","/b.png"],"downloads":[{"name":"d","url":"/d.pdf"}],"diseno":{"landColor":"#fff","tabs":[]}},"textos":{"title":{"en":"EN","es":"ES"},"desc":{"en":"d"}}}'::jsonb, v_ver);
  perform public.ficha_publica_guarda('zz-ed', '{"ficha":{"equipamiento":{"pool":true,"poolType":"infinity"}}}'::jsonb, v_ver);
  reset role;
  r := r || case when (select jsonb_array_length(ficha->'imagenes') = 2 and ficha->'downloads' is not null and ficha#>>'{diseno,landColor}' = '#fff'
                              and ficha#>>'{equipamiento,poolType}' = 'infinity' from public.fichas_publicas where slug = 'zz-ed')
                 then 'b4 guardar solo equipamiento CONSERVA imagenes/downloads/diseno ok; ' else 'b4 FALLO la mezcla pisa claves; ' end;

  perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  perform public.ficha_publica_guarda('zz-ed', '{"textos":{"title":{"es":"ES2"}}}'::jsonb, v_ver);
  reset role;
  select textos->'title' ->> 'en' || '|' || (textos->'title' ->> 'es') || '|' || (textos->'desc' ->> 'en') into t from public.fichas_publicas where slug = 'zz-ed';
  r := r || case when t = 'EN|ES2|d' then 'b5 editar title.es no borra en ni desc ok; ' else 'b5 FALLO textos (' || coalesce(t, 'null') || '); ' end;

  perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  perform public.ficha_publica_guarda('zz-ed', '{"textos":{"title":{"es":null}},"ficha":{"equipamiento":null}}'::jsonb, v_ver);
  reset role;
  r := r || case when (select textos->'title' ? 'en' and not (textos->'title' ? 'es') and not (ficha ? 'equipamiento') and ficha ? 'imagenes'
                         from public.fichas_publicas where slug = 'zz-ed')
                 then 'b6 null borra la clave (idioma y clave de ficha) ok; ' else 'b6 FALLO null no borra; ' end;

  -- (c) concurrencia
  perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  begin perform public.ficha_publica_guarda('zz-ed', '{"orden":3}'::jsonb, '2000-01-01T00:00:00Z'::timestamptz); r := r || 'c1 FALLO version obsoleta pasa; ';
  exception when others then r := r || case when sqlstate = '40001' then 'c1 ok; ' else 'c1 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', '{"orden":3}'::jsonb, v_ver); r := r || 'c2 version vigente ok; ';
  exception when others then r := r || 'c2 FALLO version vigente rechazada (' || sqlstate || ' ' || sqlerrm || '); '; end;
  begin perform public.ficha_publica_guarda('zz-nope', '{"linea":"villa","region_key":"bali"}'::jsonb, now()); r := r || 'c3 FALLO version sobre ficha inexistente; ';
  exception when others then r := r || case when sqlstate = '40001' then 'c3 ok; ' else 'c3 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;

  -- (d) validación de forma: debe fallar con 22023
  begin perform public.ficha_publica_guarda('zz-ed', '{"ficha":{"equipamiento":{"pool":"si"}}}'::jsonb, v_ver); r := r || 'd1 FALLO tipo equivocado; ';
  exception when others then r := r || case when sqlstate = '22023' then 'd1 ok; ' else 'd1 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', '{"ficha":{"clave_extra":1}}'::jsonb, v_ver); r := r || 'd2 FALLO clave extra en ficha; ';
  exception when others then r := r || case when sqlstate = '22023' then 'd2 ok; ' else 'd2 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', '{"textos":{"otro":{"en":"x"}}}'::jsonb, v_ver); r := r || 'd3 FALLO clave extra en textos; ';
  exception when others then r := r || case when sqlstate = '22023' then 'd3 ok; ' else 'd3 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', jsonb_build_object('ficha', jsonb_build_object('imagenes', (select jsonb_agg('/a.png'::text) from generate_series(1, 10000)))), v_ver);
    r := r || 'd4 FALLO array de 10.000; ';
  exception when others then r := r || case when sqlstate = '22023' then 'd4 ok; ' else 'd4 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', '{"textos":{"title":{"en":"a<b"}}}'::jsonb, v_ver); r := r || 'd5 FALLO < aceptado; ';
  exception when others then r := r || case when sqlstate = '22023' then 'd5 ok; ' else 'd5 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', '{"region":"Bali <b>x</b>"}'::jsonb, v_ver); r := r || 'd5b FALLO < en region aceptado; ';
  exception when others then r := r || case when sqlstate = '22023' then 'd5b ok; ' else 'd5b FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', '{"ficha":{"diseno":{"landColor":"red;background:url(x)"}}}'::jsonb, v_ver); r := r || 'd5c FALLO landColor con CSS aceptado; ';
  exception when others then r := r || case when sqlstate = '22023' then 'd5c ok; ' else 'd5c FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', '{"ficha":{"imagenes":["javascript:alert(1)"]}}'::jsonb, v_ver); r := r || 'd6 FALLO url javascript:; ';
  exception when others then r := r || case when sqlstate = '22023' then 'd6 ok; ' else 'd6 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', ('{"textos":{"title":{"en":"' || repeat('x', 121) || '"}}}')::jsonb, v_ver); r := r || 'd7 FALLO titulo de 121; ';
  exception when others then r := r || case when sqlstate = '22023' then 'd7 ok; ' else 'd7 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', '{"textos":"hola"}'::jsonb, v_ver); r := r || 'd8 FALLO textos no objeto; ';
  exception when others then r := r || case when sqlstate = '22023' then 'd8 ok; ' else 'd8 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', '{"orden":"abc"}'::jsonb, v_ver); r := r || 'd9 FALLO orden no numerico; ';
  exception when others then r := r || case when sqlstate = '22023' then 'd9 ok; ' else 'd9 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', '{"dormitorios":99}'::jsonb, v_ver); r := r || 'd10 FALLO dormitorios fuera de rango; ';
  exception when others then r := r || case when sqlstate = '23514' then 'd10 ok (23514 legible: ' || left(sqlerrm, 40) || '); ' else 'd10 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;

  begin perform public.ficha_publica_guarda('zz-ed-pub', jsonb_build_object('linea', 'villa', 'region_key', 'bali', 'proyecto_id', v_rf2, 'publicada_web', true,
                                              'textos', jsonb_build_object('title', jsonb_build_object('en', 'A', 'es', 'B'))));
    r := r || 'd11 FALLO alta ya publicada; ';
  exception when others then r := r || case when sqlstate = '22023' then 'd11 ok; ' else 'd11 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', '{"publicada_web":null}'::jsonb, v_ver); r := r || 'd12 FALLO null en columna obligatoria; ';
  exception when others then r := r || case when sqlstate = '22023' then 'd12 ok; ' else 'd12 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;

  -- (e) vínculos
  begin perform public.ficha_publica_guarda('zz-ed', jsonb_build_object('unidad_id', v_u_otra), v_ver); r := r || 'e1 FALLO unidad de otro proyecto; ';
  exception when others then r := r || case when sqlstate = '22023' then 'e1 ok; ' else 'e1 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', jsonb_build_object('modelo_id', v_m_otro), v_ver); r := r || 'e2 FALLO modelo de otro proyecto; ';
  exception when others then r := r || case when sqlstate = '22023' then 'e2 ok; ' else 'e2 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', jsonb_build_object('unidad_id', v_u_rf2), v_ver); r := r || 'e3 unidad propia ok; ';
  exception when others then r := r || 'e3 FALLO unidad propia rechazada (' || sqlstate || ' ' || sqlerrm || '); '; end;
  v_ver3 := (public.ficha_publica_guarda('zz-ed3', jsonb_build_object('linea', 'villa', 'region_key', 'bali', 'proyecto_id', v_rf2))->>'version')::timestamptz;
  begin perform public.ficha_publica_guarda('zz-ed3', jsonb_build_object('unidad_id', v_u_rf2), v_ver3); r := r || 'e4 FALLO misma unidad en dos fichas; ';
  exception when others then r := r || case when sqlstate = '22023' then 'e4 ok; ' else 'e4 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;

  -- (f) publicar / despublicar
  v_ver2 := (public.ficha_publica_guarda('zz-ed2', '{"linea":"villa","region_key":"bali"}'::jsonb)->>'version')::timestamptz;   -- sin proyecto
  begin perform public.ficha_publica_guarda('zz-ed2', '{"publicada_web":true,"textos":{"title":{"en":"A","es":"B"}}}'::jsonb, v_ver2); r := r || 'f1 FALLO publica sin proyecto; ';
  exception when others then r := r || case when sqlstate = '23514' then 'f1 ok (' || left(sqlerrm, 50) || '); ' else 'f1 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed3', '{"publicada_web":true,"textos":{"title":{"en":"A"}}}'::jsonb, v_ver3); r := r || 'f2 FALLO publica sin titulo ES; ';
  exception when others then r := r || case when sqlstate = '23514' then 'f2 ok; ' else 'f2 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed3', '{"linea":"signature","precio_modo":"fijo","precio_eur":0,"publicada_web":true,"textos":{"title":{"en":"A","es":"B"}}}'::jsonb, v_ver3); r := r || 'f3 FALLO publica fijo con importe 0; ';
  exception when others then r := r || case when sqlstate = '23514' then 'f3 ok; ' else 'f3 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed3', '{"precio_modo":"fijo","precio_eur":100000}'::jsonb, v_ver3); r := r || 'f4 FALLO fijo en villa; ';
  exception when others then r := r || case when sqlstate = '23514' then 'f4 ok; ' else 'f4 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed3', '{"publicada_web":true,"precio_modo":"desde","precio_eur":50000,"textos":{"title":{"en":"A","es":"B"}}}'::jsonb, v_ver3); r := r || 'f5 publica con desde ok; ';
  exception when others then r := r || 'f5 FALLO publicar con desde (' || sqlstate || ' ' || sqlerrm || '); '; end;
  reset role;
  r := r || case when (select precio_eur is null and publicada_web from public.fichas_publicas where slug = 'zz-ed3') then 'f6 desde deja precio_eur NULL ok; ' else 'f6 FALLO precio_eur conservado con desde; ' end;
  -- simula el ON DELETE SET NULL del proyecto y despublica
  update public.fichas_publicas set proyecto_id = null, unidad_id = null where slug = 'zz-ed3';
  select actualizado_en into v_ver3 from public.fichas_publicas where slug = 'zz-ed3';   -- el sello pudo avanzar la version
  perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  begin perform public.ficha_publica_guarda('zz-ed3', '{"publicada_web":false}'::jsonb, v_ver3); r := r || 'f7 despublicar sin proyecto ok; ';
  exception when others then r := r || 'f7 FALLO despublicar rechazado (' || sqlstate || ' ' || sqlerrm || '); '; end;
  begin perform public.ficha_publica_guarda('zz-ed3', '{"publicada_web":true}'::jsonb, v_ver3); r := r || 'f8 FALLO republica sin proyecto; ';
  exception when others then r := r || case when sqlstate = '23514' then 'f8 ok; ' else 'f8 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;

  -- (g) datos y CHECK tras la migración
  reset role;
  r := r || case when (select precio_eur is null from public.fichas_publicas where slug = 'palm-field-bali') then 'g1 palm-field-bali sin precio_eur ok; ' else 'g1 FALLO palm-field-bali con precio_eur; ' end;
  r := r || case when exists (select 1 from pg_indexes where indexname = 'fichas_publicas_unidad_uq' and indexdef ilike '%unique%where%unidad_id is not null%')
                  and not exists (select 1 from pg_indexes where indexname = 'fichas_publicas_unidad_idx')
                 then 'g2 indice unico parcial ok; ' else 'g2 FALLO indice; ' end;
  begin
    insert into public.fichas_publicas (slug, linea, region_key, publicada_web, precio_modo, precio_eur, textos, proyecto_id)
    values ('zz-ed-chk', 'villa', 'bali', true, 'desde', null, '{"title":{"en":"A"}}', v_rf2);
    r := r || 'g3 CHECK acepta desde sin importe ok; ';
  exception when others then r := r || 'g3 FALLO CHECK (' || sqlstate || ' ' || sqlerrm || '); '; end;
  begin
    insert into public.fichas_publicas (slug, linea, region_key, publicada_web, precio_modo, precio_eur, textos, proyecto_id)
    values ('zz-ed-chk2', 'signature', 'bali', true, 'fijo', null, '{"title":{"en":"A"}}', v_rf2);
    r := r || 'g4 FALLO CHECK deja fijo sin importe; ';
  exception when others then r := r || case when sqlstate = '23514' then 'g4 ok; ' else 'g4 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;

  -- (n) la versión es OBLIGATORIA si la ficha ya existe (F3a-bis, 5-oct-2026): sin ella no hay control de concurrencia y un «alta» reasignaría fichas ajenas
  reset role; select to_jsonb(f) into v_snap from public.fichas_publicas f where slug = 'zz-ed';
  perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  begin perform public.ficha_publica_guarda('zz-ed', '{"orden":7}'::jsonb);
    r := r || 'n1 FALLO existente sin version pasa; ';
  exception when others then r := r || case when sqlstate = '22023' and sqlerrm like 'Ya existe una ficha con esa dirección%' then 'n1 ok; ' else 'n1 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  reset role;
  r := r || case when (select to_jsonb(f) from public.fichas_publicas f where slug = 'zz-ed') = v_snap then 'n1b la fila no cambia ok; ' else 'n1b FALLO la fila cambió; ' end;
  -- n2: un «alta» con proyecto_id sobre un slug AJENO y PUBLICADO no lo reasigna ni toca nada
  select to_jsonb(f) into v_snap from public.fichas_publicas f where slug = 'riverfront-ii-small';
  perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  begin perform public.ficha_publica_guarda('riverfront-ii-small', jsonb_build_object('linea', 'villa', 'region_key', 'bali', 'proyecto_id', v_otro));
    r := r || 'n2 FALLO el alta reasigna la ficha ajena; ';
  exception when others then r := r || case when sqlstate = '22023' and sqlerrm like 'Ya existe una ficha con esa dirección%' then 'n2 ok; ' else 'n2 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  reset role;
  r := r || case when (select to_jsonb(f) from public.fichas_publicas f where slug = 'riverfront-ii-small') = v_snap
                  and (select proyecto_id from public.fichas_publicas where slug = 'riverfront-ii-small') = v_rf2
                 then 'n2b ajena intacta (proyecto y version) ok; ' else 'n2b FALLO ficha ajena cambiada; ' end;
  -- n3: los textos de 40001 de los que depende la sonda de la pantalla siguen siendo los mismos
  perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  begin perform public.ficha_publica_guarda('zz-nope', '{"linea":"villa","region_key":"bali"}'::jsonb, now());
    r := r || 'n3 FALLO; ';
  exception when others then r := r || case when sqlstate = '40001' and sqlerrm like 'Esa ficha ya no existe%' then 'n3 inexistente+version texto ok; ' else 'n3 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  begin perform public.ficha_publica_guarda('zz-ed', '{"orden":8}'::jsonb, '2000-01-01T00:00:00Z'::timestamptz);
    r := r || 'n4 FALLO; ';
  exception when others then r := r || case when sqlstate = '40001' and sqlerrm like 'Otra persona cambió esta ficha%' then 'n4 version distinta texto ok; ' else 'n4 FALLO (' || sqlstate || ' ' || sqlerrm || '); ' end; end;
  reset role;

  raise exception 'RES: %', r;
end $$;
