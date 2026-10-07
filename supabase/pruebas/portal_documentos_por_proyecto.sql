-- Prueba (se revierte sola: acaba en RAISE) de documentos por proyecto con portada en el portal — 7-oct-2026.
-- Hace de comprador del portal (claim app_metadata.portal + su email) con contratos en VARIOS proyectos y
-- comprueba que portal_situacion y el Storage no mezclan ni exponen lo de otro proyecto.
-- Esperado (cualquier «MAL» es fallo):
--   1:proyectos_con_campos_explicitos 2:contrato_con_proyecto_id 3:docs_solo_de_sus_proyectos 4:sin_documentos_generales
--   5:portada_propia_firmable 6:portada_ajena_no 7:portada_vieja_no 8:doc_general_no_firmable 9:doc_ajeno_no_firmable
--   10:anon_sin_permiso

do $$
declare
  v_email text; v_res jsonb; v_out text := ''; v_port text; v_otra text; v_n int;
  v_ids uuid[];
begin
  -- el comprador con contratos en más proyectos distintos
  select pa.email into v_email
    from public.portal_accesos pa
    join public.contrato_compradores cc on cc.client_id = pa.client_id
    join public.contratos c on c.id = cc.contrato_id
   where pa.activo and c.proyecto_id is not null
   group by pa.email order by count(distinct c.proyecto_id) desc limit 1;
  if v_email is null then raise exception 'RESULTADO: sin datos de prueba (ningún comprador con proyectos)'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role','authenticated',
                     'email', v_email, 'app_metadata', json_build_object('portal', true))::text, true);
  v_res := public.portal_situacion();

  -- 1: el bloque proyectos trae exactamente los campos acordados, y ninguno más
  select count(*) into v_n from jsonb_object_keys(v_res->'proyectos'->0) k where k not in ('id','nombre','resort','entrega','mapa','portada');
  v_out := v_out || case when jsonb_array_length(v_res->'proyectos') > 0 and v_n = 0 then '1:proyectos_con_campos_explicitos ' else '1:MAL ' end;
  -- 2: los contratos llevan proyecto_id
  v_out := v_out || case when (v_res->'contratos'->0) ? 'proyecto_id' then '2:contrato_con_proyecto_id ' else '2:MAL ' end;

  select array_agg((e->>'id')::uuid) into v_ids from jsonb_array_elements(v_res->'proyectos') e;
  -- 3: todo documento devuelto pertenece a uno de SUS proyectos (por id) o casa por nombre exacto con uno de sus contratos
  select count(*) into v_n from jsonb_array_elements(v_res->'documentos') d
   where not ((d->>'proyecto_id') is not null and (d->>'proyecto_id')::uuid = any(v_ids))
     and not exists (select 1 from jsonb_array_elements(v_res->'contratos') c
                      where lower(btrim(c->>'proyecto')) = lower(btrim(d->>'proyecto')));
  v_out := v_out || case when v_n = 0 then '3:docs_solo_de_sus_proyectos ' else '3:MAL(' || v_n || ') ' end;
  -- 4: ningún documento general (de la empresa) llega al portal
  select count(*) into v_n from jsonb_array_elements(v_res->'documentos') d
   where (d->>'id')::uuid in (select id from public.documentos_proyecto where general);
  v_out := v_out || case when v_n = 0 then '4:sin_documentos_generales ' else '4:MAL ' end;

  -- 5: la portada propia (la última de su proyecto) se puede firmar
  select (e->>'portada') into v_port from jsonb_array_elements(v_res->'proyectos') e where e->>'portada' is not null limit 1;
  v_out := v_out || case when v_port is not null and public.portal_ve_portada(v_port) then '5:portada_propia_firmable ' else '5:MAL ' end;
  -- 6: la portada de un proyecto ajeno no
  select dp.path into v_otra from public.documentos_proyecto dp
   where dp.categoria = 'portada' and dp.proyecto_id <> all(v_ids) limit 1;
  v_out := v_out || case when v_otra is not null and not public.portal_ve_portada(v_otra) then '6:portada_ajena_no ' else '6:MAL ' end;
  -- 7: una portada VIEJA de un proyecto propio tampoco (solo vale la última)
  select dp.path into v_otra from public.documentos_proyecto dp
   where dp.categoria = 'portada' and dp.proyecto_id = any(v_ids) and dp.path <> all(
     select (e->>'portada') from jsonb_array_elements(v_res->'proyectos') e where e->>'portada' is not null) limit 1;
  v_out := v_out || case when v_otra is null then '7:(sin portada vieja que probar) ' when not public.portal_ve_portada(v_otra) then '7:portada_vieja_no ' else '7:MAL ' end;
  -- 8: un documento general no se puede firmar por ruta
  select dp.path into v_otra from public.documentos_proyecto dp where dp.general limit 1;
  v_out := v_out || case when v_otra is null then '8:(sin general que probar) ' when not public.portal_ve_documento(v_otra) then '8:doc_general_no_firmable ' else '8:MAL ' end;
  -- 9: un documento visible de un proyecto AJENO no se puede firmar
  select dp.path into v_otra from public.documentos_proyecto dp
   where dp.visible_portal and not coalesce(dp.general,false) and dp.proyecto_id is not null and dp.proyecto_id <> all(v_ids) limit 1;
  v_out := v_out || case when v_otra is null then '9:(sin doc ajeno que probar) ' when not public.portal_ve_documento(v_otra) then '9:doc_ajeno_no_firmable ' else '9:MAL ' end;
  -- 10: anon no puede ejecutar la comprobación de portada
  v_out := v_out || case when has_function_privilege('anon', 'public.portal_ve_portada(text)', 'execute') then '10:MAL ' else '10:anon_sin_permiso ' end;

  raise exception 'RESULTADO: %', v_out;
end $$;
