-- PRUEBA — ficheros subidos en el investor deck (20260928184500_deck_documentos_subidos, 28-sep-2026).
-- Se ejecuta entera con execute_sql (MCP) o psql como postgres. NO ESCRIBE NADA: cada caso cambia la fila (o su
-- objeto de storage) dentro de un sub-bloque que acaba en excepción, así que Postgres lo deshace; y el bloque entero
-- termina en `raise exception 'RES: …'`. Cada caso debe decir «ok»; un «FALLO» es un documento privado que el
-- público podría descargar, o uno publicado que no le llega.
-- Toma como base un fichero subido (pdf) de un proyecto con el deck abierto, y lo deja publicado y válido ANTES de
-- cada caso, para que cada caso cambie una sola cosa.
do $$
declare r text := ''; d record; v_cerrado text; v_n int; v_old int; v_t text;
begin
  select x.id, x.proyecto, x.path into d from public.documentos_proyecto x
   where x.path ~ '\.pdf$' and x.mime = 'application/pdf' and public.deck_proyecto_abierto(x.proyecto)
     and exists (select 1 from storage.objects o where o.bucket_id = 'documentacion' and o.name = x.path
                 and o.metadata->>'mimetype' = 'application/pdf')
   order by x.publicado_investor_deck desc, x.creado_en desc limit 1;
  if d.id is null then raise exception 'RES: sin fichero pdf en un deck abierto: la prueba no tiene base'; end if;
  select p.nombre into v_cerrado from public.proyectos p where not public.deck_proyecto_abierto(p.nombre) limit 1;

  -- Deja la base válida: publicado, no confidencial, comercial, sin url, tamaño normal.
  update public.documentos_proyecto set publicado_investor_deck = true, confidencial = false, categoria = 'comercial',
         url = null, bytes = greatest(coalesce(bytes, 1), 1) where id = d.id;

  select count(*) into v_n from public.investor_deck_documento_ruta(d.id);
  r := r || '1 base sale por la ruta=' || v_n || (case when v_n = 1 then ' ok; ' else ' FALLO; ' end);
  select count(*) into v_n from public.investor_deck_documentos(d.proyecto) l
   where l.url = 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/deck-documento?id=' || d.id;
  r := r || '2 base sale en la lista con la url de la edge=' || v_n || (case when v_n = 1 then ' ok; ' else ' FALLO; ' end);

  -- Cada caso: un cambio, cuántas filas da la ruta, y se deshace.
  begin update public.documentos_proyecto set confidencial = true where id = d.id;
    select count(*) into v_n from public.investor_deck_documento_ruta(d.id); raise exception '%', v_n;
  exception when others then r := r || '3 confidencial=' || sqlerrm || (case when sqlerrm = '0' then ' ok; ' else ' FALLO; ' end); end;
  begin update public.documentos_proyecto set publicado_investor_deck = false where id = d.id;
    select count(*) into v_n from public.investor_deck_documento_ruta(d.id); raise exception '%', v_n;
  exception when others then r := r || '4 no publicado=' || sqlerrm || (case when sqlerrm = '0' then ' ok; ' else ' FALLO; ' end); end;
  begin update public.documentos_proyecto set categoria = 'faq' where id = d.id;
    select count(*) into v_n from public.investor_deck_documento_ruta(d.id); raise exception '%', v_n;
  exception when others then r := r || '5 faq=' || sqlerrm || (case when sqlerrm = '0' then ' ok; ' else ' FALLO; ' end); end;
  if v_cerrado is not null then
    begin update public.documentos_proyecto set proyecto = v_cerrado where id = d.id;
      select count(*) into v_n from public.investor_deck_documento_ruta(d.id); raise exception '%', v_n;
    exception when others then r := r || '6 deck cerrado=' || sqlerrm || (case when sqlerrm = '0' then ' ok; ' else ' FALLO; ' end); end;
  else r := r || '6 SIN deck cerrado para probar; '; end if;
  begin update public.documentos_proyecto set mime = 'text/html' where id = d.id;
    select count(*) into v_n from public.investor_deck_documento_ruta(d.id); raise exception '%', v_n;
  exception when others then r := r || '7 mime de la fila distinto=' || sqlerrm || (case when sqlerrm = '0' then ' ok; ' else ' FALLO; ' end); end;
  begin update storage.objects set metadata = jsonb_set(metadata, '{mimetype}', '"text/html"')
         where bucket_id = 'documentacion' and name = d.path;
    select count(*) into v_n from public.investor_deck_documento_ruta(d.id); raise exception '%', v_n;
  exception when others then r := r || '8 mime del objeto distinto=' || sqlerrm || (case when sqlerrm = '0' then ' ok; ' else ' FALLO; ' end); end;
  begin update public.documentos_proyecto set bytes = 0 where id = d.id;
    select count(*) into v_n from public.investor_deck_documento_ruta(d.id); raise exception '%', v_n;
  exception when others then r := r || '9 bytes 0=' || sqlerrm || (case when sqlerrm = '0' then ' ok; ' else ' FALLO; ' end); end;
  begin update public.documentos_proyecto set bytes = 52428801 where id = d.id;
    select count(*) into v_n from public.investor_deck_documento_ruta(d.id); raise exception '%', v_n;
  exception when others then r := r || '10 más de 50 MB=' || sqlerrm || (case when sqlerrm = '0' then ' ok; ' else ' FALLO; ' end); end;
  begin update public.documentos_proyecto set path = 'proyectos/x/../../otro.pdf' where id = d.id;
    select count(*) into v_n from public.investor_deck_documento_ruta(d.id); raise exception '%', v_n;
  exception
    when check_violation then r := r || '11 ruta rara: ok (lo impide el check de la tabla); ';
    when others then r := r || '11 ruta rara=' || left(sqlerrm, 40) || (case when sqlerrm = '0' then ' ok; ' else ' FALLO; ' end); end;
  begin update public.documentos_proyecto set url = 'https://drive.google.com/prueba' where id = d.id;
    select count(*) into v_n from public.investor_deck_documento_ruta(d.id);
    select count(*) into v_old from public.investor_deck_documentos(d.proyecto) l where l.url = 'https://drive.google.com/prueba';
    raise exception '%/%', v_n, v_old;
  -- La tabla impide fichero Y enlace a la vez (check documentos_proyecto_fichero_o_enlace, 28-sep). Si algún día se
  -- quita, la ruta tiene que seguir dando 0 y la lista el enlace.
  exception
    when check_violation then r := r || '12 con url: ok (lo impide el check de la tabla); ';
    when others then r := r || '12 con url: ruta/lista=' || left(sqlerrm, 40) || (case when sqlerrm = '0/1' then ' ok; ' else ' FALLO; ' end); end;

  -- Los enlaces de Drive: salen los mismos que con la regla de antes (todo el catálogo, no solo este proyecto).
  select count(*) into v_old from public.documentos_proyecto x
   where x.publicado_investor_deck and x.confidencial = false and x.categoria <> 'faq'
     and x.url is not null and x.url <> '' and public.deck_proyecto_abierto(x.proyecto);
  select count(*) into v_n from (select distinct proyecto from public.documentos_proyecto) p
   cross join lateral public.investor_deck_documentos(p.proyecto) l where l.url not like '%/functions/v1/deck-documento?id=%';
  r := r || '13 Drive antes/ahora=' || v_old || '/' || v_n || (case when v_old = v_n then ' ok; ' else ' FALLO; ' end);

  -- Permisos: la lista la ejecuta anon; ruta solo service_role; mime y visible nadie más que su dueño.
  v_t := case when has_function_privilege('anon', 'public.investor_deck_documentos(text)', 'execute') then 'ok' else 'FALLO' end;
  r := r || '14 anon lista ' || v_t || '; ';
  v_t := case when not has_function_privilege('anon', 'public.investor_deck_documento_ruta(uuid)', 'execute')
               and not has_function_privilege('authenticated', 'public.investor_deck_documento_ruta(uuid)', 'execute')
               and has_function_privilege('service_role', 'public.investor_deck_documento_ruta(uuid)', 'execute') then 'ok' else 'FALLO' end;
  r := r || '15 ruta solo service_role ' || v_t || '; ';
  v_t := case when not has_function_privilege('anon', 'public.investor_deck_documento_visible(public.documentos_proyecto)', 'execute')
               and not has_function_privilege('service_role', 'public.investor_deck_documento_visible(public.documentos_proyecto)', 'execute')
               and not has_function_privilege('anon', 'public.investor_deck_documento_mime(text)', 'execute')
               and not has_function_privilege('service_role', 'public.investor_deck_documento_mime(text)', 'execute') then 'ok' else 'FALLO' end;
  r := r || '16 visible y mime cerradas ' || v_t || '; ';

  raise exception 'RES: %', r;
end $$;
