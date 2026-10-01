-- F5 · arreglos del revisor, migración 2 (30-sep-2026). Parte del cuerpo VIVO de cada función tras
-- 20260930080806_f5_cierra_puerta_venta. Sigue apagado el interruptor modo_obligatorio: nada de esto cambia el
-- comportamiento de hoy (0 filas de contrato_closer con modo); prepara F5 para cuando se encienda.
--
-- (2) Modo fijado por un administrador: nueva columna contrato_closer.modo_fijado_admin. La ponen a true
--     _venta_modo_aplica (venta_modo_admin y objeción «pasar_equipo») y venta_objecion_resolver «mantener_propia».
--     Con ella puesta, el closer ya no cambia el modo al re-guardar (_venta_modo_declara → 42501). Porqué: sin esto,
--     un closer deshacía la decisión del admin guardando el contrato otra vez antes de firmar.
-- (3) «Propia» se rechaza si el closer es el manager del equipo de la venta, el congelado (contrato_closer.manager_email)
--     o el actual (equipos_venta.manager_email del equipo congelado), en _venta_modo_declara y en _venta_modo_aplica.
--     Porqué: venta_propia_reclamar ya lo prohibía; F5 lo había perdido y el manager cobraría el 10 % además de su fee.
-- (6) Al cambiar el closer (crm_contrato_closer_set o cualquier UPDATE de closer_email → trigger nuevo modo_reinicia) el
--     modo, origen, cruces, ventana y marca de admin vuelven a NULL/false, las objeciones pendientes se retiran y la
--     fila queda marcada modo_declarado_por = 'sistema:cambio_closer', que es la única forma de que _venta_modo_declara
--     acepte declarar de nuevo en un re-guardado (D7 sigue para el resto). La tabla no tiene grants para authenticated:
--     la marca solo la escriben funciones del servidor.
--     Límite conocido: si crm_contrato_closer_set BORRA la atribución y luego se vuelve a asignar, la fila nueva nace
--     sin modo y sin marca: el modo se declara solo en el alta (o lo fija un admin).

alter table public.contrato_closer add column if not exists modo_fijado_admin boolean not null default false;
comment on column public.contrato_closer.modo_fijado_admin is
  'F5: true cuando el modo de la venta lo fijó un administrador (venta_modo_admin u objeción resuelta). El closer ya no lo cambia al re-guardar.';

-- ── _venta_modo_declara: (2), (3) y re-declaración tras cambio de closer (6) ─────────────────────────────────────
create or replace function public._venta_modo_declara(p_raiz uuid, p_venta jsonb, p_alta boolean)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
  -- Puerta F5 (30-sep): con el interruptor apagado la clave `venta` no existe para el servidor.
  if not coalesce((select i.modo_obligatorio from public.comisiones_interruptor i where i.id), false) then
    return;
  end if;

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
  -- venta ya guardada sin modo: no se declara por aquí (D7), salvo que el closer haya cambiado (6)
  if not p_alta and k.modo is null and k.modo_declarado_por is distinct from 'sistema:cambio_closer' then return; end if;

  if v_modo is null then
    if not p_alta then return; end if;              -- re-guardado sin la clave: se conserva lo declarado
    if k.equipo_id is not null then
      raise exception 'Indica si la venta es con tu equipo o por tu cuenta' using errcode = '22023';
    end if;
    v_modo := 'propia'; v_implic := true;           -- sin equipo: por su cuenta implícito
  end if;

  if not p_alta then
    if v_modo is not distinct from k.modo and v_origen is not distinct from k.modo_origen
       and v_texto is not distinct from k.modo_origen_texto then
      return;
    end if;
    if k.modo_fijado_admin then                     -- (2) lo decidió un administrador
      raise exception 'El modo de esta venta (equipo / por su cuenta) lo fijó un administrador: solo él lo cambia' using errcode = '42501';
    end if;
    if coalesce((select c.bloqueado from public.contratos c where c.id = p_raiz), false)
       or exists (select 1 from public.contrato_firmas f where f.contrato_id = p_raiz and f.estado = 'firmado') then
      raise exception 'La venta ya está firmada: el modo (equipo / por su cuenta) solo lo cambia un administrador' using errcode = '42501';
    end if;
    if exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id = p_raiz and d.estado <> 'anulada') then
      raise exception 'La venta ya tiene comisiones: el modo (equipo / por su cuenta) solo lo cambia un administrador' using errcode = '42501';
    end if;
  end if;

  -- (3) el manager del equipo de la venta (congelado o actual) no la declara por su cuenta
  if v_modo = 'propia' and k.equipo_id is not null
     and (lower(coalesce(k.manager_email, '')) = lower(k.closer_email)
          or exists (select 1 from public.equipos_venta ev
                      where ev.id = k.equipo_id and lower(coalesce(ev.manager_email, '')) = lower(k.closer_email))) then
    raise exception 'Eres el manager de este equipo: tu venta ya cobra la fee de manager, no es por tu cuenta' using errcode = '22023';
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
end $function$;

