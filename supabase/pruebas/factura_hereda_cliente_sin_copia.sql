-- Prueba de 20261015101518_factura_hereda_cliente_sin_copia (15-oct-2026, sesión lawang-cola-2).
-- El trigger se prueba ENTERO sin dar de alta facturas reales: se engancha la función real a una tabla temporal con las tres
-- columnas que lee (contrato_id, client_id, proyecto_id). Así no se gasta la serie fiscal ni se pasa por topes y cadenas.
-- H1 alta sin cliente: hereda el adquiriente_1 de contrato_compradores y el proyecto del contrato. H2 la copia del jsonb
-- apunta a OTRA ficha: manda la tabla. H3 contrato con copia en el jsonb y SIN fila adquiriente_1: la factura nace sin
-- cliente (antes heredaba la copia; es el único caso que cambia, y la guarda de la migración exige que no exista en la viva).
-- H4 cliente puesto a mano: se respeta. H5 sin contrato: no toca nada. H6 el trigger real de facturas sigue en esta función,
-- antes de insert y de update de contrato_id/client_id/proyecto_id. H7 la función ya no lee la copia. H8 nadie de fuera la
-- ejecuta. H9 cuenta lo que mide la guarda (en la rama, que no trae datos, sale 0 sin medir nada: el número de verdad es el
-- de la guarda al aplicar en la viva). Montaje propio (la rama de Lawang es solo estructura): fichas ZZ-FH A y B con triggers,
-- y con replica el proyecto y el contrato ZZ-FH-K1 con A de adquiriente_1 y de copia.
-- !! Da de alta y toca filas dentro de la transacción: SOLO EN RAMA, NUNCA EN LA BASE VIVA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261015101518_factura_hereda_cliente_sin_copia.sql --prueba factura_hereda_cliente_sin_copia.sql
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada línea acaba en «→ ok» o «→ FALLA».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
create temp table _f (contrato_id uuid, client_id uuid, proyecto_id uuid);
create trigger trg_zz_fh before insert on _f for each row execute function public.factura_hereda_cliente();

