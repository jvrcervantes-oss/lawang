-- Prueba de F2 de «primero la parcela, luego la obra» (owner, 14-oct-2026): lo cobrado POR CONTRATO con la regla
-- (_venta_cobro_atribuido, contratos_cobrado_regla_equipo, _contrato_cobrado_venta; fuente: supabase/vivo/
-- 20261014_cobro_primero_parcela/f2_lectores.sql).
-- SOLO LECTURA: se ejecuta por execute_sql y TERMINA CON UN RAISE a propósito (el cambio de rol y los claims se
-- deshacen con él). Los ids se sacan ANTES de `set local role` (con el rol, la RLS dejaría la lista vacía y la prueba
-- pasaría sin probar nada). Cada línea dice `ok` o `FALLO`; la última cuenta los fallos.
--
--   L1  venta a venta: lo atribuido = lo cobrado por documento (la regla reparte, no crea ni pierde) y nada negativo
--   L2  el Bloqueo raíz nunca por debajo del suelo cobrado de sus parcelas; la obra atribuida nunca por encima de la
--       obra de la cascada
--   L3  el caso que lo destapó: SH-1 → RP00021 25.000 y CC00010 16.620
--   L4  la puerta: quien NO ve la venta entera recibe lo de siempre (cobrado = cobrado_doc = contratos_cobrado_equipo)
--       en TODAS sus filas de esa venta, perfil a perfil, incluidos los creadores de un solo contrato de las ventas con
--       autores distintos; y recibe exactamente los mismos contratos que contratos_cobrado_equipo
--   L5  cada perfil ve movidas por la regla exactamente las cifras de las ventas que ve enteras (el admin de la
--       empresa, más de cero: es el control de que la regla llega); un comprador del portal no recibe nada
--   L6  permisos: las dos internas solo postgres y service_role; la RPC además authenticated, sin anon
--   L7  obra_datos_cobro y la previsión leen la regla (_contrato_cobrado_venta), sin el campo carta_cobrado_importe
do $t$
declare
  out text := ''; fallos int := 0; n int; m int; k int; v_t text; v_lin text := '';
  perf record; v_rp21 uuid; v_cc10 uuid; v_parcial uuid[]; v_esperadas int; v_vistas int;
