-- PRUEBA POR ROL, COMO ATAQUE — frontera bloques 4 y 5: ficheros (documentación, obra, creatividades, justificantes
-- de gasto) y el resto (comunicados, soporte, solicitudes de cambio, copias del asistente, perfiles de banco,
-- reasignar autor). 27-sep-2026, LAW-336 / LAW-337. Plan y revisión previa #127:
-- encargos/20260927_lawang_frontera_b4_b5_resto.md
--
-- Se ejecuta con execute_sql (MCP) o psql como postgres, UN BLOQUE POR LLAMADA. Cada bloque acaba en
-- `raise exception 'RES: …'`, que REVIERTE la transacción entera (también los `update usuarios` con los que se
-- acota a un usuario de prueba a UN proyecto, y los objetos de storage falsos): NO ESCRIBE NADA.
-- Cada punto debe decir «ok»; un «FALLO» es un agujero abierto.
-- Usuarios (activos el 27-sep; cámbialos si dejan de estarlo):
--   agente con documentación, sin obra ......... dortegag@gmail.com          1cd031f2-c7da-455e-975f-c4e8708e36fb
--   agente con la herramienta obra ............. admin@lawangproperties.com  dc1961c0-f623-40c2-82c7-baf94b29bac2
--   admin sin creatividades (Pablo) ............ p@pabloglobal.es            24257595-aee2-4daa-8170-d268f46b9981
--   Andrea, su rol REAL (admin, sin creatividades ni dossier) andreabenimeli@gmail.com da378aad-9477-42ce-b349-c2d7ced8f65a
--   admin con creatividades + dossier + gastos . fran.mg@lawangproperties.com fef30aea-3ab2-43be-ad1c-7b6acdbe0c83
--   super admin ................................ jvr.cervantes@gmail.com     45d014eb-46f2-4770-87a7-69bbd08a44ae
--
-- Ejecutada el 27-sep-2026 contra producción tras aplicar 20260927150000 (antes del cierre):
--   1 documentación 19/19 (alta en su proyecto; rechaza proyecto ajeno, dosier y «general» de un agente, url
--     javascript:, cambiar el path, editar/mover a un proyecto ajeno, reclasificar como portada, que el navegador
--     registre, ruta de otro proyecto, fichero inexistente, ruta con «..»; registra el suyo con bytes y mime del
--     objeto; el agente no borra; el super admin comprueba sin borrar).
--   2 obra 13/13 (obra_puede suya=true ajena=false; lectura del cierre: ve la suya=true, la ajena=false).
--   3 creatividades 12/12: Andrea con su rol REAL rechazada con «No tienes permiso para hacer dossiers (te falta la
--     herramienta «Dossier»)…»; Fran crea un dossier borrador con 1 foto y 1 modelo en una llamada; una archivada da
--     «Esta creatividad ya no es un borrador (está «archivada»): guárdala como copia…»; enlaces intactos tras un fallo.
--   4 resto 16/16 (el agente no cierra el ticket de un comprador que no ve; no pide borrar una operación que no ve;
--     SC manual con pedido_por del servidor; comunicado con creado_por del servidor y enlace fuera de lista rechazado).
--   5 reasignar autor 9/9 + justificantes 4/4 (la traza +1 y el autor cambian en la misma transacción; contrato
--     bloqueado rechazado). El punto 2 decía «el navegador aún escribe en correcciones_datos»: lo cierra 153000.
--   6 superficie 8/8 (proacl: solo service_role/postgres en las RPC de la edge y las ayudas internas).
--   Ensayo en seco del cierre (20260927153000, revertido): 0 privilegios de tabla, 0 por columna, 0 policies de escritura.
-- Nota: el bloque 4 consume un número de la secuencia de solicitudes_cambio (SC-27 el 27-sep) aunque se revierta.

-- 1. DOCUMENTACIÓN (agente acotado a UN proyecto; super admin para borrar)
do $$
declare r text := ''; p1 uuid; p1n text; p2 uuid; p2n text; d uuid; dajeno uuid; pth text; v uuid;
  A text := '{"sub":"1cd031f2-c7da-455e-975f-c4e8708e36fb","email":"dortegag@gmail.com","role":"authenticated"}';
