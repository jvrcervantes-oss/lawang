-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «editor de textos de contrato» (encargos/20261008_lawang_editor_textos_contrato.md) · E7 · REVISIONES MULTIPLES ACTIVAS (8-oct-2026).
-- DECISION DEL OWNER (8-oct): una empresa puede tener tantas revisiones de un contrato como quiera, todas activas y seleccionables al crear el contrato
--   hasta que las archive o borre (borrar solo si ningun contrato la usa). Se crean copiando una existente.
-- QUE HACE:
--   1. Columna `variante` (clave corta estable, 'estandar' por defecto = todo lo que ya existe) + `variante_nombre` (rotulo) en plantilla_contrato_versiones. Una REVISION = una variante
--      con su propio historial de versiones. Los indices unicos parciales «una activa» y «un borrador» pasan de (empresa, slug) a (empresa, slug, variante).
--   2. Estado nuevo `archivada` (activa que ya no se ofrece a contratos nuevos; los vinculados la siguen leyendo; se restaura) y BORRADO LOGICO (borrada_en/borrada_por): nada se
--      borra fisicamente, los triggers de no-borrado NO se tocan, ningun cuerpo se mueve. El trigger de UPDATE solo gana las transiciones activa->archivada, archivada->activa,
--      archivada->retirada y la marca de borrado; la identidad (incluida la variante) sigue inmutable.
--   3. Consumidores por slug adaptados: _plantilla_esqueleto (siempre la activa de 'estandar' o la semilla: el esqueleto es unico), plantilla_contrato_cuerpo (+ p_version opcional),
--      plantilla_contrato_cuerpo_de_contrato / _cuerpo_version / _version_de_contrato (devuelven la variante; una version borrada no se lee), plantilla_contrato_fija (p_version
--      opcional: con revisiones y sin elegir, error claro), plantilla_contrato_activa (solo retira la activa/archivada de SU variante), plantilla_contrato_versiones_lista /
--      _edicion / _guarda_borrador (parametro variante, por defecto 'estandar': el front actual no se rompe), _descarta_borrador (no toca una borrada).
--   4. RPC nuevas, nacen cerradas y se abren solo a `authenticated` con empresa_en_alcance + rol dentro: plantilla_contrato_revision_crea / _archiva / _restaura / _borra y
--      plantilla_contrato_revisiones_lista (contratos que la usan y parrafos distintos de su origen). Restaurar = volver a poner un texto en uso: lo hace el super admin de la empresa
--      (igual que activar); crear, archivar y borrar, el admin de la empresa.
-- Llamador de las RPC nuevas: la pantalla `intranet/v4/textos-contrato/` (E7 front, otro agente) y el selector de revision de contracts/app.html. Hasta que se conecten no las llama nadie.
-- destructivo-ok: sin datos que se pierdan. Reemplaza 2 indices unicos parciales por otros mas finos (los datos actuales son todos 'estandar', 0 activas), reescribe el CHECK de estado (suma 'archivada') y
--   reemplaza 4 funciones cuya firma cambia (drop + create en la misma transaccion; se conservan duenos lw_lector y grants). Ninguna fila de produccion cambia salvo el DEFAULT 'estandar' de la columna nueva.
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_editor_e7_variantes.sql

alter table public.plantilla_contrato_versiones
  add column variante        text not null default 'estandar',
  add column variante_nombre text,
  add column archivada_por   text,
  add column archivada_en    timestamptz,
  add column borrada_por     text,
  add column borrada_en      timestamptz;

alter table public.plantilla_contrato_versiones
  add constraint plantilla_variante_clave   check (variante ~ '^[a-z][a-z0-9_]{0,39}$'),
  add constraint plantilla_variante_nombre  check (variante_nombre is null or (length(btrim(variante_nombre)) between 3 and 80)),
  add constraint plantilla_archivada_firmada check (estado <> 'archivada' or (archivada_por is not null and archivada_en is not null)),
  add constraint plantilla_borrada_firmada   check ((borrada_en is null) = (borrada_por is null));

alter table public.plantilla_contrato_versiones drop constraint plantilla_contrato_versiones_estado_check;
alter table public.plantilla_contrato_versiones
  add constraint plantilla_contrato_versiones_estado_check check (estado = any (array['borrador', 'activa', 'retirada', 'archivada']));

-- indices: primero los nuevos, luego se sueltan los viejos (misma transaccion)
create unique index plantilla_una_activa_v on public.plantilla_contrato_versiones (empresa, slug, variante) where estado = 'activa' and borrada_en is null;
create unique index plantilla_un_borrador_v on public.plantilla_contrato_versiones (empresa, slug, variante) where estado = 'borrador' and origen = 'empresa' and borrada_en is null;
create unique index plantilla_una_archivada_v on public.plantilla_contrato_versiones (empresa, slug, variante) where estado = 'archivada' and borrada_en is null;
drop index public.plantilla_una_activa;
drop index public.plantilla_un_borrador;
alter index public.plantilla_una_activa_v rename to plantilla_una_activa;
alter index public.plantilla_un_borrador_v rename to plantilla_un_borrador;

