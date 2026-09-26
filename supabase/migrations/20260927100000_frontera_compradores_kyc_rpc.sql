-- destructivo-ok: añade columnas, un índice único (0 rutas repetidas medidas el 27-sep), funciones y límites del bucket; cambia la policy de LECTURA de documents; no borra ni cambia ninguna fila.
-- Frontera frontend/backend — bloque 2: COMPRADORES (clients), DOCUMENTOS (documents) y bucket kyc (27-sep-2026, LAW-336).
-- SOLO AÑADE; el cierre (revoke + quitar las policies de escritura del bucket) va aparte cuando las pantallas
-- servidas ya no escriban directo. Plan, revisión previa #125 (Seguridad + Legal) y decisiones del owner:
-- encargos/20260927_lawang_frontera_b2_compradores_kyc.md
--
-- Agujeros que cierra (con el cierre): cualquier agente podía registrar en SU comprador la ruta del pasaporte
-- de otro y leerlo (agente_ve_kyc mira la fila), borrar o pisar cualquier fichero del bucket (también de
-- compradores con contrato firmado), cambiar documentos ajenos, darse el KYC por verificado y crear fichas a
-- nombre de otro o sin los datos obligatorios.
--
-- DECISIONES DEL OWNER (27-sep):
-- · «Aprobado» y «Rechazado» del KYC los pone cualquier admin; el agente solo mueve entre pendiente y en
--   revisión. Quién y cuándo lo sella el servidor.
-- · Un documento de un comprador con contrato firmado NO se destruye al retirarlo: queda marcado (quién,
--   cuándo, motivo) y sale de pantallas y portal. Sin contrato firmado se borra como hasta hoy.

-- ── bucket: tope y tipos (medido 27-sep: null/null, el plan lo daba por puesto) ──────────────────────────
update storage.buckets
   set file_size_limit = 20971520,
       allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
 where id = 'kyc';

-- ── columnas de rastro ───────────────────────────────────────────────────────────────────────────────────
alter table public.documents
  add column if not exists subido_por uuid,
  add column if not exists retirado_el timestamptz,
  add column if not exists retirado_por text,
  add column if not exists retirado_motivo text;
alter table public.clients
  add column if not exists kyc_verificado_por text,
  add column if not exists kyc_verificado_el timestamptz;

-- Una ruta, un documento: la comprobación estructural, no dentro de la RPC (dos llamadas a la vez se la saltan).
create unique index if not exists documents_storage_path_uniq on public.documents (storage_path);

-- ── lectura: solo los documentos de compradores que ves, y nunca los retirados ───────────────────────────
drop policy if exists "agentes leen documentos" on public.documents;
create policy "agentes leen documentos de sus compradores" on public.documents for select to authenticated
  using (public.es_agente() and retirado_el is null and exists (
    select 1 from public.clients c where c.id = documents.client_id and public.cliente_visible(c.propietario, c.id)));

