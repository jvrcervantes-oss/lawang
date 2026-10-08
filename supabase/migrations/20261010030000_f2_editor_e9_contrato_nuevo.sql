-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «editor de textos de contrato» (encargos/20261008_lawang_editor_textos_contrato.md) · E9 · CONTRATO NUEVO CREADO POR EL CLIENTE (8-oct-2026).
-- DECISION DEL OWNER (8-oct): el cliente no debe depender del estudio para un contrato nuevo (nombre, punto de partida, campos). Revision previa #225 (Datos, Seguridad, Bots).
-- HALLAZGO DE MODELO (medido hoy en la base): `plantillas_contrato` era GLOBAL (PK slug, sin empresa, politica «solo con sesion» = USING true): una plantilla propia de una empresa se la
--   habrian visto todas. Por eso se anade la columna minima `empresa` (null = del estudio, como las 20 de hoy) y la politica de lectura pasa a «del estudio o de mi empresa»; la vista de
--   compatibilidad `plantillas_pago` es security_invoker y hereda el filtro. El resto de consumidores leen versiones/cuerpos (ya por empresa) o consultan por slug.
-- QUE HACE:
--   1. `plantillas_contrato` + empresa / campos / creada_por (+ checks, indice de nombre unico por empresa) y la politica de lectura filtrada por empresa_en_alcance.
--   2. `plantilla_contrato_nuevo_crea(empresa, nombre, 'copia'|'blanco', slug_origen, version_origen, campos)`: crea la plantilla (slug unico con prefijo de empresa, nace ARCHIVADA = oculta de los
--      selectores de emision hasta que el contrato pueda usarse), su ESQUELETO (v1, origen semilla, no activable: es lo que protege la estructura, como en las 20 de hoy) y su primer
--      BORRADOR editable (v2) con el mismo texto. Copia = el texto de una plantilla DE LA MISMA EMPRESA (nunca solo-global ni nunca-activable); blanco = esqueleto minimo valido con los campos elegidos.
--      Tope de 30 contratos propios por empresa. Pasa por el MISMO validador que cualquier borrador. La activacion sigue siendo del super administrador de la empresa.
--   3. Un contrato en blanco NO se puede activar sin escribirlo: los textos de ejemplo «[Escribe aqui ...]» son motivo de bloqueo (`_plantilla_motivo_bloqueo`), y la activacion lo vuelve a comprobar.
-- NO HACE (queda fuera, avisado en el informe): que un contrato real use el tipo nuevo. `contratos.tipo` tiene un CHECK con 17 tipos y `_plantilla_slug_de_tipo` un mapa fijo; abrirlos toca el
--   generador (contracts/app.html) y la tabla de contratos. Hasta entonces el contrato nuevo se redacta, se valida y se activa, pero no se ofrece en los selectores (nace archivada).
-- RPC nueva: nace cerrada y se abre solo a `authenticated` (empresa_en_alcance + administrador dentro). Llamador con nombre: el configurador de contrato nuevo de la pantalla `intranet/v4/textos-contrato/`.
-- destructivo-ok: solo ANADE columnas nulas, dos constraints sobre ellas, un indice parcial, una funcion y reemplaza la politica de lectura y un validador; no toca ninguna fila
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_editor_e9_contrato_nuevo.sql

-- ------------------------------------------------------------------------------------------------------------------ modelo
alter table public.plantillas_contrato
  add column empresa    text references public.empresas (clave),
  add column campos     jsonb,
  add column creada_por text;
alter table public.plantillas_contrato
  add constraint plantillas_contrato_propia_slug  check (empresa is null or slug ~ '^[a-z][a-z0-9_]{2,59}$'),
  add constraint plantillas_contrato_propia_campos check (empresa is null or (campos is not null and jsonb_typeof(campos) = 'array' and jsonb_array_length(campos) <= 40)),
  add constraint plantillas_contrato_propia_nombre check (empresa is null or length(btrim(nombre)) between 3 and 80);
create unique index plantillas_contrato_nombre_empresa on public.plantillas_contrato (empresa, lower(nombre)) where empresa is not null;
comment on column public.plantillas_contrato.empresa is 'null = contrato del estudio (visible a todas las empresas); clave de empresa = contrato propio de esa empresa, solo visible para ella (E9, 8-oct-2026).';

drop policy "plantillas de pago: solo con sesion" on public.plantillas_contrato;
create policy "plantillas de contrato: del estudio o de mi empresa" on public.plantillas_contrato for select to authenticated, lw_lector
  using (empresa is null or public.empresa_en_alcance(empresa));