begin
  select id, nombre into p1, p1n from proyectos order by nombre limit 1;
  select id, nombre into p2, p2n from proyectos where id <> p1 order by nombre limit 1;
  update usuarios set proyectos = array[p1] where user_id = '1cd031f2-c7da-455e-975f-c4e8708e36fb';
  insert into documentos_proyecto (proyecto, proyecto_id, titulo, url, confidencial) values (p2n, p2, 'ajeno', 'https://x.io/a', true) returning id into dajeno;
  pth := 'proyectos/' || p1 || '/' || gen_random_uuid() || '.pdf';
  insert into storage.objects (bucket_id, name, metadata) values ('documentacion', pth, '{"size": 1234, "mimetype": "application/pdf"}');
  perform set_config('request.jwt.claims', A, true);
  set local role authenticated;
  d := documento_proyecto_guarda(null, jsonb_build_object('proyecto_id', p1, 'titulo', 'Enlace de prueba', 'url', 'https://drive.google.com/x', 'categoria', 'comercial'));
  r := r || '1 alta de enlace en su proyecto ok (creado_por=' || (select creado_por from documentos_proyecto where id = d) || '); ';
  begin perform documento_proyecto_guarda(null, jsonb_build_object('proyecto_id', p2, 'titulo', 'x', 'url', 'https://x.io')); r := r || '2 FALLO alta en proyecto ajeno; '; exception when others then r := r || '2 ok; '; end;
  begin perform documento_proyecto_guarda(d, '{"publicado_investor_deck":true,"confidencial":false}'); r := r || '3 FALLO agente publica en el dosier de inversores; '; exception when others then r := r || '3 ok; '; end;
  begin perform documento_proyecto_guarda(d, '{"general":true}'); r := r || '4 FALLO agente marca general; '; exception when others then r := r || '4 ok; '; end;
  begin perform documento_proyecto_guarda(d, '{"url":"javascript:alert(1)"}'); r := r || '5 FALLO url javascript:; '; exception when others then r := r || '5 ok; '; end;
  begin perform documento_proyecto_guarda(d, '{"path":"proyectos/otro/x.pdf"}'); r := r || '6 FALLO cambia el path; '; exception when others then r := r || '6 ok; '; end;
  begin perform documento_proyecto_guarda(dajeno, '{"titulo":"mío"}'); r := r || '7 FALLO edita un documento de proyecto ajeno; '; exception when others then r := r || '7 ok; '; end;
  begin perform documento_proyecto_guarda(d, jsonb_build_object('proyecto_id', p2)); r := r || '8 FALLO lo mueve a un proyecto ajeno; '; exception when others then r := r || '8 ok; '; end;
  begin perform documento_proyecto_guarda(d, '{"categoria":"portada"}'); r := r || '9 FALLO reclasifica como portada; '; exception when others then r := r || '9 ok; '; end;
  perform documento_proyecto_guarda(d, '{"visible_portal":true,"confidencial":false,"titulo":"Para el portal"}');
  r := r || '10 visible_portal/confidencial/título ok (' || (select visible_portal::text || '/' || confidencial::text from documentos_proyecto where id = d) || '); ';
  v := documento_proyecto_guarda(null, jsonb_build_object('proyecto', p1n, 'titulo', '¿Pregunta?', 'categoria', 'faq', 'carpeta', 'Preguntas frecuentes'));
  r := r || '11 FAQ sin enlace ok; ';
  begin perform documento_proyecto_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', p1, pth, '{}'); r := r || '12 FALLO el navegador registra un fichero; '; exception when others then r := r || '12 ok; '; end;
  reset role;
  set local role service_role;
  begin perform documento_proyecto_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', p2, 'proyectos/' || p2 || '/' || gen_random_uuid() || '.pdf', '{}'); r := r || '13 FALLO registra en proyecto ajeno; '; exception when others then r := r || '13 ok; '; end;
  begin perform documento_proyecto_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', p1, 'proyectos/' || p1 || '/' || gen_random_uuid() || '.pdf', '{}'); r := r || '14 FALLO registra un fichero que no existe; '; exception when others then r := r || '14 ok; '; end;
  begin perform documento_proyecto_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', p1, pth, '{"publicado_investor_deck":true,"confidencial":false}'); r := r || '15 FALLO agente registra publicado en el deck; '; exception when others then r := r || '15 ok; '; end;
  begin perform documento_proyecto_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', p1, 'proyectos/' || p1 || '/../' || gen_random_uuid() || '.pdf', '{}'); r := r || '16 FALLO ruta con ..; '; exception when others then r := r || '16 ok; '; end;
  v := documento_proyecto_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', p1, pth, '{"titulo":"Plano","categoria":"planos"}');
  r := r || '17 registra el suyo ok (bytes=' || (select bytes from documentos_proyecto where id = v) || ', mime=' || (select mime from documentos_proyecto where id = v) || '); ';
  begin perform documento_proyecto_borra('1cd031f2-c7da-455e-975f-c4e8708e36fb', v); r := r || '18 FALLO agente borra; '; exception when others then r := r || '18 ok; '; end;
  r := r || '19 super admin comprueba sin borrar: ' || (documento_proyecto_borra('45d014eb-46f2-4770-87a7-69bbd08a44ae', v, true) = pth)::text
        || ', fila sigue=' || exists (select 1 from documentos_proyecto where id = v)::text || '; ';
  raise exception 'RES: %', r;
