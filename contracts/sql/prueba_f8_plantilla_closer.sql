-- F8 · prueba de regresion (SOLO LECTURA; nunca contrato_guarda en alta ni nextval).
-- Con la plantilla 25/75 sembrada, el devengo de closer de una venta de equipo es el 25 % del devengo del manager
-- para el mismo disparo (2,5 % de un 10 %). Debe devolver 0 filas.
select c.contrato_raiz_id, c.importe as closer, m.importe as manager
  from public.comisiones_devengadas c
  join public.comisiones_devengadas m on m.contrato_raiz_id = c.contrato_raiz_id and m.nivel = 'manager'
   and m.disparado_por_snapshot->>'disparador_tipo' = c.disparado_por_snapshot->>'disparador_tipo'
   and coalesce(m.disparado_por_snapshot->>'umbral', '') = coalesce(c.disparado_por_snapshot->>'umbral', '')
 where c.nivel = 'closer' and c.estado <> 'anulada' and m.estado <> 'anulada'
   and abs(c.importe - round(m.importe * 0.25, 2)) > 0.02;
