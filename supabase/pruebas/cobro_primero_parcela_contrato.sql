-- Prueba de «el estado de la parcela se revisa cuando cambia su contrato» (migración
-- 20261014032925_cobro_primero_parcela_contrato.sql, trigger trg_zz_revalua_unidad_por_contrato).
-- ESCRIBE dentro de la transacción y TERMINA CON UN RAISE a propósito: se deshace entera. No da de alta nada, no gasta
-- series y no llama a comisiones_evaluar_contrato (LAW-217). Los avisos que disparan los cambios de estado y la firma
-- van por tablas y se deshacen con el resto. Lanzar como postgres (MCP o SQL Editor).
-- Filas reales del 14-oct-2026; si alguna cambia, el caso lo dice («precondición») en vez de dar un falso fallo:
--   A2 de Soka Village W2 · Bloqueo RP00050 SIN firmar, 19.000 de parcela y 17.592 de obra cobrados, «bloqueada»
--   SH-6 de Sumba Hills   · Bloqueo RP00132 firmado a 25.000, parcela cobrada entera, «vendida»
-- Cada línea dice `ok` o `FALLO`; la última cuenta los fallos.
--   C1  firmar el Bloqueo de una parcela ya pagada la pasa a «vendida» en el momento (antes esperaba al siguiente cobro)
--   C2  subir el precio de un Bloqueo FIRMADO por encima de lo cobrado baja la parcela a «bloqueada»; devolverlo la sube
--   C3  un BORRADOR no decide: bajar a 1 € el precio de un Bloqueo sin firmar no hace que su parcela «cumpla vendida»
--       (se compara con el mayor entre catálogo y borrador), y la parcela no se mueve
--   C4  una unidad sin contrato: 0 cobrado y ningún precio por unidad_cobro_reparto (el de catálogo lo da la vista)
--   C5  el trigger existe y su función no es llamable por la API; comisiones mide contra el Bloqueo firmado
do $t$
declare
  out text := ''; fallos int := 0; v_est text; v_est2 text; n int; m int; v_u uuid; v_c uuid; v_b boolean; v_cod text;
begin
  -- C1
  select u.estado into v_est from public.unidades u join public.contratos c on c.id = u.contrato_id
   where c.numero = 'RP00050' and not coalesce(c.bloqueado, false) limit 1;
  if v_est is distinct from 'bloqueada' then
    out := out || E'\nC1 precondición: RP00050 ya no es un Bloqueo sin firmar con su parcela «bloqueada» (' || coalesce(v_est, 'no está') || '); elegir otro caso';
  else
    update public.contratos set bloqueado = true where numero = 'RP00050';
    select u.estado into v_est from public.unidades u join public.contratos c on c.id = u.contrato_id where c.numero = 'RP00050' limit 1;
    if v_est is distinct from 'vendida' then fallos := fallos + 1; end if;
    out := out || E'\nC1 firmar RP00050 -> ' || v_est || (case when v_est = 'vendida' then ' ok' else ' FALLO' end);
  end if;

  -- C2
  select u.estado into v_est from public.unidades u join public.contratos c on c.id = u.contrato_id
   where c.numero = 'RP00132' and coalesce(c.bloqueado, false) and c.precio_total = 25000 limit 1;
  if v_est is distinct from 'vendida' then
    out := out || E'\nC2 precondición: RP00132 ya no es un Bloqueo firmado a 25.000 con su parcela «vendida» (' || coalesce(v_est, 'no está') || '); elegir otro caso';
  else
    update public.contratos set precio_total = 26000 where numero = 'RP00132';
    select u.estado into v_est from public.unidades u join public.contratos c on c.id = u.contrato_id where c.numero = 'RP00132' limit 1;
    update public.contratos set precio_total = 25000 where numero = 'RP00132';
    select u.estado into v_est2 from public.unidades u join public.contratos c on c.id = u.contrato_id where c.numero = 'RP00132' limit 1;
    if v_est is distinct from 'bloqueada' or v_est2 is distinct from 'vendida' then fallos := fallos + 1; end if;
    out := out || E'\nC2 RP00132 a 26.000 -> ' || v_est || ' · de vuelta a 25.000 -> ' || v_est2
               || (case when v_est = 'bloqueada' and v_est2 = 'vendida' then ' ok' else ' FALLO' end);
  end if;

  -- C3: un Bloqueo sin firmar cuya venta ha cobrado algo, pero menos que el suelo de catálogo
  select u.id, c.id, u.codigo into v_u, v_c, v_cod
    from public.unidades u
    join public.contratos c on c.id = u.contrato_id
    cross join lateral public._unidad_cobro_cascada(u.id) x
   where c.tipo = 'reserva_parcela' and not coalesce(c.bloqueado, false) and c.liberado_en is null
     and coalesce(c.precio_total, 0) > 0 and coalesce(u.precio_suelo, 0) > 0 and u.estado = 'bloqueada'
     and x.cobrado_suelo + x.cobrado_obra > 0 and x.cobrado_suelo + x.cobrado_obra < u.precio_suelo
     and (select count(*) from public.unidades h where h.contrato_id = c.id) = 1
   order by c.numero limit 1;
  if v_u is null then
    out := out || E'\nC3 n/a: no hay ningún Bloqueo sin firmar con algo cobrado por debajo del suelo de catálogo';
  else
    update public.contratos set precio_total = 1 where id = v_c;
    select public.unidad_cumple_estado(u.id, 'vendida', u.precio, u.precio_suelo), u.estado into v_b, v_est
      from public.unidades u where u.id = v_u;
    if v_b or v_est is distinct from 'bloqueada' then fallos := fallos + 1; end if;
    out := out || E'\nC3 borrador de ' || v_cod || ' a 1 €: cumple vendida = ' || v_b || ', estado ' || v_est
               || (case when not v_b and v_est = 'bloqueada' then ' ok' else ' FALLO' end);
  end if;

  -- C4
  select count(*), count(x.suelo_precio) + count(x.obra_precio) + count(*) filter (where x.cobrado_suelo is distinct from 0) into n, m
    from (select u.id from public.unidades u where u.contrato_id is null order by u.id limit 50) u
    cross join lateral public.unidad_cobro_reparto(u.id) x;
  if m > 0 or n = 0 then fallos := fallos + 1; end if;
  out := out || E'\nC4 ' || n || ' unidades sin contrato: sin precio y con 0 cobrado' || (case when m = 0 and n > 0 then ' ok' else ' FALLO (' || m || ')' end);

  -- C5
  select count(*) into n from pg_trigger t
   where t.tgrelid = 'public.contratos'::regclass and t.tgname = 'trg_zz_revalua_unidad_por_contrato' and t.tgenabled = 'O';
  select count(*) into m from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'comisiones_evaluar_contrato'
     and position('case when cp.suelo_de_contrato then cp.suelo_precio else u.precio_suelo end' in p.prosrc) > 0;
  v_b := has_function_privilege('authenticated', 'public.trg_revalua_unidad_por_contrato()', 'execute')
      or has_function_privilege('anon', 'public.trg_revalua_unidad_por_contrato()', 'execute');
  if n <> 1 or m <> 1 or v_b then fallos := fallos + 1; end if;
  out := out || E'\nC5 trigger ' || n || ', comisiones ' || m || ', función abierta ' || v_b
             || (case when n = 1 and m = 1 and not v_b then ' ok' else ' FALLO' end);

  raise exception E'cobro_primero_parcela_contrato: % fallo(s)%', fallos, out;
end
$t$;
