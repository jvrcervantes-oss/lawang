-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «editor de textos de contrato» (encargos/20261008_lawang_editor_textos_contrato.md) · PARTES SENSIBLES EDITABLES (8-oct-2026).
-- DECISION EXPLICITA DEL OWNER (8-oct): foro, ley aplicable, tenencia, plazo de reserva y los demas bloques fijos pasan a ser EDITABLES por el administrador de la empresa,
--   con AVISO y REGISTRO de quien los cambia. NO hay segunda firma (Seguridad la propuso en la revision previa #225 y el owner la descarto: riesgo aceptado; compensacion = el
--   registro con el texto literal antes/despues, quien y cuando). La activacion sigue siendo del super administrador de la empresa, con su confirmacion.
-- QUE HACE:
--   1. `_plantilla_exige_bloques` deja de rechazar el cambio de un bloque fijo. SIGUE rechazando lo que es SOLO GLOBAL (plantilla_solo_global: estatutos, etc.). El esqueleto,
--      los marcadores, los scripts/enlaces/on*, el aislamiento entre empresas, el texto de otra sociedad y los nunca-activables (REV04) NO se tocan: son otras funciones.
--   2. `_plantilla_bloques_tocados(cuerpo, esqueleto, slug)`: que bloques fijos cambian respecto al esqueleto, con clase, MOTIVO (el de plantilla_bloque_regla), texto antes y despues.
--   3. Tabla `plantilla_bloque_cambios` (registro de quien cambio que): SIN GRANT, solo de ANADIR (trigger impide update/delete). La escribe la RPC al guardar.
--   4. `plantilla_contrato_guarda_borrador` gana `p_confirma_sensibles` (6.o parametro, por defecto false): si el texto toca un bloque fijo y no se confirma, error en llano
--      «confirma que has leido el aviso». El super administrador GLOBAL (el estudio con su abogado) no necesita confirmar, pero queda registrado igual.
--   5. `plantilla_contrato_revisa` (el ensayo) gana `p_variante` (por defecto 'estandar') y devuelve `bloques_tocados` y `sensibles`: la pantalla avisa ANTES de guardar.
--      Guardado y ensayo comparan con lo YA GUARDADO de esa revision (`_plantilla_base_edicion`: su borrador, o su version vigente), no con el esqueleto: no se pide el aviso dos veces por el mismo cambio.
--   6. `plantilla_contrato_edicion` devuelve `bloques_fijos_motivos` (mismo orden que `bloques_fijos`): el motivo de cada bloque fijo.
--   7. `plantilla_contrato_cambios_sensibles(empresa, slug, limite)`: lectura del registro, solo administrador de la empresa.
-- Llamadores con nombre: la pantalla `intranet/v4/textos-contrato/` (guardar con confirmacion, ensayo, motivos, registro). Nada mas.
-- destructivo-ok: solo CREA una tabla y reemplaza funciones del validador (una rama se relaja a proposito); la firma de guarda_borrador y de revisa cambia (drop + create en la misma transaccion, mismo grant); no toca ninguna fila
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_editor_partes_sensibles.sql

-- ------------------------------------------------------------------------------------------------------------------ motivo de un bloque fijo
create function public._plantilla_bloque_motivo(p_entrada text, p_slug text) returns text language plpgsql stable security definer set search_path = '' as $$
declare t text := substr(coalesce(p_entrada, ''), 1, 1); txt text; r record; m text[] := '{}';
begin
  if p_entrada like 'M|%' then
    return 'zona marcada como fija por Legal (' || split_part(p_entrada, '|', 2) || ')';
  end if;
  if t = 'S' then
    txt := lower(public._plantilla_ws(regexp_replace(split_part(substr(p_entrada, 3), '</h2>', 1), '<[^>]*>', ' ', 'g')));
    for r in select patron, motivo from public.plantilla_bloque_regla where tipo = 'seccion' and (slug is null or slug = p_slug) loop
      if txt ~* r.patron then m := m || r.motivo; end if;
    end loop;
  else
    txt := lower(replace(regexp_replace(substr(coalesce(p_entrada, ''), 3), '<[^>]*>', ' ', 'g'), '&nbsp;', ' '));
    for r in select patron, motivo from public.plantilla_bloque_regla where tipo = 'elemento' and (slug is null or slug = p_slug) loop
      if txt ~* r.patron then m := m || r.motivo; end if;
    end loop;
  end if;
  return coalesce(nullif(array_to_string(array(select distinct x from unnest(m) x order by x), ', '), ''), 'parte sensible');