-- defensa en profundidad: una version de un contrato PROPIO de una empresa solo puede ser de esa empresa (cubre guarda_borrador, revision_crea y cualquier camino futuro)
create function public._trg_plantilla_version_empresa_propia() returns trigger language plpgsql security definer set search_path = '' as $$
declare e text;
begin
  select t.empresa into e from public.plantillas_contrato t where t.slug = new.slug;
  if e is not null and e <> new.empresa then
    raise exception 'Ese contrato es propio de otra empresa' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger plantilla_version_empresa_propia before insert on public.plantilla_contrato_versiones
  for each row execute function public._trg_plantilla_version_empresa_propia();
revoke all on function public._trg_plantilla_version_empresa_propia() from public, anon, authenticated, service_role;

-- ------------------------------------------------------------------------------------------------------------------ un contrato en blanco no se activa sin escribirlo
create or replace function public._plantilla_motivo_bloqueo(p_cuerpo text, p_empresa text, p_slug text) returns text
 language plpgsql stable security definer set search_path = '' as $$
declare m text[] := '{}'; x text; h text[];
begin
  select n.motivo into x from public.plantilla_nunca_activable n where n.empresa = p_empresa and n.slug = p_slug;
  if x is not null then m := m || x; end if;
  if p_slug = 'estatutos_sw' and not exists (select 1 from public.plantilla_ficha f where f.empresa = p_empresa and f.clave = 'promotora_razon' and nullif(btrim(f.valor), '') is not null) then
    m := m || 'Falta la razon social juridica de la promotora fundadora (promotora_razon): la da el owner, no se rellena con algo plausible'::text;
  end if;
  h := public._plantilla_otra_sociedad(p_cuerpo, p_empresa);
  if cardinality(h) > 0 then m := m || ('El texto nombra a otra sociedad (' || array_to_string(h, ', ') || '): usa los marcadores de la sociedad de la empresa'); end if;
  if p_cuerpo ~ '\[(Escribe|Write|Tulis)[^\]]{0,80}\]' then
    m := m || 'Quedan textos de ejemplo por escribir (los que van entre corchetes, «[Escribe aqui ...]»): escribe el contrato antes de activarlo'::text;
  end if;
  return nullif(array_to_string(m, ' | '), '');
end $$;

-- ------------------------------------------------------------------------------------------------------------------ esqueleto minimo en blanco (trilingue, con los campos elegidos)
create function public._plantilla_esqueleto_en_blanco(p_nombre text, p_campos text[], p_empresa text) returns text language plpgsql stable security definer set search_path = '' as $$
declare v text; c text; f record; sec text; tit text[]; i int;
  nom text := replace(btrim(p_nombre), '&', '&amp;');
begin
  v := E'<!DOCTYPE html>\n<html lang="es">\n<head>\n<meta charset="UTF-8">\n<title>' || nom || E'</title>\n</head>\n<body>\n  <div class="doc">\n'
    || '    <div class="doc-title"><span class="bold"><span data-lang="es">' || nom || '</span><span data-lang="en">' || nom || '</span><span data-lang="id">' || nom || E'</span></span></div>\n'
    || '    <div class="doc-date"><span data-lang="es">En Indonesia, a fecha <span class="f f-sm">{{fecha_firma}}</span></span><span data-lang="en">In Indonesia, dated <span class="f f-sm">{{fecha_firma}}</span></span><span data-lang="id">Di Indonesia, tertanggal <span class="f f-sm">{{fecha_firma}}</span></span></div>' || E'\n';
  for i in 1 .. 3 loop
    tit := case i
      when 1 then array['Objeto del contrato', 'Purpose of the agreement', 'Objek perjanjian']
      when 2 then array['Condiciones', 'Terms', 'Ketentuan']
      else array['Disposiciones finales', 'Final provisions', 'Ketentuan penutup'] end;
    v := v || '    <h2><span data-lang="es">' || tit[1] || '</span><span data-lang="en">' || tit[2] || '</span><span data-lang="id">' || tit[3] || E'</span></h2>\n'
           || E'    <p data-lang="es">[Escribe aquí el texto de esta cláusula]</p>\n'
           || E'    <p data-lang="en">[Write here the text of this clause]</p>\n'
           || E'    <p data-lang="id">[Tulis di sini isi klausul ini]</p>\n';
  end loop;
  if coalesce(cardinality(p_campos), 0) > 0 then
    v := v || '    <h2><span data-lang="es">Datos del contrato</span><span data-lang="en">Contract details</span><span data-lang="id">Data perjanjian</span></h2>' || E'\n';
    foreach c in array p_campos loop
      select replace(pf.etiqueta_es, '&', '&amp;') as es, replace(coalesce(pf.etiqueta_en, pf.etiqueta_es), '&', '&amp;') as en, replace(coalesce(pf.etiqueta_id, pf.etiqueta_es), '&', '&amp;') as id
        into f from public.plantilla_campos_propios pf where pf.empresa = p_empresa and pf.clave = c and not pf.archivado;
      v := v || '    <p data-lang="es">' || f.es || ': <span class="f f-md">{{' || c || E'}}</span></p>\n'
             || '    <p data-lang="en">' || f.en || ': <span class="f f-md">{{' || c || E'}}</span></p>\n'
             || '    <p data-lang="id">' || f.id || ': <span class="f f-md">{{' || c || E'}}</span></p>\n';
    end loop;
  end if;
  return v || E'  </div>\n</body>\n</html>';
