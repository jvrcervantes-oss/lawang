-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «plantillas de contrato por empresa» · S2 · migracion 5 (7-oct-2026): BLOQUEOS que cierran F1 y F2 de la revision de Seguridad de S2+S3. Va DESPUES de S3 (990000)
--   porque parchea sus listas cerradas; las funciones de S3 solo se tocan aqui (nunca en 990000).
--   F1  texto de OTRA sociedad. `_plantilla_otra_sociedad(cuerpo, empresa)` quita comentarios, etiquetas, entidades (tambien las numericas) y marcadores {{}}, normaliza (NFKD + sin
--       marcas combinantes = equivale a NFKC para este uso, minusculas, solo a-z0-9) y busca razon social (sin PT / Ltd), marca (y su primera palabra), NPWP y NIB (digitos), segmentos
--       largos del domicilio de las sociedades de `sociedades` que NO son propias de la empresa. Propia = `empresas.sociedad_clave` + `plantilla_sociedad_cruce` (la lista de cruces
--       empresa-sociedad aun no la ha dado el owner: la tabla nace vacia y la edita solo postgres). Los campos vacios se saltan y se resta lo que contiene la sociedad propia.
--       `plantilla_contrato_guarda_borrador` fija activable=false + bloqueo_motivo (sin repetir el dato) y `plantilla_contrato_activa` lo vuelve a comprobar en servidor (55000).
--       «Nunca activable» por lista de slugs (`plantilla_nunca_activable`: Sandal Woods ← cc00014_timon, ppjb_bonian_c2, anexo_x/y_bonian_c2) y `estatutos_sw` no activable mientras
--       `promotora_razon` este vacio en `plantilla_ficha` (campo que da el owner; no se rellena con nada plausible).
--   F2  bloques que una empresa sola NO edita (foro/ley/arbitraje, tenencia, escrow/impuestos, prorroga, defectos, datos, partes/firmas, clausulas negociadas, notariales, estatutos):
--       `_plantilla_exige_bloques` compara el cuerpo nuevo con el esqueleto: los bloques fijos tienen que quedar IDENTICOS y en el mismo orden; solo el super global los cambia.
--       Un bloque fijo es (a) lo que va entre `<!--bloque-fijo:X-->` y `<!--/bloque-fijo:X-->` (marcas que la v2 de Legal anadira: aqui se aceptan en el validador de S3), o, mientras
--       no existan, (b) cada p/li/td/th/h1-h4 cuyo texto casa con las reglas de `plantilla_bloque_regla` y cada seccion `<h2>` cuyo titulo casa; (c) plantillas enteras solo-global
--       (`plantilla_solo_global`: hak_sewa_notario, poa_notario, estatutos_sw). Las reglas son editables solo por postgres. Por contrapartida, una empresa tampoco puede ANADIR a un
--       parrafo libre una de esas palabras (se rechaza con un mensaje que lo explica).
--   S3: `prom_cargo`, `promotora_razon` y los comentarios `bloque-fijo:{foro_ley,tenencia,escrow,impuestos,prorroga,defectos,notarial,partes,firmas,datos,negociadas}` entran en las listas
--       cerradas (lo nuevo nace cerrado: solo esos). service_role revocado en las 9 funciones de S3 (la carga de S4 corre como postgres).
--   Reducir la exposicion (CEO 7-oct): EXECUTE revocado a `authenticated` en las 8 RPC de usuario de S2 hasta que S5/S7 las llamen; esas migraciones haran el GRANT con su llamador.
-- destructivo-ok: crea 5 tablas y funciones nuevas, redefine 2 RPC de S2 y 2 funciones de S3 (listas/analizador) y revoca EXECUTE; no toca filas de contratos ni de plantillas
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_plantillas_s2_5.sql

