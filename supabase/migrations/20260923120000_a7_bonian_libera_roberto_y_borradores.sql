-- A7 de Bonian: se liberan la venta desistida de Roberto Godoy y dos borradores — 23-sep-2026, owner
-- ----------------------------------------------------------------------------
-- La A7 la reclamaban cuatro contratos de cuatro compradores distintos; la
-- unidad está en RP00172 (Antonio Carrillo). El owner confirma:
--   · Roberto Godoy desistió: se liberan RP00045 (raíz, 1.000 EUR cobrados),
--     CR00022 (Carta firmada) y CC00024 (construcción). Sus 1.000 EUR no se
--     tocan aquí: devolverlos o reaplicarlos es de Administración.
--   · CG00005 (Pinilla) y RP00018 (PT Rochas), de julio, sin firma ni cobro:
--     borradores muertos.
-- Ninguno tenía unidad atada ni comisión devengada (comprobado antes). Misma
-- llave de transacción que libera_reserva() y mismo evento en el historial.

select set_config('app.via_libera_reserva', 'on', true);

with liberados as (
  update public.contratos
     set liberado_en = now(), liberado_motivo = 'desistida'
   where numero in ('RP00045', 'CR00022', 'CC00024', 'CG00005', 'RP00018')
     and liberado_en is null
  returning id, numero
)
insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
select id, 'reserva_liberada',
       jsonb_build_object('motivo', 'desistida', 'nota',
         case when numero in ('RP00045', 'CR00022', 'CC00024')
              then 'Roberto Godoy desistió; la A7 de Bonian es de RP00172 (owner, 23-sep-2026)'
              else 'Borrador sin firma ni cobro que reclamaba la A7 de Bonian (owner, 23-sep-2026)' end),
       'sistema:owner-23sep'
  from liberados;
