-- F5 · «Por su cuenta» (encargo 20260930_lawang_equipos_venta_asistente, 30-sep-2026) — parte SERVIDOR.
-- Construido sobre los cuerpos VIVOS de contrato_guarda (md5 40542c55…), comisiones_evaluar_contrato (md5 418355c6…),
-- venta_propia_reclamar/resolver/retirar, volcados con pg_get_functiondef el 30-sep a las 07:18 UTC. comisiones_reconciliar
-- NO se toca (porte AXW-98 en curso): solo reconcilia bases de devengos que ya existen, no decide niveles.
--
-- QUÉ HACE
-- 1. contrato_guarda lee p_contrato->'venta' = {modo, origen, origen_texto} y lo escribe en contrato_closer (nunca en datos)
--    dentro de la misma transacción, vía _venta_modo_declara:
--    · ALTA NUEVA = contrato_guarda con p_id NULL y sin contrato padre. Es la única que puede quedar obligada a declarar.
--      Re-guardar una raíz que ya existe con modo NULL (las 188 viejas y las creadas antes de encender el interruptor) NO
--      bloquea ni declara nada: se ignora la clave 'venta' (D7, no se reatribuye nada pasado; un admin usa venta_modo_admin).
--    · INTERRUPTOR comisiones_interruptor.modo_obligatorio (APAGADO): apagado, un alta sin 'venta' queda con modo NULL como
--      hoy; encendido, un alta sin modo de un closer CON equipo da 22023, y la de un closer SIN equipo queda 'propia'
--      implícito (modo_declarado_por = 'sistema:sin_equipo'; el motor le paga la estándar de siempre, nivel 'estandar').
--      Si llega 'venta', se escribe siempre, esté o no encendido.
--    · Hijos (contrato_padre_id): la clave 'venta' se ignora; el motor ya lee el modo de la raíz. La respuesta de
--      contrato_guarda devuelve 'venta' con el modo de la raíz para que la pantalla lo muestre.
--    · 'equipo' solo si el closer tiene equipo congelado en la venta. 'propia' con equipo exige origen de lista cerrada
--      (contacto_personal | referido_cliente | redes_propias | otro, y 'otro' exige texto), pasa los cruces y abre la
--      ventana de objeción: modo_espera_hasta = now() + 7 días, fijado aquí (nada del navegador cuenta).
--    · Antes de firmar el closer puede cambiar el modo re-guardando (si no hay devengos vivos); tras firmar solo admin
--      (trigger candado _trg_contrato_closer_modo_candado, mismo criterio de «firmado» que contrato_guarda).
-- 2. Cruces (_venta_propia_cruces) por identidad normalizada (email lower, teléfono E.164, pasaporte alfanumérico en
--    mayúsculas) de los compradores del contrato (datos adqN_* + fichas de contrato_compradores). No existe tabla
--    lead_closer: la asignación vive en lead_estado (asignado_por, responsable) y su historia en lead_dueno_log (autor, a).
--    · BLOQUEO (23514): un lead del cliente que su SM le asignó (lead_estado.asignado_por = SM y responsable = closer, o
--      lead_dueno_log autor = SM y a = closer).
--    · AVISO (no bloquea): el cliente vino por un canal de Lawang (cualquier fila de leads: Meta, web, QR), o el lead o la
--      ficha del cliente son de otro miembro del equipo (o del SM). Se guardan en contrato_closer.modo_cruces.
-- 3. Objeción: reclamaciones_venta_propia gana tipo ('reclamacion' | 'objecion') y resolucion ('mantener_propia' |
--    'pasar_equipo' | 'closer_paso_a_equipo'). Estados de una objeción: pendiente (viva), rechazada (admin mantiene
--    «propia»), retirada (admin la pasa a equipo, o el closer lo hizo antes de firmar; la resolucion dice cuál). El CHECK
--    de estado no se toca (no_destruir bloquea quitarlo; no hace falta). Una objeción NUNCA es 'aprobada' (CHECK nuevo),
--    así que ningún lector viejo que busque 'aprobada' (motor legado, salud, comision_rol_asignar) la toma por venta
--    propia pagable. RPC venta_objecion_crear (SM,
--    motivo obligatorio, dentro de la ventana), venta_objecion_resolver (admin: mantener_propia | pasar_equipo),
--    venta_modo_admin (admin, tras firma), ventas_por_su_cuenta_equipo (lectura del SM, sin cifras).
--    Cambio de modo con comisiones: lo pendiente se anula; lo ya pagado por Lawang deja una diferencia NEGATIVA al MISMO
--    perceptor (se descuenta de un pago siguiente) y el devengo se anula para que el recálculo no lo vuelva a pagar;
--    aprobado sin pagar, en disputa o con diferencias abiertas → para y lo resuelve Administración.
-- 4. Motor: modo 'propia' con equipo → nivel 'propia' con la condición individual o la estándar vigente (equipo_id NULL,
--    nivel closer: 10 % desde 30-sep, 2,5 % antes), equipo 0, y EN ESPERA mientras la ventana siga abierta o haya
--    objeción viva. 'propia' sin equipo → 'estandar' (igual que hoy). 'equipo' → equipo congelado como hoy. NULL → hoy,
--    incluida la reclamación legada, ahora filtrada por tipo = 'reclamacion'.
--    Cron comisiones-fin-espera-propia (cada hora, :41) evalúa las ventas cuya ventana terminó en los últimos 3 días.
-- 5. Aviso al SM (campana + correo del cron existente): número, closer, origen y tipo de cruces; sin cifras ni datos
--    del cliente.
-- UNIQUE (contrato_raiz_id, tramo_id, beneficiario_email) cuenta los devengos anulados: un ida y vuelta propia→equipo→propia
-- no vuelve a devengar el mismo tramo al mismo beneficiario. Se acepta (lo corrige Administración a mano).

-- 0 · interruptor
alter table public.comisiones_interruptor add column modo_obligatorio boolean not null default false;
comment on column public.comisiones_interruptor.modo_obligatorio is
  'F5 (30-sep-2026): encendido, contrato_guarda exige declarar la venta (equipo / por su cuenta) en las altas de contratos raíz de closers con equipo. Apagado hasta que el formulario clásico y el asistente envíen el modo.';

-- 1 · cruces y ventana en contrato_closer
alter table public.contrato_closer
  add column modo_cruces jsonb,
  add column modo_espera_hasta timestamptz;
alter table public.contrato_closer
  add constraint contrato_closer_modo_origen_texto_largo check (modo_origen_texto is null or length(modo_origen_texto) <= 500),
  add constraint contrato_closer_modo_espera_solo_propia check (modo_espera_hasta is null or modo = 'propia');
comment on column public.contrato_closer.modo_cruces is
  'F5: resultado de los cruces por identidad al declarar «por su cuenta» (avisos: campana, lead_otro_miembro, ficha_otro_miembro). Lo lee el SM por ventas_por_su_cuenta_equipo(); sin grants directos.';
comment on column public.contrato_closer.modo_espera_hasta is
  'F5: fin de la ventana de objeción del SM (now() + 7 días, fijado por el servidor). Mientras no pase, o haya objeción viva, la comisión no devenga.';

-- 2 · reclamaciones_venta_propia → también la objeción del SM
alter table public.reclamaciones_venta_propia add column tipo text not null default 'reclamacion';
alter table public.reclamaciones_venta_propia
  add constraint reclamaciones_venta_propia_tipo_check check (tipo in ('reclamacion', 'objecion'));
alter table public.reclamaciones_venta_propia add column resolucion text;
alter table public.reclamaciones_venta_propia
  add constraint reclamaciones_venta_propia_resolucion_check
    check (resolucion is null or resolucion in ('mantener_propia', 'pasar_equipo', 'closer_paso_a_equipo')),
  add constraint reclamaciones_venta_propia_resolucion_solo_objecion check (resolucion is null or tipo = 'objecion'),
  add constraint reclamaciones_venta_propia_aprobada_solo_reclamacion check (estado <> 'aprobada' or tipo = 'reclamacion');
create unique index reclamaciones_venta_propia_objecion_viva
  on public.reclamaciones_venta_propia (contrato_raiz_id) where tipo = 'objecion' and estado = 'pendiente';
comment on column public.reclamaciones_venta_propia.tipo is
  'reclamacion = flujo legado del 24-sep (el closer reclama; aprobada = paga venta propia). objecion = F5: el SM objeta una venta declarada «por su cuenta»; pendiente = viva (la comisión espera), rechazada = admin mantiene «propia» (resolucion mantener_propia), retirada = la venta pasó a «equipo» (resolucion pasar_equipo si lo decidió admin, closer_paso_a_equipo si lo hizo el closer antes de firmar). Una objeción nunca es aprobada ni paga.';

-- 3 · normalizadores de identidad
create or replace function public._lw_email_norm(p text)
 returns text language sql immutable set search_path to ''
as $$ select case when position('@' in coalesce(p, '')) > 1 then lower(btrim(p)) end $$;