-- ================================================================= tablas de politica (solo postgres: sin GRANT ni policy)
create table public.plantilla_sociedad_cruce (
  empresa        text not null references public.empresas (clave),
  sociedad_clave text not null references public.sociedades (clave),
  propia         boolean not null default true,
  nota           text,
  primary key (empresa, sociedad_clave)
);
comment on table public.plantilla_sociedad_cruce is 'Sociedades que cuentan como PROPIAS de una empresa ademas de empresas.sociedad_clave (lista de cruces del owner, pendiente 7-oct-2026). Solo postgres.';

create table public.plantilla_nunca_activable (
  empresa text not null references public.empresas (clave),
  slug    text not null references public.plantillas_contrato (slug),
  motivo  text not null check (btrim(motivo) <> ''),
  primary key (empresa, slug)
);
insert into public.plantilla_nunca_activable (empresa, slug, motivo) values
  ('sandal_woods', 'cc00014_timon',      'Documento de un solo ejemplar firmado por otra sociedad: no se emite para esta empresa'),
  ('sandal_woods', 'ppjb_bonian_c2',     'Documento de un solo ejemplar firmado por otra sociedad: no se emite para esta empresa'),
  ('sandal_woods', 'anexo_x_bonian_c2',  'Anexo de un solo ejemplar de otra sociedad: no se emite para esta empresa'),
  ('sandal_woods', 'anexo_y_bonian_c2',  'Anexo de un solo ejemplar de otra sociedad: no se emite para esta empresa');

create table public.plantilla_solo_global (
  slug   text primary key references public.plantillas_contrato (slug),
  motivo text not null check (btrim(motivo) <> '')
);
insert into public.plantilla_solo_global (slug, motivo) values
  ('hak_sewa_notario', 'Documento notarial: solo lo cambia el administrador global con su abogado'),
  ('poa_notario',      'Documento notarial: solo lo cambia el administrador global con su abogado'),
  ('estatutos_sw',     'Estatutos de la comunidad del complejo: solo lo cambia el administrador global con su abogado');

create table public.plantilla_ficha (
  empresa text not null references public.empresas (clave),
  clave   text not null check (clave ~ '^[a-z0-9_]+$'),
  valor   text,
  primary key (empresa, clave)
);
comment on table public.plantilla_ficha is 'Datos de ficha que una plantilla exige antes de activarse (hoy: promotora_razon para estatutos_sw, razon social juridica de la promotora fundadora: la da el owner). Solo postgres.';

