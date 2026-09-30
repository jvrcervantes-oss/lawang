-- F4 · arreglo del revisor de código (30-sep-2026): mi_condicion_comision elige la pertenencia a equipo con el MISMO orden
-- que el motor (comisiones_evaluar_contrato: `order by em.created_at desc`), no por `desde desc, created_at desc`.
-- Porqué: con dos pertenencias vigentes a la vez, «Tu condición» podía enseñar la del equipo A mientras el motor le paga con
-- la del equipo B. Única diferencia con 20260930044643 (cuerpo leído del vivo el 30-sep): la línea del order by.
-- Llamador: intranet/v4/assets/datos.js («Mis comisiones» → «Tu condición»).
create or replace function public.mi_condicion_comision()
 returns table(ambito text, equipo_nombre text, oculta boolean, proyecto_id uuid, nivel text,
               pct_comision numeric, base_calculo text, importe_fijo numeric, personal boolean, vigente_desde date)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_yo text := lower(coalesce(auth.email(), ''));
  v_hoy date := current_date;
  v_eq record;
  v_nivel text;
  v_p uuid;
  v_c public.condiciones_comision;
  v_vistas uuid[] := '{}';
begin
  if auth.uid() is null or v_yo = '' then
    raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501';
  end if;

  -- su equipo HOY (el mismo criterio de membresía que la pantalla)
  select em.equipo_id, em.rol, ev.nombre, ev.closers_ven_comision into v_eq
    from public.equipo_miembros em
    join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo
   where lower(em.closer_email) = v_yo and em.desde <= v_hoy and (em.hasta is null or em.hasta >= v_hoy)
   order by em.created_at desc   -- mismo orden que comisiones_evaluar_contrato
   limit 1;

  if v_eq.equipo_id is not null then
    if not coalesce(v_eq.closers_ven_comision, true) then
      return query select 'equipo'::text, v_eq.nombre::text, true, null::uuid, null::text, null::numeric, null::text,
                          null::numeric, null::boolean, null::date;
      return;
    end if;
    v_nivel := case when v_eq.rol in ('closer', 'setter', 'team_lead') then v_eq.rol else 'closer' end;
    -- una fila por ámbito: todos los proyectos, y cada proyecto con condición propia
    for v_p in
      select null::uuid
      union
      select distinct c.proyecto_id from public.condiciones_comision c
       where c.equipo_id = v_eq.equipo_id and c.nivel = v_nivel and c.proyecto_id is not null
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and (c.closer_email is null or lower(c.closer_email) = v_yo)
    loop
      -- mismo filtro y orden que comisiones_evaluar_contrato: la personal manda; si no, la genérica del equipo
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
      if found and not (v_c.id = any(v_vistas)) then
        v_vistas := v_vistas || v_c.id;
        return query select 'equipo'::text, v_eq.nombre::text, false, v_c.proyecto_id, v_c.nivel, v_c.pct_comision,
                            v_c.base_calculo, v_c.importe_fijo, v_c.closer_email is not null, v_c.vigente_desde;
      end if;
    end loop;
    return;
  end if;

  -- sin equipo: la estándar vigente (mismo filtro y orden que el nivel 'estandar' del motor)
  for v_p in
    select null::uuid
    union
    select distinct c.proyecto_id from public.condiciones_comision c
     where c.equipo_id is null and c.nivel = 'closer' and c.proyecto_id is not null
       and (c.activo or c.vigente_hasta is not null)
       and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
       and (c.closer_email is null or lower(c.closer_email) = v_yo)
  loop
    select * into v_c from public.condiciones_comision c
     where c.equipo_id is null
       and c.nivel = 'closer'
       and (c.activo or c.vigente_hasta is not null)
       and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
       and (c.proyecto_id = v_p or c.proyecto_id is null)
       and (c.closer_email is null or lower(c.closer_email) = v_yo)
     order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
     limit 1;
    if found and not (v_c.id = any(v_vistas)) then
      v_vistas := v_vistas || v_c.id;
      return query select 'estandar'::text, null::text, false, v_c.proyecto_id, 'estandar'::text, v_c.pct_comision,
                          v_c.base_calculo, v_c.importe_fijo, v_c.closer_email is not null, v_c.vigente_desde;
    end if;
  end loop;
end $function$;

comment on function public.mi_condicion_comision() is
  'LAW-461 (30-sep-2026): la condicion de comision que el motor aplicaria hoy a quien consulta; sin cifras si su SM oculta la comision. Llamador: datos.js «Tu condicion».';
revoke all on function public.mi_condicion_comision() from public, anon;
grant execute on function public.mi_condicion_comision() to authenticated, service_role;
