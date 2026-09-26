-- destructivo-ok: sustituye deck_faq_guarda (create or replace); no toca filas.
-- Frontera bloque 3 (27-sep-2026, LAW-336), autorevisión: el freno de Legal de las FAQ del deck comparaba con el
-- texto guardado aunque NO estuviera publicado (igual que la pantalla): guardar «nominee» sin publicar y
-- publicarlo en un segundo guardado se lo saltaba. Ahora el texto de antes solo cuenta si ya estaba publicado.
create or replace function public.deck_faq_guarda(p_id uuid, p_proyecto_id uuid, p_datos jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_old public.deck_faq%rowtype; k text; v_p jsonb; v_r jsonb; v_orden numeric; v_pub boolean; v_id uuid; l text; v_mal text;
begin
  if not public.es_admin() then raise exception 'Editar las FAQ del deck exige ser administrador' using errcode = '42501'; end if;
  if jsonb_typeof(p_datos) is distinct from 'object' then raise exception 'Datos de la pregunta no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_datos) loop
    if k not in ('pregunta', 'respuesta', 'orden', 'publicado') then raise exception 'Ese dato de la pregunta no se edita desde aquí: %', k using errcode = '22023'; end if;
  end loop;
  if p_id is not null then
    select * into v_old from public.deck_faq f where f.id = p_id for update;
    if not found then raise exception 'Esa pregunta ya no existe: recarga' using errcode = '22023'; end if;
  elsif not exists (select 1 from public.proyectos p where p.id = p_proyecto_id) then
    raise exception 'Ese proyecto no existe' using errcode = '22023';
  end if;
  v_p := case when p_datos ? 'pregunta' then public._lw_idiomas(p_datos->'pregunta', 'La pregunta', 1000) else v_old.pregunta end;
  v_r := case when p_datos ? 'respuesta' then public._lw_idiomas(p_datos->'respuesta', 'La respuesta', 6000) else v_old.respuesta end;
  if not (coalesce(v_p, '{}') ? 'es') or not (coalesce(v_r, '{}') ? 'es') then
    raise exception 'La pregunta y la respuesta en español son obligatorias: es el texto de referencia' using errcode = '22023';
  end if;
  -- la tabla exige `en` (CHECK): si falta, el deck enseña el español en ese idioma — se copia como hasta hoy
  if not v_p ? 'en' then v_p := v_p || jsonb_build_object('en', v_p->>'es'); end if;
  if not v_r ? 'en' then v_r := v_r || jsonb_build_object('en', v_r->>'es'); end if;
  v_orden := case when p_datos ? 'orden' then public._lw_num(p_datos->'orden', 'El orden') else v_old.orden end;
  if v_orden is null then select coalesce(max(f.orden), -1) + 1 into v_orden from public.deck_faq f where f.proyecto_id = coalesce(v_old.proyecto_id, p_proyecto_id); end if;
  if v_orden < 0 or v_orden > 10000 or v_orden <> trunc(v_orden) then raise exception 'El orden no es válido' using errcode = '22023'; end if;
  v_pub := case when p_datos ? 'publicado' then coalesce(public._lw_bool(p_datos->'publicado', 'Publicada'), false) else coalesce(v_old.publicado, false) end;

  if v_pub then
    foreach l in array array['es', 'en', 'id'] loop
      v_mal := public._deck_introduce_prohibido(
        -- solo cuenta como «ya estaba» lo que ya estaba PUBLICADO: guardar sin publicar y publicar después
        -- no puede ser el atajo para saltarse el freno
        case when coalesce(v_old.publicado, false)
             then coalesce(v_old.pregunta->>l, '') || E'\n' || coalesce(v_old.respuesta->>l, '') else '' end,
        coalesce(v_p->>l, '') || E'\n' || coalesce(v_r->>l, ''));
      if v_mal is not null then
        raise exception 'No se puede publicar: el texto introduce % (%). Revisadlo con Legal; si hay que decirlo, guárdala sin publicar.', v_mal, l
          using errcode = '22023';
      end if;
    end loop;
  end if;

  if p_id is null then
    insert into public.deck_faq (proyecto_id, pregunta, respuesta, orden, publicado, creado_por, actualizado_en)
    values (p_proyecto_id, v_p, v_r, v_orden::int, v_pub, (select auth.email()), now())
    returning id into v_id;
    return v_id;
  end if;
  update public.deck_faq set pregunta = v_p, respuesta = v_r, orden = v_orden::int, publicado = v_pub, actualizado_en = now() where id = p_id;
  return p_id;
end $$;
revoke all on function public.deck_faq_guarda(uuid, uuid, jsonb) from public, anon;
grant execute on function public.deck_faq_guarda(uuid, uuid, jsonb) to authenticated;