create table public.plantilla_bloque_regla (
  id      serial primary key,
  slug    text references public.plantillas_contrato (slug),   -- null = todas
  tipo    text not null check (tipo in ('elemento', 'seccion')),
  patron  text not null check (btrim(patron) <> ''),
  motivo  text not null
);
comment on table public.plantilla_bloque_regla is 'Reglas provisionales (hasta que la v2 de Legal ponga <!--bloque-fijo:*-->) que dicen que parrafos/secciones no edita una empresa sola. Regex POSIX (~*) sobre el texto sin etiquetas, en minusculas. Solo postgres.';
insert into public.plantilla_bloque_regla (slug, tipo, patron, motivo) values
  (null, 'elemento', 'siac|\ybani\y|arbitra|singapur|singapore|denpasar|ley aplicable|governing law|hukum yang berlaku|jurisdicci|yurisdiksi|jurisdiction|rige por|governed by|diatur (oleh )?hukum|tribunal|pengadilan', 'foro, ley aplicable y arbitraje'),
  (null, 'elemento', '\yhgb\y|hak guna bangunan|hak sewa|hak milik|nominee|pt pma|freehold|leasehold', 'tenencia y estructura de la propiedad'),
  (null, 'elemento', 'escrow|bphtb|\ypph\y|tipo de cambio|exchange rate|nilai tukar', 'escrow, moneda e impuestos'),
  (null, 'elemento', 'pr[oó]rroga|term extension|perpanjangan', 'prorroga'),
  (null, 'elemento', 'defecto|defect|cacat', 'defectos y garantia'),
  (null, 'elemento', 'protecci[oó]n de datos|data protection|perlindungan data|uu pdp', 'proteccion de datos'),
  (null, 'elemento', 'clausulas_negociadas|rev03_', 'clausulas negociadas (las estampa la base)'),
  (null, 'elemento', '\{\{prom_(razon|rep|rep_npwp|npwp|domicilio|ktp|nib|cred_)', 'identidad y firmantes de la sociedad'),
  (null, 'seccion',  '^\W*(\d+\.\s*)?(las partes|parties|reunidos|entre|partes|firmas|signatures|suscrito como acuerdo|anexos?)\y', 'partes, firmas y anexos'),
  (null, 'seccion',  'ley aplicable|governing law|hukum yang berlaku|arbitra|jurisdic|yurisdik|\yforo\y|\yforum\y', 'foro, ley aplicable y arbitraje'),
  (null, 'seccion',  'escrow|dep[oó]sito en garant|impuestos|\ytaxes\y|pajak|desglose y moneda', 'escrow, moneda e impuestos'),
  (null, 'seccion',  'pr[oó]rroga|term extension|perpanjangan', 'prorroga'),
  (null, 'seccion',  'defectos|defect|cacat', 'defectos y garantia'),
  (null, 'seccion',  'protecci[oó]n de datos|data protection|r[eé]gimen legal|estado jur[ií]dico|legal status|suspensi[oó]n y resoluci', 'datos, regimen legal y resolucion'),
  ('ppjb_bonian',       'seccion', 'antecedentes|precio, divisa|declaraciones y garant|incumplimiento, resoluci', 'antecedentes, precio y declaraciones (Legal S1b)'),
  ('ppjb_reserva',      'seccion', 'antecedentes|definiciones|zonas comunes', 'antecedentes y definiciones (Legal S1b)'),
  ('ppjb_parcela',      'seccion', 'zonas comunes', 'zonas comunes y gastos (Legal S1b)'),
  ('carta_reserva_hak_sewa', 'seccion', '^\W*(2|3|5|6|7|8)\.', 'paragrafos 2, 3 y 5-8 (Legal S1b)'),
  ('carta_reserva_pma',      'seccion', '^\W*(2|3|5|6|7|8|9)\.', 'paragrafos 2, 3 y 5-9 (Legal S1b)');
alter table public.plantilla_sociedad_cruce  enable row level security;
alter table public.plantilla_nunca_activable enable row level security;
alter table public.plantilla_solo_global     enable row level security;
alter table public.plantilla_ficha           enable row level security;
alter table public.plantilla_bloque_regla    enable row level security;
revoke all on table public.plantilla_sociedad_cruce, public.plantilla_nunca_activable, public.plantilla_solo_global, public.plantilla_ficha, public.plantilla_bloque_regla
  from public, anon, authenticated, service_role;
revoke all on sequence public.plantilla_bloque_regla_id_seq from public, anon, authenticated, service_role;

-- ================================================================= F1: texto de otra sociedad
create or replace function public._plantilla_norm(p text) returns text
language plpgsql immutable security definer set search_path = '' as $f$
declare t text := coalesce(p, ''); m text[]; code int;
begin
  t := regexp_replace(t, '<!--(?:(?!-->).)*-->', ' ', 'g');
  t := regexp_replace(t, '<[^>]*>', ' ', 'g');
  t := regexp_replace(t, '\{\{[^{}]*\}\}', ' ', 'g');
  for m in select regexp_matches(t, '(&#(?:[xX]([0-9a-fA-F]{1,6})|([0-9]{1,7}));)', 'g') loop
    code := case when m[2] is not null then ('x' || lpad(m[2], 8, '0'))::bit(32)::int else m[3]::int end;
    if code between 32 and 1114111 and code not between 55296 and 57343 then t := replace(t, m[1], chr(code)); end if;
  end loop;
  t := regexp_replace(t, '&[A-Za-z][A-Za-z0-9]*;', ' ', 'g');
  t := normalize(t, NFKD);
  t := regexp_replace(t, '[̀-ͯ]', '', 'g');
  return regexp_replace(lower(t), '[^a-z0-9]', '', 'g');
end $f$;

