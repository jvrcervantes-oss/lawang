CREATE OR REPLACE FUNCTION public.mi_condicion_comision()
 RETURNS TABLE(ambito text, equipo_nombre text, oculta boolean, proyecto_id uuid, nivel text, pct_comision numeric, base_calculo text, importe_fijo numeric, personal boolean, vigente_desde date, empresa text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_yo text := lower(coalesce(auth.email(), ''));
  v_hoy date := current_date;
  v_eq record;
  v_nivel text;
  v_p uuid;
  v_emp text;
  v_c public.condiciones_comision;
  v_vistas uuid[] := '{}';
  v_claves text[] := '{}';
  v_k text;
  v_hay boolean := false;
begin
  if auth.uid() is null or v_yo = '' then
    raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501';
  end if;
  for v_eq in
    select em.equipo_id, em.rol, ev.nombre, ev.closers_ven_comision, ev.empresa
      from public.equipo_miembros em
      join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo
     where lower(em.closer_email) = v_yo and em.desde <= v_hoy and (em.hasta is null or em.hasta >= v_hoy)
     order by em.created_at desc
  loop
    v_hay := true;
    if not coalesce(v_eq.closers_ven_comision, true) then
      v_k := md5(concat_ws('|', 'equipo', v_eq.nombre, 'oculta'));
      if not (v_k = any (v_claves)) then
        v_claves := v_claves || v_k;
        return query select 'equipo'::text, v_eq.nombre::text, true, null::uuid, null::text, null::numeric, null::text,
                            null::numeric, null::boolean, null::date, v_eq.empresa::text;
      end if;
      continue;
    end if;
    v_nivel := case when v_eq.rol in ('closer', 'setter', 'team_lead') then v_eq.rol else 'closer' end;
    for v_p in
      select null::uuid
      union
      select distinct c.proyecto_id from public.condiciones_comision c
       where c.equipo_id = v_eq.equipo_id and c.nivel = v_nivel and c.proyecto_id is not null
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and (c.closer_email is null or lower(c.closer_email) = v_yo)
    loop
      select * into v_c from public.condiciones_comision c
       where c.equipo_id = v_eq.equipo_id
         and (c.proyecto_id = v_p or c.proyecto_id is null)
         and c.nivel = v_nivel
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and lower(c.closer_email) = v_yo
       order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;
      if not found then
        select * into v_c from public.condiciones_comision c
         where c.equipo_id = v_eq.equipo_id
           and (c.proyecto_id = v_p or c.proyecto_id is null)
           and c.nivel = v_nivel
           and (c.activo or c.vigente_hasta is not null)
           and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
           and c.closer_email is null
         order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
         limit 1;
      end if;
      if found and not (v_c.id = any (v_vistas)) then
        v_vistas := v_vistas || v_c.id;
        v_k := md5(concat_ws('|', 'equipo', v_eq.nombre, v_c.proyecto_id, v_c.nivel, v_c.pct_comision, v_c.base_calculo, v_c.importe_fijo,
                             v_c.closer_email is not null, v_c.vigente_desde));
        if not (v_k = any (v_claves)) then
          v_claves := v_claves || v_k;
          return query select 'equipo'::text, v_eq.nombre::text, false, v_c.proyecto_id, v_c.nivel, v_c.pct_comision,
                              v_c.base_calculo, v_c.importe_fijo, v_c.closer_email is not null, v_c.vigente_desde, v_eq.empresa::text;
        end if;
      end if;
    end loop;
  end loop;
  if v_hay then return; end if;

  for v_emp in select e.clave from public.empresas e where e.activa and (not public.alcance_restringido() or public.puede_empresa(e.clave)) order by e.orden loop
    for v_p in
      select null::uuid
      union
      select distinct c.proyecto_id from public.condiciones_comision c
       where c.empresa = v_emp and c.equipo_id is null and c.nivel = 'closer' and c.proyecto_id is not null
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and (c.closer_email is null or lower(c.closer_email) = v_yo)
    loop
      select * into v_c from public.condiciones_comision c
       where c.empresa = v_emp
         and c.equipo_id is null
         and c.nivel = 'closer'
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and (c.proyecto_id = v_p or c.proyecto_id is null)
         and (c.closer_email is null or lower(c.closer_email) = v_yo)
       order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;
      if found and not (v_c.id = any (v_vistas)) then
        v_vistas := v_vistas || v_c.id;
        v_k := md5(concat_ws('|', 'estandar', v_c.proyecto_id, v_c.pct_comision, v_c.base_calculo, v_c.importe_fijo,
                             v_c.closer_email is not null, v_c.vigente_desde));
        if not (v_k = any (v_claves)) then
          v_claves := v_claves || v_k;
          return query select 'estandar'::text, null::text, false, v_c.proyecto_id, 'estandar'::text, v_c.pct_comision,
                              v_c.base_calculo, v_c.importe_fijo, v_c.closer_email is not null, v_c.vigente_desde, v_emp::text;
        end if;
      end if;
    end loop;
  end loop;
end $function$