end $$;

-- que bloques fijos cambia un texto respecto a su esqueleto: [{clase, motivo, antes, despues}] (comparacion de multiconjuntos; se empareja por orden de aparicion)
create function public._plantilla_bloques_tocados(p_cuerpo text, p_esqueleto text, p_slug text) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare esq text; a text[]; b text[]; q_antes text[]; q_desp text[]; n int; i int; res jsonb := '[]'::jsonb; x text; y text; clase text; mot text; ax text; ay text;
begin
  if p_cuerpo is null or p_esqueleto is null then return res; end if;
  esq := public._plantilla_sin_notas(p_esqueleto);
  a := public._plantilla_bloques_fijos(p_cuerpo, p_slug);
  b := public._plantilla_bloques_fijos(esq, p_slug);
  if a is not distinct from b then return res; end if;
  q_antes := array(select z.e from (select e, o, row_number() over (partition by e order by o) rn from unnest(b) with ordinality t(e, o)) z
                    where z.rn > (select count(*) from unnest(a) k where k = z.e) order by z.o);
  q_desp  := array(select z.e from (select e, o, row_number() over (partition by e order by o) rn from unnest(a) with ordinality t(e, o)) z
                    where z.rn > (select count(*) from unnest(b) k where k = z.e) order by z.o);
  n := least(greatest(coalesce(cardinality(q_antes), 0), coalesce(cardinality(q_desp), 0)), 100);
  for i in 1 .. n loop
    x := q_antes[i]; y := q_desp[i];
    clase := case substr(coalesce(x, y), 1, 1) when 'M' then 'region' when 'E' then 'elemento' when 'S' then 'seccion' else 'residuo' end;
    mot := coalesce(nullif(case when x is not null then public._plantilla_bloque_motivo(x, p_slug) end, 'parte sensible'),
                    case when y is not null then public._plantilla_bloque_motivo(y, p_slug) end, 'parte sensible');
    ax := case when x is null then null when left(x, 2) = 'M|' then substr(x, length(split_part(x, '|', 2)) + 4) else substr(x, 3) end;
    ay := case when y is null then null when left(y, 2) = 'M|' then substr(y, length(split_part(y, '|', 2)) + 4) else substr(y, 3) end;
    res := res || jsonb_build_array(jsonb_build_object('clase', clase, 'motivo', mot, 'antes', left(ax, 20000), 'despues', left(ay, 20000)));
  end loop;
  return res;
end $$;
revoke all on function public._plantilla_bloque_motivo(text, text), public._plantilla_bloques_tocados(text, text, text) from public, anon, authenticated, service_role;

-- el texto contra el que se compara un guardado: el borrador de la empresa en esa revision si existe; si no, su version vigente (activa, o la ultima, o la semilla).
-- Asi la confirmacion y el registro solo saltan por lo que CAMBIA respecto a lo ya guardado, no por lo que ya difería del esqueleto (que se confirmo al guardarlo).
create function public._plantilla_base_edicion(p_empresa text, p_slug text, p_variante text) returns text language sql stable security definer set search_path = '' as $$
  select c.cuerpo_html
    from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
   where v.empresa = p_empresa and v.slug = p_slug and v.variante = coalesce(p_variante, 'estandar') and v.borrada_en is null
   order by (v.estado = 'borrador' and v.origen = 'empresa') desc, (v.estado = 'activa') desc, v.version desc
   limit 1
$$;
revoke all on function public._plantilla_base_edicion(text, text, text) from public, anon, authenticated, service_role;


