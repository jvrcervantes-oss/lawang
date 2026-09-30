-- PRUEBA LAW-476 «la condición queda fijada al primer devengo» (30-sep-2026) — migración
-- supabase/migrations/20260930115040_law476_condicion_fija.sql.
-- Decisión del owner (30-sep, literal): «Se queda con la primera». La condición con la que una venta devengó su primer
-- tramo en un nivel (y para ese perceptor) paga TODOS los tramos siguientes de ese nivel, aunque luego se cierre, se
-- desactive o la sustituya otra por fecha. Antes el motor volvía a elegir por fecha y, si salía otra, saltaba la venta.
--
-- Se ejecuta ENTERA en una llamada con execute_sql (MCP) o psql como postgres. NO ESCRIBE NADA: cada caso va en un
-- sub-bloque que acaba en excepción y el bloque entero termina en `raise exception 'RES: …'`. Cada caso debe decir «ok».
-- SIN SECUENCIAS DE NEGOCIO: no da de alta contratos, no crea solicitudes de pago ni diferencias (se prueba en el nivel
-- `closer`, que paga el Sales Manager y no genera solicitud; las condiciones de manager del equipo se apagan dentro de
-- la prueba para que el motor no devengue nada de Lawang). Se puede pasar cuantas veces haga falta.
-- Base: RP00141 (firmada, cobrada en parte, closer T = dortegag en el equipo de S = gusabellan, 0 devengos hoy).
do $$
declare
  r text := ''; v_t text;
  v_rp uuid := (select c.id from public.contratos c where c.numero = 'RP00141' and c.contrato_padre_id is null);
  k public.contrato_closer; v_f date; v_proy uuid; v_pt numeric;
  v_c1 uuid; v_c2 uuid; v_t1 uuid; v_t2 uuid; v_n1 int; v_n2 int; v_a1 int; v_a2 int;