create or replace function public._lw_tel_e164(p text)
 returns text language plpgsql immutable set search_path to ''
as $$
declare v text := btrim(coalesce(p, '')); d text;
begin
  d := regexp_replace(v, '\D', '', 'g');
  if d = '' then return null; end if;
  if v !~ '^\+' then
    if d ~ '^00' then d := substr(d, 3);
    elsif d ~ '^0' then d := '62' || substr(d, 2);   -- número local indonesio
    end if;
  end if;
  if length(d) < 8 then return null; end if;
  return '+' || d;
end $$;

create or replace function public._lw_pasaporte_norm(p text)
 returns text language sql immutable set search_path to ''
as $$ select case when length(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g')) >= 5
                  then upper(regexp_replace(p, '[^A-Za-z0-9]', '', 'g')) end $$;

-- identidades normalizadas de los compradores de un contrato
create or replace function public._venta_identidades(p_contrato uuid)
 returns table(tipo text, valor text)
 language sql stable security definer set search_path to ''
as $$
  with f as (
    select coalesce(c.datos_fields, c.datos->'fields') as d from public.contratos c where c.id = p_contrato
  ), crudo as (
    select case when k ~ '_email$' then 'email' when k ~ '_telefono$' then 'tel' else 'pasaporte' end as t, f.d->>k as v
      from f, jsonb_object_keys(case when jsonb_typeof(f.d) = 'object' then f.d else '{}'::jsonb end) k
     where k ~ '^adq[0-9]+_(email|telefono|pasaporte)$'
    union all
    select x.t, x.v
      from public.contrato_compradores cc
      join public.clients cl on cl.id = cc.client_id
      cross join lateral (values ('email', cl.email), ('tel', cl.phone), ('pasaporte', cl.passport_number)) x(t, v)
     where cc.contrato_id = p_contrato
  )
  select distinct n.t, n.v from (
    select c.t, case c.t when 'email' then public._lw_email_norm(c.v)
                         when 'tel' then public._lw_tel_e164(c.v)
                         else public._lw_pasaporte_norm(c.v) end as v
      from crudo c
  ) n where n.v is not null
$$;

-- 4 · cruces de «por su cuenta»
create or replace function public._venta_propia_cruces(p_contrato uuid, p_closer text, p_equipo uuid, p_manager text)
 returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare
  v_closer text := lower(coalesce(p_closer, ''));
  v_sm     text := lower(coalesce(p_manager, ''));
  v_otros  text[];
  v_emails text[]; v_tels text[]; v_pas text[];
  v_leads  uuid[];
  v_bloq   jsonb; v_avisos jsonb;
begin
  select coalesce(array_agg(i.valor) filter (where i.tipo = 'email'), '{}'),
         coalesce(array_agg(i.valor) filter (where i.tipo = 'tel'), '{}'),
         coalesce(array_agg(i.valor) filter (where i.tipo = 'pasaporte'), '{}')
    into v_emails, v_tels, v_pas
    from public._venta_identidades(p_contrato) i;

  -- el equipo de hoy (miembros activos + SM), sin el propio closer
  select coalesce(array_agg(distinct x.e), '{}') into v_otros from (
    select lower(em.closer_email) as e from public.equipo_miembros em
     where em.equipo_id = p_equipo and em.desde <= current_date and (em.hasta is null or em.hasta >= current_date)
    union select v_sm
  ) x where x.e <> '' and x.e <> v_closer;

  select coalesce(array_agg(l.id), '{}') into v_leads from public.leads l
   where public._lw_email_norm(l.email) = any(v_emails) or public._lw_tel_e164(l.whatsapp) = any(v_tels);

  -- BLOQUEO: lead que su SM le asignó a él
  select coalesce(jsonb_agg(distinct jsonb_build_object('lead_id', b.lead_id)), '[]'::jsonb) into v_bloq from (
    select le.lead_id from public.lead_estado le
     where v_sm <> '' and le.lead_id = any(v_leads)
       and lower(coalesce(le.asignado_por, '')) = v_sm and lower(coalesce(le.responsable, '')) = v_closer
    union
    select ld.lead_id from public.lead_dueno_log ld
     where v_sm <> '' and ld.lead_id = any(v_leads)
       and lower(coalesce(ld.autor, '')) = v_sm and lower(coalesce(ld.a, '')) = v_closer
  ) b;

  -- AVISOS
  select coalesce(jsonb_agg(a.j order by a.j->>'tipo'), '[]'::jsonb) into v_avisos from (
    select jsonb_build_object('tipo', 'campana', 'lead_id', l.id, 'source', l.source) as j
      from public.leads l where l.id = any(v_leads)
    union all
    select jsonb_build_object('tipo', 'lead_otro_miembro', 'lead_id', le.lead_id, 'de', lower(le.responsable))
      from public.lead_estado le
     where le.lead_id = any(v_leads) and lower(coalesce(le.responsable, '')) = any(v_otros)
    union all
    select jsonb_build_object('tipo', 'ficha_otro_miembro', 'client_id', cl.id, 'de', lower(cl.propietario))
      from public.clients cl
     where lower(coalesce(cl.propietario, '')) = any(v_otros)
       and (public._lw_email_norm(cl.email) = any(v_emails)
            or public._lw_tel_e164(cl.phone) = any(v_tels)
            or public._lw_pasaporte_norm(cl.passport_number) = any(v_pas))
  ) a;

  return jsonb_build_object('bloqueo', jsonb_array_length(v_bloq) > 0, 'bloqueos', v_bloq, 'avisos', v_avisos,
                            'identidades', coalesce(array_length(v_emails, 1), 0) + coalesce(array_length(v_tels, 1), 0)
                                           + coalesce(array_length(v_pas, 1), 0),
                            'calculado_en', now());
end $$;

-- 5 · declarar el modo (lo llama contrato_guarda; sin EXECUTE para nadie más)
create or replace function public._venta_modo_declara(p_raiz uuid, p_venta jsonb, p_alta boolean)
 returns void language plpgsql security definer set search_path to ''
as $$
declare
  k          public.contrato_closer;
  v_yo       text := lower(coalesce(auth.email(), ''));
  v_modo     text;
  v_origen   text;
  v_texto    text;
  v_cruces   jsonb;
  v_espera   timestamptz;
  v_implic   boolean := false;
  v_num      text;
  v_avisos   text;
begin
  if p_venta is not null and jsonb_typeof(p_venta) not in ('object', 'null') then
    raise exception 'Venta: formato no válido' using errcode = '22023';
  end if;
  v_modo   := nullif(btrim(coalesce(p_venta->>'modo', '')), '');
  v_origen := nullif(btrim(coalesce(p_venta->>'origen', '')), '');
  v_texto  := nullif(btrim(coalesce(p_venta->>'origen_texto', '')), '');
  if v_modo is not null and v_modo not in ('equipo', 'propia') then
    raise exception 'La venta es «equipo» o «propia» (por tu cuenta)' using errcode = '22023';
  end if;
  if v_origen is not null and v_origen not in ('contacto_personal', 'referido_cliente', 'redes_propias', 'otro') then
    raise exception 'Origen no válido: contacto personal, referido de un cliente, redes propias u otro' using errcode = '22023';
  end if;
  if v_texto is not null and length(v_texto) > 500 then
    raise exception 'El origen admite como mucho 500 caracteres' using errcode = '22023';
  end if;

  select * into k from public.contrato_closer where contrato_id = p_raiz for update;
  if not found then return; end if;                 -- sin closer atribuido no hay comisión que decidir
  if not p_alta and k.modo is null then return; end if;  -- venta ya guardada sin modo: no se declara por aquí (D7)

  if v_modo is null then
    if not p_alta then return; end if;              -- re-guardado sin la clave: se conserva lo declarado
    if not coalesce((select i.modo_obligatorio from public.comisiones_interruptor i where i.id), false) then
      return;                                       -- interruptor apagado: como hoy (modo NULL)
    end if;
    if k.equipo_id is not null then
      raise exception 'Indica si la venta es con tu equipo o por tu cuenta' using errcode = '22023';
    end if;
    v_modo := 'propia'; v_implic := true;           -- sin equipo: por su cuenta implícito
  end if;

  if not p_alta then
    if v_modo = k.modo and v_origen is not distinct from k.modo_origen and v_texto is not distinct from k.modo_origen_texto then
      return;
    end if;
    if coalesce((select c.bloqueado from public.contratos c where c.id = p_raiz), false)
       or exists (select 1 from public.contrato_firmas f where f.contrato_id = p_raiz and f.estado = 'firmado') then
      raise exception 'La venta ya está firmada: el modo (equipo / por su cuenta) solo lo cambia un administrador' using errcode = '42501';
    end if;
    if exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id = p_raiz and d.estado <> 'anulada') then
      raise exception 'La venta ya tiene comisiones: el modo (equipo / por su cuenta) solo lo cambia un administrador' using errcode = '42501';
    end if;
  end if;

  if v_modo = 'equipo' then
    if k.equipo_id is null then
      raise exception 'No estás en ningún equipo de venta: esta venta es por tu cuenta' using errcode = '22023';
    end if;
    v_origen := null; v_texto := null; v_cruces := null; v_espera := null;
  elsif k.equipo_id is not null then
    if v_origen is null then
      raise exception 'Por tu cuenta: indica de dónde viene el cliente (contacto personal, referido de un cliente, redes propias u otro)' using errcode = '22023';
    end if;
    if v_origen = 'otro' and coalesce(length(v_texto), 0) < 3 then
      raise exception 'Por tu cuenta: explica de dónde viene el cliente' using errcode = '22023';
    end if;
    v_cruces := public._venta_propia_cruces(p_raiz, k.closer_email, k.equipo_id, k.manager_email);
    if coalesce((v_cruces->>'bloqueo')::boolean, false) then
      raise exception 'Este cliente es un lead que te asignó tu Sales Manager: la venta es del equipo, no por tu cuenta' using errcode = '23514';
    end if;
    v_espera := now() + interval '7 days';
  else
    if v_origen = 'otro' and v_texto is null then
      raise exception 'Por tu cuenta: explica de dónde viene el cliente' using errcode = '22023';
    end if;
    v_cruces := null; v_espera := null;             -- sin equipo nadie objeta
  end if;

  update public.contrato_closer
     set modo = v_modo, modo_origen = v_origen, modo_origen_texto = v_texto,
         modo_declarado_por = case when v_implic then 'sistema:sin_equipo' else nullif(v_yo, '') end,
         modo_declarado_en = now(), modo_cruces = v_cruces, modo_espera_hasta = v_espera
   where contrato_id = p_raiz;

  if v_modo = 'equipo' then
    update public.reclamaciones_venta_propia
       set estado = 'retirada', resolucion = 'closer_paso_a_equipo', resuelto_por = 'sistema', resuelto_en = now(),
           motivo_resolucion = 'el closer pasó la venta a «equipo» antes de firmar'
     where contrato_raiz_id = p_raiz and tipo = 'objecion' and estado = 'pendiente';
  end if;

  -- aviso al SM: sin cifras ni datos del cliente (se envía también por correo)
  if v_modo = 'propia' and k.equipo_id is not null and nullif(btrim(coalesce(k.manager_email, '')), '') is not null
     and lower(k.manager_email) <> lower(k.closer_email) then
    select c.numero into v_num from public.contratos c where c.id = p_raiz;
    select string_agg(distinct case a->>'tipo'
             when 'campana' then 'el cliente ya estaba en los leads de campañas de Lawang'
             when 'lead_otro_miembro' then 'el lead lo llevaba otra persona de tu equipo'
             when 'ficha_otro_miembro' then 'la ficha del cliente la creó otra persona de tu equipo' end, '; ')
      into v_avisos from jsonb_array_elements(coalesce(v_cruces->'avisos', '[]'::jsonb)) a;
    insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace, email_pendiente)
    values ('venta_por_su_cuenta',
            'Venta por su cuenta · ' || coalesce(v_num, '?'),
            lower(k.closer_email) || ' marca la venta ' || coalesce(v_num, '?') || ' como suya, sin el equipo (origen: '
              || case v_origen when 'contacto_personal' then 'contacto personal' when 'referido_cliente' then 'referido de un cliente'
                               when 'redes_propias' then 'redes propias' else 'otro' end || '). '
              || case when v_avisos is not null then 'Atención: ' || v_avisos || '. ' else 'Sin coincidencias en leads ni fichas del equipo. ' end
              || 'Puedes objetar hasta el ' || to_char(v_espera at time zone 'Asia/Makassar', 'DD-MM-YYYY HH24:MI') || ' (hora de Bali).',
            lower(k.manager_email), p_raiz, '/intranet/v4/equipos-venta/', true);
  end if;
