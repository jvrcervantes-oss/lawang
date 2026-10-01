-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
--
-- Título traducido de un enlace/documento para el investor deck (owner, 28-sep-2026: «en enlaces del proyecto
-- necesito que el título se pueda traducir para que se visualice en el idioma correspondiente dentro del investor
-- deck: español, inglés y bahasa»).
--
-- · `titulo` sigue siendo el texto de referencia (español), como en deck_faq. Las traducciones van en
--   `titulo_i18n` = {"en": "...", "id": "..."}; un idioma que falta cae al inglés y después al español (el deck).
-- · documento_proyecto_guarda: base = la definición VIVA del 28-sep (incluye las reglas B4 de «general» y de
--   «publicado solo lo cambia admin», que no están en 20260927151500). Se añade la clave `titulo_i18n`, saneada en
--   el servidor (solo en/id, texto sin control, 300 máx., vacíos fuera). Un documento ya publicado en el deck no
--   deja a un agente cambiar su traducción, igual que su título.
-- · investor_deck_documentos: cambia su tipo de salida (una columna más), así que se re-crea; mismos permisos que
--   dejó 20260928184500 (anon + service_role).

alter table public.documentos_proyecto
  add column if not exists titulo_i18n jsonb not null default '{}'::jsonb;
alter table public.documentos_proyecto add constraint documentos_proyecto_titulo_i18n_objeto
  check (jsonb_typeof(titulo_i18n) = 'object' and titulo_i18n - array['en', 'id'] = '{}'::jsonb);
comment on column public.documentos_proyecto.titulo_i18n is
  'Traducciones del título para el investor deck: {"en","id"}. El español es `titulo`. Lo escribe documento_proyecto_guarda.';

