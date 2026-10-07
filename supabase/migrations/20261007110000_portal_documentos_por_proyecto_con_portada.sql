-- Portal: documentos por proyecto con portada (7-oct-2026, owner: «si invierto en varios proyectos
-- necesito ver la info bien de cada proyecto, con una fotillo como en la intranet, ocultando la
-- info global»).
--
-- Revisión previa Seguridad (7-oct), recogida entera:
--  · La visibilidad de un documento dejaba de depender de `mismo_proyecto` (casa por LIKE: «River»
--    casa con «Riverfront I/II/III»). Hoy no desborda (236 pares comprador-documento, todos por
--    igualdad), pero es un riesgo latente y al agrupar en carpetas se mezclarían. Ahora manda el
--    proyecto_id; solo si a alguno de los dos lados le falta, igualdad EXACTA de nombre (sin LIKE).
--    Medido antes de aplicar: 236 pares con la regla vieja, 236 con la nueva, 0 de diferencia.
--  · Los documentos `general` (de la empresa, sin proyecto real) quedan fuera del portal, también
--    para firmar la ruta en Storage, no solo en la lista.
--  · La portada NO se cuela en portal_ve_documento con un OR: tiene su propia función y su propia
--    policy, y solo deja firmar la ÚLTIMA portada de un proyecto del comprador.
--  · portal_situacion devuelve campos EXPLÍCITOS del proyecto (nunca to_jsonb de la fila), una sola
--    portada por proyecto y solo de los proyectos donde el comprador tiene contrato.

-- Casado de proyecto, un solo sitio. Solo lo llaman funciones SECURITY DEFINER: nadie más lo ejecuta.
create or replace function public.portal_doc_es_de_proyecto(a_id uuid, a_nombre text, b_id uuid, b_nombre text)
returns boolean
language sql
immutable
set search_path to ''
as $$
  select case
           when a_id is not null and b_id is not null then a_id = b_id
           else a_nombre is not null and b_nombre is not null
                and lower(btrim(a_nombre)) = lower(btrim(b_nombre))
         end
$$;
revoke all on function public.portal_doc_es_de_proyecto(uuid, text, uuid, text) from public, anon, authenticated;

create or replace function public.portal_ve_documento(p_name text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$ select public.es_portal() and exists (
     select 1
       from documentos_proyecto dp
      where dp.visible_portal
        and not coalesce(dp.general, false)
        and dp.path = p_name
        and exists (
          select 1
            from portal_accesos pa
            join contrato_compradores cc on cc.client_id = pa.client_id
            join contratos c on c.id = cc.contrato_id
           where pa.activo
             and pa.email = lower(coalesce(auth.email(), ''))
             and public.portal_doc_es_de_proyecto(dp.proyecto_id, dp.proyecto, c.proyecto_id, c.proyecto_nombre))) $$;

-- La portada de un proyecto del comprador: solo la última, solo si el proyecto es suyo.
create or replace function public.portal_ve_portada(p_name text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$ select public.es_portal() and exists (
     select 1
       from documentos_proyecto dp
      where dp.categoria = 'portada'
        and dp.path = p_name
        and dp.proyecto_id is not null
        and dp.id = (select d2.id from documentos_proyecto d2
                      where d2.categoria = 'portada' and d2.proyecto_id = dp.proyecto_id
                      order by d2.creado_en desc limit 1)
        and exists (
          select 1
            from portal_accesos pa
            join contrato_compradores cc on cc.client_id = pa.client_id
            join contratos c on c.id = cc.contrato_id
           where pa.activo
             and pa.email = lower(coalesce(auth.email(), ''))
             and c.proyecto_id = dp.proyecto_id)) $$;
revoke all on function public.portal_ve_portada(text) from public, anon;
grant execute on function public.portal_ve_portada(text) to authenticated;

do $$ begin
  if not exists (select 1 from pg_policy where polrelid = 'storage.objects'::regclass and polname = 'portal lee la portada de sus proyectos') then
    create policy "portal lee la portada de sus proyectos" on storage.objects
      for select to authenticated
      using (bucket_id = 'documentacion' and public.portal_ve_portada(name));
  end if;
end $$;

-- portal_situacion: documentos con el mismo casado, sin `general`, con proyecto_id; contratos con
-- proyecto_id; y un bloque `proyectos` con campos explícitos. Parche por marcas de código puro,
-- idempotente y con raise si no las encuentra.
do $$
declare
  v_def text := pg_get_functiondef('public.portal_situacion()'::regprocedure);
  v_ini int; v_fin int;
  v_docs text :=
$d$'documentos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',          dp.id,
        'titulo',      dp.titulo,
        'descripcion', dp.descripcion,
        'categoria',   dp.categoria,
        'proyecto',    dp.proyecto,
        'proyecto_id', dp.proyecto_id,
        'url',         dp.url,
        'path',        dp.path
      ) order by dp.creado_en desc)
      from public.documentos_proyecto dp
     where dp.visible_portal
       and not coalesce(dp.general, false)
       and exists (
         select 1 from public.contratos c3
         join mis_ids m3 on m3.id = c3.id
        where public.portal_doc_es_de_proyecto(dp.proyecto_id, dp.proyecto, c3.proyecto_id, c3.proyecto_nombre)
       )), '[]'::jsonb),
    'proyectos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',      p.id,
        'nombre',  p.nombre,
        'resort',  p.resort,
        'entrega', p.fecha_entrega_estimada_proyecto,
        'mapa',    p.ubicacion_maps,
        'portada', (select d.path from public.documentos_proyecto d
                     where d.categoria = 'portada' and d.proyecto_id = p.id
                     order by d.creado_en desc limit 1)
      ) order by p.nombre)
      from public.proyectos p
     where p.id in (select c4.proyecto_id from public.contratos c4
                      join mis_ids m4 on m4.id = c4.id
                     where c4.proyecto_id is not null)), '[]'::jsonb),
    $d$;
begin
  if position('''proyectos'', coalesce((' in v_def) > 0 then return; end if;
  v_ini := position('''documentos'', coalesce((' in v_def);
  v_fin := position('''kyc'', coalesce((' in v_def);
  if v_ini = 0 or v_fin = 0 or v_fin < v_ini then
    raise exception 'portal_situacion: no encuentro las marcas de documentos/kyc; no se parchea';
  end if;
  v_def := substr(v_def, 1, v_ini - 1) || v_docs || substr(v_def, v_fin);
  if position('''proyecto'',    c.proyecto_nombre,' in v_def) = 0 then
    raise exception 'portal_situacion: no encuentro la marca de contratos; no se parchea';
  end if;
  v_def := replace(v_def, '''proyecto'',    c.proyecto_nombre,',
                          '''proyecto'',    c.proyecto_nombre,' || chr(10) || '        ''proyecto_id'',  c.proyecto_id,');
  execute v_def;
end $$;
