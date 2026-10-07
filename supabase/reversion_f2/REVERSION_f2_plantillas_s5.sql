-- Reversion de la migracion 20261009000000 (S5 · lectura y candados, 7-oct-2026).
-- Devuelve cuerpo/fija/activa/descarta_borrador a su definicion anterior (cuerpo sin caida a la semilla; fija solo de version activa y sin comprobar la plantilla; activa con el orden
-- `for update` -> candado asesor, es decir CON el interbloqueo; descarta sin candado asesor), restituye la policy de lectura sin semillas, quita cuerpo_de_contrato y _plantilla_slug_de_tipo
-- y deja las 8 RPC de S2 otra vez sin EXECUTE para authenticated (estado de 20261008990100). Aborta si hay versiones activadas o retiradas (historia que no se tira sin decision del owner).
-- destructivo-ok: retira dos funciones creadas por esta migracion y restituye las anteriores; sin datos
begin;
do $$ begin
  if exists (select 1 from public.plantilla_contrato_versiones where estado in ('activa', 'retirada')) then
    raise exception 'Hay versiones activadas o retiradas: no se revierte sin decision del owner';
  end if;
end $$;
create or replace function public.plantilla_contrato_cuerpo(p_slug text, p_proyecto uuid default null, p_etag text default null)
 returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_emp text; v_mis text[]; v public.plantilla_contrato_versiones%rowtype; v_c text;
begin
  if public.uid_sesion() is null or not public.es_agente() then raise exception 'Sin sesion de agente' using errcode = '42501'; end if;
  v_mis := public.mis_empresas();
  if p_proyecto is not null then v_emp := public.empresa_de_proyecto(p_proyecto);
  elsif cardinality(v_mis) = 1 then v_emp := v_mis[1]; end if;
  if v_emp is null then return null; end if;                                  -- sin empresa: nada que servir desde la base
  if not public.empresa_en_alcance(v_emp) then raise exception 'Esa empresa no es de tu alcance' using errcode = '42501'; end if;
  select * into v from public.plantilla_contrato_versiones x where x.empresa = v_emp and x.slug = p_slug and x.estado = 'activa';
  if not found then return null; end if;
  if p_etag is not null and p_etag = v.hash then
    return jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'hash', v.hash, 'sin_cambios', true);
  end if;
  select c.cuerpo_html into v_c from public.plantilla_contrato_cuerpos c where c.version_id = v.id;
  return jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'hash', v.hash, 'estado', v.estado, 'origen', v.origen, 'cuerpo_html', v_c);
end $$;
create or replace function public.plantilla_contrato_fija(p_contrato uuid, p_version uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_agente() and public._puede_herr_o_super_empresa('contratos') and public.puede_ver_contrato(p_contrato)) then
    raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
  end if;
  select * into v from public.plantilla_contrato_versiones x where x.id = p_version;
  if not found or v.estado <> 'activa' then raise exception 'Solo se fija una version activa' using errcode = '22023'; end if;
  insert into public.contrato_plantilla_version (contrato_id, version_id, fijado_por) values (p_contrato, p_version, v_autor)
  on conflict (contrato_id) do update set version_id = excluded.version_id, fijado_en = now(), fijado_por = excluded.fijado_por;
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
drop policy "versiones: lectura por empresa" on public.plantilla_contrato_versiones;
create policy "versiones: lectura por empresa" on public.plantilla_contrato_versiones for select to lw_lector
  using (public.es_agente() and public.empresa_en_alcance(empresa)
         and (estado <> 'borrador' or public.es_admin_de(empresa)
              or exists (select 1 from public.contrato_plantilla_version l where l.version_id = plantilla_contrato_versiones.id)));
drop function public.plantilla_contrato_cuerpo_de_contrato(uuid, text);
drop function public._plantilla_slug_de_tipo(text);
revoke all on function public.plantilla_contrato_cuerpo(text, uuid, text), public.plantilla_contrato_fija(uuid, uuid) from public, anon, authenticated, service_role;
commit;