create or replace function public.documento_proyecto_guarda(p_id uuid, p_datos jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_old public.documentos_proyecto%rowtype; v public.documentos_proyecto%rowtype; k text;
  v_admin boolean := public.es_admin(); v_nombre text; v_pid uuid; v_id uuid; v_b boolean;
  v_i18n jsonb; v_t text;
begin
  if not (public.es_agente() and public.puede('documentacion')) then
    raise exception 'La documentación exige la herramienta «Documentación»' using errcode = '42501';
  end if;
  if jsonb_typeof(p_datos) is distinct from 'object' then raise exception 'Datos del documento no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_datos) loop
    if k not in ('proyecto', 'proyecto_id', 'titulo', 'titulo_i18n', 'categoria', 'carpeta', 'descripcion', 'url', 'confidencial',
                 'visible_portal', 'publicado_investor_deck', 'general') then
      raise exception 'Ese dato del documento no se edita desde aquí: %', k using errcode = '22023';
    end if;
  end loop;

  if p_id is not null then
    select * into v_old from public.documentos_proyecto d where d.id = p_id for update;
    if not found then raise exception 'Ese documento ya no existe: recarga la página' using errcode = '22023'; end if;
    if not (case when v_old.general then v_admin else public.puede_proyecto(v_old.proyecto, v_old.proyecto_id) end) then
      raise exception 'Ese documento no es de tus proyectos' using errcode = '42501';
    end if;
    v := v_old;
  else
    v.categoria := 'otros'; v.carpeta := ''; v.confidencial := true; v.visible_portal := false;
    v.publicado_investor_deck := false; v.general := false; v.titulo_i18n := '{}'::jsonb;
  end if;

  if p_datos ? 'proyecto_id' and nullif(p_datos->>'proyecto_id', '') is not null then
    begin v_pid := (p_datos->>'proyecto_id')::uuid; exception when others then raise exception 'Proyecto no válido' using errcode = '22023'; end;
    select p.nombre into v_nombre from public.proyectos p where p.id = v_pid;
    if v_nombre is null then raise exception 'Ese proyecto no existe' using errcode = '22023'; end if;
    v.proyecto := v_nombre; v.proyecto_id := v_pid;
  elsif p_datos ? 'proyecto' and p_id is not null and btrim(coalesce(p_datos->>'proyecto', '')) = v_old.proyecto then
    null;
  elsif p_datos ? 'proyecto' then
    select p.id, p.nombre into v_pid, v_nombre from public.proyectos p where p.nombre = btrim(coalesce(p_datos->>'proyecto', ''));
    -- B4 general alta admin: «<Marca> (general)» no es un proyecto; solo un admin archiva ahí
    if v_pid is null and v_admin and btrim(coalesce(p_datos->>'proyecto', '')) in ('Lawang (general)', 'Sumba (general)') then
      v.proyecto := btrim(p_datos->>'proyecto'); v.proyecto_id := null; v.general := true;
    else
      if v_pid is null then raise exception 'Ese proyecto no existe' using errcode = '22023'; end if;
      v.proyecto := v_nombre; v.proyecto_id := v_pid;
    end if;
  end if;
  if v.proyecto is null then raise exception 'Falta el proyecto' using errcode = '22023'; end if;

  if p_datos ? 'titulo' then v.titulo := left(btrim(regexp_replace(coalesce(p_datos->>'titulo', ''), '[[:cntrl:]]', ' ', 'g')), 300); end if;
  if coalesce(v.titulo, '') = '' then raise exception 'Falta el título' using errcode = '22023'; end if;
  -- traducciones del título: el objeto se REHACE aquí, nunca se guarda tal cual llega
  if p_datos ? 'titulo_i18n' then
    if jsonb_typeof(p_datos->'titulo_i18n') is distinct from 'object' then
      raise exception 'Las traducciones del título no son válidas' using errcode = '22023';
    end if;
    for k in select jsonb_object_keys(p_datos->'titulo_i18n') loop
      if k not in ('en', 'id') then raise exception 'Idioma no admitido en el título: %', k using errcode = '22023'; end if;
      if jsonb_typeof(p_datos->'titulo_i18n'->k) not in ('string', 'null') then
        raise exception 'Las traducciones del título no son válidas' using errcode = '22023';
      end if;
    end loop;
    v_i18n := '{}'::jsonb;
    foreach k in array array['en', 'id'] loop
      v_t := left(btrim(regexp_replace(coalesce(p_datos->'titulo_i18n'->>k, ''), '[[:cntrl:]]', ' ', 'g')), 300);
      if v_t <> '' then v_i18n := v_i18n || jsonb_build_object(k, v_t); end if;
    end loop;
    v.titulo_i18n := v_i18n;
  end if;
  if p_datos ? 'categoria' then
    v.categoria := btrim(coalesce(p_datos->>'categoria', ''));
    if v.categoria not in ('precios', 'planos', 'legal', 'comercial', 'tecnico', 'fotos', 'faq', 'portada', 'otros') then
      raise exception 'Categoría no válida' using errcode = '22023';
    end if;
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

  if v.general is distinct from coalesce(v_old.general, false) and not v_admin then
    raise exception 'Marcar un documento como general de la empresa lo decide administración' using errcode = '42501';
  end if;
  if v.publicado_investor_deck is distinct from coalesce(v_old.publicado_investor_deck, false) and not v_admin then
    raise exception 'Publicar o retirar un documento del dosier de inversores lo decide administración' using errcode = '42501';
  end if;
  -- B4 publicado solo admin: lo que ya sirve el dosier público no lo cambia un agente (tampoco su traducción)
  if p_id is not null and coalesce(v_old.publicado_investor_deck, false) and not v_admin
     and (v.url is distinct from v_old.url or v.titulo is distinct from v_old.titulo
          or v.titulo_i18n is distinct from v_old.titulo_i18n
          or nullif(btrim(coalesce(v.descripcion, '')), '') is distinct from nullif(btrim(coalesce(v_old.descripcion, '')), '') or v.categoria is distinct from v_old.categoria
          or v.proyecto is distinct from v_old.proyecto or v.proyecto_id is distinct from v_old.proyecto_id) then
    raise exception 'Este documento está publicado en el dosier de inversores: su título, traducciones, enlace, descripción, categoría y proyecto los cambia administración' using errcode = '42501';
  end if;
  if v.publicado_investor_deck and v.confidencial then
    raise exception 'Un documento confidencial no se publica en el dosier de inversores: desmarca una de las dos' using errcode = '22023';
  end if;
  if not (case when v.general then v_admin else public.puede_proyecto(v.proyecto, v.proyecto_id) end) then
    raise exception 'Ese proyecto no es de los tuyos' using errcode = '42501';
  end if;

  if p_id is null then
    insert into public.documentos_proyecto (proyecto, proyecto_id, categoria, titulo, titulo_i18n, descripcion, url, confidencial,
                                            carpeta, visible_portal, publicado_investor_deck, general, creado_por)
    values (v.proyecto, v.proyecto_id, v.categoria, v.titulo, coalesce(v.titulo_i18n, '{}'::jsonb), v.descripcion, v.url, v.confidencial,
            v.carpeta, v.visible_portal, v.publicado_investor_deck, v.general, (select auth.email()))
    returning id into v_id;
    return v_id;
  end if;
  update public.documentos_proyecto set proyecto = v.proyecto, proyecto_id = v.proyecto_id, categoria = v.categoria,
         titulo = v.titulo, titulo_i18n = coalesce(v.titulo_i18n, '{}'::jsonb), descripcion = v.descripcion, url = v.url,
         confidencial = v.confidencial, carpeta = v.carpeta,
         visible_portal = v.visible_portal, publicado_investor_deck = v.publicado_investor_deck, general = v.general
   where id = p_id;
  return p_id;
end $$;
revoke all on function public.documento_proyecto_guarda(uuid, jsonb) from public, anon;
grant execute on function public.documento_proyecto_guarda(uuid, jsonb) to authenticated;

-- el tipo de salida cambia (titulo_i18n): create or replace no puede, se re-crea con el mismo cuerpo
-- destructivo-ok: drop de una FUNCIÓN que se re-crea en la misma transacción con los mismos permisos; no toca datos
drop function if exists public.investor_deck_documentos(text);
create function public.investor_deck_documentos(p_proyecto text)
returns table(titulo text, titulo_i18n jsonb, descripcion text, url text, categoria text)
language sql stable security definer set search_path = 'public' as $$
  select d.titulo, d.titulo_i18n, d.descripcion,
         case when coalesce(d.url, '') <> '' then d.url
              else 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/deck-documento?id=' || d.id::text end,
         d.categoria
    from public.documentos_proyecto d
   where d.proyecto = p_proyecto
     and public.investor_deck_documento_visible(d)
   order by d.creado_en desc;
$$;
revoke all on function public.investor_deck_documentos(text) from public, authenticated;
grant execute on function public.investor_deck_documentos(text) to anon, service_role;
