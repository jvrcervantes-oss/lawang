-- Hallazgo ALTA de Administración en la consulta de deploy de hoy sobre
-- facturas_contrato_obligatorio_exime_anuladas: ese fix hace que
-- borrar_operacion() avance más allá de donde antes fallaba (el CHECK de
-- facturas), así que la primera operación que YA tenga una comisión devengada
-- (closer o manager) chocará con otra FK sin ON DELETE
-- (comisiones_devengadas_contrato_raiz_id_fkey) — mismo síntoma de fondo, error
-- distinto. Verificado antes de tocar nada: hoy 0 contratos reales están en ese
-- caso, así que no era un bloqueo activo, pero sí una decisión de negocio.
--
-- Decisión del owner (22-sep-2026, presentada con las alternativas —bloquear,
-- marcar en_disputa, purgar, dejarlo— y elegida explícitamente): PURGAR
-- automáticamente el devengo y su solicitud de pago al borrar la operación.
--
-- Con UNA excepción que el propio owner vio planteada como riesgo al elegir la
-- opción ("si ya se pagó, queda un pago real sin ningún registro que lo
-- respalde — mal para auditoría"): si la solicitud de pago ya está 'cerrada'
-- (el único estado que en este esquema significa "ya se resolvió con una
-- factura real, ver solicitud_cerrada_con_factura"), NO se purga nada — se
-- para la operación entera con un mensaje claro. Un pago ya conciliado no se
-- borra solo; ese caso concreto se resuelve a mano, igual que ya para el
-- borrado por contrato bloqueado/ajeno unas líneas más abajo. Todo lo demás
-- (pendiente, aprobada, rechazada, anulada, o sin solicitud) se purga sin más.
--
-- Orden de borrado: comisiones_devengadas ANTES que solicitudes_pago, porque
-- comisiones_devengadas.solicitud_id referencia solicitudes_pago(id) sin
-- ON DELETE — borrar en el otro orden violaría esa FK.
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
  sp_cerrada_numero bigint;
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

  -- Gate: una comisión ya pagada (solicitud 'cerrada') no se purga sola.
  select sp.numero into sp_cerrada_numero
    from public.comisiones_devengadas d
    join public.solicitudes_pago sp on sp.id = d.solicitud_id
   where d.contrato_raiz_id = any(ids)
     and sp.estado = 'cerrada'
   limit 1;
  if sp_cerrada_numero is not null then
    raise exception 'Esta operacion ya tiene una comision pagada y cerrada (solicitud SP-%): no se puede borrar automaticamente, resuelvelo a mano', sp_cerrada_numero;
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
