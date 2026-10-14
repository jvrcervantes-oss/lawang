-- Traspaso de ficha: al mover un contrato se mueven tambien sus facturas a nombre de OTRO comprador cuya ficha YA es del nuevo dueno (14-oct-2026).
--
-- POR QUE: decision del CEO por defecto (14-oct-2026, reversible), sobre 20261014000241. Una pareja del mismo agente que comparte un
-- contrato, traspasada en dos pasos, dejaba la factura a nombre del primer comprador con el agente anterior: en el paso 1 el contrato
-- se excluye (el otro comprador aun es del agente anterior); en el paso 2 el contrato ya se mueve, pero la factura estaba a nombre del
-- primer comprador y se contaba como «de otro comprador». Hacia falta un tercer traspaso (prueba Q1-Q3 de traspaso_arrastra_todo.sql).
-- QUE CAMBIA: v_facturas suma, de los contratos que SE MUEVEN, las facturas a nombre de otro comprador DE ESE contrato
-- (contrato_compradores) cuya ficha ya es del nuevo dueno. Las de un comprador sin dueno o con otro dueno siguen sin moverse. Al estar en
-- v_facturas pasan por la puerta por documento y por la comprobacion del receptor, y salen del recuento de facturas_omitidas_otro_autor.
-- Solo compradores del contrato: sus fichas son las que ya se bloquean FOR SHARE antes de decidir.
-- Parche del cuerpo vivo por sustitucion de texto: aborta si el ancla no esta exactamente una vez.
-- REVERTIR: el mismo replace al reves (v_new -> v_old) sobre pg_get_functiondef de public.traspasar_cliente_con_documentos(uuid,text,text),
--   o reaplicar 20261014000241, que reescribe la funcion entera con el cuerpo anterior. Sin datos que deshacer: no escribe nada al aplicarse.
do $mig$
declare
  v_def text := pg_get_functiondef('public.traspasar_cliente_con_documentos(uuid,text,text)'::regprocedure);
  v_old text := 'or (f.contrato_id = any (v_contratos) and f.client_id is null)';
  v_new text := 'or (f.contrato_id = any (v_contratos) and f.client_id is null)' || E'\n'
             || '              -- 14-oct: y las de OTRO comprador del contrato que se mueve cuya ficha ya es del nuevo dueno' || E'\n'
             || '              or (f.contrato_id = any (v_contratos) and f.client_id <> p_client_id'
             || ' and exists (select 1 from public.contrato_compradores o join public.clients oc on oc.id = o.client_id'
             || ' where o.contrato_id = f.contrato_id and o.client_id = f.client_id and lower(btrim(oc.propietario)) = v_nuevo))';
  v_n int;
begin
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception 'traspaso: esperaba 1 ancla de facturas sin cliente y hay %', v_n; end if;
  execute replace(v_def, v_old, v_new);
end
$mig$;