create or replace function public.agente_ve_kyc(p_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_agente() and exists (
    select 1
      from public.documents d
      join public.clients c on c.id = d.client_id
     where d.storage_path = p_name
       and d.retirado_el is null
       and public.cliente_visible(c.propietario, c.id))
$$;

create or replace function public.portal_ve_kyc(p_name text) returns boolean
language sql stable security definer set search_path = 'public' as $$ select public.es_portal() and exists (
     select 1
       from documents dc
       join portal_accesos pa on pa.client_id = dc.client_id
      where pa.activo
        and dc.retirado_el is null
        and pa.email = lower(coalesce(auth.email(), ''))
        and dc.storage_path = p_name) $$;

-- portal_situacion: el bloque 'kyc' tampoco enseña los retirados. Parche quirúrgico con marca: si la
-- función cambió y la frase ya no está, la migración falla en vez de dejarla a medias.
do $$
declare v_def text; v_nuevo text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'portal_situacion';
  if strpos(v_def, 'doc.retirado_el is null') > 0 then return; end if;
  v_nuevo := replace(v_def, 'join mis_clientes mc2 on mc2.client_id = doc.client_id)',
                            'join mis_clientes mc2 on mc2.client_id = doc.client_id where doc.retirado_el is null)');
  if v_nuevo = v_def then
    raise exception 'portal_situacion cambió: no encuentro el bloque kyc que hay que filtrar';
  end if;
  execute v_nuevo;
end $$;

-- ── ficha del comprador ──────────────────────────────────────────────────────────────────────────────────
-- Alta (p_id null) o edición. Lista blanca; propietario, numero_cliente y el sello del KYC los pone el
-- servidor. En la edición solo se tocan las claves que vienen (la ficha del directorio no lleva notas).
-- Los choques de unicidad (clients_pasaporte_uniq, clients_email_tipo_key) salen tal cual: las pantallas
-- los traducen por el nombre.
create or replace function public.cliente_guarda(p_id uuid, p_datos jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_old public.clients%rowtype; v_id uuid;
  v_admin boolean := public.es_admin();
  v_tipo text; v_kyc text; v_kyc_antes text; v_falta text[] := '{}';
  v_nombre text := upper(nullif(btrim(coalesce(p_datos->>'full_name', '')), ''));
  v_email text := nullif(btrim(coalesce(p_datos->>'email', '')), '');
  v_tel text := nullif(btrim(coalesce(p_datos->>'phone', '')), '');
  v_nac text := nullif(btrim(coalesce(p_datos->>'nationality', '')), '');
  v_pas text := upper(nullif(btrim(coalesce(p_datos->>'passport_number', '')), ''));
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_agente() then raise exception 'Solo el equipo da de alta compradores' using errcode = '42501'; end if;
  if jsonb_typeof(p_datos) is distinct from 'object' then raise exception 'Datos de la ficha no válidos' using errcode = '22023'; end if;
  if v_email is not null and v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'El email no parece una dirección válida' using errcode = '22023';
  end if;

  if p_id is null then
    -- los seis datos del alta (owner, 14-sep; misma lista que faltanDatosComprador de compradores.js)
    if v_nombre is null or length(v_nombre) < 2 then v_falta := v_falta || 'Nombre completo'; end if;
    if v_email is null then v_falta := v_falta || 'Email'; end if;
    if v_tel is null or v_tel !~ '^\+[0-9]{1,4}' then v_falta := v_falta || 'Teléfono con su prefijo (+34, +62…)'; end if;
    if v_nac is null then v_falta := v_falta || 'Nacionalidad'; end if;
    if v_pas is null then v_falta := v_falta || 'Pasaporte / NPWP'; end if;
    if cardinality(v_falta) > 0 then
      raise exception 'No se puede crear la ficha, falta: %', array_to_string(v_falta, ', ') using errcode = '22023';
    end if;
    v_kyc_antes := 'pending';
  else
    select * into v_old from public.clients c where c.id = p_id for update;
    if not found or not public.cliente_visible(v_old.propietario, v_old.id) then
      raise exception 'No encuentro esa ficha entre las tuyas' using errcode = '42501';
    end if;
    if not (v_admin or (public.es_suyo(v_old.propietario) and not public.cliente_con_contrato_firmado(v_old.id))) then
      raise exception 'No se ha guardado: la base no te deja editar esta ficha. Suele ser porque no la diste de alta tú, o porque ya cuelga de un contrato firmado. Habla con un administrador.'
        using errcode = '42501';
    end if;
    if p_datos ? 'full_name' and (v_nombre is null or length(v_nombre) < 2) then
      raise exception 'Falta el nombre' using errcode = '22023';
    end if;
    v_kyc_antes := coalesce(v_old.kyc_status, 'pending');
  end if;

  v_tipo := coalesce(nullif(btrim(coalesce(p_datos->>'tipo', '')), ''), v_old.tipo, 'persona');
  -- KYC: aprobar o rechazar (y deshacerlo) solo un admin
  v_kyc := coalesce(nullif(btrim(coalesce(p_datos->>'kyc_status', '')), ''), v_kyc_antes);
  if v_kyc is distinct from v_kyc_antes and not v_admin
     and (v_kyc in ('verified', 'rejected') or v_kyc_antes in ('verified', 'rejected')) then
    raise exception 'Aprobar o rechazar el KYC de un comprador lo hace un administrador' using errcode = '42501';
  end if;

  if p_id is null then
    insert into public.clients (tipo, full_name, email, phone, nationality, passport_number, idioma_comunicacion,
                                forma_juridica, registro_num, rep_nombre, rep_cargo, notes, kyc_status,
                                kyc_verificado_por, kyc_verificado_el, propietario)
    values (v_tipo, v_nombre, v_email, v_tel, v_nac, v_pas,
            coalesce(nullif(btrim(coalesce(p_datos->>'idioma_comunicacion', '')), ''), 'es'),
            case when v_tipo = 'empresa' then nullif(btrim(coalesce(p_datos->>'forma_juridica', '')), '') end,
            case when v_tipo = 'empresa' then nullif(btrim(coalesce(p_datos->>'registro_num', '')), '') end,
            case when v_tipo = 'empresa' then nullif(btrim(coalesce(p_datos->>'rep_nombre', '')), '') end,
            case when v_tipo = 'empresa' then nullif(btrim(coalesce(p_datos->>'rep_cargo', '')), '') end,
            nullif(btrim(coalesce(p_datos->>'notes', '')), ''),
            v_kyc,
            case when v_kyc in ('verified', 'rejected') then (select auth.email()) end,
            case when v_kyc in ('verified', 'rejected') then now() end,
            (select auth.email()))
    returning id into v_id;
    return v_id;
  end if;

  update public.clients c
     set tipo = v_tipo,
         full_name = case when p_datos ? 'full_name' then v_nombre else c.full_name end,
         email = case when p_datos ? 'email' then v_email else c.email end,
         phone = case when p_datos ? 'phone' then v_tel else c.phone end,
         nationality = case when p_datos ? 'nationality' then v_nac else c.nationality end,
         passport_number = case when p_datos ? 'passport_number' then v_pas else c.passport_number end,
         idioma_comunicacion = case when p_datos ? 'idioma_comunicacion'
                                    then coalesce(nullif(btrim(coalesce(p_datos->>'idioma_comunicacion', '')), ''), 'es')
                                    else c.idioma_comunicacion end,
         -- a persona se VACÍAN (una ficha corregida no arrastra el CIF de cuando estaba mal puesta)
         forma_juridica = case when v_tipo <> 'empresa' then null when p_datos ? 'forma_juridica'
                               then nullif(btrim(coalesce(p_datos->>'forma_juridica', '')), '') else c.forma_juridica end,
         registro_num = case when v_tipo <> 'empresa' then null when p_datos ? 'registro_num'
                             then nullif(btrim(coalesce(p_datos->>'registro_num', '')), '') else c.registro_num end,
         rep_nombre = case when v_tipo <> 'empresa' then null when p_datos ? 'rep_nombre'
                           then nullif(btrim(coalesce(p_datos->>'rep_nombre', '')), '') else c.rep_nombre end,
         rep_cargo = case when v_tipo <> 'empresa' then null when p_datos ? 'rep_cargo'
                          then nullif(btrim(coalesce(p_datos->>'rep_cargo', '')), '') else c.rep_cargo end,
         notes = case when p_datos ? 'notes' then nullif(btrim(coalesce(p_datos->>'notes', '')), '') else c.notes end,
         kyc_status = v_kyc,
         kyc_verificado_por = case when v_kyc = v_kyc_antes then c.kyc_verificado_por
                                   when v_kyc in ('verified', 'rejected') then (select auth.email()) end,
         kyc_verificado_el = case when v_kyc = v_kyc_antes then c.kyc_verificado_el
                                  when v_kyc in ('verified', 'rejected') then now() end
   where c.id = p_id;
  if v_kyc is distinct from v_kyc_antes then
    insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
    values ('clients', p_id, 'kyc_status', v_kyc_antes, v_kyc, 'estado KYC desde la ficha', (select auth.email()));
  end if;
  return p_id;
end $$;
revoke all on function public.cliente_guarda(uuid, jsonb) from public, anon;
grant execute on function public.cliente_guarda(uuid, jsonb) to authenticated;

-- Traspaso SIN documentos (el que mueve contratos y facturas ya era RPC: traspasar_cliente_con_documentos).
-- Hasta hoy era un update directo que solo pasaba un admin (la policy exigía que la ficha siguiera siendo tuya).
create or replace function public.cliente_traspasa(p_id uuid, p_nuevo text, p_motivo text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_antes text; v_nuevo text := lower(btrim(coalesce(p_nuevo, '')));
begin
  if not public.es_admin() then raise exception 'Traspasar una ficha lo hace un administrador' using errcode = '42501'; end if;
  if not exists (select 1 from public.usuarios u where lower(u.email) = v_nuevo and u.activo) then
    raise exception 'El nuevo propietario no es un usuario activo del equipo' using errcode = '22023';
  end if;
  select c.propietario into v_antes from public.clients c where c.id = p_id for update;
  if not found then raise exception 'Esa ficha de comprador no existe' using errcode = '22023'; end if;
  if lower(coalesce(v_antes, '')) = v_nuevo then raise exception 'Esa ficha ya es de esa persona' using errcode = '22023'; end if;
  update public.clients set propietario = v_nuevo where id = p_id;
  insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
  values ('clients', p_id, 'propietario', v_antes, v_nuevo,
          coalesce(nullif(btrim(coalesce(p_motivo, '')), ''), 'traspaso de la ficha'), (select auth.email()));
  return p_id;
end $$;
revoke all on function public.cliente_traspasa(uuid, text, text) from public, anon;
grant execute on function public.cliente_traspasa(uuid, text, text) to authenticated;

-- ── documentos ──────────────────────────────────────────────────────────────────────────────────────────
-- Registra un fichero YA subido. La llama la edge ficheros-kyc con la sesión del usuario, después de leer
-- los primeros bytes. La ruta la dio la edge: `<client_id>/<uuid>.<ext>`; aquí se exige que sea de ESE
-- comprador, que exista en el bucket y que nadie la haya registrado (índice único).
create or replace function public.documento_kyc_registra(p_client uuid, p_path text, p_tipo text, p_caduca date default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_c public.clients%rowtype; v_id uuid;
begin
  if (select auth.uid()) is null or not public.es_agente() then
    raise exception 'Solo el equipo sube documentos' using errcode = '42501';
  end if;
  select * into v_c from public.clients c where c.id = p_client;
  if not found or not public.cliente_visible(v_c.propietario, v_c.id) then
    raise exception 'No encuentro ese comprador entre los tuyos' using errcode = '42501';
  end if;
  if p_path is null or p_path !~ ('^' || p_client::text || '/[0-9a-f-]{36}\.(pdf|jpg|jpeg|png|webp|heic|heif)$') then
    raise exception 'Ruta de documento no válida' using errcode = '22023';
  end if;
  if p_tipo is null or p_tipo not in ('passport', 'npwp', 'visa', 'proof_of_funds', 'proof_of_address', 'signed_contract', 'other') then
    raise exception 'Tipo de documento no válido' using errcode = '22023';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'kyc' and o.name = p_path) then
    raise exception 'El fichero no ha llegado al archivo: vuelve a subirlo' using errcode = '22023';
  end if;
  begin
    insert into public.documents (client_id, doc_type, storage_path, status, caduca_el, subido_por)
    values (p_client, p_tipo, p_path, 'pending', p_caduca, (select auth.uid()))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Ese fichero ya está registrado en una ficha' using errcode = '23505';
  end;
  return v_id;
end $$;
revoke all on function public.documento_kyc_registra(uuid, text, text, date) from public, anon;
grant execute on function public.documento_kyc_registra(uuid, text, text, date) to authenticated;

-- Retira un documento. Sin contrato firmado: admin, se borra la fila (trg_guarda_antes_de_borrar la guarda
-- en borrados) y devuelve la ruta para que la edge borre el fichero. Con contrato firmado: super admin y
-- motivo; NO se destruye nada, se marca (decisión del owner). Si el comprador estaba aprobado, vuelve a
-- «en revisión»: sin ese documento, «aprobado» ya no es verdad (Legal #125).
create or replace function public.documento_kyc_retira(p_id uuid, p_motivo text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_d public.documents%rowtype; v_c public.clients%rowtype; v_firmado boolean;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if not public.es_admin() then raise exception 'Retirar documentos lo hace un administrador' using errcode = '42501'; end if;
  select * into v_d from public.documents d where d.id = p_id and d.retirado_el is null for update;
  if not found then raise exception 'Ese documento ya no está en la ficha' using errcode = '22023'; end if;
  select * into v_c from public.clients c where c.id = v_d.client_id for update;
  v_firmado := public.cliente_con_contrato_firmado(v_d.client_id);

  if v_firmado then
    if not public.es_super_admin() then
      raise exception 'Este comprador tiene un contrato firmado: su documentación KYC solo la retira un super admin (queda registrado).'
        using errcode = '42501';
    end if;
    if v_motivo is null or length(v_motivo) < 10 then
      raise exception 'Este comprador tiene un contrato firmado: escribe por qué se retira el documento (queda registrado y el fichero se conserva)'
        using errcode = '22023';
    end if;
    update public.documents set retirado_el = now(), retirado_por = (select auth.email()), retirado_motivo = v_motivo
     where id = p_id;
  else
    delete from public.documents where id = p_id;
  end if;

  if v_c.kyc_status = 'verified' then
    update public.clients set kyc_status = 'submitted', kyc_verificado_por = null, kyc_verificado_el = null where id = v_c.id;
    insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
    values ('clients', v_c.id, 'kyc_status', 'verified', 'submitted', 'se retiró un documento KYC', (select auth.email()));
  end if;

  return jsonb_build_object('conservado', v_firmado,
                            'borrar_fichero', not v_firmado,
                            'path', case when v_firmado then null else v_d.storage_path end,
                            'kyc_vuelve_a_revision', v_c.kyc_status = 'verified');
end $$;
revoke all on function public.documento_kyc_retira(uuid, text) from public, anon;
grant execute on function public.documento_kyc_retira(uuid, text) to authenticated;

-- Reintento de limpieza tras borrar una ficha: ficheros bajo la carpeta de un comprador QUE YA NO EXISTE y
-- sin fila en documents (las 6 filas de una fusión antigua viven en carpeta ajena: esas tienen fila y no se
-- tocan). Nunca sale del prefijo `<uuid>/`. Solo la llama la edge con service role.
create or replace function public.kyc_sueltos_de(p_client uuid) returns setof text
language sql stable security definer set search_path = '' as $$
  select o.name from storage.objects o
   where o.bucket_id = 'kyc'
     and o.name like p_client::text || '/%'
     and not exists (select 1 from public.clients c where c.id = p_client)
     and not exists (select 1 from public.documents d where d.storage_path = o.name)
   limit 500
$$;
revoke all on function public.kyc_sueltos_de(uuid) from public, anon, authenticated;
grant execute on function public.kyc_sueltos_de(uuid) to service_role;
