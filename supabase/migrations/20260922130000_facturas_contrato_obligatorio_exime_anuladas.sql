-- destructivo-ok: DROP CONSTRAINT de un CHECK, no toca filas ni borra datos —
-- se sustituye por una versión que no rompe borrar_operacion().
--
-- Bug reportado por el owner (22-sep-2026): "Borrar operación" en
-- /intranet/operaciones/ falla con "No se pudo borrar: new row for relation
-- 'facturas' violates check constraint 'facturas_contrato_obligatorio'".
--
-- Mecanismo (confirmado con pg_get_constraintdef y una cuenta real antes de
-- tocar nada): facturas.contrato_id_fkey es ON DELETE SET NULL. borrar_operacion()
-- primero pone anulada=true en las facturas del contrato (paso pensado para no
-- dejar un hueco en la serie fiscal) y LUEGO borra el contrato — ese DELETE
-- dispara el SET NULL sobre contrato_id de esas mismas facturas, que es una
-- UPDATE implícita y por tanto reevalúa el CHECK. Cualquier factura creada
-- desde el 12-ago-2026 (cuando el check empezó a exigir contrato_id) queda con
-- contrato_id NULL y created_at demasiado reciente para la excepción existente
-- → violación, y la operación entera hace rollback. Verificado: 391 facturas
-- reales creadas desde el 12-ago tienen contrato_id — es decir, borrar
-- CUALQUIER operación con facturas recientes está roto desde esa fecha (41 días).
--
-- Fix: además de la excepción por fecha, se exime toda factura ya ANULADA. Es
-- coherente con el resto del motor: contrato_cobrado y comisiones_evaluar_contrato
-- ya excluyen f.anulada de cualquier cálculo de cobrado (LAW-38), así que una
-- factura anulada no necesita un contrato vivo al que apuntar. Y en
-- borrar_operacion(), CUALQUIER factura afectada por el SET NULL ya pasó por el
-- UPDATE anulada=true un paso antes (mismo WHERE contrato_id = any(ids)) — cero
-- excepción nueva para documentos vivos.
alter table public.facturas
  drop constraint if exists facturas_contrato_obligatorio;

alter table public.facturas
  add constraint facturas_contrato_obligatorio
  check (contrato_id is not null or created_at < '2026-08-12 00:00:00+00' or anulada)
  not valid;

-- La condición añadida (anulada) es estrictamente más permisiva que la
-- anterior: ninguna fila que ya cumplía puede dejar de cumplir. Se valida sin
-- riesgo de descubrir una fila rota a medio camino.
alter table public.facturas
  validate constraint facturas_contrato_obligatorio;;