end $$;

-- 1b. Documentos «general» de la sociedad desde la clásica (revisor de código, 27-sep; arreglado en 20260927151500).
-- Ejecutada el 27-sep: «1 admin edita un documento general desde la clásica ok (Lawang (general), proyecto_id sigue
-- null); 2 ok; 3 ok».
do $$
declare r text := ''; g record;
  ADM text := '{"sub":"24257595-aee2-4daa-8170-d268f46b9981","email":"p@pabloglobal.es","role":"authenticated"}';
  A text := '{"sub":"1cd031f2-c7da-455e-975f-c4e8708e36fb","email":"dortegag@gmail.com","role":"authenticated"}';
begin
  select * into g from documentos_proyecto where general limit 1;
  perform set_config('request.jwt.claims', ADM, true);
  set local role authenticated;
  perform documento_proyecto_guarda(g.id, jsonb_build_object('proyecto', g.proyecto, 'titulo', g.titulo || ' (editado)', 'publicado_investor_deck', g.publicado_investor_deck, 'confidencial', g.confidencial));
  r := r || '1 admin edita un documento general desde la clásica ok (' || g.proyecto || ', proyecto_id sigue ' || coalesce((select proyecto_id::text from documentos_proyecto where id = g.id), 'null') || '); ';
  reset role;
  perform set_config('request.jwt.claims', A, true);
  set local role authenticated;
  begin perform documento_proyecto_guarda(g.id, jsonb_build_object('proyecto', g.proyecto, 'titulo', 'x')); r := r || '2 FALLO agente edita un documento general; '; exception when others then r := r || '2 ok; '; end;
  begin perform documento_proyecto_guarda(null, jsonb_build_object('proyecto', g.proyecto, 'titulo', 'x', 'url', 'https://x.io')); r := r || '3 FALLO alta con nombre general inexistente; '; exception when others then r := r || '3 ok; '; end;
  raise exception 'RES: %', r;
end $$;

-- 2. OBRA (agente con la herramienta obra acotado a UN proyecto; otro agente sin la herramienta)
do $$
declare r text := ''; p1 uuid; p2 uuid; u1 uuid; u2 uuid; pth text; f uuid; fajena uuid;
  O text := '{"sub":"dc1961c0-f623-40c2-82c7-baf94b29bac2","email":"admin@lawangproperties.com","role":"authenticated"}';
  A text := '{"sub":"1cd031f2-c7da-455e-975f-c4e8708e36fb","email":"dortegag@gmail.com","role":"authenticated"}';
