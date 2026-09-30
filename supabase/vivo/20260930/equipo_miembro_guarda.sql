-- VOLCADO DE PRODUCCION (Supabase Lawang) del 2026-09-30: pg_get_functiondef(public.equipo_miembro_guarda).
-- NO es una migracion: no se aplica. Referencia para construir sobre el cuerpo VIVO (encargo 20260930_lawang_equipos_venta_asistente, F1).
-- ---- fin cabecera ----
CREATE OR REPLACE FUNCTION public.equipo_miembro_guarda(p_id uuid, p_equipo uuid, p_email text, p_desde date, p_hasta date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old public.equipo_miembros%rowtype; v_id uuid; v_n int := 0;
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
begin
  if not public.es_admin() then raise exception 'Los equipos de venta los gestiona administración' using errcode = '42501'; end if;
  if v_email is null or not public._usuario_activo(v_email) then
    raise exception 'El miembro tiene que ser un usuario activo de la intranet' using errcode = '22023';
  end if;
  if v_email = lower(coalesce((select auth.email()), '')) and not public.es_super_admin() then
    raise exception 'Nadie se añade a sí mismo a un equipo' using errcode = '42501';
  end if;
  if p_desde is null then raise exception 'Falta la fecha «Desde»' using errcode = '22023'; end if;
  if p_hasta is not null and p_hasta < p_desde then raise exception '«Hasta» no puede ser anterior a «Desde».' using errcode = '22023'; end if;
  if not exists (select 1 from public.equipos_venta e where e.id = p_equipo) then
    raise exception 'Ese equipo no existe' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.equipo_miembros em
              where lower(em.closer_email) = v_email and em.equipo_id <> p_equipo
                and (p_id is null or em.id <> p_id)
                and em.desde <= coalesce(p_hasta, 'infinity'::date)
                and p_desde <= coalesce(em.hasta, 'infinity'::date)) then
    raise exception 'Esa persona ya está en otro equipo en esas fechas: dale de baja allí primero' using errcode = '23P01';
  end if;
  if p_id is null then
    v_n := public._equipo_congela_ventas(p_equipo, v_email);
    insert into public.equipo_miembros (equipo_id, closer_email, desde, hasta, added_by)
    values (p_equipo, v_email, p_desde, p_hasta, (select auth.email())) returning id into v_id;
    insert into public.equipos_log (tabla, fila_id, antes, despues, ventas_congeladas)
    select 'equipo_miembros', v_id, null, to_jsonb(m), v_n from public.equipo_miembros m where m.id = v_id;
    return v_id;
  end if;
  select * into v_old from public.equipo_miembros m where m.id = p_id for update;
  if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;
  v_n := public._equipo_congela_ventas(v_old.equipo_id, v_old.closer_email)
       + public._equipo_congela_ventas(p_equipo, v_email);
  update public.equipo_miembros
     set equipo_id = p_equipo, closer_email = v_email, desde = p_desde, hasta = p_hasta
   where id = p_id;
  insert into public.equipos_log (tabla, fila_id, antes, despues, ventas_congeladas)
  select 'equipo_miembros', p_id, to_jsonb(v_old), to_jsonb(m), v_n from public.equipo_miembros m where m.id = p_id;
  return p_id;
end $function$