-- ------------------------------------------------------------------------------------------------------------------ triggers
create or replace function public._trg_plantilla_version_ins() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.estado <> 'borrador' or new.activado_por is not null or new.activado_en is not null or new.retirada_por is not null or new.retirada_en is not null
     or new.confirmacion_nombre is not null or new.confirmacion_texto is not null
     or new.archivada_por is not null or new.archivada_en is not null or new.borrada_por is not null or new.borrada_en is not null then
    raise exception 'Una version nace siempre como borrador; activar es un acto aparte (plantilla_contrato_activa)' using errcode = '55000';
  end if;
  return new;
end $$;

create or replace function public._trg_plantilla_version_upd() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_body text;
begin
  if old.origen = 'semilla' then
    raise exception 'Una semilla del estudio no se modifica ni se activa: se parte de ella para escribir una version nueva' using errcode = '55000';
  end if;
  if (old.id, old.empresa, old.slug, old.version, old.origen, old.hereda_de, old.variante) is distinct from (new.id, new.empresa, new.slug, new.version, new.origen, new.hereda_de, new.variante) then
    raise exception 'Identidad de la version inmutable (empresa, plantilla, version, origen, revision)' using errcode = '55000';
  end if;
  -- borrado logico: una sola via, solo esa marca, nunca se deshace
  if new.borrada_en is distinct from old.borrada_en or new.borrada_por is distinct from old.borrada_por then
    if old.borrada_en is not null then raise exception 'Una version borrada no se recupera' using errcode = '55000'; end if;
    if (to_jsonb(new) - 'borrada_en' - 'borrada_por') is distinct from (to_jsonb(old) - 'borrada_en' - 'borrada_por') then
      raise exception 'El borrado logico no cambia nada mas' using errcode = '55000';
    end if;
    if old.estado = 'activa' then raise exception 'Una revision activa se archiva antes de borrarla' using errcode = '55000'; end if;
    return new;
  end if;
  if old.borrada_en is not null then raise exception 'Una version borrada no se modifica' using errcode = '55000'; end if;
  if old.estado = 'retirada' then
    raise exception 'Una version retirada no se modifica (queda para siempre)' using errcode = '55000';
  end if;
  if old.estado in ('activa', 'archivada') then
    if (to_jsonb(new) - 'estado' - 'retirada_por' - 'retirada_en' - 'archivada_por' - 'archivada_en') is distinct from (to_jsonb(old) - 'estado' - 'retirada_por' - 'retirada_en' - 'archivada_por' - 'archivada_en') then
      raise exception 'Una version activa o archivada es inmutable: solo cambia de estado' using errcode = '55000';
    end if;
    if old.estado = 'activa' and new.estado not in ('retirada', 'archivada') then
      raise exception 'Una version activa solo puede pasar a retirada o archivada' using errcode = '55000';
    end if;
    if old.estado = 'archivada' and new.estado not in ('activa', 'retirada') then
      raise exception 'Una version archivada solo puede restaurarse o retirarse' using errcode = '55000';
    end if;
    return new;
  end if;
  if new.estado = 'retirada' then
    if new.retirada_por is null or new.retirada_en is null then raise exception 'Falta quien retira' using errcode = '22023'; end if;
    return new;
  end if;
  if new.estado = 'archivada' then
    raise exception 'Solo se archiva una version activa' using errcode = '55000';
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

-- ------------------------------------------------------------------------------------------------------------------ ayudantes (sin grants)
create or replace function public._plantilla_esqueleto(p_empresa text, p_slug text) returns text language sql stable security definer set search_path = '' as $$
  select c.cuerpo_html
    from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
   where v.empresa = p_empresa and v.slug = p_slug and v.borrada_en is null
     and ((v.estado = 'activa' and v.variante = 'estandar') or v.origen = 'semilla')
   order by (v.estado = 'activa') desc, v.version asc
   limit 1
$$;

-- párrafos de un cuerpo, normalizados (sin etiquetas ni espacios repetidos): para contar cuántos difieren de su origen
create or replace function public._plantilla_parrafos(p_html text) returns text[] language sql immutable set search_path = '' as $$
  select coalesce(array_agg(t), '{}'::text[])
    from (select btrim(pg_catalog.regexp_replace(pg_catalog.regexp_replace(x, '<[^>]*>', ' ', 'g'), '\s+', ' ', 'g')) as t
            from pg_catalog.regexp_split_to_table(coalesce(p_html, ''), '</(p|li|td|th|h[1-6]|div)>', 'i') as x) q
   where t <> ''