create or replace function public._plantilla_terminos(p_clave text) returns table (tipo text, term text)
language plpgsql stable security definer set search_path = '' as $f$
declare s public.sociedades%rowtype; b1 text; b2 text; d text; x text;
begin
  select * into s from public.sociedades where clave = p_clave;
  if not found then return; end if;
  if nullif(btrim(s.razon), '') is not null then
    b1 := regexp_replace(s.razon, '^\s*(p\.?\s?t\.?)\s+', '', 'i');
    b2 := regexp_replace(b1, '\s+(limited|ltd\.?|pt|inc\.?|co\.?)\s*$', '', 'i');
    foreach x in array array[public._plantilla_norm(b1), public._plantilla_norm(b2)] loop
      if length(x) >= 6 then tipo := 'razon social'; term := x; return next; end if;
    end loop;
  end if;
  if nullif(btrim(s.marca), '') is not null then
    foreach x in array array[public._plantilla_norm(s.marca), public._plantilla_norm(split_part(btrim(s.marca), ' ', 1))] loop
      if length(x) >= 5 then tipo := 'marca'; term := x; return next; end if;
    end loop;
  end if;
  x := regexp_replace(coalesce(s.npwp, ''), '[^0-9]', '', 'g');
  if length(x) >= 10 then tipo := 'NPWP'; term := x; return next; end if;
  x := regexp_replace(coalesce(s.nib, ''), '[^0-9]', '', 'g');
  if length(x) >= 8 then tipo := 'NIB'; term := x; return next; end if;
  for d in select regexp_split_to_table(coalesce(s.domicilio, ''), '[,;\n]+') loop
    x := public._plantilla_norm(d);
    if length(x) >= 12 then tipo := 'domicilio'; term := x; return next; end if;
  end loop;
end $f$;

create or replace function public._plantilla_otra_sociedad(p_cuerpo text, p_empresa text) returns text[]
language plpgsql stable security definer set search_path = '' as $f$
declare
  n text := public._plantilla_norm(p_cuerpo); own text[]; own_terms text[]; r record; o record; hit text[] := '{}'; esc boolean;
begin
  own := array(select e.sociedad_clave from public.empresas e where e.clave = p_empresa and e.sociedad_clave is not null
               union select c.sociedad_clave from public.plantilla_sociedad_cruce c where c.empresa = p_empresa and c.propia);
  select coalesce(array_agg(t.term), '{}') into own_terms from unnest(own) k cross join lateral public._plantilla_terminos(k) t;
  for r in select s.clave from public.sociedades s where s.clave <> all (own) loop
    for o in select * from public._plantilla_terminos(r.clave) loop
      -- se resta lo que la sociedad propia ya contiene (p. ej. un tramo de domicilio compartido)
      esc := exists (select 1 from unnest(own_terms) ot where position(o.term in ot) > 0);
      if not esc and position(o.term in n) > 0 then hit := hit || (o.tipo || ' de ' || r.clave); end if;
    end loop;
  end loop;
  return coalesce((select array_agg(distinct h order by h) from unnest(hit) h), '{}');
end $f$;

create or replace function public._plantilla_motivo_bloqueo(p_cuerpo text, p_empresa text, p_slug text) returns text
language plpgsql stable security definer set search_path = '' as $f$
declare m text[] := '{}'; x text; h text[];
begin
  select n.motivo into x from public.plantilla_nunca_activable n where n.empresa = p_empresa and n.slug = p_slug;
  if x is not null then m := m || x; end if;
  if p_slug = 'estatutos_sw' and not exists (select 1 from public.plantilla_ficha f where f.empresa = p_empresa and f.clave = 'promotora_razon' and nullif(btrim(f.valor), '') is not null) then
    m := m || 'Falta la razon social juridica de la promotora fundadora (promotora_razon): la da el owner, no se rellena con algo plausible'::text;
  end if;
  h := public._plantilla_otra_sociedad(p_cuerpo, p_empresa);
  if cardinality(h) > 0 then m := m || ('El texto nombra a otra sociedad (' || array_to_string(h, ', ') || '): usa los marcadores de la sociedad de la empresa'); end if;
  return nullif(array_to_string(m, ' | '), '');
