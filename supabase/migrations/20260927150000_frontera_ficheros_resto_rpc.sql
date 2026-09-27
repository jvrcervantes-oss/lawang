-- destructivo-ok: no borra nada al aplicarse; los `delete` van DENTRO de funciones (borrar un documento/foto/comunicado con permiso, reponer los enlaces de una creatividad), igual que las RPC de los bloques 2 y 3.
-- Frontera frontend/backend — bloques 4 y 5: FICHEROS y EL RESTO (27-sep-2026, LAW-336 / LAW-337).
-- Plan y revisión previa #127 (Marketing + Seguridad, que mandan sobre el plan):
-- encargos/20260927_lawang_frontera_b4_b5_resto.md
--
-- SOLO AÑADE (funciones nuevas + UNIQUE en obra_fotos.path, tabla vacía el 27-sep). El cierre (revoke de escritura,
-- quitar las policies de escritura de tablas y buckets, sustituir las ALL de obra por SELECT con alcance, tipos
-- admitidos en el bucket `documentacion`) va en 20260927153000 y se aplica cuando las pantallas nuevas estén SERVIDAS.
--
-- Patrón (el de los bloques 2 y 3): RPC SECURITY DEFINER con el permiso DENTRO; lista blanca de claves; «clave
-- ausente = no se toca»; los ficheros los sube la edge `ficheros` (ruta del servidor, URL firmada, bytes leídos) y los
-- registra/borra una RPC que solo ejecuta service_role, como el usuario de la sesión (`_actua_como`).
--
-- El dato tiene un dueño (patrones_tecnicos.md): `path` de documentos_proyecto y obra_fotos es de la EDGE (decide
-- quién lee: agente_ve_documento_proyecto, portal_ve_documento, portal_ve_foto casan por path) y nunca se edita;
-- `creado_por`/`copiado_por`/`pedido_por`/`corregido_por` los pone el servidor, nunca el cuerpo de la petición.

