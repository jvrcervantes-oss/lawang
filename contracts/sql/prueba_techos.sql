-- destructivo-ok: ENSAYO que termina en raise y se deshace entero (prueba un delete de modelos_villa y DDL temporal).
-- Prueba de los techos y extras (30-sep-2026, modelo de SUPLEMENTO, migración 20260930120000): fórmula 2026/2027,
-- alta de techo, cambio de techo base, alcance, lote todo-o-nada, invariantes, candado del trigger de Construcción,
-- alta/retirada de extras y permisos. Se pega en mcp__supabase-lawang__execute_sql (o el SQL Editor). NO deja rastro.
-- Resultado: la excepción final lista cada caso con «ok» o «FALLO». Cualquier «FALLO» = no se publica.
-- Supuestos de datos (30-sep, tras la migración): Dali base 48.000 / 52.000 (2027) con Sirap base, Bamboo +2.000/+4.000,
-- Alang-alang +4.000/+0 solo en Sumba Hills; Sumba Hills con Dali a 52.000 (precio propio); Palm Field W5 hereda;
-- CC00118 = Construcción Dali Sirap con extra Airbnb (5.000). Si cambian, se ajustan aquí.
do $pr$
declare
  r text := ''; v jsonb; t uuid; n int; ok boolean; x uuid;
  dali uuid := (select id from public.modelos where nombre = 'Dali');
  clan uuid := (select id from public.modelos where nombre = 'Clan');
  sumba uuid := (select id from public.proyectos where nombre = 'Sumba Hills');
  palm uuid := (select id from public.proyectos where nombre = 'Palm Field W5');
  horizon uuid := (select id from public.proyectos where nombre = 'Horizon S1');
  sirap uuid := (select id from public.modelo_techos where modelo_id = (select id from public.modelos where nombre = 'Dali') and clave = 'sirap');
  bambu uuid := (select id from public.modelo_techos where modelo_id = (select id from public.modelos where nombre = 'Dali') and clave = 'bambu');
  airbnb uuid := (select id from public.extras where clave = 'airbnb');
  adm text := (select user_id::text from public.usuarios where rol = 'admin' and activo limit 1);
  ag text := (select user_id::text from public.usuarios where rol = 'agente' and activo limit 1);
  base jsonb; cols text; sqlq text;
