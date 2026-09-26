-- Consulta de Seguridad sobre B4/B5 (27-sep-2026): un documento YA publicado en el dosier de inversores lo sirve
-- `investor_deck_documentos` a anon (título, descripción, url, categoría, filtrado por proyecto). Un agente con
-- «documentacion» podía cambiar su url/título/descripción o moverlo a otro proyecto suyo, es decir, publicar
-- contenido nuevo en una página pública sin pasar por admin. Desde aquí, un documento publicado solo lo cambia un
-- admin en lo que ve el público. Parche con marca sobre la función viva: idempotente, y falla si cambió.
do $$
declare v_def text; v_nuevo text;
begin
  select pg_get_functiondef('public.documento_proyecto_guarda(uuid,jsonb)'::regprocedure) into v_def;
  if strpos(v_def, 'B4 publicado solo admin') > 0 then return; end if;
  v_nuevo := replace(v_def,
    '  if v.publicado_investor_deck and v.confidencial then',
    '  -- B4 publicado solo admin: lo que ya sirve el dosier público no lo cambia un agente
  if p_id is not null and coalesce(v_old.publicado_investor_deck, false) and not v_admin
     and (v.url is distinct from v_old.url or v.titulo is distinct from v_old.titulo
          or v.descripcion is distinct from v_old.descripcion or v.categoria is distinct from v_old.categoria
          or v.proyecto is distinct from v_old.proyecto or v.proyecto_id is distinct from v_old.proyecto_id) then
    raise exception ''Este documento está publicado en el dosier de inversores: su título, enlace, descripción, categoría y proyecto los cambia administración'' using errcode = ''42501'';
  end if;
  if v.publicado_investor_deck and v.confidencial then');
  if v_nuevo = v_def then raise exception 'documento_proyecto_guarda cambió: no encuentro dónde insertar la comprobación'; end if;
  execute v_nuevo;
end $$;
