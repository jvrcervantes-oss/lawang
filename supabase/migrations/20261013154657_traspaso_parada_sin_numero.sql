-- Traspaso de ficha: la parada de «fila impura» también salta con un documento sin número (13-oct-2026).
--
-- POR QUÉ: consulta de Datos sobre 20261013150901. La parada 55000 se decidía con
-- `min(m.numero) filter (where not m.puro)`; `numero` admite NULL en contratos y
-- facturas (hoy 0 filas), así que una fila impura SIN número pasaría sin parar.
-- El gemelo del maestro ya usa `coalesce(m.numero, m.id::text)`: se iguala.
-- REVERTIR: el mismo replace al revés (coalesce(m.numero, m.id::text) -> m.numero).
do $mig$
declare
  v_def text := pg_get_functiondef('public.traspasar_cliente_con_documentos(uuid,text,text)'::regprocedure);
  v_old text := 'min(m.numero) filter (where not m.puro)';
  v_new text := 'min(coalesce(m.numero, m.id::text)) filter (where not m.puro)';
  v_n int;
begin
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 2 then raise exception 'traspaso: esperaba 2 paradas de fila impura y hay %', v_n; end if;
  execute replace(v_def, v_old, v_new);
end
$mig$;
