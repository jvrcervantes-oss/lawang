-- PRUEBA — recálculo automático de comisiones (20260928210000 + 20260928213000, 28-sep-2026).
-- Se ejecuta entera con execute_sql (MCP) o psql como postgres. NO ESCRIBE NADA: cada caso va en un sub-bloque
-- que acaba en excepción (Postgres lo deshace) y el bloque entero termina en `raise exception 'RES: …'`.
-- Cada caso debe decir «ok»; un «FALLO» es dinero mal calculado o una puerta abierta.
-- Base: la venta con comisión de closer y de manager pendientes, con un contrato hijo SIN firmar cuyo precio
-- cuenta en la base solo al firmarse (el 28-sep: RP00122 + CC00078). Si ya no hay ninguna así, la prueba lo dice.
do $$
declare
  r text := ''; v_raiz uuid; v_hijo uuid; v_closer uuid; v_man uuid; v_sp uuid;
  v_admin record; v_benef record; v_n int; v_t text; v_imp numeric; v_base_on numeric; v_base_off numeric;
begin
  select d.contrato_raiz_id, h.id into v_raiz, v_hijo
    from public.comisiones_devengadas d
    join public.contratos h on h.contrato_padre_id = d.contrato_raiz_id and not coalesce(h.bloqueado, false)
                            and h.liberado_en is null and h.tipo not like 'carta_reserva%' and h.precio_total > 0
   where d.nivel = 'closer' and d.estado = 'pendiente'
     and exists (select 1 from public.comisiones_devengadas m join public.solicitudes_pago sp on sp.id = m.solicitud_id
                  where m.contrato_raiz_id = d.contrato_raiz_id and m.nivel = 'manager' and m.estado = 'pendiente' and sp.estado = 'pendiente')
   limit 1;
  if v_raiz is null then raise exception 'RES: sin venta con closer+manager pendientes y un hijo sin firmar: la prueba no tiene base'; end if;
  select id into v_closer from public.comisiones_devengadas where contrato_raiz_id = v_raiz and nivel = 'closer' and estado = 'pendiente' limit 1;
  select id, solicitud_id into v_man, v_sp from public.comisiones_devengadas where contrato_raiz_id = v_raiz and nivel = 'manager' and estado = 'pendiente' limit 1;
  select u.user_id, u.email into v_admin from public.usuarios u
   where u.rol = 'super_admin' and u.activo
     and lower(u.email) not in (select lower(beneficiario_email) from public.comisiones_devengadas where contrato_raiz_id = v_raiz)
   order by u.email limit 1;
  select u.user_id, u.email into v_benef from public.usuarios u
   where lower(u.email) = (select lower(beneficiario_email) from public.comisiones_devengadas where id = v_closer);
  v_base_off := public._comisiones_precio_total(v_raiz);
  execute 'set constraints all immediate';

  -- 1 · interruptor apagado: firmar el hijo no toca lo devengado
  begin
    update public.comisiones_interruptor set recalculo_auto = false;
    select importe into v_imp from public.comisiones_devengadas where id = v_closer;
    update public.contratos set bloqueado = true where id = v_hijo;
    raise exception '%', (select importe from public.comisiones_devengadas where id = v_closer) = v_imp;
  exception when others then r := r || '1 apagado no toca=' || sqlerrm || (case when sqlerrm = 't' then ' ok; ' else ' FALLO; ' end); end;

  -- 2 · encendido, hijo sin firmar: baja en sitio; la solicitud no queda como edición humana
  begin
    update public.comisiones_interruptor set recalculo_auto = true;
    perform public.comisiones_reconciliar(v_raiz, false, '{"prueba":2}');
    select format('%s/%s/%s', (select d.importe = round((c.pct_comision / 100) * v_base_off * (t.pct_tramo / 100), 2)
                                  from public.comisiones_devengadas d join public.condiciones_comision c on c.id = d.condicion_id
                                  join public.condicion_tramos t on t.id = d.tramo_id where d.id = v_closer),
                  (select sp.importe = d.importe from public.solicitudes_pago sp join public.comisiones_devengadas d on d.solicitud_id = sp.id where d.id = v_man),
                  (select importe_editado_por is null from public.solicitudes_pago where id = v_sp)) into v_t;
    raise exception '%', v_t;
  exception when others then r := r || '2 baja en sitio=' || sqlerrm || (case when sqlerrm = 't/t/t' then ' ok; ' else ' FALLO; ' end); end;

  -- 3 · idempotente
  begin
    update public.comisiones_interruptor set recalculo_auto = true;
    perform public.comisiones_reconciliar(v_raiz, false, '{}');
    select count(*) into v_n from public.comisiones_reconciliar(v_raiz, false, '{}');
    raise exception '%', v_n;
  exception when others then r := r || '3 segunda pasada=' || sqlerrm || (case when sqlerrm = '0' then ' ok; ' else ' FALLO; ' end); end;

  -- 4 · firmar el hijo por el disparador vuelve a subir a la base con el hijo
  begin
    update public.comisiones_interruptor set recalculo_auto = true;
    perform public.comisiones_reconciliar(v_raiz, false, '{}');
    update public.contratos set bloqueado = true where id = v_hijo;
    v_base_on := public._comisiones_precio_total(v_raiz);
    raise exception '%', (select format('%s/%s', v_base_on > v_base_off,
                            d.importe = round((c.pct_comision / 100) * v_base_on * (t.pct_tramo / 100), 2))
                            from public.comisiones_devengadas d join public.condiciones_comision c on c.id = d.condicion_id
                            join public.condicion_tramos t on t.id = d.tramo_id where d.id = v_closer);
  exception when others then r := r || '4 firmar sube=' || sqlerrm || (case when sqlerrm = 't/t' then ' ok; ' else ' FALLO; ' end); end;

  -- 5 · ya pagada / aprobada: desfirmar deja diferencias negativas sin solicitud; re-firmar, positivas
  --     (la de Lawang con solicitud); rechazar esa solicitud anula su diferencia
  begin
    update public.contratos set bloqueado = true where id = v_hijo;          -- base con el hijo, interruptor apagado
    execute 'set local session_replication_role = replica';
    update public.comisiones_devengadas set estado = 'pagada', pagado_en = now() where id = v_closer;
    update public.solicitudes_pago set estado = 'aprobada' where id = v_sp;
    execute 'set local session_replication_role = origin';
    update public.comisiones_interruptor set recalculo_auto = true;
    perform public.comisiones_reconciliar(v_raiz, false, '{}');              -- cuadra con la base de hoy
    update public.contratos set bloqueado = false where id = v_hijo;
    select format('%s/%s', count(*) filter (where x.importe < 0 and x.estado = 'pendiente'), count(*) filter (where x.solicitud_id is not null))
      into v_t from public.comisiones_diferencias x where x.devengo_id in (v_closer, v_man);
    update public.contratos set bloqueado = true where id = v_hijo;
    v_t := v_t || '/' || (select count(*) from public.comisiones_diferencias x
                           where x.devengo_id = v_man and x.importe > 0 and x.solicitud_id is not null);
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin.user_id, 'email', v_admin.email, 'role', 'authenticated')::text, true);
    update public.solicitudes_pago set estado = 'rechazada', motivo_rechazo = 'prueba'
     where id = (select x.solicitud_id from public.comisiones_diferencias x where x.devengo_id = v_man and x.importe > 0);
    v_t := v_t || '/' || (select x.estado from public.comisiones_diferencias x where x.devengo_id = v_man and x.importe > 0);
    raise exception '%', v_t;
  exception when others then r := r || '5 pagadas=' || sqlerrm || (case when sqlerrm = '2/0/1/anulada' then ' ok; ' else ' FALLO; ' end); end;

  -- 6 · puertas: el closer no resuelve la suya, no llama al reconciliador, no escribe en la tabla
  begin
    update public.comisiones_interruptor set recalculo_auto = true;
    update public.contratos set bloqueado = true where id = v_hijo;
    execute 'set local session_replication_role = replica';
    update public.comisiones_devengadas set estado = 'pagada', pagado_en = now() where id = v_closer;
    execute 'set local session_replication_role = origin';
    update public.contratos set bloqueado = false where id = v_hijo;          -- diferencia negativa del closer
    perform set_config('request.jwt.claims', json_build_object('sub', v_benef.user_id, 'email', v_benef.email, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_t := '';
    begin perform public.comision_diferencia_resolver((select x.id from public.comisiones_diferencias x where x.devengo_id = v_closer limit 1), 'compensada', 'prueba');
          v_t := v_t || 'resolvio';
    exception when others then v_t := v_t || 'no'; end;
    begin perform public.comisiones_reconciliar(v_raiz); v_t := v_t || '/llamo';
    exception when others then v_t := v_t || '/no'; end;
    begin insert into public.comisiones_diferencias (devengo_id, importe, motivo) values (v_closer, 1, 'x'); v_t := v_t || '/inserto';
    exception when others then v_t := v_t || '/no'; end;
    v_t := v_t || '/' || (select count(*) from public.comisiones_diferencias);
    execute 'reset role';
    raise exception '%', v_t;
  exception when others then r := r || '6 puertas=' || sqlerrm || (case when sqlerrm = 'no/no/no/1' then ' ok; ' else ' FALLO; ' end); end;

  -- 7 · una comisión con diferencia viva no se borra
  begin
    update public.comisiones_interruptor set recalculo_auto = true;
    update public.contratos set bloqueado = true where id = v_hijo;
    execute 'set local session_replication_role = replica';
    update public.comisiones_devengadas set estado = 'pagada', pagado_en = now() where id = v_closer;
    execute 'set local session_replication_role = origin';
    update public.contratos set bloqueado = false where id = v_hijo;
    begin delete from public.comisiones_devengadas where id = v_closer; v_t := 'borro';
    exception when others then v_t := 'no'; end;
    raise exception '%', v_t;
  exception when others then r := r || '7 no se borra=' || sqlerrm || (case when sqlerrm = 'no' then ' ok; ' else ' FALLO; ' end); end;

  -- 8 · el motor dispara pct_cobrado_total contra todos los contratos (la base del importe es solo firmados)
  r := r || '8 disparo total=' || (position('_comisiones_precio_total_todos(v_raiz_id)' in
          pg_get_functiondef('public.comisiones_evaluar_contrato(uuid)'::regprocedure)) > 0)::text
        || (case when position('_comisiones_precio_total_todos(v_raiz_id)' in
          pg_get_functiondef('public.comisiones_evaluar_contrato(uuid)'::regprocedure)) > 0 then ' ok; ' else ' FALLO; ' end);

  -- 9 · ningún recálculo ha fallado en silencio
  r := r || '9 sin error=' || coalesce((select ultimo_error from public.comisiones_interruptor), 'ninguno')
        || (case when (select ultimo_error from public.comisiones_interruptor) is null then ' ok' else ' FALLO' end);

  raise exception 'RES: %', r;
end $$;