end $$;

-- 6 · candado: tras firmar, solo admin cambia el modo
create or replace function public._trg_contrato_closer_modo_candado()
 returns trigger language plpgsql security definer set search_path to ''
as $$
begin
  if (old.modo, old.modo_origen, old.modo_origen_texto) is not distinct from (new.modo, new.modo_origen, new.modo_origen_texto) then
    return new;
  end if;
  if coalesce(current_setting('app.via_modo_admin', true), '') = 'on' then
    return new;
  end if;
  if coalesce((select c.bloqueado from public.contratos c where c.id = new.contrato_id), false)
     or exists (select 1 from public.contrato_firmas f where f.contrato_id = new.contrato_id and f.estado = 'firmado') then
    raise exception 'La venta ya está firmada: el modo (equipo / por su cuenta) solo lo cambia un administrador' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger trg_contrato_closer_modo_candado
  before update of modo, modo_origen, modo_origen_texto on public.contrato_closer
  for each row execute function public._trg_contrato_closer_modo_candado();

-- 7 · aplicar un cambio de modo decidido por admin (objeción aceptada o venta_modo_admin)
create or replace function public._venta_modo_aplica(p_raiz uuid, p_modo text, p_motivo text)
 returns integer language plpgsql security definer set search_path to ''
as $$
declare
  k        public.contrato_closer;
  d        record;
  v_sp     public.solicitudes_pago;
  v_yo     text := lower(coalesce(auth.email(), ''));
  v_viejos text[];
  v_vig    numeric;
  v_dif    uuid;
  v_mot    text := 'Cambio de modo de la venta a «' || p_modo || '»: ' || coalesce(p_motivo, '');
begin
  if p_modo not in ('equipo', 'propia') then raise exception 'La venta es «equipo» o «propia»' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));
  select * into k from public.contrato_closer where contrato_id = p_raiz for update;
  if not found then raise exception 'Esa venta no tiene closer atribuido' using errcode = 'P0002'; end if;
  if p_modo = 'equipo' and k.equipo_id is null then
    raise exception 'Esta venta no es de ningún equipo: no puede pasar a «equipo»' using errcode = '22023';
  end if;

  -- lo que ya no toca con el modo nuevo
  v_viejos := case p_modo when 'equipo' then array['propia', 'estandar'] else array['manager', 'closer', 'setter', 'team_lead'] end;
  for d in select * from public.comisiones_devengadas cd
            where cd.contrato_raiz_id = p_raiz and cd.estado <> 'anulada' and cd.nivel = any(v_viejos)
            order by cd.created_at, cd.id loop
    if exists (select 1 from public.comisiones_diferencias x where x.devengo_id = d.id and x.estado in ('revisar', 'pendiente')) then
      raise exception 'Una comisión de esta venta tiene diferencias abiertas: resuélvelas antes de cambiar el modo' using errcode = '22023';
    end if;
    v_sp := null;
    if d.solicitud_id is not null then select * into v_sp from public.solicitudes_pago sp where sp.id = d.solicitud_id; end if;

    if d.estado = 'pendiente' and (v_sp.id is null or v_sp.estado in ('pendiente', 'rechazada', 'anulada')) then
      -- sin pagar: se anula (la solicitud pendiente arrastra su devengo, con rastro)
      if v_sp.estado = 'pendiente' then
        perform set_config('app.via_venta_propia', 'on', true);
        update public.solicitudes_pago set estado = 'anulada', motivo_ajuste = v_mot where id = v_sp.id;
        perform set_config('app.via_venta_propia', 'off', true);
      end if;
      if (select cd.estado from public.comisiones_devengadas cd where cd.id = d.id) <> 'anulada' then
        insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo)
        values ('comisiones_devengadas', d.id, 'anular', coalesce(d.importe_ajustado, d.importe), coalesce(d.importe_ajustado, d.importe),
                d.estado, 'anulada', v_mot);
        update public.comisiones_devengadas
           set estado = 'anulada', anulado_motivo = v_mot, anulado_por = auth.uid(), anulado_en = now()
         where id = d.id;
      end if;

    elsif d.estado = 'pagada' or v_sp.estado = 'pagada' then
      if d.nivel not in ('manager', 'estandar', 'propia') then
        raise exception 'Una comisión de equipo de esta venta ya la pagó el Sales Manager: ajústala a mano antes de cambiar el modo' using errcode = '22023';
      end if;
      -- ya pagado por Lawang: diferencia negativa al MISMO perceptor, nunca se reescribe lo pagado
      v_vig := coalesce(v_sp.importe, coalesce(d.importe_ajustado, d.importe))
             + coalesce((select sum(x.importe) from public.comisiones_diferencias x
                          where x.devengo_id = d.id and x.estado in ('pagada', 'compensada')), 0);
      if v_vig > 0 then
        perform set_config('app.via_recalculo_comision', 'on', true);
        insert into public.comisiones_diferencias (devengo_id, importe, importe_vigente, importe_nuevo, base_antes, base_despues,
                                                   motivo, estado, origen, provocado_por)
        values (d.id, -v_vig, v_vig, 0, nullif(d.disparado_por_snapshot->>'base_valor', '')::numeric,
                nullif(d.disparado_por_snapshot->>'base_valor', '')::numeric,
                v_mot || ' — ya estaba pagada: la diferencia se descuenta de un pago siguiente', 'pendiente',
                jsonb_build_object('tabla', 'contrato_closer', 'op', 'cambio_modo', 'contrato_id', p_raiz, 'modo', p_modo,
                                   'en', now(), 'quien', nullif(v_yo, '')),
                nullif(v_yo, ''))
        returning id into v_dif;
        insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
        values ('comisiones_diferencias', v_dif, 'diferencia', v_vig, 0, null, 'pendiente', v_mot, jsonb_build_object('devengo_id', d.id));
        perform set_config('app.via_recalculo_comision', 'off', true);
      end if;
      insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo)
      values ('comisiones_devengadas', d.id, 'anular', coalesce(d.importe_ajustado, d.importe), coalesce(d.importe_ajustado, d.importe),
              d.estado, 'anulada', v_mot || ' — pagada: se descuenta con una diferencia negativa');
      update public.comisiones_devengadas
         set estado = 'anulada', anulado_motivo = v_mot || ' — pagada: se descuenta con una diferencia negativa',
             anulado_por = auth.uid(), anulado_en = now()
       where id = d.id;

    else
      raise exception 'Una comisión de esta venta está aprobada sin pagar o en disputa: resuélvela en Solicitudes de pago antes de cambiar el modo' using errcode = '22023';
    end if;
  end loop;

  perform set_config('app.via_modo_admin', 'on', true);
  update public.contrato_closer
     set modo = p_modo,
         modo_origen = case when p_modo = 'propia' then k.modo_origen end,
         modo_origen_texto = case when p_modo = 'propia' then k.modo_origen_texto end,
         modo_espera_hasta = null,
         modo_declarado_por = nullif(v_yo, ''), modo_declarado_en = now()
   where contrato_id = p_raiz;
  perform set_config('app.via_modo_admin', 'off', true);

  return coalesce(public.comisiones_evaluar_contrato(p_raiz), 0);