$$;
revoke all on function public._plantilla_parrafos(text) from public, anon, authenticated, service_role;

-- ------------------------------------------------------------------------------------------------------------------ lecturas
-- dueno lw_lector (patron b6, como 20261008980200): la RLS filtra como el que llama; el permiso de crear en el esquema es solo mientras dura la migracion
grant create on schema public to lw_lector;
drop function public.plantilla_contrato_cuerpo(text, uuid, text);
create function public.plantilla_contrato_cuerpo(p_slug text, p_proyecto uuid default null, p_etag text default null, p_version uuid default null)
 returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_emp text; v_mis text[]; v public.plantilla_contrato_versiones%rowtype; v_c text;
begin
  if public.uid_sesion() is null or not public.es_agente() then raise exception 'Sin sesion de agente' using errcode = '42501'; end if;
  v_mis := public.mis_empresas();
  if p_proyecto is not null then v_emp := public.empresa_de_proyecto(p_proyecto);
  elsif cardinality(v_mis) = 1 then v_emp := v_mis[1]; end if;
  if v_emp is null then return null; end if;                                  -- sin empresa: nada que servir desde la base
  if not public.empresa_en_alcance(v_emp) then raise exception 'Esa empresa no es de tu alcance' using errcode = '42501'; end if;
  if p_version is not null then
    -- revision elegida: tiene que ser de ESA empresa y plantilla, y estar ofrecida (activa, o la semilla v1 mientras 'estandar' no tenga activa)
    select * into v from public.plantilla_contrato_versiones x
     where x.id = p_version and x.empresa = v_emp and x.slug = p_slug and x.borrada_en is null
       and (x.estado = 'activa'
            or (x.origen = 'semilla' and x.version = 1
                and not exists (select 1 from public.plantilla_contrato_versiones a where a.empresa = x.empresa and a.slug = x.slug and a.variante = 'estandar' and a.estado = 'activa' and a.borrada_en is null)));
    if not found then raise exception 'Esa revision no esta disponible' using errcode = '22023'; end if;
  else
    select * into v from public.plantilla_contrato_versiones x
     where x.empresa = v_emp and x.slug = p_slug and x.borrada_en is null
       and ((x.estado = 'activa' and x.variante = 'estandar') or (x.origen = 'semilla' and x.version = 1))
     order by (x.estado = 'activa') desc limit 1;
    if not found then return null; end if;
  end if;
  if p_etag is not null and p_etag = v.hash then
    return jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'hash', v.hash, 'variante', v.variante, 'sin_cambios', true);
  end if;
  select c.cuerpo_html into v_c from public.plantilla_contrato_cuerpos c where c.version_id = v.id;
  return jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'hash', v.hash, 'estado', v.estado, 'origen', v.origen,
                            'variante', v.variante, 'variante_nombre', v.variante_nombre, 'cuerpo_html', v_c);
end $$;
alter function public.plantilla_contrato_cuerpo(text, uuid, text, uuid) owner to lw_lector;
revoke all on function public.plantilla_contrato_cuerpo(text, uuid, text, uuid) from public, anon, service_role;
grant execute on function public.plantilla_contrato_cuerpo(text, uuid, text, uuid) to authenticated;

create or replace function public.plantilla_contrato_cuerpo_de_contrato(p_contrato uuid, p_etag text default null)
 returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_c text;
begin
  if public.uid_sesion() is null or not public.es_agente() then raise exception 'Sin sesion de agente' using errcode = '42501'; end if;
  if not public.puede_ver_contrato(p_contrato) then raise exception 'No tienes acceso a ese contrato' using errcode = '42501'; end if;
  select x.* into v from public.contrato_plantilla_version l join public.plantilla_contrato_versiones x on x.id = l.version_id where l.contrato_id = p_contrato;
  if not found then return null; end if;                                      -- sin vinculo = el contrato sigue con el fichero
  if p_etag is not null and p_etag = v.hash then
    return jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'hash', v.hash, 'variante', v.variante, 'sin_cambios', true);
  end if;
  select c.cuerpo_html into v_c from public.plantilla_contrato_cuerpos c where c.version_id = v.id;
  return jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'hash', v.hash, 'estado', v.estado, 'origen', v.origen,
                            'variante', v.variante, 'variante_nombre', v.variante_nombre, 'cuerpo_html', v_c);
end $$;

create or replace function public.plantilla_contrato_cuerpo_version(p_version uuid, p_etag text default null)
 returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_c text;
