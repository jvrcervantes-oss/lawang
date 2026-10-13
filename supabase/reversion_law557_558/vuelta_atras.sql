-- VUELTA ATRÁS de 20261013235338_law557_558_alta_con_documento_y_retencion_kyc + 20261013235905_law558_kyc_retencion_cron.
-- Restaura cliente_guarda, crm_lead_ficha_crear y kyc_sueltos_de EXACTAMENTE como estaban el 13-oct-2026 antes de la
-- migración (leídos con pg_get_functiondef de producción ese día) y quita lo nuevo.
-- ANTES de lanzarla: (1) apagar el front nuevo o volver a la versión anterior de editores.js/leads.js (la pantalla
-- nueva llama a la edge, que sin estas RPC responde alta_no_disponible y no crea nada); (2) redesplegar ficheros-kyc
-- v17 si se quiere quitar también las acciones alta_* (no es necesario: sin las RPC no hacen nada);
-- (3) `supabase functions delete kyc-retencion` (o dejarla: sin su secreto responde 500 y no toca nada).
-- Si hay altas pendientes con ficheros subidos, borrar antes esos ficheros (rutas `<id de la pendiente>/…` del bucket kyc):
-- sin la tabla, kyc_sueltos_de los verá como sueltos de una ficha inexistente y limpia_comprador los podrá quitar.
-- destructivo-ok: vuelta atrás de LAW-557/558 (quita objetos nuevos; no toca filas de clientes ni de documentos)

select cron.unschedule('kyc-retencion-diario') where exists (select 1 from cron.job where jobname = 'kyc-retencion-diario');

create or replace function public.cliente_guarda(p_id uuid, p_datos jsonb)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_old public.clients%rowtype; v_id uuid;
  v_admin boolean := public.es_admin_en_alguna_empresa();
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
    if v_nombre is null or length(v_nombre) < 2 then v_falta := array_append(v_falta, 'Nombre completo'::text); end if;
    if v_email is null then v_falta := array_append(v_falta, 'Email'::text); end if;
    if v_tel is null or v_tel !~ '^\+[0-9]{1,4}' then v_falta := array_append(v_falta, 'Teléfono con su prefijo (+34, +62…)'::text); end if;
    if v_nac is null then v_falta := array_append(v_falta, 'Nacionalidad'::text); end if;
    if v_pas is null then v_falta := array_append(v_falta, 'Pasaporte / NPWP'::text); end if;
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
    if public.es_admin_en_alguna_empresa() and not public.es_admin() and not public.admin_de_cliente(p_id, true)
       and exists (select 1 from jsonb_object_keys(p_datos) k where k not in ('notes', 'idioma_comunicacion')) then
      raise exception 'Este comprador tiene contratos o pagos en otra empresa: aqui solo puedes cambiar las notas y el idioma; su identidad y su KYC los toca un administrador de las dos empresas'
        using errcode = '42501';
    end if;
  end if;

  v_tipo := coalesce(nullif(btrim(coalesce(p_datos->>'tipo', '')), ''), v_old.tipo, 'persona');
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
end $function$;

create or replace function public.crm_lead_ficha_crear(p_lead uuid)
 returns table(client_id uuid, ya_existia boolean)
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_nombre text; v_email text; v_tel text; v_id uuid;
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if not public.lead_a_mi_alcance(p_lead) then
    raise exception 'Ese lead no es de ninguna de tus campanas' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;

  select btrim(coalesce(l.name, '')),
         nullif(lower(btrim(coalesce(l.email, ''))), ''),
         nullif(btrim(coalesce(l.whatsapp, '')), '')
    into v_nombre, v_email, v_tel
    from public.leads l where l.id = p_lead;

  if v_nombre is null then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;
  if v_nombre = '' then
    raise exception 'Ese lead no tiene nombre: no se puede abrir una ficha sin nombre' using errcode = 'PT400';
  end if;
  if v_email is null then
    raise exception 'Ese lead no dejo email: la ficha necesita un identificador' using errcode = 'PT400';
  end if;

  select c.id into v_id from public.clients c
   where c.email is not null and lower(c.email) = v_email and c.tipo = 'persona'
     and (not (select public.alcance_restringido()) or public.cliente_visible(c.propietario, c.id));
  if v_id is not null then
    return query select v_id, true;
    return;
  end if;

  insert into public.clients (full_name, email, phone, tipo, kyc_status, propietario, notes)
       values (upper(v_nombre), v_email, v_tel, 'persona', 'pending', v_quien,
               'Ficha abierta desde el CRM de leads el ' || to_char(now(), 'DD-MM-YYYY'))
    returning clients.id into v_id;

  return query select v_id, false;
end;
$function$;

create or replace function public.kyc_sueltos_de(p_client uuid)
 returns setof text
 language sql
 stable security definer
 set search_path to ''
as $function$
  select o.name from storage.objects o
   where o.bucket_id = 'kyc'
     and o.name like p_client::text || '/%'
     and not exists (select 1 from public.clients c where c.id = p_client)
     and not exists (select 1 from public.documents d where d.storage_path = o.name)
   limit 500
$function$;

drop function if exists public.cliente_alta_con_documentos(uuid, uuid, jsonb, text[], date);
drop function if exists public.kyc_alta_reserva(uuid, uuid);
drop function if exists public.kyc_alta_estado(uuid, uuid);
drop function if exists public.kyc_alta_descarta(uuid, uuid);
drop function if exists public.kyc_barrido(boolean);
drop function if exists public.kyc_retencion(boolean);
drop function if exists public._kyc_retencion_candidato(uuid, timestamptz);
drop function if exists public.kyc_retencion_registra(jsonb);
drop table if exists public.kyc_retencion_pasadas;   -- solo recuentos de cada pasada; se pierde ese historial
drop function if exists public._cliente_crea(uuid, jsonb);
drop function if exists public.cron_kyc_retencion_secret();
drop table if exists public.kyc_altas_pendientes;
delete from vault.secrets where name = 'cron_kyc_retencion';
-- Las claves de config_instancia se dejan (sin las RPC no hacen nada); si se quieren quitar:
-- delete from public.config_instancia where clave in ('kyc_meses_retencion', 'alta_exige_documento');