end $$;
revoke all on function public._plantilla_esqueleto_en_blanco(text, text[], text) from public, anon, authenticated, service_role;

-- ------------------------------------------------------------------------------------------------------------------ la RPC
create function public.plantilla_contrato_nuevo_crea(p_empresa text, p_nombre text, p_punto_partida text, p_slug_origen text default null, p_version_origen uuid default null, p_campos jsonb default '[]'::jsonb)
 returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := (select auth.uid());
  v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
  v_nom   text := btrim(coalesce(p_nombre, ''));
  v_campos text[]; v_base text; v_slug text; v_i int := 1; v_body text; v_src uuid; v_r jsonb; v_bloq text; v_idiomas text[]; v_hash text; v_bytes int; v_v1 uuid; v_v2 uuid; v_n int;
begin
  if v_uid is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El texto de los contratos de una empresa lo escribe su administracion' using errcode = '42501';
  end if;
  if not exists (select 1 from public.empresas e where e.clave = p_empresa and e.activa) then raise exception 'Empresa no valida' using errcode = '22023'; end if;
  if length(v_nom) not between 3 and 80 or v_nom ~ '[<>{}&"\x01-\x1f\x7f]' then
    raise exception 'Pon un nombre de 3 a 80 letras, sin los signos < > { } & ni comillas dobles' using errcode = '22023';
  end if;
  if p_punto_partida is null or p_punto_partida not in ('copia', 'blanco') then raise exception 'Elige si partes de una copia o de un contrato en blanco' using errcode = '22023'; end if;
  p_campos := coalesce(p_campos, '[]'::jsonb);
  if jsonb_typeof(p_campos) <> 'array' or jsonb_array_length(p_campos) > 40 then raise exception 'La lista de campos no es valida (como mucho 40)' using errcode = '22023'; end if;
  if exists (select 1 from jsonb_array_elements(p_campos) e where jsonb_typeof(e) <> 'string') then raise exception 'La lista de campos no es valida' using errcode = '22023'; end if;
  v_campos := array(select q.c from (select e #>> '{}' as c, min(o) as o from jsonb_array_elements(p_campos) with ordinality t(e, o) group by 1) q order by q.o);
  if exists (select 1 from unnest(v_campos) c where not exists (select 1 from public.plantilla_campos_propios f where f.empresa = p_empresa and f.clave = c and not f.archivado)) then
    raise exception 'Alguno de los campos no esta en el catalogo de tu empresa (o esta archivado)' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('plantilla-nueva/' || p_empresa, 0));
  select count(*) into v_n from public.plantillas_contrato t where t.empresa = p_empresa;
  if v_n >= 30 then raise exception 'Una empresa puede tener como mucho 30 contratos propios' using errcode = '54000'; end if;
  if exists (select 1 from public.plantillas_contrato t where lower(t.nombre) = lower(v_nom) and (t.empresa is null or t.empresa = p_empresa)) then
    raise exception 'Ya hay un contrato con ese nombre: elige otro' using errcode = '22023';
  end if;

  if p_punto_partida = 'copia' then
    if p_slug_origen is null then raise exception 'Falta el contrato del que partir' using errcode = '22023'; end if;
    if not exists (select 1 from public.plantillas_contrato t where t.slug = p_slug_origen and (t.empresa is null or t.empresa = p_empresa)) then
      raise exception 'Ese contrato de origen no existe' using errcode = '22023';
    end if;
    if exists (select 1 from public.plantilla_solo_global s where s.slug = p_slug_origen)
       or exists (select 1 from public.plantilla_nunca_activable n where n.empresa = p_empresa and n.slug = p_slug_origen) then
      raise exception 'Ese contrato no se copia: solo lo cambia el administrador global' using errcode = '42501';
    end if;
    if p_version_origen is not null then
      select x.id into v_src from public.plantilla_contrato_versiones x
       where x.id = p_version_origen and x.empresa = p_empresa and x.slug = p_slug_origen and x.borrada_en is null and x.estado <> 'retirada';
      if v_src is null then raise exception 'Ese texto de origen no es de esta empresa y contrato' using errcode = '22023'; end if;
    else
      select x.id into v_src from public.plantilla_contrato_versiones x
       where x.empresa = p_empresa and x.slug = p_slug_origen and x.borrada_en is null and ((x.estado = 'activa' and x.variante = 'estandar') or x.origen = 'semilla')
       order by (x.estado = 'activa') desc, x.version asc limit 1;
      if v_src is null then raise exception 'Ese contrato no tiene texto para tu empresa' using errcode = '22023'; end if;
    end if;
    select public._plantilla_sin_notas(c.cuerpo_html) into v_body from public.plantilla_contrato_cuerpos c where c.version_id = v_src;
  else
    v_body := public._plantilla_esqueleto_en_blanco(v_nom, v_campos, p_empresa);
  end if;

  -- slug unico (prefijo de empresa + nombre normalizado + sufijo si choca con cualquier slug existente)
  v_base := regexp_replace(regexp_replace(translate(lower(v_nom),
              U&'\00E1\00E0\00E4\00E2\00E3\00E9\00E8\00EB\00EA\00ED\00EC\00EF\00EE\00F3\00F2\00F6\00F4\00F5\00FA\00F9\00FC\00FB\00F1\00E7', 'aaaaaeeeeiiiiooooouuuunc'),
              '[^a-z0-9]+', '_', 'g'), '^_+|_+$', '', 'g');
  v_base := left(p_empresa, 15) || '_' || coalesce(nullif(left(v_base, 35), ''), 'contrato');      -- como mucho 51 + sufijo: cabe en los 60 del CHECK
  v_slug := v_base;
  while exists (select 1 from public.plantillas_contrato t where t.slug = v_slug) loop
    v_i := v_i + 1; v_slug := v_base || '_' || v_i;
  end loop;

  insert into public.plantillas_contrato (slug, nombre, orden, cobra, archivada, empresa, campos, creada_por)
  values (v_slug, v_nom, 500, false, true, p_empresa, to_jsonb(v_campos), v_autor);

  -- 1.o el ESQUELETO (origen semilla, no activable): lo que fija la estructura, igual que en las plantillas del estudio
  perform public._plantilla_cx_contexto(p_empresa, true);
  v_r := public._plantilla_valida(v_body, null, true);
  perform pg_catalog.set_config('lw.cx_catalogo', '', true);
  if coalesce((v_r ->> 'ok')::boolean, false) is not true then
    raise exception 'El texto de partida no pasa la validacion: %', coalesce(left((select string_agg(e, ' | ') from (select jsonb_array_elements_text(v_r -> 'errores') e limit 5) q), 600), 'sin detalle') using errcode = '22023';
  end if;
  v_idiomas := array_remove(array[
    case when v_body like '%data-lang="es"%' then 'es' end,
    case when v_body like '%data-lang="en"%' then 'en' end,
    case when v_body like '%data-lang="id"%' then 'id' end], null);
  v_hash := public._plantilla_hash(v_body);
  v_bytes := pg_catalog.octet_length(v_body);
  insert into public.plantilla_contrato_versiones (empresa, slug, version, estado, origen, idioma_set, hash, bytes, activable, bloqueo_motivo, hereda_de, autor, motivo, variante)
  values (p_empresa, v_slug, 1, 'borrador', 'semilla', v_idiomas, v_hash, v_bytes, false, 'Esqueleto de partida del contrato: no se activa, se edita su copia', v_src, v_autor, 'Esqueleto de partida (contrato nuevo)', 'estandar')
  returning id into v_v1;
  insert into public.plantilla_contrato_cuerpos (version_id, cuerpo_html) values (v_v1, v_body);

  -- 2.o el BORRADOR editable, por EXACTAMENTE el mismo validador que cualquier borrador
  perform public._plantilla_exige_valido(v_body, p_empresa, v_slug);
  v_bloq := public._plantilla_motivo_bloqueo(v_body, p_empresa, v_slug);
  insert into public.plantilla_contrato_versiones (empresa, slug, version, estado, origen, idioma_set, hash, bytes, activable, bloqueo_motivo, hereda_de, autor, motivo, variante)
  values (p_empresa, v_slug, 2, 'borrador', 'empresa', v_idiomas, v_hash, v_bytes, v_bloq is null, v_bloq, v_v1, v_autor,
          case p_punto_partida when 'copia' then 'Contrato nuevo (copia de ' || p_slug_origen || ')' else 'Contrato nuevo en blanco' end, 'estandar')
  returning id into v_v2;
  insert into public.plantilla_contrato_cuerpos (version_id, cuerpo_html) values (v_v2, v_body);

  return jsonb_build_object('slug', v_slug, 'nombre', v_nom, 'version_id', v_v2, 'esqueleto_id', v_v1, 'punto_partida', p_punto_partida,
                            'campos', to_jsonb(v_campos), 'activable', v_bloq is null, 'bloqueo', v_bloq);
end $$;
revoke all on function public.plantilla_contrato_nuevo_crea(text, text, text, text, uuid, jsonb) from public, anon, service_role;
grant execute on function public.plantilla_contrato_nuevo_crea(text, text, text, text, uuid, jsonb) to authenticated;
