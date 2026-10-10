-- LAW-478 (10-oct-2026, cierre del encargo de equipos de venta): los dos restos técnicos de F6 («Mi equipo») que quedaban.
--
-- (1) _equipo_miembro_mueve contaba también los contratos HIJOS (adendas, contratos colgados de una venta) en su lista de
--     «ventas que se mueven». Una venta es la raíz: los hijos leen equipo y modo de su raíz. Contarlos hinchaba el número
--     que admin tiene que confirmar, el aviso y equipos_log.ventas_movidas. No movía dinero. Arreglo: la lista y su
--     recuento solo cuentan raíces (contrato_padre_id is null), como ya hace _condicion_ventas_afectadas.
--     La vista previa (equipo_miembro_vista_previa) y el guardado (_equipo_miembro_guarda_con) llaman a esta MISMA
--     función, así que el número que enseña la vista previa y el que exige el guardado siguen siendo el mismo.
--     Parche por `replace` sobre la versión VIVA (no se copia su cuerpo, que la reescribió el reparto en dos empresas
--     20261008400400): ancla única comprobada; si no aparece exactamente una vez, aborta. Idempotente (marca LAW-478-raices).
--
-- (2) _trg_contrato_closer_fecha_venta comparaba `created_at >= '2026-09-24'`: ese literal se lee en la zona de la sesión
--     (UTC), así que el corte era las 08:00 de Bali. El resto del ancla usa el día de Bali. Arreglo: corte a las 00:00 de
--     Bali (+08). Medido el 10-oct: 0 contratos creados entre las 00:00 y las 08:00 de Bali del 24-sep, así que no cambia
--     ninguna fecha de venta ya guardada (y el trigger nunca reescribe una: en UPDATE conserva la vieja).
--
-- Quién manda sobre el dato: contrato_closer.fecha_venta la pone SOLO este trigger, una vez, al nacer la fila (copia
-- congelada del día de la venta); contrato_closer.equipo_id/manager_email los congela _equipo_congela_ventas.
-- ROLLBACK: (1) create or replace con el cuerpo vivo previo (pg_get_functiondef guardado en el informe del cierre; el cambio
-- es solo añadir `c.contrato_padre_id is null and (` … `)` al where de la lista); (2) volver al literal '2026-09-24'.
-- destructivo-ok: no toca filas; el «UPDATE» que ve no_destruir es el literal tg_op = 'UPDATE' del cuerpo del trigger.

do $law478$
declare
  v_def   text := pg_get_functiondef('public._equipo_miembro_mueve(uuid,uuid,text,date,date,boolean,integer,boolean,boolean)'::regprocedure);
  v_marca constant text := 'LAW-478-raices';
  v_ancla constant text := '     where (v_antes -> k.contrato_id::text) is null';
  v_fin   constant text := '        or (v_antes -> k.contrato_id::text ->> 1) is distinct from k.manager_email;';
  v_n     int;
begin
  if position(v_marca in v_def) > 0 then
    raise notice 'LAW-478 (1) ya aplicado';
  else
    v_n := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
    if v_n <> 1 or (length(v_def) - length(replace(v_def, v_fin, ''))) / length(v_fin) <> 1 then
      raise exception 'LAW-478: no encuentro exactamente una vez el where de la lista en _equipo_miembro_mueve; revisar la version viva' using errcode = '55000';
    end if;
    v_def := replace(v_def, v_ancla,
               '     where c.contrato_padre_id is null   -- ' || v_marca || ': una venta es la raiz; los hijos no se cuentan' || chr(10)
            || '       and ((v_antes -> k.contrato_id::text) is null');
    v_def := replace(v_def, v_fin,
               '        or (v_antes -> k.contrato_id::text ->> 1) is distinct from k.manager_email);');
    execute v_def;
  end if;
  if position(v_marca in pg_get_functiondef('public._equipo_miembro_mueve(uuid,uuid,text,date,date,boolean,integer,boolean,boolean)'::regprocedure)) = 0 then
    raise exception 'LAW-478: el parche (1) no quedo aplicado' using errcode = '55000';
  end if;
end $law478$;

create or replace function public._trg_contrato_closer_fecha_venta()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if tg_op = 'UPDATE' then
    new.fecha_venta := old.fecha_venta;
    return new;
  end if;
  -- día de Bali, el mismo que usan el motor y las guardas; el corte del 24-sep también es a las 00:00 de Bali (LAW-478)
  select case when c.created_at >= timestamptz '2026-09-24 00:00:00+08' then (c.created_at at time zone 'Asia/Makassar')::date end
    into new.fecha_venta
    from public.contratos c where c.id = new.contrato_id;
  return new;
end $function$;

-- los permisos no cambian con create or replace, pero se comprueba: ninguna de las dos es llamable desde fuera
do $post$
begin
  if has_function_privilege('authenticated', 'public._equipo_miembro_mueve(uuid,uuid,text,date,date,boolean,integer,boolean,boolean)', 'execute')
     or has_function_privilege('anon', 'public._equipo_miembro_mueve(uuid,uuid,text,date,date,boolean,integer,boolean,boolean)', 'execute')
     or has_function_privilege('authenticated', 'public._trg_contrato_closer_fecha_venta()', 'execute')
     or has_function_privilege('anon', 'public._trg_contrato_closer_fecha_venta()', 'execute') then
    raise exception 'LAW-478: una funcion interna quedo llamable desde fuera' using errcode = '55000';
  end if;
end $post$;