begin
  if public.uid_sesion() is null or not public.es_agente() then raise exception 'Sin sesion de agente' using errcode = '42501'; end if;
  select * into v from public.plantilla_contrato_versiones x where x.id = p_version and x.borrada_en is null;
  if not found then raise exception 'No tienes acceso a ese texto' using errcode = '42501'; end if;
  if not public.empresa_en_alcance(v.empresa) then raise exception 'No tienes acceso a ese texto' using errcode = '42501'; end if;
  if not public.es_admin_de(v.empresa) and v.estado <> 'activa'
     and not exists (select 1 from public.contrato_plantilla_version l where l.version_id = v.id) then
    raise exception 'No tienes acceso a ese texto' using errcode = '42501';
  end if;
  if p_etag is not null and p_etag = v.hash then
    return jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'hash', v.hash, 'estado', v.estado, 'variante', v.variante, 'sin_cambios', true);
  end if;
  select c.cuerpo_html into v_c from public.plantilla_contrato_cuerpos c where c.version_id = v.id;
  return jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'hash', v.hash, 'estado', v.estado, 'origen', v.origen,
                            'variante', v.variante, 'variante_nombre', v.variante_nombre, 'cuerpo_html', v_c);
end $$;

create or replace function public.plantilla_contrato_version_de_contrato(p_contrato uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  if public.uid_sesion() is null or not public.es_agente() then raise exception 'Sin sesion de agente' using errcode = '42501'; end if;
  select jsonb_build_object('version_id', v.id, 'empresa', v.empresa, 'slug', v.slug, 'version', v.version, 'estado', v.estado, 'origen', v.origen, 'hash', v.hash,
                            'variante', v.variante, 'variante_nombre', v.variante_nombre)
    into r
    from public.contrato_plantilla_version l join public.plantilla_contrato_versiones v on v.id = l.version_id
   where l.contrato_id = p_contrato;
  return r;
end $$;

drop function public.plantilla_contrato_versiones_lista(text, text);
create function public.plantilla_contrato_versiones_lista(p_empresa text default null, p_slug text default null)
 returns table(id uuid, empresa text, slug text, version integer, estado text, origen text, idioma_set text[], hash text, bytes integer, activable boolean, bloqueo_motivo text,
               autor text, fecha timestamptz, motivo text, activado_por text, activado_en timestamptz, confirmacion_nombre text, retirada_por text, retirada_en timestamptz, hereda_de uuid,
               variante text, variante_nombre text, archivada_por text, archivada_en timestamptz)
 language plpgsql stable security definer set search_path = '' as $$
begin
  if public.uid_sesion() is null or not public.es_agente() then raise exception 'Sin sesion de agente' using errcode = '42501'; end if;
  if p_empresa is not null and not public.empresa_en_alcance(p_empresa) then raise exception 'Esa empresa no es de tu alcance' using errcode = '42501'; end if;
  return query
    select v.id, v.empresa, v.slug, v.version, v.estado, v.origen, v.idioma_set, v.hash, v.bytes, v.activable, v.bloqueo_motivo,
           v.autor, v.fecha, v.motivo, v.activado_por, v.activado_en, v.confirmacion_nombre, v.retirada_por, v.retirada_en, v.hereda_de,
           v.variante, v.variante_nombre, v.archivada_por, v.archivada_en
      from public.plantilla_contrato_versiones v
     where (p_empresa is null or v.empresa = p_empresa) and (p_slug is null or v.slug = p_slug)
       and v.borrada_en is null
       and public.empresa_en_alcance(v.empresa)
       and (v.estado = 'activa' or public.es_admin_de(v.empresa))
     order by v.empresa, v.slug, v.variante, v.version desc;
end $$;
alter function public.plantilla_contrato_versiones_lista(text, text) owner to lw_lector;
revoke all on function public.plantilla_contrato_versiones_lista(text, text) from public, anon, service_role;
grant execute on function public.plantilla_contrato_versiones_lista(text, text) to authenticated;

drop function public.plantilla_contrato_edicion(text, text);
create function public.plantilla_contrato_edicion(p_empresa text, p_slug text, p_variante text default 'estandar') returns jsonb
 language plpgsql stable security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_c text; v_limpio text; v_solo text; v_nunca text; v_global boolean := public.es_super_admin();
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
  return jsonb_build_object(
    'empresa', v.empresa, 'slug', v.slug, 'version_id', v.id, 'version', v.version, 'estado', v.estado, 'origen', v.origen, 'hash', v.hash,
    'variante', v.variante, 'variante_nombre', v.variante_nombre,
    'cuerpo_html', v_limpio, 'notas_quitadas', pg_catalog.octet_length(v_c) - pg_catalog.octet_length(v_limpio),
    'solo_global', case when v_global then null else v_solo end,                                   -- el super global si puede (con su abogado)
    'nunca_activable', v_nunca,
    'bloques_fijos', case when v_global or v_solo is not null then '[]'::jsonb else to_jsonb(public._plantilla_bloques_fijos(v_limpio, p_slug)) end,
    'puede_activar', public.es_super_admin_de(p_empresa),
    'bloqueo', public._plantilla_motivo_bloqueo(v_limpio, p_empresa, p_slug));
end $$;
revoke all on function public.plantilla_contrato_edicion(text, text, text) from public, anon, service_role;
grant execute on function public.plantilla_contrato_edicion(text, text, text) to authenticated;

-- ------------------------------------------------------------------------------------------------------------------ escritura
drop function public.plantilla_contrato_guarda_borrador(text, text, text, text);
create function public.plantilla_contrato_guarda_borrador(p_empresa text, p_slug text, p_cuerpo text, p_motivo text, p_variante text default 'estandar') returns uuid
 language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := (select auth.uid());
  v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
  v_var   text := coalesce(p_variante, 'estandar');
  v_nom   text;
  v_hash  text; v_bytes int; v_idiomas text[]; v_id uuid; v_n int; v_base uuid; v_esq text; v_bloq text;
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
  return v_id;
end $$;
revoke all on function public.plantilla_contrato_guarda_borrador(text, text, text, text, text) from public, anon, service_role;
grant execute on function public.plantilla_contrato_guarda_borrador(text, text, text, text, text) to authenticated;

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
  if v.estado <> 'borrador' or v.origen <> 'empresa' or v.borrada_en is not null then raise exception 'Solo se descarta un borrador de la empresa' using errcode = '55000'; end if;
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
  select * into v0 from public.plantilla_contrato_versiones x where x.id = p_version;           -- sin bloquear: solo para saber que candado asesor tomar
  if not found or not (public.es_super_admin_de(v0.empresa) and public.empresa_en_alcance(v0.empresa)) then
    raise exception 'Activar un texto de contrato lo hace el super administrador de esa empresa' using errcode = '42501';
  end if;
  if p_confirma is not true or length(btrim(coalesce(p_nombre, ''))) < 3 then
    raise exception 'Falta la confirmacion explicita (tu nombre y aceptar el aviso)' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('plantilla/' || v0.empresa || '/' || v0.slug, 0));   -- 1.o el candado asesor (como guarda_borrador)
  select * into v from public.plantilla_contrato_versiones x where x.id = p_version for update;                              -- 2.o la fila, y se vuelve a mirar
  if v.estado <> 'borrador' or v.borrada_en is not null then raise exception 'Solo se activa un borrador' using errcode = '55000'; end if;
  if not v.activable then raise exception 'Version no activable: %', coalesce(v.bloqueo_motivo, 'sin motivo') using errcode = '55000'; end if;
  select c.cuerpo_html into v_body from public.plantilla_contrato_cuerpos c where c.version_id = v.id;
  if v_body is null then raise exception 'La version no tiene cuerpo' using errcode = '55000'; end if;
  perform public._plantilla_exige_valido(v_body, v.empresa, v.slug);
  v_bloq := public._plantilla_motivo_bloqueo(v_body, v.empresa, v.slug);                       -- F1 otra vez, en servidor, sobre el cuerpo guardado
  if v_bloq is not null then raise exception 'Version no activable: %', v_bloq using errcode = '55000'; end if;
  -- solo se retira lo de SU revision: las demas revisiones de la plantilla siguen activas
  update public.plantilla_contrato_versiones set estado = 'retirada', retirada_por = v_email, retirada_en = now()
   where empresa = v.empresa and slug = v.slug and variante = v.variante and estado in ('activa', 'archivada') and borrada_en is null;
  update public.plantilla_contrato_versiones
     set estado = 'activa', activado_por = v_email, activado_en = now(), confirmacion_nombre = btrim(p_nombre), confirmacion_texto = v_texto
   where id = v.id;
  return jsonb_build_object('version_id', v.id, 'version', v.version, 'empresa', v.empresa, 'slug', v.slug, 'variante', v.variante, 'activado_por', v_email);