-- ------------------------------------------------------------------------------------------------------------------ registro (solo se anade)
create table public.plantilla_bloque_cambios (
  id               uuid        primary key default gen_random_uuid(),
  empresa          text        not null references public.empresas (clave),
  slug             text        not null references public.plantillas_contrato (slug),
  variante         text        not null,
  version_id       uuid        not null references public.plantilla_contrato_versiones (id),
  version          int         not null,
  n                int         not null,
  clase            text        not null check (clase in ('region', 'elemento', 'seccion', 'residuo')),
  motivo           text        not null,
  antes            text,
  despues          text,
  aviso_confirmado boolean     not null,
  motivo_cambio    text        not null,
  autor            text        not null check (btrim(autor) <> ''),
  autor_uid        uuid,
  fecha            timestamptz not null default now()
);
comment on table public.plantilla_bloque_cambios is
  'Registro de quien cambio una parte sensible (bloque fijo) de un texto de contrato, con el texto literal antes y despues (owner 8-oct-2026: editables con aviso y registro, sin segunda firma). Sin GRANT: lo escribe plantilla_contrato_guarda_borrador y se lee por plantilla_contrato_cambios_sensibles. Solo se anade.';
create index plantilla_bloque_cambios_busca on public.plantilla_bloque_cambios (empresa, slug, fecha desc);
alter table public.plantilla_bloque_cambios enable row level security;
revoke all on table public.plantilla_bloque_cambios from public, anon, authenticated, service_role;

create function public._trg_plantilla_bloque_cambios_solo_anade() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'El registro de cambios en partes sensibles solo se anade: no se modifica ni se borra' using errcode = '55000';
end $$;
create trigger plantilla_bloque_cambios_solo_anade before update or delete on public.plantilla_bloque_cambios
  for each row execute function public._trg_plantilla_bloque_cambios_solo_anade();
revoke all on function public._trg_plantilla_bloque_cambios_solo_anade() from public, anon, authenticated, service_role;

-- ------------------------------------------------------------------------------------------------------------------ el validador de bloques: solo lo SOLO-GLOBAL sigue rechazando
create or replace function public._plantilla_exige_bloques(p_cuerpo text, p_esqueleto text, p_empresa text, p_slug text) returns void
 language plpgsql stable security definer set search_path = '' as $$
declare sg text; esq text;
begin
  if public.es_super_admin() then return; end if;               -- el super GLOBAL (con su abogado) si puede
  if p_esqueleto is null then return; end if;                    -- sin esqueleto el validador de S3 ya rechaza
  esq := public._plantilla_sin_notas(p_esqueleto);               -- S7: la semilla v1 trae notas de autor; el cuerpo nuevo no puede (S3)
  select s.motivo into sg from public.plantilla_solo_global s where s.slug = p_slug;
  if sg is not null then
    if public._plantilla_ws(p_cuerpo) is distinct from public._plantilla_ws(esq) then
      raise exception '%', 'Este texto no lo cambia una empresa sola. ' || sg using errcode = '42501';
    end if;
  end if;
  -- 8-oct-2026 (owner): los DEMAS bloques fijos ya no se rechazan aqui. Se avisan en el ensayo y se registran al guardar
  -- (plantilla_contrato_guarda_borrador + _plantilla_bloques_tocados). El esqueleto y los marcadores los sigue exigiendo _plantilla_valida.
end $$;

-- ------------------------------------------------------------------------------------------------------------------ guardar (firma nueva: p_confirma_sensibles)
drop function public.plantilla_contrato_guarda_borrador(text, text, text, text, text);
create function public.plantilla_contrato_guarda_borrador(p_empresa text, p_slug text, p_cuerpo text, p_motivo text, p_variante text default 'estandar', p_confirma_sensibles boolean default false)
 returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := (select auth.uid());
  v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
  v_var   text := coalesce(p_variante, 'estandar');
  v_nom   text;
  v_hash  text; v_bytes int; v_idiomas text[]; v_id uuid; v_n int; v_base uuid; v_esq text; v_bloq text; v_toc jsonb; v_nver int; v_temas text; v_prev text;
