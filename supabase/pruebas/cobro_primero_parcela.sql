-- Prueba de «primero la parcela, luego la obra» (owner, 14-oct-2026; migraciones 20261014024234_cobro_primero_parcela.sql
-- , 20261014032925_cobro_primero_parcela_contrato.sql y 20261014040310_cobro_primero_parcela_borrador.sql). Lo que ESCRIBE (firmar, cambiar un precio) se prueba aparte, en
-- cobro_primero_parcela_contrato.sql.
-- SOLO LECTURA: se ejecuta por execute_sql y TERMINA CON UN RAISE a propósito (no deja rastro; el cambio de rol y los
-- claims se deshacen con él). No da de alta nada, no gasta series y no llama a comisiones_evaluar_contrato (LAW-217).
-- Trabaja sobre TODAS las unidades con contrato de producción: son invariantes de la regla, no casos sueltos.
-- Cada línea dice `ok` o `FALLO`; la última cuenta los fallos.
--
--   T1  ninguna parcela tiene más «suelo cobrado» que su precio (el tope de la cascada)
--   T2  venta a venta: lo repartido entre sus parcelas (suelo + obra) = lo cobrado en la venta. La regla reparte, no
--       crea ni pierde dinero
--   T3  venta a venta: hay «obra cobrada» SOLO si el suelo de la venta está completo
--   T4  ninguna venta tiene dos Bloqueos de Parcela FIRMADOS con precio para la misma parcela (sumarían dos veces el
--       tope: si pasa, es un dato que arreglar, no una regla nueva)
--   T5  las tres lecturas dan lo mismo: _interno (estados, comisiones) = cascada; unidad_cobro_reparto, con un admin,
--       = cascada. Es lo que evita que vuelva a haber dos copias del reparto
--   T6  «vendida» se mide contra el precio del Bloqueo de la venta, firmado o no (owner, 14-oct; 20261014040310):
--       unidad_cumple_estado = (precio > 0 y suelo cobrado >= precio); y `suelo_de_contrato` solo es cierto si la RAÍZ
--       de la venta es un Bloqueo de Parcela sin liberar y con precio (un Bloqueo hijo no cuenta)
--   T7  sin permiso, unidad_cobro_reparto devuelve NULL (no 0) y la cascada no es llamable por authenticated / anon
--   T8  el motor de comisiones lee la cascada y mide el suelo contra el precio de contrato solo si está FIRMADO
--   T9  la vista unidades_estado sigue siendo security_invoker y trae suelo_pactado / obra_pactada
--   T10 el caso que lo destapó: SH-1 (Sumba Hills), 41.620 cobrados contra una parcela de 25.000 → 25.000 + 16.620
do $t$
declare
  out text := ''; fallos int := 0; n int; m int; v_t text;
  v_uid uuid; v_mail text;
