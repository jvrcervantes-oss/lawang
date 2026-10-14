-- Prueba de «obra firmada solo de hijos de obra» (13-oct-2026; migraciones 20261013022113 y 20261013023737).
-- Se ejecuta por execute_sql y TERMINA CON UN RAISE a propósito: no deja rastro. Los casos que cambian algo
-- van en su propio sub-bloque que acaba en excepción, así que no se pisan.
-- Para probar una migración ANTES de aplicarla: pegar su cuerpo delante de este bloque en el MISMO
-- execute_sql (el raise final deshace también la migración).
-- Cada línea dice `ok` o `FALLO`; la última cuenta los fallos.
-- 14-oct-2026: «_split» de los casos es ahora unidad_cobro_reparto (mismas columnas; unidad_parte_cobrada_split solo
-- la envolvía y se borró en 20261014130410, F6/LAW-590). Pasada ese día en producción tras el cambio: 9/9, 0 fallos.
--
-- No da de alta contratos ni llama a contrato_guarda ni a comisiones_evaluar_contrato (LAW-217: nada que
-- gaste series; comisiones inserta devengos y solicitudes de pago). Por eso trabaja sobre filas reales y
-- sobre el catálogo contrato_tipo_etapa, y la parte de comisiones se comprueba con su predicado exacto y con
-- el texto de la función, no ejecutándola. Datos de producción del 13-oct:
--   SH-144 (Sumba Hills)  · Bloqueo RP00170 con un Poder PA00010 firmado y sin Construcción
--   B2 (Mejan Village S7) · Bloqueo RP00159 con la Carta PMA CP00002 firmada y sin Construcción
--   unidades de RP00026   · Bloqueo con la Construcción de ejemplar único CC00088 (cc00014_timon) firmada
-- Casos (esperado con la versión nueva; entre corchetes lo que daba la anterior, medido el 13-oct):
--   T1  SH-144: _interno y _split dan false                           [true y true]
--   T2  B2 Mejan: _interno y _split dan false                         [true y false]
--   T3  una unidad con Construcción firmada: true en las dos          [true]
--   T4  las unidades de RP00026 (cc00014_timon firmado): true         [true]
--   T5  marcar 'poa' como obra en el catálogo → SH-144 pasa a true   (prueba que se lee el catálogo)
--   T6  desmarcar 'construccion' → la unidad de T3 pasa a false       (ídem)
--   T7  hak_sewa_notario, poa y las Cartas NO son obra en el catálogo
--   T8  comisiones: 0 raíces con un hijo de obra firmado según el catálogo entre las 12 que antes lo veían, y
--       la función lee contrato_tipo_etapa.es_obra
--   T9  total de unidades con obra firmada = unidades con un hijo de obra firmado (sin falsos ni faltas)
do $t$
declare
  out text := ''; fallos int := 0; res text; esp text;
  v_uid uuid;
  u_sh uuid; u_b2 uuid; u_cc uuid; u_tim uuid;
  a boolean; b boolean; n int; m int;
