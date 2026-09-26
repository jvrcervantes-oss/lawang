-- PRUEBA POR ROL, COMO ATAQUE — frontera bloque 3: modelos, precios y deck (27-sep-2026, LAW-336 / LAW-331).
-- Se ejecuta con execute_sql (MCP) o psql como postgres, UN BLOQUE POR LLAMADA (cada uno acaba en
-- `raise exception 'RES: …'`, que revierte la transacción entera y enseña el resultado: NO ESCRIBE NADA).
-- Cada punto debe decir «ok»; un «FALLO» es un agujero abierto. Usuarios de prueba: un agente
-- (dortegag@gmail.com) y un admin (p@pabloglobal.es); cámbialos si ya no están activos. Modelo de prueba: el
-- que tenga más techos y precios por proyecto (Dream el 27-sep).
-- Tras el cierre (revoke + quitar policies) añade el bloque 6.
-- Ejecutada el 27-sep-2026 contra producción tras aplicar 20260927120000: bloques 1-5 todo «ok» (1: 14/14;
-- 2: 19/19, techos 206000→214000 en 4 tramos al subir la base 2000, historial +5; 3: 8/8 y los 3 diseños
-- actuales pasan; 4: 19/19; 5: 10/10). Ensayo en seco del cierre (20260927123000): 0 privilegios y 0 policies
-- de escritura quedan.

-- 1. Agente: no toca precios, fichas, deck ni diseños; sí retipa un documento que no es plano
do $$
declare r text := ''; m uuid; d record; dp record; py uuid;
  A text := '{"sub":"1cd031f2-c7da-455e-975f-c4e8708e36fb","email":"dortegag@gmail.com","role":"authenticated"}';
begin
  select x.id into m from modelos x order by (select count(*) from modelo_techos t where t.modelo_id = x.id) desc, x.nombre limit 1;
  select * into d from modelo_documentos where tipo <> 'plano' limit 1;
  select * into dp from modelo_documentos where tipo = 'plano' limit 1;
  select id into py from proyectos limit 1;
  perform set_config('request.jwt.claims', A, true);
  set local role authenticated;
  begin perform modelo_precios_guarda(m, '{"base": 1}'); r := r || '1 FALLO agente cambia precio; '; exception when others then r := r || '1 ok; '; end;
  begin perform modelo_guarda(m, '{"descripcion":"x"}'); r := r || '2 FALLO agente edita ficha; '; exception when others then r := r || '2 ok; '; end;
  begin perform modelo_techos_guarda(m, '[]'); r := r || '3 FALLO agente toca techos; '; exception when others then r := r || '3 ok; '; end;
  begin perform contratos_diseno_guarda('ppjb_reserva', '{}'); r := r || '4 FALLO agente guarda diseño de contrato; '; exception when others then r := r || '4 ok; '; end;
  begin perform deck_faq_guarda(null, py, '{"pregunta":{"es":"x"},"respuesta":{"es":"y"}}'); r := r || '5 FALLO agente escribe FAQ del deck; '; exception when others then r := r || '5 ok; '; end;
  begin perform deck_prevision_guarda(py, m, null, '{"pct_gestion":0.1,"pct_mantenimiento":0.1,"pct_impuesto":0.1}'); r := r || '6 FALLO agente cambia previsión; '; exception when others then r := r || '6 ok; '; end;
  begin perform modelos_proyecto_fija(py, '{}'); r := r || '7 FALLO agente retira modelos de un proyecto; '; exception when others then r := r || '7 ok; '; end;
  begin perform deck_foto_fijar_vista((select id from deck_fotos where ambito = 'modelo' limit 1), null); r := r || '8 FALLO agente fija vista; '; exception when others then r := r || '8 ok; '; end;
  if dp.id is not null then
    begin perform modelo_documento_cambia(dp.id, '{"tipo":"otro"}'); r := r || '9 FALLO agente quita el plano; '; exception when others then r := r || '9 ok; '; end;
  end if;
  if d.id is not null then
    begin perform modelo_documento_cambia(d.id, '{"tipo":"plano"}'); r := r || '10 FALLO agente convierte en plano; '; exception when others then r := r || '10 ok; '; end;
    begin perform modelo_documento_cambia(d.id, jsonb_build_object('tipo', d.tipo)); r := r || '11 agente retipa no-plano ok; '; exception when others then r := r || '11 FALLO agente no puede retipar (' || sqlerrm || '); '; end;
  end if;
  begin perform modelo_documento_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', m, m::text || '/' || gen_random_uuid() || '.pdf', 'x', 'otro'); r := r || '12 FALLO el navegador registra un documento; '; exception when others then r := r || '12 ok; '; end;
  begin perform deck_foto_borra('1cd031f2-c7da-455e-975f-c4e8708e36fb', (select id from deck_fotos limit 1)); r := r || '13 FALLO el navegador borra una foto; '; exception when others then r := r || '13 ok; '; end;
  begin perform modelo_guarda(null, '{"nombre":"Prueba","slug":"prueba-b3"}'); r := r || '14 FALLO agente da de alta un modelo; '; exception when others then r := r || '14 ok; '; end;
  raise exception 'RES: %', r;
