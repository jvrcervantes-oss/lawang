-- LAW-447 (30-sep-2026) · primera pieza de F2 del encargo 20260930_lawang_equipos_venta_asistente.
-- Dar de alta un miembro en un equipo re-atribuia ventas viejas: `_venta_congela_equipo` y `_equipo_recongela_sin_equipo`
-- buscaban el equipo a `coalesce(fecha_venta, current_date)` y solo 13 de 188 ventas tienen fecha_venta, asi que TODA venta
-- sin devengo del closer caia en el equipo nuevo (medido: 47 ventas de un solo closer con un alta de ayer).
-- Ahora se ancla en `coalesce(fecha_venta, <contrato raiz>.created_at::date)`, la misma fecha con la que el motor
-- (`comisiones_evaluar_contrato`) ya elegia la condicion. Raiz = coalesce(contrato_padre_id, id), igual que el motor.
-- Construido sobre el cuerpo VIVO (supabase/vivo/20260930/, md5 comprobado antes de aplicar); SECURITY DEFINER y
-- search_path '' se conservan. Nada mas cambia. Prueba: contracts/sql/prueba_f2_equipos.sql (casos a y h).
-- Inversa: re-aplicar los dos volcados de supabase/vivo/20260930/.

do $g$
begin
  if md5(replace(pg_get_functiondef('public._venta_congela_equipo(uuid)'::regprocedure), E'\r', '')) <> '9a64e4e0df5d037ccf447e5776cc7a02'
     or md5(replace(pg_get_functiondef('public._equipo_recongela_sin_equipo(text,date,date)'::regprocedure), E'\r', '')) <> 'bbf1b2ac64cc0c3d688bd61cad90f21d' then
    raise exception 'LAW-447: la funcion viva ya no es la del volcado del 30-sep: rehacer sobre la nueva';
  end if;
end $g$;

CREATE OR REPLACE FUNCTION public._venta_congela_equipo(p_raiz uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eq uuid; v_man text;
begin
  if not exists (select 1 from public.contrato_closer k where k.contrato_id = p_raiz and k.equipo_congelado_en is null) then
    return;
  end if;
  select em.equipo_id, ev.manager_email into v_eq, v_man
    from public.contrato_closer k
    join public.contratos c on c.id = k.contrato_id
    join public.contratos rz on rz.id = coalesce(c.contrato_padre_id, c.id)
    join public.equipo_miembros em on lower(em.closer_email) = lower(k.closer_email)
    join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo
   where k.contrato_id = p_raiz
     and em.desde <= coalesce(k.fecha_venta, rz.created_at::date)
     and (em.hasta is null or em.hasta >= coalesce(k.fecha_venta, rz.created_at::date))
   order by em.created_at desc
   limit 1;
  update public.contrato_closer k
     set equipo_id = v_eq, manager_email = v_man, equipo_congelado_en = now()
   where k.contrato_id = p_raiz and k.equipo_congelado_en is null;
end $function$;

CREATE OR REPLACE FUNCTION public._equipo_recongela_sin_equipo(p_email text, p_desde date, p_hasta date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; n int := 0;
begin
  for r in
    select k.contrato_id from public.contrato_closer k
      join public.contratos c on c.id = k.contrato_id
      join public.contratos rz on rz.id = coalesce(c.contrato_padre_id, c.id)
     where lower(k.closer_email) = lower(p_email)
       and k.equipo_congelado_en is not null and k.equipo_id is null
       and coalesce(k.fecha_venta, rz.created_at::date) >= p_desde
       and (p_hasta is null or coalesce(k.fecha_venta, rz.created_at::date) <= p_hasta)
       and not exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id = k.contrato_id)
  loop
    update public.contrato_closer k set equipo_id = null, manager_email = null, equipo_congelado_en = null
     where k.contrato_id = r.contrato_id;
    n := n + 1;
  end loop;
  return n;
end $function$;