do $todo$
declare
  r text := ''; n bigint;
  c1 uuid; p1 uuid; k1 uuid; k2 uuid; f _f;
  c_fin constant text := 'FIN DE PRUEBAS FACTURA HEREDA CLIENTE SIN COPIA (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS FACTURA HEREDA CLIENTE SIN COPIA:%', E'\nP0 esta prueba toca contratos: solo corre en rama → FALLA';
  end if;
  -- montaje PROPIO (la rama de Lawang es solo estructura, sin datos: Backend, consulta de 844225609). Las fichas, CON triggers (abajo);
  -- proyecto, contrato y comprador, sin triggers (replica): ni numeración, ni sincronización de compradores, ni claves ajenas de
  -- empresa; la columna generada adq1_client_id sí se calcula.
  -- Ficha A = adquiriente_1 y copia del jsonb; ficha B = la otra. Todo marcado ZZ-FH.
  begin
    -- las fichas, CON triggers: numero_cliente es NOT NULL y solo lo pone trg_clients_numero_cliente (revisor de 4e65cd2fa);
    -- propietario explícito porque sin sesión trg_clients_pone_dueno caería a auth.email(), null (como recibi_total_suma_y_exento)
    insert into public.clients (full_name, propietario) values ('ZZ-FH Cliente A', 'zz-fh@prueba.invalid') returning id into k1;
    insert into public.clients (full_name, propietario) values ('ZZ-FH Cliente B', 'zz-fh@prueba.invalid') returning id into k2;
    execute 'set local session_replication_role = replica';
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-FH Proyecto', 'zz-fh-proyecto', 'zz_fh', true) returning id into p1;
    insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por)
      values ('ZZ-FH-K1', 'contrato_general', p1, 'EUR', 1000, jsonb_build_object('fields', '{}'::jsonb, 'adq1_client_id', k1::text),
              'zz-fh@prueba.invalid') returning id into c1;
    insert into public.contrato_compradores (contrato_id, client_id, rol) values (c1, k1, 'adquiriente_1');
    execute 'set local session_replication_role = origin';
  exception when others then
    r := r || pg_temp.l(false, 'P0 montaje (fichas A y B, proyecto y contrato ZZ-FH-K1): ' || sqlstate || ' ' || left(sqlerrm, 300));
    raise exception using message = replace(c_fin, '%', r);
  end;
  r := r || pg_temp.l((select adq1_client_id from public.contratos where id = c1) = k1
                      and (select client_id from public.contrato_compradores where contrato_id = c1 and rol = 'adquiriente_1') = k1,
                      'P0 montaje: ZZ-FH-K1 con A como adquiriente_1 y como copia del jsonb');

  insert into _f values (c1, null, null) returning * into f;
  r := r || pg_temp.l(f.client_id = k1 and f.proyecto_id = p1, 'H1 alta sin cliente: hereda adquiriente_1 y proyecto del contrato');

  -- sin triggers (replica): ni contrato_guarda ni trg_sincronizar_compradores deben tocar la fila de la tabla ni dar un 42501 sin
  -- sesión; la columna generada adq1_client_id se recalcula igual (es generada, no trigger)
  execute 'set local session_replication_role = replica';
  update public.contratos set datos = jsonb_set(coalesce(datos, '{}'::jsonb), '{adq1_client_id}', to_jsonb(k2::text)) where id = c1;
  execute 'set local session_replication_role = origin';
  r := r || pg_temp.l((select adq1_client_id from public.contratos where id = c1) = k2
                      and (select client_id from public.contrato_compradores where contrato_id = c1 and rol = 'adquiriente_1') = k1,
                      'H2a montaje: la copia del jsonb dice otra ficha y la tabla sigue con la suya');
  insert into _f values (c1, null, null) returning * into f;
  r := r || pg_temp.l(f.client_id = k1, 'H2 la copia del jsonb apunta a otra ficha: manda contrato_compradores');

  execute 'set local session_replication_role = replica';   -- quitar la fila sin que nada la reponga desde el jsonb
  delete from public.contrato_compradores where contrato_id = c1 and rol = 'adquiriente_1';
  execute 'set local session_replication_role = origin';
  insert into _f values (c1, null, null) returning * into f;
  r := r || pg_temp.l(f.client_id is null and f.proyecto_id = p1,
                      'H3 copia en el jsonb y sin adquiriente_1: nace sin cliente (antes heredaba la copia), el proyecto sí');

  insert into _f values (c1, k2, null) returning * into f;
  r := r || pg_temp.l(f.client_id = k2, 'H4 cliente puesto a mano: se respeta');
  insert into _f values (null, null, null) returning * into f;
  r := r || pg_temp.l(f.client_id is null and f.proyecto_id is null, 'H5 sin contrato: no toca nada');

  select count(*) into n from pg_trigger t
   where t.tgrelid = 'public.facturas'::regclass and t.tgname = 'trg_factura_hereda_cliente' and not t.tgisinternal
     and t.tgfoid = 'public.factura_hereda_cliente()'::regprocedure
     and pg_get_triggerdef(t.oid) ~* 'BEFORE INSERT OR UPDATE OF contrato_id, client_id, proyecto_id';
  r := r || pg_temp.l(n = 1, 'H6 trg_factura_hereda_cliente sigue en la función, before insert y update de sus tres columnas');

  r := r || pg_temp.l((select prosrc !~* 'adq1' from pg_proc where oid = 'public.factura_hereda_cliente()'::regprocedure),
                      'H7 la función ya no lee la copia del jsonb');
  r := r || pg_temp.l(not has_function_privilege('authenticated', 'public.factura_hereda_cliente()', 'execute')
                      and not has_function_privilege('anon', 'public.factura_hereda_cliente()', 'execute'),
                      'H8 ni authenticated ni anon la ejecutan');

  select count(*) into n from public.contratos c
   where c.id <> c1 and c.adq1_client_id is not null
     and not exists (select 1 from public.contrato_compradores cc where cc.contrato_id = c.id and cc.rol = 'adquiriente_1');
  r := r || pg_temp.l(n = 0, 'H9 contratos (fuera del de H3) con copia y sin adquiriente_1: ' || n
                      || ' (en rama sin datos no mide: lo mide la guarda al aplicar)');

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
