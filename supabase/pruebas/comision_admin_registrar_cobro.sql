-- Prueba de comision_admin_registrar_cobro, versión BOLSA (7-oct-2026). Se ejecuta por execute_sql y TERMINA CON UN
-- RAISE a propósito: no deja rastro. Cada caso dice `ok` o `FALLO`; la última línea cuenta los fallos.
-- Datos: sociedad ficticia 'zz_prueba', EUR.
--   L1 devengo 100 (1-ene, pendiente) · L2 50 (2-ene, pendiente) · L3 30 (3-ene, FACTURADA)
--   L4 20 (4-ene, ANULADA) + A4 abono -20 de L4 (sin efecto) · L5 10 (5-ene, pendiente)
--   T1  bolsa 150 → L1+L2, resto 0, vista previa (no marca nada)
--   T2  bolsa 170 → L1+L2, resto 20 y avisa de la siguiente (30): se PARA en la primera que no cabe
--   T3  bolsa 180 → L1+L2+L3, 2 sin facturar
--   T4  bolsa 190 → 4 líneas (ni L4 ni su abono cuentan; con A4 contado no llegaría)
--   T5  confirmar con ids que no son los enseñados → rechaza
--   T6  confirmar con los ids enseñados → cabecera con su fecha, 2 líneas cobradas con cobro_id, 2 filas de log
--   T7  siguiente cobro de 10: el saldo de 20 que sobró entra en la bolsa (30) y salda L3
--   T8  una línea que sale de «cobrada» suelta su cobro_id y su dinero vuelve al saldo
--   T9  bolsa 5 + saldo
--   T10 fecha futura rechaza · T11 sin sesión de super_admin rechaza
do $$
declare
  u uuid; v_out text := ''; v_fallos int := 0; r jsonb; r2 jsonb; v_ids jsonb; c uuid;
  l1 uuid; l2 uuid; l3 uuid; l4 uuid; l5 uuid;
