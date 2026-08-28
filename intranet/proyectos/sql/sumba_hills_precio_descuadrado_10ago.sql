/* Sumba Hills: 141 parcelas con precio total descuadrado — 28-ago-2026.

   Hallazgo: la carga por CSV del 10-ago-2026 (183 parcelas de Sumba Hills,
   mismo `created_at` al minuto) trajo una columna de precio total que en 136
   de esas filas no cuadraba con precio_suelo+precio_construccion de la misma
   fila — más otras 5 filas sueltas de una carga anterior (7-ago), 141 en
   total. El patrón más claro: los totales de DALI (79.000) y DALI+ (89.000)
   aparecían intercambiados en buena parte de las filas.

   `unidades_estado` (supabase/migrations/20260826112241_unidades_estado_precio_efectivo.sql)
   ya hace lo correcto — un precio guardado manda sobre sus partes, a
   propósito, porque un descuento pactado es legítimo — pero aquí el precio
   guardado no era un descuento: era un dato de importación descuadrado.

   Confirmado por el owner (28-ago): DALI+ = 89.000 €, suelo siempre 35.000 €.
   Se generaliza la misma regla (total = suelo + construcción) a las 141.

   Auditoría en correcciones_datos ANTES del update — mismo patrón que
   autoria.js. Los 3 contratos ya abiertos sobre estas parcelas (SH-41
   RP00104, SH-59 RP00060, SH-105 CR00021) NO se tocan: `contratos.precio_total`
   es un campo propio, congelado, ajeno a esta corrección.

   Verificado tras aplicar: 0 parcelas descuadradas en Sumba Hills (de 228
   con desglose de suelo/construcción).

   Dos parcelas quedan con un suelo fuera de las dos tarifas estándar
   (SH-101: 38.250 €, SH-102: 39.750 €, ambas etiquetadas "DALI" pese a no
   tener el suelo de 25.000 € del resto de DALI) — ahora internamente
   consistentes (su propio suelo+construcción = su total), pero no se tocó su
   suelo: no hay forma de saber desde la base si es un precio real distinto o
   otro resto de la misma importación. Revisar aparte. */

insert into correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
select 'unidades', id, 'precio', precio::text, (precio_suelo::numeric + precio_construccion::numeric)::text,
  'CSV del 10-ago-2026 trajo un Total descuadrado con Suelo+Construccion (confirmado por el owner: DALI+ = 89.000, suelo siempre 35.000). Recalculado a Suelo+Construccion.',
  'ceo-sesion-01ULkYbpn98nJLbbGGE9uRVg'
from unidades
where proyecto = 'Sumba Hills' and precio_suelo is not null and precio_construccion is not null
  and precio::numeric <> (precio_suelo::numeric + precio_construccion::numeric);

update unidades
set precio = precio_suelo::numeric + precio_construccion::numeric
where proyecto = 'Sumba Hills' and precio_suelo is not null and precio_construccion is not null
  and precio::numeric <> (precio_suelo::numeric + precio_construccion::numeric);
