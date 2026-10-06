-- PRUEBA — enlace por idioma de documentos para el investor deck (20261006110000_documento_url_por_idioma, 6-oct-2026).
-- Se ejecuta entera con execute_sql (MCP) o psql como postgres. NO ESCRIBE NADA: cada bloque termina en
-- `raise exception 'RES: …'` y Postgres lo deshace. Cada caso debe decir «ok».
-- Actúa como el super admin del owner sobre un enlace publicado en un deck abierto.
do $$
declare r text := ''; d record; v_j jsonb; v_n int; v_sub text; v_e text;
begin
  select x.id, x.proyecto, x.titulo into d from public.documentos_proyecto x
   where coalesce(x.url, '') <> '' and x.publicado_investor_deck and not x.confidencial and x.categoria <> 'faq'
     and public.deck_proyecto_abierto(x.proyecto)
   order by x.creado_en desc limit 1;
  if d.id is null then raise exception 'RES: sin enlace publicado en un deck abierto: la prueba no tiene base'; end if;
  select a.id::text into v_sub from auth.users a where lower(a.email) = 'jvr.cervantes@gmail.com';
  perform set_config('request.jwt.claims', json_build_object('sub', v_sub, 'email', 'jvr.cervantes@gmail.com', 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- 1 guarda y sanea: espacios fuera, vacío fuera
  perform public.documento_proyecto_guarda(d.id, jsonb_build_object('url_i18n', jsonb_build_object('en', '  https://example.com/en.pdf ', 'id', '')));
  select url_i18n into v_j from public.documentos_proyecto where id = d.id;
  r := r || '1 saneo=' || v_j::text || (case when v_j = '{"en": "https://example.com/en.pdf"}'::jsonb then ' ok; ' else ' FALLO; ' end);

  -- 2 idioma no admitido
  begin perform public.documento_proyecto_guarda(d.id, '{"url_i18n":{"fr":"https://x.com/a"}}'); r := r || '2 FALLO acepta fr; ';
  exception when others then r := r || '2 ok; '; end;
  -- 3 no objeto / valor no texto
  begin perform public.documento_proyecto_guarda(d.id, '{"url_i18n":"x"}'); r := r || '3a FALLO acepta texto; ';
  exception when others then r := r || '3a ok; '; end;
  begin perform public.documento_proyecto_guarda(d.id, '{"url_i18n":{"en":{"a":1}}}'); r := r || '3b FALLO acepta objeto; ';
  exception when others then r := r || '3b ok; '; end;
  -- 4 URL sin http(s), con esquema peligroso o con espacio
  begin perform public.documento_proyecto_guarda(d.id, '{"url_i18n":{"en":"ftp://x.com/a"}}'); r := r || '4a FALLO acepta ftp; ';
  exception when others then r := r || '4a ok; '; end;
  begin perform public.documento_proyecto_guarda(d.id, '{"url_i18n":{"id":"javascript:alert(1)"}}'); r := r || '4b FALLO acepta javascript; ';
  exception when others then r := r || '4b ok; '; end;
  begin perform public.documento_proyecto_guarda(d.id, '{"url_i18n":{"id":"https://x.com/a b"}}'); r := r || '4c FALLO acepta espacio; ';
  exception when others then r := r || '4c ok; '; end;

  -- 5 guardar sin la clave no toca los enlaces
  perform public.documento_proyecto_guarda(d.id, jsonb_build_object('titulo', d.titulo));
  select url_i18n into v_j from public.documentos_proyecto where id = d.id;
  r := r || '5 sin clave conserva=' || (case when v_j ? 'en' then 'ok; ' else 'FALLO; ' end);

  -- 6 el deck público la sirve en un enlace
  reset role;
  select count(*) into v_n from public.investor_deck_documentos(d.proyecto) l where l.url_i18n->>'en' = 'https://example.com/en.pdf';
  r := r || '6 deck sirve url_i18n=' || v_n || (case when v_n = 1 then ' ok; ' else ' FALLO; ' end);
  -- 7 permisos: deck → anon sí, authenticated no; guarda → authenticated sí, anon no
  r := r || '7 permisos=' || (case when has_function_privilege('anon', 'public.investor_deck_documentos(text)', 'execute')
       and not has_function_privilege('authenticated', 'public.investor_deck_documentos(text)', 'execute')
       and has_function_privilege('authenticated', 'public.documento_proyecto_guarda(uuid,jsonb)', 'execute')
       and not has_function_privilege('anon', 'public.documento_proyecto_guarda(uuid,jsonb)', 'execute') then 'ok; ' else 'FALLO; ' end);

  -- 8 un documento SUBIDO (con path) no lleva enlaces por idioma, y el deck los devuelve vacíos
  update public.documentos_proyecto set url = null, url_i18n = '{}',
         path = 'proyectos/' || gen_random_uuid() || '/' || gen_random_uuid() || '.pdf' where id = d.id;
  set local role authenticated;
  begin perform public.documento_proyecto_guarda(d.id, '{"url_i18n":{"en":"https://example.com/en.pdf"}}'); r := r || '8a FALLO fichero con enlaces; ';
  exception when others then v_e := sqlstate; r := r || '8a fichero con enlaces=' || v_e || (case when v_e = '22023' then ' ok; ' else ' FALLO; ' end); end;
  reset role;
  select count(*) into v_n from public.investor_deck_documentos(d.proyecto) l where l.url like '%deck-documento%' and l.url_i18n = '{}'::jsonb;
  r := r || '8b deck fichero url_i18n vacio=' || v_n || (case when v_n >= 1 then ' ok' else ' FALLO' end);
  raise exception 'RES: %', r;
end $$;

-- Caso 9: un AGENTE no-admin, manager de ese proyecto y con Documentación, no cambia los enlaces de un documento
-- publicado (regla B4), pero sí puede guardar sin cambiarlos (su formulario manda los campos tal cual). Todo en rollback.
do $$
declare r text := ''; d record; u record; v_ok boolean; v_sub text; v_e text;
begin
  select x.id, x.proyecto, x.proyecto_id, x.titulo into d from public.documentos_proyecto x
   where coalesce(x.url, '') <> '' and x.publicado_investor_deck and not x.confidencial and x.categoria <> 'faq'
     and public.deck_proyecto_abierto(x.proyecto) order by x.creado_en desc limit 1;
  update public.documentos_proyecto set url_i18n = '{"en":"https://example.com/en.pdf"}' where id = d.id;
  for u in select a.id::text sub, a.email from public.usuarios us join auth.users a on lower(a.email) = lower(us.email)
            where us.rol not in ('admin', 'super_admin') and us.activo is not false loop
    perform set_config('request.jwt.claims', json_build_object('sub', u.sub, 'email', u.email, 'role', 'authenticated')::text, true);
    begin
      v_ok := public.es_agente() and public.puede('documentacion') and public.es_manager_de(d.proyecto_id) and not public.es_admin();
    exception when others then v_ok := false; end;
    if v_ok then v_sub := u.sub; exit; end if;
  end loop;
  if v_sub is null then raise exception 'RES: sin agente no-admin con Documentación y manager de ese proyecto'; end if;
  set local role authenticated;
  begin perform public.documento_proyecto_guarda(d.id, '{"url_i18n":{"en":"https://example.com/otro.pdf"}}'); r := r || '9a FALLO no-admin cambia enlace publicado; ';
  exception when others then v_e := sqlstate; r := r || '9a no-admin cambia=' || v_e || (case when v_e = '42501' then ' ok; ' else ' FALLO; ' end); end;
  begin perform public.documento_proyecto_guarda(d.id, '{"url_i18n":{"en":"https://example.com/en.pdf","id":""}}'); r := r || '9b no-admin guarda sin cambiar ok; ';
  exception when others then r := r || '9b FALLO no-admin guarda sin cambiar: ' || sqlerrm || '; '; end;
  reset role;
  raise exception 'RES: %', r;
end $$;
