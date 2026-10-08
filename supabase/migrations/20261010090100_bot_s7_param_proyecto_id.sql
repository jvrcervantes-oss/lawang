-- destructivo-ok: drop de dos funciones nuevas (S7, sin llamadores en produccion todavia) solo para recrearlas con el parametro renombrado p_proyecto -> p_proyecto_id (el gate de lecturas por nombre lee «p_proyecto» como busqueda por nombre; es un id). Mismo cuerpo, mismos grants. Sin datos que perder.
drop function if exists public.proyecto_bot_publico_poner(uuid, boolean);
drop function if exists public.proyecto_bot_publico_lee(uuid);

create function public.proyecto_bot_publico_poner(p_proyecto_id uuid, p_valor boolean)
returns jsonb language plpgsql security definer set search_path = '' as $f$
begin
  if p_proyecto_id is null or p_valor is null then
    raise exception 'Faltan datos' using errcode = 'PT400';
  end if;
  if not public.es_admin_de(public.empresa_de_proyecto(p_proyecto_id)) then
    raise exception 'Solo un administrador puede abrir o cerrar un proyecto al bot' using errcode = '42501';
  end if;
  perform 1 from public.proyectos p where p.id = p_proyecto_id for update;
  if not found then
    raise exception 'Ese proyecto no existe' using errcode = 'PT404';
  end if;
  update public.proyectos p set bot_publico = p_valor where p.id = p_proyecto_id and p.bot_publico is distinct from p_valor;
  return public._bot_proyecto_estado(p_proyecto_id);
end $f$;

create function public.proyecto_bot_publico_lee(p_proyecto_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v jsonb;
begin
  if p_proyecto_id is null or not public.es_admin_de(public.empresa_de_proyecto(p_proyecto_id)) then
    raise exception 'Solo un administrador puede ver esto' using errcode = '42501';
  end if;
  v := public._bot_proyecto_estado(p_proyecto_id);
  if v is null then raise exception 'Ese proyecto no existe' using errcode = 'PT404'; end if;
  return v;
end $f$;

revoke all on function public.proyecto_bot_publico_poner(uuid, boolean) from public, anon, service_role;
revoke all on function public.proyecto_bot_publico_lee(uuid)            from public, anon, service_role;
grant execute on function public.proyecto_bot_publico_poner(uuid, boolean) to authenticated;
grant execute on function public.proyecto_bot_publico_lee(uuid)            to authenticated;
