-- LAW-557 + LAW-558 (13-oct-2026): el alta de un cliente va CON su documento de identidad, en una sola operación,
-- y las copias de los documentos KYC se borran solas a los 12 meses sin reserva ni contrato.
-- Plan definitivo tras la revisión previa #314 (Legal + Seguridad + Backend); decisiones del owner del 13-oct:
--   · LAW-557 «Alta y pasaporte juntos»: la ficha y su documento entran los dos o ninguno. No se bloquea emitir ni firmar.
--   · LAW-558: borrado automático a los 12 meses sin reserva ni contrato, SOLO de las copias (filas de `documents` de
--     tipos borrables y sus ficheros). La ficha se queda entera, con el número de pasaporte escrito.
--
-- POR QUÉ: hasta hoy el alta era dos pasos (cliente_guarda → subir), y si la subida fallaba quedaba una ficha sin
-- documento que nadie terminaba (estado «ficha creada, falta subir el documento»). Y las copias de pasaportes de
-- quien nunca reservó se guardaban sin plazo (el aviso de privacidad lo decía así).
--
-- CÓMO (la frontera, `contexto/patrones_tecnicos.md` → «Frontera frontend / backend»):
--   1. La edge `ficheros-kyc` pide a la base una «alta pendiente» (`kyc_alta_reserva`): un id que genera la BASE, nunca
--      el navegador. Ese id será el uuid del cliente y la carpeta de sus ficheros (`<alta_id>/<uuid>.<ext>`).
--   2. Los ficheros se suben por URL firmada a esa carpeta; la edge mira sus bytes.
--   3. `cliente_alta_con_documentos` crea la ficha con ese id y registra los documentos EN LA MISMA TRANSACCIÓN.
--      Si la ficha no valida, no queda nada (ni ficha ni documentos), y la pendiente y los ficheros siguen para el
--      reintento. Reintento tras confirmar = idempotente (devuelve la ficha ya creada del mismo dueño).
--   4. Con `config_instancia.alta_exige_documento` = true, `cliente_guarda(null, …)` y el «Crear ficha» del CRM de
--      leads se niegan: el alta solo entra por el paso 3. La migración NO lo enciende (orden: front primero, luego
--      servidor): fichero aparte `supabase/datos/law557_enciende_alta_exige_documento.sql`.
--   5. Retención: `kyc_retencion(p_dry)` (solo service_role, sin parámetro de meses: lo lee de
--      `config_instancia.kyc_meses_retencion`, mínimo 12 en código; sin la clave no hace nada). La llama la edge
--      `kyc-retencion` desde pg_cron con X-Cron-Secret (`cron_kyc_retencion_secret()`, Vault). La edge borra después
--      los ficheros que la base le devuelve.
--
-- DUEÑO DE CADA DATO («El dato tiene un dueño»):
--   · `kyc_altas_pendientes`: la escriben SOLO las RPC de aquí (edge con service_role, actuando como el usuario). Es
--     estado efímero (24 h de uso, 36 h hasta el barrido), no una copia de nada: su id pasa a ser `clients.id`.
--   · La identidad del cliente sigue siendo de `clients` (un solo escritor de alta: `_cliente_crea`).
--   · El documento, de `documents` (escritor: `documento_kyc_registra`). El fichero, de Storage `kyc`.
--   · «Última actividad» de la retención NO se guarda: se calcula cada vez de created_at, uploaded_at,
--     kyc_verificado_el y correcciones_datos (abrir la ficha y las consultas del bot NO cuentan, decisión por defecto
--     del CEO). Nada que envejezca.
--
-- BORRA FILAS (destructivo-ok: decisión del owner LAW-558 del 13-oct-2026 «borrado automático a los 12 meses sin
-- reserva ni contrato, solo las copias»; y LAW-557 «alta y pasaporte juntos»: la pendiente se consume al crear):
--   · `kyc_retencion` borra filas de `documents` de tipos borrables (nunca signed_contract) de clientes sin reserva,
--     factura, contrato ni portal, inactivos 12 meses. Hoy no hay NINGUNO posible (el cliente más antiguo es del
--     28-jul-2026, medido el 13-oct).
--   · `cliente_alta_con_documentos`, `kyc_alta_descarta` y `kyc_barrido` borran filas de `kyc_altas_pendientes`.
--   · Los ficheros los borra la edge, nunca esta migración.
-- destructivo-ok: LAW-558 decisión del owner 13-oct-2026 (retención 12 meses, solo copias) y LAW-557 (alta en una operación)
--
-- VUELTA ATRÁS: supabase/reversion_law557_558/vuelta_atras.sql (restaura cliente_guarda, crm_lead_ficha_crear y
-- kyc_sueltos_de tal cual estaban, quita lo nuevo y desprograma el cron).

