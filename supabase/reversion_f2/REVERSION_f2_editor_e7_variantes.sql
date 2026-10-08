-- Reversion de la migracion 20261010000000 (E7 · revisiones multiples activas, 8-oct-2026).
-- Devuelve el modelo a «una sola activa y un solo borrador por (empresa, slug)»: indices viejos, CHECK de estado viejo, triggers viejos y las 13 funciones a su definicion de 20261008980200 / 20261009010000 / 20261009020000.
-- GUARDA: aborta si ya existe alguna revision que no sea 'estandar', alguna version archivada o alguna borrada. Con datos de revisiones, la reversion pierde informacion: antes hay que decidir que se hace
--   con ellas (retirar o fusionar a mano). Las COLUMNAS nuevas (variante, variante_nombre, archivada_*, borrada_*) se dejan donde estan: soltarlas destruye datos y no estorban a nada.
-- Las 5 RPC nuevas y el ayudante _plantilla_parrafos se eliminan. plantilla_contrato_fija se elimina y se recrea (create or replace no puede quitar el DEFAULT del parametro).
-- destructivo-ok: no toca filas; reemplaza indices, un CHECK, triggers y funciones por sus versiones anteriores; aborta antes si hay revisiones que perderia
begin;

do $g$
declare n int;
begin
  select count(*) into n from public.plantilla_contrato_versiones where variante <> 'estandar' or estado = 'archivada' or borrada_en is not null;
  if n > 0 then
    raise exception 'REVERSION ABORTADA: hay % version(es) de revisiones no estandar, archivadas o borradas. Retirala(s) o fusionalas antes.', n using errcode = '55000';
  end if;
end $g$;

-- 5 RPC nuevas y ayudante
drop function if exists public.plantilla_contrato_revision_crea(text, text, uuid, text, text, text);
drop function if exists public.plantilla_contrato_revision_archiva(text, text, text);
drop function if exists public.plantilla_contrato_revision_restaura(text, text, text);
drop function if exists public.plantilla_contrato_revision_borra(text, text, text);
drop function if exists public.plantilla_contrato_revisiones_lista(text, text);
drop function if exists public._plantilla_parrafos(text);

-- indices y CHECK de antes
create unique index plantilla_una_activa_old on public.plantilla_contrato_versiones (empresa, slug) where estado = 'activa';
create unique index plantilla_un_borrador_old on public.plantilla_contrato_versiones (empresa, slug) where estado = 'borrador' and origen = 'empresa';
drop index public.plantilla_una_activa;
drop index public.plantilla_un_borrador;
drop index if exists public.plantilla_una_archivada_v;
alter index public.plantilla_una_activa_old rename to plantilla_una_activa;
alter index public.plantilla_un_borrador_old rename to plantilla_un_borrador;
alter table public.plantilla_contrato_versiones drop constraint plantilla_contrato_versiones_estado_check;
alter table public.plantilla_contrato_versiones
  add constraint plantilla_contrato_versiones_estado_check check (estado = any (array['borrador', 'activa', 'retirada']));

-- triggers de antes
create or replace function public._trg_plantilla_version_ins() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.estado <> 'borrador' or new.activado_por is not null or new.activado_en is not null or new.retirada_por is not null or new.retirada_en is not null
     or new.confirmacion_nombre is not null or new.confirmacion_texto is not null then
    raise exception 'Una version nace siempre como borrador; activar es un acto aparte (plantilla_contrato_activa)' using errcode = '55000';
  end if;
  return new;
end $$;

create or replace function public._trg_plantilla_version_upd() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_body text;
begin
  if old.estado = 'retirada' then
    raise exception 'Una version retirada no se modifica (queda para siempre)' using errcode = '55000';
  end if;
  if old.origen = 'semilla' then
    raise exception 'Una semilla del estudio no se modifica ni se activa: se parte de ella para escribir una version nueva' using errcode = '55000';
  end if;
  if (old.id, old.empresa, old.slug, old.version, old.origen, old.hereda_de) is distinct from (new.id, new.empresa, new.slug, new.version, new.origen, new.hereda_de) then
    raise exception 'Identidad de la version inmutable (empresa, plantilla, version, origen)' using errcode = '55000';
  end if;
  if old.estado = 'activa' then
    if new.estado <> 'retirada' or (to_jsonb(new) - 'estado' - 'retirada_por' - 'retirada_en') is distinct from (to_jsonb(old) - 'estado' - 'retirada_por' - 'retirada_en') then
      raise exception 'Una version activa es inmutable: solo puede pasar a retirada' using errcode = '55000';
    end if;
    return new;
  end if;
  if new.estado = 'retirada' then
    if new.retirada_por is null or new.retirada_en is null then raise exception 'Falta quien retira' using errcode = '22023'; end if;
    return new;
  end if;
  if new.estado = 'activa' then
    if not old.activable then
      raise exception 'Version no activable: %', coalesce(old.bloqueo_motivo, 'sin motivo') using errcode = '55000';
    end if;
    select c.cuerpo_html into v_body from public.plantilla_contrato_cuerpos c where c.version_id = old.id;
    if v_body is null or public._plantilla_hash(v_body) is distinct from new.hash then
      raise exception 'El hash de la version no coincide con su cuerpo' using errcode = '55000';
    end if;
    return new;
  end if;
  return new;
