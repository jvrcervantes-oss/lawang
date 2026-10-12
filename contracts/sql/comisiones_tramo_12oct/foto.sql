-- Foto de las 6 comisiones reapuntadas el 12-oct y de sus solicitudes de pago (solo lectura).
-- La misma consulta sirve de ANTES y de DESPUÉS de 20261012210000_comisiones_tramo_de_su_condicion:
-- entre una y otra solo puede cambiar tramo_id. huella_devengo y huella_solicitud son el md5 de la fila
-- entera (la del devengo SIN tramo_id): tienen que salir idénticas antes y después.
select c.numero,
       cd.id                as devengo_id,
       cd.condicion_id,
       cd.tramo_id,
       t.condicion_id       as tramo_de_condicion,
       cd.nivel,
       cd.estado,
       cd.importe,
       cd.importe_ajustado,
       cd.beneficiario_email,
       md5((to_jsonb(cd) - 'tramo_id')::text) as huella_devengo,
       sp.numero            as sp_numero,
       sp.importe           as sp_importe,
       sp.estado            as sp_estado,
       sp.concepto          as sp_concepto,
       md5(to_jsonb(sp)::text) as huella_solicitud
  from public.comisiones_devengadas cd
  join public.contratos c on c.id = cd.contrato_raiz_id
  join public.condicion_tramos t on t.id = cd.tramo_id
  left join public.solicitudes_pago sp on sp.id = cd.solicitud_id
 where cd.id in ('a23fb382-0771-40d6-8661-7e068cdfffb8',  -- RP00164
                 '99103540-0741-45f2-91f3-59e1fb3fe9f4',  -- RP00181
                 '95230454-a5b6-4a19-a926-8f429fa67f1c',  -- RP00211
                 'd347bd12-13f5-419f-9341-1b500437b2d8',  -- RP00161
                 '0338276a-5312-49bc-b282-61fbcd72cf3e',  -- RP00162
                 '1c493584-88ba-4fe1-b8f3-3affa186dcc9')  -- RP00200
 order by c.numero;