end $$;

create or replace function public.plantilla_contrato_fija(p_contrato uuid, p_version uuid default null) returns void language plpgsql security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_tipo text; v_proy uuid; v_emp text; v_slug text; v_vid uuid; v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_agente() and public._puede_herr_o_super_empresa('contratos') and public.puede_ver_contrato(p_contrato)) then
    raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
  end if;
  select c.tipo, c.proyecto_id into v_tipo, v_proy from public.contratos c where c.id = p_contrato;
  v_slug := case when v_tipo is null then null else public._plantilla_slug_de_tipo(v_tipo) end;
  v_vid := p_version;
  if v_vid is null then
    -- sin elegir: vale solo si no hay revisiones activas aparte de la estandar (el comportamiento de siempre); si las hay, hay que elegir
    v_emp := case when v_proy is null then null else public.empresa_de_proyecto(v_proy) end;
    if v_emp is null or v_slug is null then raise exception 'El contrato no tiene empresa o plantilla' using errcode = '22023'; end if;
    if exists (select 1 from public.plantilla_contrato_versiones a where a.empresa = v_emp and a.slug = v_slug and a.estado = 'activa' and a.variante <> 'estandar' and a.borrada_en is null) then
      raise exception 'Esta plantilla tiene varias revisiones activas: elige cual usa el contrato' using errcode = '22023';
    end if;
    select x.id into v_vid from public.plantilla_contrato_versiones x
     where x.empresa = v_emp and x.slug = v_slug and x.borrada_en is null and ((x.estado = 'activa' and x.variante = 'estandar') or (x.origen = 'semilla' and x.version = 1))
     order by (x.estado = 'activa') desc limit 1;
  end if;
  -- FOR SHARE: se serializa con archivar/borrar la misma revision (que toman FOR UPDATE) y se vuelve a leer su estado
  select * into v from public.plantilla_contrato_versiones x where x.id = v_vid for share;
  if not found then raise exception 'Version no valida' using errcode = '22023'; end if;
  if v.borrada_en is not null then raise exception 'Esa revision se ha borrado' using errcode = '22023'; end if;
  if v_tipo is null or v_slug is distinct from v.slug then
    raise exception 'Esa version es de otra plantilla que la del contrato' using errcode = '22023';
  end if;
  if not (v.estado = 'activa'
          or (v.origen = 'semilla' and v.version = 1
              and not exists (select 1 from public.plantilla_contrato_versiones a where a.empresa = v.empresa and a.slug = v.slug and a.variante = 'estandar' and a.estado = 'activa' and a.borrada_en is null))) then
    raise exception 'Solo se fija una revision activa de la empresa (o, mientras la estandar no tenga ninguna, su semilla v1)' using errcode = '22023';
  end if;
  insert into public.contrato_plantilla_version (contrato_id, version_id, fijado_por) values (p_contrato, v.id, v_autor)
  on conflict (contrato_id) do update set version_id = excluded.version_id, fijado_en = now(), fijado_por = excluded.fijado_por;
