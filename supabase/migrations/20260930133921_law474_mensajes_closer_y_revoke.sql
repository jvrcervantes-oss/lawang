-- LAW-474 · ajuste (30-sep-2026): el aviso del cambio/baja de closer habla de la intranet, no de funciones SQL,
-- y comision_devengo_anular_lawang deja de estar abierta a `authenticated` (sin llamador en la intranet:
-- reducir la exposición). Queda para admin por SQL / service_role hasta que tenga pantalla.
-- Cuerpo tomado del VIVO (pg_get_functiondef, 30-sep); solo cambian los dos textos de raise.
-- Nombres de pantalla comprobados en intranet/v4/assets/nav.js: Comisiones → «Reparto a closers» (botón Anular
-- de la comisión de closer) y Comisiones → «Pagos de %marca» (solicitudes de pago; anular la solicitud anula su devengo).

revoke execute on function public.comision_devengo_anular_lawang(uuid, text) from authenticated;

create or replace function public._trg_contrato_closer_devengos_vivos()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_ant text := lower(btrim(coalesce(old.closer_email, '')));
begin
  if v_ant <> '' then
    if exists (select 1 from public.comisiones_devengadas d
                 left join public.solicitudes_pago sp on sp.id = d.solicitud_id
                where d.contrato_raiz_id = old.contrato_id and d.estado <> 'anulada'
                  and lower(d.beneficiario_email) = v_ant and d.nivel in ('closer', 'estandar', 'propia')
                  and (d.estado <> 'pendiente' or sp.estado in ('aprobada', 'pagada'))) then
      raise exception 'Esta venta tiene comisión ya pagada, aprobada o en disputa al closer anterior: el cambio de closer lo regulariza administración'
        using errcode = '22023';
    end if;
    if exists (select 1 from public.comisiones_devengadas d
                where d.contrato_raiz_id = old.contrato_id and d.estado <> 'anulada'
                  and lower(d.beneficiario_email) = v_ant and d.nivel in ('closer', 'estandar', 'propia')) then
      raise exception 'El closer anterior tiene comisiones pendientes en esta venta: anula antes, con motivo, la comisión pendiente del closer anterior (Comisiones → Reparto a closers, o pide a administración que anule su solicitud de pago en Comisiones → Pagos de Lawang). Así el nuevo closer no cobra lo que devengó el anterior'
        using errcode = '22023';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end $function$;
