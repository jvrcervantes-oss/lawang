-- Decisión del owner (22-sep-2026, tras revisar los hallazgos MEDIA de Legal y
-- Administración sobre el purge de comisiones): además de 'pagada', el gate
-- de borrar_operacion() también bloquea cuando:
--   · la solicitud de pago (nivel manager) está 'aprobada' -- Administración
--     ya dijo que sí se paga, aunque el pago aún no se haya ejecutado.
--   · el devengo (closer o manager) está 'en_disputa' -- reclamación abierta
--     sin resolver; purgarlo la cerraría de facto sin que nadie lo decidiera.
-- 'pendiente' sigue purgándose sin más: es lo único que de verdad no
-- compromete a nadie todavía.
create or replace function public.borrar_operacion(p_contrato_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ids        uuid[];
  n_cont     int;
  n_firmas   int;
  n_fact     int;
  n_devengos int;
  n_solic    int;
  bloqueado_ajeno text;
  d_blindado_id uuid;
  solicitudes_a_purgar uuid[];
begin
  if not public.es_agente() then
    raise exception 'no autorizado';
  end if;

  select array_agg(c.id) into ids
    from public.contratos c
   where c.id = p_contrato_id or c.contrato_padre_id = p_contrato_id;
  if ids is null then
    raise exception 'esa operacion no existe';
  end if;

  if not public.es_super_admin() then
    select c.numero into bloqueado_ajeno
      from public.contratos c
     where c.id = any(ids)
       and (coalesce(c.bloqueado,false) = true
            or c.creado_por is null
            or c.creado_por <> (select auth.email()))
     limit 1;
    if bloqueado_ajeno is not null then
      raise exception 'El contrato % esta firmado o es de otra persona: esta operacion solo la puede borrar un super admin', bloqueado_ajeno;
    end if;
  end if;

  -- Gate: comisión pagada, en disputa, o con solicitud ya aprobada -- ninguna
  -- se purga sola. Solo 'pendiente' (devengo) y sin-solicitud-o-pendiente
  -- (solicitud) pasan de largo.
  select d.id into d_blindado_id
    from public.comisiones_devengadas d
    left join public.solicitudes_pago sp on sp.id = d.solicitud_id
   where d.contrato_raiz_id = any(ids)
     and (d.estado in ('pagada', 'en_disputa') or sp.estado in ('pagada', 'aprobada'))
   limit 1;
  if d_blindado_id is not null then
    raise exception 'Esta operacion tiene una comision pagada, en disputa o ya aprobada para pago (devengo %): no se puede borrar automaticamente, resuelvelo a mano', d_blindado_id;
  end if;

  update public.contrato_firmas set estado = 'anulado'
   where contrato_id = any(ids) and estado in ('pendiente','procesando');
  get diagnostics n_firmas = row_count;

  update public.facturas set anulada = true
   where contrato_id = any(ids) and coalesce(anulada,false) = false;
  get diagnostics n_fact = row_count;

  select array_agg(distinct d.solicitud_id) into solicitudes_a_purgar
    from public.comisiones_devengadas d
   where d.contrato_raiz_id = any(ids) and d.solicitud_id is not null;

  delete from public.comisiones_devengadas where contrato_raiz_id = any(ids);
  get diagnostics n_devengos = row_count;

  if solicitudes_a_purgar is not null then
    delete from public.solicitudes_pago where id = any(solicitudes_a_purgar);
    get diagnostics n_solic = row_count;
  else
    n_solic := 0;
  end if;

  delete from public.contratos where id = any(ids);
  get diagnostics n_cont = row_count;

  return jsonb_build_object(
    'contratos_borrados',   n_cont,
    'firmas_anuladas',      n_firmas,
    'facturas_anuladas',    n_fact,
    'comisiones_purgadas',  n_devengos,
    'solicitudes_purgadas', n_solic);
end $$;

revoke all on function public.borrar_operacion(uuid) from public, anon;
grant execute on function public.borrar_operacion(uuid) to authenticated;
