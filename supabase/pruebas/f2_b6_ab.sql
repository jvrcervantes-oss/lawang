-- A/B de las PUERTAS DE ESCRITURA del BLOQUE 6 para los 34 usuarios reales (8-oct-2026).
-- Cada usuario (JWT con email) llama, con argumentos de prueba, a cada funcion que el bloque convirtio: A = el texto NUEVO de la funcion, B = el texto ANTERIOR (se devuelve en la misma transaccion con los parches
-- de la reversion, SOLO funciones: las policies se comparan con f2_b6_foto.sql). Cada llamada va en una subtransaccion que se deshace, asi las llamadas no se pisan. Se compara el sqlstate de cada una:
-- 'ok' = la llamada llego al final. Debe dar DIFERENCIAS=0: los 34 se comportan exactamente igual. Termina en raise (sin rastro).
-- destructivo-ok: solo ensayo; las llamadas y los parches se deshacen con el raise final
create or replace function pg_temp.parchea(p_f regprocedure, p_old text, p_new text, p_n int default 1) returns void language plpgsql as $f$
declare v text; v_c int;
begin
  v := pg_get_functiondef(p_f);
  v_c := (length(v) - length(replace(v, p_old, ''))) / length(p_old);
  if v_c <> p_n then
    raise exception 'reversion f2_b6: «%» aparece % veces en %, esperaba %', p_old, v_c, p_f, p_n;
  end if;
  execute replace(v, p_old, p_new);
end $f$;


create temp table ab_res (fase text, usuario text, n int, res text);
create function pg_temp.pr(p_uid uuid, p_email text, p_sql text, p_modo text) returns text language plpgsql as $f$
declare got text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role',case when p_modo = 'svc' then 'service_role' else 'authenticated' end,'email',p_email)::text, true);
  execute case when p_modo = 'svc' then 'set local role service_role' else 'set local role authenticated' end;
  begin
    execute p_sql;
    raise exception 'ab_ok' using errcode = 'P0099';
  exception when others then got := case when sqlstate = 'P0099' then 'ok' else sqlstate end;
  end;
  reset role;
  return got;
end $f$;
do $t$
declare
  u record; pr text[] := '{}'; md text[] := '{}'; q text; i int; ph text; res text; dif int;
  pl uuid; ps uuid; pk uuid; p uuid; fql uuid; fqs uuid; fqk uuid; fol uuid; fos uuid; fom uuid; vl record; ml uuid[]; sl text; sl_ver timestamptz;
  cl uuid; cs uuid; dl uuid; ds uuid; ul uuid; us uuid; mod_l uuid;