begin
  select user_id into u from public.usuarios where rol = 'super_admin' and activo limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  insert into public.comision_admin_lineas (tipo_linea, recibi_numero, sociedad, devengado_el, base_total, moneda, pct_aplicado, importe, estado)
    values ('devengo', 'ZZ1', 'zz_prueba', '2026-01-01', 20000, 'EUR', 0.5, 100, 'pendiente') returning id into l1;
  insert into public.comision_admin_lineas (tipo_linea, recibi_numero, sociedad, devengado_el, base_total, moneda, pct_aplicado, importe, estado)
    values ('devengo', 'ZZ2', 'zz_prueba', '2026-01-02', 10000, 'EUR', 0.5, 50, 'pendiente') returning id into l2;
  insert into public.comision_admin_lineas (tipo_linea, recibi_numero, sociedad, devengado_el, base_total, moneda, pct_aplicado, importe, estado)
    values ('devengo', 'ZZ3', 'zz_prueba', '2026-01-03', 6000, 'EUR', 0.5, 30, 'facturada') returning id into l3;
  insert into public.comision_admin_lineas (tipo_linea, recibi_numero, sociedad, devengado_el, base_total, moneda, pct_aplicado, importe, estado, anulada)
    values ('devengo', 'ZZ4', 'zz_prueba', '2026-01-04', 4000, 'EUR', 0.5, 20, 'pendiente', true) returning id into l4;
  insert into public.comision_admin_lineas (tipo_linea, linea_origen_id, recibi_numero, sociedad, devengado_el, base_total, moneda, pct_aplicado, importe, estado)
    values ('abono', l4, 'ZZ4', 'zz_prueba', '2026-01-04', -4000, 'EUR', 0.5, -20, 'pendiente');
  insert into public.comision_admin_lineas (tipo_linea, recibi_numero, sociedad, devengado_el, base_total, moneda, pct_aplicado, importe, estado)
    values ('devengo', 'ZZ5', 'zz_prueba', '2026-01-05', 2000, 'EUR', 0.5, 10, 'pendiente') returning id into l5;

  r := public.comision_admin_registrar_cobro('zz_prueba', 'EUR', 150, current_date);
  if (r->>'ok')::boolean and (r->>'n')::int = 2 and (r->>'resto')::numeric = 0 and not (r->>'aplicado')::boolean
     and (select estado from public.comision_admin_lineas where id = l1) = 'pendiente'
  then v_out := v_out || E'T1 ok\n'; else v_out := v_out || E'T1 FALLO ' || (r-'lineas')::text || E'\n'; v_fallos := v_fallos + 1; end if;

  r := public.comision_admin_registrar_cobro('zz_prueba', 'EUR', 170, current_date);
  if (r->>'n')::int = 2 and (r->>'resto')::numeric = 20 and (r->'siguiente'->>'importe')::numeric = 30
  then v_out := v_out || E'T2 ok\n'; else v_out := v_out || E'T2 FALLO ' || (r-'lineas')::text || E'\n'; v_fallos := v_fallos + 1; end if;

  r := public.comision_admin_registrar_cobro('zz_prueba', 'EUR', 180, current_date);
  if (r->>'n')::int = 3 and (r->>'sin_facturar')::int = 2
  then v_out := v_out || E'T3 ok\n'; else v_out := v_out || E'T3 FALLO ' || (r-'lineas')::text || E'\n'; v_fallos := v_fallos + 1; end if;

  r := public.comision_admin_registrar_cobro('zz_prueba', 'EUR', 190, current_date);
  if (r->>'n')::int = 4 and (r->>'resto')::numeric = 0
  then v_out := v_out || E'T4 ok\n'; else v_out := v_out || E'T4 FALLO ' || (r-'lineas')::text || E'\n'; v_fallos := v_fallos + 1; end if;

  r := public.comision_admin_registrar_cobro('zz_prueba', 'EUR', 170, current_date);
  v_ids := r->'ids';
  r2 := public.comision_admin_registrar_cobro('zz_prueba', 'EUR', 170, current_date, null, false, true, null, array[l1]);
  if not (r2->>'ok')::boolean and (select estado from public.comision_admin_lineas where id = l1) = 'pendiente'
  then v_out := v_out || E'T5 ok\n'; else v_out := v_out || E'T5 FALLO ' || r2::text || E'\n'; v_fallos := v_fallos + 1; end if;

  r := public.comision_admin_registrar_cobro('zz_prueba', 'EUR', 170, date '2026-01-10', 'REF-1', false, true, 'prueba',
         array(select (x)::uuid from jsonb_array_elements_text(v_ids) x));
  select id into c from public.comision_admin_cobros where sociedad = 'zz_prueba';
  if (r->>'aplicado')::boolean and c is not null
     and (select n_lineas from public.comision_admin_cobros where id = c) = 2
     and (select count(*) from public.comision_admin_lineas where cobro_id = c and estado = 'cobrada') = 2
     and (select count(*) from public.comision_admin_lineas_log where linea_id in (l1, l2) and estado_despues = 'cobrada') = 2
  then v_out := v_out || E'T6 ok\n'; else v_out := v_out || E'T6 FALLO ' || (r-'lineas')::text || E'\n'; v_fallos := v_fallos + 1; end if;

  r := public.comision_admin_registrar_cobro('zz_prueba', 'EUR', 10, current_date);
  if (r->>'saldo_previo')::numeric = 20 and (r->>'bolsa')::numeric = 30 and (r->>'n')::int = 1 and (r->>'resto')::numeric = 0
  then v_out := v_out || E'T7 ok\n'; else v_out := v_out || E'T7 FALLO ' || (r-'lineas')::text || E'\n'; v_fallos := v_fallos + 1; end if;

  perform public.comision_admin_linea_estado(l1, 'pendiente', null, false, false, 'prueba de reversión');
  r := public.comision_admin_registrar_cobro('zz_prueba', 'EUR', 10, current_date);
  if (r->>'saldo_previo')::numeric = 120 and (select cobro_id from public.comision_admin_lineas where id = l1) is null
  then v_out := v_out || E'T8 ok\n'; else v_out := v_out || E'T8 FALLO ' || (r-'lineas')::text || E'\n'; v_fallos := v_fallos + 1; end if;

  r := public.comision_admin_registrar_cobro('zz_prueba', 'EUR', 5, current_date);
  if (r->>'bolsa')::numeric = 125 and (r->>'n')::int >= 1
  then v_out := v_out || E'T9 ok\n'; else v_out := v_out || E'T9 FALLO ' || (r-'lineas')::text || E'\n'; v_fallos := v_fallos + 1; end if;

  begin
    perform public.comision_admin_registrar_cobro('zz_prueba', 'EUR', 30, current_date + 5);
    v_out := v_out || E'T10 FALLO (fecha futura)\n'; v_fallos := v_fallos + 1;
  exception when others then v_out := v_out || E'T10 ok\n'; end;

  begin
    perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
    perform public.comision_admin_registrar_cobro('zz_prueba', 'EUR', 30, current_date);
    v_out := v_out || E'T11 FALLO (no super_admin)\n'; v_fallos := v_fallos + 1;
  exception when others then v_out := v_out || E'T11 ok\n'; end;

  raise exception E'\n%FALLOS: %', v_out, v_fallos;
