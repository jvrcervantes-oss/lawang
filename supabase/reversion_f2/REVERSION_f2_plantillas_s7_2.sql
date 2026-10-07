-- Reversion de la migracion 20261009020000 (S7.2 · arreglos de las consultas de Seguridad y Legal, 9-oct-2026).
-- Devuelve plantilla_contrato_cuerpo_version y plantilla_contrato_versiones_lista a su definicion de 20261008980200 (sin filtro de alcance de empresa: OJO, vuelve el hueco de
-- Seguridad mientras ambas tengan EXECUTE para authenticated), _plantilla_bloques_fijos a la de 20261008990100 (solo p/li/td/th/h1-h4, sin residuo) y quita las 2 reglas nuevas
-- y las 6 filas de politica REV04 (ppjb_parcela / ppjb_construccion en solo-global y nunca-activable). NO deshace el update que marco como no activables los borradores de esas
-- dos plantillas: se reactivan guardando el borrador otra vez (el flag lo recalcula guarda_borrador). Dueno lw_lector y grants se conservan (create or replace).
-- destructivo-ok: restituye funciones previas y borra solo las filas de politica que creo la migracion; no toca contratos ni versiones
begin;
create or replace function public.plantilla_contrato_cuerpo_version(p_version uuid, p_etag text default null)
 returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_c text;
begin
  if public.uid_sesion() is null or not public.es_agente() then raise exception 'Sin sesion de agente' using errcode = '42501'; end if;
  select * into v from public.plantilla_contrato_versiones x where x.id = p_version;      -- la policy ya filtra por empresa y estado
  if not found then raise exception 'No tienes acceso a ese texto' using errcode = '42501'; end if;
  if not public.es_admin_de(v.empresa) and v.estado <> 'activa'
     and not exists (select 1 from public.contrato_plantilla_version l where l.version_id = v.id) then
    raise exception 'No tienes acceso a ese texto' using errcode = '42501';
  end if;
  if p_etag is not null and p_etag = v.hash then
    return jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'hash', v.hash, 'estado', v.estado, 'sin_cambios', true);
  end if;
  select c.cuerpo_html into v_c from public.plantilla_contrato_cuerpos c where c.version_id = v.id;
  return jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'hash', v.hash, 'estado', v.estado, 'origen', v.origen, 'cuerpo_html', v_c);
end $$;

create or replace function public.plantilla_contrato_versiones_lista(p_empresa text default null, p_slug text default null)
 returns table (id uuid, empresa text, slug text, version int, estado text, origen text, idioma_set text[], hash text, bytes int, activable boolean, bloqueo_motivo text,
                autor text, fecha timestamptz, motivo text, activado_por text, activado_en timestamptz, confirmacion_nombre text, retirada_por text, retirada_en timestamptz, hereda_de uuid)
 language plpgsql stable security definer set search_path = '' as $$
begin
  if public.uid_sesion() is null or not public.es_agente() then raise exception 'Sin sesion de agente' using errcode = '42501'; end if;
  if p_empresa is not null and not public.empresa_en_alcance(p_empresa) then raise exception 'Esa empresa no es de tu alcance' using errcode = '42501'; end if;
  return query
    select v.id, v.empresa, v.slug, v.version, v.estado, v.origen, v.idioma_set, v.hash, v.bytes, v.activable, v.bloqueo_motivo,
           v.autor, v.fecha, v.motivo, v.activado_por, v.activado_en, v.confirmacion_nombre, v.retirada_por, v.retirada_en, v.hereda_de
      from public.plantilla_contrato_versiones v
     where (p_empresa is null or v.empresa = p_empresa) and (p_slug is null or v.slug = p_slug)
       and (v.estado = 'activa' or public.es_admin_de(v.empresa))
     order by v.empresa, v.slug, v.version desc;
end $$;

create or replace function public._plantilla_bloques_fijos(p_cuerpo text, p_slug text) returns text[]
language plpgsql stable security definer set search_path = '' as $f$
declare
  res text[] := '{}'; m text[]; tg text; pat_el text; pat_sec text; pieces text[]; i int; piece text; titulo text;
begin
  select string_agg('(?:' || patron || ')', '|') into pat_el  from public.plantilla_bloque_regla where tipo = 'elemento' and (slug is null or slug = p_slug);
  select string_agg('(?:' || patron || ')', '|') into pat_sec from public.plantilla_bloque_regla where tipo = 'seccion'  and (slug is null or slug = p_slug);
  for m in select regexp_matches(p_cuerpo, '<!--bloque-fijo:([a-z0-9_]+)-->((?:(?!<!--/bloque-fijo:).)*)<!--/bloque-fijo:\1-->', 'g') loop
    res := res || ('M|' || m[1] || '|' || public._plantilla_ws(m[2]));
  end loop;
  if pat_el is not null then
    foreach tg in array array['p', 'li', 'td', 'th', 'h1', 'h2', 'h3', 'h4'] loop
      for m in select regexp_matches(p_cuerpo, '(<' || tg || '(?: [^>]*)?>(?:(?!</' || tg || '>).)*</' || tg || '>)', 'g') loop
        if lower(regexp_replace(m[1], '<[^>]*>', ' ', 'g')) ~* pat_el then res := res || ('E|' || public._plantilla_ws(m[1])); end if;
      end loop;
    end loop;
  end if;
  if pat_sec is not null then
    pieces := string_to_array(p_cuerpo, '<h2');
    for i in 2 .. coalesce(cardinality(pieces), 0) loop
      piece := pieces[i];
      titulo := lower(public._plantilla_ws(regexp_replace(split_part(piece, '</h2>', 1), '<[^>]*>', ' ', 'g')));
      if titulo ~* pat_sec then res := res || ('S|' || public._plantilla_ws('<h2' || piece)); end if;
    end loop;
  end if;
  return res;
end $f$;
revoke all on function public._plantilla_bloques_fijos(text, text) from public, anon, authenticated, service_role;

delete from public.plantilla_bloque_regla where slug is null and tipo = 'elemento'
  and (patron like 'poder (notarial )?(irrevocable|absoluto)|kuasa%' or patron like 'plazo de (la )?reserva|reservation%');
delete from public.plantilla_nunca_activable where slug in ('ppjb_parcela', 'ppjb_construccion') and motivo like 'Lleva cl%REV04%';
delete from public.plantilla_solo_global where slug in ('ppjb_parcela', 'ppjb_construccion') and motivo like 'Lleva cl%REV04%';
commit;