end $f$;

-- ================================================================= F2: bloques que una empresa sola no edita
create or replace function public._plantilla_ws(p text) returns text
language sql immutable parallel safe set search_path = '' as $$ select btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g')) $$;

create or replace function public._plantilla_bloques_fijos(p_cuerpo text, p_slug text) returns text[]
language plpgsql stable security definer set search_path = '' as $f$
declare
  res text[] := '{}'; m text[]; tg text; pat_el text; pat_sec text; pieces text[]; i int; piece text; titulo text;
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
        if lower(regexp_replace(m[1], '<[^>]*>', ' ', 'g')) ~* pat_el then res := res || ('E|' || public._plantilla_ws(m[1])); end if;
      end loop;
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

create or replace function public._plantilla_exige_bloques(p_cuerpo text, p_esqueleto text, p_empresa text, p_slug text) returns void
language plpgsql stable security definer set search_path = '' as $f$
declare a text[]; b text[]; sg text;
begin
  if public.es_super_admin() then return; end if;               -- el super GLOBAL (con su abogado) si puede
  if p_esqueleto is null then return; end if;                    -- sin esqueleto el validador de S3 ya rechaza
  select s.motivo into sg from public.plantilla_solo_global s where s.slug = p_slug;
  if sg is not null then
    if public._plantilla_ws(p_cuerpo) is distinct from public._plantilla_ws(p_esqueleto) then
      raise exception '%', 'Este texto no lo cambia una empresa sola. ' || sg using errcode = '42501';
    end if;
    return;
  end if;
  a := public._plantilla_bloques_fijos(p_cuerpo, p_slug);
  b := public._plantilla_bloques_fijos(p_esqueleto, p_slug);
  if a is distinct from b then
    raise exception 'Tu texto cambia un bloque que una empresa no edita sola (foro y ley aplicable, tenencia, escrow e impuestos, prorroga, defectos, datos, partes y firmas, clausulas negociadas) o anade en un parrafo libre palabras de esos temas. Esos bloques los cambia el administrador global con su abogado: bloques fijos %, recibidos %', cardinality(b), cardinality(a) using errcode = '42501';
  end if;
end $f$;

revoke all on function public._plantilla_norm(text), public._plantilla_terminos(text), public._plantilla_otra_sociedad(text, text), public._plantilla_motivo_bloqueo(text, text, text),
  public._plantilla_ws(text), public._plantilla_bloques_fijos(text, text), public._plantilla_exige_bloques(text, text, text, text) from public, anon, authenticated, service_role;

-- ================================================================= las dos RPC de S2 que ahora aplican los bloqueos
create or replace function public.plantilla_contrato_guarda_borrador(p_empresa text, p_slug text, p_cuerpo text, p_motivo text)
 returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := (select auth.uid());
  v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
  v_hash  text; v_bytes int; v_idiomas text[]; v_id uuid; v_n int; v_base uuid; v_esq text; v_bloq text;