end $$;

-- SEGUNDO BLOQUE (ejecutar aparte, también termina en RAISE): confirmar con 0 líneas, doble clic, anular cobro.
--   T12 confirmar con 0 líneas guarda el importe como saldo · T13 el mismo cobro idéntico <10 min se rechaza
--   T14 el saldo de 5 + un cobro de 95 cubre una línea de 100 · T15 anular el cobro suelta la línea a su estado
--   anterior (facturada) y el saldo ignora el cobro anulado · T16 anular dos veces no hace nada · T17 motivo corto rechaza
do $$
declare
  u uuid; v_out text := ''; v_fallos int := 0; r jsonb; v_ids jsonb; c uuid; c2 uuid; m1 uuid;
begin
  select user_id into u from public.usuarios where rol = 'super_admin' and activo limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  insert into public.comision_admin_lineas (tipo_linea, recibi_numero, sociedad, devengado_el, base_total, moneda, pct_aplicado, importe, estado)
    values ('devengo', 'ZY1', 'zz_prueba2', '2026-01-01', 20000, 'EUR', 0.5, 100, 'facturada') returning id into m1;

  r := public.comision_admin_registrar_cobro('zz_prueba2', 'EUR', 5, current_date, null, false, true, null, array[]::uuid[]);
  select id into c from public.comision_admin_cobros where sociedad = 'zz_prueba2';
  if (r->>'ok')::boolean and (r->>'n')::int = 0 and (r->>'resto')::numeric = 5 and (select n_lineas from public.comision_admin_cobros where id = c) = 0
  then v_out := v_out || E'T12 ok\n'; else v_out := v_out || E'T12 FALLO ' || (r-'lineas')::text || E'\n'; v_fallos := v_fallos + 1; end if;

  r := public.comision_admin_registrar_cobro('zz_prueba2', 'EUR', 5, current_date, null, false, true, null, array[]::uuid[]);
  if not (r->>'ok')::boolean and (select count(*) from public.comision_admin_cobros where sociedad = 'zz_prueba2') = 1
  then v_out := v_out || E'T13 ok\n'; else v_out := v_out || E'T13 FALLO ' || (r-'lineas')::text || E'\n'; v_fallos := v_fallos + 1; end if;

  r := public.comision_admin_registrar_cobro('zz_prueba2', 'EUR', 95, current_date);
  if (r->>'saldo_previo')::numeric = 5 and (r->>'bolsa')::numeric = 100 and (r->>'n')::int = 1
  then v_out := v_out || E'T14 ok\n'; else v_out := v_out || E'T14 FALLO ' || (r-'lineas')::text || E'\n'; v_fallos := v_fallos + 1; end if;
  v_ids := r->'ids';
  r := public.comision_admin_registrar_cobro('zz_prueba2', 'EUR', 95, current_date, 'REF-2', false, true, null,
         array(select (x)::uuid from jsonb_array_elements_text(v_ids) x));
  select id into c2 from public.comision_admin_cobros where sociedad = 'zz_prueba2' and referencia = 'REF-2';
  if not (select estado = 'cobrada' and cobro_id = c2 from public.comision_admin_lineas where id = m1)
  then v_out := v_out || E'T15 FALLO (no cobró)\n'; v_fallos := v_fallos + 1; end if;

  r := public.comision_admin_anular_cobro(c2, 'importe mal tecleado');
  if (r->>'ok')::boolean and (r->>'lineas_sueltas')::int = 1
     and (select estado = 'facturada' and cobro_id is null from public.comision_admin_lineas where id = m1)
     and (public.comision_admin_registrar_cobro('zz_prueba2', 'EUR', 1, current_date)->>'saldo_previo')::numeric = 5
  then v_out := v_out || E'T15 ok\n'; else v_out := v_out || E'T15 FALLO ' || r::text || E'\n'; v_fallos := v_fallos + 1; end if;

  r := public.comision_admin_anular_cobro(c2, 'otra vez');
  if not (r->>'ok')::boolean then v_out := v_out || E'T16 ok\n'; else v_out := v_out || E'T16 FALLO\n'; v_fallos := v_fallos + 1; end if;
  begin
    perform public.comision_admin_anular_cobro(c, 'no');
    v_out := v_out || E'T17 FALLO (aceptó motivo corto)\n'; v_fallos := v_fallos + 1;
  exception when others then v_out := v_out || E'T17 ok\n'; end;

  raise exception E'\n%FALLOS: %', v_out, v_fallos;
end $$;