begin
  select u.proyecto_id, u.id into p1, u1 from unidades u where u.proyecto_id is not null order by u.proyecto_id, u.id limit 1;
  select u.proyecto_id, u.id into p2, u2 from unidades u where u.proyecto_id is not null and u.proyecto_id <> p1 order by u.id limit 1;
  update usuarios set proyectos = array[p1] where user_id = 'dc1961c0-f623-40c2-82c7-baf94b29bac2';
  update usuarios set proyectos = array[p2] where user_id = '1cd031f2-c7da-455e-975f-c4e8708e36fb';
  pth := u1 || '/' || gen_random_uuid() || '.jpg';
  insert into storage.objects (bucket_id, name, metadata) values ('obra', pth, '{"size": 100}');
  insert into obra_fotos (unidad_id, path) values (u2, u2 || '/' || gen_random_uuid() || '.jpg') returning id into fajena;
  set local role service_role;
  begin perform obra_foto_registra('dc1961c0-f623-40c2-82c7-baf94b29bac2', u2, u2 || '/' || gen_random_uuid() || '.jpg', null); r := r || '1 FALLO sube a una parcela de otro proyecto; '; exception when others then r := r || '1 ok; '; end;
  begin perform obra_foto_registra('1cd031f2-c7da-455e-975f-c4e8708e36fb', u1, pth, null); r := r || '2 FALLO sube sin la herramienta obra; '; exception when others then r := r || '2 ok; '; end;
  begin perform obra_foto_registra('dc1961c0-f623-40c2-82c7-baf94b29bac2', u1, u2 || '/' || gen_random_uuid() || '.jpg', null); r := r || '3 FALLO ruta en carpeta de otra parcela; '; exception when others then r := r || '3 ok; '; end;
  f := obra_foto_registra('dc1961c0-f623-40c2-82c7-baf94b29bac2', u1, pth, 'Losa');
  r := r || '4 registra en su parcela ok (creado_por=' || (select creado_por from obra_fotos where id = f) || '); ';
  begin perform obra_foto_registra('dc1961c0-f623-40c2-82c7-baf94b29bac2', u1, pth, 'otra vez'); r := r || '5 FALLO registra la misma ruta dos veces; '; exception when others then r := r || '5 ok; '; end;
  begin perform obra_foto_borra('dc1961c0-f623-40c2-82c7-baf94b29bac2', fajena); r := r || '6 FALLO borra una foto de otro proyecto; '; exception when others then r := r || '6 ok; '; end;
  reset role;
  perform set_config('request.jwt.claims', O, true);
  set local role authenticated;
  r := r || '7 obra_puede suya=' || obra_puede(u1)::text || ' ajena=' || obra_puede(u2)::text || '; ';
  perform obra_foto_cambia(f, '{"visible":false,"titulo":"Losa terminada"}');
  r := r || '8 cambia visible/título ok (' || (select visible::text || '/' || titulo from obra_fotos where id = f) || '); ';
  begin perform obra_foto_cambia(f, jsonb_build_object('unidad_id', u2)); r := r || '9 FALLO mueve la foto a una parcela ajena; '; exception when others then r := r || '9 ok; '; end;
  begin perform obra_foto_cambia(f, '{"path":"x/y.jpg"}'); r := r || '10 FALLO cambia el path; '; exception when others then r := r || '10 ok; '; end;
  begin perform obra_foto_cambia(fajena, '{"visible":false}'); r := r || '11 FALLO cambia una foto ajena; '; exception when others then r := r || '11 ok; '; end;
  r := r || '12 lectura (cierre): ve la suya=' || agente_ve_foto_obra(pth)::text || ' ve la ajena=' || agente_ve_foto_obra((select path from obra_fotos where id = fajena))::text || '; ';
  reset role;
  perform set_config('request.jwt.claims', A, true);
  set local role authenticated;
  begin perform obra_foto_cambia(fajena, '{"visible":false}'); r := r || '13 FALLO agente sin herramienta obra cambia una foto; '; exception when others then r := r || '13 ok; '; end;
  raise exception 'RES: %', r;
end $$;

