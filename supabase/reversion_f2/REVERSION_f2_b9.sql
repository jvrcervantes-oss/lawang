-- Reversion del BLOQUE 9 (equipo_venta_guarda con p_empresa), migracion 20261008700000 (7-oct-2026).
-- Devuelve la firma de 3 argumentos con el cuerpo del bloque 4. Revertir tambien el front (editores.js) o el selector manda p_empresa a una funcion que ya no lo admite.
-- destructivo-ok: retira la firma de 4 argumentos; no toca datos
begin;
drop function if exists public.equipo_venta_guarda(uuid, text, text, text);
create or replace function public.equipo_venta_guarda(p_id uuid, p_nombre text, p_manager_email text)
 returns uuid language plpgsql security definer set search_path to ''
as $function$
declare v_old public.equipos_venta%rowtype; v_id uuid; v_n int := 0;
  v_man text := nullif(lower(btrim(coalesce(p_manager_email, ''))), '');
  v_nom text := nullif(btrim(coalesce(p_nombre, '')), '');
  v_emp text;
begin
  v_emp := coalesce(public.empresa_de_equipo(p_id),
                    (select u.empresas[1] from public.usuarios u where u.user_id = (select auth.uid()) and u.activo and cardinality(coalesce(u.empresas, '{}')) = 1),
                    'lawang');
  if not public.es_admin_de(v_emp) then raise exception 'Los equipos de venta los gestiona administración' using errcode = '42501'; end if;
  if v_man is not null and exists (select 1 from public.usuarios u where lower(u.email) = v_man and u.activo
                                    and cardinality(coalesce(u.empresas, '{}')) > 0 and not (v_emp = any (u.empresas))) then
    raise exception 'El manager no vende en la empresa de este equipo' using errcode = '22023';
  end if;
  if v_nom is null then raise exception 'Falta el nombre del equipo' using errcode = '22023'; end if;
  if v_man is null or not public._usuario_activo(v_man) then
    raise exception 'El manager tiene que ser un usuario activo de la intranet' using errcode = '22023';
  end if;
  if v_man = lower(coalesce((select auth.email()), '')) and not public.es_super_admin_de(v_emp) then
    raise exception 'Nadie se pone a sí mismo de manager de un equipo' using errcode = '42501';
  end if;
  if p_id is null then
    insert into public.equipos_venta (nombre, manager_email, empresa) values (v_nom, v_man, v_emp) returning id into v_id;
    insert into public.equipos_log (tabla, fila_id, antes, despues)
    select 'equipos_venta', v_id, null, to_jsonb(e) from public.equipos_venta e where e.id = v_id;
    return v_id;
  end if;
  select * into v_old from public.equipos_venta e where e.id = p_id for update;
  if not found then raise exception 'Ese equipo no existe' using errcode = 'P0002'; end if;
  if lower(v_old.manager_email) is distinct from v_man then
    v_n := public._equipo_congela_ventas(p_id, null);
  end if;
  update public.equipos_venta set nombre = v_nom, manager_email = v_man where id = p_id;
  insert into public.equipos_log (tabla, fila_id, antes, despues, ventas_congeladas)
  select 'equipos_venta', p_id, to_jsonb(v_old), to_jsonb(e), v_n from public.equipos_venta e where e.id = p_id;
  return p_id;
end $function$;
revoke all on function public.equipo_venta_guarda(uuid, text, text) from public, anon;
grant execute on function public.equipo_venta_guarda(uuid, text, text) to authenticated;
commit;
