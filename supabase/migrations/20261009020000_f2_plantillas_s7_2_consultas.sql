-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «plantillas de contrato por empresa» · S7 · migracion 2/2 (9-oct-2026): arreglos pedidos por las consultas de Seguridad, Datos y Legal sobre la pantalla «Textos de contrato» (12960163).
--   SEGURIDAD  plantilla_contrato_cuerpo_version y plantilla_contrato_versiones_lista (S2.3, con EXECUTE a authenticated desde S7.1) no limitaban por alcance de empresa: un agente de
--              otra empresa podia leer por id un texto activo o ligado a un contrato, y la lista sin empresa devolvia las versiones activas de todas. Ahora ambas exigen
--              empresa_en_alcance(empresa) (tambien al que es admin: es_admin_de() es verdadero para cualquier empresa si eres admin global, pero el alcance sigue mandando) y la lista
--              filtra por alcance. Dueno lw_lector, security definer, search_path vacio y grants: intactos (create or replace los conserva). Llamadores medidos por grep: solo
--              intranet/v4/assets/textos-contrato.js (lista con empresa; cuerpo_version de una version de la misma empresa) y su arnes; ningun edge ni el bot los llama.
--   LEGAL A    _plantilla_bloques_fijos solo miraba p, li, td, th, h1-h4; el validador de S3 admite div y span, asi que tenencia/escrow/foro metidos en un div, un span, un strong o
--              texto suelto fuera de esos elementos no los veia F2. Ahora, ademas, el RESIDUO (el documento sin comentarios, sin <style> y sin los elementos p/li/td/th/h1-h4, partido
--              por div/br/listas/tablas y sin las etiquetas en linea) se prueba con las mismas reglas y cada trozo que casa es un bloque fijo `R|trozo`. Tambien se normaliza &nbsp;.
--              La regla nueva de tenencia (poder irrevocable/notarial, kuasa, power of attorney, apoderado, nominee, fiduciario, titular formal/registral, a nombre de tercero).
--   LEGAL B    ppjb_parcela y ppjb_construccion llevan clausulas REV04 que Legal debe reclasificar antes de activarse (el owner dijo «todavia no» a lanzar esa reclasificacion):
--              se meten en plantilla_solo_global (una empresa sola no cambia ni una coma) y en plantilla_nunca_activable para lawang y sandal_woods (ni una copia identica al esqueleto se
--              activa). SE QUITAN las cuatro filas cuando Legal las reclasifique. Los borradores ya guardados de esas dos plantillas quedan marcados no activables.
--   LEGAL C    patron de plazo de reserva en plantilla_bloque_regla («prorroga y reserva»).
-- destructivo-ok: redefine 3 funciones (2 RPC de lectura y _plantilla_bloques_fijos), inserta 2 reglas y 6 filas de politica y marca como no activables borradores de 2 plantillas; no toca contratos ni versiones activas
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_plantillas_s7_2.sql

do $g$
begin  -- aborta si lo de produccion no es lo que esta migracion espera reemplazar (no pisar una definicion distinta)
  if pg_get_functiondef('public._plantilla_bloques_fijos(text,text)'::regprocedure) not like '%array[''p'', ''li'', ''td'', ''th'', ''h1'', ''h2'', ''h3'', ''h4'']%' then
    raise exception '_plantilla_bloques_fijos no es la de 20261008990100: no se pisa';
  end if;
  if pg_get_functiondef('public.plantilla_contrato_cuerpo_version(uuid,text)'::regprocedure) like '%empresa_en_alcance%' then
    raise exception 'cuerpo_version ya limita por alcance: nada que hacer';
  end if;
end $g$;

-- ---------------------------------------------------------------- SEGURIDAD: alcance de empresa en las dos lecturas
create or replace function public.plantilla_contrato_cuerpo_version(p_version uuid, p_etag text default null)
 returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_c text;
begin
  if public.uid_sesion() is null or not public.es_agente() then raise exception 'Sin sesion de agente' using errcode = '42501'; end if;
  select * into v from public.plantilla_contrato_versiones x where x.id = p_version;      -- la policy ya filtra por empresa y estado
  if not found then raise exception 'No tienes acceso a ese texto' using errcode = '42501'; end if;
  if not public.empresa_en_alcance(v.empresa) then raise exception 'No tienes acceso a ese texto' using errcode = '42501'; end if;   -- S7.2: el alcance manda antes que el rol
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
       and public.empresa_en_alcance(v.empresa)                                           -- S7.2
       and (v.estado = 'activa' or public.es_admin_de(v.empresa))
     order by v.empresa, v.slug, v.version desc;
end $$;