-- 3. CREATIVIDADES: el rol REAL de Andrea, un admin con las herramientas (Fran) y los ataques de ruta/estado
do $$
declare r text := ''; id1 uuid := gen_random_uuid(); id2 uuid := gen_random_uuid(); e1 text; e2 text; pz text; j jsonb; fo uuid; mo uuid; ap uuid;
begin
  e1 := id1 || '/estado-1.json'; pz := id1 || '/portada-1.png'; e2 := id2 || '/estado-1.json';
  insert into storage.objects (bucket_id, name, metadata) values ('creatividades', e1, '{"size": 10}'), ('creatividades', pz, '{"size": 10}'),
    ('creatividades', e2, '{"size": 10}'), ('creatividades', id1 || '/pieza-1.png', '{"size": 10}');
  select id into fo from deck_fotos limit 1;
  select id into mo from modelos limit 1;
  select id into ap from creatividades where estado <> 'borrador' limit 1;
  set local role service_role;
  begin perform creatividad_guarda('da378aad-9477-42ce-b349-c2d7ced8f65a', id1, 'dossier', '{"titulo":"Dossier Andrea"}', e1);
    r := r || '1 FALLO Andrea (sin la herramienta Dossier) crea un dossier; ';
  exception when others then r := r || '1 Andrea rechazada con «' || left(sqlerrm, 60) || '…» ok; '; end;
  begin perform creatividad_guarda('24257595-aee2-4daa-8170-d268f46b9981', id1, 'pieza', '{"titulo":"x"}', e1); r := r || '2 FALLO admin sin la herramienta crea una pieza; '; exception when others then r := r || '2 ok; '; end;
  j := creatividad_guarda('fef30aea-3ab2-43be-ad1c-7b6acdbe0c83', id1, 'dossier', '{"titulo":"Dossier prueba","formato":"A4"}', e1, null, pz,
                          array_remove(array[fo], null), array_remove(array[mo], null));
  r := r || '3 Fran crea dossier ok (estado=' || (j->>'estado') || ', creado_por=Fran ' || ((j->>'creado_por') = 'fef30aea-3ab2-43be-ad1c-7b6acdbe0c83')::text
        || ', fotos=' || (select count(*) from creatividad_fotos where creatividad_id = id1) || ', modelos=' || (select count(*) from creatividad_modelos where creatividad_id = id1) || '); ';
  begin perform creatividad_guarda('fef30aea-3ab2-43be-ad1c-7b6acdbe0c83', id1, 'dossier', '{}', e1, id1 || '/pieza-1.png'); r := r || '4 FALLO PNG de pieza en un dossier; '; exception when others then r := r || '4 ok; '; end;
  begin perform creatividad_guarda('fef30aea-3ab2-43be-ad1c-7b6acdbe0c83', id1, 'dossier', '{}', e2); r := r || '5 FALLO estado de la carpeta de otra creatividad; '; exception when others then r := r || '5 ok; '; end;
  begin perform creatividad_guarda('fef30aea-3ab2-43be-ad1c-7b6acdbe0c83', id1, 'dossier', '{}', id1 || '/estado-99.json'); r := r || '6 FALLO estado que no se ha subido; '; exception when others then r := r || '6 ok; '; end;
  begin perform creatividad_guarda('fef30aea-3ab2-43be-ad1c-7b6acdbe0c83', id1, 'pieza', '{}', e1); r := r || '7 FALLO cambia el tipo; '; exception when others then r := r || '7 ok; '; end;
  begin perform creatividad_guarda('fef30aea-3ab2-43be-ad1c-7b6acdbe0c83', id1, 'dossier', '{"estado":"aprobada"}', e1); r := r || '8 FALLO se aprueba sola por los datos; '; exception when others then r := r || '8 ok; '; end;
  begin perform creatividad_guarda('fef30aea-3ab2-43be-ad1c-7b6acdbe0c83', id1, 'dossier', '{}', e1, null, null, array[gen_random_uuid()]); r := r || '9 FALLO foto inexistente; '; exception when others then r := r || '9 ok; '; end;
  r := r || '10 enlaces intactos tras el fallo: fotos=' || (select count(*) from creatividad_fotos where creatividad_id = id1) || '; ';
  if ap is not null then
    begin perform creatividad_guarda('fef30aea-3ab2-43be-ad1c-7b6acdbe0c83', ap, null, '{"titulo":"cambio"}', ap || '/estado-1.json');
      r := r || '11 FALLO edita una creatividad que ya no es borrador; ';
    exception when others then r := r || '11 «' || left(sqlerrm, 70) || '…» ok; '; end;
  end if;
  reset role;
  perform set_config('request.jwt.claims', '{"sub":"fef30aea-3ab2-43be-ad1c-7b6acdbe0c83","email":"fran.mg@lawangproperties.com","role":"authenticated"}', true);
  set local role authenticated;
  begin perform creatividad_guarda('fef30aea-3ab2-43be-ad1c-7b6acdbe0c83', id2, 'dossier', '{}', e2); r := r || '12 FALLO el navegador guarda sin la edge; '; exception when others then r := r || '12 ok; '; end;
  raise exception 'RES: %', r;
end $$;

-- 4. EL RESTO: comunicados, soporte, solicitudes, copias del asistente, bancos
do $$
declare r text := ''; c jsonb; h record; ct uuid; n bigint; q record; cb text; p2 uuid;
  A text := '{"sub":"1cd031f2-c7da-455e-975f-c4e8708e36fb","email":"dortegag@gmail.com","role":"authenticated"}';
  ADM text := '{"sub":"24257595-aee2-4daa-8170-d268f46b9981","email":"p@pabloglobal.es","role":"authenticated"}';