begin
  -- T1
  select count(*), coalesce(string_agg(u.codigo, ', '), '-') into n, v_t
    from public.unidades u cross join lateral public._unidad_cobro_cascada(u.id) x
   where u.contrato_id is not null and x.suelo_precio > 0 and x.cobrado_suelo > x.suelo_precio + 0.005;
  if n > 0 then fallos := fallos + 1; end if;
  out := out || E'\nT1 suelo sobre su precio: ' || n || (case when n = 0 then ' ok' else ' FALLO ' || v_t end);

  -- T2 y T3
  with per as (
    select u.contrato_id as raiz_u, sum(x.cobrado_suelo) as s, sum(x.cobrado_obra) as o, sum(x.suelo_precio) as tope, min(u.codigo) as codigo
      from public.unidades u cross join lateral public._unidad_cobro_cascada(u.id) x
     where u.contrato_id is not null
     group by u.contrato_id
  ), k as (
    select per.s, per.o, per.tope, per.codigo,
           (select coalesce(sum(public.contrato_cobrado(c.id)), 0) from public.contratos c
             where c.id = rz.id or c.contrato_padre_id = rz.id) as cobrado
      from per
      cross join lateral (select coalesce(c0.contrato_padre_id, c0.id) as id from public.contratos c0 where c0.id = per.raiz_u limit 1) rz
  )
  select count(*) filter (where abs(s + o - cobrado) > 0.02),
         count(*) filter (where tope > 0 and o > 0.02 and s < tope - 0.02),
         count(*) || ' ventas'
           || coalesce(' · no cuadra: ' || string_agg(codigo || ' ' || round(s + o, 2) || ' vs ' || round(cobrado, 2), '; ') filter (where abs(s + o - cobrado) > 0.02), '')
           || coalesce(' · obra sin suelo: ' || string_agg(codigo, ', ') filter (where tope > 0 and o > 0.02 and s < tope - 0.02), '')
    into n, m, v_t from k;
  if n > 0 then fallos := fallos + 1; end if;
  if m > 0 then fallos := fallos + 1; end if;
  out := out || E'\nT2 reparto = cobrado de la venta: ' || (case when n = 0 then 'ok' else 'FALLO' end)
             || E'\nT3 obra solo con el suelo completo: ' || (case when m = 0 then 'ok' else 'FALLO' end) || ' (' || v_t || ')';

  -- T4
  with raices as (select distinct u.contrato_id as id from public.unidades u where u.contrato_id is not null),
  blo as (
    select coalesce(c.contrato_padre_id, c.id) as raiz, c.unidad_id, c.numero
      from raices r
      join public.contratos c on c.id = r.id or c.contrato_padre_id = r.id
     where c.tipo = 'reserva_parcela' and coalesce(c.bloqueado, false) and c.liberado_en is null and coalesce(c.precio_total, 0) > 0
  ), dup as (select raiz, unidad_id, string_agg(numero, '+' order by numero) as nums from blo group by raiz, unidad_id having count(*) > 1)
  select count(*), coalesce(string_agg(nums, '; '), '-') into n, v_t from dup;
  if n > 0 then fallos := fallos + 1; end if;
  out := out || E'\nT4 dos Bloqueos firmados para la misma parcela: ' || n || (case when n = 0 then ' ok' else ' FALLO ' || v_t end);

  -- T5a: _interno = cascada
  select count(*) into n
    from public.unidades u
    cross join lateral public._unidad_cobro_cascada(u.id) x
    cross join lateral public.unidad_parte_cobrada_interno(u.id) i
   where (x.cobrado_suelo, x.cobrado_obra, x.obra_firmada) is distinct from (i.cobrado_suelo, i.cobrado_obra, i.obra_firmada);
  if n > 0 then fallos := fallos + 1; end if;
  out := out || E'\nT5a _interno = cascada: ' || (case when n = 0 then 'ok' else 'FALLO en ' || n end);

  -- T6
  select count(*) into n
    from public.unidades u cross join lateral public._unidad_cobro_cascada(u.id) x
   where u.contrato_id is not null and x.suelo_de_contrato
     and public.unidad_cumple_estado(u.id, 'vendida', u.precio, u.precio_suelo)
         is distinct from (x.suelo_precio > 0 and x.cobrado_suelo >= x.suelo_precio);
  select n + count(*) into n
    from public.unidades u cross join lateral public._unidad_cobro_cascada(u.id) x
    cross join lateral (select coalesce(c0.contrato_padre_id, c0.id) as id from public.contratos c0 where c0.id = u.contrato_id limit 1) rz
   where u.contrato_id is not null and x.suelo_de_contrato
     and not exists (select 1 from public.contratos b where b.id = rz.id
                        and b.tipo = 'reserva_parcela' and b.liberado_en is null and coalesce(b.precio_total, 0) > 0);
  if n > 0 then fallos := fallos + 1; end if;
  out := out || E'\nT6 «vendida» contra el precio de contrato: ' || (case when n = 0 then 'ok' else 'FALLO en ' || n end);

  -- T8
  select count(*) into n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'comisiones_evaluar_contrato'
     and position('public._unidad_cobro_cascada(u.id) cp' in p.prosrc) > 0
     and position('case when cp.suelo_de_contrato and v_contrato_firmado then cp.suelo_precio else u.precio_suelo end' in p.prosrc) > 0
     and position('coalesce(cp.obra_precio, u.precio_construccion)' in p.prosrc) > 0
     and position('unidad_parte_cobrada_interno' in p.prosrc) = 0;
  if n <> 1 then fallos := fallos + 1; end if;
  out := out || E'\nT8 comisiones lee la cascada: ' || (case when n = 1 then 'ok' else 'FALLO' end);

  -- T9
  select count(*) into n from pg_class c
   where c.relname = 'unidades_estado' and c.relnamespace = 'public'::regnamespace and c.reloptions::text like '%security_invoker=true%'
     and (select count(*) from information_schema.columns k where k.table_schema = 'public' and k.table_name = 'unidades_estado'
            and k.column_name in ('suelo_pactado', 'obra_pactada')) = 2;
  if n <> 1 then fallos := fallos + 1; end if;
  out := out || E'\nT9 vista security_invoker con las dos columnas: ' || (case when n = 1 then 'ok' else 'FALLO' end);

  -- T7a: permisos en el catálogo
  select count(*) into n
    from (values ('_unidad_cobro_cascada'), ('unidad_parte_cobrada_interno'), ('unidad_parte_cobrada_split'), ('unidad_cumple_estado')) as f(nombre)
    join pg_proc p on p.proname = f.nombre and p.pronamespace = 'public'::regnamespace
   where has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
      or has_function_privilege('lw_lector', p.oid, 'execute');
  select n + count(*) into n from pg_proc p
   where p.proname = 'unidad_cobro_reparto' and p.pronamespace = 'public'::regnamespace
     and (has_function_privilege('anon', p.oid, 'execute') or not has_function_privilege('authenticated', p.oid, 'execute')
          or not has_function_privilege('lw_lector', p.oid, 'execute') or not p.prosecdef);
  if n > 0 then fallos := fallos + 1; end if;
  out := out || E'\nT7a permisos (cascada cerrada, reparto para la pantalla): ' || (case when n = 0 then 'ok' else 'FALLO en ' || n end);

  -- T5b, T7b y T10 con el rol real de la pantalla
  select us.user_id, us.email into v_uid, v_mail from public.usuarios us
   where us.rol = 'super_admin' and us.activo and us.user_id is not null order by us.email limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated', 'email', v_mail)::text, true);
  execute 'set local role authenticated';
  select count(*), count(*) filter (where ue.cobrado_suelo is null) into n, m from public.unidades_estado ue where ue.contrato_id is not null;
  select string_agg(ue.cobrado_suelo || '/' || ue.suelo_pactado || ' + ' || ue.cobrado_obra, '') into v_t
    from public.unidades_estado ue where ue.proyecto = 'Sumba Hills' and ue.codigo = 'SH-1';
  execute 'reset role';
  if m > 0 then fallos := fallos + 1; end if;
  out := out || E'\nT5b un admin ve el reparto de las ' || n || ' unidades con contrato por la vista: ' || (case when m = 0 then 'ok' else 'FALLO, ' || m || ' en blanco' end);
  select count(*) into n
    from public.unidades u
    cross join lateral public._unidad_cobro_cascada(u.id) x
    cross join lateral public.unidad_cobro_reparto(u.id) r
   where u.contrato_id is not null
     and (x.cobrado_suelo, x.cobrado_obra, x.obra_firmada, x.suelo_precio, x.obra_precio)
         is distinct from (r.cobrado_suelo, r.cobrado_obra, r.obra_firmada, r.suelo_precio, r.obra_precio);
  if n > 0 then fallos := fallos + 1; end if;
  out := out || E'\nT5c unidad_cobro_reparto (admin) = cascada: ' || (case when n = 0 then 'ok' else 'FALLO en ' || n end);
  if v_t is distinct from '25000.00/25000.00 + 16620.00' then fallos := fallos + 1; end if;
  out := out || E'\nT10 SH-1: ' || coalesce(v_t, 'null') || (case when v_t = '25000.00/25000.00 + 16620.00' then ' ok' else ' FALLO (esperado 25000.00/25000.00 + 16620.00; si SH-1 cobró más, actualizar el esperado)' end);

  -- T7b: alguien autenticado que no es del equipo no ve el cobro de una parcela con contrato (NULL, no 0)
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated', 'email', 'nadie@example.invalid')::text, true);
  select count(*), count(r.cobrado_suelo) into n, m
    from (select u.id from public.unidades u where u.contrato_id is not null order by u.id limit 20) u
    cross join lateral public.unidad_cobro_reparto(u.id) r;
  if m > 0 then fallos := fallos + 1; end if;
  out := out || E'\nT7b sin permiso, NULL y no 0: ' || (case when m = 0 then 'ok' else 'FALLO, ' || m || ' de ' || n || ' con dato' end);

  raise exception E'cobro_primero_parcela: % fallo(s)%', fallos, out;
end
$t$;
