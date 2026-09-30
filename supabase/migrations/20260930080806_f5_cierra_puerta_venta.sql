-- F5 · arreglo urgente 1 (pedido por el revisor, 30-sep-2026): cerrar la puerta de «por su cuenta» mientras el
-- interruptor comisiones_interruptor.modo_obligatorio esté APAGADO.
--
-- Porqué: 20260930074916_f5_por_su_cuenta dejó contrato_guarda (grant authenticated) escribiendo la clave `venta`
-- aunque el interruptor estuviera apagado. Un closer con equipo podía declarar «propia» por la RPC, saltarse la
-- pantalla (que aún no existe) y cobrar el 10 % estándar sin que su Sales Manager lo viera. El recálculo automático
-- está ENCENDIDO, así que el efecto sería inmediato. A la hora de aplicar: 0 filas de contrato_closer con modo.
--
-- 1) _venta_modo_declara (único llamador: contrato_guarda) sale sin hacer NADA con el interruptor apagado:
--    ni modo, ni cruces, ni objeción, ni aviso. contrato_guarda ignora así la clave `venta` por completo.
-- 2) Se revoca EXECUTE a authenticated (y public/anon) de las RPC de F5 que aún no tienen pantalla que las llame
--    (reducir la exposición: sin llamador con nombre, cerrada). Se conceden cuando existan las pantallas.

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
  if not p_alta and k.modo is null then return; end if;  -- venta ya guardada sin modo: no se declara por aquí (D7)

  if v_modo is null then
    if not p_alta then return; end if;              -- re-guardado sin la clave: se conserva lo declarado
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
end $function$;

revoke execute on function public._venta_modo_declara(uuid, jsonb, boolean) from public, anon, authenticated;

revoke execute on function public.venta_objecion_crear(uuid, text) from public, anon, authenticated;
revoke execute on function public.venta_objecion_resolver(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.venta_modo_admin(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.ventas_por_su_cuenta_equipo() from public, anon, authenticated;