begin
  select h2.id, h2.client_id, c2.propietario into h from hilo_soporte h2 join clients c2 on c2.id = h2.client_id limit 1;
  select id into p2 from proyectos order by nombre desc limit 1;
  -- el agente, acotado a un proyecto donde no tiene contratos, y sin ser dueño del comprador del ticket
  update usuarios set proyectos = array[p2] where user_id = '1cd031f2-c7da-455e-975f-c4e8708e36fb';
  select c3.id into ct from contratos c3 where c3.creado_por is distinct from 'dortegag@gmail.com' limit 1;   -- un agente solo ve los suyos
  select * into q from bot_consultas where preguntado_por <> 'dortegag@gmail.com' limit 1;
  select clave into cb from cuentas_bancarias where es_propia is true and es_escrow is not true order by clave limit 1;
  perform set_config('request.jwt.claims', A, true);
  set local role authenticated;
  begin perform comunicado_guarda(null, '{"asunto":"x","cuerpo":"y"}'); r := r || '1 FALLO agente escribe un comunicado; '; exception when others then r := r || '1 ok; '; end;
  if h.id is not null then
    begin perform hilo_soporte_estado(h.id, 'cerrado'); r := r || '2 FALLO estado fuera de lista; '; exception when others then r := r || '2 ok; '; end;
    if h.propietario is distinct from 'dortegag@gmail.com' then
      begin perform hilo_soporte_estado(h.id, 'resuelto'); r := r || '3 FALLO agente cierra el ticket de un comprador que no ve; '; exception when others then r := r || '3 ok (' || left(sqlerrm, 40) || '); '; end;
    end if;
  end if;
  if ct is not null then
    begin perform solicitud_cambio_pide('borrar_operacion', ct, null, 'borrar', null); r := r || '4 FALLO pide borrar una operación que no ve; '; exception when others then r := r || '4 ok (' || left(sqlerrm, 40) || '); '; end;
  end if;
  n := solicitud_cambio_pide('manual', null, null, null, 'Prueba de aviso manual');
  r := r || '5 petición manual SC-' || n || ' ok (pedido_por=el agente ' || ((select pedido_por from solicitudes_cambio where numero = n) = '1cd031f2-c7da-455e-975f-c4e8708e36fb')::text || '); ';
  begin perform solicitud_cambio_pide('inventada', null, null, 'x', 'x'); r := r || '6 FALLO acción inventada; '; exception when others then r := r || '6 ok; '; end;
  if q.id is not null then
    begin perform bot_respuesta_copiada(q.id, 'texto'); r := r || '7 FALLO copia una consulta de otro; '; exception when others then r := r || '7 ok; '; end;
  end if;
  begin perform banco_perfil_guarda(cb, '{"fecha":1}'); r := r || '8 FALLO agente guarda un perfil de banco; '; exception when others then r := r || '8 ok; '; end;
  reset role;
  perform set_config('request.jwt.claims', ADM, true);
  set local role authenticated;
  c := comunicado_guarda(null, '{"asunto":"Prueba B5","cuerpo":"Cuerpo de prueba"}');
  r := r || '9 admin crea comunicado ok (creado_por=Pablo ' || ((c->>'creado_por') = '24257595-aee2-4daa-8170-d268f46b9981')::text || '); ';
  begin perform comunicado_guarda((c->>'id')::uuid, '{"cta_url":"https://evil.example.com","cta_texto":"Clic"}'); r := r || '10 FALLO enlace fuera de la lista blanca; '; exception when others then r := r || '10 ok; '; end;
  begin perform comunicado_guarda((c->>'id')::uuid, '{"enviado_en":"2026-01-01"}'); r := r || '11 FALLO marca como enviado; '; exception when others then r := r || '11 ok; '; end;
  perform comunicado_borra((c->>'id')::uuid);
  r := r || '12 borrador borrado=' || (not exists (select 1 from comunicados where id = (c->>'id')::uuid))::text || '; ';
  begin perform banco_perfil_guarda(cb, '{"fecha":1}'); r := r || '13 FALLO admin sin la herramienta bancos guarda perfil; '; exception when others then r := r || '13 ok; '; end;
  reset role;
  perform set_config('request.jwt.claims', '{"sub":"45d014eb-46f2-4770-87a7-69bbd08a44ae","email":"jvr.cervantes@gmail.com","role":"authenticated"}', true);
  set local role authenticated;
  begin perform banco_perfil_guarda(cb, '{"fecha":1,"css":"x"}'); r := r || '14 FALLO clave desconocida en el mapeo; '; exception when others then r := r || '14 ok; '; end;
  begin perform banco_perfil_guarda(cb, '{"fecha":"<img>"}'); r := r || '15 FALLO columna no numérica; '; exception when others then r := r || '15 ok; '; end;
  if cb is null then r := r || '16 (no hay cuenta propia no escrow para probar); '; raise exception 'RES: %', r; end if;
  perform banco_perfil_guarda(cb, '{"fecha":0,"concepto":2,"importe":3,"formatoFecha":"dd/mm/yyyy","monedaFija":"IDR"}');
  r := r || '16 super admin guarda perfil ok (actualizado_por=' || ((select actualizado_por from bancos_perfiles where cuenta_clave = cb) = '45d014eb-46f2-4770-87a7-69bbd08a44ae')::text || '); ';
  raise exception 'RES: %', r;
end $$;

-- 5. REASIGNAR AUTOR (el botón roto desde el 26-sep) y JUSTIFICANTES DE GASTO
do $$
declare r text := ''; cb uuid; cl uuid; f uuid; fa text; n0 int; n1 int; j jsonb; g uuid; soc text; cat text; pth text;
  ADM text := '{"sub":"24257595-aee2-4daa-8170-d268f46b9981","email":"p@pabloglobal.es","role":"authenticated"}';
  SUP text := '{"sub":"45d014eb-46f2-4770-87a7-69bbd08a44ae","email":"jvr.cervantes@gmail.com","role":"authenticated"}';
