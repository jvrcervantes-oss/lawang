-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «plantillas de contrato por empresa» · S2 · migracion 3/4 (7-oct-2026): LECTURA. RPC SECURITY DEFINER con duenno lw_lector (patron del bloque 6: la RLS filtra como el que llama),
--   search_path vacio, sin EXECUTE para anon. La empresa se DEDUCE en servidor (del proyecto, o de la unica empresa del que llama); el cliente nunca elige empresa para leer un texto.
--   plantilla_contrato_cuerpo(slug, proyecto?, etag?)   -> jsonb | null   La version ACTIVA de la empresa del proyecto. null = sin empresa o sin version activa: el cliente usa el fichero.
--                                                                         Llamador: generador contracts/app.html loadTemplate() (S5). Empresa de otra: 42501.
--   plantilla_contrato_cuerpo_version(version, etag?)   -> jsonb          Una version por id (borrador solo para quien edita esa empresa; el resto, la activa o la de un contrato que ve). Llamador: S5 y pantalla S7.
--   plantilla_contrato_version_de_contrato(contrato)    -> jsonb | null   Que version fijo el contrato (sin cuerpo). Llamador: S5 al abrir un contrato.
--   plantilla_contrato_versiones_lista(empresa?, slug?) -> filas SIN cuerpo (R9). Quien edita ve todos los estados de su empresa; un agente solo las activas. Llamador: pantalla S7.
--   etag: si coincide con el hash de la version no se envia el cuerpo (cache del cliente).
-- destructivo-ok: solo crea funciones nuevas
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_plantillas_s2.sql

create function public.plantilla_contrato_cuerpo(p_slug text, p_proyecto uuid default null, p_etag text default null)
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

create function public.plantilla_contrato_cuerpo_version(p_version uuid, p_etag text default null)
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

create function public.plantilla_contrato_version_de_contrato(p_contrato uuid)
 returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  if public.uid_sesion() is null or not public.es_agente() then raise exception 'Sin sesion de agente' using errcode = '42501'; end if;
  select jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'estado', v.estado, 'origen', v.origen, 'hash', v.hash)
    into r
    from public.contrato_plantilla_version l join public.plantilla_contrato_versiones v on v.id = l.version_id
   where l.contrato_id = p_contrato;                                                        -- la policy del vinculo exige poder ver el contrato
  return r;
end $$;

create function public.plantilla_contrato_versiones_lista(p_empresa text default null, p_slug text default null)
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

-- duenno lw_lector (patron b6): la RLS de las tres tablas filtra como el que llama
grant create on schema public to lw_lector;
alter function public.plantilla_contrato_cuerpo(text, uuid, text) owner to lw_lector;
alter function public.plantilla_contrato_cuerpo_version(uuid, text) owner to lw_lector;
alter function public.plantilla_contrato_version_de_contrato(uuid) owner to lw_lector;
alter function public.plantilla_contrato_versiones_lista(text, text) owner to lw_lector;
revoke create on schema public from lw_lector;
revoke all on function public.plantilla_contrato_cuerpo(text, uuid, text), public.plantilla_contrato_cuerpo_version(uuid, text),
  public.plantilla_contrato_version_de_contrato(uuid), public.plantilla_contrato_versiones_lista(text, text) from public, anon, service_role;
grant execute on function public.plantilla_contrato_cuerpo(text, uuid, text), public.plantilla_contrato_cuerpo_version(uuid, text),
  public.plantilla_contrato_version_de_contrato(uuid), public.plantilla_contrato_versiones_lista(text, text) to authenticated;
