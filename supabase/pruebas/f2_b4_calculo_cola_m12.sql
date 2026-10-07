-- COLA de la prueba de equivalencia del calculo, tras las migraciones 1-2 del bloque 4 (ver f2_b4_calculo_cabeza.sql).
-- Compara antes/despues (cada linea debe ser OK) y revisa que las copias de sandal_woods son exactas y que los candados nuevos responden. Termina en raise.
-- destructivo-ok: ensayo en transaccion que termina en raise (rollback); sin drop
select pg_temp.medir('despues');
do $c$
declare r record; out text := ''; fallos int := 0; n int; x bigint; ok boolean; h1 text; h2 text; v_eq uuid; v_lw uuid; v_sw uuid;
begin
  for r in select a.k, a.v av, d.v dv from _b4_ref a join _b4_ref d on d.k = a.k and d.tag = 'despues' where a.tag = 'antes' order by a.k loop
    out := out || case when r.av = r.dv then 'OK      ' else 'DIFIERE ' end || r.k || E'\n';
    if r.av <> r.dv then fallos := fallos + 1; end if;
  end loop;

  -- 1. equipos: 3 gemelos activos con los mismos datos
  select count(*) into n from public.equipos_venta a join public.equipos_venta b
    on b.empresa = 'sandal_woods' and b.nombre = a.nombre and lower(b.manager_email) = lower(a.manager_email) and b.closers_ven_comision = a.closers_ven_comision and b.activo = a.activo
   where a.empresa = 'lawang' and a.activo;
  out := out || case when n = 3 then 'OK      ' else 'FALLO   ' end || format('3 equipos gemelos (%s)', n) || E'\n'; if n <> 3 then fallos := fallos + 1; end if;
  select count(*) into n from public.equipos_venta where empresa = 'sandal_woods';
  out := out || case when n = 3 then 'OK      ' else 'FALLO   ' end || format('solo 3 equipos en sandal_woods (%s)', n) || E'\n'; if n <> 3 then fallos := fallos + 1; end if;
  select count(*) into n from public.equipos_venta where empresa = 'lawang';
  out := out || case when n = 5 then 'OK      ' else 'FALLO   ' end || format('los 5 equipos de siempre siguen en lawang (%s)', n) || E'\n'; if n <> 5 then fallos := fallos + 1; end if;

  -- 2. por cada pareja: miembros, plantilla, condiciones y tramos identicos en valores
  for r in select a.id a_id, b.id b_id, a.nombre from public.equipos_venta a join public.equipos_venta b on b.empresa = 'sandal_woods' and b.nombre = a.nombre where a.empresa = 'lawang' and a.activo loop
    select md5(coalesce(string_agg(concat_ws('|', closer_email, desde, hasta, rol, rol_nombre, created_at), ',' order by closer_email, desde, created_at), '')) into h1 from public.equipo_miembros where equipo_id = r.a_id;
    select md5(coalesce(string_agg(concat_ws('|', closer_email, desde, hasta, rol, rol_nombre, created_at), ',' order by closer_email, desde, created_at), '')) into h2 from public.equipo_miembros where equipo_id = r.b_id;
    out := out || case when h1 = h2 then 'OK      ' else 'FALLO   ' end || format('miembros de %s iguales', r.nombre) || E'\n'; if h1 <> h2 then fallos := fallos + 1; end if;
    select md5(coalesce(string_agg(concat_ws('|', rol_tipo, rol_nombre, pct), ',' order by rol_tipo, rol_nombre), '')) into h1 from public.plantilla_reparto where equipo_id = r.a_id;
    select md5(coalesce(string_agg(concat_ws('|', rol_tipo, rol_nombre, pct), ',' order by rol_tipo, rol_nombre), '')) into h2 from public.plantilla_reparto where equipo_id = r.b_id;
    out := out || case when h1 = h2 then 'OK      ' else 'FALLO   ' end || format('plantilla de %s igual', r.nombre) || E'\n'; if h1 <> h2 then fallos := fallos + 1; end if;
    select md5(coalesce(string_agg(concat_ws('|', c.nivel, c.proyecto_id, c.closer_email, c.pct_comision, c.base_calculo, c.importe_fijo, c.activo, c.vigente_desde, c.vigente_hasta,
             (select string_agg(concat_ws('/', t.orden, t.disparador_tipo, t.umbral, t.pct_tramo), ';' order by t.orden) from public.condicion_tramos t where t.condicion_id = c.id)),
             ',' order by c.nivel, c.proyecto_id, c.closer_email, c.vigente_desde), '')) into h1
      from public.condiciones_comision c where c.equipo_id = r.a_id and (c.proyecto_id is null or exists (select 1 from public.proyectos pr where pr.id = c.proyecto_id and pr.empresa = 'sandal_woods'));
    select md5(coalesce(string_agg(concat_ws('|', c.nivel, c.proyecto_id, c.closer_email, c.pct_comision, c.base_calculo, c.importe_fijo, c.activo, c.vigente_desde, c.vigente_hasta,
             (select string_agg(concat_ws('/', t.orden, t.disparador_tipo, t.umbral, t.pct_tramo), ';' order by t.orden) from public.condicion_tramos t where t.condicion_id = c.id)),
             ',' order by c.nivel, c.proyecto_id, c.closer_email, c.vigente_desde), '')) into h2
      from public.condiciones_comision c where c.equipo_id = r.b_id;
    out := out || case when h1 = h2 then 'OK      ' else 'FALLO   ' end || format('condiciones y tramos de %s iguales', r.nombre) || E'\n'; if h1 <> h2 then fallos := fallos + 1; end if;
  end loop;

  -- 3. condiciones estandar y tarifa
  select md5(coalesce(string_agg(concat_ws('|', c.nivel, c.proyecto_id, c.closer_email, c.pct_comision, c.base_calculo, c.importe_fijo, c.activo, c.vigente_desde, c.vigente_hasta,
           (select string_agg(concat_ws('/', t.orden, t.disparador_tipo, t.umbral, t.pct_tramo), ';' order by t.orden) from public.condicion_tramos t where t.condicion_id = c.id)),
           ',' order by c.nivel, c.closer_email, c.vigente_desde), '')) into h1 from public.condiciones_comision c where c.equipo_id is null and c.empresa = 'lawang' and c.proyecto_id is null;
  select md5(coalesce(string_agg(concat_ws('|', c.nivel, c.proyecto_id, c.closer_email, c.pct_comision, c.base_calculo, c.importe_fijo, c.activo, c.vigente_desde, c.vigente_hasta,
           (select string_agg(concat_ws('/', t.orden, t.disparador_tipo, t.umbral, t.pct_tramo), ';' order by t.orden) from public.condicion_tramos t where t.condicion_id = c.id)),
           ',' order by c.nivel, c.closer_email, c.vigente_desde), '')) into h2 from public.condiciones_comision c where c.equipo_id is null and c.empresa = 'sandal_woods';
  out := out || case when h1 = h2 then 'OK      ' else 'FALLO   ' end || 'condiciones estandar de sandal_woods = las de lawang' || E'\n'; if h1 <> h2 then fallos := fallos + 1; end if;
  select count(*) into n from public.condiciones_comision where equipo_id is null and empresa = 'sandal_woods' and sustituye_a is not null
     and sustituye_a in (select id from public.condiciones_comision where empresa = 'sandal_woods');
  out := out || case when n = 1 then 'OK      ' else 'FALLO   ' end || format('la sustitucion estandar apunta a su copia (%s)', n) || E'\n'; if n <> 1 then fallos := fallos + 1; end if;
  select count(*) into n from public.comision_admin_tarifas t join public.comision_admin_tarifas u on u.empresa = 'sandal_woods' and u.pct = t.pct and u.efectivo_desde = t.efectivo_desde where t.empresa = 'lawang';
  out := out || case when n = 1 then 'OK      ' else 'FALLO   ' end || format('tarifa de sandal_woods = la de lawang (%s)', n) || E'\n'; if n <> 1 then fallos := fallos + 1; end if;

  -- 4. candados nuevos
  select id into v_lw from public.equipos_venta where empresa = 'lawang' and activo order by nombre limit 1;
  ok := false; begin update public.equipos_venta set empresa = 'sandal_woods' where id = v_lw; exception when sqlstate '22023' then ok := true; end;
  out := out || case when ok then 'OK      ' else 'FALLO   ' end || 'la empresa de un equipo no se cambia' || E'\n'; if not ok then fallos := fallos + 1; end if;
  ok := false;
  begin
    insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, pct_comision, base_calculo, vigente_desde, empresa, created_by)
    values (null, (select id from public.proyectos where empresa = 'lawang' limit 1), 'closer', 1, 'precio_total', current_date + 400, 'sandal_woods', 'prueba');
  exception when sqlstate '22023' then ok := true; end;
  out := out || case when ok then 'OK      ' else 'FALLO   ' end || 'una condicion no puede ser de un proyecto de la otra empresa' || E'\n'; if not ok then fallos := fallos + 1; end if;
  ok := false;
  begin
    insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, pct_comision, base_calculo, vigente_desde, empresa, created_by)
    values (null, null, 'closer', 1, 'precio_total', current_date + 401, null, 'prueba');
  exception when sqlstate '23502' or sqlstate '22023' then ok := true; end;
  out := out || case when ok then 'OK      ' else 'FALLO   ' end || 'una condicion sin empresa se rechaza' || E'\n'; if not ok then fallos := fallos + 1; end if;
  -- un miembro abierto repetido en la MISMA empresa choca; en la otra no
  select m.closer_email, m.equipo_id into r from public.equipo_miembros m where m.hasta is null and m.empresa = 'lawang' limit 1;
  ok := false;
  begin
    alter table public.equipo_miembros disable trigger trg_equipo_miembros_congela;
    alter table public.equipo_miembros disable trigger trg_equipo_miembros_recongela;
    insert into public.equipo_miembros (equipo_id, closer_email, desde) values (r.equipo_id, r.closer_email, current_date + 500);
  exception when sqlstate '23505' then ok := true; end;
  out := out || case when ok then 'OK      ' else 'FALLO   ' end || 'un miembro no puede estar dos veces abierto en la misma empresa' || E'\n'; if not ok then fallos := fallos + 1; end if;
  alter table public.equipo_miembros enable trigger trg_equipo_miembros_congela;
  alter table public.equipo_miembros enable trigger trg_equipo_miembros_recongela;
  select count(*) into n from pg_trigger t where t.tgrelid = 'public.equipo_miembros'::regclass and t.tgname in ('trg_equipo_miembros_congela','trg_equipo_miembros_recongela') and t.tgenabled = 'O';
  out := out || case when n = 2 then 'OK      ' else 'FALLO   ' end || 'los triggers de congelado estan activos' || E'\n'; if n <> 2 then fallos := fallos + 1; end if;
  select count(*) into n from pg_trigger t where t.tgrelid = 'public.equipos_venta'::regclass and t.tgname = 'trg_equipos_venta_plantilla_defecto' and t.tgenabled = 'O';
  out := out || case when n = 1 then 'OK      ' else 'FALLO   ' end || 'el trigger de plantilla por defecto esta activo' || E'\n'; if n <> 1 then fallos := fallos + 1; end if;

  -- 5. permisos de las funciones nuevas
  ok := has_function_privilege('authenticated', 'public.empresa_de_sociedad(text)', 'execute') and has_function_privilege('lw_lector', 'public.empresa_de_sociedad(text)', 'execute');
  out := out || case when ok then 'OK      ' else 'FALLO   ' end || 'empresa_de_sociedad ejecutable por authenticated y lw_lector' || E'\n'; if not ok then fallos := fallos + 1; end if;
  ok := not has_function_privilege('anon', 'public.empresa_de_sociedad(text)', 'execute');
  out := out || case when ok then 'OK      ' else 'FALLO   ' end || 'empresa_de_sociedad cerrada a anon' || E'\n'; if not ok then fallos := fallos + 1; end if;
  ok := not has_function_privilege('authenticated', 'public._empresa_de_contrato_int(uuid)', 'execute') and not has_function_privilege('authenticated', 'public.puede_reparto_de(text)', 'execute')
        and not has_function_privilege('authenticated', 'public._condicion_ventas_afectadas(uuid,uuid,text,text,date,date,text)', 'execute') and not has_function_privilege('anon', 'public.empresa_de_equipo(uuid)', 'execute');
  out := out || case when ok then 'OK      ' else 'FALLO   ' end || 'las funciones internas no son ejecutables desde fuera' || E'\n'; if not ok then fallos := fallos + 1; end if;

  raise exception E'\n%FALLOS=%', out, fallos;
end $c$;
