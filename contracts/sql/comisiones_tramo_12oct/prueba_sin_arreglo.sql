-- PRUEBA DE CONTROL (sin arreglo) — 12-oct-2026. Un solo bloque DO que TERMINA en raise exception:
-- todo lo que escribe se deshace. Demuestra que, con el tramo_id como está hoy, el camino real de una firma
-- (lo que hace _trg_comisiones_reconcilia_contrato: comisiones_reconciliar + comisiones_evaluar_contrato;
-- los triggers de facturas y recibi_aplicaciones llaman solo a comisiones_evaluar_contrato) SÍ crea un
-- segundo devengo y una segunda solicitud de pago en cada uno de los 6 contratos.
-- Resultado esperado: «devengos 6 -> 12, solicitudes 6 -> 12» y por contrato «2 dev / 2 sp», sin ningún «ERROR»
-- en el detalle. Un contrato que no llegue a 2 dev / 2 sp no tiene control: su prueba con arreglo no demuestra nada.
--
-- Efectos fuera de la transacción que puede disparar este camino (revisado en las funciones vivas el 12-oct):
--   · Secuencias: cada solicitud insertada gasta un número de solicitudes_pago_numero_seq (identity) aunque
--     se deshaga → se quemarán hasta 6 números SP (p. ej. SP-114..119); la próxima real saldrá con el
--     siguiente. Sin efecto en dinero: la numeración SP ya tiene 95 huecos (max 113, 18 filas). Si
--     reconciliar creara una diferencia gastaría también un DIF-xxxxx (medido hoy: 0 diferencias, no se espera).
--     comisiones_ajustes_log.id (identity) igual: hueco invisible.
--   · Correos y avisos: _trg_solicitud_pago_aviso y _avisar_managers solo INSERTAN en notificaciones
--     (email_pendiente); el envío lo hace un proceso que lee filas ya confirmadas → al deshacerse no existen.
--     notificaciones no tiene triggers.
--   · pg_net / dblink / http / NOTIFY: ninguna función del camino los llama (comisiones_evaluar_contrato,
--     comisiones_reconciliar, _comision_devengo_reponer, _comision_diferencia_solicitud, triggers de
--     solicitudes_pago). pg_net además encola en una tabla, que también se deshace.
--   · now()/auth.uid(): sin sesión de usuario, creado_por cae al beneficiario (como en la migración del 10 %).

do $$
declare
  v_raices uuid[] := array[
    '6ac803d6-12fa-4e5d-adf1-cfd35910d34f',  -- RP00164
    'e73fa119-c48d-4470-8a52-1127a0727751',  -- RP00181
    '267ff2c0-1d90-4c97-84f7-4d306896be1b',  -- RP00211
    'e82e3db0-5cd5-4e60-b836-0a1dfb95868c',  -- RP00161
    'ae3b8523-76ab-4e4d-b348-ee1366c146ec',  -- RP00162
    'c1abc6f8-15ca-4e87-80e8-390f21cfc32d'   -- RP00200
  ]::uuid[];
  v_dev0 int; v_sp0 int; v_dev1 int; v_sp1 int; v_imp0 numeric; v_imp1 numeric;
  v_det text := '';
  r record;
begin
  select count(*), sum(coalesce(importe_ajustado, importe)) into v_dev0, v_imp0
    from public.comisiones_devengadas where contrato_raiz_id = any(v_raices) and estado <> 'anulada';
  select count(*) into v_sp0
    from public.solicitudes_pago where contrato_id = any(v_raices) and origen = 'comision_automatica' and estado <> 'anulada';

  for r in select c.id, c.numero from public.contratos c where c.id = any(v_raices) order by c.numero loop
    begin
      perform public.comisiones_reconciliar(r.id, false, jsonb_build_object('origen', 'prueba_tramo_12oct'));
      perform public.comisiones_evaluar_contrato(r.id);
    exception when others then
      v_det := v_det || r.numero || ' ERROR ' || sqlerrm || '; ';
    end;
    v_det := v_det || r.numero || ' '
      || (select count(*) from public.comisiones_devengadas d where d.contrato_raiz_id = r.id and d.estado <> 'anulada') || ' dev / '
      || (select count(*) from public.solicitudes_pago s where s.contrato_id = r.id and s.origen = 'comision_automatica' and s.estado <> 'anulada') || ' sp; ';
  end loop;

  select count(*), sum(coalesce(importe_ajustado, importe)) into v_dev1, v_imp1
    from public.comisiones_devengadas where contrato_raiz_id = any(v_raices) and estado <> 'anulada';
  select count(*) into v_sp1
    from public.solicitudes_pago where contrato_id = any(v_raices) and origen = 'comision_automatica' and estado <> 'anulada';

  raise exception 'PRUEBA SIN ARREGLO (se deshace todo): devengos % -> %, solicitudes % -> %, importe devengado % -> % | %',
    v_dev0, v_dev1, v_sp0, v_sp1, v_imp0, v_imp1, v_det;
end $$;