end $$;

-- 8 · RPC del SM: objetar dentro de la ventana
create or replace function public.venta_objecion_crear(p_raiz uuid, p_motivo text)
 returns uuid language plpgsql security definer set search_path to ''
as $$
declare
  v_yo  text := lower(coalesce(auth.email(), ''));
  v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
  k     public.contrato_closer;
  v_id  uuid;
  v_num text;
begin
  if auth.uid() is null or v_yo = '' then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if v_mot is null then raise exception 'Explica por qué la venta es del equipo' using errcode = '22023'; end if;
  if length(v_mot) > 2000 then raise exception 'El motivo admite como mucho 2000 caracteres' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));
  select * into k from public.contrato_closer where contrato_id = p_raiz for update;
  if not found or k.modo is distinct from 'propia' or k.equipo_id is null then
    raise exception 'Esa venta no está marcada «por su cuenta» dentro de un equipo' using errcode = '22023';
  end if;
  if lower(coalesce(k.manager_email, '')) <> v_yo
     or not exists (select 1 from public.equipos_venta ev where ev.id = k.equipo_id and ev.activo and lower(ev.manager_email) = v_yo) then
    raise exception 'Solo el Sales Manager del equipo de esa venta puede objetar' using errcode = '42501';
  end if;
  if lower(k.closer_email) = v_yo then raise exception 'No puedes objetar tu propia venta' using errcode = '42501'; end if;
  if k.modo_espera_hasta is null or now() >= k.modo_espera_hasta then
    raise exception 'El plazo para objetar esta venta ya terminó' using errcode = '22023';
  end if;
  if exists (select 1 from public.reclamaciones_venta_propia r where r.contrato_raiz_id = p_raiz and r.tipo = 'objecion' and r.estado = 'pendiente') then
    raise exception 'Ya hay una objeción abierta en esta venta' using errcode = '23505';
  end if;

  insert into public.reclamaciones_venta_propia (contrato_raiz_id, solicitante_email, equipo_id, manager_email, motivo, tipo)
  values (p_raiz, v_yo, k.equipo_id, v_yo, v_mot, 'objecion')
  returning id into v_id;

  select c.numero into v_num from public.contratos c where c.id = p_raiz;
  insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace, email_pendiente)
  select 'venta_objecion', 'Objeción a una venta por su cuenta · ' || coalesce(v_num, '?'),
         'El Sales Manager ' || v_yo || ' objeta que la venta ' || coalesce(v_num, '?') || ' de ' || lower(k.closer_email)
           || ' sea por su cuenta. La comisión queda en espera hasta que la resuelva un administrador.',
         u.email, p_raiz, '/intranet/v4/comisiones/', true
    from public.usuarios u where u.activo and u.rol in ('admin', 'super_admin');
  return v_id;
end $$;

-- 9 · RPC de admin: resolver la objeción
create or replace function public.venta_objecion_resolver(p_id uuid, p_decision text, p_motivo text)
 returns integer language plpgsql security definer set search_path to ''
as $$
declare
  v_yo  text := lower(coalesce(auth.email(), ''));
  v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
  r     public.reclamaciones_venta_propia;
  k     public.contrato_closer;
  n     integer := 0;
  v_num text;
begin
  if auth.uid() is null or v_yo = '' then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_admin() and public.puede('comisiones_reparto')) then
    raise exception 'La objeción la resuelve un administrador' using errcode = '42501';
  end if;
  if v_mot is null then raise exception 'Resolver una objeción exige un motivo' using errcode = '22023'; end if;
  if p_decision not in ('mantener_propia', 'pasar_equipo') then
    raise exception 'Decisión: mantener_propia o pasar_equipo' using errcode = '22023';
  end if;
  select * into r from public.reclamaciones_venta_propia where id = p_id;
  if not found or r.tipo <> 'objecion' then raise exception 'No existe esa objeción' using errcode = 'P0002'; end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || r.contrato_raiz_id::text));
  select * into r from public.reclamaciones_venta_propia where id = p_id for update;
  if r.estado <> 'pendiente' then raise exception 'Esta objeción ya está %', r.estado using errcode = '22023'; end if;
  select * into k from public.contrato_closer where contrato_id = r.contrato_raiz_id;
  if lower(coalesce(k.closer_email, '')) = v_yo or lower(coalesce(r.manager_email, '')) = v_yo then
    raise exception 'Nadie resuelve una objeción de su propia venta o de su propio equipo' using errcode = '42501';
  end if;

  if p_decision = 'mantener_propia' then
    update public.reclamaciones_venta_propia
       set estado = 'rechazada', resolucion = 'mantener_propia', resuelto_por = v_yo, resuelto_en = now(), motivo_resolucion = v_mot
     where id = r.id;
    -- la decisión cierra la ventana: la venta devenga ya si toca
    update public.contrato_closer set modo_espera_hasta = least(coalesce(modo_espera_hasta, now()), now())
     where contrato_id = r.contrato_raiz_id and modo = 'propia';
    n := coalesce(public.comisiones_evaluar_contrato(r.contrato_raiz_id), 0);
  else
    update public.reclamaciones_venta_propia
       set estado = 'retirada', resolucion = 'pasar_equipo', resuelto_por = v_yo, resuelto_en = now(), motivo_resolucion = v_mot
     where id = r.id;
    n := public._venta_modo_aplica(r.contrato_raiz_id, 'equipo', 'objeción del Sales Manager aceptada: ' || v_mot);
  end if;

  select c.numero into v_num from public.contratos c where c.id = r.contrato_raiz_id;
  insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace, email_pendiente)
  select 'venta_objecion_resuelta', 'Objeción resuelta · ' || coalesce(v_num, '?'),
         'La venta ' || coalesce(v_num, '?') || case when p_decision = 'mantener_propia' then ' sigue siendo por su cuenta.' else ' pasa a ser del equipo.' end,
         x.e, r.contrato_raiz_id, '/intranet/v4/equipos-venta/', true
    from (select lower(r.manager_email) as e union select lower(k.closer_email)) x
   where nullif(x.e, '') is not null;
  return n;
end $$;

-- 10 · RPC de admin: cambiar el modo de una venta (tras firma, o para declarar una venta vieja)
create or replace function public.venta_modo_admin(p_raiz uuid, p_modo text, p_motivo text)
 returns integer language plpgsql security definer set search_path to ''
as $$
declare
  v_yo  text := lower(coalesce(auth.email(), ''));
  v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if auth.uid() is null or v_yo = '' then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_admin() and public.puede('comisiones_reparto')) then
    raise exception 'El modo de una venta ya firmada lo cambia un administrador' using errcode = '42501';
  end if;
  if v_mot is null then raise exception 'Cambiar el modo exige un motivo' using errcode = '22023'; end if;
  if not exists (select 1 from public.contratos c where c.id = p_raiz and c.contrato_padre_id is null) then
    raise exception 'Esa venta no existe (o no es la raíz)' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.contrato_closer k where k.contrato_id = p_raiz and lower(k.closer_email) = v_yo) then
    raise exception 'Nadie cambia el modo de su propia venta' using errcode = '42501';
  end if;
  if exists (select 1 from public.reclamaciones_venta_propia r where r.contrato_raiz_id = p_raiz and r.tipo = 'objecion' and r.estado = 'pendiente') then
    raise exception 'Esta venta tiene una objeción abierta: resuélvela primero' using errcode = '22023';
  end if;
  return public._venta_modo_aplica(p_raiz, p_modo, v_mot);
