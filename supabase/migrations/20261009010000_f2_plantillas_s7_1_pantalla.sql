-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «plantillas de contrato por empresa» · S7 (pantalla «Textos de contrato», /intranet/v4/textos-contrato/) · migracion 1/1 (8-oct-2026).
--   Da llamador y GRANT a las RPC de S2 que usa la pantalla, y SOLO a esas (reducir la exposicion). Llamador con nombre: intranet/v4/assets/textos-contrato.js.
--     plantilla_contrato_versiones_lista(empresa, slug)   lista por plantilla: version activa, borrador e historial (sin cuerpo)
--     plantilla_contrato_cuerpo_version(version, etag)    el texto de una version por id (historial y diff con la anterior)
--     plantilla_contrato_guarda_borrador(empresa, slug, cuerpo, motivo)
--     plantilla_contrato_activa(version, nombre, confirma)   solo super_admin_empresa de esa empresa (o super global); la base lo impone
--     plantilla_contrato_descarta_borrador(version)       «descartar» = pasar a retirada (nunca se borra)
--     plantilla_contrato_edicion(empresa, slug)  NUEVA  el texto a editar (borrador propio > activa > semilla v1) SIN las notas de autor, los bloques que esa persona no puede cambiar
--                                                       y los permisos que la pantalla debe reflejar. Lectura; nada se guarda.
--     plantilla_contrato_revisa(empresa, slug, cuerpo)  NUEVA  ensayo sin guardar: lo que diria guarda_borrador (validador S3, bloques fijos F2) y si seria activable (F1).
--                                                       Es la ventana por la que la pantalla simula: el navegador NO valida, pregunta aqui.
--   Sigue SIN EXECUTE para authenticated: plantilla_contrato_version_de_contrato (sin llamador) y plantilla_cuerpo_valida* (aceptan un esqueleto que mandaria el navegador: S3 lo prohibe).
--   HALLAZGO MEDIDO ANTES DE ESCRIBIR LA PANTALLA (rollback, admin_empresa de Lawang): guardar la semilla v1 tal cual -> 22023 (la semilla lleva 116 notas de autor y el validador de
--   cuerpos que no son semilla las rechaza); guardarla SIN las notas -> 42501 «cambia un bloque que una empresa no edita sola» en 9 de 17 plantillas editables (carta_reserva,
--   carta_reserva_ampliada, _hak_sewa, _pma, commercial_collaboration, ppjb_construccion, ppjb_parcela, ppjb_reserva...), porque la comparacion de bloques fijos (F2) comparaba el cuerpo
--   nuevo (sin notas) contra el esqueleto (la semilla, CON notas dentro de la seccion «Las Partes»): ninguna empresa habria podido guardar ni un cambio. Se corrige aqui, en el servidor:
--   _plantilla_sin_notas() quita del esqueleto SOLO los comentarios que no son del motor (los mismos que el validador rechaza fuera de la carga v1) y _plantilla_exige_bloques compara contra eso.
--   No relaja nada: el cuerpo nuevo no puede traer notas (S3) y cualquier cambio de un bloque fijo sigue siendo distinto.
-- destructivo-ok: crea 3 funciones, redefine 1 (_plantilla_exige_bloques: solo ignora notas de autor del esqueleto) y cambia GRANT/REVOKE de EXECUTE; no toca filas
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_plantillas_s7.sql

-- ---------------------------------------------------------------- notas de autor fuera (solo las que el validador no admite)
-- Sin cuantificadores dentro del lookahead (en una ARE de Postgres decidirian la voracidad del patron): son prefijos literales de la gramatica del motor de S3/S2.5.
-- Un comentario que EMPIEZA como uno del motor pero esta mal formado se queda: el validador lo rechaza con su nombre, que es lo correcto (falla cerrado).
create function public._plantilla_sin_notas(p_cuerpo text) returns text
language sql immutable security definer set search_path = '' as $$
  select pg_catalog.regexp_replace(p_cuerpo,
    '<!--(?!if:|/if:|opt:|/opt:|seccion-hitos-->|/seccion-hitos-->|seccion-extras-construccion-->|/seccion-extras-construccion-->|extra-clauses-->|firmas-adquirientes-->|compradores-extra-->|datos-bancarios-->|datos-bancarios-sin-titulo-->|hitos-->|extras-construccion-->|cuenta:|bloque-fijo:|/bloque-fijo:).*?-->',
    '', 'g')
