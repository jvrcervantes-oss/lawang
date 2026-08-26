/* RIVERFRONT I y II: sus precios están en RUPIAS, no en euros. 26-ago-2026,
   confirmado por el owner.

   Cómo se vio: al derivar el precio total de suelo+construcción (misma tarde),
   estas diez unidades dejaron de sumar 0 y aparecieron en el resumen de
   Proyectos con «Suelo 8.250.939.130,00 EUR» — mil millones de euros de suelo.
   RF 1.1 tenía `precio_suelo` 1.033.500.000 con `moneda='EUR'` para 276 m². Al
   cambio del estudio (20.500 IDR/EUR) son ~50.400 €, que sí es un precio de
   suelo plausible en Bali; en euros sería absurdo.

   Estaba ESCONDIDO detrás de un cero: sin total guardado, estas unidades no
   sumaban en ninguna vista, así que el error no tenía dónde notarse.

   La prueba de que la intención era IDR está en los propios datos: RF 1.3 ya
   estaba correctamente en IDR. Se cambian las otras nueve.

   SEGURO de hacer, comprobado antes: las diez están `disponible`, ninguna tiene
   contrato y ninguna tiene facturas. No cuelga nada de ellas — no hay un importe
   ya cobrado ni un documento emitido que quede contradiciendo esto.

   Solo se toca `moneda`. Los IMPORTES no se convierten: ya estaban en rupias, lo
   que estaba mal era la etiqueta. */
update public.unidades
   set moneda = 'IDR'
 where proyecto in ('Riverfront I', 'Riverfront II')
   and coalesce(moneda, '') is distinct from 'IDR';;