begin
  select * into k from public.contrato_closer where contrato_id = v_rp;
  if v_rp is null or lower(k.closer_email) <> 'dortegag@gmail.com' or k.equipo_id is null or k.modo is not null
     or exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id = v_rp) then
    raise exception 'RES: RP00141 ya no sirve de base (closer %, equipo %, modo %)', k.closer_email, k.equipo_id, k.modo;
  end if;
  select coalesce(k.fecha_venta, (c.created_at at time zone 'Asia/Makassar')::date), c.proyecto_id
    into v_f, v_proy from public.contratos c where c.id = v_rp;
  v_pt := public._comisiones_precio_total(v_rp);

  -- 1 · FIJADA: tramo 1 con C1; C1 se cierra y entra C2 por fecha → el tramo 2 lo paga C1 (con sus cifras), nada de C2
  begin
    update public.condiciones_comision set activo = false, vigente_hasta = null
     where equipo_id = k.equipo_id and nivel in ('manager', 'closer', 'setter', 'team_lead');
    insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo, activo, vigente_desde)
    values (k.equipo_id, v_proy, 'closer', 'dortegag@gmail.com', 5, 'precio_total', true, v_f - 30) returning id into v_c1;
    insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo)
    values (v_c1, 1, 'pct_cobrado_total', 0, 50) returning id into v_t1;
    insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo)
    values (v_c1, 2, 'pct_cobrado_total', 100, 50) returning id into v_t2;
    v_a1 := public._condicion_ventas_afectadas(k.equipo_id, v_proy, 'closer', 'dortegag@gmail.com', v_f - 1, v_f);
    v_n1 := public.comisiones_evaluar_contrato(v_rp);                       -- tramo 1 con C1
    v_a2 := public._condicion_ventas_afectadas(k.equipo_id, v_proy, 'closer', 'dortegag@gmail.com', v_f - 1, v_f);
    -- C1 se cierra el día antes de la venta y C2 (8 %, un tramo) vale desde el día de la venta
    update public.condiciones_comision set vigente_hasta = v_f - 1 where id = v_c1;
    insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo, activo, vigente_desde, sustituye_a)
    values (k.equipo_id, v_proy, 'closer', 'dortegag@gmail.com', 8, 'precio_total', true, v_f, v_c1) returning id into v_c2;
    insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo) values (v_c2, 1, 'pct_cobrado_total', 0, 100);
    update public.condicion_tramos set umbral = 0 where id = v_t2;          -- el tramo 2 ya se cumple
    v_n2 := public.comisiones_evaluar_contrato(v_rp);
    raise exception '%', format('%s/%s/%s/%s/%s', v_n1, v_n2,
      (select count(*) from public.comisiones_devengadas d where d.contrato_raiz_id = v_rp and d.condicion_id = v_c1 and d.nivel = 'closer'
          and d.importe = round(0.05 * v_pt * 0.5, 2)),
      (select count(*) from public.comisiones_devengadas d where d.contrato_raiz_id = v_rp and d.condicion_id = v_c2),
      v_a1 - v_a2);
  exception when others then r := r || '1 fijada tras cierre y sustituta=' || sqlerrm || case when sqlerrm = '1/1/2/0/1' then ' ok; ' else ' FALLO; ' end; end;

  -- 2 · FIJADA aunque C1 se DESACTIVE (activo=false, sin fecha de cierre: el filtro de fechas ya no la vería)
  begin
    update public.condiciones_comision set activo = false, vigente_hasta = null
     where equipo_id = k.equipo_id and nivel in ('manager', 'closer', 'setter', 'team_lead');
    insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo, activo, vigente_desde)
    values (k.equipo_id, v_proy, 'closer', 'dortegag@gmail.com', 5, 'precio_total', true, v_f - 30) returning id into v_c1;
    insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo)
    values (v_c1, 1, 'pct_cobrado_total', 0, 50) returning id into v_t1;
    insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo)
    values (v_c1, 2, 'pct_cobrado_total', 100, 50) returning id into v_t2;
    v_n1 := public.comisiones_evaluar_contrato(v_rp);
    update public.condiciones_comision set activo = false where id = v_c1;
    update public.condicion_tramos set umbral = 0 where id = v_t2;
    v_n2 := public.comisiones_evaluar_contrato(v_rp);
    raise exception '%', format('%s/%s/%s', v_n1, v_n2,
      (select count(*) from public.comisiones_devengadas d where d.contrato_raiz_id = v_rp and d.condicion_id = v_c1));
  exception when others then r := r || '2 fijada aunque desactivada=' || sqlerrm || case when sqlerrm = '1/1/2' then ' ok; ' else ' FALLO; ' end; end;

  -- 3 · SIN DEVENGOS: como hoy, manda la condición vigente por fecha (C1 cerrada antes de la venta → C2)
  begin
    update public.condiciones_comision set activo = false, vigente_hasta = null
     where equipo_id = k.equipo_id and nivel in ('manager', 'closer', 'setter', 'team_lead');
    insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo, activo, vigente_desde, vigente_hasta)
    values (k.equipo_id, v_proy, 'closer', 'dortegag@gmail.com', 5, 'precio_total', true, v_f - 30, v_f - 1) returning id into v_c1;
    insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo) values (v_c1, 1, 'pct_cobrado_total', 0, 100);
    insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo, activo, vigente_desde)
    values (k.equipo_id, v_proy, 'closer', 'dortegag@gmail.com', 8, 'precio_total', true, v_f) returning id into v_c2;
    insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo) values (v_c2, 1, 'pct_cobrado_total', 0, 100);
    v_n1 := public.comisiones_evaluar_contrato(v_rp);
    raise exception '%', format('%s/%s/%s', v_n1,
      (select count(*) from public.comisiones_devengadas d where d.contrato_raiz_id = v_rp and d.condicion_id = v_c2 and d.importe = round(0.08 * v_pt, 2)),
      (select count(*) from public.comisiones_devengadas d where d.contrato_raiz_id = v_rp and d.condicion_id = v_c1));
  exception when others then r := r || '3 sin devengos por fecha=' || sqlerrm || case when sqlerrm = '1/1/0' then ' ok; ' else ' FALLO; ' end; end;

  -- 4 · PARIDAD en producción: el motor no crea nada en ninguna raíz con devengos (todas sus condiciones ya pagaron todos
  --     sus tramos). Solo se pasa si la consulta de candidatos (abajo) da 0: si no, crearía solicitudes reales.
  begin
    select coalesce(sum(public.comisiones_evaluar_contrato(x.contrato_raiz_id)), 0) into v_n1
      from (select distinct contrato_raiz_id from public.comisiones_devengadas) x;
    raise exception '%', v_n1;
  exception when others then r := r || '4 paridad raices con devengos=' || sqlerrm || case when sqlerrm = '0' then ' ok; ' else ' FALLO; ' end; end;

  raise exception 'RES: %', r;
end $$;

-- CANDIDATOS (pasar ANTES del caso 4 y antes de aplicar): tramos de la condición fijada de cada (venta, nivel, perceptor)
-- que aún no tienen devengo. 0 = ninguna venta real pasa a cobrar tramos que antes se saltaban.
-- with trip as (select distinct on (d.contrato_raiz_id, d.nivel, d.beneficiario_email) d.contrato_raiz_id, d.nivel, d.beneficiario_email, d.condicion_id
--                 from comisiones_devengadas d order by d.contrato_raiz_id, d.nivel, d.beneficiario_email, d.created_at, d.id)
-- select count(*) from trip t join condicion_tramos tr on tr.condicion_id = t.condicion_id
--  where not exists (select 1 from comisiones_devengadas d2 where d2.contrato_raiz_id = t.contrato_raiz_id and d2.tramo_id = tr.id
--                      and d2.beneficiario_email = t.beneficiario_email);
-- 30-sep 11:44 UTC: 10 ternas, 0 tramos fijados sin devengo, 0 ternas con dos condiciones.
--
-- ANTES de aplicar (30-sep, reproduce el fallo): «1 …=1/0/1/0/0 FALLO; 2 …=1/0/1 FALLO; 3 …=1/1/0 ok; 4 …=0 ok».
-- DESPUÉS (20260930115040): «1 …=1/1/2/0/1 ok; 2 …=1/1/2 ok; 3 …=1/1/0 ok; 4 …=0 ok». Secuencias SP 83, DIF 110 y RP 253
-- iguales antes y después; huellas de devengos (10:873cb219…) y solicitudes (9:e7a01534…) sin cambios.
-- La migración de LAW-474 (…_law474_restos_f5.sql) vuelve a sustituir el motor; esta prueba se repite tras ella.
