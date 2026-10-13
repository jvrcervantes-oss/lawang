-- PRUEBA — comisiones desde el 1-nov-2026 (migración comisiones_regla_1nov, owner 13-oct-2026).
-- Se ejecuta entera con execute_sql (MCP) como postgres, DESPUÉS de aplicar la migración. NO ESCRIBE NADA: cada caso
-- va en un sub-bloque que acaba en excepción y el bloque entero termina en `raise exception 'RES: …'`.
-- Cada caso debe decir «ok»; un «FALLO» es dinero mal calculado.
--
-- ⚠ NECESITA LA VÁLVULA DEL OWNER EN CADA EJECUCIÓN (~/.axisworks/destructivo-ok, tools/no_destruir.py): el montaje
--   usa session_replication_role = replica (para mover precios, firmas y el closer de una venta real sin que salten
--   sus triggers) y borra, dentro de la transacción que se deshace, los devengos de la venta de laboratorio. Lo mismo
--   le pasa a prueba_comisiones_recalculo.sql desde el freno del 11-oct.
--
-- SERIES (LAW-217): ninguna prueba consume números. El motor crea una solicitud de pago (serie SP, identity) por cada
-- devengo de manager/estándar/propia; aquí se desactivan los usuarios dentro de la transacción, así el motor no resuelve
-- creado_por y deja el devengo sin solicitud (no hace nextval). El reconciliador solo se llama en simulación (no crea
-- DIF-). El caso S compara last_value de SP, DIF, REC, PRO e INV antes y después.
--
-- LABORATORIO: la venta real RP00133 (Lawang, equipo «Gus Abellán», closer gusabellan con condición propia al 0 %).
-- Dentro de la transacción: se le borran sus devengos, se le cuelga CC00084 (de RP00132: 44.000, 20.000 cobrados), su
-- RP pasa a 59.000 (29.500 cobrados = 50 % justo) y la venta pasa al 5-nov-2026 con el equipo congelado. Queda:
--   parcela firmada = RP00133 59.000 (cobrado 29.500)
--   obra firmada    = CC00085 44.000 (0) + CC00084 44.000 (20.000) = 88.000, 22,7 % cobrado
--   la carta hija CR00051 (64.000, 5.000 cobrados) se deja SIN FIRMAR en el montaje: los casos 1–10 miden la parcela
--   sola (la carta nunca suma en la BASE, pero desde el 13-oct su cobro sí cuenta como pago: «primero parcela, luego
--   obra»). Los casos C1–C5 la firman para probar esa imputación; comparan las cifras de _comisiones_bases_firmadas
--   como números (no como texto) y el devengo que sale.
-- Condiciones sucesoras del equipo (lawang): manager c0a11010-…-04 (10 %), closer genérico c0a11010-…-03 (2,5 %,
-- plantilla del SM: closer 25 %).
-- condicion_tramos_reemplaza se quitó en la migración (sin llamador): G1/G3 ya iban por condicion_comision_guarda, la
-- RPC real de la pantalla. F8b (plantilla con distinto nº de tramos), R7 (recorte del snapshot), AD (adenda en obra) y
-- M1/M2 (moneda) se añadieron
-- el 13-oct tras la revisión de código y la consulta de Administración.
do $$
declare
  r text := '';
  v_raiz uuid; v_cc85 uuid; v_cc84 uuid; v_cr51 uuid;
  v_gus  uuid := 'd212a050-4297-4e1e-a7d3-fe4b4fcf30c0';
  c_man  uuid := 'c0a11010-1101-4a10-8000-000000000004';
  t_man2 uuid := 'c0a11010-1101-4b10-8000-000000000402';
  c_clo  uuid := 'c0a11010-1101-4a10-8000-000000000003';
  c_vic_clo uuid := 'c0a11010-1101-4a10-8000-000000000005';
  v_suc  uuid[] := array(select ('c0a11010-1101-4a10-8000-0000000000' || lpad(i::text, 2, '0'))::uuid from generate_series(1, 12) i);
  v_sp0 bigint; v_dif0 bigint; v_rec0 bigint; v_pro0 bigint; v_inv0 bigint;
  v_t text; v_n int; v_m int; v_adm record; v_sm record; v_ok boolean; v_b text;
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'condicion_tramos' and column_name = 'base_calculo')
     or not exists (select 1 from public.condiciones_comision where id = c_man) then
    raise exception 'RES: la migración comisiones_regla_1nov no está aplicada';
  end if;
  select last_value into v_sp0  from public.solicitudes_pago_numero_seq;
  select last_value into v_dif0 from public.comisiones_diferencias_seq;
  select last_value into v_rec0 from public.facturas_recibi_seq;
  select last_value into v_pro0 from public.facturas_proforma_seq;
  select last_value into v_inv0 from public.facturas_seq;
  select id into v_raiz from public.contratos where numero = 'RP00133';
  select id into v_cc85 from public.contratos where numero = 'CC00085';
  select id into v_cc84 from public.contratos where numero = 'CC00084';
  select id into v_cr51 from public.contratos where numero = 'CR00051';
  if v_raiz is null or v_cc85 is null or v_cc84 is null or v_cr51 is null then
    raise exception 'RES: falta alguna pieza del laboratorio (RP00133, CC00085, CC00084, CR00051)';
  end if;

  -- G1 · editor viejo (tramos sin base_calculo) por la RPC de la pantalla, con sesión de super admin: conserva la base
  begin
    select u.user_id, u.email into v_adm from public.usuarios u where u.rol = 'super_admin' and u.activo order by u.email limit 1;
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.email, 'role', 'authenticated')::text, true);
    set local role authenticated;
    perform public.condicion_comision_guarda(c_man,
      '{"pct_comision": 10, "base_calculo": "por_tramo", "vigente_desde": "2026-11-01"}'::jsonb,
      '[{"disparador_tipo": "pct_cobrado_suelo_firmado", "umbral": 50, "pct_tramo": 100},
        {"disparador_tipo": "pct_cobrado_obra_firmada", "umbral": 25, "pct_tramo": 100}]'::jsonb, null);
    set constraints all immediate;
    select string_agg((t->>'orden') || ':' || coalesce(t->>'base_calculo', 'null'), ',' order by (t->>'orden')::int) into v_t
      from jsonb_array_elements(public.condiciones_comision_datos()->'tramos') t where t->>'condicion_id' = c_man::text;
    raise exception 'R:%', v_t;
  exception when others then
    r := r || 'G1 editor viejo conserva la base=' || sqlerrm
         || case when sqlerrm = 'R:1:precio_suelo_firmado,2:precio_obra_firmada' then ' ok; ' else ' FALLO; ' end;
  end;

  -- G2/G3 · un SM (no admin) ante una condición de su equipo EN VIGOR: cambiar solo la base de un tramo se rechaza como
  -- cambio de cifras (G2); el editor viejo sin base, con las mismas cifras, pasa (G3). Montaje: la sucesora del closer de
  -- Victor (…-05) en vigor desde el 1-oct y un usuario «agente» de prueba como su SM.
  select u.user_id, u.email into v_sm from public.usuarios u
   where u.activo and u.rol in ('sales_manager', 'agente')
     and not exists (select 1 from public.equipo_miembros em where lower(em.closer_email) = lower(u.email))
     and not exists (select 1 from public.equipos_venta ev where lower(ev.manager_email) = lower(u.email))
   order by (u.rol = 'sales_manager') desc, u.email limit 1;   -- medido 13-oct: 10 agentes activos fuera de equipos
  if v_sm.user_id is null then
    r := r || 'G2/G3 sin usuario agente de prueba: NO PROBADO; ';
  else
    begin
      execute 'set local session_replication_role = replica';
      update public.condiciones_comision set vigente_hasta = date '2026-09-30' where id = '4a1036e7-58d0-4b81-b5fd-ab0de41dcee1';
      update public.condiciones_comision set vigente_desde = date '2026-10-01' where id = c_vic_clo;
      update public.equipos_venta set manager_email = v_sm.email where id = '7124be6e-a9bf-45d3-a775-5cc29f9d8259';
      execute 'set local session_replication_role = origin';
      perform set_config('request.jwt.claims', json_build_object('sub', v_sm.user_id, 'email', v_sm.email, 'role', 'authenticated')::text, true);
      set local role authenticated;
      begin
        perform public.condicion_comision_guarda(c_vic_clo,
          '{"pct_comision": 2.5, "base_calculo": "por_tramo", "vigente_desde": "2026-10-01"}'::jsonb,
          '[{"disparador_tipo": "pct_cobrado_suelo_firmado", "umbral": 50, "pct_tramo": 100, "base_calculo": "precio_obra_firmada"},
            {"disparador_tipo": "pct_cobrado_obra_firmada", "umbral": 25, "pct_tramo": 100, "base_calculo": "precio_suelo_firmado"}]'::jsonb, null);
        v_t := 'G2 pasó';
      exception when others then
        v_t := sqlerrm;
      end;
      r := r || 'G2 SM cambia solo la base de un tramo en vigor=' || v_t
           || case when v_t like '%en vigor desde%' then ' ok; ' else ' FALLO; ' end;
      begin
        perform public.condicion_comision_guarda(c_vic_clo,
          '{"pct_comision": 2.5, "base_calculo": "por_tramo", "vigente_desde": "2026-10-01"}'::jsonb,
          '[{"disparador_tipo": "pct_cobrado_suelo_firmado", "umbral": 50, "pct_tramo": 100},
            {"disparador_tipo": "pct_cobrado_obra_firmada", "umbral": 25, "pct_tramo": 100}]'::jsonb, null);
        v_t := 'pasa';
      exception when others then
        v_t := sqlerrm;
      end;
      raise exception 'R:%', v_t;
    exception when others then
      r := r || 'G3 SM con editor viejo y mismas cifras=' || sqlerrm || case when sqlerrm = 'R:pasa' then ' ok; ' else ' FALLO; ' end;
    end;
  end if;

  -- MONTAJE común (se deshace al final con todo lo demás)
  execute 'set local session_replication_role = replica';
  update public.usuarios set activo = false where activo = true;
  delete from public.comisiones_devengadas where contrato_raiz_id = v_raiz;
  delete from public.contrato_roles_equipo where contrato_raiz_id = v_raiz;
  update public.contratos set contrato_padre_id = v_raiz where id = v_cc84;
  update public.contratos set precio_total = 59000 where id = v_raiz;
  update public.contratos set bloqueado = false where id = v_cr51;   -- carta sin firmar: su cobro no cuenta (C1–C5 la firman)
  update public.contrato_closer
     set closer_email = 'gusabellan@gmail.com', fecha_venta = date '2026-11-05', equipo_id = v_gus,
         manager_email = 'gusabellan@gmail.com', equipo_congelado_en = now(), modo = 'equipo', modo_espera_hasta = null
   where contrato_id = v_raiz;
  execute 'set local session_replication_role = origin';

  -- B · bases de la familia: la carta hija (64.000, sin firmar en el montaje) no suma en ninguna
  select b.suelo_firmado || '/' || b.obra_firmada || ' cob ' || b.cobrado_suelo_firmado || '/' || b.cobrado_obra_firmada
    into v_t from public._comisiones_bases_firmadas(v_raiz) b;
  r := r || 'B bases sin la carta hija=' || v_t || case when v_t = '59000/88000 cob 29500/20000' then ' ok; ' else ' FALLO; ' end;

  -- 1 · parcela al 50 % justo → 10 % de la parcela firmada; obra al 22,7 % → nada; closer Gus al 0 % → nada
  begin
    perform public.comisiones_evaluar_contrato(v_raiz);
    select coalesce(string_agg(d.nivel || ':' || t.orden || ':' || d.importe || ':' || (d.disparado_por_snapshot->>'base_calculo'), ','
                               order by d.nivel, t.orden), '-') into v_t
      from public.comisiones_devengadas d join public.condicion_tramos t on t.id = d.tramo_id where d.contrato_raiz_id = v_raiz;
    raise exception 'R:%', v_t;
  exception when others then
    r := r || '1 parcela 50%=' || sqlerrm || case when sqlerrm = 'R:manager:1:5900.00:precio_suelo_firmado' then ' ok; ' else ' FALLO; ' end;
  end;

  -- 1b · un céntimo por debajo del 50 % → nada
  begin
    execute 'set local session_replication_role = replica';
    update public.contratos set precio_total = 59000.02 where id = v_raiz;
    execute 'set local session_replication_role = origin';
    perform public.comisiones_evaluar_contrato(v_raiz);
    raise exception 'R:%', (select count(*) from public.comisiones_devengadas where contrato_raiz_id = v_raiz);
  exception when others then
    r := r || '1b parcela 49,99%=' || sqlerrm || case when sqlerrm = 'R:0' then ' ok; ' else ' FALLO; ' end;
  end;

  -- 2 · obra al 25 % justo (CC00085 a 36.000 → obra 80.000) → 10 % de la obra firmada; el closer Gus (0 %) sigue sin nada
  begin
    execute 'set local session_replication_role = replica';
    update public.contratos set precio_total = 36000 where id = v_cc85;
    execute 'set local session_replication_role = origin';
    perform public.comisiones_evaluar_contrato(v_raiz);
    select coalesce(string_agg(d.nivel || ':' || t.orden || ':' || d.importe || ':' || (d.disparado_por_snapshot->>'base_calculo'), ','
                               order by d.nivel, t.orden), '-') into v_t
      from public.comisiones_devengadas d join public.condicion_tramos t on t.id = d.tramo_id where d.contrato_raiz_id = v_raiz;
    raise exception 'R:%', v_t;
  exception when others then
    r := r || '2 obra 25% y closer 0%=' || sqlerrm
         || case when sqlerrm = 'R:manager:1:5900.00:precio_suelo_firmado,manager:2:8000.00:precio_obra_firmada' then ' ok; ' else ' FALLO; ' end;
  end;

  -- 3 · obra sin firmar → solo el tramo de parcela y ninguna fila del de obra; al firmarse devenga una vez
  begin
    execute 'set local session_replication_role = replica';
    update public.contratos set bloqueado = false where id in (v_cc84, v_cc85);
    execute 'set local session_replication_role = origin';
    perform public.comisiones_evaluar_contrato(v_raiz);
    select count(*) filter (where t.orden = 2), count(*) filter (where t.orden = 1) into v_n, v_m
      from public.comisiones_devengadas d join public.condicion_tramos t on t.id = d.tramo_id where d.contrato_raiz_id = v_raiz;
    v_t := 'sin firmar t1=' || v_m || ' t2=' || v_n;
    execute 'set local session_replication_role = replica';
    update public.contratos set bloqueado = true where id = v_cc84;
    execute 'set local session_replication_role = origin';
    perform public.comisiones_evaluar_contrato(v_raiz);
    v_n := public.comisiones_evaluar_contrato(v_raiz);
    select v_t || ' | firmada: ' || string_agg(d.importe::text, ',') || ' filas=' || count(*) || ' 2a pasada=' || v_n into v_t
      from public.comisiones_devengadas d where d.contrato_raiz_id = v_raiz and d.tramo_id = 'c0a11010-1101-4b10-8000-000000000402';
    raise exception 'R:%', v_t;
  exception when others then
    r := r || '3 obra sin firmar=' || sqlerrm
         || case when sqlerrm = 'R:sin firmar t1=1 t2=0 | firmada: 4400.00 filas=1 2a pasada=0' then ' ok; ' else ' FALLO; ' end;
  end;

  -- 4 · venta del 31-oct a las 23:50 de Bali → regla vieja (ninguna sucesora); a las 00:00 del 1-nov → regla nueva
  begin
    execute 'set local session_replication_role = replica';
    update public.contrato_closer set fecha_venta = null where contrato_id = v_raiz;
    update public.contratos set created_at = timestamptz '2026-10-31 23:50:00+08' where id = v_raiz;
    execute 'set local session_replication_role = origin';
    perform public.comisiones_evaluar_contrato(v_raiz);
    select count(*) filter (where d.condicion_id = any (v_suc)), coalesce(string_agg(distinct d.condicion_id::text, ','), '-')
      into v_n, v_t
      from public.comisiones_devengadas d where d.contrato_raiz_id = v_raiz;
    raise exception 'R:sucesoras=% (condiciones %)', v_n, v_t;
  exception when others then
    r := r || '4a venta 31-oct 23:50 Bali=' || sqlerrm
         || case when sqlerrm like 'R:sucesoras=0 %' then ' ok; ' else ' FALLO; ' end;
  end;
  begin   -- 4b · la misma venta a las 00:00 del 1-nov (hora de Bali) → regla nueva
    execute 'set local session_replication_role = replica';
    update public.contrato_closer set fecha_venta = null where contrato_id = v_raiz;
    update public.contratos set created_at = timestamptz '2026-11-01 00:00:00+08' where id = v_raiz;
    execute 'set local session_replication_role = origin';
    perform public.comisiones_evaluar_contrato(v_raiz);
    raise exception 'R:%', (select count(*) from public.comisiones_devengadas d where d.contrato_raiz_id = v_raiz and d.condicion_id = c_man);
  exception when others then
    r := r || '4b venta 1-nov 00:00 Bali=' || sqlerrm || case when sqlerrm = 'R:1' then ' ok; ' else ' FALLO; ' end;
  end;

  -- 5 · obra firmada el 10-nov sobre una venta del 20-oct → regla vieja (manda la fecha de la venta, no la del hijo)
  begin
    execute 'set local session_replication_role = replica';
    update public.contrato_closer set fecha_venta = date '2026-10-20' where contrato_id = v_raiz;
    update public.contratos set created_at = timestamptz '2026-11-10 10:00:00+08', precio_total = 36000 where id = v_cc85;
    execute 'set local session_replication_role = origin';
    perform public.comisiones_evaluar_contrato(v_raiz);
    raise exception 'R:%', (select count(*) from public.comisiones_devengadas d where d.contrato_raiz_id = v_raiz and d.condicion_id = any (v_suc));
  exception when others then
    r := r || '5 adenda de obra posterior=' || sqlerrm || case when sqlerrm = 'R:0' then ' ok; ' else ' FALLO; ' end;
  end;

  -- 7 · closer de equipo por plantilla (25 % del 10 % del SM) → 2,5 % en cada tramo, sobre la base de su tramo
  begin
    execute 'set local session_replication_role = replica';
    update public.contrato_closer set closer_email = 'santidavidse@gmail.com' where contrato_id = v_raiz;
    update public.contratos set precio_total = 36000 where id = v_cc85;
    execute 'set local session_replication_role = origin';
    perform public.comisiones_evaluar_contrato(v_raiz);
    select coalesce(string_agg(d.nivel || ':' || t.orden || ':' || d.importe || ':' || coalesce(d.disparado_por_snapshot->>'plantilla_pct', '-'), ','
                               order by d.nivel, t.orden), '-') into v_t
      from public.comisiones_devengadas d join public.condicion_tramos t on t.id = d.tramo_id where d.contrato_raiz_id = v_raiz;
    raise exception 'R:%', v_t;
  exception when others then
    r := r || '7 closer por plantilla=' || sqlerrm
         || case when sqlerrm = 'R:closer:1:1475.00:25.00,closer:2:2000.00:25.00,manager:1:5900.00:-,manager:2:8000.00:-' then ' ok; ' else ' FALLO; ' end;
  end;

  -- W · el reconciliador ESCRIBIENDO (el camino del recálculo automático, encendido): desde el estado del caso 7, sube la
  --     obra a 90.000 → el closer t2 se actualiza en su sitio al 2,5 % de la obra nueva con su congelado al día y el t1
  --     (parcela) no se toca. Los devengos del manager se quitan dentro del bloque: sin solicitud irían a «revisar» y
  --     crearían una DIF- (serie). Solo consume el id interno de comisiones_ajustes_log (no es una serie de documentos).
  begin
    execute 'set local session_replication_role = replica';
    update public.contrato_closer set closer_email = 'santidavidse@gmail.com' where contrato_id = v_raiz;
    update public.contratos set precio_total = 36000 where id = v_cc85;
    execute 'set local session_replication_role = origin';
    perform public.comisiones_evaluar_contrato(v_raiz);
    execute 'set local session_replication_role = replica';
    delete from public.comisiones_devengadas where contrato_raiz_id = v_raiz and nivel = 'manager';
    update public.contratos set precio_total = 46000 where id = v_cc85;
    execute 'set local session_replication_role = origin';
    perform public.comisiones_reconciliar(v_raiz, false, '{"prueba": "W"}'::jsonb);
    select 't1=' || max(d.importe) filter (where t.orden = 1) || ' t2=' || max(d.importe) filter (where t.orden = 2)
           || ' base=' || max(d.disparado_por_snapshot->>'base_valor') filter (where t.orden = 2)
           || ' total=' || max(d.disparado_por_snapshot->>'precio_total') filter (where t.orden = 2)
           || ' t1_recalculado=' || (max(d.disparado_por_snapshot->>'recalculado_en') filter (where t.orden = 1) is not null)
      into v_t
      from public.comisiones_devengadas d join public.condicion_tramos t on t.id = d.tramo_id
     where d.contrato_raiz_id = v_raiz and d.nivel = 'closer';
    raise exception 'R:%', v_t;
  exception when others then
    r := r || 'W reconciliar escribe=' || sqlerrm
         || case when sqlerrm = 'R:t1=1475.00 t2=2250.00 base=90000 total=149000 t1_recalculado=false' then ' ok; ' else ' FALLO; ' end;
  end;

  -- 8 · raíz carta de reserva de noviembre → la carta no suma: sin tramo de parcela; la obra firmada sí paga su tramo
  begin
    execute 'set local session_replication_role = replica';
    update public.contratos set tipo = 'carta_reserva' where id = v_raiz;
    update public.contratos set precio_total = 36000 where id = v_cc85;
    execute 'set local session_replication_role = origin';
    perform public.comisiones_evaluar_contrato(v_raiz);
    select (select b.suelo_firmado || '/' || b.obra_firmada from public._comisiones_bases_firmadas(v_raiz) b) || ' devengos '
           || coalesce(string_agg(d.nivel || ':' || t.orden || ':' || d.importe, ',' order by d.nivel, t.orden), '-') into v_t
      from public.comisiones_devengadas d join public.condicion_tramos t on t.id = d.tramo_id where d.contrato_raiz_id = v_raiz;
    raise exception 'R:%', v_t;
  exception when others then
    r := r || '8 raíz carta=' || sqlerrm || case when sqlerrm = 'R:0/80000 devengos manager:2:8000.00' then ' ok; ' else ' FALLO; ' end;
  end;

  -- 9 · cambio de precio de la obra: lo devengado de la parcela no se mueve; el de obra sí (diferencia o actualización)
  begin
    perform public.comisiones_evaluar_contrato(v_raiz);                          -- solo parcela (obra al 22,7 %)
    execute 'set local session_replication_role = replica';
    update public.contratos set precio_total = 50000 where id = v_cc85;
    execute 'set local session_replication_role = origin';
    select count(*) into v_n from public.comisiones_reconciliar(v_raiz, true, '{}'::jsonb);
    v_t := 'tras cambiar obra sin devengo de obra: filas=' || v_n;
    execute 'set local session_replication_role = replica';
    update public.contratos set precio_total = 36000 where id = v_cc85;
    execute 'set local session_replication_role = origin';
    perform public.comisiones_evaluar_contrato(v_raiz);                          -- obra al 25 % → 8.000
    execute 'set local session_replication_role = replica';
    update public.contratos set precio_total = 46000 where id = v_cc85;          -- obra 90.000
    execute 'set local session_replication_role = origin';
    select v_t || ' | con devengo de obra: ' || coalesce(string_agg(
             case when x.devengo_id in (select d.id from public.comisiones_devengadas d where d.tramo_id = t_man2) then 'obra' else 'OTRO' end
             || ' nuevo ' || x.nuevo, ','), '-')
      into v_t from public.comisiones_reconciliar(v_raiz, true, '{}'::jsonb) x;
    raise exception 'R:%', v_t;
  exception when others then
    r := r || '9 cambio de precio de obra=' || sqlerrm
         || case when sqlerrm = 'R:tras cambiar obra sin devengo de obra: filas=0 | con devengo de obra: obra nuevo 9000.00' then ' ok; ' else ' FALLO; ' end;
  end;

  -- 10 · PRUEBA ROJA: con todo cuadrado el reconciliador no saca nada (si usara el precio total sacaría dos filas);
  --      al alterar la condición (12 %) y la base del tramo de obra, TIENE que sacar diferencias
  begin
    execute 'set local session_replication_role = replica';
    update public.contratos set precio_total = 36000 where id = v_cc85;
    execute 'set local session_replication_role = origin';
    perform public.comisiones_evaluar_contrato(v_raiz);
    select count(*) into v_n from public.comisiones_reconciliar(v_raiz, true, '{}'::jsonb);
    v_t := 'cuadrado=' || v_n;
    execute 'set local session_replication_role = replica';
    update public.condiciones_comision set pct_comision = 12 where id = c_man;
    execute 'set local session_replication_role = origin';
    select v_t || ' | al 12%: ' || string_agg(x.nuevo::text, ',' order by x.nuevo) into v_t
      from public.comisiones_reconciliar(v_raiz, true, '{}'::jsonb) x;
    execute 'set local session_replication_role = replica';
    update public.condicion_tramos set base_calculo = 'precio_suelo_firmado' where id = t_man2;
    execute 'set local session_replication_role = origin';
    select v_t || ' | obra sobre parcela: ' || string_agg(x.nuevo::text, ',' order by x.nuevo) into v_t
      from public.comisiones_reconciliar(v_raiz, true, '{}'::jsonb) x;
    raise exception 'R:%', v_t;
  exception when others then
    r := r || '10 prueba roja=' || sqlerrm
         || case when sqlerrm = 'R:cuadrado=0 | al 12%: 7080.00,9600.00 | obra sobre parcela: 7080.00,7080.00' then ' ok; ' else ' FALLO; ' end;
  end;

  -- F8b · (revisión 13-oct, hallazgo 4) manager con 1 tramo y closer con 2, MISMA base (precio_total) → la plantilla
  --       del SM se aplica (25 %) en los dos tramos del closer. Con la comparación tramo a tramo («1:x» ≠ «1:x,2:x») el
  --       closer perdía la plantilla en silencio: salía '-'.
  begin
    execute 'set local session_replication_role = replica';
    update public.contrato_closer set closer_email = 'santidavidse@gmail.com' where contrato_id = v_raiz;
    update public.contratos set precio_total = 36000 where id = v_cc85;
    update public.condiciones_comision set base_calculo = 'precio_total' where id in (c_man, c_clo);
    update public.condicion_tramos set base_calculo = null where condicion_id in (c_man, c_clo);
    delete from public.condicion_tramos where id = t_man2;
    execute 'set local session_replication_role = origin';
    perform public.comisiones_evaluar_contrato(v_raiz);
    select (select count(*) from public.condicion_tramos where condicion_id = c_man) || '/'
           || (select count(*) from public.condicion_tramos where condicion_id = c_clo) || ' '
           || coalesce(string_agg(d.nivel || ':' || t.orden || ':' || coalesce(d.disparado_por_snapshot->>'plantilla_pct', '-'), ','
                                  order by t.orden), '-') into v_t
      from public.comisiones_devengadas d join public.condicion_tramos t on t.id = d.tramo_id
     where d.contrato_raiz_id = v_raiz and d.nivel = 'closer';
    raise exception 'R:%', v_t;
  exception when others then
    r := r || 'F8b manager 1 tramo / closer 2, misma base=' || sqlerrm
         || case when sqlerrm = 'R:1/2 closer:1:25.00,closer:2:25.00' then ' ok; ' else ' FALLO; ' end;
  end;

  -- R7 · (revisión 13-oct, hallazgo 7) comisiones_reparto_datos recorta en el SERVIDOR las 7 cifras nuevas del snapshot a
  --      quien no ve la operación completa: el closer (santidavidse, agente) ve sus 2 devengos sin ninguna; el super
  --      admin los ve con ellas. El motor corre con los usuarios desactivados (montaje: sin solicitud, sin serie) y
  --      DESPUÉS se reactivan solo esos dos; el equipo deja ver la comisión a sus closers (closers_ven_comision).
  begin
    execute 'set local session_replication_role = replica';
    update public.contrato_closer set closer_email = 'santidavidse@gmail.com' where contrato_id = v_raiz;
    update public.contratos set precio_total = 36000 where id = v_cc85;
    execute 'set local session_replication_role = origin';
    perform public.comisiones_evaluar_contrato(v_raiz);
    execute 'set local session_replication_role = replica';
    update public.usuarios set activo = true where lower(email) in ('santidavidse@gmail.com', lower(v_adm.email));
    update public.equipos_venta set closers_ven_comision = true where id = v_gus;
    execute 'set local session_replication_role = origin';
    select u.user_id, u.email into v_sm from public.usuarios u where lower(u.email) = 'santidavidse@gmail.com';
    perform set_config('request.jwt.claims', json_build_object('sub', v_sm.user_id, 'email', v_sm.email, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select 'closer n=' || count(*) || ' con_cifras=' || count(*) filter (where (e->'disparado_por_snapshot') ?| array['precio_suelo_firmado',
             'precio_obra_firmada', 'cobrado_suelo_firmado', 'cobrado_obra_firmada', 'cobrado_directo_suelo', 'cobrado_directo_obra', 'cobrado_cartas'])
      into v_t from jsonb_array_elements(public.comisiones_reparto_datos()->'devengadas') e where e->>'contrato_raiz_id' = v_raiz::text;
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.email, 'role', 'authenticated')::text, true);
    select v_t || ' | admin n=' || count(*) || ' con_cifras=' || count(*) filter (where (e->'disparado_por_snapshot') ?& array['precio_suelo_firmado',
             'precio_obra_firmada', 'cobrado_suelo_firmado', 'cobrado_obra_firmada', 'cobrado_directo_suelo', 'cobrado_directo_obra', 'cobrado_cartas'])
      into v_t from jsonb_array_elements(public.comisiones_reparto_datos()->'devengadas') e where e->>'contrato_raiz_id' = v_raiz::text;
    raise exception 'R:%', v_t;
  exception when others then
    r := r || 'R7 snapshot recortado en servidor=' || sqlerrm
         || case when sqlerrm = 'R:closer n=2 con_cifras=0 | admin n=2 con_cifras=2' then ' ok; ' else ' FALLO; ' end;
  end;

  -- AD · (consulta de Administración, 13-oct) una ADENDA con precio cuenta en la base de OBRA aunque su tipo diga
  --      es_obra = false: CC00084 pasa a tipo 'adenda' → mismas bases que B (con la clasificación por es_obra saldría
  --      103000/44000: la adenda en la parcela).
  begin
    execute 'set local session_replication_role = replica';
    update public.contratos set tipo = 'adenda' where id = v_cc84;
    execute 'set local session_replication_role = origin';
    select b.suelo_firmado || '/' || b.obra_firmada || ' cob ' || b.cobrado_suelo_firmado || '/' || b.cobrado_obra_firmada
      into v_t from public._comisiones_bases_firmadas(v_raiz) b;
    raise exception 'R:%', v_t;
  exception when others then
    r := r || 'AD adenda en obra=' || sqlerrm || case when sqlerrm = 'R:59000/88000 cob 29500/20000' then ' ok; ' else ' FALLO; ' end;
  end;

  -- M · (consulta de Administración, 13-oct) MONEDA. M1: los recibís (y facturas) de la RP en IDR (la venta es EUR) no suman →
  --     parcela cobrada 0 y sin devengo. M2: CC00084 firmada en IDR → no suma en la base de obra, la familia queda
  --     multimoneda y el motor no devenga ningún tramo «firmado» aunque la parcela esté al 50 % (sin la guarda saldría
  --     manager:1:5900.00). El `raise warning` con la raíz no se puede capturar aquí: se comprueba la bandera.
  begin
    execute 'set local session_replication_role = replica';
    update public.facturas set moneda = 'IDR' where contrato_id = v_raiz;   -- sus recibís y las facturas a las que se aplican
    execute 'set local session_replication_role = origin';
    select b.cobrado_directo_suelo || '/' || b.cobrado_suelo_firmado || ' multi=' || b.multimoneda into v_t
      from public._comisiones_bases_firmadas(v_raiz) b;
    perform public.comisiones_evaluar_contrato(v_raiz);
    raise exception 'R:%|%', v_t, (select count(*) from public.comisiones_devengadas where contrato_raiz_id = v_raiz);
  exception when others then
    r := r || 'M1 recibí en otra moneda=' || sqlerrm || case when sqlerrm = 'R:0/0 multi=false|0' then ' ok; ' else ' FALLO; ' end;
  end;
  begin
    execute 'set local session_replication_role = replica';
    update public.contratos set moneda = 'IDR' where id = v_cc84;
    execute 'set local session_replication_role = origin';
    select b.suelo_firmado || '/' || b.obra_firmada || ' cob ' || b.cobrado_suelo_firmado || '/' || b.cobrado_obra_firmada
           || ' multi=' || b.multimoneda into v_t
      from public._comisiones_bases_firmadas(v_raiz) b;
    perform public.comisiones_evaluar_contrato(v_raiz);
    raise exception 'R:%|%|aviso=%', v_t, (select count(*) from public.comisiones_devengadas where contrato_raiz_id = v_raiz),
      (select coalesce(ultimo_error like 'venta en mas de una moneda%' || v_raiz || ')', false) from public.comisiones_interruptor);
  exception when others then
    r := r || 'M2 contrato firmado en otra moneda=' || sqlerrm
         || case when sqlerrm = 'R:59000/44000 cob 29500/0 multi=true|0|aviso=true' then ' ok; ' else ' FALLO; ' end;
  end;

  -- C · «PRIMERO PARCELA, LUEGO OBRA» (owner, 13-oct-2026). Cada caso compara las 7 cifras de _comisiones_bases_firmadas
  --     (suelo, obra, cobrado suelo, cobrado obra | bruto: directo suelo, directo obra, cartas) y el devengo. Con la
  --     fórmula anterior (solo lo cobrado en la base) fallan C1 (no devengaba), C2 y C3 (sin tramo de obra) y C4/C4b
  --     (cifras distintas). C1b es la frontera del 50 % y C5 prueba que NO hay desborde sin parcela firmada: los dos
  --     daban lo mismo con la fórmula anterior; son rojos frente a una imputación mal hecha, no frente a la vieja.
  -- C1 · todo el cobro en la carta hija (se le pasan las facturas de la RP: 29.500 + 5.000 = 34.500) y parcela 69.000
  --      → 50 % justo → 10 % de la parcela; el snapshot guarda lo cobrado en cartas
  begin
    execute 'set local session_replication_role = replica';
    update public.contratos set bloqueado = true where id = v_cr51;
    update public.facturas set contrato_id = v_cr51 where contrato_id = v_raiz and tipo <> 'proforma';
    update public.contratos set precio_total = 69000 where id = v_raiz;
    execute 'set local session_replication_role = origin';
    select (b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada,
            b.cobrado_directo_suelo, b.cobrado_directo_obra, b.cobrado_cartas) = (69000, 88000, 34500, 20000, 0, 20000, 34500),
           concat_ws('/', b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada,
                     b.cobrado_directo_suelo, b.cobrado_directo_obra, b.cobrado_cartas)
      into v_ok, v_b from public._comisiones_bases_firmadas(v_raiz) b;
    perform public.comisiones_evaluar_contrato(v_raiz);
    select coalesce(string_agg(d.nivel || ':' || t.orden || ':' || d.importe || ':' || (d.disparado_por_snapshot->>'base_calculo')
                               || ':cartas=' || ((d.disparado_por_snapshot->>'cobrado_cartas')::numeric = 34500), ','
                               order by d.nivel, t.orden), '-') into v_t
      from public.comisiones_devengadas d join public.condicion_tramos t on t.id = d.tramo_id where d.contrato_raiz_id = v_raiz;
    raise exception 'R:%|%', case when v_ok then 'bases ok' else 'bases ' || v_b end, v_t;
  exception when others then
    r := r || 'C1 cobro solo en la carta al 50%=' || sqlerrm
         || case when sqlerrm = 'R:bases ok|manager:1:6900.00:precio_suelo_firmado:cartas=true' then ' ok; ' else ' FALLO; ' end;
  end;

  -- C1b · lo mismo con la parcela a 69.000,02 (un céntimo por debajo del 50 %) → nada
  begin
    execute 'set local session_replication_role = replica';
    update public.contratos set bloqueado = true where id = v_cr51;
    update public.facturas set contrato_id = v_cr51 where contrato_id = v_raiz and tipo <> 'proforma';
    update public.contratos set precio_total = 69000.02 where id = v_raiz;
    execute 'set local session_replication_role = origin';
    perform public.comisiones_evaluar_contrato(v_raiz);
    raise exception 'R:%', (select count(*) from public.comisiones_devengadas where contrato_raiz_id = v_raiz);
  exception when others then
    r := r || 'C1b carta al 49,99%=' || sqlerrm || case when sqlerrm = 'R:0' then ' ok; ' else ' FALLO; ' end;
  end;

  -- C2 · carta firmada (5.000) y parcela 30.000: la RP sola (29.500) no la completa; carta + RP = 34.500 → parcela al
  --      100 % y el sobrante (4.500) va a obra: 24.500 / 88.000 = 27,8 % → dispara también el 25 % de obra
  --      (con la fórmula anterior la obra se quedaba en el 22,7 %)
  begin
    execute 'set local session_replication_role = replica';
    update public.contratos set bloqueado = true where id = v_cr51;
    update public.contratos set precio_total = 30000 where id = v_raiz;
    execute 'set local session_replication_role = origin';
    select (b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada,
            b.cobrado_directo_suelo, b.cobrado_directo_obra, b.cobrado_cartas) = (30000, 88000, 30000, 24500, 29500, 20000, 5000),
           concat_ws('/', b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada,
                     b.cobrado_directo_suelo, b.cobrado_directo_obra, b.cobrado_cartas)
      into v_ok, v_b from public._comisiones_bases_firmadas(v_raiz) b;
    perform public.comisiones_evaluar_contrato(v_raiz);
    select coalesce(string_agg(d.nivel || ':' || t.orden || ':' || d.importe || ':' || (d.disparado_por_snapshot->>'base_calculo'), ','
                               order by d.nivel, t.orden), '-') into v_t
      from public.comisiones_devengadas d join public.condicion_tramos t on t.id = d.tramo_id where d.contrato_raiz_id = v_raiz;
    raise exception 'R:%|%', case when v_ok then 'bases ok' else 'bases ' || v_b end, v_t;
  exception when others then
    r := r || 'C2 sobrante de la carta a obra=' || sqlerrm
         || case when sqlerrm = 'R:bases ok|manager:1:3000.00:precio_suelo_firmado,manager:2:8800.00:precio_obra_firmada'
                 then ' ok; ' else ' FALLO; ' end;
  end;

  -- C3 · desborde de la RP (caso RP00047), carta sin firmar: parcela 15.000 con 29.500 cobrados en la RP → parcela
  --      al 100 % y 14.500 a obra: 34.500 / 88.000 = 39,2 % → dispara la obra
  begin
    execute 'set local session_replication_role = replica';
    update public.contratos set precio_total = 15000 where id = v_raiz;
    execute 'set local session_replication_role = origin';
    select (b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada,
            b.cobrado_directo_suelo, b.cobrado_directo_obra, b.cobrado_cartas) = (15000, 88000, 15000, 34500, 29500, 20000, 0),
           concat_ws('/', b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada,
                     b.cobrado_directo_suelo, b.cobrado_directo_obra, b.cobrado_cartas)
      into v_ok, v_b from public._comisiones_bases_firmadas(v_raiz) b;
    perform public.comisiones_evaluar_contrato(v_raiz);
    select coalesce(string_agg(d.nivel || ':' || t.orden || ':' || d.importe, ',' order by d.nivel, t.orden), '-') into v_t
      from public.comisiones_devengadas d join public.condicion_tramos t on t.id = d.tramo_id where d.contrato_raiz_id = v_raiz;
    raise exception 'R:%|%', case when v_ok then 'bases ok' else 'bases ' || v_b end, v_t;
  exception when others then
    r := r || 'C3 desborde de la RP a obra=' || sqlerrm
         || case when sqlerrm = 'R:bases ok|manager:1:1500.00,manager:2:8800.00' then ' ok; ' else ' FALLO; ' end;
  end;

  -- C4 · nada pasa del 100 %: carta firmada, parcela 10.000 y obra 5.000 + 5.000 con 29.500 + 5.000 + 20.000 cobrados
  --      → 10.000 / 10.000 en las dos partes (bruto intacto)
  begin
    execute 'set local session_replication_role = replica';
    update public.contratos set bloqueado = true where id = v_cr51;
    update public.contratos set precio_total = 10000 where id = v_raiz;
    update public.contratos set precio_total = 5000 where id in (v_cc84, v_cc85);
    execute 'set local session_replication_role = origin';
    select (b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada,
            b.cobrado_directo_suelo, b.cobrado_directo_obra, b.cobrado_cartas) = (10000, 10000, 10000, 10000, 29500, 20000, 5000),
           concat_ws('/', b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada,
                     b.cobrado_directo_suelo, b.cobrado_directo_obra, b.cobrado_cartas)
      into v_ok, v_b from public._comisiones_bases_firmadas(v_raiz) b;
    perform public.comisiones_evaluar_contrato(v_raiz);
    select coalesce(string_agg(d.nivel || ':' || t.orden || ':' || d.importe, ',' order by d.nivel, t.orden), '-') into v_t
      from public.comisiones_devengadas d join public.condicion_tramos t on t.id = d.tramo_id where d.contrato_raiz_id = v_raiz;
    raise exception 'R:%|%', case when v_ok then 'bases ok' else 'bases ' || v_b end, v_t;
  exception when others then
    r := r || 'C4 tope 100%=' || sqlerrm
         || case when sqlerrm = 'R:bases ok|manager:1:1000.00,manager:2:1000.00' then ' ok; ' else ' FALLO; ' end;
  end;

  -- C4b · el exceso cobrado en OBRA no sube a la parcela: CC00085 sin firmar, CC00084 a 10.000 con 20.000 cobrados
  --       → obra 10.000 / 10.000 y la parcela sigue en 29.500 (no 39.500)
  begin
    execute 'set local session_replication_role = replica';
    update public.contratos set bloqueado = false where id = v_cc85;
    update public.contratos set precio_total = 10000 where id = v_cc84;
    execute 'set local session_replication_role = origin';
    select (b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada,
            b.cobrado_directo_suelo, b.cobrado_directo_obra, b.cobrado_cartas) = (59000, 10000, 29500, 10000, 29500, 20000, 0),
           concat_ws('/', b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada,
                     b.cobrado_directo_suelo, b.cobrado_directo_obra, b.cobrado_cartas)
      into v_ok, v_b from public._comisiones_bases_firmadas(v_raiz) b;
    raise exception 'R:%', case when v_ok then 'bases ok' else 'bases ' || v_b end;
  exception when others then
    r := r || 'C4b obra no sube a parcela=' || sqlerrm || case when sqlerrm = 'R:bases ok' then ' ok; ' else ' FALLO; ' end;
  end;

  -- C5 · sin parcela firmada no hay desborde: raíz convertida en carta (29.500) + CR00051 firmada (5.000) → la obra
  --      se queda en 20.000 / 88.000 (22,7 %) y no devenga (con desborde serían 54.500, 61,9 %)
  begin
    execute 'set local session_replication_role = replica';
    update public.contratos set bloqueado = true where id = v_cr51;
    update public.contratos set tipo = 'carta_reserva' where id = v_raiz;
    execute 'set local session_replication_role = origin';
    select (b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada,
            b.cobrado_directo_suelo, b.cobrado_directo_obra, b.cobrado_cartas) = (0, 88000, 0, 20000, 0, 20000, 34500),
           concat_ws('/', b.suelo_firmado, b.obra_firmada, b.cobrado_suelo_firmado, b.cobrado_obra_firmada,
                     b.cobrado_directo_suelo, b.cobrado_directo_obra, b.cobrado_cartas)
      into v_ok, v_b from public._comisiones_bases_firmadas(v_raiz) b;
    perform public.comisiones_evaluar_contrato(v_raiz);
    select coalesce(string_agg(d.nivel || ':' || t.orden || ':' || d.importe, ',' order by d.nivel, t.orden), '-') into v_t
      from public.comisiones_devengadas d join public.condicion_tramos t on t.id = d.tramo_id where d.contrato_raiz_id = v_raiz;
    raise exception 'R:%|%', case when v_ok then 'bases ok' else 'bases ' || v_b end, v_t;
  exception when others then
    r := r || 'C5 sin parcela no desborda=' || sqlerrm || case when sqlerrm = 'R:bases ok|-' then ' ok; ' else ' FALLO; ' end;
  end;

  -- V · validación de tramos: 100 por base efectiva; 'por_tramo' exige base en cada tramo
  begin
    begin
      perform public._condicion_tramos_pone(c_clo, '[{"disparador_tipo": "pct_cobrado_suelo_firmado", "umbral": 50, "pct_tramo": 100, "base_calculo": "precio_suelo_firmado"},
                                                     {"disparador_tipo": "pct_cobrado_obra_firmada", "umbral": 25, "pct_tramo": 100, "base_calculo": "precio_suelo_firmado"}]'::jsonb);
      set constraints all immediate;
      v_t := 'dos bases iguales: pasó';
    exception when others then v_t := 'dos bases iguales: rechazada';
    end;
    begin
      perform public._condicion_tramos_pone(c_clo, '[{"disparador_tipo": "pct_cobrado_suelo_firmado", "umbral": 50, "pct_tramo": 100, "base_calculo": "precio_suelo_firmado"},
                                                     {"disparador_tipo": "pct_cobrado_obra_firmada", "umbral": 25, "pct_tramo": 100, "base_calculo": null}]'::jsonb);
      set constraints all immediate;
      v_t := v_t || ', por_tramo sin base: pasó';
    exception when others then v_t := v_t || ', por_tramo sin base: rechazada';
    end;
    raise exception 'R:%', v_t;
  exception when others then
    r := r || 'V validación=' || sqlerrm
         || case when sqlerrm = 'R:dos bases iguales: rechazada, por_tramo sin base: rechazada' then ' ok; ' else ' FALLO; ' end;
  end;

  -- S · ninguna serie se ha movido
  v_t := format('SP %s/%s DIF %s/%s REC %s/%s PRO %s/%s INV %s/%s',
                v_sp0, (select last_value from public.solicitudes_pago_numero_seq),
                v_dif0, (select last_value from public.comisiones_diferencias_seq),
                v_rec0, (select last_value from public.facturas_recibi_seq),
                v_pro0, (select last_value from public.facturas_proforma_seq),
                v_inv0, (select last_value from public.facturas_seq));
  r := r || 'S series=' || v_t
       || case when v_sp0 = (select last_value from public.solicitudes_pago_numero_seq)
                and v_dif0 = (select last_value from public.comisiones_diferencias_seq)
                and v_rec0 = (select last_value from public.facturas_recibi_seq)
                and v_pro0 = (select last_value from public.facturas_proforma_seq)
                and v_inv0 = (select last_value from public.facturas_seq) then ' ok; ' else ' FALLO; ' end;

  raise exception 'RES: %', r;
end $$;
