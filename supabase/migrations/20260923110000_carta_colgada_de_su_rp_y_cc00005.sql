-- Carta colgada a mano de la RP que tiene la parcela + CC00005 a su Bloqueo — 23-sep-2026, owner
-- ----------------------------------------------------------------------------
-- 1) sincroniza_unidad_contrato() deja que una Carta de Reserva comparta
--    parcela con su Bloqueo (reserva_parcela) solo si coincide el pasaporte o
--    el email del comprador. Caso real que no pasaba: CR00020 se hizo a nombre
--    de Jorge Miguel Domingo y la venta se cerró luego a nombre de su empresa,
--    NUSA LIFE VENTURES (RP00140, C5 de Bonian). Añadir a Jorge como
--    representante no servía: contrato_identificadores() no lee ese campo, y
--    meterlo como comprador en RP00140 sería falso.
--    Excepción nueva: también pasa si la Carta está colgada EXPLÍCITAMENTE de
--    la RP que tiene la parcela (contrato_padre_id = ocupada_id). No abre una
--    segunda venta: la parcela sigue en la RP y la Carta no se la lleva
--    (`continue`). Cualquier otra coincidencia entre compradores distintos se
--    sigue frenando igual.
-- 2) CR00020 cuelga de RP00140 (sus 1.000 EUR cuentan para esa venta).
-- 3) CC00005 (construcción de José Pedro Otón, 45.000 EUR cobrados) estaba
--    suelta; cuelga de RP00013, su Bloqueo con la SH-10 de Sumba Hills.
-- El parche se aplica sobre la definición viva y falla si no encuentra el punto.

do $$
declare
  v_def   text := pg_get_functiondef('public.sincroniza_unidad_contrato()'::regprocedure);
  v_marca text := 'and ocupada_tipo = ''reserva_parcela''
         and ids_nuevo && ids_ocupa then';
begin
  if position('new.contrato_padre_id = ocupada_id' in v_def) > 0 then
    return; -- ya aplicado
  end if;
  if position(v_marca in v_def) = 0 then
    raise exception 'sincroniza_unidad_contrato: no se encuentra el punto de inserción; revisar a mano';
  end if;
  execute replace(v_def, v_marca, 'and ocupada_tipo = ''reserva_parcela''
         and (ids_nuevo && ids_ocupa or new.contrato_padre_id = ocupada_id) then');
end $$;

update public.contratos
   set contrato_padre_id = (select id from public.contratos where numero = 'RP00140')
 where numero = 'CR00020' and contrato_padre_id is null;

update public.contratos
   set contrato_padre_id = (select id from public.contratos where numero = 'RP00013')
 where numero = 'CC00005' and contrato_padre_id is null;