begin
  select p.id into pl from public.proyectos p where p.empresa='lawang' and exists (select 1 from public.deck_faq f where f.proyecto_id=p.id) and exists (select 1 from public.deck_fotos f where f.proyecto_id=p.id and f.ambito='proyecto') and exists (select 1 from public.modelos_villa v where v.proyecto_id=p.id) and exists (select 1 from public.documentos_proyecto d where d.proyecto_id=p.id and not d.general) and exists (select 1 from public.unidades x where x.proyecto_id=p.id) order by p.nombre limit 1;
  select p.id into ps from public.proyectos p where p.empresa='sandal_woods' and exists (select 1 from public.deck_faq f where f.proyecto_id=p.id) and exists (select 1 from public.deck_fotos f where f.proyecto_id=p.id and f.ambito='proyecto') and exists (select 1 from public.documentos_proyecto d where d.proyecto_id=p.id and not d.general) and exists (select 1 from public.unidades x where x.proyecto_id=p.id) order by p.nombre limit 1;
  select p.id into pk from public.proyectos p where p.empresa is null and exists (select 1 from public.deck_faq f where f.proyecto_id=p.id) order by p.nombre limit 1;
  select id into fql from public.deck_faq where proyecto_id=pl order by id limit 1;
  select id into fqs from public.deck_faq where proyecto_id=ps order by id limit 1;
  select id into fqk from public.deck_faq where proyecto_id=pk order by id limit 1;
  select id into fol from public.deck_fotos where proyecto_id=pl and ambito='proyecto' order by id limit 1;
  select id into fos from public.deck_fotos where proyecto_id=ps and ambito='proyecto' order by id limit 1;
  select id into fom from public.deck_fotos where ambito='modelo' order by id limit 1;
  select * into vl from public.modelos_villa where proyecto_id=pl and modelo_id is not null order by id limit 1;
  select array_agg(modelo_id) into ml from public.modelos_villa where proyecto_id=pl and modelo_id is not null;
  select f.slug, f.actualizado_en into sl, sl_ver from public.fichas_publicas f join public.proyectos p on p.id=f.proyecto_id where p.empresa='lawang' order by f.slug limit 1;
  select id into dl from public.documentos_proyecto where proyecto_id=pl and not general order by id limit 1;
  select id into ds from public.documentos_proyecto where proyecto_id=ps and not general order by id limit 1;
  select id into ul from public.unidades where proyecto_id=pl order by id limit 1;
  select id into us from public.unidades where proyecto_id=ps order by id limit 1;
  mod_l := vl.modelo_id;
  cl := gen_random_uuid(); cs := gen_random_uuid();
  insert into public.creatividades (id, tipo, titulo, proyecto_id, estado_path) values (cl, 'pieza', 'AB Lawang', pl, cl::text || '/estado-1.json');
  insert into public.creatividades (id, tipo, titulo, proyecto_id, estado_path) values (cs, 'pieza', 'AB Sandal', ps, cs::text || '/estado-1.json');

  foreach p in array array[pl, ps, pk] loop
    pr := pr || (format('select public.deck_config_guarda(%L, ''{"titulo":{"en":"A"},"meta_desc":{"en":"B"}}''::jsonb)', p))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.deck_faq_guarda(null, %L, ''{"pregunta":{"es":"p","en":"p"},"respuesta":{"es":"r","en":"r"}}''::jsonb)', p))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.deck_prevision_guarda(%L, %L, null, null)', p, mod_l))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.modelos_proyecto_fija(%L, %L::uuid[])', p, ml))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.ficha_publica_lee(%L)', p))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.obra_contratos_afectados(%L, ''x'', ''x'', ''x'')', p))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.obra_datos_cobro(%L, ''x'', ''x'', ''x'')', p))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.obra_confirmar_avance(%L, ''x'', ''x'', ''x'', 0, null, null)', p))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.dossier_datos(%L, %L::uuid[])', p, ml))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.documento_proyecto_puede(%L)', p))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.agente_ve_proyecto_obra(%L)', p))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.deck_transicion_empieza(%L, %L, true)', '@@UID@@', p))::text; md := md || 'svc'::text;
    pr := pr || (format('select public.investor_deck_activa_como(%L, %L, true)', '@@UID@@', p))::text; md := md || 'svc'::text;
    pr := pr || (format('select public.deck_foto_registra(%L, ''proyecto'', %L, ''x'', ''x'')', '@@UID@@', p))::text; md := md || 'svc'::text;
    pr := pr || (format('select public.documento_proyecto_registra(%L, %L, ''x'', null)', '@@UID@@', p))::text; md := md || 'svc'::text;
    pr := pr || (format('select public.creatividad_guarda(%L, gen_random_uuid(), ''pieza'', jsonb_build_object(''titulo'',''x'',''proyecto_id'',%L::text), null, null, null, null, null)', '@@UID@@', p))::text; md := md || 'svc'::text;
  end loop;
  foreach p in array array[fql, fqs, fqk] loop
    pr := pr || (format('select public.deck_faq_borra(%L)', p))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.deck_faq_guarda(%L, %L, ''{"orden": 77}''::jsonb)', p, pl))::text; md := md || 'auth'::text;
  end loop;
  foreach p in array array[fol, fos, fom] loop
    pr := pr || (format('select public.deck_foto_cambia(%L, ''{"pie":{"en":"x"}}''::jsonb)', p))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.deck_foto_mueve(%L, 1)', p))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.deck_foto_borra(%L, %L, true)', '@@UID@@', p))::text; md := md || 'svc'::text;
  end loop;
  pr := pr || (format('select public.deck_foto_fijar_vista(%L, null)', fom))::text; md := md || 'auth'::text;
  pr := pr || (format('select public.deck_foto_registra(%L, ''modelo'', %L, ''x'', ''x'')', '@@UID@@', mod_l))::text; md := md || 'svc'::text;
  pr := pr || (format('select public.ficha_publica_guarda(%L, ''{"orden": 5}''::jsonb, %L)', sl, sl_ver))::text; md := md || 'auth'::text;
  pr := pr || ('select public.ficha_publica_guarda(''ficha-nueva-ab'', ''{"linea":"villa","region_key":"bali"}''::jsonb, null)')::text; md := md || 'auth'::text;
  pr := pr || (format('select public.modelo_precios_guarda(%L, jsonb_build_object(''villas'', jsonb_build_array(jsonb_build_object(''id'', %L::text, ''precio'', %L::numeric))))', mod_l, vl.id, vl.precio_construccion))::text; md := md || 'auth'::text;
  pr := pr || (format('select public.modelo_precios_guarda(%L, jsonb_build_object(''base'', 1))', mod_l))::text; md := md || 'auth'::text;
  pr := pr || (format('select public.creatividad_estado(%L, ''pendiente'')', cl))::text; md := md || 'auth'::text;
  pr := pr || (format('select public.creatividad_estado(%L, ''aprobada'')', cl))::text; md := md || 'auth'::text;
  pr := pr || (format('select public.creatividad_estado(%L, ''pendiente'')', cs))::text; md := md || 'auth'::text;
  pr := pr || (format('select public.creatividad_descarga(%L, ''x'')', cl))::text; md := md || 'auth'::text;
  pr := pr || (format('select public.creatividad_descarga(%L, ''x'')', cs))::text; md := md || 'auth'::text;
  pr := pr || ('select public.creatividad_puede_hacer(''pieza'')')::text; md := md || 'auth'::text;
  pr := pr || ('select public.creatividad_puede_hacer(''dossier'')')::text; md := md || 'auth'::text;
  pr := pr || ('select public.creatividad_puede_ver(''pieza'', ''aprobada'')')::text; md := md || 'auth'::text;
  pr := pr || (format('select public.creatividad_guarda(%L, gen_random_uuid(), ''pieza'', jsonb_build_object(''titulo'',''x''), null, null, null, null, null)', '@@UID@@'))::text; md := md || 'svc'::text;
  pr := pr || (format('select public.creatividad_guarda(%L, %L, ''pieza'', jsonb_build_object(''titulo'',''x''), null, null, null, null, null)', '@@UID@@', cs))::text; md := md || 'svc'::text;
  foreach p in array array[dl, ds] loop
    pr := pr || (format('select public.documento_proyecto_guarda(%L, ''{"titulo":"x"}''::jsonb)', p))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.documento_proyecto_guarda(%L, ''{"publicado_investor_deck": true, "confidencial": false}''::jsonb)', p))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.documento_proyecto_borra(%L, %L, true)', '@@UID@@', p))::text; md := md || 'svc'::text;
  end loop;
  foreach p in array array[ul, us] loop
    pr := pr || (format('select public.obra_puede(%L)', p))::text; md := md || 'auth'::text;
    pr := pr || (format('select public.obra_actualizar(%L, ''x'', current_date)', p))::text; md := md || 'auth'::text;
  end loop;
  pr := pr || ('select * from public.plantillas_uso()')::text; md := md || 'auth'::text;

  foreach ph in array array['A', 'B'] loop
    if ph = 'B' then
      reset role;
      perform pg_temp.parchea('privado.creatividad_ve_fichero(text)'::regprocedure,
  $q$and public.creatividad_puede_ver(c.tipo, c.estado)
       and (not public.alcance_restringido() or (c.proyecto_id is not null and public.proyecto_en_alcance(c.proyecto_id)))$q$,
  $q$and public.creatividad_puede_ver(c.tipo, c.estado)$q$);
      perform pg_temp.parchea('public.plantillas_uso()'::regprocedure,
  $q$where public.es_super_admin_de(public._empresa_de_contrato_int(ct.id))$q$,
  $q$where public.es_super_admin()$q$);
      perform pg_temp.parchea('public.agente_ve_proyecto_obra(uuid)'::regprocedure,
  $q$public._puede_herr_o_super_empresa('obra')$q$,
  $q$public.puede('obra')$q$);
      perform pg_temp.parchea('public.obra_datos_cobro(uuid,text,text,text)'::regprocedure,
  $q$public._puede_herr_o_super_empresa('obra')$q$,
  $q$public.puede('obra')$q$);
      perform pg_temp.parchea('public.obra_contratos_afectados(uuid,text,text,text)'::regprocedure,
  $q$public._puede_herr_o_super_empresa('obra')$q$,
  $q$public.puede('obra')$q$);
      perform pg_temp.parchea('public.obra_confirmar_avance(uuid,text,text,text,integer,text,uuid[])'::regprocedure,
  $q$public._puede_herr_o_super_empresa('obra')$q$,
  $q$public.puede('obra')$q$);
      perform pg_temp.parchea('public.obra_actualizar(uuid,text,date)'::regprocedure,
  $q$and public._puede_herr_o_super_empresa('obra')$q$,
  $q$and puede('obra')$q$);
      perform pg_temp.parchea('public.obra_puede(uuid)'::regprocedure,
  $q$public._puede_herr_o_super_empresa('obra')$q$,
  $q$public.puede('obra')$q$);
      perform pg_temp.parchea('public.documento_proyecto_borra(uuid,uuid,boolean)'::regprocedure,
  $q$if not public._puede_admin_de(public._empresa_de_proyecto_int((select d.proyecto_id from public.documentos_proyecto d where d.id = p_id)), 'documentacion') then$q$,
  $q$if not (public.es_admin() and public.puede('documentacion')) then$q$);
      perform pg_temp.parchea('public.documento_proyecto_registra(uuid,uuid,text,jsonb)'::regprocedure,
  $q$if v_pub and not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto)) then$q$,
  $q$if v_pub and not public.es_admin() then$q$);
      perform pg_temp.parchea('public.documento_proyecto_registra(uuid,uuid,text,jsonb)'::regprocedure,
  $q$public._puede_editar_proyectos() and public._puede_herr_o_super_empresa('documentacion')$q$,
  $q$public._puede_editar_proyectos() and public.puede('documentacion')$q$);
      perform pg_temp.parchea('public.documento_proyecto_guarda(uuid,jsonb)'::regprocedure,
  $q$if p_id is not null and coalesce(v_old.publicado_investor_deck, false) and not (v_admin or public.es_admin_de(public._empresa_de_proyecto_int(v_old.proyecto_id)))$q$,
  $q$if p_id is not null and coalesce(v_old.publicado_investor_deck, false) and not v_admin$q$);
      perform pg_temp.parchea('public.documento_proyecto_guarda(uuid,jsonb)'::regprocedure,
  $q$if v.publicado_investor_deck is distinct from coalesce(v_old.publicado_investor_deck, false) and not (v_admin or public.es_admin_de(public._empresa_de_proyecto_int(v.proyecto_id))) then$q$,
  $q$if v.publicado_investor_deck is distinct from coalesce(v_old.publicado_investor_deck, false) and not v_admin then$q$);
      perform pg_temp.parchea('public.documento_proyecto_guarda(uuid,jsonb)'::regprocedure,
  $q$public._puede_editar_proyectos() and public._puede_herr_o_super_empresa('documentacion')$q$,
  $q$public._puede_editar_proyectos() and public.puede('documentacion')$q$);
      perform pg_temp.parchea('public.documento_proyecto_puede(uuid)'::regprocedure,
  $q$public._puede_editar_proyectos() and public._puede_herr_o_super_empresa('documentacion')$q$,
  $q$public._puede_editar_proyectos() and public.puede('documentacion')$q$);
      perform pg_temp.parchea('public.dossier_datos(uuid,uuid[])'::regprocedure,
  $q$if not (public._puede_herr_o_super_empresa('dossier') or public._puede_herr_o_super_empresa('creatividades')) then$q$,
  $q$if not (public.puede('dossier') or public.puede('creatividades')) then$q$);
      perform pg_temp.parchea('public.creatividad_descarga(uuid,text)'::regprocedure,
  $q$if not found or not public.creatividad_puede_ver(c.tipo, c.estado)
     or (public.alcance_restringido() and (c.proyecto_id is null or not public.proyecto_en_alcance(c.proyecto_id))) then$q$,
  $q$if not found or not public.creatividad_puede_ver(c.tipo, c.estado) then$q$);
      perform pg_temp.parchea('public.creatividad_guarda(uuid,uuid,text,jsonb,text,text,text,uuid[],uuid[])'::regprocedure,
  $q$if public.alcance_restringido() and (v_proy is null or not public.proyecto_en_alcance(v_proy)) then
    raise exception 'Esa creatividad tiene que ser de un proyecto de tus empresas' using errcode = '42501';
  end if;
  v_formato := case when p_datos ? 'formato' then nullif(btrim(coalesce(p_datos->>'formato', '')), '') else v.formato end;$q$,
  $q$v_formato := case when p_datos ? 'formato' then nullif(btrim(coalesce(p_datos->>'formato', '')), '') else v.formato end;$q$);
      perform pg_temp.parchea('public.creatividad_estado(uuid,text)'::regprocedure,
  $q$v_admin := public.es_admin_de(public._empresa_de_proyecto_int(c.proyecto_id));$q$,
  $q$v_admin := public.es_admin();$q$);
      perform pg_temp.parchea('public.creatividad_estado(uuid,text)'::regprocedure,
  $q$if not found then raise exception 'No existe esa creatividad.' using errcode = 'P0002'; end if;
  if public.alcance_restringido() and (c.proyecto_id is null or not public.proyecto_en_alcance(c.proyecto_id)) then
    raise exception 'No existe esa creatividad.' using errcode = 'P0002';
  end if;$q$,
  $q$if not found then raise exception 'No existe esa creatividad.' using errcode = 'P0002'; end if;$q$);
      perform pg_temp.parchea('public.creatividad_puede_hacer(text)'::regprocedure,
  $q$public._puede_herr_o_super_empresa('dossier')$q$,
  $q$public.puede('dossier')$q$);
      perform pg_temp.parchea('public.creatividad_puede_hacer(text)'::regprocedure,
  $q$public._puede_herr_o_super_empresa('creatividades')$q$,
  $q$public.puede('creatividades')$q$);
      perform pg_temp.parchea('public.ficha_publica_guarda(text,jsonb,timestamp with time zone)'::regprocedure,
  $q$if not (public.es_admin() or public._ficha_publica_puerta(p_slug, p_cambios)) then$q$,
  $q$if not public.es_admin() then$q$);
      perform pg_temp.parchea('public.ficha_publica_lee(uuid)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then$q$,
  $q$if not public.es_admin() then$q$);
      perform pg_temp.parchea('public.modelo_precios_guarda(uuid,jsonb)'::regprocedure,
  $q$if not (public.es_admin() or public._modelo_precios_puerta_empresa(p_cambios)) then raise exception 'Los precios de los modelos los cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Los precios de los modelos los cambia administración' using errcode = '42501'; end if;$q$);
      perform pg_temp.parchea('public.modelos_proyecto_fija(uuid,uuid[])'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then raise exception 'Qué modelos se construyen en un proyecto lo decide administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Qué modelos se construyen en un proyecto lo decide administración' using errcode = '42501'; end if;$q$);
      perform pg_temp.parchea('public.investor_deck_activa_como(uuid,uuid,boolean)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then raise exception 'solo un admin puede activar/desactivar el investor deck' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'solo un admin puede activar/desactivar el investor deck' using errcode = '42501'; end if;$q$);
      perform pg_temp.parchea('public.deck_transicion_empieza(uuid,uuid,boolean)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then raise exception 'Solo administración abre o cierra un deck' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Solo administración abre o cierra un deck' using errcode = '42501'; end if;$q$);
      perform pg_temp.parchea('public.deck_prevision_guarda(uuid,uuid,jsonb,jsonb)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then raise exception 'La previsión del deck la cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'La previsión del deck la cambia administración' using errcode = '42501'; end if;$q$);
      perform pg_temp.parchea('public.deck_foto_borra(uuid,uuid,boolean)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int((select f.proyecto_id from public.deck_fotos f where f.id = p_id and f.ambito = 'proyecto'))) then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$);
      perform pg_temp.parchea('public.deck_foto_registra(uuid,text,uuid,text,text)'::regprocedure,
  $q$if not (case when p_ambito = 'proyecto' then public.es_admin_de(public._empresa_de_proyecto_int(p_ref)) else public.es_admin() end) then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$);
      perform pg_temp.parchea('public.deck_foto_mueve(uuid,integer)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int((select f.proyecto_id from public.deck_fotos f where f.id = p_id and f.ambito = 'proyecto'))) then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$);
      perform pg_temp.parchea('public.deck_foto_cambia(uuid,jsonb)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int((select f.proyecto_id from public.deck_fotos f where f.id = p_id and f.ambito = 'proyecto'))) then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$);
      perform pg_temp.parchea('public.deck_faq_guarda(uuid,uuid,jsonb)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(coalesce((select f.proyecto_id from public.deck_faq f where f.id = p_id), p_proyecto_id))) then raise exception 'Editar las FAQ del deck exige ser administrador' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Editar las FAQ del deck exige ser administrador' using errcode = '42501'; end if;$q$);
      perform pg_temp.parchea('public.deck_faq_borra(uuid)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int((select f.proyecto_id from public.deck_faq f where f.id = p_id))) then raise exception 'Editar las FAQ del deck exige ser administrador' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Editar las FAQ del deck exige ser administrador' using errcode = '42501'; end if;$q$);
      perform pg_temp.parchea('public.deck_config_guarda(uuid,jsonb)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then raise exception 'Solo un administrador puede editar el Investor Deck' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Solo un administrador puede editar el Investor Deck' using errcode = '42501'; end if;$q$);
    end if;
    for u in select user_id, email from public.usuarios order by email loop
      for i in 1 .. array_length(pr, 1) loop
        q := replace(pr[i], '@@UID@@', u.user_id::text);
        res := pg_temp.pr(u.user_id, u.email, q, md[i]);
        insert into ab_res values (ph, u.email, i, res);
      end loop;
    end loop;
  end loop;
  select count(*) into dif from ab_res a join ab_res b on b.fase = 'B' and b.usuario = a.usuario and b.n = a.n where a.fase = 'A' and a.res is distinct from b.res;
  raise exception E'AB-B6 usuarios=% llamadas=% DIFERENCIAS=%\n%', (select count(distinct usuario) from ab_res), array_length(pr, 1),
    dif, (select string_agg(a.usuario || ' #' || a.n || ' ' || a.res || ' -> ' || b.res, E'\n') from ab_res a join ab_res b on b.fase = 'B' and b.usuario = a.usuario and b.n = a.n where a.fase = 'A' and a.res is distinct from b.res);
end $t$;
