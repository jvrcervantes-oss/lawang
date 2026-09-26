-- Arreglo de 20260927100000 (27-sep-2026): el alta con datos que faltan reventaba con «malformed array
-- literal» en vez de decir cuáles faltan (`text[] || 'Email'` toma el literal como array). Cazado por la
-- prueba por rol antes de publicar. Solo reemplaza cliente_guarda; nada más cambia.
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
