-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «plantillas de contrato por empresa» · S5 (generador) · migracion 1/2 (7-oct-2026): LA LECTURA QUE NECESITA contracts/app.html, con su llamador, y el cierre del interbloqueo.
--   Reducir la exposicion: de las 8 RPC de S2 solo se abren a `authenticated` las TRES que el generador llama; el resto sigue revocado hasta que S7 (pantalla) les de llamador.
--     plantilla_contrato_cuerpo(slug, proyecto?, etag?)          llamador: loadTemplate() de contracts/app.html al redactar un contrato NUEVO (la empresa se deduce en servidor).
--     plantilla_contrato_cuerpo_de_contrato(contrato, etag?)     NUEVA. llamador: openSavedContract() de contracts/app.html. Devuelve el texto de la version que ESE contrato fijo; exige poder ver el contrato.
--                                                               Sustituye, para el navegador, a plantilla_contrato_cuerpo_version(id): esa lee cualquier version por id y se queda SOLO con EXECUTE para su
--                                                               duenno lw_lector (revocada a authenticated: la usara S7 con su propio GRANT).
--     plantilla_contrato_fija(contrato, version)                 llamador: guardarContrato() de contracts/app.html al guardar. Ahora comprueba que la version es DE LA PLANTILLA del tipo del contrato
--                                                               (antes solo miraba la empresa: un agente podia fijar el texto de otra plantilla) y admite, mientras la empresa no tenga ninguna version activa
--                                                               de esa plantilla, su semilla v1 (copia exacta del fichero que se usaba hasta hoy).
--     revocadas (sin llamador): guarda_borrador, activa, descarta_borrador, versiones_lista, version_de_contrato, cuerpo_version.
--   plantilla_contrato_cuerpo cae a la semilla v1 cuando no hay version activa (misma copia exacta del fichero). Para que lo vea cualquier agente en alcance, la policy de lectura de versiones
--   deja leer las SEMILLAS (son los mismos textos que la web sirve sin login desde contracts/templates/: no hay nada que esconder).
--   INTERBLOQUEO (hallazgo de Datos/Seguridad, S4): guarda_borrador toma el candado asesor y luego `for update`; activa tomaba `for update` y luego el candado asesor = orden contrario.
--   Ahora activa lee SIN bloquear, toma el candado asesor, y solo entonces `for update` y vuelve a comprobar el estado. descarta_borrador igual. Los cuerpos de activa salen de 20261008990100 (conserva F1).
--   _plantilla_slug_de_tipo(tipo): tipo de contrato -> plantilla (inverso de CONTRACT_TIPO de contracts/assets/vocabulario.js; la prueba contracts/plantilla_tipo_slug.test.js afirma que son iguales).
-- destructivo-ok: crea 2 funciones, redefine 4 (fija, activa, descarta_borrador, cuerpo) y 1 policy de lectura, y cambia GRANT/REVOKE de EXECUTE; no toca filas
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_plantillas_s5.sql

-- ---------------------------------------------------------------- tipo -> plantilla
create function public._plantilla_slug_de_tipo(p_tipo text) returns text
language sql immutable security definer set search_path = '' as $$
  select m.slug from (values
    ('reserva_parcela', 'ppjb_parcela'), ('construccion', 'ppjb_construccion'), ('contrato_general', 'ppjb_reserva'), ('commercial_offer', 'commercial_offer'),
    ('carta_reserva', 'carta_reserva'), ('carta_reserva_ampliada', 'carta_reserva_ampliada'), ('acuerdo_comercial', 'commercial_collaboration'),
    ('protocolo_operativo', 'colaborador_operativo'), ('ppjb_bonian', 'ppjb_bonian'), ('ppjb_bonian_c2', 'ppjb_bonian_c2'), ('hak_sewa_notario', 'hak_sewa_notario'),
    ('carta_reserva_hak_sewa', 'carta_reserva_hak_sewa'), ('carta_reserva_pma', 'carta_reserva_pma'), ('poa', 'poa_notario'), ('cc00014_timon', 'cc00014_timon'),
    ('adenda', 'adenda'), ('carta_reserva_investor_deck', 'carta_reserva_investor_deck')
  ) as m(tipo, slug) where m.tipo = p_tipo
$$;
revoke all on function public._plantilla_slug_de_tipo(text) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------- las semillas las lee cualquier agente en alcance (son los textos que la web ya sirve sin login)
drop policy "versiones: lectura por empresa" on public.plantilla_contrato_versiones;
create policy "versiones: lectura por empresa" on public.plantilla_contrato_versiones for select to lw_lector
  using (public.es_agente() and public.empresa_en_alcance(empresa)
         and (estado <> 'borrador' or origen = 'semilla' or public.es_admin_de(empresa)
              or exists (select 1 from public.contrato_plantilla_version l where l.version_id = plantilla_contrato_versiones.id)));

-- ---------------------------------------------------------------- lectura para redactar: la activa, y si no hay, la semilla v1
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

-- ---------------------------------------------------------------- lectura para reabrir: el texto que ESE contrato fijo
create function public.plantilla_contrato_cuerpo_de_contrato(p_contrato uuid, p_etag text default null)
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

-- duenno lw_lector (patron b6): la RLS de las tres tablas filtra como el que llama
grant create on schema public to lw_lector;
alter function public.plantilla_contrato_cuerpo_de_contrato(uuid, text) owner to lw_lector;
revoke create on schema public from lw_lector;

-- ---------------------------------------------------------------- fijar la version: de la plantilla del contrato, activa o (sin activa) la semilla v1
create or replace function public.plantilla_contrato_fija(p_contrato uuid, p_version uuid) returns void
language plpgsql security definer set search_path = '' as $$
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

-- ---------------------------------------------------------------- interbloqueo: mismo orden en las tres escrituras (candado asesor, luego la fila)
create or replace function public.plantilla_contrato_activa(p_version uuid, p_nombre text, p_confirma boolean)
 returns jsonb language plpgsql security definer set search_path = '' as $$
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
  if v.estado <> 'borrador' then raise exception 'Solo se activa un borrador' using errcode = '55000'; end if;
  if not v.activable then raise exception 'Version no activable: %', coalesce(v.bloqueo_motivo, 'sin motivo') using errcode = '55000'; end if;
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

-- ---------------------------------------------------------------- EXECUTE: solo lo que tiene llamador
revoke all on function public.plantilla_contrato_cuerpo(text, uuid, text), public.plantilla_contrato_cuerpo_de_contrato(uuid, text), public.plantilla_contrato_fija(uuid, uuid),
  public.plantilla_contrato_activa(uuid, text, boolean), public.plantilla_contrato_descarta_borrador(uuid) from public, anon, authenticated, service_role;
grant execute on function public.plantilla_contrato_cuerpo(text, uuid, text), public.plantilla_contrato_cuerpo_de_contrato(uuid, text), public.plantilla_contrato_fija(uuid, uuid) to authenticated;