end $$;

-- 2. Admin: el cambio de precio es UNA transacción y los números los pone el servidor
do $$
declare r text := ''; m record; ajena uuid; t0 numeric; t1 numeric; b0 numeric; b1 numeric; nt int; j jsonb; nlog0 int; nlog1 int; nuevo uuid; mh uuid;
  ADM text := '{"sub":"24257595-aee2-4daa-8170-d268f46b9981","email":"p@pabloglobal.es","role":"authenticated"}';
begin
  select x.* into m from modelos x order by (select count(*) from modelo_techos t where t.modelo_id = x.id) desc, x.nombre limit 1;
  select v.id into ajena from modelos_villa v where v.modelo_id <> m.id limit 1;
  select coalesce(sum(precio_ahora), 0) + coalesce(sum(precio_2027), 0), count(*) into t0, nt from modelo_techos where modelo_id = m.id;
  b0 := m.precio_construccion;
  perform set_config('request.jwt.claims', ADM, true);
  set local role authenticated;
  -- fallo a mitad: base nueva + un precio por proyecto de OTRO modelo → no queda NADA
  begin perform modelo_precios_guarda(m.id, jsonb_build_object('base', b0 + 2000, 'villas', jsonb_build_array(jsonb_build_object('id', ajena, 'precio', 1000))));
    r := r || '1 FALLO acepta un precio de otro modelo; ';
  exception when others then r := r || '1 ok; '; end;
  select precio_construccion into b1 from modelos where id = m.id;
  select coalesce(sum(precio_ahora), 0) + coalesce(sum(precio_2027), 0) into t1 from modelo_techos where modelo_id = m.id;
  r := r || '2 tras el fallo base=' || b1 || ' techos=' || t1 || case when b1 = b0 and t1 = t0 then ' ok; ' else ' FALLO quedó a medias; ' end;
  begin perform modelo_precios_guarda(m.id, '{"moneda":"IDR"}'); r := r || '3 FALLO cambia moneda con dependientes; '; exception when others then r := r || '3 ok; '; end;
  begin perform modelo_precios_guarda(m.id, '{"base":0}'); r := r || '4 FALLO base 0; '; exception when others then r := r || '4 ok; '; end;
  begin perform modelo_precios_guarda(m.id, '{"base":-5}'); r := r || '5 FALLO base negativa; '; exception when others then r := r || '5 ok; '; end;
  begin perform modelo_precios_guarda(m.id, '{"base":"abc"}'); r := r || '6 FALLO base no numérica; '; exception when others then r := r || '6 ok; '; end;
  begin perform modelo_precios_guarda(m.id, '{"base":1000000000}'); r := r || '7 FALLO base de mil millones en EUR; '; exception when others then r := r || '7 ok; '; end;
  begin perform modelo_precios_guarda(m.id, '{"moneda":"BTC"}'); r := r || '8 FALLO moneda fuera de lista; '; exception when others then r := r || '8 ok; '; end;
  begin perform modelo_techos_guarda(m.id, jsonb_build_array(jsonb_build_object('id', (select id from modelo_techos where modelo_id <> m.id limit 1), 'precio_ahora', 1)));
    r := r || '9 FALLO toca un techo de otro modelo; ';
  exception when others then r := r || '9 ok; '; end;
  begin perform modelo_extras_guarda(m.id, jsonb_build_array(jsonb_build_object('extra_id', (select id from extras limit 1), 'precio', -5)));
    r := r || '10 FALLO extra negativo; ';
  exception when others then r := r || '10 ok; '; end;
  begin perform modelo_precios_guarda(m.id, '{"base":1,"inventado":1}'); r := r || '11 FALLO acepta una clave desconocida; '; exception when others then r := r || '11 ok; '; end;
  -- subir la base 2000 mueve cada techo 2000 en los dos tramos, lo calcula el servidor, y queda en el historial
  select count(*) into nlog0 from modelos_precios_log where modelo_id = m.id;
  j := modelo_precios_guarda(m.id, jsonb_build_object('base', b0 + 2000));
  select coalesce(sum(precio_ahora), 0) + coalesce(sum(precio_2027), 0) into t1 from modelo_techos where modelo_id = m.id;
  select count(*) into nlog1 from modelos_precios_log where modelo_id = m.id;
  r := r || '12 techos ' || t0 || '→' || t1 || ' (' || (select count(*) from modelo_techos where modelo_id = m.id and precio_2027 is not null) + nt || ' tramos)'
        || case when t1 - t0 = 2000 * (nt + (select count(*) from modelo_techos where modelo_id = m.id and precio_2027 is not null)) then ' ok; ' else ' FALLO; ' end;
  r := r || '13 historial +' || (nlog1 - nlog0) || case when nlog1 > nlog0 then ' ok; ' else ' FALLO; ' end;
  r := r || '14 contratos sin firmar (mínimo)=' || coalesce(j->>'contratos_no_firmados_min', 'FALLO') || '; ';
  -- dejar la base vacía con proyectos que la heredan
  select x.id into mh from modelos x where exists (select 1 from modelos_villa v where v.modelo_id = x.id and v.precio_construccion is null) limit 1;
  if mh is not null then
    begin perform modelo_precios_guarda(mh, '{"base":null}'); r := r || '15 FALLO base vacía con herederos; '; exception when others then r := r || '15 ok; '; end;
  end if;
  -- un modelo sin nada colgando SÍ cambia de moneda
  nuevo := modelo_guarda(null, '{"nombre":"Prueba B3","slug":"prueba-frontera-b3","moneda":"EUR"}');
  perform modelo_precios_guarda(nuevo, '{"moneda":"IDR","base":900000000}');
  r := r || '16 modelo sin dependientes pasa a ' || (select moneda || ' ' || precio_construccion from modelos where id = nuevo) || ' ok; ';
  begin perform modelo_guarda(null, '{"nombre":"Otra","slug":"prueba-frontera-b3"}'); r := r || '17 FALLO slug repetido; '; exception when others then r := r || '17 ok(' || left(sqlerrm, 40) || '); '; end;
  begin perform modelo_guarda(nuevo, '{"slug":"Con Espacios"}'); r := r || '18 FALLO slug inválido; '; exception when others then r := r || '18 ok; '; end;
  begin perform modelo_guarda(nuevo, '{"precio_construccion":5}'); r := r || '19 FALLO precio por la ficha; '; exception when others then r := r || '19 ok; '; end;
  raise exception 'RES: %', r;