begin
  if v_uid is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El texto de los contratos de una empresa lo escribe su administracion' using errcode = '42501';
  end if;
  if not exists (select 1 from public.empresas e where e.clave = p_empresa and e.activa) then raise exception 'Empresa no valida' using errcode = '22023'; end if;
  if not exists (select 1 from public.plantillas_contrato t where t.slug = p_slug) then raise exception 'Plantilla no valida' using errcode = '22023'; end if;
  if p_cuerpo is null or btrim(p_cuerpo) = '' then raise exception 'Falta el texto' using errcode = '22023'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'Falta el motivo del cambio' using errcode = '22023'; end if;
  v_bytes := pg_catalog.octet_length(p_cuerpo);
  if v_bytes > 1000000 then raise exception 'El texto supera el tope de 1 MB' using errcode = '22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('plantilla/' || p_empresa || '/' || p_slug, 0));
  perform public._plantilla_exige_valido(p_cuerpo, p_empresa, p_slug);
  v_esq := public._plantilla_esqueleto(p_empresa, p_slug);
  perform public._plantilla_exige_bloques(p_cuerpo, v_esq, p_empresa, p_slug);                 -- F2
  v_bloq := public._plantilla_motivo_bloqueo(p_cuerpo, p_empresa, p_slug);                      -- F1 (se guarda, pero no sera activable)
  v_hash := public._plantilla_hash(p_cuerpo);
  v_idiomas := array_remove(array[
    case when p_cuerpo like '%data-lang="es"%' then 'es' end,
    case when p_cuerpo like '%data-lang="en"%' then 'en' end,
    case when p_cuerpo like '%data-lang="id"%' then 'id' end], null);
  select v.id into v_id from public.plantilla_contrato_versiones v
   where v.empresa = p_empresa and v.slug = p_slug and v.estado = 'borrador' and v.origen = 'empresa' for update;
  if found then
    update public.plantilla_contrato_versiones
       set hash = v_hash, bytes = v_bytes, idioma_set = v_idiomas, autor = v_autor, fecha = now(), motivo = btrim(p_motivo),
           activable = (v_bloq is null), bloqueo_motivo = v_bloq
     where id = v_id;
    update public.plantilla_contrato_cuerpos set cuerpo_html = p_cuerpo where version_id = v_id;
  else
    select coalesce(max(v.version), 0) + 1 into v_n from public.plantilla_contrato_versiones v where v.empresa = p_empresa and v.slug = p_slug;
    select v.id into v_base from public.plantilla_contrato_versiones v
     where v.empresa = p_empresa and v.slug = p_slug and (v.estado <> 'borrador' or v.origen = 'semilla')
     order by (v.estado = 'activa') desc, v.version desc limit 1;
    insert into public.plantilla_contrato_versiones (empresa, slug, version, estado, origen, idioma_set, hash, bytes, activable, bloqueo_motivo, hereda_de, autor, motivo)
    values (p_empresa, p_slug, v_n, 'borrador', 'empresa', v_idiomas, v_hash, v_bytes, v_bloq is null, v_bloq, v_base, v_autor, btrim(p_motivo))
    returning id into v_id;
    insert into public.plantilla_contrato_cuerpos (version_id, cuerpo_html) values (v_id, p_cuerpo);
  end if;
  return v_id;
end $$;

create or replace function public.plantilla_contrato_activa(p_version uuid, p_nombre text, p_confirma boolean)
 returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v       public.plantilla_contrato_versiones%rowtype;
  v_email text := coalesce((select auth.email()), (select auth.uid())::text);
  v_body  text; v_bloq text;
  v_texto constant text := 'Responde esta empresa. El estudio no ha revisado este texto. Consulte a un abogado o notario antes de usarlo: este aviso no sustituye a un abogado indonesio colegiado.';
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  select * into v from public.plantilla_contrato_versiones x where x.id = p_version for update;
  if not found or not (public.es_super_admin_de(v.empresa) and public.empresa_en_alcance(v.empresa)) then
    raise exception 'Activar un texto de contrato lo hace el super administrador de esa empresa' using errcode = '42501';
  end if;
  if p_confirma is not true or length(btrim(coalesce(p_nombre, ''))) < 3 then
    raise exception 'Falta la confirmacion explicita (tu nombre y aceptar el aviso)' using errcode = '22023';
  end if;
  if v.estado <> 'borrador' then raise exception 'Solo se activa un borrador' using errcode = '55000'; end if;
  if not v.activable then raise exception 'Version no activable: %', coalesce(v.bloqueo_motivo, 'sin motivo') using errcode = '55000'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('plantilla/' || v.empresa || '/' || v.slug, 0));
  select c.cuerpo_html into v_body from public.plantilla_contrato_cuerpos c where c.version_id = v.id;
  if v_body is null then raise exception 'La version no tiene cuerpo' using errcode = '55000'; end if;
  perform public._plantilla_exige_valido(v_body, v.empresa, v.slug);
  v_bloq := public._plantilla_motivo_bloqueo(v_body, v.empresa, v.slug);                       -- F1 otra vez, en servidor, sobre el cuerpo guardado
  if v_bloq is not null then raise exception 'Version no activable: %', v_bloq using errcode = '55000'; end if;
  update public.plantilla_contrato_versiones set estado = 'retirada', retirada_por = v_email, retirada_en = now()
   where empresa = v.empresa and slug = v.slug and estado = 'activa';
  update public.plantilla_contrato_versiones
     set estado = 'activa', activado_por = v_email, activado_en = now(), confirmacion_nombre = btrim(p_nombre), confirmacion_texto = v_texto
   where id = v.id;
  return jsonb_build_object('version_id', v.id, 'version', v.version, 'empresa', v.empresa, 'slug', v.slug, 'activado_por', v_email);
