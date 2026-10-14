CREATE OR REPLACE FUNCTION public.condicion_comision_guarda(p_id uuid, p_cond jsonb, p_tramos jsonb, p_motivo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_equipo uuid := nullif(p_cond->>'equipo_id', '')::uuid;
  v_proy   uuid := nullif(p_cond->>'proyecto_id', '')::uuid;
  v_pedida text := nullif(btrim(coalesce(p_cond->>'empresa', '')), '');
  v_id uuid; v_primero uuid; e record;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if p_id is not null then
    return public._condicion_comision_guarda_en(p_id, p_cond, p_tramos, p_motivo, null);
  end if;
  if v_equipo is not null or v_proy is not null or v_pedida is not null then
    return public._condicion_comision_guarda_en(null, p_cond, p_tramos, p_motivo, v_pedida);
  end if;
  for e in select em.clave from public.empresas em where em.activa order by em.orden loop
    if public.es_admin_de(e.clave) then
      v_id := public._condicion_comision_guarda_en(null, p_cond, p_tramos, p_motivo, e.clave);
      v_primero := coalesce(v_primero, v_id);
    end if;
  end loop;
  if v_primero is null then
    raise exception 'Solo puedes crear condiciones para los closers, setters o team leads de tu equipo' using errcode = '42501';
  end if;
  return v_primero;
end $function$
