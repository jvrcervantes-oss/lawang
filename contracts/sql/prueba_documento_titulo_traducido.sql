-- PRUEBA — título traducido de enlaces/documentos (20260928220000_documento_titulo_traducido, 28-sep-2026).
-- Se ejecuta entera con execute_sql (MCP) o psql como postgres. NO ESCRIBE NADA: el bloque entero termina en
-- `raise exception 'RES: …'` y Postgres lo deshace. Cada caso debe decir «ok».
-- Actúa como el super admin del owner sobre un enlace publicado en un deck abierto.
do $$
declare r text := ''; d record; v_j jsonb; v_n int; v_sub text;
begin
  select x.id, x.proyecto, x.titulo into d from public.documentos_proyecto x
   where coalesce(x.url, '') <> '' and x.publicado_investor_deck and not x.confidencial and x.categoria <> 'faq'
     and public.deck_proyecto_abierto(x.proyecto)
   order by x.creado_en desc limit 1;
  if d.id is null then raise exception 'RES: sin enlace publicado en un deck abierto: la prueba no tiene base'; end if;
  select a.id::text into v_sub from auth.users a where lower(a.email) = 'jvr.cervantes@gmail.com';
  perform set_config('request.jwt.claims', json_build_object('sub', v_sub, 'email', 'jvr.cervantes@gmail.com', 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- 1 guarda y sanea: espacios fuera, control fuera, vacío fuera
  perform public.documento_proyecto_guarda(d.id, jsonb_build_object('titulo_i18n', jsonb_build_object('en', '  Brochure' || chr(10) || 'EN ', 'id', '')));
  select titulo_i18n into v_j from public.documentos_proyecto where id = d.id;
  r := r || '1 saneo=' || v_j::text || (case when v_j = '{"en": "Brochure EN"}'::jsonb then ' ok; ' else ' FALLO; ' end);

  -- 2 idioma no admitido
  begin perform public.documento_proyecto_guarda(d.id, '{"titulo_i18n":{"fr":"x"}}'); r := r || '2 FALLO acepta fr; ';
  exception when others then r := r || '2 ok; '; end;
  -- 3 no objeto / valor no texto
  begin perform public.documento_proyecto_guarda(d.id, '{"titulo_i18n":"x"}'); r := r || '3a FALLO acepta texto; ';
  exception when others then r := r || '3a ok; '; end;
  begin perform public.documento_proyecto_guarda(d.id, '{"titulo_i18n":{"en":{"a":1}}}'); r := r || '3b FALLO acepta objeto; ';
  exception when others then r := r || '3b ok; '; end;

  -- 4 guardar sin la clave no toca las traducciones
  perform public.documento_proyecto_guarda(d.id, jsonb_build_object('titulo', d.titulo));
  select titulo_i18n into v_j from public.documentos_proyecto where id = d.id;
  r := r || '4 sin clave conserva=' || (case when v_j ? 'en' then 'ok; ' else 'FALLO; ' end);

  -- 5 el deck público la sirve
  reset role;
  select count(*) into v_n from public.investor_deck_documentos(d.proyecto) l where l.titulo_i18n->>'en' = 'Brochure EN';
  r := r || '5 deck sirve titulo_i18n=' || v_n || (case when v_n = 1 then ' ok; ' else ' FALLO; ' end);
  -- 6 permisos del deck: anon sí, authenticated no
  r := r || '6 permisos=' || (case when has_function_privilege('anon', 'public.investor_deck_documentos(text)', 'execute')
       and not has_function_privilege('authenticated', 'public.investor_deck_documentos(text)', 'execute') then 'ok' else 'FALLO' end);
  raise exception 'RES: %', r;
end $$;

-- Casos 7-8: un AGENTE no-admin con Documentación en ese proyecto no cambia la traducción de un documento publicado
-- (regla B4), pero sí puede guardar sin cambiarla (su formulario manda los campos tal cual). Todo en rollback.
do $$
declare r text := ''; d record; u record; v_ok boolean; v_sub text; v_e text;
begin
  select x.id, x.proyecto, x.proyecto_id, x.titulo into d from public.documentos_proyecto x
   where coalesce(x.url, '') <> '' and x.publicado_investor_deck and not x.confidencial and x.categoria <> 'faq'
     and public.deck_proyecto_abierto(x.proyecto) order by x.creado_en desc limit 1;
  update public.documentos_proyecto set titulo_i18n = '{"en":"Brochure EN"}' where id = d.id;
  for u in select a.id::text sub, a.email from public.usuarios us join auth.users a on lower(a.email) = lower(us.email)
            where us.rol not in ('admin', 'super_admin') and us.activo is not false loop
    perform set_config('request.jwt.claims', json_build_object('sub', u.sub, 'email', u.email, 'role', 'authenticated')::text, true);
    begin
      v_ok := public.es_agente() and public.puede('documentacion') and public.puede_proyecto(d.proyecto, d.proyecto_id) and not public.es_admin();
    exception when others then v_ok := false; end;
    if v_ok then v_sub := u.sub; exit; end if;
  end loop;
  if v_sub is null then raise exception 'RES: sin agente no-admin con Documentación en ese proyecto'; end if;
  set local role authenticated;
  begin perform public.documento_proyecto_guarda(d.id, '{"titulo_i18n":{"en":"Otro"}}'); r := r || '7 FALLO no-admin cambia traduccion publicada; ';
  exception when others then v_e := sqlstate; r := r || '7 no-admin cambia=' || v_e || (case when v_e = '42501' then ' ok; ' else ' FALLO; ' end); end;
  begin perform public.documento_proyecto_guarda(d.id, '{"titulo_i18n":{"en":"Brochure EN","id":""}}'); r := r || '8 no-admin guarda sin cambiar ok; ';
  exception when others then r := r || '8 FALLO no-admin guarda sin cambiar: ' || sqlerrm || '; '; end;
  reset role;
  raise exception 'RES: %', r;
end $$;
