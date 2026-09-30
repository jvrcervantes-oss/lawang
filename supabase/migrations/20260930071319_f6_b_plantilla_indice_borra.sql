-- F6 · segunda parte: las tres piezas que borran según reglas de negocio (no datos existentes).
-- destructivo-ok: owner 30-sep «Sí, las tres» — (1) plantilla del SM reemplazada entera, (2) índice rehecho, (3) borrar solo una condición futura sin devengos

-- (2) LAW-463 (1)
-- destructivo-ok: owner 30-sep «Sí, las tres» — se recrea un índice (no datos) con un predicado más estrecho
drop index if exists public.condiciones_comision_equipo_unica;
create unique index condiciones_comision_equipo_unica on public.condiciones_comision
  using btree (equipo_id, nivel, coalesce(proyecto_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(lower(closer_email), ''::text))
  where ((equipo_id is not null) and activo and (vigente_hasta is null));

-- (1) plantilla de reparto del SM: herramienta suya, NUNCA genera solicitudes de pago (D3).
-- destructivo-ok: owner 30-sep «Sí, las tres» — delete acotado a equipo_id = p_equipo + insert en la misma transacción; log en equipos_log
create or replace function public.plantilla_reparto_guarda(p_equipo uuid, p_filas jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_antes jsonb; v_f jsonb; v_suma numeric := 0; v_n int := 0; v_vistos text[] := '{}'; v_k text;
  v_tipo text; v_nom text; v_pct numeric;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if p_equipo is null or not (public.es_admin() or public.es_manager_de_equipo(p_equipo)) then
    raise exception 'La plantilla de reparto la guarda su sales manager o administración' using errcode = '42501';
  end if;
  if not exists (select 1 from public.equipos_venta e where e.id = p_equipo) then
    raise exception 'Ese equipo no existe' using errcode = 'P0002';
  end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then raise exception 'Formato de plantilla no válido' using errcode = '22023'; end if;
  if jsonb_array_length(p_filas) > 20 then raise exception 'Como mucho 20 roles en la plantilla' using errcode = '22023'; end if;
  for v_f in select * from jsonb_array_elements(p_filas) loop
    v_tipo := v_f->>'rol_tipo';
    v_nom := nullif(btrim(coalesce(v_f->>'rol_nombre', '')), '');
    begin
      v_pct := (v_f->>'pct')::numeric;
    exception when invalid_text_representation then
      raise exception 'Revisa los porcentajes: alguno no es un número' using errcode = '22023';
    end;
    if v_tipo is null or v_tipo not in ('closer', 'setter', 'otro') then raise exception 'El tipo de rol es Closer, Setter u Otro' using errcode = '22023'; end if;
    if v_nom is null or length(v_nom) > 60 then raise exception 'Cada rol necesita un nombre (hasta 60 letras)' using errcode = '22023'; end if;
    if v_pct is null or v_pct <= 0 or v_pct > 100 then raise exception 'Cada %% va entre 0 y 100' using errcode = '22023'; end if;
    v_k := v_tipo || '|' || lower(v_nom);
    if v_k = any(v_vistos) then raise exception 'El rol «%» está repetido', v_nom using errcode = '22023'; end if;
    v_vistos := v_vistos || v_k;
    v_suma := v_suma + v_pct; v_n := v_n + 1;
  end loop;
  if v_n > 0 and v_suma <> 100 then
    raise exception using errcode = '22023', message = 'La plantilla suma ' || v_suma || '% y tiene que sumar 100%';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('rol_tipo', p.rol_tipo, 'rol_nombre', p.rol_nombre, 'pct', p.pct)), '[]'::jsonb)
    into v_antes from public.plantilla_reparto p where p.equipo_id = p_equipo;
  delete from public.plantilla_reparto p where p.equipo_id = p_equipo;
  insert into public.plantilla_reparto (equipo_id, rol_tipo, rol_nombre, pct, creado_por)
  select p_equipo, f->>'rol_tipo', btrim(f->>'rol_nombre'), (f->>'pct')::numeric, (select auth.email())
    from jsonb_array_elements(p_filas) f;
  insert into public.equipos_log (tabla, fila_id, antes, despues)
  values ('plantilla_reparto', p_equipo, v_antes, p_filas);
end $function$;
revoke all on function public.plantilla_reparto_guarda(uuid, jsonb) from public, anon;
grant execute on function public.plantilla_reparto_guarda(uuid, jsonb) to authenticated;