end $$;

-- 11 · lectura del SM (bandeja de F6): sin cifras
create or replace function public.ventas_por_su_cuenta_equipo()
 returns table(raiz_id uuid, numero text, closer_email text, origen text, origen_texto text, declarado_en timestamptz,
               espera_hasta timestamptz, cruces jsonb, objecion_id uuid, objecion_estado text, objecion_decision text,
               objecion_motivo text, objecion_resolucion text)
 language sql stable security definer set search_path to ''
as $$
  select k.contrato_id, c.numero, lower(k.closer_email), k.modo_origen, k.modo_origen_texto, k.modo_declarado_en,
         k.modo_espera_hasta, k.modo_cruces, o.id, o.estado, o.resolucion, o.motivo, o.motivo_resolucion
    from public.contrato_closer k
    join public.contratos c on c.id = k.contrato_id
    left join lateral (select r.* from public.reclamaciones_venta_propia r
                        where r.contrato_raiz_id = k.contrato_id and r.tipo = 'objecion'
                        order by (r.estado = 'pendiente') desc, r.creado_en desc limit 1) o on true
   where k.modo = 'propia' and k.equipo_id is not null
     and coalesce(auth.email(), '') <> ''
     and (lower(coalesce(k.manager_email, '')) = lower(auth.email())
          or (public.es_admin() and public.puede('comisiones_reparto')))
   order by k.modo_declarado_en desc nulls last
$$;

-- 12 · fin de la ventana: evalúa las ventas cuya espera terminó (cron)
create or replace function public._ventas_propia_fin_espera()
 returns integer language plpgsql security definer set search_path to ''
as $$
declare r record; n integer := 0;
begin
  for r in select k.contrato_id from public.contrato_closer k
            where k.modo = 'propia' and k.modo_espera_hasta <= now() and k.modo_espera_hasta > now() - interval '3 days'
              and not exists (select 1 from public.reclamaciones_venta_propia x
                               where x.contrato_raiz_id = k.contrato_id and x.tipo = 'objecion' and x.estado = 'pendiente')
            order by k.contrato_id loop
    begin
      n := n + coalesce(public.comisiones_evaluar_contrato(r.contrato_id), 0);
    exception when others then
      update public.comisiones_interruptor
         set ultimo_error = 'fin de espera por su cuenta: ' || sqlerrm || ' (contrato ' || r.contrato_id || ')', ultimo_error_en = now()
       where id;
    end;
  end loop;
  return n;
end $$;
select cron.schedule('comisiones-fin-espera-propia', '41 * * * *', 'select public._ventas_propia_fin_espera()');

-- 13 · reclamación legada: no aplica a ventas con modo, y el resolver viejo no toca objeciones
create or replace function public.venta_propia_reclamar(p_raiz uuid, p_motivo text)
 returns uuid language plpgsql security definer set search_path to ''
as $function$
declare
  v_yo  text := lower(coalesce(auth.email(), ''));
  v_eq  record;
  v_id  uuid;
begin
  if v_yo = '' then raise exception 'sesión sin identidad' using errcode = '42501'; end if;
  if nullif(btrim(coalesce(p_motivo, '')), '') is null then
    raise exception 'explica por qué es venta tuya (de dónde viene el cliente)' using errcode = '22023';
  end if;
  if not exists (select 1 from public.contratos c where c.id = p_raiz and c.contrato_padre_id is null) then
    raise exception 'esa venta no existe (o no es la raíz)' using errcode = 'P0002';
  end if;
  -- F5: una venta que ya declara equipo / por su cuenta no pasa por la reclamación antigua
  if exists (select 1 from public.contrato_closer k where k.contrato_id = p_raiz and k.modo is not null) then
    raise exception 'esta venta ya declara si es de equipo o por tu cuenta: la reclamación antigua no aplica' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_raiz::text, 2));
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));

  select * into v_eq from public._equipo_de_venta(p_raiz);
  if v_eq.closer_email is distinct from v_yo then
    raise exception 'solo el closer atribuido de la venta puede reclamarla como propia' using errcode = '42501';
  end if;
  if v_eq.equipo_id is null then
    raise exception 'esta venta no es de ningún equipo: ya cobras la comisión estándar' using errcode = '22023';
  end if;
  if v_eq.manager_email = v_yo then
    raise exception 'eres el manager de este equipo: tu venta ya cobra la fee de manager' using errcode = '22023';
  end if;
  if exists (select 1 from public.reclamaciones_venta_propia r
              where r.contrato_raiz_id = p_raiz and r.estado in ('pendiente', 'aprobada')) then
    raise exception 'esta venta ya tiene una reclamación abierta o aprobada' using errcode = '23505';
  end if;

  insert into public.reclamaciones_venta_propia (contrato_raiz_id, solicitante_email, equipo_id, manager_email, motivo)
  values (p_raiz, v_yo, v_eq.equipo_id, v_eq.manager_email, btrim(p_motivo))
  returning id into v_id;
  return v_id;
end $function$;

create or replace function public.venta_propia_resolver(p_id uuid, p_aprobar boolean, p_motivo text)
 returns integer language plpgsql security definer set search_path to ''
as $function$
declare
  v_yo     text := lower(coalesce(auth.email(), ''));
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  r        public.reclamaciones_venta_propia;
  v_closer text;
  d        record;
  n        integer := 0;
begin
  if v_yo = '' then raise exception 'sesión sin identidad' using errcode = '42501'; end if;
  select * into r from public.reclamaciones_venta_propia where id = p_id;
  if not found then raise exception 'no existe esa reclamación' using errcode = 'P0002'; end if;
  -- F5: una objeción del SM la resuelve un administrador con venta_objecion_resolver (nunca paga)
  if r.tipo <> 'reclamacion' then
    raise exception 'es una objeción del Sales Manager: la resuelve un administrador desde Comisiones' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(r.contrato_raiz_id::text, 2));
  perform pg_advisory_xact_lock(hashtext('comisiones:' || r.contrato_raiz_id::text));
  select * into r from public.reclamaciones_venta_propia where id = p_id for update;

  if r.estado <> 'pendiente' then
    raise exception 'esta reclamación ya está %', r.estado using errcode = '22023';
  end if;
  if not (lower(r.manager_email) = v_yo or (public.es_admin() and public.puede('comisiones_reparto'))) then
    raise exception 'la resuelve el manager del equipo o un administrador' using errcode = '42501';
  end if;
  if lower(r.solicitante_email) = v_yo then
    raise exception 'nadie resuelve su propia reclamación' using errcode = '42501';
  end if;

  if not p_aprobar then
    if v_motivo is null then raise exception 'rechazar exige un motivo' using errcode = '22023'; end if;
    update public.reclamaciones_venta_propia
       set estado = 'rechazada', resuelto_por = v_yo, resuelto_en = now(), motivo_resolucion = v_motivo
     where id = r.id;
    return 0;
  end if;

  -- sigue siendo el mismo closer que reclamó
  select lower(k.closer_email) into v_closer from public.contrato_closer k where k.contrato_id = r.contrato_raiz_id;
  if v_closer is distinct from lower(r.solicitante_email) then
    raise exception 'el closer de esta venta ha cambiado desde que se pidió: no se aprueba' using errcode = '22023';
  end if;
  -- nada del equipo ya aprobado, pagado o en disputa
  if exists (
       select 1 from public.comisiones_devengadas cd
         left join public.solicitudes_pago sp on sp.id = cd.solicitud_id
        where cd.contrato_raiz_id = r.contrato_raiz_id
          and cd.estado <> 'anulada'
          and (cd.estado in ('pagada', 'en_disputa') or sp.estado in ('aprobada', 'pagada'))) then
    raise exception 'hay comisiones de esta venta ya aprobadas, pagadas o en disputa: la venta propia la resuelve Administración a mano' using errcode = '22023';
  end if;

  update public.reclamaciones_venta_propia
     set estado = 'aprobada', resuelto_por = v_yo, resuelto_en = now(), motivo_resolucion = v_motivo
   where id = r.id;

  -- anula lo del equipo que estuviera pendiente (con rastro)
  perform set_config('app.via_venta_propia', 'on', true);
  update public.solicitudes_pago sp
     set estado = 'anulada', motivo_ajuste = 'Venta propia aprobada de ' || r.solicitante_email
   where sp.estado = 'pendiente'
     and sp.id in (select cd.solicitud_id from public.comisiones_devengadas cd
                    where cd.contrato_raiz_id = r.contrato_raiz_id and cd.nivel = 'manager' and cd.solicitud_id is not null);
  perform set_config('app.via_venta_propia', 'off', true);

  for d in select * from public.comisiones_devengadas cd
            where cd.contrato_raiz_id = r.contrato_raiz_id and cd.estado = 'pendiente'
              and cd.nivel in ('manager', 'closer', 'setter', 'team_lead') loop
    insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo)
    values ('comisiones_devengadas', d.id, 'anular', coalesce(d.importe_ajustado, d.importe), coalesce(d.importe_ajustado, d.importe),
            d.estado, 'anulada', 'Venta propia aprobada de ' || r.solicitante_email);
    update public.comisiones_devengadas
       set estado = 'anulada', anulado_motivo = 'Venta propia aprobada de ' || r.solicitante_email,
           anulado_por = auth.uid(), anulado_en = now()
     where id = d.id;
  end loop;

  n := public.comisiones_evaluar_contrato(r.contrato_raiz_id);
  return coalesce(n, 0);
