-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «plantillas de contrato por empresa» · S2 · migracion 2/4 (7-oct-2026): ESCRITURA, solo por RPC (SECURITY DEFINER, search_path vacio, sin EXECUTE para anon).
--   plantilla_contrato_guarda_borrador(empresa, slug, cuerpo, motivo) -> uuid   Llamador: pantalla Plantillas por empresa (S7). admin_empresa y super_admin_empresa de ESA empresa (y el global).
--   plantilla_contrato_activa(version, nombre, confirma) -> jsonb               Llamador: S7. SOLO super_admin_empresa de esa empresa o el global; exige confirmacion explicita que se guarda con la version.
--   plantilla_contrato_descarta_borrador(version)                               Llamador: S7. El borrador pasa a retirada (nada se borra).
--   El hash sha256 y el tamano los calcula el servidor; el cuerpo pasa por public.plantilla_cuerpo_valida(cuerpo, esqueleto) -> {ok, errores[]} (la pone S3; sin ella, fallo cerrado).
--   Un borrador por (empresa, plantilla): guardar de nuevo reescribe ese borrador; la version solo se congela al activar.
-- destructivo-ok: solo crea funciones nuevas
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_plantillas_s2.sql

-- esqueleto contra el que se compara un cuerpo: la activa de la empresa; si no hay, la semilla mas antigua
create or replace function public._plantilla_esqueleto(p_empresa text, p_slug text) returns text
language sql stable security definer set search_path = '' as $$
  select c.cuerpo_html
    from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
   where v.empresa = p_empresa and v.slug = p_slug and (v.estado = 'activa' or v.origen = 'semilla')
   order by (v.estado = 'activa') desc, v.version asc
   limit 1
$$;
revoke all on function public._plantilla_esqueleto(text, text) from public, anon, authenticated, service_role;

-- el validador de servidor (S3) manda; aqui solo se exige que exista y que diga ok
create or replace function public._plantilla_valida(p_cuerpo text, p_empresa text, p_slug text) returns void
language plpgsql security definer set search_path = '' as $$
declare r jsonb;
begin
  if pg_catalog.to_regprocedure('public.plantilla_cuerpo_valida(text,text)') is null then
    raise exception 'El validador de plantillas no esta instalado: no se guarda ni se activa nada' using errcode = '55000';
  end if;
  execute 'select public.plantilla_cuerpo_valida($1, $2)' into r using p_cuerpo, public._plantilla_esqueleto(p_empresa, p_slug);
  if r is null or coalesce((r ->> 'ok')::boolean, false) is not true then
    raise exception 'El texto no pasa la validacion: %', coalesce(left((select string_agg(e, ' | ') from (select jsonb_array_elements_text(r -> 'errores') e limit 5) q), 600), 'sin detalle') using errcode = '22023';
  end if;
end $$;
revoke all on function public._plantilla_valida(text, text, text) from public, anon, authenticated, service_role;

create or replace function public.plantilla_contrato_guarda_borrador(p_empresa text, p_slug text, p_cuerpo text, p_motivo text)
 returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := (select auth.uid());
  v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
  v_hash  text; v_bytes int; v_idiomas text[]; v_id uuid; v_n int; v_base uuid;
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
  perform public._plantilla_valida(p_cuerpo, p_empresa, p_slug);
  v_hash := public._plantilla_hash(p_cuerpo);
  v_idiomas := array_remove(array[
    case when p_cuerpo like '%data-lang="es"%' then 'es' end,
    case when p_cuerpo like '%data-lang="en"%' then 'en' end,
    case when p_cuerpo like '%data-lang="id"%' then 'id' end], null);
  select v.id into v_id from public.plantilla_contrato_versiones v
   where v.empresa = p_empresa and v.slug = p_slug and v.estado = 'borrador' and v.origen = 'empresa' for update;
  if found then
    update public.plantilla_contrato_versiones set hash = v_hash, bytes = v_bytes, idioma_set = v_idiomas, autor = v_autor, fecha = now(), motivo = btrim(p_motivo)
     where id = v_id;
    update public.plantilla_contrato_cuerpos set cuerpo_html = p_cuerpo where version_id = v_id;
  else
    select coalesce(max(v.version), 0) + 1 into v_n from public.plantilla_contrato_versiones v where v.empresa = p_empresa and v.slug = p_slug;
    select v.id into v_base from public.plantilla_contrato_versiones v
     where v.empresa = p_empresa and v.slug = p_slug and (v.estado <> 'borrador' or v.origen = 'semilla')
     order by (v.estado = 'activa') desc, v.version desc limit 1;
    insert into public.plantilla_contrato_versiones (empresa, slug, version, estado, origen, idioma_set, hash, bytes, activable, hereda_de, autor, motivo)
    values (p_empresa, p_slug, v_n, 'borrador', 'empresa', v_idiomas, v_hash, v_bytes, true, v_base, v_autor, btrim(p_motivo))
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
  v_body  text;
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
  perform public._plantilla_valida(v_body, v.empresa, v.slug);
  update public.plantilla_contrato_versiones set estado = 'retirada', retirada_por = v_email, retirada_en = now()
   where empresa = v.empresa and slug = v.slug and estado = 'activa';
  update public.plantilla_contrato_versiones
     set estado = 'activa', activado_por = v_email, activado_en = now(), confirmacion_nombre = btrim(p_nombre), confirmacion_texto = v_texto
   where id = v.id;
  return jsonb_build_object('version_id', v.id, 'version', v.version, 'empresa', v.empresa, 'slug', v.slug, 'activado_por', v_email);
end $$;

create or replace function public.plantilla_contrato_descarta_borrador(p_version uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_email text := coalesce((select auth.email()), (select auth.uid())::text);
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  select * into v from public.plantilla_contrato_versiones x where x.id = p_version for update;
  if not found or not (public.es_admin_de(v.empresa) and public.empresa_en_alcance(v.empresa)) then
    raise exception 'El texto de los contratos de una empresa lo escribe su administracion' using errcode = '42501';
  end if;
  if v.estado <> 'borrador' or v.origen <> 'empresa' then raise exception 'Solo se descarta un borrador de la empresa' using errcode = '55000'; end if;
  update public.plantilla_contrato_versiones set estado = 'retirada', retirada_por = v_email, retirada_en = now() where id = v.id;
end $$;

revoke all on function public.plantilla_contrato_guarda_borrador(text, text, text, text), public.plantilla_contrato_activa(uuid, text, boolean),
  public.plantilla_contrato_descarta_borrador(uuid) from public, anon, service_role;
grant execute on function public.plantilla_contrato_guarda_borrador(text, text, text, text), public.plantilla_contrato_activa(uuid, text, boolean),
  public.plantilla_contrato_descarta_borrador(uuid) to authenticated;