end $$;

create or replace function public._plantilla_esqueleto(p_empresa text, p_slug text) returns text language sql stable security definer set search_path = '' as $$
  select c.cuerpo_html
    from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
   where v.empresa = p_empresa and v.slug = p_slug and (v.estado = 'activa' or v.origen = 'semilla')
   order by (v.estado = 'activa') desc, v.version asc
   limit 1
$$;

-- funciones de lectura (duenno lw_lector) y escritura de antes
grant create on schema public to lw_lector;

drop function public.plantilla_contrato_cuerpo(text, uuid, text, uuid);
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
  select * into v from public.plantilla_contrato_versiones x
   where x.empresa = v_emp and x.slug = p_slug and (x.estado = 'activa' or (x.origen = 'semilla' and x.version = 1))
   order by (x.estado = 'activa') desc limit 1;
  if not found then return null; end if;
  if p_etag is not null and p_etag = v.hash then
    return jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'hash', v.hash, 'sin_cambios', true);
  end if;
  select c.cuerpo_html into v_c from public.plantilla_contrato_cuerpos c where c.version_id = v.id;
  return jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'hash', v.hash, 'estado', v.estado, 'origen', v.origen, 'cuerpo_html', v_c);
end $$;
alter function public.plantilla_contrato_cuerpo(text, uuid, text) owner to lw_lector;
revoke all on function public.plantilla_contrato_cuerpo(text, uuid, text) from public, anon, service_role;
grant execute on function public.plantilla_contrato_cuerpo(text, uuid, text) to authenticated;

create or replace function public.plantilla_contrato_cuerpo_de_contrato(p_contrato uuid, p_etag text default null)
 returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_c text;
begin
  if public.uid_sesion() is null or not public.es_agente() then raise exception 'Sin sesion de agente' using errcode = '42501'; end if;
  if not public.puede_ver_contrato(p_contrato) then raise exception 'No tienes acceso a ese contrato' using errcode = '42501'; end if;
  select x.* into v from public.contrato_plantilla_version l join public.plantilla_contrato_versiones x on x.id = l.version_id where l.contrato_id = p_contrato;
  if not found then return null; end if;                                      -- sin vinculo = el contrato sigue con el fichero
  if p_etag is not null and p_etag = v.hash then
    return jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'hash', v.hash, 'sin_cambios', true);
  end if;
  select c.cuerpo_html into v_c from public.plantilla_contrato_cuerpos c where c.version_id = v.id;
  return jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'hash', v.hash, 'estado', v.estado, 'origen', v.origen, 'cuerpo_html', v_c);
end $$;

create or replace function public.plantilla_contrato_cuerpo_version(p_version uuid, p_etag text default null)
 returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_c text;
begin
  if public.uid_sesion() is null or not public.es_agente() then raise exception 'Sin sesion de agente' using errcode = '42501'; end if;
  select * into v from public.plantilla_contrato_versiones x where x.id = p_version;
  if not found then raise exception 'No tienes acceso a ese texto' using errcode = '42501'; end if;
  if not public.empresa_en_alcance(v.empresa) then raise exception 'No tienes acceso a ese texto' using errcode = '42501'; end if;
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

create or replace function public.plantilla_contrato_version_de_contrato(p_contrato uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  if public.uid_sesion() is null or not public.es_agente() then raise exception 'Sin sesion de agente' using errcode = '42501'; end if;
  select jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'estado', v.estado, 'origen', v.origen, 'hash', v.hash)
    into r
    from public.contrato_plantilla_version l join public.plantilla_contrato_versiones v on v.id = l.version_id
   where l.contrato_id = p_contrato;
  return r;
end $$;