begin
  -- L1
  with a as (select r.id as raiz, x.* from public.contratos r cross join lateral public._venta_cobro_atribuido(r.id) x
              where r.contrato_padre_id is null),
       v as (select raiz, sum(cobrado_doc) d, sum(cobrado_regla) g, count(*) filter (where cobrado_regla < -0.005) neg
               from a group by raiz)
  select count(*) filter (where abs(d - g) > 0.005), coalesce(sum(neg), 0), count(*) into n, m, k from v;
  if n > 0 or m > 0 then fallos := fallos + 1; end if;
  out := out || E'\nL1 ventas ' || k || ' · descuadre ' || n || ' · negativos ' || m || (case when n = 0 and m = 0 then ' ok' else ' FALLO' end);

  -- L2
  select count(*) filter (where g is not null and g < s - 0.02), count(*) filter (where o_atr > o_cas + 0.02) into n, m from (
    select (select a.cobrado_regla from public._venta_cobro_atribuido(r.id) a where a.contrato_id = r.id and a.atribuida) g,
           (select sum(x.cobrado_suelo) from public.unidades u cross join lateral public._unidad_cobro_cascada(u.id) x where u.contrato_id = r.id) s,
           (select coalesce(sum(a.cobrado_regla), 0) from public._venta_cobro_atribuido(r.id) a where a.atribuida and a.contrato_id <> r.id) o_atr,
           (select coalesce(sum(x.cobrado_obra), 0) from public.unidades u cross join lateral public._unidad_cobro_cascada(u.id) x where u.contrato_id = r.id) o_cas
      from public.contratos r where r.contrato_padre_id is null) q;
  if n > 0 or m > 0 then fallos := fallos + 1; end if;
  out := out || E'\nL2 raíz bajo su suelo ' || n || ' · obra sobre la cascada ' || m || (case when n = 0 and m = 0 then ' ok' else ' FALLO' end);

  -- L3
  select id into v_rp21 from public.contratos where numero = 'RP00021';
  select id into v_cc10 from public.contratos where numero = 'CC00010';
  select string_agg(c.numero || '=' || round(a.cobrado_regla, 2), ' ' order by c.numero),
         count(*) filter (where (c.id = v_rp21 and a.cobrado_regla = 25000) or (c.id = v_cc10 and a.cobrado_regla = 16620))
    into v_t, n
    from public._venta_cobro_atribuido(v_rp21) a join public.contratos c on c.id = a.contrato_id
   where c.id in (v_rp21, v_cc10);
  if n <> 2 then fallos := fallos + 1; end if;
  out := out || E'\nL3 SH-1: ' || coalesce(v_t, '-') || (case when n = 2 then ' ok' else ' FALLO' end);

  -- L4 y L5: perfil a perfil. Los creadores de un hijo de una venta con autores distintos, más los perfiles de siempre.
  n := 0;
  for perf in
    select distinct on (h.creado_por) 'creador_de_un_hijo' as perfil, us.user_id as uid, us.email, '{}'::jsonb as app
      from public.contratos h join public.contratos r on r.id = h.contrato_padre_id and r.contrato_padre_id is null
      join public.usuarios us on us.email = h.creado_por and us.activo and us.user_id is not null and us.rol in ('agente', 'sales_manager')
     where h.creado_por is distinct from r.creado_por
    union all select 'agente', us.user_id, us.email, '{}'::jsonb from (select * from public.usuarios where activo and rol = 'agente' and user_id is not null order by email limit 1) us
    union all select 'project_manager', us.user_id, us.email, '{}'::jsonb from (select * from public.usuarios where activo and rol = 'project_manager' and user_id is not null order by email limit 1) us
    union all select 'sales_manager', us.user_id, us.email, '{}'::jsonb from (select * from public.usuarios where activo and rol = 'sales_manager' and user_id is not null order by email limit 1) us
    union all select 'admin_empresa', us.user_id, us.email, '{}'::jsonb from (select * from public.usuarios where activo and rol = 'admin_empresa' and empresas = array['lawang'] and user_id is not null order by email limit 1) us
    union all select 'portal', gen_random_uuid(), 'comprador@example.invalid', '{"portal": true}'::jsonb
  loop
    perform set_config('request.jwt.claims', json_build_object('sub', perf.uid, 'role', 'authenticated', 'email', perf.email, 'app_metadata', perf.app)::text, true);
    -- Los contratos de las ventas que este perfil NO ve enteras, ANTES del cambio de rol: con el rol, la RLS de
    -- `contratos` esconde justo los hermanos que no ve y la lista saldría vacía. puede_ver_contrato ya lee los claims.
    select coalesce(array_agg(c.id), '{}') into v_parcial
      from public.contratos c
     where public.puede_ver_contrato(c.id)
       and exists (select 1 from public.contratos h
                    where (h.id = coalesce(c.contrato_padre_id, c.id) or h.contrato_padre_id = coalesce(c.contrato_padre_id, c.id))
                      and not public.puede_ver_contrato(h.id));
    -- Control de que la prueba muerde: de esos, cuántos SÍ cambiarían con la regla (lo que se filtraría sin la puerta).
    select count(*) into k
      from public.contratos c
      cross join lateral public._venta_cobro_atribuido(coalesce(c.contrato_padre_id, c.id)) a
     where c.id = any (v_parcial) and a.contrato_id = c.id and a.atribuida and abs(a.cobrado_regla - a.cobrado_doc) > 0.005;
    -- Cuántas cifras DEBE ver movidas por la regla: las de las ventas que ve enteras (o de su empresa, si es admin).
    select count(*) into v_esperadas
      from public.contratos c
      cross join lateral public._venta_cobro_atribuido(coalesce(c.contrato_padre_id, c.id)) a
     where public.puede_ver_contrato(c.id) and not (c.id = any (v_parcial))
       and a.contrato_id = c.id and a.atribuida and abs(a.cobrado_regla - a.cobrado_doc) > 0.005;
    v_lin := v_lin || ' · ' || perf.perfil || ' ' || coalesce(perf.email, '-') || ' [' || cardinality(v_parcial)
                   || ' sin ver la venta entera, ' || k || ' cambiarían; ' || v_esperadas || ' movidas a la vista]';
    execute 'set local role authenticated';
    -- `cross join lateral` y no `from public.contratos_…()`: el guardia de lecturas de `contratos` del estudio
    -- confundía el nombre de la función con la tabla hasta el 14-oct (tools/no_destruir.py).
    with nueva as (select x.contrato_id, x.cobrado, x.cobrado_doc from (select 1) z cross join lateral public.contratos_cobrado_regla_equipo() x),
         vieja as (select x.contrato_id, x.cobrado from (select 1) z cross join lateral public.contratos_cobrado_equipo() x)
    select count(*) filter (where nu.contrato_id is null or vi.contrato_id is null),
           count(*) filter (where nu.contrato_id is not null and abs(nu.cobrado_doc - coalesce(vi.cobrado, 0)) > 0.005),
           count(*) filter (where nu.contrato_id = any (v_parcial) and abs(nu.cobrado - nu.cobrado_doc) > 0.005),
           count(*) filter (where abs(nu.cobrado - nu.cobrado_doc) > 0.005)
      into k, m, n, v_vistas
      from nueva nu full join vieja vi on vi.contrato_id = nu.contrato_id;
    v_lin := v_lin || (case when k + m + n > 0 or v_vistas <> v_esperadas
                            then ' (FALLO: filas distintas ' || k || ', doc distinto ' || m || ', regla sin ver la venta ' || n
                                 || ', movidas ' || v_vistas || ' de ' || v_esperadas || ')' else '' end);
    if k + m + n > 0 or v_vistas <> v_esperadas then fallos := fallos + 1; end if;
    -- el admin de la empresa es el control de que la regla SÍ llega a la pantalla (si no ve ninguna movida, no prueba nada)
    if perf.perfil = 'admin_empresa' and v_esperadas = 0 then
      fallos := fallos + 1; v_lin := v_lin || ' (FALLO: el admin no ve ninguna venta movida)';
    end if;
    if perf.perfil = 'portal' then
      select count(*) into k from public.contratos_cobrado_regla_equipo();
      v_lin := v_lin || ' [' || k || ' filas]';
      if k > 0 then fallos := fallos + 1; end if;
    end if;
    execute 'reset role';
  end loop;
  perform set_config('request.jwt.claims', '', true);
  out := out || E'\nL4/L5 puerta por perfil' || v_lin;

  -- L6
  select count(*) filter (where p.proname in ('_venta_cobro_atribuido', '_contrato_cobrado_venta')
                            and p.proacl::text <> '{postgres=X/postgres,service_role=X/postgres}'),
         count(*) filter (where p.proname = 'contratos_cobrado_regla_equipo'
                            and (has_function_privilege('anon', p.oid, 'execute') or not has_function_privilege('authenticated', p.oid, 'execute'))),
         count(*)
    into n, m, k
    from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname in ('_venta_cobro_atribuido', '_contrato_cobrado_venta', 'contratos_cobrado_regla_equipo');
  if n > 0 or m > 0 or k <> 3 then fallos := fallos + 1; end if;
  out := out || E'\nL6 permisos: ' || k || ' funciones' || (case when n = 0 and m = 0 and k = 3 then ' ok' else ' FALLO' end);

  -- L7
  select count(*) filter (where pg_get_functiondef(p.oid) not like '%_contrato_cobrado_venta%'),
         count(*) filter (where pg_get_functiondef(p.oid) like '%carta_cobrado_importe''%')
    into n, m
    from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname in ('obra_datos_cobro', 'comision_admin_prevision');
  if n > 0 or m > 0 then fallos := fallos + 1; end if;
  out := out || E'\nL7 obra y previsión leen la regla' || (case when n = 0 and m = 0 then ' ok' else ' FALLO' end);

  raise exception E'cobro_regla_lectores: % fallo(s)%', fallos, out;
end
$t$;
