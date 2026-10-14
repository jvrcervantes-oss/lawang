-- Prueba de «el estado de la parcela se revisa cuando cambia su contrato» y de lo que manda el precio del contrato
-- (migraciones 20261014032925_cobro_primero_parcela_contrato.sql y 20261014040310_cobro_primero_parcela_borrador.sql).
-- ESCRIBE dentro de la transacción y TERMINA CON UN RAISE a propósito: se deshace entera. No da de alta nada, no gasta
-- series y no llama a comisiones_evaluar_contrato (LAW-217). Los avisos que disparan los cambios de estado y la firma
-- van por tablas y se deshacen con el resto. Lanzar como postgres (MCP o SQL Editor).
-- Filas reales del 14-oct-2026; si alguna cambia, el caso lo dice («precondición») en vez de dar un falso fallo:
--   A2 de Soka Village W2 · Bloqueo RP00050 SIN firmar, 19.000 de parcela y 17.592 de obra cobrados, «bloqueada»
--   SH-6 de Sumba Hills   · Bloqueo RP00132 firmado a 25.000, parcela cobrada entera, «vendida»
-- Cada línea dice `ok` o `FALLO`; la última cuenta los fallos.
--   C1  firmar el Bloqueo de una parcela ya pagada la pasa a «vendida» en el momento, por el CAMINO REAL de la firma
--       (service_role, un UPDATE solo de `bloqueado`, como firma-submit)
--   C2  subir el precio de un Bloqueo FIRMADO por encima de lo cobrado baja la parcela a «bloqueada»; devolverlo la sube
--   C3  el precio de un BORRADOR manda en el reparto (owner, 14-oct: «aunque no estén firmados, coge el precio del
--       contrato»), pero la firma sigue siendo la puerta del estado: bajado a 1 €, la parcela «cumple vendida» y aun
--       así no se mueve de «bloqueada»
--   C4  una unidad sin contrato: 0 cobrado y ningún precio por unidad_cobro_reparto (el de catálogo lo da la vista)
--   C5  el disparador existe y mira también los borrados, su función no es llamable por la API, y comisiones mide el
--       «% cobrado del suelo» contra el precio del Bloqueo solo si está FIRMADO
--   C6  un Bloqueo colgado como hijo de otro Bloqueo no mueve el precio de la parcela: o la base no deja crearlo, o la
--       cascada no lo cuenta
--   C7  unidad_cobro_reparto no es más ancha que la RLS de `contratos`: perfil a perfil (cuenta desactivada, agente de
--       otra empresa, agente, jefe de proyecto, sales manager, admin de empresa, comprador del portal), ninguna unidad
--       con dato cuyo contrato ese perfil no pueda leer. Los ids se sacan ANTES de cambiar de rol: la función es
--       llamable por RPC con cualquier id
do $t$
declare
  out text := ''; fallos int := 0; v_est text; v_est2 text; n int; m int; k int; v_u uuid; v_c uuid; v_b boolean; v_cod text;
  v_sp0 numeric; v_sp1 numeric; v_num text; v_uid uuid; v_mail text; perf record; v_ids uuid[]; v_cts uuid[]; v_lin text := '';
