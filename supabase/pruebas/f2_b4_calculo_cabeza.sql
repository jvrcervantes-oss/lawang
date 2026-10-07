-- Prueba de EQUIVALENCIA DEL CALCULO del bloque 4 (8-oct-2026): lo que el motor de comisiones devengaria ANTES y DESPUES de las migraciones 1-2 tiene que ser identico.
-- Uso: se pega CABEZA + migraciones + COLA en una sola peticion (una transaccion que acaba en raise = sin rastro). Mide, en las dos fases:
--   (a) estado: contrato_closer, devengos, solicitudes de pago, diferencias y libro de administracion (md5 de cada uno);
--   (b) para cada venta: el equipo que resuelven _equipo_de_venta y _venta_equipo (por NOMBRE: el gemelo de sandal_woods se llama igual);
--   (c) comisiones_reconciliar(raiz, simular) de todas las ventas con devengos;
--   (d) el efecto de pasar comisiones_evaluar_contrato por TODAS las ventas (dentro de una subtransaccion que se deshace): que devengos y solicitudes
--       nacerian, comparados por VALOR (importe, %, base, tramo, beneficiario), no por id (las copias tienen otros ids).
-- destructivo-ok: ensayo en transaccion que termina en raise (rollback); sin drop
create temp table _b4_ref (tag text, k text, v text);
create or replace function pg_temp.medir(p_tag text) returns void language plpgsql as $m$
declare r record; v_ret int := 0; v_rec text := ''; v_dev text; v_sol text; v_nd int; v_ns int;
begin
  insert into _b4_ref select p_tag, 'contrato_closer', md5(coalesce(string_agg(to_jsonb(k)::text, ',' order by k.contrato_id), '')) from public.contrato_closer k;
  insert into _b4_ref select p_tag, 'devengos', md5(coalesce(string_agg(to_jsonb(d)::text, ',' order by d.id::text), '')) from public.comisiones_devengadas d;
  insert into _b4_ref select p_tag, 'solicitudes', md5(coalesce(string_agg(s.id::text || s.estado || s.importe::text, ',' order by s.id::text), '')) from public.solicitudes_pago s;
  insert into _b4_ref select p_tag, 'diferencias', md5(coalesce(string_agg(to_jsonb(x)::text, ',' order by x.id::text), '')) from public.comisiones_diferencias x;
  insert into _b4_ref select p_tag, 'libro_admin', md5(coalesce(string_agg(to_jsonb(l)::text, ',' order by l.id::text), '')) from public.comision_admin_lineas l;
  insert into _b4_ref
    select p_tag, 'resolucion_equipo', md5(coalesce(string_agg(concat_ws('|', k.contrato_id,
             (select ev.nombre from public.equipos_venta ev where ev.id = (select x.equipo_id from public._equipo_de_venta(k.contrato_id) x limit 1)),
             (select ev.nombre from public.equipos_venta ev where ev.id = public._venta_equipo(k.contrato_id))), ',' order by k.contrato_id), ''))
      from public.contrato_closer k;
  for r in select distinct contrato_raiz_id from public.comisiones_devengadas order by 1 loop
    v_rec := v_rec || coalesce((select string_agg(concat_ws('|', q.devengo_id, q.venta, q.beneficiario, q.nivel, q.estado_devengo, q.base_antes, q.base_despues,
                                                          q.vigente, q.nuevo, q.delta, q.accion, q.motivo), ';' order by q.devengo_id::text)
                                  from public.comisiones_reconciliar(r.contrato_raiz_id, true, '{}'::jsonb) q), '');
  end loop;
  insert into _b4_ref values (p_tag, 'reconciliar', md5(v_rec));
  begin
    for r in select contrato_id from public.contrato_closer order by contrato_id loop
      v_ret := v_ret + coalesce(public.comisiones_evaluar_contrato(r.contrato_id), 0);
    end loop;
    select md5(coalesce(string_agg(z.s, ',' order by z.s), '')), count(*) into v_dev, v_nd from (
      select concat_ws('|', d.contrato_raiz_id, lower(d.beneficiario_email), d.nivel, d.importe, d.moneda, d.estado,
                       d.disparado_por_snapshot->>'pct_comision', d.disparado_por_snapshot->>'base_calculo', d.disparado_por_snapshot->>'pct_tramo',
                       d.disparado_por_snapshot->>'disparador_tipo', d.disparado_por_snapshot->>'umbral') s
        from public.comisiones_devengadas d) z;
    select md5(coalesce(string_agg(z.s, ',' order by z.s), '')), count(*) into v_sol, v_ns from (
      select concat_ws('|', s.contrato_id, s.beneficiario_email, s.importe, s.moneda, s.estado, s.origen) s from public.solicitudes_pago s) z;
    raise exception 'medida hecha' using errcode = 'LWS02';
  exception when sqlstate 'LWS02' then null;
  end;
  insert into _b4_ref values (p_tag, 'evaluador_devuelve', v_ret::text), (p_tag, 'evaluador_devengos', v_dev || ':' || v_nd),
                             (p_tag, 'evaluador_solicitudes', v_sol || ':' || v_ns);
end $m$;
select pg_temp.medir('antes');
