-- Reversion de la migracion 20261008990100 (S2 · bloqueos F1/F2, 7-oct-2026).
-- Devuelve guarda_borrador y activa a su version de la migracion 980100 (sin F1 ni F2), quita las 7 funciones y las 5 tablas de politica y devuelve EXECUTE a authenticated en las 8 RPC.
-- NO deshace el parche de S3 (prom_cargo, promotora_razon y los comentarios bloque-fijo:*): son listas cerradas ampliadas, inofensivas sin llamadores; para quitarlas habria que
-- reaplicar el cuerpo original de 20261008990000. Aborta si hay versiones activadas o retiradas (historia que no se tira sin decision del owner), igual que la reversion de S2.
-- destructivo-ok: retira objetos creados por esta migracion; sin datos de contratos
begin;
do $$ begin
  if exists (select 1 from public.plantilla_contrato_versiones where estado in ('activa', 'retirada')) then
    raise exception 'Hay versiones activadas o retiradas: no se revierte sin decision del owner';
  end if;
end $$;
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
  perform public._plantilla_exige_valido(p_cuerpo, p_empresa, p_slug);
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
  perform public._plantilla_exige_valido(v_body, v.empresa, v.slug);
  update public.plantilla_contrato_versiones set estado = 'retirada', retirada_por = v_email, retirada_en = now()
   where empresa = v.empresa and slug = v.slug and estado = 'activa';
  update public.plantilla_contrato_versiones
     set estado = 'activa', activado_por = v_email, activado_en = now(), confirmacion_nombre = btrim(p_nombre), confirmacion_texto = v_texto
   where id = v.id;
  return jsonb_build_object('version_id', v.id, 'version', v.version, 'empresa', v.empresa, 'slug', v.slug, 'activado_por', v_email);
end $$;


drop function if exists public._plantilla_exige_bloques(text, text, text, text);
drop function if exists public._plantilla_bloques_fijos(text, text);
drop function if exists public._plantilla_ws(text);
drop function if exists public._plantilla_motivo_bloqueo(text, text, text);
drop function if exists public._plantilla_otra_sociedad(text, text);
drop function if exists public._plantilla_terminos(text);
drop function if exists public._plantilla_norm(text);
drop table if exists public.plantilla_bloque_regla;
drop table if exists public.plantilla_ficha;
drop table if exists public.plantilla_solo_global;
drop table if exists public.plantilla_nunca_activable;
drop table if exists public.plantilla_sociedad_cruce;
grant execute on function public.plantilla_contrato_guarda_borrador(text, text, text, text), public.plantilla_contrato_activa(uuid, text, boolean),
  public.plantilla_contrato_descarta_borrador(uuid), public.plantilla_contrato_cuerpo(text, uuid, text), public.plantilla_contrato_cuerpo_version(uuid, text),
  public.plantilla_contrato_version_de_contrato(uuid), public.plantilla_contrato_versiones_lista(text, text), public.plantilla_contrato_fija(uuid, uuid) to authenticated;
commit;
