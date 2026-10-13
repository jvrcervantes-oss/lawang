-- Prueba de _cadena_saldo con piezas que acompañan a la venta (Poder, Hak Sewa, Adenda) e hijos en otra moneda —
-- regla definitiva 20261013062019_cadena_saldo_tope_se_queda_estrecho (13-oct-2026; sustituye a 060855 y 061519).
-- Se ejecuta por execute_sql DESPUÉS de aplicar: termina con un raise a propósito, así que no deja rastro (los
-- contratos ZZT-* se deshacen; llevan número propio para no gastar la secuencia real de numeración, y cuelgan del
-- proyecto de RP00170, que tiene empresa: sin empresa el contrato es invisible y la prueba mentiría).
-- Corre sin sesión (auth.uid() nulo): es_super_admin_de —la que usa _factura_tope_cadena— da false, así que el tope
-- va por el camino real (raise 23514) y no por el del privilegio. Cada línea dice OK o MAL; ninguna debe decir MAL.
-- Regla: un hijo que acompaña (tenga o no precio_total) y un hijo en otra moneda no entran en el precio ni en
-- «sin precio»: ante un dato que no debería estar, el tope se queda estrecho (contracts/app.html:536-543).
-- Resultado con la función original (20261005210000), 13-oct: MAL en A (sin_precio = true por el Poder; el tope de
-- 5.000 sobre 1.000 PASABA) y RP00170 (sin_precio = true). Con 061519 MAL en B y H (sumaba la Adenda y los
-- 900.000.000 del Hak Sewa). Con la definitiva: todo OK.
-- No se prueba una factura sobre una pieza: darla de alta gasta un número de la serie legal de facturas (nextval no
-- se deshace con el raise). La rama fa no cambia respecto a 20261005210000.
do $t$
declare out text := ''; p uuid; r1 uuid; r2 uuid; r3 uuid; r4 uuid; r6 uuid; s record; ok boolean; acl text;
begin
  select proyecto_id into p from public.contratos where numero = 'RP00170';
  out := out || 'super_admin sin sesión = ' || coalesce(public.es_super_admin_de(public._empresa_doc(null::uuid,
           (select id from public.contratos where numero = 'RP00170')))::text, 'null') || E' (debe ser false)\n';

  -- A: raíz 1.000 EUR + Poder, Hak Sewa y Adenda hijos sin precio → cuenta el precio de la raíz y el tope funciona
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos)
    values ('ZZT-A0', 'contrato_general', p, 'EUR', 1000, '{"hitos":[]}') returning id into r1;
  insert into public.contratos (numero, tipo, proyecto_id, precio_total, contrato_padre_id, datos)
    values ('ZZT-A1', 'poa', p, null, r1, '{"hitos":[]}'),
           ('ZZT-A2', 'hak_sewa_notario', p, null, r1, '{"hitos":[]}'),
           ('ZZT-A3', 'adenda', p, null, r1, '{"hitos":[]}');
  select * into s from public._cadena_saldo(r1, null);
  ok := s.precio = 1000 and not s.sin_precio;
  out := out || case when ok then 'OK ' else 'MAL ' end || 'A piezas sin precio: precio=' || coalesce(s.precio::text, 'null') || ' sin_precio=' || s.sin_precio || E'\n';
  begin perform public._factura_tope_cadena(null, r1, 'EUR', 5000, 'factura'); out := out || E'MAL A tope 5000 sobre 1000: PASA\n';
  exception when sqlstate '23514' then out := out || E'OK A tope 5000 sobre 1000: bloquea\n'; end;
  begin perform public._factura_tope_cadena(null, r1, 'EUR', 500, 'factura'); out := out || E'OK A tope 500 sobre 1000: pasa\n';
  exception when others then out := out || 'MAL A tope 500: ' || left(sqlerrm, 100) || E'\n'; end;

  -- B: una Adenda CON precio_total (no debería tenerlo: app.html:541) no infla el tope: precio 1.000, 1.100 bloquea
  insert into public.contratos (numero, tipo, proyecto_id, precio_total, contrato_padre_id, datos)
    values ('ZZT-A4', 'adenda', p, 200, r1, '{"hitos":[]}');
  -- H: un Hak Sewa hijo con su precio en Rp metido en precio_total (hereda moneda EUR) tampoco lo infla
  insert into public.contratos (numero, tipo, proyecto_id, precio_total, contrato_padre_id, datos)
    values ('ZZT-A5', 'hak_sewa_notario', p, 900000000, r1, '{"hitos":[]}');
  select * into s from public._cadena_saldo(r1, null);
  ok := s.precio = 1000 and not s.sin_precio;
  out := out || case when ok then 'OK ' else 'MAL ' end || 'B+H piezas CON precio no cuentan: precio=' || coalesce(s.precio::text, 'null') || ' sin_precio=' || s.sin_precio || E'\n';
  begin perform public._factura_tope_cadena(null, r1, 'EUR', 1100, 'factura'); out := out || E'MAL B tope 1100 sobre 1000: PASA\n';
  exception when sqlstate '23514' then out := out || E'OK B tope 1100 sobre 1000: bloquea\n'; end;

  -- C: raíz + Construcción hija SIN precio → sigue sin precio (no se excluye de más) y no aplica tope
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos)
    values ('ZZT-C0', 'contrato_general', p, 'EUR', 1000, '{"hitos":[]}') returning id into r2;
  insert into public.contratos (numero, tipo, proyecto_id, precio_total, contrato_padre_id, datos)
    values ('ZZT-C1', 'construccion', p, null, r2, '{"hitos":[]}');
  select * into s from public._cadena_saldo(r2, null);
  out := out || case when s.sin_precio then 'OK ' else 'MAL ' end || 'C construcción sin precio: sin_precio=' || s.sin_precio || E'\n';
  begin perform public._factura_tope_cadena(null, r2, 'EUR', 5000, 'factura'); out := out || E'OK C sin precio: no aplica tope\n';
  exception when others then out := out || 'MAL C tope: ' || left(sqlerrm, 100) || E'\n'; end;

  -- D: Hak Sewa suelto como raíz, sin precio → como siempre (sin precio)
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos)
    values ('ZZT-D0', 'hak_sewa_notario', p, null, null, '{"hitos":[]}') returning id into r3;
  select * into s from public._cadena_saldo(r3, null);
  out := out || case when s.sin_precio and s.precio is null then 'OK ' else 'MAL ' end || 'D Hak Sewa raíz suelto: precio=' || coalesce(s.precio::text, 'null') || ' sin_precio=' || s.sin_precio || E'\n';

  -- E: raíz sin precio + solo un Poder sin precio → sigue sin precio (ningún precio en la cadena)
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos)
    values ('ZZT-E0', 'contrato_general', p, 'EUR', null, '{"hitos":[]}') returning id into r4;
  insert into public.contratos (numero, tipo, proyecto_id, precio_total, contrato_padre_id, datos)
    values ('ZZT-E1', 'poa', p, null, r4, '{"hitos":[]}');
  select * into s from public._cadena_saldo(r4, null);
  out := out || case when s.sin_precio and s.precio is null then 'OK ' else 'MAL ' end || 'E sin ningún precio: precio=' || coalesce(s.precio::text, 'null') || ' sin_precio=' || s.sin_precio || E'\n';

  -- G: hijo en otra moneda que la raíz (Construcción cuya parcela va en IDR) no entra en el precio ni en «sin
  -- precio»: precio 1.000 EUR, y 5.000 EUR sobre 1.000 bloquea. Al dar de alta, trg_contrato_moneda_desde_unidad le
  -- pondría la moneda del padre (no hay parcela): se da de alta firmado y luego se cambia la moneda (el trigger no
  -- toca un contrato firmado); todo se deshace con el raise final.
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos)
    values ('ZZT-G0', 'contrato_general', p, 'EUR', 1000, '{"hitos":[]}') returning id into r6;
  insert into public.contratos (numero, tipo, proyecto_id, precio_total, contrato_padre_id, datos, bloqueado)
    values ('ZZT-G1', 'construccion', p, 5000000, r6, '{"hitos":[]}', true);
  update public.contratos set moneda = 'IDR' where numero = 'ZZT-G1';
  select * into s from public._cadena_saldo(r6, null);
  ok := s.precio = 1000 and not s.sin_precio;
  out := out || case when ok then 'OK ' else 'MAL ' end || 'G hijo en otra moneda fuera: precio=' || coalesce(s.precio::text, 'null') || ' sin_precio=' || s.sin_precio || E'\n';
  begin perform public._factura_tope_cadena(null, r6, 'EUR', 5000, 'factura'); out := out || E'MAL G tope 5000 sobre 1000: PASA\n';
  exception when sqlstate '23514' then out := out || E'OK G tope 5000 sobre 1000: bloquea\n'; end;

  -- Real: RP00170 (45.900 EUR con su Poder PA00010 sin precio) deja de estar «sin precio»
  select * into s from public._cadena_saldo((select id from public.contratos where numero = 'RP00170'), null);
  out := out || case when not s.sin_precio and s.precio > 0 then 'OK ' else 'MAL ' end || 'RP00170: precio=' || coalesce(s.precio::text, 'null') || ' sin_precio=' || s.sin_precio || E'\n';

  -- Privilegios: create or replace conserva el revoke de 20261005210000 (public, anon, authenticated, service_role)
  select coalesce(array_to_string(proacl, ' '), '(null)') into acl from pg_proc where oid = 'public._cadena_saldo(uuid,uuid)'::regprocedure;
  out := out || case when not has_function_privilege('anon', 'public._cadena_saldo(uuid,uuid)', 'execute')
                       and not has_function_privilege('authenticated', 'public._cadena_saldo(uuid,uuid)', 'execute')
                       and not has_function_privilege('service_role', 'public._cadena_saldo(uuid,uuid)', 'execute')
                       and acl <> '(null)' and acl !~ '(^| )=X'
                     then 'OK ' else 'MAL ' end || 'privilegios: sin execute para public/anon/authenticated/service_role (acl ' || acl || ')';
  raise exception E'RESULTADOS\n%', out;
end $t$;
