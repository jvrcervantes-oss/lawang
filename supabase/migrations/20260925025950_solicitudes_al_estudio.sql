-- Peticiones libres «Al estudio» (25-sep-2026, owner: tercer botón en Telegram para que
-- una petición `manual` del Asistente la recoja una sesión del estudio en vez de hacerla
-- él a mano). Revisión previa #83 (Seguridad + Datos).
--
-- Dos estados nuevos, solo para accion='manual':
--   al_estudio  — el owner pulsó «🔧 Al estudio»; espera a que una sesión la tome.
--   en_estudio  — una sesión la tomó (tomar_solicitud_estudio): otra ya no la coge.
-- Se cierran con cerrar_solicitud_estudio → ejecutada | rechazada.
--
-- Decisiones escritas (no descuidos):
--   · Quien la pidió SÍ recibe aviso al pasar a al_estudio («está en el estudio»).
--   · Quien la pidió NO puede retirarla una vez en el estudio: el owner ya decidió.
--     anular_solicitud_cambio sigue actuando solo sobre `pendiente`, sin cambios.
--   · La purga de 90 días no toca al_estudio ni en_estudio (se perdería qué se pidió
--     con la petición aún abierta) y vacía también la nota del cierre.
--   · El estudio NO escribe la tabla con la service key a pelo: tres RPC acotadas,
--     solo service_role, que solo conocen estas transiciones.

-- destructivo-ok: se sustituye el CHECK por uno más amplio en la misma migración (ninguna fila afectada)
alter table public.solicitudes_cambio drop constraint sc_estado_valido;
alter table public.solicitudes_cambio add constraint sc_estado_valido
  check (estado = any (array['pendiente','ejecutada','rechazada','fallida','anulada','al_estudio','en_estudio']));

