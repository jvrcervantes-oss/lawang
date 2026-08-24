-- ============================================================================
-- Dos columnas baratas para lo que los listados leían del jsonb — 24-ago-2026
--
-- EL PROBLEMA, medido y no supuesto. El panel «Contratos guardados» tardaba
-- **4.249 ms** en abrir. No por el número de contratos (son 112) ni por falta de
-- paginación: por UNA expresión del select,
--     nombre_contrato:datos->fields->>nombre_contrato
-- `contratos.datos` guarda 70 MB en 112 filas (los anexos viajan en base64
-- dentro), y Postgres descomprime un valor TOAST entero o nada. Pedir 30 bytes
-- del jsonb obliga a descomprimir los ~625 kB de cada fila. La misma consulta
-- sin nombrar `datos` tarda 0,37 ms.
--
-- Y el remate: `nombre_contrato` está **vacío en los 112 contratos**. Se pagaban
-- cuatro segundos y cuarto por leer un campo que nadie ha rellenado nunca.
--
-- POR QUÉ COLUMNAS GENERADAS Y NO UN TRIGGER. Un espejo con trigger funciona
-- —es lo que hace esta suite en otros sitios— pero necesita que alguien lo
-- mantenga y puede divergir si se escribe la columna a mano. `generated always
-- ... stored` lo calcula Postgres en cada escritura, no se puede escribir por
-- fuera y no hay nada que se olvide. La expresión es inmutable (`->` y `->>`
-- sobre jsonb lo son), que es lo único que exige.
--
-- ⚠️ NO se borra el campo del jsonb: `datos` sigue siendo la fuente y el
-- documento sigue imprimiéndose de ahí. Estas columnas son su reflejo para que
-- un LISTADO no tenga que abrir el jsonb — nada más. Y por ser generadas, no
-- pueden decir algo distinto que su origen.
--
-- CONSECUENCIA A TENER EN CUENTA: un `insert` que copie todas las columnas de
-- `contratos` (por ejemplo, clonando una fila con `select *`) fallará al
-- intentar escribir en una columna generada. Los inserts de la suite nombran sus
-- columnas, así que hoy no afecta a ninguno.
-- ============================================================================

alter table public.contratos
  add column if not exists nombre_contrato text
    generated always as (datos->'fields'->>'nombre_contrato') stored;

alter table public.contratos
  add column if not exists parcela_codigo text
    generated always as (datos->'fields'->>'parcela_codigo') stored;

comment on column public.contratos.nombre_contrato is
  'Reflejo generado de datos.fields.nombre_contrato. Existe para que los listados no tengan que descomprimir el jsonb (70 MB en 112 filas): leerlo de datos costaba 4,2 s.';
comment on column public.contratos.parcela_codigo is
  'Reflejo generado de datos.fields.parcela_codigo (puede ser una LISTA: «A4, A5»). Mismo motivo que nombre_contrato. La verdad del enlace sigue siendo unidades.contrato_id, no este texto.';
