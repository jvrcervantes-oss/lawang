-- Traspaso de ficha: bloquea los contratos y facturas que va a mover (13-oct-2026).
--
-- POR QUÉ: revisor-codigo, 2.ª vuelta sobre 20261013150901. Los ids de contratos
-- y facturas se leían sin bloqueo; si otra transacción cambiaba el client_id de
-- una factura entre esa lectura y el UPDATE, se movería la factura de un
-- cocomprador. Ahora la lectura toma `for update` sobre las filas que se mueven,
-- así la puerta, el control del receptor y el UPDATE ven exactamente lo mismo.
--
-- Parche sobre el cuerpo vivo (patrón «parchear función viva con marca»): se
-- sustituyen las dos lecturas literales y se aborta si alguna no está, para no
-- recompilar una función distinta de la que se cree.
do $mig$
declare
  v_def text := pg_get_functiondef('public.traspasar_cliente_con_documentos(uuid,text,text)'::regprocedure);
  v_c_old text := $t$select coalesce(array_agg(distinct cc.contrato_id), '{}') into v_contratos
    from public.contrato_compradores cc where cc.client_id = p_client_id;$t$;
  v_c_new text := $t$select coalesce(array_agg(s.id), '{}') into v_contratos
    from (select c.id from public.contratos c
           where c.id in (select cc.contrato_id from public.contrato_compradores cc where cc.client_id = p_client_id)
           order by c.id for update of c) s;$t$;
  v_f_old text := $t$select coalesce(array_agg(f.id), '{}') into v_facturas
    from public.facturas f
   where f.client_id = p_client_id or (f.contrato_id = any (v_contratos) and f.client_id is null);$t$;
  v_f_new text := $t$select coalesce(array_agg(s.id), '{}') into v_facturas
    from (select f.id from public.facturas f
           where f.client_id = p_client_id or (f.contrato_id = any (v_contratos) and f.client_id is null)
           order by f.id for update of f) s;$t$;
begin
  if position(v_c_old in v_def) = 0 then raise exception 'traspaso: no encuentro la lectura de contratos esperada'; end if;
  if position(v_f_old in v_def) = 0 then raise exception 'traspaso: no encuentro la lectura de facturas esperada'; end if;
  v_def := replace(replace(v_def, v_c_old, v_c_new), v_f_old, v_f_new);
  execute v_def;
end
$mig$;