end $function$;

create or replace function public.venta_propia_retirar(p_id uuid)
 returns void language plpgsql security definer set search_path to ''
as $function$
declare v_yo text := lower(coalesce(auth.email(), ''));
begin
  update public.reclamaciones_venta_propia
     set estado = 'retirada', resuelto_por = v_yo, resuelto_en = now()
   where id = p_id and estado = 'pendiente' and lower(solicitante_email) = v_yo and tipo = 'reclamacion';
  if not found then
    raise exception 'solo quien la pidió retira una reclamación pendiente' using errcode = '42501';
  end if;
end $function$;

-- 14 · contrato_guarda (cuerpo vivo + la clave 'venta')
CREATE OR REPLACE FUNCTION public.contrato_guarda(p_id uuid, p_contrato jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_datos  jsonb := p_contrato->'datos';
  v_f      jsonb;
  v_tipo   text  := nullif(btrim(coalesce(p_contrato->>'tipo', '')), '');
  v_nrv    text;
  v_poa    text;
  v_padre  uuid;
  v_proy   text;
  v_comp   text;
  v_fecha  date;
  v_precio numeric;
  v_old    public.contratos%rowtype;
  v_row    public.contratos%rowtype;
  v_firmado boolean;
  v_venta  jsonb := p_contrato->'venta';   -- F5: {modo, origen, origen_texto}; solo cuenta en raíces
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_agente() and public.puede('contratos')) then
    raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
  end if;
  if v_datos is null or jsonb_typeof(v_datos) <> 'object' or jsonb_typeof(v_datos->'fields') <> 'object' then
    raise exception 'Contrato sin datos' using errcode = '22023';
  end if;
  if v_tipo is null then raise exception 'Contrato sin tipo' using errcode = '22023'; end if;
  v_f := v_datos->'fields';

  -- contrato padre, con la regla de la pantalla (VINCULABLES / VINCULABLES_POA): la reserva vinculada si
  -- es una Reserva de Parcela, o en un Poder el contrato (no Poder) al que acompaña; solo entre los que
  -- quien guarda puede ver. Un número que no casa no vincula.
  v_nrv := nullif(btrim(v_f->>'num_reserva_vinculada'), '');
  v_poa := nullif(btrim(v_f->>'poa_hs_vinculado'), '');
  if v_nrv is not null then
    select c.id into v_padre from public.contratos c
     where c.numero = v_nrv and c.tipo = 'reserva_parcela' and public.puede_ver_contrato(c.id) limit 1;
  end if;
  if v_padre is null and v_poa is not null then
    select c.id into v_padre from public.contratos c
     where c.numero = v_poa and c.tipo <> 'poa' and public.puede_ver_contrato(c.id) limit 1;
  end if;
  v_proy := nullif(btrim(v_f->>'proyecto_nombre'), '');
  if v_proy is null and v_poa is not null then
    select c.proyecto_nombre into v_proy from public.contratos c
     where c.numero = v_poa and c.tipo <> 'poa' and public.puede_ver_contrato(c.id) limit 1;
  end if;
  v_comp := coalesce(public.contrato_nombres_compradores(v_datos),
                     nullif(btrim(v_f->>'adq1_nombre'), ''), nullif(btrim(v_f->>'partner_nombre'), ''),
                     nullif(btrim(v_f->>'colaborador_nombre'), ''));
  begin
    v_fecha := nullif(btrim(coalesce(v_f->>'fecha_firma', '')), '')::date;
  exception when others then
    raise exception 'Rellena: la fecha de firma no es una fecha válida' using errcode = '22007';
  end;
  v_precio := public.lw_parse_importe(v_f->>'precio_total');

  if p_id is null then
    -- calendario de pagos de Construcción: lo monta el servidor (20260928052131)
    if v_tipo = 'construccion' then
      v_datos := public.contrato_calendario_aplica(v_datos, null, v_precio, v_fecha, null);
    end if;
    -- alta: la policy «agentes o su manager insertan contratos» se comprueba con la fila final, porque
    -- proyecto_id lo fijan los triggers (si no pasa, se deshace el alta entera)
    insert into public.contratos (tipo, comprador_nombre, proyecto_nombre, precio_total, moneda, fecha_firma,
                                  contrato_padre_id, unidad_id, datos)
    values (v_tipo, v_comp, v_proy, v_precio, nullif(btrim(v_f->>'moneda'), ''), v_fecha, v_padre,
            case when p_contrato ? 'unidad_id' then nullif(p_contrato->>'unidad_id', '')::uuid end, v_datos)
    returning * into v_row;
    if not (public.puede_proyecto_de(v_row.datos, v_row.proyecto_nombre, v_row.proyecto_id)
            or public.es_manager_de(v_row.proyecto_id)) then
      raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
    end if;
    -- F5: el modo de la venta (equipo / por su cuenta) se declara en el alta de la raíz, en contrato_closer
    if v_row.contrato_padre_id is null then
      perform public._venta_modo_declara(v_row.id, v_venta, true);
    end if;
  else
    select * into v_old from public.contratos c where c.id = p_id for update;
    if not found then raise exception 'Ese contrato ya no existe' using errcode = 'P0002'; end if;
    -- mismo mensaje que el trigger contrato_no_editable_en_firma: el agente sabe qué hacer
    if not public.es_super_admin() and (coalesce(v_old.bloqueado, false) or public.contrato_firma_viva(v_old.id)) then
      raise exception 'Contrato enviado a firma: usa «Editar (anula la firma)» para guardar cambios.' using errcode = '23514';
    end if;
    -- USING de la policy de UPDATE, con la fila de antes
    if not (public.es_super_admin()
            or (coalesce(v_old.bloqueado, false) = false and not public.contrato_firma_viva(v_old.id)
                and public.puede_ver_contrato(v_old.id)
                and public.puede_proyecto_de(jsonb_build_object('fields', v_old.datos_fields),
                                             v_old.proyecto_nombre, v_old.proyecto_id))) then
      raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
    end if;
    -- El padre solo cambia si el agente cambió el vínculo en el formulario. Los traspasos de carta y
    -- «carta colgada de su RP» lo fijan desde el servidor sin tocar `datos` (24 contratos el 26-sep):
    -- la pantalla vieja lo pisaba con null en cada guardado; el servidor no.
    if coalesce(v_nrv, '') || '|' || coalesce(v_poa, '')
       = coalesce(nullif(btrim(v_old.datos_fields->>'num_reserva_vinculada'), ''), '') || '|'
         || coalesce(nullif(btrim(v_old.datos_fields->>'poa_hs_vinculado'), ''), '') then
      v_padre := v_old.contrato_padre_id;
    end if;
    v_firmado := coalesce(v_old.bloqueado, false)
              or exists (select 1 from public.contrato_firmas f where f.contrato_id = p_id and f.estado = 'firmado');
    -- calendario de pagos de Construcción: lo monta el servidor, sobre el precio que se va a guardar. Un contrato
    -- firmado (solo lo guarda un super admin) conserva la tabla que se firmó (Datos, 28-sep)
    if v_tipo = 'construccion' and not v_firmado then
      v_datos := public.contrato_calendario_aplica(v_datos, v_old.datos,
                                                   case when v_firmado then v_old.precio_total else v_precio end,
                                                   v_fecha, p_id);
    end if;
    update public.contratos c
       set tipo = v_tipo, comprador_nombre = v_comp, proyecto_nombre = v_proy,
           precio_total = case when v_firmado then c.precio_total else v_precio end,
           moneda = nullif(btrim(v_f->>'moneda'), ''), fecha_firma = v_fecha,
           contrato_padre_id = v_padre,
           unidad_id = case when p_contrato ? 'unidad_id' then nullif(p_contrato->>'unidad_id', '')::uuid else c.unidad_id end,
           datos = v_datos
     where c.id = p_id
    returning * into v_row;
    -- WITH CHECK de la policy, con la fila de después
    if not (public.es_super_admin()
            or (public.puede_ver_contrato(v_row.id)
                and public.puede_proyecto_de(v_row.datos, v_row.proyecto_nombre, v_row.proyecto_id))) then
      raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
    end if;
    -- F5: una raíz que ya declaró su modo puede cambiarlo antes de firmar; las guardadas sin modo no se tocan
    if v_row.contrato_padre_id is null then
      perform public._venta_modo_declara(v_row.id, v_venta, false);
    end if;
  end if;

  return jsonb_build_object('id', v_row.id, 'numero', v_row.numero, 'precio_total', v_row.precio_total, 'moneda', v_row.moneda,
                            'fields', v_row.datos->'fields', 'hitos', v_row.datos->'hitos',
                            'calendario', v_row.datos->'calendario',
                            'venta', (select jsonb_build_object('modo', k.modo, 'origen', k.modo_origen,
                                                                'espera_hasta', k.modo_espera_hasta)
                                        from public.contrato_closer k
                                       where k.contrato_id = coalesce(v_row.contrato_padre_id, v_row.id)));