-- ─── 1. Altas pendientes ──────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.kyc_altas_pendientes (
  id            uuid primary key default gen_random_uuid(),
  uid           uuid not null,
  creado_en     timestamptz not null default now(),
  urls_firmadas int not null default 0 check (urls_firmadas >= 0)
);
comment on table public.kyc_altas_pendientes is
  'LAW-557: alta de cliente a medio hacer (ficheros subidos, ficha aún no creada). Su id será clients.id. Solo la tocan las RPC kyc_alta_* y cliente_alta_con_documentos (service_role, desde la edge ficheros-kyc). Tope 3 abiertas por usuario y 8 URLs firmadas por alta; caduca a las 24 h y se barre a las 36 h (kyc_barrido).';
create index if not exists kyc_altas_pendientes_uid_idx on public.kyc_altas_pendientes (uid, creado_en);
alter table public.kyc_altas_pendientes enable row level security;
-- Sin políticas a propósito: nadie la lee ni la escribe desde la API; solo las funciones SECURITY DEFINER de abajo.
revoke all on table public.kyc_altas_pendientes from public, anon, authenticated, service_role;

-- ─── 2. Crear la ficha: un solo escritor ───────────────────────────────────────────────────────────────────────────
-- La rama de CREAR de cliente_guarda, movida aquí (no copiada). Las comprobaciones comunes (sesión, equipo, objeto,
-- email) se leen en el CUERPO y no en DECLARE: el llamador de la vía nueva fija la identidad (_actua_como) antes de
-- llamar. p_id lo pone solo cliente_alta_con_documentos (el id de la alta pendiente, generado por la base); con null,
-- el de siempre. Sin execute para nadie: solo la llaman cliente_guarda y cliente_alta_con_documentos.
create or replace function public._cliente_crea(p_id uuid, p_datos jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid; v_admin boolean; v_tipo text; v_kyc text; v_falta text[] := '{}';
  v_nombre text; v_email text; v_tel text; v_nac text; v_pas text;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_agente() then raise exception 'Solo el equipo da de alta compradores' using errcode = '42501'; end if;
  if jsonb_typeof(p_datos) is distinct from 'object' then raise exception 'Datos de la ficha no válidos' using errcode = '22023'; end if;
  v_nombre := upper(nullif(btrim(coalesce(p_datos->>'full_name', '')), ''));
  v_email := nullif(btrim(coalesce(p_datos->>'email', '')), '');
  v_tel := nullif(btrim(coalesce(p_datos->>'phone', '')), '');
  v_nac := nullif(btrim(coalesce(p_datos->>'nationality', '')), '');
  v_pas := upper(nullif(btrim(coalesce(p_datos->>'passport_number', '')), ''));
  if v_email is not null and v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'El email no parece una dirección válida' using errcode = '22023';
  end if;

  if v_nombre is null or length(v_nombre) < 2 then v_falta := array_append(v_falta, 'Nombre completo'::text); end if;
  if v_email is null then v_falta := array_append(v_falta, 'Email'::text); end if;
  if v_tel is null or v_tel !~ '^\+[0-9]{1,4}' then v_falta := array_append(v_falta, 'Teléfono con su prefijo (+34, +62…)'::text); end if;
  if v_nac is null then v_falta := array_append(v_falta, 'Nacionalidad'::text); end if;
  if v_pas is null then v_falta := array_append(v_falta, 'Pasaporte / NPWP'::text); end if;
  if cardinality(v_falta) > 0 then
    raise exception 'No se puede crear la ficha, falta: %', array_to_string(v_falta, ', ') using errcode = '22023';
  end if;

  v_admin := public.es_admin_en_alguna_empresa();
  v_tipo := coalesce(nullif(btrim(coalesce(p_datos->>'tipo', '')), ''), 'persona');
  v_kyc := coalesce(nullif(btrim(coalesce(p_datos->>'kyc_status', '')), ''), 'pending');
  if v_kyc is distinct from 'pending' and not v_admin and v_kyc in ('verified', 'rejected') then
    raise exception 'Aprobar o rechazar el KYC de un comprador lo hace un administrador' using errcode = '42501';
  end if;

  insert into public.clients (id, tipo, full_name, email, phone, nationality, passport_number, idioma_comunicacion,
                              forma_juridica, registro_num, rep_nombre, rep_cargo, notes, kyc_status,
                              kyc_verificado_por, kyc_verificado_el, propietario)
  values (coalesce(p_id, gen_random_uuid()), v_tipo, v_nombre, v_email, v_tel, v_nac, v_pas,
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
end $$;
revoke all on function public._cliente_crea(uuid, jsonb) from public, anon, authenticated, service_role;

-- ─── 3. cliente_guarda: editar igual que siempre; crear, solo sin el interruptor ────────────────────────────────────
-- Con `alta_exige_documento` = true (jsonb boolean; ausente = false) el alta sin documento se niega: la pantalla nueva
-- va por la edge. Editar no cambia en nada (el cuerpo de editar es el de antes, línea a línea).
create or replace function public.cliente_guarda(p_id uuid, p_datos jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.clients%rowtype;
  v_admin boolean := public.es_admin_en_alguna_empresa();
  v_tipo text; v_kyc text; v_kyc_antes text;
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
    if coalesce((select c.valor = 'true'::jsonb from public.config_instancia c where c.clave = 'alta_exige_documento'), false) then
      raise exception 'El alta de un cliente va con su documento de identidad: recarga la página y usa Nuevo cliente'
        using errcode = '22023';
    end if;
    return public._cliente_crea(null, p_datos);
  end if;

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

  v_tipo := coalesce(nullif(btrim(coalesce(p_datos->>'tipo', '')), ''), v_old.tipo, 'persona');
  v_kyc := coalesce(nullif(btrim(coalesce(p_datos->>'kyc_status', '')), ''), v_kyc_antes);
  if v_kyc is distinct from v_kyc_antes and not v_admin
     and (v_kyc in ('verified', 'rejected') or v_kyc_antes in ('verified', 'rejected')) then
    raise exception 'Aprobar o rechazar el KYC de un comprador lo hace un administrador' using errcode = '42501';
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
end $$;
-- (create or replace conserva sus permisos: authenticated + service_role, como antes)

-- ─── 4. CRM de leads: con el interruptor, «Crear ficha» ya no crea ─────────────────────────────────────────────────
-- Devolver la ficha existente (mismo email) sigue igual. Solo cambia la rama que CREARÍA una ficha sin documento.
create or replace function public.crm_lead_ficha_crear(p_lead uuid)
returns table(client_id uuid, ya_existia boolean)
language plpgsql
security definer
set search_path = ''
as $$
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

  if coalesce((select c.valor = 'true'::jsonb from public.config_instancia c where c.clave = 'alta_exige_documento'), false) then
    raise exception 'Este lead aún no tiene ficha de cliente: dale de alta en Clientes (Nuevo cliente), con su pasaporte, y vuelve aquí para abrir el contrato'
      using errcode = 'PT400';
  end if;

  insert into public.clients (full_name, email, phone, tipo, kyc_status, propietario, notes)
       values (upper(v_nombre), v_email, v_tel, 'persona', 'pending', v_quien,
               'Ficha abierta desde el CRM de leads el ' || to_char(now(), 'DD-MM-YYYY'))
    returning clients.id into v_id;

  return query select v_id, false;
end;
$$;

-- ─── 5. Reservar / usar una alta pendiente (solo la edge, como el usuario de la sesión) ────────────────────────────
-- Errores de la interfaz: tokens fijos (la edge los pasa tal cual): demasiadas_altas_abiertas · alta_no_valida ·
-- demasiados_ficheros. 22023 queda SOLO para la validación de la ficha.
create or replace function public.kyc_alta_reserva(p_uid uuid, p_alta uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  perform public._actua_como(p_uid);
  if not public.es_agente() then raise exception 'Solo el equipo da de alta compradores' using errcode = '42501'; end if;
  if p_alta is null then
    -- el tope de 3 se cuenta bajo un candado por usuario: dos peticiones a la vez no lo saltan
    perform pg_advisory_xact_lock(hashtext('kyc_alta:' || p_uid::text));
    if (select count(*) from public.kyc_altas_pendientes k
         where k.uid = p_uid and k.creado_en > now() - interval '24 hours') >= 3 then
      raise exception 'demasiadas_altas_abiertas' using errcode = 'PT409';
    end if;
    insert into public.kyc_altas_pendientes (uid, urls_firmadas) values (p_uid, 1) returning id into v_id;
    return v_id;
  end if;
  update public.kyc_altas_pendientes k set urls_firmadas = k.urls_firmadas + 1
   where k.id = p_alta and k.uid = p_uid and k.creado_en > now() - interval '24 hours' and k.urls_firmadas < 8
  returning k.id into v_id;
  if v_id is null then
    if exists (select 1 from public.kyc_altas_pendientes k
                where k.id = p_alta and k.uid = p_uid and k.creado_en > now() - interval '24 hours') then
      raise exception 'demasiados_ficheros' using errcode = 'PT409';
    end if;
    raise exception 'alta_no_valida' using errcode = 'PT403';
  end if;
  return v_id;
end $$;
revoke all on function public.kyc_alta_reserva(uuid, uuid) from public, anon, authenticated;
grant execute on function public.kyc_alta_reserva(uuid, uuid) to service_role;

-- ¿De quién es esta alta? La edge lo pregunta ANTES de mirar bytes o borrar nada (B no puede tocar ficheros de A).
--   'pendiente' = la pendiente es tuya y está en plazo · 'creado' = ya es una ficha tuya (reintento) · null = nada tuyo.
create or replace function public.kyc_alta_estado(p_uid uuid, p_alta uuid)
returns text
language plpgsql
security definer          -- volátil a propósito: _actua_como fija la identidad con set_config
set search_path = ''
as $$
declare v_email text;
begin
  v_email := public._actua_como(p_uid);
  if not public.es_agente() then raise exception 'Solo el equipo da de alta compradores' using errcode = '42501'; end if;
  if p_alta is null then return null; end if;
  if exists (select 1 from public.kyc_altas_pendientes k
              where k.id = p_alta and k.uid = p_uid and k.creado_en > now() - interval '24 hours') then
    return 'pendiente';
  end if;
  if exists (select 1 from public.clients c where c.id = p_alta and lower(c.propietario) = v_email) then
    return 'creado';
  end if;
  return null;
end $$;
revoke all on function public.kyc_alta_estado(uuid, uuid) from public, anon, authenticated;
grant execute on function public.kyc_alta_estado(uuid, uuid) to service_role;

-- ─── 6. El alta con sus documentos, en UNA transacción ─────────────────────────────────────────────────────────────
-- Orden: identidad → equipo → pendiente tuya y en plazo (o reintento idempotente) → rutas → datos (solo las 11 claves
-- de la ficha) → _cliente_crea(p_alta) → documento_kyc_registra por fichero → se consume la pendiente.
-- El tipo de documento lo decide el SERVIDOR: persona → passport, empresa → other.
-- Un email o pasaporte repetido sale como 22023 con mensaje propio y SIN el detalle de la otra ficha (no se filtra
-- nada de ella). Devuelve también los ficheros de la carpeta que no entraron (subidos y descartados en pantalla):
-- la edge los borra, porque con la ficha creada ni kyc_sueltos_de ni el barrido los verían.
create or replace function public.cliente_alta_con_documentos(p_uid uuid, p_alta uuid, p_datos jsonb, p_paths text[],
                                                              p_caduca date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text; v_id uuid; v_datos jsonb; v_tipo text; v_tipo_doc text; v_p text; v_con text;
  v_claves constant text[] := array['full_name', 'email', 'phone', 'nationality', 'passport_number', 'tipo',
                                     'idioma_comunicacion', 'forma_juridica', 'registro_num', 'rep_nombre', 'rep_cargo'];
  v_sobran text[];
begin
  v_email := public._actua_como(p_uid);
  if not public.es_agente() then raise exception 'Solo el equipo da de alta compradores' using errcode = '42501'; end if;
  if p_alta is null then raise exception 'alta_no_valida' using errcode = 'PT403'; end if;

  perform 1 from public.kyc_altas_pendientes k
   where k.id = p_alta and k.uid = p_uid and k.creado_en > now() - interval '24 hours'
   for update;
  if not found then
    -- reintento tras confirmar: la pendiente ya se consumió y la ficha es de este mismo usuario
    if exists (select 1 from public.clients c where c.id = p_alta and lower(c.propietario) = v_email) then
      return jsonb_build_object('id', p_alta, 'ya_existia', true, 'sobrantes', '[]'::jsonb);
    end if;
    raise exception 'alta_no_valida' using errcode = 'PT403';
  end if;

  if p_paths is null or cardinality(p_paths) = 0 then raise exception 'faltan_ficheros' using errcode = 'PT400'; end if;
  if cardinality(p_paths) > 4 then raise exception 'demasiados_ficheros' using errcode = 'PT400'; end if;
  if (select count(distinct x) from unnest(p_paths) x) <> cardinality(p_paths) then
    raise exception 'ruta_invalida' using errcode = 'PT400';
  end if;
  foreach v_p in array p_paths loop
    if v_p is null or v_p !~ ('^' || p_alta::text
         || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png|webp|heic|heif)$') then
      raise exception 'ruta_invalida' using errcode = 'PT400';
    end if;
  end loop;

  if jsonb_typeof(p_datos) is distinct from 'object' then raise exception 'Datos de la ficha no válidos' using errcode = '22023'; end if;
  select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) into v_datos
    from jsonb_each(p_datos) e where e.key = any (v_claves);
  v_tipo := coalesce(nullif(btrim(coalesce(v_datos->>'tipo', '')), ''), 'persona');
  if v_tipo not in ('persona', 'empresa') then raise exception 'Tipo de cliente no válido' using errcode = '22023'; end if;
  v_tipo_doc := case when v_tipo = 'empresa' then 'other' else 'passport' end;

  begin
    v_id := public._cliente_crea(p_alta, v_datos);
  exception when unique_violation then
    get stacked diagnostics v_con = constraint_name;
    raise exception '%', case v_con
        when 'clients_email_tipo_key' then 'Ya hay una ficha con ese email: búscala en Clientes en lugar de crear otra'
        when 'clients_pasaporte_uniq' then 'Ya hay una ficha con ese número de pasaporte o NPWP: búscala en Clientes en lugar de crear otra'
        else 'Ya hay una ficha con esos datos: búscala en Clientes en lugar de crear otra' end
      using errcode = '22023';
  end;

  foreach v_p in array p_paths loop
    perform public.documento_kyc_registra(p_uid, v_id, v_p, v_tipo_doc, p_caduca);
  end loop;

  delete from public.kyc_altas_pendientes where id = p_alta;

  select coalesce(array_agg(o.name order by o.name), '{}') into v_sobran
    from storage.objects o
   where o.bucket_id = 'kyc' and o.name like p_alta::text || '/%'
     and not exists (select 1 from public.documents d where d.storage_path = o.name);
  return jsonb_build_object('id', v_id, 'ya_existia', false, 'sobrantes', to_jsonb(v_sobran));
end $$;
revoke all on function public.cliente_alta_con_documentos(uuid, uuid, jsonb, text[], date) from public, anon, authenticated;
grant execute on function public.cliente_alta_con_documentos(uuid, uuid, jsonb, text[], date) to service_role;

-- ─── 7. Descartar una alta a medias (al cerrar el panel sin terminar; best effort) ────────────────────────────────
-- Nunca borra nada si la pendiente no es del usuario o si ya existe el cliente. Devuelve las rutas sin fila en
-- documents de esa carpeta: las borra la edge.
create or replace function public.kyc_alta_descarta(p_uid uuid, p_alta uuid)
returns text[]
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid; v_rutas text[];
begin
  perform public._actua_como(p_uid);
  if not public.es_agente() then raise exception 'Solo el equipo da de alta compradores' using errcode = '42501'; end if;
  if p_alta is null or exists (select 1 from public.clients c where c.id = p_alta) then return '{}'; end if;
  delete from public.kyc_altas_pendientes k where k.id = p_alta and k.uid = p_uid returning k.id into v_id;
  if v_id is null then return '{}'; end if;
  select coalesce(array_agg(o.name order by o.name), '{}') into v_rutas
    from storage.objects o
   where o.bucket_id = 'kyc' and o.name like p_alta::text || '/%'
     and not exists (select 1 from public.documents d where d.storage_path = o.name);
  return v_rutas;
end $$;
revoke all on function public.kyc_alta_descarta(uuid, uuid) from public, anon, authenticated;
grant execute on function public.kyc_alta_descarta(uuid, uuid) to service_role;

-- ─── 8. kyc_sueltos_de: una carpeta con alta pendiente viva no es «suelta» ─────────────────────────────────────────
create or replace function public.kyc_sueltos_de(p_client uuid)
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select o.name from storage.objects o
   where o.bucket_id = 'kyc'
     and o.name like p_client::text || '/%'
     and not exists (select 1 from public.clients c where c.id = p_client)
     and not exists (select 1 from public.documents d where d.storage_path = o.name)
     and not exists (select 1 from public.kyc_altas_pendientes k where k.id = p_client)
   limit 500
$$;

-- ─── 9. Barrido diario (lo llama la edge kyc-retencion) ────────────────────────────────────────────────────────────
-- (1) pendientes de más de 36 h; (2) objetos de `kyc` sin fila en documents y sin pendiente viva, de más de 36 h —
-- TAMBIÉN dentro de la carpeta de un cliente que existe (revisor, 13-oct): ahí acaba el fichero cuando la base ya borró
-- su fila (retención, retirada, borrado de ficha) y el borrado en Storage falló, o una subida que llegó tarde. Un fichero
-- sin fila no lo ve nadie en la suite; todo fichero legítimo del bucket tiene su fila (medido el 13-oct: 192 de 192).
-- Con p_dry solo cuenta. Devuelve las rutas a borrar (la edge las borra; nunca se piden por el cuerpo).
create or replace function public.kyc_barrido(p_dry boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_pend int; v_rutas text[];
begin
  select count(*) into v_pend from public.kyc_altas_pendientes k where k.creado_en < now() - interval '36 hours';
  if not coalesce(p_dry, true) then
    delete from public.kyc_altas_pendientes k where k.creado_en < now() - interval '36 hours';
  end if;
  select coalesce(array_agg(x.name order by x.name), '{}') into v_rutas from (
    select o.name from storage.objects o
     where o.bucket_id = 'kyc'
       and o.created_at < now() - interval '36 hours'
       and not exists (select 1 from public.documents d where d.storage_path = o.name)
       and not exists (select 1 from public.kyc_altas_pendientes k
                        where k.id::text = split_part(o.name, '/', 1) and k.creado_en >= now() - interval '36 hours')
     limit 500) x;
  return jsonb_build_object('pendientes_caducadas', v_pend, 'rutas', to_jsonb(v_rutas));
end $$;
revoke all on function public.kyc_barrido(boolean) from public, anon, authenticated;
grant execute on function public.kyc_barrido(boolean) to service_role;

-- ─── 10. Retención LAW-558 ─────────────────────────────────────────────────────────────────────────────────────────
-- ¿Es candidato este cliente? Lo barato primero (reloj, tipos, signed_contract, vínculos en documents) y solo al
-- final _sc_referencias_cliente, que cuenta en cada tabla que apunta a clients y en contratos (lección del 1-oct:
-- nunca contratos entero; aquí es un count con where por cliente, una vez por cada cliente que pasa los filtros baratos).
create or replace function public._kyc_retencion_candidato(p_id uuid, p_corte timestamptz)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_ult timestamptz;
begin
  if not exists (select 1 from public.documents d where d.client_id = p_id and d.retirado_el is null
                   and d.doc_type in ('passport', 'npwp', 'visa', 'proof_of_funds', 'proof_of_address', 'other')) then
    return false;
  end if;
  if exists (select 1 from public.documents d where d.client_id = p_id
               and (d.doc_type = 'signed_contract' or d.contrato_id is not null or d.reservation_id is not null)) then
    return false;
  end if;
  select greatest(c.created_at, c.kyc_verificado_el,
                  (select max(d.uploaded_at) from public.documents d where d.client_id = c.id),
                  (select max(cd.corregido_en) from public.correcciones_datos cd where cd.tabla = 'clients' and cd.fila_id = c.id))
    into v_ult from public.clients c where c.id = p_id;
  if v_ult is null or v_ult >= p_corte then return false; end if;
  -- ojo: la clave de cada tabla lleva su esquema ('public.documents'); la de contratos sale sin él ('contratos')
  return (public._sc_referencias_cliente(p_id) - 'public.documents') = '{}'::jsonb;
end $$;
revoke all on function public._kyc_retencion_candidato(uuid, timestamptz) from public, anon, authenticated, service_role;

-- Sin parámetro de meses a propósito: lo manda config_instancia (mínimo 12 en código); sin la clave, no hace NADA.
-- Tope 20 por pasada, los más antiguos primero; el resto, en las noches siguientes (revisor, 13-oct: «no borrar
-- ninguno si hay más de 20» paraba la retención para siempre, porque la lista solo crece). Freno de anomalía: con más
-- de 100 candidatos no borra NINGUNO y lo devuelve como aviso (una regla de candidatos rota no vacía el archivo).
create or replace function public.kyc_retencion(p_dry boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cfg jsonb; v_meses int; v_corte timestamptz; v_cand uuid[] := '{}'; v_c uuid; v_estado text;
  v_rutas text[] := '{}'; v_esta text[]; v_n int; v_aplicados uuid[] := '{}'; v_total int;
  v_tipos constant text[] := array['passport', 'npwp', 'visa', 'proof_of_funds', 'proof_of_address', 'other'];
begin
  select c.valor into v_cfg from public.config_instancia c where c.clave = 'kyc_meses_retencion';
  if v_cfg is null or jsonb_typeof(v_cfg) <> 'number' then
    return jsonb_build_object('activa', false);
  end if;
  v_meses := greatest(12, floor((v_cfg #>> '{}')::numeric)::int);
  v_corte := now() - make_interval(months => v_meses);

  for v_c in
    select c.id from public.clients c
     where c.created_at < v_corte
       and exists (select 1 from public.documents d where d.client_id = c.id and d.retirado_el is null and d.doc_type = any (v_tipos))
     order by c.created_at, c.id
  loop
    if public._kyc_retencion_candidato(v_c, v_corte) then
      v_cand := v_cand || v_c;
      exit when cardinality(v_cand) > 100;
    end if;
  end loop;

  if cardinality(v_cand) > 100 then
    return jsonb_build_object('activa', true, 'meses', v_meses, 'aviso', 'mas_de_100_candidatos', 'candidatos', cardinality(v_cand),
                              'aplicados', 0, 'rutas', '[]'::jsonb);
  end if;
  v_total := cardinality(v_cand);
  v_cand := coalesce(v_cand[1:20], '{}');   -- ya vienen por antigüedad
  if coalesce(p_dry, true) then
    return jsonb_build_object('activa', true, 'meses', v_meses, 'dry', true, 'candidatos', v_total,
                              'clientes', to_jsonb(v_cand), 'quedan', v_total - cardinality(v_cand), 'aplicados', 0, 'rutas', '[]'::jsonb);
  end if;

  foreach v_c in array v_cand loop
    select c.kyc_status into v_estado from public.clients c where c.id = v_c for update;
    -- se vuelve a comprobar con la ficha bloqueada: algo pudo cambiar entre la lista y aquí
    if not public._kyc_retencion_candidato(v_c, v_corte) then continue; end if;
    with b as (
      delete from public.documents d
       where d.client_id = v_c and d.doc_type = any (v_tipos) and d.uploaded_at < v_corte
         and d.contrato_id is null and d.reservation_id is null
      returning d.storage_path)
    select coalesce(array_agg(b.storage_path) filter (where b.storage_path is not null), '{}'), count(*) into v_esta, v_n from b;
    if v_n = 0 then continue; end if;
    v_rutas := v_rutas || v_esta;
    v_aplicados := v_aplicados || v_c;
    insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
    values ('clients', v_c, 'documentos_kyc', null, v_n || ' documentos borrados por retención',
            'retención automática LAW-558 (12 meses sin reserva ni contrato)', 'retencion-automatica');
    if v_estado = 'verified' then
      update public.clients set kyc_status = 'submitted', kyc_verificado_por = null, kyc_verificado_el = null where id = v_c;
      insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
      values ('clients', v_c, 'kyc_status', 'verified', 'submitted', 'retención automática LAW-558: sin documentos KYC', 'retencion-automatica');
    end if;
  end loop;
  return jsonb_build_object('activa', true, 'meses', v_meses, 'dry', false, 'candidatos', v_total, 'quedan', v_total - cardinality(v_cand),
                            'aplicados', cardinality(v_aplicados), 'clientes', to_jsonb(v_aplicados), 'rutas', to_jsonb(v_rutas));
end $$;
revoke all on function public.kyc_retencion(boolean) from public, anon, authenticated;
grant execute on function public.kyc_retencion(boolean) to service_role;

-- ─── 10 bis. Registro de cada pasada y aviso si algo falla (revisor, 13-oct: «el 500 no lo lee nadie») ──────────────
-- Una fila por pasada (en seco o real) con solo recuentos: deja prueba de que el cron corre y de lo que hizo. Si la
-- pasada trae aviso o ficheros que no se pudieron borrar, correo al buzón de avisos del sistema (config_instancia
-- `email_avisos_sistema`), como mucho uno a la semana: uno cada noche se deja de leer.
create table if not exists public.kyc_retencion_pasadas (
  id bigint generated always as identity primary key,
  pasada_en timestamptz not null default now(),
  dry boolean not null,
  resumen jsonb not null,
  avisado boolean not null default false
);
alter table public.kyc_retencion_pasadas enable row level security;
revoke all on table public.kyc_retencion_pasadas from public, anon, authenticated;

create or replace function public.kyc_retencion_registra(p_resumen jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_mal boolean; v_avisa boolean := false; v_url text; v_to text;
begin
  if jsonb_typeof(p_resumen) is distinct from 'object' then raise exception 'resumen no válido' using errcode = '22023'; end if;
  v_mal := coalesce((p_resumen->>'ok')::boolean, false) is false;
  if v_mal and not exists (select 1 from public.kyc_retencion_pasadas p where p.avisado and p.pasada_en > now() - interval '7 days') then
    v_to := (select nullif(btrim(c.valor #>> '{}'), '') from public.config_instancia c
              where c.clave = 'email_avisos_sistema' and jsonb_typeof(c.valor) = 'string');
    v_url := coalesce((select nullif(btrim(c.valor #>> '{}'), '') from public.config_instancia c
                        where c.clave = 'url_envio_correo' and jsonb_typeof(c.valor) = 'string'),
                      'https://lawangproperties.com/contracts/api/send_email.php');
    if v_to is not null then
      begin
        perform net.http_post(
          url := v_url,
          headers := jsonb_build_object('Content-Type', 'application/json') || public._aviso_cabecera(),
          body := jsonb_build_object('to', v_to, 'subject', 'Aviso: la limpieza nocturna del archivo KYC no ha ido bien',
            'message', 'Aviso automático de la intranet. La pasada de kyc-retencion (borrado de copias KYC a los meses '
                       || 'fijados y limpieza de ficheros sueltos) ha terminado con un problema. Resumen (solo recuentos): '
                       || p_resumen::text || chr(10) || chr(10)
                       || 'Se revisa en kyc_retencion_pasadas. Este aviso sale como mucho una vez a la semana.',
            'attach', false));
        v_avisa := true;
      exception when others then v_avisa := false;   -- el aviso puede fallar; la fila de la pasada se guarda igual
      end;
    end if;
  end if;
  insert into public.kyc_retencion_pasadas (dry, resumen, avisado)
  values (coalesce((p_resumen->>'dry')::boolean, true), p_resumen, v_avisa);
end $$;
revoke all on function public.kyc_retencion_registra(jsonb) from public, anon, authenticated;
grant execute on function public.kyc_retencion_registra(jsonb) to service_role;

-- ─── 11. Secreto de la edge kyc-retencion (Vault, generado aquí dentro; nadie lo ha visto) ─────────────────────────
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'cron_kyc_retencion') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
      'cron_kyc_retencion',
      'Puerta de la edge kyc-retencion (LAW-558). Solo la leen cron_kyc_retencion_secret() y el job kyc-retencion-diario.');
  end if;
end $$;

create or replace function public.cron_kyc_retencion_secret()
returns text language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'cron_kyc_retencion';
$$;
revoke all on function public.cron_kyc_retencion_secret() from public, anon, authenticated;
grant execute on function public.cron_kyc_retencion_secret() to service_role;

-- ─── 12. Configuración de Lawang ───────────────────────────────────────────────────────────────────────────────────
-- 12 meses (decisión del owner LAW-558). `alta_exige_documento` NO se pone aquí: se enciende después de publicar el front.
insert into public.config_instancia (clave, valor, descripcion)
values ('kyc_meses_retencion', '12'::jsonb,
        'LAW-558: meses sin reserva ni contrato tras los que se borran las copias de los documentos KYC (mínimo 12). Sin esta clave no se borra nada.')
on conflict (clave) do nothing;
