-- destructivo-ok: ningún dato se borra al aplicar — REVOKE INSERT quita un permiso sobrante y el DELETE vive dentro de comision_recalcular (ya existente, solo super_admin).
-- Consulta de deploy (Seguridad, ÁMBAR) sobre 20260923045439_comisiones_editar_anular_recalcular:
-- 1. El motivo se quedaba pegado: `motivo_ajuste` es una columna, y un UPDATE que no la
--    manda conserva la anterior → un segundo cambio de importe o anulación pasaba sin
--    motivo nuevo, y el log apuntaba el viejo. Solo cuenta si ESTE update lo cambia.
-- 2. Recalcular miraba solo las solicitudes: un super_admin closer de esa venta podía
--    recalcular su propia comisión de reparto. Ahora mira también el devengo.
--    Y resuelve la raíz aunque le pasen un contrato hijo.
-- 3. Heredado: `authenticated` tenía INSERT en comisiones_devengadas (policy «solo admin»):
--    un admin podía meter un devengo `pagada` o con importe libre. Solo el motor (DEFINER)
--    inserta; ninguna pantalla lo hace (grep 23-sep).

do $$
declare d text; n text;
begin
  d := pg_get_functiondef('public._trg_solicitud_pago_transicion'::regproc);
  n := replace(d,
    'v_motivo  text := nullif(btrim(coalesce(new.motivo_ajuste, '''')), '''');',
    'v_motivo  text := case when new.motivo_ajuste is distinct from old.motivo_ajuste then nullif(btrim(coalesce(new.motivo_ajuste, '''')), '''') end;');
  if n = d then
    raise exception 'no encuentro la declaración de v_motivo en _trg_solicitud_pago_transicion';
  end if;
  execute n;
end $$;

create or replace function public.comision_recalcular(p_raiz uuid, p_motivo text)
returns integer language plpgsql security definer set search_path to '' as $$
declare v_motivo text := nullif(btrim(coalesce(p_motivo, '')), ''); d record; n integer;
        v_yo text := lower(coalesce(auth.email(), ''));
begin
  if not public.es_super_admin() then
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
end $$;
revoke all on function public.comision_recalcular(uuid, text) from public, anon;
grant execute on function public.comision_recalcular(uuid, text) to authenticated;

revoke insert on public.comisiones_devengadas from authenticated, anon;