end $$;

-- ------------------------------------------------------------------------------------------------------------------ revisiones (RPC nuevas)
create function public.plantilla_contrato_revision_crea(p_empresa text, p_slug text, p_origen uuid, p_nombre text, p_motivo text, p_variante text default null) returns uuid
 language plpgsql security definer set search_path = '' as $$
declare
  v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
  o public.plantilla_contrato_versiones%rowtype; v_var text; v_n int; v_i int := 1; v_body text; v_esq text; v_bloq text; v_hash text; v_bytes int; v_idiomas text[]; v_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El texto de los contratos de una empresa lo escribe su administracion' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_nombre, ''))) not between 3 and 80 then raise exception 'Pon un nombre a la revision (de 3 a 80 letras)' using errcode = '22023'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'Falta el motivo de la revision' using errcode = '22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('plantilla/' || p_empresa || '/' || p_slug, 0));
  select * into o from public.plantilla_contrato_versiones x where x.id = p_origen and x.empresa = p_empresa and x.slug = p_slug and x.borrada_en is null;
  if not found then raise exception 'Ese texto de origen no es de esta empresa y plantilla' using errcode = '22023'; end if;
  select count(distinct x.variante) into v_n from public.plantilla_contrato_versiones x where x.empresa = p_empresa and x.slug = p_slug and x.borrada_en is null;
  if v_n >= 20 then raise exception 'Tope de 20 revisiones por contrato: archiva o borra alguna' using errcode = '22023'; end if;
  if p_variante is null then
    loop
      v_var := 'rev_' || v_i;
      exit when not exists (select 1 from public.plantilla_contrato_versiones x where x.empresa = p_empresa and x.slug = p_slug and x.variante = v_var);
      v_i := v_i + 1;
    end loop;
  else
    v_var := p_variante;
    if v_var !~ '^[a-z][a-z0-9_]{0,39}$' or v_var = 'estandar' then raise exception 'Clave de revision no valida' using errcode = '22023'; end if;
    if exists (select 1 from public.plantilla_contrato_versiones x where x.empresa = p_empresa and x.slug = p_slug and x.variante = v_var) then
      raise exception 'Ya hay una revision con esa clave' using errcode = '22023';
    end if;
  end if;
  select c.cuerpo_html into v_body from public.plantilla_contrato_cuerpos c where c.version_id = o.id;
  v_body := public._plantilla_sin_notas(v_body);
  -- la copia pasa por EXACTAMENTE la misma validacion que cualquier borrador
  perform public._plantilla_exige_valido(v_body, p_empresa, p_slug);
  v_esq := public._plantilla_esqueleto(p_empresa, p_slug);
  perform public._plantilla_exige_bloques(v_body, v_esq, p_empresa, p_slug);
  v_bloq := public._plantilla_motivo_bloqueo(v_body, p_empresa, p_slug);
  v_hash := public._plantilla_hash(v_body);
  v_bytes := pg_catalog.octet_length(v_body);
  v_idiomas := array_remove(array[
    case when v_body like '%data-lang="es"%' then 'es' end,
    case when v_body like '%data-lang="en"%' then 'en' end,
    case when v_body like '%data-lang="id"%' then 'id' end], null);
  select coalesce(max(x.version), 0) + 1 into v_n from public.plantilla_contrato_versiones x where x.empresa = p_empresa and x.slug = p_slug;
  insert into public.plantilla_contrato_versiones (empresa, slug, version, estado, origen, idioma_set, hash, bytes, activable, bloqueo_motivo, hereda_de, autor, motivo, variante, variante_nombre)
  values (p_empresa, p_slug, v_n, 'borrador', 'empresa', v_idiomas, v_hash, v_bytes, v_bloq is null, v_bloq, o.id, v_autor, btrim(p_motivo), v_var, btrim(p_nombre))
  returning id into v_id;
  insert into public.plantilla_contrato_cuerpos (version_id, cuerpo_html) values (v_id, v_body);
  return v_id;