-- ── _venta_modo_aplica: (3) y marca (2) ──────────────────────────────────────────────────────────────────────────
create or replace function public._venta_modo_aplica(p_raiz uuid, p_modo text, p_motivo text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
  -- (3) el manager del equipo de la venta (congelado o actual) no cobra «por su cuenta»
  if p_modo = 'propia' and k.equipo_id is not null
     and (lower(coalesce(k.manager_email, '')) = lower(k.closer_email)
          or exists (select 1 from public.equipos_venta ev
                      where ev.id = k.equipo_id and lower(coalesce(ev.manager_email, '')) = lower(k.closer_email))) then
    raise exception 'El closer es el manager de este equipo: su venta cobra la fee de manager, no puede ser «por su cuenta»' using errcode = '22023';
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
         modo_declarado_por = nullif(v_yo, ''), modo_declarado_en = now(),
         modo_fijado_admin = true                  -- (2) el closer ya no lo cambia al re-guardar
   where contrato_id = p_raiz;
  perform set_config('app.via_modo_admin', 'off', true);

  return coalesce(public.comisiones_evaluar_contrato(p_raiz), 0);
end $function$;

-- ── venta_objecion_resolver: «mantener_propia» también fija el modo (2) ──────────────────────────────────────────
create or replace function public.venta_objecion_resolver(p_id uuid, p_decision text, p_motivo text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
    -- la decisión cierra la ventana: la venta devenga ya si toca; y el modo queda fijado por el admin (2)
    update public.contrato_closer set modo_espera_hasta = least(coalesce(modo_espera_hasta, now()), now()),
                                      modo_fijado_admin = true
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
end $function$;

-- ── (6) trigger nuevo: al cambiar el closer, el modo vuelve a NULL ──────────────────────────────────────────────
-- BEFORE UPDATE sobre NEW (no toca _trg_contrato_closer_congela). El candado del modo (BEFORE UPDATE OF modo, …) no
-- salta porque la sentencia solo pone closer_email: así el reinicio vale también en una venta firmada que un super
-- admin reasigna.
create or replace function public._trg_contrato_closer_modo_reinicia()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if old.modo is not null or old.modo_declarado_por is not null or old.modo_fijado_admin then
    new.modo := null; new.modo_origen := null; new.modo_origen_texto := null;
    new.modo_cruces := null; new.modo_espera_hasta := null; new.modo_fijado_admin := false;
    new.modo_declarado_por := 'sistema:cambio_closer'; new.modo_declarado_en := now();
    update public.reclamaciones_venta_propia
       set estado = 'retirada', resuelto_por = 'sistema', resuelto_en = now(),
           motivo_resolucion = 'cambió el closer de la venta: el modo se declara de nuevo'
     where contrato_raiz_id = new.contrato_id and tipo = 'objecion' and estado = 'pendiente';
  end if;
  return new;
end $function$;

revoke execute on function public._trg_contrato_closer_modo_reinicia() from public, anon, authenticated;

create trigger trg_contrato_closer_modo_reinicia
  before update of closer_email on public.contrato_closer
  for each row
  when (lower(coalesce(old.closer_email, '')) is distinct from lower(coalesce(new.closer_email, '')))
  execute function public._trg_contrato_closer_modo_reinicia();