-- (3) borrar una condición: SOLO la que aún no ha empezado y sin ningún devengo; cualquier otra se CIERRA.
-- destructivo-ok: owner 30-sep «Sí, las tres» — borra una sola condición futura sin devengos, con log.
create or replace function public.condicion_comision_borra(p_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_old public.condiciones_comision%rowtype; v_hoy date := (now() at time zone 'Asia/Makassar')::date;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  select * into v_old from public.condiciones_comision c where c.id = p_id for update;
  if not found or not public._condicion_es_mia(v_old.nivel, v_old.equipo_id) then
    raise exception 'No encuentro esa condición entre las tuyas' using errcode = '42501';
  end if;
  if exists (select 1 from public.comisiones_devengadas d where d.condicion_id = p_id) then
    raise exception 'Esta condición ya ha generado comisiones: ciérrala en vez de borrarla' using errcode = '22023';
  end if;
  if v_old.vigente_desde <= v_hoy then
    raise exception 'Solo se borra una condición que aún no ha empezado; esta vale desde el %: ciérrala en su lugar',
      to_char(v_old.vigente_desde, 'DD-MM-YYYY') using errcode = '22023';
  end if;
  insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
  values (p_id, to_jsonb(v_old), null, 'borrada');
  delete from public.condiciones_comision where id = p_id;
end $function$;
revoke all on function public.condicion_comision_borra(uuid) from public, anon;
grant execute on function public.condicion_comision_borra(uuid) to authenticated;

create or replace function public.condicion_comision_activa(p_id uuid, p_activo boolean)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_old public.condiciones_comision%rowtype; v_hoy date := (now() at time zone 'Asia/Makassar')::date;
  v_hasta date; v_ult date;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if p_activo is null then raise exception 'Falta el valor' using errcode = '22023'; end if;
  select * into v_old from public.condiciones_comision c where c.id = p_id for update;
  if not found or not public._condicion_es_mia(v_old.nivel, v_old.equipo_id) then
    raise exception 'No encuentro esa condición entre las tuyas' using errcode = '42501';
  end if;
  if not p_activo then
    if not v_old.activo then
      raise exception 'Esta condición ya está cerrada%', coalesce(' desde el ' || to_char(v_old.vigente_hasta, 'DD-MM-YYYY'), '') using errcode = '22023';
    end if;
    if v_old.vigente_desde > v_hoy then
      raise exception 'Esta condición empieza el %: todavía no se ha aplicado a ninguna venta. Bórrala en vez de cerrarla.',
        to_char(v_old.vigente_desde, 'DD-MM-YYYY') using errcode = '22023';
    end if;
    v_hasta := least(coalesce(v_old.vigente_hasta, v_hoy), v_hoy);
    v_ult := public._condicion_ultima_venta_devengada(p_id);
    if v_ult is not null and v_ult > v_hasta then
      raise exception 'Una venta del % ya ha cobrado comisión con esta condición: no se puede cerrar antes de esa fecha',
        to_char(v_ult, 'DD-MM-YYYY') using errcode = '22023';
    end if;
    update public.condiciones_comision set activo = false, vigente_hasta = v_hasta where id = p_id;
    insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
    values (p_id, jsonb_build_object('activo', v_old.activo, 'vigente_hasta', v_old.vigente_hasta),
            jsonb_build_object('activo', false, 'vigente_hasta', v_hasta), 'cerrada');
    return;
  end if;
  if v_old.activo then return; end if;
  if v_old.vigente_hasta is not null then
    raise exception 'Una condición cerrada no se reabre: crea una nueva desde hoy' using errcode = '22023';
  end if;
  if v_old.vigente_desde < v_hoy then
    raise exception 'Reactivarla la aplicaría a ventas pasadas: crea una nueva desde hoy' using errcode = '22023';
  end if;
  update public.condiciones_comision set activo = true where id = p_id;
  if public._condicion_solapa(p_id) is not null then
    raise exception 'Ya hay otra condición en vigor para ese mismo alcance en esas fechas' using errcode = '23P01';
  end if;
  insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
  values (p_id, jsonb_build_object('activo', false), jsonb_build_object('activo', true), null);
end $function$;
revoke all on function public.condicion_comision_activa(uuid, boolean) from public, anon;
grant execute on function public.condicion_comision_activa(uuid, boolean) to authenticated;