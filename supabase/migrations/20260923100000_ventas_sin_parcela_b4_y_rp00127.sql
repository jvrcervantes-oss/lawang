-- Ventas cobradas sin parcela enlazada: dos casos resueltos — 23-sep-2026, owner
-- ----------------------------------------------------------------------------
-- 1) Bonian B4. RP00025 (Bloqueo, 39.220 EUR cobrados) y CC00008 (Construcción,
--    mismos 4 compradores) estaban sueltas y la parcela colgaba de la
--    construcción. Convención de las 94 cadenas existentes: la RP es la raíz,
--    la construcción cuelga de ella y la parcela apunta a la raíz. Sin esto el
--    motor de comisiones no ve suelo en RP00025 y el «50% del suelo» no se
--    cumple nunca. Solo cambia el enlace interno: ningún PDF firmado.
-- 2) RP00127 (Palm Field B6) era un contrato de prueba a nombre del owner.
--    Se libera. libera_reserva() no sirve aquí (exige parcela reservada por el
--    contrato y RP00127 no tiene ninguna), así que se usa la misma llave de
--    transacción que ella (app.via_libera_reserva) y el mismo evento en el
--    historial. Su recibí de 10.000 EUR no se toca aquí.

update public.contratos
   set contrato_padre_id = (select id from public.contratos where numero = 'RP00025')
 where numero = 'CC00008' and contrato_padre_id is null;

update public.unidades
   set contrato_id = (select id from public.contratos where numero = 'RP00025')
 where codigo = 'B4'
   and contrato_id = (select id from public.contratos where numero = 'CC00008');

select set_config('app.via_libera_reserva', 'on', true);

update public.contratos
   set liberado_en = now(), liberado_motivo = 'desistida'
 where numero = 'RP00127' and liberado_en is null;

insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
select id, 'reserva_liberada',
       jsonb_build_object('motivo', 'desistida', 'nota', 'Contrato de prueba, no es una venta (owner, 23-sep-2026)'),
       'sistema:owner-23sep'
  from public.contratos
 where numero = 'RP00127'
   and not exists (select 1 from public.contrato_eventos e
                    where e.contrato_id = contratos.id and e.evento = 'reserva_liberada');