end $function$;

-- 15 · motor (cuerpo vivo + modo de la venta). Cambios marcados «F5».
CREATE OR REPLACE FUNCTION public.comisiones_evaluar_contrato(p_contrato_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_raiz_id              uuid;
  v_raiz_creada          date;
  v_fecha_equipo         date;
  v_moneda               text;
  v_proyecto_id          uuid;
  v_contrato_firmado     boolean := false;
  v_obra_firmada         boolean := false;
  v_precio_total         numeric := 0;
  v_precio_suelo         numeric := 0;
  v_precio_construccion  numeric := 0;
  v_cobrado_suelo        numeric := 0;
  v_cobrado_obra         numeric := 0;
  v_cobrado_total        numeric := 0;
  v_closer_email         text;
  v_fecha_venta          date;
  v_equipo_id            uuid;
  v_manager_email        text;
  v_propia               public.reclamaciones_venta_propia;
  v_niveles              text[];
  v_ultimo_recibi_id     uuid;
  v_ultimo_recibi_en     timestamptz;
  v_nivel                text;
  v_beneficiario         text;
  v_condicion            record;
  v_tramo                record;
  v_base                 numeric;
  v_importe              numeric;
  v_devengo_id           uuid;
  v_sp_id                uuid;
  v_creado_por           uuid;
  v_concepto             text;
  v_creados              integer := 0;
  v_eq_cong              uuid;
  v_man_cong             text;
  v_congelado            boolean := false;
  v_modo                 text;          -- F5: equipo | propia | NULL (sin declarar: como hasta hoy)
  v_espera               timestamptz;   -- F5: fin de la ventana de objeción
  v_propia_modo          boolean := false;
begin
  if p_contrato_id is null then
    return 0;
  end if;

  select coalesce(c.contrato_padre_id, c.id) into v_raiz_id
    from public.contratos c
   where c.id = p_contrato_id;

  if v_raiz_id is null then
    return 0;
  end if;

  -- mismo lock que comision_recalcular y venta_propia_resolver
  perform pg_advisory_xact_lock(hashtext('comisiones:' || v_raiz_id::text));

  select c.moneda, c.proyecto_id, c.bloqueado, (c.created_at at time zone 'Asia/Makassar')::date
    into v_moneda, v_proyecto_id, v_contrato_firmado, v_raiz_creada
    from public.contratos c
   where c.id = v_raiz_id;

  -- la Carta de Reserva hija ya vale suelo + obra: no se suma otra vez (24-sep-2026)
  v_precio_total := public._comisiones_precio_total(v_raiz_id);

  v_obra_firmada := exists (
    select 1 from public.contratos h
     where h.contrato_padre_id = v_raiz_id and h.bloqueado
  );

  select coalesce(sum(u.precio_suelo), 0),
         coalesce(sum(u.precio_construccion), 0),
         coalesce(sum(cp.cobrado_suelo), 0),
         coalesce(sum(cp.cobrado_obra), 0)
    into v_precio_suelo, v_precio_construccion, v_cobrado_suelo, v_cobrado_obra
    from public.unidades u
    left join lateral public.unidad_parte_cobrada_interno(u.id) cp on true
   where u.contrato_id = v_raiz_id;

  v_cobrado_total := v_cobrado_suelo + v_cobrado_obra;

  select k.closer_email, k.fecha_venta into v_closer_email, v_fecha_venta
    from public.contrato_closer k
   where k.contrato_id = v_raiz_id;

  if v_closer_email is null then
    return 0;
  end if;

  -- una sola fecha de la venta para equipo y condicion: fecha_venta o creacion de la raiz en hora de Bali, la misma
  -- con la que _venta_congela_equipo congela (F2, 30-sep-2026; antes el equipo de una venta no congelada se buscaba a hoy)
  v_raiz_creada := coalesce(v_fecha_venta, v_raiz_creada);
  v_fecha_equipo := v_raiz_creada;

  select k.equipo_id, k.manager_email, (k.equipo_congelado_en is not null), k.modo, k.modo_espera_hasta
    into v_eq_cong, v_man_cong, v_congelado, v_modo, v_espera
    from public.contrato_closer k where k.contrato_id = v_raiz_id;
  if coalesce(v_congelado, false) then
    v_equipo_id := v_eq_cong;   -- equipo congelado en la venta (owner, 26-sep-2026)
  else
  select em.equipo_id into v_equipo_id
    from public.equipo_miembros em
    join public.equipos_venta ev on ev.id = em.equipo_id
   where lower(em.closer_email) = lower(v_closer_email)
     and ev.activo
     and em.desde <= v_fecha_equipo
     and (em.hasta is null or em.hasta >= v_fecha_equipo)
   order by em.created_at desc
   limit 1;
  end if;

  if v_proyecto_id is null or v_moneda is null then
    return 0;
  end if;

  -- F5: la reclamación legada (24-sep) solo cuenta en ventas sin modo declarado y nunca una objeción del SM
  if v_modo is null then
    select * into v_propia
      from public.reclamaciones_venta_propia r
     where r.contrato_raiz_id = v_raiz_id and r.estado = 'aprobada' and r.tipo = 'reclamacion';
  end if;

  if v_modo = 'propia' and v_equipo_id is not null then
    -- F5: por su cuenta dentro de un equipo: en espera mientras dure la ventana de objeción o haya objeción viva;
    -- después cobra el closer la condición individual o la estándar vigente, y el equipo 0
    if (v_espera is not null and v_espera > now())
       or exists (select 1 from public.reclamaciones_venta_propia r
                   where r.contrato_raiz_id = v_raiz_id and r.tipo = 'objecion' and r.estado = 'pendiente') then
      return 0;
    end if;
    if not public.crm_usuario_activo(v_closer_email) then
      return 0;
    end if;
    v_propia_modo := true;
    v_niveles := array['propia'];
  elsif v_modo = 'propia' then
    -- F5: por su cuenta sin equipo = la estándar de siempre
    if not public.crm_usuario_activo(v_closer_email) then
      return 0;
    end if;
    v_niveles := array['estandar'];
  elsif v_propia.id is not null then
    -- venta propia aprobada: solo cobra quien la reclamó, con la condición de manager de SU equipo
    if lower(v_propia.solicitante_email) <> lower(v_closer_email) then
      return 0;
    end if;
    v_equipo_id := v_propia.equipo_id;
    v_niveles := array['propia'];
  elsif v_equipo_id is not null then
    if coalesce(v_congelado, false) then
      v_manager_email := v_man_cong;   -- manager congelado en la venta
    else
      select ev.manager_email into v_manager_email from public.equipos_venta ev where ev.id = v_equipo_id;
    end if;
    v_niveles := array['manager', 'closer', 'setter', 'team_lead'];
  else
    if not public.crm_usuario_activo(v_closer_email) then
      return 0;
    end if;
    v_niveles := array['estandar'];
  end if;

  select r.id, r.created_at
    into v_ultimo_recibi_id, v_ultimo_recibi_en
    from public.facturas r
   where r.tipo = 'recibi'
     and not coalesce(r.anulada, false)
     and (
       r.contrato_id = v_raiz_id
       or r.contrato_id in (select h.id from public.contratos h where h.contrato_padre_id = v_raiz_id)
       or exists (
            select 1
              from public.recibi_aplicaciones ra
              join public.facturas f on f.id = ra.factura_id
             where ra.recibi_id = r.id
               and not coalesce(f.anulada, false)
               and (f.contrato_id = v_raiz_id
                    or f.contrato_id in (select h.id from public.contratos h where h.contrato_padre_id = v_raiz_id))
          )
     )
   order by r.created_at desc
   limit 1;

  if v_ultimo_recibi_id is null then
    return 0;
  end if;

  foreach v_nivel in array v_niveles
  loop
    v_beneficiario := null;

    if v_nivel in ('closer', 'setter', 'team_lead') then
      if v_nivel = 'closer' then
        v_beneficiario := v_closer_email;
      else
        select re.email into v_beneficiario
          from public.contrato_roles_equipo re
         where re.contrato_raiz_id = v_raiz_id and re.rol = v_nivel and re.equipo_id = v_equipo_id;
      end if;
      if v_beneficiario is null then
        continue;
      end if;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id = v_equipo_id
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and c.nivel = v_nivel
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_raiz_creada
         and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
         and lower(c.closer_email) = lower(v_beneficiario)
       order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;

      if not found then
        select * into v_condicion
          from public.condiciones_comision c
         where c.equipo_id = v_equipo_id
           and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
           and c.nivel = v_nivel
           and (c.activo or c.vigente_hasta is not null)
           and c.vigente_desde <= v_raiz_creada
           and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
           and c.closer_email is null
         order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
         limit 1;
      end if;

    elsif v_nivel = 'estandar' or (v_nivel = 'propia' and v_propia_modo) then
      -- F5: la venta por su cuenta dentro de un equipo cobra lo mismo que quien vende sin equipo
      v_beneficiario := v_closer_email;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id is null
         and c.nivel = 'closer'
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_raiz_creada
         and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and (c.closer_email is null or lower(c.closer_email) = lower(v_closer_email))
       order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;

    else
      -- 'manager' cobra el manager; 'propia' (reclamación legada) cobra el closer con esa misma condición
      v_beneficiario := case when v_nivel = 'propia' then v_closer_email else v_manager_email end;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id = v_equipo_id
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and c.nivel = 'manager'
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_raiz_creada
         and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
         and c.closer_email is null
       order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;
    end if;

    if v_condicion.id is null or v_beneficiario is null then
      continue;
    end if;

    if v_condicion.base_calculo <> 'importe_fijo' and v_condicion.pct_comision = 0 then
      continue;
    end if;

    -- la primera condición que devenga manda (un override posterior no re-devenga)
    if exists (
      select 1 from public.comisiones_devengadas d
       where d.contrato_raiz_id = v_raiz_id
         and d.beneficiario_email = v_beneficiario
         and d.nivel = v_nivel
         and d.condicion_id <> v_condicion.id
    ) then
      continue;
    end if;

    v_base := case v_condicion.base_calculo
      when 'precio_total'        then v_precio_total
      when 'precio_suelo'        then v_precio_suelo
      when 'precio_construccion' then v_precio_construccion
      else null
    end;

    for v_tramo in
      select * from public.condicion_tramos
       where condicion_id = v_condicion.id
       order by orden
    loop
      if exists (
        select 1 from public.comisiones_devengadas d
         where d.contrato_raiz_id = v_raiz_id
           and d.tramo_id = v_tramo.id
           and d.beneficiario_email = v_beneficiario
      ) then
        continue;
      end if;

      -- como mucho un pago de Lawang vivo por tramo de la venta (manager | propia | estandar)
      if v_nivel in ('manager', 'estandar', 'propia') and exists (
        select 1 from public.comisiones_devengadas d
         where d.contrato_raiz_id = v_raiz_id
           and d.tramo_id = v_tramo.id
           and d.nivel in ('manager', 'estandar', 'propia')
           and d.estado <> 'anulada'
      ) then
        continue;
      end if;

      if not (case v_tramo.disparador_tipo
        when 'pct_cobrado_suelo' then
          v_precio_suelo > 0 and (v_cobrado_suelo / v_precio_suelo * 100) >= v_tramo.umbral
        when 'pct_cobrado_obra' then
          v_precio_construccion > 0 and (v_cobrado_obra / v_precio_construccion * 100) >= v_tramo.umbral
        when 'pct_cobrado_total' then public._comisiones_precio_total_todos(v_raiz_id) > 0 and (v_cobrado_total / public._comisiones_precio_total_todos(v_raiz_id) * 100) >= v_tramo.umbral
        when 'obra_firmada' then v_obra_firmada
        when 'contrato_firmado' then v_contrato_firmado
        else false
      end) then
        continue;
      end if;

      if v_condicion.base_calculo = 'importe_fijo' then
        v_importe := round(v_condicion.importe_fijo * v_tramo.pct_tramo / 100, 2);
      else
        if v_base is null then
          continue;
        end if;
        v_importe := round((v_condicion.pct_comision / 100) * v_base * (v_tramo.pct_tramo / 100), 2);
      end if;

      if coalesce(v_importe, 0) <= 0 then
        continue;
      end if;

      v_devengo_id := null;

      insert into public.comisiones_devengadas (
        contrato_raiz_id, tramo_id, condicion_id, beneficiario_email, nivel,
        importe, moneda, tipo_cambio_aplicado, disparado_por_snapshot
      ) values (
        v_raiz_id, v_tramo.id, v_condicion.id, v_beneficiario, v_nivel,
        v_importe, v_moneda, null,
        jsonb_build_object(
          'recibi_id', v_ultimo_recibi_id,
          'recibi_registrado_en', v_ultimo_recibi_en,
          'disparador_tipo', v_tramo.disparador_tipo,
          'umbral', v_tramo.umbral,
          'pct_tramo', v_tramo.pct_tramo,
          'base_calculo', v_condicion.base_calculo,
          'base_valor', v_base,
          'pct_comision', v_condicion.pct_comision,
          'vigente_desde', v_condicion.vigente_desde,
          'precio_total', v_precio_total,
          'precio_suelo', v_precio_suelo,
          'precio_construccion', v_precio_construccion,
          'cobrado_suelo', v_cobrado_suelo,
          'cobrado_obra', v_cobrado_obra,
          'cobrado_total', v_cobrado_total,
          'obra_firmada', v_obra_firmada,
          'contrato_firmado', v_contrato_firmado,
          'fecha_venta', v_fecha_venta,
          'equipo_id', case when v_propia_modo then null else v_equipo_id end,
          'reclamacion_id', v_propia.id,
          'modo', v_modo
        )
      )
      on conflict (contrato_raiz_id, tramo_id, beneficiario_email) do nothing
      returning id into v_devengo_id;

      if v_devengo_id is null then
        continue;
      end if;

      v_creados := v_creados + 1;

      if v_nivel in ('manager', 'estandar', 'propia') then
        v_creado_por := coalesce(
          auth.uid(),
          (select u.user_id from public.usuarios u where lower(u.email) = lower(v_beneficiario) and u.activo limit 1),
          (select u.user_id from public.usuarios u where lower(u.email) = lower(v_closer_email) and u.activo limit 1),
          (select u.user_id from public.usuarios u where u.rol = 'super_admin' and u.activo order by u.email limit 1)
        );

        v_concepto := 'Comisión ' || case v_nivel when 'manager' then 'manager' when 'propia' then 'venta propia' else 'estándar' end
          || ' — tramo ' || v_tramo.orden || ' (' || v_tramo.disparador_tipo
          || case when v_tramo.umbral is not null then ' ' || v_tramo.umbral || '%' else '' end || ')'
          || case when v_condicion.base_calculo = 'importe_fijo'
               then ' — importe fijo ' || v_condicion.importe_fijo
               else ' — ' || v_condicion.pct_comision || '% s/ ' || replace(v_condicion.base_calculo, '_', ' ')
                    || ' a fecha de disparo: ' || round(v_base, 2) || ' ' || v_moneda
             end
          || ' × ' || v_tramo.pct_tramo || '% del tramo — importe BRUTO (retención al pagar)';

        if v_creado_por is null then
          raise warning 'comisiones_evaluar_contrato: sin creado_por resoluble para la solicitud de % (raiz %) -- devengo % sin solicitud',
            v_beneficiario, v_raiz_id, v_devengo_id;
        else
          v_sp_id := null;
          begin
            insert into public.solicitudes_pago (
              contrato_id, concepto, importe, moneda, origen, beneficiario_email, creado_por
            ) values (
              v_raiz_id, v_concepto, v_importe, v_moneda, 'comision_automatica', v_beneficiario, v_creado_por
            )
            returning id into v_sp_id;

            update public.comisiones_devengadas
               set solicitud_id = v_sp_id
             where id = v_devengo_id;
          exception when others then
            raise warning 'comisiones_evaluar_contrato: fallo creando la solicitud de pago de % (raiz %, tramo %): % -- devengo % sin solicitud',
              v_beneficiario, v_raiz_id, v_tramo.id, sqlerrm, v_devengo_id;
          end;
        end if;
      end if;
    end loop;
  end loop;

  return v_creados;
end;
$function$;

-- 16 · exposición: solo las cuatro RPC con llamador (pantallas de F6/F7) para authenticated
revoke all on function public._lw_email_norm(text), public._lw_tel_e164(text), public._lw_pasaporte_norm(text),
  public._venta_identidades(uuid), public._venta_propia_cruces(uuid, text, uuid, text),
  public._venta_modo_declara(uuid, jsonb, boolean), public._venta_modo_aplica(uuid, text, text),
  public._ventas_propia_fin_espera(), public._trg_contrato_closer_modo_candado()
  from public, anon, authenticated;
revoke all on function public.venta_objecion_crear(uuid, text), public.venta_objecion_resolver(uuid, text, text),
  public.venta_modo_admin(uuid, text, text), public.ventas_por_su_cuenta_equipo()
  from public, anon;
grant execute on function public.venta_objecion_crear(uuid, text), public.venta_objecion_resolver(uuid, text, text),
  public.venta_modo_admin(uuid, text, text), public.ventas_por_su_cuenta_equipo()
  to authenticated;