-- ── resolver_solicitud_cambio: acepta 'al_estudio' DESPUÉS de las comprobaciones de
--    mensaje, estado y aprobador (ponerla antes saltaría la del aprobador — Datos).
create or replace function public.resolver_solicitud_cambio(p_id uuid, p_msg_id bigint, p_decision text, p_via text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  s        public.solicitudes_cambio;
  v_fila   jsonb;
  v_k      text;
  v_set    text;
  v_tg     bigint;
  v_aprob  public.usuarios;
  v_pide   text;
  v_quien  text;
  v_h      jsonb;
  v_res    jsonb;
  c_claims text := current_setting('request.jwt.claims', true);
  c_sub    text := current_setting('request.jwt.claim.sub', true);
  c_email  text := current_setting('request.jwt.claim.email', true);
  c_role   text := current_setting('request.jwt.claim.role', true);
begin
  if p_decision not in ('aprobar','rechazar','al_estudio') then
    raise exception 'decisión no válida' using errcode = '22023';
  end if;

  select * into s from public.solicitudes_cambio where id = p_id for update;
  if not found then
    return jsonb_build_object('estado', 'desconocida');
  end if;
  if s.telegram_msg_id is distinct from p_msg_id then
    raise exception 'el mensaje no corresponde a esta solicitud' using errcode = '42501';
  end if;
  if s.estado <> 'pendiente' then
    return jsonb_build_object('estado', s.estado, 'numero', s.numero, 'ya_resuelta', true, 'error', s.error);
  end if;

  v_tg := nullif(substring(coalesce(p_via, '') from '^telegram:(\d{1,20})$'), '')::bigint;
  select u.* into v_aprob
    from public.aprobadores_telegram a join public.usuarios u on u.user_id = a.user_id
   where a.telegram_id = v_tg and u.activo and u.rol = 'super_admin';
  if v_aprob.user_id is null then
    raise exception 'ese usuario de Telegram no puede aprobar' using errcode = '42501';
  end if;

  if p_decision = 'rechazar' then
    update public.solicitudes_cambio
       set estado = 'rechazada', resuelto_en = now(), resuelto_via = p_via
     where id = p_id;
    return jsonb_build_object('estado', 'rechazada', 'numero', s.numero);
  end if;

  if p_decision = 'al_estudio' then
    if s.accion <> 'manual' then
      raise exception 'solo una petición libre se pasa al estudio' using errcode = '22023';
    end if;
    update public.solicitudes_cambio
       set estado = 'al_estudio', resuelto_via = p_via,
           resultado = jsonb_build_object('derivado_por', p_via, 'derivado_en', now())
     where id = p_id;
    return jsonb_build_object('estado', 'al_estudio', 'numero', s.numero);
  end if;

  if s.accion = 'manual' then
    update public.solicitudes_cambio
       set estado = 'ejecutada', resuelto_en = now(), resuelto_via = p_via,
           resultado = jsonb_build_object('manual', true)
     where id = p_id;
    return jsonb_build_object('estado', 'ejecutada', 'numero', s.numero, 'manual', true);
  end if;

  select coalesce(u.email, '?') into v_pide from public.usuarios u where u.user_id = s.pedido_por;
  v_quien := 'SC-' || s.numero || ' · pedido por ' || coalesce(v_pide, '?') || ' · aprobado por ' || v_aprob.email || ' vía Telegram';

  begin
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub', v_aprob.user_id, 'role', 'authenticated', 'email', v_quien)::text, true);
    perform set_config('request.jwt.claim.sub', v_aprob.user_id::text, true);
    perform set_config('request.jwt.claim.email', v_quien, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('app.solicitud_cambio', 'SC-' || s.numero, true);

    if s.accion = 'editar_comprador' then
      select to_jsonb(c) into v_fila from public.clients c where c.id = s.fila_id for update;
      if v_fila is null then raise exception 'la ficha ya no existe'; end if;
      for v_k in select jsonb_object_keys(s.antes) loop
        if (v_fila->v_k) is distinct from (s.antes->v_k) then
          raise exception 'la ficha cambió mientras esperaba (%); hay que pedirlo otra vez', v_k;
        end if;
      end loop;
      select string_agg(format('%I = ($1->>%L)', k, k), ', ') into v_set
        from jsonb_object_keys(s.nuevos) k where k = any(public._sc_columnas_clients());
      if v_set is null then raise exception 'la solicitud no tiene campos aplicables'; end if;
      execute format('update public.clients set %s where id = $2', v_set) using s.nuevos, s.fila_id;
      v_res := jsonb_build_object('campos', (select jsonb_agg(k) from jsonb_object_keys(s.nuevos) k));

    else
      if s.accion = 'borrar_operacion' then
        perform 1 from public.contratos where id = s.fila_id or contrato_padre_id = s.fila_id for update;
      elsif s.tabla = 'facturas' then
        perform 1 from public.facturas where id = s.fila_id for update;
      elsif s.tabla = 'clients' then
        perform 1 from public.clients where id = s.fila_id for update;
      end if;
      v_h := public._sc_huella(s.accion, s.fila_id);
      if v_h is null then raise exception 'ya no existe'; end if;
      if v_h is distinct from s.antes then
        raise exception 'cambió algo desde que se pidió (estado, documentos o contratos): hay que pedirlo otra vez';
      end if;

      if s.accion = 'borrar_comprador' then
        delete from public.clients where id = s.fila_id;
        v_res := jsonb_build_object('borrada', true);

      elsif s.accion = 'anular_documento' then
        update public.facturas set anulada = true where id = s.fila_id and not coalesce(anulada, false);
        if not found then raise exception 'no se anuló nada'; end if;
        v_res := jsonb_build_object('anulado', v_h->>'numero');

      elsif s.accion = 'borrar_documento' then
        if (v_h->>'enviado')::boolean or (v_h->>'aplicaciones')::int > 0
           or (v_h->>'mes_cerrado')::boolean or (v_h->>'anulada')::boolean or v_h->>'tipo' = 'proforma' then
          raise exception 'el documento ya no se puede borrar: pide anularlo';
        end if;
        delete from public.facturas where id = s.fila_id;
        if not found then raise exception 'no se borró nada'; end if;
        v_res := jsonb_build_object('borrado', v_h->>'numero');

      elsif s.accion = 'borrar_operacion' then
        if (v_h->>'firmados')::int > 0 or (v_h->>'recibis_vivos')::int > 0
           or (v_h->>'comision_blindada')::boolean then
          raise exception 'la operación ya no se puede borrar sola';
        end if;
        v_res := public.borrar_operacion(s.fila_id);
      end if;
    end if;

    update public.solicitudes_cambio
       set estado = 'ejecutada', resuelto_en = now(), resuelto_via = p_via, resultado = v_res
     where id = p_id;
  exception when others then
    v_res := jsonb_build_object('error', sqlerrm);
  end;

  perform set_config('request.jwt.claims', coalesce(c_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(c_sub, ''), true);
  perform set_config('request.jwt.claim.email', coalesce(c_email, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(c_role, ''), true);
  perform set_config('app.solicitud_cambio', '', true);

  if v_res ? 'error' then
    update public.solicitudes_cambio
       set estado = 'fallida', error = v_res->>'error', resuelto_en = now(), resuelto_via = p_via
     where id = p_id;
    return jsonb_build_object('estado', 'fallida', 'numero', s.numero, 'error', v_res->>'error');
  end if;
  return jsonb_build_object('estado', 'ejecutada', 'numero', s.numero, 'resultado', v_res);
end
$function$;

-- ── Lo que lee el estudio: columnas contadas, nunca select=* (Seguridad).
create or replace function public.solicitudes_estudio()
 returns table(numero bigint, estado text, texto text, pedido_por_nombre text, pedido_en timestamptz, derivado_en text)
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select s.numero, s.estado, coalesce(s.texto, s.motivo),
         coalesce(u.nombre, 'Alguien del equipo'), s.pedido_en, s.resultado->>'derivado_en'
    from public.solicitudes_cambio s
    left join public.usuarios u on u.user_id = s.pedido_por
   where s.estado in ('al_estudio', 'en_estudio') and s.accion = 'manual'
   order by s.numero
   limit 20
$function$;

-- ── Tomarla: al_estudio → en_estudio, condicional. Si devuelve null, otra sesión la
--    tiene (dos copias de Lawang abiertas no hacen la misma — Seguridad).
create or replace function public.tomar_solicitud_estudio(p_numero bigint, p_sesion text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_n bigint;
begin
  update public.solicitudes_cambio
     set estado = 'en_estudio',
         resultado = coalesce(resultado, '{}'::jsonb)
                     || jsonb_build_object('tomada_por', left(coalesce(p_sesion, '?'), 80), 'tomada_en', now())
   where numero = p_numero and estado = 'al_estudio' and accion = 'manual'
  returning numero into v_n;
  if v_n is null then return null; end if;
  return jsonb_build_object('numero', v_n, 'estado', 'en_estudio');
end
$function$;

-- ── Cerrarla: solo desde al_estudio/en_estudio y solo a ejecutada|rechazada. La nota
--    la escribe el agente: corta (300) y se purga a los 90 días como el resto.
create or replace function public.cerrar_solicitud_estudio(p_numero bigint, p_decision text, p_nota text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_n bigint; v_e text;
begin
  if p_decision not in ('hecha', 'rechazada') then
    raise exception 'decisión no válida' using errcode = '22023';
  end if;
  if coalesce(btrim(p_nota), '') = '' then
    raise exception 'falta la nota: qué se hizo o por qué no' using errcode = '22023';
  end if;
  update public.solicitudes_cambio
     set estado = case p_decision when 'hecha' then 'ejecutada' else 'rechazada' end,
         resuelto_en = now(), resuelto_via = 'estudio',
         resultado = coalesce(resultado, '{}'::jsonb)
                     || jsonb_build_object('estudio', true, 'nota', left(btrim(p_nota), 300))
   where numero = p_numero and estado in ('al_estudio', 'en_estudio') and accion = 'manual'
  returning numero, estado into v_n, v_e;
  if v_n is null then return null; end if;
  return jsonb_build_object('numero', v_n, 'estado', v_e);
end
$function$;

revoke all on function public.solicitudes_estudio() from public, anon, authenticated;
revoke all on function public.tomar_solicitud_estudio(bigint, text) from public, anon, authenticated;
revoke all on function public.cerrar_solicitud_estudio(bigint, text, text) from public, anon, authenticated;
grant execute on function public.solicitudes_estudio() to service_role;
grant execute on function public.tomar_solicitud_estudio(bigint, text) to service_role;
grant execute on function public.cerrar_solicitud_estudio(bigint, text, text) to service_role;

-- ── Aviso al que la pidió: también al pasar al estudio.
create or replace function public._trg_solicitud_cambio_aviso()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_email text;
begin
  if new.estado is distinct from old.estado and new.estado in ('ejecutada','rechazada','fallida','al_estudio') then
    select u.email into v_email from public.usuarios u where u.user_id = new.pedido_por;
    if v_email is not null then
      insert into public.notificaciones (tipo, titulo, detalle, destinatario, enlace)
      values ('solicitud_cambio',
              'Tu petición SC-' || new.numero || ' — ' ||
                case new.estado when 'ejecutada' then 'hecha'
                                when 'rechazada' then 'rechazada'
                                when 'al_estudio' then 'en el estudio'
                                else 'no se pudo hacer' end,
              case when new.estado = 'fallida' then new.error else left(new.motivo, 300) end,
              v_email, '/intranet/v4/asistente/');
    end if;
  end if;
  return new;
exception when others then
  return new;
end
$function$;

-- ── Purga: no toca las abiertas en el estudio y vacía la nota del cierre (Datos).
create or replace function public.purgar_solicitudes_cambio()
 returns void
 language sql
 security definer
 set search_path to ''
as $function$
  update public.solicitudes_cambio
     set antes = case when accion = 'editar_comprador'
                      then (select jsonb_object_agg(k, null) from jsonb_object_keys(antes) k) end,
         nuevos = (select jsonb_object_agg(k, null) from jsonb_object_keys(nuevos) k),
         texto = null,
         motivo = '(purgado a los 90 días)',
         ficha_nombre = null,
         resultado = case when resultado ? 'nota' then resultado || '{"nota":null}'::jsonb else resultado end,
         purgado_en = now()
   where purgado_en is null
     and estado not in ('pendiente', 'al_estudio', 'en_estudio')
     and coalesce(resuelto_en, pedido_en) < now() - interval '90 days';
  delete from public.asistente_uso where dia < (now() at time zone 'Asia/Makassar')::date - 30;
$function$;

-- ── Resumen de las 08:00: las que están en el estudio no desaparecen del recuento
--    del owner (Datos). Mismo cuerpo que 20260925120000; solo cambia `esperando`.
create or replace function public.resumen_manana(p_hoy date)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_gracia int := coalesce((public.parametro('reservas.dias_gracia'))::int, 3);
  r jsonb := '{}'::jsonb;
begin
  if p_hoy is distinct from (now() at time zone 'Asia/Makassar')::date then
    raise exception 'p_hoy tiene que ser hoy en Bali' using errcode = '22023';
  end if;

  r := r || jsonb_build_object('hoy', p_hoy, 'leads',
    (select to_jsonb(n) from public._crm_leads_nucleo() n));

  r := r || jsonb_build_object('reservas', (
    select coalesce(jsonb_agg(x order by x->>'vence_el'), '[]'::jsonb) from (
      select jsonb_build_object('numero', min(rv.numero), 'proyecto', min(rv.proyecto_nombre),
               'parcelas', string_agg(distinct rv.codigo, ', '), 'vence_el', min(rv.vence_el),
               'dias', min(rv.vence_el) - p_hoy, 'prorrogas', max(rv.n_prorrogas)) as x
        from public.reservas_vencimiento() rv
       where rv.vence_el is not null and rv.vence_el <= p_hoy + 7 and rv.vence_el > p_hoy - v_gracia
       group by rv.contrato_id) t));
  r := r || jsonb_build_object('dias_gracia', v_gracia);

  r := r || jsonb_build_object('hitos_vencidos', (
    select coalesce(jsonb_object_agg(moneda, jsonb_build_object('n', n, 'importe', importe, 'sin_importe', sin_importe)), '{}'::jsonb)
      from (select h.moneda, count(*) n, coalesce(sum(h.monto), 0) importe, count(*) filter (where h.monto is null) sin_importe
              from public.hitos_sin_factura(p_hoy) h group by h.moneda) t),
    'hitos_mas_antiguo', (select jsonb_build_object('numero', h.numero, 'descripcion', h.descripcion, 'fecha', h.fecha)
                            from public.hitos_sin_factura(p_hoy) h order by h.fecha limit 1));
  r := r || jsonb_build_object('hitos_7d', (
    select coalesce(jsonb_object_agg(moneda, jsonb_build_object('n', n, 'importe', importe, 'sin_importe', sin_importe)), '{}'::jsonb)
      from (select coalesce(c.moneda, 'EUR') moneda, count(*) n, coalesce(sum(v.monto), 0) importe,
                   count(*) filter (where v.monto is null) sin_importe
              from public.contrato_vencimientos v join public.contratos c on c.id = v.contrato_id
             where coalesce(c.bloqueado, false) and c.liberado_en is null
               and v.factura_id is null and not coalesce(v.no_facturar, false)
               and v.fecha between p_hoy and p_hoy + 7
             group by 1) t));

  r := r || jsonb_build_object('esperando', jsonb_build_object(
    'peticiones', (select count(*) from public.solicitudes_cambio where estado = 'pendiente'),
    'al_estudio', (select count(*) from public.solicitudes_cambio where estado in ('al_estudio', 'en_estudio')),
    'pagos_pendientes', (select count(*) from public.solicitudes_pago where estado = 'pendiente'),
    'pagos_por_pagar', (select count(*) from public.solicitudes_pago where estado = 'aprobada')));
  return r;
end
$function$;
