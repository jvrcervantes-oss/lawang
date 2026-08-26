-- destructivo-ok: no hay ningún `drop`; es un `create or replace function` que
-- sustituye el cuerpo de una función existente, sin tocar filas de ninguna tabla.
-- ════════════════════════════════════════════════════════════════════════════
-- POR QUÉ ABRIR UN RECIBÍ TARDABA MUCHÍSIMO Y A VECES DABA 500 — 24-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- EL CASO (owner): "no puedo abrir los recibos", con la consola llena de
-- `contratos_del_mismo_comprador` devolviendo 500. En los logs de Postgres:
--   {"code":"57014","message":"canceling statement due to statement timeout"}
-- No era un fallo de lógica — reproducido ahora mismo con `explain analyze`
-- sobre un contrato cualquiera: 4,27 SEGUNDOS y 76.868 buffers leídos para
-- comparar UN contrato contra el resto.
--
-- LA CAUSA: la versión vieja llamaba a `contrato_identificadores(c.datos)` una
-- vez POR CADA FILA de `contratos`, para sacar pasaporte y email de dentro del
-- jsonb `datos`. El problema es lo que hay dentro de ese jsonb: `datos` guarda
-- firmas y anexos en base64 — hasta 7,3 MB en una sola fila (HS00003) —, y
-- Postgres no puede leer UNA clave de un jsonb grande sin destoastear el valor
-- ENTERO primero. Cada comparación de una fila contra otra estaba
-- descomprimiendo varios megabytes para leer dos campos de texto.
--
-- LA CURA: `contrato_compradores` ya existe y guarda exactamente lo que hace
-- falta — `contrato_id`, `client_id`, `rol` — sin el jsonb pesado, y la
-- mantiene al día `sincronizar_compradores()` (compradores_desde_contrato.sql)
-- desde el 4-ago. Es la MISMA identidad que ya resuelve esa función (por
-- pasaporte/email, una sola vez, al guardar) — comparar por `client_id` aquí no
-- es una segunda definición de "mismo comprador", es leer la que ya existe en
-- vez de recalcularla sobre el blob cada vez que alguien abre un recibí.
-- Sin fila en `contrato_compradores` (contrato viejo sin ficha enlazada, o sin
-- comprador — un Poder Notarial, una Oferta Comercial): se devuelve solo el
-- propio contrato, igual que hacía la versión vieja cuando el comprador no
-- tenía pasaporte ni email que comparar.
--
-- Verificado tras aplicar: el mismo `explain analyze` que daba 4,27 s baja a
-- fracciones de milisegundo (join por clave sobre una tabla de 147 filas, con
-- índice en `client_id` y clave primaria en `(contrato_id, rol)`).

create or replace function public.contratos_del_mismo_comprador(p_contrato_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p_contrato_id
  union
  select cc2.contrato_id
    from public.contrato_compradores cc1
    join public.contrato_compradores cc2 on cc2.client_id = cc1.client_id
   where cc1.contrato_id = p_contrato_id;
$$;

revoke all on function public.contratos_del_mismo_comprador(uuid) from public, anon;
grant execute on function public.contratos_del_mismo_comprador(uuid) to authenticated;