begin
  select id into cb from contratos where bloqueado limit 1;
  select id into cl from contratos where not coalesce(bloqueado, false) limit 1;
  select id, creado_por into f, fa from facturas where creado_por is not null and creado_por <> 'fran.mg@lawangproperties.com' limit 1;
  perform set_config('request.jwt.claims', ADM, true);
  set local role authenticated;
  begin perform reasigna_autor('facturas', f, 'fran.mg@lawangproperties.com', 'prueba'); r := r || '1 FALLO un admin (no super) reasigna; '; exception when others then r := r || '1 ok; '; end;
  begin insert into correcciones_datos (tabla, fila_id, campo, motivo) values ('facturas', f, 'creado_por', 'falsa');
    r := r || '2 (antes del cierre) el navegador aún escribe en correcciones_datos — lo quita el cierre; ';
  exception when others then r := r || '2 ok (cerrado); '; end;
  reset role;
  perform set_config('request.jwt.claims', SUP, true);
  set local role authenticated;
  begin perform reasigna_autor('usuarios', f, 'fran.mg@lawangproperties.com', 'prueba'); r := r || '3 FALLO tabla fuera de la lista; '; exception when others then r := r || '3 ok; '; end;
  begin perform reasigna_autor('facturas', f, null, 'prueba'); r := r || '4 FALLO autor null; '; exception when others then r := r || '4 ok; '; end;
  begin perform reasigna_autor('facturas', f, 'nadie@ejemplo.com', 'prueba'); r := r || '5 FALLO autor que no es del equipo; '; exception when others then r := r || '5 ok; '; end;
  begin perform reasigna_autor('facturas', f, 'fran.mg@lawangproperties.com', 'x'); r := r || '6 FALLO sin motivo; '; exception when others then r := r || '6 ok; '; end;
  if cb is not null then
    begin perform reasigna_autor('contratos', cb, 'fran.mg@lawangproperties.com', 'prueba de bloqueo'); r := r || '7 FALLO reasigna un contrato bloqueado; '; exception when others then r := r || '7 ok; '; end;
  end if;
  select count(*) into n0 from correcciones_datos where fila_id = f;
  j := reasigna_autor('facturas', f, 'FRAN.MG@lawangproperties.com', 'prueba de reasignar');
  select count(*) into n1 from correcciones_datos where fila_id = f;
  r := r || '8 factura ' || coalesce(fa, '?') || '→' || (select creado_por from facturas where id = f) || ', traza +' || (n1 - n0) || case when n1 = n0 + 1 and (select creado_por from facturas where id = f) = 'fran.mg@lawangproperties.com' then ' ok; ' else ' FALLO; ' end;
  if cl is not null then
    j := reasigna_autor('contratos', cl, 'fran.mg@lawangproperties.com', 'prueba contrato');
    r := r || '9 contrato sin bloquear reasignado ok; ';
  end if;
  reset role;
  -- justificante de gasto: un gasto de prueba (no hay ninguno en producción el 27-sep)
  select clave into soc from sociedades limit 1;
  select categoria into cat from (select 'otros'::text categoria) x;
  begin
    insert into gastos (sociedad, categoria, concepto, fecha, base) values (soc, cat, 'prueba b4', current_date, 10) returning id into g;
  exception when others then r := r || '10 (no se pudo crear el gasto de prueba: ' || left(sqlerrm, 80) || '); '; end;
  if g is not null then
    pth := g || '/' || gen_random_uuid() || '.pdf';
    insert into storage.objects (bucket_id, name, metadata) values ('gastos', pth, '{"size": 10}');
    set local role service_role;
    begin perform gasto_justificante_registra('24257595-aee2-4daa-8170-d268f46b9981', g, pth, 'f.pdf'); r := r || '11 FALLO admin sin la herramienta gastos; '; exception when others then r := r || '11 ok; '; end;
    begin perform gasto_justificante_registra('fef30aea-3ab2-43be-ad1c-7b6acdbe0c83', g, gen_random_uuid() || '/' || gen_random_uuid() || '.pdf', 'f.pdf'); r := r || '12 FALLO ruta de otro gasto; '; exception when others then r := r || '12 ok; '; end;
    perform gasto_justificante_registra('fef30aea-3ab2-43be-ad1c-7b6acdbe0c83', g, pth, 'factura.pdf');
    r := r || '13 Fran anota el justificante ok (' || (select jsonb_array_length(justificantes) from gastos where id = g) || '); ';
    reset role;
    update gastos set estado = 'anulado', anulado_motivo = 'prueba' where id = g;
    set local role service_role;
    begin perform gasto_justificante_registra('fef30aea-3ab2-43be-ad1c-7b6acdbe0c83', g, pth, 'otra.pdf'); r := r || '14 FALLO justificante en gasto anulado; '; exception when others then r := r || '14 ok; '; end;
  end if;
  raise exception 'RES: %', r;
