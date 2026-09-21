/* RF 1.4 (Riverfront I): su Bloqueo de Parcela y su Construcción se crearon el
   15-sep-2026 con `moneda='EUR'`, con el MISMO importe en rupias que ya llevaba
   la unidad. 21-sep-2026, mismo día que se corrigió el mislabel de visualización
   del cajón de unidades en Proyectos v4 — este es el mismo fallo, un nivel más
   arriba: la moneda de un contrato no se hereda de la unidad/proyecto al
   crearlo, así que queda a mano de quien lo redacta.

   Cómo se vio: el owner reportó "Capital Total Invertido" (Compradores) y
   "Volumen en Curso" (Operaciones) enseñando ~2.770.000.000 EUR — dos KPI que
   solo suman contratos con moneda='EUR' (dinero.js: nunca se mezclan monedas).
   RP00169 (reserva_parcela, RF 1.4) tenía `precio_total` 1.033.500.000 y
   CC00096 (construcción, hijo de RP00169) 1.726.000.000, ambos `moneda='EUR'`
   — la misma cifra en rupias que `unidades.precio_suelo`/`precio_construccion`
   de RF 1.4 (que sí están en IDR, correctas desde la migración 20260826124756).

   Comparado con el contrato gemelo RP00163/CC00095 de RF 1.1 (mismo proyecto,
   mismos importes, un día antes): ese SÍ se creó en IDR — lo que confirma que
   el dato correcto es rupias y que el fallo es de captura, no de origen.

   SEGURO de hacer, confirmado por el owner (21-sep-2026):
   - Ninguno de los dos contratos está `bloqueado` (sin firmar).
   - Cero filas en `contrato_firmas` para ninguno de los dos — no se ha pedido
     firma con el importe equivocado delante de nadie.
   - Los 3 documentos que cuelgan de ellos (PRO00179, PRO00180, la factura
     INV00138) tienen `enviada=false` y `anulada=false`: existen en el sistema
     pero no han salido hacia el comprador (Mariano Balestrieri). Se corrigen
     también — nacieron del mismo `precio_total` equivocado y quedarían
     contradiciendo al contrato si no.
   - Cero recibís contra ninguno de los dos: no hay dinero real de por medio
     que ya se moviera bajo el importe/moneda equivocados.

   Solo se toca `moneda`. Los IMPORTES no se convierten: ya estaban en rupias,
   lo que estaba mal era la etiqueta — igual que en la migración de las
   unidades. */
update public.contratos
   set moneda = 'IDR'
 where numero in ('RP00169', 'CC00096')
   and coalesce(moneda, '') is distinct from 'IDR';

update public.facturas
   set moneda = 'IDR'
 where numero in ('PRO00179', 'PRO00180', 'INV00138')
   and coalesce(moneda, '') is distinct from 'IDR';