begin
  if v_uid is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El texto de los contratos de una empresa lo escribe su administracion' using errcode = '42501';
  end if;
  if v_var !~ '^[a-z][a-z0-9_]{0,39}$' then raise exception 'Revision no valida' using errcode = '22023'; end if;
  if not exists (select 1 from public.empresas e where e.clave = p_empresa and e.activa) then raise exception 'Empresa no valida' using errcode = '22023'; end if;
  if not exists (select 1 from public.plantillas_contrato t where t.slug = p_slug) then raise exception 'Plantilla no valida' using errcode = '22023'; end if;
  if p_cuerpo is null or btrim(p_cuerpo) = '' then raise exception 'Falta el texto' using errcode = '22023'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'Falta el motivo del cambio' using errcode = '22023'; end if;
  v_bytes := pg_catalog.octet_length(p_cuerpo);
  if v_bytes > 1000000 then raise exception 'El texto supera el tope de 1 MB' using errcode = '22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('plantilla/' || p_empresa || '/' || p_slug, 0));
  -- una revision distinta de 'estandar' solo existe si se creo (plantilla_contrato_revision_crea): aqui no nace ninguna
  select (array_agg(v.variante_nombre order by v.version) filter (where v.variante_nombre is not null))[1] into v_nom
    from public.plantilla_contrato_versiones v where v.empresa = p_empresa and v.slug = p_slug and v.variante = v_var and v.borrada_en is null;
  if v_var <> 'estandar' and not exists (select 1 from public.plantilla_contrato_versiones v where v.empresa = p_empresa and v.slug = p_slug and v.variante = v_var and v.borrada_en is null) then
    raise exception 'Esa revision no existe: crea primero la revision' using errcode = '22023';
  end if;
  perform public._plantilla_exige_valido(p_cuerpo, p_empresa, p_slug);
  v_esq := public._plantilla_esqueleto(p_empresa, p_slug);
  perform public._plantilla_exige_bloques(p_cuerpo, v_esq, p_empresa, p_slug);
  -- partes sensibles: se pueden cambiar, pero con aviso confirmado y dejando registro. Se compara con lo YA GUARDADO de esta revision (su borrador o su version vigente),
  -- no con el esqueleto: volver a guardar un borrador que ya llevaba un cambio confirmado no vuelve a pedir el aviso ni duplica el registro.
  v_prev := public._plantilla_base_edicion(p_empresa, p_slug, v_var);
  v_toc := public._plantilla_bloques_tocados(p_cuerpo, coalesce(v_prev, v_esq), p_slug);
  if jsonb_array_length(v_toc) > 0 and p_confirma_sensibles is not true and not public.es_super_admin() then
    select left(string_agg(distinct e ->> 'motivo', ', '), 300) into v_temas from jsonb_array_elements(v_toc) e;
    raise exception 'Has cambiado partes sensibles del contrato (%): confirma que has leido el aviso para guardar el cambio', v_temas using errcode = '22023';
  end if;
  v_bloq := public._plantilla_motivo_bloqueo(p_cuerpo, p_empresa, p_slug);
  v_hash := public._plantilla_hash(p_cuerpo);
  v_idiomas := array_remove(array[
    case when p_cuerpo like '%data-lang="es"%' then 'es' end,
    case when p_cuerpo like '%data-lang="en"%' then 'en' end,
    case when p_cuerpo like '%data-lang="id"%' then 'id' end], null);
  select v.id into v_id from public.plantilla_contrato_versiones v
   where v.empresa = p_empresa and v.slug = p_slug and v.variante = v_var and v.estado = 'borrador' and v.origen = 'empresa' and v.borrada_en is null for update;
  if found then
    update public.plantilla_contrato_versiones
       set hash = v_hash, bytes = v_bytes, idioma_set = v_idiomas, autor = v_autor, fecha = now(), motivo = btrim(p_motivo),
           activable = (v_bloq is null), bloqueo_motivo = v_bloq
     where id = v_id;
    update public.plantilla_contrato_cuerpos set cuerpo_html = p_cuerpo where version_id = v_id;
  else
    select coalesce(max(v.version), 0) + 1 into v_n from public.plantilla_contrato_versiones v where v.empresa = p_empresa and v.slug = p_slug;
    select v.id into v_base from public.plantilla_contrato_versiones v
     where v.empresa = p_empresa and v.slug = p_slug and v.variante = v_var and v.borrada_en is null and (v.estado <> 'borrador' or v.origen = 'semilla')
     order by (v.estado = 'activa') desc, v.version desc limit 1;
    insert into public.plantilla_contrato_versiones (empresa, slug, version, estado, origen, idioma_set, hash, bytes, activable, bloqueo_motivo, hereda_de, autor, motivo, variante, variante_nombre)
    values (p_empresa, p_slug, v_n, 'borrador', 'empresa', v_idiomas, v_hash, v_bytes, v_bloq is null, v_bloq, v_base, v_autor, btrim(p_motivo), v_var, v_nom)
    returning id into v_id;
    insert into public.plantilla_contrato_cuerpos (version_id, cuerpo_html) values (v_id, p_cuerpo);
  end if;
  if jsonb_array_length(v_toc) > 0 then
    select v.version into v_nver from public.plantilla_contrato_versiones v where v.id = v_id;
    insert into public.plantilla_bloque_cambios (empresa, slug, variante, version_id, version, n, clase, motivo, antes, despues, aviso_confirmado, motivo_cambio, autor, autor_uid)
    select p_empresa, p_slug, v_var, v_id, v_nver, t.ord::int, t.e ->> 'clase', t.e ->> 'motivo', t.e ->> 'antes', t.e ->> 'despues',
           (p_confirma_sensibles is true), btrim(p_motivo), v_autor, v_uid
      from jsonb_array_elements(v_toc) with ordinality t(e, ord);
  end if;
  return v_id;
