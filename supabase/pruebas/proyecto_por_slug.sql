-- Prueba de proyecto-por-slug (15-oct-2026, LAW-428 fase 2 tanda A, migración 20261015213000_proyecto_por_slug_deck.sql).
-- El deck público pregunta por slug y cruza por proyecto_id; las 4 que se quedan (deck_bucket_debido, deck_config_publico,
-- deck_fotos_desajustes, investor_deck_documento_visible) dan LO MISMO que antes del recableo.
--   G1-G8  por cada gemela, sobre un proyecto con deck abierto: count + md5 (filas ordenadas por su texto) = su vieja por nombre, y > 0.
--   G9     slug de un proyecto con deck cerrado y slug inexistente: 0 filas / null en las 8 (no se distingue si existe), como la vieja.
--   G10    anon llama cada gemela con el slug abierto y recibe las mismas filas (camino real: clave publicable, sin token).
--   G11    authenticated NO ejecuta las gemelas (como las viejas: nadie del front las llama con sesión).
--   G12    los dos auxiliares no los ejecuta anon, authenticated, service_role ni lw_lector.
--   G13    proacl EXACTO de cada gemela {postgres, anon}; DEFINER; search_path ''; dueño postgres.
--   G14    recableo antes = después: copia literal del cuerpo vivo del 15-oct en pg_temp («viejo_*») frente a la recableada, para
--          cada foto (deck_bucket_debido), cada slug (deck_config_publico), cada documento (documento_visible y documento_ruta) y
--          deck_fotos_desajustes() con objetos de storage puestos en el bucket equivocado a propósito.
--   G15    investor_deck_reservar ya no la ejecuta service_role ni anon.
--   G16    ninguna gemela recibe un nombre (7.x: p_proyecto / p_proyecto_nombre / p_nombre text).
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada línea acaba en «→ ok» o «→ FALLA». Todo se deshace con el raise final.
-- No hay alta en tablas con serie (contratos, facturas): no gasta números.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
create or replace function pg_temp.val(p_sql text, p_rol text) returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_rol)::text, true);
  execute format('set local role %I', p_rol);
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(t, 'null');
end $f$;
create or replace function pg_temp.err(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then substr(t, 4, 5) end $f$;
-- huella de una función que devuelve filas: «n:md5» con las filas ordenadas por su texto (documentos y forecast pueden empatar en su orden)
create or replace function pg_temp.h(p_sql text) returns text language plpgsql as $f$
declare t text;
begin
  execute format('select count(*) || '':'' || coalesce(md5(string_agg(x::text, ''|'' order by x::text)), ''-'') from (%s) x', p_sql) into t;
  return t;
end $f$;

-- ── cuerpos VIVOS del 15-oct (pg_get_functiondef, md5(prosrc) en supabase/reversion_proyecto_por_slug/REVERSION.sql) ─────────────
create function pg_temp.viejo_deck_bucket_debido(p_ambito text, p_ref uuid) returns text language sql stable as $$
  select case
           when p_ambito = 'modelo' then 'deck'
           when p_ambito = 'proyecto' then
             case coalesce((select t.abrir from public.deck_transiciones t
                             where t.proyecto_id = p_ref and t.desde > now() - interval '15 minutes'),
                           public.deck_proyecto_abierto((select p.nombre from public.proyectos p where p.id = p_ref)))
               when true then 'deck' else 'deck-privado' end
         end;
$$;
create function pg_temp.viejo_deck_config_publico(p_slug text)
returns table(proyecto text, titulo jsonb, meta_desc jsonb, tipo_venta text, modelo_destacado_slug text, masterplan_activo boolean, masterplan_imagen text, kpis jsonb)
language sql stable as $$
  select p.nombre, c.titulo, c.meta_desc, c.tipo_venta, m.slug,
         c.masterplan_activo, c.masterplan_imagen, c.kpis
    from public.proyectos p
    join public.deck_config_proyecto c on c.proyecto_id = p.id
    left join public.modelos m on m.id = c.modelo_destacado_id
   where p.slug = p_slug
     and public.deck_proyecto_abierto(p.nombre);
$$;
create function pg_temp.viejo_documento_visible(d public.documentos_proyecto) returns boolean language sql stable as $$
  select coalesce(d.publicado_investor_deck, false)
     and d.confidencial = false
     and d.categoria <> 'faq'
     and public.deck_proyecto_abierto(d.proyecto)
     and (
       coalesce(d.url, '') <> ''
       or (
         d.path ~ '^proyectos/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|jpe?g|png|webp|docx|xlsx|pptx)$'
         and d.mime = public.investor_deck_documento_mime(d.path)
         and coalesce(d.bytes, 0) between 1 and 52428800
         and exists (select 1 from storage.objects o
                      where o.bucket_id = 'documentacion' and o.name = d.path
                        and o.metadata->>'mimetype' = public.investor_deck_documento_mime(d.path))
       )
     )
$$;
create function pg_temp.viejo_deck_fotos_desajustes(p_proyecto_id uuid default null)
returns table(name text, bucket_real text, bucket_debido text, proyecto_id uuid, motivo text) language sql stable as $$
  with objs as (
    select o.name, o.bucket_id, o.created_at
      from storage.objects o
     where o.bucket_id in ('deck', 'deck-privado')
       and (o.name like 'proyecto/%' or o.name like 'modelo/%')
  ), nombres as (
    select n.name, array_agg(n.bucket_id order by n.bucket_id) as buckets, min(n.created_at) as creado
      from objs n group by n.name
  ), est as (
    select n.name, n.buckets, n.creado, f.ambito, f.proyecto_id, p.nombre, t.abrir as t_abrir, t.desde as t_desde
      from nombres n
      left join public.deck_fotos f on f.path = n.name
      left join public.proyectos p on p.id = f.proyecto_id
      left join public.deck_transiciones t on t.proyecto_id = f.proyecto_id and t.desde > now() - interval '15 minutes'
  ), deb as (
    select e.*,
           case
             when e.ambito is null then case when e.creado > now() - interval '1 hour' then null else 'deck-privado' end
             when e.ambito = 'modelo' then 'deck'
             when e.t_abrir is not null then case when e.t_abrir then 'deck' else 'deck-privado' end
             when public.deck_proyecto_abierto(e.nombre) then 'deck'
             else 'deck-privado'
           end as debido
      from est e
  )
  select d.name,
         case when cardinality(d.buckets) > 1 then 'ambos' else d.buckets[1] end,
         d.debido,
         d.proyecto_id,
         case when cardinality(d.buckets) > 1 then 'en_ambos' when d.ambito is null then 'huerfano' else 'bucket' end
    from deb d
   where d.debido is not null
     and (cardinality(d.buckets) > 1 or d.buckets[1] <> d.debido)
     and (case when p_proyecto_id is null then d.t_desde is null else d.proyecto_id = p_proyecto_id end)
   order by d.name;
$$;

do $todo$
declare
  r text := ''; v text; v2 text; x record; xd public.documentos_proyecto; f text; ok boolean;
  pA uuid; pC uuid; m1 uuid; m2 uuid; dA1 uuid; dA2 uuid; dC uuid; dG uuid;
  fA uuid; fM1 uuid; fC uuid; fM2 uuid;
  c_emp constant text := 'zz_slug';
  c_a  constant text := 'ZZ-SLUG Abierto';  c_sa constant text := 'zz-slug-abierto';
  c_c  constant text := 'ZZ-SLUG Cerrado';  c_sc constant text := 'zz-slug-cerrado';
  -- gemela → (vieja con el nombre, gemela con el slug); %1$s = nombre/slug
  pares constant text[][] := array[
    ['investor_deck_documentos',     'select * from public.investor_deck_documentos(%L)',     'select * from public.investor_deck_documentos_por_slug(%L)'],
    ['investor_deck_faq',            'select * from public.investor_deck_faq(%L)',            'select * from public.investor_deck_faq_por_slug(%L)'],
    ['investor_deck_forecast',       'select * from public.investor_deck_forecast(%L)',       'select * from public.investor_deck_forecast_por_slug(%L)'],
    ['investor_deck_fotos',          'select * from public.investor_deck_fotos(%L)',          'select * from public.investor_deck_fotos_por_slug(%L)'],
    ['investor_deck_modelos',        'select * from public.investor_deck_modelos(%L)',        'select * from public.investor_deck_modelos_por_slug(%L)'],
    ['investor_deck_parcelas',       'select * from public.investor_deck_parcelas(%L)',       'select * from public.investor_deck_parcelas_por_slug(%L)'],
    ['parcelas_tamanos_disponibles', 'select * from public.parcelas_tamanos_disponibles(%L)', 'select * from public.parcelas_tamanos_disponibles_por_slug(%L)'],
    ['deck_ubicacion_publica',       'select public.deck_ubicacion_publica(%L) u',            'select public.deck_ubicacion_publica_por_slug(%L) u']];
  gemelas constant text[] := array[
    'investor_deck_documentos_por_slug(text)', 'investor_deck_faq_por_slug(text)', 'investor_deck_forecast_por_slug(text)',
    'investor_deck_fotos_por_slug(text)', 'investor_deck_modelos_por_slug(text)', 'investor_deck_parcelas_por_slug(text)',
    'parcelas_tamanos_disponibles_por_slug(text)', 'deck_ubicacion_publica_por_slug(text)'];
  i int;
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS PROYECTO POR SLUG:%', E'\nP0 esta prueba monta filas y objetos de storage: solo corre en rama → FALLA';
  end if;

  -- ============================================================ montaje: A con deck abierto, C cerrado (mismos tipos de fila en los dos)
  insert into public.empresas (clave, nombre) values (c_emp, 'ZZ-SLUG Empresa');
  insert into public.proyectos (nombre, slug, empresa, activo, ubicacion_maps) values (c_a, c_sa, c_emp, true, '-8.5123, 115.2634') returning id into pA;
  insert into public.proyectos (nombre, slug, empresa, activo, ubicacion_maps) values (c_c, c_sc, c_emp, true, '-8.6, 115.3') returning id into pC;
  insert into public.unidades (codigo, proyecto, proyecto_id, tipo, superficie_m2, precio, precio_suelo, moneda, estado, publicado_investor_deck) values
    ('ZZS-A1', c_a, pA, 'parcela', 300, 100000, 90000, 'EUR', 'disponible', true),
    ('ZZS-A2', c_a, pA, 'parcela', 400, null,   80000, 'EUR', 'reservada',  true),
    ('ZZS-A3', c_a, pA, 'parcela', 500, 120000, 110000,'EUR', 'disponible', false),
    ('ZZS-C1', c_c, pC, 'parcela', 600, 130000, 120000,'EUR', 'disponible', false);
  insert into public.modelos (slug, nombre, dormitorios, precio_construccion, moneda, publicado, activo, orden)
       values ('zz-slug-m1', 'ZZ-SLUG M1', 2, 50000, 'EUR', true, true, 1) returning id into m1;
  insert into public.modelos (slug, nombre, dormitorios, precio_construccion, moneda, publicado, activo, orden)
       values ('zz-slug-m2', 'ZZ-SLUG M2', 3, 60000, 'EUR', true, true, 2) returning id into m2;
  insert into public.modelos_villa (proyecto, proyecto_id, modelo, modelo_id, precio_construccion, moneda) values
    (c_a, pA, 'ZZ-SLUG M1', m1, 70000, 'EUR'), (c_a, pA, 'ZZ-SLUG M2', m2, null, null), (c_c, pC, 'ZZ-SLUG M2', m2, 65000, 'EUR');
  insert into public.deck_fotos (ambito, proyecto_id, uso, tipo, path, pie, orden) values
    ('proyecto', pA, 'galeria', 'foto', 'proyecto/' || pA || '/00000000-0000-0000-0000-00000000a001.webp', '{"en":"A"}', 0) returning id into fA;
  insert into public.deck_fotos (ambito, modelo_id, uso, tipo, path, pie, orden) values
    ('modelo', m1, 'galeria', 'foto', 'modelo/' || m1 || '/00000000-0000-0000-0000-00000000b001.webp', '{"en":"M1"}', 0) returning id into fM1;
  insert into public.deck_fotos (ambito, proyecto_id, uso, tipo, path, pie, orden) values
    ('proyecto', pC, 'galeria', 'foto', 'proyecto/' || pC || '/00000000-0000-0000-0000-00000000c001.webp', '{"en":"C"}', 0) returning id into fC;
  insert into public.deck_fotos (ambito, modelo_id, uso, tipo, path, pie, orden) values
    ('modelo', m2, 'hero', 'render', 'modelo/' || m2 || '/00000000-0000-0000-0000-00000000b002.webp', '{"en":"M2"}', 1) returning id into fM2;
  insert into public.deck_faq (proyecto_id, pregunta, respuesta, orden, publicado) values
    (pA, '{"en":"q1"}', '{"en":"a1"}', 1, true), (pA, '{"en":"q2"}', '{"en":"a2"}', 2, false), (pC, '{"en":"qc"}', '{"en":"ac"}', 1, true);
  insert into public.deck_forecast_proyecto (proyecto_id, pct_gestion, pct_mantenimiento, pct_impuesto, publicado) values
    (pA, 20, 5, 10, true), (pC, 20, 5, 10, true);
  insert into public.deck_forecast (proyecto_id, modelo_id, adr_medio, adr_optimo, ocupacion_media, ocupacion_optima, inversion_base, moneda, publicado, orden) values
    (pA, m1, 150, 200, 0.6, 0.8, 250000, 'EUR', true, 1), (pA, m2, 180, 220, 0.6, 0.8, 300000, 'EUR', true, 1),
    (pC, m2, 150, 200, 0.6, 0.8, 250000, 'EUR', true, 1);
  insert into public.documentos_proyecto (proyecto, proyecto_id, titulo, url, categoria, publicado_investor_deck, confidencial) values
    (c_a, pA, 'ZZ doc A1', 'https://drive.google.com/zz-a1', 'comercial', true, false) returning id into dA1;
  insert into public.documentos_proyecto (proyecto, proyecto_id, titulo, url, categoria, publicado_investor_deck, confidencial) values
    (c_a, pA, 'ZZ doc A2 confidencial', 'https://drive.google.com/zz-a2', 'legal', true, true) returning id into dA2;
  insert into public.documentos_proyecto (proyecto, proyecto_id, titulo, url, categoria, publicado_investor_deck, confidencial) values
    (c_c, pC, 'ZZ doc C', 'https://drive.google.com/zz-c', 'comercial', true, false) returning id into dC;
  insert into public.documentos_proyecto (proyecto, proyecto_id, titulo, url, categoria, publicado_investor_deck, confidencial) values
    ('ZZ-SLUG (general)', null, 'ZZ doc general', 'https://drive.google.com/zz-g', 'comercial', true, false) returning id into dG;
  insert into public.deck_config_proyecto (proyecto_id, titulo, meta_desc, tipo_venta, modelo_destacado_id) values
    (pA, '{"en":"A"}', '{"en":"A"}', 'parcela', m1), (pC, '{"en":"C"}', '{"en":"C"}', 'parcela', m2);

  -- ============================================================ G1-G9 vieja por nombre = gemela por slug
  for i in 1 .. array_length(pares, 1) loop
    v  := pg_temp.h(format(pares[i][2], c_a));
    v2 := pg_temp.h(format(pares[i][3], c_sa));
    r := r || pg_temp.l(v = v2 and split_part(v, ':', 1)::int > 0 and v not like '%:-',
                        format('G%s %s: abierto, vieja %s = gemela %s', i, pares[i][1], v, v2));
    v  := pg_temp.h(format(pares[i][2], c_c));
    v2 := pg_temp.h(format(pares[i][3], c_sc)) || ' / ' || pg_temp.h(format(pares[i][3], 'zz-slug-no-existe'));
    r := r || pg_temp.l(v2 in ('0:- / 0:-', '1:' || md5('()') || ' / 1:' || md5('()')) and v = split_part(v2, ' / ', 1),
                        format('G9.%s %s: cerrado e inexistente dan lo mismo y nada (vieja cerrado %s, gemela %s)', i, pares[i][1], v, v2));
  end loop;

  -- ============================================================ G10-G11 por el rol real
  for i in 1 .. array_length(pares, 1) loop
    v  := pg_temp.h(format(pares[i][3], c_sa));
    v2 := pg_temp.val(format('select count(*)::text from (%s) x', format(pares[i][3], c_sa)), 'anon');
    r := r || pg_temp.l(v2 = split_part(v, ':', 1), format('G10.%s anon llama %s_por_slug: %s filas (esperadas %s)', i, pares[i][1], v2, split_part(v, ':', 1)));
    v2 := pg_temp.val(format('select count(*)::text from (%s) x', format(pares[i][3], c_sa)), 'authenticated');
    r := r || pg_temp.l(pg_temp.err(v2) = '42501', format('G11.%s authenticated NO llama %s_por_slug (%s)', i, pares[i][1], left(v2, 60)));
  end loop;

  -- ============================================================ G12-G13 permisos y forma
  foreach f in array array['deck_proyecto_abierto_por_id(uuid)', '_proyecto_deck_abierto_de_slug(text)'] loop
    select string_agg(rl || '=' || has_function_privilege(rl, 'public.' || f, 'execute'), ' ') into v
      from unnest(array['anon', 'authenticated', 'service_role', 'lw_lector']) rl;
    r := r || pg_temp.l(v !~ '=true', 'G12 nadie ejecuta el auxiliar ' || f || ' (' || v || ')');
  end loop;
  foreach f in array gemelas loop
    -- por privilegio efectivo, no por el texto de proacl (el orden y los defaults de la rama pueden variar): anon sí; authenticated,
    -- service_role y lw_lector no; y ninguna entrada de PUBLIC («=X/» al principio de un elemento del aclitem[])
    select format('%s|%s|%s|anon=%s auth=%s srv=%s lwl=%s public=%s', pg_get_userbyid(p.proowner), p.prosecdef, p.proconfig::text,
                  has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                  has_function_privilege('service_role', p.oid, 'execute'), has_function_privilege('lw_lector', p.oid, 'execute'),
                  coalesce(p.proacl::text, '(defecto)') ~ '(^\{|,)=X/') into v
      from pg_proc p where p.oid = to_regprocedure('public.' || f);
    r := r || pg_temp.l(v = 'postgres|true|{"search_path=\"\""}|anon=true auth=false srv=false lwl=false public=false',
                        'G13 forma de ' || f || ' (' || coalesce(v, 'NO EXISTE') || ')');
    select pg_get_function_arguments(to_regprocedure('public.' || f)) into v;
    r := r || pg_temp.l(v !~* '\m(p_proyecto|p_proyecto_nombre|p_nombre) text\M', 'G16 ' || f || ' no recibe un nombre (' || v || ')');
  end loop;

  -- ============================================================ G14 recableo: antes (cuerpo vivo) = después
  for x in select f.id, f.ambito, coalesce(f.proyecto_id, f.modelo_id) ref from public.deck_fotos f where f.id in (fA, fM1, fC, fM2)
           union all select null, 'proyecto', gen_random_uuid() loop
    v := pg_temp.viejo_deck_bucket_debido(x.ambito, x.ref); v2 := public.deck_bucket_debido(x.ambito, x.ref);
    r := r || pg_temp.l(v is not distinct from v2, format('G14a deck_bucket_debido(%s) antes %s = después %s', x.ambito, v, v2));
  end loop;
  r := r || pg_temp.l(public.deck_bucket_debido('proyecto', pA) = 'deck' and public.deck_bucket_debido('proyecto', pC) = 'deck-privado',
                      'G14b el bucket debido sigue la puerta: A abierto → deck, C cerrado → deck-privado');
  foreach f in array array[c_sa, c_sc, 'zz-slug-no-existe'] loop
    v := pg_temp.h(format('select * from pg_temp.viejo_deck_config_publico(%L)', f)); v2 := pg_temp.h(format('select * from public.deck_config_publico(%L)', f));
    r := r || pg_temp.l(v = v2, format('G14c deck_config_publico(%s) antes %s = después %s', f, v, v2));
  end loop;
  for xd in select d.* from public.documentos_proyecto d where d.id in (dA1, dA2, dC, dG) loop
    ok := pg_temp.viejo_documento_visible(xd) is not distinct from public.investor_deck_documento_visible(xd);
    r := r || pg_temp.l(ok, format('G14d documento_visible(%s) antes = después (%s)', xd.titulo, public.investor_deck_documento_visible(xd)));
  end loop;
  r := r || pg_temp.l(public.investor_deck_documento_visible((select d from public.documentos_proyecto d where d.id = dA1))
                      and not public.investor_deck_documento_visible((select d from public.documentos_proyecto d where d.id = dA2))
                      and not public.investor_deck_documento_visible((select d from public.documentos_proyecto d where d.id = dC))
                      and not public.investor_deck_documento_visible((select d from public.documentos_proyecto d where d.id = dG)),
                      'G14e visible solo el de A publicado y no confidencial (C cerrado y «general» sin proyecto, fuera)');
  -- documento_ruta: sólo sirve ficheros (url vacía); un documento con enlace da 0 filas por las dos vías
  v := pg_temp.h(format('select * from public.investor_deck_documento_ruta(%L)', dA1));
  r := r || pg_temp.l(v = '0:-', 'G14f investor_deck_documento_ruta de un enlace sigue sin servirlo (' || v || ')');
  -- desajustes: objetos puestos en el bucket equivocado a propósito (A en privado, C en público, M1 en los dos)
  insert into storage.buckets (id, name, public) values ('deck', 'deck', true), ('deck-privado', 'deck-privado', false) on conflict (id) do nothing;
  insert into storage.objects (bucket_id, name) values
    ('deck-privado', (select path from public.deck_fotos where id = fA)),
    ('deck',         (select path from public.deck_fotos where id = fC)),
    ('deck',         (select path from public.deck_fotos where id = fM1)),
    ('deck-privado', (select path from public.deck_fotos where id = fM1));
  v := pg_temp.h('select * from pg_temp.viejo_deck_fotos_desajustes()'); v2 := pg_temp.h('select * from public.deck_fotos_desajustes()');
  r := r || pg_temp.l(v = v2 and split_part(v, ':', 1)::int >= 3, format('G14g deck_fotos_desajustes() antes %s = después %s (≥3 desajustes montados)', v, v2));
  v := pg_temp.h(format('select * from pg_temp.viejo_deck_fotos_desajustes(%L)', pA)); v2 := pg_temp.h(format('select * from public.deck_fotos_desajustes(%L)', pA));
  r := r || pg_temp.l(v = v2, format('G14h deck_fotos_desajustes(A) antes %s = después %s', v, v2));
  -- una transición reciente manda sobre la puerta, igual que antes
  insert into public.deck_transiciones (proyecto_id, abrir, desde) values (pC, true, now());
  v := pg_temp.viejo_deck_bucket_debido('proyecto', pC); v2 := public.deck_bucket_debido('proyecto', pC);
  r := r || pg_temp.l(v = v2 and v2 = 'deck', format('G14i con transición «abrir» reciente, C → %s (antes %s)', v2, v));

  -- ============================================================ G15 investor_deck_reservar cerrada
  select string_agg(rl || '=' || has_function_privilege(rl, 'public.investor_deck_reservar(text, text, text, text, text, text, text, text)', 'execute'), ' ') into v
    from unnest(array['anon', 'authenticated', 'service_role']) rl;
  r := r || pg_temp.l(v !~ '=true', 'G15 investor_deck_reservar no la ejecuta nadie del API (' || v || ')');

  raise exception 'FIN DE PRUEBAS PROYECTO POR SLUG (se deshace todo):%', r;
end $todo$;
