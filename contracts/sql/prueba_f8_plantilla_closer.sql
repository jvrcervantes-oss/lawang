-- F8 · prueba de regresion (SOLO LECTURA; nunca contrato_guarda en alta ni nextval).
-- El devengo de closer de una venta de equipo con plantilla congelada (snapshot plantilla_pct) es ese % del devengo del
-- manager para el mismo disparo (25 % => 2,5 % de un 10 %). Lee el % CONGELADO, no una constante: no da falsos positivos si
-- el SM edita luego su plantilla. Debe devolver 0 filas.
-- LIMITE HONESTO: no ejercita los caminos del motor (congelado, vuelta a la condicion, varias filas closer, reconciliador);
-- eso pide una venta de prueba y en produccion no se llama a contrato_guarda en alta ni se hace nextval (30-sep).
select c.contrato_raiz_id, c.importe as closer, m.importe as manager
  from public.comisiones_devengadas c
  join public.comisiones_devengadas m on m.contrato_raiz_id = c.contrato_raiz_id and m.nivel = 'manager'
   and m.disparado_por_snapshot->>'disparador_tipo' = c.disparado_por_snapshot->>'disparador_tipo'
   and coalesce(m.disparado_por_snapshot->>'umbral', '') = coalesce(c.disparado_por_snapshot->>'umbral', '')
 where c.nivel = 'closer' and c.estado <> 'anulada' and m.estado <> 'anulada'
   and c.disparado_por_snapshot->>'plantilla_pct' is not null
   and abs(c.importe - round(m.importe * (c.disparado_por_snapshot->>'plantilla_pct')::numeric / 100, 2)) > 0.02;