begin
  select user_id into v_uid from public.usuarios where activo and rol = 'super_admin' order by email limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);

  select x.id into u_sh from public.unidades x join public.contratos c on c.id = x.contrato_id where c.numero = 'RP00170' and x.codigo = 'SH-144';
  select x.id into u_b2 from public.unidades x join public.contratos c on c.id = x.contrato_id where c.numero = 'RP00159' and x.codigo = 'B2';
  select x.id into u_tim from public.unidades x join public.contratos c on c.id = x.contrato_id where c.numero = 'RP00026' limit 1;
  select h.unidad_id into u_cc from public.contratos h
   where h.tipo = 'construccion' and h.bloqueado and h.unidad_id is not null and h.contrato_padre_id is not null
   order by h.numero limit 1;

  -- T1
  select i.obra_firmada, s.obra_firmada into a, b from public.unidad_parte_cobrada_interno(u_sh) i, public.unidad_cobro_reparto(u_sh) s;
  res := coalesce(a::text, 'null') || '/' || coalesce(b::text, 'null'); esp := 'false/false';
  out := out || 'T1 ' || case when res = esp then 'ok   ' else 'FALLO' end || ' SH-144 ' || res || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T2
  select i.obra_firmada, s.obra_firmada into a, b from public.unidad_parte_cobrada_interno(u_b2) i, public.unidad_cobro_reparto(u_b2) s;
  res := coalesce(a::text, 'null') || '/' || coalesce(b::text, 'null'); esp := 'false/false';
  out := out || 'T2 ' || case when res = esp then 'ok   ' else 'FALLO' end || ' B2 Mejan ' || res || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T3
  select i.obra_firmada, s.obra_firmada into a, b from public.unidad_parte_cobrada_interno(u_cc) i, public.unidad_cobro_reparto(u_cc) s;
  res := coalesce(a::text, 'null') || '/' || coalesce(b::text, 'null'); esp := 'true/true';
  out := out || 'T3 ' || case when res = esp then 'ok   ' else 'FALLO' end || ' construccion ' || res || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T4
  select i.obra_firmada, s.obra_firmada into a, b from public.unidad_parte_cobrada_interno(u_tim) i, public.unidad_cobro_reparto(u_tim) s;
  res := coalesce(a::text, 'null') || '/' || coalesce(b::text, 'null'); esp := 'true/true';
  out := out || 'T4 ' || case when res = esp then 'ok   ' else 'FALLO' end || ' cc00014_timon ' || res || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T5
  esp := 'true/true';
  begin
    update public.contrato_tipo_etapa set es_obra = true where tipo = 'poa';
    select i.obra_firmada, s.obra_firmada into a, b from public.unidad_parte_cobrada_interno(u_sh) i, public.unidad_cobro_reparto(u_sh) s;
    raise exception '__R__%', coalesce(a::text, 'null') || '/' || coalesce(b::text, 'null');
  exception when others then res := case when sqlerrm like '\_\_R\_\_%' then substr(sqlerrm, 6) else 'ERROR ' || left(sqlerrm, 120) end; end;
  out := out || 'T5 ' || case when res = esp then 'ok   ' else 'FALLO' end || ' poa marcado como obra ' || res || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T6
  esp := 'false/false';
  begin
    update public.contrato_tipo_etapa set es_obra = false where tipo = 'construccion';
    select i.obra_firmada, s.obra_firmada into a, b from public.unidad_parte_cobrada_interno(u_cc) i, public.unidad_cobro_reparto(u_cc) s;
    raise exception '__R__%', coalesce(a::text, 'null') || '/' || coalesce(b::text, 'null');
  exception when others then res := case when sqlerrm like '\_\_R\_\_%' then substr(sqlerrm, 6) else 'ERROR ' || left(sqlerrm, 120) end; end;
  out := out || 'T6 ' || case when res = esp then 'ok   ' else 'FALLO' end || ' construccion desmarcada ' || res || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T7
  select count(*) into n from public.contrato_tipo_etapa
   where es_obra and (tipo in ('hak_sewa_notario', 'poa') or etapa = 'reserva');
  res := n::text; esp := '0';
  out := out || 'T7 ' || case when res = esp then 'ok   ' else 'FALLO' end || ' tipos no-obra marcados como obra: ' || res || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T8
  select count(*) into n from public.contratos r
   where r.numero in ('RP00040','RP00045','RP00198','RP00202','RP00203','RP00204','RP00259','RP00262','RP00264','RP00159','HS00003','RP00170')
     and exists (select 1 from public.contratos h where h.contrato_padre_id = r.id and h.bloqueado
                   and exists (select 1 from public.contrato_tipo_etapa e where e.tipo = h.tipo and e.es_obra));
  res := n::text || '/' || (position('e.tipo = h.tipo and e.es_obra' in pg_get_functiondef('public.comisiones_evaluar_contrato(uuid)'::regprocedure)) > 0)::text;
  esp := '0/true';
  out := out || 'T8 ' || case when res = esp then 'ok   ' else 'FALLO' end || ' comisiones (raices con obra / lee catalogo) ' || res || E'\n'; fallos := fallos + (res <> esp)::int;
  -- T9
  select count(*) filter (where i.obra_firmada), count(*) filter (where s.obra_firmada) into n, m
    from public.unidades x, public.unidad_parte_cobrada_interno(x.id) i, public.unidad_cobro_reparto(x.id) s;
  res := n::text || '/' || m::text || '/' || (select count(*) from public.unidades x join public.contratos c on c.id = x.contrato_id
    where exists (select 1 from public.contratos h join public.contrato_tipo_etapa e on e.tipo = h.tipo and e.es_obra
                   where h.contrato_padre_id = coalesce(c.contrato_padre_id, c.id) and h.bloqueado
                     and (h.unidad_id = x.id or (h.unidad_id is null and not exists (
                          select 1 from public.contratos h2 where h2.contrato_padre_id = coalesce(c.contrato_padre_id, c.id)
                             and h2.unidad_id = x.id and h2.tipo is distinct from 'carta_reserva')))))::text;
  esp := split_part(res, '/', 3) || '/' || split_part(res, '/', 3) || '/' || split_part(res, '/', 3);
  out := out || 'T9 ' || case when res = esp then 'ok   ' else 'FALLO' end || ' unidades con obra firmada (interno/split/esperado) ' || res || E'\n'; fallos := fallos + (res <> esp)::int;

  raise exception E'\n%FALLOS: %', out, fallos;
end
$t$;