end $$;
revoke all on function public.plantilla_contrato_guarda_borrador(text, text, text, text, text, boolean) from public, anon, service_role;
grant execute on function public.plantilla_contrato_guarda_borrador(text, text, text, text, text, boolean) to authenticated;

-- ------------------------------------------------------------------------------------------------------------------ ensayo: avisa de los bloques tocados antes de guardar
drop function public.plantilla_contrato_revisa(text, text, text);
create function public.plantilla_contrato_revisa(p_empresa text, p_slug text, p_cuerpo text, p_variante text default 'estandar') returns jsonb
 language plpgsql stable security definer set search_path = '' as $$
declare r jsonb; v_err text[]; v_esq text; v_bloq text; v_toc jsonb := '[]'::jsonb; v_prev text;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El texto de los contratos de una empresa lo escribe su administracion' using errcode = '42501';
  end if;
  if not exists (select 1 from public.plantillas_contrato t where t.slug = p_slug) then raise exception 'Plantilla no valida' using errcode = '22023'; end if;
  if p_cuerpo is null or btrim(p_cuerpo) = '' then raise exception 'Falta el texto' using errcode = '22023'; end if;
  if pg_catalog.octet_length(p_cuerpo) > 1000000 then raise exception 'El texto supera el tope de 1 MB' using errcode = '22023'; end if;
  v_esq := public._plantilla_esqueleto(p_empresa, p_slug);
  perform public._plantilla_cx_contexto(p_empresa, false);
  r := public._plantilla_valida(p_cuerpo, v_esq, false);
  perform pg_catalog.set_config('lw.cx_catalogo', '', true);                                             -- S3: la misma que usa guarda_borrador
  v_err := array(select jsonb_array_elements_text(r -> 'errores'));
  if cardinality(v_err) = 0 then
    begin
      perform public._plantilla_exige_bloques(p_cuerpo, v_esq, p_empresa, p_slug);                   -- F2: la misma (hoy solo rechaza lo SOLO-GLOBAL)
    exception when insufficient_privilege then
      v_err := v_err || sqlerrm;
    end;
  end if;
  if cardinality(v_err) = 0 then
    v_prev := public._plantilla_base_edicion(p_empresa, p_slug, coalesce(p_variante, 'estandar'));      -- lo mismo contra lo que compara el guardado
    v_toc := public._plantilla_bloques_tocados(p_cuerpo, coalesce(v_prev, v_esq), p_slug);
  end if;
  v_bloq := case when cardinality(v_err) = 0 then public._plantilla_motivo_bloqueo(p_cuerpo, p_empresa, p_slug) end;   -- F1
  return jsonb_build_object('ok', cardinality(v_err) = 0, 'errores', to_jsonb(v_err[1:40]), 'activable', cardinality(v_err) = 0 and v_bloq is null, 'bloqueo', v_bloq,
                            'n_marcadores', (r ->> 'n_marcadores')::int, 'bytes', pg_catalog.octet_length(p_cuerpo),
                            'sensibles', jsonb_array_length(v_toc) > 0,
                            'bloques_tocados', (select coalesce(jsonb_agg(jsonb_build_object('clase', e ->> 'clase', 'motivo', e ->> 'motivo', 'antes', left(e ->> 'antes', 600), 'despues', left(e ->> 'despues', 600))), '[]'::jsonb)
                                                  from jsonb_array_elements(v_toc) e));
end $$;