begin
  -- C1
  select u.estado into v_est from public.unidades u join public.contratos c on c.id = u.contrato_id
   where c.numero = 'RP00050' and not coalesce(c.bloqueado, false) limit 1;
  if v_est is distinct from 'bloqueada' then
    out := out || E'\nC1 precondición: RP00050 ya no es un Bloqueo sin firmar con su parcela «bloqueada» (' || coalesce(v_est, 'no está') || '); elegir otro caso';
  else
    perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
    execute 'set local role service_role';
    update public.contratos set bloqueado = true where numero = 'RP00050';
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    select u.estado into v_est from public.unidades u join public.contratos c on c.id = u.contrato_id where c.numero = 'RP00050' limit 1;
    if v_est is distinct from 'vendida' then fallos := fallos + 1; end if;
    out := out || E'\nC1 firmar RP00050 como service_role -> ' || v_est || (case when v_est = 'vendida' then ' ok' else ' FALLO' end);
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
    select public.unidad_cumple_estado(u.id, 'vendida', u.precio, u.precio_suelo), u.estado, x.suelo_precio
      into v_b, v_est, v_sp1
      from public.unidades u cross join lateral public._unidad_cobro_cascada(u.id) x where u.id = v_u;
    if not v_b or v_est is distinct from 'bloqueada' or v_sp1 <> 1 then fallos := fallos + 1; end if;
    out := out || E'\nC3 borrador de ' || v_cod || ' a 1 €: precio de parcela ' || v_sp1 || ', cumple vendida = ' || v_b || ', estado ' || v_est
               || (case when v_b and v_est = 'bloqueada' and v_sp1 = 1 then ' ok' else ' FALLO' end);
  end if;

  -- C4
  select count(*), count(x.suelo_precio) + count(x.obra_precio) + count(*) filter (where x.cobrado_suelo is distinct from 0) into n, m
    from (select u.id from public.unidades u where u.contrato_id is null order by u.id limit 50) u
    cross join lateral public.unidad_cobro_reparto(u.id) x;
  if m > 0 or n = 0 then fallos := fallos + 1; end if;
  out := out || E'\nC4 ' || n || ' unidades sin contrato: sin precio y con 0 cobrado' || (case when m = 0 and n > 0 then ' ok' else ' FALLO (' || m || ')' end);

  -- C5
  select count(*) into n from pg_trigger t
   where t.tgrelid = 'public.contratos'::regclass and t.tgname = 'trg_zz_revalua_unidad_por_contrato' and t.tgenabled = 'O'
     and (t.tgtype & 8) <> 0;
  select count(*) into m from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'comisiones_evaluar_contrato'
     and position('case when cp.suelo_de_contrato and v_contrato_firmado then cp.suelo_precio else u.precio_suelo end' in p.prosrc) > 0;
  v_b := has_function_privilege('authenticated', 'public.trg_revalua_unidad_por_contrato()', 'execute')
      or has_function_privilege('anon', 'public.trg_revalua_unidad_por_contrato()', 'execute');
  if n <> 1 or m <> 1 or v_b then fallos := fallos + 1; end if;
  out := out || E'\nC5 disparador con borrados ' || n || ', comisiones contra el firmado ' || m || ', función abierta ' || v_b
             || (case when n = 1 and m = 1 and not v_b then ' ok' else ' FALLO' end);

  -- C6: la Carta hija de un Bloqueo firmado con su parcela «vendida» se convierte en Bloqueo de 9.999.999 € (con
  -- sesión de admin: si no, el guardia de «solo un admin cambia la parcela» lo para antes de llegar a lo que se prueba)
  select h.id, u.id, k0.numero into v_c, v_u, v_num
    from public.unidades u
    join public.contratos k0 on k0.id = u.contrato_id
    join public.contratos h on h.contrato_padre_id = k0.id and h.tipo = 'carta_reserva'
   where k0.tipo = 'reserva_parcela' and coalesce(k0.bloqueado, false) and k0.liberado_en is null and u.estado = 'vendida'
     and k0.contrato_padre_id is null and (select count(*) from public.unidades h2 where h2.contrato_id = k0.id) = 1
   order by k0.numero limit 1;
  if v_c is null then
    out := out || E'\nC6 n/a: no hay ninguna Carta hija de un Bloqueo firmado de una sola parcela «vendida»';
  else
    select us.user_id, us.email into v_uid, v_mail from public.usuarios us
     where us.rol = 'super_admin' and us.activo and us.user_id is not null order by us.email limit 1;
    perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated', 'email', v_mail)::text, true);
    select x.suelo_precio into v_sp0 from public._unidad_cobro_cascada(v_u) x;
    begin
      update public.contratos set tipo = 'reserva_parcela', precio_total = 9999999, unidad_id = null where id = v_c;
      select x.suelo_precio into v_sp1 from public._unidad_cobro_cascada(v_u) x;
      select u.estado into v_est from public.unidades u where u.id = v_u;
      if v_sp1 is distinct from v_sp0 or v_est is distinct from 'vendida' then fallos := fallos + 1; end if;
      out := out || E'\nC6 Bloqueo hijo de 9.999.999 bajo ' || v_num || ': precio de parcela ' || v_sp0 || ' -> ' || v_sp1 || ', estado ' || v_est
                 || (case when v_sp1 = v_sp0 and v_est = 'vendida' then ' ok (la cascada no lo cuenta)' else ' FALLO' end);
    exception when unique_violation then
      out := out || E'\nC6 Bloqueo hijo bajo ' || v_num || ': la base no deja crearlo (' || left(sqlerrm, 90) || ') ok';
    end;
    perform set_config('request.jwt.claims', '', true);
  end if;

  -- C7
  select array_agg(u0.id order by u0.id), array_agg(u0.contrato_id order by u0.id) into v_ids, v_cts
    from public.unidades u0 where u0.contrato_id is not null;
  n := 0;
  for perf in
    select 'desactivada' as perfil, us.user_id as uid, us.email, '{}'::jsonb as app from (select * from public.usuarios where not activo and user_id is not null order by email limit 1) us
    union all select 'agente_otra_empresa', us.user_id, us.email, '{}'::jsonb from (select * from public.usuarios where activo and rol = 'agente' and empresas = array['sandal_woods'] and user_id is not null order by email limit 1) us
    union all select 'agente', us.user_id, us.email, '{}'::jsonb from (select * from public.usuarios where activo and rol = 'agente' and cardinality(empresas) = 2 and user_id is not null order by email limit 1) us
    union all select 'project_manager', us.user_id, us.email, '{}'::jsonb from (select * from public.usuarios where activo and rol = 'project_manager' and user_id is not null order by email limit 1) us
    union all select 'sales_manager', us.user_id, us.email, '{}'::jsonb from (select * from public.usuarios where activo and rol = 'sales_manager' and user_id is not null order by email limit 1) us
    union all select 'admin_empresa', us.user_id, us.email, '{}'::jsonb from (select * from public.usuarios where activo and rol = 'admin_empresa' and empresas = array['lawang'] and user_id is not null order by email limit 1) us
    union all select 'portal', gen_random_uuid(), 'comprador@example.invalid', '{"portal": true}'::jsonb
  loop
    perform set_config('request.jwt.claims', json_build_object('sub', perf.uid, 'role', 'authenticated', 'email', perf.email, 'app_metadata', perf.app)::text, true);
    execute 'set local role authenticated';
    select count(x.cobrado_suelo),
           count(*) filter (where x.cobrado_suelo is not null and not exists (select 1 from public.contratos c where c.id = u.contrato_id))
      into m, k
      from unnest(v_ids, v_cts) as u(id, contrato_id)
      cross join lateral public.unidad_cobro_reparto(u.id) x;
    execute 'reset role';
    n := n + k;
    v_lin := v_lin || ' · ' || perf.perfil || ' ' || m || (case when k > 0 then ' (' || k || ' SIN VER EL CONTRATO)' else '' end);
  end loop;
  perform set_config('request.jwt.claims', '', true);
  if n > 0 then fallos := fallos + 1; end if;
  out := out || E'\nC7 unidades con dato por perfil (de ' || coalesce(cardinality(v_ids), 0) || ')' || v_lin
             || (case when n = 0 then ' ok' else ' FALLO' end);

  raise exception E'cobro_primero_parcela_contrato: % fallo(s)%', fallos, out;
end
$t$;