-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0. Ayudas
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- Booleano de un jsonb: null si no viene, error legible si no es sí/no.
create or replace function public._lw_si_no(p jsonb, p_campo text) returns boolean
language plpgsql immutable set search_path = '' as $$
begin
  if p is null or jsonb_typeof(p) = 'null' then return null; end if;
  if jsonb_typeof(p) = 'boolean' then return (p #>> '{}')::boolean; end if;
  raise exception '«%» tiene que ser sí o no', p_campo using errcode = '22023';
end $$;
revoke all on function public._lw_si_no(jsonb, text) from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 1. DOCUMENTACIÓN (documentos_proyecto + bucket `documentacion`)
--    Regla (la de la policy de hoy, que se retira en el cierre): agente con la herramienta «documentacion» y el
--    proyecto entre los suyos; un documento `general` (de la empresa) es de admin. Seguridad #127: `general` y
--    `publicado_investor_deck` (lo sirve investor_deck_documentos a anon) solo los CAMBIA un admin; mover de
--    proyecto exige permiso en el de origen y en el de destino; `url` solo http(s); `path` nunca.
--    Borrar: super admin (la policy de hoy), fila y objeto en el mismo flujo (edge).
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ¿Puede esta sesión subir/escribir documentación en ese proyecto? La llama la edge `ficheros` con la sesión
-- ANTES de firmar la subida (el permiso se vuelve a mirar al registrar).
create or replace function public.documento_proyecto_puede(p_proyecto_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_agente() and public.puede('documentacion') and p_proyecto_id is not null
     and exists (select 1 from public.proyectos p where p.id = p_proyecto_id)
     and public.puede_proyecto_id(p_proyecto_id)
$$;
revoke all on function public.documento_proyecto_puede(uuid) from public, anon;
grant execute on function public.documento_proyecto_puede(uuid) to authenticated;

-- Enlaces, FAQ y la ficha de un documento subido (alta sin fichero o edición). Devuelve el id.
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

-- Registrar un fichero subido por la edge: ruta `proyectos/<proyecto_id>/<uuid>.<ext>`, objeto existente.
create or replace function public.documento_proyecto_registra(p_uid uuid, p_proyecto uuid, p_path text, p_datos jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_nombre text; v_id uuid; v_tam bigint; v_mime text; k text; v_cat text; v_tit text; v_conf boolean; v_portal boolean; v_pub boolean;
begin
  perform public._actua_como(p_uid);
  if not (public.es_agente() and public.puede('documentacion')) then
    raise exception 'La documentación exige la herramienta «Documentación»' using errcode = '42501';
  end if;
  select p.nombre into v_nombre from public.proyectos p where p.id = p_proyecto;
  if v_nombre is null then raise exception 'Ese proyecto no existe' using errcode = '22023'; end if;
  if not public.puede_proyecto_id(p_proyecto) then raise exception 'Ese proyecto no es de los tuyos' using errcode = '42501'; end if;
  if p_path is null or p_path !~ ('^proyectos/' || p_proyecto::text || '/[0-9a-f-]{36}\.(pdf|jpg|jpeg|png|webp|doc|docx|xls|xlsx|csv|ppt|pptx|dwg|dxf|zip)$') then
    raise exception 'Ruta de documento no válida' using errcode = '22023';
  end if;
  select (o.metadata->>'size')::bigint, o.metadata->>'mimetype' into v_tam, v_mime
    from storage.objects o where o.bucket_id = 'documentacion' and o.name = p_path;
  if not found then raise exception 'El fichero no ha llegado al archivo: vuelve a subirlo' using errcode = '22023'; end if;
  p_datos := coalesce(p_datos, '{}'::jsonb);
  if jsonb_typeof(p_datos) <> 'object' then raise exception 'Datos del documento no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_datos) loop
    if k not in ('titulo', 'categoria', 'carpeta', 'descripcion', 'confidencial', 'visible_portal', 'publicado_investor_deck') then
      raise exception 'Ese dato del documento no se guarda desde aquí: %', k using errcode = '22023';
    end if;
  end loop;
  v_cat := coalesce(nullif(btrim(p_datos->>'categoria'), ''), 'otros');
  if v_cat not in ('precios', 'planos', 'legal', 'comercial', 'tecnico', 'fotos', 'portada', 'otros') then
    raise exception 'Categoría no válida' using errcode = '22023';
  end if;
  v_tit := left(btrim(regexp_replace(coalesce(p_datos->>'titulo', ''), '[[:cntrl:]]', ' ', 'g')), 300);
  if v_tit = '' then v_tit := case when v_cat = 'portada' then 'Portada' else 'Documento' end; end if;
  v_conf := coalesce(public._lw_si_no(p_datos->'confidencial', 'Confidencial'), true);
  v_portal := coalesce(public._lw_si_no(p_datos->'visible_portal', 'Visible para el cliente'), false);
  v_pub := coalesce(public._lw_si_no(p_datos->'publicado_investor_deck', 'Publicar en el dosier de inversores'), false);
  if v_pub and not public.es_admin() then
    raise exception 'Publicar un documento en el dosier de inversores lo decide administración' using errcode = '42501';
  end if;
  if v_pub and v_conf then
    raise exception 'Un documento confidencial no se publica en el dosier de inversores: desmarca una de las dos' using errcode = '22023';
  end if;
  begin
    insert into public.documentos_proyecto (proyecto, proyecto_id, categoria, titulo, descripcion, path, mime, bytes,
                                            confidencial, carpeta, visible_portal, publicado_investor_deck, general, creado_por)
    values (v_nombre, p_proyecto, v_cat, v_tit, left(nullif(btrim(coalesce(p_datos->>'descripcion', '')), ''), 5000), p_path,
            v_mime, v_tam, v_conf, left(btrim(coalesce(p_datos->>'carpeta', '')), 200), v_portal, v_pub, false, (select auth.email()))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Ese fichero ya está registrado' using errcode = '23505';
  end;
  return v_id;
end $$;
revoke all on function public.documento_proyecto_registra(uuid, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.documento_proyecto_registra(uuid, uuid, text, jsonb) to service_role;

-- Borrar (enlace, FAQ o fichero): super admin, como la policy de hoy. p_solo_comprobar: devuelve la ruta sin borrar.
create or replace function public.documento_proyecto_borra(p_uid uuid, p_id uuid, p_solo_comprobar boolean default false) returns text
language plpgsql security definer set search_path = '' as $$
declare v_d public.documentos_proyecto%rowtype;
begin
  perform public._actua_como(p_uid);
  if not public.es_super_admin() then raise exception 'Borrar documentación lo hace un super admin' using errcode = '42501'; end if;
  select * into v_d from public.documentos_proyecto d where d.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe: recarga la página' using errcode = '22023'; end if;
  if not coalesce(p_solo_comprobar, false) then delete from public.documentos_proyecto where id = p_id; end if;
  return v_d.path;
end $$;
revoke all on function public.documento_proyecto_borra(uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function public.documento_proyecto_borra(uuid, uuid, boolean) to service_role;

-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 2. OBRA (obra_fotos + bucket `obra`)
--    Hasta hoy «herramienta obra» veía y tocaba las fotos de TODOS los proyectos (policy ALL sin alcance) y el
--    bucket era ALL sobre cualquier objeto. Desde aquí: herramienta obra + el proyecto de la unidad entre los suyos,
--    para subir, editar y borrar; y en el cierre, para LEER (decisión del estudio por coherencia con documentación,
--    reversible, anotada para el owner).
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
create unique index if not exists obra_fotos_path_key on public.obra_fotos (path);

create or replace function public.obra_puede(p_unidad uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_agente() and public.puede('obra') and exists (
    select 1 from public.unidades u where u.id = p_unidad and public.puede_proyecto_id(u.proyecto_id))
$$;
revoke all on function public.obra_puede(uuid) from public, anon;
grant execute on function public.obra_puede(uuid) to authenticated;

-- Lectura (la usarán las policies SELECT del cierre, sobre la tabla y sobre el bucket): cualquiera del equipo que
-- vea el proyecto de la unidad (como las unidades), sin exigir la herramienta — el cajón de una unidad enseña sus fotos.
create or replace function public.agente_ve_foto_obra(p_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_agente() and exists (
    select 1 from public.obra_fotos o join public.unidades u on u.id = o.unidad_id
     where o.path = p_name and public.puede_proyecto_id(u.proyecto_id))
$$;
revoke all on function public.agente_ve_foto_obra(text) from public, anon;
grant execute on function public.agente_ve_foto_obra(text) to authenticated;

create or replace function public.agente_ve_unidad_obra(p_unidad uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_agente() and exists (
    select 1 from public.unidades u where u.id = p_unidad and public.puede_proyecto_id(u.proyecto_id))
$$;
revoke all on function public.agente_ve_unidad_obra(uuid) from public, anon;
grant execute on function public.agente_ve_unidad_obra(uuid) to authenticated;

create or replace function public.obra_foto_registra(p_uid uuid, p_unidad uuid, p_path text, p_titulo text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  perform public._actua_como(p_uid);
  if not public.obra_puede(p_unidad) then
    raise exception 'Las fotos de obra de esa parcela no son de tus proyectos (o te falta la herramienta «Obra»)' using errcode = '42501';
  end if;
  if p_path is null or p_path !~ ('^' || p_unidad::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$') then
    raise exception 'Ruta de foto no válida' using errcode = '22023';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'obra' and o.name = p_path) then
    raise exception 'La foto no ha llegado al archivo: vuelve a subirla' using errcode = '22023';
  end if;
  begin
    insert into public.obra_fotos (unidad_id, path, titulo, creado_por)
    values (p_unidad, p_path, left(nullif(btrim(regexp_replace(coalesce(p_titulo, ''), '[[:cntrl:]]', ' ', 'g')), ''), 200), (select auth.email()))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Esa foto ya está registrada' using errcode = '23505';
  end;
  return v_id;
end $$;
revoke all on function public.obra_foto_registra(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.obra_foto_registra(uuid, uuid, text, text) to service_role;

-- Título, visible (lo ve el comprador en su portal), fecha y mover de parcela (permiso en origen y destino).
create or replace function public.obra_foto_cambia(p_id uuid, p_cambios jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v public.obra_fotos%rowtype; k text; v_b boolean; v_u uuid;
begin
  if jsonb_typeof(p_cambios) is distinct from 'object' then raise exception 'Datos de la foto no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_cambios) loop
    if k not in ('titulo', 'visible', 'tomada_en', 'unidad_id') then raise exception 'Ese dato de la foto no se edita desde aquí: %', k using errcode = '22023'; end if;
  end loop;
  select * into v from public.obra_fotos f where f.id = p_id for update;
  if not found then raise exception 'Esa foto ya no existe: recarga' using errcode = '22023'; end if;
  if not public.obra_puede(v.unidad_id) then
    raise exception 'Las fotos de obra de esa parcela no son de tus proyectos (o te falta la herramienta «Obra»)' using errcode = '42501';
  end if;
  if p_cambios ? 'titulo' then v.titulo := left(nullif(btrim(regexp_replace(coalesce(p_cambios->>'titulo', ''), '[[:cntrl:]]', ' ', 'g')), ''), 200); end if;
  v_b := public._lw_si_no(p_cambios->'visible', 'Visible'); if v_b is not null then v.visible := v_b; end if;
  if p_cambios ? 'tomada_en' then
    begin v.tomada_en := (p_cambios->>'tomada_en')::date; exception when others then raise exception 'Fecha de la foto no válida' using errcode = '22023'; end;
    if v.tomada_en is null or v.tomada_en > current_date + 1 or v.tomada_en < date '2020-01-01' then
      raise exception 'Fecha de la foto no válida' using errcode = '22023';
    end if;
  end if;
  if p_cambios ? 'unidad_id' then
    begin v_u := (p_cambios->>'unidad_id')::uuid; exception when others then raise exception 'Parcela no válida' using errcode = '22023'; end;
    if v_u is null or not public.obra_puede(v_u) then raise exception 'Esa parcela no es de tus proyectos' using errcode = '42501'; end if;
    v.unidad_id := v_u;
  end if;
  update public.obra_fotos set titulo = v.titulo, visible = v.visible, tomada_en = v.tomada_en, unidad_id = v.unidad_id where id = p_id;
  return p_id;
end $$;
revoke all on function public.obra_foto_cambia(uuid, jsonb) from public, anon;
grant execute on function public.obra_foto_cambia(uuid, jsonb) to authenticated;

create or replace function public.obra_foto_borra(p_uid uuid, p_id uuid, p_solo_comprobar boolean default false) returns text
language plpgsql security definer set search_path = '' as $$
declare v public.obra_fotos%rowtype;
begin
  perform public._actua_como(p_uid);
  select * into v from public.obra_fotos f where f.id = p_id for update;
  if not found then raise exception 'Esa foto ya no existe: recarga' using errcode = '22023'; end if;
  if not public.obra_puede(v.unidad_id) then
    raise exception 'Las fotos de obra de esa parcela no son de tus proyectos (o te falta la herramienta «Obra»)' using errcode = '42501';
  end if;
  if not coalesce(p_solo_comprobar, false) then delete from public.obra_fotos where id = p_id; end if;
  return v.path;
end $$;
revoke all on function public.obra_foto_borra(uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function public.obra_foto_borra(uuid, uuid, boolean) to service_role;

-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 3. JUSTIFICANTES DE GASTO (bucket `gastos`; la fila `gastos` ya va por RPC desde la pieza 3)
--    Sustituye a gasto_anade_justificante (que se cierra a authenticated en el cierre): misma regla (admin +
--    herramienta gastos) y además el gasto no anulado — la policy de subida lo exigía y la RPC vieja no.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function public.gasto_justificante_registra(p_uid uuid, p_gasto uuid, p_path text, p_nombre text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_estado text;
begin
  perform public._actua_como(p_uid);
  if not public._gasto_puede() then raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501'; end if;
  select g.estado into v_estado from public.gastos g where g.id = p_gasto for update;
  if v_estado is null then raise exception 'Ese gasto ya no existe: recarga' using errcode = '22023'; end if;
  if v_estado = 'anulado' then raise exception 'Ese gasto está anulado: no admite justificantes' using errcode = '22023'; end if;
  if p_path is null or p_path !~ ('^' || p_gasto::text || '/[0-9a-f-]{36}\.(pdf|jpg|jpeg|png|webp)$') then
    raise exception 'Ruta de justificante no válida' using errcode = '22023';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'gastos' and o.name = p_path) then
    raise exception 'El fichero no ha llegado al archivo: vuelve a subirlo' using errcode = '22023';
  end if;
  update public.gastos g set justificantes = g.justificantes || jsonb_build_array(jsonb_build_object(
      'path', p_path, 'nombre', left(coalesce(nullif(btrim(regexp_replace(coalesce(p_nombre, ''), '[[:cntrl:]]', ' ', 'g')), ''), 'Justificante'), 200),
      'subido_en', now()))
   where g.id = p_gasto and not (g.justificantes @> jsonb_build_array(jsonb_build_object('path', p_path)));
  return p_gasto;
end $$;
revoke all on function public.gasto_justificante_registra(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.gasto_justificante_registra(uuid, uuid, text, text) to service_role;

-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 4. CREATIVIDADES (creatividades + creatividad_fotos + creatividad_modelos + bucket `creatividades`)
--    Revisión previa #127 (Marketing): un guardado eran 5-8 escrituras sin transacción; ahora es UNA llamada
--    (metadatos + ficheros ya subidos + fotos + modelos). Mismas reglas que las policies de hoy: la herramienta del
--    tipo (`creatividad_puede_hacer`: pieza → creatividades, dossier → dossier) y solo un borrador. Las rutas
--    conservan la convención que exigen los CHECK de la tabla (`<id>/{estado|pieza|portada}-<n>.<ext>`).
--    El JSON del estado lo valida la edge (JSON.parse + objeto) antes de llamar aquí.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function public._creatividad_sin_permiso(p_tipo text) returns text
language sql immutable set search_path = '' as $$
  select case p_tipo when 'dossier' then 'No tienes permiso para hacer dossiers (te falta la herramienta «Dossier»): pídeselo a administración'
                     else 'No tienes permiso para hacer creatividades (te falta la herramienta «Creatividades»): pídeselo a administración' end
$$;
revoke all on function public._creatividad_sin_permiso(text) from public, anon, authenticated;

create or replace function public.creatividad_guarda(p_uid uuid, p_id uuid, p_tipo text, p_datos jsonb, p_estado_path text,
  p_path text default null, p_portada_path text default null, p_fotos uuid[] default null, p_modelos uuid[] default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v public.creatividades%rowtype; v_nueva boolean := false; k text; v_tipo text; v_n int;
  v_titulo text; v_proy uuid; v_formato text; v_arq text; v_precios date;
begin
  perform public._actua_como(p_uid);
  if p_id is null then raise exception 'Falta la creatividad' using errcode = '22023'; end if;
  select * into v from public.creatividades c where c.id = p_id for update;
  if not found then
    v_nueva := true;
    v_tipo := p_tipo;
    if v_tipo is null or v_tipo not in ('pieza', 'dossier') then raise exception 'Tipo de creatividad no válido' using errcode = '22023'; end if;
  else
    v_tipo := v.tipo;
    if p_tipo is not null and p_tipo <> v.tipo then raise exception 'Una creatividad no cambia de tipo' using errcode = '22023'; end if;
  end if;
  if not public.creatividad_puede_hacer(v_tipo) then raise exception '%', public._creatividad_sin_permiso(v_tipo) using errcode = '42501'; end if;
  if not v_nueva and v.estado <> 'borrador' then
    raise exception 'Esta creatividad ya no es un borrador (está «%»): guárdala como copia para seguir cambiándola', v.estado using errcode = '23514';
  end if;

  p_datos := coalesce(p_datos, '{}'::jsonb);
  if jsonb_typeof(p_datos) <> 'object' then raise exception 'Datos de la creatividad no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_datos) loop
    if k not in ('titulo', 'proyecto_id', 'formato', 'arquetipo', 'precios_a') then
      raise exception 'Ese dato de la creatividad no se guarda desde aquí: %', k using errcode = '22023';
    end if;
  end loop;
  v_titulo := case when p_datos ? 'titulo' then left(btrim(regexp_replace(coalesce(p_datos->>'titulo', ''), '[[:cntrl:]]', ' ', 'g')), 200) else v.titulo end;
  if coalesce(v_titulo, '') = '' then v_titulo := 'Sin título'; end if;
  v_proy := v.proyecto_id;
  if p_datos ? 'proyecto_id' then
    begin v_proy := nullif(p_datos->>'proyecto_id', '')::uuid; exception when others then raise exception 'Proyecto no válido' using errcode = '22023'; end;
    if v_proy is not null and not exists (select 1 from public.proyectos p where p.id = v_proy) then raise exception 'Ese proyecto no existe' using errcode = '22023'; end if;
  end if;
  v_formato := case when p_datos ? 'formato' then nullif(btrim(coalesce(p_datos->>'formato', '')), '') else v.formato end;
  if v_formato is not null and char_length(v_formato) > 20 then raise exception 'Formato no válido' using errcode = '22023'; end if;
  v_arq := case when p_datos ? 'arquetipo' then nullif(btrim(coalesce(p_datos->>'arquetipo', '')), '') else v.arquetipo end;
  if v_arq is not null and v_arq not in ('anuncio', 'doc', 'portada', 'partida', 'plano') then raise exception 'Arquetipo no válido' using errcode = '22023'; end if;
  v_precios := v.precios_a;
  if p_datos ? 'precios_a' then
    begin v_precios := nullif(p_datos->>'precios_a', '')::date; exception when others then raise exception 'Fecha de precios no válida' using errcode = '22023'; end;
  end if;

  -- ficheros: los ha subido la edge a la carpeta de ESTA creatividad; existen y cumplen la convención
  if p_estado_path is null or p_estado_path !~ ('^' || p_id::text || '/estado-[0-9]+\.json$')
     or not exists (select 1 from storage.objects o where o.bucket_id = 'creatividades' and o.name = p_estado_path) then
    raise exception 'El estado de la creatividad no ha llegado al archivo: vuelve a guardar' using errcode = '22023';
  end if;
  if p_path is not null and (v_tipo <> 'pieza' or p_path !~ ('^' || p_id::text || '/pieza-[0-9]+\.png$')
     or not exists (select 1 from storage.objects o where o.bucket_id = 'creatividades' and o.name = p_path)) then
    raise exception 'La imagen de la pieza no ha llegado al archivo: vuelve a guardar' using errcode = '22023';
  end if;
  if p_portada_path is not null and (v_tipo <> 'dossier' or p_portada_path !~ ('^' || p_id::text || '/portada-[0-9]+\.png$')
     or not exists (select 1 from storage.objects o where o.bucket_id = 'creatividades' and o.name = p_portada_path)) then
    raise exception 'La portada del dossier no ha llegado al archivo: vuelve a guardar' using errcode = '22023';
  end if;

  if v_nueva then
    insert into public.creatividades (id, tipo, titulo, proyecto_id, formato, arquetipo, precios_a, estado_path, path, portada_path)
    values (p_id, v_tipo, v_titulo, v_proy, v_formato, v_arq, v_precios, p_estado_path, p_path, p_portada_path);
  else
    update public.creatividades set titulo = v_titulo, proyecto_id = v_proy, formato = v_formato, arquetipo = v_arq,
           precios_a = v_precios, estado_path = p_estado_path, path = coalesce(p_path, path),
           portada_path = coalesce(p_portada_path, portada_path)
     where id = p_id;
  end if;

  -- enlaces: null = no se tocan; un array (aunque vacío) = se reponen enteros, en la misma transacción
  if p_fotos is not null then
    select count(*) into v_n from (select distinct unnest(p_fotos) x) s where s.x is not null
       and not exists (select 1 from public.deck_fotos f where f.id = s.x);
    if v_n > 0 then raise exception 'Alguna foto elegida ya no existe: recarga la biblioteca de fotos' using errcode = '22023'; end if;
    delete from public.creatividad_fotos where creatividad_id = p_id;
    insert into public.creatividad_fotos (creatividad_id, foto_id)
    select distinct p_id, x from unnest(p_fotos) x where x is not null;
  end if;
  if p_modelos is not null then
    select count(*) into v_n from (select distinct unnest(p_modelos) x) s where s.x is not null
       and not exists (select 1 from public.modelos m where m.id = s.x);
    if v_n > 0 then raise exception 'Algún modelo elegido ya no existe: recarga' using errcode = '22023'; end if;
    delete from public.creatividad_modelos where creatividad_id = p_id;
    insert into public.creatividad_modelos (creatividad_id, modelo_id)
    select distinct p_id, x from unnest(p_modelos) x where x is not null;
  end if;

  select * into v from public.creatividades c where c.id = p_id;   -- lleva_render lo recalcula el trigger
  return to_jsonb(v);
end $$;
revoke all on function public.creatividad_guarda(uuid, uuid, text, jsonb, text, text, text, uuid[], uuid[]) from public, anon, authenticated;
grant execute on function public.creatividad_guarda(uuid, uuid, text, jsonb, text, text, text, uuid[], uuid[]) to service_role;

-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 5. EL RESTO (bloque 5)
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- 5.1 comunicados (admin). Devuelve la fila: la pantalla la pinta tal cual. El congelado de lo ENVIADO lo sigue
-- haciendo el trigger _comunicados_congela; `creado_por` lo pone el servidor.
create or replace function public.comunicado_guarda(p_id uuid, p_datos jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v public.comunicados%rowtype; k text;
begin
  -- 27-sep-2026: + puede('comunicacion'), como la migración 20260927040933 (aplicada ANTES en producción
  -- pero con versión anterior a este fichero: sin esto, reconstruir la base en orden la deshacía).
  if not (public.es_admin() and public.puede('comunicacion')) then raise exception 'Los comunicados son de administración con la herramienta «Comunicación»' using errcode = '42501'; end if;
  if jsonb_typeof(p_datos) is distinct from 'object' then raise exception 'Datos del comunicado no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_datos) loop
    if k not in ('asunto', 'encabezado', 'cuerpo', 'cta_url', 'cta_texto') then
      raise exception 'Ese dato del comunicado no se edita desde aquí: %', k using errcode = '22023';
    end if;
  end loop;
  if p_id is not null then
    select * into v from public.comunicados c where c.id = p_id for update;
    if not found then raise exception 'Ese comunicado ya no existe: recarga' using errcode = '22023'; end if;
  end if;
  if p_datos ? 'asunto' then v.asunto := p_datos->>'asunto'; end if;
  if p_datos ? 'encabezado' then v.encabezado := nullif(btrim(coalesce(p_datos->>'encabezado', '')), ''); end if;
  if p_datos ? 'cuerpo' then v.cuerpo := p_datos->>'cuerpo'; end if;
  if p_datos ? 'cta_url' then v.cta_url := nullif(btrim(coalesce(p_datos->>'cta_url', '')), ''); end if;
  if p_datos ? 'cta_texto' then v.cta_texto := nullif(btrim(coalesce(p_datos->>'cta_texto', '')), ''); end if;
  -- el resto de reglas (longitudes, enlace de lista blanca, pareja texto/enlace) son CHECK de la tabla
  if p_id is null then
    insert into public.comunicados (asunto, encabezado, cuerpo, cta_url, cta_texto, creado_por)
    values (v.asunto, v.encabezado, v.cuerpo, v.cta_url, v.cta_texto, (select auth.uid()))
    returning * into v;
  else
    update public.comunicados set asunto = v.asunto, encabezado = v.encabezado, cuerpo = v.cuerpo,
           cta_url = v.cta_url, cta_texto = v.cta_texto
     where id = p_id returning * into v;
  end if;
  return to_jsonb(v);
end $$;
revoke all on function public.comunicado_guarda(uuid, jsonb) from public, anon;
grant execute on function public.comunicado_guarda(uuid, jsonb) to authenticated;

create or replace function public.comunicado_borra(p_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
begin
  -- 27-sep-2026: + puede('comunicacion'), como la migración 20260927040933 (aplicada ANTES en producción
  -- pero con versión anterior a este fichero: sin esto, reconstruir la base en orden la deshacía).
  if not (public.es_admin() and public.puede('comunicacion')) then raise exception 'Los comunicados son de administración con la herramienta «Comunicación»' using errcode = '42501'; end if;
  delete from public.comunicados where id = p_id;   -- lo ya enviado lo frena el trigger _comunicados_congela
  if not found then raise exception 'Ese comunicado ya no existe: recarga' using errcode = '22023'; end if;
  return p_id;
end $$;
revoke all on function public.comunicado_borra(uuid) from public, anon;
grant execute on function public.comunicado_borra(uuid) to authenticated;

-- 5.2 hilo_soporte: hoy la policy ALL dejaba a cualquier agente crear/borrar hilos ajenos. Solo el estado, de una
-- lista cerrada, y solo quien ve a ese comprador (cliente_visible: admin, su dueño o su manager).
create or replace function public.hilo_soporte_estado(p_id uuid, p_estado text) returns text
language plpgsql security definer set search_path = '' as $$
declare v_client uuid; v_prop text;
begin
  if not public.es_agente() then raise exception 'Solo el equipo cambia el estado de un ticket' using errcode = '42501'; end if;
  if p_estado is null or p_estado not in ('abierto', 'resuelto') then raise exception 'Estado de ticket no válido' using errcode = '22023'; end if;
  select h.client_id into v_client from public.hilo_soporte h where h.id = p_id for update;
  if v_client is null then raise exception 'Ese ticket ya no existe: recarga' using errcode = '22023'; end if;
  select c.propietario into v_prop from public.clients c where c.id = v_client;
  if not public.cliente_visible(v_prop, v_client) then raise exception 'Ese comprador no es de los tuyos' using errcode = '42501'; end if;
  update public.hilo_soporte set estado = p_estado, actualizado_en = now() where id = p_id;
  return p_estado;
end $$;
revoke all on function public.hilo_soporte_estado(uuid, text) from public, anon;
grant execute on function public.hilo_soporte_estado(uuid, text) to authenticated;

-- 5.3 solicitudes_cambio: la regla de la policy de hoy (equipo, `pedido_por` = quien pide, la ficha visible). Ojo:
-- `_sc_visible` es INVOKER y aquí dentro (DEFINER) lo vería todo, así que se usan los predicados de verdad de cada
-- tabla. El resto de la validación (qué se puede pedir, huella, estado inicial) lo sigue haciendo el trigger
-- _trg_solicitud_cambio_alta, que también pone pedido_por = auth.uid().
create or replace function public.solicitud_cambio_pide(p_accion text, p_fila_id uuid, p_nuevos jsonb, p_motivo text, p_texto text)
returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_num bigint; v_ok boolean;
begin
  if not public.es_agente() then raise exception 'Solo el equipo pide cambios' using errcode = '42501'; end if;
  if p_accion is null or p_accion not in ('editar_comprador', 'borrar_comprador', 'anular_documento', 'borrar_documento', 'borrar_operacion', 'manual') then
    raise exception 'Esa petición no existe' using errcode = '22023';
  end if;
  if p_accion <> 'manual' then
    if p_fila_id is null then raise exception 'falta a qué ficha o documento se refiere' using errcode = '22023'; end if;
    v_ok := case
      when p_accion in ('editar_comprador', 'borrar_comprador') then
        exists (select 1 from public.clients c where c.id = p_fila_id and public.cliente_visible(c.propietario, c.id))
      when p_accion in ('anular_documento', 'borrar_documento') then
        exists (select 1 from public.facturas f where f.id = p_fila_id and public.documento_visible(f.creado_por, f.proyecto_id, f.contrato_id))
      else
        exists (select 1 from public.contratos c where c.id = p_fila_id and public.contrato_visible(c.creado_por, c.proyecto_id))
    end;
    if not v_ok then raise exception 'esa ficha no existe o no la puedes ver' using errcode = '42501'; end if;
  end if;
  insert into public.solicitudes_cambio (accion, fila_id, nuevos, motivo, texto)
  values (p_accion, case when p_accion = 'manual' then null else p_fila_id end,
          case when p_accion = 'editar_comprador' then p_nuevos end,
          coalesce(nullif(btrim(coalesce(p_motivo, '')), ''), nullif(btrim(coalesce(p_texto, '')), ''), ''),
          left(nullif(btrim(coalesce(p_texto, '')), ''), 2000))
  returning numero into v_num;
  return v_num;
end $$;
revoke all on function public.solicitud_cambio_pide(text, uuid, jsonb, text, text) from public, anon;
grant execute on function public.solicitud_cambio_pide(text, uuid, jsonb, text, text) to authenticated;

-- 5.4 bot_respuestas_copiadas: la prueba de lo que salió hacia el comprador. Cada uno registra SU copia de una
-- consulta que hizo él (la regla de la policy de hoy); `copiado_por` del servidor. El freno de cifras lo sigue
-- poniendo el trigger bot_copia_frena.
create or replace function public.bot_respuesta_copiada(p_consulta uuid, p_texto text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_email text := (select auth.email()); v_id uuid;
begin
  if not public.es_agente() or v_email is null then raise exception 'Solo el equipo registra copias' using errcode = '42501'; end if;
  if not exists (select 1 from public.bot_consultas q where q.id = p_consulta and q.preguntado_por = v_email) then
    raise exception 'Esa consulta no es tuya' using errcode = '42501';
  end if;
  if p_texto is null or btrim(p_texto) = '' then raise exception 'No hay texto que copiar' using errcode = '22023'; end if;
  insert into public.bot_respuestas_copiadas (consulta_id, texto, copiado_por)
  values (p_consulta, p_texto, v_email)
  on conflict (consulta_id, copiado_por) do update set texto = excluded.texto
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.bot_respuesta_copiada(uuid, text) from public, anon;
grant execute on function public.bot_respuesta_copiada(uuid, text) to authenticated;

-- 5.5 bancos_perfiles: el mapeo de columnas de un extracto (admin + herramienta bancos), forma en lista blanca.
create or replace function public.banco_perfil_guarda(p_cuenta text, p_mapeo jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare k text; val jsonb;
begin
  if not (public.es_admin() and public.puede('bancos')) then
    raise exception 'Los bancos exigen ser administrador con la herramienta «Bancos»' using errcode = '42501';
  end if;
  if jsonb_typeof(p_mapeo) is distinct from 'object' then raise exception 'Columnas del extracto no válidas' using errcode = '22023'; end if;
  for k, val in select * from jsonb_each(p_mapeo) loop
    if k not in ('cabecera', 'fecha', 'fechaValor', 'concepto', 'referencia', 'importe', 'cargo', 'abono', 'saldo', 'moneda', 'formatoFecha', 'monedaFija') then
      raise exception 'Columna del extracto desconocida: %', k using errcode = '22023';
    end if;
    if jsonb_typeof(val) = 'null' then continue; end if;
    if k in ('formatoFecha', 'monedaFija') then
      if jsonb_typeof(val) <> 'string' or char_length(val #>> '{}') > 20 then raise exception 'Valor no válido para %', k using errcode = '22023'; end if;
    elsif jsonb_typeof(val) <> 'number' or (val #>> '{}')::numeric < 0 or (val #>> '{}')::numeric > 1000
          or (val #>> '{}')::numeric <> trunc((val #>> '{}')::numeric) then
      raise exception 'Valor no válido para %', k using errcode = '22023';
    end if;
  end loop;
  -- la cuenta la valida el trigger _bancos_perfil_autoria (y pone quién y cuándo)
  insert into public.bancos_perfiles (cuenta_clave, mapeo) values (p_cuenta, p_mapeo)
  on conflict (cuenta_clave) do update set mapeo = excluded.mapeo;
  return p_cuenta;
end $$;
revoke all on function public.banco_perfil_guarda(text, jsonb) from public, anon;
grant execute on function public.banco_perfil_guarda(text, jsonb) to authenticated;

-- 5.6 Reasignar el autor de un contrato o una factura (super admin). El botón estaba ROTO desde el 26-sep: contratos
-- y facturas ya no admiten update desde el navegador (piezas 1 y 5). Tablas de LISTA CERRADA con sentencias fijas
-- (nunca format('%I', p_tabla)); el nuevo autor, un usuario ACTIVO (nunca null: precedente es_suyo(null)=TRUE); la
-- traza en correcciones_datos en la MISMA transacción (antes: traza, update y «anula la traza» si fallaba).
-- Contrato bloqueado (firmado y sellado): se rechaza, como decía la pantalla — ampliarlo es decisión del owner
-- (contracts/sql/reasignar_autor_bloqueados.sql, sin aplicar). Factura anulada: sí (LAW-71, el trigger
-- factura_anulada_solo_cambia_autor deja exactamente eso).
create or replace function public.reasigna_autor(p_tabla text, p_fila uuid, p_nuevo text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_actual text; v_nuevo text; v_bloq boolean; v_motivo text := btrim(coalesce(p_motivo, ''));
begin
  if not public.es_super_admin() then raise exception 'Reasignar el autor lo hace un super admin' using errcode = '42501'; end if;
  if p_tabla is null or p_tabla not in ('contratos', 'facturas') then raise exception 'Eso no admite reasignar autor' using errcode = '22023'; end if;
  if char_length(v_motivo) < 3 then raise exception 'Escribe el motivo: es lo que explica el cambio dentro de un año' using errcode = '22023'; end if;
  select lower(u.email) into v_nuevo from public.usuarios u where lower(u.email) = lower(btrim(coalesce(p_nuevo, ''))) and u.activo;
  if v_nuevo is null then raise exception 'El nuevo autor tiene que ser un usuario activo del equipo' using errcode = '22023'; end if;

  if p_tabla = 'contratos' then
    select c.creado_por, coalesce(c.bloqueado, false) into v_actual, v_bloq from public.contratos c where c.id = p_fila for update;
    if not found then raise exception 'Ese contrato ya no existe: recarga' using errcode = '22023'; end if;
    if v_bloq then
      raise exception 'Contrato bloqueado: el PDF firmado ya está subido y no admite cambios sobre él' using errcode = '23514';
    end if;
  else
    select f.creado_por into v_actual from public.facturas f where f.id = p_fila for update;
    if not found then raise exception 'Ese documento ya no existe: recarga' using errcode = '22023'; end if;
  end if;
  if lower(coalesce(v_actual, '')) = v_nuevo then raise exception 'Ese ya es el autor' using errcode = '22023'; end if;

  insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_tabla, p_fila, 'creado_por', v_actual, v_nuevo, left(v_motivo, 500), (select auth.email()));
  if p_tabla = 'contratos' then
    update public.contratos set creado_por = v_nuevo where id = p_fila;
  else
    update public.facturas set creado_por = v_nuevo where id = p_fila;
  end if;
  return jsonb_build_object('anterior', v_actual, 'nuevo', v_nuevo);
end $$;
revoke all on function public.reasigna_autor(text, uuid, text, text) from public, anon;
grant execute on function public.reasigna_autor(text, uuid, text, text) to authenticated;
