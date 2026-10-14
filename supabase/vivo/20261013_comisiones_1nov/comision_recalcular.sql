CREATE OR REPLACE FUNCTION public.comision_recalcular(p_raiz uuid, p_motivo text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_motivo text := nullif(btrim(coalesce(p_motivo, '')), ''); d record; n integer;
        v_yo text := lower(coalesce(auth.email(), ''));
begin
  if not public.es_super_admin_de(public._empresa_de_contrato_int(p_raiz)) then
    raise exception 'solo un super admin recalcula comisiones' using errcode = '42501';
  end if;
  if v_motivo is null then
    raise exception 'recalcular exige un motivo' using errcode = '22023';
  end if;
  select coalesce(c.contrato_padre_id, c.id) into p_raiz from public.contratos c where c.id = p_raiz;
  if p_raiz is null then
    raise exception 'no existe ese contrato' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));

  if exists (
       select 1 from public.comisiones_devengadas cd
         left join public.solicitudes_pago sp on sp.id = cd.solicitud_id
        where cd.contrato_raiz_id = p_raiz
          and (cd.estado in ('pagada','en_disputa') or sp.estado in ('aprobada','pagada'))) then
    raise exception 'hay comisiones de esta venta aprobadas, pagadas o en disputa: no se recalcula' using errcode = '22023';
  end if;
  if exists (
       select 1 from public.comisiones_devengadas cd
         left join public.solicitudes_pago sp on sp.id = cd.solicitud_id
        where cd.contrato_raiz_id = p_raiz
          and (lower(cd.beneficiario_email) = v_yo or lower(coalesce(sp.beneficiario_email, '')) = v_yo)) then
    raise exception 'esta venta tiene una comisión a tu nombre: la recalcula otro super admin' using errcode = '42501';
  end if;

  update public.solicitudes_pago sp
     set estado = 'anulada', motivo_ajuste = 'Recálculo: ' || v_motivo
   where sp.estado = 'pendiente'
     and sp.id in (select solicitud_id from public.comisiones_devengadas where contrato_raiz_id = p_raiz and solicitud_id is not null);

  for d in select * from public.comisiones_devengadas where contrato_raiz_id = p_raiz loop
    insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
    values ('comisiones_devengadas', d.id, 'recalcular', coalesce(d.importe_ajustado, d.importe), null, d.estado, null, v_motivo, to_jsonb(d));
  end loop;
  delete from public.comisiones_devengadas where contrato_raiz_id = p_raiz;

  n := public.comisiones_evaluar_contrato(p_raiz);
  return coalesce(n, 0);
end $function$
