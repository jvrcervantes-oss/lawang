-- LAW-611 · W3 - C3 (RP00070) pasa de «vendida» a «bloqueada» — 15-oct-2026, sesión lawang-cola-2 (orquestador agencia-c0).
-- Cambio de DATOS, una fila de unidades y su fila de historial.
--
-- Qué pasa: la parcela W3 - C3 figura «vendida» con el Bloqueo RP00070 SIN firmar y el suelo cobrado al 67 % (22.250 de 33.250).
-- Con la regla de hoy no lo estaría, y la bajada automática (avanza_unidad_por_cobro) solo baja con el Bloqueo firmado.
-- Decisión del owner: opción (a), pasarla a «bloqueada» a mano. La regla para las demás no cambia.
--
-- Medido antes (migraciones 20261007035823, 20261007051946, 20260921060542 y 20261014032925):
--   · trg_unidad_vendida_exige_cobro solo frena al ENTRAR en vendida/cobrada: bajar a bloqueada no lo dispara; no hace falta la
--     excepción app.unidad_estado_excepcion (y no se usa: su historial diría «excepcion decidida por el owner» sin el porqué).
--   · trg_protege_liberado_contrato es de contratos (que no se toque liberado_en fuera de libera_reserva): aquí no se toca ningún
--     contrato.
--   · trg_unidad_estado_al_historial (diferido: corre al confirmar) no escribe su fila si ya hay una de esta transacción
--     (mismo en = now(), mismo antes y después): la fila con el motivo de LAW-611 se escribe aquí y la suya se omite. El ensayo
--     lo comprueba forzando los diferidos (set constraints all immediate) antes de contar.
--   · avanza_unidad_por_cobro deja una «bloqueada» como está mientras su Bloqueo no esté firmado: no la vuelve a subir.
--   · trg_unidad_estado_aviso_manager avisa a los managers del proyecto («Unidad W3 - C3 — bloqueada»): es el aviso interno de
--     siempre en un cambio de estado.
-- 89.000 frente a 95.000: la unidad tiene construcción 89.000 de catálogo; el contrato de obra CC00032 (borrador) dice 95.000.
-- La cascada ya usa el del contrato (owner 14-oct: «manda el contrato»), y unidad_cumple_estado('cobrada') toma el mayor. No es
-- otro fallo ni se toca aquí.
-- Guardas: la unidad por el id del contrato, su código, «vendida», el Bloqueo sin firmar y sin liberar, y que hoy NO cumple
-- vendida. Cualquier desajuste PARA y no escribe nada.
-- Lo prueba el ensayo deshecho contracts/sql/ensayo_law610_612_viva.sql (marca «RES LAW610-612»).
-- Reversión: update public.unidades set estado = 'vendida' where id = <la de W3 - C3> con
-- set_config('app.unidad_estado_excepcion', 'on', true) (subir a vendida sin el suelo cobrado es la excepción del owner).
do $law611$
declare
  c_raiz constant uuid := '40f7bd40-52e5-431e-a7ab-0f8f3752ff52';   -- RP00070
  v_r record; v_u public.unidades; v_n int; v_despues jsonb; v_estado text;
begin
  select c.numero, c.tipo, coalesce(c.bloqueado, false) as firmado, c.liberado_en into v_r
    from public.contratos c where c.id = c_raiz;
  if not found or v_r.numero <> 'RP00070' or v_r.tipo <> 'reserva_parcela' or v_r.firmado or v_r.liberado_en is not null then
    raise exception 'PARADA LAW-611: RP00070 no está como se midió (numero %, tipo %, firmado %, liberado %)',
      v_r.numero, v_r.tipo, v_r.firmado, v_r.liberado_en;
  end if;
  select count(*) into v_n from public.unidades u where u.contrato_id = c_raiz;
  select * into v_u from public.unidades u where u.contrato_id = c_raiz for update;
  if v_n <> 1 or v_u.codigo <> 'W3 - C3' or v_u.estado <> 'vendida' then
    raise exception 'PARADA LAW-611: la parcela de RP00070 no es W3 - C3 vendida (unidades %, código %, estado %)',
      v_n, v_u.codigo, v_u.estado;
  end if;
  if public.unidad_cumple_estado(v_u.id, 'vendida', v_u.precio, v_u.precio_suelo) then
    raise exception 'PARADA LAW-611: W3 - C3 ya cumple «vendida» (el suelo está cobrado): no se baja';
  end if;

  v_despues := jsonb_set(to_jsonb(v_u), '{estado}', to_jsonb('bloqueada'::text));
  insert into public.unidades_log (unidad_id, antes, despues, motivo, via, por)
  values (v_u.id, to_jsonb(v_u), v_despues,
          'LAW-611: vuelve a bloqueada por decisión del owner (15-oct-2026): figuraba vendida con el Bloqueo RP00070 sin firmar '
          || 'y el suelo sin cobrar entero',
          'sql directo', 'migración LAW-611');
  update public.unidades u set estado = 'bloqueada' where u.id = v_u.id;

  select u.estado into v_estado from public.unidades u where u.id = v_u.id;
  if v_estado <> 'bloqueada' then
    raise exception 'PARADA LAW-611: tras el cambio W3 - C3 queda en «%»', v_estado;
  end if;
  raise notice 'LAW-611 ok: W3 - C3 vendida -> bloqueada, con su fila de historial';
end $law611$;
