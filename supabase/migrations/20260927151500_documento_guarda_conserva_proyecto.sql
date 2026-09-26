-- Frontera bloque 4, corrección del revisor de código (27-sep-2026): la documentación clásica manda SIEMPRE el nombre
-- del proyecto al guardar, y los documentos «general» de la sociedad (NPWP, Akta, Sertifikat, NIB) llevan un nombre
-- que no es una fila de `proyectos` («Lawang (general)», «Sumba (general)»): documento_proyecto_guarda los rechazaba con
-- «Ese proyecto no existe» y el admin ya no podía editarlos. Si el nombre que llega es el que el documento ya tenía,
-- no se toca el proyecto (el permiso de origen, admin para un general, ya se ha comprobado).

create or replace function public.documento_proyecto_guarda(p_id uuid, p_datos jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_old public.documentos_proyecto%rowtype; v public.documentos_proyecto%rowtype; k text;
  v_admin boolean := public.es_admin(); v_nombre text; v_pid uuid; v_id uuid; v_b boolean;
begin
  if not (public.es_agente() and public.puede('documentacion')) then
    raise exception 'La documentación exige la herramienta «Documentación»' using errcode = '42501';
  end if;
  if jsonb_typeof(p_datos) is distinct from 'object' then raise exception 'Datos del documento no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_datos) loop
    if k not in ('proyecto', 'proyecto_id', 'titulo', 'categoria', 'carpeta', 'descripcion', 'url', 'confidencial',
                 'visible_portal', 'publicado_investor_deck', 'general') then
      raise exception 'Ese dato del documento no se edita desde aquí: %', k using errcode = '22023';
    end if;
  end loop;

  if p_id is not null then
    select * into v_old from public.documentos_proyecto d where d.id = p_id for update;
    if not found then raise exception 'Ese documento ya no existe: recarga la página' using errcode = '22023'; end if;
    -- permiso en el ORIGEN
    if not (case when v_old.general then v_admin else public.puede_proyecto(v_old.proyecto, v_old.proyecto_id) end) then
      raise exception 'Ese documento no es de tus proyectos' using errcode = '42501';
    end if;
    v := v_old;
  else
    v.categoria := 'otros'; v.carpeta := ''; v.confidencial := true; v.visible_portal := false;
    v.publicado_investor_deck := false; v.general := false;
  end if;

  -- proyecto (por id o por nombre; el nombre lo resuelve el servidor, nunca se guarda uno que no existe)
  if p_datos ? 'proyecto_id' and nullif(p_datos->>'proyecto_id', '') is not null then
    begin v_pid := (p_datos->>'proyecto_id')::uuid; exception when others then raise exception 'Proyecto no válido' using errcode = '22023'; end;
    select p.nombre into v_nombre from public.proyectos p where p.id = v_pid;
    if v_nombre is null then raise exception 'Ese proyecto no existe' using errcode = '22023'; end if;
    v.proyecto := v_nombre; v.proyecto_id := v_pid;
  elsif p_datos ? 'proyecto' and p_id is not null and btrim(coalesce(p_datos->>'proyecto', '')) = v_old.proyecto then
    null;   -- mismo proyecto que ya tenía (p.ej. «Lawang (general)», que no es una fila de `proyectos`): no se toca
  elsif p_datos ? 'proyecto' then
    select p.id, p.nombre into v_pid, v_nombre from public.proyectos p where p.nombre = btrim(coalesce(p_datos->>'proyecto', ''));
    if v_pid is null then raise exception 'Ese proyecto no existe' using errcode = '22023'; end if;
    v.proyecto := v_nombre; v.proyecto_id := v_pid;
  end if;
  if v.proyecto is null then raise exception 'Falta el proyecto' using errcode = '22023'; end if;

  if p_datos ? 'titulo' then v.titulo := left(btrim(regexp_replace(coalesce(p_datos->>'titulo', ''), '[[:cntrl:]]', ' ', 'g')), 300); end if;
  if coalesce(v.titulo, '') = '' then raise exception 'Falta el título' using errcode = '22023'; end if;
  if p_datos ? 'categoria' then
    v.categoria := btrim(coalesce(p_datos->>'categoria', ''));
    if v.categoria not in ('precios', 'planos', 'legal', 'comercial', 'tecnico', 'fotos', 'faq', 'portada', 'otros') then
      raise exception 'Categoría no válida' using errcode = '22023';
    end if;
    -- la portada es una FOTO del proyecto: solo nace subiendo una (Editar proyecto), nunca por reclasificar
    if v.categoria = 'portada' and v.categoria is distinct from v_old.categoria then
      raise exception 'La portada se cambia subiendo una foto desde «Editar proyecto»' using errcode = '22023';
    end if;
  end if;
  if p_datos ? 'carpeta' then v.carpeta := left(btrim(coalesce(p_datos->>'carpeta', '')), 200); end if;
  if p_datos ? 'descripcion' then v.descripcion := left(nullif(btrim(coalesce(p_datos->>'descripcion', '')), ''), 5000); end if;
  if p_datos ? 'url' then
    v.url := nullif(btrim(coalesce(p_datos->>'url', '')), '');
    if v.url is not null and (v.url !~* '^https?://[^[:space:]"<>]+$' or length(v.url) > 2000) then
      raise exception 'El enlace tiene que empezar por http:// o https://' using errcode = '22023';
    end if;
  end if;
  if v.path is not null and v.url is not null then raise exception 'Un documento subido no lleva enlace' using errcode = '22023'; end if;
  if v.path is null and v.url is null and v.categoria <> 'faq' then raise exception 'Falta el enlace' using errcode = '22023'; end if;

  v_b := public._lw_si_no(p_datos->'confidencial', 'Confidencial');        if v_b is not null then v.confidencial := v_b; end if;
  v_b := public._lw_si_no(p_datos->'visible_portal', 'Visible para el cliente'); if v_b is not null then v.visible_portal := v_b; end if;
  v_b := public._lw_si_no(p_datos->'general', 'Documento general');       if v_b is not null then v.general := v_b; end if;
  v_b := public._lw_si_no(p_datos->'publicado_investor_deck', 'Publicar en el dosier de inversores');
  if v_b is not null then v.publicado_investor_deck := v_b; end if;

  -- lo que cambia el PÚBLICO: solo admin (Seguridad #127)
  if v.general is distinct from coalesce(v_old.general, false) and not v_admin then
    raise exception 'Marcar un documento como general de la empresa lo decide administración' using errcode = '42501';
  end if;
  if v.publicado_investor_deck is distinct from coalesce(v_old.publicado_investor_deck, false) and not v_admin then
    raise exception 'Publicar o retirar un documento del dosier de inversores lo decide administración' using errcode = '42501';
  end if;
  if v.publicado_investor_deck and v.confidencial then
    raise exception 'Un documento confidencial no se publica en el dosier de inversores: desmarca una de las dos' using errcode = '22023';
  end if;
  -- permiso en el DESTINO
  if not (case when v.general then v_admin else public.puede_proyecto(v.proyecto, v.proyecto_id) end) then
    raise exception 'Ese proyecto no es de los tuyos' using errcode = '42501';
  end if;

  if p_id is null then
    insert into public.documentos_proyecto (proyecto, proyecto_id, categoria, titulo, descripcion, url, confidencial,
                                            carpeta, visible_portal, publicado_investor_deck, general, creado_por)
    values (v.proyecto, v.proyecto_id, v.categoria, v.titulo, v.descripcion, v.url, v.confidencial,
            v.carpeta, v.visible_portal, v.publicado_investor_deck, v.general, (select auth.email()))
    returning id into v_id;
    return v_id;
  end if;
  update public.documentos_proyecto set proyecto = v.proyecto, proyecto_id = v.proyecto_id, categoria = v.categoria,
         titulo = v.titulo, descripcion = v.descripcion, url = v.url, confidencial = v.confidencial, carpeta = v.carpeta,
         visible_portal = v.visible_portal, publicado_investor_deck = v.publicado_investor_deck, general = v.general
   where id = p_id;
  return p_id;
end $$;
revoke all on function public.documento_proyecto_guarda(uuid, jsonb) from public, anon;
grant execute on function public.documento_proyecto_guarda(uuid, jsonb) to authenticated;