revoke all on function public.plantilla_contrato_revisa(text, text, text, text) from public, anon, service_role;
grant execute on function public.plantilla_contrato_revisa(text, text, text, text) to authenticated;

-- ------------------------------------------------------------------------------------------------------------------ edicion: el motivo de cada bloque fijo
create or replace function public.plantilla_contrato_edicion(p_empresa text, p_slug text, p_variante text default 'estandar') returns jsonb
 language plpgsql stable security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_c text; v_limpio text; v_solo text; v_nunca text; v_global boolean := public.es_super_admin(); v_bf text[];
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El texto de los contratos de una empresa lo escribe su administracion' using errcode = '42501';
  end if;
  -- base de edicion DENTRO de la revision: el borrador propio; si no hay, la activa; si no, la archivada o la semilla v1 (nunca una retirada ni una borrada)
  select * into v from public.plantilla_contrato_versiones x
   where x.empresa = p_empresa and x.slug = p_slug and x.variante = coalesce(p_variante, 'estandar') and x.estado <> 'retirada' and x.borrada_en is null
   order by (x.estado = 'borrador' and x.origen = 'empresa') desc, (x.estado = 'activa') desc, x.version desc limit 1;
  if not found then raise exception 'Esa plantilla no tiene texto para esa empresa' using errcode = '22023'; end if;
  select c.cuerpo_html into v_c from public.plantilla_contrato_cuerpos c where c.version_id = v.id;
  v_limpio := public._plantilla_sin_notas(v_c);
  select s.motivo into v_solo from public.plantilla_solo_global s where s.slug = p_slug;
  select n.motivo into v_nunca from public.plantilla_nunca_activable n where n.empresa = p_empresa and n.slug = p_slug;
  v_bf := case when v_global or v_solo is not null then '{}'::text[] else public._plantilla_bloques_fijos(v_limpio, p_slug) end;
  return jsonb_build_object(
    'empresa', v.empresa, 'slug', v.slug, 'version_id', v.id, 'version', v.version, 'estado', v.estado, 'origen', v.origen, 'hash', v.hash,
    'variante', v.variante, 'variante_nombre', v.variante_nombre,
    'cuerpo_html', v_limpio, 'notas_quitadas', pg_catalog.octet_length(v_c) - pg_catalog.octet_length(v_limpio),
    'solo_global', case when v_global then null else v_solo end,                                   -- el super global si puede (con su abogado)
    'nunca_activable', v_nunca,
    'bloques_fijos', to_jsonb(v_bf),
    -- el motivo de cada bloque fijo, en el MISMO orden que bloques_fijos (los bloques son sensibles: se editan con aviso y quedan registrados)
    'bloques_fijos_motivos', coalesce((select jsonb_agg(jsonb_build_object('clase', case left(b, 1) when 'M' then 'region' when 'E' then 'elemento' when 'S' then 'seccion' else 'residuo' end,
                                                                            'motivo', public._plantilla_bloque_motivo(b, p_slug)) order by o)
                                        from unnest(v_bf) with ordinality t(b, o)), '[]'::jsonb),
    'puede_activar', public.es_super_admin_de(p_empresa),
    'bloqueo', public._plantilla_motivo_bloqueo(v_limpio, p_empresa, p_slug));
end $$;

-- ------------------------------------------------------------------------------------------------------------------ lectura del registro
create function public.plantilla_contrato_cambios_sensibles(p_empresa text, p_slug text default null, p_limite int default 50) returns jsonb
 language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El registro de cambios de los contratos de una empresa lo ve su administracion' using errcode = '42501';
  end if;
  return jsonb_build_object('cambios', coalesce((
    select jsonb_agg(to_jsonb(q) order by q.fecha desc, q.n)
      from (select c.slug, c.variante, c.version, c.n, c.clase, c.motivo, c.antes, c.despues, c.aviso_confirmado, c.motivo_cambio, c.autor, c.fecha
              from public.plantilla_bloque_cambios c
             where c.empresa = p_empresa and (p_slug is null or c.slug = p_slug)
             order by c.fecha desc, c.n
             limit least(greatest(coalesce(p_limite, 50), 1), 200)) q), '[]'::jsonb));
end $$;
revoke all on function public.plantilla_contrato_cambios_sensibles(text, text, int) from public, anon, service_role;
grant execute on function public.plantilla_contrato_cambios_sensibles(text, text, int) to authenticated;