end $$;

-- 3. contratos_diseno: solo admin y la forma entera en lista blanca (cada valor va sin escapar al CSS)
do $$
declare r text := ''; d record; n int := 0;
  ADM text := '{"sub":"24257595-aee2-4daa-8170-d268f46b9981","email":"p@pabloglobal.es","role":"authenticated"}';
begin
  perform set_config('request.jwt.claims', ADM, true);
  set local role authenticated;
  begin perform contratos_diseno_guarda('ppjb_reserva', '{"coverColor":"red;background:url(//x.io/b)"}'); r := r || '1 FALLO color con url(; '; exception when others then r := r || '1 ok; '; end;
  begin perform contratos_diseno_guarda('ppjb_reserva', '{"coverBg":{"src":"https://x.io/b.png","pos":"cover","op":1}}'); r := r || '2 FALLO imagen externa; '; exception when others then r := r || '2 ok; '; end;
  begin perform contratos_diseno_guarda('ppjb_reserva', '{"docLogo":{"pos":"left;}body{display:none","size":26,"op":1}}'); r := r || '3 FALLO posición inyectada; '; exception when others then r := r || '3 ok; '; end;
  begin perform contratos_diseno_guarda('ppjb_reserva', '{"css":"x"}'); r := r || '4 FALLO clave desconocida; '; exception when others then r := r || '4 ok; '; end;
  begin perform contratos_diseno_guarda('ppjb_reserva', '{"coverLogo":{"src":"data:image/svg+xml;base64,PHN2Zz4=","pos":"center","size":38,"op":1}}'); r := r || '5 FALLO svg incrustado; '; exception when others then r := r || '5 ok; '; end;
  begin perform contratos_diseno_guarda('ppjb_reserva', '{"docMark":{"src":"","pos":"center","size":5000,"op":1}}'); r := r || '6 FALLO tamaño fuera de rango; '; exception when others then r := r || '6 ok; '; end;
  begin perform contratos_diseno_guarda('ppjb_reserva', '{"coverGrain":"1;x"}'); r := r || '7 FALLO opacidad no numérica; '; exception when others then r := r || '7 ok; '; end;
  begin perform contratos_diseno_guarda('ppjb_reserva', '{"coverLogo":{"src":"data:image/png;base64,iVBOR\");}x{","pos":"center","size":38,"op":1}}'); r := r || '8 FALLO data URL con comillas; '; exception when others then r := r || '8 ok; '; end;
  -- los diseños que ya hay pasan tal cual: si alguno no, la lista blanca está mal, no el dato
  for d in select slug, design from contratos_diseno loop
    begin perform contratos_diseno_guarda(d.slug, d.design); n := n + 1;
    exception when others then r := r || '9 FALLO el diseño actual de ' || d.slug || ' no pasa (' || sqlerrm || '); '; end;
  end loop;
  r := r || '9 diseños actuales que pasan=' || n || '/' || (select count(*) from contratos_diseno) || '; ';
  raise exception 'RES: %', r;
