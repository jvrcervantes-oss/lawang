-- Prueba de 20261013130000_cadena_saldo_sin_piezas_que_acompanan (13-oct-2026). Se ejecuta por execute_sql DESPUÉS
-- de aplicar la migración: termina con un raise a propósito, así que no deja rastro (los contratos de prueba ZZT-* se
-- deshacen; llevan número propio para no gastar la secuencia real de numeración, y cuelgan del proyecto de RP00170,
-- que tiene empresa: sin empresa el contrato es invisible y la prueba mentiría).
-- Corre sin sesión (auth.uid() nulo): es_super_admin_de da false, así que _factura_tope_cadena va por el camino real
-- del tope (raise) y no por el del privilegio (registra_privilegio). Cada línea dice OK o MAL; ninguna debe decir MAL.
-- Resultado del 13-oct con la función vieja: MAL en A (sin_precio = true por el Poder; el tope de 5.000 sobre 1.000
-- PASABA), B (precio = 900.001.000: sumaba el Hak Sewa en IDR a los 1.000 EUR) y RP00170 (sin_precio = true).
-- Con la nueva (aplicada como 20261013060855): todo OK.
-- Ojo al leer B: el Hak Sewa hijo hereda la moneda del padre (EUR) por trg_contrato_moneda_desde_unidad aunque su
-- precio real sea en IDR; por eso la regla es por tipo y no por moneda.
do $t$
declare out text := ''; p uuid; r1 uuid; r2 uuid; r3 uuid; r4 uuid; s record; ok boolean;
begin
  select proyecto_id into p from public.contratos where numero = 'RP00170';
  out := out || 'super_admin sin sesión = ' || coalesce(public.es_super_admin_de(public._empresa_doc(null::uuid,
           (select id from public.contratos where numero = 'RP00170')))::text, 'null') || E' (debe ser false)\n';

  -- A: raíz 1.000 EUR + Poder hijo sin precio → cuenta el precio y el tope funciona
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos)
    values ('ZZT-A0', 'contrato_general', p, 'EUR', 1000, '{"hitos":[]}') returning id into r1;
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, contrato_padre_id, datos)
    values ('ZZT-A1', 'poa', p, null, null, r1, '{"hitos":[]}');
  select * into s from public._cadena_saldo(r1, null);
  ok := s.precio = 1000 and not s.sin_precio;
  out := out || case when ok then 'OK ' else 'MAL ' end || 'A poa sin precio: precio=' || coalesce(s.precio::text, 'null') || ' sin_precio=' || s.sin_precio || E'\n';
  begin perform public._factura_tope_cadena(null, r1, 'EUR', 5000, 'factura'); out := out || E'MAL A tope 5000 sobre 1000: PASA\n';
  exception when sqlstate '23514' then out := out || E'OK A tope 5000 sobre 1000: bloquea\n'; end;
  begin perform public._factura_tope_cadena(null, r1, 'EUR', 500, 'factura'); out := out || E'OK A tope 500 sobre 1000: pasa\n';
  exception when others then out := out || 'MAL A tope 500: ' || left(sqlerrm, 100) || E'\n'; end;

  -- B: además un Hak Sewa hijo CON precio en IDR → no se suma ni deja la cadena sin precio
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, contrato_padre_id, datos)
    values ('ZZT-A2', 'hak_sewa_notario', p, 'IDR', 900000000, r1, '{"hitos":[]}');
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, contrato_padre_id, datos)
    values ('ZZT-A3', 'adenda', p, null, null, r1, '{"hitos":[]}');
  select * into s from public._cadena_saldo(r1, null);
  ok := s.precio = 1000 and not s.sin_precio;
  out := out || case when ok then 'OK ' else 'MAL ' end || 'B + Hak Sewa IDR + Adenda: precio=' || coalesce(s.precio::text, 'null') || ' sin_precio=' || s.sin_precio || E'\n';

  -- C: raíz + Construcción hija SIN precio → sigue sin precio (no se excluye de más)
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos)
    values ('ZZT-C0', 'contrato_general', p, 'EUR', 1000, '{"hitos":[]}') returning id into r2;
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, contrato_padre_id, datos)
    values ('ZZT-C1', 'construccion', p, 'EUR', null, r2, '{"hitos":[]}');
  select * into s from public._cadena_saldo(r2, null);
  out := out || case when s.sin_precio then 'OK ' else 'MAL ' end || 'C construcción sin precio: sin_precio=' || s.sin_precio || E'\n';
  begin perform public._factura_tope_cadena(null, r2, 'EUR', 5000, 'factura'); out := out || E'OK C sin precio: no aplica tope\n';
  exception when others then out := out || 'MAL C tope: ' || left(sqlerrm, 100) || E'\n'; end;

  -- D: Hak Sewa suelto como raíz, sin precio → como hasta hoy (sin precio)
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos)
    values ('ZZT-D0', 'hak_sewa_notario', p, null, null, '{"hitos":[]}') returning id into r3;
  select * into s from public._cadena_saldo(r3, null);
  out := out || case when s.sin_precio and s.precio is null then 'OK ' else 'MAL ' end || 'D Hak Sewa raíz suelto: precio=' || coalesce(s.precio::text, 'null') || ' sin_precio=' || s.sin_precio || E'\n';

  -- E: raíz EUR + Construcción hija con precio en IDR → no suma monedas: sin precio, y precio solo en EUR.
  -- Al dar de alta, trg_contrato_moneda_desde_unidad le pone al hijo la moneda del padre (o de su parcela): un hijo en
  -- otra moneda solo existe si su parcela va en otra. Para fabricarlo sin parcela se da de alta firmado y luego se
  -- cambia la moneda (el trigger no toca un contrato firmado); todo se deshace con el raise final.
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos)
    values ('ZZT-E0', 'contrato_general', p, 'EUR', 1000, '{"hitos":[]}') returning id into r4;
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, contrato_padre_id, datos, bloqueado)
    values ('ZZT-E1', 'construccion', p, 'IDR', 5000000, r4, '{"hitos":[]}', true);
  update public.contratos set moneda = 'IDR' where numero = 'ZZT-E1';
  select * into s from public._cadena_saldo(r4, null);
  ok := s.sin_precio and s.precio = 1000;
  out := out || case when ok then 'OK ' else 'MAL ' end || 'E hijo en otra moneda: precio=' || coalesce(s.precio::text, 'null') || ' sin_precio=' || s.sin_precio || E'\n';

  -- Real: RP00170 (45.900 EUR con su Poder PA00010 sin precio) deja de estar «sin precio»
  select * into s from public._cadena_saldo((select id from public.contratos where numero = 'RP00170'), null);
  out := out || case when not s.sin_precio and s.precio > 0 then 'OK ' else 'MAL ' end || 'RP00170: precio=' || coalesce(s.precio::text, 'null') || ' sin_precio=' || s.sin_precio || E'\n';

  -- Privilegios: create or replace no los toca (igual que en facturas_tope_cadena_y_recibi_pendiente)
  out := out || case when not has_function_privilege('anon', 'public._cadena_saldo(uuid,uuid)', 'execute')
                       and not has_function_privilege('authenticated', 'public._cadena_saldo(uuid,uuid)', 'execute')
                     then 'OK ' else 'MAL ' end || 'privilegios: _cadena_saldo sin execute para anon/authenticated';
  raise exception E'RESULTADOS\n%', out;
end $t$;
