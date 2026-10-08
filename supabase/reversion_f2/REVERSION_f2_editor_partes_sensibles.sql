-- Reversion de la migracion 20261010020000 (partes sensibles editables, 8-oct-2026).
-- Devuelve las funciones a su definicion de 20261010000000 (E7): el cambio de un bloque fijo vuelve a rechazarse. Elimina la tabla del registro, sus ayudantes y la RPC de lectura.
-- GUARDA: aborta si el registro tiene filas (se perderia quien cambio que): exportalas antes (select * from public.plantilla_bloque_cambios) y vacia a mano con el trigger desactivado.
--   OJO: si ya se guardaron borradores que cambian bloques fijos, tras revertir esos borradores no pasan el validador viejo al volver a guardarse; no se tocan filas.
-- destructivo-ok: reemplaza funciones por sus versiones anteriores y suelta una tabla de registro VACIA (aborta antes si no lo esta)
begin;

do $g$
declare n int;
begin
  select count(*) into n from public.plantilla_bloque_cambios;
  if n > 0 then
    raise exception 'REVERSION ABORTADA: el registro de partes sensibles tiene % fila(s). Exportalas antes.', n using errcode = '55000';
  end if;
end $g$;

drop function public.plantilla_contrato_cambios_sensibles(text, text, int);
drop function public.plantilla_contrato_guarda_borrador(text, text, text, text, text, boolean);
create function public.plantilla_contrato_guarda_borrador(p_empresa text, p_slug text, p_cuerpo text, p_motivo text, p_variante text default 'estandar')
 returns uuid language plpgsql security definer set search_path = '' as $$
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

create or replace function public._plantilla_exige_bloques(p_cuerpo text, p_esqueleto text, p_empresa text, p_slug text) returns void
 language plpgsql stable security definer set search_path = '' as $$
declare a text[]; b text[]; sg text; esq text;
begin
  if public.es_super_admin() then return; end if;
  if p_esqueleto is null then return; end if;
  esq := public._plantilla_sin_notas(p_esqueleto);
  select s.motivo into sg from public.plantilla_solo_global s where s.slug = p_slug;
  if sg is not null then
    if public._plantilla_ws(p_cuerpo) is distinct from public._plantilla_ws(esq) then
      raise exception '%', 'Este texto no lo cambia una empresa sola. ' || sg using errcode = '42501';
    end if;
    return;
  end if;
  a := public._plantilla_bloques_fijos(p_cuerpo, p_slug);
  b := public._plantilla_bloques_fijos(esq, p_slug);
  if a is distinct from b then
    raise exception 'Tu texto cambia un bloque que una empresa no edita sola (foro y ley aplicable, tenencia, escrow e impuestos, prorroga, defectos, datos, partes y firmas, clausulas negociadas) o anade en un parrafo libre palabras de esos temas. Esos bloques los cambia el administrador global con su abogado: bloques fijos %, recibidos %', cardinality(b), cardinality(a) using errcode = '42501';
  end if;
end $$;

drop function public.plantilla_contrato_revisa(text, text, text, text);
create function public.plantilla_contrato_revisa(p_empresa text, p_slug text, p_cuerpo text) returns jsonb
 language plpgsql stable security definer set search_path = '' as $$
declare r jsonb; v_err text[]; v_esq text; v_bloq text;
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
  perform pg_catalog.set_config('lw.cx_catalogo', '', true);
  v_err := array(select jsonb_array_elements_text(r -> 'errores'));
  if cardinality(v_err) = 0 then
    begin
      perform public._plantilla_exige_bloques(p_cuerpo, v_esq, p_empresa, p_slug);
    exception when insufficient_privilege then
      v_err := v_err || sqlerrm;
    end;
  end if;
  v_bloq := case when cardinality(v_err) = 0 then public._plantilla_motivo_bloqueo(p_cuerpo, p_empresa, p_slug) end;
  return jsonb_build_object('ok', cardinality(v_err) = 0, 'errores', to_jsonb(v_err[1:40]), 'activable', cardinality(v_err) = 0 and v_bloq is null, 'bloqueo', v_bloq,
                            'n_marcadores', (r ->> 'n_marcadores')::int, 'bytes', pg_catalog.octet_length(p_cuerpo));
end $$;

revoke all on function public.plantilla_contrato_revisa(text, text, text) from public, anon, service_role;
grant execute on function public.plantilla_contrato_revisa(text, text, text) to authenticated;

create or replace function public.plantilla_contrato_edicion(p_empresa text, p_slug text, p_variante text default 'estandar') returns jsonb
 language plpgsql stable security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_c text; v_limpio text; v_solo text; v_nunca text; v_global boolean := public.es_super_admin();
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if p_empresa is null or not (public.es_admin_de(p_empresa) and public.empresa_en_alcance(p_empresa)) then
    raise exception 'El texto de los contratos de una empresa lo escribe su administracion' using errcode = '42501';
  end if;
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
    'solo_global', case when v_global then null else v_solo end,
    'nunca_activable', v_nunca,
    'bloques_fijos', case when v_global or v_solo is not null then '[]'::jsonb else to_jsonb(public._plantilla_bloques_fijos(v_limpio, p_slug)) end,
    'puede_activar', public.es_super_admin_de(p_empresa),
    'bloqueo', public._plantilla_motivo_bloqueo(v_limpio, p_empresa, p_slug));
end $$;

drop trigger plantilla_bloque_cambios_solo_anade on public.plantilla_bloque_cambios;
drop table public.plantilla_bloque_cambios;
drop function public._trg_plantilla_bloque_cambios_solo_anade();
drop function public._plantilla_bloques_tocados(text, text, text);
drop function public._plantilla_base_edicion(text, text, text);
drop function public._plantilla_bloque_motivo(text, text);

commit;