end $$;

create function public.plantilla_contrato_revision_archiva(p_empresa text, p_slug text, p_variante text) returns void language plpgsql security definer set search_path = '' as $$
declare v_email text := coalesce((select auth.email()), (select auth.uid())::text); v public.plantilla_contrato_versiones%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El texto de los contratos de una empresa lo escribe su administracion' using errcode = '42501';
  end if;
  if p_variante is null or p_variante = 'estandar' then raise exception 'La revision estandar no se archiva: se sustituye activando otra version' using errcode = '22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('plantilla/' || p_empresa || '/' || p_slug, 0));
  select * into v from public.plantilla_contrato_versiones x
   where x.empresa = p_empresa and x.slug = p_slug and x.variante = p_variante and x.estado = 'activa' and x.borrada_en is null for update;
  if not found then raise exception 'Esa revision no tiene una version activa que archivar' using errcode = '22023'; end if;
  update public.plantilla_contrato_versiones set estado = 'archivada', archivada_por = v_email, archivada_en = now() where id = v.id;     -- el cuerpo no se toca ni se mueve
end $$;

create function public.plantilla_contrato_revision_restaura(p_empresa text, p_slug text, p_variante text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_body text; v_bloq text;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_super_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'Volver a poner un texto en uso lo hace el super administrador de esa empresa' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('plantilla/' || p_empresa || '/' || p_slug, 0));
  select * into v from public.plantilla_contrato_versiones x
   where x.empresa = p_empresa and x.slug = p_slug and x.variante = p_variante and x.estado = 'archivada' and x.borrada_en is null for update;
  if not found then raise exception 'Esa revision no esta archivada' using errcode = '22023'; end if;
  if exists (select 1 from public.plantilla_contrato_versiones a where a.empresa = p_empresa and a.slug = p_slug and a.variante = p_variante and a.estado = 'activa' and a.borrada_en is null) then
    raise exception 'Esa revision ya tiene otra version activa' using errcode = '22023';
  end if;
  select c.cuerpo_html into v_body from public.plantilla_contrato_cuerpos c where c.version_id = v.id;
  perform public._plantilla_exige_valido(v_body, v.empresa, v.slug);                         -- las reglas pueden haber cambiado desde que se archivo
  v_bloq := public._plantilla_motivo_bloqueo(v_body, v.empresa, v.slug);
  if v_bloq is not null or not v.activable then raise exception 'Version no activable: %', coalesce(v_bloq, v.bloqueo_motivo, 'sin motivo') using errcode = '55000'; end if;
  update public.plantilla_contrato_versiones set estado = 'activa' where id = v.id;
  return jsonb_build_object('version_id', v.id, 'version', v.version, 'empresa', v.empresa, 'slug', v.slug, 'variante', v.variante);
end $$;