drop function public.plantilla_contrato_versiones_lista(text, text);
create function public.plantilla_contrato_versiones_lista(p_empresa text default null, p_slug text default null)
 returns table(id uuid, empresa text, slug text, version integer, estado text, origen text, idioma_set text[], hash text, bytes integer, activable boolean, bloqueo_motivo text,
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
       and public.empresa_en_alcance(v.empresa)
       and (v.estado = 'activa' or public.es_admin_de(v.empresa))
     order by v.empresa, v.slug, v.version desc;
end $$;
alter function public.plantilla_contrato_versiones_lista(text, text) owner to lw_lector;
revoke all on function public.plantilla_contrato_versiones_lista(text, text) from public, anon, service_role;
grant execute on function public.plantilla_contrato_versiones_lista(text, text) to authenticated;

drop function public.plantilla_contrato_edicion(text, text, text);
create function public.plantilla_contrato_edicion(p_empresa text, p_slug text) returns jsonb
 language plpgsql stable security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_c text; v_limpio text; v_solo text; v_nunca text; v_global boolean := public.es_super_admin();
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El texto de los contratos de una empresa lo escribe su administracion' using errcode = '42501';
  end if;
  -- base de edicion: el borrador propio de la empresa; si no hay, la activa; si no, la semilla v1 (nunca una retirada)
  select * into v from public.plantilla_contrato_versiones x
   where x.empresa = p_empresa and x.slug = p_slug and x.estado <> 'retirada'
   order by (x.estado = 'borrador' and x.origen = 'empresa') desc, (x.estado = 'activa') desc, x.version desc limit 1;
  if not found then raise exception 'Esa plantilla no tiene texto para esa empresa' using errcode = '22023'; end if;
  select c.cuerpo_html into v_c from public.plantilla_contrato_cuerpos c where c.version_id = v.id;
  v_limpio := public._plantilla_sin_notas(v_c);
  select s.motivo into v_solo from public.plantilla_solo_global s where s.slug = p_slug;
  select n.motivo into v_nunca from public.plantilla_nunca_activable n where n.empresa = p_empresa and n.slug = p_slug;
  return jsonb_build_object(
    'empresa', v.empresa, 'slug', v.slug, 'version_id', v.id, 'version', v.version, 'estado', v.estado, 'origen', v.origen, 'hash', v.hash,
    'cuerpo_html', v_limpio, 'notas_quitadas', pg_catalog.octet_length(v_c) - pg_catalog.octet_length(v_limpio),
    'solo_global', case when v_global then null else v_solo end,
    'nunca_activable', v_nunca,
    'bloques_fijos', case when v_global or v_solo is not null then '[]'::jsonb else to_jsonb(public._plantilla_bloques_fijos(v_limpio, p_slug)) end,
    'puede_activar', public.es_super_admin_de(p_empresa),
    'bloqueo', public._plantilla_motivo_bloqueo(v_limpio, p_empresa, p_slug));
end $$;
revoke all on function public.plantilla_contrato_edicion(text, text) from public, anon, service_role;
grant execute on function public.plantilla_contrato_edicion(text, text) to authenticated;

drop function public.plantilla_contrato_guarda_borrador(text, text, text, text, text);
create function public.plantilla_contrato_guarda_borrador(p_empresa text, p_slug text, p_cuerpo text, p_motivo text) returns uuid
 language plpgsql security definer set search_path = '' as $$
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
  perform public._plantilla_exige_bloques(p_cuerpo, v_esq, p_empresa, p_slug);
  v_bloq := public._plantilla_motivo_bloqueo(p_cuerpo, p_empresa, p_slug);
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
revoke all on function public.plantilla_contrato_guarda_borrador(text, text, text, text) from public, anon, service_role;
grant execute on function public.plantilla_contrato_guarda_borrador(text, text, text, text) to authenticated;

create or replace function public.plantilla_contrato_descarta_borrador(p_version uuid) returns void language plpgsql security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v0 public.plantilla_contrato_versiones%rowtype; v_email text := coalesce((select auth.email()), (select auth.uid())::text);
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  select * into v0 from public.plantilla_contrato_versiones x where x.id = p_version;
  if not found or not (public.es_admin_de(v0.empresa) and public.empresa_en_alcance(v0.empresa)) then
    raise exception 'El texto de los contratos de una empresa lo escribe su administracion' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('plantilla/' || v0.empresa || '/' || v0.slug, 0));
  select * into v from public.plantilla_contrato_versiones x where x.id = p_version for update;
  if v.estado <> 'borrador' or v.origen <> 'empresa' then raise exception 'Solo se descarta un borrador de la empresa' using errcode = '55000'; end if;
  update public.plantilla_contrato_versiones set estado = 'retirada', retirada_por = v_email, retirada_en = now() where id = v.id;