end $$;

-- 6. Superficie: las RPC solo-edge no las ejecuta nadie más que service_role (proacl, no has_function_privilege)
do $$
declare r text := ''; f record;
begin
  for f in select p.proname, coalesce(p.proacl::text, '(por defecto: PUBLIC)') acl from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('documento_proyecto_registra', 'documento_proyecto_borra', 'obra_foto_registra', 'obra_foto_borra',
                                'gasto_justificante_registra', 'creatividad_guarda', '_lw_si_no', '_creatividad_sin_permiso') loop
    r := r || f.proname || case when f.acl ~ '(^|[{,])=X' or f.acl ~ 'authenticated=' or f.acl ~ 'anon=' or f.acl like '(por defecto%' then ' FALLO ' || f.acl else ' ok' end || '; ';
  end loop;
  raise exception 'RES: %', r;
end $$;

-- 7. (tras el cierre 20260927153000) Escritura directa cerrada: como agente y como admin, insert/update/delete sobre
-- documentos_proyecto, obra_fotos, creatividades, creatividad_fotos, creatividad_modelos, comunicados, hilo_soporte,
-- solicitudes_cambio, bot_respuestas_copiadas, bancos_perfiles y correcciones_datos falla (privilegio o policy), y
-- subir/borrar en los buckets documentacion, obra, creatividades y gastos también. Mirar `relacl` Y
-- `information_schema.column_privileges` (hay grants por columna) de cada tabla: authenticated solo con SELECT.

-- 7. (consulta de Seguridad, 27-sep) Un documento YA publicado en el dosier público no lo cambia un agente
do $$
declare r text := ''; d record; u record; su uuid;
begin
  select user_id into su from usuarios where rol='super_admin' and activo limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',su,'role','authenticated')::text, true);
  select dp.id, dp.proyecto, dp.proyecto_id, dp.titulo into d from documentos_proyecto dp where dp.publicado_investor_deck and not dp.general limit 1;
  select us.user_id, us.email into u from usuarios us where us.activo and us.rol='agente' limit 1;
  update usuarios set herramientas = array_append(herramientas,'documentacion'), proyectos = array[d.proyecto_id] where user_id=u.user_id;
  perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'email',u.email,'role','authenticated')::text, true);
  set local role authenticated;
  begin perform public.documento_proyecto_guarda(d.id, jsonb_build_object('titulo', d.titulo || ' X')); r := r||'1 FALLO agente cambia un publicado; ';
  exception when others then r := r||'1 ok; '; end;
  begin perform public.documento_proyecto_guarda(d.id, jsonb_build_object('visible_portal', true)); r := r||'2 ok (lo no público sigue); ';
  exception when others then r := r||'2 FALLO: '||left(sqlerrm,60)||'; '; end;
  raise exception 'RES: %', r;
end $$;

-- 8. (revisor, 27-sep) Un admin da de alta en «Lawang (general)»: nace general=true y un agente con documentación lo lee
do $$
declare r text := ''; v uuid; a record; ag record; su uuid; n int;
begin
  select user_id, email into a from usuarios where rol='admin' and activo and 'documentacion' = any(herramientas) limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',a.user_id,'email',a.email,'role','authenticated')::text, true);
  set local role authenticated;
  v := public.documento_proyecto_guarda(null, '{"proyecto":"Lawang (general)","titulo":"prueba general","url":"https://example.com/x"}');
  reset role;
  r := r || '1 general=' || (select general::text from documentos_proyecto where id=v) || ' (true = ok); ';
  select user_id into su from usuarios where rol='super_admin' and activo limit 1;
  select user_id, email into ag from usuarios where activo and rol='agente' limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',su,'role','authenticated')::text, true);
  update usuarios set herramientas = array_append(herramientas,'documentacion') where user_id=ag.user_id and not ('documentacion' = any(herramientas));
  perform set_config('request.jwt.claims', json_build_object('sub',ag.user_id,'email',ag.email,'role','authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from documentos_proyecto where id=v;
  r := r || '2 agente lo lee=' || n || ' (1 = ok)';
  raise exception 'RES: %', r;
end $$;
