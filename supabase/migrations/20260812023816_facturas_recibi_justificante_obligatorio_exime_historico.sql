-- destructivo-ok: DROP CONSTRAINT de un CHECK, no toca filas ni borra datos —
-- se sustituye por una versión que no rompe el histórico.
--
-- Encontrado hoy (12-ago) probando el mismo tipo de fallo que Administración
-- señaló para facturas_contrato_obligatorio: 14 recibís reales (28-jul a
-- 7-ago-2026, antes de que "justificante obligatorio" existiera desde
-- 11-ago) tienen justificante_path NULL. Un CHECK se re-evalúa en CUALQUIER
-- UPDATE de la fila, así que anular o tocar cualquiera de esos 14 recibís
-- fallaba con violación de constraint — confirmado en pruebas: un UPDATE
-- inocuo sobre uno de ellos disparaba justo este error.
--
-- Misma solución: se exime por fecha de creación, solo lo creado desde el
-- 11-ago-2026 (cuando la regla empezó a regir) tiene que cumplir el check.
alter table public.facturas
  drop constraint if exists facturas_recibi_justificante_obligatorio;

alter table public.facturas
  add constraint facturas_recibi_justificante_obligatorio
  check (tipo <> 'recibi' or justificante_path is not null or created_at < '2026-08-11 00:00:00+00')
  not valid;

alter table public.facturas
  validate constraint facturas_recibi_justificante_obligatorio;;