end $$;

create or replace function public.plantilla_contrato_activa(p_version uuid, p_nombre text, p_confirma boolean) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v       public.plantilla_contrato_versiones%rowtype;
  v0      public.plantilla_contrato_versiones%rowtype;
  v_email text := coalesce((select auth.email()), (select auth.uid())::text);
  v_body  text; v_bloq text;
  v_texto constant text := 'Responde esta empresa. El estudio no ha revisado este texto. Consulte a un abogado o notario antes de usarlo: este aviso no sustituye a un abogado indonesio colegiado.';
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  select * into v0 from public.plantilla_contrato_versiones x where x.id = p_version;
  if not found or not (public.es_super_admin_de(v0.empresa) and public.empresa_en_alcance(v0.empresa)) then
    raise exception 'Activar un texto de contrato lo hace el super administrador de esa empresa' using errcode = '42501';
  end if;
  if p_confirma is not true or length(btrim(coalesce(p_nombre, ''))) < 3 then
    raise exception 'Falta la confirmacion explicita (tu nombre y aceptar el aviso)' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('plantilla/' || v0.empresa || '/' || v0.slug, 0));
  select * into v from public.plantilla_contrato_versiones x where x.id = p_version for update;
  if v.estado <> 'borrador' then raise exception 'Solo se activa un borrador' using errcode = '55000'; end if;
  if not v.activable then raise exception 'Version no activable: %', coalesce(v.bloqueo_motivo, 'sin motivo') using errcode = '55000'; end if;
  select c.cuerpo_html into v_body from public.plantilla_contrato_cuerpos c where c.version_id = v.id;
  if v_body is null then raise exception 'La version no tiene cuerpo' using errcode = '55000'; end if;
  perform public._plantilla_exige_valido(v_body, v.empresa, v.slug);
  v_bloq := public._plantilla_motivo_bloqueo(v_body, v.empresa, v.slug);
  if v_bloq is not null then raise exception 'Version no activable: %', v_bloq using errcode = '55000'; end if;
  update public.plantilla_contrato_versiones set estado = 'retirada', retirada_por = v_email, retirada_en = now()
   where empresa = v.empresa and slug = v.slug and estado = 'activa';
  update public.plantilla_contrato_versiones
     set estado = 'activa', activado_por = v_email, activado_en = now(), confirmacion_nombre = btrim(p_nombre), confirmacion_texto = v_texto
   where id = v.id;
  return jsonb_build_object('version_id', v.id, 'version', v.version, 'empresa', v.empresa, 'slug', v.slug, 'activado_por', v_email);
end $$;

drop function public.plantilla_contrato_fija(uuid, uuid);
create function public.plantilla_contrato_fija(p_contrato uuid, p_version uuid) returns void language plpgsql security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_tipo text; v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_agente() and public._puede_herr_o_super_empresa('contratos') and public.puede_ver_contrato(p_contrato)) then
    raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
  end if;
  select c.tipo into v_tipo from public.contratos c where c.id = p_contrato;
  select * into v from public.plantilla_contrato_versiones x where x.id = p_version;
  if not found then raise exception 'Version no valida' using errcode = '22023'; end if;
  if v_tipo is null or public._plantilla_slug_de_tipo(v_tipo) is distinct from v.slug then
    raise exception 'Esa version es de otra plantilla que la del contrato' using errcode = '22023';
  end if;
  if not (v.estado = 'activa'
          or (v.origen = 'semilla' and v.version = 1
              and not exists (select 1 from public.plantilla_contrato_versiones a where a.empresa = v.empresa and a.slug = v.slug and a.estado = 'activa'))) then
    raise exception 'Solo se fija la version activa de la empresa (o, mientras no haya ninguna, su semilla v1)' using errcode = '22023';
  end if;
  insert into public.contrato_plantilla_version (contrato_id, version_id, fijado_por) values (p_contrato, p_version, v_autor)
  on conflict (contrato_id) do update set version_id = excluded.version_id, fijado_en = now(), fijado_por = excluded.fijado_por;
end $$;
revoke all on function public.plantilla_contrato_fija(uuid, uuid) from public, anon, service_role;
grant execute on function public.plantilla_contrato_fija(uuid, uuid) to authenticated;

revoke create on schema public from lw_lector;
commit;
