-- Prueba de _cadena_saldo con piezas que acompañan a la venta (Poder, Hak Sewa, Adenda) — migraciones
-- 20261013060855_cadena_saldo_sin_piezas_que_acompanan y su corrección 20261013061519_cadena_saldo_pieza_con_precio_cuenta
-- (13-oct-2026). Se ejecuta por execute_sql DESPUÉS de aplicar: termina con un raise a propósito, así que no deja
-- rastro (los contratos ZZT-* se deshacen; llevan número propio para no gastar la secuencia real de numeración, y
-- cuelgan del proyecto de RP00170, que tiene empresa: sin empresa el contrato es invisible y la prueba mentiría).
-- Corre sin sesión (auth.uid() nulo): es_super_admin_de da false, así que _factura_tope_cadena va por el camino real
-- del tope (raise 23514) y no por el del privilegio (registra_privilegio). Cada línea dice OK o MAL; ninguna MAL.
-- Regla: una pieza hija SIN precio no deja la cadena «sin precio»; CON precio cuenta (paridad con cuentaGrupo de
-- contracts/assets/operaciones-cuentas.js, que suma precio_total de todo lo no preliminar).
-- Resultado con la función original (20261005210000), 13-oct: MAL en A (sin_precio = true por el Poder; el tope de
-- 5.000 sobre 1.000 PASABA) y en RP00170 (sin_precio = true). Con la corrección: todo OK.
-- Ojo: el hijo hereda la moneda del padre por trg_contrato_moneda_desde_unidad (un Hak Sewa con precio en IDR queda
-- con moneda EUR); por eso el precio real del Hak Sewa va en hsn_precio_rp y no en precio_total.
-- No se prueba una factura sobre una pieza: darla de alta gasta un número de la serie legal de facturas (nextval no
-- se deshace con el raise). La rama fa no cambia respecto a 20261005210000.
do $t$
declare out text := ''; p uuid; r1 uuid; r2 uuid; r3 uuid; r4 uuid; s record; ok boolean; acl text;
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

  -- B: una Adenda CON precio (sube lo pactado 200) cuenta: precio 1.200, una factura de 1.100 pasa
  insert into public.contratos (numero, tipo, proyecto_id, precio_total, contrato_padre_id, datos)
    values ('ZZT-A4', 'adenda', p, 200, r1, '{"hitos":[]}');
  select * into s from public._cadena_saldo(r1, null);
  ok := s.precio = 1200 and not s.sin_precio;
  out := out || case when ok then 'OK ' else 'MAL ' end || 'B Adenda con precio cuenta: precio=' || coalesce(s.precio::text, 'null') || ' sin_precio=' || s.sin_precio || E'\n';
  begin perform public._factura_tope_cadena(null, r1, 'EUR', 1100, 'factura'); out := out || E'OK B tope 1100 sobre 1200: pasa\n';
  exception when others then out := out || 'MAL B tope 1100: ' || left(sqlerrm, 100) || E'\n'; end;

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