end $$;

-- 4. Deck: previsión, configuración, FAQ y fotos (admin)
do $$
declare r text := ''; py record; m uuid; midr uuid; f uuid; t jsonb; ff uuid;
  ADM text := '{"sub":"24257595-aee2-4daa-8170-d268f46b9981","email":"p@pabloglobal.es","role":"authenticated"}';
begin
  select p.id, p.nombre into py from proyectos p where exists (select 1 from modelos_villa v where v.proyecto_id = p.id) limit 1;
  select v.modelo_id into m from modelos_villa v join modelos x on x.id = v.modelo_id where v.proyecto_id = py.id and x.moneda = 'EUR' limit 1;
  select id into midr from modelos where moneda = 'IDR' limit 1;
  perform set_config('request.jwt.claims', ADM, true);
  set local role authenticated;
  begin perform deck_prevision_guarda(py.id, m, '{"adr_medio":100,"adr_optimo":120,"ocupacion_media":1.5,"ocupacion_optima":0.6,"inversion_base":100000}', null); r := r || '1 FALLO ocupación 150 %; '; exception when others then r := r || '1 ok; '; end;
  begin perform deck_prevision_guarda(py.id, m, '{"adr_medio":100,"adr_optimo":120,"ocupacion_media":0.7,"ocupacion_optima":0.6,"inversion_base":100000}', null); r := r || '2 FALLO media > óptima; '; exception when others then r := r || '2 ok; '; end;
  begin perform deck_prevision_guarda(py.id, m, '{"adr_medio":0,"adr_optimo":120,"ocupacion_media":0.5,"ocupacion_optima":0.6,"inversion_base":100000}', null); r := r || '3 FALLO ADR 0; '; exception when others then r := r || '3 ok; '; end;
  if midr is not null then
    begin perform deck_prevision_guarda(py.id, midr, '{"adr_medio":100,"adr_optimo":120,"ocupacion_media":0.5,"ocupacion_optima":0.6,"inversion_base":100000}', null); r := r || '4 FALLO previsión de un modelo en IDR; '; exception when others then r := r || '4 ok; '; end;
  end if;
  begin perform deck_prevision_guarda(py.id, m, null, '{"pct_gestion":0.5,"pct_mantenimiento":0.3,"pct_impuesto":0.3}'); r := r || '5 FALLO gastos > 100 %; '; exception when others then r := r || '5 ok; '; end;
  -- gasto bueno + previsión mala en la MISMA llamada: no queda nada
  begin perform deck_prevision_guarda(py.id, m, '{"adr_medio":-1}', '{"pct_gestion":0.11,"pct_mantenimiento":0.05,"pct_impuesto":0.1}'); r := r || '6 FALLO; ';
  exception when others then r := r || '6 ok; '; end;
  r := r || '7 gastos intactos=' || coalesce((select (pct_gestion <> 0.11)::text from deck_forecast_proyecto where proyecto_id = py.id), 'sin fila') || '; ';
  perform deck_prevision_guarda(py.id, m, '{"adr_medio":100,"adr_optimo":120,"ocupacion_media":0.5,"ocupacion_optima":0.6,"inversion_base":100000,"publicado":false}', '{"pct_gestion":0.2,"pct_mantenimiento":0.05,"pct_impuesto":0.1}');
  r := r || '8 previsión válida guardada ok; ';
  -- config: el título se MEZCLA por idioma (antes el upsert borraba el español)
  perform deck_config_guarda(py.id, '{"titulo":{"en":"T en","es":"T es"},"meta_desc":{"en":"M en"}}');
  perform deck_config_guarda(py.id, '{"titulo":{"en":"T en 2"},"meta_desc":{"en":"M en 2"}}');
  select titulo into t from deck_config_proyecto where proyecto_id = py.id;
  r := r || '9 título=' || t::text || case when t->>'es' = 'T es' and t->>'en' = 'T en 2' then ' ok; ' else ' FALLO; ' end;
  begin perform deck_config_guarda(py.id, '{"kpis":[]}'); r := r || '10 FALLO acepta kpis; '; exception when others then r := r || '10 ok; '; end;
  begin perform deck_config_guarda(py.id, jsonb_build_object('modelo_destacado_id', (select id from modelos where id not in (select modelo_id from modelos_villa where proyecto_id = py.id and modelo_id is not null) limit 1)));
    r := r || '11 FALLO destacado que no se construye ahí; ';
  exception when others then r := r || '11 ok; '; end;
  -- FAQ: el freno de Legal en el servidor
  begin perform deck_faq_guarda(null, py.id, '{"pregunta":{"es":"¿Rentabilidad?"},"respuesta":{"es":"Rentabilidad garantizada del 10 %"},"publicado":true}'); r := r || '12 FALLO publica rentabilidad garantizada; ';
  exception when others then r := r || '12 ok; '; end;
  begin perform deck_faq_guarda(null, py.id, '{"pregunta":{"es":"¿Título?"},"respuesta":{"es":"Vía nominee"},"publicado":true}'); r := r || '13 FALLO publica nominee; ';
  exception when others then r := r || '13 ok; '; end;
  f := deck_faq_guarda(null, py.id, '{"pregunta":{"es":"¿Rentabilidad?"},"respuesta":{"es":"Rentabilidad garantizada del 10 %"},"publicado":false}');
  r := r || '14 sin publicar se guarda ok, creado_por=' || (select creado_por from deck_faq where id = f) || '; ';
  begin perform deck_faq_guarda(f, null, '{"pregunta":{"en":"x"}}'); r := r || '15 FALLO pregunta sin español; '; exception when others then r := r || '15 ok; '; end;
  perform deck_faq_borra(f);
  r := r || '16 borrada=' || (not exists (select 1 from deck_faq where id = f))::text || '; ';
  -- fotos: pie sin inglés, clave desconocida
  select id into ff from deck_fotos limit 1;
  if ff is not null then
    begin perform deck_foto_cambia(ff, '{"pie":{"es":"solo español"}}'); r := r || '17 FALLO pie sin inglés; '; exception when others then r := r || '17 ok; '; end;
    begin perform deck_foto_cambia(ff, '{"path":"otro/fichero.webp"}'); r := r || '18 FALLO cambia la ruta; '; exception when others then r := r || '18 ok; '; end;
    begin perform deck_foto_fijar_vista(ff, 'inventada'); r := r || '19 FALLO vista inventada; '; exception when others then r := r || '19 ok; '; end;
  end if;
  raise exception 'RES: %', r;
