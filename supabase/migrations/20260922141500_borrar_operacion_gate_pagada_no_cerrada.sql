-- Fix de un error propio, detectado verificando en vivo antes de dar el
-- deploy anterior por bueno (20260922134500_borrar_operacion_purga_comision_devengada):
-- el gate comprobaba `sp.estado = 'cerrada'`, copiando el esquema de
-- solicitudes_pago tal como lo describía la migración original
-- (20260909071823, con `factura_id` y estado 'cerrada'). El esquema real en
-- producción ya no es ese: `solicitud_estado_valido` solo admite
-- ('pendiente','aprobada','rechazada','anulada','pagada'), sin 'cerrada' ni
-- columna factura_id -- el estado terminal se llama 'pagada' y lleva
-- pago_referencia/pagado_por/pagado_en (verificado con pg_get_constraintdef
-- antes de escribir este fix, no de memoria). Con el nombre viejo, el gate
-- nunca se disparaba para una solicitud realmente pagada -- exactamente el
-- caso que se pedía blindar.
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
  sp_pagada_numero bigint;
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

  -- Gate: una comisión ya pagada (solicitud 'pagada') no se purga sola.
  select sp.numero into sp_pagada_numero
    from public.comisiones_devengadas d
    join public.solicitudes_pago sp on sp.id = d.solicitud_id
   where d.contrato_raiz_id = any(ids)
     and sp.estado = 'pagada'
   limit 1;
  if sp_pagada_numero is not null then
    raise exception 'Esta operacion ya tiene una comision pagada (solicitud SP-%): no se puede borrar automaticamente, resuelvelo a mano', sp_pagada_numero;
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
grant execute on function public.borrar_operacion(uuid) to authenticated;;