begin
  -- Las reglas de techos son un constraint trigger DIFERIDO al commit (como en producción). Tras cada llamada que
  -- escribe se disparan a mano con `set constraints all immediate; set constraints all deferred;` (= el commit).
  -- fórmula
  select jsonb_object_agg(o.clave, o.precio) into v from public._modelo_techos_opciones_tramo(dali, sumba, '2026') o;
  r := r || case when v = '{"sirap":52000,"bambu":54000,"alang_alang":56000}'::jsonb then 'ok' else 'FALLO' end || ' 2026 dali@sumba ' || v || E'\n';
  select jsonb_object_agg(o.clave, o.precio) into v from public._modelo_techos_opciones_tramo(dali, sumba, '2027') o;
  r := r || case when v = '{"sirap":52000,"bambu":56000,"alang_alang":52000}'::jsonb then 'ok' else 'FALLO' end || ' 2027 dali@sumba (sin doble subida) ' || v || E'\n';
  select jsonb_object_agg(o.clave, o.precio) into v from public._modelo_techos_opciones_tramo(dali, palm, '2026') o;
  r := r || case when v = '{"sirap":48000,"bambu":50000}'::jsonb then 'ok' else 'FALLO' end || ' 2026 dali@palm ' || v || E'\n';
  select jsonb_object_agg(o.clave, o.precio) into v from public._modelo_techos_opciones_tramo(dali, palm, '2027') o;
  r := r || case when v = '{"sirap":52000,"bambu":56000}'::jsonb then 'ok' else 'FALLO' end || ' 2027 dali@palm (hereda, sube con el catálogo) ' || v || E'\n';
  v := public.catalogo_publico()->'dali'->'techos'->'bambu';
  r := r || case when (v->>'now')::numeric = 50000 and (v->>'y2027')::numeric = 56000 then 'ok' else 'FALLO' end || ' web: precio completo de Bamboo ' || coalesce(v::text, 'null') || E'\n';

  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  -- alta de techo con suplemento, limitada a Palm Field
  t := public.modelo_techo_crea(dali, jsonb_build_object('nombre','Prueba Teja','suplemento_ahora',3000,'suplemento_2027',3500,'alcance','lista','proyectos',jsonb_build_array(palm))); set constraints all immediate; set constraints all deferred;
  select count(*) into n from public._modelo_techos_opciones_tramo(dali, palm, '2026') o where o.techo_id = t and o.precio = 51000;
  r := r || case when n = 1 then 'ok' else 'FALLO' end || ' alta: Palm Field 48.000 + 3.000' || E'\n';
  select count(*) into n from public._modelo_techos_opciones_tramo(dali, sumba, '2026') o where o.techo_id = t;
  r := r || case when n = 0 then 'ok' else 'FALLO' end || ' alta NO ofrecida en Sumba' || E'\n';
  begin perform public.modelo_techo_crea(dali, '{"nombre":"Negativo","suplemento_ahora":-1000,"suplemento_2027":0}'); set constraints all immediate; set constraints all deferred; r := r || 'FALLO suplemento negativo pasó' || E'\n';
  exception when others then r := r || case when sqlstate = '22023' then 'ok' else 'FALLO' end || ' suplemento negativo: ' || sqlerrm || E'\n'; end;
  begin perform public.modelo_techo_crea(dali, jsonb_build_object('nombre','Y','suplemento_ahora',1,'suplemento_2027',1,'alcance','lista','proyectos',jsonb_build_array(horizon))); set constraints all immediate; set constraints all deferred; r := r || 'FALLO proyecto sin la casa pasó' || E'\n';
  exception when others then r := r || case when sqlstate = '22023' then 'ok' else 'FALLO' end || ' proyecto sin la casa: ' || sqlerrm || E'\n'; end;
  -- cambio de techo base: Bamboo pasa a base (suplemento 0) y Sirap +1.000 / +2.000, en un lote
  perform public.modelo_techos_guarda_lote(dali,
    jsonb_build_array(jsonb_build_object('id', bambu, 'suplemento_ahora', 0, 'suplemento_2027', 0),
                      jsonb_build_object('id', sirap, 'suplemento_ahora', 1000, 'suplemento_2027', 2000)),
    jsonb_build_array(jsonb_build_object('id', bambu, 'cambios', '{"es_base":true}'::jsonb)), false); set constraints all immediate; set constraints all deferred;
  select (select es_base from public.modelo_techos where id = bambu) and not (select es_base from public.modelo_techos where id = sirap) into ok;
  r := r || case when ok then 'ok' else 'FALLO' end || ' cambio de techo base en un lote' || E'\n';
  -- el base con suplemento se rechaza (invariante)
  begin perform public.modelo_techos_guarda_lote(dali, jsonb_build_array(jsonb_build_object('id', bambu, 'suplemento_ahora', 500, 'suplemento_2027', 0)), '[]', false); set constraints all immediate; set constraints all deferred;
    r := r || 'FALLO base con suplemento pasó' || E'\n';
  exception when others then r := r || case when sqlstate = '23514' then 'ok' else 'FALLO' end || ' base con suplemento: ' || sqlerrm || E'\n'; end;
  -- retirar el base se rechaza
  begin perform public.modelo_techos_guarda_lote(dali, '[]', jsonb_build_array(jsonb_build_object('id', bambu, 'cambios', '{"activo":false}'::jsonb)), true); set constraints all immediate; set constraints all deferred;
    r := r || 'FALLO retirar el base pasó' || E'\n';
  exception when others then r := r || case when sqlstate = '23514' then 'ok' else 'FALLO' end || ' retirar el base: ' || sqlerrm || E'\n'; end;
  -- lote sin confirmar con contratos afectados → LW409 y nada guardado (Sirap lo llevan contratos sin firmar)
  begin perform public.modelo_techos_guarda_lote(dali, jsonb_build_array(jsonb_build_object('id', sirap, 'suplemento_ahora', 1100, 'suplemento_2027', 2000)),
      jsonb_build_array(jsonb_build_object('id', sirap, 'cambios', '{"activo":false}'::jsonb)), false); set constraints all immediate; set constraints all deferred;
    r := r || 'FALLO lote sin confirmar pasó' || E'\n';
  exception when others then r := r || case when sqlstate = 'LW409' then 'ok' else 'FALLO' end || ' lote sin confirmar: ' || sqlstate || E'\n'; end;
  select (activo and suplemento_ahora = 1000) into ok from public.modelo_techos where id = sirap;
  r := r || case when ok then 'ok' else 'FALLO' end || ' lote cancelado no dejó nada a medias' || E'\n';
  -- base 2027 vacía con techos → rechazada
  begin perform public.modelo_precios_guarda(dali, '{"base_2027":null}'); set constraints all immediate; set constraints all deferred; r := r || 'FALLO base 2027 vacía pasó' || E'\n';
  exception when others then r := r || case when sqlstate = '23514' then 'ok' else 'FALLO' end || ' base 2027 vacía: ' || sqlerrm || E'\n'; end;
  -- quitar la casa de un proyecto borra su alcance
  delete from public.modelos_villa where modelo_id = dali and proyecto_id = palm; set constraints all immediate; set constraints all deferred;
  select count(*) into n from public.modelo_techo_proyectos where techo_id = t;
  r := r || case when n = 0 then 'ok' else 'FALLO' end || ' quitar la casa de Palm borra su alcance' || E'\n';

  -- extras
  x := public.extra_crea(dali, '{"nombre":"Prueba Piscina","precio":12000}'); set constraints all immediate; set constraints all deferred;
  select count(*) into n from public.modelo_extras_opciones(dali) o where o.extra_id = x and o.precio = 12000;
  r := r || case when n = 1 then 'ok' else 'FALLO' end || ' alta de extra ofrecida en Dali' || E'\n';
  select count(*) into n from public.modelo_extras me join public.modelos m on m.id = me.modelo_id where me.extra_id = x and m.id <> dali and me.disponible;
  r := r || case when n = 0 then 'ok' else 'FALLO' end || ' alta de extra NO ofrecida en otros modelos' || E'\n';
  begin perform public.extras_catalogo_guarda(jsonb_build_array(jsonb_build_object('id', x, 'cambios', '{"activo":false}'::jsonb)), false); set constraints all immediate; set constraints all deferred;
    r := r || 'ok retirar extra sin contratos' || E'\n';
  exception when others then r := r || 'FALLO retirar extra: ' || sqlerrm || E'\n'; end;
  select count(*) into n from public.modelo_extras_opciones(dali) o where o.extra_id = x;
  r := r || case when n = 0 then 'ok' else 'FALLO' end || ' extra retirado ya no se ofrece' || E'\n';
  begin delete from public.extras where id = x; r := r || 'FALLO borrar un extra pasó' || E'\n';
  exception when others then r := r || case when sqlstate = '23503' then 'ok' else 'FALLO' end || ' borrar un extra: ' || sqlstate || E'\n'; end;

  -- trigger de Construcción (vuelve Sirap a base para poder copiar CC00118 tal cual)
  perform public.modelo_techos_guarda_lote(dali,
    jsonb_build_array(jsonb_build_object('id', sirap, 'suplemento_ahora', 0, 'suplemento_2027', 0),
                      jsonb_build_object('id', bambu, 'suplemento_ahora', 2000, 'suplemento_2027', 4000)),
    jsonb_build_array(jsonb_build_object('id', sirap, 'cambios', '{"es_base":true}'::jsonb)), false); set constraints all immediate; set constraints all deferred;
  select string_agg(quote_ident(column_name), ',') into cols from information_schema.columns
   where table_schema = 'public' and table_name = 'contratos' and is_generated = 'NEVER' and column_name not in ('id','numero','created_at','updated_at','bloqueado');
  select to_jsonb(c) into base from public.contratos c where numero = 'CC00118';
  base := jsonb_set(jsonb_set(base, '{datos,fields,descuento_comercial}', '""'), '{precio_total}', '53000');
  base := jsonb_set(base, '{datos}', (base->'datos') - 'annexes');
  sqlq := format('insert into public.contratos (%s, numero, bloqueado) select %s, $2, false from jsonb_populate_record(null::public.contratos, $1)', cols, cols);
  begin execute sqlq using base, 'ZZPRUEBA1'; r := r || 'ok contrato limpio entra' || E'\n';
  exception when others then r := r || 'FALLO contrato limpio: ' || sqlerrm || E'\n'; end;
  begin execute sqlq using jsonb_set(jsonb_set(base, '{datos,techo,precio}', '40000'), '{precio_total}', '45000'), 'ZZPRUEBA2'; r := r || 'FALLO techo manipulado pasó' || E'\n';
  exception when others then r := r || case when sqlstate = '22023' then 'ok' else 'FALLO' end || ' techo manipulado: ' || sqlerrm || E'\n'; end;
  begin execute sqlq using jsonb_set(jsonb_set(base, '{datos,extras,0,precio}', '1'), '{precio_total}', '48001'), 'ZZPRUEBA3'; r := r || 'FALLO extra manipulado pasó' || E'\n';
  exception when others then r := r || case when sqlstate = '22023' then 'ok' else 'FALLO' end || ' extra manipulado: ' || sqlerrm || E'\n'; end;
  begin execute sqlq using jsonb_set(base, '{datos}', (base->'datos') - 'techo' - 'extras'), 'ZZPRUEBA4'; r := r || 'FALLO sin techo pasó' || E'\n';
  exception when others then r := r || case when sqlstate = '22023' then 'ok' else 'FALLO' end || ' sin techo: ' || sqlerrm || E'\n'; end;
  begin execute sqlq using jsonb_set(base, '{proyecto_id}', to_jsonb(sumba::text)), 'ZZPRUEBA5'; r := r || 'FALLO precio de otro proyecto pasó' || E'\n';
  exception when others then r := r || case when sqlstate = '22023' then 'ok' else 'FALLO' end || ' precio de otro proyecto: ' || sqlerrm || E'\n'; end;

  -- permisos
  perform set_config('request.jwt.claims', json_build_object('sub', ag, 'role', 'authenticated')::text, true);
  begin perform public.modelo_techos_guarda_lote(dali, '[]', '[]', false); set constraints all immediate; set constraints all deferred; r := r || 'FALLO agente usó el lote' || E'\n';
  exception when others then r := r || case when sqlstate = '42501' then 'ok' else 'FALLO' end || ' agente sin lote: ' || sqlstate || E'\n'; end;
  begin perform public.extra_crea(dali, '{"nombre":"Z","precio":1}'); set constraints all immediate; set constraints all deferred; r := r || 'FALLO agente dio de alta un extra' || E'\n';
  exception when others then r := r || case when sqlstate = '42501' then 'ok' else 'FALLO' end || ' agente sin alta de extra: ' || sqlstate || E'\n'; end;
  begin perform public.extras_catalogo_guarda('[]', false); set constraints all immediate; set constraints all deferred; r := r || 'FALLO agente tocó el catálogo' || E'\n';
  exception when others then r := r || case when sqlstate = '42501' then 'ok' else 'FALLO' end || ' agente sin catálogo: ' || sqlstate || E'\n'; end;

  raise exception E'RESULTADO prueba_techos\n%', r;
end $pr$;
