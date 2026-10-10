-- destructivo-ok: reemplaza dos funciones de 010000 con un cambio quirúrgico (mismas firmas); no borra ni cambia ninguna fila al aplicarse.
-- Consulta de deploy de Administración (27-sep-2026, LAW-336 pieza 8):
-- · `unidades_importa` con `moneda: ""` dejaba la parcela SIN moneda (el `not in` con null no salta) — el mismo
--   fallo del 8-sep que dejó 45 parcelas sin moneda. Ahora la moneda vacía se rechaza.
-- · Precio de suelo, de construcción y superficie negativos se aceptaban (la tabla no tiene CHECK de signo):
--   un agente podía bajar el total de una parcela sin contrato. Ahora se rechazan en las dos funciones.
-- · Seguridad: una parcela SIN contrato pero en reservada/vendida/cobrada (hay 5) se trataba como libre: un
--   agente podía devolverla a disponible o cambiarle el precio. Ahora cuenta como comprometida — su estado se
--   conserva (lo cambia solo un admin) y su dinero, solo un admin con motivo, también por CSV.
do $$
declare d text; d0 text;
begin
  d := pg_get_functiondef('public.unidades_importa(jsonb)'::regprocedure); d0 := d;
  d := replace(d, $x$if f ? 'moneda' and v_mon not in ('EUR', 'USD', 'AUD', 'IDR') then$x$,
                  $x$if f ? 'moneda' and (v_mon is null or v_mon not in ('EUR', 'USD', 'AUD', 'IDR')) then$x$);
  if d = d0 then raise exception 'importa: no encuentro la comprobación de moneda'; end if;
  d0 := d;
  d := replace(d, $x$    select * into v_old from public.unidades u where u.proyecto = v_nproy and u.codigo = v_cod for update;$x$,
                  $x$    if coalesce(nullif(f->>'superficie_m2', '')::numeric, 0) < 0 or coalesce(nullif(f->>'precio_suelo', '')::numeric, 0) < 0
       or coalesce(nullif(f->>'precio_construccion', '')::numeric, 0) < 0 then
      raise exception 'Fila %: superficie y precios no pueden ser negativos', coalesce(f->>'fila', '?') using errcode = '22023';
    end if;
    select * into v_old from public.unidades u where u.proyecto = v_nproy and u.codigo = v_cod for update;$x$);
  if d = d0 then raise exception 'importa: no encuentro la búsqueda de la parcela'; end if;
  d0 := d;
  d := replace(d, $x$v_old.contrato_id is not null$x$, $x$(v_old.contrato_id is not null or v_old.estado in ('reservada', 'vendida', 'cobrada'))$x$);
  d := replace(d, $x$v_old.contrato_id is null$x$, $x$(v_old.contrato_id is null and v_old.estado not in ('reservada', 'vendida', 'cobrada'))$x$);
  if d = d0 then raise exception 'importa: no encuentro las reglas de parcela con contrato'; end if;
  execute d;

  d := pg_get_functiondef('public.unidad_guarda(uuid, jsonb, text)'::regprocedure); d0 := d;
  d := replace(d, $x$  v_proy := public._unidad_proyecto(v_nproy);$x$,
                  $x$  if coalesce(v_sup, 0) < 0 or coalesce(v_suelo, 0) < 0 or coalesce(v_obra, 0) < 0 then
    raise exception 'Superficie y precios no pueden ser negativos' using errcode = '22023';
  end if;
  if p_datos ? 'moneda' and v_mon is null then raise exception 'La moneda no puede quedar vacía' using errcode = '22023'; end if;
  v_proy := public._unidad_proyecto(v_nproy);$x$);
  if d = d0 then raise exception 'guarda: no encuentro la resolución del proyecto'; end if;
  d0 := d;
  d := replace(d, $x$if v_old.contrato_id is not null and v_dinero then$x$,
                  $x$if (v_old.contrato_id is not null or v_old.estado in ('reservada', 'vendida', 'cobrada')) and v_dinero then$x$);
  if d = d0 then raise exception 'guarda: no encuentro la regla del dinero'; end if;
  d0 := d;
  d := replace(d, $x$  if v_old.contrato_id is not null then
    v_est := v_old.estado;$x$,
                  $x$  if v_old.contrato_id is not null or (v_old.estado in ('reservada', 'vendida', 'cobrada') and not v_admin) then
    v_est := v_old.estado;$x$);
  if d = d0 then raise exception 'guarda: no encuentro la regla del estado'; end if;
  execute d;
end $$;
