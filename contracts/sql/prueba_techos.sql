-- Prueba de los techos (30-sep-2026): fórmula de precio 2026/2027, alta, alcance, retirar, invariantes y el candado
-- del trigger de Construcción. Se pega en mcp__supabase-lawang__execute_sql (o el SQL Editor). NO deja rastro: todo
-- corre en un bloque que termina en raise y se deshace. Los triggers diferidos se fuerzan con `set constraints`.
-- Lleva `-- destructivo-ok:` en la 1ª línea al pegarlo: prueba un delete de modelos_villa dentro del ensayo.
-- Resultado: la excepción final lista cada caso con «ok» o «FALLO». Cualquier «FALLO» = no se publica.
-- Supuestos de datos (30-sep): Dali base 48.000 · Sirap 48/52k · Bamboo 50/56k; Sumba Hills con Dali a 52.000,
-- Palm Field W5 con Dali a 48.000; CC00118 = Construcción Dali Sirap con extra. Si cambian, se ajustan aquí.
do $pr$
declare
  r text := ''; v jsonb; t uuid; n int; ok boolean;
  dali uuid := (select id from public.modelos where nombre = 'Dali');
  clan uuid := (select id from public.modelos where nombre = 'Clan');
  sumba uuid := (select id from public.proyectos where nombre = 'Sumba Hills');
  palm uuid := (select id from public.proyectos where nombre = 'Palm Field W5');
  horizon uuid := (select id from public.proyectos where nombre = 'Horizon S1');
  sirap uuid := (select id from public.modelo_techos where modelo_id = (select id from public.modelos where nombre = 'Dali') and clave = 'sirap');
  bambu uuid := (select id from public.modelo_techos where modelo_id = (select id from public.modelos where nombre = 'Dali') and clave = 'bambu');
  adm text := (select user_id::text from public.usuarios where rol = 'admin' and activo limit 1);
  ag text := (select user_id::text from public.usuarios where rol = 'agente' and activo limit 1);
  base jsonb; cols text; sqlq text;