end $$;

-- ================================================================= S3: listas cerradas ampliadas (prom_cargo, promotora_razon, bloque-fijo:*) con asercion de que el parche entra una sola vez
do $p$
declare d text; d2 text;
begin
  d := pg_get_functiondef('public._plantilla_marcadores()'::regprocedure);
  if d not like '%''prom_cargo''%' then
    d2 := replace(d, '''unidad_construccion_codigo''', '''unidad_construccion_codigo'', ''prom_cargo'', ''promotora_razon''');
    if d2 = d then raise exception 'parche S3: no encuentro el final de la lista de marcadores'; end if;
    execute d2;
  end if;
  d := pg_get_functiondef('public._plantilla_analiza(text,boolean)'::regprocedure);
  if d not like '%bloque-fijo%' then
    d2 := replace(d, E'        elsif cm = any (c_simple) or cm ~ ''^cuenta:[a-z0-9_]+$'' then',
$r$        elsif cm ~ '^bloque-fijo:(foro_ley|tenencia|escrow|impuestos|prorroga|defectos|notarial|partes|firmas|datos|negociadas)$' then
          if cm = any (cstack) then errs := errs || ('<!--' || cm || '--> anidado dentro de otro bloque fijo igual'); end if;
          cstack := cstack || cm; coms := coms || cm;
        elsif cm ~ '^/bloque-fijo:(foro_ley|tenencia|escrow|impuestos|prorroga|defectos|notarial|partes|firmas|datos|negociadas)$' then
          if cardinality(cstack) = 0 or cstack[cardinality(cstack)] <> substr(cm, 2) then
            errs := errs || ('cierre <!--' || cm || '--> sin su apertura (o cruzado con otro bloque)');
          else cstack := cstack[1:cardinality(cstack) - 1]; end if;
          coms := coms || cm;
        elsif cm = any (c_simple) or cm ~ '^cuenta:[a-z0-9_]+$' then$r$);
    if d2 = d then raise exception 'parche S3: no encuentro el punto de los comentarios del motor'; end if;
    execute d2;
  end if;
end $p$;

-- ================================================================= permisos
revoke all on function public._plantilla_marcadores(), public._plantilla_campos_if(), public._plantilla_clases(), public._plantilla_texto(text, boolean), public._plantilla_style_valido(text),
  public._plantilla_analiza(text, boolean), public._plantilla_valida(text, text, boolean), public.plantilla_cuerpo_valida(text, text), public.plantilla_cuerpo_valida_semilla(text, text)
  from public, anon, authenticated, service_role;
-- sin llamador no hay EXECUTE: S5 (generador) y S7 (pantalla) haran el GRANT con su llamador
revoke all on function public.plantilla_contrato_guarda_borrador(text, text, text, text), public.plantilla_contrato_activa(uuid, text, boolean),
  public.plantilla_contrato_descarta_borrador(uuid), public.plantilla_contrato_cuerpo(text, uuid, text), public.plantilla_contrato_cuerpo_version(uuid, text),
  public.plantilla_contrato_version_de_contrato(uuid), public.plantilla_contrato_versiones_lista(text, text), public.plantilla_contrato_fija(uuid, uuid)
  from public, anon, authenticated, service_role;