create function public.plantilla_contrato_revision_borra(p_empresa text, p_slug text, p_variante text) returns void language plpgsql security definer set search_path = '' as $$
declare v_email text := coalesce((select auth.email()), (select auth.uid())::text); n int;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El texto de los contratos de una empresa lo escribe su administracion' using errcode = '42501';
  end if;
  if p_variante is null or p_variante = 'estandar' then raise exception 'La revision estandar no se borra' using errcode = '22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('plantilla/' || p_empresa || '/' || p_slug, 0));
  -- 1.o se bloquean las filas de la revision (una fijacion de contrato en vuelo tiene FOR SHARE sobre ellas) y 2.o, en OTRA sentencia, se cuenta con la foto nueva
  perform 1 from public.plantilla_contrato_versiones x
   where x.empresa = p_empresa and x.slug = p_slug and x.variante = p_variante and x.borrada_en is null for update;
  if not found then raise exception 'Esa revision no existe' using errcode = '22023'; end if;
  if exists (select 1 from public.plantilla_contrato_versiones x where x.empresa = p_empresa and x.slug = p_slug and x.variante = p_variante and x.estado = 'activa' and x.borrada_en is null) then
    raise exception 'Esta revision esta activa: archivala antes de borrarla' using errcode = '55000';
  end if;
  select count(*) into n from public.contrato_plantilla_version l join public.plantilla_contrato_versiones x on x.id = l.version_id
   where x.empresa = p_empresa and x.slug = p_slug and x.variante = p_variante;
  if n > 0 then
    raise exception 'No se puede borrar: % contrato(s) usan esta revision. Archivala para que no se ofrezca en contratos nuevos; los que ya la usan la siguen leyendo.', n using errcode = '55000';
  end if;
  update public.plantilla_contrato_versiones set borrada_por = v_email, borrada_en = now()
   where empresa = p_empresa and slug = p_slug and variante = p_variante and borrada_en is null;
end $$;

create function public.plantilla_contrato_revisiones_lista(p_empresa text, p_slug text default null)
 returns table(slug text, variante text, nombre text, estado text, version_activa uuid, version_borrador uuid, version_ultima integer, contratos integer, parrafos_distintos integer,
               origen_version uuid, creada_por text, creada_en timestamptz, archivada_en timestamptz)
 language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El texto de los contratos de una empresa lo escribe su administracion' using errcode = '42501';
  end if;
  return query
  with vv as (
    select * from public.plantilla_contrato_versiones v where v.empresa = p_empresa and (p_slug is null or v.slug = p_slug) and v.borrada_en is null
  ), r as (
    select v.slug as r_slug, v.variante as r_var,
           (array_agg(v.variante_nombre order by v.version) filter (where v.variante_nombre is not null))[1] as r_nombre,
           case when bool_or(v.estado = 'activa') then 'activa'
                when bool_or(v.estado = 'archivada') then 'archivada'
                when bool_or(v.estado = 'borrador' and v.origen = 'empresa') then 'borrador'
                when bool_or(v.origen = 'semilla') then 'semilla' else 'retirada' end as r_estado,
           (array_agg(v.id order by v.version desc) filter (where v.estado = 'activa'))[1] as r_act,
           (array_agg(v.id order by v.version desc) filter (where v.estado = 'borrador' and v.origen = 'empresa'))[1] as r_bor,
           max(v.version) as r_ult,
           (array_agg(v.id order by (v.estado = 'activa') desc, (v.estado = 'borrador') desc, v.version desc))[1] as r_cur,
           (array_agg(v.hereda_de order by v.version))[1] as r_org,
           (array_agg(v.autor order by v.version))[1] as r_autor,
           min(v.fecha) as r_fecha,
           max(v.archivada_en) as r_arch
      from vv v group by v.slug, v.variante
  )
  select r.r_slug, r.r_var, coalesce(r.r_nombre, 'Estándar'), r.r_estado, r.r_act, r.r_bor, r.r_ult,
         (select count(*)::int from public.contrato_plantilla_version l join vv x on x.id = l.version_id where x.slug = r.r_slug and x.variante = r.r_var),
         case when r.r_var = 'estandar' or r.r_org is null then null
              else (select count(*)::int from (select distinct q from unnest(public._plantilla_parrafos((select c.cuerpo_html from public.plantilla_contrato_cuerpos c where c.version_id = r.r_cur))) q
                                               except
                                               select p from unnest(public._plantilla_parrafos((select c.cuerpo_html from public.plantilla_contrato_cuerpos c where c.version_id = r.r_org))) p) z) end,
         r.r_org, r.r_autor, r.r_fecha, r.r_arch
    from r
   order by r.r_slug, (r.r_var = 'estandar') desc, r.r_fecha, r.r_var;
end $$;

-- las RPC nuevas nacen cerradas y se abren solo a authenticated (la comprobacion de empresa y rol esta dentro)
revoke all on function public.plantilla_contrato_revision_crea(text, text, uuid, text, text, text),
                       public.plantilla_contrato_revision_archiva(text, text, text),
                       public.plantilla_contrato_revision_restaura(text, text, text),
                       public.plantilla_contrato_revision_borra(text, text, text),
                       public.plantilla_contrato_revisiones_lista(text, text) from public, anon, service_role;
grant execute on function public.plantilla_contrato_revision_crea(text, text, uuid, text, text, text),
                          public.plantilla_contrato_revision_archiva(text, text, text),
                          public.plantilla_contrato_revision_restaura(text, text, text),
                          public.plantilla_contrato_revision_borra(text, text, text),
                          public.plantilla_contrato_revisiones_lista(text, text) to authenticated;

revoke create on schema public from lw_lector;