begin
  set constraints all immediate;
  -- fórmula 2026
  select jsonb_object_agg(o.clave, o.precio) into v from public._modelo_techos_opciones(dali, sumba) o;
  r := r || case when v = '{"sirap":52000,"bambu":54000}'::jsonb then 'ok' else 'FALLO' end || ' 2026 dali@sumba ' || v || E'\n';
  select jsonb_object_agg(o.clave, o.precio) into v from public._modelo_techos_opciones(dali, palm) o;
  r := r || case when v = '{"sirap":48000,"bambu":50000}'::jsonb then 'ok' else 'FALLO' end || ' 2026 dali@palm ' || v || E'\n';
  -- fórmula 2027 (sin doble subida, owner 30-sep)
  execute $f$create or replace function public.catalogo_tramo_activo() returns text language sql stable set search_path = '' as $b$ select '2027'::text $b$$f$;
  select jsonb_object_agg(o.clave, o.precio) into v from public._modelo_techos_opciones(dali, sumba) o;
  r := r || case when v = '{"sirap":52000,"bambu":56000}'::jsonb then 'ok' else 'FALLO' end || ' 2027 dali@sumba ' || v || E'\n';
  execute $f$create or replace function public.catalogo_tramo_activo() returns text language sql stable set search_path = '' as $b$ select case when (now() at time zone 'Asia/Makassar') < timestamp '2027-01-01 00:00:00' then '2026' else '2027' end $b$$f$;

  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  -- alta limitada a Sumba Hills
  t := public.modelo_techo_crea(dali, jsonb_build_object('nombre','Prueba Alang','precio_ahora',49000,'precio_2027',53000,'alcance','lista','proyectos',jsonb_build_array(sumba)));
  select count(*) into n from public._modelo_techos_opciones(dali, sumba) o where o.techo_id = t and o.precio = 53000;
  r := r || case when n = 1 then 'ok' else 'FALLO' end || ' alta ofrecida en Sumba a 53.000' || E'\n';
  select count(*) into n from public._modelo_techos_opciones(dali, palm) o where o.techo_id = t;
  r := r || case when n = 0 then 'ok' else 'FALLO' end || ' alta NO ofrecida en Palm Field' || E'\n';
  v := public.catalogo_publico()->'dali'->'techos'->'prueba_alang'->'proyectos';
  r := r || case when v = '["sumbahills"]'::jsonb then 'ok' else 'FALLO' end || ' catálogo público con slug ' || coalesce(v::text, 'null') || E'\n';
  -- reglas del alta
  begin perform public.modelo_techo_crea(dali, '{"nombre":"Barato","precio_ahora":40000,"precio_2027":45000}'); r := r || 'FALLO alta bajo la base pasó' || E'\n';
  exception when others then r := r || 'ok alta bajo la base: ' || sqlerrm || E'\n'; end;
  begin perform public.modelo_techo_crea(clan, '{"nombre":"X","precio_ahora":90000,"precio_2027":95000}'); r := r || 'FALLO alta sin base pasó' || E'\n';
  exception when others then r := r || 'ok alta sin base: ' || sqlerrm || E'\n'; end;
  begin perform public.modelo_techo_crea(dali, jsonb_build_object('nombre','Y','precio_ahora',60000,'precio_2027',61000,'alcance','lista','proyectos',jsonb_build_array(horizon))); r := r || 'FALLO proyecto sin la casa pasó' || E'\n';
  exception when others then r := r || 'ok proyecto sin la casa: ' || sqlerrm || E'\n'; end;
  -- lote: retirar sirap sin confirmar -> LW409 y NADA guardado
  begin perform public.modelo_techos_guarda_lote(dali, jsonb_build_array(jsonb_build_object('id', bambu, 'precio_ahora', 51000)), jsonb_build_array(jsonb_build_object('id', sirap, 'cambios', '{"activo":false}'::jsonb)), false);
    r := r || 'FALLO lote sin confirmar pasó' || E'\n';
  exception when others then r := r || case when sqlstate = 'LW409' then 'ok' else 'FALLO' end || ' lote sin confirmar: ' || sqlstate || E'\n'; end;
  select (activo and (select precio_ahora from public.modelo_techos where id = bambu) = 50000) into ok from public.modelo_techos where id = sirap;
  r := r || case when ok then 'ok' else 'FALLO' end || ' lote cancelado no dejó nada a medias' || E'\n';
  -- invariante: dejar Palm Field sin techo
  begin perform public.modelo_techos_guarda_lote(dali, '[]', jsonb_build_array(
      jsonb_build_object('id', sirap, 'cambios', jsonb_build_object('alcance','lista','proyectos',jsonb_build_array(sumba))),
      jsonb_build_object('id', bambu, 'cambios', jsonb_build_object('alcance','lista','proyectos',jsonb_build_array(sumba)))), true);
    r := r || 'FALLO proyecto sin techo pasó' || E'\n';
  exception when others then r := r || 'ok proyecto sin techo: ' || sqlerrm || E'\n'; end;
  -- invariante: subir la base sin mover techos
  begin perform public.modelo_precios_guarda(dali, '{"base":49500,"desplaza_techos":false}'); r := r || 'FALLO base sobre techos pasó' || E'\n';
  exception when others then r := r || 'ok base sobre techos: ' || sqlerrm || E'\n'; end;

  -- trigger de Construcción (alta que copia CC00118 sin descuento)
  select string_agg(quote_ident(column_name), ',') into cols from information_schema.columns
   where table_schema = 'public' and table_name = 'contratos' and is_generated = 'NEVER' and column_name not in ('id','numero','created_at','updated_at','bloqueado');
  select to_jsonb(c) into base from public.contratos c where numero = 'CC00118';
  base := jsonb_set(jsonb_set(base, '{datos,fields,descuento_comercial}', '""'), '{precio_total}', '53000');
  base := jsonb_set(base, '{datos}', (base->'datos') - 'annexes');
  sqlq := format('insert into public.contratos (%s, numero, bloqueado) select %s, $2, false from jsonb_populate_record(null::public.contratos, $1)', cols, cols);
  begin execute sqlq using base, 'ZZPRUEBA1'; r := r || 'ok contrato limpio entra' || E'\n';
  exception when others then r := r || 'FALLO contrato limpio: ' || sqlerrm || E'\n'; end;
  begin execute sqlq using jsonb_set(jsonb_set(base, '{datos,techo,precio}', '40000'), '{precio_total}', '45000'), 'ZZPRUEBA2'; r := r || 'FALLO techo manipulado pasó' || E'\n';
  exception when others then r := r || 'ok techo manipulado: ' || sqlerrm || E'\n'; end;
  begin execute sqlq using jsonb_set(jsonb_set(base, '{datos,extras,0,precio}', '1'), '{precio_total}', '48001'), 'ZZPRUEBA3'; r := r || 'FALLO extra manipulado pasó' || E'\n';
  exception when others then r := r || 'ok extra manipulado: ' || sqlerrm || E'\n'; end;
  begin execute sqlq using jsonb_set(base, '{datos}', (base->'datos') - 'techo' - 'extras'), 'ZZPRUEBA4'; r := r || 'FALLO sin techo pasó' || E'\n';
  exception when others then r := r || 'ok sin techo: ' || sqlerrm || E'\n'; end;
  begin execute sqlq using jsonb_set(base, '{proyecto_id}', to_jsonb(sumba::text)), 'ZZPRUEBA5'; r := r || 'FALLO precio de otro proyecto pasó' || E'\n';
  exception when others then r := r || 'ok precio de otro proyecto: ' || sqlerrm || E'\n'; end;

  -- 3ª vuelta (20260930032134): techo activo sin 2027 y alcance que se va con la casa
  begin perform public.modelo_techos_guarda_lote(dali, jsonb_build_array(jsonb_build_object('id', bambu, 'precio_ahora', 50000, 'precio_2027', null)), '[]', false);
    r := r || 'FALLO activo sin 2027 pasó' || E'
';
  exception when others then r := r || 'ok activo sin 2027: ' || sqlerrm || E'
'; end;
  t := public.modelo_techo_crea(dali, jsonb_build_object('nombre','Prueba Dos','precio_ahora',49000,'precio_2027',53000,'alcance','lista','proyectos',jsonb_build_array(sumba, palm)));
  delete from public.modelos_villa where modelo_id = dali and proyecto_id = palm;   -- destructivo-ok: dentro del ensayo que se deshace
  select count(*) into n from public.modelo_techo_proyectos where techo_id = t;
  r := r || case when n = 1 then 'ok' else 'FALLO' end || ' quitar la casa de Palm borra su alcance' || E'
';

  -- permisos
  perform set_config('request.jwt.claims', json_build_object('sub', ag, 'role', 'authenticated')::text, true);
  begin perform public.modelo_techos_guarda_lote(dali, '[]', '[]', false); r := r || 'FALLO agente usó el lote' || E'\n';
  exception when others then r := r || case when sqlstate = '42501' then 'ok' else 'FALLO' end || ' agente sin lote: ' || sqlstate || E'\n'; end;

  raise exception E'RESULTADO prueba_techos\n%', r;
end $pr$;