$$;

-- ---------------------------------------------------------------- F2 con el esqueleto limpio de notas
create or replace function public._plantilla_exige_bloques(p_cuerpo text, p_esqueleto text, p_empresa text, p_slug text) returns void
language plpgsql stable security definer set search_path = '' as $f$
declare a text[]; b text[]; sg text; esq text;
begin
  if public.es_super_admin() then return; end if;               -- el super GLOBAL (con su abogado) si puede
  if p_esqueleto is null then return; end if;                    -- sin esqueleto el validador de S3 ya rechaza
  esq := public._plantilla_sin_notas(p_esqueleto);               -- S7: la semilla v1 trae notas de autor; el cuerpo nuevo no puede (S3)
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
end $f$;

-- ---------------------------------------------------------------- el texto que la pantalla edita
create function public.plantilla_contrato_edicion(p_empresa text, p_slug text) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
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
    'solo_global', case when v_global then null else v_solo end,                                   -- el super global si puede (con su abogado)
    'nunca_activable', v_nunca,
    'bloques_fijos', case when v_global or v_solo is not null then '[]'::jsonb else to_jsonb(public._plantilla_bloques_fijos(v_limpio, p_slug)) end,
    'puede_activar', public.es_super_admin_de(p_empresa),
    'bloqueo', public._plantilla_motivo_bloqueo(v_limpio, p_empresa, p_slug));
end $f$;

-- ---------------------------------------------------------------- ensayo sin guardar
create function public.plantilla_contrato_revisa(p_empresa text, p_slug text, p_cuerpo text) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
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
  r := public._plantilla_valida(p_cuerpo, v_esq, false);                                             -- S3: la misma que usa guarda_borrador
  v_err := array(select jsonb_array_elements_text(r -> 'errores'));
  if cardinality(v_err) = 0 then
    begin
      perform public._plantilla_exige_bloques(p_cuerpo, v_esq, p_empresa, p_slug);                   -- F2: la misma
    exception when insufficient_privilege then
      v_err := v_err || sqlerrm;
    end;
  end if;
  v_bloq := case when cardinality(v_err) = 0 then public._plantilla_motivo_bloqueo(p_cuerpo, p_empresa, p_slug) end;   -- F1
  return jsonb_build_object('ok', cardinality(v_err) = 0, 'errores', to_jsonb(v_err[1:40]), 'activable', cardinality(v_err) = 0 and v_bloq is null, 'bloqueo', v_bloq,
                            'n_marcadores', (r ->> 'n_marcadores')::int, 'bytes', pg_catalog.octet_length(p_cuerpo));
end $f$;

-- ---------------------------------------------------------------- EXECUTE: solo lo que tiene llamador (esta pantalla)
revoke all on function public._plantilla_sin_notas(text) from public, anon, authenticated, service_role;
revoke all on function public._plantilla_exige_bloques(text, text, text, text) from public, anon, authenticated, service_role;
revoke all on function public.plantilla_contrato_edicion(text, text), public.plantilla_contrato_revisa(text, text, text) from public, anon, service_role;
grant execute on function public.plantilla_contrato_edicion(text, text), public.plantilla_contrato_revisa(text, text, text) to authenticated;
grant execute on function public.plantilla_contrato_versiones_lista(text, text), public.plantilla_contrato_cuerpo_version(uuid, text),
  public.plantilla_contrato_guarda_borrador(text, text, text, text), public.plantilla_contrato_activa(uuid, text, boolean), public.plantilla_contrato_descarta_borrador(uuid) to authenticated;
