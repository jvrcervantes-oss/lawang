-- destructivo-ok: DROP CONSTRAINT de un CHECK, no toca filas ni borra datos —
-- se sustituye por una versión que no rompe el histórico.
--
-- Hallazgo de Administración (12-ago, mismo día que se creó el constraint
-- anterior): un CHECK sin excepción de fecha se re-evalúa en CUALQUIER UPDATE
-- de una fila, no solo si se toca contrato_id. Había 12 documentos reales
-- (3 factura + 9 recibí, todos del 4-ago-2026, antes de que 'contrato
-- obligatorio' existiera) con contrato_id NULL — anularlos, marcarlos
-- enviados o tocarlos de cualquier forma habría fallado con violación de
-- constraint desde hoy mismo, justo el camino de corrección que la propia
-- herramienta prescribe (una factura emitida se anula, no se edita).
--
-- Se exime por fecha de creación: solo los documentos creados a partir de
-- hoy (12-ago-2026, cuando "contrato obligatorio" empezó a regir) tienen
-- que cumplir el check. El histórico anterior queda editable/anulable sin
-- backfillear contrato_id a mano en 12 filas reales.
alter table public.facturas
  drop constraint if exists facturas_contrato_obligatorio;

alter table public.facturas
  add constraint facturas_contrato_obligatorio
  check (contrato_id is not null or created_at < '2026-08-12 00:00:00+00')
  not valid;

-- Sin NOT VALID el ALTER escanea toda la tabla al crearse; con la excepción
-- de fecha ya no hay ninguna fila que lo incumpla (las 12 huérfanas quedan
-- exentas por fecha), así que se puede validar del todo sin miedo a
-- descubrir una 13ª a medio camino.
alter table public.facturas
  validate constraint facturas_contrato_obligatorio;;