-- ---------------------------------------------------------------- LEGAL A/C: reglas nuevas
insert into public.plantilla_bloque_regla (slug, tipo, patron, motivo) values
  (null, 'elemento', 'poder (notarial )?(irrevocable|absoluto)|kuasa (mutlak|notaril)|power of attorney|apoderad|nominee|fiduciari|titular (formal|registral)|a nombre de (un )?tercero|atas nama pihak',
   'tenencia y estructura de la propiedad (poderes y nominee)'),
  (null, 'elemento', 'plazo de (la )?reserva|reservation (period|term)|masa (reservasi|berlaku reservasi)', 'prórroga y reserva');

-- ---------------------------------------------------------------- LEGAL A: bloques fijos tambien en div, span, texto suelto
create or replace function public._plantilla_bloques_fijos(p_cuerpo text, p_slug text) returns text[]
language plpgsql stable security definer set search_path = '' as $f$
declare
  res text[] := '{}'; m text[]; tg text; pat_el text; pat_sec text; pieces text[]; i int; piece text; titulo text; resto text; frag text;
begin
  select string_agg('(?:' || patron || ')', '|') into pat_el  from public.plantilla_bloque_regla where tipo = 'elemento' and (slug is null or slug = p_slug);
  select string_agg('(?:' || patron || ')', '|') into pat_sec from public.plantilla_bloque_regla where tipo = 'seccion'  and (slug is null or slug = p_slug);
  -- (a) regiones marcadas por Legal
  for m in select regexp_matches(p_cuerpo, '<!--bloque-fijo:([a-z0-9_]+)-->((?:(?!<!--/bloque-fijo:).)*)<!--/bloque-fijo:\1-->', 'g') loop
    res := res || ('M|' || m[1] || '|' || public._plantilla_ws(m[2]));
  end loop;
  -- (b) elementos por reglas
  if pat_el is not null then
    foreach tg in array array['p', 'li', 'td', 'th', 'h1', 'h2', 'h3', 'h4'] loop
      for m in select regexp_matches(p_cuerpo, '(<' || tg || '(?: [^>]*)?>(?:(?!</' || tg || '>).)*</' || tg || '>)', 'g') loop
        if lower(replace(regexp_replace(m[1], '<[^>]*>', ' ', 'g'), '&nbsp;', ' ')) ~* pat_el then res := res || ('E|' || public._plantilla_ws(m[1])); end if;
      end loop;
    end loop;
    -- (b2) S7.2: el RESIDUO = lo que no esta dentro de un p/li/td/th/h1-h4 (div, span, strong, texto suelto). Sin comentarios ni <style>; se parte por las etiquetas de bloque
    --      y se quitan las de linea (asi «Hak <span>Milik</span>» sigue siendo «Hak Milik»). Cada trozo que casa con las reglas es un bloque fijo.
    resto := regexp_replace(p_cuerpo, '<!--(?:(?!-->).)*-->', '', 'g');
    resto := regexp_replace(resto, '<style(?: [^>]*)?>(?:(?!</style>).)*</style>', '', 'g');
    foreach tg in array array['p', 'li', 'td', 'th', 'h1', 'h2', 'h3', 'h4'] loop
      resto := regexp_replace(resto, '<' || tg || '(?: [^>]*)?>(?:(?!</' || tg || '>).)*</' || tg || '>', E'\n', 'g');
    end loop;
    resto := regexp_replace(resto, '</?(?:div|br|ul|ol|table|thead|tbody|tfoot|tr|body|html|head|title|meta)(?: [^>]*)?/?>', E'\n', 'g');
    resto := replace(regexp_replace(resto, '<[^>]*>', '', 'g'), '&nbsp;', ' ');
    for frag in select regexp_split_to_table(resto, E'\n') loop
      frag := public._plantilla_ws(frag);
      if frag <> '' and lower(frag) ~* pat_el then res := res || ('R|' || frag); end if;
    end loop;
  end if;
  -- (c) secciones <h2> por titulo
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

-- ---------------------------------------------------------------- LEGAL B: REV04 pendientes de reclasificar
insert into public.plantilla_solo_global (slug, motivo) values
  ('ppjb_parcela',      'Lleva cláusulas REV04: pendiente de reclasificar por Legal; solo el administrador global con su abogado (se quita al reclasificar)'),
  ('ppjb_construccion', 'Lleva cláusulas REV04: pendiente de reclasificar por Legal; solo el administrador global con su abogado (se quita al reclasificar)');
insert into public.plantilla_nunca_activable (empresa, slug, motivo)
  select e, s, 'Lleva cláusulas REV04: pendiente de reclasificar por Legal; solo el administrador global con su abogado (se quita al reclasificar)'
    from unnest(array['lawang', 'sandal_woods']) e cross join unnest(array['ppjb_parcela', 'ppjb_construccion']) s;
update public.plantilla_contrato_versiones
   set activable = false,
       bloqueo_motivo = coalesce(bloqueo_motivo || ' | ', '') || 'Lleva cláusulas REV04: pendiente de reclasificar por Legal; solo el administrador global con su abogado (se quita al reclasificar)'
 where slug in ('ppjb_parcela', 'ppjb_construccion') and estado = 'borrador' and origen = 'empresa' and activable;