end $$;

-- 5. Registro de ficheros: solo la edge (service_role), como el usuario de la sesión, en SU carpeta
do $$
declare r text := ''; m uuid; otro uuid; p text; v uuid;
begin
  select id into m from modelos order by nombre limit 1;
  select id into otro from modelos where id <> m order by nombre limit 1;
  p := m::text || '/' || gen_random_uuid()::text || '.pdf';
  insert into storage.objects (bucket_id, name, metadata) values ('modelos', p, '{"size": 1234}');
  set local role service_role;
  begin perform modelo_documento_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', m, p, 'plano.pdf', 'plano'); r := r || '1 FALLO agente registra un plano; '; exception when others then r := r || '1 ok; '; end;
  begin perform modelo_documento_registra('24257595-aee2-4daa-8170-d268f46b9981', otro, p, 'x.pdf', 'otro'); r := r || '2 FALLO ruta de otro modelo; '; exception when others then r := r || '2 ok; '; end;
  begin perform modelo_documento_registra('24257595-aee2-4daa-8170-d268f46b9981', m, m::text || '/' || gen_random_uuid() || '.pdf', 'x.pdf', 'otro'); r := r || '3 FALLO fichero que no existe; '; exception when others then r := r || '3 ok; '; end;
  begin perform modelo_documento_registra(gen_random_uuid(), m, p, 'x.pdf', 'otro'); r := r || '4 FALLO usuario falso; '; exception when others then r := r || '4 ok; '; end;
  v := modelo_documento_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', m, p, E'nombre\x01 real.pdf', 'calidades');
  r := r || '5 agente registra no-plano ok (tamaño=' || (select tamano_bytes from modelo_documentos where id = v) || ', subido_por=agente ' || ((select subido_por from modelo_documentos where id = v) = '1cd031f2-c7da-455e-975f-c4e8708e36fb')::text || '); ';
  begin perform modelo_documento_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', m, p, 'x.pdf', 'otro'); r := r || '6 FALLO registra dos veces; '; exception when others then r := r || '6 ok; '; end;
  begin perform modelo_documento_borra('1cd031f2-c7da-455e-975f-c4e8708e36fb', v); r := r || '7 FALLO agente borra; '; exception when others then r := r || '7 ok; '; end;
  r := r || '8 admin comprueba sin borrar: ' || (modelo_documento_borra('24257595-aee2-4daa-8170-d268f46b9981', v, true) = p)::text
        || ', fila sigue=' || exists (select 1 from modelo_documentos where id = v)::text || '; ';
  begin perform deck_foto_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', 'modelo', m, 'modelo/' || m || '/' || gen_random_uuid() || '.webp', 'x'); r := r || '9 FALLO agente registra foto del deck; '; exception when others then r := r || '9 ok; '; end;
  begin perform deck_foto_registra('24257595-aee2-4daa-8170-d268f46b9981', 'modelo', m, 'modelo/' || otro || '/' || gen_random_uuid() || '.webp', 'x'); r := r || '10 FALLO foto en carpeta ajena; '; exception when others then r := r || '10 ok; '; end;
  raise exception 'RES: %', r;
end $$;

-- 6. (tras el cierre) Escritura directa cerrada: como agente y como admin, insert/update/delete sobre las 11
-- tablas y subir/borrar en los buckets `modelos` y `deck` falla (privilegio o policy). Mirar también
-- `relacl` de cada tabla: authenticated solo con SELECT (arwd → r).
