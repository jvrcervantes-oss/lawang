-- Devengos cuyo tramo es de OTRA condición, en toda la tabla (solo lectura).
-- 12-oct-2026: antes del arreglo da 6 filas (las reapuntadas por 20261012190000); después tiene que dar 0.
-- Por qué importa: comisiones_evaluar_contrato busca el devengo previo por el tramo de la condición fijada;
-- si el tramo guardado es de otra condición no lo ve e inserta un segundo devengo con su solicitud de pago.
select c.numero, cd.id, cd.condicion_id, cd.tramo_id, t.condicion_id as tramo_de, cd.estado, cd.importe
  from public.comisiones_devengadas cd
  join public.contratos c on c.id = cd.contrato_raiz_id
  join public.condicion_tramos t on t.id = cd.tramo_id
 where t.condicion_id <> cd.condicion_id
 order by c.numero;
